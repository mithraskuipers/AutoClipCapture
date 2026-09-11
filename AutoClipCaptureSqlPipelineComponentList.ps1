<#
=====================================================================
 AutoClipCaptureSqlPipelineComponentList.ps1

 Optional pre-pass (Pipelines[].ComponentList.Enabled) that just pages
 through Screen 1 (REPOSITORY LIST) front to back, capturing everything
 into a plain text file (ComponentList.OutputFileName) - no clicking,
 no selecting, nothing opened. Off by default (see
 AutoClipCaptureConfig.json - ComponentList.Enabled is false) so
 pressing the pipeline hotkey goes straight into the row-selection walk
 in AutoClipCaptureSqlPipelineScreen1.ps1 instead. Turn it on if you
 also want a plain-text copy of the whole repository list saved
 somewhere before/instead of the click-through pass.

 States (all start with "List" so AutoClipCapture.ps1's tick switch
 routes them here):
   ListCapture_Start - one-time setup (resets the output file for this
                        run), then falls straight into a copy.
   ListCapture_Wait  - short delay before copying (only used between
                        pages, after ListCapture_Next).
   ListCapture_Copy  - Ctrl+C, trim ComponentList.SkipRowsStart/
                        SkipRowsEnd rows off, append what's left to the
                        output file, then either stop (EndOfListText
                        seen, or this page duplicates the last one) or
                        move to ListCapture_Next.
   ListCapture_Next  - send ComponentList.NextActionToken (F8 by
                        default) to bring the next page into view.
=====================================================================
#>

function Invoke-PipelineListTick {
    $pipeline = $global:CR_ActivePipelineConfig
    $cl       = $pipeline.ComponentList

    switch ($global:CR_PipelineState) {

        'ListCapture_Start' {
            try {
                if (Test-Path $global:CR_PipelineListOutputPath) {
                    Remove-Item -Path $global:CR_PipelineListOutputPath -Force
                }
            } catch {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not reset $($global:CR_PipelineListOutputPath): $_" -ForegroundColor Yellow
            }
            $global:CR_PipelineListPageIdx      = 0
            $global:CR_PipelineListPrevFiltered = $null

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Capturing component list (page 1)" ([System.Drawing.Color]::Lime)
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'ListCapture_Copy'
            $global:CR_ElapsedMs     = 0
        }

        'ListCapture_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'ListCapture_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'ListCapture_Copy' {
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

                $isEndOfList = Test-RelayTextContains -Text $text -Needle ([string]$cl.EndOfListText)

                $filtered = Get-FilteredCaptureText -Text $text -SkipStart ([int]$cl.SkipRowsStart) -SkipEnd ([int]$cl.SkipRowsEnd)
                $isDuplicate = $false
                if (-not $isEndOfList -and $null -ne $global:CR_PipelineListPrevFiltered) {
                    $similarity = Get-TextSimilarity -A $global:CR_PipelineListPrevFiltered -B $filtered
                    $isDuplicate = ($similarity -ge [double]$cl.DupDetectThreshold)
                }

                if (-not $isDuplicate -and -not [string]::IsNullOrEmpty($filtered)) {
                    try {
                        Add-Content -Path $global:CR_PipelineListOutputPath -Value $filtered
                    } catch {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Failed to write $($global:CR_PipelineListOutputPath): $_" -ForegroundColor Red
                    }
                }

                if ($isEndOfList -or $isDuplicate) {
                    $reason = if ($isEndOfList) { "'$($cl.EndOfListText)' marker seen" } else { "next page matched the previous one - no new data" }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list capture done - $reason. $($global:CR_PipelineListPageIdx + 1) page(s) saved to $($global:CR_PipelineListOutputPath)." -ForegroundColor Green
                    Show-RelayResultOverlay -Text "COMPONENT LIST SAVED" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }

                if ([int]$global:CR_PipelineListPageIdx + 1 -ge [int]$cl.MaxPages) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Reached the MaxPages safety limit ($($cl.MaxPages)) - stopping." -ForegroundColor Yellow
                    Show-RelayResultOverlay -Text "STOPPED (page limit reached)" -Color ([System.Drawing.Color]::Gray)
                    Stop-PipelineCapture
                    return
                }

                $global:CR_PipelineListPrevFiltered = $filtered
                $global:CR_PipelineListPageIdx++
                $global:CR_PipelineState = 'ListCapture_Next'
                $global:CR_ElapsedMs     = 0
            }
        }

        'ListCapture_Next' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Capturing component list (page $($global:CR_PipelineListPageIdx + 1))" ([System.Drawing.Color]::Lime)
            [System.Windows.Forms.SendKeys]::SendWait([string]$cl.NextActionToken)
            $global:CR_PipelineState = 'ListCapture_Wait'
            $global:CR_ElapsedMs     = 0
        }

        default {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unknown List state '$($global:CR_PipelineState)' - resetting." -ForegroundColor Yellow
            $global:CR_PipelineState = 'ListCapture_Start'
            $global:CR_ElapsedMs     = 0
        }
    }
}
