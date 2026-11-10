#!/bin/sh
# install.sh — one-line installer for the dmtools CLI (Dart port).
#
#   curl -fsSL "https://github.com/epam/dmtools-dart/releases/latest/download/install.sh" | sh
#
# What it does:
#   1. Detects OS and architecture.
#   2. Downloads the matching dmtools bundle from a GitHub Release
#      (AOT-compiled binary + the QuickJS shared library it loads).
#   3. Installs both under ~/.dmtools/bin and ensures it is on PATH.
#
# Install a specific version:
#   ... | sh -s -- v0.1.0          (or:  sh install.sh 0.1.0)
#   ... | DMTOOLS_VERSION=v0.1.0 sh
#
# The repository is public — no token needed. DMTOOLS_GITHUB_TOKEN is
# still honored (optional) for API rate limits or private forks:
#   export DMTOOLS_GITHUB_TOKEN=ghp_...
#
# Environment overrides:
#   DMTOOLS_INSTALL_DIR   installation root (default: ~/.dmtools)
#   DMTOOLS_VERSION       version to install (default: latest release)
#   DMTOOLS_GITHUB_TOKEN  optional auth token (rate limits / private forks)
#
# POSIX sh only (dash-safe): no [[ ]], arrays, or pipefail.

set -eu

REPO="epam/dmtools-dart"
BINARY="dmtools"

# ── Output helpers ──────────────────────────────────────────────────────────
info() { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m✘\033[0m %s\n' "$*" >&2; }

# ── 1. Detect OS/arch ───────────────────────────────────────────────────────
os=""
case "$(uname -s)" in
  Linux*) os=linux ;;
  Darwin*) os=macos ;;
  MINGW* | MSYS* | CYGWIN* | *_NT-*) os=windows ;;
  *)
    err "unsupported OS: $(uname -s). This installer covers Linux, macOS and"
    err "Windows (Git Bash)."
    exit 1
    ;;
esac

arch=""
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *)
    err "unsupported architecture: $(uname -m)."
    err "Prebuilt binaries: linux-x64, macos-x64, macos-arm64, windows-x64."
    exit 1
    ;;
esac

# Windows ships as a zip (Compress-Archive) — same bundle layout inside.
if [ "$os" = "windows" ]; then
  if [ "$arch" != "x64" ]; then
    err "no prebuilt Windows bundle for ${arch}; only windows-x64 exists."
    exit 1
  fi
  asset="dmtools-${os}-${arch}.zip"
else
  asset="dmtools-${os}-${arch}.tar.gz"
fi

# ── 2. Parse CLI arguments & skill selection (dm.ai#675 parity) ─────────────
AVAILABLE_SKILLS_CSV="dmtools,jira,confluence,github,gitlab,figma,teams,sharepoint,ado,testrail,xray"
ALWAYS_ON_INTEGRATIONS="ai,cli,file,kb,mermaid"
skills_arg=""
skills_was_set=0
all_skills_flag=0
no_skill_files=0
skip_unknown_skills=0
prune_skills=0
strict_mode=0
version_arg=""

case "$(printf '%s' "${DMTOOLS_STRICT_INSTALL:-false}" | tr '[:upper:]' '[:lower:]')" in
  "" | false | 0 | no | off) strict_mode=0 ;;
  true | 1 | yes | on) strict_mode=1 ;;
  *)
    err "Invalid DMTOOLS_STRICT_INSTALL value: ${DMTOOLS_STRICT_INSTALL}. Use true or false."
    exit 1
    ;;
esac

