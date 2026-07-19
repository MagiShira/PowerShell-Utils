#Requires -Version 5.1
<#
.SYNOPSIS
    Collects the Windows Autopilot hardware ID for the local device and records it
    to CSV files for bulk import into Microsoft Intune.

.DESCRIPTION
    Wrapper around Microsoft's Get-WindowsAutoPilotInfo.ps1 (expected to sit next to
    this script). For the machine it runs on it gathers the serial number, make/model,
    Windows Product ID and the Autopilot hardware hash, then writes:

        reports\<serial>.csv    - full detail for this single device
        reports\master.csv      - running audit log of every device collected
        reports\masterforupload.csv - the exact 5-column format Intune expects

    Re-running on an already-collected device is a no-op unless -Force is supplied,
    in which case the existing rows for that serial are replaced. This keeps
    masterforupload.csv free of the duplicate rows that break the Intune import.

.PARAMETER OutputPath
    Directory to write the report files into. Defaults to a 'reports' folder next to
    this script. If that location is not writable (e.g. a read-only share) it falls
    back to the user's Desktop.

.PARAMETER GroupTag
    Optional Autopilot group tag to record in the upload CSV.

.PARAMETER AssignedUser
    Optional UPN of the user to assign to the device in the upload CSV.

.PARAMETER Force
    Re-collect and overwrite an existing record for this device's serial number.

.EXAMPLE
    .\collector.ps1

.EXAMPLE
    .\collector.ps1 -GroupTag "Kiosk" -AssignedUser "jane@contoso.com"
#>
[CmdletBinding()]
param(
    [string] $OutputPath = '',
    [string] $GroupTag = '',
    [string] $AssignedUser = '',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

# --- Resolve where this script lives ---------------------------------------
# $PSScriptRoot is unreliable in some hosts (e.g. an SCCM/MDT task-sequence
# PowerShell, or when the param defaults are bound), so fall back through a
# couple of other ways to find the script's own folder before giving up.
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $scriptRoot 'reports'
}

# --- Helpers ---------------------------------------------------------------

function Get-SafeFileName {
    # Strip characters that are illegal in Windows file names.
    param([string] $Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $pattern = '[{0}]' -f [regex]::Escape($invalid)
    ($Name -replace $pattern, '_').Trim()
}

function Write-IntuneCsv {
    # Write the Intune upload file as UTF-8 *without* a BOM and without stray quoting,
    # which is the format the Autopilot importer is happiest with. Fields are only
    # quoted when they contain a comma.
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable] $Rows,
        [Parameter(Mandatory)] [string[]] $Columns,
        [Parameter(Mandatory)] [string] $Path
    )
    $format = {
        param($values)
        ($values | ForEach-Object {
            if ($_ -match ',') { '"{0}"' -f ($_ -replace '"', '""') } else { "$_" }
        }) -join ','
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((& $format $Columns))
    foreach ($row in $Rows) {
        $lines.Add((& $format ($Columns | ForEach-Object { $row.$_ })))
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

# --- Preconditions ---------------------------------------------------------

$identity = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an administrator. Right-click and 'Run as administrator', or launch from an elevated prompt."
    exit 1
}

$autoPilotScript = Join-Path $scriptRoot 'Get-WindowsAutoPilotInfo.ps1'
if (-not (Test-Path $autoPilotScript)) {
    Write-Error "Get-WindowsAutoPilotInfo.ps1 not found next to this script ($scriptRoot)."
    exit 1
}

if ($AssignedUser -and $AssignedUser -notmatch '@') {
    Write-Warning "AssignedUser '$AssignedUser' does not look like a UPN (no '@'). Recording it anyway."
}

# --- Gather device details -------------------------------------------------

$bios     = Get-CimInstance -ClassName Win32_BIOS
$computer = Get-CimInstance -ClassName Win32_ComputerSystem

$serial       = "$($bios.SerialNumber)".Trim()
$manufacturer = "$($computer.Manufacturer)".Trim()
$model        = "$($computer.Model)".Trim()

try {
    $productId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ProductId').ProductId
} catch {
    $productId = ''
    Write-Warning "Could not read Windows Product ID (this is optional for Autopilot registration)."
}

# Flag serials that manufacturers leave as placeholders - these will not register correctly.
$bogusSerials = @('', 'To be filled by O.E.M.', 'Default string', 'System Serial Number',
                  'None', 'Not Applicable', 'Not Specified', '0', 'Unknown')
if ($bogusSerials -contains $serial) {
    Write-Warning "Serial number '$serial' looks like a placeholder/BIOS default. The device may not register in Autopilot correctly."
}

Write-Host "Collecting Autopilot hardware hash for $manufacturer $model (serial: $serial)..."

# Delegate the actual hash retrieval to Microsoft's script.
$hwHash = & $autoPilotScript | Select-Object -ExpandProperty 'Hardware Hash' -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($hwHash)) {
    Write-Error "Failed to retrieve a hardware hash. This usually means the device's TPM/MDM data is unavailable (common on VMs). Nothing was written."
    exit 1
}

