#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt die winget-Manifeste (microsoft/winget-pkgs) einer Version aus den Vorlagen in installer\winget.

.DESCRIPTION
    - setzt Version, SHA-256 des Installers und Veroeffentlichungsdatum in die Vorlagen ein
    - entfernt die Kommentare der Vorlagen (bis auf die Schema-Angabe)
    - schreibt die Dateien nach <OutputDir>\manifests\w\WePrintEasy\WePrintEasy\<Version>\
      (gleicher Aufbau wie in winget-pkgs) und gibt diesen Ordner zurueck

    Der Installer liegt am GitHub-Release v<Version> (.github/workflows/release.yml); eingereicht
    werden die Manifeste von .github/workflows/winget.yml. Von Hand pruefen und einreichen:
        winget validate --manifest <Ordner>
        winget install --manifest <Ordner>      (vorher: winget settings --enable LocalManifestFiles)
        wingetcreate submit --prtitle "New package: WePrintEasy.WePrintEasy version <Version>" <Ordner>

    Aufruf:  powershell -File .\tools\New-WingetManifest.ps1 -Version 1.0.11 -InstallerPath .\dist\WePrintEasy-Setup-1.0.11.exe

.PARAMETER Version
    Version, z. B. 1.0.11. Ohne Angabe: $script:WpeVersion in src\WePrintEasy.psm1

.PARAMETER InstallerPath
    Der veroeffentlichte Installer WePrintEasy-Setup-<Version>.exe (fuer die Pruefsumme).

.PARAMETER InstallerSha256
    Statt -InstallerPath: SHA-256 des Installers.

.PARAMETER ReleaseDate
    Datum des Releases. Standard: heute
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallerPath,
    [string]$InstallerSha256,
    [datetime]$ReleaseDate = (Get-Date),
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot ist in Parameter-Vorgaben von Windows PowerShell 5.1 noch leer
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist\winget' }
$packageId = 'WePrintEasy.WePrintEasy'
$templates = Join-Path $root 'installer\winget'

if (-not $Version) {
    $psm1 = [IO.File]::ReadAllText((Join-Path $root 'src\WePrintEasy.psm1'))
    if ($psm1 -notmatch "\`$script:WpeVersion\s*=\s*'([^']+)'") { throw 'Version ($script:WpeVersion) in src\WePrintEasy.psm1 nicht gefunden.' }
    $Version = $Matches[1]
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "'$Version' ist keine Version (1.2.3)." }

if ([bool]$InstallerPath -eq [bool]$InstallerSha256) { throw 'Entweder -InstallerPath oder -InstallerSha256 angeben.' }
if ($InstallerPath) {
    $expected = "WePrintEasy-Setup-$Version.exe"
    if ((Split-Path -Leaf $InstallerPath) -ne $expected) { throw "Installer fuer $Version muss $expected heissen, nicht '$(Split-Path -Leaf $InstallerPath)'." }
    $InstallerSha256 = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash
}
if ($InstallerSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "'$InstallerSha256' ist keine SHA-256-Pruefsumme." }

$values = @{
    '__VERSION__'      = $Version
    '__SHA256__'       = $InstallerSha256.ToUpperInvariant()
    '__RELEASE_DATE__' = $ReleaseDate.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

$files = @(Get-ChildItem -LiteralPath $templates -Filter "$packageId*.yaml" | Sort-Object Name)
if ($files.Count -lt 3) { throw "Vorlagen fuer $packageId in $templates nicht gefunden." }

$parts = $packageId.Split('.')
$target = Join-Path $OutputDir ('manifests\{0}\{1}\{2}\{3}' -f $parts[0].Substring(0, 1).ToLowerInvariant(), $parts[0], $parts[1], $Version)
if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Path $target -Force | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName, $utf8)
    foreach ($k in $values.Keys) { $text = $text.Replace($k, $values[$k]) }
    if ($text -match '__[A-Z0-9_]+__') { throw "$($f.Name): Platzhalter $($Matches[0]) ist nicht belegt." }
    # Kommentare der Vorlage gehoeren nicht in winget-pkgs; die Schema-Angabe bleibt
    $lines = @($text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' -or $_ -match '^# yaml-language-server:' })
    $lines = @("# Created with tools/New-WingetManifest.ps1 (https://github.com/LeonMTN05/WePrintEasy)") + $lines
    [IO.File]::WriteAllText((Join-Path $target $f.Name), (($lines -join "`n").TrimEnd() + "`n"), $utf8)
}

Write-Host "winget-Manifeste $packageId $Version -> $target" -ForegroundColor Green
$target
