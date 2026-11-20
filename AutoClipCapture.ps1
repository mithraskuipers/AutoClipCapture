<#
=====================================================================
 AutoClipCapture.ps1
=====================================================================
 Runs quietly in the background and listens for GLOBAL hotkeys
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
                            a .txt copy in ..\txt and a .cbl copy in
                            ..\cbl (the txt and cbl folders right
                            outside this script's own folder), both
                            with identical content. Cancelling this
                            prompt cancels the
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
                       Auto capture current file) can run at a time. Modes
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

   Ctrl+Shift+S     -> Stop the current automation globally.
   Ctrl+Shift+P     -> Pause or resume the current automation globally.
   Ctrl+Shift+R     -> Completely restart AutoClipCapture, clearing its
                       in-memory automation state and reloading config.

   [Pipeline hotkeys] -> A pipeline walks the COB rows on REPOSITORY
                       LIST. For each row it selects B, enters
                       COMPONENT VERSION, selects S beside PROD/UT/ET
                       only when S is not already present, and opens
                       SOURCE CODE. It then runs Auto Capture Current
                       File through the source pages. After duplicate
                       page detection marks the end, it sends one F3,
                       verifies the repository page, and continues with
                       the next COB row. Pipelines are configured in
                       AutoClipCaptureConfig.json (see the Pipelines
                       array) - like Modes, they aren't edited from the
                       config GUI.

                       Each pipeline has TWO hotkeys: Hotkey (Ctrl+Shift+M)
                       runs it fully automatically, and StepHotkey
                       (Ctrl+Shift+N) runs the exact same thing step by
                       step, waiting for the step-confirm key (Right
                       Arrow) before each input. Screen1Select.StartRowOffset
                       (default 1) starts the row clicking that many rows
                       below the calibrated first data row.

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
    # can also run calibration directly when an unconfigured pipeline is
    # detected at startup or via Show-Screen1CalibrationPrompt.
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
function Get-DefaultPipelineTimingsMs {
    [pscustomobject]@{
        RepositoryList = [pscustomobject]@{
            BeforeClickMs = 0
            AfterClickMs = 1000
            AfterSelectionLetterMs = 1000
            AfterEnterMs = 1000
            AfterClipboardCopyMs = 1000
            InitialScanAfterClipboardCopyMs = 250
            AfterPageKeyMs = 1000
            AfterDeleteMs = 1000
            AfterF3Ms = 1000
        }
        ComponentVersion = [pscustomobject]@{
            BeforeClickMs = 0
            AfterClickMs = 1000
            PauseAfterSBeforeEnterMs = 500
            AfterEnterMs = 1000
            AfterClipboardCopyMs = 1000
            AfterF3Ms = 1000
        }
        SourceCode = [pscustomobject]@{
            AfterActionKeyMs = 250
            AfterClipboardCopyMs = 250
            AfterF3Ms = 1000
        }
        ComponentList = [pscustomobject]@{
            AfterPageKeyMs = 250
            AfterClipboardCopyMs = 250
        }
    }
}

function Show-ConfigEditorGui {
<#
=====================================================================
 AutoClipCaptureConfigGUI.ps1
=====================================================================
 GUI for editing AutoClipCaptureConfig.json - the settings file used
 by AutoClipCapture.ps1. Organized into tabs:

   General           - default log location, Auto capture current file's
                        action key
   Timing & Rows      - copy/action delays, internal poll interval,
                        rows to skip at the start/end of each capture,
                        the found/not-found result-banner duration
   Duplicates         - duplicate-capture detection (pause & ask when
                        back-to-back captures come back almost
                        identical)
   Hotkeys            - the Toggle hotkey (start/stop Auto capture current file, the classic
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

 Auto capture current file's ACTION KEY is different: it's just simulated as a
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
        PipelineTimingsMs       = Get-DefaultPipelineTimingsMs
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
$grpLog.Text = "Default log location (asked for a filename each time you start Auto capture current file)"
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
$grpAction.Text = "Auto capture current file: action key (pressed after each Ctrl+C)"
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
$lblGeneralHint.Text = "This action key is only used by Auto capture current file. Each Mode (see the Modes tab) has its own separate action key."
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
$grpRows.Text = "Row filtering (skip rows in each captured chunk before saving - Auto capture current file only)"
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
$grpDup.Text = "Duplicate-capture detection (Auto capture current file only)"
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
$lblToggle.Text = "Auto capture current file:"
$lblToggle.Location = New-Object System.Drawing.Point(15, 25)
$lblToggle.Size = New-Object System.Drawing.Size(155, 20)

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
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Auto capture current file"; Mods = $script:ToggleMods;    Key = $script:ToggleKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "Exit";         Mods = $script:ExitMods;      Key = $script:ExitKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "SQL Search";   Mods = $script:SqlSearchMods; Key = $script:SqlSearchKey })
    [void]$allHotkeys.Add([pscustomobject]@{ Name = "F3";           Mods = $script:F3Mods;        Key = $script:F3Key })
    foreach ($m in $script:ModesList) {
        if ($m.Id -eq 'sql-search') { continue }   # already covered above with its live edited value
        if ($m.Enabled) {
            [void]$allHotkeys.Add([pscustomobject]@{ Name = "Mode '$($m.Name)'"; Mods = [int]$m.Hotkey.Modifiers; Key = [int]$m.Hotkey.Key })
        }
    }
    foreach ($reserved in @(
        [pscustomobject]@{ Name = 'Pause/resume'; Mods = 6; Key = 0x50 },
        [pscustomobject]@{ Name = 'Stop automation'; Mods = 6; Key = 0x53 }
    )) {
        foreach ($configured in $allHotkeys) {
            if ($configured.Mods -eq $reserved.Mods -and $configured.Key -eq $reserved.Key) {
                [System.Windows.Forms.MessageBox]::Show(
                    "$($configured.Name) uses a reserved hotkey for $($reserved.Name). Choose a different combination; Ctrl+Shift+P and Ctrl+Shift+S are always reserved for pause/resume and stop.",
                    "Reserved Hotkey", 'OK', 'Warning') | Out-Null
                return
            }
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
        PipelineTimingsMs         = if ($existing.PSObject.Properties.Name -contains 'PipelineTimingsMs') { $existing.PipelineTimingsMs } else { Get-DefaultPipelineTimingsMs }
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
# Invoke-Screen1CalibrationTool function below. Calibration runs in this
# process and uses the existing console; it must return to its caller and
# must never launch or exit a second PowerShell process.
#=====================================================================
function Invoke-Screen1CalibrationTool {
    param(
        $Pipeline,
        [IntPtr]$TargetHandle = [IntPtr]::Zero
    )
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
   3. Inspects copied text dimensions as a clue, then uses this session's
      configured grid of 80 columns x 32 rows. Clipboard text can omit
      blank rows, headers, or columns, so it is never treated as truth.
      The detected terminal rectangle divided by the configured grid gives
      CharWidthPx/CharHeightPx -
      measured from the ACTUAL terminal area only, unlike
      CalibrateScreen1AutoGuided.ps1's original approach of dividing
      the WHOLE window client area by 80x32 (which silently counted
      the menu/toolbar/status-bar height as if it were extra terminal
      rows, and produced a CharHeightPx that was too small - accurate
      only right at the one manually-nudged row, and increasingly off
      moving down the page).
   4. Works out OriginX/OriginY from that rectangle's actual top-left
      corner.
   5. Copies the CURRENT screen (Ctrl+C) to verify a COB data row is
      present. Its screen row is configured as row 6 (0-based), and the
      selection field is configured as columns 1-2 (0-based). The real pipeline
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
 at least one visible "COB" row before running this. The known first
 data row is terminal screen row 6 (counting from 0 at the top).

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

Add-Type -TypeDefinition @"
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
"@ -ErrorAction SilentlyContinue

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
    return $false
}
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

$targets = @()
foreach ($pipeline in $config.Pipelines) {
    if ($null -ne $pipeline.Screen1Select) { $targets += $pipeline }
}
if ($targets.Count -eq 0) {
    Write-Host "No pipeline with a Screen1Select block was found in the config. Nothing to calibrate." -ForegroundColor Red
    return $false
}
$chosenPipeline = $null
if ($null -ne $Pipeline) {
    $chosenPipeline = $targets | Where-Object { $_.Id -eq $Pipeline.Id } | Select-Object -First 1
    if ($null -eq $chosenPipeline) {
        Write-Host "Requested pipeline '$($Pipeline.Id)' wasn't found in AutoClipCaptureConfig.json." -ForegroundColor Red
        return $false
    }
} elseif ($targets.Count -eq 1) {
    $chosenPipeline = $targets[0]
} else {
    Write-Host "`nMultiple pipelines need calibration. Which one?"
    for ($i = 0; $i -lt $targets.Count; $i++) { Write-Host ("  [{0}] {1} ({2})" -f $i, $targets[$i].Name, $targets[$i].Id) }
    $pIdx = Read-Host "Enter the number"
    $parsedPipelineIndex = -1
    if (-not [int]::TryParse([string]$pIdx, [ref]$parsedPipelineIndex) -or $parsedPipelineIndex -lt 0 -or $parsedPipelineIndex -ge $targets.Count) {
        Write-Host "Invalid choice. Nothing changed." -ForegroundColor Red
        return $false
    }
    $chosenPipeline = $targets[$parsedPipelineIndex]
}

# Calibrate the actual selection-field column directly. The COB row is
# still used as a known row anchor, but the field's horizontal position
# is not assumed to be a fixed number of cells from the COB text.
$clickColumnOffset = 0
$chosenPipeline.Screen1Select.ClickColumnOffset = $clickColumnOffset

Write-Host "`nMake sure your terminal window is open, fully visible, and NOT covered by another window." -ForegroundColor Cyan
$windows = [CalibNative4]::GetVisibleWindows()
$terminalTitlePrefix = '3270-display(32 regels)'
$terminalWindows = @($windows | Where-Object { $_.Value.StartsWith($terminalTitlePrefix, [System.StringComparison]::OrdinalIgnoreCase) })
$providedTargetVisible = ($TargetHandle -ne [IntPtr]::Zero) -and [CalibNative4]::IsWindowVisible($TargetHandle)
if ($providedTargetVisible) {
    $targetHandle = $TargetHandle
    $targetInfo = $windows | Where-Object { $_.Key -eq $targetHandle } | Select-Object -First 1
    $targetTitle = if ($null -ne $targetInfo) { $targetInfo.Value } else { 'selected terminal window' }
    Write-Host ("`nUsing the already selected mainframe window: {0}" -f $targetTitle) -ForegroundColor Cyan
} elseif ($terminalWindows.Count -eq 0) {
    Write-Host "`nCouldn't find a visible window whose title starts with '$terminalTitlePrefix'. Nothing changed." -ForegroundColor Red
    Write-Host "Visible windows:"
    foreach ($window in $windows) { Write-Host ("  {0}" -f $window.Value) }
    return $false
} elseif ($terminalWindows.Count -eq 1) {
    $targetHandle = $terminalWindows[0].Key
    Write-Host ("`nAutomatically detected mainframe window: {0}" -f $terminalWindows[0].Value) -ForegroundColor Cyan
} else {
    Write-Host "`nMultiple mainframe windows matched. Select the terminal to calibrate:"
    for ($i = 0; $i -lt $terminalWindows.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f $i, $terminalWindows[$i].Value)
    }
    $winIdx = Read-Host "Enter the number of the intended terminal window"
    $parsedWindowIndex = -1
    if (-not [int]::TryParse([string]$winIdx, [ref]$parsedWindowIndex) -or $parsedWindowIndex -lt 0 -or $parsedWindowIndex -ge $terminalWindows.Count) {
        Write-Host "Invalid choice. Nothing changed." -ForegroundColor Red
        return $false
    }
    $targetHandle = $terminalWindows[$parsedWindowIndex].Key
}
[void][CalibNative4]::SetForegroundWindow($targetHandle)
Start-Sleep -Milliseconds 300   # give it a moment to actually come to the front before the screenshot

Write-Host "`nTaking a screenshot and looking for the terminal grid..." -ForegroundColor Cyan
$bmp = Get-WindowScreenshot -Handle $targetHandle
if ($null -eq $bmp) {
    Write-Host "Couldn't read that window's size/screenshot. Nothing changed." -ForegroundColor Red
    return $false
}
$calibrationClientWidth = $bmp.Width
$calibrationClientHeight = $bmp.Height

$box = Find-DarkRectangle -Bmp $bmp
$bmp.Dispose()

if ($null -eq $box -or ($box.Right - $box.Left) -lt 100 -or ($box.Bottom - $box.Top) -lt 100) {
    Write-Host "`nCouldn't confidently find a solid dark terminal rectangle in that window." -ForegroundColor Red
    Write-Host "(Maybe the terminal uses a light color scheme, or another window was on top of it.)" -ForegroundColor Red
    Write-Host "Use CalibrateScreen1AutoGuided.bat instead - it doesn't rely on detecting a dark background." -ForegroundColor Yellow
    return $false
}

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
    return $false
}
$clipboardLines = $copiedText -split "`r`n|`n|`r"
$clipboardWidths = @($clipboardLines | ForEach-Object { $_.Length } | Sort-Object -Unique)
$clipboardMinWidth = ($clipboardLines | ForEach-Object { $_.Length } | Measure-Object -Minimum).Minimum
$clipboardMaxWidth = ($clipboardLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
Write-Host ("  Clipboard clue: {0} lines, line widths {1}-{2} characters ({3} distinct widths)." -f $clipboardLines.Count, $clipboardMinWidth, $clipboardMaxWidth, $clipboardWidths.Count) -ForegroundColor DarkCyan
Write-Host ("  'COB' appears in clipboard line {0}, column {1}: `"{2}`"" -f $cobMatch.LineIndex, $cobMatch.ColIndex, $cobMatch.LineText.Trim()) -ForegroundColor Cyan
# This Host On-Demand session is configured as 80 columns by 32 rows.
# The first COB data row is visible screen row 6 (0-based); clipboard
# line indices remain diagnostic only and may omit leading screen rows.
$cols = 80
$rows = 32
$realLineIndex = 6
$calibratedSelectionColumn = 1
$selectionFieldLastColumn = 2
Write-Host "Using configured terminal grid: 80 columns x 32 rows; first COB data row is screen row 6 (0-based)." -ForegroundColor Cyan
Write-Host "Using selection field columns 1-2 (0-based); click target is column 1." -ForegroundColor Cyan
Write-Host "Clipboard dimensions above are diagnostic only and are not used as screen coordinates." -ForegroundColor DarkGray
$boxWidth  = $box.Right - $box.Left
$boxHeight = $box.Bottom - $box.Top
$CharWidthPx  = [math]::Round(($boxWidth / $cols), 2)
$CharHeightPx = [math]::Round(($boxHeight / $rows), 2)
if ($CharWidthPx -lt 4 -or $CharWidthPx -gt 30 -or $CharHeightPx -lt 6 -or $CharHeightPx -gt 50) {
    Write-Host "Detected terminal is $boxWidth x $boxHeight px; these dimensions imply an implausible cell size ($CharWidthPx x $CharHeightPx px). Nothing changed." -ForegroundColor Red
    return $false
}
$OriginX = [math]::Round($box.Left + ($CharWidthPx / 2))
$OriginY = [math]::Round($box.Top + ($CharHeightPx / 2))
Write-Host ("  Terminal box = {0}x{1} px at ({2},{3}); grid = {4} columns x {5} rows; cell = {6}x{7} px" -f $boxWidth,$boxHeight,$box.Left,$box.Top,$cols,$rows,$CharWidthPx,$CharHeightPx) -ForegroundColor Cyan

$targetColIndex = $calibratedSelectionColumn + $clickColumnOffset
if ($targetColIndex -lt 0 -or $targetColIndex -ge $cols -or $selectionFieldLastColumn -ge $cols) {
    Write-Host "Selection field would be outside terminal columns. Nothing changed." -ForegroundColor Red
    return $false
}
$confirmX = $OriginX + ($targetColIndex * $CharWidthPx)
$confirmY = $OriginY + ($realLineIndex * $CharHeightPx)

$pt = New-Object POINT2
$pt.X = [int][math]::Round($confirmX)
$pt.Y = [int][math]::Round($confirmY)
[void][CalibNative4]::ClientToScreen($targetHandle, [ref]$pt)
if ($confirmX -lt ($box.Left + 0.5) -or $confirmX -ge ($box.Right - 0.5) -or $confirmY -lt ($box.Top + 0.5) -or $confirmY -ge ($box.Bottom - 0.5)) {
    Write-Host "Computed calibration point is outside the detected terminal area. Nothing changed." -ForegroundColor Red
    return $false
}
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pt.X, $pt.Y)

Write-Host ""
Write-Host "Pointer moved to column 1 inside the two-column selection field (columns 1-2) on the known first COB data row." -ForegroundColor Cyan
Write-Host "Look at the terminal - does it land there? ENTER to save, Esc to cancel." -ForegroundColor Cyan
Write-Host "(Reminder: this assumes 100% display scaling and today's font/window size." -ForegroundColor DarkGray
Write-Host " Recalibrate if either changes later.)" -ForegroundColor DarkGray
while ($true) {
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'Enter') { break }
    if ($key.Key -eq 'Escape') {
        Write-Host "`nCancelled - nothing saved." -ForegroundColor Yellow
        return $false
    }
}

$chosenPipeline.Screen1Select.OriginX = $OriginX
$chosenPipeline.Screen1Select.OriginY = $OriginY
$chosenPipeline.Screen1Select.CharWidthPx = $CharWidthPx
$chosenPipeline.Screen1Select.CharHeightPx = $CharHeightPx
foreach ($geometry in @(
    @{ Name = 'TerminalLeft'; Value = [int]$box.Left },
    @{ Name = 'TerminalTop'; Value = [int]$box.Top },
    @{ Name = 'TerminalWidth'; Value = [int]$boxWidth },
    @{ Name = 'TerminalHeight'; Value = [int]$boxHeight },
    @{ Name = 'TerminalColumns'; Value = [int]$cols },
    @{ Name = 'TerminalRows'; Value = [int]$rows },
    @{ Name = 'CalibrationClientWidth'; Value = [int]$calibrationClientWidth },
    @{ Name = 'CalibrationClientHeight'; Value = [int]$calibrationClientHeight }
)) {
    if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains $geometry.Name)) {
        $chosenPipeline.Screen1Select | Add-Member -NotePropertyName $geometry.Name -NotePropertyValue $geometry.Value -Force
    } else {
        $chosenPipeline.Screen1Select.($geometry.Name) = $geometry.Value
    }
}

# Save the known screen-row anchor and selection-field column. Each
# repository page's copied text identifies which rows contain COB; the
# first COB line is mapped to this screen-row anchor, not to clipboard
# line 0. ClickColumnOffset is zero because SelectionColumnIndex is the
# actual selection field.
foreach ($prop in @(
    @{ Name = 'FirstDataRowLineIndex'; Value = $realLineIndex },
    @{ Name = 'SelectionColumnIndex';  Value = $calibratedSelectionColumn }
)) {
    if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains $prop.Name)) {
        $chosenPipeline.Screen1Select | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    } else {
        $chosenPipeline.Screen1Select.($prop.Name) = $prop.Value
    }
}

