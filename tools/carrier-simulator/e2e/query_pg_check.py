"""Runs the SQL of GET /query (PostgreSQL) on a simulated carrier table and compares it with the simulator.

    python -I tools/carrier-simulator/e2e/query_pg_check.py

Only touches the local portable Postgres (127.0.0.1:5433, database postgres, a throwaway schema that is dropped at
the end); never the remote database. The SQL comes from supabase/functions/carrier-link-ingest/query_cli.ts (deno).

Checks, for include_all_scans false and true, that the query gives exactly what connector.build_delivery gives
(without noise): (a) the same shipments, (b) the same file rows, (c) the same control totals.
Exit 0 = OK, 1 = differences, 2 = Postgres or deno not available.
"""
import collections
import csv
import datetime as dt
import io
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(SIM))
sys.path.insert(0, SIM)

from carrier_sim import connector, dataset  # noqa: E402

PSQL = os.environ.get("PSQL", r"C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe")
PG = ["-h", "127.0.0.1", "-p", "5433", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"]
SCHEMA = "cl_query_check"
CLI = os.path.join(REPO, "supabase", "functions", "carrier-link-ingest", "query_cli.ts")
NO_NOISE = {"unagreed_scans_share": 0, "invalid_rows": 0}


def psql(sql, csv_out=False):
    args = [PSQL] + PG + (["--csv"] if csv_out else [])
    env = dict(os.environ, PGPASSWORD=os.environ.get("PGPASSWORD", "postgres"))
    r = subprocess.run(args, input=sql, capture_output=True, text=True, encoding="utf-8", env=env)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[-2000:])
    return r.stdout


def query_sql(config):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(config, f)
        path = f.name
    try:
        r = subprocess.run(["deno", "run", "--quiet", "--allow-read", CLI, path, "postgresql"],
                           capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(path)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout


def split_statements(sql):
    """The two statements of the query (file, totals), comments kept."""
    head, rest = sql.split("-- Statement 1: the delivery file", 1)
    file_sql, totals_sql = rest.split("-- Statement 2: control totals", 1)
    return file_sql, totals_sql


def load_table(scans, ts_fmt):
    """carrier_scans with the carrier's columns; event_ts as timestamp (unparseable -> NULL, as a real DB column)."""
    cols = dataset.FIELDS
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    for s in scans:
        row = []
        for c in cols:
            v = s.get(c)
            if c == "event_ts":
                t = connector.parse_ts(v, ts_fmt)
                v = t.isoformat(sep=" ") if t else None
            row.append("" if v is None or v == "" else v)
        w.writerow(row)
    ddl = ", ".join('"%s" %s' % (c, "timestamp" if c == "event_ts" else "text") for c in cols)
    psql("DROP SCHEMA IF EXISTS %s CASCADE; CREATE SCHEMA %s; CREATE TABLE %s.carrier_scans (%s);\n"
         "COPY %s.carrier_scans FROM STDIN WITH (FORMAT csv);\n%s\\.\n"
         % (SCHEMA, SCHEMA, SCHEMA, ddl, SCHEMA, buf.getvalue()))


def norm_row(r, fields, ts_fmt):
    out = []
    for f in fields:
        v = r.get(f)
        if f == "event_ts" and v not in (None, ""):
            t = connector.parse_ts(v, ts_fmt) if "/" in str(v) else dt.datetime.fromisoformat(str(v))
            v = t.isoformat(sep=" ") if t else None
        out.append(None if v in (None, "") else str(v))
    return tuple(out)


def run_case(scans, config, p0, p1, ts_fmt, label):
    fields = connector.output_fields(config)
    expected = connector.build_delivery(scans, config, p0, p1, "check", fmt="jsonl", noise=NO_NOISE)
    exp_rows = [json.loads(l) for l in expected["bytes"].decode("utf-8").splitlines() if l.strip()]
    exp_rows_n = collections.Counter(norm_row(r, fields, ts_fmt) for r in exp_rows)
    exp_items = {r[config["fields"]["item_id"]["field"]] for r in exp_rows}
    exp_totals = collections.Counter({(t["place_ref"], t.get("mode_ref"), t.get("product")): t["delivered"]
                                      for t in expected["control_totals"]})

    file_sql, totals_sql = split_statements(query_sql(config))
    pre = "SET search_path = %s;\n" % SCHEMA
    got_rows = list(csv.DictReader(io.StringIO(psql(pre + file_sql, csv_out=True))))
    got_rows_n = collections.Counter(norm_row(r, fields, ts_fmt) for r in got_rows)
    got_items = {r[config["fields"]["item_id"]["field"]] for r in got_rows}
    got_totals = collections.Counter()
    for t in csv.DictReader(io.StringIO(psql(pre + totals_sql, csv_out=True))):
        got_totals[(t["place_ref"] or None, t["mode_ref"] or None, t["product"] or None)] = int(t["delivered"])

    problems = []
    if got_items != exp_items:
        problems.append("shipments: missing %s, extra %s" % (sorted(exp_items - got_items)[:5], sorted(got_items - exp_items)[:5]))
    if got_rows_n != exp_rows_n:
        problems.append("rows: missing %s, extra %s" % (list((exp_rows_n - got_rows_n).items())[:3],
                                                       list((got_rows_n - exp_rows_n).items())[:3]))
    if got_totals != exp_totals:
        problems.append("totals: expected %s, got %s" % (dict(exp_totals), dict(got_totals)))
    if not exp_items:
        problems.append("empty period: the check proves nothing")
    if problems:
        print("%s: DIFFERENT\n  %s" % (label, "\n  ".join(problems)))
        return False
    print("%s: OK n_items=%d n_rows=%d" % (label, len(exp_items), len(exp_rows)))
    return True


def main():
    try:
        psql("SELECT 1;")
    except Exception as e:  # noqa: BLE001
        print("Postgres 127.0.0.1:5433 not available (%s). Start it: pg_ctl -D C:/Users/fernandezi/pgportable/data "
              "-o \"-p 5433\" start" % str(e)[:200])
        return 2
    with open(os.path.join(SIM, "network.json"), encoding="utf-8") as f:
        network = json.load(f)
    with open(os.path.join(SIM, "examples", "01-get-config.json"), encoding="utf-8") as f:
        config = json.load(f)["body"]
    np_ = config["next_period"]
    p0, p1 = dt.date.fromisoformat(np_["period_start"]), dt.date.fromisoformat(np_["period_end"])
    scans, _items = dataset.generate(network, "query-check", p0 - dt.timedelta(days=10), p1,
                                     dt.datetime.combine(p1 + dt.timedelta(days=2), dt.time()))
    ts_fmt = network["ts_format"]
    try:
        load_table(scans, ts_fmt)
        ok = run_case(scans, config, p0, p1, ts_fmt, "agreed points only")
        ok = run_case(scans, dict(config, include_all_scans=True), p0, p1, ts_fmt, "include_all_scans") and ok
    finally:
        try:
            psql("DROP SCHEMA IF EXISTS %s CASCADE;" % SCHEMA)
        except Exception:  # noqa: BLE001
            pass
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
