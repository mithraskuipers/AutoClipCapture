<#
=====================================================================
 AutoClipCaptureConfigGUI.ps1
=====================================================================
 GUI for editing AutoClipCaptureConfig.json - the settings file used
 by AutoClipCapture.ps1. Organized into tabs:

   General           - default log location, the Toggle relay's
                        action key
   Timing & Rows      - copy/action delays, internal poll interval,
                        rows to skip at the start/end of each capture,
                        the found/not-found result-banner duration
   Duplicates         - duplicate-capture detection (pause & ask when
                        back-to-back captures come back almost
                        identical)
   Hotkeys            - the Toggle hotkey (start/stop the classic
                        capture-and-log relay), the Exit hotkey, the
                        SQL Search hotkey, and the F3 (single press)
                        hotkey

 The SQL Search scan mode and the F3 single-press action are no longer
 added/edited from this GUI - only their hotkeys are. Everything else
 about SQL Search (its action key, the phrases it looks for, etc.) is
 still read from AutoClipCaptureConfig.json by AutoClipCapture.ps1;
 edit that file directly if it ever needs to change.

 HOTKEYS (Toggle/Exit/SQL Search/F3) are global shortcuts, so Windows
 requires at least one modifier (Ctrl/Alt/Shift) - a bare key like
 "F9" alone isn't accepted for those. A hotkey can also be marked
 "right-side only", meaning it only fires when the physical RIGHT
 Ctrl/Alt/Shift key is the one held down (useful if a left-hand combo
 you use elsewhere would otherwise collide). SQL Search and F3 default
 to Alt+> and Alt+< and don't require this, since either side's
 Alt/Shift key works fine for those.

 The Toggle relay's ACTION KEY is different: it's just simulated as a
 keypress inside the target application, so it can be a single key
 with no modifier at all (e.g. plain F8), or a modified combo if the
 target app needs one (e.g. Ctrl+F8).

 Changes only take effect the next time AutoClipCapture.ps1 is started
 (or restarted) - it reads the config once at launch.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ConfigPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"

# The default "scan mode" bound to Alt+> - see
# AutoClipCapture.ps1 for the exact loop this describes. Kept identical
# to (and in sync with) the copy in AutoClipCapture.ps1 so a fresh
# config looks the same whichever of the two scripts creates it first.
function Get-DefaultSqlSearchMode {
    [pscustomobject]@{
        Id                  = "sql-search"
        Name                = "SQL Search"
        Enabled             = $true
        Hotkey              = [pscustomobject]@{ Modifiers = 5; Key = 0xBE; Display = "Alt+>"; RequireRightModifier = $false }  # Alt+Shift+Period ('>')
        UseFocusedWindow    = $true
        ActionKeyToken      = "{F5}"
        ActionKeyDisplay    = "F5"
        FoundText           = "EXEC SQL"
        FoundOverlayText    = "SQL FOUND"
        NotFoundText        = "No CHARS 'sql' found"
        TerminalText        = "*Bottom of data reached*"
        NotFoundOverlayText = "NO SQL FOUND"
        MaxIterations       = 500
    }
}

function Get-DefaultConfig {
    [pscustomobject]@{
        LogFile                 = "CapturedOutput.txt"
        CopyDelayMs             = 150
        AfterActionKeyDelayMs   = 150
        TimerTickMs             = 50
        SkipRowsStart           = 0
        SkipRowsEnd             = 0
        ActionKeyDisplay        = "F8"
        ActionKeyToken          = "{F8}"
        DupDetectEnabled        = $true
        DupDetectThreshold      = 0.995
        ToggleHotkey            = [pscustomobject]@{ Modifiers = 3; Key = 0x43; Display = "Ctrl+Alt+C"; RequireRightModifier = $false }
        ExitHotkey              = [pscustomobject]@{ Modifiers = 3; Key = 0x58; Display = "Ctrl+Alt+X"; RequireRightModifier = $false }
        F3Hotkey                = [pscustomobject]@{ Modifiers = 5; Key = 0xBC; Display = "Alt+<"; RequireRightModifier = $false }  # Alt+Shift+Comma ('<')
        ResultOverlayDurationMs = 4000
        Modes                   = @( Get-DefaultSqlSearchMode )
    }
}

