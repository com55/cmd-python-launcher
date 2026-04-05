@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ====================
rem UV project template
rem ====================
set "CFG_RUN_TARGET=main.py"
set "CFG_SYNC_ARGS="
set "CFG_AUTO_INSTALL_UV=1"

set "PROJECT_ROOT=%~dp0"
if not defined PROJECT_ROOT set "PROJECT_ROOT=%CD%\"

set "RUN_TARGET=%PROJECT_ROOT%%CFG_RUN_TARGET%"
set "RUN_USER_ARGS=%*"

if not exist "%PROJECT_ROOT%pyproject.toml" (
    echo [run-uv] pyproject.toml not found: "%PROJECT_ROOT%pyproject.toml"
    exit /b 1
)

if not exist "%RUN_TARGET%" (
    echo [run-uv] Run target not found: "%RUN_TARGET%"
    exit /b 1
)

call :ensure_uv UV_EXE
if errorlevel 1 exit /b 1

pushd "%PROJECT_ROOT%"
if defined CFG_SYNC_ARGS (
    echo [run-uv] Running: uv sync %CFG_SYNC_ARGS%
    "%UV_EXE%" sync %CFG_SYNC_ARGS%
) else (
    echo [run-uv] Running: uv sync
    "%UV_EXE%" sync
)
if errorlevel 1 (
    set "SYNC_EXIT=%ERRORLEVEL%"
    popd
    exit /b %SYNC_EXIT%
)

echo [run-uv] Running: uv run "%CFG_RUN_TARGET%" %RUN_USER_ARGS%
"%UV_EXE%" run "%CFG_RUN_TARGET%" %RUN_USER_ARGS%
set "RUN_EXIT=%ERRORLEVEL%"
popd
exit /b %RUN_EXIT%

:find_uv
set "%~1="
for /f "delims=" %%U in ('where uv 2^>nul') do (
    if not defined %~1 set "%~1=%%U"
)
exit /b 0

:ensure_uv
call :find_uv %~1
if defined %~1 exit /b 0

if "%CFG_AUTO_INSTALL_UV%"=="0" (
    echo [run-uv] uv not found and CFG_AUTO_INSTALL_UV=0
    exit /b 1
)

echo [run-uv] uv not found, attempting to install with official installer
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 ^| iex"
if errorlevel 1 (
    echo [run-uv] Failed to install uv using official installer.
    exit /b 1
)

call :find_uv %~1
if not defined %~1 (
    echo [run-uv] uv was installed but command is not in PATH yet. Open a new terminal and run again.
    exit /b 1
)
exit /b 0
