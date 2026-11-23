"""ONEMS Carrier Link v4 - simulated carrier. Python 3 stdlib only; run with `python -I`.

  python -I sim.py generate --seed S --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-16T03:00 [--network network.json]
                            [--out out/dataset]
        writes the carrier "database": out/dataset/scans.csv (one row per scan) + items.json (ground truth, tests only)
  python -I sim.py keygen --out out/carrier_key.txt
        creates a random connector key (local tests only) and prints "<sha256 hex> <first 12 chars>"
  python -I sim.py deliver --config config.json [--max N] [--format jsonl|csv] [--tamper] [--no-wait]
        reference connector, for every deliverable period in calendar order: GET /config -> build the file with ALL the
        complete shipments of next_period -> POST /deliveries -> PUT the file to the signed URL ->
        POST /deliveries/{id}/complete -> poll GET /deliveries/{id} until processed / rejected. Prints and saves every
        request and response under out_dir/<period_start>_<period_end>/.
        --tamper uploads a file that differs from the declared sha256 (same size): the delivery must end rejected.
  python -I sim.py build --config-json get-config.json --dataset out/dataset --from 2026-11-02 --to 2026-11-04
                         [--format jsonl|csv] [--seed S] --out DIR
        offline: the delivery file + manifest + POST /deliveries body for one period, from a saved GET /config answer
  python -I sim.py call --config config.json --method GET --path config [--body FILE] [--save FILE]
        one raw API call (negative tests, replays); the path may omit the leading "/"
  python -I sim.py status --config config.json --delivery ID [--wait]
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import secrets
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from carrier_sim import connector, dataset, transport  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FINAL = ("processed", "rejected")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, obj):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
        f.write("\n")


def load_config(path):
    cfg = load_json(path)
    base = os.path.dirname(os.path.abspath(path))
    for k in ("key_file", "dataset_dir", "out_dir"):
        if cfg.get(k):
            cfg[k] = os.path.normpath(os.path.join(base, cfg[k]))
    if cfg.get("mode") not in ("local", "dev"):
        raise SystemExit("config: mode must be 'local' or 'dev'")
    for k in ("key_file", "seed", "dataset_dir", "out_dir"):
        if cfg.get(k) in (None, ""):
            raise SystemExit("config: %s is required" % k)
    for f in cfg.get("formats") or ["jsonl"]:
        if f not in ("jsonl", "csv"):
            raise SystemExit("config: formats holds jsonl and/or csv only")
    local = cfg.get("local") or {}
    if local.get("process_cmd"):
        local["process_cmd"] = [os.path.normpath(os.path.join(base, x)) if x.startswith(".") else x
                                for x in local["process_cmd"]]
    return cfg


def make_transport(cfg):
    key = transport.read_key(cfg["key_file"])
    if cfg["mode"] == "dev":
        if not cfg.get("base_url"):
            raise SystemExit("config: base_url is required in dev mode")
        return transport.DevTransport(cfg["base_url"], key)
    os.makedirs(cfg["out_dir"], exist_ok=True)
    return transport.LocalTransport(cfg.get("local") or {}, key, cfg["out_dir"])


def show(label, status, body, limit=1500):
    print("%s -> HTTP %s %s" % (label, status, json.dumps(body, ensure_ascii=False)[:limit]))


def _sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def cmd_generate(a):
    network = load_json(a.network)
    as_of = dt.datetime.fromisoformat(a.as_of)
    scans, items = dataset.generate(network, a.seed, dt.date.fromisoformat(a.date_from),
                                    dt.date.fromisoformat(a.date_to), as_of)
    meta = {"seed": a.seed, "from": a.date_from, "to": a.date_to, "as_of": a.as_of, "carrier": network["carrier"],
            "network_sha256": _sha256_file(a.network)}
    dataset.write(a.out, scans, items, meta)
    kinds = {}
    for it in items:
        kinds[it["anomaly"] or "normal"] = kinds.get(it["anomaly"] or "normal", 0) + 1
    print("dataset %s: %d items, %d scans %s" % (a.out, len(items), len(scans), json.dumps(kinds, sort_keys=True)))
    return 0


def cmd_keygen(a):
    if not os.path.exists(a.out):
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w", encoding="ascii") as f:
            f.write("onems_" + secrets.token_hex(24))
    key = transport.read_key(a.out)
    print(hashlib.sha256(key.encode()).hexdigest(), key[:12])
    return 0


def write_delivery(out_dir, delivery, period_start, period_end):
    """Writes delivery.<fmt>, manifest.json and the POST /deliveries body; returns (file path, request body)."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "delivery." + delivery["format"])
    with open(path, "wb") as f:
        f.write(delivery["bytes"])
    body = connector.open_request(delivery, period_start, period_end)
    save_json(os.path.join(out_dir, "manifest.json"), delivery["manifest"])
    save_json(os.path.join(out_dir, "02-open-request.json"), body)
    return path, body