# Converts a captured key + modifier bitmask into a SendKeys-compatible
# token, e.g. F8 -> "{F8}", Ctrl+F8 -> "^({F8})", 'a' -> "a".
function Convert-KeyToSendKeysToken {
    param(
        [Parameter(Mandatory)][int]$Vk,
        [Parameter(Mandatory)][int]$Mods
    )

    $key = [System.Windows.Forms.Keys]$Vk
    $name = $key.ToString()

    $specialMap = @{
        'Back'        = '{BACKSPACE}'
        'Tab'         = '{TAB}'
        'Enter'       = '{ENTER}'
        'Return'      = '{ENTER}'
        'Escape'      = '{ESC}'
        'Space'       = ' '
        'PageUp'      = '{PGUP}'
        'Prior'       = '{PGUP}'
        'PageDown'    = '{PGDN}'
        'Next'        = '{PGDN}'
        'End'         = '{END}'
        'Home'        = '{HOME}'
        'Left'        = '{LEFT}'
        'Up'          = '{UP}'
        'Right'       = '{RIGHT}'
        'Down'        = '{DOWN}'
        'Insert'      = '{INSERT}'
        'Delete'      = '{DELETE}'
        'Help'        = '{HELP}'
        'NumLock'     = '{NUMLOCK}'
        'Scroll'      = '{SCROLLLOCK}'
        'CapsLock'    = '{CAPSLOCK}'
        'PrintScreen' = '{PRTSC}'
        'Pause'       = '{BREAK}'
        'Add'         = '{ADD}'
        'Subtract'    = '{SUBTRACT}'
        'Multiply'    = '{MULTIPLY}'
        'Divide'      = '{DIVIDE}'
        'Decimal'     = '{DECIMAL}'
    }

    if ($name -match '^F([0-9]|1[0-9]|2[0-4])$') {
        $baseToken = "{$($name.ToUpper())}"
    }
    elseif ($name -match '^NumPad(\d)$') {
        $baseToken = "{NUMPAD$($Matches[1])}"
    }
    elseif ($specialMap.ContainsKey($name)) {
        $baseToken = $specialMap[$name]
    }
    elseif ($name -match '^D(\d)$') {
        $baseToken = $Matches[1]
    }
    elseif ($name.Length -eq 1) {
        $ch = $name.ToLower()
        if ('+^%~(){}[]' -like "*$ch*") { $baseToken = "{$ch}" } else { $baseToken = $ch }
    }
    else {
        # Best-effort fallback for keys without an explicit mapping above
        $baseToken = "{$($name.ToUpper())}"
    }

    $prefix = ""
    if ($Mods -band 0x0002) { $prefix += '^' }  # Ctrl
    if ($Mods -band 0x0001) { $prefix += '%' }  # Alt
    if ($Mods -band 0x0004) { $prefix += '+' }  # Shift

    if ($prefix -eq "") { return $baseToken }
    return "$prefix($baseToken)"
}

# Turns a captured System.Windows.Forms.KeyEventArgs into the
# {Mods,Vk,Display} triple used throughout, honoring whether a
# modifier is required (hotkeys) or not (action keys).
function Get-KeyCaptureResult {
    param(
        [Parameter(Mandatory)]$EventArgs,
        [Parameter(Mandatory)][bool]$RequireModifier
    )

    $modifierKeys = @(
        [System.Windows.Forms.Keys]::ControlKey,
        [System.Windows.Forms.Keys]::Menu,
        [System.Windows.Forms.Keys]::ShiftKey,
        [System.Windows.Forms.Keys]::LWin,
        [System.Windows.Forms.Keys]::RWin
    )
    if ($modifierKeys -contains $EventArgs.KeyCode) { return $null }  # wait for the real key

    if ($RequireModifier -and -not ($EventArgs.Control -or $EventArgs.Alt -or $EventArgs.Shift)) {
        [System.Windows.Forms.MessageBox]::Show(
            "A hotkey needs at least one modifier (Ctrl, Alt, and/or Shift). Try again.",
            "Modifier required", 'OK', 'Warning') | Out-Null
        return [pscustomobject]@{ Retry = $true }
    }

    $mods = 0
    $parts = @()
    if ($EventArgs.Control) { $mods = $mods -bor 0x0002; $parts += 'Ctrl' }
    if ($EventArgs.Alt)     { $mods = $mods -bor 0x0001; $parts += 'Alt' }
    if ($EventArgs.Shift)   { $mods = $mods -bor 0x0004; $parts += 'Shift' }

    $vk = [int]$EventArgs.KeyCode
    $parts += $EventArgs.KeyCode.ToString()
    $display = [string]::Join('+', $parts)

    return [pscustomobject]@{ Retry = $false; Mods = $mods; Vk = $vk; Display = $display }
}

# ------------------------- Load existing config -------------------------
if (Test-Path $ConfigPath) {
    try {
        $existing = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        $existing = Get-DefaultConfig
    }
} else {
    $existing = Get-DefaultConfig
}

$defaultsForFallback = Get-DefaultConfig
if (-not ($existing.PSObject.Properties.Name -contains 'ActionKeyToken')) {
    $existing | Add-Member -NotePropertyName ActionKeyToken   -NotePropertyValue $defaultsForFallback.ActionKeyToken
    $existing | Add-Member -NotePropertyName ActionKeyDisplay -NotePropertyValue $defaultsForFallback.ActionKeyDisplay
}
if (-not ($existing.PSObject.Properties.Name -contains 'AfterActionKeyDelayMs')) {
    $fallbackDelay = if ($existing.PSObject.Properties.Name -contains 'AfterF8DelayMs') { $existing.AfterF8DelayMs } else { $defaultsForFallback.AfterActionKeyDelayMs }
    $existing | Add-Member -NotePropertyName AfterActionKeyDelayMs -NotePropertyValue $fallbackDelay
}
if (-not ($existing.PSObject.Properties.Name -contains 'SkipRowsStart')) {
    $existing | Add-Member -NotePropertyName SkipRowsStart -NotePropertyValue $defaultsForFallback.SkipRowsStart
}
if (-not ($existing.PSObject.Properties.Name -contains 'SkipRowsEnd')) {
    $existing | Add-Member -NotePropertyName SkipRowsEnd -NotePropertyValue $defaultsForFallback.SkipRowsEnd
}
if (-not ($existing.PSObject.Properties.Name -contains 'DupDetectEnabled')) {
    $existing | Add-Member -NotePropertyName DupDetectEnabled -NotePropertyValue $defaultsForFallback.DupDetectEnabled
}
if (-not ($existing.PSObject.Properties.Name -contains 'DupDetectThreshold')) {
    $existing | Add-Member -NotePropertyName DupDetectThreshold -NotePropertyValue $defaultsForFallback.DupDetectThreshold
}
if (-not ($existing.PSObject.Properties.Name -contains 'ResultOverlayDurationMs')) {
    $existing | Add-Member -NotePropertyName ResultOverlayDurationMs -NotePropertyValue $defaultsForFallback.ResultOverlayDurationMs
}
if (-not ($existing.PSObject.Properties.Name -contains 'Modes') -or $null -eq $existing.Modes) {
    $existing | Add-Member -NotePropertyName Modes -NotePropertyValue @( Get-DefaultSqlSearchMode ) -Force
}
if (-not ($existing.PSObject.Properties.Name -contains 'F3Hotkey') -or $null -eq $existing.F3Hotkey) {
    $existing | Add-Member -NotePropertyName F3Hotkey -NotePropertyValue $defaultsForFallback.F3Hotkey -Force
}
foreach ($hk in @($existing.ToggleHotkey, $existing.ExitHotkey, $existing.F3Hotkey)) {
    if (-not ($hk.PSObject.Properties.Name -contains 'RequireRightModifier')) {
        $hk | Add-Member -NotePropertyName RequireRightModifier -NotePropertyValue $false -Force
    }
}
foreach ($m in @($existing.Modes)) {
    if (-not ($m.PSObject.Properties.Name -contains 'UseFocusedWindow')) {
        $m | Add-Member -NotePropertyName UseFocusedWindow -NotePropertyValue $false -Force
    }
    if ($null -ne $m.Hotkey -and -not ($m.Hotkey.PSObject.Properties.Name -contains 'RequireRightModifier')) {
        $m.Hotkey | Add-Member -NotePropertyName RequireRightModifier -NotePropertyValue $false -Force
    }
}

