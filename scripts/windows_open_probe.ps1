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
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing, Accessibility
Add-Type -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Accessibility;
public sealed class OpenProbeAccessible {
  private readonly IAccessible owner;
  private readonly object child;
  public OpenProbeAccessible(IAccessible owner, object child) { this.owner = owner; this.child = child; }
  public OpenProbeAccessible Current { get { return this; } }
  public string Name { get { try { return owner.get_accName(child) ?? ""; } catch (COMException) { return ""; } } }
  public string Value { get { try { return owner.get_accValue(child) ?? ""; } catch (COMException) { return ""; } } }
  public int Role { get { try { return Convert.ToInt32(owner.get_accRole(child)); } catch (COMException) { return 0; } } }
  public int State { get { try { return Convert.ToInt32(owner.get_accState(child)); } catch (COMException) { return 0; } } }
  public bool IsOffscreen { get { return (State & 0x18000) != 0; } }
  public bool IsEnabled { get { return (State & 1) == 0; } }
  public bool IsChecked { get { return (State & 0x10) != 0; } }
  public void Invoke() { owner.accDoDefaultAction(child); }
}
public static class OpenProbeWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
  private delegate bool EnumWindow(IntPtr hwnd, IntPtr state);
  [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hwnd, EnumWindow callback, IntPtr state);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder name, int count);
  [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(
      IntPtr hwnd, uint objectId, ref Guid iid, out IntPtr accessible);
  [DllImport("oleacc.dll")] private static extern int AccessibleChildren(
      IAccessible parent, int start, int count,
      [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex=2)] object[] children, out int obtained);
  public static OpenProbeAccessible[] Snapshot(IntPtr root) {
    var nodes = new List<OpenProbeAccessible>();
    var seen = new HashSet<string>();
    EnumWindow callback = (hwnd, state) => {
      var name = new StringBuilder(256);
      GetClassName(hwnd, name, name.Capacity);
      if (name.ToString() != "FLUTTERVIEW") return true;
      var iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
      IntPtr pointer;
      if (AccessibleObjectFromWindow(hwnd, unchecked((uint)-4), ref iid, out pointer) == 0 && pointer != IntPtr.Zero) {
        try { Visit((IAccessible)Marshal.GetObjectForIUnknown(pointer), 0, nodes, seen, 0); }
        finally { Marshal.Release(pointer); }
      }
      return true;
    };
    EnumChildWindows(root, callback, IntPtr.Zero);
    GC.KeepAlive(callback);
    return nodes.ToArray();
  }
  private static void Visit(IAccessible owner, object child, List<OpenProbeAccessible> nodes, HashSet<string> seen, int depth) {
    if (depth > 60 || nodes.Count >= 4000) return;
    IntPtr identity = Marshal.GetIUnknownForObject(owner);
    string key = identity.ToString() + ":" + child.ToString();
    Marshal.Release(identity);
    if (!seen.Add(key)) return;
    nodes.Add(new OpenProbeAccessible(owner, child));
    if (Convert.ToInt32(child) != 0) return;
    int count;
    try { count = Math.Min(owner.accChildCount, 4000); } catch (COMException) { return; }
    if (count <= 0) return;
    var children = new object[count];
    int obtained;
    if (AccessibleChildren(owner, 0, count, children, out obtained) < 0) return;
    for (int i=0; i<obtained; i++) {
      var accessible = children[i] as IAccessible;
      if (accessible != null) Visit(accessible, 0, nodes, seen, depth+1);
      else if (children[i] is int) Visit(owner, children[i], nodes, seen, depth+1);
    }
  }
  public static string[] EnableAccessibility(IntPtr root) {
    // Flutter enables semantics on OBJID_CLIENT requests to its child view.
    // Query the actual window subtree, as a screen reader does; no app hook.
    var observations = new List<string>();
    Action<IntPtr> query = hwnd => {
      var iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
      IntPtr accessible;
      int hr = AccessibleObjectFromWindow(hwnd, unchecked((uint)-4), ref iid, out accessible);
      observations.Add(hwnd.ToString() + ": " + hr.ToString());
      if (accessible != IntPtr.Zero) Marshal.Release(accessible);
    };
    query(root);
    EnumWindow callback = (hwnd, state) => { query(hwnd); return true; };
    EnumChildWindows(root, callback, IntPtr.Zero);
    GC.KeepAlive(callback);
    return observations.ToArray();
  }
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
    $all = [OpenProbeWindow]::Snapshot($script:app.MainWindowHandle)
    foreach ($element in $all) {
        if ($element.Current.IsOffscreen) { continue }
        if ($ControlType -eq [Windows.Automation.ControlType]::Button -and $element.Role -ne 43) { continue }
        if ($ControlType -eq [Windows.Automation.ControlType]::CheckBox -and $element.Role -ne 44) { continue }
        if ($element.Current.Name -match $NamePattern) { return $element }
    }
    return $null
}

