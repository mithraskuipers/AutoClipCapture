<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 Screen 1 = the REPOSITORY LIST overview (Type/Name/Appl/Subappl/
 Status columns, one row per component, "Row x of y ... More -->").

 This file drives the Ctrl+Shift+M pipeline's main job: walk every row
 slot of Screen 1, page by page, and for each one:
   0. Row positions are FIXED, pure arithmetic - no page content is
      read to find them. Screen1Select.FirstDataRowLineIndex and
      Screen1Select.SelectionColumnIndex (set once by
      CalibrateScreen1Auto.ps1, by actually finding the real first
      "COB" row on a real screen) anchor row 0; every following row is
      just + CharHeightPx per row, for exactly RowsPerPage rows. This
      only works because the header above the list (title/"Show
      Deleted: N"/column headers/filter line) is always exactly the
      same size on every page - if that ever isn't true, row math
      drifts and this whole approach stops being safe.
   1. Every row slot is tried - there's no "is this actually a COB
      row" check anymore. A slot with nothing real in it (past the end
      of a partially-filled last page, or a non-COB row type) simply
      doesn't navigate anywhere; step 4 below already treats that as
      the normal "nothing happened, move on" case, so no separate
      blank-detection step is needed.
   1a. Click Screen1Select.ClickColumnOffset character columns to the
      left of SelectionColumnIndex (default -2, lands on the "_"
      selection field) using the pixel math calibrated by
      CalibrateScreen1Auto.ps1/CalibrateScreen1AutoGuided.ps1 into
      Pipelines[].Screen1Select (OriginX/OriginY/CharWidthPx/
      CharHeightPx).
   2. Type Screen1Select.SelectionText (default "B") and press Enter.
   3. Confirm we landed on Screen 2 (COMPONENT VERSION - SELECT). If we
      did, hand off to AutoClipCaptureSqlPipelineScreen2.ps1, which
      logs it (if enabled) and queues a single F3 "back" to Screen 1
      (that shared "go back" mechanic lives in AutoClipCapture.ps1
      itself - see Back_Action/Back_Wait/Back_Copy).
   4. If nothing happened (blank slot, non-COB row, or the item is
      unavailable) - we're still on Screen 1 - just move on to the
      next row slot without going back.
   5. Once every row slot on the current page (RowsPerPage of them)
      has been tried, press Screen1Select.PageNextToken (F8 by
      default) to bring the next page into view, and keep going with
      the SAME fixed row slots - until either
      Screen1Select.EndOfListText shows up (explicit "end of list"
      marker) or a freshly-paged screen comes back near-identical to
      the one before it (Screen1Select.DupDetectThreshold - same
      comparison the duplicate-capture protection elsewhere uses),
      which means paging further isn't revealing anything new either.

 States (all start with "Comp" so AutoClipCapture.ps1's tick switch
 routes them here):
   CompScan_Action  - build the fixed row-slot list (Get-Screen1FixedRows,
                      pure arithmetic, no clipboard read needed). This
                      exact name is also the pipeline's hard-coded
                      starting state (see the Ctrl+Shift+M hotkey
                      handler), so a pipeline with no ComponentList
                      pre-pass lands here immediately.
   CompZoom_Action  - click the row at
                      $global:CR_PipelineScreen1Rows[$global:CR_PipelineComponentIdx],
                      type the selection letter, press Enter.
   CompZoom_Wait    - short delay before copying, so the new screen
                      has time to render.
   CompZoom_Copy    - Ctrl+C, read the clipboard, work out what
                      happened, branch accordingly (see below).
   CompNext_Action  - decide the next row (same page) or trigger a
                      page turn. Reached either right after a
                      non-navigating row (still on Screen 1) or once
                      Screen 2 has been dealt with and Back_Copy has
                      confirmed we're back on Screen 1. This exact
                      name also doubles as the "AfterBack" marker the
                      shared Back_Copy logic checks to know it should
                      expect Screen 1 (not Screen 2) once the F3
                      completes.
   CompPage_Action  - send Screen1Select.PageNextToken (e.g. F8) to
                      move to the next page.
   CompPage_Wait    - short delay before copying the new page.
   CompPage_Copy    - Ctrl+C, check EndOfListText / duplicate-page
                      (still genuinely needs the page's text - that's
                      the one place content is still read, purely to
                      know when to STOP paging, never to find rows);
                      either stop (pipeline complete) or rebuild the
                      same fixed row-slot list and keep going from row
                      0 of the new page.

 $global:CR_PipelineComponentIdx is the 0-based index *into
 $global:CR_PipelineScreen1Rows* (0..RowsPerPage-1, always the same
 fixed slots). Both are reset by AutoClipCapture.ps1 whenever the
 pipeline (re)starts, and reset again here every time a new page comes
 in.
