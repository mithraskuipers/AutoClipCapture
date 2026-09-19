<#
=====================================================================
 AutoClipCapture.ps1
=====================================================================
 Runs quietly in the background and listens for two GLOBAL hotkeys
 (they work even while a different application is focused):

   [Toggle hotkey]  -> Start / stop the capture loop.
                       When STARTING:
                         1. You are asked to CLICK the window you
                            want AutoClipCapture to operate on. A small
                            status banner in the top-left corner of
                            the screen tells you it's waiting for
                            the click (press Esc to cancel instead).
                         2. The window you clicked is identified and
                            a Yes/No confirmation box shows its title.
                            Press Enter (or click Yes) to accept it,
                            or No to click a different window.
                         3. You are asked for a filename - that becomes
                            the base name for this session's output.
                            Whatever's typed (extension or not) is only
                            ever used as a base name: the clipboard
                            data gets appended to TWO files every time,
                            a .txt copy under LogDir\txt and a .cbl
                            copy under LogDir\cbl, both with identical
                            content. Cancelling this prompt cancels the
                            start (nothing runs).
                       Once running, it repeatedly:
                         1. Brings the selected window to the
                            foreground and sends it CTRL+C
                         2. Waits briefly for the clipboard to update
                         3. Appends the clipboard text to both the .txt
                            and .cbl files for this session
                         4. Brings the selected window to the
                            foreground again and sends the configured
                            ACTION KEY (default F8)
                         5. Waits briefly, then repeats from step 1
                       While running, a small status overlay in the
                       top-left corner of the screen shows which of
                       these steps is currently happening.

   [Exit hotkey]    -> Fully quits this script

   [Mode hotkeys]   -> Any number of extra "scan modes" can be defined,
                       each bound to its own hotkey (Alt+> by default
                       runs the built-in "SQL Search" mode).
                       Pressing a mode's hotkey:
                         1. If the mode is set to use the focused
                            window (the default for SQL Search), the
                            window that already has focus at the
                            moment the hotkey is pressed is used
                            immediately - no click-to-select or
                            confirmation step. Older modes without
                            that flag still ask you to click/confirm a
                            target window, same as the Toggle hotkey
                            above.
                         2. Repeatedly sends the mode's ACTION KEY to
                            that window, waits, sends CTRL+C, waits,
                            then checks the clipboard text against the
                            mode's configured phrases:
                              - If the "found" phrase appears -> stop
                                and show the "found" message full-
                                screen.
                              - If the "not found" phrase (or the
                                optional second "not found" phrase)
                                appears -> stop and show the "not
                                found" message full-screen.
                              - If neither appears yet (e.g. the
                                screen hasn't finished updating) ->
                                press the action key again and check
                                once more, up to a safety limit
                                (MaxIterations) so a misconfigured
                                mode can't loop forever.
                         3. Once a definitive found/not-found answer
                            is reached, the captured text is scanned
                            for a line starting with "BROWSE" that has
                            a component identifier in parentheses (2
                            letters followed by a letter/number mix,
                            e.g. "BROWSE (AB12C) ..."). That
                            identifier and a Y/N for whether SQL was
                            found get recorded as a row in a Markdown
                            table file, component_sql_check.md
                            (created next to your log file). Re-
                            running the check on a component you've
                            already scanned updates its existing row
                            instead of adding a duplicate, so the
                            table is a running, growing record of
                            every component checked so far.
                       Pressing the same mode's hotkey again while it
                       is running cancels it. Only one mode (or the
                       Toggle relay) can run at a time. Modes
                       themselves are no longer edited from the config
                       GUI - only their hotkeys are. A hotkey flagged
                       "right-side only" only fires when the physical
                       RIGHT Ctrl/Alt/Shift key is the one held down
                       (off by default for SQL Search and F3 now that
                       they use Alt+Shift combos, since either side's
                       Alt/Shift works fine for those).

   [F3 hotkey]      -> Alt+< by default. Sends a single F3
                       keypress straight to whatever window already
                       has focus - no window selection, no loop, no
                       clipboard involved. Ignored while the Toggle
                       relay or a scan mode is running.

   [Pipeline hotkeys] -> Any number of multi-screen "Pipelines" can be
                       defined, each bound to its own hotkey, for
                       walking a full Screen1 (components) -> Screen2
                       (environments) -> Screen3 (SQL search) tree
                       instead of a single-screen scan Mode. For each
                       component: try to zoom in (Component.ZoomActionToken);
                       if the resulting screen still contains
                       Component.UnavailableText, that component is
                       skipped (Component.NextActionToken moves to the
                       next one). Otherwise every environment is walked
                       the same way (Environment.ZoomActionToken /
                       Environment.UnavailableText / Environment.NextActionToken),
                       and once an environment is available the existing
                       SQL Search logic (the Sql block - same fields as
                       a scan Mode) always runs. Results are recorded
                       per (component, environment) pair in
                       pipeline_sql_check.md. Going back a screen is
                       always a single F3 press (never held/repeated),
                       so a screen that treats repeated F3 as "back
                       multiple screens" (e.g. out to a logout screen)
                       stays safe. Pipelines are configured in
                       AutoClipCaptureConfig.json (see the Pipelines
                       array) - like Modes, they aren't edited from the
                       config GUI.

                       A Pipeline can also turn on an optional
                       "ComponentList" pre-pass (Pipelines[].ComponentList.Enabled).
                       When on, pressing the pipeline's hotkey (assumed
                       to be pressed while already sitting on Screen 1,
                       the component overview) first pages through the
                       entire overview once, front to back - Ctrl+C,
                       trim off ComponentList.SkipRowsStart/SkipRowsEnd
                       rows (default 5/3), append what's left to
                       pipeline_component_list.txt, press
                       ComponentList.NextActionToken (F8 by default) to
                       reach the next page, and repeat - without
                       opening a single component. It stops
                       automatically once a page comes back matching
                       the one before it (ComponentList.DupDetectThreshold,
                       same comparison the duplicate-capture protection
                       below uses), which means paging further isn't
                       revealing anything new. It also stops right away,
                       without waiting for that repeat-page check and
                       without pressing the next-page key at all, the
                       moment a page's raw captured text contains
                       ComponentList.EndOfListText (default "Bottom of
                       List") - an explicit "you're already at the
                       end" marker some screens show on their last
                       page. That saved list is then available for
                       later use; this phase's job ends once the list
                       is captured.

 Duplicate-capture protection: each capture is compared to the one
 immediately before it. If they come back 99.5% identical (default;
 configurable), that usually means the target app has stopped handing
 back new data (e.g. you've reached the end of a list). The loop pauses,
 shows a Continue / Stop Capture dialog, and waits for you - it will not
 silently keep looping and appending duplicate content forever. Choosing
 Continue won't re-prompt every cycle; it only asks again once new,
 different content shows up and then goes stale again.

 All settings - default log location, timing, the action key, the
 Toggle/Exit/F3 hotkeys, duplicate-capture detection, how many rows to
 skip at the start/end of each capture (e.g. to drop a repeated
 header/footer row a target app always copies along with the data),
 and the list of scan Modes - are read from
 AutoClipCaptureConfig.json (same folder as this script). Run this same
 script with the -EditConfig switch (StartAutoClipCapture.bat EditConfig,
 or "powershell -STA -File AutoClipCapture.ps1 -EditConfig") to change them
 in a GUI without hand-editing the file. If AutoClipCaptureConfig.json
 doesn't exist yet, a default one is created automatically on first run.

 IMPORTANT:
   - Must run in STA mode (needed for clipboard access). The
     included .bat launcher already starts it with -STA.
   - Because the loop now re-focuses your chosen window itself
     before every action, you no longer have to babysit window
     focus by hand - just make sure that window still exists.
     If it gets closed, the capture stops automatically.
=====================================================================
#>

<#
=====================================================================
 CONSOLIDATION NOTE - read this if you're used to the old multi-file layout
=====================================================================
 This single file now contains everything that used to be split across:
   - AutoClipCapture.ps1                        this script, as before
   - AutoClipCaptureSqlPipelineScreen1.ps1       now inlined below, in its
                                                 own clearly marked region
   - AutoClipCaptureSqlPipelineScreen2.ps1       same
   - AutoClipCaptureSqlPipelineScreen3.ps1       same
   - AutoClipCaptureSqlPipelineComponentList.ps1 same
   - AutoClipCaptureConfigGUI.ps1                now the Show-ConfigEditorGui
                                                 function below, invoked with
                                                 the -EditConfig switch
   - CalibrateScreen1Auto.ps1                    now the
                                                 Invoke-Screen1CalibrationTool
                                                 function below, invoked with
                                                 the -Calibrate switch
 Only two files are needed now:
   - AutoClipCapture.ps1        this file
   - AutoClipCaptureConfig.json settings, unchanged, same format as before
 ...plus StartAutoClipCapture.bat to launch it. CalibrateScreen1Auto.bat and
 ConfigureAutoClipCapture.bat are no longer needed either - both jobs now go
 through StartAutoClipCapture.bat's Calibrate/EditConfig arguments below.

 Run normally (double-click StartAutoClipCapture.bat, or
 "powershell -STA -File AutoClipCapture.ps1") to start the capture relay/
 hotkeys exactly as before.

 Run with -EditConfig ("StartAutoClipCapture.bat EditConfig", or
 "powershell -STA -File AutoClipCapture.ps1 -EditConfig") to open the
 settings GUI instead - it edits the same AutoClipCaptureConfig.json file
 and does not start the capture relay.

 Run with -Calibrate ("StartAutoClipCapture.bat Calibrate", or
 "powershell -STA -File AutoClipCapture.ps1 -Calibrate") to open the Screen1
 auto-calibration tool instead - same tool AutoClipCapture.ps1 already
 offers to launch for you when a pipeline isn't calibrated yet, just
 runnable on demand too. It does not start the capture relay.

 Behavior of every hotkey, pipeline, and setting is unchanged - this was a
 pure file-layout consolidation, nothing about how the automation runs was
 touched.
=====================================================================
#>

param(
    # Launch the settings GUI (same editor that used to be
    # AutoClipCaptureConfigGUI.ps1) instead of starting the capture relay.
    [switch]$EditConfig,

    # Launch the Screen1 auto-calibration tool (same tool that used to be
    # CalibrateScreen1Auto.ps1) instead of starting the capture relay. This
    # is also how AutoClipCapture.ps1 relaunches itself, as a fresh separate
    # process, when it offers to calibrate an unconfigured pipeline at
    # startup or via Show-Screen1CalibrationPrompt.
    [switch]$Calibrate
)

$ConfigPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"

#=====================================================================
# region: AutoClipCaptureConfigGUI.ps1 - formerly its own file, now the
# Show-ConfigEditorGui function below, invoked when this script is run
# with -EditConfig. Everything inside is unchanged from the standalone
# version - it's just wrapped in a function now instead of being a
# top-level script.
#=====================================================================
function Show-ConfigEditorGui {
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
        # Pipelines aren't edited by this GUI (see the header comment
        # in AutoClipCapture.ps1) - carry whatever was already in the
        # file straight through so saving settings here can't silently
        # delete them.
        Pipelines                = if ($existing.PSObject.Properties.Name -contains 'Pipelines') { $existing.Pipelines } else { @() }
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
}
# endregion: AutoClipCaptureConfigGUI.ps1
#=====================================================================

#=====================================================================
# region: CalibrateScreen1Auto.ps1 - formerly its own file, now the
# Invoke-Screen1CalibrationTool function below, invoked when this script
# is run with -Calibrate. Everything inside is unchanged from the
# standalone version - it's just wrapped in a function now instead of
# being a top-level script. Like the standalone version, it's meant to
# run as its own dedicated process (see the -Calibrate dispatch above and
# Invoke-Screen1CalibrationNow below, which is what actually launches it) -
# it reads/writes the console directly (Read-Host, Console.ReadKey, pause)
# and calls exit on its own error paths, which is exactly right for a
# standalone process but would be wrong if it ran inline inside the
# capture relay's own process.
#=====================================================================
function Invoke-Screen1CalibrationTool {
<#
=====================================================================
 CalibrateScreen1Auto.ps1

 Automatic replacement for CalibrateScreen1AutoGuided.ps1's manual
 "nudge with arrow keys until it looks right" steps.

 WHY THIS IS POSSIBLE: the terminal itself renders as a solid black
 rectangle sitting inside a visibly lighter window (menu bar, icon
 toolbar, status bar - see your own screenshots). That contrast is
 detectable in a screenshot. So instead of asking you to judge pixel
 alignment by eye, this script:
   1. Takes a screenshot of exactly the target window's client area
      (Graphics.CopyFromScreen - the window must be visible on top,
      not covered by another window, while this runs).
   2. Scans it row by row and column by column for the largest solid
      dark rectangle - that's the terminal grid, as opposed to the
      lighter menu/toolbar/status-bar chrome around it.
   3. Divides that rectangle's pixel width/height by the known fixed
      grid (80 columns x 32 rows) to get CharWidthPx/CharHeightPx -
      measured from the ACTUAL terminal area only, unlike
      CalibrateScreen1AutoGuided.ps1's original approach of dividing
      the WHOLE window client area by 80x32 (which silently counted
      the menu/toolbar/status-bar height as if it were extra terminal
      rows, and produced a CharHeightPx that was too small - accurate
      only right at the one manually-nudged row, and increasingly off
      moving down the page).
   4. Works out OriginX/OriginY from that rectangle's actual top-left
      corner.
   5. Copies the CURRENT screen (Ctrl+C) and finds the real first line
      with "COB" printed on it - ONCE. That line/column becomes
      FirstDataRowLineIndex/SelectionColumnIndex, saved into
      Screen1Select permanently. The real pipeline
      (AutoClipCaptureSqlPipelineScreen1.ps1) no longer reads page
      content at all to find rows - every row on every page is now
      pure arithmetic from these saved numbers (row N = first row +
      N x CharHeightPx). This only works because the header above the
      list is always exactly the same size - if that's not true for
      your screens, this whole approach isn't safe to use.
   6. Shows you the result and moves the mouse to the computed point
      for ONE quick look - press Enter to accept, Esc to cancel
      (nothing is saved on cancel; CalibrateScreen1AutoGuided.ps1 is
      still there as a manual fallback if detection ever gets it
      wrong, e.g. a non-black terminal color scheme).

 NOTE: make sure the terminal is showing a REPOSITORY LIST page with
 at least one visible "COB" row before running this - step 5 needs
 real COB text on screen to calibrate against, this one time.

 Run it via "StartAutoClipCapture.bat Calibrate", via the -Calibrate
 switch ("powershell -STA -File AutoClipCapture.ps1 -Calibrate"), or
 let AutoClipCapture.ps1 launch it for you when it offers to calibrate
 an unconfigured pipeline.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Make THIS PROCESS DPI-aware before the screenshot/coordinate
# code below runs - MUST match AutoClipCapture.ps1's own DPI-awareness
# call exactly, or the two scripts will disagree about what a pixel
# is and every click will drift off by the display scaling percentage.
# See the matching comment at the top of AutoClipCapture.ps1 for why.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CR_DpiAwareness {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue

    $perMonitorV2 = [IntPtr](-4)
    $setDpi = $false
    try { $setDpi = [CR_DpiAwareness]::SetProcessDpiAwarenessContext($perMonitorV2) } catch {}
    if (-not $setDpi) {
        try { [void][CR_DpiAwareness]::SetProcessDpiAwareness(2) } catch {}
        try { [void][CR_DpiAwareness]::SetProcessDPIAware() } catch {}
    }
} catch {
    Write-Host "Could not set DPI awareness - if Windows display scaling isn't 100%, calibration will be off. $_" -ForegroundColor Yellow
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public struct POINT2 { public int X; public int Y; }
public struct RECT2 { public int Left; public int Top; public int Right; public int Bottom; }

public static class CalibNative4
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT2 lpRect);

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT2 lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    public static List<KeyValuePair<IntPtr,string>> GetVisibleWindows()
    {
        var list = new List<KeyValuePair<IntPtr,string>>();
        EnumWindows((hWnd, lParam) =>
        {
            if (IsWindowVisible(hWnd))
            {
                int len = GetWindowTextLength(hWnd);
                if (len > 0)
                {
                    var sb = new StringBuilder(len + 1);
                    GetWindowText(hWnd, sb, sb.Capacity + 1);
                    string title = sb.ToString();
                    if (!string.IsNullOrWhiteSpace(title))
                    {
                        list.Add(new KeyValuePair<IntPtr,string>(hWnd, title));
                    }
                }
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

# A row/column counts as "terminal" if at least this fraction of its
# pixels are dark. The terminal's black background dominates even rows
# full of bright text; menu/toolbar/status-bar rows are mostly light
# with only a little dark text/icon detail, so they score far lower.
$DarkFraction   = 0.40
$DarkThreshold  = 40   # average of R,G,B below this counts as "dark"

function Get-WindowScreenshot {
    param([IntPtr]$Handle)

    $rect = New-Object RECT2
    [void][CalibNative4]::GetClientRect($Handle, [ref]$rect)
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { return $null }

    $topLeft = New-Object POINT2
    $topLeft.X = 0; $topLeft.Y = 0
    [void][CalibNative4]::ClientToScreen($Handle, [ref]$topLeft)

    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($topLeft.X, $topLeft.Y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    return $bmp
}

# Returns @{ Left; Top; Right; Bottom } (exclusive) of the largest solid
# dark rectangle in the bitmap, using fast LockBits byte access rather
# than the (very slow, one-call-per-pixel) Bitmap.GetPixel.
function Find-DarkRectangle {
    param([System.Drawing.Bitmap]$Bmp)

    $w = $Bmp.Width
    $h = $Bmp.Height
    $rectFull = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $bmpData = $Bmp.LockBits($rectFull, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    $bytes = New-Object byte[] ($bmpData.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($bmpData.Scan0, $bytes, 0, $bytes.Length)
    $Bmp.UnlockBits($bmpData)
    $stride = $bmpData.Stride

    # ---- Per-row dark fraction -> largest contiguous "dark" row band ----
    $rowDark = New-Object bool[] $h
    for ($y = 0; $y -lt $h; $y++) {
        $darkCount = 0
        $rowOffset = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $px = $rowOffset + ($x * 4)
            $b = $bytes[$px]; $gr = $bytes[$px + 1]; $r = $bytes[$px + 2]
            if ((([int]$r + [int]$gr + [int]$b) / 3) -lt $DarkThreshold) { $darkCount++ }
        }
        $rowDark[$y] = (($darkCount / [double]$w) -ge $DarkFraction)
    }

    $bestTop = -1; $bestBottom = -1; $bestLen = 0
    $curStart = -1
    for ($y = 0; $y -le $h; $y++) {
        $isDark = ($y -lt $h) -and $rowDark[$y]
        if ($isDark -and $curStart -lt 0) { $curStart = $y }
        elseif (-not $isDark -and $curStart -ge 0) {
            $len = $y - $curStart
            if ($len -gt $bestLen) { $bestLen = $len; $bestTop = $curStart; $bestBottom = $y }
            $curStart = -1
        }
    }
    if ($bestTop -lt 0) { return $null }

    # ---- Per-column dark fraction, restricted to those rows -> left/right ----
    $bandHeight = $bestBottom - $bestTop
    $colDark = New-Object bool[] $w
    for ($x = 0; $x -lt $w; $x++) {
        $darkCount = 0
        for ($y = $bestTop; $y -lt $bestBottom; $y++) {
            $px = ($y * $stride) + ($x * 4)
            $b = $bytes[$px]; $gr = $bytes[$px + 1]; $r = $bytes[$px + 2]
            if ((([int]$r + [int]$gr + [int]$b) / 3) -lt $DarkThreshold) { $darkCount++ }
        }
        $colDark[$x] = (($darkCount / [double]$bandHeight) -ge $DarkFraction)
    }

    $bestLeft = -1; $bestRight = -1; $bestColLen = 0
    $curStart = -1
    for ($x = 0; $x -le $w; $x++) {
        $isDark = ($x -lt $w) -and $colDark[$x]
        if ($isDark -and $curStart -lt 0) { $curStart = $x }
        elseif (-not $isDark -and $curStart -ge 0) {
            $len = $x - $curStart
            if ($len -gt $bestColLen) { $bestColLen = $len; $bestLeft = $curStart; $bestRight = $x }
            $curStart = -1
        }
    }
    if ($bestLeft -lt 0) { return $null }

    return @{ Left = $bestLeft; Top = $bestTop; Right = $bestRight; Bottom = $bestBottom }
}

# Mirrors AutoClipCaptureSqlPipelineScreen1.ps1's Get-Screen1DataRows:
# finds the first line that actually has "COB" printed on it, and the
# 0-based (line, column) it's at on THIS screen - never a hardcoded
# row/column guess. This is what makes the preview below test the
# exact same thing the real pipeline will click on, instead of a
# fixed row/column number that may not match this screen's layout.
function Get-FirstCobMatch {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $lines = $Text -split "`r`n|`n|`r"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '\bCOB\b')
        if ($m.Success) {
            return [pscustomobject]@{ LineIndex = $i; ColIndex = $m.Index; LineText = $lines[$i] }
        }
    }
    return $null
}

Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Screen1Select Automatic Calibration" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "ASSUMPTIONS this calibration relies on:" -ForegroundColor Magenta
Write-Host "  - Windows display scaling is set to 100% (Settings > System > Display)." -ForegroundColor Magenta
Write-Host "  - The terminal's font size / window size won't change after this runs -" -ForegroundColor Magenta
Write-Host "    if either does, the saved numbers go stale and you'll need to" -ForegroundColor Magenta
Write-Host "    recalibrate (clicks will drift, worse further down the page)." -ForegroundColor Magenta
Write-Host "  - The terminal window is fully visible on screen and not covered by" -ForegroundColor Magenta
Write-Host "    another window right when the screenshot below is taken." -ForegroundColor Magenta
Write-Host "  - The terminal renders on a solid dark/black background (this is what" -ForegroundColor Magenta
Write-Host "    the detection below actually looks for)." -ForegroundColor Magenta
Write-Host ""

$configPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Could not find AutoClipCaptureConfig.json next to this script." -ForegroundColor Red
    pause
    exit 1
}
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

$targets = @()
foreach ($pipeline in $config.Pipelines) {
    if ($null -ne $pipeline.Screen1Select) { $targets += $pipeline }
}
if ($targets.Count -eq 0) {
    Write-Host "No pipeline with a Screen1Select block was found in the config. Nothing to calibrate." -ForegroundColor Red
    pause
    exit 1
}
$chosenPipeline = $targets[0]
if ($targets.Count -gt 1) {
    Write-Host "`nMultiple pipelines need calibration. Which one?"
    for ($i = 0; $i -lt $targets.Count; $i++) { Write-Host ("  [{0}] {1} ({2})" -f $i, $targets[$i].Name, $targets[$i].Id) }
    $pIdx = Read-Host "Enter the number"
    $chosenPipeline = $targets[[int]$pIdx]
}

# ClickColumnOffset: how many characters LEFT of "COB" the selection
# field sits. This is the only fixed assumption left - unlike the old
# cobColumn/firstDataRow guesses, AutoClipCaptureSqlPipelineScreen1.ps1
# never assumes which column/row "COB" itself is on; it finds "COB" on
# the real screen first and adds this offset to whatever column that
# turned out to be. The preview below now does exactly the same thing,
# so there's no separate row/column guess left to go stale.
$clickColumnOffset = -2
$cols = 80
$rows = 32
$chosenPipeline.Screen1Select.ClickColumnOffset = $clickColumnOffset

Write-Host "`nMake sure your terminal window is open, fully visible, and NOT covered by another window." -ForegroundColor Cyan
Write-Host "Open windows:"
$windows = [CalibNative4]::GetVisibleWindows()
for ($i = 0; $i -lt $windows.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f $i, $windows[$i].Value)
}
$winIdx = Read-Host "`nType the number next to your mainframe terminal window"
if (-not ($winIdx -as [int]) -or [int]$winIdx -lt 0 -or [int]$winIdx -ge $windows.Count) {
    Write-Host "Invalid choice. Nothing changed." -ForegroundColor Red
    pause
    exit 1
}
$targetHandle = $windows[[int]$winIdx].Key
[void][CalibNative4]::SetForegroundWindow($targetHandle)
Start-Sleep -Milliseconds 300   # give it a moment to actually come to the front before the screenshot

Write-Host "`nTaking a screenshot and looking for the terminal grid..." -ForegroundColor Cyan
$bmp = Get-WindowScreenshot -Handle $targetHandle
if ($null -eq $bmp) {
    Write-Host "Couldn't read that window's size/screenshot. Nothing changed." -ForegroundColor Red
    pause
    exit 1
}

$box = Find-DarkRectangle -Bmp $bmp
$bmp.Dispose()

if ($null -eq $box -or ($box.Right - $box.Left) -lt 100 -or ($box.Bottom - $box.Top) -lt 100) {
    Write-Host "`nCouldn't confidently find a solid dark terminal rectangle in that window." -ForegroundColor Red
    Write-Host "(Maybe the terminal uses a light color scheme, or another window was on top of it.)" -ForegroundColor Red
    Write-Host "Use CalibrateScreen1AutoGuided.bat instead - it doesn't rely on detecting a dark background." -ForegroundColor Yellow
    pause
    exit 1
}

$boxWidth  = $box.Right - $box.Left
$boxHeight = $box.Bottom - $box.Top
$CharWidthPx  = [math]::Round(($boxWidth / $cols), 2)
$CharHeightPx = [math]::Round(($boxHeight / $rows), 2)

# Sanity-check the measured cell size against plausible terminal font
# dimensions, so a bad detection (e.g. it found some other dark UI
# panel instead of the actual terminal) gets caught here instead of
# silently producing bad click coordinates later.
if ($CharWidthPx -lt 4 -or $CharWidthPx -gt 30 -or $CharHeightPx -lt 6 -or $CharHeightPx -gt 50) {
    Write-Host "`nDetected rectangle is $boxWidth x $boxHeight px, giving an implausible char size" -ForegroundColor Red
    Write-Host "($CharWidthPx x $CharHeightPx px). That's probably not the terminal grid." -ForegroundColor Red
    Write-Host "Use CalibrateScreen1AutoGuided.bat instead." -ForegroundColor Yellow
    pause
    exit 1
}

# Row-0/column-0 origin (cell CENTER), matching the exact convention
# AutoClipCaptureSqlPipelineScreen1.ps1's click formula expects:
#   ClientX = OriginX + Col * CharWidthPx
#   ClientY = OriginY + Row * CharHeightPx
$OriginX = [math]::Round($box.Left + ($CharWidthPx / 2))
$OriginY = [math]::Round($box.Top + ($CharHeightPx / 2))

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host " Detected" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host ("  Terminal box   = {0}x{1} px (at client offset {2},{3})" -f $boxWidth, $boxHeight, $box.Left, $box.Top)
Write-Host ("  OriginX        = {0}" -f $OriginX)
Write-Host ("  OriginY        = {0}" -f $OriginY)
Write-Host ("  CharWidthPx    = {0}" -f $CharWidthPx)
Write-Host ("  CharHeightPx   = {0}" -f $CharHeightPx)

# ---- Find the REAL first "COB" row on whatever screen is showing
# right now, instead of assuming a fixed row/column - this is the part
# that used to be hardcoded (cobColumn=5, firstDataRow=7) and could be
# wrong for a given screen's actual layout. Make sure your terminal is
# currently showing a REPOSITORY LIST page with at least one COB row
# visible before continuing. ----
Write-Host "`nCopying the current screen to find the real first 'COB' row..." -ForegroundColor Cyan
[void][CalibNative4]::SetForegroundWindow($targetHandle)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('^c')

$copiedText = $null
for ($try = 0; $try -lt 10; $try++) {
    Start-Sleep -Milliseconds 150
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $candidate = [System.Windows.Forms.Clipboard]::GetText()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $copiedText = $candidate; break }
        }
    } catch {}
}

$cobMatch = Get-FirstCobMatch -Text $copiedText
if ($null -eq $cobMatch) {
    Write-Host "`nCouldn't find any line with 'COB' on the current screen." -ForegroundColor Red
    Write-Host "Navigate the terminal to a REPOSITORY LIST page that actually shows COB rows, then run this again." -ForegroundColor Red
    pause
    exit 1
}
Write-Host ("  First 'COB' found at line {0}, column {1}: `"{2}`"" -f $cobMatch.LineIndex, $cobMatch.ColIndex, $cobMatch.LineText.Trim()) -ForegroundColor Cyan

# NOTE: previously corrected by +1 here on the assumption the raw
# detected line sits one row ABOVE the true first data row. In
# practice that made the real pipeline land one row BELOW the true
# first data row (starting on the second COB row instead of the
# first), so the raw detected line index is used as-is.
$realLineIndex = $cobMatch.LineIndex

$targetColIndex = $cobMatch.ColIndex + $clickColumnOffset
$confirmX = $OriginX + ($targetColIndex * $CharWidthPx)
$confirmY = $OriginY + ($realLineIndex * $CharHeightPx)

$pt = New-Object POINT2
$pt.X = [int][math]::Round($confirmX)
$pt.Y = [int][math]::Round($confirmY)
[void][CalibNative4]::ClientToScreen($targetHandle, [ref]$pt)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pt.X, $pt.Y)

Write-Host ""
Write-Host "Pointer moved to the computed first-data-row selection field (next to 'COB')." -ForegroundColor Cyan
Write-Host "Look at the terminal - does it land there? ENTER to save, Esc to cancel." -ForegroundColor Cyan
Write-Host "(Reminder: this assumes 100% display scaling and today's font/window size." -ForegroundColor DarkGray
Write-Host " Recalibrate if either changes later.)" -ForegroundColor DarkGray
while ($true) {
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'Enter') { break }
    if ($key.Key -eq 'Escape') {
        Write-Host "`nCancelled - nothing saved." -ForegroundColor Yellow
        pause
        exit 0
    }
}

