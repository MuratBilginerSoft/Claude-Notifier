#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$RepoRaw    = 'https://raw.githubusercontent.com/CHANGEME/claude-notifier/main'
$HelperName = 'notify.ps1'
$HomeDir    = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$InstallDir = Join-Path $HomeDir '.claude-notifier'
$HelperDest = Join-Path $InstallDir $HelperName
$SettingsDir  = Join-Path $HomeDir '.claude'
$SettingsPath = Join-Path $SettingsDir 'settings.json'

function Install-Helper {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    if ($env:CLAUDE_NOTIFIER_SOURCE) {
        $src = Join-Path $env:CLAUDE_NOTIFIER_SOURCE "scripts/$HelperName"
        if (-not (Test-Path $src)) { throw "CLAUDE_NOTIFIER_SOURCE set but $src not found" }
        Copy-Item -Force $src $HelperDest
    } else {
        $url = "$RepoRaw/scripts/$HelperName"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $HelperDest
    }
    Write-Host "[OK] Installed helper to $HelperDest"
}

function ConvertTo-Hashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IList]) {
        $arr = @()
        foreach ($item in $obj) { $arr += ConvertTo-Hashtable $item }
        return $arr
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

function Write-Settings($obj) {
    New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
    $tmp = "$SettingsPath.tmp"
    ($obj | ConvertTo-Json -Depth 32) | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $SettingsPath
}

function Build-HookEntry([string]$EventName) {
    return @{
        hooks = @(@{
            type    = 'command'
            shell   = 'powershell'
            async   = $true
            command = ('& "$HOME\.claude-notifier\notify.ps1" -Event ' + $EventName)
        })
    }
}

function Merge-Hook($settings, [string]$EventName) {
    if (-not $settings.Contains('hooks')) { $settings['hooks'] = @{} }
    if (-not $settings['hooks'].Contains($EventName)) { $settings['hooks'][$EventName] = @() }

    # Remove any existing claude-notifier entries (idempotent re-install)
    $filtered = @()
    foreach ($group in $settings['hooks'][$EventName]) {
        $groupHooks = @()
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

function Install-Hooks {
    $settings = Read-Settings
    Merge-Hook $settings 'Stop'
    Merge-Hook $settings 'Notification'
    Write-Settings $settings
    Write-Host "[OK] Patched $SettingsPath"
}

if ($Uninstall) {
    # Stub â€” implemented in Task 5
    throw "Uninstall not yet implemented."
}

Install-Helper
Install-Hooks
Write-Host ""
Write-Host "claude-notifier installed. Restart Claude Code or run /hooks to load the new settings."
