#!/usr/bin/env bash
# machine_tick.sh — the local pre-flight twin of the machine-sm.yml cron tick
# (gh-152). agents/docs/machine-factory-integration.md (Troubleshooting)
# recommends "run a local tick" before enabling the rules on a target repo;
# until now that meant hand-assembling the `dmtools run` overrides. This
# helper replicates exactly what agents/.github/workflows/factory-sm.yml
# does in CI:
#
#   - the reconciled repository: the workflow passes github.repository;
#     locally it resolves from `git remote get-url origin` (never a
#     hardcoded owner/repo, so any factory target repo can use this);
#   - the engine checkout: dmtools-agents at --ref, DEFAULT the exact
#     `agents` submodule pin at HEAD — the same commit production executes,
#     so a local tick cannot disagree with the cron about rules/engine;
#     the already-checked-out agents/ submodule is reused when it matches;
#   - the invocation, from inside the engine checkout:
#       dmtools run sm_github.json '{"params":{"jobParams":{"repo":
#         "<owner>/<repo>"[,"dryRun":true]}}}'
#     with SOURCE_GITHUB_TOKEN in the environment (plus the GH_TOKEN/GH_REPO
#     mirror the workflow step exports).
#
# Modes:
#   --dry    plan only — the engine logs what it would do, changes nothing
#            (default; the factory's dryRun=true).
#   --live   real actions: labels, dispatches, branch updates, merges.
#
# Exit codes: 0 the tick completed ("no action needed" counts);
#             1 the engine ran and failed;
#             2 configuration error (wrong cwd, no origin, no token, no
#               dmtools, unusable engine checkout).
# Nothing secret is printed: the token is read from the environment (or
# dmtools.env) and only ever exported into the engine's environment.
set -euo pipefail

readonly CONFIG_EXIT=2
readonly ENGINE_EXIT=1

usage() {
  cat <<'EOF'
usage: ./scripts/machine_tick.sh [--dry] [--live] [--ref <sha|branch>]

  --dry                plan only, no actions (default; factory dryRun=true)
  --live               perform real actions (factory dryRun=false)
  --ref <sha|branch>   dmtools-agents ref to check out
                       (default: the `agents` submodule pin — the prod ref)

SOURCE_GITHUB_TOKEN comes from the environment or dmtools.env.
Exit codes: 0 ok · 1 engine failed · 2 configuration error.
EOF
}

# die <exit-code> <message...> — one line to stderr, then exit.
die() {
  local code="$1"
  shift
  echo "machine_tick: $*" >&2
  exit "$code"
}

# Redact userinfo credentials from a URL before it is echoed anywhere.
redact_url() {
  printf '%s\n' "$1" | sed -E 's#(://)[^/@]+@#\1##'
}

mode="dry"
factory_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry)
      mode="dry"
      ;;
    --live)
      mode="live"
      ;;
    --ref)
      if [ "$#" -lt 2 ]; then
        usage >&2
        die "$CONFIG_EXIT" "--ref needs a value (sha or branch)"
      fi
      factory_ref="$2"
      shift
      ;;
    --ref=*)
      factory_ref="${1#--ref=}"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "$CONFIG_EXIT" "unknown argument: $1"
      ;;
  esac
  shift
done

case "$factory_ref" in
  -*) die "$CONFIG_EXIT" "--ref looks like a flag, not a sha/branch: $factory_ref" ;;
esac

# ── cwd: the tick reconciles THIS checkout — repo root or nothing ──
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  die "$CONFIG_EXIT" "not inside a git repository — run from the target repo root"
if [ "$(pwd -P)" != "$repo_root" ]; then
  die "$CONFIG_EXIT" "run from the repository root (${repo_root}), not a subdirectory"
fi

# ── target repo: the factory passes github.repository; parse origin ──
origin_url="$(git remote get-url origin 2>/dev/null)" ||
  die "$CONFIG_EXIT" "no 'origin' remote — cannot resolve the target repository"
repo="$(printf '%s\n' "$origin_url" | sed -E \
  -e 's#^(git@|ssh://git@)[^:/]+[:/]##' \
  -e 's#^(https?|git)://[^/]+/##' \
  -e 's#\.git$##')"
if ! printf '%s\n' "$repo" | grep -Eq '^[^/[:space:]]+/[^/[:space:]]+$'; then
  die "$CONFIG_EXIT" "origin does not look like a GitHub owner/repo ($(redact_url "$origin_url")) — the SM engine reconciles github.com repositories"
fi

# ── engine ref: default to the exact commit production executes ──
if [ -z "$factory_ref" ]; then
  factory_ref="$(git ls-tree HEAD agents 2>/dev/null | awk '{print $3}')" ||
    die "$CONFIG_EXIT" "cannot read the agents submodule pin — pass --ref <sha|branch>"
  if [ -z "$factory_ref" ]; then
    die "$CONFIG_EXIT" "no agents submodule pin at HEAD — pass --ref <sha|branch> to pick the dmtools-agents ref"
  fi