$chosenPipeline.Screen1Select.OriginX = $OriginX
$chosenPipeline.Screen1Select.OriginY = $OriginY
$chosenPipeline.Screen1Select.CharWidthPx = $CharWidthPx
$chosenPipeline.Screen1Select.CharHeightPx = $CharHeightPx

# These two are now the permanent, fixed row/column constants the real
# pipeline uses for EVERY row on EVERY page (no more per-row text
# scanning at runtime - see AutoClipCaptureSqlPipelineScreen1.ps1's
# Get-Screen1FixedRows). They only need to be right once: LineIndex is
# where row 1 of data sits (only valid because the header above the
# list is always the same fixed size), ColIndex is where "Type" text
# (COB/ASM) starts - the selection field itself is ColIndex + ClickColumnOffset.
foreach ($prop in @(
    @{ Name = 'FirstDataRowLineIndex'; Value = $realLineIndex },
    @{ Name = 'SelectionColumnIndex';  Value = $cobMatch.ColIndex  }
)) {
    if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains $prop.Name)) {
        $chosenPipeline.Screen1Select | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    } else {
        $chosenPipeline.Screen1Select.($prop.Name) = $prop.Value
    }
}

$calibNote = "Auto-calibrated {0} assuming 100% Windows display scaling AND that the header above the list is always exactly this many lines. Recalibrate if display scaling, the terminal's font size, the window size, or the header's line count changes." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains 'CalibrationNote')) {
    $chosenPipeline.Screen1Select | Add-Member -NotePropertyName CalibrationNote -NotePropertyValue $calibNote -Force
} else {
    $chosenPipeline.Screen1Select.CalibrationNote = $calibNote
}

$backupPath = Join-Path $PSScriptRoot ("AutoClipCaptureConfig.backup-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -Path $configPath -Destination $backupPath -Force
Write-Host ("`nBacked up old config to: {0}" -f (Split-Path $backupPath -Leaf))

$config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "Done! AutoClipCaptureConfig.json has been updated." -ForegroundColor Green
Write-Host "Close this window and try Ctrl+Shift+M again." -ForegroundColor Green
Write-Host ""
pause
}
# endregion: CalibrateScreen1Auto.ps1
#=====================================================================

# Both the main capture relay and the config-editor GUI need these,
# regardless of which one ends up running.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($EditConfig) {
    # -EditConfig was passed: open the settings GUI and stop - do not
    # start the capture relay, do not touch DPI awareness or hotkeys.
    Show-ConfigEditorGui
    return
}

if ($Calibrate) {
    # -Calibrate was passed: run the Screen1 auto-calibration tool and
    # stop - do not start the capture relay. This branch runs the tool's
    # own DPI-awareness setup itself (see Invoke-Screen1CalibrationTool
    # below), so it deliberately does not fall through to the capture
    # relay's DPI-awareness block right below.
    Invoke-Screen1CalibrationTool
    return
}

# ---- Make THIS PROCESS DPI-aware before anything below ever touches
# a screen coordinate (ClientToScreen, SetCursorPos, GetWindowRect, or
# CalibrateScreen1Auto.ps1's screenshot capture). This has to happen
# before any window/handle exists, so it's the very first thing this
# script does.
#
# WHY THIS MATTERS: on any Windows display scaling other than 100%, an
# app that hasn't declared itself DPI-aware gets coordinates from
# user32 in "virtualized" (scaled-down) units instead of real pixels.
# A screenshot (Graphics.CopyFromScreen), however, is always real
# pixels. Mixing the two is exactly what makes a calibrated click
# consistently land off to one side by roughly the scaling percentage,
# no matter how carefully OriginX/CharWidthPx were measured - which is
# the #1 real-world cause of "the red circle/click is off, and it
# doesn't move where I expect." If Windows display scaling is already
# 100%, this call is a harmless no-op.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CR_DpiAwareness {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue

    $perMonitorV2 = [IntPtr](-4)   # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (Win10 1703+)
    $setDpi = $false
    try { $setDpi = [CR_DpiAwareness]::SetProcessDpiAwarenessContext($perMonitorV2) } catch {}
    if (-not $setDpi) {
        try { [void][CR_DpiAwareness]::SetProcessDpiAwareness(2) } catch {}   # PROCESS_PER_MONITOR_DPI_AWARE (Win8.1+)
        try { [void][CR_DpiAwareness]::SetProcessDPIAware() } catch {}         # system-DPI-aware fallback (Vista+)
    }
} catch {
    Write-Host "[AutoClipCapture] Could not set DPI awareness - if Windows display scaling isn't 100%, clicks may land off-target. $_" -ForegroundColor Yellow
}

# Pipeline screen logic lives in its own file per screen, all kept in
# this same folder (no subfolders): Screen 1 = components,
# Screen 2 = environments, Screen 3 = the COBOL/SQL search screen.
# ComponentList is an optional "Step 1" pre-pass that also lives on
# Screen 1 (paging through the full component overview once, up
# front, before any zooming happens) - kept in its own file since it's
# a separate phase with its own state names. Dot-sourcing just defines
# their functions into this script's scope - no side effects until the
# pipeline tick handler below actually calls into them.
# Pipeline screen logic used to live in its own file per screen (dot-sourced
# at startup); they're now inlined directly below as clearly marked regions,
# in the same order they used to be dot-sourced. Nothing about how they work
# changed - Screen 1 = components, Screen 2 = environments, Screen 3 = the
# COBOL/SQL search screen, and ComponentList = the optional Screen 1
# paging pre-pass.

