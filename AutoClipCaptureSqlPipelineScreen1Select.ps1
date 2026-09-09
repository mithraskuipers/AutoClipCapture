<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1Select.ps1

 SQL Pipeline - post-list rewind ("Step 2" - return to the top of
 Screen 1 once the component list is complete).

 Dot-sourced by AutoClipCapture.ps1; defines
 Invoke-PipelineScreen1SelectTick, called once per timer tick whenever
 $global:CR_PipelineState starts with "Rewind". This phase runs right
 after the Component List pre-pass
 (AutoClipCaptureSqlPipelineComponentList.ps1) finishes, but only when
 the pipeline's Screen1Select.Enabled is true - see
 Complete-PipelineListCapture in that file for the hand-off.

 This phase does NOT select, click, or open any individual row/
 component anymore - it only presses F7 (or whatever
 Screen1Select.RewindActionToken is configured to) repeatedly until
 the screen stops changing, i.e. page 1 is back on top, purely so the
 terminal is left in a known, tidy state after paging all the way to
 the bottom of the list. Once that settles, it writes the Markdown
 component list (Write-PipelineComponentListMarkdown, defined in
 AutoClipCaptureSqlPipelineComponentList.ps1 - available here because
 both files are dot-sourced into the same script) and stops the
 pipeline. If you don't want the rewind at all, set this pipeline's
 Screen1Select.Enabled to false in AutoClipCaptureConfig.json - the
 Markdown file is then written immediately after the last page is
 read, without pressing F7 again.

   Rewind_Start (copy the page currently on-screen, as a baseline)
     -> Rewind_Wait -> Rewind_Copy: press F7, copy again, compare to
        the baseline
          -> different -> that's the new baseline; press F7 again
             (Rewind_Start, next page up)
          -> same -> F7 stopped changing anything, so this is page 1.
             Write the Markdown list and stop.

 Runs at Screen1Select.RewindStepDelayMs (default 300ms, falling back
 to Screen1Select.StepDelayMs if not set) - fast, since this is just
 "press F7, copy, compare" in a loop with nothing to watch or verify.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs, $LogDir,
 Set-RelayForeground, Set-RelayStatus, Update-PipelineScreenTracking,
 Show-RelayResultOverlay, Stop-PipelineCapture) and in
 AutoClipCaptureSqlPipelineComponentList.ps1
 (Write-PipelineComponentListMarkdown) - all in scope here because
 these files are dot-sourced directly into that script, not run
 standalone.
=====================================================================
#>

function Invoke-PipelineScreen1SelectTick {
    $pipeline = $global:CR_ActivePipelineConfig
    $selCfg   = $pipeline.Screen1Select
    # Rewind (pressing F7 back to the top of screen 1) doesn't need the
    # cautious, watch-it-happen pace a row-selection step would use -
    # it's just "press F7, copy, compare" in a loop, so it can run much
    # faster. Falls back to StepDelayMs if RewindStepDelayMs isn't set.
    $rewindDelay = if ($null -ne $selCfg.RewindStepDelayMs) { [int]$selCfg.RewindStepDelayMs } else { [int]$selCfg.StepDelayMs }

    switch ($global:CR_PipelineState) {

        # ---- Rewind to the top of Screen 1 by pressing F7 until a
        # page comes back identical to the one before it. ----
        'Rewind_Start' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Rewinding to top ($($selCfg.RewindActionDisplay))..." ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'Rewind_BaselineWait'
            $global:CR_ElapsedMs = 0
        }
        'Rewind_BaselineWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $rewindDelay) { return }

            $text = ''
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $text = [System.Windows.Forms.Clipboard]::GetText()
                }
            } catch {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
            }
            $global:CR_PipelineRewindPrevText = $text
            $global:CR_PipelineRewindPresses  = 0
            $global:CR_PipelineState = 'Rewind_Action'
            $global:CR_ElapsedMs = 0
        }
        'Rewind_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.RewindActionToken)
            $global:CR_PipelineState = 'Rewind_Wait'
            $global:CR_ElapsedMs = 0
        }
        'Rewind_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $rewindDelay) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'Rewind_Copy'
            $global:CR_ElapsedMs = 0
        }
        'Rewind_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $rewindDelay) { return }

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
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Rewind: landed on screen $detected instead of screen 1 - stopping to be safe." -ForegroundColor Red
                Show-RelayResultOverlay -Text "UNEXPECTED SCREEN - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            if ($text -eq $global:CR_PipelineRewindPrevText) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Rewind: page stopped changing after $($global:CR_PipelineRewindPresses) x $($selCfg.RewindActionDisplay) - at the top." -ForegroundColor Cyan
                Write-PipelineComponentListMarkdown -Pipeline $pipeline
                Show-RelayResultOverlay -Text "COMPONENT LIST COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                Stop-PipelineCapture
                return
            }

            $global:CR_PipelineRewindPresses++
            if ($global:CR_PipelineRewindPresses -ge [int]$selCfg.MaxRewindPresses) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Rewind: safety limit of $($selCfg.MaxRewindPresses) x $($selCfg.RewindActionDisplay) reached without the page settling - stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "STOPPED (rewind limit reached)" -Color ([System.Drawing.Color]::Gray)
                Stop-PipelineCapture
                return
            }

            $global:CR_PipelineRewindPrevText = $text
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Rewind: page $($global:CR_PipelineRewindPresses) changed - pressing $($selCfg.RewindActionDisplay) again." -ForegroundColor DarkCyan
            $global:CR_PipelineState = 'Rewind_Action'
            $global:CR_ElapsedMs = 0
        }
    }
}
