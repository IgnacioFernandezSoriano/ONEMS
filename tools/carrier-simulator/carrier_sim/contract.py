"""Python port of supabase/functions/carrier-link-ingest/lib.ts (Carrier Link v4 connector API).

Routes, limits, the request validation of POST /deliveries and the CL_* error table (HTTP status + fixed message).
Keep in sync with lib.ts: tests/test_simulator.py parses lib.ts and fails if the error table or a limit differs, and
the local mode answers exactly what the Edge Function would answer.
"""
import datetime as dt
import re

MAX_BODY_BYTES = 5 * 1024 * 1024
ABSOLUTE_MAX_FILE_BYTES = 524_288_000
MAX_CONTROL_TOTALS = 10_000
RATE_LIMIT_PER_MINUTE = 30
BUCKET = "cl-deliveries"
UPLOAD_URL_TTL_SECONDS = 7200
FORMATS = ("jsonl", "csv")
CONTENT_TYPE_BY_FORMAT = {"jsonl": "application/x-ndjson", "csv": "text/csv"}

NEW_ROUTES = "GET /config, POST /deliveries, POST /deliveries/{id}/complete, GET /deliveries/{id}"
ROUTE_METHOD = {"config": "GET", "deliveries": "POST", "complete": "POST", "delivery": "GET", "gone": None}

# Every CL_ code with its HTTP status and fixed English message (lib.ts ERRORS). 500 = never an HTTP answer of the
# API (internal, or only seen in delivery.error of a failed delivery).
_INTERNAL = "Internal server error."
_TMP_STORAGE = "Temporary storage error (retried automatically)."
_TMP_PROC = "Temporary processing error (retried automatically)."
ERRORS = {
    "CL_UNAUTHORIZED": (401, "Invalid or inactive API key."),
    "CL_RATE_LIMITED": (429, "Rate limit exceeded: at most %d requests per minute." % RATE_LIMIT_PER_MINUTE),
    "CL_NOT_FOUND": (404, "Unknown route. Routes: %s." % NEW_ROUTES),
    "CL_METHOD_NOT_ALLOWED": (405, "Method not allowed on this route."),
    "CL_ENDPOINT_GONE": (410, "Carrier Link v4 removed the demand and batch endpoints. Deliver every complete "
                              "shipment of the period as one file: %s." % NEW_ROUTES),
    "CL_BODY_TOO_LARGE": (413, "The request body is larger than %d bytes." % MAX_BODY_BYTES),
    "CL_INTERNAL": (500, _INTERNAL),
    "CL_BAD_REQUEST": (400, "Invalid request."),
    "CL_COMPRESSION_UNSUPPORTED": (400, "Compressed files are not supported: upload the plain JSON Lines or CSV file."),
    "CL_BAD_PERIOD": (400, "period_start is after period_end."),
    "CL_BAD_CONTROL_TOTALS": (400, "control_totals must be an array (max 10000) of {place_ref, mode_ref?, product?, "
                                   "delivered} with delivered an integer >= 0."),
    "CL_FILE_TOO_LARGE": (413, "The file is larger than this connector's max_file_bytes (see GET /config limits)."),
    "CL_FEED_NOT_FOUND": (404, "The connector of this API key no longer exists."),
    "CL_FEED_PAUSED": (403, "The connector is paused."),
    "CL_FORBIDDEN": (403, "Forbidden."),
    "CL_PERIOD_NOT_CLOSED": (422, "The period is not closed yet: its last day must be before today (account time "
                                  "zone)."),
    "CL_PERIOD_NOT_IN_CALENDAR": (422, "The period does not match the delivery calendar. Use next_period from GET "
                                       "/config."),
    "CL_NO_ACTIVE_PLAN": (422, "No active plan of this connector covers the period."),
    "CL_PERIOD_ALREADY_DELIVERED": (409, "The period (or part of it) was already delivered."),
    "CL_SUPERSEDED": (409, "This delivery was replaced by a newer delivery of the same period with another file."),
    "CL_DELIVERY_NOT_FOUND": (404, "Delivery not found."),
    "CL_FILE_NOT_UPLOADED": (409, "The file was not uploaded yet: upload it to the upload URL, then complete."),
    "CL_UPLOAD_EXPIRED": (410, "The delivery expired before the file was completed (7 days). Open the delivery "
                               "again."),
    "CL_SHA256_MISMATCH": (422, "The uploaded file does not match the declared sha256 / size."),
    "CL_TOO_MANY_ROWS": (413, "The file has more rows than the connector allows (see GET /config limits.max_rows)."),
    "CL_RECORD_TOO_LONG": (413, "A record (line) of the file is too long."),
    "CL_MAPPING_INCOMPLETE": (422, "The field mapping of the connector is incomplete (ask the regulator)."),
    "CL_BAD_ENCODING": (422, "The file is not valid UTF-8."),
    "CL_BAD_CSV_HEADER": (422, "The CSV header row is missing, blank or has duplicate column names."),
    "CL_FILE_MISSING": (422, "The uploaded file could not be found when processing started."),
    "CL_RETRIES_EXHAUSTED": (422, "Processing failed 3 times; the delivery was rejected. Deliver the period again."),
    "CL_STORAGE_ERROR": (500, _TMP_STORAGE),
    "CL_STORAGE_SHORT_READ": (500, _TMP_STORAGE),
    "CL_FILE_SIZE_UNKNOWN": (500, _TMP_STORAGE),
    "CL_WORKER_ERROR": (500, _TMP_PROC),
    "CL_WORKER_LOST": (500, _TMP_PROC),
    "CL_BAD_SHA_STATE": (500, _TMP_PROC),
    "CL_PROCESSING_ERROR": (500, _TMP_PROC),
    "CL_CURSOR_MISMATCH": (500, _INTERNAL),
    "CL_DELIVERY_NOT_LOADING": (500, _INTERNAL),
    "CL_LEASE_LOST": (500, _INTERNAL),
    "CL_STAGING_LOST": (500, _INTERNAL),
    "CL_STAGING_NOT_EMPTY": (500, _INTERNAL),
    "CL_STOPPED": (500, _INTERNAL),
    "CL_DELIVERY_BAD_TRANSITION": (500, _INTERNAL),
    "CL_DELIVERY_IMMUTABLE": (500, _INTERNAL),
    "CL_QUOTA_NOT_FOUND": (500, _INTERNAL),
}