#=====================================================================
# region: AutoClipCaptureSqlPipelineScreen1.ps1 - formerly its own file, now inlined here
#=====================================================================
<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 Screen 1 = the REPOSITORY LIST overview (Type/Name/Appl/Subappl/
 Status columns, one row per component, "Row x of y ... More -->").

 This file drives the Ctrl+Shift+M pipeline's main job: walk every row
 slot of Screen 1, page by page, and for each one:
   0. Row positions are FIXED, pure arithmetic - no page content is
      read to find them. Screen1Select.FirstDataRowLineIndex and
      Screen1Select.SelectionColumnIndex (set once by
      CalibrateScreen1Auto.ps1, by actually finding the real first
      "COB" row on a real screen) anchor row 0; every following row is
      just + CharHeightPx per row, for exactly RowsPerPage rows. This
      only works because the header above the list (title/"Show
      Deleted: N"/column headers/filter line) is always exactly the
      same size on every page - if that ever isn't true, row math
      drifts and this whole approach stops being safe.
   1. Every row slot is tried - there's no "is this actually a COB
      row" check anymore. A slot with nothing real in it (past the end
      of a partially-filled last page, or a non-COB row type) simply
      doesn't navigate anywhere; step 4 below already treats that as
      the normal "nothing happened, move on" case, so no separate
      blank-detection step is needed.
   1a. Click Screen1Select.ClickColumnOffset character columns to the
      left of SelectionColumnIndex (default -2, lands on the "_"
      selection field) using the pixel math calibrated by
      CalibrateScreen1Auto.ps1/CalibrateScreen1AutoGuided.ps1 into
      Pipelines[].Screen1Select (OriginX/OriginY/CharWidthPx/
      CharHeightPx).
   2. Type Screen1Select.SelectionText (default "B") and press Enter.
   3. Confirm we landed on Screen 2 (COMPONENT VERSION - SELECT). If we
      did, hand off to AutoClipCaptureSqlPipelineScreen2.ps1, which
      logs it (if enabled) and queues a single F3 "back" to Screen 1
      (that shared "go back" mechanic lives in AutoClipCapture.ps1
      itself - see Back_Action/Back_Wait/Back_Copy).
   4. If nothing happened (blank slot, non-COB row, or the item is
      unavailable) - we're still on Screen 1 - just move on to the
      next row slot without going back.
   5. Once every row slot on the current page (RowsPerPage of them)
      has been tried, press Screen1Select.PageNextToken (F8 by
      default) to bring the next page into view, and keep going with
      the SAME fixed row slots - until either
      Screen1Select.EndOfListText shows up (explicit "end of list"
      marker) or a freshly-paged screen comes back near-identical to
      the one before it (Screen1Select.DupDetectThreshold - same
      comparison the duplicate-capture protection elsewhere uses),
      which means paging further isn't revealing anything new either.

 States (all start with "Comp" so AutoClipCapture.ps1's tick switch
 routes them here):
   CompScan_Action  - build the fixed row-slot list (Get-Screen1FixedRows,
                      pure arithmetic, no clipboard read needed). This
                      exact name is also the pipeline's hard-coded
                      starting state (see the Ctrl+Shift+M hotkey
                      handler), so a pipeline with no ComponentList
                      pre-pass lands here immediately.
   CompZoom_Action  - click the row at
                      $global:CR_PipelineScreen1Rows[$global:CR_PipelineComponentIdx],
                      type the selection letter, press Enter.
   CompZoom_Wait    - short delay before copying, so the new screen
                      has time to render.
   CompZoom_Copy    - Ctrl+C, read the clipboard, work out what
                      happened, branch accordingly (see below).
   CompNext_Action  - decide the next row (same page) or trigger a
                      page turn. Reached either right after a
                      non-navigating row (still on Screen 1) or once
                      Screen 2 has been dealt with and Back_Copy has
                      confirmed we're back on Screen 1. This exact
                      name also doubles as the "AfterBack" marker the
                      shared Back_Copy logic checks to know it should
                      expect Screen 1 (not Screen 2) once the F3
                      completes.
   CompPage_Action  - send Screen1Select.PageNextToken (e.g. F8) to
                      move to the next page.
   CompPage_Wait    - short delay before copying the new page.
   CompPage_Copy    - Ctrl+C, check EndOfListText / duplicate-page
                      (still genuinely needs the page's text - that's
                      the one place content is still read, purely to
                      know when to STOP paging, never to find rows);
                      either stop (pipeline complete) or rebuild the
                      same fixed row-slot list and keep going from row
                      0 of the new page.

 $global:CR_PipelineComponentIdx is the 0-based index *into
 $global:CR_PipelineScreen1Rows* (0..RowsPerPage-1, always the same
 fixed slots). Both are reset by AutoClipCapture.ps1 whenever the
 pipeline (re)starts, and reset again here every time a new page comes
 in.
=====================================================================
#>

# Builds the fixed set of row slots for one page - RowsPerPage of
# them, starting at FirstDataRowLineIndex/SelectionColumnIndex (set
# once, for real, by CalibrateScreen1Auto.ps1's Ctrl+C-based
# detection) and stepping one line at a time. No page content is read
# here at all: every page gets literally the same LineIndex/ColIndex
# list, because the header above the list is always the same size.
function Get-Screen1FixedRows {
    param($Screen1Select)

    $rows = New-Object System.Collections.Generic.List[object]
    $firstLine = [int]$Screen1Select.FirstDataRowLineIndex
    $col       = [int]$Screen1Select.SelectionColumnIndex
    $count     = [int]$Screen1Select.RowsPerPage

    for ($i = 0; $i -lt $count; $i++) {
        $rows.Add([pscustomobject]@{
            LineIndex = $firstLine + $i
            ColIndex  = $col
        })
    }

    return $rows
}

# Works out the on-screen (screen-coordinate) point for one row slot,
# using the OriginX/OriginY/CharWidthPx/CharHeightPx calibration
# CalibrateScreen1Auto.ps1 produces, and the LineIndex/ColIndex that
# Get-Screen1FixedRows generated for that slot (pure arithmetic off
# FirstDataRowLineIndex/SelectionColumnIndex - not read from content).
function Get-Screen1RowScreenPoint {
    param(
        [IntPtr]$Handle,
        $Screen1Select,
        [int]$LineIndex,
        [int]$ColIndex
    )

    $targetColIndex = $ColIndex + [int]$Screen1Select.ClickColumnOffset

    # No manual scaling correction here anymore - this used to multiply
    # by a percentage typed into a popup at Ctrl+Shift+M start
    # (Show-ScalingPrompt), completely independent of what
    # CalibrateScreen1Auto.ps1 measured. That meant a mistyped or
    # left-over non-100 value here would make every click disagree with
    # the calibration preview, with nothing to indicate why. Confirmed
    # DPI-awareness already produces correct real-pixel coordinates
    # (single monitor, 100% Windows scaling), so this math is now
    # IDENTICAL to what CalibrateScreen1Auto.ps1's own preview computes.
    $clientX = [double]$Screen1Select.OriginX + ($targetColIndex * [double]$Screen1Select.CharWidthPx)
    $clientY = [double]$Screen1Select.OriginY + ($LineIndex * [double]$Screen1Select.CharHeightPx)

    $pt = New-Object POINT
    $pt.X = [int][math]::Round($clientX)
    $pt.Y = [int][math]::Round($clientY)
    [void][Win32]::ClientToScreen($Handle, [ref]$pt)
    return $pt
}

# Moves the real mouse cursor to a screen-coordinate point and performs
# a single left click there. Used instead of keyboard navigation because
# the REPOSITORY LIST screen expects a line-command letter typed
# directly into each row's own selection field, not a highlighted-item
# Enter/Down style list.
function Invoke-Screen1RowClick {
    param([System.Drawing.Point]$ScreenPoint)

    [void][Win32]::SetCursorPos($ScreenPoint.X, $ScreenPoint.Y)
    Start-Sleep -Milliseconds 20
    [Win32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # MOUSEEVENTF_LEFTDOWN
    Start-Sleep -Milliseconds 20
    [Win32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # MOUSEEVENTF_LEFTUP
}

function Invoke-PipelineScreen1Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $s1       = $pipeline.Screen1Select

    switch ($global:CR_PipelineState) {

        'CompScan_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0 -or $null -eq $s1.FirstDataRowLineIndex -or $null -eq $s1.SelectionColumnIndex) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run StartAutoClipCapture.bat Calibrate first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            # Fixed row slots - pure arithmetic, no Ctrl+C/clipboard
            # read needed at all to find them.
            $global:CR_PipelineScreen1Rows   = Get-Screen1FixedRows -Screen1Select $s1
            $global:CR_PipelineComponentIdx  = 0
            $global:CR_PipelineState = 'CompZoom_Action'
            $global:CR_ElapsedMs     = 0
        }

        'CompZoom_Action' {
            if ($null -eq $s1 -or [double]$s1.CharWidthPx -le 0 -or [double]$s1.CharHeightPx -le 0 -or $null -eq $s1.FirstDataRowLineIndex -or $null -eq $s1.SelectionColumnIndex) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select isn't calibrated yet - run StartAutoClipCapture.bat Calibrate first. Stopping." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NOT CALIBRATED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }

            $rowIdx = [int]$global:CR_PipelineComponentIdx
            $row = $global:CR_PipelineScreen1Rows[$rowIdx]
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)

            if (-not $global:CR_PipelineStepPending) {
                $wr = New-Object RECT
                [void][Win32]::GetWindowRect($global:CR_TargetHandle, [ref]$wr)
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Row $($rowIdx + 1): LineIndex=$($row.LineIndex) ColIndex=$($row.ColIndex) -> click ($($screenPt.X),$($screenPt.Y))  |  Screen1Select Origin=($($s1.OriginX),$($s1.OriginY)) CharSize=$($s1.CharWidthPx)x$($s1.CharHeightPx)  |  Target window bounds ($($wr.Left),$($wr.Top))-($($wr.Right),$($wr.Bottom))" -ForegroundColor DarkGray
                if ($screenPt.X -lt $wr.Left -or $screenPt.X -gt $wr.Right -or $screenPt.Y -lt $wr.Top -or $screenPt.Y -gt $wr.Bottom) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] WARNING: that click point is OUTSIDE the target window's bounds - Screen1Select needs recalibrating (StartAutoClipCapture.bat Calibrate)." -ForegroundColor Red
                }
            }

            # Shown BEFORE anything is clicked - the red circle marker
            # lands on $screenPt so a wrong target is obvious right
            # away, without a single click having happened yet.
            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - about to click here, type '$($s1.SelectionText)' + Enter"
            if (Request-PipelineStepConfirm -Description $desc -MarkerPoint $screenPt) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - selecting" ([System.Drawing.Color]::Lime)
            Invoke-Screen1RowClick -ScreenPoint $screenPt
            Start-Sleep -Milliseconds 20
            [System.Windows.Forms.SendKeys]::SendWait([string]$s1.SelectionText + '{ENTER}')

            $global:CR_PipelineState = 'CompZoom_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompZoom_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompZoom_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompZoom_Copy' {
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

                $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name

                if ($detected -eq 2) {
                    # Landed on Screen 2 (COMPONENT VERSION - SELECT).
                    # Hand off to Screen2.ps1 to log it and queue the
                    # single F3 back to Screen 1.
                    $global:CR_PipelineScreen1RetryCount   = 0
                    $global:CR_PipelineScreen2CapturedText = $text
                    $global:CR_PipelineState = 'EnvLog_Action'
                    $global:CR_ElapsedMs     = 0
                }
                elseif ($detected -eq 1) {
                    # Still on Screen 1 - this row's selection field
                    # didn't lead anywhere (blank row, or the item is
                    # unavailable). Nothing to go "back" from - just
                    # move on to the next row.
                    $global:CR_PipelineScreen1RetryCount = 0
                    $global:CR_PipelineState = 'CompNext_Action'
                    $global:CR_ElapsedMs     = 0
                }
                else {
                    # Unrecognized screen (e.g. the terminal hadn't
                    # finished redrawing yet). Retry the same row a few
                    # times before giving up on it, rather than either
                    # spinning forever or aborting the whole pipeline
                    # over one slow screen.
                    $global:CR_PipelineScreen1RetryCount++
                    $maxRetries = [int]$s1.MaxRowRetries
                    if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Row $($global:CR_PipelineComponentIdx + 1) on page $($global:CR_PipelineScreen1PageIdx + 1) gave an unrecognized screen $maxRetries time(s) in a row - skipping it." -ForegroundColor Yellow
                        $global:CR_PipelineScreen1RetryCount = 0
                        $global:CR_PipelineState = 'CompNext_Action'
                    } else {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unrecognized screen after selecting row $($global:CR_PipelineComponentIdx + 1) - retrying ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                        $global:CR_PipelineState = 'CompZoom_Action'
                    }
                    $global:CR_ElapsedMs = 0
                }
            }
        }

        'CompNext_Action' {
            $nextRow = [int]$global:CR_PipelineComponentIdx + 1
            if ($nextRow -lt $global:CR_PipelineScreen1Rows.Count) {
                $global:CR_PipelineComponentIdx = $nextRow
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            } else {
                # Every detected row on this page has been tried - page forward.
                $global:CR_PipelineState = 'CompPage_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompPage_Action' {
            if ([int]$global:CR_PipelineScreen1PageIdx + 1 -ge [int]$s1.MaxPages) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Reached the MaxPages safety limit ($($s1.MaxPages)) - stopping." -ForegroundColor Yellow
                Show-RelayResultOverlay -Text "STOPPED (page limit reached)" -Color ([System.Drawing.Color]::Gray)
                Stop-PipelineCapture
                return
            }

            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press $($s1.PageNextDisplay) to page forward"
            if (Request-PipelineStepConfirm -Description $desc) { return }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Paging to next screen ($($s1.PageNextDisplay))" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait([string]$s1.PageNextToken)
            $global:CR_PipelineState = 'CompPage_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompPage_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompPage_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompPage_Copy' {
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

                $isEndOfList = Test-RelayTextContains -Text $text -Needle ([string]$s1.EndOfListText)
                $isDuplicate = $false
                if (-not $isEndOfList -and $null -ne $global:CR_PipelineScreen1PrevPageText) {
                    $similarity = Get-TextSimilarity -A $global:CR_PipelineScreen1PrevPageText -B $text
                    $isDuplicate = ($similarity -ge [double]$s1.DupDetectThreshold)
                }

                if ($isEndOfList -or $isDuplicate) {
                    $reason = if ($isEndOfList) { "'$($s1.EndOfListText)' marker seen" } else { "next page matched the previous one - no new data" }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Done - $reason. Processed $($global:CR_PipelineScreen1PageIdx + 1) page(s)." -ForegroundColor Green
                    Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }

                # Text was only needed for the end-of-list/duplicate
                # check just above - row positions are the same fixed
                # slots on every page, so just rebuild them directly.
                $global:CR_PipelineScreen1PrevPageText = $text
                $global:CR_PipelineScreen1PageIdx++
                $global:CR_PipelineScreen1Rows   = Get-Screen1FixedRows -Screen1Select $s1
                $global:CR_PipelineComponentIdx  = 0
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            }
        }

        default {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unknown Screen1 state '$($global:CR_PipelineState)' - resetting." -ForegroundColor Yellow
            $global:CR_PipelineComponentIdx = 0
            $global:CR_PipelineState = 'CompScan_Action'
            $global:CR_ElapsedMs     = 0
        }
    }
}
#=====================================================================
# endregion: AutoClipCaptureSqlPipelineScreen1.ps1
#=====================================================================

#=====================================================================
# region: AutoClipCaptureSqlPipelineScreen2.ps1 - formerly its own file, now inlined here
#=====================================================================
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
#=====================================================================
# endregion: AutoClipCaptureSqlPipelineScreen2.ps1
#=====================================================================

#=====================================================================
# region: AutoClipCaptureSqlPipelineScreen3.ps1 - formerly its own file, now inlined here
#=====================================================================
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
#=====================================================================
# endregion: AutoClipCaptureSqlPipelineScreen3.ps1
#=====================================================================

#=====================================================================
# region: AutoClipCaptureSqlPipelineComponentList.ps1 - formerly its own file, now inlined here
#=====================================================================
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

            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press Ctrl+C to capture page 1"
            if (Request-PipelineStepConfirm -Description $desc) { return }

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
            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press the next-page key to capture page $($global:CR_PipelineListPageIdx + 1)"
            if (Request-PipelineStepConfirm -Description $desc) { return }

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
#=====================================================================
# endregion: AutoClipCaptureSqlPipelineComponentList.ps1
#=====================================================================

function Get-DefaultConfig {
    [pscustomobject]@{
        LogFile               = "CapturedOutput.txt"
        CopyDelayMs           = 150
        AfterActionKeyDelayMs = 150
        TimerTickMs           = 50
        SkipRowsStart         = 0
        SkipRowsEnd           = 0
        ActionKeyDisplay      = "F8"
        ActionKeyToken        = "{F8}"
        DupDetectEnabled      = $true
        DupDetectThreshold    = 0.995   # 99.5%
        ToggleHotkey          = [pscustomobject]@{ Modifiers = 3; Key = 0x43; Display = "Ctrl+Alt+C"; RequireRightModifier = $false }  # Ctrl+Alt+C
        ExitHotkey            = [pscustomobject]@{ Modifiers = 3; Key = 0x58; Display = "Ctrl+Alt+X"; RequireRightModifier = $false }  # Ctrl+Alt+X
        F3Hotkey              = [pscustomobject]@{ Modifiers = 5; Key = 0xBC; Display = "Alt+<"; RequireRightModifier = $false }     # Alt+Shift+Comma ('<') -> single F3 press
        PipelineStepConfirmEnabled = $true
        StepConfirmHotkey     = [pscustomobject]@{ Modifiers = 0; Key = 0x27; Display = "Right Arrow" }   # VK_RIGHT
        ResultOverlayDurationMs = 4000
        Modes                 = @( Get-DefaultSqlSearchMode )
        Pipelines             = @()
    }
}

# The default "scan mode" bound to Alt+>. Instead of the
# plain Toggle relay (Ctrl+Alt+C), this repeatedly presses F5, copies
# the screen, and looks for "EXEC SQL" - showing a big SQL FOUND / NO
# SQL FOUND banner once it knows the answer. UseFocusedWindow means it
# targets whatever window already has focus when the hotkey is
# pressed, instead of asking you to click/confirm a window first.
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

if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "AutoClipCaptureConfig.json is corrupt or unreadable - falling back to defaults." -ForegroundColor Yellow
        $Config = Get-DefaultConfig
    }
} else {
    $Config = Get-DefaultConfig
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Host "No config found - created a default AutoClipCaptureConfig.json." -ForegroundColor Yellow
}

