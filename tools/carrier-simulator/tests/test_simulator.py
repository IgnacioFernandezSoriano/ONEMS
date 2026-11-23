"""Unit tests of the carrier simulator (stdlib unittest, no database, no network beyond 127.0.0.1).

Run: python -I tools/carrier-simulator/tests/test_simulator.py
"""
import datetime as dt
import http.server
import json
import os
import sys
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from carrier_sim import connector, contract, dataset, transport  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FMT = "%d/%m/%Y %H:%M:%S"


def load_network():
    with open(os.path.join(HERE, "network.json"), encoding="utf-8") as f:
        return json.load(f)


def scan(tn, ts, site, code, service="STD", **extra):
    row = {"tracking_no": tn, "event_ts": ts, "site_code": site, "event_code": code, "service": service,
           "weight_g": "100", "recipient_name": "", "recipient_phone": ""}
    row.update(extra)
    return row


def stratum(sid, start, end, p0="2026-11-09", p1="2026-11-15", cands=10, req=2):
    return {"stratum_id": sid, "period": {"start": p0, "end": p1, "iso_week": "2026-W46"},
            "start_points": [{"place_ref": p, "mode_ref": m} for p, m in start],
            "end_points": [{"place_ref": p, "mode_ref": m} for p, m in end],
            "samples_required": req, "candidates_requested": cands}


class ContractTest(unittest.TestCase):
    """Same answers as supabase/functions/carrier-link-ingest/lib.ts (see lib.test.ts)."""

    def test_sql_error_mapping(self):
        f = contract.sql_error_to_http
        self.assertEqual(f("22023", "CL_DEMAND_TESTING_DRY_RUN_ONLY: x"), (403, "CL_DEMAND_TESTING_DRY_RUN_ONLY"))
        self.assertEqual(f("22023", "CL_BAD_PAYLOAD: x"), (400, "CL_BAD_PAYLOAD"))
        self.assertEqual(f("22023", "plan not found"), (400, "CL_BAD_REQUEST"))
        self.assertEqual(f("42501", "Forbidden"), (403, "CL_FORBIDDEN"))
        self.assertIsNone(f(None, None))
        self.assertEqual(f("P0001", "CL_DEMAND_NOT_OPEN: demand is failed"), (409, "CL_DEMAND_NOT_OPEN"))
        self.assertEqual(f("22023", "CL_DEMAND_NOT_OPEN: demand is failed"), (409, "CL_DEMAND_NOT_OPEN"))
        self.assertIsNone(f("P0001", "something else"))
        self.assertIsNone(f("P0001", "CL_OTHER: x"))

    def test_envelope(self):
        good = {"demand_id": "d", "batch_id": "b", "strata": [
            {"stratum_id": "s", "population_size": 3, "selection_method": "m", "rows": []}]}
        self.assertIsNone(contract.validate_envelope(good))
        self.assertIn("demand_id", contract.validate_envelope(dict(good, demand_id=" ")))
        self.assertIn("strata", contract.validate_envelope(dict(good, strata=[])))
        for bad in (-1, 1.5, True, "3", float("inf")):
            b = json.loads(json.dumps(good))
            b["strata"][0]["population_size"] = bad
            self.assertIn("population_size", contract.validate_envelope(b), bad)
        b = json.loads(json.dumps(good))
        b["strata"][0]["population_size"] = 3.0
        self.assertIsNone(contract.validate_envelope(b))
        self.assertEqual(contract.count_rows({"strata": [{"rows": [1, 2]}, {"rows": [3]}, "x"]}), 3)


