"""Unit tests of the carrier simulator (Carrier Link v4). stdlib unittest, no database, no network beyond 127.0.0.1.

Run: python -I tools/carrier-simulator/tests/test_simulator.py
"""
import csv
import datetime as dt
import hashlib
import http.server
import io
import json
import os
import re
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from carrier_sim import connector, contract, dataset, transport  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(HERE))
LIB_TS = os.path.join(ROOT, "supabase", "functions", "carrier-link-ingest", "lib.ts")
FMT = "%d/%m/%Y %H:%M:%S"
D = dt.date


def load_network():
    with open(os.path.join(HERE, "network.json"), encoding="utf-8") as f:
        return json.load(f)


def scan(tn, ts, site, code, service="STD", **extra):
    row = {"tracking_no": tn, "event_ts": ts, "site_code": site, "event_code": code, "service": service,
           "weight_g": "100", "recipient_name": "", "recipient_phone": ""}
    row.update(extra)
    return row


def config(**over):
    """A GET /config answer of the simulated connector (shape of cl_connector_config)."""
    c = {
        "schema_version": "4.0", "date_timezone": "Africa/Nairobi",
        "connector": {"id": "c1517000-0000-4000-8000-0000000000f1", "name": "SimPost", "status": "active",
                      "carrier": "SIMPOST"},
        "calendar": {"delivery_days": [1, 4], "delivery_hour": 3, "timezone": "Africa/Nairobi",
                     "deliveries_per_week": 2, "frequency": "several_per_week"},
        "fields": {"item_id": {"field": "tracking_no"}, "product": {"field": "service"},
                   "scan_at": {"field": "event_ts", "format": "DD/MM/YYYY HH24:MI:SS", "timezone": "Africa/Nairobi"},
                   "place_ref": {"field": "site_code"}, "mode_ref": {"field": "event_code"}},
        "mapping_complete": True, "extra_fields": ["weight_g"], "include_all_scans": False,
        "products": [{"code": "SIM-STD", "carrier_codes": ["STD"]}],
        "points": [{"place_ref": p, "mode_ref": m, "role": r} for p, m, r in (
            ("NPT-PO", "ACC", "origin"), ("NPT-PO", "DLV", "destination"), ("SVL-PO", "ACC", "origin"),
            ("SVL-PO", "DLV", "destination"), ("EMR-PO", None, "both"))],
        "next_period": {"period_start": "2026-11-09", "period_end": "2026-11-11", "deliverable": True},
    }
    c.update(over)
    return c


