<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 Screen 1 = the REPOSITORY LIST overview (Type/Name/Appl/Subappl/
 Status columns, one row per component, "Row x of y ... More -->").

 This file drives the Ctrl+Shift+M pipeline's main job: walk every row
 of Screen 1, page by page, and for each one:
   0. Ctrl+C the current page and find every line that actually has
      "COB" printed on it (Get-Screen1DataRows). Row *positions* are
      no longer assumed from a fixed RowsPerPage count - they're read
      straight off the just-captured text, so a page with fewer rows
      than usual (e.g. the last page of the list) is handled exactly
      like any other: whatever COB lines are actually there is exactly
      what gets clicked, no more, no less.
   1. For each detected row: click 2 character columns to the left of
      where "COB" starts *on that row's own line*
      (Screen1Select.ClickColumnOffset, default -2 - lands on the "_"
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
   4. If nothing happened (blank/unavailable row - we're still on
      Screen 1), just move on to the next row without going back.
   5. Once every detected row on the current page has been tried,
      press Screen1Select.PageNextToken (F8 by default) to bring the
      next page into view, re-scan it the same way, and keep going -
      until either Screen1Select.EndOfListText shows up (explicit "end
      of list" marker) or a freshly-paged screen comes back
      near-identical to the one before it
      (Screen1Select.DupDetectThreshold - same comparison the
      duplicate-capture protection elsewhere uses), which means paging
      further isn't revealing anything new either.

 States (all start with "Comp" so AutoClipCapture.ps1's tick switch
 routes them here):
   CompScan_Action  - Ctrl+C the current page. This exact name is also
                      the pipeline's hard-coded starting state (see
                      the Ctrl+Shift+M hotkey handler), so a pipeline
                      with no ComponentList pre-pass lands here
                      immediately, and the very first page gets
                      scanned before anything is clicked.
   CompScan_Wait    - short delay before reading the clipboard, so the
                      copy has time to land.
   CompScan_Copy    - parse the captured text with
                      Get-Screen1DataRows, store the detected
                      (line, column) pairs in
                      $global:CR_PipelineScreen1Rows, reset the row
                      index to 0, and move on to CompZoom_Action. If
                      nothing with "COB" on it was found at all,
                      retries a few times (a slow-to-render screen)
                      before giving up on the page.
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
                      completes. Going "next" after a Back doesn't
                      require a re-scan - F3 lands back on the exact
                      same page, so the row list captured back in
                      CompScan_Copy is still valid.
   CompPage_Action  - send Screen1Select.PageNextToken (e.g. F8) to
                      move to the next page.
   CompPage_Wait    - short delay before copying the new page.
   CompPage_Copy    - Ctrl+C, check EndOfListText / duplicate-page;
                      either stop (pipeline complete) or re-parse the
                      newly-paged text for COB rows (same as
                      CompScan_Copy, done inline here since the page
                      was just copied anyway) and keep going from row
                      0 of the new page.

 $global:CR_PipelineComponentIdx is the 0-based index *into
 $global:CR_PipelineScreen1Rows* (not a raw row-on-page count anymore).
 Both are reset by AutoClipCapture.ps1 whenever the pipeline
 (re)starts, and reset again here every time a new page comes in.
=====================================================================
#>

# Scans captured Screen 1 text for every data row that actually has
# "COB" printed on it, and returns their exact (0-based) line number
# within $Text and the (0-based) character column "COB" starts at on
# that specific line. Scanning starts at $firstDataRowIdx0 (row 7,
# matching CalibrateScreen1Auto.ps1's own constant) purely to skip past
# the title/"Show Deleted"/column-header/filter rows above the real
# list - everything from there down is checked on its own merits, so a
# short final page (fewer rows than usual) or an odd gap is handled
# correctly instead of assumed away.
function Get-Screen1DataRows {
    param([string]$Text, $Screen1Select)

    $rows = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($Text)) { return $rows }

    $firstDataRow     = 7
    $firstDataRowIdx0 = $firstDataRow - 1
    $lines = $Text -split "`r`n|`n|`r"

    for ($i = $firstDataRowIdx0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (Test-RelayTextContains -Text $line -Needle 'Bottom of List') { break }
        if (Test-RelayTextContains -Text $line -Needle 'Command ===>')   { break }

        $m = [regex]::Match($line, '\bCOB\b')
        if (-not $m.Success) { continue }

        $rows.Add([pscustomobject]@{
            LineIndex = $i
            ColIndex  = $m.Index
        })
    }

    return $rows
}

# Works out the on-screen (screen-coordinate) point for one detected
# row, using the exact same OriginX/OriginY/CharWidthPx/CharHeightPx
# calibration CalibrateScreen1Auto.ps1 produces - but the row/column
# themselves now come from Get-Screen1DataRows (the actual detected
# line and "COB" column for that row) instead of a fixed per-row
# offset, so drift between rows never accumulates.
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
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run CalibrateScreen1Auto.bat first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1) - scanning for rows" ([System.Drawing.Color]::Lime)
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'CompScan_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompScan_Wait' {
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
                $rows = Get-Screen1DataRows -Text $text -Screen1Select $s1

                if ($rows.Count -eq 0) {
                    $global:CR_PipelineScreen1RetryCount++
                    $maxRetries = [int]$s1.MaxRowRetries
                    if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] No 'COB' rows found on page $($global:CR_PipelineScreen1PageIdx + 1) after $maxRetries retries - stopping." -ForegroundColor Yellow
                        Show-RelayResultOverlay -Text "NO ROWS FOUND - STOPPED" -Color ([System.Drawing.Color]::Gray)
                        Stop-PipelineCapture
                        return
                    }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] No 'COB' rows found yet - retrying scan ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                    $global:CR_PipelineState = 'CompScan_Action'
                    $global:CR_ElapsedMs     = 0
                    return
                }

                $global:CR_PipelineScreen1RetryCount = 0
                $global:CR_PipelineScreen1Rows        = $rows
                $global:CR_PipelineComponentIdx       = 0
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompZoom_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run CalibrateScreen1Auto.bat first. Stopping." -ForegroundColor Red
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
            $row = $global:CR_PipelineScreen1Rows[$rowIdx]
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)

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

                # Text was just captured for the duplicate/end-of-list
                # check above anyway - parse it for COB rows right here
                # instead of spending a separate CompScan_Action cycle
                # re-copying the same page again.
                $rows = Get-Screen1DataRows -Text $text -Screen1Select $s1
                if ($rows.Count -eq 0) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] New page had no 'COB' rows and no end-of-list/duplicate marker either - stopping to be safe." -ForegroundColor Yellow
                    Show-RelayResultOverlay -Text "NO ROWS FOUND - STOPPED" -Color ([System.Drawing.Color]::Gray)
                    Stop-PipelineCapture
                    return
                }

                $global:CR_PipelineScreen1PrevPageText = $text
                $global:CR_PipelineScreen1PageIdx++
                $global:CR_PipelineScreen1Rows   = $rows
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
