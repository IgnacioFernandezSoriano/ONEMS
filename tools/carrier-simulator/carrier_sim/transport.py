"""How the connector talks to ONEMS. Both transports answer (http_status, json_body) like carrier-link-ingest v4.

DevTransport   real HTTP to the Edge Function with the connector key in x-api-key (GET /config, POST /deliveries,
               POST /deliveries/{id}/complete, GET /deliveries/{id}) and the PUT of the file to the signed upload URL
               (no key: the token is in the URL). Refuses a non-loopback host unless CONFIRM_REMOTE=<project ref> is
               set (owner confirmation) and the URL is https; never follows redirects (a 3xx is returned as is, so the
               key never travels to another address); the upload URL must be https on the same host as base_url.
LocalTransport the local Postgres only (127.0.0.1:5433, onems_t) through psql. A Python port of
               supabase/functions/carrier-link-ingest/handler.ts: the same route/method checks, the same body
               validation (contract.py) and the SAME SQL functions in the SAME order, each in its own transaction run
               as service_role: api_key_resolve -> cl_connector_config | cl_delivery_open | cl_delivery_complete |
               cl_delivery_status. Documented local stubs:
                 * the signed upload URL is local://cl-deliveries/<path>; the "PUT" writes the file under
                   <work_dir>/storage/<path> and registers the object in storage.objects (bucket cl-deliveries, with
                   metadata.size), as Supabase Storage does; a second PUT of the same path answers HTTP 400 with
                   statusCode "409" in the body (no upsert; some Storage versions answer HTTP 409 instead);
                 * processing (pg_cron + the carrier-link-worker Edge Function) is emulated by tick(): it runs
                   local.process_cmd (e2e/local_worker.ts: the REAL worker loader against the local DB, then
                   CALL cl_delivery_process_run) before each status poll;
                 * not emulated: the per-key rate limit and the api_usage_log row.
"""
import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

from . import contract

LOOPBACK = {"127.0.0.1", "localhost", "::1"}
LOCAL_UPLOAD_PREFIX = "local://%s/" % contract.BUCKET


class TransportError(Exception):
    pass


class NetworkError(TransportError):
    """No HTTP answer (connection refused, timeout, DNS...): the same call may be retried."""


def default_psql():
    """psql of the local tests: $PSQL, else the portable Postgres under the user's home, else psql on the PATH."""
    if os.environ.get("PSQL"):
        return os.environ["PSQL"]
    portable = os.path.join(os.path.expanduser("~"), "pgportable", "pgsql", "bin", "psql.exe")
    return portable if os.path.exists(portable) else (shutil.which("psql") or "psql")


def already_uploaded(status, body):
    """Supabase Storage answers a second PUT of the same object with 409, or with HTTP 400 and statusCode "409" in
    the body (depending on the Storage version): both mean the file is already there -> go on with complete."""
    if status == 409:
        return True
    return status == 400 and isinstance(body, dict) and str(body.get("statusCode")) == "409"


def with_retries(call, retry_after=lambda: None, max_retries=5, sleep=time.sleep, log=print, base=30, cap=480):
    """CL-REQ-019: repeats call() (-> (status, body)) on a network error, 429 or 5xx, at most max_retries times.
    429: waits Retry-After (60 s if absent); otherwise exponential backoff base*2^n capped at cap seconds."""
    attempt = 0
    while True:
        try:
            status, body = call()
            err = None
        except NetworkError as e:
            status, body, err = None, None, e
        retryable = err is not None or status == 429 or (status is not None and status >= 500)
        if not retryable or attempt >= max_retries:
            if err is not None:
                raise err
            return status, body
        wait = (retry_after() or 60) if status == 429 else min(base * 2 ** attempt, cap)
        log("  %s: retry %d/%d in %ss" % (err or "HTTP %s" % status, attempt + 1, max_retries, wait))
        sleep(wait)
        attempt += 1


def read_key(path):
    try:
        with open(path, encoding="utf-8") as f:
            key = f.read().strip()
    except OSError as e:
        raise TransportError("cannot read the key file %s (%s)" % (path, e.strerror))
    if not key:
        raise TransportError("empty key file: %s" % path)
    return key


def _json(raw):
    try:
        return json.loads(raw.decode("utf-8") or "null")
    except ValueError:
        return {"raw": raw.decode("utf-8", "replace")[:2000]}


# ---------------------------------------------------------------------------------------------------------------- DEV
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a redirect: the x-api-key header (and the upload token) must only reach the configured host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


