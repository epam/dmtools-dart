#!/usr/bin/env bash
# machine-kit/setup.sh — install the dark-factory merge loop into a repo.
#
# The "machine" (ported from dm.ai via dmtools-dart):
#   PR → required checks green → Jira label pr_approved → auto-merge.
# Pieces: gate workflow (repo-specific) + auto-update-prs.yml +
# merge-trigger.yml + agents/ submodule + branch protection +
# MERGE_TRIGGER_ENABLED fuse.
#
# Usage (two phases — workflows land via PR, protection applies after merge):
#   setup.sh workflows <target-repo-dir> [--gate-workflow NAME]
#            [--install-repo OWNER/REPO] [--checks "a,b"] [--no-submodule]
#       Renders templates into .github/workflows/, adds the agents/ submodule,
#       pushes branch machine/merge-loop, opens a PR.
#       [--checks] here only pre-registers what `protect` will require.
#
#   setup.sh protect <owner/repo> [--checks "a,b"] [--enable-fuse]
#       AFTER the PR merges: sets branch protection (required checks, strict,
#       enforce-admins, no review requirement) and optionally flips
#       MERGE_TRIGGER_ENABLED=true. Warns about missing secrets/vars.
#
# Examples:
#   setup.sh workflows ~/git/fa --gate-workflow CI --checks "Quality gates"
#   setup.sh protect IstiN/flutter_agent_harness --checks "Quality gates" --enable-fuse
set -euo pipefail

AGENTS_SUBMODULE_REF="bdfa5f4" # dmtools-agents main pin (suite 917/917)
DEFAULT_INSTALL_REPO="epam/dmtools-dart"
BRANCH="machine/merge-loop"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 not found in PATH"; }

render() { # render <src> <dst> <name-val>...
  local src="$1" dst="$2"; shift 2
  sed -e "s|@@GATE_WORKFLOW_NAME@@|${GATE_WORKFLOW_NAME}|g" \
      -e "s|@@DMTOOLS_INSTALL_REPO@@|${DMTOOLS_INSTALL_REPO}|g" \
      "$src" >"$dst"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  workflows) ;;
  protect) ;;
  *) die "usage: setup.sh {workflows|protect} ...";;
esac

need git; need gh

# ---------------------------------------------------------------- workflows
if [ "$cmd" = "workflows" ]; then
  REPO_DIR="${1:?target repo dir required}"; shift || true
  GATE_WORKFLOW_NAME="Quality"
  DMTOOLS_INSTALL_REPO="$DEFAULT_INSTALL_REPO"
  CHECKS=""
  ADD_SUBMODULE=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --gate-workflow) GATE_WORKFLOW_NAME="$2"; shift 2;;
      --install-repo)  DMTOOLS_INSTALL_REPO="$2"; shift 2;;
      --checks)        CHECKS="$2"; shift 2;;
      --no-submodule)  ADD_SUBMODULE=0; shift;;
      *) die "unknown flag: $1";;
    esac
  done
  [ -d "$REPO_DIR/.git" ] || die "$REPO_DIR is not a git repo"
  cd "$REPO_DIR"
  ORIGIN_URL=$(git remote get-url origin)
  SLUG=$(echo "$ORIGIN_URL" | sed -E 's#.*(github.com[:/])##; s#\.git$##')
  gh api "repos/$SLUG" --jq .permissions.admin >/dev/null 2>&1 \
    || gh repo view "$SLUG" --json viewerPermission \
       --jq 'select(.viewerPermission=="ADMIN")' >/dev/null \
    || die "no admin on $SLUG — branch protection setup will fail"
  git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
  mkdir -p .github/workflows
  HERE="$(cd "$(dirname "$0")" && pwd)"
  render "$HERE/templates/merge-trigger.yml"   .github/workflows/merge-trigger.yml
  render "$HERE/templates/auto-update-prs.yml" .github/workflows/auto-update-prs.yml
  if [ "$ADD_SUBMODULE" = "1" ] && [ ! -d "agents" ]; then
    git submodule add https://github.com/IstiN/dmtools-agents agents
    git config -f .gitmodules submodule.agents.branch main
    ( cd agents && git checkout "$AGENTS_SUBMODULE_REF" )
  fi
  git add .github/workflows/merge-trigger.yml .github/workflows/auto-update-prs.yml
  [ "$ADD_SUBMODULE" = "1" ] && git add agents .gitmodules 2>/dev/null || true
  git commit -m "ci(machine): wire the dark-factory merge loop

