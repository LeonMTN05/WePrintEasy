#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Richtet eine Entwicklungs-/Testumgebung fuer WePrintEasy auf einem einzelnen
    Testserver ein, der zugleich Domaenencontroller, Druckserver und Terminalserver ist.
    NUR AUF EINEM TESTSERVER AUSFUEHREN.

.DESCRIPTION
    - OU "WePrintEasy-Test" mit Testbenutzern und -gruppen:
        wpetest1  Anna Buchhaltung  (GG_WPE_Buchhaltung)          -> Gruppe, Prioritaet 10
        wpetest2  Lars Lager        (GG_WPE_Lager)                -> Gruppe, Prioritaet 20
        wpetest3  Dora Direkt       (GG_WPE_Buchhaltung)          -> direkte Zuweisung schlaegt Gruppe
        GG_WPE_Alle enthaelt die beiden Abteilungsgruppen (verschachtelt) -> Prioritaet 100
      GG_WPE_Alle ist Mitglied von "Remotedesktopbenutzer".
    - GPO "WePrintEasy Test - RDP-Anmeldung am DC" (verknuepft mit der OU Domain Controllers):
      Recht "Anmelden ueber Remotedesktopdienste" fuer Administratoren + Remotedesktopbenutzer.
      Ohne diese Richtlinie duerfen sich an einem DC nur Administratoren per RDP anmelden.
    - Drei freigegebene Testdrucker; Druckauftraege landen als Datei in C:\WPE-Druckausgabe.
    - Installiert WePrintEasy aus diesem Repository (Konfiguration lokal), traegt die drei
      Drucker in die Druckerliste ein und legt die Zuweisungen an.

    Eine Druckerverbindung zum eigenen Rechner (\\DIESER-SERVER\Freigabe) ist unter Windows
    nicht moeglich - die Zuweisungen verwenden daher die lokalen Druckernamen.

    Das Kennwort der Testbenutzer wird in tests\testumgebung.local.txt abgelegt
    (per .git\info\exclude von Git ausgenommen).

.PARAMETER SkipInstall
    WePrintEasy nicht installieren und keine Zuweisungen anlegen (z. B. um Setup.cmd selbst zu testen).

.PARAMETER ResetPassword
    Neues Kennwort fuer bereits vorhandene Testbenutzer setzen.

.PARAMETER Remove
    Testumgebung wieder entfernen (Benutzer, Gruppen, OU, GPO, Drucker, Ports, Ausgabeordner).
    WePrintEasy selbst bleibt installiert (dafuer Uninstall-WePrintEasy.ps1).

.EXAMPLE
    .\tests\New-WpeTestEnvironment.ps1
.EXAMPLE
    .\tests\New-WpeTestEnvironment.ps1 -Remove
#>
# Zufaellig erzeugtes Kennwort der Testbenutzer im Testlabor - wird ohnehin im Klartext angezeigt
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$ResetPassword,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy

$root = Split-Path -Parent $PSScriptRoot
$credFile = Join-Path $PSScriptRoot 'testumgebung.local.txt'
$outDir = 'C:\WPE-Druckausgabe'
$gpoName = 'WePrintEasy Test - RDP-Anmeldung am DC'
$domain = Get-ADDomain
$ouPath = "OU=WePrintEasy-Test,$($domain.DistinguishedName)"
$rdpGroupSid = 'S-1-5-32-555'   # VORDEFINIERT\Remotedesktopbenutzer

