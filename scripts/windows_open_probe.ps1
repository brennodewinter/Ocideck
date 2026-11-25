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
  public int[] Bounds() {
    int x, y, width, height;
    owner.accLocation(out x, out y, out width, out height, child);
    return new[] { x, y, width, height };
  }
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
  [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] private struct CursorInfo { public int Size, Flags; public IntPtr Cursor; public Point Position; }
  [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll", SetLastError = true)] private static extern bool GetCursorInfo(ref CursorInfo cursor);
  [DllImport("user32.dll")] private static extern IntPtr GetCursor();
  [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, IntPtr processId);
  [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint left, uint right, bool attach);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
  [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
  public static void EnablePerMonitorDpi() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
  public static bool ResizeClient(IntPtr hwnd, int x, int y, int width, int height) {
    Rect frame, client;
    if (!GetWindowRect(hwnd, out frame) || !GetClientRect(hwnd, out client)) return false;
    return SetWindowPos(hwnd, IntPtr.Zero, x, y, width + frame.Right - frame.Left - client.Right,
                        height + frame.Bottom - frame.Top - client.Bottom, 4);
  }
  public static int[] ClientGeometry(IntPtr hwnd) {
    Rect client;
    if (!GetClientRect(hwnd, out client)) return new int[0];
    var dimensions = new List<int> { client.Right, client.Bottom };
    EnumWindow callback = (child, state) => {
      var name = new StringBuilder(32);
      GetClassName(child, name, name.Capacity);
      Rect view;
      if (name.ToString() != "FLUTTERVIEW" || !GetClientRect(child, out view)) return true;
      dimensions.Add(view.Right);
      dimensions.Add(view.Bottom);
      return false;
    };
    EnumChildWindows(hwnd, callback, IntPtr.Zero);
    GC.KeepAlive(callback);
    return dimensions.ToArray();
  }
  public static IntPtr Cursor(IntPtr window) {
    var cursor = new CursorInfo { Size = Marshal.SizeOf(typeof(CursorInfo)) };
    if (GetCursorInfo(ref cursor) && cursor.Cursor != IntPtr.Zero) return cursor.Cursor;
    // The virtual desktop can suppress its global cursor. Read the input
    // queue of the foreground window in that case.
    uint owner = GetWindowThreadProcessId(window, IntPtr.Zero);
    uint current = GetCurrentThreadId();
    if (owner == current) return GetCursor();
    if (!AttachThreadInput(current, owner, true)) return IntPtr.Zero;
    try { return GetCursor(); }
    finally { AttachThreadInput(current, owner, false); }
  }
  public static void MovePointer(int x, int y) {
    if (!SetCursorPos(x - 1, y)) throw new InvalidOperationException("SetCursorPos failed");
    mouse_event(1, 1, 0, 0, UIntPtr.Zero);
  }
  public static void Click() {
    mouse_event(2, 0, 0, 0, UIntPtr.Zero);
    mouse_event(4, 0, 0, 0, UIntPtr.Zero);
  }
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

function Wait-WinRtOperation($Operation, [Type]$ResultType) {
    $task = $script:winRtAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    if (-not $task.Wait(5000)) { throw 'Native OCR did not return in time.' }
    return $task.Result
}

function Get-SettingsSearchPosition($Bounds) {
    # Flutter's Windows accessibility tree can still expose the welcome screen
    # while the rendered modal is visible. Read the actual search field on screen.
    $image = New-Object Drawing.Bitmap($Bounds.Width, $Bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    $path = Join-Path $EvidenceDirectory 'window-settings.png'
    try {
        $graphics.CopyFromScreen($Bounds.Location, [Drawing.Point]::Empty, $Bounds.Size)
        $image.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    $file = Wait-WinRtOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
    $stream = Wait-WinRtOperation ($file.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    try {
        $decoder = Wait-WinRtOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            $text = Wait-WinRtOperation ($script:ocr.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            foreach ($line in $text.Lines) {
                if ($line.Text -notmatch 'Search a setting|Zoek een instelling') { continue }
                foreach ($word in $line.Words) {
                    if ($word.Text -notmatch '^(setting|instelling)$') { continue }
                    $rect = $word.BoundingRect
                    return [Drawing.Point]::new(($Bounds.X + [int]($rect.X + $rect.Width / 2)),
                                                ($Bounds.Y + [int]($rect.Y + $rect.Height / 2)))
                }
            }
        } finally { $bitmap.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-NativeWindow {
    [OpenProbeWindow]::EnablePerMonitorDpi()
    $handle = $script:app.MainWindowHandle
    [void][OpenProbeWindow]::ShowWindow($handle, 9)
    [void][OpenProbeWindow]::SetForegroundWindow($handle)
    [void](Wait-Probe 'foreground app for mouse input' { [OpenProbeWindow]::GetForegroundWindow() -eq $handle })
    $screen = [Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $scale = [OpenProbeWindow]::GetDpiForWindow($handle) / 96.0
    if ($scale -le 0) { throw 'Could not determine the window DPI.' }
    $width = [int][Math]::Min(1280, [Math]::Floor(($screen.Width - 18) / $scale))
    $height = [int][Math]::Min(850, [Math]::Floor(($screen.Height - 34) / $scale))
    if ($width -lt 980 -or $height -lt 670) {
        throw "Work area $($screen.Width)x$($screen.Height) at scale $scale leaves only ${width}x${height} for the client probe."
    }
    $snapshots = @()
    foreach ($targetHeight in @([Math]::Max(650, $height - 100), $height)) {
        $requestedWidth = [int]($width * $scale)
        $requestedHeight = [int]($targetHeight * $scale)
        if (-not [OpenProbeWindow]::ResizeClient($handle, $screen.X, $screen.Y, $requestedWidth, $requestedHeight)) {
            throw 'Win32 could not request the new client size.'
        }
        [void](Wait-Probe "the native client and Flutter viewport at ${width}x${targetHeight}" {
            $r = [OpenProbeWindow]::ClientGeometry($handle)
            return ($r.Count -eq 4 -and [Math]::Abs($r[0] - $requestedWidth) -le 2 -and
                [Math]::Abs($r[1] - $requestedHeight) -le 2 -and $r[0] -eq $r[2] -and $r[1] -eq $r[3])
        })
        $snapshots += [ordered]@{ logicalWidth = $width; logicalHeight = $targetHeight; scale = $scale }
    }
    $settings = Wait-Probe 'the visible Settings button' {
        Find-Control (Get-AppRoot) '^(Settings|Instellingen)$' ([Windows.Automation.ControlType]::Button)
    }
    $bounds = $settings.Bounds()
    if ($bounds[2] -le 0 -or $bounds[3] -le 0) { throw 'Settings has no visible mouse target.' }
    $buttonX = $bounds[0] + [int]($bounds[2] / 2)
    $buttonY = $bounds[1] + [int]($bounds[3] / 2)
    if (-not [OpenProbeWindow]::SetCursorPos($buttonX, $buttonY)) {
        throw 'Could not move the pointer over Settings.'
    }
    Start-Sleep -Milliseconds 120
    [OpenProbeWindow]::Click()

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
    $script:winRtAsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }
    $script:ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (-not $script:ocr) { throw 'No native OCR language is available on this runner.' }
    $display = [Windows.Forms.Screen]::FromHandle($handle).Bounds
    $search = Wait-Probe 'visible Settings search after native mouse input' {
        Get-SettingsSearchPosition $display
    }
    [OpenProbeWindow]::MovePointer($search.X, ($search.Y - [int](27 * $scale)))
    Start-Sleep -Milliseconds 250
    $before = Wait-Probe 'native cursor outside the search field' {
        $cursor = [OpenProbeWindow]::Cursor($handle)
        if ($cursor -ne [IntPtr]::Zero) { $cursor }
    }
    [OpenProbeWindow]::MovePointer($search.X, $search.Y)
    [void](Wait-Probe 'native cursor changes over Settings search' {
        $hover = [OpenProbeWindow]::Cursor($handle)
        return ($hover -ne [IntPtr]::Zero -and $hover -ne $before)
    })
    Save-ProbeEvidence 'window-settings-clicked'
    [Windows.Forms.SendKeys]::SendWait('{ESC}')
    [void](Wait-Probe 'Settings dismissed' {
        $null -eq (Get-SettingsSearchPosition $display)
    })
    [ordered]@{ sizes = $snapshots; cursorChanged = $true; settingsClicked = $true } |
        ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'window.json')
    [void][OpenProbeWindow]::ShowWindow($handle, 3)
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

function Get-SourceHash([string]$Path) {
    # Windows PowerShell inherits pwsh's module search path in Actions;
    # use .NET directly instead of relying on Get-FileHash autoloading.
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
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

    Test-NativeWindow

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
        $hash = Get-SourceHash (Join-Path $EvidenceDirectory "fixtures\$($source.Name)")
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