ROWS = [
    # I1: complete NPT -> SVL, arrival 11/11 inside 09..11; the MPC scan is not at an agreed point
    scan("I1", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I1", "10/11/2026 15:00:00", "NPT-MPC", "DSP"),
    scan("I1", "11/11/2026 10:00:00", "SVL-PO", "DLV", recipient_name="X. Person", recipient_phone="+999"),
    # I2: arrival after the period
    scan("I2", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I2", "12/11/2026 10:00:00", "SVL-PO", "DLV"),
    # I3: never delivered
    scan("I3", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I3", "11/11/2026 09:00:00", "SVL-MPC", "ARR"),
    # I4: other product (not in the plan)
    scan("I4", "10/11/2026 09:00:00", "NPT-PO", "ACC", "EXP"), scan("I4", "11/11/2026 10:00:00", "SVL-PO", "DLV", "EXP"),
    # I5: misrouted: delivered by mistake at EMR (any-mode point) on 09/11, then at SVL on 12/11 -> NOT in 09..11
    scan("I5", "06/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I5", "09/11/2026 10:00:00", "EMR-PO", "DLV"),
    scan("I5", "12/11/2026 10:00:00", "SVL-PO", "DLV"),
    # I6: departure in an earlier period (05/11), arrival in the period
    scan("I6", "05/11/2026 09:00:00", "SVL-PO", "ACC"), scan("I6", "09/11/2026 08:00:00", "NPT-PO", "DLV"),
    # I7: clock error: arrival recorded before the departure -> not complete
    scan("I7", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I7", "09/11/2026 11:00:00", "SVL-PO", "DLV"),
    # I8: delivered at a place that is not an agreed point
    scan("I8", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I8", "11/11/2026 10:00:00", "RDF-PO", "DLV"),
    # I9: arrival only with an unreadable timestamp -> not complete; I10: a duplicate unreadable ACC -> complete
    scan("I9", "10/11/2026 09:00:00", "NPT-PO", "ACC"), scan("I9", "31/11/2026 25:61:00", "SVL-PO", "DLV"),
    scan("I10", "31/11/2026 25:61:00", "EMR-PO", "ACC"), scan("I10", "10/11/2026 09:00:00", "EMR-PO", "ACC"),
    scan("I10", "11/11/2026 12:00:00", "NPT-PO", "DLV"),
    # I11: a single scan at a 'both' point (EMR): no departure before it -> not complete
    scan("I11", "10/11/2026 09:00:00", "EMR-PO", "DLV"),
]
NO_NOISE = {"unagreed_scans_share": 0, "invalid_rows": 0}


def build(rows=ROWS, cfg=None, fmt="jsonl", noise=NO_NOISE, seed="s", p0=D(2026, 11, 9), p1=D(2026, 11, 11), **kw):
    return connector.build_delivery(rows, cfg or config(), p0, p1, seed, fmt=fmt, noise=noise, **kw)


def jsonl_records(data):
    return [json.loads(x) for x in data.decode("utf-8").split("\n") if x]


# ---------------------------------------------------------------------------------------------------------- contract
class ContractSyncTest(unittest.TestCase):
    """contract.py is a port of lib.ts: same limits and the same error table (status and message)."""

    @classmethod
    def setUpClass(cls):
        with open(LIB_TS, encoding="utf-8") as f:
            cls.src = f.read()

    def const(self, name):
        m = re.search(r"export const %s = ([0-9_ *]+)\n" % name, self.src)
        value = 1
        for factor in m.group(1).replace("_", "").split("*"):    # e.g. "5 * 1024 * 1024"
            value *= int(factor)
        return value

    def test_limits(self):
        self.assertEqual(self.const("MAX_BODY_BYTES"), contract.MAX_BODY_BYTES)
        self.assertEqual(self.const("ABSOLUTE_MAX_FILE_BYTES"), contract.ABSOLUTE_MAX_FILE_BYTES)
        self.assertEqual(self.const("MAX_CONTROL_TOTALS"), contract.MAX_CONTROL_TOTALS)
        self.assertEqual(self.const("RATE_LIMIT_PER_MINUTE"), contract.RATE_LIMIT_PER_MINUTE)
        self.assertEqual(self.const("UPLOAD_URL_TTL_SECONDS"), contract.UPLOAD_URL_TTL_SECONDS)

    def test_error_table(self):
        ts = dict((c, int(s)) for c, s in re.findall(r"^\s+(CL_[A-Z0-9_]+): \{\s*status: (\d+)", self.src, re.M))
        self.assertEqual(ts, {c: v[0] for c, v in contract.ERRORS.items()})
        # plain literal messages are identical (template-string ones are built from the same constants)
        for code, msg in re.findall(r"^\s+(CL_[A-Z0-9_]+): \{\s*status: \d+, message: '([^']*)'", self.src, re.M):
            self.assertEqual(contract.ERRORS[code][1], msg, code)
        for code, msg in re.findall(r"^\s+(CL_[A-Z0-9_]+): \{\s*status: \d+, message: \"([^\"]*)\"", self.src, re.M):
            self.assertEqual(contract.ERRORS[code][1], msg, code)
        self.assertIn("Carrier Link v4 removed", contract.ERRORS["CL_ENDPOINT_GONE"][1])

    def test_routes(self):
        r = contract.parse_route
        self.assertEqual(r("/config"), {"kind": "config"})
        self.assertEqual(r("/deliveries/"), {"kind": "deliveries"})
        self.assertEqual(r("/deliveries/x"), {"kind": "delivery", "id": "x"})
        self.assertEqual(r("/deliveries/x/complete"), {"kind": "complete", "id": "x"})
        self.assertEqual(r("/demands"), {"kind": "gone"})
        self.assertEqual(r("/batches/1/x"), {"kind": "gone"})
        self.assertIsNone(r("/other"))
        self.assertIsNone(r("/deliveries/x/y"))

    def test_validate_open_request(self):
        good = {"period_start": "2026-11-09", "period_end": "2026-11-11", "sha256": "A" * 64, "size_bytes": 10,
                "control_totals": []}
        ok = contract.validate_open_request(good)
        self.assertTrue(ok[0])
        self.assertEqual(ok[1]["format"], "jsonl")
        self.assertEqual(ok[1]["sha256"], "a" * 64)
        self.assertTrue(contract.validate_open_request(dict(good, size_bytes=10.0))[0])
        cases = [
            ("x", "CL_BAD_REQUEST"), (dict(good, name="x"), "CL_BAD_REQUEST"),
            (dict(good, compression="gzip"), "CL_COMPRESSION_UNSUPPORTED"),
            (dict(good, format="jsonl.gz"), "CL_COMPRESSION_UNSUPPORTED"),
            (dict(good, format="zip"), "CL_COMPRESSION_UNSUPPORTED"), (dict(good, format="xml"), "CL_BAD_REQUEST"),
            (dict(good, period_start="2026-02-30"), "CL_BAD_REQUEST"), (dict(good, period_end=None), "CL_BAD_REQUEST"),
            (dict(good, sha256="z" * 64), "CL_BAD_REQUEST"), (dict(good, control_totals={}), "CL_BAD_CONTROL_TOTALS"),
            (dict(good, control_totals=[{}] * 10001), "CL_BAD_CONTROL_TOTALS"),
            (dict(good, size_bytes=0), "CL_BAD_REQUEST"), (dict(good, size_bytes=True), "CL_BAD_REQUEST"),
            (dict(good, size_bytes="10"), "CL_BAD_REQUEST"),
            (dict(good, size_bytes=524_288_001), "CL_FILE_TOO_LARGE"),
        ]
        for body, code in cases:
            self.assertEqual(contract.validate_open_request(body)[1], code, body if body == "x" else list(body))
        self.assertTrue(contract.validate_open_request(dict(good, compression="none", format="csv"))[0])

    def test_sql_error_mapping(self):
        f = contract.sql_error_to_http
        self.assertEqual(f("22023", "CL_PERIOD_NOT_IN_CALENDAR: x"), (422, "CL_PERIOD_NOT_IN_CALENDAR"))
        self.assertEqual(f("P0001", "CL_PERIOD_ALREADY_DELIVERED: x"), (409, "CL_PERIOD_ALREADY_DELIVERED"))
        self.assertEqual(f("22023", "CL_FILE_TOO_LARGE: x"), (413, "CL_FILE_TOO_LARGE"))
        self.assertEqual(f("22023", "something"), (400, "CL_BAD_REQUEST"))
        self.assertEqual(f("42501", "Forbidden"), (403, "CL_FORBIDDEN"))
        self.assertIsNone(f("22023", "CL_UNKNOWN_CODE: x"))          # unknown CL code: unexpected
        self.assertIsNone(f("22023", "CL_LEASE_LOST"))               # internal code: unexpected
        self.assertIsNone(f("XX000", "boom"))
        self.assertEqual(contract.cl_code("CL_PROCESSING_ERROR 57014"), "CL_PROCESSING_ERROR")

    def test_public_delivery_and_error_body(self):
        self.assertEqual(contract.public_delivery({"a": 1, "file_path": "x"}), {"a": 1})
        b = contract.error_body("CL_DELIVERY_NOT_FOUND")
        self.assertEqual(b, {"success": False, "error": "CL_DELIVERY_NOT_FOUND", "message": "Delivery not found."})


# ----------------------------------------------------------------------------------------------------------- dataset
class DatasetTest(unittest.TestCase):
    def setUp(self):
        self.net = load_network()
        self.as_of = dt.datetime(2026, 11, 19, 6, 0)

    def gen(self, seed="t"):
        return dataset.generate(self.net, seed, D(2026, 11, 2), D(2026, 11, 8), self.as_of)

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
        for k in self.net["anomalies"]:
            self.assertIn(k, {i["anomaly"] for i in items})
        for it in items:
            codes = [r["event_code"] for r in by[it["tracking_no"]]]
            if it["anomaly"] == "undelivered":
                self.assertNotIn("DLV", codes)
            if it["anomaly"] == "misrouted_corrected":
                self.assertEqual(codes.count("DLV"), 2)

    def test_no_future_scans(self):
        scans, _ = dataset.generate(self.net, "t", D(2026, 11, 17), D(2026, 11, 18), self.as_of)
        for s in scans:
            t = connector.parse_ts(s["event_ts"], FMT)
            self.assertTrue(t is None or t <= self.as_of)


# --------------------------------------------------------------------------------------------------------- connector
class CompleteShipmentTest(unittest.TestCase):
    """The normative definition of a complete shipment of the period (spec v4)."""

    def shipments(self, cfg=None, p0=D(2026, 11, 9), p1=D(2026, 11, 11)):
        items = connector.index_items(ROWS, connector.field_names(cfg or config()), FMT)
        return [i for i, _ in connector.complete_shipments(items, cfg or config(), p0, p1)]

    def test_definition(self):
        # I1 complete; I6 departure in an earlier period; I10 duplicate unreadable ACC is harmless.
        self.assertEqual(self.shipments(), ["I1", "I10", "I6"])

    def test_latest_arrival_decides_the_period(self):
        self.assertIn("I5", self.shipments(p0=D(2026, 11, 12), p1=D(2026, 11, 15)))
        self.assertIn("I2", self.shipments(p0=D(2026, 11, 12), p1=D(2026, 11, 15)))

    def test_products_from_the_config(self):
        cfg = config(products=[{"code": "SIM-EXP", "carrier_codes": ["EXP"]}])
        self.assertEqual(self.shipments(cfg), ["I4"])

    def test_any_mode_point(self):
        cfg = config(points=[{"place_ref": "NPT-PO", "mode_ref": None, "role": "origin"},
                             {"place_ref": "SVL-PO", "mode_ref": None, "role": "destination"}])
        self.assertEqual(self.shipments(cfg), ["I1"])

    def test_without_product_field_every_product_counts(self):
        cfg = config()
        del cfg["fields"]["product"]
        self.assertEqual(self.shipments(cfg), ["I1", "I10", "I4", "I6"])


class BuildDeliveryTest(unittest.TestCase):
    def test_rows_only_agreed_points_and_fields(self):
        d = build()
        recs = jsonl_records(d["bytes"])
        self.assertEqual({r["tracking_no"] for r in recs}, {"I1", "I6", "I10"})
        self.assertNotIn("NPT-MPC", {r["site_code"] for r in recs})                 # not an agreed point
        self.assertEqual(len([r for r in recs if r["tracking_no"] == "I10"]), 3)   # unreadable ACC is sent too
        for r in recs:
            self.assertEqual(list(r), ["tracking_no", "service", "event_ts", "site_code", "event_code", "weight_g"])
            self.assertIsInstance(r["weight_g"], int)
        self.assertNotIn(b"Person", d["bytes"])
        self.assertNotIn(b"recipient", d["bytes"])

    def test_include_all_scans(self):
        recs = jsonl_records(build(cfg=config(include_all_scans=True))["bytes"])
        self.assertIn("NPT-MPC", {r["site_code"] for r in recs})
        self.assertNotIn("recipient_name", recs[0])

    def test_sha256_size_and_request(self):
        d = build()
        self.assertEqual(d["sha256"], hashlib.sha256(d["bytes"]).hexdigest())
        self.assertEqual(d["size_bytes"], len(d["bytes"]))
        req = connector.open_request(d, D(2026, 11, 9), D(2026, 11, 11))
        self.assertTrue(contract.validate_open_request(req)[0])
        self.assertEqual(req["format"], "jsonl")
        self.assertEqual(d["manifest"]["shipments"], 3)

    def test_control_totals(self):
        rows = ROWS + [scan("I12", "10/11/2026 09:00:00", "NPT-PO", "ACC"),
                       scan("I12", "11/11/2026 09:00:00", "SVL-PO", "DLV", "XX9")]   # corrupt code on the arrival
        d = build(rows)
        self.assertEqual(d["control_totals"], [
            {"place_ref": "NPT-PO", "mode_ref": "DLV", "product": "STD", "delivered": 2},
            {"place_ref": "SVL-PO", "mode_ref": "DLV", "product": "STD", "delivered": 2}])

    def test_csv(self):
        d = build(fmt="csv")
        text = d["bytes"].decode("utf-8")
        self.assertTrue(text.startswith("tracking_no,service,event_ts,site_code,event_code,weight_g\r\n"))
        rows = list(csv.reader(io.StringIO(text, newline="")))
        self.assertEqual(len(rows) - 1, d["manifest"]["rows"])
        self.assertEqual(len(jsonl_records(build()["bytes"])), d["manifest"]["rows"])

    def test_noise_is_seeded(self):
        noise = {"unagreed_scans_share": 1.0, "invalid_rows": 3}
        a, b = build(noise=noise), build(noise=noise)
        self.assertEqual(a["bytes"], b["bytes"])
        lines = a["bytes"].decode().split("\n")[:-1]
        broken = [x for x in lines if x.startswith('{"broken')]
        self.assertEqual(len(broken), 3)
        self.assertEqual(a["manifest"]["records"], len(lines))
        self.assertIn("NPT-MPC", a["bytes"].decode())                     # scans at non-agreed places
        self.assertNotEqual(build(noise=noise, seed="other")["bytes"], a["bytes"])
        c = build(fmt="csv", noise=noise)
        self.assertEqual(c["bytes"].decode().count("BROKEN-RECORD-"), 3)

    def test_personal_data_refused(self):
        with self.assertRaises(connector.ConnectorError):
            build(cfg=config(extra_fields=["weight_g", "recipient_phone"]))
        with self.assertRaises(connector.ConnectorError):
            build(pii_fields=["weight_g"])

    def test_incomplete_mapping_refused(self):
        cfg = config(mapping_complete=False)
        with self.assertRaises(connector.ConnectorError):
            build(cfg=cfg)

    def test_field_missing_in_carrier_table(self):
        with self.assertRaises(connector.ConnectorError):
            build(cfg=config(extra_fields=["volume_cm3"]))

    def test_time_zone_limit(self):
        cfg = config()
        cfg["fields"]["scan_at"]["timezone"] = "UTC"
        with self.assertRaises(connector.ConnectorError):
            build(cfg=cfg)

    def test_empty_period(self):
        d = build(rows=[])
        self.assertEqual(d["bytes"], b"\n")                    # size_bytes >= 1: one blank line, no record
        self.assertEqual(d["size_bytes"], 1)
        self.assertEqual(d["control_totals"], [])
        self.assertTrue(contract.validate_open_request(connector.open_request(d, D(2026, 11, 9), D(2026, 11, 11)))[0])
        c = build(rows=[], fmt="csv")
        self.assertEqual(c["bytes"], b"tracking_no,service,event_ts,site_code,event_code,weight_g\r\n")

    def test_iso_offset_refused_loudly(self):
        cfg = config()
        cfg["fields"]["scan_at"]["format"] = None
        rows = [scan("I1", "2026-11-10T09:00:00", "NPT-PO", "ACC"), scan("I1", "2026-11-11T10:00:00", "SVL-PO", "DLV")]
        self.assertEqual(jsonl_records(build(rows, cfg)["bytes"])[0]["tracking_no"], "I1")
        rows.append(scan("I2", "2026-11-10T09:00:00+03:00", "NPT-PO", "ACC"))
        with self.assertRaises(connector.ConnectorError):
            build(rows, cfg)
        self.assertIsNone(connector.parse_ts("not a date", None))

    def test_pg_format(self):
        self.assertEqual(connector.pg_format_to_strptime("DD/MM/YYYY HH24:MI:SS"), FMT)
        self.assertEqual(connector.pg_format_to_strptime("YYYY-MM-DD HH24:MI"), "%Y-%m-%d %H:%M")
        self.assertIsNone(connector.pg_format_to_strptime(None))
        self.assertEqual(connector.parse_ts("2026-11-10T09:00:00", None), dt.datetime(2026, 11, 10, 9))


# --------------------------------------------------------------------------------------------------------- transport
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
        self._answer(200, {"schema_version": "4.0"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
        StubHandler.seen.append(("POST", self.path, self.headers.get("x-api-key"), body))
        self._answer(201, {"delivery": {"status": "pending_upload"}})

    def do_PUT(self):
        data = self.rfile.read(int(self.headers["Content-Length"]))
        StubHandler.seen.append(("PUT", self.path, self.headers.get("x-api-key"),
                                 (self.headers.get("Content-Type"), data)))
        self._answer(200, {"Key": "x"})


def serve(handler):
    srv = http.server.HTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


class DevTransportTest(unittest.TestCase):
    def test_http_contract_against_loopback_stub(self):
        StubHandler.seen = []
        srv = serve(StubHandler)
        try:
            base = "http://127.0.0.1:%d/functions/v1/carrier-link-ingest" % srv.server_port
            t = transport.DevTransport(base, "onems_k")
            self.assertEqual(t.request("GET", "/config"), (200, {"schema_version": "4.0"}))
            self.assertEqual(t.request("POST", "/deliveries", {"a": 1})[0], 201)
            with tempfile.TemporaryDirectory() as tmp:
                p = os.path.join(tmp, "f.jsonl")
                with open(p, "wb") as f:
                    f.write(b'{"x":1}\n')
                up = {"url": "http://127.0.0.1:%d/storage/v1/object/upload/sign/cl-deliveries/a.jsonl?token=t"
                             % srv.server_port, "method": "PUT", "headers": {"Content-Type": "application/x-ndjson"}}
                self.assertEqual(t.upload(up, p)[0], 200)
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual([(m, p, k) for m, p, k, _ in StubHandler.seen], [
            ("GET", "/functions/v1/carrier-link-ingest/config", "onems_k"),
            ("POST", "/functions/v1/carrier-link-ingest/deliveries", "onems_k"),
            ("PUT", "/storage/v1/object/upload/sign/cl-deliveries/a.jsonl?token=t", None)])   # no key on the PUT
        self.assertEqual(StubHandler.seen[2][3], ("application/x-ndjson", b'{"x":1}\n'))

    def test_redirect_not_followed(self):
        class Redirect(StubHandler):
            def do_GET(self):
                StubHandler.seen.append(("REDIRECT", self.path, self.headers.get("x-api-key"), None))
                self.send_response(302)
                self.send_header("Location", "http://127.0.0.1:%d/elsewhere" % target.server_port)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"{}")
        StubHandler.seen = []
        target, src = serve(StubHandler), serve(Redirect)
        try:
            t = transport.DevTransport("http://127.0.0.1:%d/fn/carrier-link-ingest" % src.server_port, "onems_k")
            self.assertEqual(t.request("GET", "/config")[0], 302)
        finally:
            for srv in (target, src):
                srv.shutdown()
                srv.server_close()
        self.assertEqual([x[0] for x in StubHandler.seen], ["REDIRECT"])   # the target never saw the key

    def with_confirm(self, value, fn):
        old = os.environ.pop("CONFIRM_REMOTE", None)
        if value is not None:
            os.environ["CONFIRM_REMOTE"] = value
        try:
            return fn()
        finally:
            os.environ.pop("CONFIRM_REMOTE", None)
            if old is not None:
                os.environ["CONFIRM_REMOTE"] = old

    def test_remote_needs_https(self):
        with self.assertRaises(transport.TransportError):
            self.with_confirm("abcdef", lambda: transport.DevTransport(
                "http://abcdef.supabase.co/functions/v1/carrier-link-ingest", "k"))

    def test_remote_needs_confirmation(self):
        url = "https://abcdef.supabase.co/functions/v1/carrier-link-ingest"
        for value in (None, "other"):
            with self.assertRaises(transport.TransportError):
                self.with_confirm(value, lambda: transport.DevTransport(url, "k"))
        self.with_confirm("abcdef", lambda: transport.DevTransport(url, "k"))    # no call made

    def test_upload_url_must_stay_on_the_project_host(self):
        t = self.with_confirm("abcdef", lambda: transport.DevTransport(
            "https://abcdef.supabase.co/functions/v1/carrier-link-ingest", "k"))
        for url in ("https://evil.example/x", "http://abcdef.supabase.co/storage/v1/object/upload/sign/x"):
            with self.assertRaises(transport.TransportError):
                t.upload({"url": url}, __file__)

    def test_local_refuses_remote_host(self):
        with self.assertRaises(transport.TransportError):
            transport.LocalTransport({"host": "db.example.com"}, "k", ".")

    def test_local_routes_answer_before_the_database(self):
        t = transport.LocalTransport({"psql": "no-such-psql"}, "k", ".")
        self.assertEqual(t.request("GET", "/demands")[0], 410)
        self.assertEqual(t.request("POST", "/batches")[1]["error"], "CL_ENDPOINT_GONE")
        self.assertEqual(t.request("GET", "/nothing")[0], 404)
        self.assertEqual(t.request("GET", "/deliveries")[0], 405)
        self.assertEqual(t.request("OPTIONS", "/config"), (204, None))
        with self.assertRaises(transport.TransportError):
            t.upload({"url": "https://x.supabase.co/storage/v1/object/upload/sign/x"}, __file__)


class RetryAndUploadTest(unittest.TestCase):
    def run_seq(self, answers, retry_after=None, max_retries=5):
        seq, waits = list(answers), []

        def call():
            x = seq.pop(0)
            if isinstance(x, Exception):
                raise x
            return x
        out = transport.with_retries(call, lambda: retry_after, max_retries=max_retries, sleep=waits.append,
                                     log=lambda *_: None)
        return out, waits, seq

    def test_429_waits_retry_after(self):
        out, waits, _ = self.run_seq([(429, {}), (200, {"ok": 1})], retry_after=17)
        self.assertEqual(out, (200, {"ok": 1}))
        self.assertEqual(waits, [17])

    def test_5xx_and_network_backoff_bounded(self):
        out, waits, left = self.run_seq([(500, {}), transport.NetworkError("x"), (503, {}), (201, {})])
        self.assertEqual(out[0], 201)
        self.assertEqual(waits, [30, 60, 120])
        out, waits, left = self.run_seq([(500, {})] * 10, max_retries=3)
        self.assertEqual(out[0], 500)
        self.assertEqual(len(waits), 3)
        self.assertEqual(len(left), 6)
        with self.assertRaises(transport.NetworkError):
            self.run_seq([transport.NetworkError("down")] * 3, max_retries=2)

    def test_client_errors_not_retried(self):
        out, waits, left = self.run_seq([(409, {"error": "CL_PERIOD_ALREADY_DELIVERED"}), (200, {})])
        self.assertEqual(out[0], 409)
        self.assertEqual(waits, [])

    def test_already_uploaded(self):
        self.assertTrue(transport.already_uploaded(409, {}))
        self.assertTrue(transport.already_uploaded(400, {"statusCode": "409", "error": "Duplicate"}))
        self.assertTrue(transport.already_uploaded(400, {"statusCode": 409}))
        self.assertFalse(transport.already_uploaded(400, {"statusCode": "400"}))
        self.assertFalse(transport.already_uploaded(200, {}))
        self.assertFalse(transport.already_uploaded(403, None))

    def test_loopback_upload_host_is_pinned(self):
        t = transport.DevTransport("http://127.0.0.1:9/functions/v1/carrier-link-ingest", "k")
        with self.assertRaises(transport.TransportError):
            t.upload({"url": "http://evil.example/x"}, __file__)

    def test_network_error_is_raised_as_such(self):
        t = transport.DevTransport("http://127.0.0.1:9/functions/v1/carrier-link-ingest", "k", timeout=2)
        with self.assertRaises(transport.NetworkError):
            t.request("GET", "/config")


if __name__ == "__main__":
    unittest.main(verbosity=1)