$printers = @(
    @{ Name = 'WPE Buero'; Share = 'WPE-Buero'; Driver = 'Microsoft PCL6 Class Driver'; Location = 'EG Büro'; Comment = 'Testdrucker Büro (alle)' }
    @{ Name = 'WPE Buchhaltung'; Share = 'WPE-Buchhaltung'; Driver = 'Microsoft PS Class Driver'; Location = '1. OG Buchhaltung'; Comment = 'Testdrucker Buchhaltung' }
    @{ Name = 'WPE Lager'; Share = 'WPE-Lager'; Driver = 'Generic / Text Only'; Location = 'Halle 2'; Comment = 'Testdrucker Lager' }
)
$groups = @(
    @{ Name = 'GG_WPE_Alle'; Description = 'WePrintEasy Test: alle Testbenutzer (enthaelt die Abteilungsgruppen)' }
    @{ Name = 'GG_WPE_Buchhaltung'; Description = 'WePrintEasy Test: Buchhaltung' }
    @{ Name = 'GG_WPE_Lager'; Description = 'WePrintEasy Test: Lager' }
)
$users = @(
    @{ Sam = 'wpetest1'; Given = 'Anna'; Surname = 'Buchhaltung'; Group = 'GG_WPE_Buchhaltung' }
    @{ Sam = 'wpetest2'; Given = 'Lars'; Surname = 'Lager'; Group = 'GG_WPE_Lager' }
    @{ Sam = 'wpetest3'; Given = 'Dora'; Surname = 'Direkt'; Group = 'GG_WPE_Buchhaltung' }
)

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

function New-TestPassword {
    # Erfuellt die Komplexitaetsregeln der Domaene (Gross, klein, Ziffer, Sonderzeichen)
    $sets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!$%#+-'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = { param([string]$s) $b = New-Object byte[] 4; $rng.GetBytes($b); $s[[BitConverter]::ToUInt32($b, 0) % $s.Length] }
    $chars = @(foreach ($s in $sets) { & $pick $s; & $pick $s; & $pick $s; & $pick $s })
    $rng.Dispose()
    -join ($chars | Sort-Object { [guid]::NewGuid() })
}

function Get-GpoSecEditPath($Gpo) {
    "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies\{$($Gpo.Id)}\Machine\Microsoft\Windows NT\SecEdit"
}

# =============================================================================
if ($Remove) {
    Write-Step 'Testumgebung entfernen'
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if ($gpo) { Remove-GPO -Guid $gpo.Id -Confirm:$false; Write-Host "    GPO '$gpoName' entfernt" }
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'") {
        Set-ADOrganizationalUnit -Identity $ouPath -ProtectedFromAccidentalDeletion $false
        Remove-ADOrganizationalUnit -Identity $ouPath -Recursive -Confirm:$false
        Write-Host "    OU $ouPath mit Benutzern und Gruppen entfernt"
    }
    foreach ($p in $printers) {
        if (Get-Printer -Name $p.Name -ErrorAction SilentlyContinue) { Remove-Printer -Name $p.Name; Write-Host "    Drucker '$($p.Name)' entfernt" }
        $port = Join-Path $outDir "$($p.Share).prn"
        if (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue) { Remove-PrinterPort -Name $port }
    }
    if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
    if (Test-Path -LiteralPath $credFile) { Remove-Item -LiteralPath $credFile -Force }
    & gpupdate.exe /target:computer /force | Out-Null
    Write-Host 'Fertig. WePrintEasy selbst bleibt installiert (Uninstall-WePrintEasy.ps1 -RemoveConfig).' -ForegroundColor Green
    return
}

# =============================================================================
Write-Step "OU $ouPath"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'")) {
    New-ADOrganizationalUnit -Name 'WePrintEasy-Test' -Path $domain.DistinguishedName -Description 'Testbenutzer und -gruppen fuer WePrintEasy'
}

Write-Step 'Gruppen'
foreach ($g in $groups) {
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($g.Name)'")) {
        New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope Global -GroupCategory Security -Path $ouPath -Description $g.Description
        Write-Host "    $($g.Name) angelegt"
    }
}
# Verschachtelung: Abteilungsgruppen sind Mitglied von GG_WPE_Alle
Add-ADGroupMember -Identity 'GG_WPE_Alle' -Members 'GG_WPE_Buchhaltung', 'GG_WPE_Lager'
Add-ADGroupMember -Identity (Get-ADGroup -Identity $rdpGroupSid) -Members 'GG_WPE_Alle'