=====================================================================
#>

# Builds the fixed set of row slots for one page - RowsPerPage of
# them, starting at FirstDataRowLineIndex/SelectionColumnIndex (set
# once, for real, by CalibrateScreen1Auto.ps1's Ctrl+C-based
# detection) and stepping one line at a time. No page content is read
# here at all: every page gets literally the same LineIndex/ColIndex
# list, because the header above the list is always the same size.
function Get-Screen1FixedRows {
    param($Screen1Select)

    $rows = New-Object System.Collections.Generic.List[object]
    $firstLine = [int]$Screen1Select.FirstDataRowLineIndex
    $col       = [int]$Screen1Select.SelectionColumnIndex
    $count     = [int]$Screen1Select.RowsPerPage

    for ($i = 0; $i -lt $count; $i++) {
        $rows.Add([pscustomobject]@{
            LineIndex = $firstLine + $i
            ColIndex  = $col
        })
    }

    return $rows
}

# Works out the on-screen (screen-coordinate) point for one row slot,
# using the OriginX/OriginY/CharWidthPx/CharHeightPx calibration
# CalibrateScreen1Auto.ps1 produces, and the LineIndex/ColIndex that
# Get-Screen1FixedRows generated for that slot (pure arithmetic off
# FirstDataRowLineIndex/SelectionColumnIndex - not read from content).
function Get-Screen1RowScreenPoint {
    param(
        [IntPtr]$Handle,
        $Screen1Select,
        [int]$LineIndex,
        [int]$ColIndex
    )

    $targetColIndex = $ColIndex + [int]$Screen1Select.ClickColumnOffset

    $clientX = [double]$Screen1Select.OriginX + ($targetColIndex * [double]$Screen1Select.CharWidthPx)
    $clientY = [double]$Screen1Select.OriginY + ($LineIndex * [double]$Screen1Select.CharHeightPx)

    # ---- Manual display-scaling correction (entered at Ctrl+Shift+M
    # start via Show-ScalingPrompt in AutoClipCapture.ps1). Screen1Select
    # was measured from a real-pixel screenshot; if the process actually
    # sending the click isn't running in that same real-pixel coordinate
    # space (Windows DPI virtualization), this converts for it. At the
    # default of 100 this multiplier is exactly 1.0 - a complete no-op. ----
    $scaleFactor = 100.0 / [double]$global:CR_PipelineScalePercent
    $clientX = $clientX * $scaleFactor
    $clientY = $clientY * $scaleFactor

    $pt = New-Object POINT
    $pt.X = [int][math]::Round($clientX)
    $pt.Y = [int][math]::Round($clientY)
    [void][Win32]::ClientToScreen($Handle, [ref]$pt)
    return $pt
}

