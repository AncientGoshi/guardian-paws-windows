# Guardian Paws Windows — Direct Telegram Bot

A transparent Windows parental-controls helper for **one new local standard child account**. The Windows PC runs the Telegram bot directly using Telegram long polling. The existing HTTPS Guardian Paws Mini App is used only as a button-based Telegram control surface: it sends a small allowlisted action back through Telegram to that local bot; it does not receive the bot token or connect directly to the Windows PC.

## What it does

- Creates a named **standard** local child account and refuses to alter an existing account.
- Runs `GuardianPaws-DirectBot` as a visible Task Scheduler entry under `LocalSystem`.
- Stores the Telegram bot token locally, protected with Windows DPAPI machine protection and ACLs limited to `SYSTEM` and local `Administrators`.
- Allows only up to **two** locally paired Telegram numeric account IDs.
- Accepts commands only from a **private Telegram chat**; group chats and unpaired accounts are ignored.
- Provides account-level downtime through `/downtime on` and `/downtime off`.
- Runs a visible `GuardianPaws-Enforcer` LocalSystem task every minute for the optional, administrator-configured weekly downtime and application limits below.
- Provides a **YouTube Shorts switch** for the child’s Microsoft Edge/Google Chrome profile.

## Important limitation: Shorts switch

`/shorts off` writes the documented Chromium URL-block policy for:

```text
*://www.youtube.com/shorts*
*://youtube.com/shorts*
```

It is scoped to the child account’s Edge/Chrome policy hive, not the parent account. The child agent checks the policy state every 30 seconds while that account is logged in.

This is a best-effort browser control, not universal YouTube filtering. It does not affect other browsers, other devices, YouTube apps, or future URL shapes that YouTube may introduce. Restart the child browser after changing the switch, then inspect `edge://policy` or `chrome://policy` if needed.

## Safety boundaries

This project intentionally does **not**:

- hide its Scheduled Tasks or launcher;
- capture passwords, messages, keystrokes, or browsing history;
- accept arbitrary shell commands, URLs, file paths, registry changes, or programs from Telegram;
- interfere with Windows Settings, Safe Mode, or normal uninstall/recovery;
- modify or disable the parent administrator account.

A standard child account can stop its own visible browser-policy agent, so it is not tamper-proof. Keep the parent administrator password private and use router/network controls as an additional layer where needed.

## Optional SYSTEM enforcer policy

The installer creates an inactive, strict `Policy` in `%ProgramData%\GuardianPaws\config.json`. A parent administrator may edit only this schema (and should use an elevated editor):

```json
{
  "Version": 1,
  "ScheduledDowntime": [{ "Days": ["Monday", "Tuesday"], "Start": "20:00", "End": "07:00" }],
  "Applications": [
    { "Name": "chrome.exe", "DailyMinutes": 60, "AlwaysAllowed": false },
    { "Name": "explorer.exe", "DailyMinutes": 1440, "AlwaysAllowed": true }
  ],
  "GlobalDailyMinutes": 90
}
```

Only simple `.exe` **basenames** are accepted (no paths, arguments, wildcards, PIDs, users, or commands); names are limited to 32 configured applications. Times are local `HH:mm` and overnight windows use the selected start day. Limits are 1–1440 minutes. The task samples once each minute and records per-day, per-basename running time in `%ProgramData%\GuardianPaws\enforcement-state.json`; a missed interval is capped at two minutes. It only stops matching configured processes after verifying that their process owner SID is the configured child SID. `AlwaysAllowed` processes are neither stopped nor charged to the global limit. An empty schedule/application list is inactive.

During a scheduled window it logs off and disables only that child account. Outside a window it re-enables the account **only when this enforcer recorded that it disabled it**; it does not undo a parent/Telgram manual disable.

## Before install

1. Copy this folder to the Windows PC.
2. You need the **token** for the existing Telegram bot—not merely its numeric bot ID.
3. If that bot currently has a Telegram webhook pointing to the old Worker, this direct bot removes that webhook on startup so long polling can work. The old webhook/Worker will therefore stop receiving bot updates.
4. Ensure there is a separate parent local Administrator account with an offline-known password.

