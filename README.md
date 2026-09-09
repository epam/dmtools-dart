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

### Install the prebuilt binary (no Dart SDK required)

```bash
curl -fsSL \
  "https://github.com/epam/dmtools-dart/releases/latest/download/install.sh" | sh
```

The repository is public — no token required. (`DMTOOLS_GITHUB_TOKEN` is
still honored as an optional override for API rate limits or private forks.)

This installs a standalone AOT binary plus the QuickJS shared library it
loads to `~/.dmtools/bin` and puts it on your `PATH`. Install a specific
version with `... | sh -s -- v0.1.0` (or `DMTOOLS_VERSION=v0.1.0`).
Prebuilt platforms: `linux-x64`, `macos-x64`, `macos-arm64`; on anything
else build from source (below). Releases are cut dm.ai-style by pressing
the **Run workflow** button in
[release-cli.yml](.github/workflows/release-cli.yml) — the patch version
auto-increments from `pubspec.yaml` (or set a custom version), the bump
is committed and tagged, assets and `dmtools-checksums.sha256` are
published, and installs are exercised on every supported OS by
[install-test.yml](.github/workflows/install-test.yml).

### Install from a source checkout (macOS / Linux)

```bash
make install          # build + install to ~/.local/bin (override: PREFIX=…)
```

Installs a small `dmtools` launcher plus the AOT binary (`dmtools.bin`) to
`$(PREFIX)/bin`, with the QuickJS shared library in `native/quickjs/` beside
them. The launcher exports `JSR_QUICKJS_LIB` with the absolute library path —
required because the runtime's exe-relative fallback (`Platform.script`)
does not resolve to the installed executable in AOT builds — so `dmtools`
works from any directory. `install.sh` uses the same launcher layout and
additionally strips macOS quarantine and ad-hoc re-signs the binary
(fa1.dev installer pattern). Prints a PATH hint when `~/.local/bin` is not
on your `PATH` (macOS: add `export PATH="$HOME/.local/bin:$PATH"` to
`~/.zshrc`). Not supported on Windows — use the prebuilt installer or build
with `make build`.

### Build from source

```bash
dart pub get
make native          # compile the QuickJS shared library (required before tests)
dart format .
dart analyze
dart test
```

> **`make native` is required once per checkout.** The JS runtime
> (`quickjs_runtime` package) loads `libquickjs_bridge.so` at test and CLI
> run time; without it you get raw `dlopen ... libquickjs_bridge.so (no
> such file)` failures. `make native` builds it inside the package
> checkout (override the location via `JSR_QUICKJS_LIB`); see the
> [Makefile](Makefile) for platform notes. CI builds it automatically.

Quality gates (CI [quality.yml](.github/workflows/quality.yml)): `dart format`
clean, `dart analyze` clean, 80% line coverage on `lib`, and a CRAP score
≤ 8.0 enforced by [crap4dart](crap4dart.yaml). Live integration tests run
nightly and on demand — never per-PR — via
[integration.yml](.github/workflows/integration.yml); each integration runs in
its own matrix slot with its own concurrency group.

Repo automation (dm.ai parity): the
[agents/](agents) submodule pins [IstiN/dmtools-agents](https://github.com/IstiN/dmtools-agents)
and feeds the L4 suite; [auto-update-prs.yml](.github/workflows/auto-update-prs.yml)
re-bases mergeable PRs after every push to main;
[merge-trigger.yml](.github/workflows/merge-trigger.yml) launches the agents
merge loop when CI passes (fused off via the `MERGE_TRIGGER_ENABLED` variable
until the Teammate job is ported); [ai-teammate.yml](.github/workflows/ai-teammate.yml)
is a reusable (`workflow_call`) runner for dmtools-agents configs.

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

## Machine

This repo runs its own dark-factory loop: GitHub issues drive AI teammates
(bug/story development, PR review, PR rework), and PRs merge automatically
once reviewed and green — see [machine-kit/teammate-install/](machine-kit/teammate-install/).

- [fa-story-dev.json](machine-kit/teammate-install/runners/fa-story-dev.json) — story development teammate (ZAI)
- [fa-bug-dev.json](machine-kit/teammate-install/runners/fa-bug-dev.json) — bug development teammate (ZAI)
- [fa-review-kimi.json](machine-kit/teammate-install/runners/fa-review-kimi.json) — PR review teammate (Kimi; may approve with suggestions)
- [fa-rework-zai.json](machine-kit/teammate-install/runners/fa-rework-zai.json) — PR rework teammate (addresses review comments)
