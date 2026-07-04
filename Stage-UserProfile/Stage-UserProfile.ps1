<#
.SYNOPSIS
    Pre-creates (stages) the Windows user profile for a local account.

.DESCRIPTION
    Forces creation of a user's profile directory and registry hive without
    requiring that user to interactively log on. This is useful during OS
    deployment or provisioning when an application or service needs the profile
    folder (e.g. C:\Users\<UserName>) and NTUSER.DAT to exist ahead of time.

    The script resolves the local account to its SID, checks whether a profile
    already exists (and short-circuits if so), and otherwise calls the Win32
    CreateProfile API in userenv.dll via P/Invoke to build the profile.

    Must be run elevated (administrator) and the target account must already
    exist as a local user on this machine.

.PARAMETER UserName
    The name of the local user account whose profile should be staged.
    Resolved against the local computer ($env:COMPUTERNAME), not a domain.

.EXAMPLE
    .\Stage-UserProfile.ps1 -UserName 'svc_backup'
    Pre-creates the profile for the local account 'svc_backup'.

.NOTES
    Author: Elane Faisal-Sage, Student Worker 3, University of Nevada, Reno
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
)

$ErrorActionPreference = "Stop"

Write-Host "Pre-creating profile for local user: $UserName"

# Resolve local account SID
$account = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $UserName)
$sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value

Write-Host "Resolved SID: $sid"

# Check if profile already exists
$existingProfile = Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue

if ($existingProfile -and $existingProfile.LocalPath -and (Test-Path $existingProfile.LocalPath)) {
    Write-Host "Profile already exists at: $($existingProfile.LocalPath)"
    exit 0
}

# Import CreateProfile from userenv.dll
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class UserProfileApi
{
    [DllImport("userenv.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CreateProfile(
        string pszUserSid,
        string pszUserName,
        StringBuilder pszProfilePath,
        uint cchProfilePath
    );
}
"@

$profilePath = New-Object System.Text.StringBuilder 260

$result = [UserProfileApi]::CreateProfile(
    $sid,
    $UserName,
    $profilePath,
    [uint32]$profilePath.Capacity
)

if ($result -ne 0) {
    throw "CreateProfile failed for $UserName. HRESULT: $result"
}

Write-Host "Profile created successfully at: $($profilePath.ToString())"
exit 0
