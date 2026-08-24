BeforeAll {
    . (Join-Path $PSScriptRoot '../scripts/GuardianPaws.Enforcer.ps1')
}

Describe 'Guardian Paws enforcer policy schema' {
    It 'accepts a bounded policy with executable basenames and a weekly schedule' {
        $policy = @{ Version = 1; ScheduledDowntime = @(@{ Days = @('Monday','Tuesday'); Start = '20:30'; End = '07:00' }); Applications = @(@{ Name = 'chrome.exe'; DailyMinutes = 60; AlwaysAllowed = $false }, @{ Name = 'explorer.exe'; DailyMinutes = 1440; AlwaysAllowed = $true }); GlobalDailyMinutes = 90 }
        $actual = ConvertTo-GuardianPawsPolicy $policy
        $actual.Applications[0].Name | Should -Be 'chrome.exe'
        $actual.GlobalDailyMinutes | Should -Be 90
    }
    It 'rejects paths, command lines, and wildcards as application names' {
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@(@{Name='C:\Windows\notepad.exe';DailyMinutes=1;AlwaysAllowed=$false});GlobalDailyMinutes=1 } } | Should -Throw
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@(@{Name='*.exe';DailyMinutes=1;AlwaysAllowed=$false});GlobalDailyMinutes=1 } } | Should -Throw
    }
    It 'rejects unknown policy and application fields' {
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@();GlobalDailyMinutes=1; Command='whoami' } } | Should -Throw
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@(@{Name='calc.exe';DailyMinutes=1;AlwaysAllowed=$false; Path='x'});GlobalDailyMinutes=1 } } | Should -Throw
    }
    It 'requires a Boolean AlwaysAllowed flag and bounded integer minute values' {
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@(@{Name='calc.exe';DailyMinutes='5.5';AlwaysAllowed='false'});GlobalDailyMinutes=1 } } | Should -Throw
        { ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(); Applications=@();GlobalDailyMinutes=1441 } } | Should -Throw
    }
    It 'recognizes an overnight scheduled downtime window using its start day' {
        $policy = ConvertTo-GuardianPawsPolicy @{ Version=1; ScheduledDowntime=@(@{Days=@('Monday');Start='20:00';End='07:00'});Applications=@();GlobalDailyMinutes=1 }
        (Test-GuardianPawsDowntimeNow $policy ([datetime]'2026-08-24T21:00:00')) | Should -BeTrue
        (Test-GuardianPawsDowntimeNow $policy ([datetime]'2026-08-25T06:30:00')) | Should -BeTrue
        (Test-GuardianPawsDowntimeNow $policy ([datetime]'2026-08-25T07:00:00')) | Should -BeFalse
    }
}
