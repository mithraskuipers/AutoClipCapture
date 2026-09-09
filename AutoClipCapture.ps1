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
                         3. You are asked for a filename - that
                            becomes the .txt file the clipboard data
                            gets appended to for this session.
                            Cancelling this prompt cancels the start
                            (nothing runs).
                       Once running, it repeatedly:
                         1. Brings the selected window to the
                            foreground and sends it CTRL+C
                         2. Waits briefly for the clipboard to update
                         3. Appends the clipboard text to the chosen
                            file
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
                       revealing anything new. That saved list is then
                       available for later use; this phase's job ends
                       once the list is captured.

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
 AutoClipCaptureConfig.json (same folder as this script). Use AutoClipCaptureConfigGUI.ps1 (or
 the "ConfigureAutoClipCapture.bat" launcher) to change them without
 editing this file. If AutoClipCaptureConfig.json doesn't exist yet, a default
 one is created automatically on first run.

 IMPORTANT:
   - Must run in STA mode (needed for clipboard access). The
     included .bat launcher already starts it with -STA.
   - Because the loop now re-focuses your chosen window itself
     before every action, you no longer have to babysit window
     focus by hand - just make sure that window still exists.
     If it gets closed, the capture stops automatically.
=====================================================================
#>

$ConfigPath = Join-Path $PSScriptRoot "AutoClipCaptureConfig.json"

# Pipeline screen logic lives in its own file per screen, all kept in
# this same folder (no subfolders): Screen 1 = components,
# Screen 2 = environments, Screen 3 = the COBOL/SQL search screen.
# ComponentList is an optional "Step 1" pre-pass that also lives on
# Screen 1 (paging through the full component overview once, up
# front, before any zooming happens) - kept in its own file since it's
# a separate phase with its own state names. Dot-sourcing just defines
# their functions into this script's scope - no side effects until the
# pipeline tick handler below actually calls into them.
. (Join-Path $PSScriptRoot "AutoClipCaptureSqlPipelineScreen1.ps1")
. (Join-Path $PSScriptRoot "AutoClipCaptureSqlPipelineScreen2.ps1")
. (Join-Path $PSScriptRoot "AutoClipCaptureSqlPipelineScreen3.ps1")
. (Join-Path $PSScriptRoot "AutoClipCaptureSqlPipelineComponentList.ps1")
. (Join-Path $PSScriptRoot "AutoClipCaptureSqlPipelineScreen1Select.ps1")

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
        OutputFileName     = 'pipeline_component_list.md'
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
}

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
    $lbl.Text = "Enter a filename for this capture (no extension needed):"
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
$statusForm.Size            = New-Object System.Drawing.Size(320, 32)

$screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$statusForm.Location = New-Object System.Drawing.Point(($screenArea.Left + 8), ($screenArea.Top + 8))

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock      = 'Fill'
$statusLabel.TextAlign = 'MiddleCenter'
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
    $global:CR_PipelineState         = 'CompZoom_Action'
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
    $global:CR_PipelineRewindPrevText    = $null
    $global:CR_PipelineRewindPresses     = 0
    $global:CR_PipelineComponentList     = @()
    $global:CR_PipelineSelectSearchPages = 0
    $global:CR_TargetHandle          = [IntPtr]::Zero
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
        $selCfg = $p.Screen1Select
        if ($null -ne $selCfg -and [bool]$selCfg.Enabled) {
            Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (pages through the component list, rewinds to the top, writes a Markdown table - does not open/select anything)" -ForegroundColor White
        } else {
            Write-Host "  $($p.Hotkey.Display)  -> pipeline: $($p.Name)  (pages through the component list, writes a Markdown table - does not open/select anything)" -ForegroundColor White
        }
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
Write-Host ""

$global:CR_Running      = $false
$global:CR_Selecting    = $false
$global:CR_State        = 'Idle'   # Idle -> PostCopy -> PostAction -> Idle ...
$global:CR_ElapsedMs    = 0
$global:CR_LogFile      = $DefaultLogFile
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
$global:CR_PipelineState            = 'CompZoom_Action'
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