$calibNote = "Auto-calibrated {0} using detected terminal bounds, an 80x32 session grid, first COB row 6 (0-based), and selection field columns 1-2. Clipboard dimensions were diagnostic only. Recalibrate if display scaling, terminal size, font, or layout changes." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
if (-not ($chosenPipeline.Screen1Select.PSObject.Properties.Name -contains 'CalibrationNote')) {
    $chosenPipeline.Screen1Select | Add-Member -NotePropertyName CalibrationNote -NotePropertyValue $calibNote -Force
} else {
    $chosenPipeline.Screen1Select.CalibrationNote = $calibNote
}

$backupPath = Join-Path $PSScriptRoot ("AutoClipCaptureConfig.backup-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -Path $configPath -Destination $backupPath -Force | Out-Null
Write-Host ("`nBacked up old config to: {0}" -f (Split-Path $backupPath -Leaf))

$config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "Done! AutoClipCaptureConfig.json has been updated." -ForegroundColor Green
Write-Host "Calibration complete; the caller will continue using the updated settings." -ForegroundColor Green
Write-Host ""
return $true
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
    # -Calibrate was passed: run calibration in this process and stop -
    # do not start the capture relay. The calibration tool sets DPI
    # awareness before it takes the screenshot.
    [void](Invoke-Screen1CalibrationTool)
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

# Pipeline screen logic lives in this same script: Screen 1 = the
# repository list, Screen 2 = component version, Screen 3 = source code.
# ComponentList is an optional "Step 1" pre-pass that also lives on
# Screen 1 (paging through the full component overview once, up
# front, before any zooming happens) - kept in its own file since it's
# a separate phase with its own state names. Dot-sourcing just defines
# their functions into this script's scope - no side effects until the
# pipeline tick handler below actually calls into them.
# Pipeline screen logic used to live in its own file per screen (dot-sourced
# at startup); they're now inlined directly below as clearly marked regions,
# in the same order they used to be dot-sourced. Nothing about how they work
# changed - Screen 1 = repository list, Screen 2 = component version,
# Screen 3 = source code, and ComponentList = the optional Screen 1
# paging pre-pass.

#=====================================================================
# region: AutoClipCaptureSqlPipelineScreen1.ps1 - formerly its own file, now inlined here
#=====================================================================
<#
=====================================================================
 AutoClipCaptureSqlPipelineScreen1.ps1

 Screen 1 = the REPOSITORY LIST overview (Type/Name/Appl/Subappl/
 Status columns, one row per component, "Row x of y ... More -->").

 This file drives the Ctrl+Shift+M pipeline's main job: process the COB
 rows on each REPOSITORY LIST page. The copied page text identifies COB
 rows; its first COB line is anchored to the calibrated screen row 6 so
 clipboard line numbers are never used as absolute screen rows. Each
 subsequent row maps by its offset from that known row; non-COB rows are
 skipped, and processing ends at the last COB row.
   1. Click/type B/Enter only on rows whose text contains COB.
      A successful selection opens COMPONENT VERSION. If the terminal
      stays on REPOSITORY LIST and the upper-right message changes, click
      that same row and press Delete to clear B, then continue without F3.
      A changed upper-right message on COMPONENT VERSION after S/Enter
      means the source selection failed; press F3 from there and continue.
   1a. Click the calibrated selection field at SelectionColumnIndex
      (ClickColumnOffset is zero) using the pixel math calibrated by
      CalibrateScreen1Auto.ps1/CalibrateScreen1AutoGuided.ps1 into
      Pipelines[].Screen1Select (OriginX/OriginY/CharWidthPx/
      CharHeightPx).
   2. Type Screen1Select.SelectionText (default "B") and press Enter.
   3. Confirm COMPONENT VERSION, find its PROD/UT/ET source row in
      copied text, then select calibrated screen row 8 two columns to
      the left with S and Enter. Confirm the source-code menu on row 0,
      run Auto Capture Current File through the end of source, then
      press F3 and verify REPOSITORY LIST returned.
   4. Only after that verified return, continue to the next COB row.
   5. When the last COB row on a nonfinal page is processed, show a
      centered page-complete message and press Screen1Select.PageNextToken
      (F8 by default). When Screen1Select.EndOfListText appears, process
      every COB row on that final page, then stop without another F8.
      A freshly-paged duplicate page without the marker still ends safely
      because it contains no new list data.

 States (all start with "Comp" so AutoClipCapture.ps1's tick switch
 routes them here):
   CompScan_Action  - copy the page and build the relevant row list
                      (Get-Screen1RowsThroughLastCob), anchored to the
                      known first COB screen row. This exact name is also the pipeline's hard-coded
                      starting state (see the Ctrl+Shift+M hotkey
                      handler), so a pipeline with no ComponentList
                      pre-pass lands here immediately.
   CompZoom_Action  - click the row at
                      $global:CR_PipelineScreen1Rows[$global:CR_PipelineComponentIdx]
                      and type the selection letter.
   CompZoom_Cleanup_* - click a stale B row, delete it, and recopy the
                      page to verify it is clear before continuing.
   CompZoom_Wait    - short delay before copying, so the new screen
                      has time to render.
   CompZoom_Copy    - Ctrl+C, read the clipboard, work out what
                      happened, branch accordingly (see below).
   CompNext_Action  - move past a non-COB row, or decide the next COB
                      row. After the last COB row, show the centered
                      page-complete message and trigger a page turn.
                      Reached after F3 confirms REPOSITORY LIST or while
                      skipping non-COB rows. This exact
                      name also doubles as the "AfterBack" marker the
                      shared Back_Copy logic checks to know it should
                      expect Screen 1 (not Screen 2) once the F3
                      completes.
   CompPage_Action  - send Screen1Select.PageNextToken (e.g. F8) to
                      move to the next page.
   CompPage_Wait    - short delay before copying the new page.
   CompPage_Copy    - Ctrl+C, check EndOfListText / duplicate-page; mark
                      an EndOfListText page as final and build its COB
                      row list anchored to screen row 6. The final page
                      is processed fully before stopping without F8.

 $global:CR_PipelineComponentIdx is the 0-based index into the current
 page's row list through its last COB row. It is reset by AutoClipCapture.ps1 whenever the
 pipeline (re)starts, and reset again here every time a new page comes
 in.
=====================================================================
#>

# Builds row slots through the last real COB data row on the copied page.
# Clipboard line indices may start after omitted headers/blank rows, so
# the first COB row with a concrete component name is anchored to
# calibrated FirstDataRowLineIndex (screen row 6); wildcard filter rows
# such as "COB DQ*" are not data and must not shift this anchor.
function Get-Screen1RowsThroughLastCob {
    param(
        [string]$Text,
        $Screen1Select,
        [int]$RowCount = -1
    )

    $rows = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($Text)) { return $rows }

    $lines = @($Text -split "`r`n|`r|`n")
    $cobLineIndexes = New-Object System.Collections.Generic.List[int]
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $componentMatch = [regex]::Match(
            $lines[$lineIndex],
            '\bCOB\b\s+(?<name>[A-Za-z0-9@#$._-]+)(?=\s|$)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($componentMatch.Success -and $componentMatch.Groups['name'].Value -notmatch '[*?]') {
            $cobLineIndexes.Add($lineIndex)
        }
    }
    if ($cobLineIndexes.Count -eq 0) { return $rows }

    $pageRowCount = if ($RowCount -ge 0) { $RowCount } else { [int]$Screen1Select.RowsPerPage }
    $firstScreenRow = [int]$Screen1Select.FirstDataRowLineIndex
    if ($Screen1Select.PSObject.Properties.Name -contains 'StartRowOffset' -and $null -ne $Screen1Select.StartRowOffset) {
        $firstScreenRow += [int]$Screen1Select.StartRowOffset
    }
    $firstClipboardCobLine = [int]$cobLineIndexes[0]
    $selectionColumn = [int]$Screen1Select.SelectionColumnIndex
    $terminalRows = if ($null -ne $Screen1Select.TerminalRows) { [int]$Screen1Select.TerminalRows } else { 32 }

    $lastClipboardCobLine = [int]$cobLineIndexes[$cobLineIndexes.Count - 1]
    $cobLines = @{}
    foreach ($clipboardLine in $cobLineIndexes) { $cobLines[[int]$clipboardLine] = $true }
    $lastRelevantOffset = [math]::Min(($lastClipboardCobLine - $firstClipboardCobLine), ($pageRowCount - 1))
    for ($rowOffset = 0; $rowOffset -le $lastRelevantOffset; $rowOffset++) {
        $screenRow = $firstScreenRow + $rowOffset
        if ($screenRow -lt 0 -or $screenRow -ge $terminalRows) { continue }
        $clipboardLine = $firstClipboardCobLine + $rowOffset
        $lineText = [string]$lines[$clipboardLine]
        $selectionBCount = 0
        if ($cobLines.ContainsKey([int]$clipboardLine)) {
            $rowCobMatch = [regex]::Match($lineText, '\bCOB\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($rowCobMatch.Success) {
                $selectionPrefix = $lineText.Substring(0, $rowCobMatch.Index)
                $selectionBCount = [regex]::Matches($selectionPrefix, 'B', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
            }
        }
        $componentName = ''
        if ($cobLines.ContainsKey([int]$clipboardLine)) {
            $componentMatch = [regex]::Match($lineText, '\bCOB\b\s+(?<name>[A-Za-z0-9@#$._-]+)(?=\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($componentMatch.Success) { $componentName = [string]$componentMatch.Groups['name'].Value }
        }
        $rows.Add([pscustomobject]@{
            LineIndex = $screenRow
            ColIndex  = $selectionColumn
            HasCob    = $cobLines.ContainsKey([int]$clipboardLine)
            ClipboardLineIndex = [int]$clipboardLine
            LineText = $lineText
            BCount  = [int]$selectionBCount
            ComponentName = $componentName
        })
    }
    return $rows
}

# Let the user choose the first COB component by its list number or
# identifier from the initial scan's already-copied terminal text. The
# selected screen row applies only to the initial scan; later F8 pages
# always start at the first COB row automatically.
function Select-InitialRepositoryCobStart {
    param(
        [string]$Text,
        $Pipeline
    )

    $s1 = $Pipeline.Screen1Select
    $pageRows = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
    $rows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $pageRows)
    $candidates = New-Object System.Collections.Generic.List[object]
    for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
        $row = $rows[$rowIndex]
        $name = [string]$row.ComponentName
        # Filter/header entries such as DF* contain a wildcard and are
        # not real repository components that can be selected.
        if ([bool]$row.HasCob -and -not [string]::IsNullOrWhiteSpace($name) -and $name -notmatch '[*?]') {
            $candidates.Add([pscustomobject]@{ Number = $candidates.Count + 1; RowIndex = $rowIndex; LineIndex = [int]$row.LineIndex; Name = $name })
        }
    }
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Accepted = $true; Cancelled = $false; Reason = ''; LineIndex = -1; Name = '' }
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Click the first COB component to process'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.TopMost = $true
    $dialog.ClientSize = New-Object System.Drawing.Size(520, 620)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = "Found $($candidates.Count) COB components on this page. Click the row where processing should start:"
    $intro.Location = New-Object System.Drawing.Point(12, 12)
    $intro.Size = New-Object System.Drawing.Size(496, 36)

    $listPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $listPanel.Location = New-Object System.Drawing.Point(12, 54)
    $listPanel.Size = New-Object System.Drawing.Size(496, 510)
    $listPanel.AutoScroll = $true
    $listPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $listPanel.WrapContents = $false
    $listPanel.Padding = New-Object System.Windows.Forms.Padding(4)

    foreach ($candidate in $candidates) {
        $componentButton = New-Object System.Windows.Forms.Button
        $componentButton.Text = ('{0,2}.   {1}' -f $candidate.Number, $candidate.Name)
        $componentButton.Size = New-Object System.Drawing.Size(460, 34)
        $componentButton.Margin = New-Object System.Windows.Forms.Padding(2)
        $componentButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $componentButton.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $componentButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System

        # Capture this specific row for its click handler, then close the
        # picker immediately so one click starts processing at that row.
        $choiceRow = $candidate
        $currentDialog = $dialog
        $clickHandler = {
            $currentDialog.Tag = $choiceRow
            $currentDialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $currentDialog.Close()
        }.GetNewClosure()
        $componentButton.Add_Click($clickHandler)
        [void]$listPanel.Controls.Add($componentButton)
    }

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Location = New-Object System.Drawing.Point(418, 576)
    $cancelButton.Size = New-Object System.Drawing.Size(78, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($intro, $listPanel, $cancelButton))
    $dialog.CancelButton = $cancelButton

    $dialogResult = $dialog.ShowDialog()
    $chosenRow = $dialog.Tag
    $dialog.Dispose()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $chosenRow) {
        return [pscustomobject]@{ Accepted = $false; Cancelled = $true; Reason = ''; LineIndex = -1; Name = '' }
    }
    return [pscustomobject]@{ Accepted = $true; Cancelled = $false; Reason = ''; LineIndex = [int]$chosenRow.LineIndex; Name = [string]$chosenRow.Name }
}

# Record row-specific failures with the complete repository row from the
# clipboard, then recover to REPOSITORY LIST and resume at the next row.
function Skip-PipelineRowAfterFailure {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string]$ObservedText = '',
        [switch]$RepositoryListCommandMayBePresent
    )

    $pipeline = $global:CR_ActivePipelineConfig
    $rowIndex = [int]$global:CR_PipelineComponentIdx
    $row = $null
    if ($rowIndex -ge 0 -and $rowIndex -lt $global:CR_PipelineScreen1Rows.Count) {
        $row = $global:CR_PipelineScreen1Rows[$rowIndex]
    }
    $rowData = if ($null -ne $row -and $row.PSObject.Properties.Name -contains 'LineText') { [string]$row.LineText } else { '[row text unavailable]' }
    $screenRow = if ($null -ne $row) { [string]$row.LineIndex } else { '[unknown]' }
    $cobOrdinal = 0
    for ($i = 0; $i -le $rowIndex -and $i -lt $global:CR_PipelineScreen1Rows.Count; $i++) {
        if ([bool]$global:CR_PipelineScreen1Rows[$i].HasCob) { $cobOrdinal++ }
    }
    $pageNumber = [int]$global:CR_PipelineScreen1PageIdx + 1
    $rowNumber = $rowIndex + 1
    $failurePath = Join-Path $LogDir 'pipeline_failed_rows.txt'
    $entry = @(
        "===== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====",
        "Pipeline: $($pipeline.Name)",
        "Repository page: $pageNumber; COB number on page: $cobOrdinal; row slot: $rowNumber; screen row: $screenRow",
        "Failure: $Reason",
        "Repository row data: $rowData"
    )
    if (-not [string]::IsNullOrWhiteSpace($ObservedText)) {
        $entry += 'Observed screen clipboard text:'
        $entry += $ObservedText
    }
    $entry += ''
    if (-not $global:CR_PipelineFailureRowLogged) {
        try {
            Add-Content -LiteralPath $failurePath -Value $entry -Encoding UTF8
            $global:CR_PipelineFailureRowLogged = $true
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Logged failed repository row $rowNumber to $failurePath" -ForegroundColor Yellow
        } catch {
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not write failed-row log '$failurePath': $_" -ForegroundColor Red
        }
    }

    $global:CR_PipelineScreen1RetryCount = 0
    $global:CR_PipelineStepPending = $false
    $global:CR_PipelineStepConfirmed = $false
    $global:CR_PipelineStepDescription = ''
    Hide-StepMarker
    if ($RepositoryListCommandMayBePresent -or [int]$global:CR_PipelineCurrentScreen -eq 1) {
        if ($RepositoryListCommandMayBePresent) {
            $currentRow = if ($rowIndex -ge 0 -and $rowIndex -lt $global:CR_PipelineScreen1Rows.Count) { $global:CR_PipelineScreen1Rows[$rowIndex] } else { $null }
            if ($null -ne $currentRow -and [bool]$currentRow.HasCob -and [int]$currentRow.BCount -gt 0) {
                $global:CR_PipelineCleanupLineIndex = [int]$currentRow.LineIndex
                $global:CR_PipelineCleanupKeepCount = 0
                $global:CR_PipelineCleanupResumeState = 'CompNext_Action'
                $global:CR_PipelineCleanupRetryCount = 0
                $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
            } else {
                $global:CR_PipelineState = 'CompNext_Action'
            }
        } else {
            $global:CR_PipelineState = 'CompNext_Action'
        }
    } else {
        $global:CR_PipelineAfterBack = 'CompNext_Action'
        $global:CR_PipelineBackRetryCount = 0
        $global:CR_PipelineState = 'Back_Action'
    }
    $global:CR_ElapsedMs = 0
    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Row $rowNumber failed; returning to REPOSITORY LIST and continuing" ([System.Drawing.Color]::Orange)
}

