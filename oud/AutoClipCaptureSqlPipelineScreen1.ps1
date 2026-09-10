<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 SQL Pipeline - Screen 1 (Components).

 Dot-sourced by AutoClipCapture.ps1; defines Invoke-PipelineScreen1Tick,
 called once per timer tick whenever $global:CR_PipelineState starts
 with "Comp". Handles trying to zoom into the current component and,
 if it's unavailable, moving on to the next one:

   CompZoom_Action -> CompZoom_Wait -> CompZoom_Copy
     -> unavailable -> CompNext_Action -> CompNext_Wait -> CompZoom_Action (next item)
     -> available   -> hands off to Screen 2 (EnvZoom_Action)

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs /
 $AfterActionKeyDelayMs, Set-RelayForeground, Set-RelayStatus,
 Test-RelayTextContains, Get-PipelineItemLabel, Show-RelayResultOverlay,
 Stop-PipelineCapture) - all in scope here because this file is
 dot-sourced directly into that script, not run standalone.
=====================================================================
#>

function Invoke-PipelineScreen1Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $comp = $pipeline.Component

    switch ($global:CR_PipelineState) {
        'CompZoom_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Component $($global:CR_PipelineComponentIdx + 1): zooming in" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($comp.ZoomActionToken)
            $global:CR_PipelineState = 'CompZoom_Wait'
            $global:CR_ElapsedMs = 0
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
                $global:CR_ElapsedMs = 0
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
                    # Landed on screen 2 - the zoom worked.
                    $global:CR_PipelineComponentLabel = Get-PipelineItemLabel -Text $text -Pattern $comp.LabelPattern -FallbackLabel "Component $($global:CR_PipelineComponentIdx + 1)"
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component '$($global:CR_PipelineComponentLabel)' available - entering environments." -ForegroundColor Green
                    $global:CR_PipelineEnvironmentIdx = 0
                    $global:CR_PipelineState = 'EnvZoom_Action'
                    $global:CR_ElapsedMs = 0
                } elseif ($detected -eq 1) {
                    # Still on screen 1 - this component didn't open.
                    # UnavailableText just explains why in the log.
                    if (Test-RelayTextContains -Text $text -Needle $comp.UnavailableText) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component $($global:CR_PipelineComponentIdx + 1) unavailable - skipping." -ForegroundColor Yellow
                    } else {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component $($global:CR_PipelineComponentIdx + 1) didn't open (stayed on screen 1, '$($comp.UnavailableText)' not seen) - skipping." -ForegroundColor Yellow
                    }
                    $global:CR_PipelineState = 'CompNext_Action'
                    $global:CR_ElapsedMs = 0
                } else {
                    # Neither screen 1 nor screen 2 - an unrecognized
                    # screen (popup, error, ...). Play it safe and skip
                    # this component rather than get stuck on it.
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unexpected screen (detected: $detected) after trying component $($global:CR_PipelineComponentIdx + 1) - skipping." -ForegroundColor Yellow
                    $global:CR_PipelineState = 'CompNext_Action'
                    $global:CR_ElapsedMs = 0
                }
            }
        }
        # ---- Back on screen 1: move to the next component ----
        'CompNext_Action' {
            $global:CR_PipelineComponentIdx++
            if ($global:CR_PipelineComponentIdx -ge [int]$comp.MaxItems) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] All components processed." -ForegroundColor Cyan
                Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                Stop-PipelineCapture
                return
            }
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Next component" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($comp.NextActionToken)
            $global:CR_PipelineState = 'CompNext_Wait'
            $global:CR_ElapsedMs = 0
        }
        'CompNext_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                $global:CR_PipelineState = 'CompZoom_Action'
            }
        }
    }
}
