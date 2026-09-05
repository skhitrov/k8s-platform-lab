#!/usr/bin/env python3
"""Derive the CRD kind schema from Kubernetes' versioned OpenAPI v3 document."""
import json
from pathlib import Path
import sys


def convert(value):
    if isinstance(value, list):
        return [convert(item) for item in value]
    if not isinstance(value, dict):
        return value
    result = {key: convert(item) for key, item in value.items()}
    if isinstance(result.get("$ref"), str):
        result["$ref"] = result["$ref"].replace("#/components/schemas/", "#/definitions/")
    if result.get("type") == "object" and "properties" in result:
        result.setdefault("additionalProperties", False)
    return result


document = json.loads(Path(sys.argv[1]).read_text())
schema = {
    "$schema": "http://json-schema.org/draft-04/schema#",
    "$ref": "#/definitions/io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.CustomResourceDefinition",
    "definitions": convert(document["components"]["schemas"]),
}
directory = Path(sys.argv[2]) / "apiextensions.k8s.io"
directory.mkdir(parents=True, exist_ok=True)
(directory / "customresourcedefinition_v1.json").write_text(json.dumps(schema), encoding="utf-8")
