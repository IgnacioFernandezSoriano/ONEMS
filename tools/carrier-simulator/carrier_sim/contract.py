"""Python port of supabase/functions/carrier-link-ingest/lib.ts (limits, envelope checks, SQL error -> HTTP).

Keep in sync with lib.ts: the local mode answers exactly what the Edge Function would answer.
"""
import math
import re

MAX_BODY_BYTES = 5 * 1024 * 1024
MAX_ROWS = 5000
RATE_LIMIT_PER_MINUTE = 30
MAX_DEMANDS = 100
SELECTION_METHOD = "uniform_random_within_stratum"

# CL_ codes whose HTTP status is not the default for their SQLSTATE (lib.ts STATUS_BY_CODE).
STATUS_BY_CODE = {
    "CL_DEMAND_TESTING_DRY_RUN_ONLY": 403,
    "CL_DEMAND_NOT_OPEN": 409,
}


def _is_obj(v):
    return isinstance(v, dict)


def _non_empty(v):
    return isinstance(v, str) and v.strip() != ""


def count_rows(batch):
    if not _is_obj(batch) or not isinstance(batch.get("strata"), list):
        return 0
    return sum(len(s["rows"]) for s in batch["strata"] if _is_obj(s) and isinstance(s.get("rows"), list))


def validate_envelope(batch):
    """Returns None when the envelope is valid, else the error text of the Edge Function (HTTP 400)."""
    if not _is_obj(batch):
        return "CL_BAD_PAYLOAD: the batch must be a JSON object"
    if not _non_empty(batch.get("demand_id")):
        return "CL_BAD_PAYLOAD: demand_id is required"
    if not _non_empty(batch.get("batch_id")):
        return "CL_BAD_PAYLOAD: batch_id is required"
    strata = batch.get("strata")
    if not isinstance(strata, list) or len(strata) == 0:
        return "CL_BAD_PAYLOAD: strata must be a non-empty array"
    for s in strata:
        if not _is_obj(s):
            return "CL_BAD_PAYLOAD: every stratum must be an object"
        if not _non_empty(s.get("stratum_id")):
            return "CL_BAD_PAYLOAD: every stratum needs stratum_id"
        p = s.get("population_size")
        if isinstance(p, bool) or not isinstance(p, (int, float)) or not math.isfinite(p) or p != int(p) or p < 0:
            return "CL_BAD_PAYLOAD: population_size must be a non-negative integer"
        if not _non_empty(s.get("selection_method")):
            return "CL_BAD_PAYLOAD: every stratum needs selection_method"
        if not isinstance(s.get("rows"), list):
            return "CL_BAD_PAYLOAD: every stratum needs a rows array"
    return None


def sql_error_to_http(sqlstate, message):
    """(status, code) for a Postgres error, or None = unexpected (the Edge Function answers 500)."""
    m = re.match(r"^(CL_[A-Z_]+)", message or "")
    cl = m.group(1) if m else None
    known = cl is not None and cl in STATUS_BY_CODE
    if sqlstate == "P0001":
        return (STATUS_BY_CODE[cl], cl) if known else None
    if sqlstate == "22023":
        return (STATUS_BY_CODE.get(cl) or 400, cl or "CL_BAD_REQUEST")
    if sqlstate == "42501":
        return (STATUS_BY_CODE.get(cl) or 403, cl or "CL_FORBIDDEN")
    return None


def summary_stratum_ids(summary):
    if not _is_obj(summary) or not isinstance(summary.get("strata"), list):
        return []
    return [s["stratum_id"] for s in summary["strata"] if _is_obj(s) and isinstance(s.get("stratum_id"), str)]
