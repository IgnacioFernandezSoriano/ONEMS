"""Reference connector logic (no I/O): from a demand and the carrier's scans to the batches ONEMS expects.

Per stratum (spec section 4, R4, R23):
  * population = CLOSED items of the demand's products: a scan at one of the stratum's start points and, as in
    cl_ingest_batch, the LATEST scan at one of its end points (other than the first start scan) with its LOCAL date
    inside the period (only scans with a readable timestamp decide);
  * candidates = min(candidates_requested, population) items drawn uniformly at random (seeded, reproducible);
  * rows = ALL scans of the candidates at the start/end points of ANY stratum of the demand (any city), or all their
    scans when include_all_scans is true; only the configured output fields (personal data refused: PII_FIELDS).
Batches: whole strata packed in demand order, at most max_rows rows and max_bytes bytes per batch. ONEMS accepts each
stratum only once per demand (CL_STRATUM_ALREADY_DELIVERED), so a stratum is never split; a stratum larger than the
limit is an error.
"""
import datetime as dt
import hashlib
import json
import random

from . import contract

DEFAULT_OUTPUT_FIELDS = ["tracking_no", "event_ts", "site_code", "event_code", "service", "weight_g"]
# Personal data the connector must never send (spec R19 / anti-goals), on top of any configured pii_fields.
PII_FIELDS = frozenset(["recipient_name", "recipient_phone", "recipient_address", "recipient_email",
                        "sender_name", "sender_phone", "sender_address", "sender_email"])


class ConnectorError(Exception):
    pass


def parse_ts(value, fmt):
    try:
        return dt.datetime.strptime((value or "").strip(), fmt)
    except ValueError:
        return None


def _point_key(p):
    place = (p.get("place_ref") or "").strip()
    mode = p.get("mode_ref")
    mode = mode.strip() if isinstance(mode, str) and mode.strip() != "" else None
    return place, mode


def matches(scan, points):
    """points = set of (place, mode); mode None = any event code at that place (ONEMS rule D4)."""
    place = (scan.get("site_code") or "").strip()
    if not place:
        return False
    code = (scan.get("event_code") or "").strip()
    return (place, code) in points or (place, None) in points


def index_items(scans, fmt):
    """tracking_no -> list of (scan, parsed datetime or None), in table order."""
    out = {}
    for s in scans:
        tn = s.get("tracking_no")
        if tn:
            out.setdefault(tn, []).append((s, parse_ts(s.get("event_ts"), fmt)))
    return out


def item_service(entries):
    """Service of the item: the one on its earliest readable scan (how the carrier's own table would answer)."""
    readable = [(t, s) for s, t in entries if t is not None]
    if not readable:
        return None
    return min(readable, key=lambda x: x[0])[1].get("service")


def population(items, stratum, products):
    start = {_point_key(p) for p in stratum["start_points"]}
    end = {_point_key(p) for p in stratum["end_points"]}
    p0 = dt.date.fromisoformat(stratum["period"]["start"])
    p1 = dt.date.fromisoformat(stratum["period"]["end"])
    pop = []
    for tn in sorted(items):
        entries = items[tn]
        if item_service(entries) not in products:
            continue
        # Same rule as cl_ingest_batch: start = first readable start reading; end = LATEST readable end reading that
        # is not that same reading (a single scan at a point with both roles is not a shipment). The item is closed
        # in the period only if that latest end reading's local date is inside the period.
        starts = [(t, i) for i, (s, t) in enumerate(entries) if t is not None and matches(s, start)]
        if not starts:
            continue
        first_start = min(starts)[1]
        ends = [t for i, (s, t) in enumerate(entries) if t is not None and matches(s, end) and i != first_start]
        if ends and p0 <= max(ends).date() <= p1:
            pop.append(tn)
    return pop


def draw(pop, k, seed, demand_id, stratum_id):
    rng = random.Random("%s|%s|%s" % (seed, demand_id, stratum_id))
    return sorted(rng.sample(pop, min(k, len(pop))))


def check_output_fields(fields, pii_fields=None):
    banned = PII_FIELDS | set(pii_fields or [])
    bad = sorted(f for f in fields if f in banned)
    if bad:
        raise ConnectorError("output_fields contains personal data, never sent to ONEMS: %s" % ", ".join(bad))


def build_strata(demand, items, seed, output_fields=None, pii_fields=None):
    """Returns [{stratum_id, population_size, selection_method, rows}, ...] in demand order and a manifest."""
    fields = output_fields or DEFAULT_OUTPUT_FIELDS
    check_output_fields(fields, pii_fields)
    products = set(demand.get("products") or [])
    all_points = set()
    for s in demand["strata"]:
        all_points |= {_point_key(p) for p in s["start_points"] + s["end_points"]}
    all_scans = bool(demand.get("include_all_scans"))
    out, manifest = [], []
    for s in demand["strata"]:
        pop = population(items, s, products)
        chosen = draw(pop, s["candidates_requested"], seed, demand["demand_id"], s["stratum_id"])
        rows = []
        for tn in chosen:
            for scan, _t in items[tn]:
                if all_scans or matches(scan, all_points):
                    rows.append({f: scan.get(f) for f in fields if f in scan})
        out.append({"stratum_id": s["stratum_id"], "population_size": len(pop),
                    "selection_method": contract.SELECTION_METHOD, "rows": rows})
        manifest.append({"stratum_id": s["stratum_id"], "iso_week": s["period"].get("iso_week"),
                         "samples_required": s["samples_required"],
                         "candidates_requested": s["candidates_requested"],
                         "population_size": len(pop), "candidates": chosen, "rows": len(rows)})
    return out, manifest


def batch_prefix(demand_id, seed):
    # Stable for (demand, seed): a retry re-sends the same batch_id and ONEMS answers the stored result.
    return "SIM-%s-%s" % (demand_id[:8], hashlib.sha256(str(seed).encode()).hexdigest()[:6])


def pack_batches(demand_id, strata, seed, max_rows=contract.MAX_ROWS, max_bytes=contract.MAX_BODY_BYTES):
    max_rows = min(max_rows, contract.MAX_ROWS)
    max_bytes = min(max_bytes, contract.MAX_BODY_BYTES)
    envelope = 200   # demand_id, batch_id and JSON punctuation
    groups, cur, cur_rows, cur_bytes = [], [], 0, envelope
    for s in strata:
        n = len(s["rows"])
        size = len(json.dumps(s).encode("utf-8")) + 2
        if n > max_rows or envelope + size > max_bytes:
            raise ConnectorError("stratum %s has %d rows / %d bytes (limits %d rows, %d bytes): a stratum cannot be "
                                 "split across batches" % (s["stratum_id"], n, size, max_rows, max_bytes))
        if cur and (cur_rows + n > max_rows or cur_bytes + size > max_bytes):
            groups.append(cur)
            cur, cur_rows, cur_bytes = [], 0, envelope
        cur.append(s)
        cur_rows += n
        cur_bytes += size
    if cur:
        groups.append(cur)
    prefix = batch_prefix(demand_id, seed)
    batches = []
    for i, g in enumerate(groups, 1):
        b = {"demand_id": demand_id, "batch_id": "%s-%02d" % (prefix, i), "strata": g}
        if len(json.dumps(b).encode("utf-8")) > max_bytes:
            raise ConnectorError("batch %s exceeds %d bytes" % (b["batch_id"], max_bytes))
        batches.append(b)
    return batches