# --- Prepare output directory ----------------------------------------------

function Test-WritableDirectory {
    # Create the directory if missing and confirm we can actually write into it.
    # Returns $true on success; on any failure (e.g. a read-only USB) returns $false
    # so the caller can fall back to a writable location.
    param([string] $Path)
    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $Path (".write_test_{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-WritableDirectory $OutputPath)) {
    $fallback = Join-Path ([Environment]::GetFolderPath('Desktop')) 'IntuneHwIdReports'
    Write-Warning "'$OutputPath' is missing or not writable (e.g. a read-only drive). Falling back to '$fallback'."
    if (-not (Test-WritableDirectory $fallback)) {
        Write-Error "Could not create a writable reports folder at '$OutputPath' or '$fallback'. Nothing was written."
        exit 1
    }
    $OutputPath = $fallback
}

$masterCsvPath       = Join-Path $OutputPath 'master.csv'
$masterUploadCsvPath = Join-Path $OutputPath 'masterforupload.csv'
$deviceFileName      = Get-SafeFileName $serial
if ([string]::IsNullOrWhiteSpace($deviceFileName)) { $deviceFileName = $env:COMPUTERNAME }
$deviceCsvPath       = Join-Path $OutputPath "$deviceFileName.csv"

# --- Duplicate check -------------------------------------------------------

$existingMaster = @()
if (Test-Path $masterCsvPath) { $existingMaster = @(Import-Csv -Path $masterCsvPath) }
$alreadyCollected = $existingMaster | Where-Object { $_.SerialNumber -eq $serial }

if ($alreadyCollected -and -not $Force) {
    Write-Warning "Serial '$serial' was already collected on $($alreadyCollected[0].CollectedOn). Use -Force to re-collect. No changes made."
    exit 0
}

# --- Build records ---------------------------------------------------------

$collectedOn = (Get-Date).ToString('s')

$detailRecord = [PSCustomObject]@{
    CollectedOn     = $collectedOn
    ComputerName    = $env:COMPUTERNAME
    SerialNumber    = $serial
    Manufacturer    = $manufacturer
    Model           = $model
    WindowsProductID = $productId
    HardwareHash    = $hwHash
}

$uploadRecord = [PSCustomObject]@{
    'Device Serial Number' = $serial
    'Windows Product ID'   = $productId
    'Hardware Hash'        = $hwHash
    'Group Tag'            = $GroupTag
    'Assigned User'        = $AssignedUser
}

# --- Write per-device file (always overwrites) -----------------------------

$detailRecord | Export-Csv -Path $deviceCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote device report: $deviceCsvPath"

# --- Upsert into master.csv ------------------------------------------------

$masterRecords = @($existingMaster | Where-Object { $_.SerialNumber -ne $serial })
$masterRecords += $detailRecord
$masterRecords | Export-Csv -Path $masterCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Updated master log: $masterCsvPath ($($masterRecords.Count) device(s) total)"

# --- Upsert into the Intune upload file ------------------------------------

$uploadColumns = @('Device Serial Number', 'Windows Product ID', 'Hardware Hash', 'Group Tag', 'Assigned User')
$uploadRecords = @()
if (Test-Path $masterUploadCsvPath) {
    $uploadRecords = @(Import-Csv -Path $masterUploadCsvPath |
        Where-Object { $_.'Device Serial Number' -ne $serial })
}
$uploadRecords += $uploadRecord
Write-IntuneCsv -Rows $uploadRecords -Columns $uploadColumns -Path $masterUploadCsvPath
Write-Host "Updated Intune upload file: $masterUploadCsvPath ($($uploadRecords.Count) device(s) ready to import)"

Write-Host ""
Write-Host "Done. Import '$masterUploadCsvPath' into Intune > Devices > Enroll devices > Windows Autopilot devices." -ForegroundColor Green
