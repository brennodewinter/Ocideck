# Runs against the INSTALLED release binary. No Flutter test bindings or mocks.
# UIA calls themselves can hang on an unresponsive provider: the parent bounds
# the entire worker process and its app child, in addition to per-step polling.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [ValidateRange(60, 600)][int]$TimeoutSeconds = 240,
    [switch]$Worker
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'This probe requires an interactive Windows desktop.' }
$Executable = (Resolve-Path $Executable).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)

if (-not $Worker) {
    New-Item -ItemType Directory -Force $EvidenceDirectory | Out-Null
    $fixtures = Join-Path $EvidenceDirectory 'fixtures'
    & python (Join-Path $PSScriptRoot 'windows_open_probe_fixtures.py') $fixtures
    if ($LASTEXITCODE -ne 0) { throw 'Could not create open-probe fixtures.' }
    $arguments = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File',
        "`"$PSCommandPath`"", '-Worker', '-Executable', "`"$Executable`"",
        '-EvidenceDirectory', "`"$EvidenceDirectory`"")
    $child = Start-Process powershell.exe -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $EvidenceDirectory 'worker.stdout.log') `
        -RedirectStandardError (Join-Path $EvidenceDirectory 'worker.stderr.log')
    try {
        if (-not $child.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Windows open probe exceeded $TimeoutSeconds seconds; no passing evidence."
        }
        $child.Refresh()
        if ($child.ExitCode -ne 0) { throw "Windows open probe failed (exit $($child.ExitCode))." }
        $resultPath = Join-Path $EvidenceDirectory 'result.json'
        if (-not (Test-Path $resultPath)) { throw 'Open probe returned without result.json.' }
        $result = Get-Content -Raw $resultPath | ConvertFrom-Json
        if ($result.status -ne 'passed' -or @($result.opened).Count -ne 2 -or
            $result.opened -notcontains 'markdown' -or $result.opened -notcontains 'package' -or
            -not $result.cancelled -or -not $result.sourceHashesPreserved) {
            throw 'Open probe did not prove both opens and cancellation.'
        }
        Write-Host 'Windows open probe passed: native picker, Markdown, package, cancellation, source preservation.'
    } catch {
        [ordered]@{ status = 'supervisor-failed'; error = "$_" } | ConvertTo-Json |
            Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'supervisor-failure.json')
        throw
    } finally {
        if (-not $child.HasExited) { & taskkill.exe /PID $child.Id /T /F | Out-Null }
    }
    return
}

# Windows PowerShell 5.1 supplies the .NET Framework UI Automation assemblies.
# https://learn.microsoft.com/dotnet/framework/ui-automation/invoke-a-control-using-ui-automation
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class OpenProbeWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
}
'@
$script:app = $null
$script:opened = @()
$script:cancelled = $false
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $EvidenceDirectory 'fixtures\manifest.json') | ConvertFrom-Json

function Wait-Probe([string]$Description, [scriptblock]$Condition, [int]$Seconds = 30) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
        if ($script:app) {
            $script:app.Refresh()
            if ($script:app.HasExited) { throw "App exited while waiting for $Description." }
        }
        # UIA elements can be replaced between two reads during a Flutter frame.
        try { $value = & $Condition }
        catch [Windows.Automation.ElementNotAvailableException] { $value = $null }
        if ($null -ne $value -and $value -ne $false) { return $value }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

function Get-AppRoot {
    $script:app.Refresh()
    if ($script:app.MainWindowHandle -eq [IntPtr]::Zero) { return $null }
    return [Windows.Automation.AutomationElement]::FromHandle($script:app.MainWindowHandle)
}

function Find-Control($Root, [string]$NamePattern, $ControlType = $null) {
    if ($null -eq $Root) { return $null }
    $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $all) {
        if ($element.Current.IsOffscreen) { continue }
        if ($ControlType -and $element.Current.ControlType -ne $ControlType) { continue }
        if ($element.Current.Name -match $NamePattern) { return $element }
    }
    return $null
}

function Invoke-Control($Element) {
    $pattern = $null
    if (-not $Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        throw "Control has no InvokePattern: $($Element.Current.Name)"
    }
    $pattern.Invoke()
}

function Find-Marker($Root, [string]$Marker) {
    if ($null -eq $Root) { return $null }
    $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $all) {
        if ($element.Current.IsOffscreen) { continue }
        if ($element.Current.Name.Contains($Marker)) { return $element }
        # Editable slide titles expose their contents as Value, not Name.
        $pattern = $null
        if ($element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
            if ($pattern.Current.Value.Contains($Marker)) { return $element }
        }
        $pattern = $null
        if ($element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) {
            if ($pattern.DocumentRange.GetText(2048).Contains($Marker)) { return $element }
        }
    }
    return $null
}

function Get-NativePicker {
    # The native picker lives in a worker isolate but belongs to our process.
    $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll(
        [Windows.Automation.TreeScope]::Children,
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$script:app.Id))
    foreach ($window in $windows) {
        # A Flutter modal must never count as evidence of a native dialog.
        if ($window.Current.ClassName -eq '#32770') { return $window }
    }
    return $null
}

function Open-NativePicker {
    $root = Get-AppRoot
    [void][OpenProbeWindow]::SetForegroundWindow($script:app.MainWindowHandle)
    [void](Wait-Probe 'app keyboard focus' {
        [OpenProbeWindow]::GetForegroundWindow() -eq $script:app.MainWindowHandle
    })
    if ($root.Current.IsKeyboardFocusable) { $root.SetFocus() }
    [Windows.Forms.SendKeys]::SendWait('^o')
    $browse = Wait-Probe 'the in-app Browse action' {
        Find-Control (Get-AppRoot) '^(Browse|Bladeren)(\u2026|\.\.\.)$' ([Windows.Automation.ControlType]::Button)
    }
    Invoke-Control $browse
    return Wait-Probe 'the native Windows file dialog' { Get-NativePicker }
}