## Install on the Windows PC

**Use the verified release workflow in [`SAFE-INSTALL.md`](SAFE-INSTALL.md).** Do not use remote PowerShell `IEX` installers, shortened URLs, execution-policy bypasses, or Defender exclusions.

After downloading the release ZIP, verifying its SHA-256, extracting it, and unblocking the reviewed local scripts as documented there, open **Windows PowerShell as Administrator** and explicitly configure the machine's script policy required by the visible `LocalSystem` tasks:

```powershell
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
```

Then change to the extracted project folder and run:

```powershell
.\scripts\Install-GuardianPawsDirectBot.ps1 -ChildUserName GuardianChild -DisplayName 'Child account' -ExtensionUpdateUrl 'https://guard.catbiologymc.com/guardian-paws/update.xml'
```

The installer securely prompts for:

- the existing Telegram bot token;
- a new password for the new child account.

It prints a 9-digit pairing code. Within 15 minutes, send this in a **private** chat to the existing bot:

```text
/pair 123456789
```

The first pairing code adds one guardian. To add a second guardian later, open PowerShell as the parent administrator and run:

```powershell
.\scripts\New-GuardianPawsPairingCode.ps1
```

It prints a new 15-minute private-chat pairing code and refuses to create a third guardian.

## Mini App controls

After the Mini App deployment and the Windows bot update are complete, send `/panel` in the bot's private chat. Tap **Open Guardian Paws**, enter the portal PIN, then use the buttons for Shorts, downtime, or status.

The keyboard button is intentional: Telegram delivers `WebApp.sendData()` actions from it as a `web_app_data` update to the direct long-polling bot. The Mini App can send only these allowlisted action names: `shorts-off`, `shorts-on`, `downtime-on`, `downtime-off`, and `status`. The Windows bot still rejects actions from unpaired Telegram accounts.

### Upgrade an existing direct-bot installation

Copy the updated project folder to the Windows PC, ensure the explicit `LocalMachine` `RemoteSigned` policy described above is still in place, then run this from an elevated PowerShell window:

```powershell
.\scripts\Update-GuardianPawsDirectBot.ps1 -ExtensionUpdateUrl 'https://guard.catbiologymc.com/guardian-paws/update.xml'
```

It preserves the paired guardians and protected bot token, updates the local scripts, registers the Mini App URL (`https://guard.catbiologymc.com/guardian` by default), and restarts the direct-bot task.

## Telegram commands

```text
/shorts off      Block Shorts paths in the child Edge/Chrome profile
/shorts on       Allow Shorts paths again
/shorts status   Show current account and Shorts status

/downtime on     Log off and disable the named child account
/downtime off    Re-enable the named child account
/downtime status Show current account and Shorts status

/status
/help
```

## Local parent recovery

From a parent administrator PowerShell window, recovery does not depend on Telegram, Internet access, or the bot process:

```powershell
Enable-LocalUser -Name 'GuardianChild'
Unregister-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-DirectBot' -Confirm:$false
Unregister-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-ChildAgent' -Confirm:$false
Unregister-ScheduledTask -TaskPath '\GuardianPaws\' -TaskName 'GuardianPaws-Enforcer' -Confirm:$false
```

The original pre-direct-bot scaffold is recoverable on the Pi at:

```text
/opt/guardian-paws-windows-pre-direct-bot-20260824T165103Z.tar.gz
```

## Testing

The source has pure Pester tests for command authorization, private-chat restriction, pairing capacity, Shorts state, and enforcer policy validation:

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

The enforcer policy tests are platform-neutral; scheduled-task registration, DPAPI, local-account changes, process ownership, and actual enforcement must be tested on a sacrificial Windows account before use. This change was not deployed.

## EXE packaging

This is deliberately a PowerShell wrapper first, so it works on x64 and ARM64 Windows without guessing the laptop architecture. The Task Scheduler installer invokes the system `powershell.exe` directly.

A future `.exe` package should ship separate `win-x64` and `win-arm64` builds plus a tiny architecture-selecting launcher. Do not use an `.exe` to hide the Telegram token: it must remain protected in local Windows configuration.
