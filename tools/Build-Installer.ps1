#Requires -Version 5.1
<#
.SYNOPSIS
    Baut den Windows-Installer dist\WePrintEasy-Setup-<Version>.exe (Inno Setup 6).

.DESCRIPTION
    - Version aus $script:WpeVersion in src\WePrintEasy.psm1
    - Seitenbilder des Assistenten aus dem App-Symbol (docs\weprinteasy-icon.png)
    - kompiliert installer\WePrintEasy.iss mit ISCC.exe
    - signiert die .exe optional (Authenticode, signtool.exe aus dem Windows SDK)

    Inno Setup 6 installieren:  winget install --id JRSoftware.InnoSetup -e

    Aufruf:  powershell -File .\tools\Build-Installer.ps1

.PARAMETER IsccPath
    Pfad zu ISCC.exe. Ohne Angabe: PATH, Registry, Standardordner.

.PARAMETER CertificateThumbprint
    Optional: Fingerabdruck eines Codesignatur-Zertifikats (Cert:\CurrentUser\My oder
    Cert:\LocalMachine\My). Ohne Signatur zeigt Windows SmartScreen beim Start der .exe
    "Unbekannter Herausgeber" an.

.PARAMETER TimestampServer
    Zeitstempeldienst fuer die Signatur.
#>
[CmdletBinding()]
param(
    [string]$IsccPath,
    [string]$OutputDir,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot ist in Parameter-Vorgaben von Windows PowerShell 5.1 noch leer
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist' }

function Find-Iscc {
    $c = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($hive in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        $k = Get-ItemProperty -LiteralPath (Join-Path $hive 'Inno Setup 6_is1') -ErrorAction SilentlyContinue
        if ($k -and $k.InstallLocation -and (Test-Path -LiteralPath (Join-Path $k.InstallLocation 'ISCC.exe'))) { return Join-Path $k.InstallLocation 'ISCC.exe' }
    }
    foreach ($d in "${env:ProgramFiles(x86)}\Inno Setup 6", "$env:ProgramFiles\Inno Setup 6", "$env:LOCALAPPDATA\Programs\Inno Setup 6") {
        if (Test-Path -LiteralPath (Join-Path $d 'ISCC.exe')) { return Join-Path $d 'ISCC.exe' }
    }
    return $null
}

function Find-SignTool {
    $c = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function New-WizardImage([string]$Path, [int]$Width, [int]$Height, [System.Drawing.Color]$Back, [double]$LogoShare, [double]$LogoTop) {
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear($Back)
        $size = [int]([Math]::Min($Width, $Height) * $LogoShare)
        $g.DrawImage($script:logo, [int](($Width - $size) / 2), [int](($Height * $LogoTop) - $size / 2), $size, $size)
    } finally { $g.Dispose() }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
}

if (-not $IsccPath) { $IsccPath = Find-Iscc }
if (-not $IsccPath -or -not (Test-Path -LiteralPath $IsccPath)) {
    throw 'ISCC.exe (Inno Setup 6) nicht gefunden. Installieren: winget install --id JRSoftware.InnoSetup -e  - oder -IsccPath angeben.'
}

$psm1 = [IO.File]::ReadAllText((Join-Path $root 'src\WePrintEasy.psm1'))
if ($psm1 -notmatch "\`$script:WpeVersion\s*=\s*'([^']+)'") { throw 'Version ($script:WpeVersion) in src\WePrintEasy.psm1 nicht gefunden.' }
$version = $Matches[1]

# Seitenbilder: grosses Bild (Willkommen/Fertig) in der Farbe der Setup-Seitenleiste, kleines oben rechts
Add-Type -AssemblyName System.Drawing
$images = Join-Path ([IO.Path]::GetTempPath()) "WePrintEasy-Installer-$PID"
New-Item -ItemType Directory -Path $images -Force | Out-Null
$script:logo = [System.Drawing.Image]::FromFile((Join-Path $root 'docs\weprinteasy-icon.png'))
try {
    $navy = [System.Drawing.Color]::FromArgb(0, 70, 140)
    foreach ($s in @(@{ P = 100; F = 1.0 }, @{ P = 125; F = 1.25 }, @{ P = 150; F = 1.5 })) {
        New-WizardImage (Join-Path $images "wizard-$($s.P).bmp") ([int](164 * $s.F)) ([int](314 * $s.F)) $navy 0.62 0.32
        New-WizardImage (Join-Path $images "small-$($s.P).bmp") ([int](55 * $s.F)) ([int](55 * $s.F)) ([System.Drawing.Color]::White) 0.92 0.5
    }
} finally { $script:logo.Dispose() }

Write-Host "==> Inno Setup: WePrintEasy $version" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
& $IsccPath /Qp "/DAppVersion=$version" "/DRepoRoot=$root" "/DOutputDir=$OutputDir" "/DWizardImages=$images" (Join-Path $root 'installer\WePrintEasy.iss')
$exitCode = $LASTEXITCODE
Remove-Item -LiteralPath $images -Recurse -Force -ErrorAction SilentlyContinue
if ($exitCode -ne 0) { throw "ISCC.exe ist mit Code $exitCode fehlgeschlagen." }
$exe = Join-Path $OutputDir "WePrintEasy-Setup-$version.exe"

if ($CertificateThumbprint) {
    $signtool = Find-SignTool
    if (-not $signtool) { throw 'signtool.exe (Windows SDK) nicht gefunden.' }
    $t = ($CertificateThumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    $store = if (Test-Path -LiteralPath "Cert:\CurrentUser\My\$t") { @() } elseif (Test-Path -LiteralPath "Cert:\LocalMachine\My\$t") { @('/sm') } else { throw "Zertifikat $t nicht gefunden." }
    Write-Host "==> Signieren ($t)" -ForegroundColor Cyan
    & $signtool sign /fd SHA256 /sha1 $t @store /tr $TimestampServer /td SHA256 /d 'WePrintEasy Setup' $exe
    if ($LASTEXITCODE -ne 0) { throw "signtool.exe ist mit Code $LASTEXITCODE fehlgeschlagen." }
}

$file = Get-Item -LiteralPath $exe
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ''
Write-Host ("{0}: {1:N1} MB" -f $file.Name, ($file.Length / 1MB)) -ForegroundColor Green
Write-Host "SHA-256 $hash"
