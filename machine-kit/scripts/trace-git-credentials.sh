#!/usr/bin/env bash
# trace-git-credentials.sh — gh-63 Task 1 push-time credential evidence,
# plus the hard gates that turn it into run-killing proofs.
#
# One copy serves every call site (PR #68 review thread 18 — the four
# inline copies of this block — pre- and post-agent, workflow and template —
# were the same drift hazard that forced the installer extraction in
# thread 6):
#
#   trace-git-credentials.sh                 # full pre-agent trace (default)
#   trace-git-credentials.sh --post-agent    # memory-persist re-assert gate
#
# Full mode (pre-agent, right before the agent step), what each section
# proves:
#   --show-origin        WHERE each credential source lives; the extraheader
#                        section must come back empty — asserted below, so
#                        any resurrection of the checkout's App token
#                        (github-actions[bot]) — checkout layout change or
#                        mid-run config write — fails the run here instead
#                        of silently re-arming bot pushes
#   submodule foreach    same proof for each submodule local config
#                        (checkout arms those with submodules: true)
#   git var              the commit identity actually in effect
#   git credential fill  dry-runs the exact push-path resolution; the
#                        SOURCE helper must answer (username=x-access-token)
#                        or the run fails — gh-63's acceptance criterion,
#                        checked BEFORE the agent. With SOURCE_GITHUB_TOKEN
#                        unset it degrades to a ::warning:: instead
#                        (review thread 16: review runs that never push
#                        were fully viable on the github.token fallback and
#                        must not die here — pushes fail on their own at the
#                        persist step).
#
# --post-agent mode (memory-persist step, the last push path): re-asserts
# the extraheader emptiness and --show-origins the config so the run log
# answers WHICH source re-armed it mid-run (ticket Task 1). MUST run BEFORE
# the installer re-invocation — the installer purges the extraheader as its
# step 1, so running it first destroys the evidence and turns this gate
# into dead code (review thread 15).
#
# Every dump of the extraheader VALUE is redacted (review threads 11/12):
# the value is AUTHORIZATION: basic <base64(App token)> — decodable and
# NOT masked by GitHub's log masking (which matches the raw token string
# only). git 2.x prints "<origin>\t<value>" (--show-origin --get-all has
# NO key= prefix), so the sed redacts everything after the first TAB —
# a sed on '=' alone would only trim the base64 padding. The origin
# (file/scope) stays visible; a tab-less line is fully redacted.
set -euo pipefail

mode=full
if [ "${1:-}" = "--post-agent" ]; then
  mode=post-agent
fi

mkdir -p .dmtools

if [ "$mode" = post-agent ]; then
  echo "── post-agent extraheader trace (must be empty) ──"
  git config --show-origin --get-all http.https://github.com/.extraheader | sed -E 's/^([^\t]*\t).*/\1<redacted>/; t; s/.+/<redacted> (unexpected line without origin)/' || true
  if git config --get-all http.https://github.com/.extraheader | grep -q .; then
    echo "::error::App-token extraheader reappeared after the agent session — a mid-run re-assertion would push as github-actions[bot]"
    exit 1
  fi
  exit 0
fi

echo "── credential.helper — all scopes, with origins ──"
git config --show-origin --get-all credential.helper || true
git config --show-origin --get-all credential.https://github.com.helper || true
echo "── http.https://github.com/.extraheader (must be empty — App token purged) ──"
git config --show-origin --get-all http.https://github.com/.extraheader | sed -E 's/^([^\t]*\t).*/\1<redacted>/; t; s/.+/<redacted> (unexpected line without origin)/' || true
if git config --get-all http.https://github.com/.extraheader | grep -q .; then
  echo "::error::App-token extraheader still present after purge — pushes would authenticate as github-actions[bot]"
  exit 1
fi
echo "── submodule extraheaders (must be empty — App token purged there too) ──"
# checkout arms every submodule's local config with the same token; a push
# made from inside agents/ must not fall back to it (gh-63). The probe
# echoes a LEFTOVER marker line only when a config is still armed, so "no
# submodules" and "all clean" stay quiet. The marker names the submodule
# but NEVER the header value (threads 11/12).
sub_leftovers="$(git submodule foreach --quiet --recursive \
  'c="$(git config --get-all http.https://github.com/.extraheader || true)"; [ -z "$c" ] || echo "LEFTOVER ${sm_path}: <redacted>"' \
  || true)"
if [ -n "$sub_leftovers" ]; then
  echo "::error::App-token extraheader still present in a submodule config after purge — pushes from inside the submodule would authenticate as github-actions[bot]"
  printf '%s\n' "$sub_leftovers"
  exit 1
fi
echo "── commit identity ──"
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
echo "── dry-run: credential a github.com push would use ──"
# Capture first, then branch: with GIT_ASKPASS=echo `git credential fill`
# exits 0 even when NO helper answered (echo prints its prompt back, git
# accepts it as a bogus credential) — only the SOURCE helper's username
# proves the SOURCE credential wins (review thread 9). CRED_HELPER_CONTEXT
# tags the helper's log line so this dry-run stays distinguishable from
# real pushes in the evidence log (review thread 3).
out="$(printf 'protocol=https\nhost=github.com\n' | CRED_HELPER_CONTEXT=trace-dry-run GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git credential fill 2>&1)" || true
if [ -z "${SOURCE_GITHUB_TOKEN:-}" ]; then
  # No PAT configured: this run may still be fully viable — review runs
  # post their comments with the github.token fallback (review thread 16).
  # The App token is gone either way (persist-credentials: false + the
  # purge gates above), so a push can only FAIL — never fall back to the
  # bot identity. Degrade to a warning; keep the hard gate below for runs
  # where the secret IS configured.
  echo "::warning::SOURCE_GITHUB_TOKEN not set — skipping the dry-run gate; pushes will fail (no App token is persisted, gh-63)"
  printf '%s\n' "$out" | sed -E 's/^password=.+/password=<redacted — no SOURCE_GITHUB_TOKEN configured>/' || true
elif printf '%s\n' "$out" | grep -q '^username=x-access-token$'; then
  echo "$out" | sed -E 's/^password=.+/password=<redacted — served by the SOURCE_GITHUB_TOKEN helper>/'
else
  echo "::error::dry-run credential was NOT served by the SOURCE_GITHUB_TOKEN helper — a github.com push would not authenticate as the SOURCE account"
  printf '%s\n' "$out" | sed -E 's/^password=.+/password=<redacted>/'
  exit 1
fi