def tampered_copy(path):
    """Same size, one digit changed: the sha256 no longer matches the declared one."""
    with open(path, "rb") as f:
        data = bytearray(f.read())
    for i in range(len(data) // 2, len(data)):
        if 48 <= data[i] <= 57:
            data[i] = 48 + (data[i] - 47) % 10
            break
    out = path + ".tampered"
    with open(out, "wb") as f:
        f.write(bytes(data))
    return out


def api(t, cfg, method, path, body=None):
    """One API call with the retries of CL-REQ-019 (network error, 429 with Retry-After, 5xx; bounded)."""
    local = cfg["mode"] == "local"
    return transport.with_retries(lambda: t.request(method, path, body), lambda: t.last_retry_after,
                                  max_retries=int(cfg.get("max_retries", 5)),
                                  sleep=(lambda _s: None) if local else time.sleep)


def open_and_upload(t, cfg, run_dir, body, src, attempt):
    """POST /deliveries then the single PUT. A failed PUT (or an expired URL) is solved by opening again with the
    same body: same delivery, fresh URL (manual §12.2). Returns (delivery_id, ok)."""
    status, resp = api(t, cfg, "POST", "/deliveries", body)
    name = "03-open-response.json" if attempt == 0 else "03-open-response.retry%d.json" % attempt
    save_json(os.path.join(run_dir, name), {"http_status": status, "body": resp})
    show("POST /deliveries", status, resp, 600)
    if status not in (200, 201):
        return None, False
    did = resp["delivery"]["delivery_id"]
    if not resp.get("upload"):
        print("no upload URL: the delivery is already %s" % resp["delivery"].get("status"))
        return did, True
    try:
        status, up = t.upload(resp["upload"], src)
    except transport.NetworkError as e:
        status, up = None, {"network_error": str(e)}
    name = "04-upload-response.json" if attempt == 0 else "04-upload-response.retry%d.json" % attempt
    save_json(os.path.join(run_dir, name), {"http_status": status, "body": up})
    show("PUT <upload url>", status, up)
    if status == 200 or transport.already_uploaded(status, up):
        if status != 200:
            print("  the file is already there (Storage duplicate): go on with complete")
        return did, True
    return did, False


def poll(t, cfg, delivery_id, wait=True):
    """GET /deliveries/{id} until a final status (local mode: one server 'minute' (tick) before each poll)."""
    interval = 0 if cfg["mode"] == "local" else max(30.0, float(cfg.get("poll_seconds", 60)))   # CL-REQ-018
    deadline = time.monotonic() + float(cfg.get("poll_timeout_seconds", 3600))
    last = None
    while True:
        t.tick()
        status, body = api(t, cfg, "GET", "/deliveries/%s" % delivery_id)
        d = (body or {}).get("delivery") or {}
        now = (status, d.get("status"), d.get("phase"))
        if now != last:
            print("GET /deliveries/%s -> HTTP %s status=%s phase=%s rows=%s/%s shipments=%s valid=%s drawn=%s"
                  % (delivery_id, status, d.get("status"), d.get("phase"), d.get("rows_loaded"), d.get("rows_total"),
                     d.get("shipments_total"), d.get("shipments_valid"), d.get("shipments_drawn")))
            last = now
        if status != 200 or d.get("status") in FINAL or not wait:
            return status, body
        if d.get("status") == "failed":
            print("  failed (%s): ONEMS retries it automatically (at most 3 attempts, 5 minutes apart)" % d.get("error"))
        if time.monotonic() > deadline:
            print("  still %s after the poll timeout" % d.get("status"))
            return status, body
        time.sleep(interval)


def cmd_deliver(a):
    cfg = load_config(a.config)
    t = make_transport(cfg)
    scans = dataset.read_scans(cfg["dataset_dir"])
    formats = [a.format] if a.format else (cfg.get("formats") or ["jsonl"])
    done, rc = 0, 0
    while done < a.max:
        status, config = api(t, cfg, "GET", "/config")
        if status != 200:
            show("GET /config", status, config)
            return 1
        np = config.get("next_period") or {}
        print("GET /config -> HTTP 200 connector=%s status=%s next_period=%s"
              % ((config.get("connector") or {}).get("name"), (config.get("connector") or {}).get("status"),
                 json.dumps(np)))
        if not np:
            print("no period left to deliver (no active plan ahead)")
            break
        if not np.get("deliverable"):
            print("next period %s..%s is not closed yet: nothing to deliver now" % (np["period_start"], np["period_end"]))
            break
        p0 = dt.date.fromisoformat(np["period_start"])
        p1 = dt.date.fromisoformat(np["period_end"])
        fmt = formats[done % len(formats)]
        run_dir = os.path.join(cfg["out_dir"], "%s_%s%s" % (p0, p1, "-tampered" if a.tamper else ""))
        save_json(os.path.join(run_dir, "01-get-config.json"), {"http_status": status, "body": config})
        delivery = connector.build_delivery(scans, config, p0, p1, cfg["seed"], fmt=fmt, noise=cfg.get("noise"),
                                            pii_fields=cfg.get("pii_fields"))
        path, body = write_delivery(run_dir, delivery, p0, p1)
        m = delivery["manifest"]
        print("period %s..%s: %d complete shipments, %d rows (+%d broken), %s, %d bytes, sha256 %s"
              % (p0, p1, m["shipments"], m["rows"], m["invalid_rows"], fmt, m["size_bytes"], m["sha256"]))

        src = tampered_copy(path) if a.tamper else path
        reopen = int(cfg.get("max_reopen", 2))
        for attempt in range(reopen + 1):
            did, uploaded = open_and_upload(t, cfg, run_dir, body, src, attempt)
            if did is None:
                return 1
            if not uploaded:
                if attempt < reopen:
                    print("  upload failed: open again for a fresh URL")
                    continue
                return 1
            status, resp = api(t, cfg, "POST", "/deliveries/%s/complete" % did)
            save_json(os.path.join(run_dir, "05-complete-response.json"), {"http_status": status, "body": resp})
            show("POST /deliveries/%s/complete" % did, status, resp, 600)
            if status == 409 and (resp or {}).get("error") == "CL_FILE_NOT_UPLOADED" and attempt < reopen:
                print("  the file is not there: open again and upload")
                continue
            break
        if status >= 500 or (status == 409 and (resp or {}).get("error") == "CL_FILE_NOT_UPLOADED"):
            return 1
        status, resp = poll(t, cfg, did, wait=not a.no_wait)
        save_json(os.path.join(run_dir, "06-status.json"), {"http_status": status, "body": resp})
        final = ((resp or {}).get("delivery") or {}).get("status")
        done += 1
        if final != "processed":
            print("delivery %s ended %s (%s): stop" % (did, final, ((resp or {}).get("delivery") or {}).get("error")))
            rc = 0 if (a.tamper and final == "rejected") else 1
            break
    print("%d delivery(ies) sent" % done)
    return rc


def cmd_build(a):
    config = load_json(a.config_json)
    config = config.get("body", config)
    delivery = connector.build_delivery(dataset.read_scans(a.dataset), config, dt.date.fromisoformat(a.date_from),
                                        dt.date.fromisoformat(a.date_to), a.seed, fmt=a.format)
    path, _body = write_delivery(a.out, delivery, dt.date.fromisoformat(a.date_from), dt.date.fromisoformat(a.date_to))
    print("%s: %s" % (path, json.dumps(delivery["manifest"])))
    return 0


def cmd_call(a):
    cfg = load_config(a.config)
    t = make_transport(cfg)
    body = None
    if a.body:
        with open(a.body, "rb") as f:
            body = f.read()
    path = a.path if a.path.startswith("/") else "/" + a.path   # "config" = "/config"
    status, resp = t.request(a.method.upper(), path, body)
    if a.save:
        save_json(a.save, {"http_status": status, "body": resp})
    show("%s %s" % (a.method.upper(), path), status, resp)
    return 0


def cmd_status(a):
    cfg = load_config(a.config)
    status, resp = poll(make_transport(cfg), cfg, a.delivery, wait=a.wait)
    show("GET /deliveries/%s" % a.delivery, status, resp, 4000)
    return 0 if status == 200 else 1


def main(argv):
    p = argparse.ArgumentParser(prog="sim.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate")
    g.add_argument("--network", default=os.path.join(HERE, "network.json"))
    g.add_argument("--seed", required=True)
    g.add_argument("--from", dest="date_from", required=True)
    g.add_argument("--to", dest="date_to", required=True)
    g.add_argument("--as-of", dest="as_of", required=True)
    g.add_argument("--out", default=os.path.join(HERE, "out", "dataset"))

    k = sub.add_parser("keygen")
    k.add_argument("--out", required=True)

    d = sub.add_parser("deliver")
    d.add_argument("--config", required=True)
    d.add_argument("--max", type=int, default=100, help="at most N deliveries in this run")
    d.add_argument("--format", choices=("jsonl", "csv"))
    d.add_argument("--tamper", action="store_true")
    d.add_argument("--no-wait", action="store_true")

    b = sub.add_parser("build")
    b.add_argument("--config-json", required=True)
    b.add_argument("--dataset", required=True)
    b.add_argument("--from", dest="date_from", required=True)
    b.add_argument("--to", dest="date_to", required=True)
    b.add_argument("--format", choices=("jsonl", "csv"), default="jsonl")
    b.add_argument("--seed", default="sim-2026")
    b.add_argument("--out", required=True)

    c = sub.add_parser("call")
    c.add_argument("--config", required=True)
    c.add_argument("--method", required=True)
    c.add_argument("--path", required=True)
    c.add_argument("--body")
    c.add_argument("--save")

    s = sub.add_parser("status")
    s.add_argument("--config", required=True)
    s.add_argument("--delivery", required=True)
    s.add_argument("--wait", action="store_true")

    a = p.parse_args(argv)
    cmds = {"generate": cmd_generate, "keygen": cmd_keygen, "deliver": cmd_deliver, "build": cmd_build,
            "call": cmd_call, "status": cmd_status}
    try:
        return cmds[a.cmd](a)
    except (transport.TransportError, connector.ConnectorError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
