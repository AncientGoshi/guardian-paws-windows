BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/GuardianPaws.DirectBot.psm1') -Force
}

Describe 'Telegram command authorization' {
    BeforeAll {
        $script:GuardianPawsTestConfig = @{ GuardianIds = @(1001); Pairing = @{ Code = '123456789'; ExpiresUtc = '2030-01-01T00:00:00Z' } }
    }

    It 'accepts Shorts commands from an approved guardian in a private chat' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 1001 }; text = '/shorts off' } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'shorts-off'
    }

    It 'rejects a command from an unpaired Telegram account' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 9999 }; text = '/downtime on' } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'unauthorized'
    }

    It 'rejects commands from a group chat even if the sender is approved' {
        $update = @{ message = @{ chat = @{ type = 'group' }; from = @{ id = 1001 }; text = '/shorts on' } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'ignored'
    }

    It 'accepts the limited Mini App Shorts action from an approved guardian' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 1001 }; web_app_data = @{ data = '{"v":1,"action":"shorts-off"}' } } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'shorts-off'
    }

    It 'does not accept arbitrary Mini App payloads' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 1001 }; web_app_data = @{ data = '{"v":1,"action":"open-calculator"}' } } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'ignored'
    }

    It 'rejects Mini App actions from an unpaired Telegram account' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 9999 }; web_app_data = @{ data = '{"v":1,"action":"downtime-on"}' } } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig).Action | Should -Be 'unauthorized'
    }

    It 'allows one valid local pairing code while capacity remains' {
        $update = @{ message = @{ chat = @{ type = 'private' }; from = @{ id = 7777 }; text = '/pair 123456789' } }
        (Get-GuardianPawsCommand -Update $update -Config $script:GuardianPawsTestConfig -NowUtc ([datetime]'2029-12-31T23:00:00Z')).Action | Should -Be 'pair'
    }
}

Describe 'YouTube Shorts state' {
    It 'maps shorts off to a blocked child-browser policy' {
        (Set-GuardianPawsShortsState -Enabled $false).ShortsBlocked | Should -BeTrue
    }

    It 'maps shorts on to an allowed child-browser policy' {
        (Set-GuardianPawsShortsState -Enabled $true).ShortsBlocked | Should -BeFalse
    }
}