# Keep a dedicated, append-only list of COMPONENT VERSION rows rejected by
# the mainframe as unavailable, tied back to their repository component.
function Add-ComponentUnavailableNote {
    param(
        [string]$Environment = '',
        [int]$AttemptNumber = 0
    )

    $rowIndex = [int]$global:CR_PipelineComponentIdx
    $row = if ($rowIndex -ge 0 -and $rowIndex -lt $global:CR_PipelineScreen1Rows.Count) { $global:CR_PipelineScreen1Rows[$rowIndex] } else { $null }
    $componentName = if ($null -ne $row -and $row.PSObject.Properties.Name -contains 'ComponentName') { [string]$row.ComponentName } else { '' }
    $repositoryRow = if ($null -ne $row -and $row.PSObject.Properties.Name -contains 'LineText') { [string]$row.LineText } else { '' }
    if ([string]::IsNullOrWhiteSpace($componentName) -and -not [string]::IsNullOrWhiteSpace($repositoryRow)) {
        $nameMatch = [regex]::Match($repositoryRow, '\bCOB\b\s+(?<name>[A-Za-z0-9@#$._-]+)(?=\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($nameMatch.Success) { $componentName = [string]$nameMatch.Groups['name'].Value }
    }
    if ([string]::IsNullOrWhiteSpace($componentName)) { $componentName = '[unknown]' }

    $notePath = Join-Path $LogDir 'component_unavailable.csv'
    $note = [pscustomobject][ordered]@{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Pipeline = [string]$global:CR_ActivePipelineConfig.Name
        RepositoryPage = [int]$global:CR_PipelineScreen1PageIdx + 1
        ComponentName = $componentName
        RepositoryRow = $repositoryRow
        ErrorText = if ([string]::IsNullOrWhiteSpace($Environment)) { 'Component unavailable' } else { "Component unavailable ($Environment, attempt $AttemptNumber)" }
    }
    try {
        if (Test-Path -LiteralPath $notePath) {
            $note | Export-Csv -Path $notePath -NoTypeInformation -Encoding UTF8 -Append
        } else {
            $note | Export-Csv -Path $notePath -NoTypeInformation -Encoding UTF8
        }
        Write-Host "[AutoClipCapture] [$($global:CR_ActivePipelineConfig.Name)] Recorded Component unavailable for '$componentName' in $notePath" -ForegroundColor Yellow
    } catch {
        Write-Host "[AutoClipCapture] Could not record Component unavailable for '$componentName' in '$notePath': $_" -ForegroundColor Red
    }
    return $componentName
}

# REPOSITORY LIST shows its own "Row <first> of <total>" indicator
# (top-right of the panel). This works out how many real data rows are
# on the CURRENT page from that indicator, so the last page of a list -
# which is almost never a full RowsPerPage rows, e.g. 570 total rows
# over pages of 25 leaves a final page with only 20, not 25 - doesn't
# get treated as if it had RowsPerPage rows. Falls back to RowsPerPage
# whenever the indicator can't be found or doesn't shrink the count, so
# this can only ever trim a page down, never break a normal full page.
function Get-Screen1RowsOnPage {
    param(
        [string]$Text,
        [int]$RowsPerPage
    )
    if ($Text -match 'Row\s+(\d+)\s+of\s+(\d+)') {
        $first = [int]$Matches[1]
        $total = [int]$Matches[2]
        $remaining = $total - $first + 1
        if ($remaining -gt 0 -and $remaining -lt $RowsPerPage) {
            return $remaining
        }
    }
    return $RowsPerPage
}

# The REPOSITORY LIST command prompt has two protected blank cells
# immediately after "Command ===> ". Other text later on that same line
# is normal and must not block row processing.
function Assert-Screen1CommandFieldEmpty {
    param(
        [string]$Text,
        [string]$PipelineName
    )

    if ([string]::IsNullOrEmpty($Text)) { return $true }
    $commandPrompt = [regex]::Match($Text, '(?im)^[ \t]*Command[ \t]*===>')
    if (-not $commandPrompt.Success) { return $true }

    $lineEnd = $Text.IndexOfAny([char[]]@("`r", "`n"), $commandPrompt.Index)
    if ($lineEnd -lt 0) { $lineEnd = $Text.Length }
    $suffixStart = $commandPrompt.Index + $commandPrompt.Length
    $afterPrompt = $Text.Substring($suffixStart, ($lineEnd - $suffixStart))
    # The visible prompt ends with one separator space. Check only the two
    # cells after that space; text farther right on the line is legitimate.
    if ($afterPrompt.StartsWith(' ') -or $afterPrompt.StartsWith("`t")) {
        $afterPrompt = $afterPrompt.Substring(1)
    }
    $checkLength = [Math]::Min(2, $afterPrompt.Length)
    if ($checkLength -eq 0 -or [string]::IsNullOrWhiteSpace($afterPrompt.Substring(0, $checkLength))) {
        return $true
    }

    $commandText = $afterPrompt.Substring(0, $checkLength)
    Write-Host "[AutoClipCapture] [$PipelineName] REPOSITORY LIST has text in the two protected cells after 'Command ===> ' ('$commandText'). Stopping before another row can be selected." -ForegroundColor Red
    Show-RelayResultOverlay -Text "COMMAND FIELD NOT EMPTY - STOPPED" -Color ([System.Drawing.Color]::Red)
    Stop-PipelineCapture
    return $false
}

# Works out the on-screen (screen-coordinate) point for a COB row,
# using the OriginX/OriginY/CharWidthPx/CharHeightPx calibration
# CalibrateScreen1Auto.ps1 produces and the anchored row/selection
# column generated from the current page's copied text.
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
    if ($null -eq $Screen1Select.TerminalLeft -or $null -eq $Screen1Select.TerminalTop -or
        $null -eq $Screen1Select.TerminalWidth -or $null -eq $Screen1Select.TerminalHeight -or
        $null -eq $Screen1Select.TerminalColumns -or $null -eq $Screen1Select.TerminalRows -or
        $null -eq $Screen1Select.CalibrationClientWidth -or $null -eq $Screen1Select.CalibrationClientHeight) { return $null }

    $clientRect = New-Object RECT
    [void][Win32]::GetClientRect($Handle, [ref]$clientRect)
    if (($clientRect.Right - $clientRect.Left) -ne [int]$Screen1Select.CalibrationClientWidth -or
        ($clientRect.Bottom - $clientRect.Top) -ne [int]$Screen1Select.CalibrationClientHeight) { return $null }
    if ($LineIndex -lt 0 -or $LineIndex -ge [int]$Screen1Select.TerminalRows -or
        $targetColIndex -lt 0 -or $targetColIndex -ge [int]$Screen1Select.TerminalColumns) { return $null }

    $clientX = [double]$Screen1Select.OriginX + ($targetColIndex * [double]$Screen1Select.CharWidthPx)
    $clientY = [double]$Screen1Select.OriginY + ($LineIndex * [double]$Screen1Select.CharHeightPx)
    $left = [double]$Screen1Select.TerminalLeft
    $top = [double]$Screen1Select.TerminalTop
    $right = $left + [double]$Screen1Select.TerminalWidth
    $bottom = $top + [double]$Screen1Select.TerminalHeight
    if ($clientX -lt $left -or $clientX -ge $right -or $clientY -lt $top -or $clientY -ge $bottom) { return $null }

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

    if (-not [Win32]::SetCursorPos($ScreenPoint.X, $ScreenPoint.Y)) { return $false }
    Start-Sleep -Milliseconds 50
    if (-not [Win32]::ClickLeftAtCurrentCursor()) { return $false }
    Start-Sleep -Milliseconds 75
    return $true
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

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying REPOSITORY LIST page $($global:CR_PipelineScreen1PageIdx + 1)" ([System.Drawing.Color]::Lime)
            # Read the page's own "Row <first> of <total>" indicator
            # before assuming it's a full RowsPerPage rows - matters if
            # the pipeline is started while already sitting on a
            # partial (typically the very last) page.
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            $global:CR_PipelineState = 'CompScan_Copy'
            $global:CR_ElapsedMs     = 0
        }

        'CompScan_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.InitialScanAfterClipboardCopyMs) {
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
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Expected REPOSITORY LIST before scanning a page, detected screen $detected. Stopping without clicking." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "REPOSITORY LIST NOT FOUND - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                if (-not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }

                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Analyzing REPOSITORY LIST page $($global:CR_PipelineScreen1PageIdx + 1); looking for COB rows" ([System.Drawing.Color]::Lime)
                $global:CR_PipelineScreen1IsLastPage = Test-RelayTextContains -Text $text -Needle ([string]$s1.EndOfListText)
                $rowCount = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
                $global:CR_PipelineScreen1PrevPageText = $text
                $global:CR_PipelineScreen1Rows   = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $rowCount)
                $global:CR_PipelineComponentIdx  = 0
                $startPickerWasShown = $false
                if ([bool]$global:CR_PipelineStartPickerPending) {
                    $global:CR_PipelineStartPickerPending = $false
                    $timer.Stop()
                    $startChoice = Select-InitialRepositoryCobStart -Text $text -Pipeline $pipeline
                    if (-not $startChoice.Accepted) {
                        if ($startChoice.Cancelled) {
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Start cancelled in the component picker." -ForegroundColor Yellow
                        } else {
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not choose a starting component: $($startChoice.Reason)" -ForegroundColor Red
                            [void][System.Windows.Forms.MessageBox]::Show([string]$startChoice.Reason, 'Cannot choose a COB component', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        }
                        Stop-PipelineCapture
                        return
                    }
                    $global:CR_PipelineStartRowLineIndex = [int]$startChoice.LineIndex
                    $global:CR_PipelineStartRowName = [string]$startChoice.Name
                    $startPickerWasShown = $true
                }
                if ([int]$global:CR_PipelineStartRowLineIndex -ge 0) {
                    $selectedRowIndex = -1
                    for ($candidateIndex = 0; $candidateIndex -lt $global:CR_PipelineScreen1Rows.Count; $candidateIndex++) {
                        $candidateRow = $global:CR_PipelineScreen1Rows[$candidateIndex]
                        if ([int]$candidateRow.LineIndex -eq [int]$global:CR_PipelineStartRowLineIndex -and
                            [bool]$candidateRow.HasCob -and
                            [string]::Equals([string]$candidateRow.ComponentName, [string]$global:CR_PipelineStartRowName, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $selectedRowIndex = $candidateIndex
                            break
                        }
                    }
                    if ($selectedRowIndex -lt 0) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Selected component '$($global:CR_PipelineStartRowName)' was not present at the selected screen row on the initial scan. Stopping without clicking." -ForegroundColor Red
                        Show-RelayResultOverlay -Text 'SELECTED COMPONENT NOT FOUND - STOPPED' -Color ([System.Drawing.Color]::Red)
                        Stop-PipelineCapture
                        return
                    }
                    $global:CR_PipelineComponentIdx = $selectedRowIndex
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Starting at COB component $($global:CR_PipelineStartRowName) (screen row $($global:CR_PipelineStartRowLineIndex))." -ForegroundColor Cyan
                }
                # The chosen start row applies only to the first page. F8
                # initializes every later page at its first COB row.
                $global:CR_PipelineStartRowLineIndex = -1
                $global:CR_PipelineStartRowName = ''
                $global:CR_PipelineLastProcessedCobLineIndex = -1
                $global:CR_PipelineBWriteRetryCount = 0
                $global:CR_PipelineFailureRowLogged = $false
                $cobCount = @($global:CR_PipelineScreen1Rows | Where-Object { $_.HasCob }).Count
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Repository page $($global:CR_PipelineScreen1PageIdx + 1): found $cobCount COB row(s) across $($global:CR_PipelineScreen1Rows.Count) row slot(s) through the last COB." -ForegroundColor DarkCyan
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found $cobCount COB row(s) on REPOSITORY LIST page $($global:CR_PipelineScreen1PageIdx + 1)" ([System.Drawing.Color]::Lime)
                $global:CR_PipelineState = if ($global:CR_PipelineScreen1Rows.Count -gt 0) { 'CompZoom_Action' } else { 'CompNext_Action' }
                $global:CR_ElapsedMs     = 0
                if ($startPickerWasShown) { $timer.Start() }
            }
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
            if (-not [bool]$row.HasCob) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Skipping REPOSITORY LIST row slot $($rowIdx + 1) at screen row $($row.LineIndex): no COB text." -ForegroundColor DarkGray
                $global:CR_PipelineState = 'CompNext_Action'
                $global:CR_ElapsedMs = 0
                return
            }
            # The SOURCE CAPTURE COMPLETE banner may still be within its
            # display timeout when this row is reached. Hide it before
            # placing the cursor/clicking; click-through styling is a
            # second safeguard against overlays intercepting input.
            Hide-RelayResultOverlay
            if ([int]$row.BCount -gt 0) {
                $global:CR_PipelineCleanupLineIndex = [int]$row.LineIndex
                $global:CR_PipelineCleanupKeepCount = 0
                $global:CR_PipelineCleanupResumeState = 'CompZoom_Action'
                $global:CR_PipelineCleanupRetryCount = 0
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Target COB row $($row.LineIndex) already has B; clearing it before selecting this row" ([System.Drawing.Color]::Yellow)
                $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
                $global:CR_ElapsedMs = 0
                return
            }
            $cobOrdinal = @($global:CR_PipelineScreen1Rows | Select-Object -First ($rowIdx + 1) | Where-Object { $_.HasCob }).Count
            $cobTotal = @($global:CR_PipelineScreen1Rows | Where-Object { $_.HasCob }).Count
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Looking for COB row $cobOrdinal of $cobTotal at screen row $($row.LineIndex)" ([System.Drawing.Color]::Lime)
            $terminalRows = if ($null -ne $s1.TerminalRows) { [int]$s1.TerminalRows } else { 32 }
            $firstDataRow = [int]$s1.FirstDataRowLineIndex
            if ($s1.PSObject.Properties.Name -contains 'StartRowOffset' -and $null -ne $s1.StartRowOffset) {
                $firstDataRow += [int]$s1.StartRowOffset
            }
            $lastDataRow = [Math]::Min(($firstDataRow + [int]$s1.RowsPerPage - 1), ($terminalRows - 1))
            if ($row.LineIndex -lt $firstDataRow -or $row.LineIndex -gt $lastDataRow -or [string]$row.LineText -match '(?i)Command\s*===\s*>') {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Refusing to click screen row $($row.LineIndex): it is outside the calibrated REPOSITORY LIST data rows $firstDataRow-$lastDataRow, or the copied row is the command field." -ForegroundColor Red
                Show-RelayResultOverlay -Text "INVALID DATA ROW - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
            if ($null -eq $pt) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Calibrated terminal bounds no longer match the target point or window size. Recalibrate after terminal resize/font changes; stopping before click." -ForegroundColor Red
                Show-RelayResultOverlay -Text "TERMINAL CALIBRATION STALE - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)

            if (-not $global:CR_PipelineStepPending) {
                $wr = New-Object RECT
                [void][Win32]::GetWindowRect($global:CR_TargetHandle, [ref]$wr)
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Row $($rowIdx + 1): LineIndex=$($row.LineIndex) ColIndex=$($row.ColIndex) -> click ($($screenPt.X),$($screenPt.Y))  |  Screen1Select Origin=($($s1.OriginX),$($s1.OriginY)) CharSize=$($s1.CharWidthPx)x$($s1.CharHeightPx)  |  Target window bounds ($($wr.Left),$($wr.Top))-($($wr.Right),$($wr.Bottom))" -ForegroundColor DarkGray
                if ($screenPt.X -lt $wr.Left -or $screenPt.X -ge $wr.Right -or $screenPt.Y -lt $wr.Top -or $screenPt.Y -ge $wr.Bottom) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Click point is outside target window bounds. Stopping before click; recalibrate." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
            }

            # Shown BEFORE anything is clicked - the red circle marker
            # lands on $screenPt so a wrong target is obvious right
            # away, without a single click having happened yet.
            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - about to click here, type '$($s1.SelectionText)' + Enter"
            if (Request-PipelineStepConfirm -Description $desc -MarkerPoint $screenPt) { return }

            if ([int]$PipelineTimingsMs.RepositoryList.BeforeClickMs -gt 0) {
                Start-Sleep -Milliseconds ([int]$PipelineTimingsMs.RepositoryList.BeforeClickMs)
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            # Recompute after foregrounding and immediately before input:
            # restoring/moving the Host On-Demand window while the step
            # confirmation is open must never leave a stale click point.
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
            if ($null -eq $pt) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Terminal geometry changed while awaiting confirmation. Recalibrate; stopping before click." -ForegroundColor Red
                Show-RelayResultOverlay -Text "TERMINAL CALIBRATION STALE - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)
            $wr = New-Object RECT
            [void][Win32]::GetWindowRect($global:CR_TargetHandle, [ref]$wr)
            if ($screenPt.X -lt $wr.Left -or $screenPt.X -ge $wr.Right -or $screenPt.Y -lt $wr.Top -or $screenPt.Y -ge $wr.Bottom) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Click point is outside target window bounds after activation. Stopping before click; recalibrate." -ForegroundColor Red
                Stop-PipelineCapture
                return
            }

            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page $($global:CR_PipelineScreen1PageIdx + 1), row $($rowIdx + 1)/$($global:CR_PipelineScreen1Rows.Count) - selecting" ([System.Drawing.Color]::Lime)

            # Don't send HOME/DEL here. On this Host On-Demand screen,
            # HOME can focus the Show Deleted field, and DEL would erase
            # its N value. Click first, then give each key a separate
            # one-second stage so the terminal cannot merge/repeat input.
            if (-not (Invoke-Screen1RowClick -ScreenPoint $screenPt)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Windows did not accept the REPOSITORY LIST mouse click; stopping before typing B." -ForegroundColor Red
                Show-RelayResultOverlay -Text "ROW CLICK FAILED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Clicked selection cell for COB row $($rowIdx + 1); preparing B" ([System.Drawing.Color]::Lime)
            $global:CR_PipelineState = 'CompZoom_Type'
            $global:CR_ElapsedMs     = 0
        }

        'CompZoom_Type' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClickMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable before typing B.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText)
                    return
                }
                # Recompute and click again immediately before typing. A
                # cursor move alone is not proof the emulator received the
                # earlier click; never send B to whichever field had focus
                # before this row was selected.
                $rowIdx = [int]$global:CR_PipelineComponentIdx
                $row = $global:CR_PipelineScreen1Rows[$rowIdx]
                $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $row.LineIndex -ColIndex $row.ColIndex
                if ($null -eq $pt) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Terminal geometry changed before the REPOSITORY LIST click; stopping before typing B." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "TERMINAL CALIBRATION STALE - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)
                if (-not (Invoke-Screen1RowClick -ScreenPoint $screenPt)) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Windows did not accept the immediate pre-type row click; stopping before typing B." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "ROW CLICK FAILED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                # Advance before SendWait: it can pump Windows messages,
                # so a nested timer tick must never dispatch a second B.
                # Enter is the very next terminal key after B; copying or
                # clicking between them can leave HOD outside the row field.
                $global:CR_PipelineState = 'CompZoom_Enter'
                $global:CR_ElapsedMs = 0
                $selectionText = [string]$s1.SelectionText
                if ($selectionText -cne 'B' -or -not [Win32]::SendUnicodeCharacter([char]$selectionText[0])) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not send the literal selection character '$selectionText'; stopping before Enter." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "SELECTION KEY FAILED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Entered B for row $($global:CR_PipelineComponentIdx + 1); preparing immediate Enter" ([System.Drawing.Color]::Lime)
            }
        }

        'CompZoom_VerifyWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterSelectionLetterMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable while verifying B on the REPOSITORY LIST row.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText)
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying REPOSITORY LIST to verify B placement before Enter" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompZoom_VerifyCopy'
                $global:CR_ElapsedMs = 0
            }
        }

        'CompZoom_VerifyCopy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) { $text = [System.Windows.Forms.Clipboard]::GetText() }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed while verifying B: $_" -ForegroundColor Yellow
                }
                $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                if ($detected -ne 1) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Expected REPOSITORY LIST while verifying B before Enter; detected screen $detected. Stopping safely." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "ROW SELECTION UNVERIFIED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                if (-not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }

                $rowCount = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
                $freshRows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $rowCount)
                $global:CR_PipelineScreen1Rows = $freshRows
                $global:CR_PipelineScreen1PrevPageText = $text
                $rowIdx = [int]$global:CR_PipelineComponentIdx
                $targetRow = if ($rowIdx -ge 0 -and $rowIdx -lt $freshRows.Count) { $freshRows[$rowIdx] } else { $null }
                if ($null -eq $targetRow -or -not $targetRow.HasCob) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not map the active COB row in the fresh REPOSITORY LIST copy; stopping before Enter." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "ROW SELECTION UNVERIFIED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }

                $lastProcessedLine = [int]$global:CR_PipelineLastProcessedCobLineIndex
                $previousRow = @($freshRows | Where-Object { [int]$_.LineIndex -eq $lastProcessedLine -and $_.HasCob } | Select-Object -First 1)
                if ($lastProcessedLine -ge 0 -and $lastProcessedLine -ne [int]$targetRow.LineIndex -and $previousRow.Count -gt 0 -and [int]$previousRow[0].BCount -gt 0) {
                    $global:CR_PipelineCleanupLineIndex = $lastProcessedLine
                    $global:CR_PipelineCleanupKeepCount = 0
                    $global:CR_PipelineCleanupResumeState = 'CompZoom_VerifyWait'
                    $global:CR_PipelineCleanupRetryCount = 0
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Previous COB row $lastProcessedLine still has B; clearing that exact row before Enter" ([System.Drawing.Color]::Yellow)
                    $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
                    $global:CR_ElapsedMs = 0
                    return
                }

                if ([int]$targetRow.BCount -eq 1) {
                    $global:CR_PipelineLastProcessedCobLineIndex = [int]$targetRow.LineIndex
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Verified one B on target COB row $($targetRow.LineIndex) and cleared the previous row if needed; pressing Enter next" ([System.Drawing.Color]::Lime)
                    $global:CR_PipelineState = 'CompZoom_Enter'
                    $global:CR_ElapsedMs = 0
                } elseif ([int]$targetRow.BCount -gt 1) {
                    $global:CR_PipelineCleanupLineIndex = [int]$targetRow.LineIndex
                    $global:CR_PipelineCleanupKeepCount = 1
                    $global:CR_PipelineCleanupResumeState = 'CompZoom_VerifyWait'
                    $global:CR_PipelineCleanupRetryCount = 0
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found $($targetRow.BCount) B characters at the target; removing extras before Enter" ([System.Drawing.Color]::Yellow)
                    $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
                    $global:CR_ElapsedMs = 0
                } else {
                    $global:CR_PipelineBWriteRetryCount++
                    $maxBWriteRetries = [Math]::Max(1, [int]$s1.MaxRowRetries)
                    if ($global:CR_PipelineBWriteRetryCount -gt $maxBWriteRetries) {
                        Skip-PipelineRowAfterFailure -Reason 'B was not visible in the active COB selection cell after repeated click/type attempts; Enter was not sent.' -ObservedText $text
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] B was not found on target row; retrying click and B ($($global:CR_PipelineBWriteRetryCount)/$maxBWriteRetries)" ([System.Drawing.Color]::Yellow)
                    $global:CR_PipelineState = 'CompZoom_Type'
                    $global:CR_ElapsedMs = 0
                }
            }
        }

        'CompZoom_Cleanup_Action' {
            $cleanupLine = [int]$global:CR_PipelineCleanupLineIndex
            $cleanupRow = @($global:CR_PipelineScreen1Rows | Where-Object { [int]$_.LineIndex -eq $cleanupLine } | Select-Object -First 1)
            if ($cleanupRow.Count -eq 0 -or -not $cleanupRow[0].HasCob) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not locate stale B at screen row $cleanupLine; stopping before Delete." -ForegroundColor Red
                Show-RelayResultOverlay -Text "STALE B ROW NOT FOUND - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            $cleanupRow = $cleanupRow[0]
            if ([int]$cleanupRow.BCount -le [int]$global:CR_PipelineCleanupKeepCount) {
                $global:CR_PipelineState = [string]$global:CR_PipelineCleanupResumeState
                $global:CR_ElapsedMs = 0
                return
            }
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $cleanupRow.LineIndex -ColIndex $cleanupRow.ColIndex
            if ($null -eq $pt) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Stale B row $cleanupLine is outside calibrated terminal bounds; stopping before Delete." -ForegroundColor Red
                Show-RelayResultOverlay -Text "STALE B CLICK OUT OF BOUNDS - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable while clearing a stale repository B.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText)
                return
            }
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Clicking old selection at screen row $cleanupLine to clear B" ([System.Drawing.Color]::Yellow)
            if (-not (Invoke-Screen1RowClick -ScreenPoint $screenPt)) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Windows did not accept click on stale B row $cleanupLine; stopping before Delete." -ForegroundColor Red
                Show-RelayResultOverlay -Text "STALE B CLICK FAILED - STOPPED" -Color ([System.Drawing.Color]::Red)
                Stop-PipelineCapture
                return
            }
            $global:CR_PipelineState = 'CompZoom_CleanupDeleteWait'
            $global:CR_ElapsedMs = 0
        }

        'CompZoom_CleanupDeleteWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClickMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable before deleting a stale B.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText)
                    return
                }
                $cleanupRow = @($global:CR_PipelineScreen1Rows | Where-Object { [int]$_.LineIndex -eq [int]$global:CR_PipelineCleanupLineIndex } | Select-Object -First 1)
                if ($cleanupRow.Count -eq 0) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Stale B row disappeared before Delete; stopping safely." -ForegroundColor Red
                    Stop-PipelineCapture
                    return
                }
                $deleteCount = [Math]::Max(1, ([int]$cleanupRow[0].BCount - [int]$global:CR_PipelineCleanupKeepCount))
                $global:CR_PipelineState = 'CompZoom_CleanupVerifyWait'
                $global:CR_ElapsedMs = 0
                for ($deleteIndex = 0; $deleteIndex -lt $deleteCount; $deleteIndex++) {
                    [System.Windows.Forms.SendKeys]::SendWait('{DELETE}')
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Deleted $deleteCount B character(s) from old row; copying page to verify" ([System.Drawing.Color]::Yellow)
            }
        }

        'CompZoom_CleanupVerifyWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterDeleteMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable while verifying that stale B was deleted.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText)
                    return
                }
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompZoom_CleanupCopy'
                $global:CR_ElapsedMs = 0
            }
        }

        'CompZoom_CleanupCopy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) { $text = [System.Windows.Forms.Clipboard]::GetText() }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed while checking stale B cleanup: $_" -ForegroundColor Yellow
                }
                $detected = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                if ($detected -ne 1) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] REPOSITORY LIST was not visible after deleting stale B; stopping before typing or Enter." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "STALE B CLEANUP UNVERIFIED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                if (-not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }
                $rowCount = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
                $freshRows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $rowCount)
                $global:CR_PipelineScreen1Rows = $freshRows
                $global:CR_PipelineScreen1PrevPageText = $text
                $cleanupRow = @($freshRows | Where-Object { [int]$_.LineIndex -eq [int]$global:CR_PipelineCleanupLineIndex } | Select-Object -First 1)
                if ($cleanupRow.Count -eq 0) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Could not map screen row $($global:CR_PipelineCleanupLineIndex) after Delete; stopping before continuing." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "CLEANUP ROW NOT FOUND - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                if ([int]$cleanupRow[0].BCount -gt [int]$global:CR_PipelineCleanupKeepCount) {
                    $global:CR_PipelineCleanupRetryCount++
                    if ($global:CR_PipelineCleanupRetryCount -gt 1) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] B is still present at old row $($global:CR_PipelineCleanupLineIndex) after retry; stopping before processing another row." -ForegroundColor Red
                        Show-RelayResultOverlay -Text "OLD B STILL PRESENT - STOPPED" -Color ([System.Drawing.Color]::Red)
                        Stop-PipelineCapture
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Old row still contains B; retrying clear once" ([System.Drawing.Color]::Yellow)
                    $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
                    $global:CR_ElapsedMs = 0
                    return
                }
                if ([int]$global:CR_PipelineCleanupKeepCount -eq 1) {
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Verified target row has exactly one B" ([System.Drawing.Color]::Lime)
                } else {
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Verified old row has no B" ([System.Drawing.Color]::Lime)
                }
                $global:CR_PipelineState = [string]$global:CR_PipelineCleanupResumeState
                $global:CR_ElapsedMs = 0
            }
        }

        'CompZoom_Enter' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterSelectionLetterMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable before pressing Enter after B.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText) -RepositoryListCommandMayBePresent
                    return
                }
                $rowIdx = [int]$global:CR_PipelineComponentIdx
                $row = if ($rowIdx -ge 0 -and $rowIdx -lt $global:CR_PipelineScreen1Rows.Count) { $global:CR_PipelineScreen1Rows[$rowIdx] } else { $null }
                if ($null -eq $row -or -not [bool]$row.HasCob) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] The active COB row is no longer mapped; stopping before Enter." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "COB ROW CHANGED - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                $global:CR_PipelineLastProcessedCobLineIndex = [int]$row.LineIndex
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Sending Enter immediately after B on COB row $($row.LineIndex)" ([System.Drawing.Color]::Lime)
                $global:CR_PipelineState = 'CompZoom_Wait'
                $global:CR_ElapsedMs = 0
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            }
        }

        'CompZoom_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterEnterMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable while waiting for COMPONENT VERSION.' -ObservedText ([string]$global:CR_PipelineScreen1PrevPageText) -RepositoryListCommandMayBePresent
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying screen after Enter; looking for COMPONENT VERSION" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'CompZoom_Copy'
                $global:CR_ElapsedMs     = 0
            }
        }

        'CompZoom_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs) {
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
                    # Landed on the COMPONENT VERSION page, recognized by
                    # COMPONENT VERSION on clipboard row 0. Hand off to
                    # Screen2.ps1 to log it and select its source row.
                    $global:CR_PipelineScreen1RetryCount   = 0
                    $global:CR_PipelineScreen2CapturedText = $text
                    $global:CR_PipelineScreen2BeforeSelectionText = $text
                    $global:CR_PipelineSourceSelectionSent = $false
                    $global:CR_PipelineSourceCandidateIdx = 0
                    $global:CR_PipelineSourceCandidates = @()
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found COMPONENT VERSION after Enter" ([System.Drawing.Color]::Lime)
                    $global:CR_PipelineState = 'EnvLog_Action'
                    $global:CR_ElapsedMs     = 0
                }
                elseif ($detected -eq 1) {
                    if (-not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }
                    $rowCount = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
                    $freshRows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $rowCount)
                    $activeRowIndex = [int]$global:CR_PipelineComponentIdx
                    if ($activeRowIndex -ge 0 -and $activeRowIndex -lt $freshRows.Count) {
                        $activeRow = $freshRows[$activeRowIndex]
                        if ($activeRow.HasCob) {
                            $cobMatch = [regex]::Match([string]$activeRow.LineText, '\bCOB\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                            $selectionPrefix = if ($cobMatch.Success) { ([string]$activeRow.LineText).Substring(0, $cobMatch.Index).Trim() } else { '' }
                            $selectionCodes = @($selectionPrefix.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int][char]$_ }) -join ' '
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Copied selection field after Enter: '$selectionPrefix' (Unicode $selectionCodes), expected exactly 'B' before COB." -ForegroundColor Yellow
                        }
                    }
                    if ($freshRows.Count -ne $global:CR_PipelineScreen1Rows.Count) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] REPOSITORY LIST row count changed after Enter ($($global:CR_PipelineScreen1Rows.Count) -> $($freshRows.Count)); stopping before recovery." -ForegroundColor Red
                        Show-RelayResultOverlay -Text "REPOSITORY ROW COUNT CHANGED - STOPPED" -Color ([System.Drawing.Color]::Red)
                        Stop-PipelineCapture
                        return
                    }
                    $previousRepositoryText = [string]$global:CR_PipelineScreen1PrevPageText
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] COMPONENT VERSION not found; still on REPOSITORY LIST" ([System.Drawing.Color]::Yellow)
                    $rejected = Test-RelayTextContains -Text $text -Needle ([string]$s1.InvalidCommandText)
                    $topRightChanged = Test-PipelineTopRightChanged -Before $previousRepositoryText -After $text
                    $global:CR_PipelineScreen1Rows = $freshRows
                    $global:CR_PipelineScreen1PrevPageText = $text
                    if ($rejected -or $topRightChanged) {
                        $reason = 'REPOSITORY LIST stayed open and its top-right message changed after B/Enter.'
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Removing B, logging the row, and continuing." -ForegroundColor Yellow
                        Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text -RepositoryListCommandMayBePresent
                    } else {
                        # Enter should have opened COMPONENT VERSION. Keep
                        # checking this same page briefly for a delayed
                        # transition; never advance to another row unless
                        # we observed COMPONENT VERSION, selected its source,
                        # verified source code, and F3 returned
                        # us to REPOSITORY LIST.
                        $global:CR_PipelineScreen1RetryCount++
                        $maxRetries = [int]$s1.MaxRowRetries
                        if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                            $reason = 'COMPONENT VERSION did not open after B/Enter; REPOSITORY LIST remained visible.'
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Removing B, logging the row, and continuing." -ForegroundColor Yellow
                            Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text -RepositoryListCommandMayBePresent
                            return
                        }
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Still on REPOSITORY LIST after Enter; retrying Enter on the same B row without typing another B ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                        $global:CR_PipelineState = 'CompZoom_Enter'
                        $global:CR_ElapsedMs     = 0
                    }
                }
                else {
                    # Do not click again while the terminal is on a page
                    # we cannot identify. Recapture after a delay; a row
                    # advances only through COMPONENT VERSION -> source
                    # code -> F3 -> verified REPOSITORY LIST.
                    $global:CR_PipelineScreen1RetryCount++
                    $maxRetries = [int]$s1.MaxRowRetries
                    if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                        $reason = 'Unrecognized page appeared after B/Enter.'
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and trying F3 to return to REPOSITORY LIST." -ForegroundColor Yellow
                        Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text
                        return
                    } else {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Unrecognized page after Enter; recapturing without clicking again ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                        $global:CR_PipelineState = 'CompZoom_Wait'
                    }
                    $global:CR_ElapsedMs = 0
                }
            }
        }

        'CompNext_Action' {
            $lastProcessedLine = [int]$global:CR_PipelineLastProcessedCobLineIndex
            $previousRow = @($global:CR_PipelineScreen1Rows | Where-Object { [int]$_.LineIndex -eq $lastProcessedLine -and $_.HasCob } | Select-Object -First 1)
            if ($lastProcessedLine -ge 0 -and $previousRow.Count -gt 0 -and [int]$previousRow[0].BCount -gt 0) {
                $global:CR_PipelineCleanupLineIndex = $lastProcessedLine
                $global:CR_PipelineCleanupKeepCount = 0
                $global:CR_PipelineCleanupResumeState = 'CompNext_Action'
                $global:CR_PipelineCleanupRetryCount = 0
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Before advancing, checking previous COB row $lastProcessedLine; clearing its B before moving on" ([System.Drawing.Color]::Yellow)
                $global:CR_PipelineState = 'CompZoom_Cleanup_Action'
                $global:CR_ElapsedMs = 0
                return
            }
            $global:CR_PipelineLastProcessedCobLineIndex = -1
            $nextRow = -1
            for ($candidateIndex = ([int]$global:CR_PipelineComponentIdx + 1); $candidateIndex -lt $global:CR_PipelineScreen1Rows.Count; $candidateIndex++) {
                if ([bool]$global:CR_PipelineScreen1Rows[$candidateIndex].HasCob) {
                    $nextRow = $candidateIndex
                    break
                }
            }
            if ($nextRow -ge 0) {
                $global:CR_PipelineComponentIdx = $nextRow
                $global:CR_PipelineBWriteRetryCount = 0
                $global:CR_PipelineFailureRowLogged = $false
                $nextCobOrdinal = @($global:CR_PipelineScreen1Rows | Select-Object -First ($nextRow + 1) | Where-Object { $_.HasCob }).Count
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Advancing to COB row $nextCobOrdinal; checking its selection cell" ([System.Drawing.Color]::Lime)
                $global:CR_PipelineState = 'CompZoom_Action'
                $global:CR_ElapsedMs     = 0
            } else {
                if ([bool]$global:CR_PipelineScreen1IsLastPage) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Finished every COB row on the final REPOSITORY LIST page; Bottom of List is present, so no F8 is needed." -ForegroundColor Green
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Final REPOSITORY LIST page processed; complete" ([System.Drawing.Color]::Lime)
                    Show-RelayResultOverlay -Text "ALL REPOSITORY LIST PAGES PROCESSED" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }
                # Every COB row on this page has been processed. Put a
                # clear centered message on screen before paging forward.
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] All COB rows on page $($global:CR_PipelineScreen1PageIdx + 1) verified; preparing F8" ([System.Drawing.Color]::Lime)
                Show-RelayResultOverlay -Text "DONE PROCESSING THIS PAGE" -Color ([System.Drawing.Color]::LimeGreen)
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
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Sending $($s1.PageNextDisplay) to copy the next REPOSITORY LIST page" ([System.Drawing.Color]::Lime)
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Paging to next screen ($($s1.PageNextDisplay))" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait([string]$s1.PageNextToken)
            $global:CR_PipelineState = 'CompPage_Wait'
            $global:CR_ElapsedMs     = 0
        }

        'CompPage_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterPageKeyMs) {
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
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                        $text = [System.Windows.Forms.Clipboard]::GetText()
                    }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed: $_" -ForegroundColor Yellow
                }

                $pageScreen = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                if ($pageScreen -ne 1) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Expected REPOSITORY LIST after paging, detected screen $pageScreen. Stopping without scanning." -ForegroundColor Red
                    Show-RelayResultOverlay -Text "REPOSITORY LIST NOT FOUND - STOPPED" -Color ([System.Drawing.Color]::Red)
                    Stop-PipelineCapture
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Analyzing newly copied REPOSITORY LIST page" ([System.Drawing.Color]::Lime)
                if (-not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }

                $isEndOfList = Test-RelayTextContains -Text $text -Needle ([string]$s1.EndOfListText)
                $isDuplicate = $false
                if (-not $isEndOfList -and $null -ne $global:CR_PipelineScreen1PrevPageText) {
                    $similarity = Get-TextSimilarity -A $global:CR_PipelineScreen1PrevPageText -B $text
                    $isDuplicate = ($similarity -ge [double]$s1.DupDetectThreshold)
                }

                if ($isDuplicate -and -not $isEndOfList) {
                    $reason = 'next page matched the previous one - no new data'
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Done - $reason. Processed $($global:CR_PipelineScreen1PageIdx + 1) page(s)." -ForegroundColor Green
                    Show-RelayResultOverlay -Text "PIPELINE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }

                if ($isEndOfList) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Bottom of List is present on this REPOSITORY LIST page; scanning its COB rows as the final page." -ForegroundColor DarkCyan
                }

                # Page row count caps the clipboard-derived COB row list
                # on the final partially filled page. The first COB line
                # anchors at the calibrated screen row on every page.
                $rowCount = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$s1.RowsPerPage)
                $global:CR_PipelineScreen1IsLastPage = $isEndOfList
                $global:CR_PipelineScreen1PrevPageText = $text
                $nextPageRows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $s1 -RowCount $rowCount)
                $cobCount = @($nextPageRows | Where-Object { $_.HasCob }).Count
                $global:CR_PipelineScreen1PageIdx++
                if ($cobCount -eq 0) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] REPOSITORY LIST page $($global:CR_PipelineScreen1PageIdx + 1) has no COB rows. All COB rows have been processed." -ForegroundColor Green
                    Show-RelayResultOverlay -Text "ALL COB ROWS PROCESSED" -Color ([System.Drawing.Color]::LimeGreen)
                    Stop-PipelineCapture
                    return
                }

                $global:CR_PipelineScreen1Rows = $nextPageRows
                $global:CR_PipelineComponentIdx  = 0
                $global:CR_PipelineLastProcessedCobLineIndex = -1
                $global:CR_PipelineBWriteRetryCount = 0
                $global:CR_PipelineFailureRowLogged = $false
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Repository page $($global:CR_PipelineScreen1PageIdx + 1): found $cobCount COB row(s) across $($global:CR_PipelineScreen1Rows.Count) row slot(s) through the last COB." -ForegroundColor DarkCyan
                $global:CR_PipelineState = if ($global:CR_PipelineScreen1Rows.Count -gt 0) { 'CompZoom_Action' } else { 'CompNext_Action' }
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

 Screen 2 = COMPONENT VERSION. Log the page and try PROD/UT/ET markers
 in top-to-bottom order. If the mainframe reports Component unavailable,
 log that candidate and try the next environment row before returning to
 the repository. Check the selection cell two columns to the left: if it
 already contains S, press Enter without typing; otherwise type one S,
 then press Enter. Clipboard line indices are
 not treated as screen rows. Only after Screen 3's source-code menu is
 verified on row 0 does the shared F3 state return to Screen 1.

 States (start with "Env" so AutoClipCapture.ps1 routes them here):
   EnvLog_Action     - log the captured COMPONENT VERSION page.
   EnvSelect_Action  - locate the current PROD/UT/ET marker in copied
                       text and check its row-specific selection cell,
                       anchored to screen row 8 for the top candidate.
   EnvSelect_TypeWait - only if needed, wait and type one S.
   EnvSelect_EnterWait - wait and press Enter, with or without typing S.
   EnvSelect_Wait    - wait for the source-code screen to render.
   EnvSelect_Copy    - copy and verify the source-code menu on row 0;
                       only then start Auto Capture Current File.
