# Intune Hardware ID Collector

Collects the **Windows Autopilot hardware ID** from a device and builds a CSV you can
bulk-import into Microsoft Intune (Devices → Enroll devices → Windows Autopilot devices).

## Files

| File | Purpose |
| --- | --- |
| `collector.ps1` | The wrapper you run. Gathers device details + hardware hash and writes the report CSVs. |
| `Get-WindowsAutoPilotInfo.ps1` | Microsoft's official script (MIT licensed) that produces the hardware hash. Must sit next to `collector.ps1`. |
| `runHwIdCollector.bat` | Convenience launcher — finds the tool folder and runs the collector elevated. |

## Usage

Run from an **elevated** PowerShell prompt (the script enforces admin):

```powershell
.\collector.ps1
.\collector.ps1 -GroupTag "Kiosk" -AssignedUser "jane@contoso.com"
.\collector.ps1 -Force              # re-collect a device already recorded
.\collector.ps1 -OutputPath D:\reports
```

### Output (in `reports\` next to the script by default)

- `<serial>.csv` — full detail for the single device just collected.
- `master.csv` — running audit log of every device (timestamp, computer name, make/model, hash).
- `masterforupload.csv` — the exact 5-column format Intune expects. **This is the file you import.**

Re-running on the same device is a no-op unless you pass `-Force`, which replaces that
device's rows in place — so `masterforupload.csv` never accumulates the duplicate rows
that would make the Intune import fail.

## Launcher

Included is a `.bat` that serves as a launcher for the script should you choose to put this script 
on a USB. It is configured for the way *I* use it, and can easily be updated to match your
configuration. 

### What it does

Because a USB stick doesn't always get the same drive letter, the launcher searches every
drive from `D:` to `Z:` for `collector.ps1` inside a folder you specify, `cd`s into the first
match, and runs the collector with `-ExecutionPolicy Bypass` so it works on a machine whose
policy would otherwise block scripts. Out of the box it looks for
`PowerShell\kc118-intuneHwIdCollector\` (e.g.
`D:\PowerShell\kc118-intuneHwIdCollector\collector.ps1`). If no drive has it, it says so and
exits.

To keep the scripts in the **drive root** instead of a subfolder, leave `scriptFolder` blank
(`set scriptFolder=`) or set it to a single backslash (`set scriptFolder=\`). The launcher
then looks for `collector.ps1` directly in each drive root (e.g. `D:\collector.ps1`).

### Configuring it for your own USB

Everything you'd change lives in the `CONFIG` block at the top of `runHwIdCollector.bat`:

```bat
REM  Path to the tool folder, relative to a drive root.
REM  Leave blank (or set to \) to use the drive root itself.
set scriptFolder=PowerShell\kc118-intuneHwIdCollector

REM  Extra arguments passed to collector.ps1 on every run (optional).
set collectorArgs=
```

`runHwIdCollector.bat` is meant to sit at the **root of the USB**, with the two PowerShell
scripts in the folder it searches for:

```
D:\runHwIdCollector.bat
D:\PowerShell\kc118-intuneHwIdCollector\collector.ps1
D:\PowerShell\kc118-intuneHwIdCollector\Get-WindowsAutoPilotInfo.ps1
```

To adapt it to your own layout:

1. Copy `runHwIdCollector.bat` to the root of the USB, and put `collector.ps1` and
   `Get-WindowsAutoPilotInfo.ps1` together in a folder somewhere on the same drive.
2. Set `scriptFolder` to that folder's path **relative to the drive root** — do not include
   the drive letter. For example, if the scripts live in `X:\Autopilot\`, use
   `set scriptFolder=Autopilot`.
3. (Optional) Put arguments you always want in `collectorArgs`, e.g.
   `set collectorArgs=-GroupTag "Kiosk"`.

### Running it

The collector requires elevation, so run the launcher as an administrator. Either way works:

- **File Explorer:** right-click `runHwIdCollector.bat` → **Run as administrator**.
- **Win+R:** press `Win`+`R`, type the full path to the `.bat` at the USB root (e.g.
  `D:\runHwIdCollector.bat`), then press `Ctrl`+`Shift`+`Enter`.
  
Anything after the `.bat` on the command line is forwarded to `collector.ps1`, so both of
these work:

```bat
runHwIdCollector.bat
runHwIdCollector.bat -GroupTag "Sales" -AssignedUser "jane@contoso.com"
```

Arguments from `collectorArgs` and from the command line are both passed through.