function Save-ProbeEvidence([string]$Stage) {
    try {
        $root = Get-AppRoot
        if ($root) {
            $all = $root.FindAll([Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.Condition]::TrueCondition)
            $rows = foreach ($element in $all) {
                [ordered]@{ name = $element.Current.Name; id = $element.Current.AutomationId
                    type = $element.Current.ControlType.ProgrammaticName; offscreen = $element.Current.IsOffscreen }
            }
            ConvertTo-Json -InputObject @($rows) -Depth 4 |
                Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory "$Stage.uia.json")
        }
        $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
            $bitmap.Save((Join-Path $EvidenceDirectory "$Stage.png"), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    } catch { Write-Warning "Could not capture $Stage evidence: $_" }
}

try {
    if (Get-Process ocideck -ErrorAction SilentlyContinue) {
        throw 'Another OciDeck instance is running; refusing to drive or kill an unrelated instance.'
    }
    $script:app = Start-Process -FilePath $Executable -PassThru
    $root = Wait-Probe 'the installed app window' { Get-AppRoot } 60
    [void][OpenProbeWindow]::ShowWindow($script:app.MainWindowHandle, 3)
    # Querying UIA also asks Flutter to expose its real semantics tree.
    $initial = Wait-Probe 'consent or the welcome actions' {
        Find-Control (Get-AppRoot) '^(Agree|Akkoord gaan|New presentation|Nieuwe presentatie)$' ([Windows.Automation.ControlType]::Button)
    } 60
    if ($initial.Current.Name -match '^(Agree|Akkoord gaan)$') {
        $checkbox = Find-Control (Get-AppRoot) '.*' ([Windows.Automation.ControlType]::CheckBox)
        if (-not $checkbox) { throw 'Consent checkbox is not exposed to UI Automation.' }
        $toggle = $checkbox.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
        if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::On) { $toggle.Toggle() }
        $agree = Wait-Probe 'enabled consent button' {
            $button = Find-Control (Get-AppRoot) '^(Agree|Akkoord gaan)$' ([Windows.Automation.ControlType]::Button)
            if ($button -and $button.Current.IsEnabled) { return $button }
        }
        Invoke-Control $agree
    }
    [void](Wait-Probe 'welcome screen' {
        Find-Control (Get-AppRoot) '^(New presentation|Nieuwe presentatie)$' ([Windows.Automation.ControlType]::Button)
    })

    # Cancellation is followed by a new open, proving the app remains usable.
    $dialog = Open-NativePicker
    $cancel = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::AutomationIdProperty, '2'))
    if (-not $cancel) { throw 'Native Cancel button (ID 2) not found.' }
    Invoke-Control $cancel
    [void](Wait-Probe 'native cancellation' { $null -eq (Get-NativePicker) })
    $script:cancelled = $true

    foreach ($scenario in $manifest.scenarios) {
        if (Find-Marker (Get-AppRoot) $scenario.marker) {
            throw 'Marker was visible before opening; this would be a false positive.'
        }
        $dialog = Open-NativePicker
        $nameBox = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.OrCondition]::new(
                [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::AutomationIdProperty, '1148'),
                [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::AutomationIdProperty, 'FileNameControlHost')))
        if (-not $nameBox) { throw 'Native filename control not found.' }
        $value = $null
        if (-not $nameBox.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$value)) {
            $nameBox = $nameBox.FindFirst([Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit))
            if (-not $nameBox) { throw 'Native filename edit control not found.' }
            $value = $nameBox.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
        }
        $value.SetValue($scenario.path)
        $open = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::AutomationIdProperty, '1'))
        if (-not $open) { throw 'Native Open button (ID 1) not found.' }
        Invoke-Control $open
        [void](Wait-Probe 'native dialog closing' { $null -eq (Get-NativePicker) })
        [void](Wait-Probe "opened $($scenario.kind) presentation in the editor" {
            $root = Get-AppRoot
            $marker = Find-Marker $root $scenario.marker
            $welcome = Find-Control $root '^(New presentation|Nieuwe presentatie)$' ([Windows.Automation.ControlType]::Button)
            return ($null -ne $marker -and $null -eq $welcome)
        } 60)
        [ordered]@{ marker = $scenario.marker; nativeDialogClosed = $true; editorVisible = $true } |
            ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory "$($scenario.kind).proof.json")
        $script:opened += $scenario.kind
        Save-ProbeEvidence $scenario.kind
    }
    # Opening must not repair/rewrite original project files behind our back.
    foreach ($source in $manifest.sourceHashes.PSObject.Properties) {
        $hash = (Get-FileHash (Join-Path $EvidenceDirectory "fixtures\$($source.Name)") -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $source.Value) { throw "Opening modified source: $($source.Name)" }
    }
    [ordered]@{ status = 'passed'; executable = $Executable; opened = $script:opened
        cancelled = $script:cancelled; sourceHashesPreserved = $true; utc = [DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'result.json')
} catch {
    Save-ProbeEvidence 'failed'
    [ordered]@{ status = 'failed'; error = "$_"; opened = $script:opened; cancelled = $script:cancelled } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'result.json')
    throw
} finally {
    if ($script:app) {
        $script:app.Refresh()
        if (-not $script:app.HasExited) { Stop-Process -Id $script:app.Id -Force }
    }
}
