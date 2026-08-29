<#
=====================================================================
 AutoClipCaptureConfigGUI.ps1
=====================================================================
 GUI for editing AutoClipCaptureConfig.json - the settings file used
 by AutoClipCapture.ps1. Organized into tabs so it stays a manageable
 size no matter how many Modes you add:

   General           - default log location, the Toggle relay's
                        action key
   Timing & Rows      - copy/action delays, internal poll interval,
                        rows to skip at the start/end of each capture
   Duplicates         - duplicate-capture detection (pause & ask when
                        back-to-back captures come back almost
                        identical)
   Hotkeys            - the Toggle hotkey (start/stop the classic
                        capture-and-log relay) and the Exit hotkey
   Modes              - the result-banner duration, and the list of
                        scan Modes (each its own hotkey + action key +
                        the phrases it looks for). Add / Edit / Remove
                        modes here - no script editing required.

 The built-in "SQL Search" mode (Ctrl+Shift+1 by default) is a good
 example to copy when adding a new mode: repeatedly press an action
 key, copy the screen, and look for a phrase - showing a full-screen
 "found" or "not found" banner once it knows the answer.

 HOTKEYS (Toggle/Exit/every Mode's hotkey) are global shortcuts, so
 Windows requires at least one modifier (Ctrl/Alt/Shift) - a bare key
 like "F9" alone isn't accepted for those.

 ACTION KEYS (the Toggle relay's, and each Mode's) are different:
 they're just simulated as a keypress inside the target application,
 so they can be a single key with no modifier at all (e.g. plain F8),
 or a modified combo if the target app needs one (e.g. Ctrl+F8).

 Changes only take effect the next time AutoClipCapture.ps1 is started
 (or restarted) - it reads the config once at launch.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ConfigPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"

# The default "scan mode" bound to Ctrl+Shift+1 - see AutoClipCapture.ps1
# for the exact loop this describes. Kept identical to (and in sync
# with) the copy in AutoClipCapture.ps1 so a fresh config looks the
# same whichever of the two scripts creates it first.
function Get-DefaultSqlSearchMode {
    [pscustomobject]@{
        Id                  = "sql-search"
        Name                = "SQL Search"
        Enabled             = $true
        Hotkey              = [pscustomobject]@{ Modifiers = 6; Key = 0x31; Display = "Ctrl+Shift+1" }  # Ctrl+Shift+1
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
        ToggleHotkey            = [pscustomobject]@{ Modifiers = 3; Key = 0x43; Display = "Ctrl+Alt+C" }
        ExitHotkey              = [pscustomobject]@{ Modifiers = 3; Key = 0x58; Display = "Ctrl+Alt+X" }
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

# Working copies of captured key/hotkey state (Toggle/Exit)
$script:ToggleMods = [int]$existing.ToggleHotkey.Modifiers
$script:ToggleKey  = [int]$existing.ToggleHotkey.Key
$script:ExitMods   = [int]$existing.ExitHotkey.Modifiers
$script:ExitKey    = [int]$existing.ExitHotkey.Key
$script:ActionToken = [string]$existing.ActionKeyToken
$script:Capturing  = $null   # $null, 'Toggle', 'Exit', or 'Action'
$script:PreCaptureText = ""

# Working, mutable list of Modes shown/edited on the Modes tab. Each
# entry is a plain pscustomobject with: Id, Name, Enabled, Hotkey
# {Modifiers,Key,Display}, ActionKeyToken, ActionKeyDisplay, FoundText,
# FoundOverlayText, NotFoundText, TerminalText, NotFoundOverlayText,
# MaxIterations.
$script:ModesList = New-Object System.Collections.ArrayList
foreach ($m in @($existing.Modes)) { [void]$script:ModesList.Add($m) }

# ============================= Mode editor dialog =============================
# Shown for both "Add..." and "Edit...". Returns the edited mode as a
# pscustomobject, or $null if the user cancelled.
function Show-ModeEditorDialog {
    param($ExistingMode)

    $isNew = ($null -eq $ExistingMode)
    if ($isNew) {
        $work = [pscustomobject]@{
            Id                  = [guid]::NewGuid().ToString()
            Name                = "New Mode"
            Enabled             = $true
            Hotkey              = [pscustomobject]@{ Modifiers = 0; Key = 0; Display = "" }
            ActionKeyToken      = "{F5}"
            ActionKeyDisplay    = "F5"
            FoundText           = ""
            FoundOverlayText    = ""
            NotFoundText        = ""
            TerminalText        = ""
            NotFoundOverlayText = ""
            MaxIterations       = 500
        }
    } else {
        # Work on a copy so Cancel doesn't mutate the original entry.
        $work = [pscustomobject]@{
            Id                  = $ExistingMode.Id
            Name                = $ExistingMode.Name
            Enabled             = [bool]$ExistingMode.Enabled
            Hotkey              = [pscustomobject]@{ Modifiers = [int]$ExistingMode.Hotkey.Modifiers; Key = [int]$ExistingMode.Hotkey.Key; Display = [string]$ExistingMode.Hotkey.Display }
            ActionKeyToken      = [string]$ExistingMode.ActionKeyToken
            ActionKeyDisplay    = [string]$ExistingMode.ActionKeyDisplay
            FoundText           = [string]$ExistingMode.FoundText
            FoundOverlayText    = [string]$ExistingMode.FoundOverlayText
            NotFoundText        = [string]$ExistingMode.NotFoundText
            TerminalText        = [string]$ExistingMode.TerminalText
            NotFoundOverlayText = [string]$ExistingMode.NotFoundOverlayText
            MaxIterations       = [int]$ExistingMode.MaxIterations
        }
    }

    $dlg                 = New-Object System.Windows.Forms.Form
    $dlg.Text            = if ($isNew) { "Add Mode" } else { "Edit Mode" }
    $dlg.ClientSize      = New-Object System.Drawing.Size(460, 560)
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.TopMost         = $true
    $dlg.KeyPreview      = $true

    # --- Name ---
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Mode name:"
    $lblName.Location = New-Object System.Drawing.Point(15, 15)
    $lblName.Size = New-Object System.Drawing.Size(120, 20)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(140, 12)
    $txtName.Size = New-Object System.Drawing.Size(305, 22)
    $txtName.Text = $work.Name

    # --- Hotkey / action key group ---
    $grpKeys = New-Object System.Windows.Forms.GroupBox
    $grpKeys.Text = "Keys"
    $grpKeys.Location = New-Object System.Drawing.Point(15, 45)
    $grpKeys.Size = New-Object System.Drawing.Size(430, 115)

    $lblHotkey = New-Object System.Windows.Forms.Label
    $lblHotkey.Text = "Starts/stops this mode:"
    $lblHotkey.Location = New-Object System.Drawing.Point(15, 25)
    $lblHotkey.Size = New-Object System.Drawing.Size(150, 20)

    $txtHotkey = New-Object System.Windows.Forms.TextBox
    $txtHotkey.Location = New-Object System.Drawing.Point(170, 22)
    $txtHotkey.Size = New-Object System.Drawing.Size(140, 22)
    $txtHotkey.ReadOnly = $true
    $txtHotkey.Text = $work.Hotkey.Display

    $btnSetHotkey = New-Object System.Windows.Forms.Button
    $btnSetHotkey.Text = "Set..."
    $btnSetHotkey.Location = New-Object System.Drawing.Point(325, 20)
    $btnSetHotkey.Size = New-Object System.Drawing.Size(85, 25)
    $btnSetHotkey.Add_Click({
        $script:MEdCapturing = 'Hotkey'
        $script:MEdPreCaptureText = $txtHotkey.Text
        $txtHotkey.Text = "Press keys... (Esc to cancel)"
        $txtHotkey.BackColor = 'LightYellow'
    })

    $lblActionKey = New-Object System.Windows.Forms.Label
    $lblActionKey.Text = "Action key (each cycle):"
    $lblActionKey.Location = New-Object System.Drawing.Point(15, 58)
    $lblActionKey.Size = New-Object System.Drawing.Size(150, 20)

    $txtActionKey = New-Object System.Windows.Forms.TextBox
    $txtActionKey.Location = New-Object System.Drawing.Point(170, 55)
    $txtActionKey.Size = New-Object System.Drawing.Size(140, 22)
    $txtActionKey.ReadOnly = $true
    $txtActionKey.Text = $work.ActionKeyDisplay

    $btnSetActionKey = New-Object System.Windows.Forms.Button
    $btnSetActionKey.Text = "Set..."
    $btnSetActionKey.Location = New-Object System.Drawing.Point(325, 53)
    $btnSetActionKey.Size = New-Object System.Drawing.Size(85, 25)
    $btnSetActionKey.Add_Click({
        $script:MEdCapturing = 'ModeAction'
        $script:MEdPreCaptureText = $txtActionKey.Text
        $txtActionKey.Text = "Press a key... (Esc to cancel)"
        $txtActionKey.BackColor = 'LightYellow'
    })

    $lblKeysHint = New-Object System.Windows.Forms.Label
    $lblKeysHint.Text = "Hotkey needs a modifier (Ctrl/Alt/Shift). Action key can be bare (e.g. F5)."
    $lblKeysHint.Location = New-Object System.Drawing.Point(15, 88)
    $lblKeysHint.Size = New-Object System.Drawing.Size(400, 18)
    $lblKeysHint.Font = New-Object System.Drawing.Font($lblKeysHint.Font.FontFamily, 7.5)
    $lblKeysHint.ForeColor = 'Gray'

    $grpKeys.Controls.AddRange(@($lblHotkey, $txtHotkey, $btnSetHotkey, $lblActionKey, $txtActionKey, $btnSetActionKey, $lblKeysHint))

    # --- Detection phrases group ---
    $grpPhrases = New-Object System.Windows.Forms.GroupBox
    $grpPhrases.Text = "What to look for in the copied text each cycle"
    $grpPhrases.Location = New-Object System.Drawing.Point(15, 168)
    $grpPhrases.Size = New-Object System.Drawing.Size(430, 260)

    function New-PhraseRow {
        param([string]$LabelText, [int]$Y, [string]$Value)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $LabelText
        $lbl.Location = New-Object System.Drawing.Point(15, $Y)
        $lbl.Size = New-Object System.Drawing.Size(400, 15)
        $lbl.Font = New-Object System.Drawing.Font($lbl.Font.FontFamily, 8)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(15, ($Y + 16))
        $txt.Size = New-Object System.Drawing.Size(400, 22)
        $txt.Text = $Value

        return [pscustomobject]@{ Label = $lbl; TextBox = $txt }
    }

    $rowFound        = New-PhraseRow -LabelText "Found phrase -> stop and show the FOUND message:"                    -Y 20  -Value $work.FoundText
    $rowFoundMsg     = New-PhraseRow -LabelText "FOUND message (shown full-screen):"                                  -Y 62  -Value $work.FoundOverlayText
    $rowNotFound     = New-PhraseRow -LabelText "Not-found phrase -> stop and show the NOT FOUND message:"             -Y 104 -Value $work.NotFoundText
    $rowTerminal     = New-PhraseRow -LabelText "Optional 2nd not-found phrase (also stops with NOT FOUND):"           -Y 146 -Value $work.TerminalText
    $rowNotFoundMsg  = New-PhraseRow -LabelText "NOT FOUND message (shown full-screen):"                              -Y 188 -Value $work.NotFoundOverlayText

    $grpPhrases.Controls.AddRange(@(
        $rowFound.Label, $rowFound.TextBox,
        $rowFoundMsg.Label, $rowFoundMsg.TextBox,
        $rowNotFound.Label, $rowNotFound.TextBox,
        $rowTerminal.Label, $rowTerminal.TextBox,
        $rowNotFoundMsg.Label, $rowNotFoundMsg.TextBox
    ))

    # --- Safety limit + Enabled ---
    $lblMaxIter = New-Object System.Windows.Forms.Label
    $lblMaxIter.Text = "Stop after this many scan attempts (safety limit):"
    $lblMaxIter.Location = New-Object System.Drawing.Point(15, 438)
    $lblMaxIter.Size = New-Object System.Drawing.Size(290, 20)

    $numMaxIter = New-Object System.Windows.Forms.NumericUpDown
    $numMaxIter.Location = New-Object System.Drawing.Point(325, 435)
    $numMaxIter.Size = New-Object System.Drawing.Size(85, 22)
    $numMaxIter.Minimum = 1
    $numMaxIter.Maximum = 100000
    $numMaxIter.Increment = 10
    $numMaxIter.Value = [Math]::Min([Math]::Max([int]$work.MaxIterations, 1), 100000)

    $chkEnabled = New-Object System.Windows.Forms.CheckBox
    $chkEnabled.Text = "Enabled (hotkey is active while AutoClipCapture is running)"
    $chkEnabled.Location = New-Object System.Drawing.Point(15, 465)
    $chkEnabled.Size = New-Object System.Drawing.Size(400, 20)
    $chkEnabled.Checked = [bool]$work.Enabled

    # --- OK / Cancel ---
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(255, 500)
    $btnOk.Size = New-Object System.Drawing.Size(90, 32)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(355, 500)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 32)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.CancelButton = $btnCancel

    $btnOk.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please give this mode a name.", "Missing Name", 'OK', 'Warning') | Out-Null
            return
        }
        if ($chkEnabled.Checked -and [int]$script:MEdHotkeyVk -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("An enabled mode needs a hotkey. Set one, or clear ""Enabled"".", "Missing Hotkey", 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($rowFound.TextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please specify the 'found' phrase to look for.", "Missing Phrase", 'OK', 'Warning') | Out-Null
            return
        }

        $work.Name                = $txtName.Text.Trim()
        $work.Enabled              = $chkEnabled.Checked
        $work.Hotkey               = [pscustomobject]@{ Modifiers = [int]$script:MEdHotkeyMods; Key = [int]$script:MEdHotkeyVk; Display = $txtHotkey.Text }
        $work.ActionKeyToken       = $script:MEdActionToken
        $work.ActionKeyDisplay     = $txtActionKey.Text
        $work.FoundText            = $rowFound.TextBox.Text
        $work.FoundOverlayText     = $rowFoundMsg.TextBox.Text
        $work.NotFoundText         = $rowNotFound.TextBox.Text
        $work.TerminalText         = $rowTerminal.TextBox.Text
        $work.NotFoundOverlayText  = $rowNotFoundMsg.TextBox.Text
        $work.MaxIterations        = [int]$numMaxIter.Value

        $dlg.Tag = 'Saved'
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $dlg.Controls.AddRange(@($lblName, $txtName, $grpKeys, $grpPhrases, $lblMaxIter, $numMaxIter, $chkEnabled, $btnOk, $btnCancel))

    # Dialog-local key-capture state (kept separate from the main
    # form's $script:Capturing so the two never collide).
    $script:MEdCapturing      = $null   # $null, 'Hotkey', or 'ModeAction'
    $script:MEdPreCaptureText = ""
    $script:MEdHotkeyMods     = $work.Hotkey.Modifiers
    $script:MEdHotkeyVk       = $work.Hotkey.Key
    $script:MEdActionToken    = $work.ActionKeyToken

    $dlg.Add_KeyDown({
        param($sender, $e)
        if (-not $script:MEdCapturing) { return }

        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            switch ($script:MEdCapturing) {
                'Hotkey'     { $txtHotkey.Text     = $script:MEdPreCaptureText; $txtHotkey.BackColor     = 'Window' }
                'ModeAction' { $txtActionKey.Text  = $script:MEdPreCaptureText; $txtActionKey.BackColor  = 'Window' }
            }
            $script:MEdCapturing = $null
            $e.Handled = $true
            $e.SuppressKeyPress = $true
            return
        }

        $requireMod = ($script:MEdCapturing -eq 'Hotkey')
        $captured = Get-KeyCaptureResult -EventArgs $e -RequireModifier $requireMod
        if ($null -eq $captured) {
            $e.Handled = $true; $e.SuppressKeyPress = $true; return   # pure modifier press - keep waiting
        }
        if ($captured.Retry) {
            $e.Handled = $true; $e.SuppressKeyPress = $true; return   # needs a modifier - message already shown
        }

        switch ($script:MEdCapturing) {
            'Hotkey' {
                $script:MEdHotkeyMods = $captured.Mods
                $script:MEdHotkeyVk   = $captured.Vk
                $txtHotkey.Text = $captured.Display
                $txtHotkey.BackColor = 'Window'
            }
            'ModeAction' {
                $script:MEdActionToken = Convert-KeyToSendKeysToken -Vk $captured.Vk -Mods $captured.Mods
                $txtActionKey.Text = $captured.Display
                $txtActionKey.BackColor = 'Window'
            }
        }
        $script:MEdCapturing = $null
        $e.Handled = $true
        $e.SuppressKeyPress = $true
    })

    $result = $dlg.ShowDialog()
    $dlg.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $work }
    return $null
}

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
$tabModes   = New-Object System.Windows.Forms.TabPage; $tabModes.Text   = "Modes"
$tabs.Controls.AddRange(@($tabGeneral, $tabTiming, $tabDup, $tabKeys, $tabModes))

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

$tabTiming.Controls.AddRange(@($grpTiming, $grpRows))

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
$grpKeys.Size = New-Object System.Drawing.Size(415, 110)

$lblToggle = New-Object System.Windows.Forms.Label
$lblToggle.Text = "Start / stop Toggle relay:"
$lblToggle.Location = New-Object System.Drawing.Point(15, 30)
$lblToggle.Size = New-Object System.Drawing.Size(150, 20)

$txtToggle = New-Object System.Windows.Forms.TextBox
$txtToggle.Location = New-Object System.Drawing.Point(170, 27)
$txtToggle.Size = New-Object System.Drawing.Size(140, 22)
$txtToggle.ReadOnly = $true
$txtToggle.Text = $existing.ToggleHotkey.Display

$btnSetToggle = New-Object System.Windows.Forms.Button
$btnSetToggle.Text = "Set..."
$btnSetToggle.Location = New-Object System.Drawing.Point(325, 25)
$btnSetToggle.Size = New-Object System.Drawing.Size(85, 25)
$btnSetToggle.Add_Click({
    $script:Capturing = 'Toggle'
    $script:PreCaptureText = $txtToggle.Text
    $txtToggle.Text = "Press keys... (Esc to cancel)"
    $txtToggle.BackColor = 'LightYellow'
})

$lblExit = New-Object System.Windows.Forms.Label
$lblExit.Text = "Quit AutoClipCapture:"
$lblExit.Location = New-Object System.Drawing.Point(15, 65)
$lblExit.Size = New-Object System.Drawing.Size(150, 20)

$txtExit = New-Object System.Windows.Forms.TextBox
$txtExit.Location = New-Object System.Drawing.Point(170, 62)
$txtExit.Size = New-Object System.Drawing.Size(140, 22)
$txtExit.ReadOnly = $true
$txtExit.Text = $existing.ExitHotkey.Display

$btnSetExit = New-Object System.Windows.Forms.Button
$btnSetExit.Text = "Set..."
$btnSetExit.Location = New-Object System.Drawing.Point(325, 60)
$btnSetExit.Size = New-Object System.Drawing.Size(85, 25)
$btnSetExit.Add_Click({
    $script:Capturing = 'Exit'
    $script:PreCaptureText = $txtExit.Text
    $txtExit.Text = "Press keys... (Esc to cancel)"
    $txtExit.BackColor = 'LightYellow'
})

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Hold Ctrl/Alt/Shift (any combination) and press a key. Each Mode has its own hotkey - see the Modes tab."
$lblHint.Location = New-Object System.Drawing.Point(15, 90)
$lblHint.Size = New-Object System.Drawing.Size(390, 15)
$lblHint.Font = New-Object System.Drawing.Font($lblHint.Font.FontFamily, 7.5)
$lblHint.ForeColor = 'Gray'

$grpKeys.Controls.AddRange(@($lblToggle, $txtToggle, $btnSetToggle, $lblExit, $txtExit, $btnSetExit, $lblHint))
$tabKeys.Controls.Add($grpKeys)

# ===================== Modes tab =====================
$grpOverlay = New-Object System.Windows.Forms.GroupBox
$grpOverlay.Text = "Result banner"
$grpOverlay.Location = New-Object System.Drawing.Point(10, 10)
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

$lstModes = New-Object System.Windows.Forms.ListView
$lstModes.Location = New-Object System.Drawing.Point(10, 75)
$lstModes.Size = New-Object System.Drawing.Size(415, 260)
$lstModes.View = 'Details'
$lstModes.FullRowSelect = $true
$lstModes.GridLines = $true
$lstModes.MultiSelect = $false
[void]$lstModes.Columns.Add("Name", 140)
[void]$lstModes.Columns.Add("Hotkey", 100)
[void]$lstModes.Columns.Add("Action Key", 85)
[void]$lstModes.Columns.Add("Enabled", 65)

function Update-ModesListView {
    $lstModes.Items.Clear()
    foreach ($m in $script:ModesList) {
        $item = New-Object System.Windows.Forms.ListViewItem($m.Name)
        [void]$item.SubItems.Add($m.Hotkey.Display)
        [void]$item.SubItems.Add($m.ActionKeyDisplay)
        [void]$item.SubItems.Add($(if ($m.Enabled) { "Yes" } else { "No" }))
        [void]$lstModes.Items.Add($item)
    }
}
Update-ModesListView

$btnModeAdd = New-Object System.Windows.Forms.Button
$btnModeAdd.Text = "Add..."
$btnModeAdd.Location = New-Object System.Drawing.Point(10, 340)
$btnModeAdd.Size = New-Object System.Drawing.Size(100, 28)
$btnModeAdd.Add_Click({
    $newMode = Show-ModeEditorDialog -ExistingMode $null
    if ($null -ne $newMode) {
        [void]$script:ModesList.Add($newMode)
        Update-ModesListView
    }
})

$btnModeEdit = New-Object System.Windows.Forms.Button
$btnModeEdit.Text = "Edit..."
$btnModeEdit.Location = New-Object System.Drawing.Point(120, 340)
$btnModeEdit.Size = New-Object System.Drawing.Size(100, 28)
$btnModeEdit.Add_Click({
    if ($lstModes.SelectedIndices.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select a mode to edit first.", "No Mode Selected", 'OK', 'Information') | Out-Null
        return
    }
    $idx = $lstModes.SelectedIndices[0]
    $edited = Show-ModeEditorDialog -ExistingMode $script:ModesList[$idx]
    if ($null -ne $edited) {
        $script:ModesList[$idx] = $edited
        Update-ModesListView
    }
})

$btnModeRemove = New-Object System.Windows.Forms.Button
$btnModeRemove.Text = "Remove"
$btnModeRemove.Location = New-Object System.Drawing.Point(230, 340)
$btnModeRemove.Size = New-Object System.Drawing.Size(100, 28)
$btnModeRemove.Add_Click({
    if ($lstModes.SelectedIndices.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select a mode to remove first.", "No Mode Selected", 'OK', 'Information') | Out-Null
        return
    }
    $idx = $lstModes.SelectedIndices[0]
    $name = $script:ModesList[$idx].Name
    $confirm = [System.Windows.Forms.MessageBox]::Show("Remove the mode '$name'?", "Confirm Remove", 'YesNo', 'Question')
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $script:ModesList.RemoveAt($idx)
        Update-ModesListView
    }
})

