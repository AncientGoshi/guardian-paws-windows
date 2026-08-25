# Guardian Paws Windows — Native CMD / EXE release

Guardian Paws is a transparent helper for **one new local standard child account** on a 64-bit Windows 10 or Windows 11 PC.

## This release uses no PowerShell

- Start it through `scripts\Install-GuardianPaws.cmd` from an elevated Command Prompt.
- It runs a self-contained `GuardianPaws.exe`; Windows does **not** need a .NET runtime installed.
- It uses documented Windows components only: `net.exe`, `schtasks.exe`, `icacls.exe`, Registry policy keys, and Windows DPAPI.
- It does not download or execute remote code, use an execution-policy bypass, create Defender exclusions, or hide its tasks.

## What it does

- Prompts locally (hidden input) for the Telegram bot token and a password for a **new** child account.
- Protects the bot token locally with Windows DPAPI and grants access only to `SYSTEM` and local Administrators.
- Copies its EXE visibly to `%ProgramData%\GuardianPaws\app\GuardianPaws.exe`.
- Creates visible root-level tasks named `GuardianPaws-DirectBot` and `GuardianPaws-Enforcer`, running as `SYSTEM`.
- Allows no more than two paired numeric Telegram guardians, and only private-chat commands.
- Offers allowlisted Telegram / Mini App actions: Shorts on/off, downtime on/off, and status.
- Applies documented Edge/Chrome child-HKCU policies for the visible Guardian Paws extension and the YouTube Shorts block list.

## Safety boundary

A standard child account cannot edit the installed EXE or its protected configuration using normal account permissions. A parent Windows Administrator can always inspect, disable, remove, or uninstall Guardian Paws. This is intentional: it is a parental-control helper, not a covert or “tamper-proof” system.

## Install

1. Download the release ZIP and its `.sha256` file from GitHub Releases.
2. In **Command Prompt**, calculate the ZIP hash:

   ```cmd
   certutil -hashfile GuardianPaws-Windows-v1.1.2-win-x64.zip SHA256
   ```

   Compare it exactly with the published `.sha256` value.
3. Extract the ZIP using Explorer or:

   ```cmd
   tar -xf GuardianPaws-Windows-v1.1.2-win-x64.zip
   ```
4. Open **Command Prompt as Administrator**, change into the extracted folder, then run:

   ```cmd
   scripts\Install-GuardianPaws.cmd GuardianChild "Child account" "https://guard.catbiologymc.com/guardian-paws/update.xml"
   ```
5. When it prints a pairing code, send `/pair <code>` privately to the Telegram bot within 15 minutes.
6. Send `/panel` in the paired private chat and use **Open Guardian Paws** for the Mini App.

## Commands

```text
/panel
/shorts off | on | status
/downtime on | off | status
/status
/help
```

## Parent recovery / uninstall

A parent administrator can inspect the two tasks in **Task Scheduler Library**: `GuardianPaws-DirectBot` and `GuardianPaws-Enforcer`.

To remove the scheduled tasks using the packaged CMD launcher:

```cmd
scripts\Install-GuardianPaws.cmd uninstall
```

Then, after preserving anything you need, remove `%ProgramData%\GuardianPaws` manually. Re-enable the child account with:

```cmd
net user GuardianChild /active:yes
```

Do not use Defender exclusions or remote installer commands.

## Validation boundary

The release build is verified on Linux as a self-contained Windows x64 PE executable and through source-level native installer contract tests. Full installation/task/DPAPI/browser-policy behavior still needs a sacrificial physical Windows 10/11 test before broad deployment.
