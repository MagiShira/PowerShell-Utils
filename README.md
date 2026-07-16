# Scripting-Utils
Miscellaneous scripts I have written to accomplish things that aren't large enough to warrant their own repository.

Feel free to use anything here in your environment, and, while I make no promises of extended support, if you run into an issue/want to chat about these, feel free to open an [issue](https://github.com/MagiShira/Scripting-Utils/issues).

## Utilities

| Utility | What it does |
| --- | --- |
| [Collect-HardwareId](#collect-hardwareid) | Collects a device's Windows Autopilot hardware ID and builds CSVs for bulk import into Microsoft Intune. |
| [Stage-UserProfile](#stage-userprofile) | Pre-creates a local user's Windows profile (folder + registry hive) without an interactive logon. |
| [TattooRegistry](#tattooregistry) | Writes SCCM Task Sequence environment variables into the registry ("tattooing" a machine). |

### Collect-HardwareId
An **Intune Autopilot hardware ID collector**. `collector.ps1` wraps Microsoft's `Get-WindowsAutoPilotInfo.ps1` to gather a device's serial, make/model, Windows Product ID, and Autopilot hardware hash, then writes three CSVs to a directory.

### Stage-UserProfile
`Stage-UserProfile.ps1` pre-creates ("stages") the Windows profile for an **existing local account** so that `C:\Users\<UserName>` and its `NTUSER.DAT` hive exist without that user ever logging on interactively — useful during OS deployment/provisioning when an app or service needs the profile ahead of time. It resolves the account to its SID, short-circuits if a profile already exists, and otherwise calls the Win32 `CreateProfile` API in `userenv.dll` via P/Invoke. Requires elevation; pass the account name with `-UserName`.

### TattooRegistry
`Write-VariableToRegistry.ps1` connects to the `Microsoft.SMS.TSEnvironment` COM object during a running **SCCM Task Sequence** and writes Task Sequence variables to the registry (default `HKLM:\SOFTWARE\CCMEXEC`) as string values. Use `-IncludeVariables` for an explicit whitelist, `-ExcludeVariables` for a wildcard-capable blacklist (e.g. `'*Password*'`), or neither to write everything. `-RegistryPath` sets the destination key.

## License
This repository is licensed under the CC0 1.0 Universal license, with the exception of `Collect-HardwareId/Get-WindowsAutoPilotInfo.ps1`, which is © Microsoft and licensed under MIT (see the header in that file).
