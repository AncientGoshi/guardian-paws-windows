Set-StrictMode -Version Latest

function Get-GuardianPawsCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Update,
        [Parameter(Mandatory)]$Config,
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    $message = $Update.message
    if ($null -eq $message -or $message.chat.type -ne 'private' -or $null -eq $message.from.id) {
        return [pscustomobject]@{ Action = 'ignored'; SenderId = $null }
    }

    $senderId = [long]$message.from.id
    if ($message -is [System.Collections.IDictionary]) {
        $text = if ($message.Contains('text')) { [string]$message['text'] } else { '' }
        $webAppObject = if ($message.Contains('web_app_data')) { $message['web_app_data'] } else { $null }
    } else {
        $textProperty = $message.PSObject.Properties['text']
        $webAppProperty = $message.PSObject.Properties['web_app_data']
        $text = if ($null -ne $textProperty) { [string]$textProperty.Value } else { '' }
        $webAppObject = if ($null -ne $webAppProperty) { $webAppProperty.Value } else { $null }
    }
    if ($webAppObject -is [System.Collections.IDictionary]) {
        $webAppData = if ($webAppObject.Contains('data')) { [string]$webAppObject['data'] } else { '' }
    } elseif ($null -ne $webAppObject -and $null -ne $webAppObject.PSObject.Properties['data']) {
        $webAppData = [string]$webAppObject.PSObject.Properties['data'].Value
    } else { $webAppData = '' }
    $normalized = $text.Trim().ToLowerInvariant()

    if ($normalized -match '^/pair\s+([0-9]{9})$') {
        $code = $Matches[1]
        $expires = [datetime]$Config.Pairing.ExpiresUtc
        $ids = @($Config.GuardianIds | ForEach-Object { [long]$_ })
        if ($code -eq [string]$Config.Pairing.Code -and $NowUtc.ToUniversalTime() -lt $expires.ToUniversalTime() -and $ids.Count -lt 2 -and $ids -notcontains $senderId) {
            return [pscustomobject]@{ Action = 'pair'; SenderId = $senderId }
        }
        return [pscustomobject]@{ Action = 'unauthorized'; SenderId = $senderId }
    }

    $ids = @($Config.GuardianIds | ForEach-Object { [long]$_ })
    if ($ids -notcontains $senderId) { return [pscustomobject]@{ Action = 'unauthorized'; SenderId = $senderId } }

    if (-not [string]::IsNullOrWhiteSpace($webAppData)) {
        try {
            $payload = $webAppData | ConvertFrom-Json -ErrorAction Stop
            if ($payload.v -eq 1 -and $payload.action -in @('shorts-off', 'shorts-on', 'downtime-on', 'downtime-off', 'status')) {
                return [pscustomobject]@{ Action = [string]$payload.action; SenderId = $senderId; FromMiniApp = $true }
            }
            if ($payload.v -eq 2 -and $payload.action -eq 'policy-set' -and $null -ne $payload.policy) {
                return [pscustomobject]@{ Action = 'policy-set'; SenderId = $senderId; Policy = $payload.policy; FromMiniApp = $true }
            }
        } catch { }
        return [pscustomobject]@{ Action = 'ignored'; SenderId = $senderId }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{ Action = 'ignored'; SenderId = $senderId } }

    $actions = @{
        '/shorts off' = 'shorts-off'; '/shorts on' = 'shorts-on'; '/shorts status' = 'shorts-status'
        '/downtime on' = 'downtime-on'; '/downtime off' = 'downtime-off'; '/downtime status' = 'downtime-status'
        '/status' = 'status'; '/help' = 'help'; '/panel' = 'panel'; '/start' = 'panel'
    }
    $action = if ($actions.ContainsKey($normalized)) { $actions[$normalized] } else { 'unknown' }
    return [pscustomobject]@{ Action = $action; SenderId = $senderId }
}

function Set-GuardianPawsShortsState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Enabled)
    return [pscustomobject]@{ ShortsBlocked = -not $Enabled }
}

function Get-GuardianPawsState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ ShortsBlocked = $false; UpdatedUtc = $null } }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-GuardianPawsState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$State)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.$PID.tmp"
    $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporary -Encoding UTF8 -NoNewline
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Import-GuardianPawsDpapi {
    [CmdletBinding()]
    param()
    # Windows PowerShell 5.1 does not always load the System.Security assembly
    # that defines DPAPI's ProtectedData type until it is explicitly requested.
    Add-Type -AssemblyName 'System.Security' -ErrorAction Stop
}

function Get-GuardianPawsMachineSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProtectedBase64)
    Import-GuardianPawsDpapi
    $protected = [Convert]::FromBase64String($ProtectedBase64)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($protected, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Text.Encoding]::UTF8.GetString($plain)
}

function Protect-GuardianPawsMachineSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory)][securestring]$Secret)
    Import-GuardianPawsDpapi
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try {
        $plainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $protected = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($plainText), $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        return [Convert]::ToBase64String($protected)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

Export-ModuleMember -Function @('Get-GuardianPawsCommand', 'Set-GuardianPawsShortsState', 'Get-GuardianPawsState', 'Save-GuardianPawsState', 'Get-GuardianPawsMachineSecret', 'Protect-GuardianPawsMachineSecret')
