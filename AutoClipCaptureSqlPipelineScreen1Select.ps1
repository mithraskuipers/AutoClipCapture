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
          -> found -> click Screen1Select.ClickColumnOffset columns to
             the side of that row's RowPrefixText (default -1, i.e.
             one column to its left - the classic ISPF-style
             prefix/selection field)
             -> Select_ClickWait: clear the primary command line
                (in case a previous attempt's action key ended up
                there instead of in a row's prefix field - see the
                contamination check below) and re-click the row,
                then type Screen1Select.ActionKeyChar (default "B")
                *without* pressing Enter yet
             -> Select_TypeWait -> Select_VerifyPlacementCopy: copy
                the screen again and check, BEFORE pressing Enter:
                  a) the action key character actually landed exactly
                     Screen1Select.ClickColumnOffset columns to the
                     side of the target row's RowPrefixText - i.e. is
                     really sitting in that row's prefix field - and
                  b) Screen1Select.CommandPromptText (default
                     "Command ===>") is NOT immediately followed by
                     the action key character anywhere on the page -
                     which is what it looks like when the character
                     lands in the primary command line instead of a
                     row's prefix field.
                Both have to pass, or Enter never gets pressed for
                this id at all - see "Placement verification" below.
             -> Select_EnterAction -> Select_EnterWait ->
                Select_VerifyCopy: copy again and check which screen
                we're on
                  -> screen 2 -> it worked. Log it, go back with F3
                     (Select_BackAction -> Select_BackWait), then move
                     on to the next id. (What happens after landing on
                     screen 2 is a separate feature to be added later -
                     for now this phase's job ends at "F3 back, try
                     the next one", so the row-selection mechanism
                     itself can be watched and verified end to end
                     before anything gets built on top of it.)
                  -> still screen 1 -> unavailable (same
                     Component.UnavailableText check Screen 1's
                     classic zoom flow already uses) - move on to the
                     next id directly, no F3 needed.
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

 ---- Mouse-click calibration ----
 Every click is computed as a plain grid formula, in CLIENT-relative
 pixels (i.e. relative to the target window's own client area):

     ClientX = Screen1Select.OriginX + Column * Screen1Select.CharWidthPx
     ClientY = Screen1Select.OriginY + Row    * Screen1Select.CharHeightPx

 ...where Row/Column are 0-based positions *within the raw clipboard
 text* (Row = which line, Column = character offset into that line),
 and OriginX/OriginY are the pixel position of ROW 0 / COLUMN 0 of
 that same text - not the position of any particular row.

 There's no separate calibration script/session for this anymore.
 Instead, AutoClipCapture.ps1's startup banner tells the user, for
 every pipeline with Screen1Select enabled: click the terminal with
 the mouse Screen1Select.ClickColumnOffset column(s) to the side of
 the TOPMOST visible RowPrefixText row before pressing that pipeline's
 hotkey. Set-Screen1SelectCalibrationFromMouse (below) then reads
 wherever the mouse happens to be right at that moment, copies the
 screen the user is looking at to find the real (Row, Col) of that
 topmost row, measures the window's client pixel size, and back-solves
 OriginX/OriginY/CharWidthPx/CharHeightPx from those two things - no
 dialog, nothing else needed from the user. If it can't find a
 RowPrefixText row on the currently-visible screen (i.e. the user
 hadn't actually navigated/clicked there yet), it says so in the
 console and the pipeline doesn't start - just click the right spot
 and press the hotkey again.

 ---- Placement verification ----
 Because a click landing even one row or column off can end up typing
 the action key character into the wrong field - including the
 terminal's own primary command line, which silently accepts stray
 letters as commands - every attempt is verified with a Ctrl+C copy
 BEFORE Enter is pressed, not after: see Test-Screen1SelectPlacement
 below. The command line also gets defensively cleared right before
 every attempt (Select_ClickWait), regardless of whether the previous
 attempt was judged to have gone wrong, so a stray character from one
 attempt can never carry over and contaminate the next.

 Relies on shared state/helpers defined in AutoClipCapture.ps1
 ($global:CR_* pipeline state, $TimerTickMs / $CopyDelayMs, $LogDir,
 Set-RelayForeground, Set-RelayStatus, Test-RelayTextContains,
 Update-PipelineScreenTracking, Show-RelayResultOverlay,
 Invoke-RelayMouseClick, Stop-PipelineCapture) - all in scope here
 because this file is dot-sourced directly into that script, not run
 standalone.
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
        # RowPrefixText doesn't have to be the very first token - once
        # the action key has been typed into the prefix field, the
        # field's own leftover character(s) (e.g. a permanent "_"
        # placeholder before the editable position) glue together with
        # the typed key into their own token, pushing RowPrefixText to
        # the second token position. So this scans every token
        # position for RowPrefixText immediately followed by TargetId,
        # not just position 0 - matches both before and after typing.
        for ($t = 0; $t -lt ($tokens.Count - 1); $t++) {
            if ($tokens[$t] -eq $RowPrefixText -and $tokens[$t + 1] -eq $TargetId) {
                $col = $line.IndexOf($RowPrefixText, [StringComparison]::OrdinalIgnoreCase)
                if ($col -lt 0) { $col = 0 }
                return [pscustomobject]@{ Row = $i; Col = $col }
            }
        }
    }
    return $null
}

