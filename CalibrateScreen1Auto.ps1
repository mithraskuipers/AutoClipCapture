<#
=====================================================================
 CalibrateScreen1Auto.ps1

 Automatic replacement for CalibrateScreen1AutoGuided.ps1's manual
 "nudge with arrow keys until it looks right" steps.

 WHY THIS IS POSSIBLE: the terminal itself renders as a solid black
 rectangle sitting inside a visibly lighter window (menu bar, icon
 toolbar, status bar - see your own screenshots). That contrast is
 detectable in a screenshot. So instead of asking you to judge pixel
 alignment by eye, this script:
   1. Takes a screenshot of exactly the target window's client area
      (Graphics.CopyFromScreen - the window must be visible on top,
      not covered by another window, while this runs).
   2. Scans it row by row and column by column for the largest solid
      dark rectangle - that's the terminal grid, as opposed to the
      lighter menu/toolbar/status-bar chrome around it.
   3. Divides that rectangle's pixel width/height by the known fixed
      grid (80 columns x 32 rows) to get CharWidthPx/CharHeightPx -
      measured from the ACTUAL terminal area only, unlike
      CalibrateScreen1AutoGuided.ps1's original approach of dividing
      the WHOLE window client area by 80x32 (which silently counted
      the menu/toolbar/status-bar height as if it were extra terminal
      rows, and produced a CharHeightPx that was too small - accurate
      only right at the one manually-nudged row, and increasingly off
      moving down the page).
   4. Works out OriginX/OriginY from that rectangle's actual top-left
      corner.
   5. Copies the CURRENT screen (Ctrl+C) and finds the real first line
      with "COB" printed on it - ONCE. That line/column becomes
      FirstDataRowLineIndex/SelectionColumnIndex, saved into
      Screen1Select permanently. The real pipeline
      (AutoClipCaptureSqlPipelineScreen1.ps1) no longer reads page
      content at all to find rows - every row on every page is now
      pure arithmetic from these saved numbers (row N = first row +
      N x CharHeightPx). This only works because the header above the
      list is always exactly the same size - if that's not true for
      your screens, this whole approach isn't safe to use.
   6. Shows you the result and moves the mouse to the computed point
      for ONE quick look - press Enter to accept, Esc to cancel
      (nothing is saved on cancel; CalibrateScreen1AutoGuided.ps1 is
      still there as a manual fallback if detection ever gets it
      wrong, e.g. a non-black terminal color scheme).

 NOTE: make sure the terminal is showing a REPOSITORY LIST page with
 at least one visible "COB" row before running this - step 5 needs
 real COB text on screen to calibrate against, this one time.

 Run it via CalibrateScreen1Auto.bat.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Make THIS PROCESS DPI-aware before the screenshot/coordinate
