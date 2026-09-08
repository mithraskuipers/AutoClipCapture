<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1Select.ps1

 SQL Pipeline - Screen 1 Select (rewind-to-top, then list-driven row
 selection).

 Dot-sourced by AutoClipCapture.ps1; defines
 Invoke-PipelineScreen1SelectTick, called once per timer tick whenever
 $global:CR_PipelineState starts with "Rewind" or "Select". This phase
 runs right after the Component List pre-pass
 (AutoClipCaptureSqlPipelineComponentList.ps1) finishes, but only when
 the pipeline's Screen1Select.Enabled is true - see
 Complete-PipelineListCapture in that file for the hand-off.

   Rewind_Start (copy the page currently on-screen, as a baseline)
     -> Rewind_Wait -> Rewind_Copy: press F7, copy again, compare to
        the baseline
          -> different -> that's the new baseline; press F7 again
             (Rewind_Start, next page up)
          -> same -> F7 stopped changing anything, so this is page 1.
             Move on to loading the list.
     -> Select_LoadList: read the just-created component list file
        (Screen1Select.SkipsLoadFrom = $global:CR_PipelineListOutputPath)
        and pull each row's component id (the whitespace-delimited
        token right after Screen1Select.RowPrefixText, e.g. "COB") out
        in file order.
     -> Select_SearchPage -> Select_SearchCopy: copy the page
        currently on-screen; split it into lines, split each line
        into whitespace tokens, and look for a line whose first token
        is RowPrefixText and whose *second token is exactly* the
        current id - a token-for-token comparison, never a substring
        search, so "KI001" can never match a row for "KI0011" or
        "KI001A"
          -> found -> click Screen1Select.InputColumn on that row (the
             classic ISPF-style prefix/selection field), then type
             Screen1Select.ActionKeyChar (default "B"), VERIFY it
             landed correctly (see below), and only then press Enter
             -> Select_ClickWait -> Select_VerifyPlacementWait ->
             Select_VerifyPlacementCopy -> Select_TypeWait ->
             Select_VerifyCopy: copy again and check which screen
             we're on
               -> screen 2 -> it worked. Log it, go back with F3
                  (Select_BackAction -> Select_BackWait), then move on
                  to the next id. (What happens after landing on
                  screen 2 is a separate feature to be added later -
                  for now this phase's job ends at "F3 back, try the
                  next one", so the row-selection mechanism itself can
                  be watched and verified end to end before anything
                  gets built on top of it.)
               -> still screen 1 -> unavailable (same
                  Component.UnavailableText check Screen 1's classic
                  zoom flow already uses) or the click/type simply
                  didn't land - either way, already on screen 1, so
                  just move on to the next id directly, no F3 needed.
          -> not found, and the page doesn't say
             ComponentList.BottomOfListText either -> press F8
             (Screen1Select.NextActionToken) and search the next page
          -> not found, but the page DOES say BottomOfListText -> this
             id genuinely isn't anywhere in the list (a data mismatch,
             since it came from the list we just built) - log it and
             move on to the next id without paging further
     -> once every id from the list has been tried -> "PIPELINE
        COMPLETE" and stop.

 Row-selection actions (the Select_* states) run at
 Screen1Select.StepDelayMs (default 900ms) rather than the pipeline's
 usual fast AfterActionKeyDelayMs/CopyDelayMs, specifically so they can
 be watched end to end while still being verified - turn it down once
 it's known to work reliably.

 The rewind-to-top phase (the Rewind_* states, pressing F7 until the
 page stops changing) doesn't need that same caution - it's just
 "press F7, copy, compare" in a loop - so it runs at the separate,
 faster Screen1Select.RewindStepDelayMs (default 300ms) instead. Falls
 back to StepDelayMs if RewindStepDelayMs isn't set in the config.

 ---- Click point: fixed screen grid, no calibration, no click ----
 The target screen is a fixed-size character grid -
 Screen1Select.GridRows x Screen1Select.GridCols (32x80 for a classic
 3270 model 2 screen). Two more fixed facts about that grid describe
 exactly where the selection field lives:
   - Screen1Select.InputColumn: the 1-based column where the action
     character (e.g. "B") goes, on every row - always the same column,
     because the prefix/selection field is a fixed part of the panel.
   - Screen1Select.DataStartRow: the 1-based row where the TOPMOST
     visible data row always sits.
 From those, plus the target window's own current client pixel size
 (GetClientRect), Get-PipelinePageClickPoint works out an exact click
 point with no manual click and no calibration step at all:
   1. pixelsPerCol = clientWidth  / GridCols
      pixelsPerRow = clientHeight / GridRows
   2. Find-PipelineFirstComponentRow finds the topmost RowPrefixText
      row in the CURRENT page's raw clipboard text (its 0-based text-
      line index). The row we actually want to click may be several
      text lines below that, on the same page.
   3. TargetGridRow = DataStartRow + (TargetTextRow - TopTextRow)
      ClientX = (InputColumn  - 0.5) * pixelsPerCol
      ClientY = (TargetGridRow - 0.5) * pixelsPerRow
 The "- 0.5" centers the click inside the character cell rather than
 on its edge.

 ---- Verify before Enter ----
 After clicking and typing Screen1Select.ActionKeyChar (e.g. "B"), the
 pipeline does NOT press Enter right away. It copies the screen again
 first and checks two things (Test-PipelineActionCharPlacement):
   - the character actually landed at column InputColumn on the
     target row's own text line, and nowhere else;
   - the "Command ===>" line did not pick up that character (the
     classic symptom of a wrong click point).
 Only if both checks pass does it press Enter. If either fails, it
 logs why, shows an on-screen "MISPLACED" warning, and stops the
 pipeline without pressing Enter - clear the stray character by hand
 and figure out why before starting the pipeline again (a wrong
 GridRows/GridCols/InputColumn/DataStartRow in the config is the most
 likely cause).

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs, $LogDir,
 Set-RelayForeground, Set-RelayStatus, Test-RelayTextContains,
 Update-PipelineScreenTracking, Show-RelayResultOverlay,
 Invoke-RelayMouseClick, Get-RelayClientSize, Stop-PipelineCapture) -
 all in scope here because this file is dot-sourced directly into that
 script, not run standalone.
