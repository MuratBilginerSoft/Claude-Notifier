# Requires PowerShell 5.1+
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$RepoRaw    = 'https://cdn.jsdelivr.net/gh/MuratBilginerSoft/Claude-Notifier@main'
$HelperName = 'notify.ps1'
$HomeDir    = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$InstallDir = Join-Path $HomeDir '.claude-notifier'
$HelperDest = Join-Path $InstallDir $HelperName
$SettingsDir  = Join-Path $HomeDir '.claude'
$SettingsPath = Join-Path $SettingsDir 'settings.json'

# AUMID registered under HKCU so Windows shows our app name + icon in the
# toast header and actually renders the popup (unregistered AUMIDs are
# silenced in Windows 11 and only reach the Action Center).
$Aumid           = 'BrainyTech.ClaudeNotifier'
$AumidDisplay    = 'Claude Notifier - BrainyTech'
$AumidRegKey     = "HKCU:\SOFTWARE\Classes\AppUserModelId\$Aumid"

function Install-Helper {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    if ($env:CLAUDE_NOTIFIER_SOURCE) {
        $src = Join-Path $env:CLAUDE_NOTIFIER_SOURCE "scripts/$HelperName"
        if (-not (Test-Path $src)) { throw "CLAUDE_NOTIFIER_SOURCE set but $src not found" }
        Copy-Item -Force $src $HelperDest
    } else {
        $url = "$RepoRaw/scripts/$HelperName"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $HelperDest
        } catch {
            throw "Failed to download helper from ${url}: $_"
        }
    }
    Write-Host "[OK] Installed helper to $HelperDest"

    # Icon is non-critical: if download fails, toasts fall back to logo-less
    # rendering rather than aborting the install.
    $iconDest = Join-Path $InstallDir 'icon.png'
    try {
        if ($env:CLAUDE_NOTIFIER_SOURCE) {
            $src = Join-Path $env:CLAUDE_NOTIFIER_SOURCE 'assets/icon.png'
            if (Test-Path $src) { Copy-Item -Force $src $iconDest }
        } else {
            Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/assets/icon.png" -OutFile $iconDest
        }
        if (Test-Path $iconDest) { Write-Host "[OK] Installed icon to $iconDest" }
    } catch {
        Write-Host "[WARN] Could not install icon: $_"
        Write-Host "       Toasts will show without a custom logo."
    }
}

function ConvertTo-Hashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IList]) {
        $arr = @()
        foreach ($item in $obj) { $arr += ,(ConvertTo-Hashtable $item) }
        # Leading comma prevents PowerShell's `return` from unwrapping
        # single-element arrays into scalars (which would erase array-ness
        # before Add-ArraySentinels has a chance to preserve it).
        return ,$arr
    }
    if ($obj -is [PSCustomObject]) {
        $ht = [ordered]@{}
        foreach ($prop in $obj.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    }
    return $obj
}

function Read-Settings {
    if (-not (Test-Path $SettingsPath)) { return [ordered]@{} }
    $raw = Get-Content -Raw -Path $SettingsPath
    if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
    try {
        $parsed = $raw | ConvertFrom-Json
        return ConvertTo-Hashtable $parsed
    } catch {
        throw "Failed to parse ${SettingsPath}: $_`nAborting without changes."
    }
}

# PowerShell 5.1's ConvertTo-Json unwraps single-element arrays nested in
# hashtables (e.g. @{allow = @("x")} serializes to {"allow":"x"} instead of
# {"allow":["x"]}). This corrupts array-valued fields like permissions.allow on
# round-trip. Workaround: before serializing, append a unique sentinel string
# to every single-element array so ConvertTo-Json emits a proper JSON array.
# After serialization, strip the sentinel tokens with a regex pass.
$script:ArraySentinel = '__CN_PRESERVE_ARRAY_SENTINEL__'

function Add-ArraySentinels($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) {
        foreach ($key in @($obj.Keys)) {
            $obj[$key] = Add-ArraySentinels $obj[$key]
        }
        return $obj
    }
    if ($obj -is [System.Collections.IList] -and -not ($obj -is [string])) {
        $walked = @()
        foreach ($item in $obj) { $walked += ,(Add-ArraySentinels $item) }
        if ($walked.Count -eq 1) { return @($walked[0], $script:ArraySentinel) }
        return $walked
    }
    return $obj
}