=====================================================================
#>

function Invoke-PipelineScreen2Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    $s1       = $pipeline.Screen1Select

    switch ($global:CR_PipelineState) {

        'EnvLog_Action' {
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Logging COMPONENT VERSION page; then looking for PROD, UT, or ET" ([System.Drawing.Color]::Lime)
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

            $global:CR_PipelineState = 'EnvSelect_Action'
            $global:CR_ElapsedMs         = 0
        }

        'EnvSelect_Action' {
            $componentText = [string]$global:CR_PipelineScreen2CapturedText
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Analyzing COMPONENT VERSION page for PROD, UT, or ET rows" ([System.Drawing.Color]::Lime)
            $componentLines = @($componentText -split "`r`n|`r|`n")
            # Clipboard line positions are not screen row positions: some
            # terminal copies omit leading blank rows or headers. Find the
            # source marker as a column clue, anchor its topmost row at
            # screen row 8, and map later candidates by their line offset.
            $sourceCandidates = @()
            for ($lineIndex = 0; $lineIndex -lt $componentLines.Count; $lineIndex++) {
                $matches = [regex]::Matches($componentLines[$lineIndex], '\b(?:PROD|UT|ET)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $matches) {
                    $sourceCandidates += [pscustomobject]@{
                        Match = $match
                        Line = $componentLines[$lineIndex]
                        LineIndex = $lineIndex
                    }
                }
            }
            if ($sourceCandidates.Count -eq 0) {
                $reason = 'No PROD, UT, or ET marker was found in COMPONENT VERSION clipboard text.'
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Did not find PROD, UT, or ET; logging row failure and returning" ([System.Drawing.Color]::Yellow)
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }

            # Clipboard line order preserves top-to-bottom screen order.
            # Keep the rows ordered so an unavailable top choice can be
            # retried against the next PROD/UT/ET entry on this page.
            $sourceCandidates = @($sourceCandidates | Sort-Object LineIndex, @{ Expression = { $_.Match.Index } })
            $global:CR_PipelineSourceCandidates = @($sourceCandidates)
            $candidateIndex = [int]$global:CR_PipelineSourceCandidateIdx
            if ($candidateIndex -lt 0 -or $candidateIndex -ge $sourceCandidates.Count) {
                $reason = 'No remaining PROD, UT, or ET rows are available to try on COMPONENT VERSION.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            if ($sourceCandidates.Count -gt 1) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Found $($sourceCandidates.Count) PROD/UT/ET rows; trying row $($candidateIndex + 1) of $($sourceCandidates.Count), marker '$($sourceCandidates[$candidateIndex].Match.Value)'." -ForegroundColor DarkCyan
            }
            $selectedSourceCandidate = $sourceCandidates[$candidateIndex]
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Trying environment row $($candidateIndex + 1) of $($sourceCandidates.Count): $($selectedSourceCandidate.Match.Value)" ([System.Drawing.Color]::Lime)
            $sourceMatch = $selectedSourceCandidate.Match
            $sourceCol = $sourceMatch.Index - 2
            $sourceRow = 8 + ([int]$selectedSourceCandidate.LineIndex - [int]$sourceCandidates[0].LineIndex)
            if ($sourceCol -lt 0 -or $sourceCol -ge [int]$s1.TerminalColumns) {
                $reason = "Selection column two characters left of $($sourceMatch.Value) on COMPONENT VERSION row $sourceRow is outside the terminal grid."
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }

            $sourceLine = [string]$selectedSourceCandidate.Line
            $leftOfMarker = $sourceLine.Substring(0, [Math]::Min($sourceMatch.Index, $sourceLine.Length))
            $existingSelections = [regex]::Matches(
                $leftOfMarker,
                '(?<![A-Z0-9])S(?![A-Z0-9])',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            if ($existingSelections.Count -gt 1) {
                $reason = "COMPONENT VERSION row $sourceRow has more than one standalone S before $($sourceMatch.Value); skipped to avoid submitting an invalid command."
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            if ($existingSelections.Count -eq 1) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] COMPONENT VERSION row $sourceRow already has S before $($sourceMatch.Value); skipping S and pressing Enter only." -ForegroundColor DarkGray
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found existing S before $($sourceMatch.Value); checking source page with Enter" ([System.Drawing.Color]::Lime)
                $global:CR_PipelineSourceSelectionSent = $true
                $global:CR_PipelineState = 'EnvSelect_EnterWait'
                $global:CR_ElapsedMs = 0
                return
            }

            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $sourceRow -ColIndex $sourceCol
            if ($null -eq $pt) {
                $reason = 'COMPONENT VERSION selection point is outside calibrated terminal bounds.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)
            $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] COMPONENT VERSION row $sourceRow, marker $($sourceMatch.Value) - about to click two columns left, type S + Enter"
            if (Request-PipelineStepConfirm -Description $desc -MarkerPoint $screenPt) { return }

            if ([int]$PipelineTimingsMs.ComponentVersion.BeforeClickMs -gt 0) {
                Start-Sleep -Milliseconds ([int]$PipelineTimingsMs.ComponentVersion.BeforeClickMs)
            }

            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                $reason = 'Target window was unavailable before selecting the COMPONENT VERSION source row.'
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            $pt = Get-Screen1RowScreenPoint -Handle $global:CR_TargetHandle -Screen1Select $s1 -LineIndex $sourceRow -ColIndex $sourceCol
            if ($null -eq $pt) {
                $reason = 'COMPONENT VERSION geometry changed while preparing the source selection.'
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            $screenPt = New-Object System.Drawing.Point($pt.X, $pt.Y)
            if (-not (Invoke-Screen1RowClick -ScreenPoint $screenPt)) {
                $reason = 'Windows did not accept the COMPONENT VERSION source-row click.'
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $componentText
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Clicked COMPONENT VERSION row $sourceRow selection cell for $($sourceMatch.Value)" ([System.Drawing.Color]::Lime)
            $global:CR_PipelineState = 'EnvSelect_TypeWait'
            $global:CR_ElapsedMs = 0
        }

        'EnvSelect_TypeWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentVersion.AfterClickMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable before typing S.' -ObservedText ([string]$global:CR_PipelineScreen2CapturedText)
                    return
                }
                if (-not $global:CR_PipelineSourceSelectionSent) {
                    # Mark before dispatch so a recovered/re-entered state
                    # can never type a second S on this COMPONENT VERSION.
                    $global:CR_PipelineSourceSelectionSent = $true
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Sending the single literal S selection for this COMPONENT VERSION page." -ForegroundColor DarkGray
                    if (-not [Win32]::SendUnicodeCharacter([char]'S')) {
                        Skip-PipelineRowAfterFailure -Reason 'Could not send the literal S selection character.' -ObservedText ([string]$global:CR_PipelineScreen2CapturedText)
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Entered S; preparing Enter to open SOURCE CODE" ([System.Drawing.Color]::Lime)
                } else {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] S was already sent for this COMPONENT VERSION page; skipping duplicate input." -ForegroundColor Yellow
                }
                $global:CR_PipelineState = 'EnvSelect_EnterWait'
                $global:CR_ElapsedMs = 0
            }
        }

        'EnvSelect_EnterWait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentVersion.PauseAfterSBeforeEnterMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable before pressing Enter on COMPONENT VERSION.' -ObservedText ([string]$global:CR_PipelineScreen2CapturedText)
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Sending Enter on COMPONENT VERSION" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                $global:CR_PipelineScreen2CapturedText = $null
                $global:CR_PipelineState = 'EnvSelect_Wait'
                $global:CR_ElapsedMs = 0
            }
        }

        'EnvSelect_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentVersion.AfterEnterMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    Skip-PipelineRowAfterFailure -Reason 'Target window was unavailable after pressing Enter on COMPONENT VERSION.' -ObservedText ([string]$global:CR_PipelineScreen2CapturedText)
                    return
                }
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying screen after Enter; checking for SOURCE CODE menu" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'EnvSelect_Copy'
                $global:CR_ElapsedMs = 0
            }
        }

        'EnvSelect_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentVersion.AfterClipboardCopyMs) {
                $sourceText = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                        $sourceText = [System.Windows.Forms.Clipboard]::GetText()
                    }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed on source-code page: $_" -ForegroundColor Yellow
                }

                $detected = Update-PipelineScreenTracking -Text $sourceText -PipelineName $pipeline.Name
                $componentCommandError = ($detected -eq 2) -and (Test-PipelineTopRightChanged -Before $global:CR_PipelineScreen2BeforeSelectionText -After $sourceText)
                $componentUnavailable = ($detected -eq 2) -and (Test-RelayTextContains -Text $sourceText -Needle 'Component unavailable')
                if ($detected -eq 2 -and ($componentCommandError -or $componentUnavailable)) {
                    if ($componentUnavailable) {
                        $candidateIndex = [int]$global:CR_PipelineSourceCandidateIdx
                        $environmentName = ''
                        if ($candidateIndex -ge 0 -and $candidateIndex -lt $global:CR_PipelineSourceCandidates.Count) {
                            $environmentName = [string]$global:CR_PipelineSourceCandidates[$candidateIndex].Match.Value
                        }
                        $unavailableComponent = Add-ComponentUnavailableNote -Environment $environmentName -AttemptNumber ($candidateIndex + 1)
                        $nextCandidateIndex = $candidateIndex + 1
                        if ($nextCandidateIndex -lt $global:CR_PipelineSourceCandidates.Count) {
                            $nextEnvironment = [string]$global:CR_PipelineSourceCandidates[$nextCandidateIndex].Match.Value
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] '$environmentName' is unavailable for '$unavailableComponent'; trying next environment '$nextEnvironment' on this COMPONENT VERSION page." -ForegroundColor Yellow
                            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] $environmentName unavailable for $unavailableComponent; trying $nextEnvironment" ([System.Drawing.Color]::Yellow)
                            $global:CR_PipelineSourceCandidateIdx = $nextCandidateIndex
                            $global:CR_PipelineSourceSelectionSent = $false
                            $global:CR_PipelineScreen2BeforeSelectionText = $sourceText
                            $global:CR_PipelineState = 'EnvSelect_Action'
                            $global:CR_ElapsedMs = 0
                            return
                        }
                        $reason = "COMPONENT VERSION reported 'Component unavailable' for repository component '$unavailableComponent' on its final candidate '$environmentName'. No PROD/UT/ET alternatives remain."
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Returning to REPOSITORY LIST and continuing." -ForegroundColor Yellow
                    } else {
                        $reason = 'COMPONENT VERSION top-right error message changed after S/Enter.'
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] SOURCE CODE not found; COMPONENT VERSION shows an error" ([System.Drawing.Color]::Yellow)
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                    Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $sourceText
                } elseif ($detected -eq 3) {
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found SOURCE CODE menu; starting Auto Capture Current File" ([System.Drawing.Color]::Lime)
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] SOURCE CODE verified; starting Auto Capture Current File" ([System.Drawing.Color]::Orange)
                    $global:CR_PipelineSourceCaptureText = $sourceText
                    $global:CR_PipelineState = 'SrcCapture_Start'
                    $global:CR_ElapsedMs = 0
                } else {
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] SOURCE CODE menu not found yet (screen $detected); checking again" ([System.Drawing.Color]::Yellow)
                    $global:CR_PipelineScreen1RetryCount++
                    $maxRetries = [int]$s1.MaxRowRetries
                    if ($global:CR_PipelineScreen1RetryCount -gt $maxRetries) {
                        $reason = "SOURCE CODE page was not verified by the row-0 menu text (detected screen $detected)."
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                        Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $sourceText
                        return
                    }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Source-code page not yet verified (detected screen $detected); recapturing without another S or F3 ($($global:CR_PipelineScreen1RetryCount)/$maxRetries)." -ForegroundColor Yellow
                    $global:CR_PipelineState = 'EnvSelect_Wait'
                    $global:CR_ElapsedMs = 0
                }
            }
        }

        default {
            $reason = "Unknown COMPONENT VERSION state '$($global:CR_PipelineState)'."
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and trying to return to REPOSITORY LIST." -ForegroundColor Yellow
            Skip-PipelineRowAfterFailure -Reason $reason -ObservedText ([string]$global:CR_PipelineScreen2CapturedText)
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

 Screen 3 = the COBOL source-code page, recognized by the row-0 menu
 text "Menu  Utilities  Compilers  Help". Once verified, run the same
 capture loop as Auto Capture Current File: append filtered screens to
 the component's .txt/.cbl files, send the configured action key (F8 by
 default), and stop only when copied text contains "Bottom of data".
 Only then queue the single F3 return to Screen 1. Unexpected Sql_*
 states fail safely.