# ---- Resolve settings from config (with fallbacks for older config files) ----
$DefaultLogFile = $Config.LogFile
if (-not [System.IO.Path]::IsPathRooted($DefaultLogFile)) {
    $DefaultLogFile = Join-Path $PSScriptRoot $DefaultLogFile
}
$LogDir             = Split-Path -Path $DefaultLogFile -Parent
$DefaultBaseName    = [System.IO.Path]::GetFileNameWithoutExtension($DefaultLogFile)

# The classic Toggle relay (Ctrl+Shift+P) always saves two copies of
# whatever it captures - a .txt copy under LogDir\txt and a .cbl copy
# under LogDir\cbl - regardless of what extension (if any) the person
# types into the filename prompt. Created up front so they exist even
# before the first capture starts.
$TxtDir = Join-Path $LogDir "txt"
$CblDir = Join-Path $LogDir "cbl"
foreach ($d in @($TxtDir, $CblDir)) {
    if (-not (Test-Path -Path $d)) {
        try {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        } catch {
            Write-Host "Could not create '$d': $_" -ForegroundColor Yellow
        }
    }
}

$CopyDelayMs = [int]$Config.CopyDelayMs
$TimerTickMs = [int]$Config.TimerTickMs

if ($Config.PSObject.Properties.Name -contains 'AfterActionKeyDelayMs') {
    $AfterActionKeyDelayMs = [int]$Config.AfterActionKeyDelayMs
} elseif ($Config.PSObject.Properties.Name -contains 'AfterF8DelayMs') {
    $AfterActionKeyDelayMs = [int]$Config.AfterF8DelayMs   # old config field name
} else {
    $AfterActionKeyDelayMs = 150
}

if ($Config.PSObject.Properties.Name -contains 'ActionKeyToken') {
    $ActionKeyToken   = [string]$Config.ActionKeyToken
    $ActionKeyDisplay = [string]$Config.ActionKeyDisplay
} else {
    $ActionKeyToken   = '{F8}'
    $ActionKeyDisplay = 'F8'
}

if ($Config.PSObject.Properties.Name -contains 'SkipRowsStart') {
    $SkipRowsStart = [int]$Config.SkipRowsStart
} else {
    $SkipRowsStart = 0
}
if ($Config.PSObject.Properties.Name -contains 'SkipRowsEnd') {
    $SkipRowsEnd = [int]$Config.SkipRowsEnd
} else {
    $SkipRowsEnd = 0
}

if ($Config.PSObject.Properties.Name -contains 'DupDetectEnabled') {
    $DupDetectEnabled = [bool]$Config.DupDetectEnabled
} else {
    $DupDetectEnabled = $true
}
if ($Config.PSObject.Properties.Name -contains 'DupDetectThreshold') {
    $DupDetectThreshold = [double]$Config.DupDetectThreshold
} else {
    $DupDetectThreshold = 0.995
}
if ($DupDetectThreshold -gt 1) { $DupDetectThreshold = $DupDetectThreshold / 100.0 }  # tolerate "99.5" as well as "0.995"

if ($Config.PSObject.Properties.Name -contains 'ResultOverlayDurationMs') {
    $ResultOverlayDurationMs = [int]$Config.ResultOverlayDurationMs
} else {
    $ResultOverlayDurationMs = 4000
}

# ---- Pipeline step-confirm mode: when enabled, a Pipeline (e.g.
# Ctrl+Shift+M) no longer sends its keystrokes/clicks automatically one
# after another. Instead, before each one it shows what it's about to
# do (and, for a Screen1 row click, exactly where via a red circle
# marker) and waits for StepConfirmHotkey (Right Arrow by default) to
# be pressed before actually doing it. Set PipelineStepConfirmEnabled
# to false in the config to go back to fully automatic. ----
if ($Config.PSObject.Properties.Name -contains 'PipelineStepConfirmEnabled') {
    $global:CR_StepConfirmEnabled = [bool]$Config.PipelineStepConfirmEnabled
} else {
    $global:CR_StepConfirmEnabled = $true
}

if ($Config.PSObject.Properties.Name -contains 'StepConfirmHotkey' -and $null -ne $Config.StepConfirmHotkey) {
    $StepConfirmModifiers = [int]$Config.StepConfirmHotkey.Modifiers
    $StepConfirmKey       = [int]$Config.StepConfirmHotkey.Key
    $StepConfirmDisplay   = [string]$Config.StepConfirmHotkey.Display
} else {
    $StepConfirmModifiers = 0
    $StepConfirmKey       = 0x27   # VK_RIGHT
    $StepConfirmDisplay   = 'Right Arrow'
}

# Older config files won't have a Modes array yet - fall back to the
# built-in SQL Search mode (Alt+>) so it's available by
# default even for configs created before Modes existed.
if ($Config.PSObject.Properties.Name -contains 'Modes' -and $null -ne $Config.Modes) {
    $ModeConfigs = @($Config.Modes)
} else {
    $ModeConfigs = @( Get-DefaultSqlSearchMode )
}

# Fill in fields that older config files (or modes added before this
# feature existed) won't have, so nothing throws on a missing property.
foreach ($m in $ModeConfigs) {
    if (-not ($m.PSObject.Properties.Name -contains 'UseFocusedWindow')) {
        $m | Add-Member -NotePropertyName UseFocusedWindow -NotePropertyValue $false -Force
    }
    if ($null -ne $m.Hotkey -and -not ($m.Hotkey.PSObject.Properties.Name -contains 'RequireRightModifier')) {
        $m.Hotkey | Add-Member -NotePropertyName RequireRightModifier -NotePropertyValue $false -Force
    }
}

# ---- Pipelines: multi-screen component/environment navigation runs.
# Older config files won't have a Pipelines array yet - default to none.
# Each pipeline's Component/Environment/Sql sub-objects are backfilled
# with sane defaults for any field an older/hand-edited entry omits, so
# nothing throws on a missing property. ----
if ($Config.PSObject.Properties.Name -contains 'Pipelines' -and $null -ne $Config.Pipelines) {
    $PipelineConfigs = @($Config.Pipelines)
} else {
    $PipelineConfigs = @()
}

function Add-PipelineLevelDefaults {
    param($Level, [int]$DefaultMaxItems)
    if ($null -eq $Level) { return $Level }
    $defaults = @{
        ZoomActionToken   = '{ENTER}'
        ZoomActionDisplay = 'Enter'
        NextActionToken   = '{DOWN}'
        NextActionDisplay = 'Down'
        UnavailableText   = 'unavailable'
        MaxItems          = $DefaultMaxItems
        LabelPattern      = '\(([A-Za-z]{2}[A-Za-z0-9]+)\)'
    }
    foreach ($key in $defaults.Keys) {
        if (-not ($Level.PSObject.Properties.Name -contains $key)) {
            $Level | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
        }
    }
    return $Level
}

# Same idea as Add-PipelineLevelDefaults, but for the ComponentList
# pre-pass block, which has its own set of fields (no ZoomActionToken/
# UnavailableText - it never opens anything, just pages through
# Screen 1). Enabled defaults to $false so a Pipeline entry from before
# this feature existed (or one that simply never mentions
# ComponentList) keeps starting straight at CompZoom_Action, unchanged.
function Add-PipelineComponentListDefaults {
    param($Pipeline)
    if ($null -eq $Pipeline) { return }

    $defaults = @{
        Enabled            = $false
        NextActionToken    = '{F8}'
        NextActionDisplay  = 'F8'
        SkipRowsStart      = 5
        SkipRowsEnd        = 3
        DupDetectThreshold = 0.995
        MaxPages           = 500
        OutputFileName     = 'pipeline_component_list.txt'
        EndOfListText      = 'Bottom of List'
    }

    if (-not ($Pipeline.PSObject.Properties.Name -contains 'ComponentList') -or $null -eq $Pipeline.ComponentList) {
        $Pipeline | Add-Member -NotePropertyName ComponentList -NotePropertyValue ([pscustomobject]$defaults) -Force
        return
    }

    $cl = $Pipeline.ComponentList
    foreach ($key in $defaults.Keys) {
        if (-not ($cl.PSObject.Properties.Name -contains $key)) {
            $cl | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
        }
    }
    if ($cl.DupDetectThreshold -gt 1) { $cl.DupDetectThreshold = $cl.DupDetectThreshold / 100.0 }  # tolerate "99.5" as well as "0.995"
}

# Screen1Select is the block CalibrateScreen1AutoGuided.ps1 fills in
# (OriginX/OriginY/CharWidthPx/CharHeightPx/ClickColumnOffset) and that
# AutoClipCaptureSqlPipelineScreen1.ps1 reads to click the "B" selection
# field on each row of Screen 1 (REPOSITORY LIST) before typing into it.
# OriginX/Y/CharWidthPx/CharHeightPx default to 0 - meaning "not
# calibrated yet" - so a fresh config doesn't throw, it just won't click
# in a useful spot until CalibrateScreen1AutoGuided.bat has been run.
function Add-PipelineScreen1SelectDefaults {
    param($Pipeline)
    if ($null -eq $Pipeline) { return }

    $defaults = @{
        OriginX            = 0
        OriginY            = 0
        CharWidthPx        = 0
        CharHeightPx       = 0
        ClickColumnOffset  = -2
        SelectionText      = 'B'
        RowsPerPage        = 25
        PageNextToken      = '{F8}'
        PageNextDisplay    = 'F8'
        EndOfListText      = 'Bottom of List'
        DupDetectThreshold = 0.995
        MaxPages           = 500
        MaxRowRetries      = 3
        LogScreen2Text     = $true
        OutputFileName     = 'pipeline_component_versions.txt'
        CalibrationNote    = 'Not calibrated yet - run StartAutoClipCapture.bat Calibrate (or CalibrateScreen1AutoGuided.bat, if you still use that one).'
    }

    if (-not ($Pipeline.PSObject.Properties.Name -contains 'Screen1Select') -or $null -eq $Pipeline.Screen1Select) {
        $Pipeline | Add-Member -NotePropertyName Screen1Select -NotePropertyValue ([pscustomobject]$defaults) -Force
        return
    }

    $s1 = $Pipeline.Screen1Select
    foreach ($key in $defaults.Keys) {
        if (-not ($s1.PSObject.Properties.Name -contains $key)) {
            $s1 | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
        }
    }
    if ($s1.DupDetectThreshold -gt 1) { $s1.DupDetectThreshold = $s1.DupDetectThreshold / 100.0 }  # tolerate "99.5" as well as "0.995"
}

foreach ($p in $PipelineConfigs) {
    if (-not ($p.PSObject.Properties.Name -contains 'UseFocusedWindow')) {
        $p | Add-Member -NotePropertyName UseFocusedWindow -NotePropertyValue $false -Force
    }
    if ($null -ne $p.Hotkey -and -not ($p.Hotkey.PSObject.Properties.Name -contains 'RequireRightModifier')) {
        $p.Hotkey | Add-Member -NotePropertyName RequireRightModifier -NotePropertyValue $false -Force
    }
    [void](Add-PipelineLevelDefaults -Level $p.Component -DefaultMaxItems 100)
    [void](Add-PipelineLevelDefaults -Level $p.Environment -DefaultMaxItems 20)
    if ($null -ne $p.Sql -and -not ($p.Sql.PSObject.Properties.Name -contains 'MaxIterations')) {
        $p.Sql | Add-Member -NotePropertyName MaxIterations -NotePropertyValue 500 -Force
    }
    Add-PipelineComponentListDefaults -Pipeline $p
    Add-PipelineScreen1SelectDefaults -Pipeline $p
}

$ToggleHotkeyId  = 1
$ToggleModifiers = [int]$Config.ToggleHotkey.Modifiers
$ToggleKey       = [int]$Config.ToggleHotkey.Key
$ToggleDisplay   = [string]$Config.ToggleHotkey.Display
$ToggleRequireRightModifier = ($Config.ToggleHotkey.PSObject.Properties.Name -contains 'RequireRightModifier') -and [bool]$Config.ToggleHotkey.RequireRightModifier

$ExitHotkeyId    = 2
$ExitModifiers   = [int]$Config.ExitHotkey.Modifiers
$ExitKey         = [int]$Config.ExitHotkey.Key
$ExitDisplay     = [string]$Config.ExitHotkey.Display
$ExitRequireRightModifier = ($Config.ExitHotkey.PSObject.Properties.Name -contains 'RequireRightModifier') -and [bool]$Config.ExitHotkey.RequireRightModifier

$StepConfirmHotkeyId = 4   # NOT registered at startup - only while a Pipeline is actively running (see Register-PipelineStepHotkey), so Right Arrow behaves normally everywhere else

$F3HotkeyId      = 3
if ($Config.PSObject.Properties.Name -contains 'F3Hotkey' -and $null -ne $Config.F3Hotkey) {
    $F3Modifiers = [int]$Config.F3Hotkey.Modifiers
    $F3Key       = [int]$Config.F3Hotkey.Key
    $F3Display   = [string]$Config.F3Hotkey.Display
    $F3RequireRightModifier = ($Config.F3Hotkey.PSObject.Properties.Name -contains 'RequireRightModifier') -and [bool]$Config.F3Hotkey.RequireRightModifier
} else {
    $f3Default   = (Get-DefaultConfig).F3Hotkey
    $F3Modifiers = [int]$f3Default.Modifiers
    $F3Key       = [int]$f3Default.Key
    $F3Display   = [string]$f3Default.Display
    $F3RequireRightModifier = [bool]$f3Default.RequireRightModifier
}
$F3ActionKeyToken = '{F3}'
# ----------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Native/custom types: window-focus helpers, the hidden hotkey host
# window, and the top-left status overlay window. All compiled in one
# block so they share the same assembly. ----
$formSource = @"
using System;
using System.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public static class Win32
{
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(System.Drawing.Point pt);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int MessageBoxW(IntPtr hWnd, string lpText, string lpCaption, uint uType);

    // ---- Mouse click support (used by the cobol-pipeline's Screen1
    // row-selection step: AutoClipCaptureSqlPipelineScreen1.ps1 clicks
    // the "B" selection field on a specific row before typing into it,
    // using the same client-coordinate math as
    // CalibrateScreen1AutoGuided.ps1/Screen1Select in the config). ----
    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, UIntPtr dwExtraInfo);

    // Used purely for diagnostics: lets the step-confirm gate print the
    // target window's actual on-screen bounds next to a computed click
    // point, so a click landing outside those bounds is obvious from
    // the console output, not just from the marker looking "off".
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

public struct POINT { public int X; public int Y; }

public class HotkeyForm : Form
{
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler<int> HotkeyPressed;

    private const int WM_HOTKEY = 0x0312;

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            int id = m.WParam.ToInt32();
            if (HotkeyPressed != null) HotkeyPressed(this, id);
        }
        base.WndProc(ref m);
    }
}

public class StatusOverlay : Form
{
    protected override bool ShowWithoutActivation
    {
        get { return true; }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            const int WS_EX_NOACTIVATE = 0x08000000;
            const int WS_EX_TOOLWINDOW = 0x00000080;
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
            return cp;
        }
    }
}
"@

Add-Type -TypeDefinition $formSource -ReferencedAssemblies "System.Windows.Forms", "System.Drawing"

# Must be set before ANY Windows Forms control is created on this thread
# (including the filename-prompt dialog and the hidden hotkey form below) -
# .NET throws "Thread exception mode cannot be changed once any Controls
# are created on the thread" if this runs any later. Defining the types
# above does not create any controls, so this can safely come after them.
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    Write-Host "[AutoClipCapture] Unhandled UI exception (recovered): $($e.Exception.Message)" -ForegroundColor Yellow
})

# Minimize this script's own console window. It sends Ctrl+C to whatever
# window currently has focus - if this console itself ever ends up
# focused (easy to do by accident, e.g. after an Alt-Tab), that Ctrl+C
# goes to PowerShell instead of your target app, which makes PowerShell
# abort the running pipeline ("The pipeline has been stopped."). Keeping
# this window minimized makes that far less likely to happen.
try {
    $consoleHandle = (Get-Process -Id $PID).MainWindowHandle
    if ($consoleHandle -ne [IntPtr]::Zero) {
        [Win32]::ShowWindowAsync($consoleHandle, 6) | Out-Null  # 6 = SW_MINIMIZE
    }
} catch {
    # Non-critical - if this fails for any reason, just carry on.
}

