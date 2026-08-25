Describe 'Guardian Paws native Windows release contract' {
    BeforeAll { $root = Split-Path -Parent $PSScriptRoot }

    It 'ships a CMD installer rather than a PowerShell installer entry point' {
        Test-Path (Join-Path $root 'scripts/Install-GuardianPaws.cmd') | Should -BeTrue
        Test-Path (Join-Path $root 'native/GuardianPaws/Program.cs') | Should -BeTrue
    }

    It 'uses Windows-native Task Scheduler through schtasks and does not invoke PowerShell' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'schtasks\.exe'
        $source | Should -Not -Match '(?i)powershell\.exe|New-ScheduledTask|Register-ScheduledTask'
    }

    It 'keeps the executable in ProgramData and grants the child read-execute only' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'CommonApplicationData'
        $source | Should -Match 'icacls\.exe'
        $source | Should -Match '\(OI\)\(CI\)RX'
    }
}