=====================================================================
#>

function Invoke-PipelineScreen3Tick {
    $pipeline = $global:CR_ActivePipelineConfig
    switch ($global:CR_PipelineState) {
        'SrcCapture_Start' {
            $sourceText = [string]$global:CR_PipelineSourceCaptureText
            $baseName = Get-ComponentIdFromText -Text $sourceText
            if ([string]::IsNullOrWhiteSpace($baseName)) {
                $reason = 'SOURCE CODE was reached, but no BROWSE component identifier was found for Auto Capture Current File.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $sourceText
                return
            }

            $baseName = Get-SafeFileName $baseName
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
            if ([string]::IsNullOrWhiteSpace($baseName)) {
                $reason = 'Could not make a safe output filename for the source file.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $sourceText
                return
            }

            foreach ($dir in @($TxtDir, $CblDir)) {
                if (-not (Test-Path -Path $dir)) {
                    try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch {
                        $reason = "Could not create capture folder '$dir': $_"
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                        Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $sourceText
                        return
                    }
                }
            }

            $global:CR_PipelineSourceLogFile = Join-Path $TxtDir ($baseName + '.txt')
            $global:CR_PipelineSourceLogFileCbl = Join-Path $CblDir ($baseName + '.cbl')
            $global:CR_PipelineSourceCapturePreviousText = $null
            $global:CR_PipelineSourceCapturePages = 0
            $global:CR_PipelineSourceCaptureRetries = 0
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Auto Capture Current File started for $baseName; output: $($global:CR_PipelineSourceLogFile) and $($global:CR_PipelineSourceLogFileCbl)" -ForegroundColor Green
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found source file $baseName; starting Auto Capture Current File" ([System.Drawing.Color]::Lime)
            $global:CR_PipelineState = 'SrcCapture_Save'
            $global:CR_ElapsedMs = 0
        }

        'SrcCapture_Save' {
            $text = [string]$global:CR_PipelineSourceCaptureText
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Analyzing source capture page $($global:CR_PipelineSourceCapturePages + 1)" ([System.Drawing.Color]::Lime)
            if ([string]::IsNullOrWhiteSpace($text)) {
                $reason = 'Source capture returned empty text.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason
                return
            }

            # Only the mainframe's explicit Bottom of data marker ends
            # source capture. Repeated text without that marker is not
            # proof of end-of-file; keep paging, but don't append duplicate
            # content to the output files.
            $reachedBottom = Test-RelayTextContains -Text $text -Needle 'Bottom of data'
            $repeatedPage = $false
            if ($null -ne $global:CR_PipelineSourceCapturePreviousText) {
                $similarity = Get-TextSimilarity -A $global:CR_PipelineSourceCapturePreviousText -B $text
                $repeatedPage = ($similarity -ge $DupDetectThreshold)
            }

            if ($global:CR_PipelineSourceCapturePages -ge 10000) {
                $reason = 'Auto Capture Current File reached the 10000-page safety limit.'
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text
                return
            }

            $filtered = Get-FilteredCaptureText -Text $text -SkipStart $SkipRowsStart -SkipEnd $SkipRowsEnd
            if ($repeatedPage -and -not $reachedBottom) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] The copied source page repeated without a Bottom of data marker; skipping duplicate output and continuing to page." -ForegroundColor Yellow
            } else {
                try {
                    if (-not [string]::IsNullOrEmpty($filtered)) {
                        Add-Content -Path $global:CR_PipelineSourceLogFile -Value $filtered
                        Add-Content -Path $global:CR_PipelineSourceLogFileCbl -Value $filtered
                    }
                } catch {
                    $reason = "Failed to save Auto Capture Current File output: $_"
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                    Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text
                    return
                }
            }

            $global:CR_PipelineSourceCapturePreviousText = $text
            $global:CR_PipelineSourceCapturePages++
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Analyzed source page $($global:CR_PipelineSourceCapturePages)." -ForegroundColor DarkCyan
            if (-not $reachedBottom -and -not $repeatedPage) {
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Saved source capture page $($global:CR_PipelineSourceCapturePages)" ([System.Drawing.Color]::Lime)
            }
            if ($reachedBottom) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Found 'Bottom of data' after analyzing source page $($global:CR_PipelineSourceCapturePages); returning with F3." -ForegroundColor Green
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Found Bottom of data; source capture complete, returning with F3" ([System.Drawing.Color]::Lime)
                Show-RelayResultOverlay -Text "SOURCE CAPTURE COMPLETE" -Color ([System.Drawing.Color]::LimeGreen) -TopRight
                $global:CR_PipelineScreen1RetryCount = 0
                $global:CR_PipelineAfterBack = 'CompNext_Action'
                $global:CR_PipelineState = 'Back_Action'
                $global:CR_ElapsedMs = 0
                return
            }
            if ($repeatedPage) {
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Page repeated without Bottom of data; continuing to page" ([System.Drawing.Color]::Yellow)
            }
            $global:CR_PipelineState = 'SrcCapture_Action'
            $global:CR_ElapsedMs = 0
        }

        'SrcCapture_Action' {
            if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                $reason = 'Target window was unavailable during source capture.'
                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText ([string]$global:CR_PipelineSourceCaptureText)
                return
            }
            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Auto Capture Current File - sending $ActionKeyDisplay" ([System.Drawing.Color]::Orange)
            [System.Windows.Forms.SendKeys]::SendWait($ActionKeyToken)
            $global:CR_PipelineState = 'SrcCapture_Wait'
            $global:CR_ElapsedMs = 0
        }

        'SrcCapture_Wait' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.SourceCode.AfterActionKeyMs) {
                if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                    $reason = 'Target window was unavailable while paging source capture.'
                    Skip-PipelineRowAfterFailure -Reason $reason -ObservedText ([string]$global:CR_PipelineSourceCaptureText)
                    return
                }
                try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Copying next SOURCE CODE page" ([System.Drawing.Color]::Lime)
                [System.Windows.Forms.SendKeys]::SendWait('^c')
                $global:CR_PipelineState = 'SrcCapture_Copy'
                $global:CR_ElapsedMs = 0
            }
        }

        'SrcCapture_Copy' {
            $global:CR_ElapsedMs += $TimerTickMs
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.SourceCode.AfterClipboardCopyMs) {
                $text = ''
                try {
                    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                        $text = [System.Windows.Forms.Clipboard]::GetText()
                    }
                } catch {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed during source capture: $_" -ForegroundColor Yellow
                }

                if ([string]::IsNullOrWhiteSpace($text)) {
                    $global:CR_PipelineSourceCaptureRetries++
                    if ($global:CR_PipelineSourceCaptureRetries -gt [int]$pipeline.Screen1Select.MaxRowRetries) {
                        $reason = "Could not read source text after $($global:CR_PipelineSourceCaptureRetries) attempts."
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                        Skip-PipelineRowAfterFailure -Reason $reason
                        return
                    }
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Source clipboard was empty; retrying Ctrl+C ($($global:CR_PipelineSourceCaptureRetries))." -ForegroundColor Yellow
                    $global:CR_PipelineState = 'SrcCapture_Wait'
                    $global:CR_ElapsedMs = 0
                    return
                }

                Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Analyzing copied SOURCE CODE page" ([System.Drawing.Color]::Lime)
                $sourceScreen = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                if ($sourceScreen -ne 3) {
                    $reason = "Auto Capture Current File left SOURCE CODE (detected screen $sourceScreen)."
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] SOURCE CODE not found on copied page; logging failure" ([System.Drawing.Color]::Yellow)
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and returning to REPOSITORY LIST." -ForegroundColor Yellow
                    Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text
                    return
                }

                $global:CR_PipelineSourceCaptureRetries = 0
                $global:CR_PipelineSourceCaptureText = $text
                $global:CR_PipelineState = 'SrcCapture_Save'
                $global:CR_ElapsedMs = 0
            }
        }

        default {
            $reason = "Unexpected source-code state '$($global:CR_PipelineState)'."
            Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason Logging the row and trying to return to REPOSITORY LIST." -ForegroundColor Yellow
            Skip-PipelineRowAfterFailure -Reason $reason -ObservedText ([string]$global:CR_PipelineSourceCaptureText)
        }
    }
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
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentList.AfterPageKeyMs) {
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
            if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.ComponentList.AfterClipboardCopyMs) {
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
        PipelineTimingsMs     = Get-DefaultPipelineTimingsMs
        Modes                 = @( Get-DefaultSqlSearchMode )
        Pipelines             = @()
    }
}

