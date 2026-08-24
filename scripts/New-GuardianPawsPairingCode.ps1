<# Opens one new local, time-limited Telegram pairing window for guardian #2. Run as parent administrator. #>
[CmdletBinding()]
param([string]$Root = "$env:ProgramData\GuardianPaws")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this from PowerShell opened with Run as administrator.' }
$configPath = Join-Path $Root 'config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (@($config.GuardianIds).Count -ge 2) { throw 'Two guardian accounts are already paired. Refusing to create another pairing code.' }
$bytes = New-Object byte[] 4
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$code = (100000000 + ([BitConverter]::ToUInt32($bytes, 0) % 900000000)).ToString()
$config.Pairing.Code = $code
$config.Pairing.ExpiresUtc = [datetime]::UtcNow.AddMinutes(15).ToString('o')
$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8 -NoNewline
Write-Host "In a private chat with the bot, the second guardian must send: /pair $code" -ForegroundColor Green
Write-Host 'The code expires in 15 minutes.'
