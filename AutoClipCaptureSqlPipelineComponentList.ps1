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
          -> same as the previous page -> end of the list reached;
             stop here. (Step 2, which will make use of the saved
             list, is a separate feature to be added later - this
             phase's job ends at "list captured".)

 Each page is filtered with its own row-skip settings
 (ComponentList.SkipRowsStart / SkipRowsEnd - default 5/3), independent
 of the top-level SkipRowsStart/SkipRowsEnd used by the classic Toggle
 relay, since a given screen's header/footer padding doesn't have to
 match the pipeline's. "End of list" uses the same
 Get-TextSimilarity comparison the classic Toggle relay uses to detect
 a stuck capture (ComponentList.DupDetectThreshold - default 0.995),
 except here it stops automatically instead of asking, since running
 off the end of a bounded list is the expected, successful outcome
 rather than something to prompt about.

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

            $isDuplicate = $false
            if ($null -ne $global:CR_PipelineListPrevFiltered) {
                $similarity = Get-TextSimilarity -A $global:CR_PipelineListPrevFiltered -B $filtered
                if ($similarity -ge [double]$listCfg.DupDetectThreshold) { $isDuplicate = $true }
            }

            if ($isDuplicate) {
                # F8 didn't reveal anything new - this page is a repeat
                # of the previous one, so it was already saved. Don't
                # append it again; the list is complete.
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: page $($global:CR_PipelineListPageIdx + 1) matches the previous page - end of list reached." -ForegroundColor Cyan
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list complete - $($global:CR_PipelineListPageIdx) page(s) saved to $($global:CR_PipelineListOutputPath)" -ForegroundColor Green
                Show-RelayResultOverlay -Text "COMPONENT LIST COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                Stop-PipelineCapture
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
