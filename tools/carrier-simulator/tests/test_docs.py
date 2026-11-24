"""Checks the connector documentation artifacts (docs/carrier-link): JSON Schemas, worked example and OpenAPI.

  python -I tools/carrier-simulator/tests/test_docs.py

No third-party package: a small JSON Schema (draft 2020-12) validator for the keywords the schemas use. An unknown
keyword is an error, so a schema can never silently use something this validator does not check. The OpenAPI file is
YAML: it is converted with the repository's own js-yaml (node_modules) and then checked (version, exact routes and
methods, responses, every $ref resolves, examples valid against their schemas).
"""
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DOCS = os.path.join(ROOT, "docs", "carrier-link")
SCHEMAS = os.path.join(DOCS, "schemas")
EXAMPLE = os.path.join(DOCS, "ejemplo")
DRAFT = "https://json-schema.org/draft/2020-12/schema"

KEYWORDS = {"$schema", "$id", "$ref", "$defs", "title", "description", "default", "examples", "type", "properties",
            "required", "additionalProperties", "items", "enum", "const", "pattern", "minimum", "maximum", "minLength",
            "maxLength", "minItems", "maxItems", "minProperties", "format", "anyOf", "propertyNames"}
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


class Validator:
    """Draft 2020-12 subset. Schemas are loaded from SCHEMAS by file name; $ref = 'file#/json/pointer' or '#/...'."""

    def __init__(self):
        self.docs = {n: load(os.path.join(SCHEMAS, n)) for n in os.listdir(SCHEMAS) if n.endswith(".json")}

    def check_schema(self, s, where, doc=None):
        doc = doc or where
        if isinstance(s, bool):
            return
        assert isinstance(s, dict), where
        unknown = set(s) - KEYWORDS
        assert not unknown, "%s: unsupported keywords %s" % (where, unknown)
        for k in ("properties", "$defs"):
            for name, sub in (s.get(k) or {}).items():
                self.check_schema(sub, "%s/%s/%s" % (where, k, name), doc)
        for k in ("items", "additionalProperties", "propertyNames"):
            if isinstance(s.get(k), dict):
                self.check_schema(s[k], "%s/%s" % (where, k), doc)
        for i, sub in enumerate(s.get("anyOf") or []):
            self.check_schema(sub, "%s/anyOf/%d" % (where, i), doc)
        if "$ref" in s:
            self.resolve(s["$ref"], doc)

    def resolve(self, ref, base):
        file, _, pointer = ref.partition("#")
        doc_name = file or base
        node = self.docs[doc_name]
        for part in [p for p in pointer.split("/") if p]:
            node = node[part]
        return node, doc_name

    def errors(self, inst, s, doc, path="$"):
        if s is True:
            return []
        if s is False:
            return ["%s: not allowed" % path]
        out = []
        if "$ref" in s:
            sub, d = self.resolve(s["$ref"], doc)
            out += self.errors(inst, sub, d, path)
        if "anyOf" in s and not any(not self.errors(inst, sub, doc, path) for sub in s["anyOf"]):
            out.append("%s: no anyOf branch matches" % path)
        if "type" in s:
            types = s["type"] if isinstance(s["type"], list) else [s["type"]]
            okt = any((t == "integer" and isinstance(inst, int) and not isinstance(inst, bool))
                      or (t == "number" and isinstance(inst, (int, float)) and not isinstance(inst, bool))
                      or (t in TYPES and isinstance(inst, TYPES[t]) and not (t != "boolean" and isinstance(inst, bool)))
                      for t in types)
            if not okt:
                return out + ["%s: type %s expected, got %r" % (path, types, inst)]
        if "enum" in s and inst not in s["enum"]:
            out.append("%s: %r not in %s" % (path, inst, s["enum"]))
        if "const" in s and inst != s["const"]:
            out.append("%s: %r != %r" % (path, inst, s["const"]))
        if isinstance(inst, str):
            if "pattern" in s and not re.search(s["pattern"], inst):
                out.append("%s: %r does not match %s" % (path, inst, s["pattern"]))
            if len(inst) < s.get("minLength", 0) or len(inst) > s.get("maxLength", 10 ** 9):
                out.append("%s: length" % path)
            out += self.format_errors(inst, s.get("format"), path)
        if isinstance(inst, (int, float)) and not isinstance(inst, bool):
            if inst < s.get("minimum", float("-inf")) or inst > s.get("maximum", float("inf")):
                out.append("%s: %r out of range" % (path, inst))
        if isinstance(inst, list):
            if len(inst) < s.get("minItems", 0) or len(inst) > s.get("maxItems", 10 ** 9):
                out.append("%s: item count" % path)
            if "items" in s:
                for i, x in enumerate(inst):
                    out += self.errors(x, s["items"], doc, "%s[%d]" % (path, i))
        if isinstance(inst, dict):
            for k in s.get("required", []):
                if k not in inst:
                    out.append("%s: missing %s" % (path, k))
            if len(inst) < s.get("minProperties", 0):
                out.append("%s: too few properties" % path)
            props = s.get("properties", {})
            for k, v in inst.items():
                if "propertyNames" in s:
                    out += self.errors(k, s["propertyNames"], doc, "%s.<%s>" % (path, k))
                if k in props:
                    out += self.errors(v, props[k], doc, "%s.%s" % (path, k))
                elif "additionalProperties" in s:
                    out += self.errors(v, s["additionalProperties"], doc, "%s.%s" % (path, k))
        return out

    @staticmethod
    def format_errors(v, fmt, path):
        try:
            if fmt == "date":
                dt.date.fromisoformat(v)
            elif fmt == "date-time":
                dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
            elif fmt == "uuid" and not re.match(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", v):
                raise ValueError(v)
        except ValueError:
            return ["%s: %r is not a %s" % (path, v, fmt)]
        return []

    def validate(self, inst, schema_name):
        return self.errors(inst, self.docs[schema_name], schema_name)


V = Validator()


class SchemasTest(unittest.TestCase):
    def test_schemas_are_draft_2020_12_and_self_consistent(self):
        self.assertEqual(sorted(V.docs), sorted([
            "config-response.schema.json", "delivery-file-row.schema.json", "delivery-open-request.schema.json",
            "delivery-open-response.schema.json", "delivery-response.schema.json", "delivery.schema.json",
            "error.schema.json"]))
        for name, s in V.docs.items():
            self.assertEqual(s["$schema"], DRAFT, name)
            self.assertTrue(s["$id"].endswith("/" + name), name)
            V.check_schema(s, name)

    def test_validator_rejects(self):
        self.assertTrue(V.validate({"period_start": "2026-11-02"}, "delivery-open-request.schema.json"))
        req = load(os.path.join(EXAMPLE, "03-open-request.json"))
        self.assertTrue(V.validate(dict(req, name="x"), "delivery-open-request.schema.json"))
        self.assertTrue(V.validate(dict(req, size_bytes=0), "delivery-open-request.schema.json"))
        self.assertTrue(V.validate(dict(req, period_end="2026-02-30"), "delivery-open-request.schema.json"))
        bad = json.loads(json.dumps(req))
        bad["control_totals"][0]["delivered"] = -1
        self.assertTrue(V.validate(bad, "delivery-open-request.schema.json"))
        self.assertTrue(V.validate({"x": {"a": 1}}, "delivery-file-row.schema.json"))
        self.assertTrue(V.validate({"success": True, "error": "CL_X", "message": "m"}, "error.schema.json"))


class ExampleTest(unittest.TestCase):
    """The worked example (output of tools/carrier-simulator/e2e/run.sh with SAVE_EXAMPLES=1) matches the schemas."""

    BODIES = {
        "01-get-config.json": "config-response.schema.json",
        "18-get-config-after.json": "config-response.schema.json",
        "04-open-response.json": "delivery-open-response.schema.json",
        "12-replay-open-existing.json": "delivery-open-response.schema.json",
        "06-complete-response.json": "delivery-response.schema.json",
        "07-status-processed.json": "delivery-response.schema.json",
        "09-status-processed-csv.json": "delivery-response.schema.json",
        "10-tampered-complete-response.json": "delivery-response.schema.json",
        "11-tampered-status-rejected.json": "delivery-response.schema.json",
        "13-error-already-delivered.json": "error.schema.json",
        "14-error-not-in-calendar.json": "error.schema.json",
        "15-error-no-active-plan.json": "error.schema.json",
        "16-error-delivery-not-found.json": "error.schema.json",
        "17-error-v3-route-gone.json": "error.schema.json",
    }

    def test_responses(self):
        for f, schema in self.BODIES.items():
            self.assertEqual(V.validate(load(os.path.join(EXAMPLE, f))["body"], schema), [], f)

    def test_request_and_file(self):
        req = load(os.path.join(EXAMPLE, "03-open-request.json"))
        self.assertEqual(V.validate(req, "delivery-open-request.schema.json"), [])
        path = os.path.join(EXAMPLE, "02-delivery-2026-11-02_2026-11-04.jsonl")
        with open(path, "rb") as f:
            data = f.read()
        import hashlib
        self.assertEqual(hashlib.sha256(data).hexdigest(), req["sha256"])
        self.assertEqual(len(data), req["size_bytes"])
        good = 0
        for line in data.decode("utf-8").split("\n"):
            try:
                rec = json.loads(line) if line else None
            except ValueError:
                continue                                     # the 'broken record' noise lines
            if isinstance(rec, dict):
                self.assertEqual(V.validate(rec, "delivery-file-row.schema.json"), [])
                good += 1
        self.assertGreater(good, 100)
        manifest = load(os.path.join(EXAMPLE, "02-delivery-2026-11-02_2026-11-04.manifest.json"))
        self.assertEqual(manifest["sha256"], req["sha256"])
        self.assertEqual(good, manifest["rows"])


def openapi():
    node = shutil.which("node")
    if not node:
        return None
    js = ("const y=require('js-yaml');const fs=require('fs');"
          "process.stdout.write(JSON.stringify(y.load(fs.readFileSync(process.argv[1],'utf8'))))")
    p = subprocess.run([node, "-e", js, os.path.join(DOCS, "openapi.yaml")], cwd=ROOT, capture_output=True)
    if p.returncode != 0:
        raise AssertionError(p.stderr.decode())
    return json.loads(p.stdout.decode("utf-8"))


class OpenApiTest(unittest.TestCase):
    ROUTES = {
        "/config": {"get": {"200", "401", "404", "405", "429", "500"}},
        "/deliveries": {"post": {"200", "201", "400", "401", "403", "404", "409", "413", "422", "429", "500"}},
        "/deliveries/{id}/complete": {"post": {"200", "202", "401", "403", "404", "409", "410", "413", "422", "429",
                                               "500"}},
        "/deliveries/{id}": {"get": {"200", "401", "404", "429", "500"}},
        "/demands": {"get": {"410"}},
        "/batches": {"post": {"410"}},
    }

    @classmethod
    def setUpClass(cls):
        cls.doc = openapi()
        if cls.doc is None:
            raise unittest.SkipTest("node is not installed: OpenAPI not checked")

    def refs(self, node, out):
        if isinstance(node, dict):
            if "$ref" in node:
                out.append(node["$ref"])
            for v in node.values():
                self.refs(v, out)
        elif isinstance(node, list):
            for v in node:
                self.refs(v, out)
        return out

    def test_document(self):
        d = self.doc
        self.assertTrue(re.match(r"^3\.1\.\d+$", d["openapi"]))
        self.assertTrue(d["info"]["title"] and d["info"]["version"])
        self.assertEqual(set(d["paths"]), set(self.ROUTES))
        for path, ops in self.ROUTES.items():
            item = d["paths"][path]
            self.assertEqual({k for k in item if k in ("get", "post", "put", "delete", "patch")}, set(ops), path)
            for method, statuses in ops.items():
                op = item[method]
                self.assertTrue(op.get("operationId") and op.get("summary"), path)
                self.assertTrue(statuses <= set(op["responses"]), "%s %s: %s" % (
                    method, path, sorted(statuses - set(op["responses"]))))
                if path in ("/demands", "/batches"):
                    self.assertTrue(op.get("deprecated"))
        for ref in self.refs(d, []):
            if ref.startswith("#/"):
                node = d
                for part in ref[2:].split("/"):
                    node = node[part]
            else:
                file, _, pointer = ref.partition("#")
                self.assertTrue(file.startswith("schemas/"), ref)
                V.resolve(file[len("schemas/"):] + ("#" + pointer if pointer else ""), None)

    def test_examples_in_openapi(self):
        """Every inline example of a response or request validates against its schema file."""
        n = 0
        for path, item in self.doc["paths"].items():
            for method, op in item.items():
                if not isinstance(op, dict) or "responses" not in op:
                    continue
                bodies = [op.get("requestBody", {})] + list(op["responses"].values())
                for b in bodies:
                    resolved = b
                    if "$ref" in b:
                        resolved = self.doc
                        for part in b["$ref"][2:].split("/"):
                            resolved = resolved[part]
                    media = (resolved.get("content") or {}).get("application/json")
                    if not media or "example" not in media:
                        continue
                    ref = media["schema"]["$ref"]
                    self.assertTrue(ref.startswith("schemas/"), ref)
                    self.assertEqual(V.validate(media["example"], ref[len("schemas/"):]), [], "%s %s" % (method, path))
                    n += 1
        self.assertGreaterEqual(n, 5)


if __name__ == "__main__":
    unittest.main(verbosity=1)