# code below runs - MUST match AutoClipCapture.ps1's own DPI-awareness
# call exactly, or the two scripts will disagree about what a pixel
# is and every click will drift off by the display scaling percentage.
# See the matching comment at the top of AutoClipCapture.ps1 for why.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CR_DpiAwareness {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue

    $perMonitorV2 = [IntPtr](-4)
    $setDpi = $false
    try { $setDpi = [CR_DpiAwareness]::SetProcessDpiAwarenessContext($perMonitorV2) } catch {}
    if (-not $setDpi) {
        try { [void][CR_DpiAwareness]::SetProcessDpiAwareness(2) } catch {}
        try { [void][CR_DpiAwareness]::SetProcessDPIAware() } catch {}
    }
} catch {
    Write-Host "Could not set DPI awareness - if Windows display scaling isn't 100%, calibration will be off. $_" -ForegroundColor Yellow
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public struct POINT2 { public int X; public int Y; }
public struct RECT2 { public int Left; public int Top; public int Right; public int Bottom; }

public static class CalibNative4
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
    public static extern bool GetClientRect(IntPtr hWnd, out RECT2 lpRect);

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT2 lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

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

# A row/column counts as "terminal" if at least this fraction of its
# pixels are dark. The terminal's black background dominates even rows
# full of bright text; menu/toolbar/status-bar rows are mostly light
# with only a little dark text/icon detail, so they score far lower.
$DarkFraction   = 0.40
$DarkThreshold  = 40   # average of R,G,B below this counts as "dark"

function Get-WindowScreenshot {
    param([IntPtr]$Handle)

    $rect = New-Object RECT2
    [void][CalibNative4]::GetClientRect($Handle, [ref]$rect)
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { return $null }

    $topLeft = New-Object POINT2
    $topLeft.X = 0; $topLeft.Y = 0
    [void][CalibNative4]::ClientToScreen($Handle, [ref]$topLeft)

    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($topLeft.X, $topLeft.Y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    return $bmp
}

# Returns @{ Left; Top; Right; Bottom } (exclusive) of the largest solid
# dark rectangle in the bitmap, using fast LockBits byte access rather
# than the (very slow, one-call-per-pixel) Bitmap.GetPixel.
function Find-DarkRectangle {
    param([System.Drawing.Bitmap]$Bmp)

    $w = $Bmp.Width
    $h = $Bmp.Height
    $rectFull = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $bmpData = $Bmp.LockBits($rectFull, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    $bytes = New-Object byte[] ($bmpData.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($bmpData.Scan0, $bytes, 0, $bytes.Length)
    $Bmp.UnlockBits($bmpData)
    $stride = $bmpData.Stride

    # ---- Per-row dark fraction -> largest contiguous "dark" row band ----
    $rowDark = New-Object bool[] $h
    for ($y = 0; $y -lt $h; $y++) {
        $darkCount = 0
        $rowOffset = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $px = $rowOffset + ($x * 4)
            $b = $bytes[$px]; $gr = $bytes[$px + 1]; $r = $bytes[$px + 2]
            if ((([int]$r + [int]$gr + [int]$b) / 3) -lt $DarkThreshold) { $darkCount++ }
        }
        $rowDark[$y] = (($darkCount / [double]$w) -ge $DarkFraction)
    }

    $bestTop = -1; $bestBottom = -1; $bestLen = 0
    $curStart = -1
    for ($y = 0; $y -le $h; $y++) {
        $isDark = ($y -lt $h) -and $rowDark[$y]
        if ($isDark -and $curStart -lt 0) { $curStart = $y }
        elseif (-not $isDark -and $curStart -ge 0) {
            $len = $y - $curStart
            if ($len -gt $bestLen) { $bestLen = $len; $bestTop = $curStart; $bestBottom = $y }
            $curStart = -1
        }
    }
    if ($bestTop -lt 0) { return $null }

    # ---- Per-column dark fraction, restricted to those rows -> left/right ----
    $bandHeight = $bestBottom - $bestTop
    $colDark = New-Object bool[] $w
    for ($x = 0; $x -lt $w; $x++) {
        $darkCount = 0
        for ($y = $bestTop; $y -lt $bestBottom; $y++) {
            $px = ($y * $stride) + ($x * 4)
            $b = $bytes[$px]; $gr = $bytes[$px + 1]; $r = $bytes[$px + 2]
            if ((([int]$r + [int]$gr + [int]$b) / 3) -lt $DarkThreshold) { $darkCount++ }
        }
        $colDark[$x] = (($darkCount / [double]$bandHeight) -ge $DarkFraction)
    }

    $bestLeft = -1; $bestRight = -1; $bestColLen = 0
    $curStart = -1
    for ($x = 0; $x -le $w; $x++) {
        $isDark = ($x -lt $w) -and $colDark[$x]
        if ($isDark -and $curStart -lt 0) { $curStart = $x }
        elseif (-not $isDark -and $curStart -ge 0) {
            $len = $x - $curStart
            if ($len -gt $bestColLen) { $bestColLen = $len; $bestLeft = $curStart; $bestRight = $x }
            $curStart = -1
        }
    }
    if ($bestLeft -lt 0) { return $null }

    return @{ Left = $bestLeft; Top = $bestTop; Right = $bestRight; Bottom = $bestBottom }
}

# Mirrors AutoClipCaptureSqlPipelineScreen1.ps1's Get-Screen1DataRows:
# finds the first line that actually has "COB" printed on it, and the
# 0-based (line, column) it's at on THIS screen - never a hardcoded
# row/column guess. This is what makes the preview below test the
# exact same thing the real pipeline will click on, instead of a
# fixed row/column number that may not match this screen's layout.
function Get-FirstCobMatch {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $lines = $Text -split "`r`n|`n|`r"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '\bCOB\b')
        if ($m.Success) {
            return [pscustomobject]@{ LineIndex = $i; ColIndex = $m.Index; LineText = $lines[$i] }
        }
    }
    return $null
}

Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Screen1Select Automatic Calibration" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "ASSUMPTIONS this calibration relies on:" -ForegroundColor Magenta
Write-Host "  - Windows display scaling is set to 100% (Settings > System > Display)." -ForegroundColor Magenta
Write-Host "  - The terminal's font size / window size won't change after this runs -" -ForegroundColor Magenta
Write-Host "    if either does, the saved numbers go stale and you'll need to" -ForegroundColor Magenta
Write-Host "    recalibrate (clicks will drift, worse further down the page)." -ForegroundColor Magenta
Write-Host "  - The terminal window is fully visible on screen and not covered by" -ForegroundColor Magenta
Write-Host "    another window right when the screenshot below is taken." -ForegroundColor Magenta
Write-Host "  - The terminal renders on a solid dark/black background (this is what" -ForegroundColor Magenta
Write-Host "    the detection below actually looks for)." -ForegroundColor Magenta
Write-Host ""

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

# ClickColumnOffset: how many characters LEFT of "COB" the selection
# field sits. This is the only fixed assumption left - unlike the old
# cobColumn/firstDataRow guesses, AutoClipCaptureSqlPipelineScreen1.ps1
# never assumes which column/row "COB" itself is on; it finds "COB" on
# the real screen first and adds this offset to whatever column that
# turned out to be. The preview below now does exactly the same thing,
# so there's no separate row/column guess left to go stale.
$clickColumnOffset = -2
$cols = 80
$rows = 32
$chosenPipeline.Screen1Select.ClickColumnOffset = $clickColumnOffset

Write-Host "`nMake sure your terminal window is open, fully visible, and NOT covered by another window." -ForegroundColor Cyan
Write-Host "Open windows:"
$windows = [CalibNative4]::GetVisibleWindows()
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
[void][CalibNative4]::SetForegroundWindow($targetHandle)
Start-Sleep -Milliseconds 300   # give it a moment to actually come to the front before the screenshot

Write-Host "`nTaking a screenshot and looking for the terminal grid..." -ForegroundColor Cyan
$bmp = Get-WindowScreenshot -Handle $targetHandle
if ($null -eq $bmp) {
    Write-Host "Couldn't read that window's size/screenshot. Nothing changed." -ForegroundColor Red
    pause
    exit 1
}

$box = Find-DarkRectangle -Bmp $bmp
$bmp.Dispose()

if ($null -eq $box -or ($box.Right - $box.Left) -lt 100 -or ($box.Bottom - $box.Top) -lt 100) {
    Write-Host "`nCouldn't confidently find a solid dark terminal rectangle in that window." -ForegroundColor Red
    Write-Host "(Maybe the terminal uses a light color scheme, or another window was on top of it.)" -ForegroundColor Red
    Write-Host "Use CalibrateScreen1AutoGuided.bat instead - it doesn't rely on detecting a dark background." -ForegroundColor Yellow
    pause
    exit 1
}

$boxWidth  = $box.Right - $box.Left
$boxHeight = $box.Bottom - $box.Top
$CharWidthPx  = [math]::Round(($boxWidth / $cols), 2)
$CharHeightPx = [math]::Round(($boxHeight / $rows), 2)

# Sanity-check the measured cell size against plausible terminal font
# dimensions, so a bad detection (e.g. it found some other dark UI
# panel instead of the actual terminal) gets caught here instead of
# silently producing bad click coordinates later.
if ($CharWidthPx -lt 4 -or $CharWidthPx -gt 30 -or $CharHeightPx -lt 6 -or $CharHeightPx -gt 50) {
    Write-Host "`nDetected rectangle is $boxWidth x $boxHeight px, giving an implausible char size" -ForegroundColor Red
    Write-Host "($CharWidthPx x $CharHeightPx px). That's probably not the terminal grid." -ForegroundColor Red
    Write-Host "Use CalibrateScreen1AutoGuided.bat instead." -ForegroundColor Yellow
    pause
    exit 1
}

# Row-0/column-0 origin (cell CENTER), matching the exact convention
# AutoClipCaptureSqlPipelineScreen1.ps1's click formula expects:
#   ClientX = OriginX + Col * CharWidthPx
#   ClientY = OriginY + Row * CharHeightPx
$OriginX = [math]::Round($box.Left + ($CharWidthPx / 2))
$OriginY = [math]::Round($box.Top + ($CharHeightPx / 2))

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Detected" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host ("  Terminal box   = {0}x{1} px (at client offset {2},{3})" -f $boxWidth, $boxHeight, $box.Left, $box.Top)
Write-Host ("  OriginX        = {0}" -f $OriginX)
Write-Host ("  OriginY        = {0}" -f $OriginY)
Write-Host ("  CharWidthPx    = {0}" -f $CharWidthPx)
Write-Host ("  CharHeightPx   = {0}" -f $CharHeightPx)

# ---- Find the REAL first "COB" row on whatever screen is showing
# right now, instead of assuming a fixed row/column - this is the part
# that used to be hardcoded (cobColumn=5, firstDataRow=7) and could be
# wrong for a given screen's actual layout. Make sure your terminal is
# currently showing a REPOSITORY LIST page with at least one COB row
# visible before continuing. ----
Write-Host "`nCopying the current screen to find the real first 'COB' row..." -ForegroundColor Cyan
[void][CalibNative4]::SetForegroundWindow($targetHandle)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('^c')

$copiedText = $null
for ($try = 0; $try -lt 10; $try++) {
    Start-Sleep -Milliseconds 150
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $candidate = [System.Windows.Forms.Clipboard]::GetText()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $copiedText = $candidate; break }
        }
    } catch {}
}

