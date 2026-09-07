<#
=====================================================================
 CalibrateScreen1ClickPosition.ps1

 Standalone helper - NOT dot-sourced by AutoClipCapture.ps1, run this
 one on its own (double-click, or "powershell -ExecutionPolicy Bypass
 -File CalibrateScreen1ClickPosition.ps1").

 Prints the mouse cursor's position, once per half second, relative to
 the CLIENT AREA of whichever window currently has focus - i.e. the
 exact same coordinate space AutoClipCapture's Screen1Select pipeline
 phase clicks into (ClientX/ClientY, via ClientToScreen). Use it to
 work out the 4 numbers that pipeline needs
 (OriginX / OriginY / CharWidthPx / CharHeightPx), in
 AutoClipCaptureConfig.json's Pipelines[].Screen1Select block:

   1. Run this script, then click the mainframe terminal window once
      to give it focus (keep this console window visible too, e.g. on
      a second monitor or snapped to a side).
   2. Position the target window exactly where/how it'll be sitting
      whenever the real pipeline runs later - this only stays accurate
      as long as the window doesn't move or get resized afterwards.
   3. Hover the mouse over the exact spot you'd click for the very
      first data row's selection field (one column to the left of
      "COB" by default - i.e. Screen1Select.ClickColumnOffset columns
      from where "COB" starts). Read off the X/Y this script prints
      -> that's OriginX/OriginY.
   4. Without moving the window, hover the same column several rows
      further down (the more rows apart, the more accurate the
      result) and read off Y again.
      CharHeightPx = (that Y - OriginY) / (number of rows down).
   5. Hover one column further right, same row as step 3, and read off
      X again. CharWidthPx = that X - OriginX.
   6. Put all 4 numbers into AutoClipCaptureConfig.json.

 Ctrl+C in this console window to stop.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct POINT { public int X; public int Y; }

public static class CalibNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
}
"@

Write-Host "Calibration running. Click the target window to focus it, then hover the mouse over reference points."
Write-Host "Printing the client-relative position under the cursor every 0.5s. Ctrl+C to stop."
Write-Host ""

while ($true) {
    Start-Sleep -Milliseconds 500

    $handle = [CalibNative]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        Write-Host "(no foreground window)"
        continue
    }

    $origin = New-Object POINT
    $origin.X = 0
    $origin.Y = 0
    [void][CalibNative]::ClientToScreen($handle, [ref]$origin)

    $cursor = [System.Windows.Forms.Cursor]::Position
    $clientX = $cursor.X - $origin.X
    $clientY = $cursor.Y - $origin.Y

    Write-Host ("Client-relative point under mouse:  X={0,-6} Y={1,-6}" -f $clientX, $clientY)
}
