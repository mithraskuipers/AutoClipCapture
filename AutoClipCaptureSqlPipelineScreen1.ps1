<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 Screen 1 = the REPOSITORY LIST overview (Type/Name/Appl/Subappl/
 Status columns, one row per component, "Row x of y ... More -->").

 This file drives the Ctrl+Shift+M pipeline's main job: walk every row
 of Screen 1, page by page, and for each one:
   1. Click the row's selection field (the little "_" column just left
      of "COB") using the pixel math calibrated by
      CalibrateScreen1AutoGuided.ps1 into Pipelines[].Screen1Select.
   2. Type Screen1Select.SelectionText (default "B") and press Enter.
   3. Confirm we landed on Screen 2 (COMPONENT VERSION - SELECT). If we
      did, hand off to AutoClipCaptureSqlPipelineScreen2.ps1, which
      logs it (if enabled) and queues a single F3 "back" to Screen 1
      (that shared "go back" mechanic lives in AutoClipCapture.ps1
      itself - see Back_Action/Back_Wait/Back_Copy).
   4. If nothing happened (blank/unavailable row - we're still on
      Screen 1), just move on to the next row without going back.
   5. Once every row on the current page has been tried, press
      Screen1Select.PageNextToken (F8 by default) to bring the next
      page into view and keep going - until either
      Screen1Select.EndOfListText shows up (explicit "end of list"
      marker) or a freshly-paged screen comes back near-identical to
      the one before it (Screen1Select.DupDetectThreshold - same
      comparison the duplicate-capture protection elsewhere uses),
      which means paging further isn't revealing anything new either.

 States (all start with "Comp" so AutoClipCapture.ps1's tick switch
 routes them here):
   CompZoom_Action  - click the current row, type the selection
                      letter, press Enter. This exact name is also the
                      pipeline's hard-coded starting state (see the
                      Ctrl+Shift+M hotkey handler), so a pipeline with
                      no ComponentList pre-pass lands here immediately.
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
   CompPage_Copy    - Ctrl+C, check EndOfListText / duplicate-page,
                      either stop (pipeline complete) or reset the
                      row counter and keep going from row 0 of the
                      new page.

 $global:CR_PipelineComponentIdx doubles here as the 0-based row index
 *within the current page* (it's reset to 0 by AutoClipCapture.ps1
 whenever the pipeline (re)starts, and reset again here every time a
 new page comes in).
=====================================================================
#>

# Works out the on-screen (screen-coordinate) point for a given row on
# the current page, using the exact same math
# CalibrateScreen1AutoGuided.ps1 uses to derive/verify OriginX/OriginY
# in the first place - see that script's own comments for the full
# derivation. $RowIndexOnPage is 0-based (0 = first data row visible
# on the current page).
function Get-Screen1RowScreenPoint {
    param(
        [IntPtr]$Handle,
        $Screen1Select,
        [int]$RowIndexOnPage
    )

    # Fixed for this setup (matches CalibrateScreen1AutoGuided.ps1
    # exactly): "COB" always starts at column 5, the selection field is
    # always column 3, and the first data row is always row 7 - the
    # first 6 rows are the title/"Show Deleted"/column-header rows.
    $cobColumn        = 5
    $firstDataRow     = 7
    $targetColIndex   = ($cobColumn - 1) + [int]$Screen1Select.ClickColumnOffset
    $firstDataRowIdx0 = $firstDataRow - 1

    $clientX = [double]$Screen1Select.OriginX + ($targetColIndex * [double]$Screen1Select.CharWidthPx)
    $clientY = [double]$Screen1Select.OriginY + (($firstDataRowIdx0 + $RowIndexOnPage) * [double]$Screen1Select.CharHeightPx)

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

        'CompZoom_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run CalibrateScreen1AutoGuided.bat first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            $rowIdx = [int]$global:CR_PipelineComponentIdx
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -RowIndexOnPage $rowIdx
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1) - selecting" ([System.Drawing.Color]::Lime)
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
            if ($nextRow -lt [int]$s1.RowsPerPage) {
                $global:CR_PipelineComponentIdx = $nextRow
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            } else {
                # Current page exhausted - page forward.
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

                $global:CR_PipelineScreen1PrevPageText = $text
                $global:CR_PipelineScreen1PageIdx++
                $global:CR_PipelineComponentIdx = 0
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        default {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unknown Screen1 state '$($global:CR_PipelineState)' - resetting." -ForegroundColor Yellow
            $global:CR_PipelineComponentIdx = 0
            $global:CR_PipelineState = 'CompZoom_Action'
            $global:CR_ElapsedMs     = 0
        }
    }
}
