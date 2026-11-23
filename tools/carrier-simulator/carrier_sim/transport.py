"""How the connector talks to ONEMS. Both transports answer (http_status, json_body) like carrier-link-ingest.

DevTransport   real HTTP to the Edge Function (GET /demands, POST /batches[?dry_run=true]) with the connector key in
               x-api-key. Refuses a non-loopback host unless CONFIRM_REMOTE=<project ref> is set (owner confirmation)
               and the URL is https; never follows redirects (a 3xx is returned as is, the key is not re-sent).
LocalTransport the local Postgres (127.0.0.1:5433, onems_t) through psql, calling the SAME SQL functions as
               supabase/functions/carrier-link-ingest/index.ts in the SAME order, one transaction per call:
               api_key_resolve -> (GET) open demands of the key's connector
                               -> (POST) envelope checks, connector status, cl_ingest_batch, and for a real batch still
                                  'validated': cl_sample_stratum per stratum of the summary, then cl_finish_batch.
               Not emulated: the per-key rate limit and the api_usage_log row (they need the request clock/IP only).
"""
import json
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request

from . import contract

LOOPBACK = {"127.0.0.1", "localhost", "::1"}


class TransportError(Exception):
    pass


def read_key(path):
    try:
        with open(path, encoding="utf-8") as f:
            key = f.read().strip()
    except OSError as e:
        raise TransportError("cannot read the key file %s (%s)" % (path, e.strerror))
    if not key:
        raise TransportError("empty key file: %s" % path)
    return key


