BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'src/GuardianPaws.DirectBot.psm1'
    $script:InstallerPath = Join-Path $script:ProjectRoot 'scripts/Install-GuardianPawsDirectBot.ps1'
    $script:UpdaterPath = Join-Path $script:ProjectRoot 'scripts/Update-GuardianPawsDirectBot.ps1'
}

Describe 'Guardian Paws Windows compatibility contracts' {
    It 'loads the Windows DPAPI assembly before using ProtectedData' {
        $module = Get-Content -LiteralPath $script:ModulePath -Raw
        $assemblyLoad = $module.IndexOf("Add-Type -AssemblyName 'System.Security'")
        $firstProtectedDataUse = $module.IndexOf('[Security.Cryptography.ProtectedData]')
        $assemblyLoad | Should -BeGreaterThan -1
        $firstProtectedDataUse | Should -BeGreaterThan $assemblyLoad
    }

    It 'does not configure background tasks with an execution-policy bypass' {
        foreach ($path in @($script:InstallerPath, $script:UpdaterPath)) {
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match '(?i)-ExecutionPolicy\s+Bypass'
        }
    }

    It 'uses the supported daily-trigger repetition object rather than incompatible trigger parameters' {
        $installer = Get-Content -LiteralPath $script:InstallerPath -Raw
        $installer | Should -Match '\$enforcerTrigger\.Repetition\.Interval\s*=\s*'
        $installer | Should -Match '\$enforcerTrigger\.Repetition\.Duration\s*=\s*'
        $installer | Should -Not -Match 'New-ScheduledTaskTrigger\s+-Daily[^\r\n]*-RepetitionInterval'
    }
}
