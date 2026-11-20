"""Helpers for run.sh (no dependencies; run with `python -I`). Never prints the API key.

  one              stdin = `supabase db query --output-format json` output or raw JSON; prints the first column of the
                   first row as JSON (exit 1 on a CLI error).
  rows             same input; prints every row as one JSON line.
  strata           stdin = cl_ingest_batch summary; prints its stratum ids, one per line.
  get KEY          stdin = JSON object; prints obj[KEY] (JSON for objects, raw for strings).
  keygen DIR       creates DIR/carrier_key.txt and DIR/carrier_key_header.txt (if absent) and prints
                   "<sha256 hex> <first 12 chars>".
  render TMPL OUT HASH PREFIX   renders the key SQL template.
  http FILE        FILE = curl body followed by a last line with the HTTP status; prints a short view, exit 1 if >= 400.
  verify BASE SUM  compares the check summary with the baseline; exit 1 if an expectation fails.
"""
import hashlib
import json
import os
import secrets
import sys


def _payload(text):
    text = text.strip()
    i = text.find("{")
    if i < 0:
        raise SystemExit("no JSON in output:\n" + text[:2000])
    obj = json.loads(text[i:])
    if isinstance(obj, dict) and obj.get("_tag") == "Error":
        raise SystemExit("CLI error: " + json.dumps(obj.get("error"), ensure_ascii=False))
    return obj


def _rows(obj):
    if isinstance(obj, dict) and "rows" in obj and "boundary" in obj:
        return obj["rows"]
    return [{"value": obj}]


def _val(v):
    if isinstance(v, str):
        try:
            return json.loads(v)
        except ValueError:
            return v
    return v


def main(a):
    cmd = a[1] if len(a) > 1 else ""
    if cmd == "one":
        rows = _rows(_payload(sys.stdin.read()))
        if not rows:
            raise SystemExit("no rows")
        print(json.dumps(_val(next(iter(rows[0].values()))), ensure_ascii=False))
    elif cmd == "rows":
        for r in _rows(_payload(sys.stdin.read())):
            print(json.dumps({k: _val(v) for k, v in r.items()}, ensure_ascii=False))
    elif cmd == "strata":
        for s in _val(json.loads(sys.stdin.read())).get("strata") or []:
            if isinstance(s, dict) and isinstance(s.get("stratum_id"), str):
                print(s["stratum_id"])
    elif cmd == "get":
        v = json.loads(sys.stdin.read()).get(a[2])
        print(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))
    elif cmd == "keygen":
        d = a[2]
        kf = os.path.join(d, "carrier_key.txt")
        if not os.path.exists(kf):
            with open(kf, "w", encoding="ascii") as f:
                f.write("onems_" + secrets.token_hex(24))
        with open(kf, encoding="ascii") as f:
            key = f.read().strip()
        with open(os.path.join(d, "carrier_key_header.txt"), "w", encoding="ascii") as f:
            f.write("x-api-key: " + key + "\n")
        print(hashlib.sha256(key.encode()).hexdigest(), key[:12])
    elif cmd == "render":
        tmpl, out, h, p = a[2:6]
        with open(tmpl, encoding="utf-8") as f:
            s = f.read()
        with open(out, "w", encoding="utf-8") as f:
            f.write(s.replace("__KEY_HASH__", h).replace("__KEY_PREFIX__", p))
    elif cmd == "http":
        with open(a[2], encoding="utf-8") as f:
            lines = f.read().rstrip("\n").split("\n")
        code, body = int(lines[-1]), "\n".join(lines[:-1])
        try:
            obj = json.loads(body)
            if isinstance(obj, dict) and "demands" in obj:
                view = {"demands": [{"demand_id": d.get("demand_id"), "strata": len(d.get("strata") or []),
                                     "required": [s.get("samples_required") for s in d.get("strata") or []],
                                     "candidates_requested": [s.get("candidates_requested") for s in d.get("strata") or []]}
                                    for d in obj["demands"]]}
            else:
                view = obj
            print("HTTP %d %s" % (code, json.dumps(view, ensure_ascii=False, indent=1)))
        except ValueError:
            print("HTTP %d %s" % (code, body[:2000]))
        return 1 if code >= 400 else 0
    elif cmd == "verify":
        with open(a[2], encoding="utf-8") as f:
            base = json.load(f)
        with open(a[3], encoding="utf-8") as f:
            summ = json.load(f)
        ok = True
        for k, v in sorted((summ.get("expect") or {}).items()):
            print("  %-28s %s" % (k, "OK" if v else "FAIL"))
            ok = ok and bool(v)
        for k in ("panelist_rows_demo2", "panelist_hash_demo2", "apd_demo2", "incidents_demo2"):
            same = base.get(k) == summ.get(k)
            print("  %-28s %s" % ("unchanged " + k, "OK" if same else "FAIL (%s -> %s)" % (base.get(k), summ.get(k))))
            ok = ok and same
        print("  %-28s %+d (all accounts, real activity included)" %
              ("delta panelist_rows_all", int(summ.get("panelist_rows_all", 0)) - int(base.get("panelist_rows_all", 0))))
        print("RESULT: " + ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
