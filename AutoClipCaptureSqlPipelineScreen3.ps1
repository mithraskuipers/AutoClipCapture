<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen3.ps1

 Screen 3 = the COBOL/SQL search screen a full component -> environment
 -> SQL-search pipeline would eventually drill into. NOT IMPLEMENTED
 YET - the current cobol-pipeline flow only ever goes Screen 1 -> click
 a row -> Screen 2 -> F3 back -> next row (see
 AutoClipCaptureSqlPipelineScreen1.ps1 and ...Screen2.ps1), so no
 'Sql_*' state should ever actually be set.

 This file exists only so AutoClipCapture.ps1's dot-source of it at
 startup succeeds, and so that IF some future state machine change
 ever does set a 'Sql_*' state by mistake (or on purpose, once this is
 built out), the pipeline fails safely - stopping with a clear message
 - instead of the tick switch silently matching nothing and the
 automation hanging forever in an unhandled state.

 When this actually gets built out, it should follow the same shape as
 the other two files: a few small states (Action -> Wait -> Copy),
 using $pipeline.Sql (already present in AutoClipCaptureConfig.json
 and already defaulted by AutoClipCapture.ps1's
 Add-PipelineLevelDefaults/MaxIterations backfill) for the actual
 found/not-found search logic - mirroring the built-in "SQL Search"
 scan Mode's Action/PostAction/PostCopy loop.
=====================================================================
#>

function Invoke-PipelineScreen3Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen 3 (SQL search) isn't implemented yet - stopping to be safe." -ForegroundColor Red
    Show-RelayResultOverlay -Text "SCREEN 3 NOT IMPLEMENTED - STOPPED" -Color ([System.Drawing.Color]::Red)
    Stop-PipelineCapture
}
