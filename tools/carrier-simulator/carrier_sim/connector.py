"""Reference connector logic (no I/O): from GET /config and the carrier's scan table to one delivery file.

Carrier Link v4 (spec section "v4", R24): for each delivery period the carrier sends ALL the complete shipments of the
period; ONEMS counts, draws and keeps only the drawn ones. The carrier never samples or preselects.

Normative definition of a complete shipment of the period (with the carrier's own codes, read from GET /config):
  a shipment of a product of the plan (its product code is one of config.products[].carrier_codes) that
  (1) has its FINAL arrival event (latest readable scan at a point with role destination/both) with a local date
      inside [period_start, period_end] (config.date_timezone);
  (2) has a departure event at a point with role origin/both that is earlier than that arrival (in this period or
      before);
  (3) is sent with ALL its scans at the agreed points (config.points, any role), or ALL its scans when
      config.include_all_scans is true (a plan with diagnosis).
Never delivered, still in transit or delivered at a non-agreed place = not complete = not in the file.

Rows only carry the fields of the connector (config.fields[*].field + config.extra_fields), never personal data
(PII_FIELDS, plus any configured pii_fields: the connector refuses to start if the config asks for one of them).

Noise of a real extraction, on purpose and seeded (NOISE): for a share of the shipments, their scans at places that
are NOT agreed points are also sent (ONEMS rejects those rows as unknown_reading_point), and a few syntactically broken
records are inserted (rejected as bad_record). The carrier's own data errors come from the dataset (unreadable
timestamps, corrupt product codes on one scan, misrouted shipments...).
"""
import csv
import hashlib
import io
import json
import random
import re

DEFAULT_NOISE = {"unagreed_scans_share": 0.08, "invalid_rows": 2}
# Personal data the connector must never send (spec R19 / anti-goals), on top of any configured pii_fields.
PII_FIELDS = frozenset(["recipient_name", "recipient_phone", "recipient_address", "recipient_email",
                        "sender_name", "sender_phone", "sender_address", "sender_email"])
STANDARD_FIELDS = ("item_id", "product", "scan_at", "place_ref", "mode_ref")
ORIGIN_ROLES = ("origin", "both")
DEST_ROLES = ("destination", "both")

# PostgreSQL to_timestamp tokens -> strptime (the subset a scan_at format of ONEMS uses).
_PG_TOKENS = [("YYYY", "%Y"), ("HH24", "%H"), ("HH12", "%I"), ("MI", "%M"), ("SS", "%S"), ("MM", "%m"),
              ("DD", "%d"), ("AM", "%p"), ("PM", "%p")]


class ConnectorError(Exception):
    pass


def pg_format_to_strptime(fmt):
    """'DD/MM/YYYY HH24:MI:SS' -> '%d/%m/%Y %H:%M:%S'. None = ISO 8601 (handled by parse_ts)."""
    if not fmt:
        return None
    out, i = "", 0
    while i < len(fmt):
        for tok, rep in _PG_TOKENS:
            if fmt.startswith(tok, i):
                out += rep
                i += len(tok)
                break
        else:
            out += "%%" if fmt[i] == "%" else fmt[i]
            i += 1
    return out


def parse_ts(value, fmt):
    import datetime as dt
    v = (value or "").strip()
    if not v:
        return None
    try:
        if fmt is None:
            t = dt.datetime.fromisoformat(v)
            return t.replace(tzinfo=None) if t.tzinfo is None else None   # offsets: see check_timezones
        return dt.datetime.strptime(v, fmt)
    except ValueError:
        return None


def field_names(config):
    """{standard field: carrier field} from GET /config (only the mapped ones)."""
    fields = config.get("fields") or {}
    out = {}
    for k in STANDARD_FIELDS:
        f = fields.get(k)
        if isinstance(f, dict) and isinstance(f.get("field"), str) and f["field"].strip():
            out[k] = f["field"]
    return out