append_skill_arg() {
  val="$(printf '%s' "$1" | sed "s/^[[:space:]\"']*//;s/[[:space:]\"']*$//")"
  [ -n "$val" ] || return 0
  if [ -n "$skills_arg" ]; then
    skills_arg="${skills_arg},${val}"
  else
    skills_arg="$val"
  fi
  skills_was_set=1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-skills)
      no_skill_files=1
      shift
      ;;
    --global | --global-only | --global-skills | --no-local-skills)
      # Skills are always installed globally into user-level agent directories;
      # accept these flags explicitly for CLI parity with dm.ai install.sh.
      shift
      ;;
    --skill)
      if [ $# -lt 2 ]; then
        err "Missing value for --skill. Use --skill jira"
        exit 1
      fi
      append_skill_arg "$2"
      shift 2
      ;;
    --skill=*)
      append_skill_arg "${1#--skill=}"
      shift
      ;;
    --skills)
      if [ $# -lt 2 ]; then
        err "Missing value for --skills. Use --skills=jira,github or --skills jira,github"
        exit 1
      fi
      append_skill_arg "$2"
      shift 2
      ;;
    --skills=*)
      append_skill_arg "${1#--skills=}"
      shift
      ;;
    --all-skills)
      all_skills_flag=1
      shift
      ;;
    --skip-unknown)
      skip_unknown_skills=1
      shift
      ;;
    --prune)
      prune_skills=1
      shift
      ;;
    --strict)
      strict_mode=1
      shift
      ;;
    --help | -h)
      echo "Usage: install.sh [--skill <name>] [--skills=<name,name>] [--all-skills] [--no-skills] [--global] [--prune] [--skip-unknown] [--strict] [version]"
      echo "  --skill <name>      Select a single skill. Repeat to add more skills."
      echo "  --skills=<csv>      Comma-separated skill selection (${AVAILABLE_SKILLS_CSV})."
      echo "  --all-skills        Install every supported skill."
      echo "  --no-skills         Do not install skill files into agent directories (~/.claude, ...)"
      echo "  --prune             Remove unselected DMTools skills from agent directories."
      echo "  --skip-unknown      Warn and continue when unknown skill names are supplied."
      echo "  --strict            Legacy alias for strict invalid-skill handling."
      echo "  version             Optional DMTools version (vX.Y.Z or X.Y.Z)."
      exit 0
      ;;
    --*)
      err "Unknown installer option: $1"
      exit 1
      ;;
    *)
      if [ -n "$version_arg" ]; then
        err "Only one version argument is supported. Received: $version_arg $1"
        exit 1
      fi
      version_arg="$1"
      shift
      ;;
  esac
done

is_known_skill() {
  case "$1" in
    dmtools | jira | confluence | github | gitlab | figma | teams | sharepoint | ado | testrail | xray)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

csv_contains() {
  case ",$1," in
    *,"$2",*) return 0 ;;
    *) return 1 ;;
  esac
}

csv_append_unique() {
  if [ -z "$1" ]; then
    printf '%s' "$2"
  elif csv_contains "$1" "$2"; then
    printf '%s' "$1"
  else
    printf '%s,%s' "$1" "$2"
  fi
}

skills_source="default"
raw_skills="all"
if [ "$all_skills_flag" -eq 1 ]; then
  raw_skills="all"
  skills_source="cli"
elif [ "$skills_was_set" -eq 1 ]; then
  raw_skills="$skills_arg"
  skills_source="cli"
elif [ "${DMTOOLS_SKILLS+x}" = "x" ]; then
  raw_skills="${DMTOOLS_SKILLS:-}"
  skills_source="env"
fi

normalized_raw="$(printf '%s' "$raw_skills" | sed "s/^[[:space:]\"']*//;s/[[:space:]\"']*$//" | tr '[:upper:]' '[:lower:]')"
compact_raw="$(printf '%s' "$normalized_raw" | tr -d ',[:space:]')"
install_all_skills=0
effective_skills_csv=""
invalid_skills_csv=""

if [ -z "$compact_raw" ] || [ "$normalized_raw" = "all" ]; then
  install_all_skills=1