$lblModesHint = New-Object System.Windows.Forms.Label
$lblModesHint.Text = "Each Mode runs its own scan loop on its own hotkey (see 'SQL Search' for an example). Only one Mode - or the Toggle relay - can run at a time; pressing a running mode's hotkey again cancels it."
$lblModesHint.Location = New-Object System.Drawing.Point(10, 378)
$lblModesHint.Size = New-Object System.Drawing.Size(415, 45)
$lblModesHint.ForeColor = 'Gray'
$lblModesHint.Font = New-Object System.Drawing.Font($lblModesHint.Font.FontFamily, 7.5)

$tabModes.Controls.AddRange(@($grpOverlay, $lstModes, $btnModeAdd, $btnModeEdit, $btnModeRemove, $lblModesHint))

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

    $script:ModesList = New-Object System.Collections.ArrayList
    foreach ($m in @($defaults.Modes)) { [void]$script:ModesList.Add($m) }
    Update-ModesListView
})

$btnCancel.Add_Click({ $form.Close() })

$btnSave.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtLogFile.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please specify a log file path.", "Missing Log File", 'OK', 'Warning') | Out-Null
        return
    }

    # Collect every hotkey (Toggle, Exit, and each enabled Mode) and
    # make sure none of them collide.
    $allHotkeys = New-Object System.Collections.ArrayList
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Toggle relay"; Mods = $script:ToggleMods; Key = $script:ToggleKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Exit";         Mods = $script:ExitMods;   Key = $script:ExitKey })
    foreach ($m in $script:ModesList) {
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

    $modesForSave = @()
    foreach ($m in $script:ModesList) {
        $modesForSave += [pscustomobject]@{
            Id                  = $m.Id
            Name                = $m.Name
            Enabled             = [bool]$m.Enabled
            Hotkey              = [pscustomobject]@{ Modifiers = [int]$m.Hotkey.Modifiers; Key = [int]$m.Hotkey.Key; Display = [string]$m.Hotkey.Display }
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
        ToggleHotkey             = [pscustomobject]@{ Modifiers = $script:ToggleMods; Key = $script:ToggleKey; Display = $txtToggle.Text }
        ExitHotkey               = [pscustomobject]@{ Modifiers = $script:ExitMods;   Key = $script:ExitKey;   Display = $txtExit.Text }
        ResultOverlayDurationMs  = [int]$numOverlayDur.Value
        Modes                    = $modesForSave
    }

    $newConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show(
        "Configuration saved to:`n$ConfigPath`n`nRestart AutoClipCapture for the changes to take effect.",
        "Saved", 'OK', 'Information') | Out-Null
})

$form.Controls.AddRange(@($tabs, $btnSave, $btnDefaults, $btnCancel))

# ------------------------- Key-combo capture (main form: Toggle/Exit/Action) ---------------------------
$form.Add_KeyDown({
    param($sender, $e)

    if (-not $script:Capturing) { return }

    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        switch ($script:Capturing) {
            'Toggle' { $txtToggle.Text = $script:PreCaptureText; $txtToggle.BackColor = 'Window' }
            'Exit'   { $txtExit.Text   = $script:PreCaptureText; $txtExit.BackColor   = 'Window' }
            'Action' { $txtAction.Text = $script:PreCaptureText; $txtAction.BackColor = 'Window' }
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