# The default "scan mode" bound to Alt+>. Instead of the
# plain Auto capture current file (Ctrl+Alt+C), this repeatedly presses F5, copies
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

# Auto capture current file (Ctrl+Shift+A in the current config) always saves two copies of
# whatever it captures - a .txt copy in ..\txt and a .cbl copy in
# ..\cbl - regardless of what extension (if any) the person types into
# the filename prompt. Those are the "txt" and "cbl" folders right
# OUTSIDE this script's own folder (siblings of it, not subfolders),
# always resolved from the script's location - not from LogFile, which
# only decides LogDir (the other output files) and the default base
# name. GetFullPath collapses the ".." so messages show a clean path.
# Created up front so they exist even before the first capture starts.
$TxtDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\txt"))
$CblDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\cbl"))
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

# Backfill timing fields introduced after older config files were created.
# All PipelineTimingsMs values are milliseconds; edit the JSON to tune each
# page and action independently. Missing fields retain the safe defaults.
$defaultPipelineTimings = Get-DefaultPipelineTimingsMs
if (-not ($Config.PSObject.Properties.Name -contains 'PipelineTimingsMs') -or $null -eq $Config.PipelineTimingsMs) {
    $Config | Add-Member -NotePropertyName PipelineTimingsMs -NotePropertyValue $defaultPipelineTimings -Force
}
foreach ($pageProperty in $defaultPipelineTimings.PSObject.Properties) {
    $pageName = $pageProperty.Name
    if (-not ($Config.PipelineTimingsMs.PSObject.Properties.Name -contains $pageName) -or $null -eq $Config.PipelineTimingsMs.$pageName) {
        $Config.PipelineTimingsMs | Add-Member -NotePropertyName $pageName -NotePropertyValue $pageProperty.Value -Force
        continue
    }
    foreach ($delayProperty in $pageProperty.Value.PSObject.Properties) {
        if (-not ($Config.PipelineTimingsMs.$pageName.PSObject.Properties.Name -contains $delayProperty.Name)) {
            $Config.PipelineTimingsMs.$pageName | Add-Member -NotePropertyName $delayProperty.Name -NotePropertyValue $delayProperty.Value -Force
        }
    }
}
$PipelineTimingsMs = $Config.PipelineTimingsMs

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
    $global:CR_StepConfirmAllowed = [bool]$Config.PipelineStepConfirmEnabled
} else {
    $global:CR_StepConfirmAllowed = $true
}
# Per-run flag: $true only for a pipeline started with its StepHotkey
# (Ctrl+Shift+N). A pipeline started with its normal Hotkey
# (Ctrl+Shift+M) runs fully automatically. Set for real in the
# pipeline hotkey handler each time a pipeline starts.
$global:CR_StepConfirmEnabled = $false

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
        ClickColumnOffset  = 0
        SelectionText      = 'B'
        RowsPerPage        = 25
        StartRowOffset     = 0
        PageNextToken      = '{F8}'
        PageNextDisplay    = 'F8'
        EndOfListText      = 'Bottom of List'
        DupDetectThreshold = 0.995
        MaxPages           = 500
        MaxRowRetries      = 3
        InvalidCommandText = 'Invalid REPOLIST Command'
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
    # Step-by-step twin of the pipeline hotkey: Ctrl+Shift+N by default.
    if (-not ($p.PSObject.Properties.Name -contains 'StepHotkey') -or $null -eq $p.StepHotkey) {
        $p | Add-Member -NotePropertyName StepHotkey -NotePropertyValue ([pscustomobject]@{ Modifiers = 6; Key = 78; Display = 'Ctrl+Shift+N'; RequireRightModifier = $false }) -Force
    } elseif (-not ($p.StepHotkey.PSObject.Properties.Name -contains 'RequireRightModifier')) {
        $p.StepHotkey | Add-Member -NotePropertyName RequireRightModifier -NotePropertyValue $false -Force
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

# Always-available global controls, independent of which window has focus.
$StopHotkeyId      = 7
$StopModifiers     = 0x0002 -bor 0x0004 # MOD_CONTROL | MOD_SHIFT
$StopKey           = 0x53              # S
$StopDisplay       = 'Ctrl+Shift+S'
$PauseHotkeyId     = 8
$PauseModifiers    = 0x0002 -bor 0x0004 # MOD_CONTROL | MOD_SHIFT
$PauseKey          = 0x50              # P
$PauseDisplay      = 'Ctrl+Shift+P'
$RestartHotkeyId   = 9
$RestartModifiers  = 0x0002 -bor 0x0004 # MOD_CONTROL | MOD_SHIFT
$RestartKey        = 0x52              # R
$RestartDisplay    = 'Ctrl+Shift+R'

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
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, UIntPtr dwExtraInfo);

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public INPUTUNION U;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // Send a literal UTF-16 character without translating it through the
    // active keyboard layout. Repository commands must always be ASCII B.
    public static bool SendUnicodeCharacter(char character)
    {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = 1;
        inputs[0].U.ki.wScan = character;
        inputs[0].U.ki.dwFlags = 0x0004;
        inputs[0].U.ki.dwExtraInfo = UIntPtr.Zero;
        inputs[1].type = 1;
        inputs[1].U.ki.wScan = character;
        inputs[1].U.ki.dwFlags = 0x0004 | 0x0002;
        inputs[1].U.ki.dwExtraInfo = UIntPtr.Zero;
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
    }

    public static bool ClickLeftAtCurrentCursor()
    {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = 0;
        inputs[0].U.mi.dwFlags = 0x0002;
        inputs[0].U.mi.dwExtraInfo = UIntPtr.Zero;
        inputs[1].type = 0;
        inputs[1].U.mi.dwFlags = 0x0004;
        inputs[1].U.mi.dwExtraInfo = UIntPtr.Zero;
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
    }

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

// Same non-activating overlay, but also click-through (WS_EX_TRANSPARENT +
// WS_EX_LAYERED), so the bottom-center hotkey overview never swallows a
// click meant for the window underneath it.
public class MenuOverlay : StatusOverlay
{
    protected override CreateParams CreateParams
    {
        get
        {
            const int WS_EX_TRANSPARENT = 0x00000020;
            const int WS_EX_LAYERED = 0x00080000;
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TRANSPARENT | WS_EX_LAYERED;
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
if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $StopHotkeyId, $StopModifiers, $StopKey)) {
    Write-Host "Failed to register the STOP hotkey ($StopDisplay). It may already be in use by another app." -ForegroundColor Red
}
if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $PauseHotkeyId, $PauseModifiers, $PauseKey)) {
    Write-Host "Failed to register the PAUSE hotkey ($PauseDisplay). It may already be in use by another app." -ForegroundColor Red
}
if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $RestartHotkeyId, $RestartModifiers, $RestartKey)) {
    Write-Host "Failed to register the RESTART hotkey ($RestartDisplay). It may already be in use by another app." -ForegroundColor Red
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

# ---- Step-by-step twin hotkeys (Ctrl+Shift+N by default): same pipeline,
# but each input waits for the step-confirm key. IDs live in their own
# range so they never collide with the automatic pipeline hotkeys. ----
$PipelineStepHotkeyMap  = @{}
$PipelineStepHotkeyBase = 6000
$pipelineIndex = 0
foreach ($p in $PipelineConfigs) {
    $pipelineIndex++
    if (-not $p.Enabled) { continue }
    if ($null -eq $p.StepHotkey -or $null -eq $p.StepHotkey.Key -or [int]$p.StepHotkey.Key -eq 0) { continue }
    $hkId  = $PipelineStepHotkeyBase + $pipelineIndex
    if (-not [HotkeyForm]::RegisterHotKey($FormHandle, $hkId, [int]$p.StepHotkey.Modifiers, [int]$p.StepHotkey.Key)) {
        Write-Host "Failed to register the step-by-step hotkey for pipeline '$($p.Name)' ($($p.StepHotkey.Display)). It may already be in use." -ForegroundColor Red
        continue
    }
    $PipelineStepHotkeyMap[$hkId] = $p
}

# True only when Screen1Select has real (non-zero) pixel geometry -
# i.e. CalibrateScreen1Auto.ps1/CalibrateScreen1AutoGuided.ps1 has
# actually been run for this pipeline, not just the placeholder
# 0/0/0/0 a fresh config ships with. Defined here (before the startup
# flagging loop just below, and well before the Ctrl+Shift+M handler
# further down) since both call it.
function Test-Screen1Calibrated {
    param($Screen1Select)
    return ($null -ne $Screen1Select -and [double]$Screen1Select.CharWidthPx -gt 0 -and [double]$Screen1Select.CharHeightPx -gt 0 -and $null -ne $Screen1Select.FirstDataRowLineIndex -and $null -ne $Screen1Select.SelectionColumnIndex -and $null -ne $Screen1Select.TerminalLeft -and $null -ne $Screen1Select.TerminalTop -and $null -ne $Screen1Select.TerminalWidth -and $null -ne $Screen1Select.TerminalHeight -and $null -ne $Screen1Select.TerminalColumns -and $null -ne $Screen1Select.TerminalRows -and $null -ne $Screen1Select.CalibrationClientWidth -and $null -ne $Screen1Select.CalibrationClientHeight)
}

# ---- Top-left status overlay: a click-through, non-activating history
# panel so its larger 10-line view never blocks the terminal underneath. ----
$statusForm = New-Object MenuOverlay
$statusForm.FormBorderStyle = 'None'
$statusForm.StartPosition   = 'Manual'
$statusForm.ShowInTaskbar   = $false
$statusForm.TopMost         = $true
$statusForm.BackColor       = [System.Drawing.Color]::Black
$statusForm.Opacity         = 0.85
$statusForm.Size            = New-Object System.Drawing.Size(1040, 220)

$screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$statusForm.Location = New-Object System.Drawing.Point(($screenArea.Left + 8), ($screenArea.Top + 8))

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock      = 'Fill'
$statusLabel.Padding   = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$statusLabel.AutoSize  = $false
$statusLabel.TextAlign = 'TopLeft'
$statusLabel.ForeColor = [System.Drawing.Color]::Lime
$statusLabel.Font      = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$statusLabel.Text      = ''
$statusForm.Controls.Add($statusLabel)
$global:CR_StatusHistory = New-Object 'System.Collections.Generic.List[string]'

# Force the overlay's handle to exist now (so Select-TargetWindow can
# compare clicked windows against it) without actually showing it yet.
[void]$statusForm.Handle
$statusForm.Hide()

function Set-RelayStatus {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Lime
    )
    $statusLine = ($Text -replace '[\r\n]+', ' ').Trim()
    if ($statusLine.Length -gt 120) { $statusLine = $statusLine.Substring(0, 117) + '...' }
    $global:CR_StatusHistory.Add("[$(Get-Date -Format 'HH:mm:ss')] $statusLine")
    while ($global:CR_StatusHistory.Count -gt 10) { $global:CR_StatusHistory.RemoveAt(0) }
    $statusLabel.ForeColor = $Color
    $statusLabel.Text      = $global:CR_StatusHistory -join [Environment]::NewLine
    if (-not $statusForm.Visible) { $statusForm.Show() }
}

function Hide-RelayStatus {
    $statusForm.Hide()
}

# ---- Big centered "result" banner used by scan Modes to announce their
# outcome (e.g. "SQL FOUND" / "NO SQL FOUND"). Uses the non-activating,
# click-through MenuOverlay type so a visible banner can never intercept
# a simulated click on the target window underneath it. It is bigger,
# centered, and auto-hiding after $ResultOverlayDurationMs (0 = stays
# until the next action starts). ----
$resultOverlay = New-Object MenuOverlay
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
        [int]$DurationMs = $ResultOverlayDurationMs,
        [switch]$TopRight
    )
    $resultHideTimer.Stop()
    $resultOverlay.BackColor = $Color
    $resultLabel.Text        = $Text

    $screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if ($TopRight) {
        $x = $screenArea.Right - $resultOverlay.Width - 16
        $y = $screenArea.Top + 16
    } else {
        $x = $screenArea.Left + [int](($screenArea.Width  - $resultOverlay.Width)  / 2)
        $y = $screenArea.Top  + [int](($screenArea.Height - $resultOverlay.Height) / 2)
    }
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

# Used by "Auto capture current file" to name its output automatically.
# Brings the target window to the front, copies its current screen
# (Ctrl+C), and returns the component identifier from the "BROWSE (...)"
# line (e.g. "CF205"), or $null if the clipboard has no such line.
# The clipboard is cleared first so stale text from an earlier copy can
# never be mistaken for this screen.
function Get-AutoCaptureBaseName {
    param([IntPtr]$Handle)

    if (-not (Set-RelayForeground -Handle $Handle)) { return $null }

    try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
    [System.Windows.Forms.SendKeys]::SendWait('^c')

    $text = $null
    $waited = 0
    $sourceCopyDelayMs = [Math]::Max(1, [int]$PipelineTimingsMs.SourceCode.AfterClipboardCopyMs)
    $maxWait = [Math]::Max($sourceCopyDelayMs * 4, 1000)
    while ($waited -lt $maxWait) {
        Start-Sleep -Milliseconds $sourceCopyDelayMs
        $waited += $sourceCopyDelayMs
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                $candidate = [System.Windows.Forms.Clipboard]::GetText()
                if (-not [string]::IsNullOrWhiteSpace($candidate)) { $text = $candidate; break }
            }
        } catch {}
    }

    return (Get-ComponentIdFromText -Text $text)
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