# Working, mutable list of Modes. No longer edited from this GUI -
# kept as-is (aside from the SQL Search hotkey below) and written back
# unchanged on Save, so AutoClipCapture.ps1 keeps working exactly as
# before.
$script:ModesList = New-Object System.Collections.ArrayList
foreach ($m in @($existing.Modes)) { [void]$script:ModesList.Add($m) }

# The one Mode whose hotkey this GUI still exposes.
$script:SqlSearchMode = $script:ModesList | Where-Object { $_.Id -eq 'sql-search' } | Select-Object -First 1
if ($null -eq $script:SqlSearchMode) {
    $script:SqlSearchMode = Get-DefaultSqlSearchMode
    [void]$script:ModesList.Add($script:SqlSearchMode)
}

# Working copies of captured key/hotkey state
$script:ToggleMods           = [int]$existing.ToggleHotkey.Modifiers
$script:ToggleKey            = [int]$existing.ToggleHotkey.Key
$script:ExitMods             = [int]$existing.ExitHotkey.Modifiers
$script:ExitKey              = [int]$existing.ExitHotkey.Key
$script:F3Mods               = [int]$existing.F3Hotkey.Modifiers
$script:F3Key                = [int]$existing.F3Hotkey.Key
$script:SqlSearchMods        = [int]$script:SqlSearchMode.Hotkey.Modifiers
$script:SqlSearchKey         = [int]$script:SqlSearchMode.Hotkey.Key
$script:ActionToken          = [string]$existing.ActionKeyToken
$script:Capturing            = $null   # $null, 'Toggle', 'Exit', 'SqlSearch', 'F3', or 'Action'
$script:PreCaptureText       = ""

# ------------------------- Build the main form -----------------------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "AutoClipCapture - Configuration"
$form.ClientSize      = New-Object System.Drawing.Size(470, 515)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.KeyPreview      = $true

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size = New-Object System.Drawing.Size(450, 445)

$tabGeneral = New-Object System.Windows.Forms.TabPage; $tabGeneral.Text = "General"
$tabTiming  = New-Object System.Windows.Forms.TabPage; $tabTiming.Text  = "Timing && Rows"
$tabDup     = New-Object System.Windows.Forms.TabPage; $tabDup.Text     = "Duplicates"
$tabKeys    = New-Object System.Windows.Forms.TabPage; $tabKeys.Text    = "Hotkeys"
$tabs.Controls.AddRange(@($tabGeneral, $tabTiming, $tabDup, $tabKeys))

# ===================== General tab =====================
$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = "Default log location (you'll be asked for a filename each time you start the Toggle relay)"
$grpLog.Location = New-Object System.Drawing.Point(10, 10)
$grpLog.Size = New-Object System.Drawing.Size(415, 60)

$txtLogFile = New-Object System.Windows.Forms.TextBox
$txtLogFile.Location = New-Object System.Drawing.Point(15, 25)
$txtLogFile.Size = New-Object System.Drawing.Size(290, 22)
$txtLogFile.Text = $existing.LogFile

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(315, 23)
$btnBrowse.Size = New-Object System.Drawing.Size(85, 25)
$btnBrowse.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $sfd.Title = "Choose log file location"
    $sfd.OverwritePrompt = $false
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtLogFile.Text = $sfd.FileName
    }
})
$grpLog.Controls.AddRange(@($txtLogFile, $btnBrowse))

$grpAction = New-Object System.Windows.Forms.GroupBox
$grpAction.Text = "Toggle relay's action key (pressed after each Ctrl+C)"
$grpAction.Location = New-Object System.Drawing.Point(10, 80)
$grpAction.Size = New-Object System.Drawing.Size(415, 95)

