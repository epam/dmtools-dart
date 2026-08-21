# Contributing to DMTools (Dart)

Thank you for your interest in contributing! This document explains how to build, test, and submit changes.

DMTools-dart is the pure-Dart port of [DMTools](https://github.com/epam/dm.ai) (Java/GraalJS → Dart/QuickJS). When behavior is ambiguous, **the Java source is the spec** — record the decision in your commit message.

## Getting Started

```bash
git clone https://github.com/epam/dmtools-dart.git
cd dmtools-dart

dart pub get
make native   # compile the QuickJS shared library — required once per checkout

# Credentials live in dmtools.env (git-ignored) — see README → Configuration
```

> **`make native` is required before tests and the CLI.** Without it you get raw `dlopen ... libquickjs_bridge.so` failures. CI builds it automatically.

## Building

```bash
# Compile the standalone AOT executable (needs the native library)
make build

# Run from source (fast iteration)
dart run bin/dmtools.dart
```

## Running Tests

```bash
# Unit + contract tests (fast, no API calls — run these for every change)
dart test

# A single file
dart test test/integrations/bitrise/bitrise_client_test.dart
```

> **Note:** Integration tests (`test/integration/`, tag `integration`) make real API calls and require valid credentials from `dmtools.env`. They are excluded from the default run and executed by the nightly [integration.yml](.github/workflows/integration.yml).

## Quality Gates

CI ([quality.yml](.github/workflows/quality.yml)) enforces on every push and PR — run them locally before pushing:

```bash
dart format --set-exit-if-changed .
dart analyze
dart test --coverage=coverage
dart pub global run coverage:format_coverage \
  --lcov --in coverage --out coverage/lcov.info --report-on lib
crap4dart check --all    # CRAP threshold 8.0 — see crap4dart.yaml
crap4dart analyze
```

Coverage gate: 80% on `lib`. All logic lives in `lib/`; `bin/` only parses argv and delegates.

## Submitting a Pull Request

1. Fork the repository and create a feature branch from `main`.
2. Make your changes following the code style (see [AGENTS.md](AGENTS.md)).
3. Add or update unit tests for any new logic — tests ship with code.
4. Verify all gates pass (above).
5. Open a pull request with a clear description of what you changed and why — and, when porting behavior, the Java file that served as spec.

## Adding a New MCP Tool

See the conventions in [AGENTS.md](AGENTS.md) and the existing per-integration catalogs under `lib/src/integrations/<name>/<name>_tools.dart` — declaration order, executor routing, and the matching tests under `test/integrations/<name>/`.

## Code Style

- `dart format` defaults; public API documented (the `public_docs` gate enforces it).
- Keep methods small: complexity ≤ 10, body ≤ 60 lines, params ≤ 6 — the gates enforce this.
- Generated code (`*.g.dart`, `*.freezed.dart`) is gate-excluded — regenerate, never hand-edit.

## Reporting Bugs

Please open a [GitHub Issue](https://github.com/epam/dmtools-dart/issues) with:
- A minimal reproduction case
- Your DMTools version (`dmtools --version`)
- Operating system

## Questions

Open a [GitHub Issue](https://github.com/epam/dmtools-dart/issues) with the `question` label for questions and ideas.