=====================================================================
#>

# Parses the saved component-list text file into an ordered array of
# component ids: for each non-blank line, splits on whitespace and
# keeps the second token when the first token matches RowPrefixText
# (e.g. "    COB      KI001    KI       KI" -> "KI001"). Lines that
# don't match that shape are skipped rather than causing an error, so
# stray blank lines or a trailing note in the file can't break parsing.
function Get-PipelineComponentIdsFromListFile {
    param(
        [string]$Path,
        [string]$RowPrefixText
    )
    $ids = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $Path)) { return $ids.ToArray() }

    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $tokens = $trimmed -split '\s+'
        if ($tokens.Count -ge 2 -and $tokens[0] -eq $RowPrefixText) {
            [void]$ids.Add($tokens[1])
        }
    }
    return $ids.ToArray()
}

# Searches raw (unfiltered) captured text line-by-line for a row whose
# first whitespace token is RowPrefixText and whose second token is
# *exactly* TargetId - never a substring/Contains match. Returns
# $null when nothing matches, otherwise an object with the 0-based
# line index and the character column RowPrefixText starts at on that
# line (both needed for the click-point math, and both measured
# against the raw text so they line up with the real on-screen grid -
# filtering/trimming would shift them).
function Find-PipelineComponentRow {
    param(
        [string]$Text,
        [string]$RowPrefixText,
        [string]$TargetId
    )
    if ([string]::IsNullOrEmpty($Text)) { return $null }

    $lines = $Text -split "`r`n|`r|`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $tokens = $trimmed -split '\s+'
        if ($tokens.Count -ge 2 -and $tokens[0] -eq $RowPrefixText -and $tokens[1] -eq $TargetId) {
            $col = $line.IndexOf($RowPrefixText, [StringComparison]::OrdinalIgnoreCase)
            if ($col -lt 0) { $col = 0 }
            return [pscustomobject]@{ Row = $i; Col = $col }
        }
    }
    return $null
}

