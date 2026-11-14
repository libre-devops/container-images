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
# The PowerShell Gallery answers 503 now and then: retry with backoff.
foreach ($name in $modules.Keys) {
    $version = $modules[$name]
    Write-Host "Installing $name $version"
    for ($attempt = 1; ; $attempt++) {
        try {
            Install-PSResource -Name $name -Version "[$version]" -Repository PSGallery `
                -TrustRepository -Scope AllUsers -AcceptLicense -Quiet
            break
        } catch {
            if ($attempt -ge 4) { throw }
            $delay = 20 * $attempt
            Write-Warning "Installing $name failed (attempt $attempt): $($_.Exception.Message); retrying in ${delay}s"
            Start-Sleep -Seconds $delay
        }
    }
}
'
