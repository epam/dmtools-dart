#!/usr/bin/env bash
# machine-kit/teammate-install/install.sh — provision the Dart orchestrator
# stack: the dmtools-dart CLI (epam/dmtools-dart releases) + the fa agent
# (IstiN/flutter_agent_harness releases).
#
# Runs as the single cliCommand of machine-kit/teammate-install/install-
# dmtools-fa.json (CliAgent). Configuration comes from the sibling
# dmtools.env (git-ignored — fill it from dmtools.env.example); every
# variable is optional with a sane default.
#
# Idempotent: already-installed components are detected and skipped.
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Config: sibling dmtools.env wins, real environment still beats it ────────
if [ -f "${HERE}/dmtools.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${HERE}/dmtools.env"; set +a
fi

DMTOOLS_DART_VERSION="${DMTOOLS_DART_VERSION:-latest}"
DMTOOLS_DART_INSTALL_DIR="${DMTOOLS_DART_INSTALL_DIR:-${HOME}/.dmtools-dart}"
FA_VERSION="${FA_VERSION:-latest}"
FA_INSTALL_DIR="${FA_INSTALL_DIR:-${HOME}/.local/bin}"
FA_LIB_DIR="$(dirname "${FA_INSTALL_DIR}")/lib"
DART_INSTALL_SH="https://github.com/epam/dmtools-dart/releases/latest/download/install.sh"
FA_REPO="IstiN/flutter_agent_harness"

log()  { echo "[install] $*"; }
fail() { echo "[install] ERROR: $*" >&2; exit 1; }

# ── 1. dmtools-dart CLI ───────────────────────────────────────────────────────
install_dmtools_dart() {
  if [ -x "${DMTOOLS_DART_INSTALL_DIR}/bin/dmtools" ]; then
    log "dmtools-dart already installed: $("${DMTOOLS_DART_INSTALL_DIR}/bin/dmtools" --version 2>/dev/null || echo 'unknown version')"
    return 0
  fi
  log "installing dmtools-dart (${DMTOOLS_DART_VERSION}) → ${DMTOOLS_DART_INSTALL_DIR}"
  export DMTOOLS_INSTALL_DIR="${DMTOOLS_DART_INSTALL_DIR}"
  export DMTOOLS_VERSION="${DMTOOLS_DART_VERSION}"
  if [ "${DMTOOLS_VERSION}" != "latest" ]; then
    curl -fsSL "${DART_INSTALL_SH}" | sh -s -- "${DMTOOLS_VERSION}"
  else
    curl -fsSL "${DART_INSTALL_SH}" | sh
  fi
  [ -x "${DMTOOLS_DART_INSTALL_DIR}/bin/dmtools" ] \
    || fail "dmtools-dart binary not found after install (${DMTOOLS_DART_INSTALL_DIR}/bin/dmtools)"
  log "dmtools-dart installed: $("${DMTOOLS_DART_INSTALL_DIR}/bin/dmtools" --version 2>/dev/null || echo 'version n/a')"
}

# ── 2. fa CLI ─────────────────────────────────────────────────────────────────
install_fa() {
  if [ -x "${FA_INSTALL_DIR}/fa" ]; then
    log "fa already installed: $("${FA_INSTALL_DIR}/fa" --version 2>/dev/null || echo 'unknown version')"
    return 0
  fi
  local os arch asset url tmp
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    Linux)  os="linux" ;;
    *) fail "unsupported OS ($(uname -s)) for the fa release bundle" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64)        arch="x64" ;;
    *) fail "unsupported arch ($(uname -m))" ;;
  esac
  asset="fa-${os}-${arch}.tar.gz"
  url="https://github.com/${FA_REPO}/releases/latest/download/${asset}"
  [ "${FA_VERSION}" != "latest" ] && \
    url="https://github.com/${FA_REPO}/releases/${FA_VERSION}/download/${asset}"

  log "installing fa (${FA_VERSION}) → ${FA_INSTALL_DIR}"
  tmp="$(mktemp -d)"
  curl -fsSL "${url}" -o "${tmp}/${asset}" \
    || fail "fa release bundle download failed (${url})"
  tar -xzf "${tmp}/${asset}" -C "${tmp}"
  mkdir -p "${FA_INSTALL_DIR}" "${FA_LIB_DIR}"
  cp "${tmp}/bundle/bin/fa" "${FA_INSTALL_DIR}/fa"
  chmod +x "${FA_INSTALL_DIR}/fa"
  # Shared libs load from ../lib relative to the binary (release-bundle layout).
  [ -d "${tmp}/bundle/lib" ] && cp -R "${tmp}/bundle/lib/." "${FA_LIB_DIR}/"
  rm -rf "${tmp}"
  [ -x "${FA_INSTALL_DIR}/fa" ] || fail "fa binary not found after install"
  log "fa installed: $("${FA_INSTALL_DIR}/fa" --version 2>/dev/null || echo 'version n/a')"
}

# ── 3. Verify the fa provider env declaration (fail fast, before first run) ──
verify_fa_env() {
  if [ -z "${FA_PROVIDER_TYPE:-}" ]; then
    log "WARN: FA_PROVIDER_TYPE not set — fa will not be able to boot a provider until dmtools.env declares it"
    return 0
  fi
  if [ -z "${FA_PROVIDER_CONFIG:-}" ]; then
    fail "FA_PROVIDER_TYPE is set but FA_PROVIDER_CONFIG is missing — declare {\"baseUrl\",\"model\",\"apiKeyEnvVar\"} in dmtools.env"
  fi
  log "fa provider preconfig: ${FA_PROVIDER_TYPE} ${FA_PROVIDER_CONFIG}"
}

install_dmtools_dart
install_fa
verify_fa_env

log "done: dmtools-dart (${DMTOOLS_DART_INSTALL_DIR}/bin) + fa (${FA_INSTALL_DIR})"
echo 'NOTE: add both bin dirs to PATH to use the CLIs interactively:'
echo "      export PATH=\"${DMTOOLS_DART_INSTALL_DIR}/bin:${FA_INSTALL_DIR}:\$PATH\""
