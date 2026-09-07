<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen2.ps1

 SQL Pipeline - Screen 2 (Environments).

 Dot-sourced by AutoClipCapture.ps1; defines Invoke-PipelineScreen2Tick,
 called once per timer tick whenever $global:CR_PipelineState starts
 with "Env". Handles trying to zoom into the current environment and,
 if it's unavailable, moving on to the next one:

   EnvZoom_Action -> EnvZoom_Wait -> EnvZoom_Copy
     -> unavailable -> EnvNext_Action -> EnvNext_Wait -> EnvZoom_Action (next item)
     -> available   -> hands off to Screen 3 (Sql_Action)

 Once every environment for the current component has been tried,
 EnvNext_Action queues Back_Action (single F3 press, handled centrally
 in AutoClipCapture.ps1) to return to Screen 1 and move to the next
 component.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs /
 $AfterActionKeyDelayMs, Set-RelayForeground, Set-RelayStatus,
 Test-RelayTextContains, Get-PipelineItemLabel, Stop-PipelineCapture)
 - all in scope here because this file is dot-sourced directly into
 that script, not run standalone.
=====================================================================
#>

function Invoke-PipelineScreen2Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $envLevel = $pipeline.Environment

    switch ($global:CR_PipelineState) {
        'EnvZoom_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Environment $($global:CR_PipelineEnvironmentIdx + 1): zooming in" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($envLevel.ZoomActionToken)
            $global:CR_PipelineState = 'EnvZoom_Wait'
            $global:CR_ElapsedMs = 0
        }
        'EnvZoom_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'EnvZoom_Copy'
                $global:CR_ElapsedMs = 0
            }
        }
        'EnvZoom_Copy' {
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

                if (Test-RelayTextContains -Text $text -Needle $envLevel.UnavailableText) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Environment $($global:CR_PipelineEnvironmentIdx + 1) unavailable - skipping." -ForegroundColor Yellow
                    $global:CR_PipelineState = 'EnvNext_Action'
                    $global:CR_ElapsedMs = 0
                } else {
                    $global:CR_PipelineEnvironmentLabel = Get-PipelineItemLabel -Text $text -Pattern $envLevel.LabelPattern -FallbackLabel "Environment $($global:CR_PipelineEnvironmentIdx + 1)"
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Environment '$($global:CR_PipelineEnvironmentLabel)' available - running SQL search." -ForegroundColor Green
                    $global:CR_PipelineSqlIterations = 0
                    $global:CR_PipelineState = 'Sql_Action'
                    $global:CR_ElapsedMs = 0
                }
            }
        }
        # ---- Back on screen 2: move to the next environment, or (once
        # they're exhausted) back out to screen 1 ----
        'EnvNext_Action' {
            $global:CR_PipelineEnvironmentIdx++
            if ($global:CR_PipelineEnvironmentIdx -ge [int]$envLevel.MaxItems) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] All environments processed for '$($global:CR_PipelineComponentLabel)' - returning to components." -ForegroundColor Cyan
                $global:CR_PipelineAfterBack = 'CompNext_Action'
                $global:CR_PipelineState = 'Back_Action'
                $global:CR_ElapsedMs = 0
                return
            }
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Next environment" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($envLevel.NextActionToken)
            $global:CR_PipelineState = 'EnvNext_Wait'
            $global:CR_ElapsedMs = 0
        }
        'EnvNext_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                $global:CR_PipelineState = 'EnvZoom_Action'
            }
        }
    }
}
