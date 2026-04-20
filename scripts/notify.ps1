param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Stop','Notification')]
    [string]$Event
)

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
        $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$(Escape-Xml $msg)</text>
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
