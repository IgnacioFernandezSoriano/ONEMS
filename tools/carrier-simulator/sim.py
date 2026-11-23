"""ONEMS Carrier Link - simulated carrier. Python 3 stdlib only; run with `python -I`.

  python -I sim.py generate --seed S --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-19T06:00 [--network network.json]
                            [--out out/dataset]
        writes the carrier "database": out/dataset/scans.csv (one row per scan) + items.json (ground truth, tests only)
  python -I sim.py keygen --out out/carrier_key.txt
        creates a random connector key (local tests only) and prints "<sha256 hex> <first 12 chars>"
  python -I sim.py run --config config.json [--dry-run | --real] [--max-rows N] [--demand ID]
        reference connector: GET /demands, builds the batches of every open demand (or one), POSTs them and prints
        and saves the responses under out_dir/<demand_id>/
  python -I sim.py post --config config.json --file batch.json [--dry-run | --real]
        posts one batch file as is (replays, manual tests)
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import secrets
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from carrier_sim import connector, dataset, transport  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


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
    for k in ("key_file", "dataset_dir", "out_dir", "network"):
        if cfg.get(k):
            cfg[k] = os.path.normpath(os.path.join(base, cfg[k]))
    cfg.setdefault("network", os.path.join(HERE, "network.json"))
    if cfg.get("mode") not in ("local", "dev"):
        raise SystemExit("config: mode must be 'local' or 'dev'")
    for k in ("key_file", "seed", "dataset_dir", "out_dir"):
        if cfg.get(k) in (None, ""):
            raise SystemExit("config: %s is required" % k)
    return cfg


def make_transport(cfg):
    key = transport.read_key(cfg["key_file"])
    if cfg["mode"] == "dev":
        if not cfg.get("base_url"):
            raise SystemExit("config: base_url is required in dev mode")
        return transport.DevTransport(cfg["base_url"], key)
    os.makedirs(cfg["out_dir"], exist_ok=True)
    return transport.LocalTransport(cfg.get("local") or {}, key, cfg["out_dir"])


def show(status, body):
    print("HTTP %d %s" % (status, json.dumps(body, ensure_ascii=False)[:4000]))


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


def cmd_run(a):
    cfg = load_config(a.config)
    dry = cfg.get("dry_run", True) if a.dry is None else a.dry
    max_rows = a.max_rows or cfg.get("max_rows") or 5000
    network = load_json(cfg["network"])
    t = make_transport(cfg)

    status, body = t.get_demands()
    print("GET /demands -> HTTP %d, %d open demand(s)" % (status, len((body or {}).get("demands") or [])))
    if status != 200:
        show(status, body)
        return 1
    save_json(os.path.join(cfg["out_dir"], "get-demands.json"), body)
    demands = body["demands"]
    if a.demand:
        demands = [d for d in demands if d.get("demand_id") == a.demand]
        if not demands:
            print("demand %s is not open for this connector" % a.demand)
            return 1
    items = connector.index_items(dataset.read_scans(cfg["dataset_dir"]), network["ts_format"])
    rc = 0
    for d in demands:
        if d.get("carrier") != network["carrier"]:
            print("WARNING: demand %s is for carrier %r, the simulated network is %r"
                  % (d["demand_id"], d.get("carrier"), network["carrier"]))
        strata, manifest = connector.build_strata(d, items, cfg["seed"], cfg.get("output_fields"),
                                                  cfg.get("pii_fields"))
        batches = connector.pack_batches(d["demand_id"], strata, cfg["seed"], max_rows=max_rows)
        run_dir = os.path.join(cfg["out_dir"], d["demand_id"])
        save_json(os.path.join(run_dir, "demand.json"), d)
        print("demand %s: %d strata, %d candidates, %d rows -> %d batch(es)%s"
              % (d["demand_id"], len(strata), sum(len(m["candidates"]) for m in manifest),
                 sum(len(s["rows"]) for s in strata), len(batches), " [dry_run]" if dry else ""))
        posted = []
        for i, b in enumerate(batches, 1):
            save_json(os.path.join(run_dir, "batch-%02d.json" % i), b)
            status, resp = t.post_batch(b, dry)
            name = "response-%02d%s.json" % (i, ".dry_run" if dry else "")
            save_json(os.path.join(run_dir, name), {"http_status": status, "body": resp})
            print("POST /batches%s %s (%d strata, %d rows) -> HTTP %d"
                  % ("?dry_run=true" if dry else "", b["batch_id"], len(b["strata"]),
                     sum(len(s["rows"]) for s in b["strata"]), status))
            show(status, _short(resp))
            posted.append({"file": "batch-%02d.json" % i, "batch_id": b["batch_id"], "response": name,
                           "http_status": status, "strata": [s["stratum_id"] for s in b["strata"]]})
            if status != 200:
                rc = 1
        save_json(os.path.join(run_dir, "manifest%s.json" % (".dry_run" if dry else "")),
                  {"demand_id": d["demand_id"], "seed": cfg["seed"], "dry_run": dry, "max_rows": max_rows,
                   "strata": manifest, "batches": posted})
    return rc


def _short(resp):
    """Compact view of a response for the console (the full one is saved)."""
    if not isinstance(resp, dict) or "ingest" not in resp:
        return resp
    ing = resp.get("ingest") or {}
    view = {"ingest": {k: ing.get(k) for k in ("batch", "status", "dry_run", "reason") if k in ing}}
    view["ingest"]["strata"] = [{k: s.get(k) for k in ("population_size", "rows", "candidates", "candidates_valid",
                                                       "rejected", "rows_rejected")}
                                for s in ing.get("strata") or []]
    if "sampling" in resp:
        view["samples_selected"] = [x.get("samples_selected") if isinstance(x, dict) else x
                                    for x in resp["sampling"]]
    if "finish" in resp:
        view["finish"] = resp["finish"]
    if "failed" in resp:
        view["failed"] = resp["failed"]
    return view


def cmd_post(a):
    cfg = load_config(a.config)
    dry = cfg.get("dry_run", True) if a.dry is None else a.dry
    t = make_transport(cfg)
    status, resp = t.post_batch(load_json(a.file), dry)
    if a.save:
        save_json(a.save, {"http_status": status, "body": resp})
    show(status, resp)
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

    for name in ("run", "post"):
        r = sub.add_parser(name)
        r.add_argument("--config", required=True)
        r.add_argument("--dry-run", dest="dry", action="store_const", const=True, default=None)
        r.add_argument("--real", dest="dry", action="store_const", const=False)
        if name == "run":
            r.add_argument("--max-rows", type=int)
            r.add_argument("--demand")
        else:
            r.add_argument("--file", required=True)
            r.add_argument("--save")

    a = p.parse_args(argv)
    try:
        return {"generate": cmd_generate, "keygen": cmd_keygen, "run": cmd_run, "post": cmd_post}[a.cmd](a)
    except (transport.TransportError, connector.ConnectorError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