function Get-SafeFileName {
    param([string]$Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('_') } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# Drops the first $SkipStart and last $SkipEnd rows from one captured
# clipboard chunk before it's written to the log. Used to strip off
# headers/footers that a target app includes with every Ctrl+C (e.g.
# a column header row and a totals row). Returns '' when there aren't
# enough rows left after skipping - the caller should then write
# nothing for that cycle rather than an empty line.
function Get-FilteredCaptureText {
    param(
        [string]$Text,
        [int]$SkipStart,
        [int]$SkipEnd
    )

    if ($SkipStart -le 0 -and $SkipEnd -le 0) { return $Text }
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Split on any line-ending style so this works regardless of what
    # the source app puts on the clipboard.
    $lines = $Text -split "`r`n|`r|`n"

    # A trailing empty element shows up when the text ends with a line
    # break - drop it so it isn't counted as an extra "row".
    if ($lines.Length -gt 1 -and $lines[$lines.Length - 1] -eq '') {
        $lines = $lines[0..($lines.Length - 2)]
    }

    $total = $lines.Length
    $start = [Math]::Max(0, $SkipStart)
    $end   = [Math]::Max(0, $SkipEnd)

    if ($start + $end -ge $total) { return '' }

    $keep = $lines[$start..($total - $end - 1)]
    return ($keep -join [Environment]::NewLine)
}

# Compares two captured text blocks and returns how much they overlap, as
# a fraction from 0.0 (nothing in common) to 1.0 (identical). Works line
# by line (matching the row-oriented nature of the row-skip feature above)
# using a multiset intersection, so it stays accurate even if a couple of
# rows shifted position between captures, and stays fast regardless of
# capture size. Used to detect a capture loop that's stuck copying the
# same content over and over (e.g. the target app reached the end of its
# data and stopped producing anything new).
function Get-TextSimilarity {
    param(
        [string]$A,
        [string]$B
    )

    if ([string]::IsNullOrEmpty($A) -and [string]::IsNullOrEmpty($B)) { return 1.0 }
    if ([string]::IsNullOrEmpty($A) -or [string]::IsNullOrEmpty($B)) { return 0.0 }
    if ($A -eq $B) { return 1.0 }

    $linesA = $A -split "`r`n|`r|`n"
    $linesB = $B -split "`r`n|`r|`n"

    $countA = @{}
    foreach ($l in $linesA) {
        if ($countA.ContainsKey($l)) { $countA[$l]++ } else { $countA[$l] = 1 }
    }

    $matched = 0
    foreach ($l in $linesB) {
        if ($countA.ContainsKey($l) -and $countA[$l] -gt 0) {
            $countA[$l]--
            $matched++
        }
    }

    $totalMax = [Math]::Max($linesA.Length, $linesB.Length)
    if ($totalMax -eq 0) { return 1.0 }
    return [double]$matched / [double]$totalMax
}

# Small modal prompt shown each time a capture session is started.
# Returns the trimmed filename the user typed, or $null if cancelled.
function Show-FilenamePrompt {
    param(
        [string]$DefaultName,
        [string]$TargetTitle
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Start Capture"
    # ClientSize (not Size) so the title bar/border chrome doesn't eat
    # into the usable area - that was clipping the bottom of the Start
    # Capture/Cancel buttons.
    $dlg.ClientSize      = New-Object System.Drawing.Size(370, 140)
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.TopMost         = $true

    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = "Target window: $TargetTitle"
    $lblTarget.Location = New-Object System.Drawing.Point(15, 12)
    $lblTarget.Size = New-Object System.Drawing.Size(340, 18)
    $lblTarget.Font = New-Object System.Drawing.Font($lblTarget.Font, [System.Drawing.FontStyle]::Italic)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Enter a filename for this capture (saved as .txt and .cbl):"
    $lbl.Location = New-Object System.Drawing.Point(15, 38)
    $lbl.Size = New-Object System.Drawing.Size(340, 20)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 62)
    $txt.Size = New-Object System.Drawing.Size(335, 22)
    $txt.Text = $DefaultName
    $txt.SelectAll()

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Start Capture"
    $btnOk.Location = New-Object System.Drawing.Point(170, 98)
    $btnOk.Size = New-Object System.Drawing.Size(115, 28)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(290, 98)
    $btnCancel.Size = New-Object System.Drawing.Size(70, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.AddRange(@($lblTarget, $lbl, $txt, $btnOk, $btnCancel))
    $dlg.Add_Shown({ $txt.Focus(); $txt.SelectAll() })

    $result = $dlg.ShowDialog()
    $dlg.Dispose()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

    $name = $txt.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    return $name
}

# Invisible/off-screen host window - only needed so Windows has something
# to deliver the WM_HOTKEY messages to.
$form = New-Object HotkeyForm
$form.ShowInTaskbar   = $false
$form.FormBorderStyle = 'FixedToolWindow'
$form.StartPosition   = 'Manual'
$form.Location        = New-Object System.Drawing.Point(-2000, -2000)
$form.Size            = New-Object System.Drawing.Size(1, 1)
$form.Opacity         = 0

# Save the handle now, while the form is alive - Application.Exit() closes
# and disposes the form before the cleanup code below runs, so re-reading
# $form.Handle at that point no longer returns a valid IntPtr.
$FormHandle = $form.Handle

if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $ToggleHotkeyId, $ToggleModifiers, $ToggleKey)) {
    Write-Host "Failed to register the TOGGLE hotkey ($ToggleDisplay). It may already be in use by another app." -ForegroundColor Red
}
if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $ExitHotkeyId, $ExitModifiers, $ExitKey)) {
    Write-Host "Failed to register the EXIT hotkey ($ExitDisplay). It may already be in use by another app." -ForegroundColor Red
}
if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $F3HotkeyId, $F3Modifiers, $F3Key)) {
    Write-Host "Failed to register the F3 hotkey ($F3Display). It may already be in use by another app." -ForegroundColor Red
}

# ---- Register one global hotkey per enabled Mode. IDs start at 100 so
# they never collide with ToggleHotkeyId(1)/ExitHotkeyId(2), or with
# each other, regardless of how many modes exist. $ModeHotkeyMap maps
# hotkey id -> the mode's config object, for the hotkey handler below. ----
$ModeHotkeyMap  = @{}
$ModeHotkeyBase = 100
$modeIndex = 0
foreach ($m in $ModeConfigs) {
    $modeIndex++
    if (-not $m.Enabled) { continue }
    if ($null -eq $m.Hotkey -or $null -eq $m.Hotkey.Key -or [int]$m.Hotkey.Key -eq 0) {
        Write-Host "Mode '$($m.Name)' has no hotkey assigned - skipping." -ForegroundColor Yellow
        continue
    }
    $hkId  = $ModeHotkeyBase + $modeIndex
    $mMods = [int]$m.Hotkey.Modifiers
    $mKey  = [int]$m.Hotkey.Key
    if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $hkId, $mMods, $mKey)) {
        Write-Host "Failed to register the hotkey for mode '$($m.Name)' ($($m.Hotkey.Display)). It may already be in use." -ForegroundColor Red
        continue
    }
    $ModeHotkeyMap[$hkId] = $m
}

# ---- Register one global hotkey per enabled Pipeline. IDs start well
# clear of the Mode range above so the two never collide regardless of
# how many of either exist. $PipelineHotkeyMap maps hotkey id -> the
# pipeline's config object, for the hotkey handler below. ----
$PipelineHotkeyMap  = @{}
$PipelineHotkeyBase = 5000
$pipelineIndex = 0
foreach ($p in $PipelineConfigs) {
    $pipelineIndex++
    if (-not $p.Enabled) { continue }
    if ($null -eq $p.Hotkey -or $null -eq $p.Hotkey.Key -or [int]$p.Hotkey.Key -eq 0) {
        Write-Host "Pipeline '$($p.Name)' has no hotkey assigned - skipping." -ForegroundColor Yellow
        continue
    }
    $hkId  = $PipelineHotkeyBase + $pipelineIndex
    $pMods = [int]$p.Hotkey.Modifiers
    $pKey  = [int]$p.Hotkey.Key
    if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $hkId, $pMods, $pKey)) {
        Write-Host "Failed to register the hotkey for pipeline '$($p.Name)' ($($p.Hotkey.Display)). It may already be in use." -ForegroundColor Red
        continue
    }
    $PipelineHotkeyMap[$hkId] = $p
}

# True only when Screen1Select has real (non-zero) pixel geometry -
# i.e. CalibrateScreen1Auto.ps1/CalibrateScreen1AutoGuided.ps1 has
# actually been run for this pipeline, not just the placeholder
# 0/0/0/0 a fresh config ships with. Defined here (before the startup
# flagging loop just below, and well before the Ctrl+Shift+M handler
# further down) since both call it.
function Test-Screen1Calibrated {
    param($Screen1Select)
    return ($null -ne $Screen1Select -and [double]$Screen1Select.CharWidthPx -gt 0 -and [double]$Screen1Select.CharHeightPx -gt 0 -and $null -ne $Screen1Select.FirstDataRowLineIndex -and $null -ne $Screen1Select.SelectionColumnIndex)
}

# ---- Top-left status overlay: a tiny always-on-top banner that never
# steals keyboard focus (StatusOverlay overrides ShowWithoutActivation
# and adds WS_EX_NOACTIVATE), so showing/updating it never interrupts
# whatever window the automation is currently sending keys to. ----
$statusForm = New-Object StatusOverlay
$statusForm.FormBorderStyle = 'None'
$statusForm.StartPosition   = 'Manual'
$statusForm.ShowInTaskbar   = $false
$statusForm.TopMost         = $true
$statusForm.BackColor       = [System.Drawing.Color]::Black
$statusForm.Opacity         = 0.85
$statusForm.Size            = New-Object System.Drawing.Size(760, 64)

$screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$statusForm.Location = New-Object System.Drawing.Point(($screenArea.Left + 8), ($screenArea.Top + 8))

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock      = 'Fill'
$statusLabel.Padding   = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$statusLabel.AutoSize  = $false
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.ForeColor = [System.Drawing.Color]::Lime
$statusLabel.Font      = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$statusLabel.Text      = ''
$statusForm.Controls.Add($statusLabel)

# Force the overlay's handle to exist now (so Select-TargetWindow can
# compare clicked windows against it) without actually showing it yet.
[void]$statusForm.Handle
$statusForm.Hide()

function Set-RelayStatus {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Lime
    )
    $statusLabel.ForeColor = $Color
    $statusLabel.Text      = $Text
    if (-not $statusForm.Visible) { $statusForm.Show() }
}

function Hide-RelayStatus {
    $statusForm.Hide()
}

# ---- Big centered "result" banner used by scan Modes to announce their
# outcome (e.g. "SQL FOUND" / "NO SQL FOUND"). Reuses the same
# non-activating StatusOverlay window type as the corner status banner
# above, just bigger, centered, and auto-hiding after
# $ResultOverlayDurationMs (0 = stays until the next action starts). ----
$resultOverlay = New-Object StatusOverlay
$resultOverlay.FormBorderStyle = 'None'
$resultOverlay.StartPosition   = 'Manual'
$resultOverlay.ShowInTaskbar   = $false
$resultOverlay.TopMost         = $true
$resultOverlay.Opacity         = 0.92
$resultOverlay.Size            = New-Object System.Drawing.Size(520, 160)

$resultLabel = New-Object System.Windows.Forms.Label
$resultLabel.Dock      = 'Fill'
$resultLabel.TextAlign = 'MiddleCenter'
$resultLabel.ForeColor = [System.Drawing.Color]::White
$resultLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)
$resultLabel.Text      = ''
$resultOverlay.Controls.Add($resultLabel)

[void]$resultOverlay.Handle
$resultOverlay.Hide()

$resultHideTimer = New-Object System.Windows.Forms.Timer
$resultHideTimer.Add_Tick({
    $resultHideTimer.Stop()
    $resultOverlay.Hide()
})

function Show-RelayResultOverlay {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::LimeGreen,
        [int]$DurationMs = $ResultOverlayDurationMs
    )
    $resultHideTimer.Stop()
    $resultOverlay.BackColor = $Color
    $resultLabel.Text        = $Text

    $screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $screenArea.Left + [int](($screenArea.Width  - $resultOverlay.Width)  / 2)
    $y = $screenArea.Top  + [int](($screenArea.Height - $resultOverlay.Height) / 2)
    $resultOverlay.Location = New-Object System.Drawing.Point($x, $y)

    $resultOverlay.Show()
    $resultOverlay.BringToFront()

    if ($DurationMs -gt 0) {
        $resultHideTimer.Interval = $DurationMs
        $resultHideTimer.Start()
    }
}

function Hide-RelayResultOverlay {
    $resultHideTimer.Stop()
    $resultOverlay.Hide()
}

# ---- Small red-circle marker used by the pipeline step-confirm gate
# below to show exactly where a Screen1 row click is about to land,
# BEFORE the click actually happens. Same non-activating StatusOverlay
# window type as the status banner/result overlay above, so showing it
# never steals focus away from the target window. ----
$stepMarker = New-Object StatusOverlay
$stepMarker.FormBorderStyle = 'None'
$stepMarker.StartPosition   = 'Manual'
$stepMarker.ShowInTaskbar   = $false
$stepMarker.TopMost         = $true
$stepMarker.Size            = New-Object System.Drawing.Size(46, 46)
$stepMarker.BackColor       = [System.Drawing.Color]::Magenta
$stepMarker.TransparencyKey = [System.Drawing.Color]::Magenta
$stepMarker.Add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 4)
    $e.Graphics.DrawEllipse($pen, 3, 3, 39, 39)
    $pen.Dispose()
})

[void]$stepMarker.Handle
$stepMarker.Hide()

function Show-StepMarker {
    param([System.Drawing.Point]$ScreenPoint)
    $stepMarker.Location = New-Object System.Drawing.Point(($ScreenPoint.X - 23), ($ScreenPoint.Y - 23))
    if (-not $stepMarker.Visible) { $stepMarker.Show() }
    $stepMarker.Invalidate()
    $stepMarker.BringToFront()
}

function Hide-StepMarker {
    $stepMarker.Hide()
}

# ---- Registers/unregisters the step-confirm hotkey (Right Arrow by
# default) ONLY while a Pipeline is actually running. It is never
# registered at startup like Toggle/Exit/F3 are, so it never swallows
# Right Arrow presses in other applications the rest of the time. ----
function Register-PipelineStepHotkey {
    if (-not $global:CR_StepConfirmEnabled) { return }
    if ($global:CR_StepHotkeyRegistered) { return }
    if ([HotkeyForm]::RegisterHotKey($FormHandle, $StepConfirmHotkeyId, $StepConfirmModifiers, $StepConfirmKey)) {
        $global:CR_StepHotkeyRegistered = $true
    } else {
        Write-Host "[AutoClipCapture] Could not register the step-confirm hotkey ($StepConfirmDisplay) - it may already be in use elsewhere. The pipeline will stall waiting for it; disable PipelineStepConfirmEnabled in the config or free up that key." -ForegroundColor Red
    }
}

function Unregister-PipelineStepHotkey {
    if (-not $global:CR_StepHotkeyRegistered) { return }
    [void][HotkeyForm]::UnregisterHotKey($FormHandle, $StepConfirmHotkeyId)
    $global:CR_StepHotkeyRegistered = $false
}

# ---- The step-confirm gate itself. Call this at the very top of any
# pipeline state that is about to send real input (a keystroke or a
# mouse click), right after computing exactly what that input will be
# (including, if it's a click, the exact screen point). Returns $true
# if the caller should stop and return without doing anything yet
# (still waiting on the user), or $false once it's fine to go ahead -
# either because step-confirm is switched off, or because the pending
# step was just confirmed via the Right Arrow hotkey.
#
# $Description is shown in the corner status banner in place of the
# usual "doing X" text, with a "[<key> to continue]" suffix appended.
# $MarkerPoint (optional) additionally shows the red-circle marker at
# that screen point for as long as the step is pending, so a wrong
# click target is obvious before anything is actually clicked. ----
function Request-PipelineStepConfirm {
    param(
        [string]$Description,
        [System.Drawing.Point]$MarkerPoint
    )

    if (-not $global:CR_StepConfirmEnabled) { return $false }

    if ($global:CR_PipelineStepConfirmed) {
        # Right Arrow was pressed for this pending step - consume it
        # and let the caller proceed with the actual input now.
        $global:CR_PipelineStepConfirmed   = $false
        $global:CR_PipelineStepPending     = $false
        $global:CR_PipelineStepDescription = ''
        Hide-StepMarker
        return $false
    }

    if (-not $global:CR_PipelineStepPending) {
        $global:CR_PipelineStepPending     = $true
        $global:CR_PipelineStepDescription = $Description
        Set-RelayStatus "$Description   [$StepConfirmDisplay to continue]" ([System.Drawing.Color]::Yellow)
        if ($PSBoundParameters.ContainsKey('MarkerPoint')) {
            Show-StepMarker -ScreenPoint $MarkerPoint
        } else {
            Hide-StepMarker
        }
    }
    return $true
}

# Case-insensitive "does Text contain Needle" check used by Mode
# evaluation. Plain substring search (not -like/-match), so a needle
# that itself contains wildcard-ish characters like * still matches the
# literal text rather than being treated as a wildcard pattern.
function Test-RelayTextContains {
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return $false }
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return ($Text.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# ---- Component/SQL tracking (component_sql_check.md) ----
#
# The captured text for a scan Mode is expected to have a line near the
# top starting with "BROWSE", containing a component identifier in
# parentheses - e.g. "BROWSE (AB12C) Some Screen Title". The identifier
# always starts with 2 letters, followed by a mix of letters/numbers.
# This pulls that identifier out so the result (SQL found / not found)
# can be recorded against it.
function Get-ComponentIdFromText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }

    foreach ($line in ($Text -split "`r`n|`r|`n")) {
        if ($line.TrimStart().StartsWith("BROWSE", [StringComparison]::OrdinalIgnoreCase)) {
            $m = [System.Text.RegularExpressions.Regex]::Match($line, '\(([A-Za-z]{2}[A-Za-z0-9]+)\)')
            if ($m.Success) {
                return $m.Groups[1].Value
            }
        }
    }
    return $null
}

# Generic version of the above used by Pipelines: searches the whole
# captured text (not just a "BROWSE" line) for the first match of a
# configurable regex Pattern, and falls back to a positional label
# (e.g. "Component 3") when nothing matches - so a pipeline still
# produces a usable results table even on a screen whose text doesn't
# match the pattern.
function Get-PipelineItemLabel {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$FallbackLabel
    )
    if (-not [string]::IsNullOrWhiteSpace($Pattern) -and -not [string]::IsNullOrEmpty($Text)) {
        try {
            $m = [System.Text.RegularExpressions.Regex]::Match($Text, $Pattern)
            if ($m.Success) {
                if ($m.Groups.Count -gt 1) { return $m.Groups[1].Value }
                return $m.Value
            }
        } catch {
            # Bad/unsupported regex in config - fall through to the
            # positional fallback rather than crashing the pipeline.
        }
    }
    return $FallbackLabel
}

# ---- Screen tracking ----
#
# Each of the 3 pipeline screens has its own fingerprint in the
# captured text, independent of which state the pipeline *thinks*
# it's in:
#   Screen 1 (overview)    -> "REPOSITORY LIST" near the top
#   Screen 2 (environment) -> "COMPONENT VERSION" near the top
#   Screen 3 (COBOL code)  -> neither of the above, but has both
#                             "BROWSE" and "Menu" on the first page
# Returns 1, 2, 3, or 0 for text that matches none of them - a popup,
# an error, a logout screen, or anything else unrecognized.
function Get-PipelineScreenNumber {
    param([string]$Text)

    if (Test-RelayTextContains -Text $Text -Needle 'REPOSITORY LIST')   { return 1 }
    if (Test-RelayTextContains -Text $Text -Needle 'COMPONENT VERSION') { return 2 }
    if ((Test-RelayTextContains -Text $Text -Needle 'BROWSE') -and (Test-RelayTextContains -Text $Text -Needle 'Menu')) {
        return 3
    }
    return 0
}

