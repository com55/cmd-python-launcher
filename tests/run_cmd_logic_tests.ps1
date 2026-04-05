Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$runCmdSource = Join-Path $repoRoot "normal\run.cmd"
$sandboxRoot = Join-Path $repoRoot "tests\.sandbox"

if (Test-Path $sandboxRoot) {
    Remove-Item -Recurse -Force $sandboxRoot
}
New-Item -ItemType Directory -Path $sandboxRoot | Out-Null

$realPython = (Get-Command python -ErrorAction Stop).Source
$realPowerShell = (Get-Command powershell -ErrorAction Stop).Source
$baseSystemPath = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0"

function New-CaseProject {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Requirements
    )

    $caseDir = Join-Path $sandboxRoot $Name
    New-Item -ItemType Directory -Path $caseDir | Out-Null
    Copy-Item $runCmdSource (Join-Path $caseDir "run.cmd")

    @'
import sys
print("ENTRY_OK", " ".join(sys.argv[1:]))
'@ | Set-Content -Path (Join-Path $caseDir "main.py") -Encoding ASCII

    Set-Content -Path (Join-Path $caseDir "requirements.txt") -Value $Requirements -Encoding ASCII
    return $caseDir
}

function New-ToolsDir {
    param([Parameter(Mandatory = $true)][string]$CaseDir)
    $toolsDir = Join-Path $CaseDir "tools"
    New-Item -ItemType Directory -Path $toolsDir | Out-Null
    return $toolsDir
}

function Write-FakePython {
    param(
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$RealPythonPath
    )

    $content = @"
@echo off
if /I "%~1"=="--version" (
  echo Python $Version
  exit /b 0
)
"$RealPythonPath" %*
"@
    Set-Content -Path (Join-Path $ToolsDir "python.cmd") -Value $content -Encoding ASCII
}

function Write-FakeUv {
    param(
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$RealPythonPath
    )

    $content = @"
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "REAL_PY=$RealPythonPath"

if /I "%~1"=="venv" (
  "%REAL_PY%" -m venv "%~4"
  exit /b %ERRORLEVEL%
)

if /I "%~1"=="run" (
  "%REAL_PY%" "%~6"
  exit /b %ERRORLEVEL%
)

if /I "%~1"=="pip" (
  if /I "%~2"=="install" (
    "%~4" -m pip install -r "%~6"
    exit /b %ERRORLEVEL%
  )
  if /I "%~2"=="freeze" (
    "%~4" -m pip freeze
    exit /b %ERRORLEVEL%
  )
)

echo FAKE_UV_UNHANDLED %*
exit /b 1
"@
    Set-Content -Path (Join-Path $ToolsDir "uv.cmd") -Value $content -Encoding ASCII
}

function Write-PowerShellWrapper {
    param(
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$RealPowerShellPath,
        [Parameter(Mandatory = $true)][string]$RealPythonPath
    )

    $uvTemplate = @"
@echo off
setlocal
"$RealPythonPath" "%~6"
exit /b %ERRORLEVEL%
"@

    $wrapper = @"
@echo off
setlocal EnableExtensions
set "ARGS=%*"

echo %ARGS% | findstr /I "astral.sh/uv/install.ps1" >nul
if not errorlevel 1 (
  >"%~dp0uv.cmd" (
$($uvTemplate -split "`r?`n" | ForEach-Object {"    echo $_"} | Out-String)
  )
  exit /b 0
)

"$RealPowerShellPath" %*
exit /b %ERRORLEVEL%
"@

    Set-Content -Path (Join-Path $ToolsDir "powershell.cmd") -Value $wrapper -Encoding ASCII
}

