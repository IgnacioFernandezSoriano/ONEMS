"""Seeded synthetic carrier database: one row per scan event, in the CARRIER's own field names.

Scan table (scans.csv), columns = the carrier's fields:
    tracking_no, event_ts (local time, network ts_format, no offset), site_code, event_code, service, weight_g,
    recipient_name, recipient_phone (personal data: present in the carrier DB, never sent by the connector)

Ground truth (items.json): per item its origin/destination city, service, anomaly and expected delivery city. Only the
tests read it; the connector only reads scans.csv, like a real connector only reads the carrier's tables.

Life of a normal item: ACC (acceptance, origin post office) -> DSP (dispatch, origin processing center) -> ARR (hub) ->
ARR (destination processing center) -> OFD (out for delivery, destination post office) -> DLV (delivery, same office).
Scans after `as_of` do not exist yet (items still in transit are simply not closed).

Anomalies (one per item at most, rates from network.json):
    undelivered          no OFD/DLV (stuck at the destination processing center or lost)
    misrouted_corrected  sorted to another city X: ARR + DLV at X (wrong delivery scan), then forwarded and delivered
                         at the right office 1-2 days later
    misrouted_lost       delivered in another city X (never reaches its destination)
    clock_error          the DLV scanner clock is wrong: DLV time is one day BEFORE the acceptance
    bad_service          the DLV scan carries a corrupt service code (bad_service_code)
    bad_timestamp        an extra duplicate ACC scan with an unparseable event_ts (bad_timestamp_value)
    missing_site         the OFD scan has an empty site_code
"""
import csv
import datetime as dt
import json
import os
import random

FIELDS = ["tracking_no", "event_ts", "site_code", "event_code", "service", "weight_g",
          "recipient_name", "recipient_phone"]
FIRST = ["A.", "B.", "C.", "D.", "E.", "F.", "G.", "H."]
LAST = ["Otieno", "Mwangi", "Kamau", "Achieng", "Njoroge", "Wanjiru", "Odhiambo", "Kiptoo"]


def _pick_weighted(rng, weights):
    keys = sorted(weights)
    return rng.choices(keys, weights=[weights[k] for k in keys], k=1)[0]


def tracking_number(index):
    # Unique for index < 10**9 (7919 is coprime with 10**9); looks scattered like a real tracking number.
    return "SP%09dSL" % ((index * 7919 + 104729) % 10 ** 9)