# Detects the screen from freshly-captured text, compares it against
# $global:CR_PipelineCurrentScreen (what we were on a moment ago),
# logs whether we progressed, went back, stayed put, or landed
# somewhere unrecognized, then updates the tracked value and returns
# the detected screen number. Called at every clipboard capture point
# across all 3 screen files, so the console always shows the real,
# independently-verified screen - not just what the state machine
# assumed would happen.
function Update-PipelineScreenTracking {
    param(
        [string]$Text,
        [string]$PipelineName
    )

    $detected = Get-PipelineScreenNumber -Text $Text
    $previous = $global:CR_PipelineCurrentScreen

    if ($detected -eq 0) {
        Write-Host "[AutoClipCapture] [$PipelineName] Screen check: unrecognized screen (was screen $previous)." -ForegroundColor Yellow
    } elseif ($previous -eq 0) {
        Write-Host "[AutoClipCapture] [$PipelineName] Screen check: now on screen $detected." -ForegroundColor DarkCyan
    } elseif ($detected -eq $previous) {
        Write-Host "[AutoClipCapture] [$PipelineName] Screen check: stayed on screen $detected." -ForegroundColor DarkCyan
    } elseif ($detected -gt $previous) {
        Write-Host "[AutoClipCapture] [$PipelineName] Screen check: progressed from screen $previous to screen $detected." -ForegroundColor DarkCyan
    } else {
        Write-Host "[AutoClipCapture] [$PipelineName] Screen check: went back from screen $previous to screen $detected." -ForegroundColor DarkCyan
    }

    $global:CR_PipelineCurrentScreen = $detected
    return $detected
}

# Records one component's SQL-found result into a growing Markdown
# table at component_sql_check.md (same folder as the configured log
# file). If the component already has a row, that row is updated in
# place rather than duplicated - so re-running the check on the same
# page later just refreshes its Y/N instead of adding a second entry.
# Brand-new components get appended, which is how the table grows over
# time as more pages get scanned.
function Update-ComponentSqlCheckFile {
    param(
        [string]$Text,
        [bool]$SqlFound
    )

    $component = Get-ComponentIdFromText -Text $Text
    if ([string]::IsNullOrWhiteSpace($component)) {
        Write-Host "[AutoClipCapture] Component/SQL tracking: no 'BROWSE (...)' line found - skipping record." -ForegroundColor Yellow
        return
    }

    $mark = if ($SqlFound) { 'Y' } else { 'N' }
    $headerLine1 = '| Component | SQL |'
    $headerLine2 = '|-----------|-----|'
    $filePath = Join-Path $LogDir "component_sql_check.md"

    try {
        if (-not (Test-Path $filePath)) {
            @($headerLine1, $headerLine2, "| $component | $mark |") |
                Set-Content -Path $filePath -Encoding UTF8
            Write-Host "[AutoClipCapture] component_sql_check.md created - added '$component' = $mark." -ForegroundColor Cyan
            return
        }

        $lines = @(Get-Content -Path $filePath -Encoding UTF8)
        if ($lines.Count -lt 2 -or $lines[0] -notmatch '^\|\s*Component\b') {
            # File exists but doesn't look like our table (missing/odd
            # header) - rebuild the header and keep any existing rows.
            $dataRows = @($lines | Where-Object { $_ -match '^\|.*\|.*\|\s*$' -and $_ -ne $headerLine1 -and $_ -ne $headerLine2 })
            $lines = @($headerLine1, $headerLine2) + $dataRows
        }

        $updated = $false
        for ($i = 2; $i -lt $lines.Count; $i++) {
            $cells = $lines[$i].Trim().Trim('|') -split '\|'
            if ($cells.Count -ge 1 -and $cells[0].Trim() -eq $component) {
                $lines[$i] = "| $component | $mark |"
                $updated = $true
                break
            }
        }

        if (-not $updated) {
            $lines += "| $component | $mark |"
        }

        Set-Content -Path $filePath -Value $lines -Encoding UTF8
        $verb = if ($updated) { 'updated' } else { 'added' }
        Write-Host "[AutoClipCapture] component_sql_check.md $verb - '$component' = $mark." -ForegroundColor Cyan
    } catch {
        Write-Host "[AutoClipCapture] Failed to update component_sql_check.md: $_" -ForegroundColor Red
    }
}

# Windows' RegisterHotKey doesn't distinguish left/right modifier keys -
# e.g. Ctrl+Delete fires the same whether it's the left or right Ctrl
# held down. For any hotkey flagged "right-side only" in the config,
# this checks - at the moment the hotkey fires - whether the
# RIGHT-hand variant of every modifier bit set in $Modifiers is actually
# the one currently held, so (for example) a left-Ctrl combo press is
# ignored. Off by default for SQL Search and F3 now that they're
# Alt+Shift combos, where either side works fine.
function Test-RightModifierSatisfied {
    param(
        [int]$Modifiers,
        [bool]$RequireRight
    )
    if (-not $RequireRight) { return $true }

    $VK_RSHIFT   = 0xA1
    $VK_RMENU    = 0xA5
    $VK_RCONTROL = 0xA3

    if (($Modifiers -band 0x0002) -ne 0 -and (([Win32]::GetAsyncKeyState($VK_RCONTROL) -band 0x8000) -eq 0)) { return $false }
    if (($Modifiers -band 0x0001) -ne 0 -and (([Win32]::GetAsyncKeyState($VK_RMENU)    -band 0x8000) -eq 0)) { return $false }
    if (($Modifiers -band 0x0004) -ne 0 -and (([Win32]::GetAsyncKeyState($VK_RSHIFT)   -band 0x8000) -eq 0)) { return $false }
    return $true
}

# ---- Window picking: user clicks a window, we identify it, then a
# Yes/No dialog (Enter = Yes) confirms it before anything starts. ----
function Select-TargetWindow {
    Set-RelayStatus "Click the target window... (Esc to cancel)" ([System.Drawing.Color]::Yellow)
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Cross

    $VK_LBUTTON = 0x01
    $VK_ESCAPE  = 0x1B
    $picked     = [IntPtr]::Zero

    while ($true) {
        Start-Sleep -Milliseconds 15
        [System.Windows.Forms.Application]::DoEvents()

        if (([Win32]::GetAsyncKeyState($VK_ESCAPE) -band 0x8000) -ne 0) {
            $picked = [IntPtr]::Zero
            break
        }

        if (([Win32]::GetAsyncKeyState($VK_LBUTTON) -band 0x8000) -ne 0) {
            $pt   = [System.Windows.Forms.Cursor]::Position
            $hwnd = [Win32]::WindowFromPoint($pt)
            $root = [Win32]::GetAncestor($hwnd, [uint32]2)   # GA_ROOT

            # Wait for the click to release before deciding anything, so
            # only one deliberate click is ever consumed here.
            while (([Win32]::GetAsyncKeyState($VK_LBUTTON) -band 0x8000) -ne 0) {
                Start-Sleep -Milliseconds 10
                [System.Windows.Forms.Application]::DoEvents()
            }

            if ($root -eq [IntPtr]::Zero -or $root -eq $statusForm.Handle) {
                continue   # clicked on our own overlay or nothing useful - keep waiting
            }
            $picked = $root
            break
        }
    }

    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default

    if ($picked -eq [IntPtr]::Zero) { return $null }

    $sb = New-Object System.Text.StringBuilder 256
    [void][Win32]::GetWindowText($picked, $sb, $sb.Capacity)
    $title = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($title)) { $title = "(untitled window)" }

    return [pscustomobject]@{ Handle = $picked; Title = $title }
}

function Confirm-TargetWindow {
    param([string]$Title)
    $msg = "Target window identified:`n`n$Title`n`nIs this correct?"

    # Using the raw Win32 MessageBoxW (instead of
    # [System.Windows.Forms.MessageBox]::Show) so we can pass
    # MB_SETFOREGROUND/MB_TOPMOST - this is what's triggered from a
    # global hotkey handler, so there is no already-focused WinForms
    # window to make it foreground/active. Without these flags the box
    # can appear behind or without keyboard focus, forcing a mouse click
    # instead of just pressing Enter for the (still) default Yes button.
    $MB_YESNO         = 0x00000004
    $MB_ICONQUESTION  = 0x00000020
    $MB_DEFBUTTON1    = 0x00000000
    $MB_TOPMOST       = 0x00040000
    $MB_SETFOREGROUND = 0x00010000
    $flags = $MB_YESNO -bor $MB_ICONQUESTION -bor $MB_DEFBUTTON1 -bor $MB_TOPMOST -bor $MB_SETFOREGROUND

    $IDYES = 6
    $result = [Win32]::MessageBoxW([IntPtr]::Zero, $msg, "Confirm Target Window", [uint32]$flags)
    return ($result -eq $IDYES)
}

# Asks (Yes/No) whether to launch calibration right now for a pipeline
# whose Screen1Select isn't calibrated yet. Same MessageBoxW pattern as
# Confirm-TargetWindow, for the same reason - this fires from the
# Ctrl+Shift+M global hotkey handler, so there's no already-focused
# WinForms window to make foreground/topmost on its own.
function Show-Screen1CalibrationPrompt {
    param([string]$PipelineName)
    $msg = "'$PipelineName' isn't calibrated yet (Screen1Select has no pixel geometry).`n`nRun calibration now?`n`nYes = launch the calibration tool now.`nNo  = skip and try to start anyway (it will stop immediately if it's really not calibrated)."

    $MB_YESNO         = 0x00000004
    $MB_ICONQUESTION  = 0x00000020
    $MB_DEFBUTTON1    = 0x00000000
    $MB_TOPMOST       = 0x00040000
    $MB_SETFOREGROUND = 0x00010000
    $flags = $MB_YESNO -bor $MB_ICONQUESTION -bor $MB_DEFBUTTON1 -bor $MB_TOPMOST -bor $MB_SETFOREGROUND

    $IDYES = 6
    $result = [Win32]::MessageBoxW([IntPtr]::Zero, $msg, "Screen1 Not Calibrated", [uint32]$flags)
    return ($result -eq $IDYES)
}

# Runs CalibrateScreen1Auto.ps1 to completion (blocking - waits for the
# user to accept/cancel it), then re-reads AutoClipCaptureConfig.json
# and copies the fresh OriginX/OriginY/CharWidthPx/CharHeightPx/
# ClickColumnOffset/FirstDataRowLineIndex/SelectionColumnIndex/
# CalibrationNote onto the *existing* in-memory $Pipeline.Screen1Select
# object (matched by pipeline Id) rather than replacing $Pipeline
# itself - $PipelineHotkeyMap and $global:CR_ActivePipelineConfig hold
# references to that same object, so calibration takes effect
# immediately without restarting AutoClipCapture.ps1.
function Invoke-Screen1CalibrationNow {
    param($Pipeline)

    $selfScript = $PSCommandPath
    if ([string]::IsNullOrEmpty($selfScript) -or -not (Test-Path $selfScript)) {
        Write-Host "[AutoClipCapture] Can't determine this script's own file path to relaunch for calibration." -ForegroundColor Red
        return
    }

    Start-Process -FilePath "powershell.exe" `
        -ArgumentList @('-STA','-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-File', "`"$selfScript`"", '-Calibrate') `
        -Wait

    if (-not (Test-Path $ConfigPath)) { return }
    try {
        $freshConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "[AutoClipCapture] Couldn't re-read AutoClipCaptureConfig.json after calibration: $_" -ForegroundColor Yellow
        return
    }

    $freshPipeline = $freshConfig.Pipelines | Where-Object { $_.Id -eq $Pipeline.Id } | Select-Object -First 1
    if ($null -eq $freshPipeline -or $null -eq $freshPipeline.Screen1Select -or $null -eq $Pipeline.Screen1Select) { return }

    $Pipeline.Screen1Select.OriginX          = $freshPipeline.Screen1Select.OriginX
    $Pipeline.Screen1Select.OriginY          = $freshPipeline.Screen1Select.OriginY
    $Pipeline.Screen1Select.CharWidthPx      = $freshPipeline.Screen1Select.CharWidthPx
    $Pipeline.Screen1Select.CharHeightPx     = $freshPipeline.Screen1Select.CharHeightPx
    $Pipeline.Screen1Select.ClickColumnOffset = $freshPipeline.Screen1Select.ClickColumnOffset
    foreach ($fieldName in @('CalibrationNote', 'FirstDataRowLineIndex', 'SelectionColumnIndex')) {
        if ($Pipeline.Screen1Select.PSObject.Properties.Name -contains $fieldName) {
            $Pipeline.Screen1Select.$fieldName = $freshPipeline.Screen1Select.$fieldName
        } else {
            $Pipeline.Screen1Select | Add-Member -NotePropertyName $fieldName -NotePropertyValue $freshPipeline.Screen1Select.$fieldName -Force
        }
    }
}

# ---- Any pipeline whose Screen1Select still has the uncalibrated
# 0/0/0/0 (or missing FirstDataRowLineIndex/SelectionColumnIndex)
# placeholder geometry gets offered calibration RIGHT NOW, at startup -
# rather than waiting until its hotkey is pressed with the target
# window possibly not even focused yet. Saying No (or the terminal not
# being ready) just means you'll be asked again the first time that
# pipeline's hotkey is actually pressed (Show-Screen1CalibrationPrompt
# further down handles that case). Make sure the terminal is already
# open on a REPOSITORY LIST page with a COB row visible before
# answering Yes here - that's what calibration needs to measure
# against. ----
foreach ($p in $PipelineHotkeyMap.Values) {
    if ($null -ne $p.Screen1Select -and -not (Test-Screen1Calibrated -Screen1Select $p.Screen1Select)) {
        Write-Host "[AutoClipCapture] [$($p.Name)] Screen1Select isn't calibrated yet." -ForegroundColor Yellow
        if (Show-Screen1CalibrationPrompt -PipelineName $p.Name) {
            Write-Host "[AutoClipCapture] [$($p.Name)] Launching Screen1 calibration..." -ForegroundColor Cyan
            Invoke-Screen1CalibrationNow -Pipeline $p
            if (Test-Screen1Calibrated -Screen1Select $p.Screen1Select) {
                Write-Host "[AutoClipCapture] [$($p.Name)] Calibrated." -ForegroundColor Green
            } else {
                Write-Host "[AutoClipCapture] [$($p.Name)] Still not calibrated - you'll be asked again when its hotkey is pressed." -ForegroundColor Yellow
            }
        } else {
            Write-Host "[AutoClipCapture] [$($p.Name)] Skipped - you'll be asked again when its hotkey is pressed." -ForegroundColor Yellow
        }
    }
}

