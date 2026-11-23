[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class ResizeProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left, Top, Right, Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X, Y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayMode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
        public short Version, DriverVersion, Size, DriverExtra;
        public int Fields, PositionX, PositionY, Orientation, FixedOutput;
        public short Color, Duplex, YResolution, TTOption, Collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FormName;
        public short LogPixels;
        public int BitsPerPixel, Width, Height, Flags, Frequency, ICMMethod, ICMIntent;
        public int MediaType, DitherType, Reserved1, Reserved2, PanningWidth, PanningHeight;
    }

    private delegate bool ChildVisitor(IntPtr handle, IntPtr ignored);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr window, ChildVisitor visit, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplaySettings(string device, int mode, ref DisplayMode display);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int ChangeDisplaySettings(ref DisplayMode mode, int flags);

    public static int SetDisplaySize(int width, int height) {
        var mode = new DisplayMode { Size = (short)Marshal.SizeOf(typeof(DisplayMode)) };
        if (!EnumDisplaySettings(null, -1, ref mode)) return -1;
        mode.Width = width;
        mode.Height = height;
        mode.Fields = 0x180000;
        return ChangeDisplaySettings(ref mode, 0);
    }

    public static IntPtr FlutterChild(IntPtr root) {
        IntPtr found = IntPtr.Zero;
        ChildVisitor visit = (handle, ignored) => {
            var name = new StringBuilder(128);
            GetClassName(handle, name, name.Capacity);
            if (!String.Equals(name.ToString(), "FLUTTERVIEW", StringComparison.OrdinalIgnoreCase)) return true;
            found = handle;
            return false;
        };
        EnumChildWindows(root, visit, IntPtr.Zero);
        GC.KeepAlive(visit);
        return found;
    }

    public static Rect ClientOnScreen(IntPtr window) {
        Rect size;
        var origin = new Point();
        if (!GetClientRect(window, out size) || !ClientToScreen(window, ref origin)) {
            throw new InvalidOperationException("Could not read the window client rectangle.");
        }
        return new Rect {
            Left = origin.X,
            Top = origin.Y,
            Right = origin.X + size.Width,
            Bottom = origin.Y + size.Height
        };
    }
}
'@

[void][ResizeProbe]::SetProcessDpiAwarenessContext([IntPtr](-4))
$display = [Windows.Forms.Screen]::PrimaryScreen
$initialDisplayBounds = $display.Bounds
$resolutionChanged = $false
$app = $null
$results = [Collections.Generic.List[object]]::new()

function Get-EdgeBrightness($bitmap, [int]$x, [int]$y) {
    $samples = 0
    $visible = 0
    for ($dx = -13; $dx -le 13; $dx += 2) {
        for ($dy = -13; $dy -le 13; $dy += 2) {
            $color = $bitmap.GetPixel($x + $dx, $y + $dy)
            $samples++
            if ([Math]::Max($color.R, [Math]::Max($color.G, $color.B)) -gt 24) { $visible++ }
        }
    }
    return [Math]::Round($visible / $samples, 2)
}

function Test-WindowFrame([string]$name, [IntPtr]$window, [IntPtr]$child) {
    Start-Sleep -Milliseconds 900
    $root = [ResizeProbe]::ClientOnScreen($window)
    $view = [ResizeProbe]::ClientOnScreen($child)
    $screen = [Windows.Forms.Screen]::FromHandle($window).Bounds
    if ($root.Width -lt 850 -or $root.Height -lt 570 -or
        $root.Left -lt $screen.Left -or $root.Top -lt $screen.Top -or
        $root.Right -gt $screen.Right -or $root.Bottom -gt $screen.Bottom) {
        throw "$name client area is too small or outside the desktop for pixel validation."
    }
    $bitmap = [Drawing.Bitmap]::new($root.Width, $root.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($root.Left, $root.Top, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $EvidenceDirectory "$name.png"), [Drawing.Imaging.ImageFormat]::Png)
        $right = Get-EdgeBrightness $bitmap ($root.Width - 35) ([int]($root.Height * 0.6))
        $bottom = Get-EdgeBrightness $bitmap ([int]($root.Width * 0.82)) ($root.Height - 30)
        $results.Add([ordered]@{
            step = $name; width = $root.Width; height = $root.Height
            flutterWidth = $view.Width; flutterHeight = $view.Height
            dpi = [ResizeProbe]::GetDpiForWindow($window)
            rightNonBlack = $right; bottomNonBlack = $bottom
        })
        if ($root.Left -ne $view.Left -or $root.Top -ne $view.Top -or
            $root.Width -ne $view.Width -or $root.Height -ne $view.Height) {
            throw "$name Flutter child does not fill the client area."
        }
        if ($right -lt 0.8 -or $bottom -lt 0.8) {
            throw "$name contains unexpected black pixels near an edge."
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($display.WorkingArea.Width -lt 1450 -or $display.WorkingArea.Height -lt 850) {
        foreach ($size in @(@{ Width=1600; Height=900 }, @{ Width=1920; Height=1080 })) {
            if ([ResizeProbe]::SetDisplaySize($size.Width, $size.Height) -eq 0) {
                $resolutionChanged = $true
                break
            }
        }
        $display = [Windows.Forms.Screen]::PrimaryScreen
    }
    $area = $display.WorkingArea
    if ($area.Width -lt 1400 -or $area.Height -lt 820) {
        throw "Desktop is $($area.Width)x$($area.Height); insufficient to test beyond the reported dimensions."
    }

    $app = Start-Process $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
    $child = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 250
        $app.Refresh()
        if ($app.HasExited) { throw "OciDeck exited before presenting a window ($($app.ExitCode))." }
        $root = $app.MainWindowHandle
        if ($root -ne [IntPtr]::Zero) { $child = [ResizeProbe]::FlutterChild($root) }
    } while ($child -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $deadline)
    if ($child -eq [IntPtr]::Zero) { throw 'No visible Windows Flutter child was found.' }

    [void][ResizeProbe]::SetForegroundWindow($root)
    Start-Sleep -Seconds 3
    [void][ResizeProbe]::MoveWindow($root, ($area.Left + 24), ($area.Top + 24), 1130, 700, $true)
    Test-WindowFrame 'start-smaller' $root $child
    [void][ResizeProbe]::ShowWindow($root, 3)
    Test-WindowFrame 'maximized' $root $child
    [void][ResizeProbe]::ShowWindow($root, 9)
    Test-WindowFrame 'restored' $root $child
    [void][ResizeProbe]::MoveWindow($root, ($area.Left + 10), ($area.Top + 10), 1380, 794, $true)
    Test-WindowFrame 'grown-manually' $root $child
    [void][ResizeProbe]::MoveWindow($root, ($area.Left + 24), ($area.Top + 24), 1130, 700, $true)
    Test-WindowFrame 'shrunk-again' $root $child

    if ($results[1].width -lt ($results[0].width + 150) -or
        $results[3].height -lt ($results[2].height + 75)) {
        throw 'The client area did not change enough to verify both resize transitions.'
    }
} finally {
    $results | ConvertTo-Json | Tee-Object -FilePath (Join-Path $EvidenceDirectory 'observations.json')
    if ($app -and !$app.HasExited) { Stop-Process -Id $app.Id }
    if ($resolutionChanged) {
        [void][ResizeProbe]::SetDisplaySize($initialDisplayBounds.Width, $initialDisplayBounds.Height)
    }
}