_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
_COMPRESSION_RE = re.compile(r"(gz|gzip|zip|bz2|bzip2|xz|zst|zstd|br|brotli|deflate|compress|lz4|7z)$", re.I)
_OPEN_KEYS = {"period_start", "period_end", "sha256", "control_totals", "format", "size_bytes", "compression"}


def is_uuid(s):
    return isinstance(s, str) and bool(_UUID_RE.match(s))


def parse_route(path):
    """Route of a path after the base URL (e.g. '/deliveries/<id>/complete'); None = unknown route."""
    from urllib.parse import unquote
    seg = [s for s in path.split("?")[0].rstrip("/").split("/") if s != ""]
    if len(seg) == 1 and seg[0] == "config":
        return {"kind": "config"}
    if len(seg) == 1 and seg[0] == "deliveries":
        return {"kind": "deliveries"}
    if len(seg) == 2 and seg[0] == "deliveries":
        return {"kind": "delivery", "id": unquote(seg[1])}
    if len(seg) == 3 and seg[0] == "deliveries" and seg[2] == "complete":
        return {"kind": "complete", "id": unquote(seg[1])}
    if len(seg) >= 1 and seg[0] in ("demands", "batches"):
        return {"kind": "gone"}
    return None


def _is_iso_date(v):
    if not isinstance(v, str) or not re.match(r"^\d{4}-\d{2}-\d{2}$", v):
        return False
    try:
        dt.date.fromisoformat(v)
        return True
    except ValueError:
        return False


