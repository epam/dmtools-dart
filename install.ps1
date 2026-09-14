# DMTools CLI Installation Script for Windows PowerShell (Dart port).
# Usage:  irm https://github.com/epam/dmtools-dart/releases/latest/download/install.ps1 | iex
# Pinned: $env:DMTOOLS_VERSION="v0.1.11"; irm https://raw.githubusercontent.com/epam/dmtools-dart/v0.1.11/install.ps1 | iex
#
# Mirrors the dm.ai Java installer layout: installs under
# %USERPROFILE%\.dmtools\bin, writes a dmtools.cmd launcher beside the exe
# (pinning JSR_QUICKJS_LIB at the bundled QuickJS library), and appends the
# bin dir to the user PATH.

$ErrorActionPreference = "Stop"

$REPO = "epam/dmtools-dart"
$ASSET = "dmtools-windows-x64.zip"
$INSTALL_DIR = if ($env:DMTOOLS_INSTALL_DIR) { $env:DMTOOLS_INSTALL_DIR } else { "$env:USERPROFILE\.dmtools" }
$BIN_DIR = "$INSTALL_DIR\bin"

function Write-Info { Write-Host $args -ForegroundColor Green }
function Write-Warn { Write-Host "Warning: $args" -ForegroundColor Yellow }
function Write-Error-Message { Write-Host "Error: $args" -ForegroundColor Red; exit 1 }

# ── 1. Resolve the download base ───────────────────────────────────────────
$version = $env:DMTOOLS_VERSION
if ($version) {
    if (-not $version.StartsWith("v")) { $version = "v$version" }
    $base = "https://github.com/$REPO/releases/download/$version"
    Write-Info "Installing dmtools $version"
} else {
    $base = "https://github.com/$REPO/releases/latest/download"
    Write-Info "Installing dmtools (latest release)"
}

# Optional auth (rate limits / private forks).
$headers = @{}
if ($env:DMTOOLS_GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $($env:DMTOOLS_GITHUB_TOKEN)"
}

# ── 2. Download + extract ──────────────────────────────────────────────────
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dmtools-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp $ASSET
    Write-Host "Downloading $base/$ASSET ..."
    try {
        Invoke-WebRequest -Uri "$base/$ASSET" -OutFile $zip -Headers $headers -UseBasicParsing
    } catch {
        Write-Error-Message "download failed: $($_.Exception.Message)"
    }

    # Best-effort checksum (a missing file/tool must not block the install).
    $sums = Join-Path $tmp "dmtools-checksums.sha256"
    try {
        Invoke-WebRequest -Uri "$base/dmtools-checksums.sha256" -OutFile $sums -Headers $headers -UseBasicParsing
        $expected = (Select-String -Path $sums -Pattern ([regex]::Escape($ASSET)) |
            Select-Object -First 1).Line -split ' ' | Select-Object -First 1
        if ($expected) {
            $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $expected.ToLower()) {
                Write-Error-Message "checksum mismatch for ${ASSET}: expected $expected, got $actual."
            }
            Write-Info "Checksum verified."
        }
    } catch { Write-Warn "checksum file unavailable — skipping verification." }

    $extract = Join-Path $tmp "extract"
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $src = Join-Path $extract "dmtools"
    if (-not (Test-Path (Join-Path $src "dmtools.exe")) -or
        -not (Test-Path (Join-Path $src "native\quickjs\libquickjs_bridge.so"))) {
        Write-Error-Message "archive is missing the expected layout (dmtools.exe + native\quickjs\)."
    }

    # ── 3. Install: exe + QuickJS library + cmd launcher ───────────────────
    New-Item -ItemType Directory -Path "$BIN_DIR\native\quickjs" -Force | Out-Null
    Copy-Item (Join-Path $src "dmtools.exe") "$BIN_DIR\dmtools.exe" -Force
    Copy-Item (Join-Path $src "native\quickjs\libquickjs_bridge.so") `
        "$BIN_DIR\native\quickjs\libquickjs_bridge.so" -Force

    # Launcher pins JSR_QUICKJS_LIB at the bundled library: in an AOT build
    # Platform.script does not resolve to the installed exe, and there is no
    # package_config next to an installed binary — the runtime's first lookup
    # candidate (the env var) is the only reliable path.
    @"
@echo off
set "JSR_QUICKJS_LIB=%~dp0native\quickjs\libquickjs_bridge.so"
"%~dp0dmtools.exe" %*
"@ | Set-Content -Path "$BIN_DIR\dmtools.cmd" -Encoding ASCII

    if ($version) { $display = $version } else { $display = "latest" }
    Set-Content -Path "$INSTALL_DIR\version.txt" -Value $display
    Write-Info "Installed $BIN_DIR\dmtools.cmd"

    # ── 4. User PATH (idempotent) ──────────────────────────────────────────
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$BIN_DIR*") {
        [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $BIN_DIR), "User")
        Write-Info "Added $BIN_DIR to the user PATH (open a new terminal)."
    } else {
        Write-Info "$BIN_DIR is already on the user PATH."
    }

    # ── 5. Smoke-test ──────────────────────────────────────────────────────
    $out = & "$BIN_DIR\dmtools.cmd" --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "dmtools $out"
    } else {
        Write-Warn "installed binary failed to start: $out"
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Info "Installation complete. Try: dmtools list"
