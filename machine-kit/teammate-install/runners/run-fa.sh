#!/usr/bin/env bash
# machine-kit/teammate-install/runners/run-fa.sh — generic fa runner for
# dmtools CliAgent jobs. Provider VARIATION lives entirely in the job's
# params.envVariables (the Java-parity override path): each runner JSON
# pins FA_PROVIDER_TYPE + FA_PROVIDER_CONFIG, keys come from the
# environment (dmtools.env / real env — cli_execute_command injects both;
# job overrides beat dmtools.env, so this script never re-loads it).
#
# Contract:
#   required env : FA_PROVIDER_TYPE, FA_PROVIDER_CONFIG (JSON with
#                  baseUrl+model+apiKeyEnvVar), and the key in the env var
#                  FA_PROVIDER_CONFIG's apiKeyEnvVar names
#   optional env : FA_RUN_NAME (session suffix), FA_SESSION_ROOT,
#                  FA_SESSION_NAME
#   prompt       : $1, else input/ticket.md (CliAgent input convention),
#                  else stdin
set -eu

fail() { echo "[run-fa] ERROR: $*" >&2; exit 1; }

[ -n "${FA_PROVIDER_TYPE:-}" ] || fail "FA_PROVIDER_TYPE is not set (declare it in the job's envVariables)"
[ -n "${FA_PROVIDER_CONFIG:-}" ] || fail "FA_PROVIDER_CONFIG is not set (declare it in the job's envVariables)"

# Fail fast on a missing key: extract apiKeyEnvVar from the declaration
# and require the named env var (or its _BASE64 twin) to be non-empty.
KEY_VAR="$(printf '%s' "${FA_PROVIDER_CONFIG}" | sed -n 's/.*"apiKeyEnvVar"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -n "${KEY_VAR}" ] && [ -z "$(eval "echo \${${KEY_VAR}:-}")" ] \
   && [ -z "$(eval "echo \${${KEY_VAR}_BASE64:-}")" ]; then
  fail "provider key missing: ${KEY_VAR} is empty (add it to dmtools.env or the real environment)"
fi

# ── Prompt: arg → input/ticket.md → stdin ────────────────────────────────────
PROMPT="${1:-}"
if [ -z "${PROMPT}" ] && [ -f "input/ticket.md" ]; then
  PROMPT="$(cat input/ticket.md)"
fi
if [ -z "${PROMPT}" ] && [ ! -t 0 ]; then
  PROMPT="$(cat)"
fi
[ -n "${PROMPT}" ] || fail "no prompt: pass an argument, use the input/ticket.md convention, or pipe stdin"

# ── Deterministic session per runner kind ────────────────────────────────────
SESSION_NAME="${FA_SESSION_NAME:-dmtools-${FA_RUN_NAME:-run}}"
SESSION_ROOT="${FA_SESSION_ROOT:-${HOME}/.fah/dmtools-sessions}"
mkdir -p "${SESSION_ROOT}"

echo "[run-fa] provider=${FA_PROVIDER_TYPE} session=${SESSION_NAME}"
exec fa --session "${SESSION_NAME}" --session-root "${SESSION_ROOT}" -p "${PROMPT}"
