<#
=====================================================================
 DiagnoseDpi.ps1

 One-shot, read-only diagnostic for "the click / red circle lands
 outside the terminal window". It does NOT touch your config or move
 the mouse - it only reports numbers.

 It checks:
   1. Which DPI-awareness mode this process actually ends up in, using
      the exact same fallback chain CalibrateScreen1Auto.ps1 and
      AutoClipCapture.ps1 both use (PerMonitorV2 -> PerMonitor -> 
      System-aware). If this does NOT come out as PER-MONITOR-AWARE,
      Windows will virtualize/rescale coordinates for any monitor
      whose scaling % differs from the DPI baseline - which is exactly
      what produces a click that's consistently, wildly off on a
      multi-monitor setup with mixed scaling.
   2. Every monitor you have, its bounds, and its real DPI/scaling %.
   3. Which monitor your terminal window is actually sitting on, and
      that monitor's DPI vs the others - so you can see directly
      whether a scaling mismatch between monitors lines up with the
      size of the miss you're seeing.

 Run it via:
   powershell -STA -NoProfile -ExecutionPolicy Bypass -File DiagnoseDpi.ps1
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public struct RECT3 { public int Left; public int Top; public int Right; public int Bottom; }

public static class DpiDiagNative
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT3 lpRect);
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT3 lpRect);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, int dwFlags);
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(POINT3 pt, int dwFlags);

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    public static List<KeyValuePair<IntPtr,string>> GetVisibleWindows()
    {
        var list = new List<KeyValuePair<IntPtr,string>>();
        EnumWindows((hWnd, lParam) =>
        {
            if (IsWindowVisible(hWnd))
            {
                int len = GetWindowTextLength(hWnd);
                if (len > 0)
                {
                    var sb = new StringBuilder(len + 1);
                    GetWindowText(hWnd, sb, sb.Capacity + 1);
                    string title = sb.ToString();
                    if (!string.IsNullOrWhiteSpace(title))
                        list.Add(new KeyValuePair<IntPtr,string>(hWnd, title));
                }
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}

public struct POINT3 { public int X; public int Y; }
"@

$MDT_EFFECTIVE_DPI = 0
$MONITOR_DEFAULTTONEAREST = 2

function Get-MonitorDpi {
    param([IntPtr]$MonitorHandle)
    $dpiX = 0; $dpiY = 0
    try {
        [void][DpiDiagNative]::GetDpiForMonitor($MonitorHandle, $MDT_EFFECTIVE_DPI, [ref]$dpiX, [ref]$dpiY)
        return $dpiX
    } catch { return $null }
}

# ---- Step 1: replicate the exact DPI-awareness call chain the other
# two scripts use, then ask Windows what actually took effect. ----
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Step 1: DPI awareness this process actually got" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow

$perMonitorV2 = [IntPtr](-4)
$stage = "NONE - all calls failed or threw"
try {
    if ([DpiDiagNative]::SetProcessDpiAwarenessContext($perMonitorV2)) {
        $stage = "SetProcessDpiAwarenessContext(PerMonitorV2) returned TRUE"
    } else {
        try {
            [void][DpiDiagNative]::SetProcessDpiAwareness(2)
            $stage = "Fell back to SetProcessDpiAwareness(2) - PerMonitorV2 call itself returned FALSE"
        } catch {
            [void][DpiDiagNative]::SetProcessDPIAware()
            $stage = "Fell back all the way to SetProcessDPIAware() - system-DPI-aware only"
        }
    }
} catch {
    $stage = "Threw an exception calling SetProcessDpiAwarenessContext: $_"
}
Write-Host "  Attempted: $stage"

$ctx = [DpiDiagNative]::GetThreadDpiAwarenessContext()
$awareness = [DpiDiagNative]::GetAwarenessFromDpiAwarenessContext($ctx)
# DPI_AWARENESS: -1 invalid, 0 Unaware, 1 System-aware, 2 Per-monitor-aware
$awarenessName = switch ($awareness) {
    0 { "UNAWARE  <-- likely BUG: coordinates get virtualized/rescaled on monitors that don't match the DPI baseline" }
    1 { "SYSTEM-AWARE  <-- one scale factor for ALL monitors - still wrong if your monitors use different %" }
    2 { "PER-MONITOR-AWARE  <-- correct: real pixels everywhere, this is what you want" }
    default { "UNKNOWN ($awareness)" }
}
Write-Host "  ACTUAL effective awareness right now: $awarenessName" -ForegroundColor Cyan
Write-Host ""

# ---- Step 2: every monitor, its bounds, and its real DPI/scaling ----
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Step 2: Your monitors and their scaling" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow

$screens = [System.Windows.Forms.Screen]::AllScreens
for ($i = 0; $i -lt $screens.Count; $i++) {
    $s = $screens[$i]
    $b = $s.Bounds
    $centerPt = New-Object POINT3
    $centerPt.X = $b.Left + [int]($b.Width / 2)
    $centerPt.Y = $b.Top + [int]($b.Height / 2)
    $hMon = [DpiDiagNative]::MonitorFromPoint($centerPt, $MONITOR_DEFAULTTONEAREST)
    $dpi = Get-MonitorDpi -MonitorHandle $hMon
    $pct = if ($dpi) { [math]::Round(($dpi / 96.0) * 100) } else { "?" }
    $primaryTag = if ($s.Primary) { " (PRIMARY)" } else { "" }
    Write-Host ("  Monitor {0}{1}: bounds ({2},{3})-({4},{5})  size {6}x{7}  DPI={8}  Scaling={9}%" -f `
        $i, $primaryTag, $b.Left, $b.Top, $b.Right, $b.Bottom, $b.Width, $b.Height, $dpi, $pct) -ForegroundColor Cyan
}
Write-Host ""

# ---- Step 3: pick the terminal window, compare its monitor to the rest ----
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Step 3: Your terminal window's monitor vs the others" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
$windows = [DpiDiagNative]::GetVisibleWindows()
for ($i = 0; $i -lt $windows.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f $i, $windows[$i].Value)
}
$winIdx = Read-Host "`nType the number next to your mainframe terminal window"
if (-not ($winIdx -as [int]) -or [int]$winIdx -lt 0 -or [int]$winIdx -ge $windows.Count) {
    Write-Host "Invalid choice - stopping here. You already have Steps 1-2 above." -ForegroundColor Red
    pause
    exit 0
}
$handle = $windows[[int]$winIdx].Key

$wRect = New-Object RECT3
[void][DpiDiagNative]::GetWindowRect($handle, [ref]$wRect)
$cRect = New-Object RECT3
[void][DpiDiagNative]::GetClientRect($handle, [ref]$cRect)
Write-Host ("`n  Window rect (screen coords)  = ({0},{1})-({2},{3})" -f $wRect.Left,$wRect.Top,$wRect.Right,$wRect.Bottom)
Write-Host ("  Client size                   = {0}x{1}" -f $cRect.Right,$cRect.Bottom)

$hMonWin = [DpiDiagNative]::MonitorFromWindow($handle, $MONITOR_DEFAULTTONEAREST)
$winDpi = Get-MonitorDpi -MonitorHandle $hMonWin
$winPct = if ($winDpi) { [math]::Round(($winDpi / 96.0) * 100) } else { "?" }
Write-Host ("  Terminal window's monitor DPI = {0}  (Scaling={1}%)" -f $winDpi, $winPct) -ForegroundColor Cyan

$winCtx = [DpiDiagNative]::GetWindowDpiAwarenessContext($handle)
$targetAware = [DpiDiagNative]::GetAwarenessFromDpiAwarenessContext($winCtx)
Write-Host ("  Terminal window's OWN reported DPI-awareness code = {0}  (0=Unaware 1=System 2=PerMonitor)" -f $targetAware) -ForegroundColor Cyan
Write-Host ""

Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " What this means" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host "- Look back at Step 1. If it's NOT 'PER-MONITOR-AWARE', this script (and by" -ForegroundColor Yellow
Write-Host "  extension CalibrateScreen1Auto.ps1 / AutoClipCapture.ps1, which use the same" -ForegroundColor Yellow
Write-Host "  fallback code) is getting coordinates in a virtualized space rather than real" -ForegroundColor Yellow
Write-Host "  pixels - that alone can fully explain a click landing far outside the window." -ForegroundColor Yellow
Write-Host "- Compare the scaling % of each monitor in Step 2 to each other, and to the" -ForegroundColor Yellow
Write-Host "  terminal window's monitor in Step 3. If they're NOT all the same percentage," -ForegroundColor Yellow
Write-Host "  that mismatch is very likely the root cause - Windows only virtualizes/rescales" -ForegroundColor Yellow
Write-Host "  coordinates for windows on a monitor whose scaling differs from the baseline," -ForegroundColor Yellow
Write-Host "  which is exactly why a single-monitor test might look fine while this doesn't." -ForegroundColor Yellow
Write-Host ""
pause