else
  saw_all=0
  old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $raw_skills
  IFS="$old_ifs"
  for tok in "$@"; do
    tok="$(printf '%s' "$tok" | sed "s/^[[:space:]\"']*//;s/[[:space:]\"']*$//" | tr '[:upper:]' '[:lower:]')"
    [ -n "$tok" ] || continue
    [ "$tok" = "jira_xray" ] && tok="xray"
    if [ "$tok" = "all" ]; then
      saw_all=1
      continue
    fi
    if is_known_skill "$tok"; then
      effective_skills_csv="$(csv_append_unique "$effective_skills_csv" "$tok")"
    else
      invalid_skills_csv="$(csv_append_unique "$invalid_skills_csv" "$tok")"
    fi
  done
  [ "$saw_all" -eq 1 ] && install_all_skills=1
fi

if [ "$install_all_skills" -eq 1 ]; then
  effective_skills_csv="$AVAILABLE_SKILLS_CSV"
fi

if [ -n "$invalid_skills_csv" ] && [ "$skills_source" != "cli" ] && [ "$skip_unknown_skills" -ne 1 ]; then
  warn "Skipping unknown skills: $invalid_skills_csv"
fi

if [ -z "$effective_skills_csv" ]; then
  err "No valid skills selected. Unknown skills: ${invalid_skills_csv:-none}. Allowed skills: $AVAILABLE_SKILLS_CSV"
  exit 1
fi

if [ -n "$invalid_skills_csv" ]; then
  if [ "$skip_unknown_skills" -eq 1 ]; then
    warn "Skipping unknown skills: $invalid_skills_csv"
  elif [ "$strict_mode" -eq 1 ]; then
    err "Unknown skills are not allowed in strict mode: $invalid_skills_csv. Allowed skills: $AVAILABLE_SKILLS_CSV"
    exit 1
  elif [ "$skills_source" = "cli" ]; then
    err "Unknown skills: $invalid_skills_csv. Use --skip-unknown to continue."
    exit 1
  fi
fi

effective_integrations_csv="$ALWAYS_ON_INTEGRATIONS"
old_ifs="$IFS"
IFS=','
# shellcheck disable=SC2086
set -- $effective_skills_csv
IFS="$old_ifs"
for sk in "$@"; do
  case "$sk" in
    jira | confluence | github | gitlab | figma | ado | testrail)
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "$sk")"
      ;;
    teams)
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "teams")"
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "teams_auth")"
      ;;
    sharepoint)
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "sharepoint")"
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "teams_auth")"
      ;;
    xray)
      effective_integrations_csv="$(csv_append_unique "$effective_integrations_csv" "jira_xray")"
      ;;
  esac
done

info "Effective skills: $effective_skills_csv (source: $skills_source)"
info "Effective integrations: $effective_integrations_csv"

# DMTOOLS_DOWNLOAD_BASE overrides the artifact root (default: GitHub Releases)
# — used by mirrors and by the installer's own tests.
version="${version_arg:-${DMTOOLS_VERSION:-}}"
if [ -n "$version" ]; then
  case "$version" in
    v*) ;;
    *) version="v$version" ;;
  esac
  # Tagged download URL: releases/download/vX.Y.Z/<asset>
  download_base="${DMTOOLS_DOWNLOAD_BASE:-https://github.com/${REPO}/releases/download/${version}}"
  display_version="$version"
else
  # Latest: GitHub's redirect endpoint needs no tag lookup.
  download_base="${DMTOOLS_DOWNLOAD_BASE:-https://github.com/${REPO}/releases/latest/download}"
  display_version="latest"
fi
# ── 3. Optional auth (private repo) ─────────────────────────────────────────
fetch_direct() {
  # fetch_direct <url> <output-file> — curl or wget with bounded timeouts/retries.
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
      curl -fSL --connect-timeout 15 --max-time 60 --retry 2 --retry-delay 2 \
        --progress-bar -H "Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
        "$1" -o "$2"
    else
      curl -fSL --connect-timeout 15 --max-time 60 --retry 2 --retry-delay 2 \
        --progress-bar "$1" -o "$2"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
      wget --timeout=30 --tries=3 --progress=bar -q \
        --header="Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
        -O "$2" "$1"
    else
      wget --timeout=30 --tries=3 --progress=bar -q -O "$2" "$1"
    fi
  else
    err "neither curl nor wget is available."
    exit 1
  fi
}

