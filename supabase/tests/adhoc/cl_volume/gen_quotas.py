"""Quota JSON for the Carrier Link volume test (no dependencies; run with `python -I`).

Python port of generateClQuotas (src/lib/carrierLink/quotaCalculator.ts) with the defaults the web uses:
working days Monday-Friday, no holidays, equal route weights, the week split of distributeSamplesAcrossWeeks with the
fixed rng () => 0.5, and the largest-remainder split per week whose leftovers rotate across routes (cursor).
Only quotas with samples > 0 are written (the shape cl_plan_set_quotas expects).

Routes = every ordered pair of the 30 fixture cities (870). Each plan starts its rotation cursor at a different route,
so the 5 plans do not ask for the same routes in the same week.

Usage: python -I gen_quotas.py OUT_DIR [--plans 5] [--total 15000]
Writes OUT_DIR/quotas_p<i>.json (i = 1..plans) and prints one summary line per plan.
"""
import datetime as dt
import json
import sys

START, END = dt.date(2025, 12, 29), dt.date(2026, 12, 27)
CITIES = ["c1f00000-0000-4000-8000-%012d" % (1000 + g) for g in range(1, 31)]


def plan_weeks(start, end):
    """buildPlanWeeks: working days (Mon-Fri) grouped by ISO week, in date order."""
    weeks, d = {}, start
    while d <= end:
        if d.isoweekday() <= 5:
            monday = d - dt.timedelta(days=d.isoweekday() - 1)
            weeks.setdefault(monday, []).append(d)
        d += dt.timedelta(days=1)
    return [weeks[k] for k in sorted(weeks)]


def across_weeks(total, weeks):
    """distributeSamplesAcrossWeeks(total, weeks, false, undefined, () => 0.5)."""
    weights = [len(w) for w in weeks]
    wsum = sum(weights)
    exact = [total * w / wsum for w in weights]
    counts = [int(e) for e in exact]
    fractions = [e - c for e, c in zip(exact, counts)]
    remaining = total - sum(counts)
    while remaining > 0:
        pool = fractions if any(f > 1e-9 for f in fractions) else weights
        r = 0.5 * sum(pool)
        idx = 0
        while idx < len(pool) - 1 and r >= pool[idx]:
            r -= pool[idx]
            idx += 1
        counts[idx] += 1
        fractions[idx] = 0
        remaining -= 1
    return counts


def split_by_weight(total, n, start):
    """splitByWeight with equal weights: largest remainders, ties to the route nearest after `start` (cyclic)."""
    if total <= 0:
        return [0] * n, 0
    exact = [total / n] * n
    counts = [int(e) for e in exact]
    remaining = total - sum(counts)
    extras = remaining
    order = sorted(range(n), key=lambda i: (-(exact[i] - counts[i]), (i - start + n) % n))
    k = 0
    while remaining > 0:
        counts[order[k]] += 1
        k = (k + 1) % n
        remaining -= 1
    return counts, extras


def quotas(total, cursor):
    routes = [(o, d) for o in sorted(CITIES) for d in sorted(CITIES) if o != d]
    weeks = plan_weeks(START, END)
    per_week = across_weeks(total, weeks)
    out = []
    for wi, days in enumerate(weeks):
        y, w, _ = days[0].isocalendar()
        counts, extras = split_by_weight(per_week[wi], len(routes), cursor)
        cursor = (cursor + extras) % len(routes)
        for (o, d), c in zip(routes, counts):
            if c > 0:
                out.append({"origin_city_id": o, "destination_city_id": d, "iso_year": y, "iso_week": w, "samples": c})
    return out, len(routes), len(weeks)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    out_dir, plans, total = argv[1], 5, 15000
    rest = argv[2:]
    while rest:
        if rest[0] == "--plans" and len(rest) > 1:
            plans, rest = int(rest[1]), rest[2:]
        elif rest[0] == "--total" and len(rest) > 1:
            total, rest = int(rest[1]), rest[2:]
        else:
            print("unknown argument: %s" % rest[0], file=sys.stderr)
            return 2
    for i in range(1, plans + 1):
        q, n_routes, n_weeks = quotas(total, ((i - 1) * 174) % 870)
        path = "%s/quotas_p%d.json" % (out_dir, i)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(q, f, separators=(",", ":"))
        s = sum(x["samples"] for x in q)
        assert s == total, (s, total)
        print("plan %d: %d routes x %d weeks, %d quota cells > 0, %d samples -> %s"
              % (i, n_routes, n_weeks, len(q), s, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