# Moves the real mouse cursor to a screen-coordinate point and performs
# a single left click there. Used instead of keyboard navigation because
# the REPOSITORY LIST screen expects a line-command letter typed
# directly into each row's own selection field, not a highlighted-item
# Enter/Down style list.
function Invoke-Screen1RowClick {
    param([System.Drawing.Point]$ScreenPoint)

    [void][Win32]::SetCursorPos($ScreenPoint.X, $ScreenPoint.Y)
    Start-Sleep -Milliseconds 20
    [Win32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # MOUSEEVENTF_LEFTDOWN
    Start-Sleep -Milliseconds 20
    [Win32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # MOUSEEVENTF_LEFTUP
}

function Invoke-PipelineScreen1Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $s1       = $pipeline.Screen1Select

    switch ($global:CR_PipelineState) {

        'CompScan_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0 -or $null -eq $s1.FirstDataRowLineIndex -or $null -eq $s1.SelectionColumnIndex) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run CalibrateScreen1Auto.bat first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            # Fixed row slots - pure arithmetic, no Ctrl+C/clipboard
            # read needed at all to find them.
            $global:CR_PipelineScreen1Rows   = Get-Screen1FixedRows -Screen1Select $s1
            $global:CR_PipelineComponentIdx  = 0
            $global:CR_PipelineState = 'CompZoom_Action'
            $global:CR_ElapsedMs     = 0
        }

        'CompZoom_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0 -or $null -eq $s1.FirstDataRowLineIndex -or $null -eq $s1.SelectionColumnIndex) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run CalibrateScreen1Auto.bat first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            $rowIdx = [int]$global:CR_PipelineComponentIdx
            $row = $global:CR_PipelineScreen1Rows[$rowIdx]
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)

            if (-not $global:CR_PipelineStepPending) {
                $wr = New-Object RECT
                [void][Win32]::GetWindowRect($global:CR_TargetHandle, [ref]$wr)
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Row $($rowIdx + 1): LineIndex=$($row.LineIndex) ColIndex=$($row.ColIndex) -> click ($($screenPt.X),$($screenPt.Y))  |  Screen1Select Origin=($($s1.OriginX),$($s1.OriginY)) CharSize=$($s1.CharWidthPx)x$($s1.CharHeightPx)  |  Scaling=$($global:CR_PipelineScalePercent)%  |  Target window bounds ($($wr.Left),$($wr.Top))-($($wr.Right),$($wr.Bottom))" -ForegroundColor DarkGray
                if ($screenPt.X -lt $wr.Left -or $screenPt.X -gt $wr.Right -or $screenPt.Y -lt $wr.Top -or $screenPt.Y -gt $wr.Bottom) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] WARNING: that click point is OUTSIDE the target window's bounds - Screen1Select needs recalibrating (CalibrateScreen1Auto.bat)." -ForegroundColor Red
                }
            }

            # Shown BEFORE anything is clicked - the red circle marker
            # lands on $screenPt so a wrong target is obvious right
            # away, without a single click having happened yet.
            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - about to click here, type '$($s1.SelectionText)' + Enter"
            if (Request-PipelineStepConfirm -Description $desc -MarkerPoint $screenPt) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - selecting" ([System.Drawing.Color]::Lime)
            Invoke-Screen1RowClick -ScreenPoint $screenPt
            Start-Sleep -Milliseconds 20
            [System.Windows.Forms.SendKeys]::SendWait([string]$s1.SelectionText + '{ENTER}')

            $global:CR_PipelineState = 'CompZoom_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompZoom_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompZoom_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompZoom_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $CopyDelayMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                        $text = [System.Windows.Forms.Clipboard]::GetText()
                    }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
                }

                $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name

                if ($detected -eq 2) {
                    # Landed on Screen 2 (COMPONENT VERSION - SELECT).
                    # Hand off to Screen2.ps1 to log it and queue the
                    # single F3 back to Screen 1.
                    $global:CR_PipelineScreen1RetryCount   = 0
                    $global:CR_PipelineScreen2CapturedText = $text
                    $global:CR_PipelineState = 'EnvLog_Action'
                    $global:CR_ElapsedMs     = 0
                }
                elseif ($detected -eq 1) {
                    # Still on Screen 1 - this row's selection field
                    # didn't lead anywhere (blank row, or the item is
                    # unavailable). Nothing to go "back" from - just
                    # move on to the next row.
                    $global:CR_PipelineScreen1RetryCount = 0
                    $global:CR_PipelineState = 'CompNext_Action'
                    $global:CR_ElapsedMs     = 0
                }
                else {
                    # Unrecognized screen (e.g. the terminal hadn't
                    # finished redrawing yet). Retry the same row a few
                    # times before giving up on it, rather than either
                    # spinning forever or aborting the whole pipeline
                    # over one slow screen.
                    $global:CR_PipelineScreen1RetryCount++
                    $maxRetries = [int]$s1.MaxRowRetries
                    if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Row $($global:CR_PipelineComponentIdx + 1) on page $($global:CR_PipelineScreen1PageIdx + 1) gave an unrecognized screen $maxRetries time(s) in a row - skipping it." -ForegroundColor Yellow
                        $global:CR_PipelineScreen1RetryCount = 0
                        $global:CR_PipelineState = 'CompNext_Action'
                    } else {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unrecognized screen after selecting row $($global:CR_PipelineComponentIdx + 1) - retrying ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                        $global:CR_PipelineState = 'CompZoom_Action'
                    }
                    $global:CR_ElapsedMs = 0
                }
            }
        }

        'CompNext_Action' {
            $nextRow = [int]$global:CR_PipelineComponentIdx + 1
            if ($nextRow -lt $global:CR_PipelineScreen1Rows.Count) {
                $global:CR_PipelineComponentIdx = $nextRow
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            } else {
                # Every detected row on this page has been tried - page forward.
                $global:CR_PipelineState = 'CompPage_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompPage_Action' {
            if ([int]$global:CR_PipelineScreen1PageIdx + 1 -ge [int]$s1.MaxPages) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Reached the MaxPages safety limit ($($s1.MaxPages)) - stopping." -ForegroundColor Yellow
                Show-RelayResultOverlay -Text "STOPPED (page limit reached)" -Color ([System.Drawing.Color]::Gray)
                Stop-PipelineCapture
                return
            }

            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press $($s1.PageNextDisplay) to page forward"
            if (Request-PipelineStepConfirm -Description $desc) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Paging to next screen ($($s1.PageNextDisplay))" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait([string]$s1.PageNextToken)
            $global:CR_PipelineState = 'CompPage_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompPage_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompPage_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompPage_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $CopyDelayMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                        $text = [System.Windows.Forms.Clipboard]::GetText()
                    }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
                }

                [void](Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name)

                $isEndOfList = Test-RelayTextContains -Text $text -Needle ([string]$s1.EndOfListText)
                $isDuplicate = $false
                if (-not $isEndOfList -and $null -ne $global:CR_PipelineScreen1PrevPageText) {
                    $similarity = Get-TextSimilarity -A $global:CR_PipelineScreen1PrevPageText -B $text
                    $isDuplicate = ($similarity -ge [double]$s1.DupDetectThreshold)
                }

                if ($isEndOfList -or $isDuplicate) {
                    $reason = if ($isEndOfList) { "'$($s1.EndOfListText)' marker seen" } else { "next page matched the previous one - no new data" }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Done - $reason. Processed $($global:CR_PipelineScreen1PageIdx + 1) page(s)." -ForegroundColor Green
                    Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }

                # Text was only needed for the end-of-list/duplicate
                # check just above - row positions are the same fixed
                # slots on every page, so just rebuild them directly.
                $global:CR_PipelineScreen1PrevPageText = $text
                $global:CR_PipelineScreen1PageIdx++
                $global:CR_PipelineScreen1Rows   = Get-Screen1FixedRows -Screen1Select $s1
                $global:CR_PipelineComponentIdx  = 0
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        default {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unknown Screen1 state '$($global:CR_PipelineState)' - resetting." -ForegroundColor Yellow
            $global:CR_PipelineComponentIdx = 0
            $global:CR_PipelineState = 'CompScan_Action'
            $global:CR_ElapsedMs     = 0
        }
    }
}