$cobMatch = Get-FirstCobMatch -Text $copiedText
if ($null -eq $cobMatch) {
    Write-Host "`nCouldn't find any line with 'COB' on the current screen." -ForegroundColor Red
    Write-Host "Navigate the terminal to a REPOSITORY LIST page that actually shows COB rows, then run this again." -ForegroundColor Red
    pause
    exit 1
}
Write-Host ("  First 'COB' found at line {0}, column {1}: `"{2}`"" -f $cobMatch.LineIndex, $cobMatch.ColIndex, $cobMatch.LineText.Trim()) -ForegroundColor Cyan

# Confirmed against a real Ctrl+Shift+M run: the line index found above
# consistently lands one row ABOVE the true first data row - most
# likely because the Ctrl+C clipboard text's line 0 sits one line
# below the detected rectangle's visual top edge (OriginY), not
# exactly at it. Correcting by +1 here (and saving that corrected
# value below) makes what you see in THIS preview match what the real
# pipeline will actually click.
$realLineIndex = $cobMatch.LineIndex + 1

$targetColIndex = $cobMatch.ColIndex + $clickColumnOffset
$confirmX = $OriginX + ($targetColIndex * $CharWidthPx)
$confirmY = $OriginY + ($realLineIndex * $CharHeightPx)

$pt = New-Object POINT2
$pt.X = [int][math]::Round($confirmX)
$pt.Y = [int][math]::Round($confirmY)
[void][CalibNative4]::ClientToScreen($targetHandle, [ref]$pt)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pt.X, $pt.Y)

Write-Host ""
Write-Host "Pointer moved to the computed first-data-row selection field (next to 'COB')." -ForegroundColor Cyan
Write-Host "Look at the terminal - does it land there? ENTER to save, Esc to cancel." -ForegroundColor Cyan
Write-Host "(Reminder: this assumes 100% display scaling and today's font/window size." -ForegroundColor DarkGray
Write-Host " Recalibrate if either changes later.)" -ForegroundColor DarkGray
while ($true) {
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'Enter') { break }
    if ($key.Key -eq 'Escape') {
        Write-Host "`nCancelled - nothing saved." -ForegroundColor Yellow
        pause
        exit 0
    }
}

