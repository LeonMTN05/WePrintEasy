#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
    Testet den Windows-Installer unbeaufsichtigt, wie winget ihn ausfuehrt:
    - installieren mit den Parametern von winget fuer Inno Setup (/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART)
    - Programmordner und Eintrag in Apps und Features (Version, optional Name und Herausgeber wie im Manifest)
    - deinstallieren mit QuietUninstallString aus Apps und Features (so deinstalliert winget)
    Haengt ein Schritt, bricht der Test nach -TimeoutMinutes ab und zeigt Prozesse, Fenster und Protokolle.
    NUR auf einem Testsystem ausfuehren (CI): installiert und entfernt WePrintEasy.

    Aufruf:  .\tests\Test-Setup.ps1 -InstallerPath .\dist\WePrintEasy-Setup-1.0.13.exe [-ManifestPath <installer.yaml>]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallerPath,
    # winget-Manifest (installer.yaml): AppsAndFeaturesEntries muessen zu Apps und Features passen
    [string]$ManifestPath,
    [int]$TimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
if ((Split-Path -Leaf $InstallerPath) -notmatch '^WePrintEasy-Setup-(\d+\.\d+\.\d+)\.exe$') { throw "Unerwarteter Dateiname: $InstallerPath" }
$version = $Matches[1]
$start = Get-Date
$app = Join-Path $env:ProgramFiles 'WePrintEasy'
# AppId in installer\WePrintEasy.iss
$arpKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{62BED98D-291F-401A-A240-5C8EC56F56F3}_is1'
$innoLog = Join-Path ([IO.Path]::GetTempPath()) "WePrintEasy-Setup-Test-$PID.log"

function Show-Diagnostics {
    Write-Host '--- Prozesse seit Beginn'
    Get-CimInstance Win32_Process | Where-Object { $_.CreationDate -ge $start } |
        Format-Table ProcessId, ParentProcessId, Name, CommandLine -Wrap | Out-String -Width 400 | Write-Host
    Write-Host '--- Fenster'
    Get-Process | Where-Object MainWindowTitle | Format-Table Id, ProcessName, MainWindowTitle | Out-String -Width 400 | Write-Host
    foreach ($l in $innoLog, (Join-Path $app 'Setup\WePrintEasy-Setup.log'), (Join-Path $env:TEMP 'WePrintEasy-Uninstall.log')) {
        if (Test-Path -LiteralPath $l) { Write-Host "--- $l"; Get-Content -LiteralPath $l -Tail 150 | Write-Host }
    }
}

function Invoke-Bounded([string]$File, [string]$Arguments) {
    Write-Host "==> $File $Arguments" -ForegroundColor Cyan
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
    # Ohne Zugriff auf Handle liefert ExitCode nach WaitForExit(ms) unter Windows PowerShell nichts
    $null = $p.Handle
    if (-not $p.WaitForExit($TimeoutMinutes * 60000)) {
        Show-Diagnostics
        & taskkill.exe /T /F /PID $p.Id | Out-Null
        throw "$(Split-Path -Leaf $File): nach $TimeoutMinutes Minuten nicht fertig."
    }
    if ($p.ExitCode -ne 0) { Show-Diagnostics; throw "$(Split-Path -Leaf $File): Code $($p.ExitCode)" }
}

if (Test-Path -LiteralPath $arpKey) { throw 'WePrintEasy ist schon installiert - der Test braucht ein System ohne WePrintEasy.' }

Invoke-Bounded $InstallerPath "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"$innoLog`""
if (-not (Test-Path -LiteralPath (Join-Path $app 'WePrintEasy-Agent.ps1'))) { Show-Diagnostics; throw "Nach dem Setup fehlt $app\WePrintEasy-Agent.ps1." }
$arp = Get-ItemProperty -LiteralPath $arpKey
Write-Host "Apps und Features: $($arp.DisplayName) $($arp.DisplayVersion) ($($arp.Publisher))"
if ($arp.DisplayVersion -ne $version) { throw "Apps und Features meldet Version '$($arp.DisplayVersion)' statt $version." }
if ($ManifestPath) {
    $manifest = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ManifestPath).Path)
    if ($manifest -notmatch "(?m)^- DisplayName: $([regex]::Escape($arp.DisplayName))\r?$" -or $manifest -notmatch "(?m)^  Publisher: $([regex]::Escape($arp.Publisher))\r?$") {
        throw 'DisplayName/Publisher in Apps und Features passen nicht zu AppsAndFeaturesEntries im Manifest.'
    }
}

if ($arp.QuietUninstallString -notmatch '^"([^"]+)"\s*(.*)$') { throw "QuietUninstallString fehlt oder ist unerwartet: '$($arp.QuietUninstallString)'" }
Invoke-Bounded $Matches[1] "$($Matches[2]) /SUPPRESSMSGBOXES /NORESTART"
# Der Deinstaller laeuft aus einer temporaeren Kopie weiter
for ($i = 0; $i -lt 60 -and ((Test-Path -LiteralPath (Join-Path $app 'WePrintEasy-Agent.ps1')) -or (Test-Path -LiteralPath $arpKey)); $i++) { Start-Sleep -Seconds 2 }
if (Test-Path -LiteralPath (Join-Path $app 'WePrintEasy-Agent.ps1')) { Show-Diagnostics; throw "Nach der Deinstallation ist $app noch vorhanden." }
if (Test-Path -LiteralPath $arpKey) { Show-Diagnostics; throw 'Eintrag in Apps und Features nach der Deinstallation noch vorhanden.' }
Remove-Item -LiteralPath $innoLog -ErrorAction SilentlyContinue
Write-Host "WePrintEasy $version unbeaufsichtigt installiert und wieder entfernt ($($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))." -ForegroundColor Green
