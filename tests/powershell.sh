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
Invoke-ScriptAnalyzer -ScriptDefinition "Write-Output 1" | Out-Null
Write-Host "ok: PSScriptAnalyzer runs"
'
