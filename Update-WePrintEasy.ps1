#Requires -Version 5.1
<#
.SYNOPSIS
    Aktualisiert eine vorhandene WePrintEasy-Installation. Start über Update.cmd.

.DESCRIPTION
    Spielt die Programmdateien aus diesem Ordner neu ein und übernimmt dabei alle
    bisherigen Einstellungen:
      - Konfigurationspfad, Zuweisungen und Druckerliste
      - Sprache, Signierung (gleiches Zertifikat, selbstsigniert wird bei Bedarf erneuert)
      - Editor-Gruppe, RDS-Richtlinie, Verknüpfung unter Windows-Tools
    Anschließend wird die Systemprüfung angezeigt.

    Laufende Agenten in Benutzersitzungen arbeiten bis zur nächsten Anmeldung
    mit der alten Version weiter.

.PARAMETER NoPause
    Am Ende nicht auf eine Taste warten (für automatisierte Updates).
#>
[CmdletBinding()]
param([switch]$NoPause)

$ErrorActionPreference = 'Stop'
$regKey = 'HKLM:\SOFTWARE\WePrintEasy'
# Texte in der Sprache der vorhandenen Installation
Import-Module (Join-Path $PSScriptRoot 'src\WePrintEasy.psm1') -Force
Initialize-WpeLanguage

function Wait-Exit([int]$Code) {
    if (-not $NoPause) { Write-Host ''; [void](Read-Host (Get-WpeText 'Update.PressEnter')) }
    exit $Code
}

# --- Administratorrechte -------------------------------------------------------------
$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($NoPause) { $argList += '-NoPause' }
    try {
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Host (Get-WpeText 'Update.NeedsAdmin') -ForegroundColor Red
        Wait-Exit 1
    }
    exit 0
}

$Host.UI.RawUI.WindowTitle = 'WePrintEasy Update'
Write-Host 'WePrintEasy Update' -ForegroundColor Cyan
Write-Host '==================' -ForegroundColor Cyan
Write-Host ''

# --- Vorhandene Installation -------------------------------------------------------
$reg = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
if (-not $reg -or -not $reg.PSObject.Properties['InstallPath'] -or -not (Test-Path -LiteralPath (Join-Path $reg.InstallPath 'WePrintEasy-Agent.ps1'))) {
    Write-Host (Get-WpeText 'Update.NotInstalled') -ForegroundColor Yellow
    Write-Host (Get-WpeText 'Update.UseSetup')
    Wait-Exit 1
}
$installPath = [string]$reg.InstallPath
$signed = $reg.PSObject.Properties['ExecutionPolicy'] -and $reg.ExecutionPolicy -eq 'AllSigned'
Write-Host (Get-WpeText 'Update.InfoInstall' $installPath)
Write-Host (Get-WpeText 'Update.InfoConfig' $reg.ConfigPath)
Write-Host (Get-WpeText 'Update.InfoSigning' $(if ($signed) { Get-WpeText 'Update.SignedKept' } else { Get-WpeText 'Common.No' }))
Write-Host (Get-WpeText 'Update.InfoLanguage' (Get-WpeSupportedLanguage)[(Get-WpeLanguage)])
Write-Host (Get-WpeText 'Update.InfoSource' $PSScriptRoot)
Write-Host ''

$admins = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*WePrintEasy-Admin.ps1*' })
if ($admins) {
    Write-Host (Get-WpeText 'Update.AdminOpen' $admins.Count) -ForegroundColor Yellow
}
$agents = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*WePrintEasy-Agent.ps1*' })

# --- Update ---------------------------------------------------------------------------
$params = @{ InstallPath = $installPath; Language = (Get-WpeLanguage) }
# Verknüpfung nur erneuern, wenn sie bisher vorhanden war (in irgendeiner Sprache)
if (-not @(Get-WpeShortcutPath -All | Where-Object { Test-Path -LiteralPath $_ }).Count) { $params.NoShortcut = $true }

try {
    & (Join-Path $PSScriptRoot 'Install-WePrintEasy.ps1') @params
} catch {
    Write-Host ''
    Write-Host (Get-WpeText 'Setup.Error' $_.Exception.Message) -ForegroundColor Red
    Write-Host (Get-WpeText 'Update.Failed') -ForegroundColor Red
    Wait-Exit 1
}

# --- Systemprüfung -------------------------------------------------------------------
Write-Host ''
Write-Host (Get-WpeText 'Update.SystemCheck') -ForegroundColor Cyan
Import-Module (Join-Path $installPath 'WePrintEasy.psm1') -Force
Initialize-WpeLanguage
$failed = 0
foreach ($c in Get-WpeSystemStatus) {
    $color = switch ($c.Status) { 'OK' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Gray' } }
    if ($c.Status -eq 'Error') { $failed++ }
    Write-Host ('  {0,-8} {1,-24} {2}' -f (Get-WpeText "Status.$($c.Status)"), $c.Check, $c.Detail) -ForegroundColor $color
}
Write-Host ''
if ($agents) {
    Write-Host (Get-WpeText 'Update.AgentsRunning' $agents.Count) -ForegroundColor Yellow
}
if ($failed) {
    Write-Host (Get-WpeText 'Update.DoneErrors' $failed) -ForegroundColor Red
    Wait-Exit 1
}
Write-Host (Get-WpeText 'Update.Done') -ForegroundColor Green
Wait-Exit 0
