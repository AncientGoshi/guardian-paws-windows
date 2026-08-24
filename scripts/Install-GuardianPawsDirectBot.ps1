<#
Installs the direct local Telegram bot. Run once as a parent administrator on the Windows PC.
It creates a new standard local child account and three visible Scheduled Tasks:
- GuardianPaws-DirectBot (LocalSystem; Telegram long-poll controller)
- GuardianPaws-ChildAgent (child account; per-user Edge/Chrome Shorts policy)
- GuardianPaws-Enforcer (LocalSystem; scheduled downtime and configured app limits every minute)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ChildUserName,
    [string]$DisplayName = $ChildUserName,
    [securestring]$BotToken,
    [ValidatePattern('^https://')][string]$MiniAppUrl = 'https://guard.catbiologymc.com/guardian',
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$ExtensionUpdateUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this setup from PowerShell opened with Run as administrator.' }
if ($ChildUserName.Length -lt 1 -or $ChildUserName.Length -gt 20 -or $ChildUserName -match '[<>:"/\\|?*\[\];=,+\s]' -or $ChildUserName -in @('Administrator', 'DefaultAccount', 'Guest', 'WDAGUtilityAccount')) { throw 'Use a new 1–20 character child username without spaces/reserved characters or a built-in account name.' }
$existingChild = Get-LocalUser -Name $ChildUserName -ErrorAction SilentlyContinue
if ($existingChild -and $existingChild.Description -ne 'Guardian Paws standard child account') { throw "'$ChildUserName' already exists and is not an incomplete Guardian Paws child account. Refusing to modify it." }
$reusingIncompleteChild = $null -ne $existingChild
if (-not $BotToken) { $BotToken = Read-Host -AsSecureString -Prompt 'Paste the existing Telegram bot token' }
if ($BotToken.Length -eq 0) { throw 'No bot token was supplied.' }

$childPassword = Read-Host -AsSecureString -Prompt "Create a password for the new child account $ChildUserName"
if ($childPassword.Length -eq 0) { throw 'No child password was supplied.' }
if ($reusingIncompleteChild) {
    # Safe recovery only for the exact account marker created by a prior interrupted installer run.
    Set-LocalUser -Name $ChildUserName -Password $childPassword
    $childLocalUser = Get-LocalUser -Name $ChildUserName -ErrorAction Stop
} else {
    New-LocalUser -Name $ChildUserName -FullName $DisplayName -Password $childPassword -AccountNeverExpires -Description 'Guardian Paws standard child account' | Out-Null
    $childLocalUser = Get-LocalUser -Name $ChildUserName -ErrorAction Stop
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$root = Join-Path $env:ProgramData 'GuardianPaws'
$app = Join-Path $root 'app'
New-Item -ItemType Directory -Force -Path $app | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'src') -Destination $app -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot 'scripts') -Destination $app -Recurse -Force
Import-Module (Join-Path $app 'src/GuardianPaws.DirectBot.psm1') -Force

$bytes = New-Object byte[] 4
# .NET Framework / Windows PowerShell 5.1 has no static RandomNumberGenerator.Fill().
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$pairingCode = (100000000 + ([BitConverter]::ToUInt32($bytes, 0) % 900000000)).ToString()
$config = [pscustomobject]@{
    Version = 1
    ChildUserName = $ChildUserName
    ChildSid = $childLocalUser.SID.Value
    BotTokenProtected = Protect-GuardianPawsMachineSecret -Secret $BotToken
    MiniAppUrl = $MiniAppUrl
    ExtensionUpdateUrl = $ExtensionUpdateUrl
    GuardianIds = @()
    Pairing = [pscustomobject]@{ Code = $pairingCode; ExpiresUtc = [datetime]::UtcNow.AddMinutes(15).ToString('o') }
    # Parent administrators may edit only this constrained schema. Empty schedules/apps mean no enforcement.
    Policy = [pscustomobject]@{ Version = 1; ScheduledDowntime = @(); Applications = @(); GlobalDailyMinutes = 1440 }
}
$configPath = Join-Path $root 'config.json'
$statePath = Join-Path $root 'state.json'
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8 -NoNewline
[pscustomobject]@{ ShortsBlocked = $false; UpdatedUtc = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8 -NoNewline

# Bot secret is readable only by SYSTEM and local administrators. The child can only read state/app files.
$childIdentity = "$env:COMPUTERNAME\$ChildUserName"
& icacls $root /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' "$childIdentity`:(OI)(CI)RX" | Out-Null
& icacls $configPath /inheritance:r /grant:r 'SYSTEM:F' 'Administrators:F' | Out-Null
& icacls $statePath /inheritance:r /grant:r 'SYSTEM:F' 'Administrators:F' "$childIdentity`:R" | Out-Null

$botAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$app\scripts\GuardianPaws.DirectBot.ps1`""
$botTrigger = New-ScheduledTaskTrigger -AtStartup
$system = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'GuardianPaws-DirectBot' -TaskPath '\GuardianPaws\' -Action $botAction -Trigger $botTrigger -Principal $system -Settings $settings -Force | Out-Null

$agentAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$app\scripts\GuardianPaws.ChildAgent.ps1`" -StatePath `"$statePath`" -ExtensionUpdateUrl `"$ExtensionUpdateUrl`""
$agentTrigger = New-ScheduledTaskTrigger -AtLogOn -User $childIdentity
$childPrincipal = New-ScheduledTaskPrincipal -UserId $childIdentity -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'GuardianPaws-ChildAgent' -TaskPath '\GuardianPaws\' -Action $agentAction -Trigger $agentTrigger -Principal $childPrincipal -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -Force | Out-Null

# This normal Task Scheduler entry is deliberately visible. It runs once per minute as SYSTEM.
$enforcerAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$app\scripts\GuardianPaws.Enforcer.ps1`""
$enforcerTrigger = New-ScheduledTaskTrigger -Daily -At '12:00AM' -DaysInterval 1 -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 1)
Register-ScheduledTask -TaskName 'GuardianPaws-Enforcer' -TaskPath '\GuardianPaws\' -Description 'Guardian Paws visible child-account downtime and app-limit enforcer (runs every minute).' -Action $enforcerAction -Trigger $enforcerTrigger -Principal $system -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew) -Force | Out-Null

Start-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-DirectBot'
Start-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-Enforcer'
Write-Host "Installed. In a private chat with the existing bot, send: /pair $pairingCode" -ForegroundColor Green
Write-Host 'That code expires in 15 minutes and permits at most two guardian Telegram accounts.'
Write-Host "Recovery (parent admin): Enable-LocalUser -Name '$ChildUserName'; Unregister-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-Enforcer' -Confirm:`$false"