def generate(network, seed, date_from, date_to, as_of):
    """Returns (scans, items). date_from/date_to = acceptance dates (inclusive); as_of = naive local datetime."""
    rng = random.Random("dataset:%s" % seed)
    fmt = network["ts_format"]
    cities = network["cities"]
    city_w = [c.get("weight", 1) for c in cities]
    anomalies = network.get("anomalies", {})
    an_keys = sorted(anomalies)
    an_p = [anomalies[k] for k in an_keys]
    scans, items = [], []
    index = 0
    day = date_from
    while day <= date_to:
        for _ in range(network["items_per_day"]):
            index += 1
            item = tracking_number(index)
            service = _pick_weighted(rng, network["services"])
            origin = rng.choices(cities, weights=city_w, k=1)[0]
            dest = rng.choices([c for c in cities if c is not origin],
                               weights=[c.get("weight", 1) for c in cities if c is not origin], k=1)[0]
            u, anomaly, acc = rng.random(), None, 0.0
            for k, p in zip(an_keys, an_p):
                acc += p
                if u < acc:
                    anomaly = k
                    break
            other = [c for c in cities if c is not origin and c is not dest]
            wrong = rng.choice(other) if other else None
            if anomaly in ("misrouted_corrected", "misrouted_lost") and wrong is None:
                anomaly = None
            weight = rng.randint(20, 2000)
            who = ("%s %s" % (rng.choice(FIRST), rng.choice(LAST)),
                   "+999 7%02d %03d %03d" % (rng.randint(0, 99), rng.randint(0, 999), rng.randint(0, 999)))
            t0 = dt.datetime.combine(day, dt.time(rng.randint(8, 16), rng.randint(0, 59), rng.randint(0, 59)))
            transit = rng.choice(network["transit_days"][service])
            t_del = dt.datetime.combine(day + dt.timedelta(days=transit),
                                        dt.time(rng.randint(9, 16), rng.randint(0, 59), rng.randint(0, 59)))
            span = t_del - t0
            ev = []   # (datetime or raw string, site, event, service override)

            def at(frac):
                return t0 + span * frac

            ev.append((t0, origin["post_office"], "ACC", None))
            ev.append((at(0.10), origin["processing_center"], "DSP", None))
            ev.append((at(0.35), network["hub"], "ARR", None))
            final_city = dest
            if anomaly in ("misrouted_corrected", "misrouted_lost"):
                ev.append((at(0.60), wrong["processing_center"], "ARR", None))
                ev.append((t_del - dt.timedelta(hours=2), wrong["post_office"], "OFD", None))
                ev.append((t_del, wrong["post_office"], "DLV", None))
                if anomaly == "misrouted_lost":
                    final_city = wrong
                else:
                    extra = dt.timedelta(days=rng.randint(1, 2))
                    ev.append((t_del + extra - dt.timedelta(hours=20), dest["processing_center"], "ARR", None))
                    ev.append((t_del + extra - dt.timedelta(hours=2), dest["post_office"], "OFD", None))
                    ev.append((t_del + extra, dest["post_office"], "DLV", None))
            else:
                ev.append((at(0.60), dest["processing_center"], "ARR", None))
                if anomaly != "undelivered":
                    ev.append((t_del - dt.timedelta(hours=2), dest["post_office"],
                               "OFD", None))
                    dlv_at = t_del - dt.timedelta(days=transit + 1) if anomaly == "clock_error" else t_del
                    ev.append((dlv_at, dest["post_office"], "DLV",
                               network["bad_service_code"] if anomaly == "bad_service" else None))
                else:
                    final_city = None
            if anomaly == "bad_timestamp":
                ev.insert(1, (network["bad_timestamp_value"], origin["post_office"], "ACC", None))

            # Scans that would happen after as_of do not exist yet (the raw bad timestamp is a duplicate of ACC).
            rows = []
            for when, site, code, svc in ev:
                if isinstance(when, dt.datetime):
                    # clock_error: the DLV happens at t_del but is recorded one day before the acceptance.
                    physical = t_del if (anomaly == "clock_error" and code == "DLV") else when
                    if physical > as_of:
                        continue
                    ts = when.strftime(fmt)
                else:
                    if t0 > as_of:
                        continue
                    ts = when
                if anomaly == "missing_site" and code == "OFD":
                    site = ""
                row = {"tracking_no": item, "event_ts": ts, "site_code": site, "event_code": code,
                       "service": svc or service, "weight_g": weight, "recipient_name": "", "recipient_phone": ""}
                if code == "DLV":
                    row["recipient_name"], row["recipient_phone"] = who
                rows.append(row)
            delivered = any(r["event_code"] == "DLV" for r in rows)
            scans.extend(rows)
            items.append({"tracking_no": item, "service": service, "origin": origin["code"],
                          "destination": dest["code"], "anomaly": anomaly,
                          "delivered_in": (final_city["code"] if final_city and delivered else None),
                          "wrong_city": wrong["code"] if anomaly in ("misrouted_corrected", "misrouted_lost") else None,
                          "scans": len(rows)})
        day += dt.timedelta(days=1)
    return scans, items


def write(out_dir, scans, items, meta):
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "scans.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(scans)
    with open(os.path.join(out_dir, "items.json"), "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "items": items}, f, indent=0)


def read_scans(dataset_dir):
    with open(os.path.join(dataset_dir, "scans.csv"), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def read_items(dataset_dir):
    with open(os.path.join(dataset_dir, "items.json"), encoding="utf-8") as f:
        return json.load(f)