fetch_gh_api_asset() {
  # Fallback when GitHub browser_download_url returns 502/503/504 edge errors:
  # resolves the asset id via the GitHub Releases REST API and downloads with
  # Accept: application/octet-stream (or `gh release download` when available).
  api_repo="$1"
  api_tag="$2"
  api_asset="$3"
  api_out="$4"
  if command -v gh >/dev/null 2>&1; then
    gh_dir="$(dirname "$api_out")"
    if [ "$api_tag" = "latest" ]; then
      if gh release download --repo "$api_repo" --pattern "$api_asset" --dir "$gh_dir" --clobber >/dev/null 2>&1 &&
        [ -s "$gh_dir/$api_asset" ]; then
        [ "$gh_dir/$api_asset" = "$api_out" ] || mv "$gh_dir/$api_asset" "$api_out"
        return 0
      fi
    else
      if gh release download "$api_tag" --repo "$api_repo" --pattern "$api_asset" --dir "$gh_dir" --clobber >/dev/null 2>&1 &&
        [ -s "$gh_dir/$api_asset" ]; then
        [ "$gh_dir/$api_asset" = "$api_out" ] || mv "$gh_dir/$api_asset" "$api_out"
        return 0
      fi
    fi
  fi
  command -v curl >/dev/null 2>&1 || return 1
  if [ "$api_tag" = "latest" ]; then
    rel_ep="https://api.github.com/repos/${api_repo}/releases/latest"
  else
    rel_ep="https://api.github.com/repos/${api_repo}/releases/tags/${api_tag}"
  fi
  rel_json="$tmpdir/release_meta_$$.json"
  if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
    curl -fsSL --connect-timeout 15 --max-time 30 \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
      "$rel_ep" -o "$rel_json" 2>/dev/null || return 1
  else
    curl -fsSL --connect-timeout 15 --max-time 30 \
      -H "Accept: application/vnd.github+json" \
      "$rel_ep" -o "$rel_json" 2>/dev/null || return 1
  fi
  asset_api_url="$(tr '\n' ' ' < "$rel_json" | sed 's/{"url":/\n{"url":/g' | grep "\"name\"[[:space:]]*:[[:space:]]*\"${api_asset}\"" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\/releases\/assets\/[0-9]*\)".*/\1/p' | head -n 1)"
  rm -f "$rel_json"
  [ -n "$asset_api_url" ] || return 1
  if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
    curl -fsSL --connect-timeout 15 --max-time 60 --retry 2 --retry-delay 2 \
      -H "Accept: application/octet-stream" \
      -H "Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
      "$asset_api_url" -o "$api_out"
  else
    curl -fsSL --connect-timeout 15 --max-time 60 --retry 2 --retry-delay 2 \
      -H "Accept: application/octet-stream" \
      "$asset_api_url" -o "$api_out"
  fi
}

fetch() {
  # fetch <url> <output-file> — tries direct URL first, then falls back to
  # GitHub Releases API asset download if the URL is a github.com release asset.
  if fetch_direct "$1" "$2"; then
    return 0
  fi
  case "$1" in
    https://github.com/*/*/releases/latest/download/*)
      f_rest="${1#https://github.com/}"
      f_repo="${f_rest%%/releases/latest/download/*}"
      f_asset="${1##*/}"
      warn "direct download failed ($1); falling back to GitHub Releases API for ${f_repo}@latest/${f_asset}..."
      fetch_gh_api_asset "$f_repo" "latest" "$f_asset" "$2"
      return $?
      ;;
    https://github.com/*/*/releases/download/*/*)
      f_rest="${1#https://github.com/}"
      f_repo="${f_rest%%/releases/download/*}"
      f_after="${f_rest#*/releases/download/}"
      f_tag="${f_after%%/*}"
      f_asset="${1##*/}"
      warn "direct download failed ($1); falling back to GitHub Releases API for ${f_repo}@${f_tag}/${f_asset}..."
      fetch_gh_api_asset "$f_repo" "$f_tag" "$f_asset" "$2"
      return $?
      ;;
  esac
  return 1
}