$chosenPipeline.Screen1Select.OriginX = $OriginX
$chosenPipeline.Screen1Select.OriginY = $OriginY
$chosenPipeline.Screen1Select.CharWidthPx = $CharWidthPx
$chosenPipeline.Screen1Select.CharHeightPx = $CharHeightPx

# These two are now the permanent, fixed row/column constants the real
# pipeline uses for EVERY row on EVERY page (no more per-row text
# scanning at runtime - see AutoClipCaptureSqlPipelineScreen1.ps1's
# Get-Screen1FixedRows). They only need to be right once: LineIndex is
# where row 1 of data sits (only valid because the header above the
# list is always the same fixed size), ColIndex is where "Type" text
# (COB/ASM) starts - the selection field itself is ColIndex + ClickColumnOffset.
foreach ($prop in @(
    @{ Name = 'FirstDataRowLineIndex'; Value = $realLineIndex },
    @{ Name = 'SelectionColumnIndex';  Value = $cobMatch.ColIndex  }
)) {
    if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains $prop.Name)) {
        $chosenPipeline.Screen1Select | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    } else {
        $chosenPipeline.Screen1Select.($prop.Name) = $prop.Value
    }
}

$calibNote = "Auto-calibrated {0} assuming 100% Windows display scaling AND that the header above the list is always exactly this many lines. Recalibrate if display scaling, the terminal's font size, the window size, or the header's line count changes." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains 'CalibrationNote')) {
    $chosenPipeline.Screen1Select | Add-Member -NotePropertyName CalibrationNote -NotePropertyValue $calibNote -Force
} else {
    $chosenPipeline.Screen1Select.CalibrationNote = $calibNote
}

$backupPath = Join-Path $PSScriptRoot ("AutoClipCaptureConfig.backup-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -Path $configPath -Destination $backupPath -Force
Write-Host ("`nBacked up old config to: {0}" -f (Split-Path $backupPath -Leaf))

$config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "Done! AutoClipCaptureConfig.json has been updated." -ForegroundColor Green
Write-Host "Close this window and try Ctrl+Shift+M again." -ForegroundColor Green
Write-Host ""
pause
