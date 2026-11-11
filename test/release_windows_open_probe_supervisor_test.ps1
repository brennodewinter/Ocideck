# Fault injection for the real supervisor. This never runs the native UI worker.
# Run with pwsh on any host, or Windows PowerShell on the release runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$probe = Join-Path $PSScriptRoot '..\scripts\windows_open_probe.ps1'
if ([IO.Path]::DirectorySeparatorChar -eq '/') {
    $probe = Join-Path $PSScriptRoot '../scripts/windows_open_probe.ps1'
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('open-supervisor-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
$executable = Join-Path $temporary 'fake.exe'
Set-Content $executable 'not an executable; Start-Process is replaced'
$originalOS = $env:OS
$env:OS = 'Windows_NT'
$global:openProbeTestMode = ''
$global:openProbeTestCaseDirectory = ''
$global:openProbeTestKilled = $false

# Avoid needing a command named 'python' on macOS; production uses runner Python.
$global:openProbeTestPython = @(Get-Command python, python3 -CommandType Application -ErrorAction SilentlyContinue)[0].Source
function python {
    & $global:openProbeTestPython @args
    $global:LASTEXITCODE = $LASTEXITCODE
}

function Start-Process {
    param($FilePath, $ArgumentList, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
    if ($FilePath -ne 'powershell.exe') { throw 'Unexpected child process in supervisor test.' }
    if ($global:openProbeTestMode -ne 'missing-result') {
        $result = @{ status = 'passed'; opened = @('markdown', 'package')
            cancelled = $true; sourceHashesPreserved = $true }
        switch ($global:openProbeTestMode) {
            'failed-result' { $result.status = 'failed' }
            'duplicate-open' { $result.opened = @('markdown', 'markdown') }
            'missing-cancel' { $result.cancelled = $false }
            'changed-source' { $result.sourceHashesPreserved = $false }
        }
        $result | ConvertTo-Json | Set-Content (Join-Path $global:openProbeTestCaseDirectory 'result.json')
    }
    $child = [pscustomobject]@{ Id = 123; HasExited = ($global:openProbeTestMode -ne 'timeout'); ExitCode = 0 }
    if ($global:openProbeTestMode -eq 'child-error') { $child.ExitCode = 7 }
    $child | Add-Member ScriptMethod Refresh { }
    $child | Add-Member ScriptMethod WaitForExit { param($milliseconds) return $this.HasExited }
    return $child
}

function taskkill.exe { $global:openProbeTestKilled = $true }

try {
    Write-Host 'Supervisor fault-injection tests (no native UI worker executed).'
    foreach ($case in @('passed', 'child-error', 'timeout', 'missing-result',
            'failed-result', 'duplicate-open', 'missing-cancel', 'changed-source')) {
        $global:openProbeTestMode = $case
        $global:openProbeTestKilled = $false
        $global:openProbeTestCaseDirectory = Join-Path $temporary $case
        $failed = $false
        $failure = ''
        try {
            & $probe -Executable $executable -EvidenceDirectory $global:openProbeTestCaseDirectory -TimeoutSeconds 60 *> $null
        } catch { $failed = $true; $failure = "$_" }
        if ($case -eq 'passed' -and $failed) { throw "Supervisor rejected complete passing evidence: $failure" }
        if ($case -ne 'passed' -and -not $failed) { throw "Supervisor accepted $case." }
        if ($case -eq 'timeout' -and -not $global:openProbeTestKilled) { throw 'Timed-out worker was not killed.' }
        if ($case -ne 'passed' -and -not (Test-Path (Join-Path $global:openProbeTestCaseDirectory 'supervisor-failure.json'))) {
            throw "Supervisor failure evidence missing for $case."
        }
        Write-Host "Supervisor case passed: $case"
    }
} finally {
    $env:OS = $originalOS
    Remove-Item -Recurse -Force $temporary
}