Write-Step 'Benutzer'
$password = $null
$existingCount = @($users | Where-Object { Get-ADUser -Filter "SamAccountName -eq '$($_.Sam)'" }).Count
if ($existingCount -lt $users.Count -or $ResetPassword -or -not (Test-Path -LiteralPath $credFile)) {
    $password = New-TestPassword
}
foreach ($u in $users) {
    $display = "$($u.Given) $($u.Surname)"
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'"
    if (-not $existing) {
        New-ADUser -Name $display -SamAccountName $u.Sam -UserPrincipalName "$($u.Sam)@$($domain.DNSRoot)" `
            -GivenName $u.Given -Surname $u.Surname -DisplayName $display -Path $ouPath `
            -Description 'WePrintEasy Testbenutzer' -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
            -Enabled $true -PasswordNeverExpires $true -ChangePasswordAtLogon $false
        Write-Host "    $($u.Sam) ($display) angelegt"
    } elseif ($password) {
        Set-ADAccountPassword -Identity $u.Sam -Reset -NewPassword (ConvertTo-SecureString $password -AsPlainText -Force)
        Enable-ADAccount -Identity $u.Sam
        Write-Host "    $($u.Sam): Kennwort neu gesetzt"
    }
    Add-ADGroupMember -Identity $u.Group -Members $u.Sam
}
if ($password) {
    $lines = @(
        "WePrintEasy Testumgebung - $($domain.NetBIOSName) ($($domain.DNSRoot)), erstellt $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        "RDP-Ziel: $env:COMPUTERNAME.$($domain.DNSRoot)"
        "Kennwort aller Testbenutzer: $password"
        ''
    ) + @($users | ForEach-Object { "$($domain.NetBIOSName)\$($_.Sam)   $($_.Given) $($_.Surname)   ($($_.Group))" })
    Set-Content -LiteralPath $credFile -Value $lines -Encoding UTF8
    $exclude = Join-Path $root '.git\info\exclude'
    if ((Test-Path -LiteralPath $exclude) -and -not (Select-String -LiteralPath $exclude -SimpleMatch '*.local.txt' -Quiet)) {
        Add-Content -LiteralPath $exclude -Value '*.local.txt'
    }
    Write-Host "    Zugangsdaten: $credFile"
}

# =============================================================================
Write-Step "GPO '$gpoName' (RDP-Anmeldung fuer Remotedesktopbenutzer am DC)"
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) { $gpo = New-GPO -Name $gpoName -Comment 'Nur Testumgebung WePrintEasy: erlaubt Remotedesktopbenutzern die RDP-Anmeldung am DC.' }
$secDir = Get-GpoSecEditPath $gpo
New-Item -ItemType Directory -Path $secDir -Force | Out-Null
$inf = @'
[Unicode]
Unicode=yes
[Version]
signature="$CHICAGO$"
Revision=1
[Privilege Rights]
SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555
'@
$infPath = Join-Path $secDir 'GptTmpl.inf'
$current = if (Test-Path -LiteralPath $infPath) { [IO.File]::ReadAllText($infPath) } else { '' }
if ($current.Trim() -ne $inf.Trim()) {
    [IO.File]::WriteAllText($infPath, $inf, [Text.Encoding]::Unicode)
    # Sicherheitseinstellungen-CSE eintragen und Computer-Version erhoehen, damit die Clients neu anwenden
    $gpoDn = "CN={$($gpo.Id)},CN=Policies,CN=System,$($domain.DistinguishedName)"
    $ad = Get-ADObject -Identity $gpoDn -Properties versionNumber
    $version = [int]$ad.versionNumber + 1
    Set-ADObject -Identity $gpoDn -Replace @{
        gPCMachineExtensionNames = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-0020AF0BCCF7}]'
        versionNumber            = $version
    }
    $gptIni = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies\{$($gpo.Id)}\GPT.INI"
    Set-Content -LiteralPath $gptIni -Value "[General]`r`nVersion=$version" -Encoding ASCII
}
$dcOu = $domain.DomainControllersContainer
if (-not ((Get-GPInheritance -Target $dcOu).GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id })) {
    New-GPLink -Guid $gpo.Id -Target $dcOu -LinkEnabled Yes -Order 1 | Out-Null
}
& gpupdate.exe /target:computer /force | Out-Null
$sec = Join-Path $env:TEMP "wpe-sec-$([guid]::NewGuid().ToString('N')).inf"
& secedit.exe /export /cfg $sec /areas USER_RIGHTS | Out-Null
$right = (Select-String -LiteralPath $sec -Pattern '^SeRemoteInteractiveLogonRight' | Select-Object -First 1).Line
Remove-Item -LiteralPath $sec -Force
Write-Host "    Wirksam: $right"
if ($right -notmatch 'S-1-5-32-555') { Write-Host '    WARNUNG: Recht noch nicht wirksam - gpupdate /force spaeter erneut ausfuehren.' -ForegroundColor Yellow }

