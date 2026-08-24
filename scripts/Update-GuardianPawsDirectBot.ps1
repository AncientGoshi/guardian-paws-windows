<#
Updates an existing Guardian Paws direct-bot installation with Mini App controls.
Run as a parent administrator from the extracted Guardian Paws project directory.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^https://')][string]$MiniAppUrl = 'https://guard.catbiologymc.com/guardian',
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$ExtensionUpdateUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this update from PowerShell opened with Run as administrator.' }

$root = Join-Path $env:ProgramData 'GuardianPaws'
$app = Join-Path $root 'app'
$configPath = Join-Path $root 'config.json'
if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $app)) { throw 'No existing Guardian Paws direct-bot installation was found.' }

$projectRoot = Split-Path -Parent $PSScriptRoot
Stop-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-DirectBot' -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-Enforcer' -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $projectRoot 'src') -Destination $app -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot 'scripts') -Destination $app -Recurse -Force

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$config | Add-Member -NotePropertyName MiniAppUrl -NotePropertyValue $MiniAppUrl -Force
$config | Add-Member -NotePropertyName ExtensionUpdateUrl -NotePropertyValue $ExtensionUpdateUrl -Force
$child = Get-LocalUser -Name $config.ChildUserName -ErrorAction Stop
$config | Add-Member -NotePropertyName ChildSid -NotePropertyValue $child.SID.Value -Force
if ($null -eq $config.Policy) { $config | Add-Member -NotePropertyName Policy -NotePropertyValue ([pscustomobject]@{ Version = 1; ScheduledDowntime = @(); Applications = @(); GlobalDailyMinutes = 1440 }) -Force }
$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8 -NoNewline
$agentAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$app\scripts\GuardianPaws.ChildAgent.ps1`" -StatePath `"$root\state.json`" -ExtensionUpdateUrl `"$ExtensionUpdateUrl`""
$agentTrigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$($config.ChildUserName)"
$childPrincipal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$($config.ChildUserName)" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'GuardianPaws-ChildAgent' -TaskPath '\GuardianPaws\' -Description 'Guardian Paws visible child-account browser policy agent.' -Action $agentAction -Trigger $agentTrigger -Principal $childPrincipal -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -Force | Out-Null
$system = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$enforcerAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$app\scripts\GuardianPaws.Enforcer.ps1`""
$enforcerTrigger = New-ScheduledTaskTrigger -Daily -At '12:00AM' -DaysInterval 1 -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 1)
Register-ScheduledTask -TaskName 'GuardianPaws-Enforcer' -TaskPath '\GuardianPaws\' -Description 'Guardian Paws visible child-account downtime and app-limit enforcer (runs every minute).' -Action $enforcerAction -Trigger $enforcerTrigger -Principal $system -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew) -Force | Out-Null
Start-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-DirectBot'
Start-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-Enforcer'
Write-Host 'Updated. In a private chat with the paired bot, send /panel and use Open Guardian Paws.' -ForegroundColor Green