# Returns a compact signature for the upper-right terminal area from
# the first few copied screen lines. This distinguishes an in-place
# mainframe command error from a normal screen that simply did not open.
function Get-PipelineTopRightSignature {
    param(
        [string]$Text,
        [int]$LineCount = 3,
        [int]$Width = 20
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $lines = @($Text -split "`r`n|`r|`n")
    $signature = New-Object System.Collections.Generic.List[string]
    $limit = [Math]::Min($LineCount, $lines.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        $line = ([string]$lines[$i]).TrimEnd()
        $start = [Math]::Max(0, $line.Length - $Width)
        $signature.Add(("{0}:{1}" -f $i, $line.Substring($start)))
    }
    return ($signature -join "`n")
}

function Test-PipelineTopRightChanged {
    param(
        [string]$Before,
        [string]$After
    )

    $beforeSignature = Get-PipelineTopRightSignature -Text $Before
    $afterSignature = Get-PipelineTopRightSignature -Text $After
    if ([string]::IsNullOrEmpty($beforeSignature) -or [string]::IsNullOrEmpty($afterSignature)) { return $false }
    return (-not [string]::Equals($beforeSignature, $afterSignature, [StringComparison]::Ordinal))
}

# ---- Screen tracking ----
#
# Identify the current page from copied row 0 (the emulator's top data
# row), rather than trusting the state machine's expected destination.
# COMPONENT VERSION is the displayed heading used for the component list
# page in this workflow; accept COMPONENT LIST as an alternate heading.
function Get-PipelineScreenName {
    param([string]$Text)

    $topRow = ''
    $topLines = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrEmpty($Text)) {
        # HOD can omit leading blank rows or split the centered heading
        # around fixed-width terminal columns in the clipboard. Build a
        # compact prefix from the first few nonblank copied lines so the
        # title is still recognized even when row 0 isn't copied as one
        # contiguous string.
        foreach ($line in ($Text -split "`r`n|`r|`n")) {
            $candidateTopRow = [regex]::Replace(([string]$line).Replace([string][char]0, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidateTopRow)) {
                if ([string]::IsNullOrEmpty($topRow)) { $topRow = $candidateTopRow }
                $topLines.Add($candidateTopRow)
                if ($topLines.Count -ge 3) { break }
            }
        }
    }
    $normalizedTopText = [regex]::Replace(($topLines -join ' '), '\s+', ' ').Trim()
    $normalizedFullText = ''
    if (-not [string]::IsNullOrEmpty($Text)) {
        $cleanFullText = [regex]::Replace($Text.Replace([string][char]0, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F]', ' ')
        $normalizedFullText = [regex]::Replace($cleanFullText, '\s+', ' ').Trim()
    }
    if (Test-RelayTextContains -Text $topRow -Needle 'REPOSITORY LIST') { return 'REPOSITORY LIST' }
    # HOD may preserve the terminal's column spacing in copied text, so
    # the words in the centered row-0 heading can be separated by more
    # than one space or split across clipboard lines. Match the compact
    # prefix as well as the original first copied line.
    if (($normalizedTopText -match '(?i)REPOSITORY\s+LIST') -or
        ($normalizedFullText -match '(?i)REPOSITORY\s+LIST')) { return 'REPOSITORY LIST' }
    if ((Test-RelayTextContains -Text $topRow -Needle 'COMPONENT LIST') -or
        (Test-RelayTextContains -Text $topRow -Needle 'COMPONENT VERSION') -or
        $normalizedTopText -match '(?i)COMPONENT\s+(LIST|VERSION)' -or
        $normalizedFullText -match '(?i)COMPONENT\s+(LIST|VERSION)') {
        return 'COMPONENT LIST'
    }
    if ((Test-RelayTextContains -Text $topRow -Needle 'Menu  Utilities  Compilers  Help') -or
        $normalizedTopText -match '(?i)MENU\s+UTILITIES\s+COMPILERS\s+HELP' -or
        $normalizedFullText -match '(?i)MENU\s+UTILITIES\s+COMPILERS\s+HELP') { return 'SOURCE CODE' }

    # Some HOD copy modes omit the screen title even while copying the
    # repository table. Recognize that page from its distinctive table
    # headings and Show Deleted field, together with at least one COB row.
    # This fallback still requires repository-specific screen content
    # before the pipeline is allowed to click a selection field.
    if (($normalizedFullText -match '(?i)SHOW\s+DELETED\s*:') -and
        ($normalizedFullText -match '(?i)TYPE\s+NAME\s+APPL') -and
        ($normalizedFullText -match '(?i)\bCOB\b')) { return 'REPOSITORY LIST' }
    return 'UNKNOWN'
}

# Preserve the numeric page IDs used by the pipeline state machine, while
# deriving them from the human-readable page check above.
function Get-PipelineScreenNumber {
    param([string]$Text)

    $pageName = Get-PipelineScreenName -Text $Text
    switch ($pageName) {
        'REPOSITORY LIST' { return 1 }
        'COMPONENT LIST'  { return 2 }
        'SOURCE CODE'     { return 3 }
        default           { return 0 }
    }
}

function Get-PipelineScreenNameFromNumber {
    param([int]$ScreenNumber)

    switch ($ScreenNumber) {
        1 { return 'REPOSITORY LIST' }
        2 { return 'COMPONENT LIST' }
        3 { return 'SOURCE CODE' }
        default { return 'UNKNOWN' }
    }
}

# Detects the screen from freshly-captured text, compares it against
# $global:CR_PipelineCurrentScreen (what we were on a moment ago),
# logs whether we progressed, went back, stayed put, or landed
# somewhere unrecognized, then updates the tracked value and returns
# the detected screen number. Called at every clipboard capture point
# across all screen files, so the console always shows the real,
# independently-verified screen - not just what the state machine
# assumed would happen.
function Update-PipelineScreenTracking {
    param(
        [string]$Text,
        [string]$PipelineName
    )

    $detected = Get-PipelineScreenNumber -Text $Text
    $previous = $global:CR_PipelineCurrentScreen
    $detectedName = Get-PipelineScreenNameFromNumber -ScreenNumber $detected
    $previousName = Get-PipelineScreenNameFromNumber -ScreenNumber ([int]$previous)

    if ($detected -eq 0) {
        Write-Host "[AutoClipCapture] [$PipelineName] Page check: top row did not match REPOSITORY LIST, COMPONENT LIST, or SOURCE CODE (was $previousName)." -ForegroundColor Yellow
    } elseif ($previous -eq 0) {
        Write-Host "[AutoClipCapture] [$PipelineName] Page check: now on $detectedName (identified from copied top row)." -ForegroundColor DarkCyan
    } elseif ($detected -eq $previous) {
        Write-Host "[AutoClipCapture] [$PipelineName] Page check: stayed on $detectedName." -ForegroundColor DarkCyan
    } elseif ($detected -gt $previous) {
        Write-Host "[AutoClipCapture] [$PipelineName] Page check: moved from $previousName to $detectedName." -ForegroundColor DarkCyan
    } else {
        Write-Host "[AutoClipCapture] [$PipelineName] Page check: returned from $previousName to $detectedName." -ForegroundColor DarkCyan
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

# Runs calibration in this process (blocking - waits for the user to
# accept/cancel it), then re-reads AutoClipCaptureConfig.json
# and copies the fresh OriginX/OriginY/CharWidthPx/CharHeightPx/
# ClickColumnOffset/FirstDataRowLineIndex/SelectionColumnIndex/
# CalibrationNote onto the *existing* in-memory $Pipeline.Screen1Select
# object (matched by pipeline Id) rather than replacing $Pipeline
# itself - $PipelineHotkeyMap and $global:CR_ActivePipelineConfig hold
# references to that same object, so calibration takes effect
# immediately without restarting AutoClipCapture.ps1.
function Invoke-Screen1CalibrationNow {
    param(
        $Pipeline,
        [IntPtr]$TargetHandle = [IntPtr]::Zero
    )

    $calibrationSucceeded = Invoke-Screen1CalibrationTool -Pipeline $Pipeline -TargetHandle $TargetHandle
    if (-not $calibrationSucceeded) { return }

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
    foreach ($fieldName in @(
        'CalibrationNote', 'FirstDataRowLineIndex', 'SelectionColumnIndex',
        'TerminalLeft', 'TerminalTop', 'TerminalWidth', 'TerminalHeight',
        'TerminalColumns', 'TerminalRows', 'CalibrationClientWidth', 'CalibrationClientHeight'
    )) {
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
    $global:CR_Paused            = $false
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
# Auto capture current file. Called both when a mode reaches a stop condition
# (found / not-found / safety limit) and when its hotkey is pressed
# again to cancel it manually.
function Stop-ModeCapture {
    $timer.Stop()
    $global:CR_Paused           = $false
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
    $global:CR_Paused                = $false
    $global:CR_ActiveAutomation      = $null
    $global:CR_ActivePipelineConfig  = $null
    $global:CR_PipelineState         = 'CompScan_Action'
    $global:CR_ElapsedMs             = 0
    $global:CR_PipelineComponentIdx  = 0
    $global:CR_PipelineStartRowLineIndex = -1
    $global:CR_PipelineStartRowName = ''
    $global:CR_PipelineStartPickerPending = $false
    $global:CR_PipelineLastProcessedCobLineIndex = -1
    $global:CR_PipelineBWriteRetryCount = 0
    $global:CR_PipelineCleanupLineIndex = -1
    $global:CR_PipelineCleanupKeepCount = 0
    $global:CR_PipelineCleanupResumeState = 'CompZoom_Action'
    $global:CR_PipelineCleanupRetryCount = 0
    $global:CR_PipelineEnvironmentIdx = 0
    $global:CR_PipelineSqlIterations = 0
    $global:CR_PipelineAfterBack     = $null
    $global:CR_PipelineBackRetryCount = 0
    $global:CR_PipelineFailureRowLogged = $false
    $global:CR_PipelineComponentLabel   = $null
    $global:CR_PipelineEnvironmentLabel = $null
    $global:CR_PipelineCurrentScreen    = 0
    $global:CR_PipelineListPageIdx      = 0
    $global:CR_PipelineListPrevFiltered = $null
    $global:CR_PipelineListOutputPath   = $null
    $global:CR_PipelineScreen1PageIdx      = 0
    $global:CR_PipelineScreen1IsLastPage   = $false
    $global:CR_PipelineScreen1PrevPageText = $null
    $global:CR_PipelineScreen1RetryCount   = 0
    $global:CR_PipelineScreen1Rows          = @()
    $global:CR_PipelineScreen2CapturedText = $null
    $global:CR_PipelineScreen2BeforeSelectionText = $null
    $global:CR_PipelineSourceSelectionSent = $false
    $global:CR_PipelineSourceCandidateIdx = 0
    $global:CR_PipelineSourceCandidates = @()
    $global:CR_PipelineSourceCaptureText = $null
    $global:CR_PipelineSourceCapturePreviousText = $null
    $global:CR_PipelineSourceLogFile = $null
    $global:CR_PipelineSourceLogFileCbl = $null
    $global:CR_PipelineSourceCapturePages = 0
    $global:CR_PipelineSourceCaptureRetries = 0
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
Write-Host "  $ToggleDisplay  -> Auto capture current file (start/stop the capture loop)" -ForegroundColor White
Write-Host "                    (click a window to target, confirm it, then name the file)"
Write-Host "  $StopDisplay  -> stop the current automation" -ForegroundColor White
Write-Host "  $PauseDisplay  -> pause/resume the current automation" -ForegroundColor White
Write-Host "  $RestartDisplay  -> completely restart AutoClipCapture" -ForegroundColor White
Write-Host "  $ExitDisplay  -> quit"
Write-Host "  $F3Display  -> send a single F3 to the focused window"
foreach ($hkId in $ModeHotkeyMap.Keys) {
    $m = $ModeHotkeyMap[$hkId]
    Write-Host "  $($m.Hotkey.Display)  -> mode: $($m.Name)  (action key: $($m.ActionKeyDisplay)) - run it on the currently opened source code" -ForegroundColor White
}
foreach ($hkId in $PipelineHotkeyMap.Keys) {
    $p = $PipelineHotkeyMap[$hkId]
    if ($null -ne $p.ComponentList -and [bool]$p.ComponentList.Enabled) {
        Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (START ON THE REPOSITORY LIST PAGE; component list pre-pass first)" -ForegroundColor White
    } else {
        Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (START ON THE REPOSITORY LIST PAGE)" -ForegroundColor White
    }
}
foreach ($hkId in $PipelineStepHotkeyMap.Keys) {
    $p = $PipelineStepHotkeyMap[$hkId]
    Write-Host "  $($p.StepHotkey.Display)  -> pipeline: $($p.Name)  (same as $($p.Hotkey.Display), but STEP BY STEP - press $StepConfirmDisplay to confirm each input)" -ForegroundColor White
}
Write-Host "Action key: $ActionKeyDisplay"
Write-Host "Log folder: $LogDir"
Write-Host "TXT folder: $TxtDir"
Write-Host "CBL folder: $CblDir"
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
    Write-Host "This build now forces per-monitor DPI awareness before touching any screen coordinate - if Screen1Select was calibrated with an OLDER build and clicks look off (or the red circle when stepping through Ctrl+Shift+N lands outside the terminal), run StartAutoClipCapture.bat Calibrate again to recalibrate under the new, consistent coordinates. This only matters if Windows display scaling isn't 100%." -ForegroundColor Cyan
}
Write-Host ""

# ---- Bottom-center hotkey overview: shown once at startup and whenever
# nothing is running, so the available functions and their keybindings
# are always visible. Click-through (MenuOverlay), and hidden while a
# capture, mode or pipeline is running or being set up, so it never sits
# on top of the screen being worked on. ----
$menuRows = New-Object System.Collections.ArrayList
foreach ($hkId in ($ModeHotkeyMap.Keys | Sort-Object)) {
    $m = $ModeHotkeyMap[$hkId]
    $menuModeText = if ([string]$m.Id -eq 'sql-search') { 'SQL search mode in current opened source code' } else { "$($m.Name) mode" }
    [void]$menuRows.Add(@([string]$m.Hotkey.Display, $menuModeText))
}
[void]$menuRows.Add(@([string]$ToggleDisplay, 'Auto capture current file'))
[void]$menuRows.Add(@([string]$StopDisplay, 'Stop the current automation'))
[void]$menuRows.Add(@([string]$PauseDisplay, 'Pause/resume the current automation'))
[void]$menuRows.Add(@([string]$RestartDisplay, 'Completely restart AutoClipCapture'))
foreach ($hkId in ($PipelineHotkeyMap.Keys | Sort-Object)) {
    $p = $PipelineHotkeyMap[$hkId]
    [void]$menuRows.Add(@([string]$p.Hotkey.Display, "$($p.Name) pipeline (start on the REPOSITORY LIST page)"))
}
foreach ($hkId in ($PipelineStepHotkeyMap.Keys | Sort-Object)) {
    $p = $PipelineStepHotkeyMap[$hkId]
    [void]$menuRows.Add(@([string]$p.StepHotkey.Display, "$($p.Name) pipeline, step by step ($StepConfirmDisplay confirms each input)"))
}
[void]$menuRows.Add(@([string]$ExitDisplay, 'Quit'))

$menuKeyWidth = ($menuRows | ForEach-Object { $_[0].Length } | Measure-Object -Maximum).Maximum
$menuLines = @('AutoClipCapture is ready. Press a hotkey:')
foreach ($r in $menuRows) { $menuLines += ('  ' + $r[0].PadRight($menuKeyWidth) + '   ' + $r[1]) }
$menuText = $menuLines -join "`r`n"

$menuFont = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)
$menuSize = [System.Windows.Forms.TextRenderer]::MeasureText($menuText, $menuFont)

$menuOverlay = New-Object MenuOverlay
$menuOverlay.FormBorderStyle = 'None'
$menuOverlay.StartPosition   = 'Manual'
$menuOverlay.ShowInTaskbar   = $false
$menuOverlay.TopMost         = $true
$menuOverlay.BackColor       = [System.Drawing.Color]::Black
$menuOverlay.Opacity         = 0.88
$menuOverlay.Size            = New-Object System.Drawing.Size(($menuSize.Width + 40), ($menuSize.Height + 28))

$menuLabel = New-Object System.Windows.Forms.Label
$menuLabel.Dock      = 'Fill'
$menuLabel.AutoSize  = $false
$menuLabel.TextAlign = 'MiddleLeft'
$menuLabel.Padding   = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
$menuLabel.ForeColor = [System.Drawing.Color]::White
$menuLabel.Font      = $menuFont
$menuLabel.Text      = $menuText
$menuOverlay.Controls.Add($menuLabel)

[void]$menuOverlay.Handle
$menuOverlay.Hide()

$menuSyncTimer = New-Object System.Windows.Forms.Timer
$menuSyncTimer.Interval = 300
$menuSyncTimer.Add_Tick({
    $shouldShow = ($null -eq $global:CR_ActiveAutomation) -and (-not $global:CR_Selecting)
    if ($shouldShow -and -not $menuOverlay.Visible) {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $x = $area.Left + [int](($area.Width - $menuOverlay.Width) / 2)
        $y = $area.Bottom - $menuOverlay.Height - 30
        $menuOverlay.Location = New-Object System.Drawing.Point($x, $y)
        $menuOverlay.Show()
    } elseif (-not $shouldShow -and $menuOverlay.Visible) {
        $menuOverlay.Hide()
    }
})
$menuSyncTimer.Start()

$global:CR_Running      = $false
$global:CR_Selecting    = $false
$global:CR_Paused        = $false
$global:CR_State        = 'Idle'   # Idle -> PostCopy -> PostAction -> Idle ...
$global:CR_ElapsedMs    = 0
$global:CR_LogFile      = Join-Path $TxtDir ($DefaultBaseName + ".txt")
$global:CR_LogFileCbl   = Join-Path $CblDir ($DefaultBaseName + ".cbl")
$global:CR_TargetHandle = [IntPtr]::Zero
$global:CR_TargetTitle  = ''
$global:CR_PrevCaptureText     = $null
$global:CR_SuppressDupWarning  = $false

# $null = nothing running, 'Relay' = the Auto capture current file loop,
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
$global:CR_PipelineStartRowLineIndex = -1
$global:CR_PipelineStartRowName = ''
$global:CR_PipelineStartPickerPending = $false
$global:CR_PipelineLastProcessedCobLineIndex = -1
$global:CR_PipelineBWriteRetryCount = 0
$global:CR_PipelineCleanupLineIndex = -1
$global:CR_PipelineCleanupKeepCount = 0
$global:CR_PipelineCleanupResumeState = 'CompZoom_Action'
$global:CR_PipelineCleanupRetryCount = 0
$global:CR_PipelineEnvironmentIdx   = 0
$global:CR_PipelineSqlIterations    = 0
$global:CR_PipelineAfterBack        = $null   # state to resume at once the single F3 "back" completes
$global:CR_PipelineBackRetryCount  = 0
$global:CR_PipelineFailureRowLogged = $false
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
# time a new page is scanned/paged into). Each row also carries BCount,
# freshly derived from the selection field before COB. ----
$global:CR_PipelineScreen1PageIdx      = 0     # 0-based page counter, for MaxPages/logging
$global:CR_PipelineScreen1IsLastPage   = $false # current repository page includes the configured end-of-list marker
$global:CR_PipelineScreen1PrevPageText = $null # previous page's raw capture, for end-of-list duplicate detection
$global:CR_PipelineScreen1RetryCount   = 0     # consecutive "unrecognized screen"/"no rows found" retries
$global:CR_PipelineScreen1Rows         = @()   # row slots through last COB: @{ LineIndex; ColIndex; HasCob }
$global:CR_PipelineScreen2CapturedText = $null # text captured right after landing on Screen 2, handed to Screen2.ps1 for logging
$global:CR_PipelineScreen2BeforeSelectionText = $null # baseline for detecting an in-place S/Enter error banner
$global:CR_PipelineSourceSelectionSent = $false # enforce at most one S per COMPONENT VERSION page
$global:CR_PipelineSourceCandidateIdx = 0
$global:CR_PipelineSourceCandidates = @()
$global:CR_PipelineSourceCaptureText = $null
$global:CR_PipelineSourceCapturePreviousText = $null
$global:CR_PipelineSourceLogFile = $null
$global:CR_PipelineSourceLogFileCbl = $null
$global:CR_PipelineSourceCapturePages = 0
$global:CR_PipelineSourceCaptureRetries = 0

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
        # ---- A Pipeline is running (repository -> component version ->
        # source capture, screen by screen); the classic Relay and
        # single-level scan Mode state machines below are both skipped
        # entirely while this is the case. Each screen's own logic lives in its own
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
                'Src*'  { Invoke-PipelineScreen3Tick }
                'Sql_*' { Invoke-PipelineScreen3Tick }

                # ---- Single F3 press back to the previous screen, then
                # verify we actually landed where expected before
                # resuming wherever the caller queued up via AfterBack.
                # Always exactly one F3 press - never held/repeated.
                # The repository loop returns automatically after source
                # capture completes; other back actions
                # retain the configured step-confirm gate. F3 alone does
                # not guarantee some screens won't
                # still jump back further than intended (e.g. all the
                # way out to a logout screen), so Back_Copy checks the
                # landing screen against what AfterBack implies before
                # continuing: CompNext_Action means "should be back on
                # screen 1", EnvNext_Action means "should be back on
                # screen 2". A mismatch stops the pipeline rather than
                # risk compounding it by pressing on regardless. ----
                'Back_Action' {
                    $desc = "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] About to press $F3Display to go back"
                    if ($global:CR_PipelineAfterBack -ne 'CompNext_Action' -and (Request-PipelineStepConfirm -Description $desc)) { return }

                    if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window is gone - stopping." -ForegroundColor Red
                        Stop-PipelineCapture
                        return
                    }
                    # Never trust the remembered page before F3. Copy the
                    # live terminal now and let Back_PrecheckCopy refuse
                    # the key if the page is already REPOSITORY LIST (or
                    # cannot be identified).
                    try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
                    [System.Windows.Forms.SendKeys]::SendWait('^c')
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Checking the live page before allowing F3" ([System.Drawing.Color]::Lime)
                    $global:CR_PipelineState = 'Back_PrecheckWait'
                    $global:CR_ElapsedMs = 0
                }
                'Back_PrecheckWait' {
                    $global:CR_ElapsedMs += $TimerTickMs
                    $precheckDelayMs = switch ([int]$global:CR_PipelineCurrentScreen) {
                        3 { [int]$PipelineTimingsMs.SourceCode.AfterClipboardCopyMs }
                        2 { [int]$PipelineTimingsMs.ComponentVersion.AfterClipboardCopyMs }
                        default { [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs }
                    }
                    if ($global:CR_ElapsedMs -ge $precheckDelayMs) {
                        $global:CR_PipelineState = 'Back_PrecheckCopy'
                        $global:CR_ElapsedMs = 0
                    }
                }
                'Back_PrecheckCopy' {
                    $text = ''
                    try {
                        if ([System.Windows.Forms.Clipboard]::ContainsText()) { $text = [System.Windows.Forms.Clipboard]::GetText() }
                    } catch {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Clipboard read failed during the pre-F3 page check: $_" -ForegroundColor Yellow
                    }
                    $liveScreen = Update-PipelineScreenTracking -Text $text -PipelineName $pipeline.Name
                    if ($liveScreen -eq 1) {
                        if ($global:CR_PipelineAfterBack -eq 'CompNext_Action') {
                            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Already on REPOSITORY LIST; F3 blocked and returning to the repository loop" ([System.Drawing.Color]::Yellow)
                            $global:CR_PipelineState = 'Back_Copy'
                            $global:CR_ElapsedMs = [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs
                        } else {
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] F3 blocked: live page check found REPOSITORY LIST, where F3 is forbidden. Stopping safely." -ForegroundColor Red
                            Show-RelayResultOverlay -Text "F3 BLOCKED ON REPOSITORY LIST" -Color ([System.Drawing.Color]::Red)
                            Stop-PipelineCapture
                        }
                        return
                    }
                    if ($liveScreen -notin @(2, 3)) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] F3 blocked: the live page could not be identified, so it is unsafe to press F3." -ForegroundColor Red
                        Show-RelayResultOverlay -Text "F3 BLOCKED - PAGE UNKNOWN" -Color ([System.Drawing.Color]::Red)
                        Stop-PipelineCapture
                        return
                    }
                    if (-not (Set-RelayForeground -Handle $global:CR_TargetHandle)) {
                        Write-Host "[AutoClipCapture] [$($pipeline.Name)] Target window disappeared after the pre-F3 page check; F3 was not sent." -ForegroundColor Red
                        Stop-PipelineCapture
                        return
                    }
                    Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Live page is $(Get-PipelineScreenNameFromNumber -ScreenNumber $liveScreen); sending F3" ([System.Drawing.Color]::Orange)
                    [System.Windows.Forms.SendKeys]::SendWait($F3ActionKeyToken)
                    $global:CR_PipelineState = 'Back_Wait'
                    $global:CR_ElapsedMs = 0
                }
                'Back_Wait' {
                    $global:CR_ElapsedMs += $TimerTickMs
                    $backDelayMs = switch ([int]$global:CR_PipelineCurrentScreen) {
                        3 { [int]$PipelineTimingsMs.SourceCode.AfterF3Ms }
                        2 { [int]$PipelineTimingsMs.ComponentVersion.AfterF3Ms }
                        default { [int]$PipelineTimingsMs.RepositoryList.AfterF3Ms }
                    }
                    if ($global:CR_ElapsedMs -ge $backDelayMs) {
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
                    $backCopyDelayMs = if ($global:CR_PipelineAfterBack -eq 'CompNext_Action') {
                        [int]$PipelineTimingsMs.RepositoryList.AfterClipboardCopyMs
                    } else {
                        [int]$PipelineTimingsMs.ComponentVersion.AfterClipboardCopyMs
                    }
                    if ($global:CR_ElapsedMs -ge $backCopyDelayMs) {
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
                            if ($expected -eq 1 -and $detected -eq 2 -and [int]$global:CR_PipelineBackRetryCount -lt 1) {
                                $global:CR_PipelineBackRetryCount++
                                Write-Host "[AutoClipCapture] [$($pipeline.Name)] F3 returned to COMPONENT VERSION instead of REPOSITORY LIST; trying one more F3 before skipping the failed row." -ForegroundColor Yellow
                                $global:CR_PipelineState = 'Back_Action'
                                $global:CR_ElapsedMs = 0
                                return
                            }
                            if ($expected -eq 1 -and [int]$global:CR_PipelineBackRetryCount -lt 2) {
                                $reason = "F3 landed on screen $detected instead of REPOSITORY LIST; trying one final return before advancing."
                                Write-Host "[AutoClipCapture] [$($pipeline.Name)] $reason" -ForegroundColor Yellow
                                Skip-PipelineRowAfterFailure -Reason $reason -ObservedText $text
                                $global:CR_PipelineBackRetryCount = 2
                                return
                            }
                            Write-Host "[AutoClipCapture] [$($pipeline.Name)] Landed on screen $detected after going back, expected screen $expected - stopping to be safe." -ForegroundColor Red
                            Show-RelayResultOverlay -Text "UNEXPECTED SCREEN - STOPPED" -Color ([System.Drawing.Color]::Red)
                            Stop-PipelineCapture
                            return
                        }

                        if ($expected -eq 1 -and -not (Assert-Screen1CommandFieldEmpty -Text $text -PipelineName $pipeline.Name)) { return }

                        if ($expected -eq 1) {
                            Set-RelayStatus "-> $($global:CR_TargetTitle) : [$($pipeline.Name)] Back on REPOSITORY LIST; copying and checking old COB selection marks" ([System.Drawing.Color]::Lime)
                            $repositoryRows = Get-Screen1RowsOnPage -Text $text -RowsPerPage ([int]$pipeline.Screen1Select.RowsPerPage)
                            $refreshedRows = @(Get-Screen1RowsThroughLastCob -Text $text -Screen1Select $pipeline.Screen1Select -RowCount $repositoryRows)
                            $previousSlotCount = $global:CR_PipelineScreen1Rows.Count
                            if ($refreshedRows.Count -eq 0 -or $refreshedRows.Count -ne $previousSlotCount) {
                                Write-Host "[AutoClipCapture] [$($pipeline.Name)] REPOSITORY LIST row count changed after return ($previousSlotCount -> $($refreshedRows.Count)); stopping before advancing." -ForegroundColor Red
                                Show-RelayResultOverlay -Text "REPOSITORY ROW COUNT CHANGED - STOPPED" -Color ([System.Drawing.Color]::Red)
                                Stop-PipelineCapture
                                return
                            }
                            if ($global:CR_PipelineComponentIdx -ge $refreshedRows.Count) {
                                Write-Host "[AutoClipCapture] [$($pipeline.Name)] The refreshed REPOSITORY LIST rows no longer align with the active row index; stopping safely." -ForegroundColor Red
                                Show-RelayResultOverlay -Text "ROW MAPPING CHANGED - STOPPED" -Color ([System.Drawing.Color]::Red)
                                Stop-PipelineCapture
                                return
                            }
                            $global:CR_PipelineScreen1Rows = $refreshedRows
                            $global:CR_PipelineScreen1PrevPageText = $text
                        }

                        $global:CR_PipelineState     = $global:CR_PipelineAfterBack
                        $global:CR_PipelineAfterBack = $null
                        $global:CR_PipelineBackRetryCount = 0
                        $global:CR_ElapsedMs         = 0
                    }
                }
            }
        } catch {
            Write-Host "[AutoClipCapture] [$($global:CR_ActivePipelineConfig.Name)] Tick error (recovered): $($_.Exception.Message)" -ForegroundColor Yellow
            $failedState = [string]$global:CR_PipelineState
            if ($failedState -like 'Src*' -or $failedState -like 'Env*' -or $failedState -like 'CompZoom*' -or $failedState -like 'CompReject*' -or $failedState -like 'Back_*') {
                # Log row-level errors and recover to the repository list
                # before moving on to another COB row.
                $observedFailureText = if ($failedState -like 'Src*') { [string]$global:CR_PipelineSourceCaptureText } elseif ($failedState -like 'Env*') { [string]$global:CR_PipelineScreen2CapturedText } else { [string]$global:CR_PipelineScreen1PrevPageText }
                Skip-PipelineRowAfterFailure -Reason "Pipeline tick failed in state '$failedState': $($_.Exception.Message)" -ObservedText $observedFailureText
            } else {
                # Re-scan rather than resume CompZoom_Action directly -
                # the error could have hit mid-scan, leaving the row list
                # stale or empty.
                $global:CR_PipelineState = 'CompScan_Action'
                $global:CR_ElapsedMs = 0
            }
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
                if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.SourceCode.AfterClipboardCopyMs) {
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
                if ($global:CR_ElapsedMs -ge [int]$PipelineTimingsMs.SourceCode.AfterActionKeyMs) {
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
            Write-Host "[AutoClipCapture] Can't start Auto capture current file - '$busyName' is currently running." -ForegroundColor Yellow
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
            #    two files: <base>.txt in ..\txt and <base>.cbl in
            #    ..\cbl (the folders just outside the script's folder).
            #    UPDATE: there is no filename prompt anymore. The base
            #    name is inferred automatically from the first screen
            #    of the target window: Ctrl+C it, find the line that
            #    starts with "BROWSE", and take what's inside the
            #    parentheses on that line - e.g. "BROWSE (CF205) ..."
            #    gives the base name CF205.
            $name = Get-AutoCaptureBaseName -Handle $target.Handle
            if ([string]::IsNullOrWhiteSpace($name)) {
                Write-Host "[AutoClipCapture] Capture start cancelled - no 'BROWSE (...)' line found on the first screen, so no filename could be inferred. Open the source code screen and try again." -ForegroundColor Red
                Show-RelayResultOverlay -Text "NO FILENAME FOUND" -Color ([System.Drawing.Color]::OrangeRed)
                Hide-RelayStatus
                return
            }
            $safeName = Get-SafeFileName $name
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $safeName }
            Write-Host "[AutoClipCapture] Filename inferred from screen: $baseName" -ForegroundColor Cyan

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
    elseif ($id -eq $RestartHotkeyId) {
        Write-Host "[AutoClipCapture] Restarting completely by $RestartDisplay..." -ForegroundColor Cyan
        $global:CR_RestartRequested = $true
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
        # On Host On-Demand, identify the live page before sending F3.
        # REPOSITORY LIST is an absolute no-F3 page; unknown pages fail
        # closed too. Other focused apps keep the original direct F3 use.
        $fgHandle = [Win32]::GetForegroundWindow()
        $fgTitleBuilder = New-Object System.Text.StringBuilder 256
        if ($fgHandle -ne [IntPtr]::Zero) { [void][Win32]::GetWindowText($fgHandle, $fgTitleBuilder, $fgTitleBuilder.Capacity) }
        $fgTitle = $fgTitleBuilder.ToString()
        if ($fgTitle.StartsWith('3270-display(32 regels)', [System.StringComparison]::OrdinalIgnoreCase)) {
            try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            Start-Sleep -Milliseconds ([Math]::Max(150, [int]$PipelineTimingsMs.ComponentVersion.AfterClipboardCopyMs))
            $pageText = ''
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) { $pageText = [System.Windows.Forms.Clipboard]::GetText() }
            } catch {
                Write-Host "[AutoClipCapture] Could not read Host On-Demand page before manual F3: $_" -ForegroundColor Yellow
            }
            $pageNumber = Get-PipelineScreenNumber -Text $pageText
            if ($pageNumber -eq 1) {
                Write-Host "[AutoClipCapture] F3 blocked: the focused Host On-Demand page is REPOSITORY LIST, where F3 is forbidden." -ForegroundColor Red
                return
            }
            if ($pageNumber -notin @(2, 3)) {
                Write-Host "[AutoClipCapture] F3 blocked: the focused Host On-Demand page could not be identified safely." -ForegroundColor Red
                return
            }
        }
        [System.Windows.Forms.SendKeys]::SendWait($F3ActionKeyToken)
        Write-Host "[AutoClipCapture] F3 sent to the focused window." -ForegroundColor Green
    }
    elseif ($id -eq $StopHotkeyId) {
        if ($global:CR_Selecting) { return }
        if ($null -eq $global:CR_ActiveAutomation) {
            Write-Host "[AutoClipCapture] No automation is running." -ForegroundColor DarkGray
            return
        }

        if ($global:CR_ActiveAutomation -eq 'Relay') {
            Stop-RelayCapture
        } elseif ($null -ne $global:CR_ActivePipelineConfig) {
            Stop-PipelineCapture
        } else {
            Stop-ModeCapture
        }
        Write-Host "[AutoClipCapture] STOPPED by $StopDisplay." -ForegroundColor Cyan
    }
    elseif ($id -eq $PauseHotkeyId) {
        if ($global:CR_Selecting) { return }
        if ($null -eq $global:CR_ActiveAutomation) {
            Write-Host "[AutoClipCapture] No automation is running to pause." -ForegroundColor DarkGray
            return
        }

        if (-not $global:CR_Paused) {
            $timer.Stop()
            $global:CR_Paused = $true
            Set-RelayStatus "-> $($global:CR_TargetTitle) : PAUSED (press $PauseDisplay to resume)" ([System.Drawing.Color]::Yellow)
            Write-Host "[AutoClipCapture] PAUSED by $PauseDisplay. Press $PauseDisplay again to resume." -ForegroundColor Yellow
        } else {
            $global:CR_Paused = $false
            $timer.Start()
            Set-RelayStatus "-> $($global:CR_TargetTitle) : resumed" ([System.Drawing.Color]::Lime)
            Write-Host "[AutoClipCapture] Resumed by $PauseDisplay." -ForegroundColor Green
        }
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
    elseif ($PipelineHotkeyMap.ContainsKey($id) -or $PipelineStepHotkeyMap.ContainsKey($id)) {
        # Ctrl+Shift+M (Hotkey) = fully automatic; Ctrl+Shift+N (StepHotkey) = step by step.
        $isStepRun = $PipelineStepHotkeyMap.ContainsKey($id)
        $pipeline  = if ($isStepRun) { $PipelineStepHotkeyMap[$id] } else { $PipelineHotkeyMap[$id] }
        $pressedHotkey = if ($isStepRun) { $pipeline.StepHotkey } else { $pipeline.Hotkey }
        if (-not (Test-RightModifierSatisfied -Modifiers ([int]$pressedHotkey.Modifiers) -RequireRight ([bool]$pressedHotkey.RequireRightModifier))) { return }
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
                    Invoke-Screen1CalibrationNow -Pipeline $pipeline -TargetHandle $target.Handle
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
            $global:CR_PipelineStartRowLineIndex = -1
            $global:CR_PipelineStartRowName = ''
            $global:CR_PipelineStartPickerPending = (-not $useComponentList -and $null -ne $pipeline.Screen1Select)
            $global:CR_PipelineLastProcessedCobLineIndex = -1
            $global:CR_PipelineBWriteRetryCount = 0
            $global:CR_PipelineCleanupLineIndex = -1
            $global:CR_PipelineCleanupKeepCount = 0
            $global:CR_PipelineCleanupResumeState = 'CompZoom_Action'
            $global:CR_PipelineCleanupRetryCount = 0
            $global:CR_PipelineEnvironmentIdx   = 0
            $global:CR_PipelineSqlIterations    = 0
            $global:CR_PipelineAfterBack        = $null
            $global:CR_PipelineBackRetryCount  = 0
            $global:CR_PipelineFailureRowLogged = $false
            $global:CR_PipelineComponentLabel   = $null
            $global:CR_PipelineEnvironmentLabel = $null
            $global:CR_PipelineCurrentScreen    = 0
            $global:CR_PipelineListPageIdx      = 0
            $global:CR_PipelineListPrevFiltered = $null
            $global:CR_PipelineListOutputPath   = if ($useComponentList) { Join-Path $LogDir $pipeline.ComponentList.OutputFileName } else { $null }
            $global:CR_PipelineScreen1PageIdx      = 0
            $global:CR_PipelineScreen1IsLastPage   = $false
            $global:CR_PipelineScreen1PrevPageText = $null
            $global:CR_PipelineScreen1RetryCount   = 0
            $global:CR_PipelineScreen1Rows          = @()
            $global:CR_PipelineScreen2CapturedText = $null
            $global:CR_PipelineSourceCandidateIdx = 0
            $global:CR_PipelineSourceCandidates = @()
            $global:CR_PipelineStepPending     = $false
            $global:CR_PipelineStepConfirmed   = $false
            $global:CR_PipelineStepDescription = ''
            Hide-StepMarker
            $global:CR_StepConfirmEnabled = ($isStepRun -and $global:CR_StepConfirmAllowed)
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
                } else {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Automatic mode - running all steps without confirmation." -ForegroundColor Cyan
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
[HotkeyForm]::UnregisterHotKey($FormHandle, $StopHotkeyId)    | Out-Null
[HotkeyForm]::UnregisterHotKey($FormHandle, $PauseHotkeyId)   | Out-Null
[HotkeyForm]::UnregisterHotKey($FormHandle, $RestartHotkeyId) | Out-Null
Unregister-PipelineStepHotkey
foreach ($hkId in $ModeHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
foreach ($hkId in $PipelineHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
$menuSyncTimer.Stop()
$menuOverlay.Dispose()
$statusForm.Dispose()
$resultOverlay.Dispose()
Write-Host "AutoClipCapture stopped."
if ($global:CR_RestartRequested) {
    $restartExecutable = Join-Path $PSHOME 'powershell.exe'
    $restartArguments = '-STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    try {
        Start-Process -FilePath $restartExecutable -ArgumentList $restartArguments -WorkingDirectory $PSScriptRoot
    } catch {
        Write-Host "Could not restart AutoClipCapture: $_" -ForegroundColor Red
    }
}
