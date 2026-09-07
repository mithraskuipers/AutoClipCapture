<#
=====================================================================
 CalibrateScreen1AutoGuided.ps1

 The easiest way to fill in Pipelines[].Screen1Select's OriginX /
 OriginY / CharWidthPx / CharHeightPx.

 You don't hover or hunt for anything. You just answer a few simple
 number questions (window from a list, how many columns/rows the
 terminal shows, which column "COB" starts on, which row the first
 data line is on). The script then:

   1. Calculates a starting guess from the window's size and that
      grid info.
   2. Moves your mouse pointer there FOR you, so you can just look
      at the terminal and see if it landed in the right spot.
   3. If it's off, nudge it with the arrow keys (hold Shift for
      bigger jumps) and press Enter to confirm. If it looks right
      already, just press Enter.
   4. Repeats that 2 more times to also work out the character
      width/height, then saves everything into
      AutoClipCaptureConfig.json for you (after backing up the old
      one).

 Run it via CalibrateScreen1AutoGuided.bat - no PowerShell
 knowledge required. Ctrl+C at any time aborts without changing
 the config file. Only needs re-running if the terminal window's
 size/position changes.

 Fix note: OriginX/OriginY are saved as the row-0/column-0 point of
 the click grid (not the first-data-row point itself), since that's
 what AutoClipCaptureSqlPipelineScreen1Select.ps1's click formula
 expects. Saving the first-data-row point directly used to double-
 count that offset on every click, landing several rows/columns off
 target during the SQL pipeline's row-selection phase.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public struct POINT { public int X; public int Y; }
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

public static class CalibNative3
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
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

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
                    {
                        list.Add(new KeyValuePair<IntPtr,string>(hWnd, title));
                    }
                }
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

function Move-CursorToClientPoint {
    param($Handle, [double]$X, [double]$Y)
    $pt = New-Object POINT
    $pt.X = [int][math]::Round($X)
    $pt.Y = [int][math]::Round($Y)
    [void][CalibNative3]::ClientToScreen($Handle, [ref]$pt)
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pt.X, $pt.Y)
}

function Confirm-Point {
    param($Handle, [ref]$X, [ref]$Y, [string]$AxisMode, [string]$Instruction)
    Write-Host ""
    Write-Host $Instruction -ForegroundColor Cyan
    while ($true) {
        Move-CursorToClientPoint -Handle $Handle -X $X.Value -Y $Y.Value
        Write-Host ("  Pointer moved. Arrow keys to nudge (Shift+arrow = bigger step), ENTER to confirm.") -NoNewline
        Write-Host ("   [X={0} Y={1}]" -f [math]::Round($X.Value,1), [math]::Round($Y.Value,1))
        $key = [Console]::ReadKey($true)
        $step = 1
        if ($key.Modifiers -band [ConsoleModifiers]::Shift) { $step = 10 }
        switch ($key.Key) {
            'Enter'      { return }
            'UpArrow'    { if ($AxisMode -ne 'horizontal') { $Y.Value -= $step } }
            'DownArrow'  { if ($AxisMode -ne 'horizontal') { $Y.Value += $step } }
            'LeftArrow'  { if ($AxisMode -ne 'vertical')   { $X.Value -= $step } }
            'RightArrow' { if ($AxisMode -ne 'vertical')   { $X.Value += $step } }
        }
    }
}

function Read-NumberOrDefault {
    param([string]$Prompt, [double]$Default)
    $raw = Read-Host ("{0} [Enter for {1}]" -f $Prompt, $Default)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    $val = 0.0
    if ([double]::TryParse($raw, [ref]$val)) { return $val }
    return $Default
}

Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Screen1Select Auto-Guided Calibration" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow

# ---- Load config first, so we know ClickColumnOffset and where to save ----
$configPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Could not find AutoClipCaptureConfig.json next to this script." -ForegroundColor Red
    pause
    exit 1
}
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

$targets = @()
foreach ($pipeline in $config.Pipelines) {
    if ($null -ne $pipeline.Screen1Select) { $targets += $pipeline }
}
if ($targets.Count -eq 0) {
    Write-Host "No pipeline with a Screen1Select block was found in the config. Nothing to calibrate." -ForegroundColor Red
    pause
    exit 1
}
$chosenPipeline = $targets[0]
if ($targets.Count -gt 1) {
    Write-Host "`nMultiple pipelines need calibration. Which one?"
    for ($i = 0; $i -lt $targets.Count; $i++) { Write-Host ("  [{0}] {1} ({2})" -f $i, $targets[$i].Name, $targets[$i].Id) }
    $pIdx = Read-Host "Enter the number"
    $chosenPipeline = $targets[[int]$pIdx]
}

# Fixed for this setup: "COB" always starts at column 5, and the
# selection field where the action letter (e.g. "B") gets typed is
# always columns 2-3. We click the left edge of that field (column 2).
$cobColumn = 5
$clickTargetColumn = 3
$clickColumnOffset = $clickTargetColumn - $cobColumn   # -2
$chosenPipeline.Screen1Select.ClickColumnOffset = $clickColumnOffset

