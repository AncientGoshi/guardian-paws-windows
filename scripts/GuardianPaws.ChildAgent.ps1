<#
Runs inside the named child account. It changes only that account's HKCU browser policies.
The extension is deliberately visible and force-installed by documented Chromium policy; a
standard child account cannot remove it from normal browser extension controls.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$ExtensionUpdateUrl,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/GuardianPaws.DirectBot.psm1') -Force

$ExtensionId = 'llkmcggfkabiooejicbdngjaagobgaen'
function Set-GuardianPawsShortsBrowserPolicy {
    param([Parameter(Mandatory)][bool]$Blocked)
    $rules = @('*://www.youtube.com/shorts*', '*://youtube.com/shorts*')
    foreach ($browser in @('Microsoft\Edge', 'Google\Chrome')) {
        $key = "HKCU:\Software\Policies\$browser\URLBlocklist"
        if ($Blocked) {
            New-Item -Path $key -Force | Out-Null
            for ($index = 0; $index -lt $rules.Count; $index++) {
                New-ItemProperty -Path $key -Name "GuardianPaws$($index + 1)" -Value $rules[$index] -PropertyType String -Force | Out-Null
            }
        } else { Remove-ItemProperty -Path $key -Name 'GuardianPaws1', 'GuardianPaws2' -ErrorAction SilentlyContinue }
    }
}
function Set-GuardianPawsBrowserExtensionPolicy {
    foreach ($browser in @('Microsoft\Edge', 'Google\Chrome')) {
        $key = "HKCU:\Software\Policies\$browser\ExtensionInstallForcelist"
        New-Item -Path $key -Force | Out-Null
        # Chrome/Edge show this as an organization-managed, force-installed extension.
        New-ItemProperty -Path $key -Name 'GuardianPaws1' -Value "$ExtensionId;$ExtensionUpdateUrl" -PropertyType String -Force | Out-Null
    }
}

do {
    $state = Get-GuardianPawsState -Path $StatePath
    Set-GuardianPawsShortsBrowserPolicy -Blocked ([bool]$state.ShortsBlocked)
    Set-GuardianPawsBrowserExtensionPolicy
    if (-not $Once) { Start-Sleep -Seconds 30 }
} while (-not $Once)
