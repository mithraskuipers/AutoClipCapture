<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen2.ps1

 Screen 2 = COMPONENT VERSION - SELECT, the screen that appears after
 typing a selection letter (e.g. "B") into a Screen 1 row and pressing
 Enter. For the current, simplified cobol-pipeline flow this screen is
 only ever looked at, not drilled into any further (no environment
 zoom, no SQL search) - Screen1.ps1 already captured its text via
 Ctrl+C right before handing off here (see CompZoom_Copy), so this
 file's only job is:
   1. Optionally append that captured text to
      Screen1Select.OutputFileName (pipeline_component_versions.txt by
      default), if Screen1Select.LogScreen2Text is true.
   2. Queue a single F3 back to Screen 1 via the shared
      Back_Action/Back_Wait/Back_Copy state chain in
      AutoClipCapture.ps1, by setting $global:CR_PipelineAfterBack to
      'CompNext_Action' (the exact state name AutoClipCapture.ps1's
      Back_Copy checks for to know it should expect to land back on
      Screen 1).

 State (starts with "Env" so AutoClipCapture.ps1's tick switch routes
 it here):
   EnvLog_Action - do the steps above, in a single tick (no waiting
                   needed - the text was already captured on Screen 1).
=====================================================================
#>

function Invoke-PipelineScreen2Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $s1       = $pipeline.Screen1Select

    switch ($global:CR_PipelineState) {

        'EnvLog_Action' {
            if ([bool]$s1.LogScreen2Text -and -not [string]::IsNullOrEmpty($global:CR_PipelineScreen2CapturedText)) {
                try {
                    $outPath = Join-Path $LogDir ([string]$s1.OutputFileName)
                    $rowLabel = "Page $($global:CR_PipelineScreen1PageIdx + 1), row $($global:CR_PipelineComponentIdx + 1)"
                    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $header = "===== $rowLabel - $stamp ====="
                    Add-Content -Path $outPath -Value $header
                    Add-Content -Path $outPath -Value $global:CR_PipelineScreen2CapturedText
                    Add-Content -Path $outPath -Value ''
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Failed to log Screen 2 text: $_" -ForegroundColor Yellow
                }
            }

            $global:CR_PipelineScreen2CapturedText = $null

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Viewed, returning" ([System.Drawing.Color]::Orange)
            $global:CR_PipelineAfterBack = 'CompNext_Action'
            $global:CR_PipelineState     = 'Back_Action'
            $global:CR_ElapsedMs         = 0
        }

        default {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unknown Screen2 state '$($global:CR_PipelineState)' - going back to be safe." -ForegroundColor Yellow
            $global:CR_PipelineAfterBack = 'CompNext_Action'
            $global:CR_PipelineState     = 'Back_Action'
            $global:CR_ElapsedMs         = 0
        }
    }
}
