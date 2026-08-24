<#
Guardian Paws enforcement task. This is intentionally a visible LocalSystem task, not a service.
It accepts policy only from the administrator-protected config.json file and acts only on the
configured local child SID and executable basenames that pass the schema below.
#>
[CmdletBinding()]
param([string]$Root = "$env:ProgramData\GuardianPaws")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GuardianPawsProperty {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } }
    elseif ($null -ne $Object.PSObject.Properties[$Name]) { return $Object.PSObject.Properties[$Name].Value }
    return $null
}
function Test-GuardianPawsExactProperties {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Allowed, [string[]]$Required = @())
    $names = if ($Object -is [System.Collections.IDictionary]) { @($Object.Keys | ForEach-Object { [string]$_ }) } else { @($Object.PSObject.Properties.Name) }
    foreach ($name in $names) { if ($Allowed -notcontains $name) { throw "Policy contains unsupported property '$name'." } }
    foreach ($name in $Required) { if ($names -notcontains $name) { throw "Policy is missing required property '$name'." } }
}
function ConvertTo-GuardianPawsExeName {
    param([Parameter(Mandatory)]$Value)
    if ($Value -isnot [string] -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\.exe$') { throw 'Application Name must be a simple .exe basename (no path, spaces, or wildcards).' }
    return $Value.ToLowerInvariant()
}
function ConvertTo-GuardianPawsMinutes {
    param([Parameter(Mandatory)]$Value, [string]$Field = 'DailyMinutes')
    $number = 0
    if (-not [int]::TryParse([string]$Value, [ref]$number) -or $number -lt 1 -or $number -gt 1440) { throw "$Field must be an integer from 1 through 1440." }
    return $number
}
function Test-GuardianPawsTime {
    param([Parameter(Mandatory)]$Value)
    if ($Value -isnot [string] -or $Value -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') { throw 'Downtime Start and End must use 24-hour HH:mm format.' }
}
function ConvertTo-GuardianPawsPolicy {
    <# Strict, intentionally small schema:
       { Version:1, ScheduledDowntime:[{Days:[Monday...],Start:"HH:mm",End:"HH:mm"}],
         Applications:[{Name:"app.exe",DailyMinutes:1..1440,AlwaysAllowed:boolean}], GlobalDailyMinutes:1..1440 }
       No paths, command lines, PIDs, users, or action names are accepted. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Policy)
    Test-GuardianPawsExactProperties -Object $Policy -Allowed @('Version','ScheduledDowntime','Applications','GlobalDailyMinutes') -Required @('Version','ScheduledDowntime','Applications','GlobalDailyMinutes')
    if ([string](Get-GuardianPawsProperty $Policy 'Version') -ne '1') { throw 'Policy Version must be 1.' }
    $downtime = @(Get-GuardianPawsProperty $Policy 'ScheduledDowntime')
    $apps = @(Get-GuardianPawsProperty $Policy 'Applications')
    if ($downtime.Count -gt 28 -or $apps.Count -gt 32) { throw 'Policy has too many downtime windows or applications.' }
    $validDays = @('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')
    $normalizedDowntime = @()
    foreach ($window in $downtime) {
        Test-GuardianPawsExactProperties -Object $window -Allowed @('Days','Start','End') -Required @('Days','Start','End')
        $days = @(Get-GuardianPawsProperty $window 'Days')
        if ($days.Count -lt 1 -or $days.Count -gt 7) { throw 'Downtime Days must contain one through seven day names.' }
        foreach ($day in $days) { if ($day -isnot [string] -or $validDays -notcontains $day) { throw 'Downtime Days contains an invalid day name.' } }
        $start = Get-GuardianPawsProperty $window 'Start'; $end = Get-GuardianPawsProperty $window 'End'
        Test-GuardianPawsTime $start; Test-GuardianPawsTime $end
        if ($start -eq $end) { throw 'Downtime Start and End must differ.' }
        $normalizedDowntime += [pscustomobject]@{ Days = @($days); Start = $start; End = $end }
    }
    $seen = @{}; $normalizedApps = @()
    foreach ($app in $apps) {
        Test-GuardianPawsExactProperties -Object $app -Allowed @('Name','DailyMinutes','AlwaysAllowed') -Required @('Name','DailyMinutes','AlwaysAllowed')
        $name = ConvertTo-GuardianPawsExeName (Get-GuardianPawsProperty $app 'Name')
        if ($seen.ContainsKey($name)) { throw "Application '$name' is duplicated." }; $seen[$name] = $true
        $allowed = Get-GuardianPawsProperty $app 'AlwaysAllowed'
        if ($allowed -isnot [bool]) { throw 'AlwaysAllowed must be a Boolean.' }
        $normalizedApps += [pscustomobject]@{ Name = $name; DailyMinutes = ConvertTo-GuardianPawsMinutes (Get-GuardianPawsProperty $app 'DailyMinutes'); AlwaysAllowed = $allowed }
    }
    return [pscustomobject]@{ Version = 1; ScheduledDowntime = $normalizedDowntime; Applications = $normalizedApps; GlobalDailyMinutes = ConvertTo-GuardianPawsMinutes (Get-GuardianPawsProperty $Policy 'GlobalDailyMinutes') 'GlobalDailyMinutes' }
}
function Test-GuardianPawsDowntimeNow {
    param([Parameter(Mandatory)]$Policy, [datetime]$Now = (Get-Date))
    foreach ($window in $Policy.ScheduledDowntime) {
        $start = [TimeSpan]::ParseExact($window.Start, 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
        $end = [TimeSpan]::ParseExact($window.End, 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
        if ($start -lt $end) { if ($window.Days -contains $Now.DayOfWeek.ToString() -and $Now.TimeOfDay -ge $start -and $Now.TimeOfDay -lt $end) { return $true } }
        else {
            if (($window.Days -contains $Now.DayOfWeek.ToString() -and $Now.TimeOfDay -ge $start) -or ($window.Days -contains $Now.AddDays(-1).DayOfWeek.ToString() -and $Now.TimeOfDay -lt $end)) { return $true }
        }
    }; return $false
}
function Get-GuardianPawsEnforcementState { param([string]$Path) if (Test-Path -LiteralPath $Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }; return [pscustomobject]@{ Date = ''; LastSampleUtc = $null; AppSeconds = @{}; GlobalSeconds = 0; AccountDisabledByEnforcer = $false } }
function Save-GuardianPawsEnforcementState { param([string]$Path, $State) $tmp = "$Path.$PID.tmp"; $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8 -NoNewline; Move-Item -LiteralPath $tmp -Destination $Path -Force }
function Get-GuardianPawsChildProcesses { param([string]$ChildSid, $Policy)
    $configured = @{}; foreach ($app in $Policy.Applications) { $configured[$app.Name] = $app }
    $result = @(); foreach ($process in @(Get-CimInstance Win32_Process)) { $name = ([string]$process.Name).ToLowerInvariant(); if (-not $configured.ContainsKey($name)) { continue }; try { $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop; if ($owner.Sid -eq $ChildSid) { $result += [pscustomobject]@{ ProcessId = [int]$process.ProcessId; Name = $name; Policy = $configured[$name] } } } catch { } }; return $result
}
function Invoke-GuardianPawsEnforcer {
    param([Parameter(Mandatory)][string]$Root)
    $configPath = Join-Path $Root 'config.json'; $statePath = Join-Path $Root 'enforcement-state.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Test-GuardianPawsExactProperties -Object $config -Allowed @('Version','ChildUserName','ChildSid','BotTokenProtected','MiniAppUrl','ExtensionUpdateUrl','GuardianIds','Pairing','LastUpdateId','Policy') -Required @('Version','ChildUserName','ChildSid','Policy')
    if ($config.ChildUserName -isnot [string] -or $config.ChildUserName -notmatch '^[A-Za-z0-9._-]{1,20}$' -or $config.ChildSid -isnot [string] -or $config.ChildSid -notmatch '^S-1-5-21-(\d+-){3}\d+$') { throw 'Configured child identity is invalid.' }
    $policy = ConvertTo-GuardianPawsPolicy $config.Policy; $state = Get-GuardianPawsEnforcementState $statePath; $now = Get-Date
    $child = Get-LocalUser -SID $config.ChildSid -ErrorAction Stop
    if (Test-GuardianPawsDowntimeNow $policy $now) { if ($child.Enabled) { Disable-LocalUser -Name $child.Name; $state.AccountDisabledByEnforcer = $true }; & quser $child.Name 2>$null | Select-Object -Skip 1 | ForEach-Object { if ($_ -match '^\s*>?\S+\s+(\d+)\s+') { & logoff $Matches[1] } } }
    elseif ($state.AccountDisabledByEnforcer) { Enable-LocalUser -Name $child.Name; $state.AccountDisabledByEnforcer = $false }
    $date = $now.ToString('yyyy-MM-dd'); if ($state.Date -ne $date) { $state.Date = $date; $state.AppSeconds = @{}; $state.GlobalSeconds = 0; $state.LastSampleUtc = $null }
    $elapsed = 0; if ($state.LastSampleUtc) { try { $elapsed = [Math]::Min(120, [Math]::Max(0, (($now.ToUniversalTime() - [datetime]$state.LastSampleUtc).TotalSeconds))) } catch { $elapsed = 0 } }
    $processes = @(Get-GuardianPawsChildProcesses $config.ChildSid $policy); $activeNames = @($processes | Select-Object -ExpandProperty Name -Unique)
    foreach ($name in $activeNames) { if ($null -eq $state.AppSeconds.$name) { $state.AppSeconds | Add-Member -NotePropertyName $name -NotePropertyValue 0 }; $state.AppSeconds.$name = [double]$state.AppSeconds.$name + $elapsed; $app = @($policy.Applications | Where-Object Name -eq $name)[0]; if (-not $app.AlwaysAllowed) { $state.GlobalSeconds = [double]$state.GlobalSeconds + $elapsed } }
    $globalExceeded = [double]$state.GlobalSeconds -ge ($policy.GlobalDailyMinutes * 60)
    foreach ($process in $processes) { if ($process.Policy.AlwaysAllowed) { continue }; if ($globalExceeded -or [double]$state.AppSeconds.($process.Name) -ge ($process.Policy.DailyMinutes * 60)) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue } }
    $state.LastSampleUtc = $now.ToUniversalTime().ToString('o'); Save-GuardianPawsEnforcementState $statePath $state
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-GuardianPawsEnforcer -Root $Root }
