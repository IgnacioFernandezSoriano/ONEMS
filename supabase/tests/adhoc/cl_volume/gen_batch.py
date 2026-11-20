"""Realistic Carrier Link batch(es) for one demand of the volume test (no dependencies; run with `python -I`).

Input: one demand payload (cl_demands.payload, as GET /demands returns it). Output: one or more batch files in the
CARRIER's field names (connector of fixture.sql), split so that no batch has more than --max-rows readings (the Edge
Function refuses more than 5,000 rows per POST); a demand may arrive in several batches, each stratum in only one.

Per stratum, candidates_requested shipments (the plan's oversampling), each with three readings:
    acceptance  (C<nn>-HUB / ACC, origin city)      -> start
    dispatch    (C<nn>-HUB / DSP, origin city)      -> intermediate (registered point without E2E role)
    delivery    (C<mm>-HUB / DLV, destination city) -> end, local date inside the stratum period, with personal data
                                                       (recipient_name, recipient_address, ...) that ingest must drop
Transit 1-5 days. About 4 % of the shipments lack the acceptance reading (rejected as no_start), like a real feed.
population_size is 6-15 times the candidates. Deterministic: seeded with the demand id + --suffix.

Usage: python -I gen_batch.py DEMAND_JSON OUT_DIR [--suffix r1] [--max-rows 5000]
Writes OUT_DIR/batch_<n>.json and OUT_DIR/manifest.json:
  {"demand_id", "strata", "candidates", "rows", "batches": [{"file", "batch_id", "strata": [ids], "rows", "bytes"}]}
"""
import datetime as dt
import json
import os
import random
import sys

FIRST = ["J.", "M.", "A.", "R.", "L.", "K.", "D.", "S."]
LAST = ["Otieno", "Wanjiru", "Kamau", "Mwangi", "Achieng", "Njoroge", "Kiptoo", "Mutua"]


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    src, out_dir = argv[1], argv[2]
    suffix, max_rows = "r1", 5000
    rest = argv[3:]
    while rest:
        if rest[0] == "--suffix" and len(rest) > 1:
            suffix, rest = rest[1], rest[2:]
        elif rest[0] == "--max-rows" and len(rest) > 1:
            max_rows, rest = int(rest[1]), rest[2:]
        else:
            print("unknown argument: %s" % rest[0], file=sys.stderr)
            return 2

    with open(src, encoding="utf-8") as f:
        demand = json.load(f)
    rng = random.Random("%s:%s" % (demand["demand_id"], suffix))
    product = demand["products"][0]
    used = set()

    def new_id():
        while True:
            v = "VL%010dKE" % rng.randint(0, 9999999999)
            if v not in used:
                used.add(v)
                return v

    def row(item, when, point, pii=False):
        r = {"tracking_number": item, "service_code": product, "event_time": when.strftime("%Y-%m-%d %H:%M:%S"),
             "facility_id": point["place_ref"], "event_code": point["mode_ref"],
             "weight_kg": round(rng.uniform(0.05, 2.5), 2)}
        if pii:
            r["recipient_name"] = "%s %s" % (rng.choice(FIRST), rng.choice(LAST))
            r["recipient_address"] = "P.O. Box %d-%05d" % (rng.randint(1, 9999), rng.randint(100, 99999))
            r["recipient_phone"] = "+254 7%02d %03d %03d" % (rng.randint(0, 99), rng.randint(0, 999), rng.randint(0, 999))
        return r

    out_strata, candidates = [], 0
    for s in demand["strata"]:
        p0 = dt.date.fromisoformat(s["period"]["start"])
        p1 = dt.date.fromisoformat(s["period"]["end"])
        days = [p0 + dt.timedelta(days=k) for k in range((p1 - p0).days + 1)]
        n = s["candidates_requested"]
        rows = []
        for _ in range(n):
            item = new_id()
            sp = rng.choice(s["start_points"])
            ep = rng.choice(s["end_points"])
            end_at = dt.datetime.combine(rng.choice(days), dt.time(rng.randint(8, 17), rng.randint(0, 59), rng.randint(0, 59)))
            start_at = dt.datetime.combine(end_at.date() - dt.timedelta(days=rng.randint(1, 5)),
                                           dt.time(rng.randint(7, 11), rng.randint(0, 59), rng.randint(0, 59)))
            dispatch = start_at + dt.timedelta(hours=rng.randint(2, 5), minutes=rng.randint(0, 59))
            if rng.random() >= 0.04:
                rows.append(row(item, start_at, sp))
            rows.append(row(item, dispatch, {"place_ref": sp["place_ref"], "mode_ref": "DSP"}))
            rows.append(row(item, end_at, ep, pii=True))
        candidates += n
        out_strata.append({"stratum_id": s["stratum_id"], "population_size": rng.randint(n * 6, n * 15),
                           "selection_method": "uniform_random_within_stratum", "rows": rows})

    # Split by rows, keeping each stratum whole and the demand order.
    chunks, cur, cur_rows = [], [], 0
    for st in out_strata:
        k = len(st["rows"])
        if k > max_rows:
            print("stratum %s alone has %d rows (> %d)" % (st["stratum_id"], k, max_rows), file=sys.stderr)
            return 1
        if cur and cur_rows + k > max_rows:
            chunks.append(cur)
            cur, cur_rows = [], 0
        cur.append(st)
        cur_rows += k
    if cur:
        chunks.append(cur)

    os.makedirs(out_dir, exist_ok=True)
    manifest = {"demand_id": demand["demand_id"], "strata": len(out_strata), "candidates": candidates,
                "rows": sum(len(s["rows"]) for s in out_strata), "batches": []}
    for i, ch in enumerate(chunks, 1):
        batch_id = "VOL-%s-%s-%d" % (demand["demand_id"][:8], suffix, i)
        body = json.dumps({"demand_id": demand["demand_id"], "batch_id": batch_id, "strata": ch})
        path = os.path.join(out_dir, "batch_%d.json" % i)
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        manifest["batches"].append({"file": path, "batch_id": batch_id, "strata": [s["stratum_id"] for s in ch],
                                    "rows": sum(len(s["rows"]) for s in ch), "bytes": len(body.encode("utf-8"))})
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    print("demand %s: %d strata, %d shipments, %d rows in %d batch(es) of %s rows, %s bytes"
          % (demand["demand_id"][:8], manifest["strata"], candidates, manifest["rows"], len(chunks),
             "/".join(str(b["rows"]) for b in manifest["batches"]), "/".join(str(b["bytes"]) for b in manifest["batches"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