def output_fields(config, pii_fields=None):
    """Fields sent in every row: the mapped carrier fields + the allowed extra fields, personal data refused."""
    names = field_names(config)
    if not config.get("mapping_complete") or not all(k in names for k in ("item_id", "scan_at", "place_ref")):
        raise ConnectorError("the connector mapping is incomplete in ONEMS (item_id, scan_at and place_ref are "
                             "required): ask the regulator")
    out = []
    for f in [names[k] for k in STANDARD_FIELDS if k in names] + list(config.get("extra_fields") or []):
        if f not in out:
            out.append(f)
    banned = PII_FIELDS | set(pii_fields or [])
    bad = sorted(f for f in out if f in banned)
    if bad:
        raise ConnectorError("the connector would send personal data, refused: %s" % ", ".join(bad))
    return out


def check_timezones(config):
    """The simulator has no time zone database (stdlib only on Windows): scan times must be in the zone of the
    period dates. A real connector converts each scan to config.date_timezone before taking its local date."""
    scan = (config.get("fields") or {}).get("scan_at") or {}
    tz = scan.get("timezone") or config.get("date_timezone")
    if tz != config.get("date_timezone"):
        raise ConnectorError("simulator limitation: scan_at.timezone %r differs from date_timezone %r"
                             % (tz, config.get("date_timezone")))


def _norm(v):
    return v.strip() if isinstance(v, str) and v.strip() != "" else None


def agreed_points(config):
    """{'origin': {(place, mode)}, 'destination': {...}, 'all': {...}}; mode None = any event code at that place."""
    out = {"origin": set(), "destination": set(), "all": set()}
    for p in config.get("points") or []:
        key = (_norm(p.get("place_ref")), _norm(p.get("mode_ref")))
        if key[0] is None:
            continue
        out["all"].add(key)
        if p.get("role") in ORIGIN_ROLES:
            out["origin"].add(key)
        if p.get("role") in DEST_ROLES:
            out["destination"].add(key)
    return out


def at_point(place, mode, points):
    place = _norm(place)
    if place is None:
        return False
    return (place, _norm(mode)) in points or (place, None) in points


def index_items(scans, names, ts_fmt):
    """item -> [(scan, parsed local datetime or None)], in table order."""
    out = {}
    for s in scans:
        item = _norm(s.get(names["item_id"]))
        if item:
            out.setdefault(item, []).append((s, parse_ts(s.get(names["scan_at"]), ts_fmt)))
    return out


def product_codes(config):
    codes = set()
    for p in config.get("products") or []:
        codes.update(c for c in (p.get("carrier_codes") or []) if isinstance(c, str))
    return codes


def item_product(entries, names):
    """The shipment's product: the one on its earliest readable scan (how the carrier's own table answers)."""
    if "product" not in names:
        return None
    readable = [(t, s) for s, t in entries if t is not None]
    if not readable:
        return None
    return min(readable, key=lambda x: x[0])[1].get(names["product"])


def complete_shipments(items, config, period_start, period_end):
    """[(item, arrival scan)] of the complete shipments whose final arrival is inside the period (definition above)."""
    names = field_names(config)
    pts = agreed_points(config)
    codes = product_codes(config)
    out = []
    for item in sorted(items):
        entries = items[item]
        if "product" in names and item_product(entries, names) not in codes:
            continue
        place_f, mode_f = names["place_ref"], names.get("mode_ref")
        arrivals = [(t, i) for i, (s, t) in enumerate(entries)
                    if t is not None and at_point(s.get(place_f), s.get(mode_f) if mode_f else None, pts["destination"])]
        if not arrivals:
            continue
        t_arr, i_arr = max(arrivals)
        if not (period_start <= t_arr.date() <= period_end):
            continue
        departs = [t for i, (s, t) in enumerate(entries)
                   if i != i_arr and t is not None and t < t_arr
                   and at_point(s.get(place_f), s.get(mode_f) if mode_f else None, pts["origin"])]
        if departs:
            out.append((item, entries[i_arr][0]))
    return out


def _row(scan, fields, extra):
    row = {}
    for f in fields:
        v = scan.get(f)
        if v == "":
            v = None
        if f in extra and isinstance(v, str) and re.match(r"^-?\d{1,15}$", v):
            v = int(v)
        row[f] = v
    return row