$lblAction = New-Object System.Windows.Forms.Label
$lblAction.Text = "Key to press:"
$lblAction.Location = New-Object System.Drawing.Point(15, 28)
$lblAction.Size = New-Object System.Drawing.Size(140, 20)

$txtAction = New-Object System.Windows.Forms.TextBox
$txtAction.Location = New-Object System.Drawing.Point(160, 25)
$txtAction.Size = New-Object System.Drawing.Size(140, 22)
$txtAction.ReadOnly = $true
$txtAction.Text = $existing.ActionKeyDisplay

$btnSetAction = New-Object System.Windows.Forms.Button
$btnSetAction.Text = "Set..."
$btnSetAction.Location = New-Object System.Drawing.Point(310, 23)
$btnSetAction.Size = New-Object System.Drawing.Size(85, 25)
$btnSetAction.Add_Click({
    $script:Capturing = 'Action'
    $script:PreCaptureText = $txtAction.Text
    $txtAction.Text = "Press a key... (Esc to cancel)"
    $txtAction.BackColor = 'LightYellow'
})

$lblActionDelay = New-Object System.Windows.Forms.Label
$lblActionDelay.Text = "Delay after this key, before next Ctrl+C (ms):"
$lblActionDelay.Location = New-Object System.Drawing.Point(15, 63)
$lblActionDelay.Size = New-Object System.Drawing.Size(280, 20)

$numAfterActionDelay = New-Object System.Windows.Forms.NumericUpDown
$numAfterActionDelay.Location = New-Object System.Drawing.Point(310, 60)
$numAfterActionDelay.Size = New-Object System.Drawing.Size(80, 22)
$numAfterActionDelay.Minimum = 0
$numAfterActionDelay.Maximum = 10000
$numAfterActionDelay.Increment = 10
$numAfterActionDelay.Value = [int]$existing.AfterActionKeyDelayMs

$grpAction.Controls.AddRange(@($lblAction, $txtAction, $btnSetAction, $lblActionDelay, $numAfterActionDelay))

$lblGeneralHint = New-Object System.Windows.Forms.Label
$lblGeneralHint.Text = "This action key is only used by the Toggle relay. Each Mode (see the Modes tab) has its own separate action key."
$lblGeneralHint.Location = New-Object System.Drawing.Point(10, 182)
$lblGeneralHint.Size = New-Object System.Drawing.Size(415, 30)
$lblGeneralHint.ForeColor = 'Gray'
$lblGeneralHint.Font = New-Object System.Drawing.Font($lblGeneralHint.Font.FontFamily, 7.5)

$tabGeneral.Controls.AddRange(@($grpLog, $grpAction, $lblGeneralHint))

# ===================== Timing & Rows tab =====================
$grpTiming = New-Object System.Windows.Forms.GroupBox
$grpTiming.Text = "Timing (milliseconds)"
$grpTiming.Location = New-Object System.Drawing.Point(10, 10)
$grpTiming.Size = New-Object System.Drawing.Size(415, 85)

$lblCopy = New-Object System.Windows.Forms.Label
$lblCopy.Text = "Delay after Ctrl+C, before reading clipboard:"
$lblCopy.Location = New-Object System.Drawing.Point(15, 28)
$lblCopy.Size = New-Object System.Drawing.Size(280, 20)

$numCopyDelay = New-Object System.Windows.Forms.NumericUpDown
$numCopyDelay.Location = New-Object System.Drawing.Point(310, 25)
$numCopyDelay.Size = New-Object System.Drawing.Size(80, 22)
$numCopyDelay.Minimum = 0
$numCopyDelay.Maximum = 10000
$numCopyDelay.Increment = 10
$numCopyDelay.Value = [int]$existing.CopyDelayMs

$lblTick = New-Object System.Windows.Forms.Label
$lblTick.Text = "Internal poll interval (advanced):"
$lblTick.Location = New-Object System.Drawing.Point(15, 55)
$lblTick.Size = New-Object System.Drawing.Size(280, 20)

$numTimerTick = New-Object System.Windows.Forms.NumericUpDown
$numTimerTick.Location = New-Object System.Drawing.Point(310, 52)
$numTimerTick.Size = New-Object System.Drawing.Size(80, 22)
$numTimerTick.Minimum = 10
$numTimerTick.Maximum = 1000
$numTimerTick.Increment = 10
$numTimerTick.Value = [int]$existing.TimerTickMs

$grpTiming.Controls.AddRange(@($lblCopy, $numCopyDelay, $lblTick, $numTimerTick))

$grpRows = New-Object System.Windows.Forms.GroupBox
$grpRows.Text = "Row filtering (skip rows in each captured chunk before saving - Toggle relay only)"
$grpRows.Location = New-Object System.Drawing.Point(10, 105)
$grpRows.Size = New-Object System.Drawing.Size(415, 90)

$lblSkipStart = New-Object System.Windows.Forms.Label
$lblSkipStart.Text = "Skip first N rows:"
$lblSkipStart.Location = New-Object System.Drawing.Point(15, 28)
$lblSkipStart.Size = New-Object System.Drawing.Size(280, 20)

$numSkipStart = New-Object System.Windows.Forms.NumericUpDown
$numSkipStart.Location = New-Object System.Drawing.Point(310, 25)
$numSkipStart.Size = New-Object System.Drawing.Size(80, 22)
$numSkipStart.Minimum = 0
$numSkipStart.Maximum = 1000
$numSkipStart.Increment = 1
$numSkipStart.Value = [int]$existing.SkipRowsStart