class DevTransport:
    def __init__(self, base_url, key, timeout=120, upload_timeout=7200):
        self.last_retry_after = None
        self.base = base_url.rstrip("/")
        self.key = key
        self.timeout = timeout
        self.upload_timeout = upload_timeout
        url = urllib.parse.urlparse(self.base)
        self.host = url.hostname or ""
        self.remote = self.host not in LOOPBACK
        if self.remote and url.scheme != "https":
            raise TransportError("remote call refused: %s is not https (the key would travel in clear)" % self.base)
        if self.remote:
            ref = self.host.split(".")[0]
            if os.environ.get("CONFIRM_REMOTE") != ref:
                raise TransportError("remote call refused: set CONFIRM_REMOTE=%s once the owner has confirmed this run"
                                     % ref)

    def _open(self, req, timeout):
        self.last_retry_after = None
        try:
            with _OPENER.open(req, timeout=timeout) as r:
                return r.status, _json(r.read())
        except urllib.error.HTTPError as e:
            ra = e.headers.get("Retry-After") if e.headers else None
            self.last_retry_after = int(ra) if ra and ra.strip().isdigit() else None
            return e.code, _json(e.read())
        except (urllib.error.URLError, OSError) as e:      # no HTTP answer at all
            raise NetworkError("network error: %s" % getattr(e, "reason", e))

    def request(self, method, path, body=None, headers=None):
        data = None
        h = {"x-api-key": self.key, "Accept": "application/json"}
        if body is not None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
            h["Content-Type"] = "application/json"
        h.update(headers or {})
        return self._open(urllib.request.Request(self.base + path, data=data, method=method, headers=h), self.timeout)

    def upload(self, upload, path):
        """One PUT of the whole file to the signed URL (streamed from disk, never the API key)."""
        url = urllib.parse.urlparse(upload["url"])
        # The upload URL must stay on the project host (and be https when the host is remote).
        if url.hostname != self.host or (self.remote and url.scheme != "https"):
            raise TransportError("upload URL refused: it must be %s on %s"
                                 % ("https" if self.remote else "http(s)", self.host))
        size = os.path.getsize(path)
        headers = dict(upload.get("headers") or {})
        headers["Content-Length"] = str(size)
        with open(path, "rb") as f:
            req = urllib.request.Request(upload["url"], data=f, method=upload.get("method", "PUT"), headers=headers)
            return self._open(req, self.upload_timeout)

    def tick(self):
        """Processing runs on the server (pg_cron + worker): nothing to do."""


# -------------------------------------------------------------------------------------------------------------- LOCAL
class SqlError(Exception):
    def __init__(self, sqlstate, message):
        super().__init__("%s %s" % (sqlstate, message))
        self.sqlstate, self.message = sqlstate, message


