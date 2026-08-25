# Guardian Paws Go runtime

This is a pure-Go Windows replacement runtime. It intentionally coexists with
`../native/GuardianPaws`; the C# runtime has not been changed or removed.

## Install a published build

Choose the ZIP that matches the Windows PC:

- `GuardianPaws-Windows-Go-v1.2.1-amd64.zip` for ordinary Intel/AMD 64-bit Windows PCs.
- `GuardianPaws-Windows-Go-v1.2.1-arm64.zip` for Windows on ARM devices.

After checking the accompanying `.sha256` file, extract the ZIP, open **Command Prompt as Administrator** in the extracted folder, then run:

```cmd
scripts\Install-GuardianPaws-Go.cmd ChildName "Child display name" "https://example.com/update.xml"
```

To remove the visible tasks later:

```cmd
scripts\Install-GuardianPaws-Go.cmd uninstall
```

## Build and test on Linux

Run from this directory using the installed Go toolchain:

```sh
GO=/home/dog/.local/go/bin/go
"$GO" test ./...
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 "$GO" build -o ../app/GuardianPaws-Go-amd64.exe .
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 "$GO" build -o ../app/GuardianPaws-Go-arm64.exe .
```

Package the selected architecture as `app/GuardianPaws-Go.exe` alongside
`scripts/Install-GuardianPaws-Go.cmd`. From an elevated Windows CMD prompt:

```cmd
Install-GuardianPaws-Go.cmd ChildName "Child display name" "https://example.com/update.xml"
Install-GuardianPaws-Go.cmd uninstall
```

The installer creates only visible `GuardianPaws-DirectBot` and
`GuardianPaws-Enforcer` Task Scheduler tasks. Parent-admin recovery is through
those visible tasks or the documented uninstall command.

## Deliberate limitations

* Linux tests cover option validation and guardian/WebApp allow-lists only.
  DPAPI, local-account creation, registry policy writes, ACLs, Task Scheduler,
  and Telegram live polling require a real elevated Windows test machine.
* `net.exe` account-active output is English-localized. On a non-English
  Windows installation, `/status` can report downtime even when the account is
  enabled; the enable/disable action itself is unaffected.
* The supplied CMD wrapper is a separate Go entry point so existing C# release
  packaging and its installer remain untouched.