# Computes the CLIENT-relative pixel point for a 0-based (Row, Col)
# text position, using the Screen1Select calibration fields. See the
# header comment above for what these mean and how to measure them.
function Get-PipelineGridClickPoint {
    param([int]$Row, [int]$Col, $SelectCfg)
    $x = [double]$SelectCfg.OriginX + ($Col * [double]$SelectCfg.CharWidthPx)
    $y = [double]$SelectCfg.OriginY + ($Row * [double]$SelectCfg.CharHeightPx)
    return New-Object System.Drawing.Point([int][Math]::Round($x), [int][Math]::Round($y))
}

# Same raw-text scan as Find-PipelineComponentRow above, but matches
# on RowPrefixText alone (no target id) - used by the mouse-based
# calibration below to find the topmost visible row, whatever id it
# has.
function Find-PipelineFirstRowWithPrefix {
    param(
        [string]$Text,
        [string]$RowPrefixText
    )
    if ([string]::IsNullOrEmpty($Text)) { return $null }

    $lines = $Text -split "`r`n|`r|`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $tokens = $trimmed -split '\s+'
        foreach ($tok in $tokens) {
            if ($tok -eq $RowPrefixText) {
                $col = $line.IndexOf($RowPrefixText, [StringComparison]::OrdinalIgnoreCase)
                if ($col -lt 0) { $col = 0 }
                return [pscustomobject]@{ Row = $i; Col = $col }
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------------
# Set-Screen1SelectCalibrationFromMouse
#
# No dialog, nothing interactive - just reads wherever the mouse
# currently is (the user was told, in the startup banner, to click
# there before pressing this pipeline's hotkey) and derives
# OriginX/OriginY/CharWidthPx/CharHeightPx from it:
#
#   1. Copies the screen the user is looking at right now and finds
#      the real (Row, Col) of the topmost RowPrefixText row in the raw
#      clipboard text - using the exact same parsing
#      (Find-PipelineFirstRowWithPrefix, built the same way as
#      Find-PipelineComponentRow) that the live row search uses at
#      runtime, so calibration and matching can never drift apart.
#   2. Reads the window's client pixel size and divides by the
#      terminal's fixed 80x32 character grid to get
#      CharWidthPx/CharHeightPx.
#   3. Back-solves OriginX/OriginY so the grid formula
#         ClientX = OriginX + Col * CharWidthPx
#         ClientY = OriginY + Row * CharHeightPx
#      reproduces exactly where the mouse is right now for that
#      measured (Row, Col).
#   4. Saves the result into this pipeline's Screen1Select block and
#      persists AutoClipCaptureConfig.json (after backing up the old
#      one), then returns $true so the pipeline can start immediately.
#
# Returns $false (nothing changed, nothing clicked/typed) if the
# target window can't be measured, or no RowPrefixText row is visible
# right now to measure against - in which case the user just needs to
# click the right spot and press the hotkey again.
# ---------------------------------------------------------------------
function Set-Screen1SelectCalibrationFromMouse {
    param($Pipeline, [IntPtr]$Handle)

    $selCfg = $Pipeline.Screen1Select
    $offset = [int]$selCfg.ClickColumnOffset

    # Grab the cursor position immediately - nothing between here and
    # using it should move the real mouse pointer.
    $cursorScreenPos = [System.Windows.Forms.Cursor]::Position

    if (-not (Set-RelayForeground -Handle $Handle)) {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Target window is gone - start cancelled." -ForegroundColor Red
        return $false
    }

    [System.Windows.Forms.SendKeys]::SendWait('^c')
    Start-Sleep -Milliseconds 300

    $text = ''
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $text = [System.Windows.Forms.Clipboard]::GetText()
        }
    } catch {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
    }

    $found = Find-PipelineFirstRowWithPrefix -Text $text -RowPrefixText $selCfg.RowPrefixText
    if ($null -eq $found) {
        $sideCount = [Math]::Abs($offset)
        $side = if ($offset -lt 0) { "left" } else { "right" }
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Start cancelled - no '$($selCfg.RowPrefixText)' row visible on the current screen." -ForegroundColor Red
        Write-Host "  Click the terminal $sideCount character(s) to the $side of the TOPMOST visible '$($selCfg.RowPrefixText)' row, then press this pipeline's hotkey again." -ForegroundColor Yellow
        return $false
    }

    $clientPt = New-Object System.Drawing.Point($cursorScreenPos.X, $cursorScreenPos.Y)
    if (-not [Win32]::ScreenToClient($Handle, [ref]$clientPt)) {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Couldn't convert the mouse position - start cancelled." -ForegroundColor Red
        return $false
    }

    $rect = New-Object RECT
    if (-not [Win32]::GetClientRect($Handle, [ref]$rect)) {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Couldn't read the target window's size - start cancelled." -ForegroundColor Red
        return $false
    }
    $clientW = $rect.Right - $rect.Left
    $clientH = $rect.Bottom - $rect.Top
    if ($clientW -le 0 -or $clientH -le 0) {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Target window has no usable size - start cancelled." -ForegroundColor Red
        return $false
    }

    $cols = 80
    $rows = 32
    $charWidthPx  = $clientW / $cols
    $charHeightPx = $clientH / $rows

    $clickCol = $found.Col + $offset

    $originX = $clientPt.X - ($clickCol  * $charWidthPx)
    $originY = $clientPt.Y - ($found.Row * $charHeightPx)

    $selCfg.OriginX      = [math]::Round($originX, 2)
    $selCfg.OriginY      = [math]::Round($originY, 2)
    $selCfg.CharWidthPx  = [math]::Round($charWidthPx, 2)
    $selCfg.CharHeightPx = [math]::Round($charHeightPx, 2)

    try {
        $backupPath = Join-Path $PSScriptRoot ("AutoClipCaptureConfig.backup-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        if (Test-Path $ConfigPath) { Copy-Item -Path $ConfigPath -Destination $backupPath -Force }
        $Config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
    } catch {
        Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Calibrated for this run, but saving to config failed: $_" -ForegroundColor Yellow
    }

    Write-Host "[AutoClipCapture] [$($Pipeline.Name)] Calibrated from mouse position - OriginX=$($selCfg.OriginX) OriginY=$($selCfg.OriginY) CharWidthPx=$($selCfg.CharWidthPx) CharHeightPx=$($selCfg.CharHeightPx)." -ForegroundColor Green
    return $true
}

# ---------------------------------------------------------------------
# Test-Screen1SelectPlacement
#
# Called after the action key character has been typed but BEFORE
# Enter is pressed. Copies the screen (the caller passes in that raw
# text) and checks two things:
#
#   a) The character actually sitting Screen1Select.ClickColumnOffset
#      column(s) to the side of TargetId's RowPrefixText really is
#      ActionKeyChar - i.e. it landed in that row's prefix field, and
#      nowhere else. Re-finds the row fresh (same parsing as the live
#      search) rather than trusting the row/column found earlier, so
#      this check can't be fooled by anything that shifted between the
#      click and now.
#   b) CommandPromptText (default "Command ===>") is NOT immediately
#      followed by ActionKeyChar anywhere in the text - that pattern
#      only appears when the character landed in the terminal's
#      primary command line instead of a row's prefix field.
#
# Returns a pscustomobject: { Ok, Reason, Row, Col }. Ok is $true only
# when both checks pass.
# ---------------------------------------------------------------------
function Test-Screen1SelectPlacement {
    param(
        [string]$Text,
        [string]$TargetId,
        $SelectCfg
    )

    $offset = [int]$SelectCfg.ClickColumnOffset
    $actionChar = [string]$SelectCfg.ActionKeyChar
    $cmdPromptText = if ($SelectCfg.PSObject.Properties.Name -contains 'CommandPromptText' -and $SelectCfg.CommandPromptText) {
        [string]$SelectCfg.CommandPromptText
    } else {
        'Command ===>'
    }

    # b) Command-line contamination check - anywhere in the text.
    $contamPattern = [regex]::Escape($cmdPromptText) + '\s*' + [regex]::Escape($actionChar)
    if ([regex]::IsMatch($Text, $contamPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        return [pscustomobject]@{ Ok = $false; Reason = "'$actionChar' appears right after '$cmdPromptText' - it landed in the command line, not the row's prefix field"; Row = -1; Col = -1 }
    }

    # a) Placement check - re-find the row fresh.
    $found = Find-PipelineComponentRow -Text $Text -RowPrefixText $SelectCfg.RowPrefixText -TargetId $TargetId
    if ($null -eq $found) {
        return [pscustomobject]@{ Ok = $false; Reason = "row for '$TargetId' isn't on screen anymore"; Row = -1; Col = -1 }
    }

    $expectedCol = $found.Col + $offset
    $lines = $Text -split "`r`n|`r|`n"
    $line = $lines[$found.Row]
    $actualChar = if ($expectedCol -ge 0 -and $expectedCol -lt $line.Length) { $line.Substring($expectedCol, 1) } else { '' }

    if ($actualChar -ne $actionChar) {
        return [pscustomobject]@{ Ok = $false; Reason = "expected '$actionChar' $([Math]::Abs($offset)) column(s) from '$($SelectCfg.RowPrefixText)' on row $($found.Row), found '$actualChar' instead"; Row = $found.Row; Col = $expectedCol }
    }

    return [pscustomobject]@{ Ok = $true; Reason = 'placement verified'; Row = $found.Row; Col = $expectedCol }
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
                $clickCol = $found.Col + [int]$selCfg.ClickColumnOffset
                $pt = Get-PipelineGridClickPoint -Row $found.Row -Col $clickCol -SelectCfg $selCfg
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: found '$targetId' at row $($found.Row) - clicking (row $($found.Row), col $clickCol)." -ForegroundColor DarkCyan
                if (-not (Invoke-RelayMouseClick -Handle $global:CR_TargetHandle -ClientX $pt.X -ClientY $pt.Y)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                $global:CR_PipelineSelectClickPoint = $pt
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
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' not on this page - pressing $($selCfg.NextActionDisplay) for the next one." -ForegroundColor DarkCyan
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.NextActionToken)
            $global:CR_PipelineState = 'Select_SearchPage'
            $global:CR_ElapsedMs = 0
        }

        # ---- Click landed. Before typing the action key: defensively
        # clear the primary command line (in case a previous attempt's
        # character ended up there instead of in a row's prefix
        # field), then re-click the target row (clearing the command
        # line likely moved focus away from it) and type the action
        # key character - but NOT Enter yet, that only happens after
        # Select_VerifyPlacementCopy confirms it landed correctly. ----
        'Select_ClickWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -lt $delay) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait('{HOME}' + (' ' * 30))
            $pt = $global:CR_PipelineSelectClickPoint
            if (-not (Invoke-RelayMouseClick -Handle $global:CR_TargetHandle -ClientX $pt.X -ClientY $pt.Y)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.ActionKeyChar)
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
            $global:CR_PipelineState = 'Select_VerifyPlacementCopy'
            $global:CR_ElapsedMs = 0
        }

        # ---- BEFORE pressing Enter: copy and verify the action key
        # character really landed in the target row's prefix field,
        # and definitely not next to the command prompt. Enter is only
        # ever sent from Select_EnterAction, once this has passed. ----
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

            $check = Test-Screen1SelectPlacement -Text $text -TargetId $targetId -SelectCfg $selCfg
            if ($check.Ok) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' - placement verified (row $($check.Row), col $($check.Col)). Pressing Enter." -ForegroundColor DarkCyan
                $global:CR_PipelineState = 'Select_EnterAction'
                $global:CR_ElapsedMs = 0
            } else {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' - placement check FAILED ($($check.Reason)). NOT pressing Enter - skipping this component." -ForegroundColor Red
                Complete-PipelineComponentSelection -Pipeline $pipeline
            }
        }
        'Select_EnterAction' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            [System.Windows.Forms.SendKeys]::SendWait($selCfg.ActionKeyEnterToken)
            $global:CR_PipelineState = 'Select_EnterWait'
            $global:CR_ElapsedMs = 0
        }
        'Select_EnterWait' {
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
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Select: '$targetId' opened successfully -> screen 2. Going back with $($selCfg.BackActionDisplay)." -ForegroundColor Green
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