class LocalTransport:
    def __init__(self, local, key, work_dir):
        self.last_retry_after = None
        self.psql = local.get("psql") or default_psql()
        self.host = local.get("host", "127.0.0.1")
        if self.host not in LOOPBACK:
            raise TransportError("local mode only talks to a loopback Postgres, not %s" % self.host)
        self.port = str(local.get("port", 5433))
        self.db = local.get("dbname", "onems_t")
        self.user = local.get("user", "postgres")
        self.password = local.get("password", "postgres")
        self.process_cmd = local.get("process_cmd")
        self.key = key
        self.storage_dir = os.path.join(work_dir, "storage")

    # -- psql
    def _sql(self, sql, variables, role="service_role"):
        """Runs sql (psql variables :'name') in its own transaction; returns the single value or raises SqlError."""
        cmd = [self.psql, "-h", self.host, "-p", self.port, "-U", self.user, "-d", self.db,
               "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
        for k, v in variables.items():
            cmd += ["-v", "%s=%s" % (k, v)]
        prefix = "BEGIN;\nSET LOCAL ROLE %s;\n" % role if role else "BEGIN;\n"
        env = dict(os.environ, PGPASSWORD=self.password, PGCLIENTENCODING="UTF8")
        p = subprocess.run(cmd, input=(prefix + sql + "\nCOMMIT;\n").encode("utf-8"), capture_output=True, env=env)
        err = p.stderr.decode("utf-8", "replace")
        if p.returncode != 0:
            m = re.search(r"ERROR:\s+([0-9A-Z]{5}):\s+(.*)", err)
            if m:
                raise SqlError(m.group(1), m.group(2).strip())
            raise TransportError("psql failed: %s" % err.strip()[:500])
        return p.stdout.decode("utf-8").strip()

    def _feed(self):
        out = self._sql("SELECT row_to_json(k) FROM public.api_key_resolve(:'key') k LIMIT 1;", {"key": self.key})
        k = json.loads(out) if out else None
        if not k or k.get("scope") != "carrier_feed" or not k.get("feed_id"):
            return None
        return k["feed_id"]

    def _call(self, sql, variables):
        try:
            out = self._sql(sql, variables)
        except SqlError as e:
            mapped = contract.sql_error_to_http(e.sqlstate, e.message)
            raise _HttpError(mapped[1] if mapped else "CL_INTERNAL")
        return json.loads(out) if out else None

    # -- the Edge Function (handler.ts handle)
    def request(self, method, path, body=None, headers=None):
        headers = {k.lower(): v for k, v in (headers or {}).items()}
        if method == "OPTIONS":
            return 204, None
        route = contract.parse_route(path)
        if route is None:
            return _fail("CL_NOT_FOUND")
        if route["kind"] == "gone":
            return _fail("CL_ENDPOINT_GONE")
        if method != contract.ROUTE_METHOD[route["kind"]]:
            return _fail("CL_METHOD_NOT_ALLOWED")
        try:
            try:
                feed = self._feed()
            except SqlError as e:              # api_key_resolve failed: same mapping as any other database error
                mapped = contract.sql_error_to_http(e.sqlstate, e.message)
                return _fail(mapped[1] if mapped else "CL_INTERNAL")
            if not feed:
                return _fail("CL_UNAUTHORIZED")
            if route["kind"] == "config":
                return 200, self._call("SELECT public.cl_connector_config(:'feed'::uuid);", {"feed": feed})
            if route["kind"] == "deliveries":
                return self._open(feed, body, headers)
            if not contract.is_uuid(route["id"]):
                return _fail("CL_DELIVERY_NOT_FOUND")
            if route["kind"] == "complete":
                d = self._call("SELECT public.cl_delivery_complete(:'feed'::uuid, :'id'::uuid);",
                               {"feed": feed, "id": route["id"]})
                if d and d.get("status") == "rejected":
                    cl = contract.cl_code(d.get("error") if isinstance(d.get("error"), str) else None)
                    code = cl if cl and contract.status_of(cl) < 500 else "CL_INTERNAL"
                    return _fail(code, extra={"delivery": contract.public_delivery(d)})
                return (202 if d and d.get("status") == "received" else 200), {"delivery": contract.public_delivery(d)}
            d = self._call("SELECT public.cl_delivery_status(:'feed'::uuid, :'id'::uuid);",
                           {"feed": feed, "id": route["id"]})
            return 200, {"delivery": contract.public_delivery(d)}
        except _HttpError as e:
            return _fail(e.code)

    def _open(self, feed, body, headers):
        ce = (headers.get("content-encoding") or "").strip().lower()
        if ce and ce != "identity":
            return _fail("CL_COMPRESSION_UNSUPPORTED", "Content-Encoding is not supported: send a plain JSON body")
        raw = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
        if len(raw) > contract.MAX_BODY_BYTES:
            return _fail("CL_BODY_TOO_LARGE")
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except ValueError:
            return _fail("CL_BAD_REQUEST", "invalid JSON")
        v = contract.validate_open_request(parsed)
        if not v[0]:
            return _fail(v[1], v[2])
        b = v[1]
        d = self._call("SELECT public.cl_delivery_open(p_feed_id => :'feed'::uuid, p_period_start => :'ps'::date,"
                       " p_period_end => :'pe'::date, p_sha256 => :'sha', p_control_totals => :'ct'::jsonb,"
                       " p_format => :'fmt', p_size_bytes => :'size'::bigint);",
                       {"feed": feed, "ps": b["period_start"], "pe": b["period_end"], "sha": b["sha256"],
                        "ct": json.dumps(b["control_totals"]), "fmt": b["format"], "size": b["size_bytes"]})
        upload = None
        if d and d.get("status") == "pending_upload":
            upload = {"url": LOCAL_UPLOAD_PREFIX + d["file_path"], "method": "PUT",
                      "headers": {"Content-Type": contract.CONTENT_TYPE_BY_FORMAT.get(d["format"],
                                                                                    "application/octet-stream")},
                      "expires_in_seconds": contract.UPLOAD_URL_TTL_SECONDS}
        return (200 if d and d.get("existing") else 201), {"delivery": contract.public_delivery(d), "upload": upload}

    # -- Supabase Storage stub
    def upload(self, upload, path):
        url = upload.get("url") or ""
        if not url.startswith(LOCAL_UPLOAD_PREFIX):
            raise TransportError("local mode only uploads to %s... URLs" % LOCAL_UPLOAD_PREFIX)
        name = url[len(LOCAL_UPLOAD_PREFIX):]
        if not re.match(r"^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jsonl|csv)$", name):
            raise TransportError("unexpected object path %r" % name)
        with open(path, "rb") as f:
            data = f.read()
        exists = self._sql("SELECT count(*) FROM storage.objects WHERE bucket_id = :'b' AND name = :'n';",
                           {"b": contract.BUCKET, "n": name}, role=None)
        if exists != "0":   # what Supabase Storage answers to a second PUT of the same object (no upsert)
            return 400, {"statusCode": "409", "error": "Duplicate", "message": "The resource already exists"}
        dest = os.path.join(self.storage_dir, *name.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
        meta = json.dumps({"size": len(data), "mimetype": (upload.get("headers") or {}).get("Content-Type")})
        self._sql("INSERT INTO storage.objects (bucket_id, name, metadata) VALUES (:'b', :'n', :'m'::jsonb);",
                  {"b": contract.BUCKET, "n": name, "m": meta}, role=None)
        return 200, {"Key": "%s/%s" % (contract.BUCKET, name)}

    def tick(self):
        """One 'minute' of the server: worker + DB phases (local.process_cmd), if configured."""
        if not self.process_cmd:
            return
        p = subprocess.run(self.process_cmd + ["--storage", self.storage_dir], capture_output=True)
        if p.returncode != 0:
            raise TransportError("process_cmd failed: %s" % p.stderr.decode("utf-8", "replace").strip()[:800])


class _HttpError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def _fail(code, detail=None, extra=None):
    return contract.status_of(code), contract.error_body(code, detail, extra)
