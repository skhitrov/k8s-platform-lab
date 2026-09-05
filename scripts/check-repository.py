#!/usr/bin/env python3
"""Cross-file invariants that YAML/schema validators cannot detect."""
import json
from pathlib import Path
import re
import subprocess


def yaml(path):
    output = subprocess.check_output(["yq", "-o=json", "eval-all", "[.]", str(path)], text=True)
    return json.loads(output)


lock = yaml("platform/versions.yaml")[0]
for key, chart in lock["charts"].items():
    assert re.fullmatch(r"[a-f0-9]{64}", chart["sha256"]), f"Missing chart hash: {key}"
for app in yaml("platform/gitops/addons.yaml"):
    source = app["spec"]["sources"][0]
    chart = lock["charts"][source["chart"]]
    assert str(source["targetRevision"]) == str(chart["version"]), f"Version drift: {app['metadata']['name']}"
    assert source["repoURL"] == chart["repository"], f"Repository drift: {source['chart']}"
pins = json.loads(Path(".github/action-pins.json").read_text())
for path in Path(".github/workflows").glob("*.yml"):
    workflow = yaml(path)[0]
    assert workflow.get("permissions") == {"contents": "read"}, f"Unsafe workflow defaults: {path}"
    for job in workflow["jobs"].values():
        assert job["runs-on"] == "ubuntu-24.04", "Public PRs must not run on a self-hosted runner"
        for step in job["steps"]:
            if "uses" in step:
                action, sha = step["uses"].split("@")
                assert re.fullmatch(r"[a-f0-9]{40}", sha), f"Unpinned action: {step['uses']}"
                assert pins[action]["sha"] == sha, f"Update action-pins.json with {step['uses']}"
for env in ("dev", "staging"):
    values = yaml(f"deploy/chart/taskflow/values-{env}.yaml")[0]
    digest = values["image"]["digest"]
    assert not digest or re.fullmatch(r"sha256:[a-f0-9]{64}", digest), f"Invalid {env} digest"
    if digest:
        assert re.fullmatch(r"[a-f0-9]{40}", values["image"]["tag"]), f"Invalid {env} source SHA"
kind = yaml("platform/kind/cluster.yaml")[0]
assert len(kind["nodes"]) == 3
assert sum(node["role"] == "worker" for node in kind["nodes"]) == 2
assert kind["networking"]["disableDefaultCNI"] is True
workbook = Path("docs/workbook.md").read_text()
days = re.findall(r"^\| (\d{2}) \|", workbook, flags=re.MULTILINE)
assert days == [f"{number:02d}" for number in range(1, 85)], "Workbook must contain all 84 ordered daily exercises"
for document in [Path("README.md"), *Path("docs").rglob("*.md"), *Path("labs").rglob("*.md")]:
    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", document.read_text()):
        if "://" in target or target.startswith("#"):
            continue
        local_target = target.split("#", 1)[0]
        assert (document.parent / local_target).exists(), f"Broken local link in {document}: {target}"
print("Repository lock, delivery permissions, and topology invariants passed.")
