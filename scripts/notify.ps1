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

if ($sound -eq '1') {
    try {
        if ($Event -eq 'Stop') { [System.Media.SystemSounds]::Asterisk.Play() }
        else                   { [System.Media.SystemSounds]::Exclamation.Play() }
    } catch { [Console]::Error.WriteLine("sound failed: $_") }
}

if ($toast -eq '1') {
    try {
        [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] > $null
        $x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $n = $x.GetElementsByTagName('text')
        $null = $n.Item(0).AppendChild($x.CreateTextNode('Claude Code'))
        $null = $n.Item(1).AppendChild($x.CreateTextNode($msg))
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { [Console]::Error.WriteLine("toast failed: $_") }
}

exit 0