$lblSkipEnd = New-Object System.Windows.Forms.Label
$lblSkipEnd.Text = "Skip last N rows:"
$lblSkipEnd.Location = New-Object System.Drawing.Point(15, 58)
$lblSkipEnd.Size = New-Object System.Drawing.Size(280, 20)

$numSkipEnd = New-Object System.Windows.Forms.NumericUpDown
$numSkipEnd.Location = New-Object System.Drawing.Point(310, 55)
$numSkipEnd.Size = New-Object System.Drawing.Size(80, 22)
$numSkipEnd.Minimum = 0
$numSkipEnd.Maximum = 1000
$numSkipEnd.Increment = 1
$numSkipEnd.Value = [int]$existing.SkipRowsEnd

$grpRows.Controls.AddRange(@($lblSkipStart, $numSkipStart, $lblSkipEnd, $numSkipEnd))

$grpOverlay = New-Object System.Windows.Forms.GroupBox
$grpOverlay.Text = "SQL Search result banner"
$grpOverlay.Location = New-Object System.Drawing.Point(10, 200)
$grpOverlay.Size = New-Object System.Drawing.Size(415, 55)

$lblOverlayDur = New-Object System.Windows.Forms.Label
$lblOverlayDur.Text = "Show the full-screen found/not-found banner for (ms, 0 = until next action):"
$lblOverlayDur.Location = New-Object System.Drawing.Point(15, 25)
$lblOverlayDur.Size = New-Object System.Drawing.Size(310, 20)

$numOverlayDur = New-Object System.Windows.Forms.NumericUpDown
$numOverlayDur.Location = New-Object System.Drawing.Point(330, 22)
$numOverlayDur.Size = New-Object System.Drawing.Size(70, 22)
$numOverlayDur.Minimum = 0
$numOverlayDur.Maximum = 60000
$numOverlayDur.Increment = 500
$numOverlayDur.Value = [Math]::Min([Math]::Max([int]$existing.ResultOverlayDurationMs, 0), 60000)

$grpOverlay.Controls.AddRange(@($lblOverlayDur, $numOverlayDur))

$tabTiming.Controls.AddRange(@($grpTiming, $grpRows, $grpOverlay))

# ===================== Duplicates tab =====================
$grpDup = New-Object System.Windows.Forms.GroupBox
$grpDup.Text = "Duplicate-capture detection (Toggle relay only)"
$grpDup.Location = New-Object System.Drawing.Point(10, 10)
$grpDup.Size = New-Object System.Drawing.Size(415, 80)

$chkDupDetect = New-Object System.Windows.Forms.CheckBox
$chkDupDetect.Text = "Pause and ask when back-to-back captures are nearly identical"
$chkDupDetect.Location = New-Object System.Drawing.Point(15, 25)
$chkDupDetect.Size = New-Object System.Drawing.Size(390, 20)
$chkDupDetect.Checked = [bool]$existing.DupDetectEnabled

$lblDupThreshold = New-Object System.Windows.Forms.Label
$lblDupThreshold.Text = "Similarity threshold to trigger the pause (%):"
$lblDupThreshold.Location = New-Object System.Drawing.Point(15, 53)
$lblDupThreshold.Size = New-Object System.Drawing.Size(280, 20)

$numDupThreshold = New-Object System.Windows.Forms.NumericUpDown
$numDupThreshold.Location = New-Object System.Drawing.Point(310, 50)
$numDupThreshold.Size = New-Object System.Drawing.Size(80, 22)
$numDupThreshold.DecimalPlaces = 2
$numDupThreshold.Minimum = 50
$numDupThreshold.Maximum = 100
$numDupThreshold.Increment = 0.1
$rawThreshold = [double]$existing.DupDetectThreshold
if ($rawThreshold -le 1) { $rawThreshold = $rawThreshold * 100 }
$numDupThreshold.Value = [Math]::Round([Math]::Min([Math]::Max($rawThreshold, 50), 100), 2)

$lblDupThreshold.Enabled = $chkDupDetect.Checked
$numDupThreshold.Enabled = $chkDupDetect.Checked
$chkDupDetect.Add_CheckedChanged({
    $lblDupThreshold.Enabled = $chkDupDetect.Checked
    $numDupThreshold.Enabled = $chkDupDetect.Checked
})

$grpDup.Controls.AddRange(@($chkDupDetect, $lblDupThreshold, $numDupThreshold))
$tabDup.Controls.Add($grpDup)

# ===================== Hotkeys tab =====================
$grpKeys = New-Object System.Windows.Forms.GroupBox
$grpKeys.Text = "Global hotkeys (need at least one modifier)"
$grpKeys.Location = New-Object System.Drawing.Point(10, 10)
$grpKeys.Size = New-Object System.Drawing.Size(415, 200)

$lblToggle = New-Object System.Windows.Forms.Label
$lblToggle.Text = "Start / stop Toggle relay:"
$lblToggle.Location = New-Object System.Drawing.Point(15, 25)
$lblToggle.Size = New-Object System.Drawing.Size(150, 20)

$txtToggle = New-Object System.Windows.Forms.TextBox
$txtToggle.Location = New-Object System.Drawing.Point(170, 22)
$txtToggle.Size = New-Object System.Drawing.Size(140, 22)
$txtToggle.ReadOnly = $true
$txtToggle.Text = $existing.ToggleHotkey.Display