# ---------------------------------------------------------------------------------------------------------------- DEV
class DevTransport:
    def __init__(self, base_url, key, timeout=120):
        self.base = base_url.rstrip("/")
        self.key = key
        self.timeout = timeout
        url = urllib.parse.urlparse(self.base)
        host = url.hostname or ""
        if host not in LOOPBACK and url.scheme != "https":
            raise TransportError("remote call refused: %s is not https (the key would travel in clear)" % self.base)
        if host not in LOOPBACK:
            ref = host.split(".")[0]
            if os.environ.get("CONFIRM_REMOTE") != ref:
                raise TransportError("remote call refused: set CONFIRM_REMOTE=%s once the owner has confirmed this run"
                                     % ref)

    def _call(self, method, path, body=None):
        data = None
        headers = {"x-api-key": self.key, "Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with _OPENER.open(req, timeout=self.timeout) as r:
                return r.status, _json(r.read())
        except urllib.error.HTTPError as e:
            return e.code, _json(e.read())

    def get_demands(self):
        return self._call("GET", "/demands")

    def post_batch(self, batch, dry_run):
        return self._call("POST", "/batches" + ("?dry_run=true" if dry_run else ""), batch)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a redirect: the x-api-key header must only reach the configured endpoint."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _json(raw):
    try:
        return json.loads(raw.decode("utf-8") or "null")
    except ValueError:
        return {"raw": raw.decode("utf-8", "replace")[:2000]}


# -------------------------------------------------------------------------------------------------------------- LOCAL
class SqlError(Exception):
    def __init__(self, sqlstate, message):
        super().__init__("%s %s" % (sqlstate, message))
        self.sqlstate, self.message = sqlstate, message


class LocalTransport:
    def __init__(self, local, key, work_dir):
        self.psql = local.get("psql", "C:/Users/fernandezi/pgportable/pgsql/bin/psql.exe")
        self.host = local.get("host", "127.0.0.1")
        if self.host not in LOOPBACK:
            raise TransportError("local mode only talks to a loopback Postgres, not %s" % self.host)
        self.port = str(local.get("port", 5433))
        self.db = local.get("dbname", "onems_t")
        self.user = local.get("user", "postgres")
        self.password = local.get("password", "postgres")
        self.key = key
        self.work_dir = work_dir

    def _sql(self, sql, variables):
        """Runs sql (psql variables :'name') in its own transaction; returns the single value or raises SqlError."""
        cmd = [self.psql, "-h", self.host, "-p", self.port, "-U", self.user, "-d", self.db,
               "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
        for k, v in variables.items():
            cmd += ["-v", "%s=%s" % (k, v)]
        env = dict(os.environ, PGPASSWORD=self.password, PGCLIENTENCODING="UTF8")
        p = subprocess.run(cmd, input=sql.encode("utf-8"), capture_output=True, env=env)
        err = p.stderr.decode("utf-8", "replace")
        if p.returncode != 0:
            m = re.search(r"ERROR:\s+([0-9A-Z]{5}):\s+(.*)", err)
            if m:
                raise SqlError(m.group(1), m.group(2).strip())
            raise TransportError("psql failed: %s" % err.strip()[:500])
        return p.stdout.decode("utf-8").strip()

    def _rpc(self, sql, variables):
        try:
            out = self._sql(sql, variables)
        except SqlError as e:
            mapped = contract.sql_error_to_http(e.sqlstate, e.message)
            raise HttpError(*(mapped or (500, "Internal server error")))
        return json.loads(out) if out else None

    def _feed(self):
        out = self._sql("SELECT row_to_json(k) FROM public.api_key_resolve(:'key') k LIMIT 1;", {"key": self.key})
        k = json.loads(out) if out else None
        if not k or k.get("scope") != "carrier_feed" or not k.get("feed_id"):
            return None
        return k["feed_id"]

    def get_demands(self):
        feed = self._feed()
        if not feed:
            return 401, {"success": False, "error": "Invalid or inactive API key"}
        out = self._sql("SELECT COALESCE(jsonb_agg(x.payload ORDER BY x.requested_at), '[]'::jsonb) FROM ("
                        " SELECT d.payload, d.requested_at FROM public.cl_demands d"
                        "  WHERE d.feed_id = :'feed' AND d.status = 'open'"
                        "  ORDER BY d.requested_at LIMIT %d) x;" % contract.MAX_DEMANDS, {"feed": feed})
        return 200, {"demands": json.loads(out)}

    def post_batch(self, batch, dry_run):
        feed = self._feed()
        if not feed:
            return 401, {"success": False, "error": "Invalid or inactive API key"}
        body = json.dumps(batch).encode("utf-8")
        if len(body) > contract.MAX_BODY_BYTES:
            return 413, {"success": False, "error": "CL_BODY_TOO_LARGE"}
        bad = contract.validate_envelope(batch)
        if bad:
            return 400, {"success": False, "error": bad}
        if contract.count_rows(batch) > contract.MAX_ROWS:
            return 413, {"success": False, "error": "CL_TOO_MANY_ROWS"}
        status = self._sql("SELECT status FROM public.cl_feeds WHERE id = :'feed';", {"feed": feed})
        if not status:
            return 500, {"success": False, "error": "Internal server error"}
        if status == "paused":
            return 403, {"success": False, "error": "CL_FEED_PAUSED"}
        if status == "testing" and not dry_run:
            return 403, {"success": False, "error": "CL_FEED_TESTING_DRY_RUN_ONLY"}

        fd, path = tempfile.mkstemp(suffix=".json", dir=self.work_dir)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(body)
            fpath = os.path.abspath(path).replace("\\", "/")
            try:
                ingest = self._rpc("SELECT public.cl_ingest_batch(:'feed', pg_read_file(:'file')::jsonb, :'dry'::boolean);",
                                   {"feed": feed, "file": fpath, "dry": "true" if dry_run else "false"})
            except HttpError as e:
                return e.status, {"success": False, "error": e.code}
        finally:
            os.remove(path)
        if dry_run or not isinstance(ingest, dict) or ingest.get("status") != "validated" or not ingest.get("batch"):
            return 200, {"ingest": ingest}

        bst = self._sql("SELECT b.status FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id"
                        " WHERE b.id = :'batch' AND d.feed_id = :'feed';", {"batch": ingest["batch"], "feed": feed})
        if bst != "validated":
            return 200, {"ingest": ingest}

        sampling = []
        for sid in contract.summary_stratum_ids(ingest):
            try:
                sampling.append(self._rpc("SELECT public.cl_sample_stratum(:'batch', :'sid');",
                                          {"batch": ingest["batch"], "sid": sid}))
            except HttpError as e:
                code = "internal" if e.status == 500 else e.code
                return e.status, {"ingest": ingest, "sampling": sampling, "failed": {"stratum_id": sid, "code": code}}
        try:
            finish = self._rpc("SELECT public.cl_finish_batch(:'batch');", {"batch": ingest["batch"]})
        except HttpError as e:
            return e.status, {"success": False, "error": e.code}
        return 200, {"ingest": ingest, "sampling": sampling, "finish": finish}


class HttpError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status, self.code = status, code