function Write-Settings($obj) {
    New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
    $null = Add-ArraySentinels $obj
    $json = ($obj | ConvertTo-Json -Depth 32)
    $escaped = [regex]::Escape($script:ArraySentinel)
    $json = [regex]::Replace($json, ",\s*`"$escaped`"", '')
    $tmp = "$SettingsPath.tmp"
    $json | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $SettingsPath
}

function Build-HookEntry([string]$EventName) {
    return [ordered]@{
        hooks = @([ordered]@{
            type    = 'command'
            shell   = 'powershell'
            async   = $true
            command = ('& "$HOME\.claude-notifier\notify.ps1" -Event ' + $EventName)
        })
    }
}

# Merge-Hook mutates $settings in place via reference.
function Merge-Hook($settings, [string]$EventName) {
    if (-not $settings.Contains('hooks')) { $settings['hooks'] = @{} }
    if (-not $settings['hooks'].Contains($EventName)) { $settings['hooks'][$EventName] = @() }

    # Remove any existing claude-notifier entries (idempotent re-install)
    $filtered = @()
    foreach ($group in $settings['hooks'][$EventName]) {
        $groupHooks = @()
        if (-not $group['hooks']) { continue }
        foreach ($h in $group['hooks']) {
            if (-not ($h['command'] -and ($h['command'] -match 'claude-notifier'))) {
                $groupHooks += $h
            }
        }
        if ($groupHooks.Count -gt 0) {
            $group['hooks'] = $groupHooks
            $filtered += $group
        }
    }
    $filtered += Build-HookEntry $EventName
    $settings['hooks'][$EventName] = $filtered
}

function Register-Aumid {
    New-Item -Path $AumidRegKey -Force | Out-Null
    New-ItemProperty -Path $AumidRegKey -Name 'DisplayName' -Value $AumidDisplay -PropertyType String -Force | Out-Null
    $iconPath = Join-Path $InstallDir 'icon.png'
    if (Test-Path -LiteralPath $iconPath) {
        New-ItemProperty -Path $AumidRegKey -Name 'IconUri' -Value $iconPath -PropertyType String -Force | Out-Null
    }
    Write-Host "[OK] Registered toast AUMID $Aumid"
}

function Unregister-Aumid {
    if (Test-Path $AumidRegKey) {
        Remove-Item -Path $AumidRegKey -Recurse -Force
        Write-Host "[OK] Unregistered toast AUMID $Aumid"
    }
}

function Install-Hooks {
    $settings = Read-Settings
    Merge-Hook $settings 'Stop'
    Merge-Hook $settings 'Notification'
    Write-Settings $settings
    Write-Host "[OK] Patched $SettingsPath"
}

function Uninstall-Hooks {
    if (-not (Test-Path $SettingsPath)) {
        Write-Host "No settings.json found; nothing to unpatch."
        return
    }
    $settings = Read-Settings
    if (-not $settings.Contains('hooks')) {
        Write-Host "No hooks section found; nothing to remove."
        return
    }
    foreach ($eventName in @('Stop','Notification')) {
        if (-not $settings['hooks'].Contains($eventName)) { continue }
        $keptGroups = @()
        foreach ($group in $settings['hooks'][$eventName]) {
            $keptHooks = @()
            if (-not $group['hooks']) { continue }
            foreach ($h in $group['hooks']) {
                if (-not ($h['command'] -and ($h['command'] -match 'claude-notifier'))) {
                    $keptHooks += $h
                }
            }
            if ($keptHooks.Count -gt 0) {
                $group['hooks'] = $keptHooks
                $keptGroups += $group
            }
        }
        if ($keptGroups.Count -eq 0) {
            $settings['hooks'].Remove($eventName)
        } else {
            $settings['hooks'][$eventName] = $keptGroups
        }
    }
    if ($settings['hooks'].Count -eq 0) {
        $settings.Remove('hooks')
    }
    Write-Settings $settings
    Write-Host "[OK] Removed claude-notifier hooks from $SettingsPath"
}

function Uninstall-Helper {
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-Host "[OK] Removed $InstallDir"
    } else {
        Write-Host "$InstallDir not found; skipping."
    }
}

if ($Uninstall) {
    Uninstall-Hooks
    Unregister-Aumid
    Uninstall-Helper
    Write-Host ""
    Write-Host "claude-notifier uninstalled."
    exit 0
}

Install-Helper
Register-Aumid
Install-Hooks
Write-Host ""
Write-Host "claude-notifier installed. Restart Claude Code or run /hooks to load the new settings."
