"""Checks one connector run against the dataset's ground truth (and, for a real run, the local DB).

  python -I check.py dry  RUN_DIR DATASET_DIR
  python -I check.py real RUN_DIR DATASET_DIR
  python -I check.py replay RUN_DIR REPLAY_RESPONSE
  python -I check.py expect RESPONSE_FILE HTTP_STATUS CL_CODE

Expected deliberate rejections, from items.json (the connector does not filter them, a real one would not either):
  clock_error   -> candidate 'start_after_end'
  bad_service   -> candidate 'unknown_product' + 1 row 'unknown_product' (the DLV scan with the corrupt code)
  bad_timestamp -> 1 row 'bad_timestamp' (duplicate ACC scan); the candidate stays valid
  'already_sampled' (D12) is accepted only for an item drawn in more than one stratum (misrouted then delivered).
Anything else (unknown_reading_point, missing_field, bad_value, no_start, no_end, end_out_of_period, ...) is a failure.
Exit 0 = PASS.
"""
import collections
import json
import os
import subprocess
import sys

FORBIDDEN_FIELDS = {"recipient_name", "recipient_phone"}
PLAN = "c1517000-0000-4000-8000-0000000000a1"
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


def check_run(run_dir, dataset_dir, dry):
    suffix = ".dry_run" if dry else ""
    man = load(os.path.join(run_dir, "manifest%s.json" % suffix))
    truth = {it["tracking_no"]: it for it in load(os.path.join(dataset_dir, "items.json"))["items"]}
    by_stratum = {s["stratum_id"]: s for s in man["strata"]}
    seen = collections.Counter(tn for s in man["strata"] for tn in s["candidates"])
    totals = collections.Counter()
    selected_total, fulfilled_expected, last_finish = 0, True, None

    print("== %s run: demand %s, %d strata, %d batches" % ("dry" if dry else "real", man["demand_id"],
                                                          len(man["strata"]), len(man["batches"])))
    ok(len(man["batches"]) > 1 or man["max_rows"] >= 5000, "several batches when the row limit is small")
    for b in man["batches"]:
        batch = load(os.path.join(run_dir, b["file"]))
        resp = load(os.path.join(run_dir, b["response"]))
        body = resp["body"]
        ing = body.get("ingest") or {}
        rows = [r for s in batch["strata"] for r in s["rows"]]
        ok(resp["http_status"] == 200, "%s HTTP 200 (got %s)" % (b["batch_id"], resp["http_status"]))
        ok(len(rows) <= man["max_rows"], "%s %d rows <= %d" % (b["batch_id"], len(rows), man["max_rows"]))
        ok(not any(FORBIDDEN_FIELDS & set(r) for r in rows), "%s carries no personal data" % b["batch_id"])
        ok(ing.get("status") == "validated", "%s ingest validated" % b["batch_id"])
        ok(bool(ing.get("dry_run")) == dry and ((ing.get("batch") is None) == dry), "%s dry_run flag" % b["batch_id"])
        for st in ing.get("strata") or []:
            m = by_stratum[st["stratum_id"]]
            cands = m["candidates"]
            kinds = collections.Counter(truth[tn]["anomaly"] for tn in cands)
            multi = sum(1 for tn in cands if seen[tn] > 1)
            exp_rej = {k: v for k, v in (("start_after_end", kinds["clock_error"]),
                                         ("unknown_product", kinds["bad_service"])) if v}
            exp_rows = {k: v for k, v in (("bad_timestamp", kinds["bad_timestamp"]),
                                          ("unknown_product", kinds["bad_service"])) if v}
            got_rej = dict(st["rejected"])
            used = got_rej.pop("already_sampled", 0)
            tag = "%s %s" % (m["iso_week"], st["stratum_id"][:8])
            ok(st["population_size"] == m["population_size"] and st["candidates"] == len(cands)
               and st["rows"] == m["rows"], "%s population %d, candidates %d, rows %d echoed"
               % (tag, m["population_size"], len(cands), m["rows"]))
            ok(got_rej == exp_rej, "%s rejected candidates %s == expected %s" % (tag, got_rej, exp_rej))
            ok(used <= multi, "%s already_sampled %d <= items drawn in 2 strata %d" % (tag, used, multi))
            ok(st["rows_rejected"] == exp_rows, "%s rejected rows %s == expected %s" % (tag, st["rows_rejected"], exp_rows))
            ok(st["candidates_valid"] == len(cands) - sum(st["rejected"].values()), "%s candidates_valid %d"
               % (tag, st["candidates_valid"]))
            totals.update(kinds)
            if not dry:
                fulfilled_expected &= st["candidates_valid"] >= m["samples_required"]
        if not dry:
            samp = body.get("sampling") or []
            ok(len(samp) == len(batch["strata"]), "%s sampled %d strata" % (b["batch_id"], len(samp)))
            selected_total += sum(x.get("samples_selected", 0) for x in samp)
            ok((body.get("finish") or {}).get("status") == "sampled", "%s finish sampled" % b["batch_id"])
            last_finish = body.get("finish")
    print("  deliberate cases drawn: %s" % dict(sorted((k or "normal", v) for k, v in totals.items())))
    # "All readings at start/end points of ANY city": some rows are at a point of another stratum (misrouted items).
    demand = load(os.path.join(run_dir, "demand.json"))
    own = {s["stratum_id"]: {(p["place_ref"], p["mode_ref"]) for p in s["start_points"] + s["end_points"]}
           for s in demand["strata"]}
    foreign = sum(1 for b in man["batches"] for s in load(os.path.join(run_dir, b["file"]))["strata"]
                  for r in s["rows"] if (r["site_code"], r["event_code"]) not in own[s["stratum_id"]])
    ok(foreign >= 1, "rows at points of other cities are sent too (%d)" % foreign)
    for k in ("clock_error", "bad_service", "bad_timestamp"):
        ok(totals[k] >= 1, "the run exercises %s" % k)
    if not dry:
        ok(last_finish and last_finish.get("demand_status") == ("fulfilled" if fulfilled_expected else "partial"),
           "demand ends %s" % ("fulfilled" if fulfilled_expected else "partial"))
        n_samples = int(sql("SELECT count(*) FROM public.cl_samples WHERE plan_id = '%s' AND status = 'active'" % PLAN))
        n_onedb = int(sql("SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id"
                          " WHERE s.plan_id = '%s' AND o.source = 'carrier'" % PLAN))
        ok(n_samples == selected_total, "cl_samples %d == samples selected %d" % (n_samples, selected_total))
        ok(n_onedb == n_samples, "one_db carrier rows %d == samples" % n_onedb)
        mis = int(sql("SELECT count(*) FROM public.cl_samples WHERE plan_id = '%s' AND possible_misrouting" % PLAN))
        extra = int(sql("SELECT count(*) FROM public.cl_samples WHERE plan_id = '%s' AND extra ? 'weight_g'" % PLAN))
        ok(extra == n_samples, "allowed extra field weight_g kept on every sample")
        alerts = sql("SELECT COALESCE(string_agg(alert_type || ':' || n, ' '), '') FROM (SELECT alert_type, count(*) AS n"
                     " FROM public.cl_alerts WHERE plan_id = '%s' GROUP BY 1 ORDER BY 1) x" % PLAN)
        bad = {"unknown_reading_point", "population_incoherent", "selection_method", "emit_failed", "missing_standard",
               "missing_points", "reader_without_city"}
        ok(not any(a.split(":")[0] in bad for a in alerts.split()), "no unexpected alert (%s)" % (alerts or "none"))
        print("  possible_misrouting samples: %d" % mis)


def check_replay(run_dir, replay_file):
    man = load(os.path.join(run_dir, "manifest.json"))
    first = load(os.path.join(run_dir, man["batches"][0]["response"]))["body"]
    again = load(replay_file)
    print("== replay of %s" % man["batches"][0]["batch_id"])
    ok(again["http_status"] == 200, "HTTP 200")
    ok(again["body"].get("ingest") == first.get("ingest"), "same stored summary returned")
    ok("sampling" not in again["body"], "nothing sampled again")


def check_expect(response_file, status, code):
    r = load(response_file)
    print("== expected refusal %s %s" % (status, code))
    ok(r["http_status"] == int(status) and r["body"].get("error") == code,
       "got HTTP %s %s" % (r["http_status"], r["body"].get("error")))


def main(a):
    if len(a) == 5 and a[1] == "expect":
        check_expect(a[2], a[3], a[4])
    elif len(a) != 4 or a[1] not in ("dry", "real", "replay"):
        print(__doc__, file=sys.stderr)
        return 2
    elif a[1] == "replay":
        check_replay(a[2], a[3])
    else:
        check_run(a[2], a[3], a[1] == "dry")
    print("RESULT: %s" % ("PASS" if not fails else "FAIL (%d)" % len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
