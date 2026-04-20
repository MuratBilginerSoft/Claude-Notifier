param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Stop','Notification')]
    [string]$Event
)

# Force UTF-8 on stdin/stdout so Turkish (and any non-ASCII) chars survive.
# PowerShell 5.1 inherits the system OEM codepage (e.g. IBM857 on Turkish
# Windows), which corrupts Claude Code's UTF-8 JSON payload before we see it
# and mangles non-ASCII characters in any text we emit.
try {
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

# Defaults
$lang   = if ($env:CLAUDE_NOTIFIER_LANG)   { $env:CLAUDE_NOTIFIER_LANG.ToLower() } else { 'en' }
$events = if ($env:CLAUDE_NOTIFIER_EVENTS) { $env:CLAUDE_NOTIFIER_EVENTS.ToLower() } else { 'stop,notification' }
$sound  = if ([string]::IsNullOrEmpty($env:CLAUDE_NOTIFIER_SOUND)) { '1' } else { $env:CLAUDE_NOTIFIER_SOUND }
$toast  = if ([string]::IsNullOrEmpty($env:CLAUDE_NOTIFIER_TOAST)) { '1' } else { $env:CLAUDE_NOTIFIER_TOAST }

if (($events -split ',') -notcontains $Event.ToLower()) { exit 0 }

$messages = @{
    'Stop'         = @{ 'en' = 'Task complete';               'tr' = 'İş tamamlandı' }
    'Notification' = @{ 'en' = 'Claude needs your attention'; 'tr' = 'Claude dikkatini bekliyor' }
}
$msg = $messages[$Event][$lang]
if (-not $msg) { $msg = $messages[$Event]['en'] }

# --- Hook payload excerpt ---------------------------------------------------
# Claude Code pipes a JSON payload to the hook's stdin:
#   Notification: { message: "...", transcript_path: "...", ... }
#   Stop:         { transcript_path: "...", ... }
# We surface ~200 chars as a secondary toast line so the user can tell at a
# glance *what* finished or *what* Claude is asking, not just that something
# happened. Any failure falls through silently — the generic message still shows.
function Truncate([string]$s, [int]$max) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $clean = ($s -replace '[\r\n\t]+', ' ' -replace '\s+', ' ').Trim()
    if ($clean.Length -le $max) { return $clean }
    return $clean.Substring(0, $max - 1) + [char]0x2026
}

function Get-LastAssistantText([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return '' }
    # Transcript files are UTF-8; Get-Content's default (ANSI/OEM codepage) would
    # garble non-ASCII characters in the assistant's text on Turkish Windows.
    try { $lines = Get-Content -LiteralPath $path -Tail 200 -Encoding UTF8 -ErrorAction Stop } catch { return '' }
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.content) {
                foreach ($item in $obj.message.content) {
                    if ($item.type -eq 'text' -and $item.text) { return [string]$item.text }
                }
            }
        } catch { continue }
    }
    return ''
}

$excerpt = ''
try {
    if ([Console]::IsInputRedirected) {
        # Claude Code writes the JSON payload then closes stdin, so ReadToEnd()
        # returns immediately. If stdin is redirected but empty (e.g. manual
        # test with `< /dev/null`), this returns '' and we fall through.
        $stdinText = [Console]::In.ReadToEnd()
        if (-not [string]::IsNullOrWhiteSpace($stdinText)) {
            $payload = $stdinText | ConvertFrom-Json -ErrorAction Stop
            if ($Event -eq 'Notification' -and $payload.message) {
                $excerpt = Truncate ([string]$payload.message) 200
            } elseif ($Event -eq 'Stop' -and $payload.transcript_path) {
                $excerpt = Truncate (Get-LastAssistantText ([string]$payload.transcript_path)) 200
            }
        }
    }
} catch { [Console]::Error.WriteLine("excerpt extraction failed: $_") }

function Invoke-SoundSpec([string]$spec, [string]$fallback) {
    # $fallback is one of the five built-in names below (trusted).
    # $spec is user-supplied: accepts a built-in name (case-insensitive) or a path to an audio file.
    $builtins = @('Asterisk','Beep','Exclamation','Hand','Question')
    $name = $null
    $file = $null
    if (-not [string]::IsNullOrWhiteSpace($spec)) {
        $match = $builtins | Where-Object { $_ -ieq $spec } | Select-Object -First 1
        if ($match)                         { $name = $match }
        elseif (Test-Path -LiteralPath $spec) { $file = $spec }
        else { [Console]::Error.WriteLine("sound spec not recognized: $spec (not a built-in name or existing file); using default") }
    }
    if (-not $name -and -not $file) { $name = $fallback }
    if ($file) {
        $player = New-Object System.Media.SoundPlayer $file
        $player.PlaySync()
        return
    }
    switch ($name) {
        'Asterisk'    { [System.Media.SystemSounds]::Asterisk.Play() }
        'Beep'        { [System.Media.SystemSounds]::Beep.Play() }
        'Exclamation' { [System.Media.SystemSounds]::Exclamation.Play() }
        'Hand'        { [System.Media.SystemSounds]::Hand.Play() }
        'Question'    { [System.Media.SystemSounds]::Question.Play() }
    }
}

if ($sound -eq '1') {
    try {
        if ($Event -eq 'Stop') { Invoke-SoundSpec $env:CLAUDE_NOTIFIER_SOUND_STOP         'Asterisk'    }
        else                   { Invoke-SoundSpec $env:CLAUDE_NOTIFIER_SOUND_NOTIFICATION 'Exclamation' }
    } catch { [Console]::Error.WriteLine("sound failed: $_") }
}

function Escape-Xml([string]$s) {
    return $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&apos;'
}

# AUMID registered by install.ps1 (HKCU:\SOFTWARE\Classes\AppUserModelId\...).
# Registration provides the app name + icon shown in the toast header and
# makes Windows deliver the popup (unregistered AUMIDs are silenced in 11).
$AUMID = 'BrainyTech.ClaudeNotifier'

if ($toast -eq '1') {
    try {
        $secondText = if ($excerpt) { "<text>$(Escape-Xml $excerpt)</text>" } else { '' }
        $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$(Escape-Xml $msg)</text>
      $secondText
    </binding>
  </visual>
</toast>
"@
        [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] > $null
        [Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime] > $null
        $x = New-Object Windows.Data.Xml.Dom.XmlDocument
        $x.LoadXml($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AUMID).Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { [Console]::Error.WriteLine("toast failed: $_") }
}

exit 0