$btnSetToggle = New-Object System.Windows.Forms.Button
$btnSetToggle.Text = "Set..."
$btnSetToggle.Location = New-Object System.Drawing.Point(325, 20)
$btnSetToggle.Size = New-Object System.Drawing.Size(85, 25)
$btnSetToggle.Add_Click({
    $script:Capturing = 'Toggle'
    $script:PreCaptureText = $txtToggle.Text
    $txtToggle.Text = "Press keys... (Esc to cancel)"
    $txtToggle.BackColor = 'LightYellow'
})

$lblExit = New-Object System.Windows.Forms.Label
$lblExit.Text = "Quit AutoClipCapture:"
$lblExit.Location = New-Object System.Drawing.Point(15, 55)
$lblExit.Size = New-Object System.Drawing.Size(150, 20)

$txtExit = New-Object System.Windows.Forms.TextBox
$txtExit.Location = New-Object System.Drawing.Point(170, 52)
$txtExit.Size = New-Object System.Drawing.Size(140, 22)
$txtExit.ReadOnly = $true
$txtExit.Text = $existing.ExitHotkey.Display

$btnSetExit = New-Object System.Windows.Forms.Button
$btnSetExit.Text = "Set..."
$btnSetExit.Location = New-Object System.Drawing.Point(325, 50)
$btnSetExit.Size = New-Object System.Drawing.Size(85, 25)
$btnSetExit.Add_Click({
    $script:Capturing = 'Exit'
    $script:PreCaptureText = $txtExit.Text
    $txtExit.Text = "Press keys... (Esc to cancel)"
    $txtExit.BackColor = 'LightYellow'
})

$lblSqlSearch = New-Object System.Windows.Forms.Label
$lblSqlSearch.Text = "SQL Search (repeats F5, watches clipboard):"
$lblSqlSearch.Location = New-Object System.Drawing.Point(15, 85)
$lblSqlSearch.Size = New-Object System.Drawing.Size(230, 20)

$txtSqlSearch = New-Object System.Windows.Forms.TextBox
$txtSqlSearch.Location = New-Object System.Drawing.Point(170, 82)
$txtSqlSearch.Size = New-Object System.Drawing.Size(140, 22)
$txtSqlSearch.ReadOnly = $true
$txtSqlSearch.Text = $script:SqlSearchMode.Hotkey.Display

$btnSetSqlSearch = New-Object System.Windows.Forms.Button
$btnSetSqlSearch.Text = "Set..."
$btnSetSqlSearch.Location = New-Object System.Drawing.Point(325, 80)
$btnSetSqlSearch.Size = New-Object System.Drawing.Size(85, 25)
$btnSetSqlSearch.Add_Click({
    $script:Capturing = 'SqlSearch'
    $script:PreCaptureText = $txtSqlSearch.Text
    $txtSqlSearch.Text = "Press keys... (Esc to cancel)"
    $txtSqlSearch.BackColor = 'LightYellow'
})

$chkSqlSearchRight = New-Object System.Windows.Forms.CheckBox
$chkSqlSearchRight.Text = "Require RIGHT-hand Ctrl/Alt/Shift"
$chkSqlSearchRight.Location = New-Object System.Drawing.Point(170, 108)
$chkSqlSearchRight.Size = New-Object System.Drawing.Size(240, 20)
$chkSqlSearchRight.Checked = [bool]$script:SqlSearchMode.Hotkey.RequireRightModifier

$lblF3 = New-Object System.Windows.Forms.Label
$lblF3.Text = "F3 (single press, focused window):"
$lblF3.Location = New-Object System.Drawing.Point(15, 140)
$lblF3.Size = New-Object System.Drawing.Size(230, 20)

$txtF3 = New-Object System.Windows.Forms.TextBox
$txtF3.Location = New-Object System.Drawing.Point(170, 137)
$txtF3.Size = New-Object System.Drawing.Size(140, 22)
$txtF3.ReadOnly = $true
$txtF3.Text = $existing.F3Hotkey.Display

$btnSetF3 = New-Object System.Windows.Forms.Button
$btnSetF3.Text = "Set..."
$btnSetF3.Location = New-Object System.Drawing.Point(325, 135)
$btnSetF3.Size = New-Object System.Drawing.Size(85, 25)
$btnSetF3.Add_Click({
    $script:Capturing = 'F3'
    $script:PreCaptureText = $txtF3.Text
    $txtF3.Text = "Press keys... (Esc to cancel)"
    $txtF3.BackColor = 'LightYellow'
})

$chkF3Right = New-Object System.Windows.Forms.CheckBox
$chkF3Right.Text = "Require RIGHT-hand Ctrl/Alt/Shift"
$chkF3Right.Location = New-Object System.Drawing.Point(170, 163)
$chkF3Right.Size = New-Object System.Drawing.Size(240, 20)
$chkF3Right.Checked = [bool]$existing.F3Hotkey.RequireRightModifier

$grpKeys.Controls.AddRange(@(
    $lblToggle, $txtToggle, $btnSetToggle,
    $lblExit, $txtExit, $btnSetExit,
    $lblSqlSearch, $txtSqlSearch, $btnSetSqlSearch, $chkSqlSearchRight,
    $lblF3, $txtF3, $btnSetF3, $chkF3Right
))

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Hold Ctrl/Alt/Shift (any combination) and press a key. ""Right-hand"" hotkeys only fire when that physical side of the modifier is held."
$lblHint.Location = New-Object System.Drawing.Point(10, 215)
$lblHint.Size = New-Object System.Drawing.Size(415, 30)
$lblHint.Font = New-Object System.Drawing.Font($lblHint.Font.FontFamily, 7.5)
$lblHint.ForeColor = 'Gray'

