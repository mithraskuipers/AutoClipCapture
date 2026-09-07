<#
=====================================================================
 AutoClipCaptureSqlPipelineComponentList.ps1

 SQL Pipeline - Component List capture ("Step 1" - Screen 1 pre-pass).

 Dot-sourced by AutoClipCapture.ps1; defines Invoke-PipelineListTick,
 called once per timer tick whenever $global:CR_PipelineState starts
 with "List". This is an optional first phase of a Pipeline (turned on
 per-pipeline via Pipelines[].ComponentList.Enabled in
 AutoClipCaptureConfig.json): before ever trying to zoom into a
 component, it pages through the entire Screen 1 component overview
 once, top to bottom, and saves the raw listing to a text file -
 without opening a single component. It never leaves Screen 1.

 This is the automated equivalent of a person doing, by hand: Ctrl+C
 the current page, trim off the header/footer rows, paste the result
 into a text file, press F8 to scroll to the next page, and repeat -
 stopping only once a page comes back identical to the one before it
 (i.e. F8 stopped revealing anything new, so the end of the list has
 been reached).

   ListCapture_Start (page 1 is already on-screen - no page-turn needed)
     -> ListCapture_Wait -> read clipboard, filter, compare to the
        previous page
          -> different from the previous page -> append it to the
             output file -> ListNext_Action -> ListNext_Wait
             -> ListCapture_Wait (next page)
          -> same as the previous page -> end of the list reached.
          -> page contains ComponentList.BottomOfListText (default
             "Bottom of List") -> end of list reached; save this page
             (it's genuinely the last one, not a repeat) - no F8
             page-turn, no similarity check needed.
        Either way, "end of the list" hands off to
        Complete-PipelineListCapture: if this pipeline's
        Screen1Select.Enabled is true, that's a rewind-to-top followed
        by a list-driven row search (see
        AutoClipCaptureSqlPipelineScreen1Select.ps1); otherwise the
        pipeline just stops here, list saved.

 Each page is filtered with its own row-skip settings
 (ComponentList.SkipRowsStart / SkipRowsEnd - default 5/3), independent
 of the top-level SkipRowsStart/SkipRowsEnd used by the classic Toggle
 relay, since a given screen's header/footer padding doesn't have to
 match the pipeline's. "End of list" is detected two ways: (1) an
 explicit ComponentList.BottomOfListText marker (checked against the
 raw, unfiltered clipboard text, since that marker typically lives in
 the footer rows that get trimmed) - the fast path, since it's known
 the instant the last page appears; or (2), as a fallback for lists
 that don't print such a marker, the same Get-TextSimilarity
 comparison the classic Toggle relay uses to detect a stuck capture
 (ComponentList.DupDetectThreshold - default 0.995) - which only finds
 out one page late, since it needs the repeated page to notice nothing
 changed. Either way it stops automatically instead of asking, since
 running off the end of a bounded list is the expected, successful
 outcome rather than something to prompt about.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs /
 $AfterActionKeyDelayMs, $LogDir, Set-RelayForeground, Set-RelayStatus,
 Get-FilteredCaptureText, Get-TextSimilarity,
 Update-PipelineScreenTracking, Show-RelayResultOverlay,
 Stop-PipelineCapture) - all in scope here because this file is
 dot-sourced directly into that script, not run standalone.
=====================================================================
#>

