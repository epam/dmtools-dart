# Agents suite sharding (gh-315)

The Quality pipeline's long pole was the `agents-suite` job: 92 test files /
917 tests in one sequential QuickJS engine — 11m44s of the job's 12m20s. The
suite now runs as a 6-way CI matrix of runner-level shards with a merge gate,
the same shape the `dart test` suite already uses (`test` matrix ×4 → `gate`).

**Zero changes under `agents/`** — the suite runs unmodified (GOAL.md Phase 4
acceptance rule). Sharding is a params-level change in *our* runner: each
shard feeds a subset of `jobParams.testFiles` to the same `testRunner.js`.

## Components

```
quality.yml (dispatch)
 ├─ static ───────────────────────────── unchanged
 ├─ test (matrix ×4) ─────────────────── unchanged
 ├─ agents-suite (matrix ×6)            ← sharded; each shard:
 │    bin/run_agents_suite.dart agents
 │      --shard-index i --total-shards 6 --manifest-out <path>
 │      ├─ ShardPlanner.split(testFiles, i, N)   // pure, deterministic
 │      ├─ pre-flight: every planned file exists & non-empty
 │      ├─ JsJobRunner().runScript(testRunner.js, run_all.json jobParams verbatim, testFiles → subset)
 │      └─ writes the suite-shard manifest artifact (JSON, parse-only)
 └─ agents-gate (needs: agents-suite)   ← required merge check
      ├─ downloads the 6 manifests
      ├─ asserts: union(planned) == run_all.json testFiles, exactly once each
      └─ asserts: every shard success:true, failed == 0
```

- `ShardPlanner` (`lib/src/agents/suite_sharding.dart`) — round-robin
  (`files[pos]` → shard `pos % N`): order-stable, deterministic, balances
  known-uneven file costs (`test_smAgent.js` alone emits about half the
  suite's log volume). No count is hardcoded; everything derives from
  `run_all.json` per run, so submodule bumps never require code changes.
- **Suite-shard manifest** — `{"shard": i, "total": N, "plannedFiles": [...],
  "success": bool, "passed": int, "failed": int}`. Machine-written JSON from
  our runner; the gate parses it as data, never evals it.
- **Pre-flight** — today `testRunner.js` silently `continue`s a missing or
  empty test file (green with fewer tests). The runner now fails the shard
  before the engine starts (AC3): gate semantics strictly stricter, never
  weaker.
- **agents-gate** (`scripts/agents_shard_gate.dart`) — any red shard already
  fails through `needs:`; the merge additionally fails on partition defects
  (missing / duplicated / unexpected file) and on missing shard manifests.
  Required status check alongside `static` and `gate` — note the required
  context moved from the (now matrix) `agents-suite` job to `agents-gate`,
  exactly like `test (n)` shards are covered by `gate`.
  Lockstep pins: `test/release_required_checks_test.dart`,
  `machine-sm.yml` validation-checks, `release-cli.yml` stamp loop.

## Why N=6

Round-robin balances the file count, but per-file test weights are known
uneven (`test_smAgent.js`'s quarter of the list carried 432 of 917 tests —
measured on the real suite at N=4). Static per-file test counts give a
max-shard share of 34% @ N=4, 24% @ N=6, 22% @ N=8; N=6 keeps the slowest
shard ≈ 4 min so the whole dispatch (incl. `agents-gate`) stays ≤ 7 min.
N stays a pure workflow constant — retune by editing the matrix list and
`TOTAL_SHARDS` together; no code change.

## Serial path is unchanged (AC5)

`dart run bin/run_agents_suite.dart [agents-path]` — no flags — passes the
identical full `testFiles` list to the engine and keeps the exit contract
(0 green, 1 red, 2 config missing). Sharding is opt-in. The canonical
`dmtools run agents/js/unit-tests/run_all.json` pipeline is untouched.

Invalid flag combos (`i ≥ N`, `N < 1`, `i`/`N` split, empty planned shard,
missing or empty `--manifest-out`, unknown flags) exit non-zero before the
engine.

One delta from the historical serial run: a planned file that is missing or
empty now fails the serial run in pre-flight (exit 1) where `testRunner.js`
used to skip it silently and still go green — AC3's strictly-stricter gate
applies to both modes.

## Bumping the shard count N

Edit `quality.yml` only: the `agents-suite` matrix list and the
`TOTAL_SHARDS` env (keep them equal). No Dart change — the planner derives
everything from `run_all.json`. Runner pool capacity (E4): if the Bitrise
pool cannot host the extra concurrent jobs, shards queue — wall time
degrades, correctness is unaffected.

## Suite parity (AC6) — order-dependence runbook (E3)

```bash
dart run scripts/agents_shard_parity.dart agents [total-shards]
```

Runs the suite serially, then sharded (sequential shards, fresh engine
each), and compares per-shard outcomes against the serial run. Exit 0 =
parity; exit 1 = mismatch (order-dependent behavior), with the differing
runs printed.

A mismatch means a test file depends on execution order — it passes
serially only because an earlier file left globals behind, or fails sharded
because a global it relies on is no longer set. Fix the file's
self-containment; files live upstream, so the fix is a **PR to
dmtools-agents** — never a local patch under `agents/`.

Cadence: on-demand (release time, or whenever a shard fails while the serial
run is green).

## Tests

- `test/agents/suite_sharding_test.dart` — planner partition properties
  (AC1) and merge outcomes (AC4: green, red shard, missing/duplicated
  file, malformed JSON, shard-count defects).
- `test/agents/suite_shard_runner_test.dart` — runner IT on a fixture
  mini-agents tree (AC2 flags/manifest, AC3 pre-flight, AC5 serial
  passthrough, AC6 parity smoke) plus one test through the REAL unmodified
  `testRunner.js` when the agents/ submodule is checked out.
