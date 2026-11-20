"""Synthetic Carrier Link batch for the DEMO2 test (no dependencies; run with `python -I`).

Reads the GET /demands answer ({"demands": [payload, ...]}) and writes ONE batch for one demand, in the CARRIER's field
names and values (the connector of "Carrier A" as configured by 10_points_feed.sql):

    tracking_number  -> item_id          service_code -> product ('STD' = A STANDARD)
    event_time       -> scan_at          ('YYYY-MM-DD HH24:MI:SS', America/New_York local time)
    facility_id      -> place_ref        event_code   -> mode_ref
    weight_kg        -> allowed extra field
    recipient_name / recipient_address / recipient_phone / sender_email -> personal data, must be DROPPED on entry

Per stratum: population_size (>= candidates), selection_method uniform_random_within_stratum and, per candidate
shipment, a start reading (acceptance), an intermediate reading (dispatch 'DSP' at the start facility, a registered
point with no E2E role) and an end reading (delivery) whose local date is inside the stratum period. Transit times are
1-6 calendar days, so with the A STANDARD standard (4 days) + 1 day of equivalence some samples are on time and some
late. The smallest stratum (fewest samples_required, last in demand order) carries the special cases:
    * 1 misrouted shipment: an extra delivery reading in another city (an end point of another stratum) before the
      final delivery -> possible_misrouting;
    * 2 invalid shipments: end before start (start_after_end) and an unknown service code (unknown_product);
  and it gets exactly samples_required valid candidates, so the draw always selects the misrouted shipment.
Deterministic: the random generator is seeded with the demand id (+ --suffix).

Usage: python -I gen_batch.py DEMANDS_JSON OUT_BATCH_JSON [--demand latest|first|<demand_id>] [--suffix 01]
"""
import datetime as dt
import json
import random
import sys

DROP_FIELDS = ("recipient_name", "recipient_address", "recipient_phone", "sender_email")
FIRST = ["J.", "M.", "A.", "R.", "L.", "K.", "D.", "S."]
LAST = ["Smith", "Garcia", "Johnson", "Lee", "Brown", "Martinez", "Davis", "Wilson"]


def city_key(place_ref):
    # Carrier facility codes of the test connector are '<CITY>-<SITE>' (NYC-RDC, NYC-LDC, BAL-PC, PHL-RH).
    return place_ref.split("-")[0]


