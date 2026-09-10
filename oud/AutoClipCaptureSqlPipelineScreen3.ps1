<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen3.ps1

 SQL Pipeline - Screen 3 (COBOL code / SQL search).

 Dot-sourced by AutoClipCapture.ps1; defines Invoke-PipelineScreen3Tick,
 called once per timer tick whenever $global:CR_PipelineState starts
 with "Sql_". This is the screen that always runs once an environment
 is available - same Action/Wait/Copy shape as a classic scan Mode,
 just nested inside the pipeline and using the pipeline's own Sql
 config block (same fields: ActionKeyToken, FoundText, NotFoundText,
 TerminalText, MaxIterations, ...):

   Sql_Action -> Sql_Wait -> Sql_Copy
     -> found / not-found / limit reached -> record result, queue
        Back_Action (single F3 press, handled centrally in
        AutoClipCapture.ps1) to return to Screen 2 and move on
     -> otherwise -> loop back to Sql_Action

 Also owns Update-PipelineSqlCheckFile, which records each result to
 pipeline_sql_check.md keyed by (Component, Environment) pair - kept
 separate from the classic scan Mode's component_sql_check.md so the
 two never collide.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs /
 $AfterActionKeyDelayMs, $LogDir, Set-RelayForeground, Set-RelayStatus,
 Test-RelayTextContains, Show-RelayResultOverlay, Stop-PipelineCapture)
 - all in scope here because this file is dot-sourced directly into
 that script, not run standalone.
=====================================================================
#>

function Invoke-PipelineScreen3Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $sql = $pipeline.Sql

    switch ($global:CR_PipelineState) {
        'Sql_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Sending $($sql.ActionKeyDisplay)" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($sql.ActionKeyToken)
            $global:CR_PipelineState = 'Sql_Wait'
            $global:CR_ElapsedMs = 0
        }
        'Sql_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying (Ctrl+C)" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'Sql_Copy'
                $global:CR_ElapsedMs = 0
            }
        }
        'Sql_Copy' {
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

                Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name | Out-Null

                $global:CR_PipelineSqlIterations++

                $foundMatch    = Test-RelayTextContains -Text $text -Needle $sql.FoundText
                $notFoundMatch = (Test-RelayTextContains -Text $text -Needle $sql.NotFoundText) -or
                                 (Test-RelayTextContains -Text $text -Needle $sql.TerminalText)

                if ($foundMatch) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] '$($sql.FoundText)' found for '$($global:CR_PipelineComponentLabel) / $($global:CR_PipelineEnvironmentLabel)'." -ForegroundColor Green
                    Show-RelayResultOverlay -Text $sql.FoundOverlayText -Color ([System.Drawing.Color]::LimeGreen)
                    Update-PipelineSqlCheckFile -Component $global:CR_PipelineComponentLabel -Environment $global:CR_PipelineEnvironmentLabel -SqlFound $true
                    $global:CR_PipelineAfterBack = 'EnvNext_Action'
                    $global:CR_PipelineState = 'Back_Action'
                    $global:CR_ElapsedMs = 0
                }
                elseif ($notFoundMatch) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Not-found phrase matched for '$($global:CR_PipelineComponentLabel) / $($global:CR_PipelineEnvironmentLabel)'." -ForegroundColor Yellow
                    Show-RelayResultOverlay -Text $sql.NotFoundOverlayText -Color ([System.Drawing.Color]::OrangeRed)
                    Update-PipelineSqlCheckFile -Component $global:CR_PipelineComponentLabel -Environment $global:CR_PipelineEnvironmentLabel -SqlFound $false
                    $global:CR_PipelineAfterBack = 'EnvNext_Action'
                    $global:CR_PipelineState = 'Back_Action'
                    $global:CR_ElapsedMs = 0
                }
                elseif ($global:CR_PipelineSqlIterations -ge [int]$sql.MaxIterations) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] SQL search stopped - safety limit of $($sql.MaxIterations) iterations reached." -ForegroundColor Yellow
                    Show-RelayResultOverlay -Text "STOPPED (limit reached)" -Color ([System.Drawing.Color]::Gray)
                    $global:CR_PipelineAfterBack = 'EnvNext_Action'
                    $global:CR_PipelineState = 'Back_Action'
                    $global:CR_ElapsedMs = 0
                }
                else {
                    $global:CR_PipelineState = 'Sql_Action'
                    $global:CR_ElapsedMs = 0
                }
            }
        }
    }
}

# Same idea as Update-ComponentSqlCheckFile (in AutoClipCapture.ps1),
# but for Pipeline runs, which check SQL per (Component, Environment)
# pair rather than per component alone. Kept in its own file
# (pipeline_sql_check.md) so it never collides with the classic SQL
# Search mode's table.
function Update-PipelineSqlCheckFile {
    param(
        [string]$Component,
        [string]$Environment,
        [bool]$SqlFound
    )

    $mark = if ($SqlFound) { 'Y' } else { 'N' }
    $headerLine1 = '| Component | Environment | SQL |'
    $headerLine2 = '|-----------|-------------|-----|'
    $filePath = Join-Path $LogDir "pipeline_sql_check.md"

    try {
        if (-not (Test-Path $filePath)) {
            @($headerLine1, $headerLine2, "| $Component | $Environment | $mark |") |
                Set-Content -Path $filePath -Encoding UTF8
            Write-Host "[AutoClipCapture] pipeline_sql_check.md created - added '$Component / $Environment' = $mark." -ForegroundColor Cyan
            return
        }

        $lines = @(Get-Content -Path $filePath -Encoding UTF8)
        if ($lines.Count -lt 2 -or $lines[0] -notmatch '^\|\s*Component\b') {
            $dataRows = @($lines | Where-Object { $_ -match '^\|.*\|.*\|.*\|\s*$' -and $_ -ne $headerLine1 -and $_ -ne $headerLine2 })
            $lines = @($headerLine1, $headerLine2) + $dataRows
        }

        $updated = $false
        for ($i = 2; $i -lt $lines.Count; $i++) {
            $cells = $lines[$i].Trim().Trim('|') -split '\|'
            if ($cells.Count -ge 2 -and $cells[0].Trim() -eq $Component -and $cells[1].Trim() -eq $Environment) {
                $lines[$i] = "| $Component | $Environment | $mark |"
                $updated = $true
                break
            }
        }

        if (-not $updated) {
            $lines += "| $Component | $Environment | $mark |"
        }

        Set-Content -Path $filePath -Value $lines -Encoding UTF8
        $verb = if ($updated) { 'updated' } else { 'added' }
        Write-Host "[AutoClipCapture] pipeline_sql_check.md $verb - '$Component / $Environment' = $mark." -ForegroundColor Cyan
    } catch {
        Write-Host "[AutoClipCapture] Failed to update pipeline_sql_check.md: $_" -ForegroundColor Red
    }
}
