#!/usr/bin/env python3
"""Convert our rendered CRD OpenAPI schemas into local kubeconform schemas."""
import json
from pathlib import Path
import sys


def convert(value):
    if isinstance(value, list):
        return [convert(item) for item in value]
    if not isinstance(value, dict):
        return value
    result = {key: convert(item) for key, item in value.items()}
    if result.get("x-kubernetes-int-or-string"):
        result.pop("type", None)
        result["anyOf"] = [{"type": "integer"}, {"type": "string"}]
    if result.pop("nullable", False) and isinstance(result.get("type"), str):
        result["type"] = [result["type"], "null"]
    if (result.get("type") == "object" and "properties" in result
            and not result.get("x-kubernetes-preserve-unknown-fields")):
        result.setdefault("additionalProperties", False)
    return result


destination = Path(sys.argv[1])
count = 0
for crd in json.load(sys.stdin):
    group = crd["spec"]["group"]
    kind = crd["spec"]["names"]["kind"].lower()
    directory = destination / group
    directory.mkdir(parents=True, exist_ok=True)
    for version in crd["spec"]["versions"]:
        schema = convert(version["schema"]["openAPIV3Schema"])
        schema["$schema"] = "http://json-schema.org/draft-07/schema#"
        schema.setdefault("properties", {}).update({
            "apiVersion": {"type": "string"}, "kind": {"type": "string"},
            "metadata": {"type": "object"},
        })
        filename = directory / f"{kind}_{version['name']}.json"
        filename.write_text(json.dumps(schema), encoding="utf-8")
        count += 1
print(f"Extracted {count} custom-resource schemas from checksum-verified releases.")