def validate_open_request(body):
    """(True, normalized body) or (False, code, detail): same checks and order as lib.ts validateOpenRequest."""
    def bad(detail, code="CL_BAD_REQUEST"):
        return False, code, detail

    if not isinstance(body, dict):
        return bad("the body must be a JSON object")
    for k in body:
        if k not in _OPEN_KEYS:
            return bad("unknown field: %s" % k[:50])
    comp = body.get("compression")
    if comp is not None and comp != "none":
        return bad('compressed files are not supported: upload the plain file (compression "none")',
                   "CL_COMPRESSION_UNSUPPORTED")
    fmt = body.get("format")
    fmt = "jsonl" if fmt is None else fmt
    if not isinstance(fmt, str):
        return bad('format must be "jsonl" or "csv"')
    if _COMPRESSION_RE.search(fmt.strip()):
        return bad('compressed files are not supported: format must be "jsonl" or "csv"', "CL_COMPRESSION_UNSUPPORTED")
    if fmt not in FORMATS:
        return bad('format must be "jsonl" or "csv"')
    if not _is_iso_date(body.get("period_start")):
        return bad("period_start must be a date YYYY-MM-DD")
    if not _is_iso_date(body.get("period_end")):
        return bad("period_end must be a date YYYY-MM-DD")
    sha = body.get("sha256")
    if not isinstance(sha, str) or not re.match(r"^[0-9a-fA-F]{64}$", sha):
        return bad("sha256 must be the 64-character hexadecimal SHA-256 of the file")
    ct = body.get("control_totals")
    if not isinstance(ct, list):
        return bad("control_totals must be an array (it may be empty)", "CL_BAD_CONTROL_TOTALS")
    if len(ct) > MAX_CONTROL_TOTALS:
        return bad("control_totals holds at most %d entries" % MAX_CONTROL_TOTALS, "CL_BAD_CONTROL_TOTALS")
    size = body.get("size_bytes")
    if isinstance(size, float) and size.is_integer():   # JSON 3.0 is the integer 3 in JavaScript
        size = int(size)
    if isinstance(size, bool) or not isinstance(size, int) or size < 1 or size > 2 ** 53 - 1:
        return bad("size_bytes must be the file size in bytes (a positive integer)")
    if size > ABSOLUTE_MAX_FILE_BYTES:
        return bad("the file is larger than %d bytes" % ABSOLUTE_MAX_FILE_BYTES, "CL_FILE_TOO_LARGE")
    return True, {"period_start": body["period_start"], "period_end": body["period_end"], "sha256": sha.lower(),
                  "control_totals": ct, "format": fmt, "size_bytes": size}


def cl_code(message):
    m = re.match(r"^(CL_[A-Z0-9_]*[A-Z0-9])", message or "")
    return m.group(1) if m else None


def status_of(code):
    e = ERRORS.get(code) if code else None
    return e[0] if e else 500


def sql_error_to_http(sqlstate, message):
    """(status, code) for a Postgres error, or None = unexpected (answered 500 CL_INTERNAL). lib.ts sqlErrorToHttp."""
    cl = cl_code(message)
    if cl and cl in ERRORS:
        status = ERRORS[cl][0]
        return (status, cl) if status < 500 else None
    if cl:
        return None
    if sqlstate == "22023":
        return 400, "CL_BAD_REQUEST"
    if sqlstate == "42501":
        return 403, "CL_FORBIDDEN"
    return None


def error_body(code, detail=None, extra=None):
    body = {"success": False, "error": code, "message": ERRORS.get(code, ERRORS["CL_INTERNAL"])[1]}
    if detail:
        body["detail"] = detail
    if extra:
        body.update(extra)
    return body


def public_delivery(summary):
    """Delivery summary as the connector sees it (without the internal storage path)."""
    if not isinstance(summary, dict):
        return None
    return {k: v for k, v in summary.items() if k != "file_path"}