class DatasetTest(unittest.TestCase):
    def setUp(self):
        self.net = load_network()
        self.as_of = dt.datetime(2026, 11, 19, 6, 0)

    def gen(self, seed="t"):
        return dataset.generate(self.net, seed, dt.date(2026, 11, 2), dt.date(2026, 11, 8), self.as_of)

    def test_deterministic(self):
        self.assertEqual(self.gen("a"), self.gen("a"))
        self.assertNotEqual(self.gen("a")[0], self.gen("b")[0])

    def test_shapes(self):
        scans, items = self.gen()
        self.assertEqual(len(items), 7 * self.net["items_per_day"])
        self.assertEqual(len({i["tracking_no"] for i in items}), len(items))
        by = {}
        for s in scans:
            by.setdefault(s["tracking_no"], []).append(s)
            self.assertEqual(set(s), set(dataset.FIELDS))
            t = connector.parse_ts(s["event_ts"], FMT)
            if t is not None:
                self.assertLessEqual(t, self.as_of)
        kinds = {i["anomaly"] for i in items}
        for k in self.net["anomalies"]:
            self.assertIn(k, kinds)
        for it in items:
            rows = by[it["tracking_no"]]
            codes = [r["event_code"] for r in rows]
            a = it["anomaly"]
            if a == "undelivered":
                self.assertNotIn("DLV", codes)
            elif a == "clock_error":
                acc = connector.parse_ts(rows[0]["event_ts"], FMT)
                dlv = connector.parse_ts([r for r in rows if r["event_code"] == "DLV"][0]["event_ts"], FMT)
                self.assertLess(dlv, acc)
            elif a == "bad_service":
                self.assertEqual([r for r in rows if r["event_code"] == "DLV"][0]["service"], "XX9")
            elif a == "bad_timestamp":
                self.assertEqual(sum(1 for r in rows if connector.parse_ts(r["event_ts"], FMT) is None), 1)
            elif a == "missing_site":
                self.assertEqual([r for r in rows if r["event_code"] == "OFD"][0]["site_code"], "")
            elif a == "misrouted_corrected":
                self.assertEqual(codes.count("DLV"), 2)
            if "DLV" in codes and a != "clock_error":
                self.assertIn(rows[-1]["recipient_name"][:1], "ABCDEFGH")

    def test_no_future_scans(self):
        scans, _ = dataset.generate(self.net, "t", dt.date(2026, 11, 17), dt.date(2026, 11, 18), self.as_of)
        for s in scans:
            t = connector.parse_ts(s["event_ts"], FMT)
            self.assertTrue(t is None or t <= self.as_of)