# Shown when back-to-back captures come back nearly identical. Returns
# 'Continue' or 'Stop'.
function Show-DuplicateCapturePrompt {
    param(
        [double]$Similarity,
        [string]$TargetTitle
    )

    $pct = [Math]::Round($Similarity * 100, 2)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Duplicate Capture Detected"
    $dlg.Size            = New-Object System.Drawing.Size(430, 190)
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.TopMost         = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "The last two captures from `"$TargetTitle`" are $pct% identical.`n`nThis usually means the target app has stopped producing new data (e.g. you've reached the end of a list). Continue capturing anyway, or stop here?"
    $lbl.Location = New-Object System.Drawing.Point(15, 12)
    $lbl.Size = New-Object System.Drawing.Size(395, 100)

    $btnContinue = New-Object System.Windows.Forms.Button
    $btnContinue.Text = "Continue"
    $btnContinue.Location = New-Object System.Drawing.Point(140, 118)
    $btnContinue.Size = New-Object System.Drawing.Size(125, 30)
    $btnContinue.DialogResult = [System.Windows.Forms.DialogResult]::Yes

    $btnStop = New-Object System.Windows.Forms.Button
    $btnStop.Text = "Stop Capture"
    $btnStop.Location = New-Object System.Drawing.Point(275, 118)
    $btnStop.Size = New-Object System.Drawing.Size(125, 30)
    $btnStop.DialogResult = [System.Windows.Forms.DialogResult]::No

    $dlg.AcceptButton = $btnContinue
    $dlg.CancelButton = $btnStop
    $dlg.Controls.AddRange(@($lbl, $btnContinue, $btnStop))

    $result = $dlg.ShowDialog()
    $dlg.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { return 'Continue' }
    return 'Stop'
}

# Fully resets every piece of session state to "off". Used by both the
# manual toggle-off and the duplicate-capture "Stop" choice, so a new
# session started afterwards always begins from the same clean slate
# instead of possibly inheriting stale state (leftover State/elapsed
# counters, a suppressed duplicate-warning flag, the previous capture's
# text, etc.) from however the previous session ended.
function Stop-RelayCapture {
    $timer.Stop()
    $global:CR_Running            = $false
    $global:CR_ActiveAutomation   = $null
    $global:CR_State              = 'Idle'
    $global:CR_ElapsedMs          = 0
    $global:CR_PrevCaptureText    = $null
    $global:CR_SuppressDupWarning = $false
    $global:CR_TargetHandle       = [IntPtr]::Zero
    Hide-RelayStatus
}

# Mirrors Stop-RelayCapture, but for a running scan Mode instead of the
# classic Toggle relay. Called both when a mode reaches a stop condition
# (found / not-found / safety limit) and when its hotkey is pressed
# again to cancel it manually.
function Stop-ModeCapture {
    $timer.Stop()
    $global:CR_ActiveAutomation = $null
    $global:CR_ActiveModeConfig = $null
    $global:CR_ModeState        = 'Action'
    $global:CR_ElapsedMs        = 0
    $global:CR_ModeIterations   = 0
    $global:CR_TargetHandle     = [IntPtr]::Zero
    Hide-RelayStatus
}

# Mirrors Stop-ModeCapture, but for a running Pipeline. Called when a
# pipeline runs out of components (finished) and when its hotkey is
# pressed again to cancel it manually.
function Stop-PipelineCapture {
    $timer.Stop()
    $global:CR_ActiveAutomation      = $null
    $global:CR_ActivePipelineConfig  = $null
    $global:CR_PipelineState         = 'CompScan_Action'
    $global:CR_ElapsedMs             = 0
    $global:CR_PipelineComponentIdx  = 0
    $global:CR_PipelineEnvironmentIdx = 0
    $global:CR_PipelineSqlIterations = 0
    $global:CR_PipelineAfterBack     = $null
    $global:CR_PipelineComponentLabel   = $null
    $global:CR_PipelineEnvironmentLabel = $null
    $global:CR_PipelineCurrentScreen    = 0
    $global:CR_PipelineListPageIdx      = 0
    $global:CR_PipelineListPrevFiltered = $null
    $global:CR_PipelineListOutputPath   = $null
    $global:CR_PipelineScreen1PageIdx      = 0
    $global:CR_PipelineScreen1PrevPageText = $null
    $global:CR_PipelineScreen1RetryCount   = 0
    $global:CR_PipelineScreen1Rows          = @()
    $global:CR_PipelineScreen2CapturedText = $null
    $global:CR_TargetHandle          = [IntPtr]::Zero
    $global:CR_PipelineStepPending     = $false
    $global:CR_PipelineStepConfirmed   = $false
    $global:CR_PipelineStepDescription = ''
    Unregister-PipelineStepHotkey
    Hide-StepMarker
    Hide-RelayStatus
}

# Brings the target window to the foreground before an automated key is
# sent to it. Returns $false if the window no longer exists.
function Set-RelayForeground {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) { return $true }
    if (-not [Win32]::IsWindow($Handle)) { return $false }

    if ([Win32]::IsIconic($Handle)) {
        [void][Win32]::ShowWindow($Handle, 9)   # SW_RESTORE
    }

    if ([Win32]::GetForegroundWindow() -ne $Handle) {
        [void][Win32]::SetForegroundWindow($Handle)

        if ([Win32]::GetForegroundWindow() -ne $Handle) {
            # Windows normally blocks a background process from stealing
            # foreground focus outright. Tapping Alt first is a long-
            # standing, widely used workaround that "unlocks"
            # SetForegroundWindow for the very next call.
            [Win32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)  # Alt down
            [Win32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)  # Alt up
            [void][Win32]::SetForegroundWindow($Handle)
        }
    }

    Start-Sleep -Milliseconds 30
    return $true
}

Write-Host "AutoClipCapture is running." -ForegroundColor White
Write-Host "  $ToggleDisplay  -> start/stop the capture loop" -ForegroundColor White
Write-Host "                    (click a window to target, confirm it, then name the file)"
Write-Host "  $ExitDisplay  -> quit"
Write-Host "  $F3Display  -> send a single F3 to the focused window"
foreach ($hkId in $ModeHotkeyMap.Keys) {
    $m = $ModeHotkeyMap[$hkId]
    Write-Host "  $($m.Hotkey.Display)  -> mode: $($m.Name)  (action key: $($m.ActionKeyDisplay))" -ForegroundColor White
}
foreach ($hkId in $PipelineHotkeyMap.Keys) {
    $p = $PipelineHotkeyMap[$hkId]
    if ($null -ne $p.ComponentList -and [bool]$p.ComponentList.Enabled) {
        Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (component list pre-pass -> component -> environment -> SQL search)" -ForegroundColor White
    } else {
        Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (component -> environment -> SQL search)" -ForegroundColor White
    }
}
Write-Host "Action key: $ActionKeyDisplay"
Write-Host "Log folder: $LogDir"
Write-Host "Config:     $ConfigPath"
if ($SkipRowsStart -gt 0 -or $SkipRowsEnd -gt 0) {
    Write-Host "Row filter: skipping first $SkipRowsStart and last $SkipRowsEnd row(s) of each capture"
}
if ($DupDetectEnabled) {
    Write-Host "Duplicate-capture protection: ON (pauses to ask at $([Math]::Round($DupDetectThreshold * 100, 2))% overlap with the previous capture)"
} else {
    Write-Host "Duplicate-capture protection: OFF"
}
$anyScreen1Pipeline = ($PipelineHotkeyMap.Values | Where-Object { $null -ne $_.Screen1Select }) | Select-Object -First 1
if ($null -ne $anyScreen1Pipeline) {
    Write-Host "This build now forces per-monitor DPI awareness before touching any screen coordinate - if Screen1Select was calibrated with an OLDER build and clicks look off (or the red circle when stepping through Ctrl+Shift+M lands outside the terminal), run StartAutoClipCapture.bat Calibrate again to recalibrate under the new, consistent coordinates. This only matters if Windows display scaling isn't 100%." -ForegroundColor Cyan
}
Write-Host ""

$global:CR_Running      = $false
$global:CR_Selecting    = $false
$global:CR_State        = 'Idle'   # Idle -> PostCopy -> PostAction -> Idle ...
$global:CR_ElapsedMs    = 0
$global:CR_LogFile      = Join-Path $TxtDir ($DefaultBaseName + ".txt")
$global:CR_LogFileCbl   = Join-Path $CblDir ($DefaultBaseName + ".cbl")
$global:CR_TargetHandle = [IntPtr]::Zero
$global:CR_TargetTitle  = ''
$global:CR_PrevCaptureText     = $null
$global:CR_SuppressDupWarning  = $false

# $null = nothing running, 'Relay' = the classic Toggle capture loop,
# or a Mode's Id = that scan Mode is running. Only one of these can be
# active at a time - it's what the Toggle/Mode hotkey handlers check
# before allowing a new session to start.
$global:CR_ActiveAutomation = $null
$global:CR_ActiveModeConfig = $null
$global:CR_ModeState        = 'Action'   # Action -> PostAction -> PostCopy -> Action ...
$global:CR_ModeIterations   = 0

# $null = no Pipeline running, otherwise the running Pipeline's config
# object (also referenced via $global:CR_ActiveAutomation = pipeline.Id,
# same convention as Modes). See the tick handler below for the full
# CompZoom -> CompNext / EnvZoom -> EnvNext / Sql -> Back state chain.
$global:CR_ActivePipelineConfig     = $null
$global:CR_PipelineState            = 'CompScan_Action'
$global:CR_PipelineComponentIdx     = 0
$global:CR_PipelineEnvironmentIdx   = 0
$global:CR_PipelineSqlIterations    = 0
$global:CR_PipelineAfterBack        = $null   # state to resume at once the single F3 "back" completes
$global:CR_PipelineComponentLabel   = $null
$global:CR_PipelineEnvironmentLabel = $null
$global:CR_PipelineCurrentScreen    = 0   # 0 = unknown, else 1/2/3 - see Get-PipelineScreenNumber

# ---- ComponentList pre-pass state (see AutoClipCaptureSqlPipelineComponentList.ps1) ----
$global:CR_PipelineListPageIdx      = 0     # how many pages have been saved so far
$global:CR_PipelineListPrevFiltered = $null # previous page's filtered text, for end-of-list comparison
$global:CR_PipelineListOutputPath   = $null # resolved path of pipeline_component_list.txt for this run

# ---- Screen1 row-selection state (see AutoClipCaptureSqlPipelineScreen1.ps1).
# $global:CR_PipelineComponentIdx (declared above) is reused here as the
# 0-based index *into $global:CR_PipelineScreen1Rows* (reset to 0 every
# time a new page is scanned/paged into). ----
$global:CR_PipelineScreen1PageIdx      = 0     # 0-based page counter, for MaxPages/logging
$global:CR_PipelineScreen1PrevPageText = $null # previous page's raw capture, for end-of-list duplicate detection
$global:CR_PipelineScreen1RetryCount   = 0     # consecutive "unrecognized screen"/"no rows found" retries
$global:CR_PipelineScreen1Rows         = @()   # detected @{ LineIndex; ColIndex } for each "COB" row on the current page
$global:CR_PipelineScreen2CapturedText = $null # text captured right after landing on Screen 2, handed to Screen2.ps1 for logging

# ---- Step-confirm gate state (see Request-PipelineStepConfirm) ----
$global:CR_PipelineStepPending     = $false   # true while a queued input is waiting on Right Arrow
$global:CR_PipelineStepConfirmed   = $false   # set by the StepConfirmHotkeyId handler, consumed by Request-PipelineStepConfirm
$global:CR_PipelineStepDescription = ''
$global:CR_StepHotkeyRegistered    = $false   # whether the Right Arrow hotkey is currently registered (only while a pipeline runs)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $TimerTickMs

$tickAction = {
    if ($null -eq $global:CR_ActiveAutomation) { return }

    if ($null -ne $global:CR_ActivePipelineConfig) {
        # ---- A Pipeline is running (component -> environment -> SQL
        # search, screen by screen); the classic Relay and single-level
        # scan Mode state machines below are both skipped entirely while
        # this is the case. Each screen's own logic lives in its own
        # file (AutoClipCaptureSqlPipelineScreen1/2/3.ps1, dot-sourced
        # near the top of this script) - this just routes the current
        # sub-state to the right one. Only the shared "go back a
        # screen" step stays here, since it isn't owned by any single
        # screen. ----
        try {
            $pipeline = $global:CR_ActivePipelineConfig

            switch -Wildcard ($global:CR_PipelineState) {
                'List*' { Invoke-PipelineListTick }
                'Comp*' { Invoke-PipelineScreen1Tick }
                'Env*'  { Invoke-PipelineScreen2Tick }
                'Sql_*' { Invoke-PipelineScreen3Tick }

                # ---- Single F3 press back to the previous screen, then
                # verify we actually landed where expected before
                # resuming wherever the caller queued up via AfterBack.
                # Always exactly one F3 press - never held/repeated -
                # but that alone doesn't guarantee some screens won't
                # still jump back further than intended (e.g. all the
                # way out to a logout screen), so Back_Copy checks the
                # landing screen against what AfterBack implies before
                # continuing: CompNext_Action means "should be back on
                # screen 1", EnvNext_Action means "should be back on
                # screen 2". A mismatch stops the pipeline rather than
                # risk compounding it by pressing on regardless. ----
                'Back_Action' {
                    $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press $F3Display to go back"
                    if (Request-PipelineStepConfirm -Description $desc) { return }

                    if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                        Stop-PipelineCapture
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Returning ($F3Display)" ([System.Drawing.Color]::Orange)
                    [System.Windows.Forms.SendKeys]::SendWait($F3ActionKeyToken)
                    $global:CR_PipelineState = 'Back_Wait'
                    $global:CR_ElapsedMs = 0
                }
                'Back_Wait' {
                    $global:CR_ElapsedMs += $TimerTickMs
                    if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                        if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                            Stop-PipelineCapture
                            return
                        }
                        [System.Windows.Forms.SendKeys]::SendWait('^c')
                        $global:CR_PipelineState = 'Back_Copy'
                        $global:CR_ElapsedMs = 0
                    }
                }
                'Back_Copy' {
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

                        $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                        $expected = if ($global:CR_PipelineAfterBack -eq 'CompNext_Action') { 1 } else { 2 }

                        if ($detected -ne $expected) {
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Landed on screen $detected after going back, expected screen $expected - stopping to be safe." -ForegroundColor Red
                            Show-RelayResultOverlay -Text "UNEXPECTED SCREEN - STOPPED" -Color ([System.Drawing.Color]::Red)
                            Stop-PipelineCapture
                            return
                        }

                        $global:CR_PipelineState     = $global:CR_PipelineAfterBack
                        $global:CR_PipelineAfterBack = $null
                        $global:CR_ElapsedMs         = 0
                    }
                }
            }
        } catch {
            Write-Host "[AutoClipCapture] [$($global:CR_ActivePipelineConfig.Name)] Tick error (recovered): $($_.Exception.Message)" -ForegroundColor Yellow
            # Re-scan rather than resume CompZoom_Action directly - the
            # error could have hit mid-scan, leaving
            # $global:CR_PipelineScreen1Rows stale or empty.
            $global:CR_PipelineState = 'CompScan_Action'
            $global:CR_ElapsedMs = 0
        }
        return
    }

    if ($global:CR_ActiveAutomation -ne 'Relay') {
        # ---- A scan Mode is running; the classic Relay state machine
        # below is skipped entirely while that's the case. ----
        try {
            $mode = $global:CR_ActiveModeConfig
            switch ($global:CR_ModeState) {
                'Action' {
                    if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                        Write-Host "[AutoClipCapture] [$($mode.Name)] Target window is gone - stopping." -ForegroundColor Red
                        Stop-ModeCapture
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($mode.Name)] Sending $($mode.ActionKeyDisplay)" ([System.Drawing.Color]::Orange)
                    [System.Windows.Forms.SendKeys]::SendWait($mode.ActionKeyToken)
                    $global:CR_ModeState = 'PostAction'
                    $global:CR_ElapsedMs = 0
                }
                'PostAction' {
                    $global:CR_ElapsedMs += $TimerTickMs
                    if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                        if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                            Write-Host "[AutoClipCapture] [$($mode.Name)] Target window is gone - stopping." -ForegroundColor Red
                            Stop-ModeCapture
                            return
                        }
                        Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($mode.Name)] Copying (Ctrl+C)" ([System.Drawing.Color]::Lime)
                        [System.Windows.Forms.SendKeys]::SendWait('^c')
                        $global:CR_ModeState = 'PostCopy'
                        $global:CR_ElapsedMs = 0
                    }
                }
                'PostCopy' {
                    $global:CR_ElapsedMs += $TimerTickMs
                    if ($global:CR_ElapsedMs -ge $CopyDelayMs) {
                        $text = ''
                        try {
                            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                                $text = [System.Windows.Forms.Clipboard]::GetText()
                            }
                        } catch {
                            Write-Host "[AutoClipCapture] [$($mode.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
                        }

                        $global:CR_ModeIterations++

                        $foundMatch    = Test-RelayTextContains -Text $text -Needle $mode.FoundText
                        # NotFoundText and TerminalText are both treated as an
                        # immediate "not found" stop condition - either one
                        # appearing means the target app has already given a
                        # definitive answer, so there's no reason to press
                        # the action key again.
                        $notFoundMatch = (Test-RelayTextContains -Text $text -Needle $mode.NotFoundText) -or
                                         (Test-RelayTextContains -Text $text -Needle $mode.TerminalText)

                        if ($foundMatch) {
                            Write-Host "[AutoClipCapture] [$($mode.Name)] '$($mode.FoundText)' found." -ForegroundColor Green
                            Show-RelayResultOverlay -Text $mode.FoundOverlayText -Color ([System.Drawing.Color]::LimeGreen)
                            Update-ComponentSqlCheckFile -Text $text -SqlFound $true
                            Stop-ModeCapture
                        }
                        elseif ($notFoundMatch) {
                            Write-Host "[AutoClipCapture] [$($mode.Name)] Not-found phrase matched." -ForegroundColor Yellow
                            Show-RelayResultOverlay -Text $mode.NotFoundOverlayText -Color ([System.Drawing.Color]::OrangeRed)
                            Update-ComponentSqlCheckFile -Text $text -SqlFound $false
                            Stop-ModeCapture
                        }
                        elseif ($global:CR_ModeIterations -ge [int]$mode.MaxIterations) {
                            Write-Host "[AutoClipCapture] [$($mode.Name)] Stopped - safety limit of $($mode.MaxIterations) iterations reached." -ForegroundColor Yellow
                            Show-RelayResultOverlay -Text "STOPPED (limit reached)" -Color ([System.Drawing.Color]::Gray)
                            Stop-ModeCapture
                        }
                        else {
                            # Neither phrase matched yet (e.g. the screen
                            # hasn't finished updating) - press the action
                            # key again and check once more.
                            $global:CR_ModeState = 'Action'
                            $global:CR_ElapsedMs = 0
                        }
                    }
                }
            }
        } catch {
            Write-Host "[AutoClipCapture] [$($global:CR_ActiveModeConfig.Name)] Tick error (recovered): $($_.Exception.Message)" -ForegroundColor Yellow
            $global:CR_ModeState = 'Action'
            $global:CR_ElapsedMs = 0
        }
        return
    }

    try {
        switch ($global:CR_State) {
            'Idle' {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Write-Host "[AutoClipCapture] Target window is gone - stopping capture." -ForegroundColor Red
                    Stop-RelayCapture
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : Copying (Ctrl+C)" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_State     = 'PostCopy'
                $global:CR_ElapsedMs = 0
            }
            'PostCopy' {
                $global:CR_ElapsedMs += $TimerTickMs
                if ($global:CR_ElapsedMs -ge $CopyDelayMs) {
                    $stopRequested = $false
                    try {
                        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                            $text = [System.Windows.Forms.Clipboard]::GetText()

                            # ---- Duplicate-capture check: compare this
                            # capture against the immediately previous one.
                            # If they're near-identical, the target app has
                            # likely stopped producing new data - pause and
                            # let the user decide whether to keep going. ----
                            if ($DupDetectEnabled -and $null -ne $global:CR_PrevCaptureText) {
                                $similarity = Get-TextSimilarity -A $global:CR_PrevCaptureText -B $text
                                if ($similarity -ge $DupDetectThreshold) {
                                    if (-not $global:CR_SuppressDupWarning) {
                                        $timer.Stop()
                                        $pct = [Math]::Round($similarity * 100, 2)
                                        Set-RelayStatus "-> $($global:CR_TargetTitle) : Duplicate capture ($pct% match)" ([System.Drawing.Color]::Yellow)
                                        Write-Host "[AutoClipCapture] Duplicate capture detected ($pct% match with the previous one)." -ForegroundColor Yellow

                                        $choice = Show-DuplicateCapturePrompt -Similarity $similarity -TargetTitle $global:CR_TargetTitle
                                        if ($choice -eq 'Stop') {
                                            Stop-RelayCapture
                                            Write-Host "[AutoClipCapture] Capture STOPPED (duplicate content confirmed by user)." -ForegroundColor Cyan
                                            $stopRequested = $true
                                        } else {
                                            # Don't nag again every single cycle - only re-arm once a
                                            # genuinely different capture comes in (see the 'else' below).
                                            $global:CR_SuppressDupWarning = $true
                                            Write-Host "[AutoClipCapture] Continuing despite duplicate content (won't ask again until new content appears)." -ForegroundColor Yellow
                                        }

                                        if ($global:CR_Running) { $timer.Start() }
                                    }
                                } else {
                                    $global:CR_SuppressDupWarning = $false
                                }
                            }

                            $global:CR_PrevCaptureText = $text

                            if (-not $stopRequested) {
                                $filtered = Get-FilteredCaptureText -Text $text -SkipStart $SkipRowsStart -SkipEnd $SkipRowsEnd
                                if (-not [string]::IsNullOrEmpty($filtered)) {
                                    try {
                                        Add-Content -Path $global:CR_LogFile -Value $filtered
                                    } catch {
                                        Write-Host "[AutoClipCapture] Failed to write to $($global:CR_LogFile): $_" -ForegroundColor Red
                                    }
                                    try {
                                        Add-Content -Path $global:CR_LogFileCbl -Value $filtered
                                    } catch {
                                        Write-Host "[AutoClipCapture] Failed to write to $($global:CR_LogFileCbl): $_" -ForegroundColor Red
                                    }
                                }
                            }
                        }
                    } catch {
                        Write-Host "Clipboard read failed: $_" -ForegroundColor Yellow
                    }

                    if ($stopRequested) { return }

                    if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                        Write-Host "[AutoClipCapture] Target window is gone - stopping capture." -ForegroundColor Red
                        Stop-RelayCapture
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : Sending $ActionKeyDisplay" ([System.Drawing.Color]::Orange)
                    [System.Windows.Forms.SendKeys]::SendWait($ActionKeyToken)
                    $global:CR_State     = 'PostAction'
                    $global:CR_ElapsedMs = 0
                }
            }
            'PostAction' {
                $global:CR_ElapsedMs += $TimerTickMs
                if ($global:CR_ElapsedMs -ge $AfterActionKeyDelayMs) {
                    $global:CR_State = 'Idle'
                }
            }
        }
    } catch {
        # Covers cases like a stray Ctrl+C landing on this console, which
        # makes PowerShell throw "The pipeline has been stopped." here.
        # Log it and reset to a safe state instead of letting it bubble
        # up and crash the whole app.
        Write-Host "[AutoClipCapture] Tick error (recovered): $($_.Exception.Message)" -ForegroundColor Yellow
        $global:CR_State     = 'Idle'
        $global:CR_ElapsedMs = 0
    }
}

$timer.Add_Tick($tickAction)
$timer.Start()

$hotkeyAction = {
    param($sender, $id)

    if ($id -eq $ToggleHotkeyId) {
        if (-not (Test-RightModifierSatisfied -Modifiers $ToggleModifiers -RequireRight $ToggleRequireRightModifier)) { return }
        if ($global:CR_Selecting) { return }   # ignore repeat presses mid-selection

        if ($global:CR_ActiveAutomation -eq 'Relay') {
            Stop-RelayCapture
            Write-Host "[AutoClipCapture] Capture STOPPED" -ForegroundColor Cyan
            return
        }
        if ($null -ne $global:CR_ActiveAutomation) {
            $busyName = if ($global:CR_ActiveModeConfig) { $global:CR_ActiveModeConfig.Name } else { $global:CR_ActiveAutomation }
            Write-Host "[AutoClipCapture] Can't start the Toggle relay - '$busyName' is currently running." -ForegroundColor Yellow
            return
        }

        $global:CR_Selecting = $true
        try {
            # 1. Click-to-pick the target window, with a Yes/No
            #    identify-and-confirm step (Enter = Yes).
            $target = $null
            while ($true) {
                $picked = Select-TargetWindow
                if ($null -eq $picked) {
                    Write-Host "[AutoClipCapture] Capture start cancelled (no window selected)." -ForegroundColor Yellow
                    Hide-RelayStatus
                    return
                }
                if (Confirm-TargetWindow -Title $picked.Title) {
                    $target = $picked
                    break
                }
                Write-Host "[AutoClipCapture] Selection rejected - click the correct window." -ForegroundColor Yellow
            }

            # 2. Ask for the filename, same as before, then start
            #    right away once Enter is pressed. Whatever name (and
            #    whatever extension, if any) is typed here only
            #    supplies the base name - the actual output is always
            #    two files: <base>.txt under LogDir\txt and
            #    <base>.cbl under LogDir\cbl.
            $name = Show-FilenamePrompt -DefaultName $DefaultBaseName -TargetTitle $target.Title
            if ($null -eq $name) {
                Write-Host "[AutoClipCapture] Capture start cancelled." -ForegroundColor Yellow
                Hide-RelayStatus
                return
            }
            $safeName = Get-SafeFileName $name
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $DefaultBaseName }

            foreach ($d in @($TxtDir, $CblDir)) {
                if (-not (Test-Path -Path $d)) {
                    try { New-Item -ItemType Directory -Path $d -Force | Out-Null } catch {
                        Write-Host "[AutoClipCapture] Could not create '$d': $_" -ForegroundColor Yellow
                    }
                }
            }

            $global:CR_LogFile      = Join-Path $TxtDir ($baseName + ".txt")
            $global:CR_LogFileCbl   = Join-Path $CblDir ($baseName + ".cbl")
            $global:CR_TargetHandle = $target.Handle
            $global:CR_TargetTitle  = $target.Title
            $global:CR_Running      = $true
            $global:CR_ActiveAutomation = 'Relay'
            $global:CR_State        = 'Idle'
            $global:CR_ElapsedMs    = 0
            $global:CR_PrevCaptureText    = $null
            $global:CR_SuppressDupWarning = $false

            # Stop then Start (rather than just Start) so the timer's
            # own interval countdown always begins fresh for this new
            # session, regardless of whatever state - running, stopped
            # via duplicate-detection, stopped manually - it was left
            # in by the previous one.
            $timer.Stop()
            $timer.Start()

            Write-Host "[AutoClipCapture] Capture STARTED -> $($global:CR_LogFile)" -ForegroundColor Green
            Write-Host "[AutoClipCapture] Capture STARTED -> $($global:CR_LogFileCbl)" -ForegroundColor Green
            Write-Host "[AutoClipCapture] Target window -> $($target.Title)" -ForegroundColor Green
            Set-RelayStatus "-> $($target.Title) : starting..." ([System.Drawing.Color]::Lime)
        } finally {
            $global:CR_Selecting = $false
        }
    }
    elseif ($id -eq $ExitHotkeyId) {
        if (-not (Test-RightModifierSatisfied -Modifiers $ExitModifiers -RequireRight $ExitRequireRightModifier)) { return }
        Write-Host "[AutoClipCapture] Exiting..." -ForegroundColor Magenta
        [System.Windows.Forms.Application]::Exit()
    }
    elseif ($id -eq $F3HotkeyId) {
        if (-not (Test-RightModifierSatisfied -Modifiers $F3Modifiers -RequireRight $F3RequireRightModifier)) { return }
        if ($global:CR_Selecting) { return }   # ignore repeat presses mid-selection
        if ($null -ne $global:CR_ActiveAutomation) {
            $busyName = if ($global:CR_ActiveModeConfig) { $global:CR_ActiveModeConfig.Name } else { $global:CR_ActiveAutomation }
            Write-Host "[AutoClipCapture] Can't send F3 - '$busyName' is currently running." -ForegroundColor Yellow
            return
        }
        # No window selection - simply assume the currently focused
        # window is the intended target and send F3 straight to it.
        [System.Windows.Forms.SendKeys]::SendWait($F3ActionKeyToken)
        Write-Host "[AutoClipCapture] F3 sent to the focused window." -ForegroundColor Green
    }
    elseif ($id -eq $StepConfirmHotkeyId) {
        # Only ever registered while a pipeline is running (see
        # Register-PipelineStepHotkey), and only actually does
        # anything if a step is currently pending confirmation.
        if ($global:CR_PipelineStepPending) {
            $global:CR_PipelineStepConfirmed = $true
        }
    }
    elseif ($ModeHotkeyMap.ContainsKey($id)) {
        $mode = $ModeHotkeyMap[$id]
        if (-not (Test-RightModifierSatisfied -Modifiers ([int]$mode.Hotkey.Modifiers) -RequireRight ([bool]$mode.Hotkey.RequireRightModifier))) { return }
        if ($global:CR_Selecting) { return }   # ignore repeat presses mid-selection

        if ($global:CR_ActiveAutomation -eq $mode.Id) {
            Stop-ModeCapture
            Write-Host "[AutoClipCapture] [$($mode.Name)] Cancelled." -ForegroundColor Cyan
            return
        }
        if ($null -ne $global:CR_ActiveAutomation) {
            $busyName = if ($global:CR_ActiveModeConfig) { $global:CR_ActiveModeConfig.Name } else { $global:CR_ActiveAutomation }
            Write-Host "[AutoClipCapture] Can't start '$($mode.Name)' - '$busyName' is currently running." -ForegroundColor Yellow
            return
        }

        $global:CR_Selecting = $true
        try {
            $target = $null
            if ($mode.UseFocusedWindow) {
                # Assume the window that already has focus is the
                # target - no click-to-select or confirmation step.
                $fgHandle = [Win32]::GetForegroundWindow()
                if ($fgHandle -eq [IntPtr]::Zero) {
                    Write-Host "[AutoClipCapture] [$($mode.Name)] Start cancelled (no focused window found)." -ForegroundColor Yellow
                    return
                }
                $sb = New-Object System.Text.StringBuilder 256
                [void][Win32]::GetWindowText($fgHandle, $sb, $sb.Capacity)
                $fgTitle = $sb.ToString()
                if ([string]::IsNullOrWhiteSpace($fgTitle)) { $fgTitle = "(untitled window)" }
                $target = [pscustomobject]@{ Handle = $fgHandle; Title = $fgTitle }
            } else {
                while ($true) {
                    $picked = Select-TargetWindow
                    if ($null -eq $picked) {
                        Write-Host "[AutoClipCapture] [$($mode.Name)] Start cancelled (no window selected)." -ForegroundColor Yellow
                        Hide-RelayStatus
                        return
                    }
                    if (Confirm-TargetWindow -Title $picked.Title) {
                        $target = $picked
                        break
                    }
                    Write-Host "[AutoClipCapture] [$($mode.Name)] Selection rejected - click the correct window." -ForegroundColor Yellow
                }
            }

            Hide-RelayResultOverlay
            $global:CR_TargetHandle     = $target.Handle
            $global:CR_TargetTitle      = $target.Title
            $global:CR_ActiveAutomation = $mode.Id
            $global:CR_ActiveModeConfig = $mode
            $global:CR_ModeState        = 'Action'
            $global:CR_ElapsedMs        = 0
            $global:CR_ModeIterations   = 0

            $timer.Stop()
            $timer.Start()

            Write-Host "[AutoClipCapture] [$($mode.Name)] STARTED -> $($target.Title)" -ForegroundColor Green
            Set-RelayStatus "-> $($target.Title) : [$($mode.Name)] starting..." ([System.Drawing.Color]::Lime)
        } finally {
            $global:CR_Selecting = $false
        }
    }
    elseif ($PipelineHotkeyMap.ContainsKey($id)) {
        $pipeline = $PipelineHotkeyMap[$id]
        if (-not (Test-RightModifierSatisfied -Modifiers ([int]$pipeline.Hotkey.Modifiers) -RequireRight ([bool]$pipeline.Hotkey.RequireRightModifier))) { return }
        if ($global:CR_Selecting) { return }   # ignore repeat presses mid-selection

        if ($global:CR_ActiveAutomation -eq $pipeline.Id) {
            Stop-PipelineCapture
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Cancelled." -ForegroundColor Cyan
            return
        }
        if ($null -ne $global:CR_ActiveAutomation) {
            $busyName = if ($global:CR_ActiveModeConfig) { $global:CR_ActiveModeConfig.Name } elseif ($global:CR_ActivePipelineConfig) { $global:CR_ActivePipelineConfig.Name } else { $global:CR_ActiveAutomation }
            Write-Host "[AutoClipCapture] Can't start pipeline '$($pipeline.Name)' - '$busyName' is currently running." -ForegroundColor Yellow
            return
        }

        $global:CR_Selecting = $true
        try {
            $target = $null
            if ($pipeline.UseFocusedWindow) {
                # Assume the window that already has focus is the
                # target - no click-to-select or confirmation step.
                $fgHandle = [Win32]::GetForegroundWindow()
                if ($fgHandle -eq [IntPtr]::Zero) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Start cancelled (no focused window found)." -ForegroundColor Yellow
                    return
                }
                $sb = New-Object System.Text.StringBuilder 256
                [void][Win32]::GetWindowText($fgHandle, $sb, $sb.Capacity)
                $fgTitle = $sb.ToString()
                if ([string]::IsNullOrWhiteSpace($fgTitle)) { $fgTitle = "(untitled window)" }
                $target = [pscustomobject]@{ Handle = $fgHandle; Title = $fgTitle }
            } else {
                while ($true) {
                    $picked = Select-TargetWindow
                    if ($null -eq $picked) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Start cancelled (no window selected)." -ForegroundColor Yellow
                        Hide-RelayStatus
                        return
                    }
                    if (Confirm-TargetWindow -Title $picked.Title) {
                        $target = $picked
                        break
                    }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Selection rejected - click the correct window." -ForegroundColor Yellow
                }
            }

            $useComponentList = ($null -ne $pipeline.ComponentList) -and [bool]$pipeline.ComponentList.Enabled

            # ---- Screen1 calibration gate: the row-scanning pass
            # (CompScan_Action, see Screen1.ps1) needs real pixel
            # geometry to click anywhere. Catch an uncalibrated
            # pipeline here - with the target window already known and
            # focused - rather than letting it fail deep in the state
            # machine. Yes launches calibration and picks the result up
            # immediately (no restart needed); No skips the check and
            # tries to start anyway (Screen1.ps1's own guard will still
            # stop it cleanly if it's genuinely still 0/0/0/0). ----
            if (-not $useComponentList -and $null -ne $pipeline.Screen1Select -and -not (Test-Screen1Calibrated -Screen1Select $pipeline.Screen1Select)) {
                if (Show-Screen1CalibrationPrompt -PipelineName $pipeline.Name) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Launching Screen1 calibration..." -ForegroundColor Cyan
                    Invoke-Screen1CalibrationNow -Pipeline $pipeline
                    if (-not (Test-Screen1Calibrated -Screen1Select $pipeline.Screen1Select)) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Still not calibrated - start cancelled." -ForegroundColor Yellow
                        Hide-RelayStatus
                        return
                    }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Calibrated - continuing." -ForegroundColor Green
                } else {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Calibration check skipped by user - attempting to start anyway." -ForegroundColor Yellow
                }
            }

            Hide-RelayResultOverlay
            $global:CR_TargetHandle             = $target.Handle
            $global:CR_TargetTitle              = $target.Title
            $global:CR_ActiveAutomation         = $pipeline.Id
            $global:CR_ActivePipelineConfig     = $pipeline
            $global:CR_PipelineState            = if ($useComponentList) { 'ListCapture_Start' } else { 'CompScan_Action' }
            $global:CR_ElapsedMs                = 0
            $global:CR_PipelineComponentIdx     = 0
            $global:CR_PipelineEnvironmentIdx   = 0
            $global:CR_PipelineSqlIterations    = 0
            $global:CR_PipelineAfterBack        = $null
            $global:CR_PipelineComponentLabel   = $null
            $global:CR_PipelineEnvironmentLabel = $null
            $global:CR_PipelineCurrentScreen    = 0
            $global:CR_PipelineListPageIdx      = 0
            $global:CR_PipelineListPrevFiltered = $null
            $global:CR_PipelineListOutputPath   = if ($useComponentList) { Join-Path $LogDir $pipeline.ComponentList.OutputFileName } else { $null }
            $global:CR_PipelineScreen1PageIdx      = 0
            $global:CR_PipelineScreen1PrevPageText = $null
            $global:CR_PipelineScreen1RetryCount   = 0
            $global:CR_PipelineScreen1Rows          = @()
            $global:CR_PipelineScreen2CapturedText = $null
            $global:CR_PipelineStepPending     = $false
            $global:CR_PipelineStepConfirmed   = $false
            $global:CR_PipelineStepDescription = ''
            Hide-StepMarker
            Register-PipelineStepHotkey

            $timer.Stop()
            $timer.Start()

            if ($useComponentList) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] STARTED -> $($target.Title) (component list pre-pass -> $($global:CR_PipelineListOutputPath))" -ForegroundColor Green
                Set-RelayStatus "-> $($target.Title) : [$($pipeline.Name)] starting component list..." ([System.Drawing.Color]::Lime)
            } else {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] STARTED -> $($target.Title)" -ForegroundColor Green
                if ($global:CR_StepConfirmEnabled) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Step-confirm mode is ON - press $StepConfirmDisplay each time to let the next input through." -ForegroundColor Cyan
                }
                Set-RelayStatus "-> $($target.Title) : [$($pipeline.Name)] starting..." ([System.Drawing.Color]::Lime)
                if ($null -ne $pipeline.Screen1Select -and -not [string]::IsNullOrEmpty($pipeline.Screen1Select.CalibrationNote)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Screen1Select note: $($pipeline.Screen1Select.CalibrationNote)" -ForegroundColor DarkGray
                }
            }
        } finally {
            $global:CR_Selecting = $false
        }
    }
}

$form.Add_HotkeyPressed($hotkeyAction)

[System.Windows.Forms.Application]::Run($form)

# Cleanup on exit
$timer.Stop()
[HotkeyForm]::UnregisterHotKey($FormHandle, $ToggleHotkeyId) | Out-Null
[HotkeyForm]::UnregisterHotKey($FormHandle, $ExitHotkeyId)   | Out-Null
[HotkeyForm]::UnregisterHotKey($FormHandle, $F3HotkeyId)     | Out-Null
Unregister-PipelineStepHotkey
foreach ($hkId in $ModeHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
foreach ($hkId in $PipelineHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
$statusForm.Dispose()
$resultOverlay.Dispose()
Write-Host "AutoClipCapture stopped."