function Invoke-RunCmd {
    param(
        [Parameter(Mandatory = $true)][string]$CaseDir,
        [Parameter(Mandatory = $true)][string]$PathValue,
        [string]$Args = ""
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    if ([string]::IsNullOrWhiteSpace($Args)) {
        $psi.Arguments = '/d /c "run.cmd"'
    }
    else {
        $psi.Arguments = '/d /c "run.cmd ' + $Args + '"'
    }
    $psi.WorkingDirectory = $CaseDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["PATH"] = $PathValue

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $output = ($stdout + $stderr)
    $exitCode = $proc.ExitCode

    return [PSCustomObject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

$results = @()

# Case 1: Existing .venv satisfied + cache hit on second run
$case1 = New-CaseProject -Name "case1_venv_ok" -Requirements ""
& $realPython -m venv (Join-Path $case1 ".venv") | Out-Null
$run1 = Invoke-RunCmd -CaseDir $case1 -PathValue $env:PATH
$run1b = Invoke-RunCmd -CaseDir $case1 -PathValue $env:PATH
$results += [PSCustomObject]@{
    Case = "1_existing_venv_satisfied"
    ExitCode = $run1.ExitCode
    Passed = ($run1.Output -match "Checking requirements in existing \.venv" -and $run1.Output -match "ENTRY_OK")
    Notes = "Expect requirement check + run from .venv"
}
$results += [PSCustomObject]@{
    Case = "1b_existing_venv_cache_hit"
    ExitCode = $run1b.ExitCode
    Passed = ($run1b.Output -match "Cache hit: using existing \.venv" -and $run1b.Output -match "ENTRY_OK")
    Notes = "Expect cache hit on repeat"
}

# Case 2: Existing .venv but requirements differ
$case2 = New-CaseProject -Name "case2_venv_diff" -Requirements "@@@"
& $realPython -m venv (Join-Path $case2 ".venv") | Out-Null
$run2 = Invoke-RunCmd -CaseDir $case2 -PathValue $env:PATH
$results += [PSCustomObject]@{
    Case = "2_existing_venv_requirements_differ"
    ExitCode = $run2.ExitCode
    Passed = ($run2.Output -match "Existing \.venv found but requirements differ, installing requirements")
    Notes = "Expect mismatch branch"
}

# Case 3: No .venv, system python valid
$case3 = New-CaseProject -Name "case3_system_python_ok" -Requirements ""
$run3 = Invoke-RunCmd -CaseDir $case3 -PathValue $env:PATH
$results += [PSCustomObject]@{
    Case = "3_system_python_direct"
    ExitCode = $run3.ExitCode
    Passed = ($run3.Output -match "Checking installed requirements on system python" -and $run3.Output -match "ENTRY_OK")
    Notes = "Expect direct system python run"
}

# Case 4: Python below minimum + uv exists => ensure_venv_from_uv
$case4 = New-CaseProject -Name "case4_low_py_uv_exists" -Requirements ""
$tools4 = New-ToolsDir -CaseDir $case4
Write-FakePython -ToolsDir $tools4 -Version "3.6.0" -RealPythonPath $realPython
Write-FakeUv -ToolsDir $tools4 -RealPythonPath $realPython
$path4 = "$tools4;$baseSystemPath"
$run4 = Invoke-RunCmd -CaseDir $case4 -PathValue $path4
$results += [PSCustomObject]@{
    Case = "4_low_python_uv_exists"
    ExitCode = $run4.ExitCode
    Passed = ($run4.Output -match "Python found" -and $run4.Output -match "uv is available, creating \.venv using uv python" -and $run4.Output -match "ENTRY_OK")
    Notes = "Expect uv-based venv creation"
}

# Case 5: Python below minimum + uv missing => ensure_venv_from_python
$case5 = New-CaseProject -Name "case5_low_py_no_uv" -Requirements ""
$tools5 = New-ToolsDir -CaseDir $case5
Write-FakePython -ToolsDir $tools5 -Version "3.6.0" -RealPythonPath $realPython
$path5 = "$tools5;$baseSystemPath"
$run5 = Invoke-RunCmd -CaseDir $case5 -PathValue $path5
$results += [PSCustomObject]@{
    Case = "5_low_python_uv_missing"
    ExitCode = $run5.ExitCode
    Passed = ($run5.Output -match "uv not found, creating \.venv using installed python" -and $run5.Output -match "ENTRY_OK")
    Notes = "Expect python-based venv creation"
}

# Case 6: No python + uv exists => uv fallback run
$case6 = New-CaseProject -Name "case6_no_py_uv_exists" -Requirements ""
$tools6 = New-ToolsDir -CaseDir $case6
Write-FakeUv -ToolsDir $tools6 -RealPythonPath $realPython
$path6 = "$tools6;$baseSystemPath"
$run6 = Invoke-RunCmd -CaseDir $case6 -PathValue $path6
$results += [PSCustomObject]@{
    Case = "6_no_python_uv_fallback"
    ExitCode = $run6.ExitCode
    Passed = ($run6.Output -match "Python command not found, using uv fallback" -and $run6.Output -match "ENTRY_OK")
    Notes = "Expect uv run fallback"
}

# Case 7: No python + no uv => official installer path
$case7 = New-CaseProject -Name "case7_no_py_no_uv_install" -Requirements ""
$tools7 = New-ToolsDir -CaseDir $case7
Write-PowerShellWrapper -ToolsDir $tools7 -RealPowerShellPath $realPowerShell -RealPythonPath $realPython
$path7 = "$tools7;$baseSystemPath"
$run7 = Invoke-RunCmd -CaseDir $case7 -PathValue $path7
$results += [PSCustomObject]@{
    Case = "7_no_python_no_uv_installer"
    ExitCode = $run7.ExitCode
    Passed = ($run7.Output -match "uv not found, attempting to install with official installer")
    Notes = "Expect installer branch invocation"
}

$results | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $sandboxRoot "results.json") -Encoding UTF8
$results | Format-Table -AutoSize
Write-Output "\nDetailed results: $sandboxRoot\results.json"