function Invoke-Control($Element) {
    if ($Element -is [OpenProbeAccessible]) { $Element.Invoke(); return }
    $pattern = $null
    if (-not $Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        throw "Control has no InvokePattern: $($Element.Current.Name)"
    }
    $pattern.Invoke()
}

function Find-Marker($Root, [string]$Marker) {
    if ($null -eq $Root) { return $null }
    $all = [OpenProbeWindow]::Snapshot($script:app.MainWindowHandle)
    foreach ($element in $all) {
        if ($element.Current.IsOffscreen) { continue }
        if ($element.Current.Name.Contains($Marker)) { return $element }
        if ($element.Value.Contains($Marker)) { return $element }
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

function Focus-NativePicker($Dialog) {
    $handle = [IntPtr]$Dialog.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) { throw 'Native picker has no window handle.' }
    [void][OpenProbeWindow]::SetForegroundWindow($handle)
    [void](Wait-Probe 'native picker keyboard focus' {
        [OpenProbeWindow]::GetForegroundWindow() -eq $handle
    })
}

function Open-NativePicker {
    $root = Get-AppRoot
    [void][OpenProbeWindow]::SetForegroundWindow($script:app.MainWindowHandle)
    [void](Wait-Probe 'app keyboard focus' {
        [OpenProbeWindow]::GetForegroundWindow() -eq $script:app.MainWindowHandle
    })
    $welcomeOpen = Find-Control $root '^(Open|Openen)(\u2026|\.\.\.)$' ([Windows.Automation.ControlType]::Button)
    if ($welcomeOpen) {
        # The same welcome-screen action as in the reported video.
        Invoke-Control $welcomeOpen
    } else {
        $more = Wait-Probe 'the editor More menu' {
            Find-Control (Get-AppRoot) '^(More|Meer)$' ([Windows.Automation.ControlType]::Button)
        }
        Invoke-Control $more
        $openAction = Wait-Probe 'the editor Open menu action' {
            Find-Control (Get-AppRoot) '^(Open|Openen)(\u2026|\.\.\.)$'
        }
        Invoke-Control $openAction
    }
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
            $accessible = [OpenProbeWindow]::Snapshot($script:app.MainWindowHandle)
            $msaa = foreach ($node in $accessible) {
                [ordered]@{ name=$node.Name; value=$node.Value; role=$node.Role; state=$node.State }
            }
            ConvertTo-Json -InputObject @($msaa) -Depth 4 |
                Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory "$Stage.msaa.json")
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
    $script:app = Start-Process -FilePath $Executable -PassThru `
        -RedirectStandardOutput (Join-Path $EvidenceDirectory 'app.stdout.log') `
        -RedirectStandardError (Join-Path $EvidenceDirectory 'app.stderr.log')
    $root = Wait-Probe 'the installed app window' { Get-AppRoot } 60
    [void][OpenProbeWindow]::ShowWindow($script:app.MainWindowHandle, 3)
    # UIA alone can expose only FLUTTERVIEW until MSAA is requested on the
    # child HWND. AccessibleObjectFromWindow sends WM_GETOBJECT/OBJID_CLIENT.
    [OpenProbeWindow]::EnableAccessibility($script:app.MainWindowHandle) |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'accessibility-activation.json')
    $initial = Wait-Probe 'consent or the welcome actions' {
        Find-Control (Get-AppRoot) '^(Agree|Akkoord gaan)$|^(New presentation|Nieuwe presentatie)(\s|$)' ([Windows.Automation.ControlType]::Button)
    } 60
    if ($initial.Current.Name -match '^(Agree|Akkoord gaan)$') {
        $checkbox = Find-Control (Get-AppRoot) '.*' ([Windows.Automation.ControlType]::CheckBox)
        if (-not $checkbox) { throw 'Consent checkbox is not exposed to UI Automation.' }
        if (-not $checkbox.IsChecked) { $checkbox.Invoke() }
        $agree = Wait-Probe 'enabled consent button' {
            $button = Find-Control (Get-AppRoot) '^(Agree|Akkoord gaan)$' ([Windows.Automation.ControlType]::Button)
            if ($button -and $button.Current.IsEnabled) { return $button }
        }
        Invoke-Control $agree
    }
    [void](Wait-Probe 'welcome screen' {
        Find-Control (Get-AppRoot) '^(New presentation|Nieuwe presentatie)(\s|$)' ([Windows.Automation.ControlType]::Button)
    })

    # Cancellation is followed by a new open, proving the app remains usable.
    $dialog = Open-NativePicker
    Focus-NativePicker $dialog
    [Windows.Forms.SendKeys]::SendWait('{ESC}')
    [void](Wait-Probe 'native cancellation' { $null -eq (Get-NativePicker) })
    $script:cancelled = $true

    foreach ($scenario in $manifest.scenarios) {
        if (Find-Marker (Get-AppRoot) $scenario.marker) {
            throw 'Marker was visible before opening; this would be a false positive.'
        }
        $dialog = Open-NativePicker
        Focus-NativePicker $dialog
        # The Windows picker exposes some standard controls as UIA panes
        # without Invoke/Value patterns on this runner. Use its real filename
        # keyboard accelerator and clipboard input instead of app internals.
        [Windows.Forms.SendKeys]::SendWait('%n')
        Start-Sleep -Milliseconds 300
        [Windows.Forms.Clipboard]::SetText([string]$scenario.path)
        [Windows.Forms.SendKeys]::SendWait('^a^v')
        Start-Sleep -Milliseconds 300
        Save-ProbeEvidence "selected-$($scenario.kind)"
        [Windows.Forms.SendKeys]::SendWait('{ENTER}')
        [void](Wait-Probe 'native dialog closing' { $null -eq (Get-NativePicker) })
        Start-Sleep -Milliseconds 1000
        Save-ProbeEvidence "returned-$($scenario.kind)"
        [void](Wait-Probe "opened $($scenario.kind) presentation in the editor" {
            $root = Get-AppRoot
            $marker = Find-Marker $root $scenario.marker
            $welcome = Find-Control $root '^(New presentation|Nieuwe presentatie)(\s|$)' ([Windows.Automation.ControlType]::Button)
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
    # Disposable runner: retain the app's own bounded flight-recorder logs.
    try {
        $logs = @(Get-ChildItem $env:APPDATA -Recurse -File -Filter 'ocideck*.log' -ErrorAction SilentlyContinue)
        $index = 0
        foreach ($log in $logs) {
            Copy-Item $log.FullName (Join-Path $EvidenceDirectory "app-flight-$index.log")
            $index++
        }
    } catch { Write-Warning "Could not collect app flight recorder: $_" }
    if ($script:app) {
        $script:app.Refresh()
        if (-not $script:app.HasExited) { Stop-Process -Id $script:app.Id -Force }
    }
}
