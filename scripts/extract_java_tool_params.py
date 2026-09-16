#!/usr/bin/env python3
"""Extracts the Java MCP parameter-name fixtures for the catalog parity test.

Usage:
    python3 scripts/extract_java_tool_params.py <path-to>/tools-raw.json

`tools-raw.json` is the Java reference catalog
(dm.ai: dmtools-ai-docs/references/mcp-tools/tools-raw.json — clone the
upstream repo fresh, per AGENTS.md, and always re-extract from the latest).

Writes (sorted, `tool:param1,param2,...` lines, params in Java declaration
order):

- test/fixtures/java_mcp_tool_params.txt — every Java tool that exact-matches
  a Dart tool name AND whose parameter names already match the Dart registry.
  test/mcp/catalog_parity_test.dart enforces this parity from the fixture, so
  a param renamed on one side only (gh-123: `status` vs `statusName`) turns
  the suite red.
- test/fixtures/java_mcp_param_drift.txt — exact-name matches whose parameter
  names still diverge (the param-side counterpart of
  java_mcp_tool_gaps.txt). The parity test asserts each listed tool still
  diverges; fix one, move its line into the params fixture (re-run this
  script), and the suite goes green again.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures"


def dart_params() -> dict:
    out = subprocess.run(
        ["dart", "run", "scripts/dump_tool_params.dart"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def main() -> None:
    raw = json.loads(pathlib.Path(sys.argv[1]).read_text())["tools"]
    java = {t["name"]: t["inputSchema"]["properties"] for t in raw}
    dart = dart_params()

    parity, drift = [], []
    for name in sorted(set(java) & set(dart)):
        jp = list(java[name])
        line = f"{name}:{','.join(jp)}"
        (parity if sorted(jp) == sorted(dart[name]["params"]) else drift).append(line)

    (FIXTURES / "java_mcp_tool_params.txt").write_text(
        "\n".join(parity) + "\n")
    (FIXTURES / "java_mcp_param_drift.txt").write_text(
        "\n".join(drift) + "\n")
    print(f"parity={len(parity)} drift={len(drift)}")


if __name__ == "__main__":
    main()