# ---- Pick the target window from a list (no clicking required) ----
Write-Host "`nMake sure your terminal window is open and positioned where it'll stay." -ForegroundColor Cyan
Write-Host "Open windows:"
$windows = [CalibNative3]::GetVisibleWindows()
for ($i = 0; $i -lt $windows.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f $i, $windows[$i].Value)
}
$winIdx = Read-Host "`nType the number next to your mainframe terminal window"
if (-not ($winIdx -as [int]) -or [int]$winIdx -lt 0 -or [int]$winIdx -ge $windows.Count) {
    Write-Host "Invalid choice. Nothing changed." -ForegroundColor Red
    pause
    exit 1
}
$targetHandle = $windows[[int]$winIdx].Key

$rect = New-Object RECT
[void][CalibNative3]::GetClientRect($targetHandle, [ref]$rect)
$clientW = $rect.Right - $rect.Left
$clientH = $rect.Bottom - $rect.Top
if ($clientW -le 0 -or $clientH -le 0) {
    Write-Host "Couldn't read that window's size. Nothing changed." -ForegroundColor Red
    pause
    exit 1
}

# ---- No questions left - everything is fixed ----
$cols = 80
$rows = 32
$firstDataRow = 7   # first 6 rows are skipped as header, so the first data row is row 7
Write-Host "`nTerminal display fixed at $cols columns x $rows rows. 'COB' at column $cobColumn, click target at column $clickTargetColumn, first data row $firstDataRow." -ForegroundColor Cyan

# Character size comes straight from the window's pixel size divided
# by the known 80x32 grid - no separate checkpoint needed for this,
# since there's nothing on-screen to visually judge "10 rows down"
# against anyway.
$CharWidthPx = [math]::Round(($clientW / $cols), 2)
$CharHeightPx = [math]::Round(($clientH / $rows), 2)

$targetColIndex = ($cobColumn - 1) + $clickColumnOffset
$originX = ($targetColIndex * $CharWidthPx) + ($CharWidthPx / 2)
$originY = (($firstDataRow - 1) * $CharHeightPx) + ($CharHeightPx / 2)

# ---- The one check you can actually judge by eye: does the pointer ----
# ---- land next to the real, visible "COB" text? ----
Confirm-Point -Handle $targetHandle -X ([ref]$originX) -Y ([ref]$originY) -AxisMode 'both' `
    -Instruction "Look at the terminal. Is the pointer on the first data row, $($cobColumn - $clickTargetColumn) column(s) left of 'COB'? Nudge if not, then Enter."

$OriginX = [math]::Round($originX)
$OriginY = [math]::Round($originY)

# ---- Convert the verified point above (which is the pixel position
# of ROW $($firstDataRow-1) / COLUMN $targetColIndex, 0-based) into the
# row-0/column-0 origin that AutoClipCaptureSqlPipelineScreen1Select.ps1's
# click formula actually expects:
#   ClientX = OriginX + Col * CharWidthPx
#   ClientY = OriginY + Row * CharHeightPx
# Saving the verified point itself (as earlier versions of this script
# did) double-counts that offset at click time - every row then gets
# clicked $($firstDataRow-1) rows and $targetColIndex columns further
# down/right than intended, which is what caused rows to appear to
# get "skipped" (really: the wrong row got clicked) during the SQL
# pipeline's component-selection phase.
$OriginX = $OriginX - ($targetColIndex * $CharWidthPx)
$OriginY = $OriginY - (($firstDataRow - 1) * $CharHeightPx)
$OriginX = [math]::Round($OriginX)
$OriginY = [math]::Round($OriginY)

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Results" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host ("  OriginX       = {0}" -f $OriginX)
Write-Host ("  OriginY       = {0}" -f $OriginY)
Write-Host ("  CharWidthPx   = {0}" -f $CharWidthPx)
Write-Host ("  CharHeightPx  = {0}" -f $CharHeightPx)


if ($CharWidthPx -le 0 -or $CharHeightPx -le 0) {
    Write-Host "`nCharWidthPx or CharHeightPx came out zero or negative - step 2 or 3 wasn't actually" -ForegroundColor Red
    Write-Host "further down/right than step 1. Nothing was saved. Please run this again." -ForegroundColor Red
    pause
    exit 1
}

$chosenPipeline.Screen1Select.OriginX = $OriginX
$chosenPipeline.Screen1Select.OriginY = $OriginY
$chosenPipeline.Screen1Select.CharWidthPx = $CharWidthPx
$chosenPipeline.Screen1Select.CharHeightPx = $CharHeightPx

$backupPath = Join-Path $PSScriptRoot ("AutoClipCaptureConfig.backup-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -Path $configPath -Destination $backupPath -Force
Write-Host ("`nBacked up old config to: {0}" -f (Split-Path $backupPath -Leaf))

$config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "Done! AutoClipCaptureConfig.json has been updated." -ForegroundColor Green
Write-Host "Close this window and try Ctrl+Shift+M again." -ForegroundColor Green
Write-Host ""
pause
