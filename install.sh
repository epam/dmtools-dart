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
# The repository is private, so downloads need a token with repo read
# access:
#   export DMTOOLS_GITHUB_TOKEN=ghp_...
#
# Environment overrides:
#   DMTOOLS_INSTALL_DIR   installation root (default: ~/.dmtools)
#   DMTOOLS_VERSION       version to install (default: latest release)
#   DMTOOLS_GITHUB_TOKEN  token for GitHub API/download auth (private repo)
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
  *)
    err "unsupported OS: $(uname -s). This installer covers Linux and macOS;"
    err "Windows users should build from source: make build (MinGW-w64)."
    exit 1
    ;;
esac

arch=""
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *)
    err "unsupported architecture: $(uname -m)."
    err "Prebuilt binaries: linux-x64, macos-x64, macos-arm64."
    exit 1
    ;;
esac

# linux-arm64 has no prebuilt asset yet (no ARM builder for a private repo).
if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
  err "no prebuilt binary for linux-arm64 yet — build from source:"
  err "  dart pub get && make native && dart compile exe bin/dmtools.dart -o dmtools"
  exit 1
fi

asset="dmtools-${os}-${arch}.tar.gz"

# ── 2. Resolve version ──────────────────────────────────────────────────────
# DMTOOLS_DOWNLOAD_BASE overrides the artifact root (default: GitHub Releases)
# — used by mirrors and by the installer's own tests.
version="${1:-${DMTOOLS_VERSION:-}}"
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
fetch() {
  # fetch <url> <output-file> — curl or wget, with optional bearer auth.
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
      curl -fSL --progress-bar -H "Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
        "$1" -o "$2"
    else
      curl -fSL --progress-bar "$1" -o "$2"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
      wget --progress=bar -q --header="Authorization: Bearer ${DMTOOLS_GITHUB_TOKEN}" \
        -O "$2" "$1"
    else
      wget --progress=bar -q -O "$2" "$1"
    fi
  else
    err "neither curl nor wget is available."
    exit 1
  fi
}

# ── 4. Download and verify the archive ──────────────────────────────────────
tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t dmtools-install)"
trap 'rm -rf "$tmpdir"' EXIT

info "Downloading dmtools for ${os}-${arch} (${display_version})..."
archive="$tmpdir/$asset"
if ! fetch "$download_base/$asset" "$archive"; then
  err "download failed: $download_base/$asset"
  if [ -z "${DMTOOLS_GITHUB_TOKEN:-}" ]; then
    err "the repository is private — export DMTOOLS_GITHUB_TOKEN with read"
    err "access to ${REPO} and retry."
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
# The AOT binary resolves libquickjs_bridge.so at
# <exe-dir>/native/quickjs/libquickjs_bridge.so (or JSR_QUICKJS_LIB), so the
# archive layout — dmtools + native/quickjs/… — is copied verbatim into the
# bin directory.
install_root="${DMTOOLS_INSTALL_DIR:-$HOME/.dmtools}"
install_bin="$install_root/bin"
mkdir -p "$install_bin"

mkdir -p "$tmpdir/extract"
tar -xzf "$archive" -C "$tmpdir/extract"

src="$tmpdir/extract/dmtools"
if [ ! -f "$src/$BINARY" ] || [ ! -f "$src/native/quickjs/libquickjs_bridge.so" ]; then
  err "archive is missing expected layout (dmtools/ + dmtools/native/quickjs/):"
  err "$(tar -tzf "$archive" | head -n 10)"
  exit 1
fi

rm -rf "$install_bin/native"
cp "$src/$BINARY" "$install_bin/$BINARY"
chmod +x "$install_bin/$BINARY"
mkdir -p "$install_bin/native/quickjs"
cp "$src/native/quickjs/libquickjs_bridge.so" \
  "$install_bin/native/quickjs/libquickjs_bridge.so"

# Record the installed version for idempotency/debugging.
printf '%s\n' "$display_version" > "$install_root/version.txt"

ok "Installed $install_bin/$BINARY"

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
if "$install_bin/$BINARY" --version >/dev/null 2>&1; then
  ok "$("$install_bin/$BINARY" --version)"
else
  warn "installed binary failed to start; try setting JSR_QUICKJS_LIB to"
  warn "$install_bin/native/quickjs/libquickjs_bridge.so"
fi

printf '\n'
ok "Installation complete. Try:"
printf '\n  dmtools list\n  dmtools doctor\n\n'