$tabKeys.Controls.AddRange(@($grpKeys, $lblHint))


# --- Bottom buttons ---
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save"
$btnSave.Location = New-Object System.Drawing.Point(185, 465)
$btnSave.Size = New-Object System.Drawing.Size(100, 32)

$btnDefaults = New-Object System.Windows.Forms.Button
$btnDefaults.Text = "Reset to Defaults"
$btnDefaults.Location = New-Object System.Drawing.Point(10, 465)
$btnDefaults.Size = New-Object System.Drawing.Size(130, 32)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(310, 465)
$btnCancel.Size = New-Object System.Drawing.Size(100, 32)

$btnDefaults.Add_Click({
    $defaults = Get-DefaultConfig
    $txtLogFile.Text           = $defaults.LogFile
    $txtAction.Text            = $defaults.ActionKeyDisplay
    $numAfterActionDelay.Value = $defaults.AfterActionKeyDelayMs
    $numCopyDelay.Value        = $defaults.CopyDelayMs
    $numTimerTick.Value        = $defaults.TimerTickMs
    $numSkipStart.Value        = $defaults.SkipRowsStart
    $numSkipEnd.Value          = $defaults.SkipRowsEnd
    $chkDupDetect.Checked      = $defaults.DupDetectEnabled
    $numDupThreshold.Value     = [Math]::Round($defaults.DupDetectThreshold * 100, 2)
    $txtToggle.Text            = $defaults.ToggleHotkey.Display
    $txtExit.Text              = $defaults.ExitHotkey.Display
    $script:ToggleMods         = [int]$defaults.ToggleHotkey.Modifiers
    $script:ToggleKey          = [int]$defaults.ToggleHotkey.Key
    $script:ExitMods           = [int]$defaults.ExitHotkey.Modifiers
    $script:ExitKey            = [int]$defaults.ExitHotkey.Key
    $script:ActionToken        = $defaults.ActionKeyToken
    $numOverlayDur.Value       = $defaults.ResultOverlayDurationMs

    $defaultSqlSearch          = @($defaults.Modes) | Where-Object { $_.Id -eq 'sql-search' } | Select-Object -First 1
    $txtSqlSearch.Text         = $defaultSqlSearch.Hotkey.Display
    $chkSqlSearchRight.Checked = [bool]$defaultSqlSearch.Hotkey.RequireRightModifier
    $script:SqlSearchMods      = [int]$defaultSqlSearch.Hotkey.Modifiers
    $script:SqlSearchKey       = [int]$defaultSqlSearch.Hotkey.Key
    $script:SqlSearchMode.Hotkey = [pscustomobject]@{ Modifiers = $script:SqlSearchMods; Key = $script:SqlSearchKey; Display = $txtSqlSearch.Text; RequireRightModifier = $chkSqlSearchRight.Checked }
    $script:SqlSearchMode.UseFocusedWindow = [bool]$defaultSqlSearch.UseFocusedWindow

    $txtF3.Text                = $defaults.F3Hotkey.Display
    $chkF3Right.Checked        = [bool]$defaults.F3Hotkey.RequireRightModifier
    $script:F3Mods             = [int]$defaults.F3Hotkey.Modifiers
    $script:F3Key              = [int]$defaults.F3Hotkey.Key
})

$btnCancel.Add_Click({ $form.Close() })