# ── 4. Download and verify the archive ──────────────────────────────────────
tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t dmtools-install)"
trap 'rm -rf "$tmpdir"' EXIT

info "Downloading dmtools for ${os}-${arch} (${display_version})..."
archive="$tmpdir/$asset"
if ! fetch "$download_base/$asset" "$archive"; then
  err "download failed: $download_base/$asset"
  if [ -z "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
    err "not authenticated — for rate limits or private forks export"
    err "DMTOOLS_GITHUB_TOKEN and retry."
  elif [ -n "$version" ]; then
    err "check that release ${version} exists and has a ${asset} asset."
  fi
  exit 1
fi

# Best-effort checksum verification (mirrors the Java dm.ai installer):
# a missing checksum file or a missing sha256 utility must not block the
# install; a mismatch is fatal.
checksums="$tmpdir/dmtools-checksums.sha256"
if fetch "$download_base/dmtools-checksums.sha256" "$checksums" 2>/dev/null &&
  [ -s "$checksums" ]; then
  expected="$(grep " ${asset}\$" "$checksums" | head -n 1 | cut -d' ' -f1)"
  if [ -n "$expected" ]; then
    actual=""
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "$archive" | cut -d' ' -f1)"
    elif command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
    fi
    if [ -n "$actual" ]; then
      if [ "$actual" != "$expected" ]; then
        err "checksum mismatch for ${asset}: expected ${expected}, got ${actual}."
        exit 1
      fi
      ok "Checksum verified."
    fi
  fi
fi

# ── 5. Install binary + QuickJS library ─────────────────────────────────────
# The AOT binary cannot reliably resolve libquickjs_bridge.so relative to
# itself (the runtime's "exe-relative" fallback uses Platform.script, which
# does not resolve to the installed executable in AOT builds), so the
# installer places the library under native/quickjs/ and a small `dmtools`
# launcher beside it that exports JSR_QUICKJS_LIB — the runtime's first
# lookup candidate. The launcher self-locates, so the install dir can be
# moved without breaking.
install_root="${DMTOOLS_INSTALL_DIR:-$HOME/.dmtools}"
install_bin="$install_root/bin"
mkdir -p "$install_bin"

mkdir -p "$tmpdir/extract"
if [ "$os" = "windows" ]; then
  # Git Bash ships no unzip; GNU tar cannot read zip archives. Expand-Archive
  # is present on every supported Windows (PowerShell 5+). The call runs from
  # a generated .ps1 file: inline -Command strings with nested quoting can
  # hang the interpreter (an unclosed quote makes it wait on stdin forever —
  # the first CI leg timed out exactly like that).
  pwsh_exe=""
  if command -v powershell >/dev/null 2>&1; then
    pwsh_exe="powershell"
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh_exe="pwsh"
  else
    err "neither powershell nor pwsh is available to extract the zip."
    exit 1
  fi
  win_archive="$(cygpath -w "$archive" 2>/dev/null || echo "$archive")"
  win_extract="$(cygpath -w "$tmpdir/extract" 2>/dev/null || echo "$tmpdir/extract")"
  cat > "$tmpdir/extract.ps1" <<PS1
\$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath '$win_archive' -DestinationPath '$win_extract' -Force
PS1
  "$pwsh_exe" -NoProfile -ExecutionPolicy Bypass -File "$tmpdir/extract.ps1"
else
  tar -xzf "$archive" -C "$tmpdir/extract"
fi

src="$tmpdir/extract/dmtools"
if [ ! -f "$src/$BINARY" ] && [ ! -f "$src/$BINARY.exe" ] ||
  [ ! -f "$src/native/quickjs/libquickjs_bridge.so" ]; then
  err "archive is missing expected layout (dmtools/ + dmtools/native/quickjs/):"
  exit 1