function Invoke-PipelineListTick {
    $pipeline = $global:CR_ActivePipelineConfig
    $listCfg  = $pipeline.ComponentList

    # ---- Shared "list capture is done" exit point, used by both the
    # BottomOfListText branch and the duplicate-page branch below. When
    # this pipeline's Screen1Select phase is enabled, hands off to it
    # (rewind to top, then hunt down each id from the list) instead of
    # stopping outright - see AutoClipCaptureSqlPipelineScreen1Select.ps1. ----
    function Complete-PipelineListCapture {
        param([string]$Reason)

        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: $Reason - end of list reached." -ForegroundColor Cyan
        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list complete - $($global:CR_PipelineListPageIdx) page(s) saved to $($global:CR_PipelineListOutputPath)" -ForegroundColor Green

        $selCfg = $pipeline.Screen1Select
        if ($null -ne $selCfg -and [bool]$selCfg.Enabled) {
            Show-RelayResultOverlay -Text "LIST DONE - REWINDING" -Color ([System.Drawing.Color]::DeepSkyBlue)
            $global:CR_PipelineState = 'Rewind_Start'
            $global:CR_ElapsedMs = 0
        } else {
            Show-RelayResultOverlay -Text "COMPONENT LIST COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
            Stop-PipelineCapture
        }
    }

    switch ($global:CR_PipelineState) {

        # ---- Page 1 is already on-screen the moment the pipeline
        # hotkey is pressed (that's the assumption this whole phase
        # relies on) - so the very first page needs a copy, not a
        # page-turn. ----
        'ListCapture_Start' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Component list: capturing page 1" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'ListCapture_Wait'
            $global:CR_ElapsedMs = 0
        }

        # ---- Every page (including the first) lands here once its
        # Ctrl+C has been sent: wait for the clipboard to settle, then
        # read / filter / compare / append / decide whether to keep
        # going. ----
        'ListCapture_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $CopyDelayMs) { return }

            $text = ''
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $text = [System.Windows.Forms.Clipboard]::GetText()
                }
            } catch {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
            }

            $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
            if ($detected -ne 1) {
                # We should never leave Screen 1 during this phase - if
                # we did (a stray keypress landed elsewhere, a popup
                # appeared, etc.) stop rather than risk capturing
                # garbage or pressing on somewhere unexpected.
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: landed on screen $detected instead of screen 1 - stopping to be safe." -ForegroundColor Red
                Show-RelayResultOverlay -Text "UNEXPECTED SCREEN - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            $filtered = Get-FilteredCaptureText -Text $text -SkipStart ([int]$listCfg.SkipRowsStart) -SkipEnd ([int]$listCfg.SkipRowsEnd)

            # ---- Explicit "Bottom of List" marker: checked against the
            # raw (unfiltered) text, since it typically lives in the
            # footer rows SkipRowsEnd trims off. Unlike duplicate
            # detection, this page IS genuinely the last one - not a
            # repeat of the one before it - so it still needs saving.
            # Once saved, there's nothing left to page through: skip
            # the similarity check and don't press F8 again. ----
            if (Test-RelayTextContains -Text $text -Needle $listCfg.BottomOfListText) {
                if (-not [string]::IsNullOrEmpty($filtered)) {
                    try {
                        Add-Content -Path $global:CR_PipelineListOutputPath -Value $filtered -Encoding UTF8
                    } catch {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Failed to write to $($global:CR_PipelineListOutputPath): $_" -ForegroundColor Red
                    }
                }
                $global:CR_PipelineListPageIdx++
                Complete-PipelineListCapture -Reason "page $($global:CR_PipelineListPageIdx) contains '$($listCfg.BottomOfListText)'"
                return
            }

            $isDuplicate = $false
            if ($null -ne $global:CR_PipelineListPrevFiltered) {
                $similarity = Get-TextSimilarity -A $global:CR_PipelineListPrevFiltered -B $filtered
                if ($similarity -ge [double]$listCfg.DupDetectThreshold) { $isDuplicate = $true }
            }

            if ($isDuplicate) {
                # F8 didn't reveal anything new - this page is a repeat
                # of the previous one, so it was already saved. Don't
                # append it again; the list is complete.
                Complete-PipelineListCapture -Reason "page $($global:CR_PipelineListPageIdx + 1) matches the previous page"
                return
            }

            if (-not [string]::IsNullOrEmpty($filtered)) {
                try {
                    Add-Content -Path $global:CR_PipelineListOutputPath -Value $filtered -Encoding UTF8
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Failed to write to $($global:CR_PipelineListOutputPath): $_" -ForegroundColor Red
                }
            }

            $global:CR_PipelineListPageIdx++
            $global:CR_PipelineListPrevFiltered = $filtered
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: page $($global:CR_PipelineListPageIdx) captured." -ForegroundColor DarkCyan

            if ($global:CR_PipelineListPageIdx -ge [int]$listCfg.MaxPages) {
                # Safety valve, same idea as Sql.MaxIterations - a
                # misconfigured threshold or a page that never stops
                # changing (e.g. a clock/counter on-screen) shouldn't
                # be able to loop forever.
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: safety limit of $($listCfg.MaxPages) pages reached - stopping." -ForegroundColor Yellow
                Show-RelayResultOverlay -Text "STOPPED (page limit reached)" -Color ([System.Drawing.Color]::Gray)
                Stop-PipelineCapture
                return
            }

            $global:CR_PipelineState = 'ListNext_Action'
            $global:CR_ElapsedMs = 0
        }

        # ---- Turn the page (F8 by default, configurable) and copy
        # whatever comes up next. ----
        'ListNext_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Component list: page $($global:CR_PipelineListPageIdx + 1)" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($listCfg.NextActionToken)
            $global:CR_PipelineState = 'ListNext_Wait'
            $global:CR_ElapsedMs = 0
        }
        'ListNext_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'ListCapture_Wait'
                $global:CR_ElapsedMs = 0
            }
        }
    }
}