fi

# ── engine checkout: reuse the pinned submodule when it matches, else clone ──
agents_url="$(git config --file .gitmodules --get submodule.agents.url 2>/dev/null || true)"
if [ -z "$agents_url" ] && [ -e agents/.git ]; then
  agents_url="$(git -C agents remote get-url origin 2>/dev/null || true)"
fi
if [ -z "$agents_url" ]; then
  die "$CONFIG_EXIT" "cannot resolve the dmtools-agents clone URL — .gitmodules needs submodule.agents.url"
fi

# ── token: [REDACTED:Sensitive Value], else dmtools.env — never echoed ──
# Config checks fail fast BEFORE any network work (checkout/clone).
if [ -z "${SOURCE_GITHUB_TOKEN:-}" ] && [ -f dmtools.env ]; then
  token="[REDACTED:Sensitive Value]"
  if [ "${#token}" -ge 2 ]; then
    first="${token:[REDACTED:Sensitive Value]}"
    last="${token: [REDACTED:Sensitive Value]}"
    if [ "$first" = '"' ] || [ "$first" = "'" ]; then
      if [ "$first" = "$last" ]; then
        token="[REDACTED:Sensitive Value]"
        token="[REDACTED:Sensitive Value]"
      fi
    fi
  fi
  SOURCE_GITHUB_TOKEN="$token"
fi
if [ -z "${SOURCE_GITHUB_TOKEN:-}" ]; then
  die "$CONFIG_EXIT" "SOURCE_GITHUB_TOKEN is not set — export it or add SOURCE_GITHUB_TOKEN=<pat> to dmtools.env (the engine needs GitHub API access; the cron uses the SOURCE_GITHUB_TOKEN secret)"
fi
export SOURCE_GITHUB_TOKEN
# Mirror of the factory step's environment: gh CLI callers inside the
# engine resolve the same credential and repository as in production.
export GH_TOKEN="$SOURCE_GITHUB_TOKEN"
export GH_REPO="$repo"

# ── dmtools: PATH first, the local dart fallback second ──
if command -v dmtools >/dev/null 2>&1; then
  dmtools_cmd=("$(command -v dmtools)")
  echo "→ dmtools: ${dmtools_cmd[0]}"
elif [ -f bin/dmtools.dart ] && command -v dart >/dev/null 2>&1; then
  dmtools_cmd=(dart run "$repo_root/bin/dmtools.dart")
  echo "→ dmtools: dart run bin/dmtools.dart (fallback — not on PATH)"
else
  die "$CONFIG_EXIT" "dmtools not found on PATH and the dart fallback is unavailable (need bin/dmtools.dart plus dart on PATH)"
fi

engine_dir=""
if [ -e agents/.git ] &&
  [ "$(git -C agents rev-parse HEAD 2>/dev/null || true)" = "$factory_ref" ]; then
  engine_dir="agents"
  echo "→ engine: agents/ submodule checkout already at ${factory_ref:0:12} (reusing)"
fi
if [ -z "$engine_dir" ]; then
  engine_dir="$(mktemp -d)"
  trap 'rm -rf "$engine_dir"' EXIT
  echo "→ engine: cloning $(redact_url "$agents_url") at ${factory_ref:0:12}"
  if ! git clone --quiet "$agents_url" "$engine_dir" 2>/dev/null; then
    die "$CONFIG_EXIT" "cannot clone dmtools-agents from $(redact_url "$agents_url") — check the URL and your network"
  fi
  if ! git -C "$engine_dir" checkout --quiet "$factory_ref" 2>/dev/null; then
    die "$CONFIG_EXIT" "dmtools-agents has no ref '${factory_ref}'"
  fi
fi
if [ ! -f "$engine_dir/sm_github.json" ]; then
  die "$CONFIG_EXIT" "no sm_github.json at ${factory_ref:0:12} — is this a dmtools-agents ref?"
fi

# ── the same override the factory passes (dry adds dryRun:true) ──
dry_json=""
if [ "$mode" = "dry" ]; then
  dry_json=',"dryRun":true'
fi
override="$(printf '{"params":{"jobParams":{"repo":"%s"%s}}}' "$repo" "$dry_json")"

echo "→ SM tick: repo=$repo mode=$mode ref=${factory_ref:0:12}"
set +e
(
  cd "$engine_dir" || exit 1
  "${dmtools_cmd[@]}" run sm_github.json "$override"
)
status=$?
set -e
if [ "$status" -ne 0 ]; then
  die "$ENGINE_EXIT" "SM engine failed (exit $status, mode=$mode) — see the output above"
fi
if [ "$mode" = "dry" ]; then
  echo "✓ dry tick complete — nothing was changed; the plan above is what the cron tick would do"
else
  echo "✓ live tick complete"
fi