fi

rm -rf "$install_bin/native"
if [ "$os" = "windows" ]; then
  mkdir -p "$install_bin/native/quickjs"
  cp "$src/native/quickjs/libquickjs_bridge.so" \
    "$install_bin/native/quickjs/libquickjs_bridge.so"

  # ORDER MATTERS (msys/cygwin .exe magic): the launchers must be written
  # while no dmtools.exe exists yet. `cat > dmtools` in git-bash resolves
  # the target to the existing dmtools.exe and OVERWRITES the real binary
  # with the launcher script — exactly how the first windows CI legs ended
  # up with a 154-byte dmtools.exe and a self-exec loop. The exe copy goes
  # LAST, after every launcher write.
  cat > "$install_bin/$BINARY" <<LAUNCHER
#!/bin/sh
DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export JSR_QUICKJS_LIB="\$DIR/native/quickjs/libquickjs_bridge.so"
exec "\$DIR/dmtools.exe" "\$@"
LAUNCHER
  # Launcher for cmd.exe / PowerShell users (dm.ai installs dmtools.cmd too).
  # Single backslashes: cmd.exe does not escape backslashes — doubled ones
  # leak into JSR_QUICKJS_LIB verbatim.
  cat > "$install_bin/$BINARY.cmd" <<LAUNCHER
@echo off
set "JSR_QUICKJS_LIB=%~dp0native\quickjs\libquickjs_bridge.so"
"%~dp0dmtools.exe" %*
LAUNCHER

  # The real binary, LAST (see the ORDER MATTERS note above).
  cp "$src/$BINARY.exe" "$install_bin/$BINARY.exe"

  # Best-effort: put the install bin on the Windows USER Path so cmd/PowerShell
  # sessions see it too (the rc-file block below covers Git Bash). Runs from
  # a generated .ps1 file — inline -Command quoting can hang the interpreter.
  if command -v powershell >/dev/null 2>&1; then
    win_bin="$(cygpath -w "$install_bin" 2>/dev/null || echo "$install_bin")"
    cat > "$tmpdir/addpath.ps1" <<PS1
\$bin = '$win_bin'
\$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (\$null -eq \$p) { \$p = '' }
if (\$p -notlike ('*' + \$bin + '*')) {
  [Environment]::SetEnvironmentVariable('Path', (\$p.TrimEnd(';') + ';' + \$bin), 'User')
}
PS1
    powershell -NoProfile -ExecutionPolicy Bypass -File "$tmpdir/addpath.ps1" \
      >/dev/null 2>&1 || true
  fi
else
  cp "$src/$BINARY" "$install_bin/$BINARY.bin"
  chmod +x "$install_bin/$BINARY.bin"
  mkdir -p "$install_bin/native/quickjs"
  cp "$src/native/quickjs/libquickjs_bridge.so" \
    "$install_bin/native/quickjs/libquickjs_bridge.so"
fi

# Launcher: sets JSR_QUICKJS_LIB to the absolute library path, then execs
# the real binary. CWD-independent — works from any directory.
# POSIX launcher (Linux/macOS only — Windows got its own launchers above).
if [ "$os" != "windows" ]; then
  cat > "$install_bin/$BINARY" <<LAUNCHER
#!/bin/sh
# dmtools launcher — points the QuickJS runtime at the library installed
# beside this script (JSR_QUICKJS_LIB is the runtime's first lookup
# candidate; the exe-relative fallback cannot be relied on in AOT builds).
DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export JSR_QUICKJS_LIB="\$DIR/native/quickjs/libquickjs_bridge.so"
exec "\$DIR/dmtools.bin" "\$@"
LAUNCHER
  chmod +x "$install_bin/$BINARY"
fi

