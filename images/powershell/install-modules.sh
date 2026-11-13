#!/bin/sh
# Installs the pinned PowerShell modules for all users, at exact versions.
# Reads PSSCRIPTANALYZER_VERSION, PESTER_VERSION, AZ_POWERSHELL_VERSION,
# MICROSOFT_GRAPH_VERSION and LIBREDEVOPSHELPERS_VERSION from the environment.
# Az and Microsoft.Graph are meta-modules: each pins its submodules exactly.

set -eu

: "${PSSCRIPTANALYZER_VERSION:?}" "${PESTER_VERSION:?}" "${AZ_POWERSHELL_VERSION:?}" "${MICROSOFT_GRAPH_VERSION:?}" "${LIBREDEVOPSHELPERS_VERSION:?}"

# shellcheck disable=SC2016 # PowerShell code, expanded by pwsh, not sh
pwsh -NoLogo -NoProfile -NonInteractive -Command '
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$modules = [ordered]@{
    PSScriptAnalyzer   = $env:PSSCRIPTANALYZER_VERSION
    Pester             = $env:PESTER_VERSION
    Az                 = $env:AZ_POWERSHELL_VERSION
    "Microsoft.Graph"  = $env:MICROSOFT_GRAPH_VERSION
    LibreDevOpsHelpers = $env:LIBREDEVOPSHELPERS_VERSION
}
foreach ($name in $modules.Keys) {
    $version = $modules[$name]
    Write-Host "Installing $name $version"
    Install-PSResource -Name $name -Version "[$version]" -Repository PSGallery `
        -TrustRepository -Scope AllUsers -AcceptLicense -Quiet
}
'