def build_delivery(scans, config, period_start, period_end, seed, fmt="jsonl", ts_fmt=None, noise=None,
                   pii_fields=None):
    """The delivery file of one period: {'bytes', 'sha256', 'size_bytes', 'format', 'control_totals', 'manifest'}."""
    if fmt not in ("jsonl", "csv"):
        raise ConnectorError("format must be jsonl or csv")
    check_timezones(config)
    fields = output_fields(config, pii_fields)
    names = field_names(config)
    if scans and any(f not in scans[0] for f in fields):
        missing = sorted(f for f in fields if f not in scans[0])
        raise ConnectorError("ONEMS expects fields the carrier table does not have: %s" % ", ".join(missing))
    scan_cfg = (config.get("fields") or {}).get("scan_at") or {}
    ts_fmt = ts_fmt or pg_format_to_strptime(scan_cfg.get("format"))
    noise = dict(DEFAULT_NOISE, **(noise or {}))
    extra = set(config.get("extra_fields") or [])
    pts = agreed_points(config)
    all_scans = bool(config.get("include_all_scans"))
    place_f, mode_f = names["place_ref"], names.get("mode_ref")

    items = index_items(scans, names, ts_fmt)
    shipments = complete_shipments(items, config, period_start, period_end)
    rng = random.Random("noise|%s|%s|%s" % (seed, period_start, period_end))
    rows, noisy, totals = [], 0, {}
    for item, arrival in shipments:
        with_noise = rng.random() < noise["unagreed_scans_share"]
        noisy += 1 if with_noise else 0
        for s, _t in items[item]:
            agreed = at_point(s.get(place_f), s.get(mode_f) if mode_f else None, pts["all"])
            if all_scans or agreed or (with_noise and _norm(s.get(place_f))):
                rows.append(_row(s, fields, extra))
        # Control total: shipments delivered per arrival point (the scan's own place and event code) and product
        # (the shipment's product, as in the definition; not the code written on the arrival scan).
        key = (arrival.get(place_f), arrival.get(mode_f) if mode_f else None, item_product(items[item], names))
        totals[key] = totals.get(key, 0) + 1
    # Broken records at seeded positions (never inside the header).
    invalid = int(noise["invalid_rows"])
    positions = sorted(rng.randrange(0, len(rows) + 1) for _ in range(invalid)) if invalid > 0 else []

    buf = io.StringIO(newline="")
    if fmt == "csv":
        w = csv.writer(buf, lineterminator="\r\n")
        w.writerow(fields)
    k = 0
    for i in range(len(rows) + 1):
        while k < len(positions) and positions[k] == i:
            if fmt == "csv":
                buf.write("BROKEN-RECORD-%d\r\n" % (k + 1))          # wrong number of columns
            else:
                buf.write('{"broken record %d"\n' % (k + 1))          # not a JSON object
            k += 1
        if i < len(rows):
            if fmt == "csv":
                w.writerow(["" if rows[i][f] is None else rows[i][f] for f in fields])
            else:
                buf.write(json.dumps(rows[i], ensure_ascii=False, separators=(",", ":")) + "\n")
    data = buf.getvalue().encode("utf-8")
    control_totals = [{"place_ref": p, "mode_ref": m, "product": pr, "delivered": n}
                      for (p, m, pr), n in sorted(totals.items(), key=lambda x: tuple(str(v) for v in x[0]))]
    for t in control_totals:
        if t["mode_ref"] is None:
            del t["mode_ref"]
        if t["product"] is None:
            del t["product"]
    sha = hashlib.sha256(data).hexdigest()
    manifest = {"period_start": period_start.isoformat(), "period_end": period_end.isoformat(), "format": fmt,
                "fields": fields, "shipments": len(shipments), "rows": len(rows), "invalid_rows": len(positions),
                "records": len(rows) + len(positions), "shipments_with_unagreed_scans": noisy,
                "include_all_scans": all_scans, "size_bytes": len(data), "sha256": sha}
    return {"bytes": data, "sha256": sha, "size_bytes": len(data), "format": fmt,
            "control_totals": control_totals, "manifest": manifest}


def open_request(delivery, period_start, period_end):
    """Body of POST /deliveries for a built delivery."""
    return {"period_start": period_start.isoformat(), "period_end": period_end.isoformat(),
            "format": delivery["format"], "size_bytes": delivery["size_bytes"], "sha256": delivery["sha256"],
            "control_totals": delivery["control_totals"]}