# macOS quarantine / signature hardening (as in the flutter_agent_harness
# installer): downloaded executables are tagged by Gatekeeper and killed on
# launch unless the quarantine attribute is removed; an ad-hoc re-sign
# makes the binary runnable from any directory on Apple Silicon.
if [ "$(uname -s)" = "Darwin" ]; then
  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$install_bin/$BINARY" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$install_bin/$BINARY.bin" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$install_bin/native" 2>/dev/null || true
  fi
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$install_bin/$BINARY.bin" 2>/dev/null || true
  fi
fi

# Record the installed version for idempotency/debugging.
printf '%s\n' "$display_version" > "$install_root/version.txt"

ok "Installed $install_bin/$BINARY"

# ── 5b. Persist installer skill config & metadata (dm.ai#675 parity) ────────
installer_env_path="${DMTOOLS_INSTALLER_ENV_PATH:-$install_bin/dmtools-installer.env}"
runtime_env_path="${DMTOOLS_RUNTIME_ENV_PATH:-$install_bin/dmtools-runtime.env}"
installed_skills_json_path="${DMTOOLS_INSTALLED_SKILLS_JSON_PATH:-$install_root/installed-skills.json}"
endpoints_json_path="${DMTOOLS_ENDPOINTS_JSON_PATH:-$install_root/endpoints.json}"
mkdir -p "$(dirname "$installer_env_path")" "$(dirname "$runtime_env_path")"

cat > "$installer_env_path" <<EOF
# Generated by the DMTools installer.
DMTOOLS_SKILLS="$effective_skills_csv"
DMTOOLS_INTEGRATIONS="$effective_integrations_csv"
EOF
rm -f "$runtime_env_path"

skills_json="["
endpoints_json="["
first_item=1
old_ifs="$IFS"
IFS=','
# shellcheck disable=SC2086
set -- $effective_skills_csv
IFS="$old_ifs"
for sk in "$@"; do
  if [ "$first_item" -eq 0 ]; then
    skills_json="${skills_json}, "
    endpoints_json="${endpoints_json}, "
  fi
  skills_json="${skills_json}{\"name\":\"${sk}\"}"
  endpoints_json="${endpoints_json}{\"name\":\"${sk}\",\"path\":\"/dmtools/${sk}\"}"
  first_item=0
done
skills_json="${skills_json}]"
endpoints_json="${endpoints_json}]"

integrations_json="["
first_item=1
old_ifs="$IFS"
IFS=','
# shellcheck disable=SC2086
set -- $effective_integrations_csv
IFS="$old_ifs"
for ig in "$@"; do
  if [ "$first_item" -eq 0 ]; then
    integrations_json="${integrations_json}, "
  fi
  integrations_json="${integrations_json}\"${ig}\""
  first_item=0
done
integrations_json="${integrations_json}]"

cat > "$installed_skills_json_path" <<EOF
{
  "version": "$display_version",
  "installed_skills": $skills_json,
  "integrations": $integrations_json
}
EOF

cat > "$endpoints_json_path" <<EOF
{
  "version": "$display_version",
  "endpoints": $endpoints_json
}
EOF

# ── 6. Ensure the bin directory is on PATH ──────────────────────────────────
case ":${PATH}:" in
  *":$install_bin:") ok "'$BINARY' is already on PATH." ;;
  *)
    warn "'$BINARY' is not on PATH yet. Add it with:"
    # The literal $PATH belongs in the rc file (expands at shell startup).
    # shellcheck disable=SC2016
    printf '\n  export PATH="%s:$PATH"\n\n' "$install_bin"

    shell_rc=""
    fish_rc="no"
    case "${SHELL:-}" in
      */zsh) shell_rc="$HOME/.zshrc" ;;
      */bash) shell_rc="$HOME/.bashrc" ;;
      */fish)
        shell_rc="$HOME/.config/fish/config.fish"
        fish_rc="yes"
        ;;
    esac
    if [ -n "$shell_rc" ]; then
      mkdir -p "$(dirname "$shell_rc")"
      if [ -f "$shell_rc" ] && grep -qF "$install_bin" "$shell_rc" 2>/dev/null; then
        ok "$install_bin is already referenced in $shell_rc"
      elif [ "$fish_rc" = "yes" ]; then
        printf '\n# dmtools CLI PATH\nfish_add_path -g "%s"\n' "$install_bin" >> "$shell_rc"
        ok "Added $install_bin to $shell_rc (open a new terminal, or restart fish)."
      else
        # The literal $PATH belongs in the rc file (expands at shell startup).
        # shellcheck disable=SC2016
        printf '\n# dmtools CLI PATH\nexport PATH="%s:$PATH"\n' "$install_bin" >> "$shell_rc"
        ok "Added $install_bin to $shell_rc (open a new terminal, or source it)."
      fi
    fi
    ;;