def ts(d):
    return d.strftime("%Y-%m-%d %H:%M:%S")


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    src, out = argv[1], argv[2]
    pick, suffix = "latest", "01"
    rest = argv[3:]
    while rest:
        if rest[0] == "--demand" and len(rest) > 1:
            pick, rest = rest[1], rest[2:]
        elif rest[0] == "--suffix" and len(rest) > 1:
            suffix, rest = rest[1], rest[2:]
        else:
            print("unknown argument: %s" % rest[0], file=sys.stderr)
            return 2

    with open(src, encoding="utf-8") as f:
        demands = json.load(f).get("demands") or []
    if not demands:
        print("no open demand in %s" % src, file=sys.stderr)
        return 1
    if pick == "first":
        demand = demands[0]
    elif pick == "latest":
        demand = demands[-1]          # GET /demands orders by requested_at ascending
    else:
        matches = [d for d in demands if d.get("demand_id") == pick]
        if not matches:
            print("demand %s not found" % pick, file=sys.stderr)
            return 1
        demand = matches[0]

    rng = random.Random("%s:%s" % (demand["demand_id"], suffix))
    product = (demand.get("products") or ["STD"])[0]
    strata = demand["strata"]
    special = min(range(len(strata)), key=lambda i: (strata[i]["samples_required"], -i))
    used = set()

    def new_id():
        while True:
            v = "CA%09dUS" % rng.randint(0, 999999999)
            if v not in used:
                used.add(v)
                return v

    def row(item, when, point, code=None, prod=None, pii=False):
        r = {
            "tracking_number": item,
            "service_code": prod or product,
            "event_time": ts(when),
            "facility_id": point["place_ref"],
            "event_code": code or point.get("mode_ref") or "DLV",
            "weight_kg": round(rng.uniform(0.1, 2.5), 2),
        }
        if pii:
            r["recipient_name"] = "%s %s" % (rng.choice(FIRST), rng.choice(LAST))
            r["recipient_address"] = "%d Main St Apt %d" % (rng.randint(1, 999), rng.randint(1, 40))
            r["recipient_phone"] = "+1 555 %03d %04d" % (rng.randint(0, 999), rng.randint(0, 9999))
            r["sender_email"] = "sender%d@example.com" % rng.randint(1, 9999)
        return r

    def shipment(stratum, end_day, transit_days, prod=None):
        """Acceptance -> dispatch -> delivery; local NY times 07:00-15:59 (same date in Europe/Madrid)."""
        item = new_id()
        start_pt = rng.choice(stratum["start_points"])
        end_pt = rng.choice(stratum["end_points"])
        end_at = dt.datetime.combine(end_day, dt.time(rng.randint(7, 15), rng.randint(0, 59), rng.randint(0, 59)))
        start_at = dt.datetime.combine(end_day - dt.timedelta(days=transit_days),
                                       dt.time(rng.randint(7, 11), rng.randint(0, 59), rng.randint(0, 59)))
        if start_at >= end_at:
            start_at = end_at - dt.timedelta(hours=6)
        dispatch = start_at + dt.timedelta(hours=rng.randint(2, 5), minutes=rng.randint(0, 59))
        rows = [row(item, start_at, start_pt, prod=prod),
                row(item, dispatch, {"place_ref": start_pt["place_ref"]}, code="DSP", prod=prod),
                row(item, end_at, end_pt, prod=prod, pii=True)]
        return item, rows, start_pt, end_pt, start_at, end_at

    other_ends = []
    for s in strata:
        for p in s["end_points"]:
            if p not in other_ends:
                other_ends.append(p)

    out_strata, notes = [], {"demand_id": demand["demand_id"], "strata": [], "special_stratum": strata[special]["stratum_id"]}
    for i, s in enumerate(strata):
        p0 = dt.date.fromisoformat(s["period"]["start"])
        p1 = dt.date.fromisoformat(s["period"]["end"])
        days = [p0 + dt.timedelta(days=k) for k in range((p1 - p0).days + 1)]
        cands = s["candidates_requested"]
        n_valid = s["samples_required"] if i == special else cands
        rows, info = [], {"stratum_id": s["stratum_id"], "iso_week": s["period"]["iso_week"], "items": []}
        for k in range(n_valid):
            transit = rng.choice([1, 1, 2, 2, 2, 3, 3, 4, 5, 6])
            item, rr, sp, ep, sa, ea = shipment(s, rng.choice(days), transit)
            kind = "valid"
            if i == special and k == 0:
                # Misrouted: extra delivery reading in another city the day before the final delivery.
                own = {city_key(p["place_ref"]) for p in s["start_points"] + s["end_points"]}
                wrong = [p for p in other_ends if city_key(p["place_ref"]) not in own]
                if not wrong:
                    print("no end point in another city for the misrouted shipment", file=sys.stderr)
                    return 1
                detour = sa + (ea - sa) / 2
                rr.insert(2, row(item, detour, wrong[0], code=wrong[0].get("mode_ref") or "DLV"))
                kind = "misrouted via " + wrong[0]["place_ref"]
            rows.extend(rr)
            info["items"].append({"item": item, "kind": kind, "transit_days": transit})
        if i == special:
            # Invalid 1: delivery before acceptance.
            item, rr, sp, ep, sa, ea = shipment(s, rng.choice(days), 2)
            rr[0]["event_time"] = ts(ea + dt.timedelta(days=1))
            rr[1]["event_time"] = ts(ea + dt.timedelta(days=1, hours=3))
            rows.extend(rr)
            info["items"].append({"item": item, "kind": "invalid: start_after_end"})
            # Invalid 2: a service code the connector has no equivalence for.
            item, rr, sp, ep, sa, ea = shipment(s, rng.choice(days), 2, prod="INTL-PRI")
            rows.extend(rr)
            info["items"].append({"item": item, "kind": "invalid: unknown_product"})
        n_items = len(info["items"])
        out_strata.append({
            "stratum_id": s["stratum_id"],
            "population_size": rng.randint(cands * 6, cands * 15),
            "selection_method": "uniform_random_within_stratum",
            "rows": rows,
        })
        info["candidates"] = n_items
        notes["strata"].append(info)

    batch = {"demand_id": demand["demand_id"], "batch_id": "CA-%s-%s" % (demand["demand_id"][:8], suffix),
             "strata": out_strata}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(batch, f, indent=1)
    with open(out + ".notes.json", "w", encoding="utf-8") as f:
        json.dump(notes, f, indent=1)
    total = sum(len(s["items"]) for s in notes["strata"])
    rows_n = sum(len(s["rows"]) for s in out_strata)
    print("batch %s: %d strata, %d shipments, %d rows -> %s" % (batch["batch_id"], len(out_strata), total, rows_n, out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