# ---- Rewind + Select state (see AutoClipCaptureSqlPipelineScreen1Select.ps1) ----
$global:CR_PipelineRewindPrevText    = $null # previous page's raw text while pressing F7, for "stopped changing = at the top" detection
$global:CR_PipelineRewindPresses     = 0     # safety counter so a page that never stops changing can't loop forever
$global:CR_PipelineComponentList     = @()   # component ids parsed out of the saved list file, in file order
$global:CR_PipelineSelectSearchPages = 0     # how many times F8 has been pressed hunting for the *current* id
$global:CR_PipelineSelectFoundRow    = $null # 0-based text-line index of the row currently being selected, saved for the pre-Enter placement check

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
                'Rewind*' { Invoke-PipelineScreen1SelectTick }
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
            $global:CR_PipelineState = 'CompZoom_Action'
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
                                    Add-Content -Path $global:CR_LogFile -Value $filtered
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
            #    right away once Enter is pressed.
            $name = Show-FilenamePrompt -DefaultName $DefaultBaseName -TargetTitle $target.Title
            if ($null -eq $name) {
                Write-Host "[AutoClipCapture] Capture start cancelled." -ForegroundColor Yellow
                Hide-RelayStatus
                return
            }
            $safeName = Get-SafeFileName $name
            if (-not $safeName.ToLower().EndsWith('.txt')) { $safeName += '.txt' }

            $global:CR_LogFile      = Join-Path $LogDir $safeName
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

            # When this pipeline's component-list pre-pass is enabled,
            # ask for the output filename now (same prompt/validation
            # as the classic Toggle relay's Show-FilenamePrompt), rather
            # than always writing to the fixed name from config. The
            # configured OutputFileName is still used as the suggested
            # default text in the box.
            $listOutputPath = $null
            if ($useComponentList) {
                $defaultListBase = [System.IO.Path]::GetFileNameWithoutExtension($pipeline.ComponentList.OutputFileName)
                $listName = Show-FilenamePrompt -DefaultName $defaultListBase -TargetTitle $target.Title
                if ($null -eq $listName) {
                    Write-Host "[AutoClipCapture] [$($pipeline.Name)] Start cancelled (no filename entered)." -ForegroundColor Yellow
                    Hide-RelayStatus
                    return
                }
                $safeListName = Get-SafeFileName $listName
                if (-not $safeListName.ToLower().EndsWith('.md')) { $safeListName += '.md' }
                $listOutputPath = Join-Path $LogDir $safeListName
            }

            # Row-selection has been removed from this pipeline - it
            # only pages through the component list, optionally
            # rewinds to the top (Screen1Select.Enabled), and writes a
            # Markdown table. Just a confirmation here, nothing
            # blocking.
            $selCfg = $pipeline.Screen1Select
            if ($null -ne $selCfg -and [bool]$selCfg.Enabled) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] Will rewind to the top ($($selCfg.RewindActionDisplay)) once the list is complete." -ForegroundColor Cyan
            }

            Hide-RelayResultOverlay
            $global:CR_TargetHandle             = $target.Handle
            $global:CR_TargetTitle              = $target.Title
            $global:CR_ActiveAutomation         = $pipeline.Id
            $global:CR_ActivePipelineConfig     = $pipeline
            $global:CR_PipelineState            = if ($useComponentList) { 'ListCapture_Start' } else { 'CompZoom_Action' }
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
            $global:CR_PipelineListOutputPath   = $listOutputPath
            $global:CR_PipelineRewindPrevText   = $null
            $global:CR_PipelineRewindPresses    = 0
            $global:CR_PipelineComponentList    = @()
            $global:CR_PipelineSelectFoundRow   = $null
            $global:CR_PipelineSelectSearchPages = 0

            $timer.Stop()
            $timer.Start()

            if ($useComponentList) {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] STARTED -> $($target.Title) (component list pre-pass -> $($global:CR_PipelineListOutputPath))" -ForegroundColor Green
                Set-RelayStatus "-> $($target.Title) : [$($pipeline.Name)] starting component list..." ([System.Drawing.Color]::Lime)
            } else {
                Write-Host "[AutoClipCapture] [$($pipeline.Name)] STARTED -> $($target.Title)" -ForegroundColor Green
                Set-RelayStatus "-> $($target.Title) : [$($pipeline.Name)] starting..." ([System.Drawing.Color]::Lime)
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
foreach ($hkId in $ModeHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
foreach ($hkId in $PipelineHotkeyMap.Keys) {
    [HotkeyForm]::UnregisterHotKey($FormHandle, $hkId) | Out-Null
}
$statusForm.Dispose()
$resultOverlay.Dispose()
Write-Host "AutoClipCapture stopped."