esac

# ── 7. Smoke-test the installed binary ──────────────────────────────────────
# Timeout-guarded: the first windows CI legs timed out because the smoke
# hung the whole job (10+ minutes until the job timeout killed it). A
# smoke that cannot hang beats a smoke that sometimes proves the point.
smoke_rc=0
smoke_out=""
if command -v timeout >/dev/null 2>&1; then
  smoke_out="$(timeout 30 "$install_bin/$BINARY" --version 2>&1)" || smoke_rc=$?
else
  smoke_out="$("$install_bin/$BINARY" --version 2>&1)" || smoke_rc=$?
fi
if [ "$smoke_rc" -eq 0 ] && [ -n "$smoke_out" ]; then
  ok "$smoke_out"
else
  warn "installed binary failed the smoke test (rc=$smoke_rc): $smoke_out"
  warn "try setting JSR_QUICKJS_LIB to"
  warn "$install_bin/native/quickjs/libquickjs_bridge.so"
fi

# ── 8. Install/update agent skills globally (dm.ai#675 parity) ──────────────
# Runs skill-install.sh from the canonical epam/dm.ai release (or
# DMTOOLS_SKILL_INSTALL_BASE_URL) with --global so ~/.claude, ~/.copilot, and
# ~/.agents receive the selected skills automatically. Never fatal: the CLI
# binary is already installed.
if [ "$no_skill_files" -eq 1 ] || [ "${DMTOOLS_INSTALLER_SKIP_SKILL_FILES:-false}" = "true" ]; then
  info "Skipping skill files (--no-skills)."
elif ! command -v bash >/dev/null 2>&1; then
  warn "bash is not available — skipping global agent skill installation."
else
  skill_base="${DMTOOLS_SKILL_INSTALL_BASE_URL:-https://github.com/epam/dm.ai/releases/latest/download}"
  skill_script="$install_root/skill-install.sh"
  info "Installing agent skills ($effective_skills_csv) into user-level agent directories..."
  if ! fetch "$skill_base/skill-install.sh" "$skill_script" 2>/dev/null; then
    warn "Could not download skill-install.sh from $skill_base — skills were not installed. Retry later with: curl -fsSL $skill_base/skill-install.sh | bash -s -- --global --skills=$effective_skills_csv"
  else
    chmod +x "$skill_script"
    set -- --global
    if [ "$install_all_skills" -eq 1 ]; then
      set -- "$@" --all-skills
    else
      set -- "$@" "--skills=$effective_skills_csv"
    fi
    [ "$skip_unknown_skills" -eq 1 ] && set -- "$@" --skip-unknown
    [ "$prune_skills" -eq 1 ] && set -- "$@" --prune
    mkdir -p "$HOME/.agents/skills" 2>/dev/null || true
    if ! DMTOOLS_SKILLS_GLOBAL_ONLY=true DMTOOLS_SKILL_RELEASE_BASE_URL="${DMTOOLS_SKILL_RELEASE_BASE_URL:-$skill_base}" bash "$skill_script" "$@"; then
      warn "Skill installation did not complete; the DMTools CLI itself is installed."
    fi
  fi
fi

printf '\n'
ok "Installation complete. Try:"
printf '\n  dmtools list\n  dmtools doctor\n\n'
