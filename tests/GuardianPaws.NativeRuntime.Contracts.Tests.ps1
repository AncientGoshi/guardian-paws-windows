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

    It 'passes a quoted task command to schtasks as one native argument' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'ArgumentList\.Add\(taskRun\)'
        $source | Should -Not -Match 'taskRun\.Replace\('
    }

    It 'uses matching local-machine DPAPI scope for bot startup under SYSTEM' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'CryptUnprotectData\([^\r\n]+LocalMachine'
    }

    It 'passes the newly entered child password to net.exe as one native argument' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'CreateChildAccount\(child, password, display\)'
        $source | Should -Match 'ArgumentList\.Add\(password\)'
    }

    It 'keeps the Go installer secret prompts from echoing credentials' {
        $source = Get-Content (Join-Path $root 'native-go/main_windows.go') -Raw
        $source | Should -Match 'getConsoleInputMode'
        $source | Should -Match 'setConsoleInputMode'
        $source | Should -Match 'enableEchoInput'
    }

    It 'keeps the executable in ProgramData and grants the child read-execute only' {
        $source = Get-Content (Join-Path $root 'native/GuardianPaws/Program.cs') -Raw
        $source | Should -Match 'CommonApplicationData'
        $source | Should -Match 'icacls\.exe'
        $source | Should -Match '\(OI\)\(CI\)RX'
    }
}