class ConnectorTest(unittest.TestCase):
    def setUp(self):
        a = [("NPT-PO", "ACC")]
        b = [("SVL-PO", "DLV")]
        self.demand = {"demand_id": "d0000000-0000-4000-8000-000000000001", "products": ["STD"],
                       "include_all_scans": False,
                       "strata": [stratum("s-ab", a, b), stratum("s-ae", a, [("EMR-PO", "DLV")])]}
        rows = [
            # closed NPT -> SVL, delivered in period
            scan("I1", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I1", "10/11/2026 15:00:00", "NPT-MPC", "DSP"),
            scan("I1", "12/11/2026 10:00:00", "SVL-PO", "DLV", recipient_name="X"),
            # delivered after the period
            scan("I2", "14/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I2", "16/11/2026 10:00:00", "SVL-PO", "DLV"),
            # never delivered
            scan("I3", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I3", "11/11/2026 09:00:00", "SVL-MPC", "ARR"),
            # other product
            scan("I4", "10/11/2026 09:00:00", "NPT-PO", "ACC", "EXP"), scan("I4", "11/11/2026 10:00:00", "SVL-PO", "DLV", "EXP"),
            # misrouted: wrong DLV in EMR, then delivered in SVL -> in both strata
            scan("I5", "09/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I5", "10/11/2026 10:00:00", "EMR-PO", "DLV"),
            scan("I5", "12/11/2026 10:00:00", "SVL-PO", "DLV"),
            # only the unreadable timestamp at the end point: not closed for the connector
            scan("I6", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I6", "31/11/2026 25:61:00", "SVL-PO", "DLV"),
        ]
        self.items = connector.index_items(rows, FMT)

    def test_population_closed_in_period(self):
        s_ab, s_ae = self.demand["strata"]
        self.assertEqual(connector.population(self.items, s_ab, {"STD"}), ["I1", "I5"])
        self.assertEqual(connector.population(self.items, s_ae, {"STD"}), ["I5"])

    def test_any_mode_point(self):
        s = stratum("s", [("NPT-PO", None)], [("SVL-PO", None)])
        self.assertEqual(connector.population(self.items, s, {"STD"}), ["I1", "I5"])

    def test_rows_all_points_of_any_city_without_pii(self):
        strata, manifest = connector.build_strata(self.demand, self.items, "seed")
        ab = strata[0]
        self.assertEqual(ab["population_size"], 2)
        self.assertEqual(ab["selection_method"], "uniform_random_within_stratum")
        sites = [(r["tracking_no"], r["site_code"], r["event_code"]) for r in ab["rows"]]
        self.assertIn(("I5", "EMR-PO", "DLV"), sites)          # end point of the other stratum (other city)
        self.assertNotIn(("I1", "NPT-MPC", "DSP"), sites)       # intermediate scan: not a point
        for r in ab["rows"]:
            self.assertEqual(set(r), set(connector.DEFAULT_OUTPUT_FIELDS))
        self.assertEqual(manifest[0]["candidates"], ["I1", "I5"])

    def test_include_all_scans(self):
        d = dict(self.demand, include_all_scans=True)
        strata, _ = connector.build_strata(d, self.items, "seed")
        self.assertIn(("I1", "NPT-MPC", "DSP"),
                      [(r["tracking_no"], r["site_code"], r["event_code"]) for r in strata[0]["rows"]])

    def test_draw_uniform_seeded(self):
        pop = ["X%03d" % i for i in range(100)]
        a = connector.draw(pop, 10, "s", "d", "st")
        self.assertEqual(a, connector.draw(pop, 10, "s", "d", "st"))
        self.assertNotEqual(a, connector.draw(pop, 10, "s2", "d", "st"))
        self.assertEqual(len(a), 10)
        self.assertEqual(connector.draw(pop[:3], 10, "s", "d", "st"), pop[:3])
        hits = {}
        for k in range(2000):
            for x in connector.draw(pop, 10, "s", "d", "st%d" % k):
                hits[x] = hits.get(x, 0) + 1
        self.assertEqual(len(hits), 100)
        self.assertLess(max(hits.values()), 2 * min(hits.values()) + 40)   # every item ~200 times

    def test_pack_batches(self):
        strata = [{"stratum_id": "s%d" % i, "population_size": 9, "selection_method": "m", "rows": [{"a": 1}] * n}
                  for i, n in enumerate([40, 50, 30, 100, 1])]
        bs = connector.pack_batches("d0000000-x", strata, "seed", max_rows=100)
        self.assertEqual([[s["stratum_id"] for s in b["strata"]] for b in bs], [["s0", "s1"], ["s2"], ["s3"], ["s4"]])
        self.assertEqual(len({b["batch_id"] for b in bs}), 4)
        self.assertEqual(bs[0]["batch_id"], connector.pack_batches("d0000000-x", strata, "seed", max_rows=100)[0]["batch_id"])
        self.assertNotEqual(bs[0]["batch_id"], connector.pack_batches("d0000000-x", strata, "other", max_rows=100)[0]["batch_id"])
        for b in bs:
            self.assertIsNone(contract.validate_envelope(b))
        with self.assertRaises(connector.ConnectorError):
            connector.pack_batches("d", strata, "seed", max_rows=99)
        self.assertEqual(len(connector.pack_batches("d", strata, "seed", max_rows=10 ** 6)), 1)  # capped at 5000


class StubHandler(http.server.BaseHTTPRequestHandler):
    seen = []

    def log_message(self, *a):
        pass

    def _answer(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        StubHandler.seen.append(("GET", self.path, self.headers.get("x-api-key"), None))
        self._answer(200, {"demands": []})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        StubHandler.seen.append(("POST", self.path, self.headers.get("x-api-key"), body))
        self._answer(403, {"success": False, "error": "CL_FEED_TESTING_DRY_RUN_ONLY"})


class DevTransportTest(unittest.TestCase):
    def test_http_contract_against_loopback_stub(self):
        srv = http.server.HTTPServer(("127.0.0.1", 0), StubHandler)
        th = threading.Thread(target=srv.serve_forever, daemon=True)
        th.start()
        try:
            base = "http://127.0.0.1:%d/functions/v1/carrier-link-ingest" % srv.server_port
            t = transport.DevTransport(base, "onems_k")
            self.assertEqual(t.get_demands(), (200, {"demands": []}))
            self.assertEqual(t.post_batch({"batch_id": "b"}, True)[0], 403)
            self.assertEqual(t.post_batch({"batch_id": "b"}, False)[1]["error"], "CL_FEED_TESTING_DRY_RUN_ONLY")
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual([(m, p, k) for m, p, k, _ in StubHandler.seen], [
            ("GET", "/functions/v1/carrier-link-ingest/demands", "onems_k"),
            ("POST", "/functions/v1/carrier-link-ingest/batches?dry_run=true", "onems_k"),
            ("POST", "/functions/v1/carrier-link-ingest/batches", "onems_k")])

    def test_remote_needs_confirmation(self):
        old = os.environ.pop("CONFIRM_REMOTE", None)
        try:
            with self.assertRaises(transport.TransportError):
                transport.DevTransport("https://abcdef.supabase.co/functions/v1/carrier-link-ingest", "k")
            os.environ["CONFIRM_REMOTE"] = "other"
            with self.assertRaises(transport.TransportError):
                transport.DevTransport("https://abcdef.supabase.co/functions/v1/carrier-link-ingest", "k")
            os.environ["CONFIRM_REMOTE"] = "abcdef"
            transport.DevTransport("https://abcdef.supabase.co/functions/v1/carrier-link-ingest", "k")  # no call made
        finally:
            os.environ.pop("CONFIRM_REMOTE", None)
            if old is not None:
                os.environ["CONFIRM_REMOTE"] = old

    def test_local_refuses_remote_host(self):
        with self.assertRaises(transport.TransportError):
            transport.LocalTransport({"host": "db.example.com"}, "k", ".")


if __name__ == "__main__":
    unittest.main(verbosity=1)
