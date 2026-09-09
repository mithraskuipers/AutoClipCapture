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
 once, top to bottom, and saves the list of components it finds to a
 Markdown table. It never leaves Screen 1, and it never clicks or
 types into any row - this pipeline no longer selects/opens
 individual components, it only lists them.

 This is the automated equivalent of a person doing, by hand: Ctrl+C
 the current page, note down each component's id, press F8 to scroll
 to the next page, and repeat - stopping only once a page comes back
 identical to the one before it (i.e. F8 stopped revealing anything
 new, so the end of the list has been reached).

   ListCapture_Start (page 1 is already on-screen - no page-turn needed)
     -> ListCapture_Wait -> read clipboard, filter, pull each row's
        component id out (the whitespace-delimited token right after
        Screen1Select.RowPrefixText, e.g. "COB") and append them to
        $global:CR_PipelineComponentList
          -> more to do -> ListNext_Action -> ListNext_Wait
             -> ListCapture_Wait (next page)
          -> page contains ComponentList.BottomOfListText (default
             "Bottom of List"), or a page comes back identical to the
             one before it -> end of the list reached.
        Either way, "end of the list" hands off to
        Complete-PipelineListCapture: if this pipeline's
        Screen1Select.Enabled is true, that's a rewind-to-top (see
        AutoClipCaptureSqlPipelineScreen1Select.ps1) and then the
        Markdown file is written; otherwise the Markdown file is
        written immediately and the pipeline stops right here.

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

 ---- Output: a Markdown table, not a raw text dump ----
 $global:CR_PipelineListOutputPath now points at an .md file. Instead
 of appending raw filtered screen text page by page,
 Get-PipelineRowComponentIds pulls just the component id out of each
 matching row (same "first token is RowPrefixText, second token is the
 id" shape Get-PipelineComponentIdsFromListFile used to parse back out
 of the old text file) and appends it to $global:CR_PipelineComponentList
 as it goes. Once the list is complete (and, if enabled, the screen has
 been rewound to the top), Write-PipelineComponentListMarkdown writes
 the whole thing out as a two-column table:

     | # | Component |
     | --- | --- |
     | 1 | KI001 |
     | 2 | KI002 |
     ...

 with # starting at 1 and incrementing once per row, in the order the
 components were found.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs /
 $AfterActionKeyDelayMs, $LogDir, Set-RelayForeground, Set-RelayStatus,
 Get-FilteredCaptureText, Get-TextSimilarity,
 Update-PipelineScreenTracking, Show-RelayResultOverlay,
 Stop-PipelineCapture) - all in scope here because this file is
 dot-sourced directly into that script, not run standalone.
=====================================================================
#>

# Pulls the component id out of each row in $Text whose first
# whitespace token is RowPrefixText (e.g. "COB") - i.e. its SECOND
# token, matching the row shape
# "    COB      KI001    KI       KI" -> "KI001". Lines that don't
# match that shape are skipped rather than causing an error, so stray
# blank lines or footer text can't break parsing. Returns an array
# (possibly empty) of ids, in the order they appear in $Text.
function Get-PipelineRowComponentIds {
    param(
        [string]$Text,
        [string]$RowPrefixText
    )
    $ids = @()
    if ([string]::IsNullOrEmpty($Text)) { return $ids }

    $lines = $Text -split "`r`n|`r|`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $tokens = $trimmed -split '\s+'
        if ($tokens.Count -ge 2 -and $tokens[0] -eq $RowPrefixText) {
            $ids += $tokens[1]
        }
    }
    return $ids
}

# Writes $global:CR_PipelineComponentList out as a Markdown table (# ,
# Component), overwriting whatever's at $global:CR_PipelineListOutputPath.
# Top-level (not nested) so it's callable from
# AutoClipCaptureSqlPipelineScreen1Select.ps1's Rewind_Copy state too,
# once rewinding finishes - that's the only reason this phase still
# rewinds at all, now that it no longer selects individual rows.
function Write-PipelineComponentListMarkdown {
    param($Pipeline)

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('| # | Component |')
    [void]$lines.Add('| --- | --- |')
    $i = 0
    foreach ($id in $global:CR_PipelineComponentList) {
        $i++
        [void]$lines.Add("| $i | $id |")
    }

    try {
        Set-Content -Path $global:CR_PipelineListOutputPath -Value $lines -Encoding UTF8
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Component list: $($global:CR_PipelineComponentList.Count) component(s) written to $($global:CR_PipelineListOutputPath)" -ForegroundColor Green
    } catch {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Failed to write $($global:CR_PipelineListOutputPath): $_" -ForegroundColor Red
    }
}

function Invoke-PipelineListTick {
    $pipeline = $global:CR_ActivePipelineConfig
    $listCfg  = $pipeline.ComponentList
    $rowPrefixText = $pipeline.Screen1Select.RowPrefixText

    # ---- Shared "list capture is done" exit point, used by both the
    # BottomOfListText branch and the duplicate-page branch below. When
    # this pipeline's Screen1Select phase is enabled, hands off to it
    # for a rewind-to-top first - see
    # AutoClipCaptureSqlPipelineScreen1Select.ps1 - otherwise the
    # Markdown file is written right here. ----
    function Complete-PipelineListCapture {
        param([string]$Reason)

        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: $Reason - end of list reached ($($global:CR_PipelineComponentList.Count) component(s), $($global:CR_PipelineListPageIdx) page(s))." -ForegroundColor Cyan

        $selCfg = $pipeline.Screen1Select
        if ($null -ne $selCfg -and [bool]$selCfg.Enabled) {
            Show-RelayResultOverlay -Text "LIST DONE - REWINDING" -Color ([System.Drawing.Color]::DeepSkyBlue)
            $global:CR_PipelineState = 'Rewind_Start'
            $global:CR_ElapsedMs = 0
        } else {
            Write-PipelineComponentListMarkdown -Pipeline $pipeline
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
            # repeat of the one before it - so its components still
            # need to be collected. Once collected, there's nothing
            # left to page through: skip the similarity check and
            # don't press F8 again. ----
            if (Test-RelayTextContains -Text $text -Needle $listCfg.BottomOfListText) {
                $global:CR_PipelineComponentList += (Get-PipelineRowComponentIds -Text $filtered -RowPrefixText $rowPrefixText)
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
                # of the previous one, so its components were already
                # collected. Don't collect it again; the list is
                # complete.
                Complete-PipelineListCapture -Reason "page $($global:CR_PipelineListPageIdx + 1) matches the previous page"
                return
            }

            $global:CR_PipelineComponentList += (Get-PipelineRowComponentIds -Text $filtered -RowPrefixText $rowPrefixText)

            $global:CR_PipelineListPageIdx++
            $global:CR_PipelineListPrevFiltered = $filtered
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Component list: page $($global:CR_PipelineListPageIdx) captured ($($global:CR_PipelineComponentList.Count) component(s) so far)." -ForegroundColor DarkCyan

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
