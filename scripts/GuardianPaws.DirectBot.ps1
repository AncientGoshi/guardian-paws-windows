<#
Direct Telegram controller. Intended to run as LocalSystem via the installer-created task.
It accepts only private-chat messages from locally paired numeric Telegram IDs.
#>
[CmdletBinding()]
param(
    [string]$Root = "$env:ProgramData\GuardianPaws"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/GuardianPaws.DirectBot.psm1') -Force
$configPath = Join-Path $Root 'config.json'
$statePath = Join-Path $Root 'state.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Guardian Paws configuration missing: $configPath" }

function Read-Config { Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json }
function Save-Config($Config) { $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8 -NoNewline }
function Invoke-Telegram([string]$Method, $Body) {
    $config = Read-Config
    $token = Get-GuardianPawsMachineSecret -ProtectedBase64 $config.BotTokenProtected
    return Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/$Method" -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 6) -TimeoutSec 45
}
function Send-Reply([long]$ChatId, [string]$Text) { Invoke-Telegram -Method 'sendMessage' -Body @{ chat_id = $ChatId; text = $Text } | Out-Null }
function Send-Panel([long]$ChatId) {
    $config = Read-Config
    Invoke-Telegram -Method 'sendMessage' -Body @{
        chat_id = $ChatId
        text = 'Open Guardian Paws to control this Windows child account.'
        reply_markup = @{
            keyboard = @(@(@{ text = 'Open Guardian Paws'; web_app = @{ url = $config.MiniAppUrl } }))
            resize_keyboard = $true
            is_persistent = $true
        }
    } | Out-Null
}
function Configure-MiniApp {
    $config = Read-Config
    Invoke-Telegram -Method 'setChatMenuButton' -Body @{ menu_button = @{ type = 'web_app'; text = 'Guardian Paws'; web_app = @{ url = $config.MiniAppUrl } } } | Out-Null
    Invoke-Telegram -Method 'setMyCommands' -Body @{ commands = @(
        @{ command = 'panel'; description = 'Open Guardian Paws controls' },
        @{ command = 'status'; description = 'Show child status' },
        @{ command = 'shorts'; description = 'Control YouTube Shorts' },
        @{ command = 'downtime'; description = 'Control child access' }
    ) } | Out-Null
}
function Set-Downtime([bool]$Enabled) {
    $config = Read-Config
    if ($Enabled) {
        Disable-LocalUser -Name $config.ChildUserName
        & quser $config.ChildUserName 2>$null | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^\s*\S+\s+(\d+)\s+') { & logoff $Matches[1] }
        }
        return 'Downtime is active. The child account was logged off and disabled. Use /downtime off for recovery.'
    }
    Enable-LocalUser -Name $config.ChildUserName
    return 'Downtime is off. The child account may sign in again.'
}
function Get-StatusText {
    $config = Read-Config; $state = Get-GuardianPawsState -Path $statePath; $child = Get-LocalUser -Name $config.ChildUserName
    $shorts = if ($state.ShortsBlocked) { 'blocked in child Edge/Chrome' } else { 'allowed' }
    $access = if ($child.Enabled) { 'available' } else { 'downtime active' }
    return "Child account: $access`nYouTube Shorts: $shorts"
}
function Apply-Command($Command, $ChatId) {
    switch ($Command.Action) {
        'pair' {
            $config = Read-Config
            $config.GuardianIds = @($config.GuardianIds) + [long]$Command.SenderId
            $config.Pairing.Code = ''
            $config.Pairing.ExpiresUtc = [datetime]::UtcNow.AddMinutes(-1).ToString('o')
            Save-Config $config
            return 'This Telegram account is now paired as a Guardian.'
        }
        'shorts-off' { $state = Set-GuardianPawsShortsState -Enabled $false; $state | Add-Member -NotePropertyName UpdatedUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')); Save-GuardianPawsState -Path $statePath -State $state; return 'YouTube Shorts are blocked for the child Edge/Chrome profile. The child browser may need restarting.' }
        'shorts-on' { $state = Set-GuardianPawsShortsState -Enabled $true; $state | Add-Member -NotePropertyName UpdatedUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')); Save-GuardianPawsState -Path $statePath -State $state; return 'YouTube Shorts are allowed for the child Edge/Chrome profile.' }
        'shorts-status' { return Get-StatusText }
        'downtime-on' { return Set-Downtime -Enabled $true }
        'downtime-off' { return Set-Downtime -Enabled $false }
        'downtime-status' { return Get-StatusText }
        'status' { return Get-StatusText }
        'policy-set' {
            $config = Read-Config
            $config | Add-Member -NotePropertyName Policy -NotePropertyValue $Command.Policy -Force
            Save-Config $config
            return 'Screen-time policy saved. The visible Guardian Paws enforcer will apply the valid parts within one minute.'
        }
        'panel' { return '__OPEN_PANEL__' }
        'help' { return "Commands:`n/panel (open controls)`n/shorts off|on|status`n/downtime on|off|status`n/status" }
        'unknown' { return 'Unknown command. Send /help.' }
        default { return $null }
    }
}

# A direct bot cannot share long-poll updates with a webhook. Remove an old webhook once at startup.
Invoke-Telegram -Method 'deleteWebhook' -Body @{ drop_pending_updates = $false } | Out-Null
Configure-MiniApp
$initialConfig = Read-Config
$offset = if ($null -ne $initialConfig.LastUpdateId) { [long]$initialConfig.LastUpdateId + 1 } else { 0L }
while ($true) {
    try {
        $response = Invoke-Telegram -Method 'getUpdates' -Body @{ offset = $offset; timeout = 30; allowed_updates = @('message') }
        foreach ($update in @($response.result)) {
            $offset = [long]$update.update_id + 1
            $updateConfig = Read-Config
            $updateConfig | Add-Member -NotePropertyName LastUpdateId -NotePropertyValue ([long]$update.update_id) -Force
            Save-Config $updateConfig
            $command = Get-GuardianPawsCommand -Update $update -Config $updateConfig
            if ($command.Action -in @('ignored', 'unauthorized')) { continue }
            $chatId = [long]$update.message.chat.id
            $reply = Apply-Command -Command $command -ChatId $chatId
            if ($reply -eq '__OPEN_PANEL__') { Send-Panel -ChatId $chatId }
            elseif ($reply) { Send-Reply -ChatId $chatId -Text $reply }
        }
    } catch {
        Start-Sleep -Seconds 10
    }
}
