"""Markdown summary of a cl_volume run (no dependencies; run with `python -I`).

Usage: python -I summarize.py OUT_DIR   (reads quotas.jsonl, emit.jsonl, posts.jsonl, growth.json, run*/p*/demand.json)

POST estimate: the Edge Function makes N + 5 sequential round trips per POST (api_key_resolve, cl_feeds read,
cl_ingest_batch, cl_batches read, N x cl_sample_stratum, cl_finish_batch); the estimate adds RTT ms per round trip to
the measured database time. "worst" also multiplies the database time by 3 (a small shared Supabase instance is
slower than this laptop). Budget: 120 s per POST.
"""
import glob
import json
import os
import statistics
import sys

BUDGET_MS = 120000
WEEKS, PLANS = 52, 5


def lines(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(x) for x in f if x.strip()]


def main(argv):
    out = argv[1]
    quotas = lines(os.path.join(out, "quotas.jsonl"))
    emits = lines(os.path.join(out, "emit.jsonl"))
    posts = lines(os.path.join(out, "posts.jsonl"))
    with open(os.path.join(out, "growth.json"), encoding="utf-8") as f:
        growth = json.load(f)

    print("## Quotas (cl_plan_set_quotas + cl_plan_activate, one call per plan)\n")
    print("| plan | quota cells > 0 | JSON bytes | set_quotas ms | activate ms |")
    print("|---|---|---|---|---|")
    for q in quotas:
        print("| %d | %d | %d | %.1f | %.1f |" % (q["plan"], q["cells"], q["json_bytes"], q["set_quotas_ms"], q["activate_ms"]))

    print("\n## Emission (cl_emit_due_demands, 5 active plans, one connector)\n")
    print("| run | p_now | demands | emit ms | strata/demand | required/demand | candidates/demand | payload bytes/demand (jsonb text) | payload bytes/demand (compact JSON) | GET /demands body (5 demands, compact) |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for e in emits:
        pd = e["per_demand"] or []
        compact = []
        for path in sorted(glob.glob(os.path.join(out, "run%d" % e["run"], "p*", "demand.json"))):
            with open(path, encoding="utf-8") as f:
                compact.append(len(json.dumps(json.load(f), separators=(",", ":")).encode("utf-8")))
        rng = lambda k: "%d-%d" % (min(x[k] for x in pd), max(x[k] for x in pd)) if pd else "-"
        body = sum(compact) + len('{"demands":[]}') + max(len(compact) - 1, 0)
        print("| %d | %s | %d | %.1f | %s | %s | %s | %s | %s | %d |" % (
            e["run"], e["p_now"], e["demands"], e["emit_ms"], rng("strata"), rng("samples_required"),
            rng("candidates_requested"), rng("payload_bytes"),
            ("%d-%d" % (min(compact), max(compact))) if compact else "-", body))

    print("\n## POST /batches (ingest + sampling per stratum + finish, each call its own transaction)\n")
    print("| run | plan | post | rows | body bytes | strata | ingest ms | sampling total ms | max stratum ms | p50 stratum ms | finish ms | DB total s | est. POST s (50 ms RTT) | est. POST s (100 ms RTT) | worst s (DB x3 + 100 ms RTT) | % of 120 s (worst) | selected/required | demand |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    worst_all = []
    for p in posts:
        db = p["ingest_ms"] + p["sampling_ms"] + p["finish_ms"]
        trips = p["strata"] + 5
        e50, e100 = db + trips * 50, db + trips * 100
        worst = 3 * db + trips * 100
        worst_all.append(worst)
        print("| %d | %d | %d | %d | %d | %d | %.0f | %.0f | %.1f | %.1f | %.0f | %.1f | %.1f | %.1f | %.1f | %.0f %% | %s/%s | %s |" % (
            p["run"], p["plan"], p["post"], p["rows"], p["bytes"], p["strata"], p["ingest_ms"], p["sampling_ms"],
            p["sampling_max_ms"], p["sampling_p50_ms"], p["finish_ms"], db / 1000, e50 / 1000, e100 / 1000,
            worst / 1000, 100 * worst / BUDGET_MS, p["samples_selected"], p["samples_required"], p["demand_status"]))

    def stat(k):
        v = [p[k] for p in posts]
        return "%.0f / %.0f / %.0f" % (min(v), statistics.median(v), max(v))
    print("\nmin / median / max over %d POSTs: ingest ms %s; sampling total ms %s; max stratum ms %s; finish ms %s; "
          "worst-case POST %.1f s (%.0f %% of 120 s)" % (
              len(posts), stat("ingest_ms"), stat("sampling_ms"), stat("sampling_max_ms"), stat("finish_ms"),
              max(worst_all) / 1000, 100 * max(worst_all) / BUDGET_MS))

    demand_weeks = growth["demands"] or 1
    print("\n## Database growth (%d demand-weeks processed = %d runs x %d plans)\n" % (
        demand_weeks, len(emits), PLANS))
    print("| table | rows now | bytes now (table+indexes+toast) | rows per plan-week | rows per year (5 products x 52 weeks) | MB per year (approx.) |")
    print("|---|---|---|---|---|---|")
    for name, t in growth["tables"].items():
        per = t["rows"] / demand_weeks
        bpr = t["total_bytes"] / t["rows"] if t["rows"] else 0
        # Quotas are written once per plan (all 52 weeks at activation), not per weekly demand.
        year = t["rows"] if name == "cl_plan_quotas" else per * WEEKS * PLANS
        print("| %s | %d | %d | %.0f | %.0f | %.0f |" % (name, t["rows"], t["total_bytes"], per, year, year * bpr / 1e6))
    print("\ncl_plan_quotas is written once per plan (52 weeks at activation): its 'per year' is the current count.")
    print("\nalerts by type: %s" % json.dumps(growth.get("alerts_by_type")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
