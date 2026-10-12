#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Entfernt WePrintEasy von einem Terminalserver.

    Laufende Agenten in Benutzersitzungen werden beendet.

.PARAMETER RemoveConfig
    Loescht zusaetzlich die Konfigurationsdatei (nur bei lokaler Konfiguration).

.PARAMETER RemoveClientDefaultPrinterPolicy
    Entfernt die bei der Installation mit -DisableClientDefaultPrinter gesetzte Richtlinie.

    Ein bei der Installation erstelltes selbstsigniertes Codesignatur-Zertifikat
    (-SelfSignedCertificate) wird immer entfernt; fremde Zertifikate (z. B. aus
    der Firmen-CA) bleiben unangetastet.

.PARAMETER KeepInstallFolder
    Nur fuer die Deinstallation des Windows-Installers (WePrintEasy-Setup.exe):
    den Programmordner nicht loeschen, das erledigt dessen Deinstallation selbst.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveConfig,
    [switch]$RemoveClientDefaultPrinterPolicy,
    [switch]$KeepInstallFolder
)

$ErrorActionPreference = 'Stop'
$regKey = 'HKLM:\SOFTWARE\WePrintEasy'
# Eintrag des Windows-Installers unter "Programme und Features" (AppId in installer\WePrintEasy.iss)
$uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{62BED98D-291F-401A-A240-5C8EC56F56F3}_is1'
$reg = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
$installPath = if ($reg -and $reg.PSObject.Properties['InstallPath']) { $reg.InstallPath } else { Join-Path $env:ProgramFiles 'WePrintEasy' }
$configPath = if ($reg -and $reg.PSObject.Properties['ConfigPath']) { $reg.ConfigPath } else { Join-Path $env:ProgramData 'WePrintEasy\config.json' }

# Texte und Verknuepfungsnamen aus dem Modul (Quellordner, sonst Installation - vor dem Loeschen laden)
$module = Join-Path $PSScriptRoot 'src\WePrintEasy.psm1'
if (-not (Test-Path -LiteralPath $module)) { $module = Join-Path $installPath 'WePrintEasy.psm1' }
Import-Module $module -Force
Initialize-WpeLanguage -ConfigPath $configPath
$remove = Get-WpeText 'Uninstall.Remove'

# Anmelde-Aufgabe und evtl. uebrig gebliebene "Erzwingen"-Aufgaben
foreach ($task in @(Get-ScheduledTask -TaskPath '\WePrintEasy\' -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess((Get-WpeText 'Uninstall.Task' $task.TaskName), $remove)) { $task | Unregister-ScheduledTask -Confirm:$false }
}

# Laufende Agenten beenden - sonst setzen sie den Drucker bis zur Abmeldung weiter zurueck
$agents = @()
try { $agents = @(Get-WpeAgentProcess) } catch { Write-Warning (Get-WpeText 'Install.AgentsUnknown' $_.Exception.Message) }
foreach ($a in $agents) {
    if ($PSCmdlet.ShouldProcess((Get-WpeText 'Agent.ProcessLabel' $a.User $a.SessionId), (Get-WpeText 'Uninstall.Stop'))) {
        Stop-Process -Id $a.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# Eintrag dieses Servers in der Versionsuebersicht (bei zentraler Konfiguration fuer die anderen Server)
try { Unregister-WpeHost -ConfigPath $configPath -Confirm:$false } catch { Write-Warning (Get-WpeText 'Uninstall.HostKept' $_.Exception.Message) }

foreach ($lnk in Get-WpeShortcutPath -All) {
    if ((Test-Path -LiteralPath $lnk) -and $PSCmdlet.ShouldProcess($lnk, $remove)) { Remove-Item -LiteralPath $lnk -Force }
}

if (-not $KeepInstallFolder) {
    if ((Test-Path -LiteralPath $installPath) -and $PSCmdlet.ShouldProcess($installPath, $remove)) {
        Remove-Item -LiteralPath $installPath -Recurse -Force
    }
    # Mit dem Programmordner ist auch die Deinstallation des Windows-Installers weg
    if ((Test-Path -LiteralPath $uninstallKey) -and $PSCmdlet.ShouldProcess($uninstallKey, $remove)) { Remove-Item -LiteralPath $uninstallKey -Recurse -Force }
}

if ($RemoveConfig) {
    if ($configPath.StartsWith('\\')) {
        Write-Warning (Get-WpeText 'Uninstall.CentralKept' $configPath)
    } else {
        $dir = Split-Path -Parent $configPath
        if ((Test-Path -LiteralPath $dir) -and $PSCmdlet.ShouldProcess($dir, $remove)) {
            # Rechte zuruecksetzen, falls Dateien nicht lesbar sind (z. B. nach aelteren Installationen)
            & icacls.exe (Join-Path $dir '*') /reset /C /Q 2>&1 | Out-Null
            Remove-Item -LiteralPath $dir -Recurse -Force
        }
    }
}

if ($RemoveClientDefaultPrinterPolicy -and $PSCmdlet.ShouldProcess('fForceClientLptDef', $remove)) {
    Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fForceClientLptDef -ErrorAction SilentlyContinue
}

$thumb = if ($reg -and $reg.PSObject.Properties['SigningThumbprint']) { [string]$reg.SigningThumbprint } else { '' }
if ($thumb -and $reg.PSObject.Properties['SigningCertCreated'] -and $reg.SigningCertCreated -eq 1 -and
    $PSCmdlet.ShouldProcess((Get-WpeText 'Uninstall.Certificate' $thumb), $remove)) {
    foreach ($s in 'My', 'Root', 'TrustedPublisher') {
        $p = "Cert:\LocalMachine\$s\$thumb"
        if (-not (Test-Path -LiteralPath $p)) { continue }
        if ($s -eq 'My') { Remove-Item -LiteralPath $p -DeleteKey } else { Remove-Item -LiteralPath $p }
    }
}

if ((Test-Path -LiteralPath $regKey) -and $PSCmdlet.ShouldProcess($regKey, $remove)) { Remove-Item -LiteralPath $regKey -Recurse -Force }

Write-Host (Get-WpeText 'Uninstall.Done') -ForegroundColor Green
