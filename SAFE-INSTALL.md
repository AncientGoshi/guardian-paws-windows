# Guardian Paws Windows: Safe installation

## Do not use the former shortened URL / `IEX` bootstrap

That delivery method is revoked. It was flagged by Microsoft Defender and is not acceptable.

## Requirements

- 64-bit Windows 10 or Windows 11.
- A parent local Administrator account.
- Windows PowerShell 5.1 or newer.
- The existing Telegram bot token.
- Edge and/or Chrome if website screen-time enforcement is wanted.

## Install from a verified GitHub release

1. Download `GuardianPaws-Windows-v1.0.0.zip` from the GitHub release page.
2. In an elevated Windows PowerShell window, calculate its SHA-256:

   ```powershell
   Get-FileHash "$env:USERPROFILE\Downloads\GuardianPaws-Windows-v1.0.0.zip" -Algorithm SHA256
   ```

   Compare it exactly to the release checksum.
3. If it matches, unblock and extract it:

   ```powershell
   Unblock-File "$env:USERPROFILE\Downloads\GuardianPaws-Windows-v1.0.0.zip"
   Expand-Archive "$env:USERPROFILE\Downloads\GuardianPaws-Windows-v1.0.0.zip" -DestinationPath "$env:USERPROFILE\Downloads\GuardianPaws-Windows-v1.0.0" -Force
   Set-Location "$env:USERPROFILE\Downloads\GuardianPaws-Windows-v1.0.0"
   Unblock-File .\scripts\*.ps1
   ```
4. Review `README.md` and the scripts. Guardian Paws deliberately does not use an execution-policy bypass; its visible LocalSystem tasks require this explicit machine-wide policy choice in the elevated PowerShell window:

   ```powershell
   Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
   ```

   Then install explicitly:

   ```powershell
   .\scripts\Install-GuardianPawsDirectBot.ps1 -ChildUserName GuardianChild -DisplayName 'Child account' -ExtensionUpdateUrl 'https://guard.catbiologymc.com/guardian-paws/update.xml'
   ```

The installer prompts locally for the child password and Telegram bot token. It does not embed, upload, or print either secret.

## Recovery

The installer creates visible `\GuardianPaws\` Scheduled Tasks. A parent administrator can inspect/remove them in Task Scheduler. The browser extension is force-installed only in the dedicated child account and can be recovered/removed by the parent administrator.
