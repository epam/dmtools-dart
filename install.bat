@echo off
REM DMTools CLI Installation Script for Windows (Dart port)
REM Works in cmd.exe and automatically uses PowerShell
REM Usage: curl -fsSL https://raw.githubusercontent.com/epam/dmtools-dart/main/install.bat -o "%TEMP%\dmtools-install.bat" && "%TEMP%\dmtools-install.bat"
REM For specific version: set DMTOOLS_VERSION=v0.1.11 && curl -fsSL https://raw.githubusercontent.com/epam/dmtools-dart/v0.1.11/install.bat -o "%TEMP%\dmtools-install.bat" && "%TEMP%\dmtools-install.bat"

setlocal

echo ============================================
echo DMTools CLI Installer for Windows
echo ============================================
echo.

REM Detect version from environment or default to latest
set DETECTED_VERSION=%DMTOOLS_VERSION%
if "%DETECTED_VERSION%"=="" (
    set DETECTED_VERSION=latest
)

REM Construct installer URL
if "%DETECTED_VERSION%"=="latest" (
    set INSTALLER_URL=https://github.com/epam/dmtools-dart/releases/latest/download/install.ps1
    echo Using latest version...
) else (
    set INSTALLER_URL=https://github.com/epam/dmtools-dart/releases/download/%DETECTED_VERSION%/install.ps1
    echo Using version: %DETECTED_VERSION%
)

echo Installer URL: %INSTALLER_URL%
echo.

REM Prefer Windows PowerShell, fall back to PowerShell Core
where powershell >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Found Windows PowerShell
    echo Downloading and running installer...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-RestMethod -Uri '%INSTALLER_URL%' -UseBasicParsing | Invoke-Expression } catch { Write-Host 'Error: Failed to download or execute installer' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    goto :end
)

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Found PowerShell Core (pwsh)
    echo Downloading and running installer...
    pwsh -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-RestMethod -Uri '%INSTALLER_URL%' -UseBasicParsing | Invoke-Expression } catch { Write-Host 'Error: Failed to download or execute installer' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    goto :end
)

echo Error: PowerShell not found!
echo DMTools requires PowerShell to install on Windows.
echo Or use Git Bash:
echo   curl -fsSL https://raw.githubusercontent.com/epam/dmtools-dart/main/install.sh ^| bash
echo.
pause
exit /b 1

:end
echo.
endlocal
