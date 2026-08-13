# dmtools-dart

![tests](.badges/tests.svg)
![coverage](.badges/coverage.svg)
![crap4dart](.badges/crap4dart.svg)

Pure Dart port of [DMTools](https://github.com/epam/dm.ai) — the enterprise
dark-factory orchestrator (Jira, ADO, GitHub, GitLab, Confluence, TestRail,
Bitrise, Jenkins, Figma, Teams, SharePoint, AI providers) with a QuickJS
scripting runtime via `dart:ffi`. No JVM, no GraalVM — Dart only.

- **[GOAL.md](GOAL.md)** — the spec: mission, constraints, phases 0–5
- **[AGENTS.md](AGENTS.md)** — the operating manual: rules, commands, layout
- **[test/integration/README.md](test/integration/README.md)** — the four test layers and the live-integration credential matrix

## Quick start

```bash
dart pub get
dart format .
dart analyze
dart test
```

Quality gates (CI [quality.yml](.github/workflows/quality.yml)): `dart format`
clean, `dart analyze` clean, 80% line coverage on `lib`, and a CRAP score
≤ 8.0 enforced by [crap4dart](crap4dart.yaml). Live integration tests run
nightly and on demand — never per-PR — via
[integration.yml](.github/workflows/integration.yml); each integration runs in
its own matrix slot with its own concurrency group.

## Configuration

Every integration is configured through environment variables resolved in a
fixed chain: real env → `dmtools.env` → `dmtools-local.env` (git-ignored). A
config that works with Java DMTools works unchanged here. Check what is wired
up with:

```bash
dart run bin/dmtools.dart doctor    # configuration presence report
```

The full per-integration variable matrix (auth secrets plus sandbox-target
`DMTOOLS_IT_*` variables) lives in
[test/integration/README.md](test/integration/README.md).