# Like Find-PipelineComponentRow, but returns the TOPMOST row whose
# first whitespace token is RowPrefixText, regardless of which id it
# is. Used as the per-page reference point for click-point math - see
# Get-PipelinePageClickPoint below.
function Find-PipelineFirstComponentRow {
    param(
        [string]$Text,
        [string]$RowPrefixText
    )
    if ([string]::IsNullOrEmpty($Text)) { return $null }

    $lines = $Text -split "`r`n|`r|`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $tokens = $trimmed -split '\s+'
        if ($tokens.Count -ge 1 -and $tokens[0] -eq $RowPrefixText) {
            $col = $lines[$i].IndexOf($RowPrefixText, [StringComparison]::OrdinalIgnoreCase)
            if ($col -lt 0) { $col = 0 }
            return [pscustomobject]@{ Row = $i; Col = $col }
        }
    }
    return $null
}

# Computes the CLIENT-relative pixel point to click for TargetRow (a
# 0-based line index into $Text), using the FIXED screen grid
# (Screen1Select.GridRows/GridCols/InputColumn/DataStartRow) and the
# target window's CURRENT client pixel size - no click, no stored
# calibration. Returns $null if the topmost row can't be found on this
# page or the window's client size is unavailable - callers must treat
# $null as "can't click safely right now" and stop rather than guess.
# See the header comment above for the full explanation.
function Get-PipelinePageClickPoint {
    param(
        [string]$Text,
        [int]$TargetRow,
        [string]$RowPrefixText,
        [IntPtr]$Handle,
        $SelectCfg
    )
    $topRow = Find-PipelineFirstComponentRow -Text $Text -RowPrefixText $RowPrefixText
    if ($null -eq $topRow) { return $null }

    $size = Get-RelayClientSize -Handle $Handle
    if ($null -eq $size) { return $null }

    $gridRows = [double]$SelectCfg.GridRows
    $gridCols = [double]$SelectCfg.GridCols
    if ($gridRows -le 0 -or $gridCols -le 0) { return $null }

    $pixelsPerCol = [double]$size.Width  / $gridCols
    $pixelsPerRow = [double]$size.Height / $gridRows

    $targetGridRow = [double]$SelectCfg.DataStartRow + ($TargetRow - $topRow.Row)
    $x = ([double]$SelectCfg.InputColumn - 0.5) * $pixelsPerCol
    $y = ($targetGridRow - 0.5) * $pixelsPerRow
    return New-Object System.Drawing.Point([int][Math]::Round($x), [int][Math]::Round($y))
}

# Checks whether Screen1Select.ActionKeyChar actually landed exactly
# at column InputColumn on the target row's own text line - and, just
# as importantly, that it did NOT land on the "Command ===>" line,
# which is the classic sign of a wrong click point (a wrong
# GridRows/GridCols/InputColumn/DataStartRow, most likely). Re-reads
# the row by its saved line index rather than re-searching for the id,
# since once the action character is typed, that row's own leading
# token is no longer RowPrefixText.
function Test-PipelineActionCharPlacement {
    param(
        [string]$Text,
        [int]$Row,
        [int]$Col,
        [string]$ExpectedChar
    )
    $result = [pscustomobject]@{ Placed = $false; OnCommandLine = $false }
    if ([string]::IsNullOrEmpty($Text)) { return $result }

    $lines = $Text -split "`r`n|`r|`n"

    $commandPattern = "Command\s*===>\s*" + [regex]::Escape($ExpectedChar) + "(\s|$)"
    if (($lines -join "`n") -match $commandPattern) {
        $result.OnCommandLine = $true
        return $result
    }

    if ($Row -lt 0 -or $Row -ge $lines.Count -or $Col -lt 0) { return $result }
    $line = $lines[$Row]
    if ($Col -ge $line.Length) { return $result }

    $result.Placed = ($line.Substring($Col, 1) -eq $ExpectedChar)
    return $result
}

