"""Checks the connector runs of e2e/run.sh against the dataset's ground truth and the local DB (onems_t).

  python -I check.py tampered   RUNS_DIR
  python -I check.py deliveries RUNS_DIR DATASET_DIR
  python -I check.py expect     RESPONSE_FILE HTTP_STATUS CL_CODE|-

deliveries, per period (calendar order): open 201 + upload URL, PUT 200, complete 202, final status processed;
  rows_total = records of the file (broken ones included), shipments_total = complete shipments the connector sent,
  rejected reasons only the ones the noise and the dataset anomalies explain, drawn = samples of that delivery = one_db
  rows, every drawn item is a real complete shipment of that file (never undelivered), staging empty, control totals
  stored exactly as declared, no personal field in any file. At the end: both weeks settled, the tampered period's
  delivery_rejected incident closed automatically, notices queued for the account and the carrier.
Exit 0 = PASS.
"""
import collections
import csv
import io
import json
import os
import subprocess
import sys

FEED = "c1517000-0000-4000-8000-0000000000f1"
PLAN = "c1517000-0000-4000-8000-0000000000a1"
FORBIDDEN_FIELDS = {"recipient_name", "recipient_phone"}
# Row reasons the file can produce: broken records (noise), scans at non-agreed places (noise), the duplicate
# acceptance scan with an unreadable date (bad_timestamp anomaly), the delivery scan with a corrupt product code
# (bad_service anomaly).
ROW_REASONS = {"bad_record", "unknown_reading_point", "bad_timestamp", "unknown_product"}
# Shipment reasons: only the bad_service shipments (a scan with a corrupt product code -> unknown_product). A shipment
# delivered by mistake in another registered city and then re-delivered keeps a valid route; clock_error shipments
# (arrival recorded before the departure) are not complete by the normative definition, so they are never sent.
SHIPMENT_REASONS = {"unknown_product"}
PSQL = [os.environ.get("PSQL", "C:/Users/fernandezi/pgportable/pgsql/bin/psql.exe"), "-h", "127.0.0.1", "-p", "5433",
        "-U", "postgres", "-d", "onems_t", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"]

fails = []


def ok(cond, msg):
    print("  %-4s %s" % ("OK" if cond else "FAIL", msg))
    if not cond:
        fails.append(msg)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sql(q):
    env = dict(os.environ, PGPASSWORD="postgres")
    return subprocess.run(PSQL + ["-c", q], capture_output=True, env=env, check=True).stdout.decode().strip()


def read_file_items(path, fmt, item_field="tracking_no"):
    """(records, items, fields seen) of a delivery file, parsed like the worker does."""
    with open(path, "rb") as f:
        text = f.read().decode("utf-8")
    records, items, fields = 0, set(), set()
    if fmt == "csv":
        rows = list(csv.reader(io.StringIO(text, newline="")))
        header = rows[0]
        fields.update(header)
        for r in rows[1:]:
            records += 1
            if len(r) == len(header):
                items.add(dict(zip(header, r))[item_field])
    else:
        for line in text.split("\n"):
            if not line.strip():
                continue
            records += 1
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if isinstance(o, dict):
                fields.update(o)
                items.add(o[item_field])
    return records, items, fields


def period_dirs(runs):
    return sorted(os.path.join(runs, d) for d in os.listdir(runs) if "_" in d and not d.endswith("-tampered"))


def check_tampered(runs):
    d = [os.path.join(runs, x) for x in os.listdir(runs) if x.endswith("-tampered")]
    ok(len(d) == 1, "one tampered run")
    d = d[0]
    ok(load(os.path.join(d, "03-open-response.json"))["http_status"] == 201, "tampered: open 201")
    ok(load(os.path.join(d, "04-upload-response.json"))["http_status"] == 200, "tampered: PUT 200")
    ok(load(os.path.join(d, "05-complete-response.json"))["http_status"] == 202, "tampered: complete 202 (received)")
    st = load(os.path.join(d, "06-status.json"))
    dl = st["body"]["delivery"]
    ok(st["http_status"] == 200 and dl["status"] == "rejected" and dl["error"] == "CL_SHA256_MISMATCH",
       "tampered: final status rejected CL_SHA256_MISMATCH")
    ok(dl["shipments_drawn"] in (None, 0), "tampered: nothing drawn")
    ok(sql("SELECT count(*) FROM public.cl_samples WHERE delivery_id = '%s'" % dl["delivery_id"]) == "0",
       "tampered: no samples")
    inc = sql("SELECT status || '|' || jsonb_array_length(periods) FROM public.cl_incidents"
              " WHERE feed_id = '%s' AND incident_type = 'delivery_rejected'" % FEED)
    ok(inc == "open|1", "incident delivery_rejected open with 1 period (%s)" % inc)
    kinds = sql("SELECT string_agg(recipient_kind, ',' ORDER BY recipient_kind) FROM public.cl_notifications n"
                " JOIN public.cl_incidents i ON i.id = n.incident_id WHERE i.feed_id = '%s'"
                " AND i.incident_type = 'delivery_rejected'" % FEED)
    ok(kinds == "account_manager,carrier", "notices queued for the account and the carrier (%s)" % kinds)
    ok("item_id" not in json.dumps(st["body"]), "the status answer reveals no item")


def check_deliveries(runs, dataset_dir):
    truth = {it["tracking_no"]: it for it in load(os.path.join(dataset_dir, "items.json"))["items"]}
    dirs = period_dirs(runs)
    ok([os.path.basename(x) for x in dirs] == ["2026-11-02_2026-11-04", "2026-11-05_2026-11-08",
                                               "2026-11-09_2026-11-11", "2026-11-12_2026-11-15"],
       "4 periods in calendar order (Mon+Thu): %s" % [os.path.basename(x) for x in dirs])
    seen_items = set()
    for d in dirs:
        name = os.path.basename(d)
        man = load(os.path.join(d, "manifest.json"))
        print("== %s (%s): %d shipments, %d records" % (name, man["format"], man["shipments"], man["records"]))
        op = load(os.path.join(d, "03-open-response.json"))
        ok(op["http_status"] == 201 and op["body"]["upload"]["method"] == "PUT"
           and op["body"]["upload"]["expires_in_seconds"] == 7200, "open 201 with a PUT upload URL (2 h)")
        ok("file_path" not in op["body"]["delivery"], "no internal storage path in the answer")
        ok(load(os.path.join(d, "04-upload-response.json"))["http_status"] == 200, "PUT 200")
        ok(load(os.path.join(d, "05-complete-response.json"))["http_status"] == 202, "complete 202")
        dl = load(os.path.join(d, "06-status.json"))["body"]["delivery"]
        did = dl["delivery_id"]
        ok(dl["status"] == "processed" and dl["phase"] == "done", "processed (%s/%s)" % (dl["status"], dl["phase"]))
        path = os.path.join(d, "delivery." + man["format"])
        records, items, fields = read_file_items(path, man["format"])
        ok(not (fields & FORBIDDEN_FIELDS), "no personal field in the file")
        ok(records == man["records"] == dl["rows_total"], "rows_total %s = records %s" % (dl["rows_total"], records))
        ok(len(items) == man["shipments"] == dl["shipments_total"],
           "shipments_total %s = shipments in the file %s" % (dl["shipments_total"], len(items)))
        ok(not (items & seen_items), "no shipment repeated from an earlier period")
        seen_items |= items
        rr = dl["rejected_reasons"] or {}
        ok(set((rr.get("rows") or {})) <= ROW_REASONS, "row reasons explained: %s" % rr.get("rows"))
        ok(set((rr.get("shipments") or {})) <= SHIPMENT_REASONS, "shipment reasons explained: %s" % rr.get("shipments"))
        ok((rr.get("rows") or {}).get("bad_record", 0) == man["invalid_rows"], "broken records = bad_record")
        undelivered = [i for i in items if truth[i]["delivered_in"] is None or truth[i]["anomaly"] == "undelivered"]
        ok(not undelivered, "no undelivered shipment in the file")
        ok(not [i for i in items if truth[i]["anomaly"] == "clock_error"], "no clock_error shipment (not complete)")
        kind = collections.Counter(truth[i]["anomaly"] for i in items)
        ok((rr.get("shipments") or {}).get("unknown_product", 0) == kind["bad_service"]
           == (rr.get("rows") or {}).get("unknown_product", 0),
           "unknown_product = bad_service shipments in the file (%d)" % kind["bad_service"])
        ok((rr.get("rows") or {}).get("bad_timestamp", 0) == kind["bad_timestamp"],
           "bad_timestamp rows = bad_timestamp shipments in the file (%d)" % kind["bad_timestamp"])
        drawn = sql("SELECT coalesce(string_agg(item_id, ',' ORDER BY item_id), '') FROM public.cl_samples"
                    " WHERE delivery_id = '%s'" % did)
        drawn = [x for x in drawn.split(",") if x]
        ok(len(drawn) == dl["shipments_drawn"], "samples = shipments_drawn (%d)" % len(drawn))
        ok(set(drawn) <= items, "every drawn item is a shipment of this file")
        ok(all(truth[i]["anomaly"] not in ("clock_error", "bad_service", "undelivered") for i in drawn),
           "no drawn item with an invalid record")
        n1 = sql("SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id"
                 " WHERE s.delivery_id = '%s'" % did)
        ok(int(n1) == len(drawn), "one_db rows = drawn (%s)" % n1)
        sel = sql("SELECT coalesce(sum(selected), 0) || '|' || coalesce(bool_and(selected <= quota_for_delivery"
                  " AND selected <= population), true) FROM public.cl_delivery_strata WHERE delivery_id = '%s'" % did)
        ok(sel == "%d|true" % len(drawn), "strata: selected = drawn, never above quota or population (%s)" % sel)
        ct = json.loads(sql("SELECT control_totals FROM public.cl_deliveries WHERE id = '%s'" % did))
        ok(ct == load(os.path.join(d, "02-open-request.json"))["control_totals"], "control totals stored as declared")
        ok(sum(t["delivered"] for t in ct) == man["shipments"], "control totals add up to the shipments sent")
        alerts = {a["type"] for a in dl.get("alerts") or []}
        ok(alerts <= {"unknown_reading_point", "unknown_product", "insufficient_candidates"},
           "carrier-visible alerts explained: %s" % sorted(alerts))
        ok("possible_misrouting" not in json.dumps(dl), "the drawn sample is not revealed")
    ok(sql("SELECT (SELECT count(*) FROM public.cl_delivery_rows) + (SELECT count(*) FROM public.cl_delivery_items)")
       == "0", "staging empty")
    q = sql("SELECT string_agg(DISTINCT status, ',' ORDER BY status) FROM public.cl_plan_quotas WHERE plan_id = '%s'"
            % PLAN)
    ok(set(q.split(",")) <= {"fulfilled", "carried", "unfilled"}, "both weeks settled (%s)" % q)
    tot = sql("SELECT sum(samples_obtained) || '/' || sum(samples_planned) FROM public.cl_plan_quotas"
              " WHERE plan_id = '%s'" % PLAN)
    print("  samples obtained / planned: %s" % tot)
    inc = sql("SELECT status || '|' || coalesce(closed_how, '-') FROM public.cl_incidents WHERE feed_id = '%s'"
              " AND incident_type = 'delivery_rejected'" % FEED)
    ok(inc == "resolved|auto", "delivery_rejected closed automatically once the period was processed (%s)" % inc)
    ok(sql("SELECT count(*) FROM public.cl_samples WHERE plan_id = '%s' AND delivery_id IS NULL" % PLAN) == "0",
       "every sample comes from a delivery")


def check_expect(path, status, code):
    r = load(path)
    ok(r["http_status"] == int(status), "%s: HTTP %s (got %s)" % (os.path.basename(path), status, r["http_status"]))
    if code != "-":
        ok((r["body"] or {}).get("error") == code, "%s: %s (got %s)" % (os.path.basename(path), code,
                                                                       (r["body"] or {}).get("error")))


def main(argv):
    mode = argv[0]
    if mode == "tampered":
        check_tampered(argv[1])
    elif mode == "deliveries":
        check_deliveries(argv[1], argv[2])
    elif mode == "expect":
        check_expect(argv[1], argv[2], argv[3])
    else:
        raise SystemExit("unknown mode %s" % mode)
    if fails:
        print("FAIL (%d)" % len(fails))
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