$btnSave.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtLogFile.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please specify a log file path.", "Missing Log File", 'OK', 'Warning') | Out-Null
        return
    }

    # Collect every hotkey (Toggle, Exit, SQL Search, F3) and make sure
    # none of them collide.
    $allHotkeys = New-Object System.Collections.ArrayList
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Toggle relay"; Mods = $script:ToggleMods;    Key = $script:ToggleKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Exit";         Mods = $script:ExitMods;      Key = $script:ExitKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "SQL Search";   Mods = $script:SqlSearchMods; Key = $script:SqlSearchKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "F3";           Mods = $script:F3Mods;        Key = $script:F3Key })
    foreach ($m in $script:ModesList) {
        if ($m.Id -eq 'sql-search') { continue }   # already covered above with its live edited value
        if ($m.Enabled) {
            [void]$allHotkeys.Add([pscustomobject]@{ Name = "Mode '$($m.Name)'"; Mods = [int]$m.Hotkey.Modifiers; Key = [int]$m.Hotkey.Key })
        }
    }
    for ($i = 0; $i -lt $allHotkeys.Count; $i++) {
        for ($j = $i + 1; $j -lt $allHotkeys.Count; $j++) {
            if ($allHotkeys[$i].Mods -eq $allHotkeys[$j].Mods -and $allHotkeys[$i].Key -eq $allHotkeys[$j].Key) {
                [System.Windows.Forms.MessageBox]::Show(
                    "$($allHotkeys[$i].Name) and $($allHotkeys[$j].Name) are both set to the same hotkey. Please give each one a different combination.",
                    "Duplicate Hotkey", 'OK', 'Warning') | Out-Null
                return
            }
        }
    }

    # Apply the (possibly edited) SQL Search hotkey to its mode entry
    # before writing Modes back out - everything else about that mode
    # (action key, phrases, etc.) is preserved untouched.
    $script:SqlSearchMode.Hotkey = [pscustomobject]@{
        Modifiers             = $script:SqlSearchMods
        Key                   = $script:SqlSearchKey
        Display               = $txtSqlSearch.Text
        RequireRightModifier  = [bool]$chkSqlSearchRight.Checked
    }

    $modesForSave = @()
    foreach ($m in $script:ModesList) {
        $modesForSave += [pscustomobject]@{
            Id                  = $m.Id
            Name                = $m.Name
            Enabled             = [bool]$m.Enabled
            Hotkey              = [pscustomobject]@{ Modifiers = [int]$m.Hotkey.Modifiers; Key = [int]$m.Hotkey.Key; Display = [string]$m.Hotkey.Display; RequireRightModifier = [bool]$m.Hotkey.RequireRightModifier }
            UseFocusedWindow    = [bool]$m.UseFocusedWindow
            ActionKeyToken      = [string]$m.ActionKeyToken
            ActionKeyDisplay    = [string]$m.ActionKeyDisplay
            FoundText           = [string]$m.FoundText
            FoundOverlayText    = [string]$m.FoundOverlayText
            NotFoundText        = [string]$m.NotFoundText
            TerminalText        = [string]$m.TerminalText
            NotFoundOverlayText = [string]$m.NotFoundOverlayText
            MaxIterations       = [int]$m.MaxIterations
        }
    }

    $newConfig = [pscustomobject]@{
        LogFile                 = $txtLogFile.Text
        CopyDelayMs              = [int]$numCopyDelay.Value
        AfterActionKeyDelayMs    = [int]$numAfterActionDelay.Value
        TimerTickMs              = [int]$numTimerTick.Value
        SkipRowsStart            = [int]$numSkipStart.Value
        SkipRowsEnd              = [int]$numSkipEnd.Value
        ActionKeyDisplay         = $txtAction.Text
        ActionKeyToken           = $script:ActionToken
        DupDetectEnabled         = [bool]$chkDupDetect.Checked
        DupDetectThreshold       = [double]($numDupThreshold.Value / 100)
        ToggleHotkey             = [pscustomobject]@{ Modifiers = $script:ToggleMods; Key = $script:ToggleKey; Display = $txtToggle.Text; RequireRightModifier = $false }
        ExitHotkey               = [pscustomobject]@{ Modifiers = $script:ExitMods;   Key = $script:ExitKey;   Display = $txtExit.Text;   RequireRightModifier = $false }
        F3Hotkey                 = [pscustomobject]@{ Modifiers = $script:F3Mods;     Key = $script:F3Key;     Display = $txtF3.Text;     RequireRightModifier = [bool]$chkF3Right.Checked }
        ResultOverlayDurationMs  = [int]$numOverlayDur.Value
        Modes                    = $modesForSave
    }

    $newConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show(
        "Configuration saved to:`n$ConfigPath`n`nRestart AutoClipCapture for the changes to take effect.",
        "Saved", 'OK', 'Information') | Out-Null
})

$form.Controls.AddRange(@($tabs, $btnSave, $btnDefaults, $btnCancel))

# ------------------------- Key-combo capture (main form: Toggle/Exit/SqlSearch/F3/Action) ---------------------------
$form.Add_KeyDown({
    param($sender, $e)

    if (-not $script:Capturing) { return }

    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        switch ($script:Capturing) {
            'Toggle'    { $txtToggle.Text    = $script:PreCaptureText; $txtToggle.BackColor    = 'Window' }
            'Exit'      { $txtExit.Text      = $script:PreCaptureText; $txtExit.BackColor      = 'Window' }
            'SqlSearch' { $txtSqlSearch.Text = $script:PreCaptureText; $txtSqlSearch.BackColor = 'Window' }
            'F3'        { $txtF3.Text        = $script:PreCaptureText; $txtF3.BackColor        = 'Window' }
            'Action'    { $txtAction.Text    = $script:PreCaptureText; $txtAction.BackColor    = 'Window' }
        }
        $script:Capturing = $null
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }

    $requireMod = ($script:Capturing -ne 'Action')
    $captured = Get-KeyCaptureResult -EventArgs $e -RequireModifier $requireMod
    if ($null -eq $captured) {
        $e.Handled = $true; $e.SuppressKeyPress = $true; return   # pure modifier press - keep waiting
    }
    if ($captured.Retry) {
        $e.Handled = $true; $e.SuppressKeyPress = $true; return   # needs a modifier - message already shown
    }

    switch ($script:Capturing) {
        'Toggle' {
            $script:ToggleMods = $captured.Mods
            $script:ToggleKey  = $captured.Vk
            $txtToggle.Text = $captured.Display
            $txtToggle.BackColor = 'Window'
        }
        'Exit' {
            $script:ExitMods = $captured.Mods
            $script:ExitKey  = $captured.Vk
            $txtExit.Text = $captured.Display
            $txtExit.BackColor = 'Window'
        }
        'SqlSearch' {
            $script:SqlSearchMods = $captured.Mods
            $script:SqlSearchKey  = $captured.Vk
            $txtSqlSearch.Text = $captured.Display
            $txtSqlSearch.BackColor = 'Window'
        }
        'F3' {
            $script:F3Mods = $captured.Mods
            $script:F3Key  = $captured.Vk
            $txtF3.Text = $captured.Display
            $txtF3.BackColor = 'Window'
        }
        'Action' {
            $script:ActionToken = Convert-KeyToSendKeysToken -Vk $captured.Vk -Mods $captured.Mods
            $txtAction.Text = $captured.Display
            $txtAction.BackColor = 'Window'
        }
    }

    $script:Capturing = $null
    $e.Handled = $true
    $e.SuppressKeyPress = $true
})

[System.Windows.Forms.Application]::Run($form)