# Advances to the next id in the list (or finishes the pipeline if
# that was the last one) and resets the per-id search-page counter.
# Shared by every "done with this id" exit point below so they can't
# drift out of sync with each other.
function Complete-PipelineComponentSelection {
    param($Pipeline)

    $global:CR_PipelineComponentIdx++
    $global:CR_PipelineSelectSearchPages = 0

    if ($global:CR_PipelineComponentIdx -ge $global:CR_PipelineComponentList.Count) {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] All $($global:CR_PipelineComponentList.Count) component(s) from the list processed." -ForegroundColor Cyan
        Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
        Stop-PipelineCapture
        return
    }

    $global:CR_PipelineState = 'Select_SearchPage'
    $global:CR_ElapsedMs = 0
}

function Invoke-PipelineScreen1SelectTick {
    $pipeline = $global:CR_ActivePipelineConfig
    $selCfg   = $pipeline.Screen1Select
    $comp     = $pipeline.Component
    $delay    = [int]$selCfg.StepDelayMs
    # Rewind (pressing F7 back to the top of screen 1) doesn't need the
    # cautious, watch-it-happen pace the row-selection steps still use -
    # it's just "press F7, copy, compare" in a loop, so it can run much
    # faster. Falls back to StepDelayMs if RewindStepDelayMs isn't set.
    $rewindDelay = if ($null -ne $selCfg.RewindStepDelayMs) { [int]$selCfg.RewindStepDelayMs } else { $delay }

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
                $global:CR_PipelineState = 'Select_LoadList'
                $global:CR_ElapsedMs = 0
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

        # ---- Load the saved list, then start hunting for each id ----
        'Select_LoadList' {
            $ids = Get-PipelineComponentIdsFromListFile -Path $global:CR_PipelineListOutputPath -RowPrefixText $selCfg.RowPrefixText
            $global:CR_PipelineComponentList = $ids
            $global:CR_PipelineComponentIdx = 0
            $global:CR_PipelineSelectSearchPages = 0

            if ($ids.Count -eq 0) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: no component ids found in $($global:CR_PipelineListOutputPath) - nothing to do." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NO COMPONENTS FOUND" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: loaded $($ids.Count) component id(s) from the list. Starting selection." -ForegroundColor Green
            $global:CR_PipelineState = 'Select_SearchPage'
            $global:CR_ElapsedMs = 0
        }

        # ---- Copy the page currently on-screen and search it for the
        # current id. ----
        'Select_SearchPage' {
            if ($global:CR_PipelineComponentIdx -ge $global:CR_PipelineComponentList.Count) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] All $($global:CR_PipelineComponentList.Count) component(s) from the list processed." -ForegroundColor Cyan
                Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                Stop-PipelineCapture
                return
            }
            $targetId = $global:CR_PipelineComponentList[$global:CR_PipelineComponentIdx]
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Component $($global:CR_PipelineComponentIdx + 1)/$($global:CR_PipelineComponentList.Count) ($targetId): searching page" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'Select_SearchCopy'
            $global:CR_ElapsedMs = 0
        }
        'Select_SearchCopy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            $targetId = $global:CR_PipelineComponentList[$global:CR_PipelineComponentIdx]
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
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: landed on screen $detected instead of screen 1 while searching for '$targetId' - stopping to be safe." -ForegroundColor Red
                Show-RelayResultOverlay -Text "UNEXPECTED SCREEN - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            $found = Find-PipelineComponentRow -Text $text -RowPrefixText $selCfg.RowPrefixText -TargetId $targetId
            if ($null -ne $found) {
                $pt = Get-PipelinePageClickPoint -Text $text -TargetRow $found.Row -RowPrefixText $selCfg.RowPrefixText -Handle $global:CR_TargetHandle -SelectCfg $selCfg
                if ($null -eq $pt) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: couldn't work out a click point for '$targetId' (topmost row not found on this page, or window size unavailable) - stopping." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "CLICK POINT FAILED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }

                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: found '$targetId' at row $($found.Row) - clicking (client $($pt.X), $($pt.Y))." -ForegroundColor DarkCyan
                if (-not (Invoke-RelayMouseClick -Handle $global:CR_TargetHandle -ClientX $pt.X -ClientY $pt.Y)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                $global:CR_PipelineSelectFoundRow = $found.Row
                $global:CR_PipelineState = 'Select_ClickWait'
                $global:CR_ElapsedMs = 0
                return
            }

            if (Test-RelayTextContains -Text $text -Needle $pipeline.ComponentList.BottomOfListText) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' not found anywhere in the list (reached bottom) - skipping." -ForegroundColor Yellow
                Complete-PipelineComponentSelection -Pipeline $pipeline
                return
            }

            $global:CR_PipelineSelectSearchPages++
            if ($global:CR_PipelineSelectSearchPages -ge [int]$selCfg.MaxSearchPagesPerItem) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' not found within $($selCfg.MaxSearchPagesPerItem) page(s) - skipping." -ForegroundColor Yellow
                Complete-PipelineComponentSelection -Pipeline $pipeline
                return
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.NextActionToken)
            $global:CR_PipelineState = 'Select_SearchPage'
            $global:CR_ElapsedMs = 0
        }

        # ---- Click landed - type ONLY the action key (no Enter yet),
        # then copy and verify it landed in the right place before
        # committing with Enter. ----
        'Select_ClickWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.ActionKeyChar)
            $global:CR_PipelineState = 'Select_VerifyPlacementWait'
            $global:CR_ElapsedMs = 0
        }
        'Select_VerifyPlacementWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'Select_VerifyPlacementCopy'
            $global:CR_ElapsedMs = 0
        }
        'Select_VerifyPlacementCopy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            $targetId = $global:CR_PipelineComponentList[$global:CR_PipelineComponentIdx]
            $text = ''
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $text = [System.Windows.Forms.Clipboard]::GetText()
                }
            } catch {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
            }

            $placeCol  = [int]$selCfg.InputColumn - 1   # config is 1-based, text index is 0-based
            $placement = Test-PipelineActionCharPlacement -Text $text -Row $global:CR_PipelineSelectFoundRow -Col $placeCol -ExpectedChar $selCfg.ActionKeyChar

            if ($placement.OnCommandLine -or -not $placement.Placed) {
                if ($placement.OnCommandLine) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$($selCfg.ActionKeyChar)' landed on the Command line instead of next to '$targetId' - the click point is wrong. Stopping before pressing Enter." -ForegroundColor Red
                } else {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$($selCfg.ActionKeyChar)' did not land at column $($selCfg.InputColumn) on '$targetId''s row as expected - the click point is wrong. Stopping before pressing Enter." -ForegroundColor Red
                }
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clear the stray '$($selCfg.ActionKeyChar)' by hand, double-check Screen1Select.GridRows/GridCols/InputColumn/DataStartRow, then start the pipeline again." -ForegroundColor Yellow
                Show-RelayResultOverlay -Text "MISPLACED '$($selCfg.ActionKeyChar)' - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.ActionKeyEnterToken)
            $global:CR_PipelineState = 'Select_TypeWait'
            $global:CR_ElapsedMs = 0
        }
        'Select_TypeWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'Select_VerifyCopy'
            $global:CR_ElapsedMs = 0
        }
        'Select_VerifyCopy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            $targetId = $global:CR_PipelineComponentList[$global:CR_PipelineComponentIdx]
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
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' opened successfully -> screen 2. Going back." -ForegroundColor Green
                $global:CR_PipelineState = 'Select_BackAction'
                $global:CR_ElapsedMs = 0
            } elseif ($detected -eq 1) {
                if (Test-RelayTextContains -Text $text -Needle $comp.UnavailableText) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' unavailable - skipping." -ForegroundColor Yellow
                } else {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' didn't open (stayed on screen 1, '$($comp.UnavailableText)' not seen) - skipping." -ForegroundColor Yellow
                }
                Complete-PipelineComponentSelection -Pipeline $pipeline
            } else {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: unexpected screen (detected: $detected) after trying '$targetId' - skipping." -ForegroundColor Yellow
                Complete-PipelineComponentSelection -Pipeline $pipeline
            }
        }

        # ---- Back to screen 1, then move on to the next id ----
        'Select_BackAction' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.BackActionToken)
            $global:CR_PipelineState = 'Select_BackWait'
            $global:CR_ElapsedMs = 0
        }
        'Select_BackWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }
            Complete-PipelineComponentSelection -Pipeline $pipeline
        }
    }
}
