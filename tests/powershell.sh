# Smoke tests for the powershell image.
# shellcheck shell=bash disable=SC2016 # PowerShell code, expanded by pwsh, not bash
set -euo pipefail

pwsh -NoProfile -Command '$PSVersionTable'

pwsh -NoLogo -NoProfile -NonInteractive -Command '
$ErrorActionPreference = "Stop"
function Assert-Version([string] $What, [string] $Got, [string] $Want) {
    if ($Got -ne $Want) { throw "$What is $Got, want $Want" }
    Write-Host "ok: $What $Want"
}
Assert-Version "PowerShell" $PSVersionTable.PSVersion.ToString() $env:EXPECT_POWERSHELL
$modules = [ordered]@{
    PSScriptAnalyzer   = $env:EXPECT_PSSCRIPTANALYZER
    Pester             = $env:EXPECT_PESTER
    LibreDevOpsHelpers = $env:EXPECT_LIBREDEVOPSHELPERS
    Az                 = $env:EXPECT_AZ_POWERSHELL
}
foreach ($name in $modules.Keys) {
    Import-Module $name -RequiredVersion $modules[$name]
    $loaded = Get-Module $name
    Assert-Version "$name imports at" $loaded.Version.ToString() $modules[$name]
}
Import-Module Az.Accounts
# Microsoft.Graph is a meta-module of about forty: check it is installed at the
# pinned version, and that its authentication module loads in the same session
# as Az.Accounts, since both carry their own copies of the identity libraries.
$graph = Get-InstalledPSResource -Name Microsoft.Graph -Scope AllUsers
Assert-Version "Microsoft.Graph is installed at" $graph.Version.ToString() $env:EXPECT_MICROSOFT_GRAPH
foreach ($name in "Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "Microsoft.Graph.Groups") {
    Import-Module $name -RequiredVersion $env:EXPECT_MICROSOFT_GRAPH
}
Get-MgContext | Out-Null
Get-AzContext | Out-Null
Write-Host "ok: Microsoft.Graph and Az load together"
Invoke-ScriptAnalyzer -ScriptDefinition "Write-Output 1" | Out-Null
Write-Host "ok: PSScriptAnalyzer runs"
'