- merge-trigger.yml: on green @@GATE_WORKFLOW_NAME@@ runs agents/sm_merge.json
  (Jira pr_approved label → merge configs); fused via MERGE_TRIGGER_ENABLED
- auto-update-prs.yml: keeps open PR branches current (strict up-to-date)
- agents/ submodule pinned at ${AGENTS_SUBMODULE_REF}

Rendered by machine-kit/setup.sh (gate workflow: ${GATE_WORKFLOW_NAME},
dmtools CLI: ${DMTOOLS_INSTALL_REPO})." >/dev/null
  git push -u origin "$BRANCH"
  gh pr create --title "ci(machine): dark-factory merge loop (merge-trigger + auto-update)" \
    --body "Installed by dmtools-dart \`machine-kit/setup.sh\`.

- gate workflow: **${GATE_WORKFLOW_NAME}**
- required checks registered for \`protect\` phase: ${CHECKS:-<set via protect>}
- agents submodule: IstiN/dmtools-agents @ ${AGENTS_SUBMODULE_REF}

After merge run:
\`\`\`
setup.sh protect ${SLUG} ${CHECKS:+--checks \"$CHECKS\"} --enable-fuse
\`\`\`
Prerequisites (secrets/vars): JIRA_EMAIL, JIRA_BASE_PATH (vars),
JIRA_API_TOKEN, SOURCE_GITHUB_TOKEN (secrets), MERGE_TRIGGER_ENABLED (set by protect)."
  echo "done: PR opened on $SLUG — merge it, then run the protect phase"
  exit 0
fi

# ------------------------------------------------------------------ protect
REPO_SLUG="${1:?owner/repo required}"; shift || true
CHECKS=""
ENABLE_FUSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --checks) CHECKS="$2"; shift 2;;
    --enable-fuse) ENABLE_FUSE=1; shift;;
    *) die "unknown flag: $1";;
  esac
done
[ -n "$CHECKS" ] || die "--checks \"name[,name…]\" required (exact job names)"

CONTEXTS=$(python3 - "$CHECKS" <<'PY'
import json,sys
print(json.dumps([c.strip() for c in sys.argv[1].split(',') if c.strip()]))
PY
)
gh api -X PUT "repos/$REPO_SLUG/branches/main/protection" --input - >/dev/null <<EOF
{
  "required_status_checks": {"strict": true, "contexts": $CONTEXTS},
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
echo "branch protection: main ← required [$CHECKS], strict, enforce-admins"

for v in JIRA_EMAIL JIRA_BASE_PATH; do
  gh api "repos/$REPO_SLUG/actions/variables/$v" --jq .name >/dev/null 2>&1 \
    || echo "MISSING var: $v (gh variable set $v -b <value> -R $REPO_SLUG)"
done
for s in JIRA_API_TOKEN SOURCE_GITHUB_TOKEN; do
  gh secret list -R "$REPO_SLUG" --jq '.[].name' | grep -qx "$s" \
    || echo "MISSING secret: $s (gh secret set $s -R $REPO_SLUG)"
done
if [ "$ENABLE_FUSE" = "1" ]; then
  gh api -X PATCH "repos/$REPO_SLUG/actions/variables/MERGE_TRIGGER_ENABLED" \
    -f value=true >/dev/null 2>&1 \
  || gh api -X POST "repos/$REPO_SLUG/actions/variables" \
    -f name=MERGE_TRIGGER_ENABLED -f value=true >/dev/null
  echo "fuse: MERGE_TRIGGER_ENABLED=true"
fi
echo "done: machine is live on $REPO_SLUG"