# =============================================================================
Write-Step "Testdrucker (Ausgabe als Datei nach $outDir)"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
foreach ($p in $printers) {
    if (-not (Get-PrinterDriver -Name $p.Driver -ErrorAction SilentlyContinue)) { Add-PrinterDriver -Name $p.Driver }
    $port = Join-Path $outDir "$($p.Share).prn"
    if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $port }
    if (Get-Printer -Name $p.Name -ErrorAction SilentlyContinue) {
        Set-Printer -Name $p.Name -DriverName $p.Driver -PortName $port -Location $p.Location -Comment $p.Comment -Shared $true -ShareName $p.Share
    } else {
        Add-Printer -Name $p.Name -DriverName $p.Driver -PortName $port -Location $p.Location -Comment $p.Comment -Shared -ShareName $p.Share
        Write-Host "    $($p.Name) angelegt (\\$env:COMPUTERNAME\$($p.Share), $($p.Driver))"
    }
}

# =============================================================================
if ($SkipInstall) {
    Write-Host ''
    Write-Host 'Fertig (ohne WePrintEasy-Installation).' -ForegroundColor Green
    return
}

Write-Step 'WePrintEasy aus dem Repository installieren'
& (Join-Path $root 'Install-WePrintEasy.ps1') -ImportPrinters None

Import-Module (Join-Path $env:ProgramFiles 'WePrintEasy\WePrintEasy.psm1') -Force
$cfgPath = Get-WpeConfigPath

Write-Step 'Druckerliste (lokale Namen - Verbindung zum eigenen Server ist nicht moeglich)'
Set-WpePrinterCatalog -ConfigPath $cfgPath -Confirm:$false -Printers @($printers | ForEach-Object {
        [pscustomobject]@{ Path = $_.Name; DriverName = $_.Driver; Location = $_.Location; Comment = $_.Comment }
    })

Write-Step 'Zuweisungen'
Set-WpeAssignment -ConfigPath $cfgPath -Confirm:$false -Type Group -Name 'GG_WPE_Alle' -Printer 'WPE Buero' -Priority 100 -Comment 'Fallback fuer alle Testbenutzer' | Out-Null
Set-WpeAssignment -ConfigPath $cfgPath -Confirm:$false -Type Group -Name 'GG_WPE_Buchhaltung' -Printer 'WPE Buchhaltung' -Priority 10 | Out-Null
Set-WpeAssignment -ConfigPath $cfgPath -Confirm:$false -Type Group -Name 'GG_WPE_Lager' -Printer 'WPE Lager' -Priority 20 | Out-Null
Set-WpeAssignment -ConfigPath $cfgPath -Confirm:$false -Type User -Name 'wpetest3' -DisplayName 'Dora Direkt' -Printer 'WPE Buero' -Comment 'Direkte Zuweisung schlaegt GG_WPE_Buchhaltung' | Out-Null
Get-WpeAssignment -ConfigPath $cfgPath | Format-Table Type, Name, Printer, Priority -AutoSize | Out-String | Write-Host

Write-Host 'Testumgebung bereit.' -ForegroundColor Green
Write-Host "  Anmelden per RDP an $env:COMPUTERNAME.$($domain.DNSRoot) als $($domain.NetBIOSName)\wpetest1..3 (Kennwort: $credFile)"
Write-Host '  Erwartet: wpetest1 -> WPE Buchhaltung, wpetest2 -> WPE Lager, wpetest3 -> WPE Buero'
Write-Host "  Druckauftraege: $outDir\<Freigabe>.prn"
