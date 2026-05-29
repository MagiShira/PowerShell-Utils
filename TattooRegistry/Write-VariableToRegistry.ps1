<#
.SYNOPSIS
    Writes SCCM Task Sequence environment variables to the registry.

.DESCRIPTION
    Connects to the Microsoft.SMS.TSEnvironment COM object and enumerates all
    available Task Sequence variables, writing each one as a string value to the
    specified registry key. Must be run within a running SCCM Task Sequence.

    Use -IncludeVariables for a whitelist (only those names are written).
    Use -ExcludeVariables for a blacklist with wildcard support.
    If neither is provided, all variables are written.

.PARAMETER RegistryPath
    The registry path where variables will be written.
    Defaults to 'HKLM:\SOFTWARE\CCMEXEC'.

.PARAMETER IncludeVariables
    An explicit list of TS variable names to write. When provided, only these
    variables are written and -ExcludeVariables is ignored.

.PARAMETER ExcludeVariables
    A list of TS variable name patterns to skip. Supports wildcards (e.g. '*Password*').
    Ignored when -IncludeVariables is specified.

.EXAMPLE
    .\Write-VariableToRegistry.ps1
    Writes all TS variables to the default registry path.

.EXAMPLE
    .\Write-VariableToRegistry.ps1 -RegistryPath 'HKLM:\SOFTWARE\MyOrg\OSD'
    Writes all TS variables to a custom registry path.

.EXAMPLE
    .\Write-VariableToRegistry.ps1 -IncludeVariables '_SMSTSAdvertID','_SMSTSPackageName','TSVersion'
    Writes only the specified variables

.EXAMPLE
    .\Write-VariableToRegistry.ps1 -ExcludeVariables '*Password*','*Secret*'
    Writes all variables except those matching the given patterns.

.NOTES
    Author: Elane Faisal-Sage, Student Worker 3, University of Nevada, Reno
#>

[CmdletBinding()]
param(
    [string]$RegistryPath = 'HKLM:\SOFTWARE\CCMEXEC',
    [string[]]$IncludeVariables,
    [string[]]$ExcludeVariables
)

try {
    $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
} catch {
    Write-Error "Failed to connect to TSEnvironment COM object. Ensure this runs inside a Task Sequence: $_"
    exit 1
}

if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

$variableNames = $tsenv.GetVariables()

if ($IncludeVariables) {
    $variableNames = $variableNames | Where-Object { $_ -in $IncludeVariables }
} elseif ($ExcludeVariables) {
    $variableNames = $variableNames | Where-Object {
        $name = $_
        -not ($ExcludeVariables | Where-Object { $name -like $_ })
    }
}

foreach ($name in $variableNames) {
    $value = $tsenv.Value($name)
    Set-ItemProperty -Path $RegistryPath -Name $name -Value $value -Type String
    Write-Verbose "Wrote: $name = $value"
}

Write-Output "Wrote $($variableNames.Count) variable(s) to $RegistryPath"
