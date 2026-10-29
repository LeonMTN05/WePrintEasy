<#
    Integrationstests auf einem echten Windows Server (als Administrator).
    Wird in GitHub Actions auf windows-2025 ausgefuehrt, kann aber auch auf
    einem Testserver laufen - ACHTUNG: legt 70 Testdrucker an, installiert und
    deinstalliert WePrintEasy und aendert den Standarddrucker des Benutzers.

    Ablauf:
      1. 70 freigegebene Testdrucker anlegen (simuliert den Druck-/Fileserver)
      2. Installation per Kommandozeile inkl. Druckerimport, danach signiert
         (selbstsigniertes Zertifikat, Agent unter AllSigned)
      3. Anmelde-Agent mit echten Druckern (Benutzer, Gruppe, Netzwerkdrucker,
         Zuruecksetzen, Wiederverbindung, Live-Aenderung)
      4. Deinstallation
      5. Setup-Assistent (grafisch, automatisch durchlaufen) inkl. Installation
      6. Verwaltungsprogramm (alle Ansichten, Bildschirmfotos)
#>
[CmdletBinding()]
param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) 'wpe-results'))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installDir = Join-Path $env:ProgramFiles 'WePrintEasy'
$server = $env:COMPUTERNAME
$userLog = Join-Path $env:LOCALAPPDATA 'WePrintEasy\agent.log'

$script:Failed = 0; $script:Passed = 0
function Assert {
    param([string]$Name, [scriptblock]$Condition)
    $err = ''
    try { $ok = [bool](& $Condition) } catch { $ok = $false; $err = $_.Exception.Message }
    if ($ok) { $script:Passed++; Write-Host "  [OK]   $Name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  [FAIL] $Name $err" -ForegroundColor Red }
}
function Invoke-Section {
    param([string]$Name, [scriptblock]$Block)
    Write-Host ''; Write-Host "### $Name" -ForegroundColor Cyan
    try { . $Block } catch {
        $script:Failed++
        Write-Host "  [FAIL] Abschnitt abgebrochen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "         $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    }
}
function Invoke-Agent {
    param([switch]$Once)
    $a = @('-NoProfile', '-ExecutionPolicy', (Get-WpeExecutionPolicy -Path "$installDir\WePrintEasy-Agent.ps1"), '-File', "`"$installDir\WePrintEasy-Agent.ps1`"")
    if ($Once) { $a += '-Once' }
    if ($Once) { return (Start-Process -FilePath $psExe -ArgumentList $a -WindowStyle Hidden -PassThru -Wait) }
    return (Start-Process -FilePath $psExe -ArgumentList $a -WindowStyle Hidden -PassThru)
}
function Wait-Until {
    param([scriptblock]$Condition, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) { if (& $Condition) { return $true }; Start-Sleep -Milliseconds 500 }
    return [bool](& $Condition)
}
function Get-LogText { if (Test-Path $userLog) { Get-Content -LiteralPath $userLog -Raw -Encoding UTF8 } else { '' } }
# Nur Agenten dieser Sitzung - auf einem Testserver koennen andere Benutzer angemeldet sein
$mySession = [Diagnostics.Process]::GetCurrentProcess().SessionId
# Komma: auch ein einzelner Agent bleibt ein Array (sonst fehlt .Count bei PSCustomObject in PowerShell 5.1)
function Get-MyAgent { , @(Get-WpeAgentProcess | Where-Object { $_.SessionId -eq $mySession }) }

Import-Module (Join-Path $root 'src\WePrintEasy.psm1') -Force
Write-Host "Rechner: $server  Benutzer: $env:USERDOMAIN\$env:USERNAME  OS: $((Get-CimInstance Win32_OperatingSystem).Caption)  PS: $($PSVersionTable.PSVersion)"

# =============================================================================
Invoke-Section '1. Testdrucker (simulierter Druck-/Fileserver)' {
Start-Service Spooler -ErrorAction SilentlyContinue
$drivers = @(Get-PrinterDriver | ForEach-Object { $_.Name })
Write-Host "  Vorhandene Treiber: $($drivers -join ', ')"
$port = 'WPE_TEST_PORT'
if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $port -PrinterHostAddress '127.0.0.1' }
# Freigebbaren Treiber suchen (klassische v3-Treiber; der PDF-Treiber ist nicht freigebbar)
$driver = $null
$ntprint = Join-Path $env:SystemRoot 'INF\ntprint.inf'
foreach ($d in @('Generic / Text Only', 'MS Publisher Imagesetter', 'Microsoft PS Class Driver', 'Microsoft PCL6 Class Driver') + $drivers) {
    try {
        if (-not (Get-PrinterDriver -Name $d -ErrorAction SilentlyContinue)) {
            try { Add-PrinterDriver -Name $d -ErrorAction Stop } catch { Add-PrinterDriver -Name $d -InfPath $ntprint -ErrorAction Stop }
        }
        if (Get-Printer -Name 'WPE Probe' -ErrorAction SilentlyContinue) { Remove-Printer -Name 'WPE Probe' }
        Add-Printer -Name 'WPE Probe' -DriverName $d -PortName $port -ErrorAction Stop
        Set-Printer -Name 'WPE Probe' -Shared $true -ShareName 'WPE-Probe' -ErrorAction Stop
        Remove-Printer -Name 'WPE Probe'
        $driver = $d
        break
    } catch {
        Write-Host "  Treiber '$d' nicht nutzbar: $($_.Exception.Message)"
        Remove-Printer -Name 'WPE Probe' -ErrorAction SilentlyContinue
    }
}
Write-Host "  Verwende Treiber: $driver"
if (-not $driver) { $driver = 'Microsoft Print To PDF'; Write-Host '  KEIN freigebbarer Treiber - Netzwerktests werden fehlschlagen.' -ForegroundColor Red }
for ($i = 1; $i -le 70; $i++) {
    $name = "WPE Test $i"
    if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
        Add-Printer -Name $name -DriverName $driver -PortName $port -Location "Raum $i.0$($i % 4)" -Comment "Testdrucker $i"
    }
    try { Set-Printer -Name $name -Shared $true -ShareName "WPE-Test-$i" -ErrorAction Stop } catch { if ($i -eq 1) { Write-Host "  Freigabe fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red } }
}
Assert '70 Testdrucker angelegt und freigegeben' { @(Get-Printer -Name 'WPE Test *' | Where-Object Shared).Count -eq 70 }
$fromServer = @(Get-WpePrintServerPrinter -PrintServer $server)
Assert 'Get-WpePrintServerPrinter liefert die 70 Freigaben' { @($fromServer | Where-Object { $_.ShareName -like 'WPE-Test-*' }).Count -eq 70 }
Assert 'Treiber wird als lokal vorhanden erkannt' { ($fromServer | Where-Object ShareName -eq 'WPE-Test-1').DriverInstalled -eq $true }
Assert 'Standort wird uebernommen' { ($fromServer | Where-Object ShareName -eq 'WPE-Test-7').Location -eq 'Raum 7.03' }

# =============================================================================
}
Invoke-Section '2. Installation per Kommandozeile' {
& (Join-Path $root 'Install-WePrintEasy.ps1') -PrintServer $server -ImportPrinters All -DisableClientDefaultPrinter -Language en *>&1 | Out-File (Join-Path $OutDir 'install-cli.log') -Encoding utf8
Get-Content (Join-Path $OutDir 'install-cli.log') | ForEach-Object { Write-Host "    | $_" }
$script:cfgPath = Get-WpeConfigPath
Assert 'Programmdateien installiert (inkl. Sprachdateien und Symbol)' { @('WePrintEasy.psm1', 'WePrintEasy.Gui.ps1', 'WePrintEasy-Agent.ps1', 'WePrintEasy-Admin.ps1', 'WePrintEasy-Admin.cmd', 'WePrintEasy-Tray.ps1', 'WePrintEasy.Strings.en.psd1', 'WePrintEasy.Strings.de.psd1', 'WePrintEasy.ico' | Where-Object { Test-Path (Join-Path $installDir $_) }).Count -eq 9 }
Assert 'Lizenz liegt der Installation bei' { Test-Path (Join-Path $installDir 'LICENSE') }
Assert 'Registry: ConfigPath gesetzt' { $cfgPath -eq (Join-Path $env:ProgramData 'WePrintEasy\config.json') }
$task = Get-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent' -ErrorAction SilentlyContinue
Assert 'Geplante Aufgabe vorhanden' { $null -ne $task }
Assert 'Aufgabe: 2 Trigger (Anmeldung + Wiederverbindung)' { @($task.Triggers).Count -eq 2 -and @($task.Triggers | Where-Object { $_.StateChange -eq 3 }).Count -eq 1 }
Assert 'Aufgabe: laeuft als Gruppe Benutzer, eingeschraenkt' { $task.Principal.GroupId -match 'Users|Benutzer' -and [string]$task.Principal.RunLevel -eq 'Limited' }
Assert 'Aufgabe: parallele Instanzen, kein Zeitlimit' { [string]$task.Settings.MultipleInstances -eq 'Parallel' -and $task.Settings.ExecutionTimeLimit -eq 'PT0S' }
Assert 'Aufgabe: unsichtbar ueber conhost --headless' { $task.Actions[0].Execute -like '*conhost.exe' -and $task.Actions[0].Arguments -like '--headless*' }
Assert 'RDS-Richtlinie fForceClientLptDef = 0' { (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services').fForceClientLptDef -eq 0 }
$script:toolsDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Administrative Tools'
Assert 'Verknuepfung unter Windows-Tools (englisch, mit App-Symbol)' { $l = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $toolsDir 'WePrintEasy Printer Management.lnk')); (Test-Path $l.FullName) -and $l.IconLocation -like '*WePrintEasy.ico,0' }
Assert 'Sprache: Registry en, Aufgabenbeschreibung englisch' { (Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy').Language -eq 'en' -and $task.Description -like 'Sets the user*' }
$cfg = Read-WpeConfig -Path $cfgPath
Assert 'Druckerliste: 70 Drucker vom Fileserver importiert' { @($cfg.Printers | Where-Object { $_.ShareName -like 'WPE-Test-*' }).Count -eq 70 }
Assert 'Standard-Druckserver gesetzt' { $cfg.Settings.DefaultPrintServer -eq $server }
$acl = Get-Acl (Split-Path $cfgPath)
$usersSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$usersRules = @($acl.Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) -eq $usersSid })
$fileAcl = Get-Acl $cfgPath
$fileUsers = @($fileAcl.Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) -eq $usersSid })
Assert 'Rechte: config.json erbt Leserecht fuer Benutzer' { $fileUsers.Count -ge 1 -and ($fileUsers | Where-Object { $_.IsInherited -and ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) }) }
Assert 'Rechte: config.json fuer Administratoren lesbar' { [bool](Read-WpeConfig -Path $cfgPath) }
Assert 'Rechte: Benutzer duerfen Konfiguration nur lesen' { $usersRules.Count -ge 1 -and -not ($usersRules | Where-Object { $_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::WriteData }) }
$fileRules = @((Get-Acl $cfgPath).Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) -eq $usersSid })
Assert 'Rechte: config.json selbst ist fuer Benutzer lesbar (keine leere Zugriffsliste)' { $fileRules.Count -ge 1 -and [bool]([IO.File]::ReadAllText($cfgPath)) }
$status = @(Get-WpeSystemStatus)
$status | ForEach-Object { Write-Host ("    {0,-8} {1,-26} {2}" -f $_.Status, $_.Check, $_.Detail) }
Assert 'Systempruefung: keine Fehler' { @($status | Where-Object Status -eq 'Error').Count -eq 0 }
& (Join-Path $root 'Install-WePrintEasy.ps1') -PrintServer $server -ImportPrinters All -DisableClientDefaultPrinter *>&1 | Out-Null
Assert 'Erneute Installation (Update) funktioniert und behaelt Druckerliste' { @((Read-WpeConfig -Path $cfgPath).Printers).Count -ge 70 }
# Defekte Zugriffsliste (aeltere Installer-Versionen) wird beim Update repariert
& icacls.exe $cfgPath /inheritance:r /Q | Out-Null
Assert 'Vorbereitung: config.json nicht mehr lesbar' { try { [void][IO.File]::ReadAllText($cfgPath); $false } catch { $true } }
& (Join-Path $root 'Install-WePrintEasy.ps1') *>&1 | Out-Null
Assert 'Update repariert die Zugriffsliste, Druckerliste bleibt erhalten' { @((Read-WpeConfig -Path $cfgPath).Printers).Count -ge 70 }

# =============================================================================
}
Invoke-Section '2b. Signierte Installation (selbstsigniertes Zertifikat)' {
& (Join-Path $root 'Install-WePrintEasy.ps1') -DisableClientDefaultPrinter -SelfSignedCertificate *>&1 | Out-File (Join-Path $OutDir 'install-signed.log') -Encoding utf8
Get-Content (Join-Path $OutDir 'install-signed.log') | ForEach-Object { Write-Host "    | $_" }
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy'
$script:signThumb = [string]$reg.SigningThumbprint
$sigs = @(Get-WpeSignatureStatus -InstallPath $installDir)
Assert 'Signatur: alle 5 Skripte gueltig signiert' { $sigs.Count -eq 5 -and @($sigs | Where-Object Status -ne 'Valid').Count -eq 0 }
Assert 'Registry: AllSigned, selbst erstelltes Zertifikat' { $reg.ExecutionPolicy -eq 'AllSigned' -and $reg.SigningCertCreated -eq 1 -and $signThumb }
Assert 'Zertifikat vertrauenswuerdig (Root + TrustedPublisher)' { (Test-Path "Cert:\LocalMachine\Root\$signThumb") -and (Test-Path "Cert:\LocalMachine\TrustedPublisher\$signThumb") }
$task = Get-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent'
Assert 'Aufgabe startet mit -ExecutionPolicy AllSigned' { $task.Actions[0].Arguments -like '*-ExecutionPolicy AllSigned *' }
Assert 'WePrintEasy-Admin.cmd startet mit AllSigned' { (Get-Content (Join-Path $installDir 'WePrintEasy-Admin.cmd') -Raw) -match '-ExecutionPolicy AllSigned ' }
Assert 'Registry: Sprache bleibt beim Update ohne -Language erhalten' { $reg.Language -eq 'en' }
Assert 'Systempruefung: Signatur OK' { (@(Get-WpeSystemStatus) | Where-Object Id -eq 'Signature').Status -eq 'OK' }
$p = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'AllSigned', '-File', "`"$installDir\WePrintEasy-Agent.ps1`"", '-Once') -WindowStyle Hidden -PassThru -Wait
Assert 'Agent laeuft unter AllSigned ohne Rueckfrage (Exitcode 0)' { $p.ExitCode -eq 0 }
Add-Content -LiteralPath (Join-Path $installDir 'WePrintEasy-Agent.ps1') -Value '# manipuliert'
Assert 'Systempruefung erkennt veraenderte Datei' { (@(Get-WpeSystemStatus) | Where-Object Id -eq 'Signature').Status -eq 'Error' }
$up = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$root\Update-WePrintEasy.ps1`"", '-NoPause') -WindowStyle Hidden -PassThru -Wait
Assert 'Update-WePrintEasy.ps1 endet erfolgreich (Exitcode 0)' { $up.ExitCode -eq 0 }
Assert 'Updater: signiert weiter mit demselben Zertifikat' { (Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy').SigningThumbprint -eq $signThumb -and @(Get-WpeSignatureStatus -InstallPath $installDir | Where-Object Status -ne 'Valid').Count -eq 0 }

# =============================================================================
}
Invoke-Section '3. Anmelde-Agent mit echten Druckern' {
# Protokolltexte werden englisch geprueft - eine vorhandene Konfiguration (Testserver) koennte eine andere Sprache vorgeben
$cfg = Read-WpeConfig -Path $cfgPath; $cfg.Settings.Language = ''; Save-WpeConfig -Config $cfg -Path $cfgPath -Confirm:$false
Remove-Item $userLog -ErrorAction SilentlyContinue
Set-WpeDefaultPrinter -Name 'WPE Test 2' -Confirm:$false
Assert 'Ausgangslage: Standarddrucker WPE Test 2' { (Get-WpeDefaultPrinter) -eq 'WPE Test 2' }

Set-WpeAssignment -Type User -Name $env:USERNAME -Printer 'WPE Test 1' -Comment 'Integrationstest' | Out-Null
Assert 'Zuweisung per Anmeldename (SID automatisch ermittelt)' { (Get-WpeAssignment -Type User -Name $env:USERNAME).Sid -eq ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value) }
$p = Invoke-Agent -Once
Assert 'Agent -Once beendet sich mit 0' { $p.ExitCode -eq 0 }
Assert 'Benutzerzuweisung: Standarddrucker = WPE Test 1' { (Get-WpeDefaultPrinter) -eq 'WPE Test 1' }
Assert 'Protokoll: "Default printer set ... (previously: WPE Test 2)"' { (Get-LogText) -match "Default printer set: 'WPE Test 1' \(previously: 'WPE Test 2'\)" }
Assert '"Windows verwaltet Standarddrucker" deaktiviert' { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows').LegacyDefaultPrinterMode -eq 1 }

# Netzwerkdrucker (\\server\freigabe) automatisch verbinden.
# Windows erlaubt keine Druckerverbindung zum eigenen Rechnernamen (0x8007007B) - daher ueber einen
# Alias-Namen versuchen, wie er bei einem separaten Fileserver vorliegt.
$alias = 'wpe-printsrv'
$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
if (-not (Select-String -Path $hosts -Pattern $alias -Quiet)) { Add-Content -Path $hosts -Value "127.0.0.1 $alias" }
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name DisableStrictNameChecking -Value 1 -Type DWord
New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name BackConnectionHostNames -Value @($alias) -PropertyType MultiString -Force | Out-Null
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name DisableLoopbackCheck -Value 1 -Type DWord
Restart-Service LanmanServer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$netPrinter = $null
foreach ($cand in @("\\$alias\WPE-Test-5", "\\$server\WPE-Test-5")) {
    try {
        Add-Printer -ConnectionName $cand -ErrorAction Stop
        # Unter welchem Namen fuehrt Windows die Verbindung? (Drucker "WPE Test 5", Freigabe "WPE-Test-5")
        $probe = @(Get-WpePrinterConnection | Where-Object ShareName -eq 'WPE-Test-5')
        Write-Host "    Verbindung $cand erscheint als: $(@(Get-WpeInstalledPrinterNames | Where-Object { $_ -like '\\*' }) -join ' | ') (Stufe 2: $(@($probe | ForEach-Object { '{0} [{1}, {2}]' -f $_.Name, $_.Server, $_.ShareName }) -join ' | '))"
        foreach ($n in @($cand) + @($probe | ForEach-Object { $_.Name })) { Remove-Printer -Name $n -ErrorAction SilentlyContinue }
        $netPrinter = $cand
        break
    } catch {
        Write-Host "    Verbindung $cand nicht moeglich: $($_.Exception.Message.Trim()) [$($_.FullyQualifiedErrorId)]"
    }
}
Remove-Item $userLog -ErrorAction SilentlyContinue
if ($netPrinter) {
    Set-WpeAssignment -Type User -Name $env:USERNAME -Printer $netPrinter | Out-Null
    $p = Invoke-Agent -Once
    $conn = @(Get-WpePrinterConnection | Where-Object ShareName -eq 'WPE-Test-5') | Select-Object -First 1
    $netHost = $netPrinter.Split('\')[2]
    Assert "Netzwerkdrucker $netPrinter wird verbunden und Standard (auch unter dem Druckernamen)" { $d = Get-WpeDefaultPrinter; $d -eq $netPrinter -or ($conn -and $d -eq $conn.Name) }
    Assert 'Get-WpePrinterConnection: Verbindung mit Server und Freigabename' { $conn -and (-not $conn.Server -or (ConvertTo-WpeShortHost $conn.Server) -eq (ConvertTo-WpeShortHost $netHost)) -and $conn.ShareName -eq 'WPE-Test-5' }
    Assert 'Resolve-WpeInstalledPrinter: Freigabe ergibt den Drucker der Sitzung' { (Resolve-WpeInstalledPrinter -Pattern $netPrinter -InstalledNames @(Get-WpeInstalledPrinterNames)) -eq (Get-WpeDefaultPrinter) }
    Assert 'Get-WpeShareConnectionName: Druckername auf dem Server' { (Get-WpeShareConnectionName -Path $netPrinter) -eq "\\$netHost\WPE Test 5" }
    Assert 'Protokoll: Netzwerkdrucker verbunden' { (Get-LogText) -match 'Network printer .* connected' }
    $firstLog = Get-LogText
    Remove-Item $userLog -ErrorAction SilentlyContinue
    $p = Invoke-Agent -Once
    Assert 'Zweiter Lauf: Drucker gilt als gesetzt (Ergebnis Ok, keine Warnung)' { $p.ExitCode -eq 0 -and (Get-LogText) -match 'result Ok' -and (Get-LogText) -notmatch '\[WARN\]' }
    Set-Content -LiteralPath $userLog -Value $firstLog -Encoding UTF8 -NoNewline
} else {
    Write-Host '  [SKIP] Druckerverbindung auf einem Einzelrechner nicht moeglich (Windows verbietet Verbindungen zu sich selbst).' -ForegroundColor Yellow
    Set-WpeAssignment -Type User -Name $env:USERNAME -Printer "\\$server\WPE-Test-5" | Out-Null
    $p = Invoke-Agent -Once
    Assert 'Nicht verbindbarer Drucker: Agent laeuft fehlerfrei weiter (Exitcode 0)' { $p.ExitCode -eq 0 }
    Assert 'Nicht verbindbarer Drucker: Warnung mit Fehlercode im Protokoll' { (Get-LogText) -match "WARN\] Connection to .*WPE-Test-5.* failed: .*\[0x" }
    Assert 'Nicht verbindbarer Drucker: bisheriger Standarddrucker bleibt' { (Get-WpeDefaultPrinter) -eq 'WPE Test 1' }
}

# Gruppenzuweisung (BUILTIN\Benutzer ist im Token jedes Benutzers)
Remove-WpeAssignment -Type User -Name $env:USERNAME
Set-WpeAssignment -Type Group -Name 'Users' -Sid 'S-1-5-32-545' -DisplayName 'Benutzer (Test)' -Printer 'WPE Test 3' -Priority 50 | Out-Null
Set-WpeAssignment -Type Group -Name 'Administrators' -Sid 'S-1-5-32-544' -Printer 'WPE Test 9' -Priority 90 | Out-Null
$p = Invoke-Agent -Once
Assert 'Gruppenzuweisung mit kleinster Prioritaet greift (WPE Test 3)' { (Get-WpeDefaultPrinter) -eq 'WPE Test 3' }

# Dauerbetrieb: Zuruecksetzen, Wiederverbindung, Live-Aenderung
$cfg = Read-WpeConfig -Path $cfgPath
$cfg.Settings.LogonPhaseSeconds = 4
$cfg.Settings.EnforceIntervalSeconds = 5
Save-WpeConfig -Config $cfg -Path $cfgPath -Confirm:$false
Remove-Item $userLog -ErrorAction SilentlyContinue
$agent = Invoke-Agent
Start-Sleep -Seconds 7
Assert 'Agent laeuft im Hintergrund' { -not $agent.HasExited }
Set-WpeDefaultPrinter -Name 'WPE Test 2' -Confirm:$false     # simuliert RDP-Umleitung / Benutzer
Assert 'Verstellter Standarddrucker wird zurueckgesetzt (<= 12 s)' { Wait-Until { (Get-WpeDefaultPrinter) -eq 'WPE Test 3' } 12 }
$second = Invoke-Agent
Assert 'Zweite Instanz (Wiederverbindung) beendet sich sofort' { $second.WaitForExit(30000) -and $second.ExitCode -eq 0 }
Assert 'Laufender Agent startet Anmeldephase neu' { Wait-Until { (Get-LogText) -match 'reconnected' } 10 }
Set-WpeAssignment -Type Group -Name 'Users' -Sid 'S-1-5-32-545' -Printer 'WPE Test 4' -Priority 50 | Out-Null
Assert 'Geaenderte Zuweisung wird ohne Neuanmeldung uebernommen (<= 15 s)' { Wait-Until { (Get-WpeDefaultPrinter) -eq 'WPE Test 4' } 15 }
Assert 'Nur eine Agent-Instanz pro Sitzung' { (Get-MyAgent).Count -eq 1 }
# Update: der laufende Agent wird mit der neuen Version neu gestartet (sonst liefe er bis zur Abmeldung alt weiter)
& (Join-Path $root 'Install-WePrintEasy.ps1') *>&1 | Out-File (Join-Path $OutDir 'install-restart.log') -Encoding utf8
Get-Content (Join-Path $OutDir 'install-restart.log') | Select-String 'Agent|agent' | ForEach-Object { Write-Host "    | $_" }
$restarted = Get-MyAgent
Assert 'Update startet den laufenden Agenten neu (alter beendet, genau ein neuer)' { $agent.HasExited -and $restarted.Count -eq 1 -and $restarted[0].ProcessId -ne $agent.Id }
Set-WpeDefaultPrinter -Name 'WPE Test 2' -Confirm:$false
Assert 'Neu gestarteter Agent setzt weiter zurueck (<= 15 s)' { Wait-Until { (Get-WpeDefaultPrinter) -eq 'WPE Test 4' } 15 }
Assert 'Keine Neustart-Aufgaben uebrig' { @(Get-ScheduledTask -TaskPath '\WePrintEasy\' | Where-Object TaskName -like 'Restart *').Count -eq 0 }
Assert 'Registry und Versionsuebersicht: installierte Version' { $v = (Get-WpeAboutInfo).Version; (Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy').Version -eq $v -and (@(Get-WpeHost) | Where-Object ComputerName -eq $env:COMPUTERNAME).Version -eq $v }
# "Alles neu starten" (Druckerverwaltung): laufender Agent neu, Sitzung ohne Agent bekommt einen
$beforeIds = @(Get-MyAgent | ForEach-Object { $_.ProcessId })
$ra = Restart-WpeAll -InstallPath $installDir -Confirm:$false
$ra.Agents | ForEach-Object { Write-Host "    | $($_.User) ($($_.SessionId)): $($_.Status) $($_.Message)" }
$after = Get-MyAgent
Assert 'Alles neu starten: Agent dieser Sitzung neu gestartet (genau einer, neue Prozess-ID)' { $after.Count -eq 1 -and $beforeIds -notcontains $after[0].ProcessId -and @($ra.Agents | Where-Object Status -eq 'Restarted').Count -ge 1 }
if (@(Get-WpeUserSession | Where-Object SessionId -eq $mySession).Count) {
    foreach ($r in Get-MyAgent) { Stop-Process -Id $r.ProcessId -Force; [void](Wait-Process -Id $r.ProcessId -Timeout 10 -ErrorAction SilentlyContinue) }
    $ra = Restart-WpeAll -InstallPath $installDir -Confirm:$false
    Assert 'Alles neu starten: Sitzung ohne Agent bekommt einen (Status Started)' { (Get-MyAgent).Count -eq 1 -and @($ra.Agents | Where-Object Status -eq 'Started').Count -ge 1 }
} else {
    Write-Host '  [SKIP] Sitzung ohne explorer.exe - Start in einer Sitzung ohne Agent nicht pruefbar.' -ForegroundColor Yellow
}
foreach ($r in Get-MyAgent) { Stop-Process -Id $r.ProcessId -Force -ErrorAction SilentlyContinue }
if (-not $agent.HasExited) { Stop-Process -Id $agent.Id -Force }
Copy-Item $userLog (Join-Path $OutDir 'agent.log') -ErrorAction SilentlyContinue
Write-Host '    Agent-Protokoll:'; Get-Content $userLog | ForEach-Object { Write-Host "    | $_" }

# Platzhalter
Set-WpeAssignment -Type Group -Name 'Users' -Sid 'S-1-5-32-545' -Printer 'WPE Test 6?' -Priority 50 | Out-Null
$p = Invoke-Agent -Once
Assert 'Platzhalter "WPE Test 6?" waehlt passenden Drucker' { (Get-WpeDefaultPrinter) -like 'WPE Test 6?' }
Assert 'Protokollpfad des Benutzers ermittelbar' { (Get-WpeAgentLogPath -UserSid ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) -eq $userLog }

# Sprache der Konfiguration gilt auch fuer das Agent-Protokoll
$cfg = Read-WpeConfig -Path $cfgPath; $cfg.Settings.Language = 'de'; Save-WpeConfig -Config $cfg -Path $cfgPath -Confirm:$false
Remove-Item $userLog -ErrorAction SilentlyContinue
$p = Invoke-Agent -Once
Assert 'Einstellung Sprache = de: Agent protokolliert deutsch' { (Get-LogText) -match 'Vorgabe: ''WPE Test 6\?'' \(über Gruppe' }
$cfg.Settings.Language = ''; Save-WpeConfig -Config $cfg -Path $cfgPath -Confirm:$false

# Druckerwahl bei zentraler Konfiguration: Freigabe nur "Lesen" wird erkannt und behoben
$shareDir = Join-Path $OutDir 'share'
New-Item -ItemType Directory -Path $shareDir -Force | Out-Null
$everyone = (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value
$admins = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
New-SmbShare -Name 'WpeChoiceTest$' -Path $shareDir -ReadAccess $everyone -FullAccess $admins | Out-Null
try {
    $shareCfg = "\\$server\WpeChoiceTest$\config.json"
    $c = Read-WpeConfig -Path $shareCfg; $c.Settings.AllowUserPrinterChoice = $true; Save-WpeConfig -Config $c -Path $shareCfg -Confirm:$false
    Initialize-WpeChoiceDirectory -ConfigPath $shareCfg -Confirm:$false
    $r = @(Get-WpeSystemStatus -ConfigPath $shareCfg) | Where-Object Id -eq 'UserChoiceShare'
    Assert 'Freigabe nur "Lesen": Systempruefung meldet Fehler mit Behebung' { $r.Status -eq 'Error' -and $r.Fix -eq 'ShareAccess' }
    Set-WpeShareChangeAccess -ConfigPath $shareCfg -Confirm:$false
    Assert 'Behebung: Benutzer duerfen auf der Freigabe schreiben' { (Get-WpeShareAccess -ConfigPath $shareCfg).Writable -and (@(Get-WpeSystemStatus -ConfigPath $shareCfg) | Where-Object Id -eq 'UserChoiceShare').Status -eq 'OK' }
} finally {
    Remove-SmbShare -Name 'WpeChoiceTest$' -Force -ErrorAction SilentlyContinue
}

# =============================================================================
}
Invoke-Section '4. Deinstallation' {
$agent = Invoke-Agent
Assert 'Vorbereitung: Agent laeuft' { Wait-Until { (Get-MyAgent).Count -eq 1 } 10 }
& (Join-Path $root 'Uninstall-WePrintEasy.ps1') -RemoveConfig -RemoveClientDefaultPrinterPolicy -Confirm:$false *>&1 | Out-Null
Assert 'Laufender Agent wird beendet' { $agent.WaitForExit(10000) }
Assert 'Aufgabe entfernt' { -not (Get-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent' -ErrorAction SilentlyContinue) }
Assert 'Programmordner entfernt' { -not (Test-Path $installDir) }
Assert 'Registry entfernt' { -not (Test-Path 'HKLM:\SOFTWARE\WePrintEasy') }
Assert 'Konfiguration entfernt' { -not (Test-Path $cfgPath) }
Assert 'Verknuepfung entfernt' { -not @(Get-WpeShortcutPath -All | Where-Object { Test-Path $_ }).Count }
Assert 'Richtlinie entfernt' { $null -eq (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -ErrorAction SilentlyContinue).fForceClientLptDef }
Assert 'Selbstsigniertes Zertifikat entfernt' { $signThumb -and -not (@('My', 'Root', 'TrustedPublisher') | Where-Object { Test-Path "Cert:\LocalMachine\$_\$signThumb" }) }

# =============================================================================
}
Invoke-Section '5. Setup-Assistent (grafisch, automatischer Durchlauf)' {
# Zuerst auf Englisch (Bildschirmfotos fuer die englische Website/README), danach wieder entfernen
$enSetupShots = Join-Path $OutDir 'screenshots-en'
New-Item -ItemType Directory -Path $enSetupShots -Force | Out-Null
$sp = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$root\Setup-WePrintEasy.ps1`"", '-PrintServer', $server, '-Language', 'en', '-ScreenshotDir', "`"$enSetupShots`"") -PassThru
if (-not $sp.WaitForExit(600000)) { Stop-Process -Id $sp.Id -Force; Write-Host '  Setup (englisch) haengt - abgebrochen.' -ForegroundColor Red }
$msgs = if (Test-Path "$enSetupShots\gui-messages.txt") { Get-Content "$enSetupShots\gui-messages.txt" -Raw } else { '' }
Assert 'Setup englisch: alle 7 Schritte fotografiert' { @(Get-ChildItem $enSetupShots -Filter 'setup-*.png').Count -eq 7 }
Assert 'Setup englisch: Installation erfolgreich' { $msgs -match 'INSTALLSTATE Done' }
Assert 'Setup englisch: keine Fehler in der Oberflaeche' { $msgs -notmatch 'ERROR' }
Assert 'Setup englisch: Sprache en, englische Verknuepfung' { (Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy').Language -eq 'en' -and (Test-Path (Join-Path $toolsDir 'WePrintEasy Printer Management.lnk')) }
Remove-Item "$enSetupShots\gui-messages.txt", "$enSetupShots\setup-install.log" -ErrorAction SilentlyContinue
& (Join-Path $root 'Uninstall-WePrintEasy.ps1') -RemoveConfig -RemoveClientDefaultPrinterPolicy -Confirm:$false *>&1 | Out-Null
Assert 'Setup englisch: wieder deinstalliert' { -not (Test-Path 'HKLM:\SOFTWARE\WePrintEasy') }

# Danach auf Deutsch (Bildschirmfotos fuer docs/screenshots)
$setupShots = Join-Path $OutDir 'screenshots'
New-Item -ItemType Directory -Path $setupShots -Force | Out-Null
$sp = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$root\Setup-WePrintEasy.ps1`"", '-PrintServer', $server, '-Language', 'de', '-ScreenshotDir', "`"$setupShots`"") -PassThru
if (-not $sp.WaitForExit(600000)) { Stop-Process -Id $sp.Id -Force; Write-Host '  Setup haengt - abgebrochen.' -ForegroundColor Red }
$msgs = if (Test-Path "$setupShots\gui-messages.txt") { Get-Content "$setupShots\gui-messages.txt" -Raw } else { '' }
Write-Host '    GUI-Meldungen:'; ($msgs -split "`n") | ForEach-Object { if ($_) { Write-Host "    | $_" } }
if (Test-Path "$setupShots\setup-install.log") { Write-Host '    Installationsprotokoll (Setup):'; Get-Content "$setupShots\setup-install.log" | ForEach-Object { Write-Host "    | $_" } }
Assert 'Setup: alle 7 Schritte fotografiert' { @(Get-ChildItem $setupShots -Filter 'setup-*.png').Count -eq 7 }
Assert 'Setup: Installation erfolgreich' { $msgs -match 'INSTALLSTATE Done' }
Assert 'Setup: keine Fehler in der Oberflaeche' { $msgs -notmatch 'ERROR' }
Assert 'Setup: Aufgabe installiert' { [bool](Get-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent' -ErrorAction SilentlyContinue) }
Assert 'Setup: RDS-Richtlinie gesetzt' { (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -ErrorAction SilentlyContinue).fForceClientLptDef -eq 0 }
$script:cfgPath = Get-WpeConfigPath
$cfg = Read-WpeConfig -Path $cfgPath
Assert 'Setup: 70 Drucker (lokaler Treiber vorhanden) vorausgewaehlt und uebernommen' { @($cfg.Printers | Where-Object { $_.ShareName -like 'WPE-Test-*' }).Count -eq 70 }
Assert 'Setup: Einstellungen gespeichert' { $cfg.Settings.DefaultPrintServer -eq $server -and $cfg.Settings.EnforceDuringSession -eq $true }
Assert 'Setup: Sprache Deutsch in Konfiguration und Registry' { $cfg.Settings.Language -eq 'de' -and (Get-ItemProperty 'HKLM:\SOFTWARE\WePrintEasy').Language -eq 'de' }
Assert 'Setup: deutsche Verknuepfung, keine englische' { (Test-Path (Join-Path $toolsDir 'WePrintEasy Druckerverwaltung.lnk')) -and -not (Test-Path (Join-Path $toolsDir 'WePrintEasy Printer Management.lnk')) }

# =============================================================================
}
Invoke-Section '6. Verwaltungsprogramm (alle Ansichten)' {
Set-WpeAssignment -Type User -Name $env:USERNAME -DisplayName 'Max Mustermann (Test)' -Printer "\\$server\WPE-Test-12" -Comment 'Buero 2.14' | Out-Null
Set-WpeAssignment -Type Group -Name 'Users' -Sid 'S-1-5-32-545' -DisplayName 'Alle Mitarbeiter' -Printer "\\$server\WPE-Test-1" -Priority 100 -Comment 'Fallback Flur' | Out-Null
Set-WpeAssignment -Type Group -Name 'Administrators' -Sid 'S-1-5-32-544' -DisplayName 'IT-Abteilung' -Printer "\\$server\WPE-Test-30" -Priority 10 | Out-Null
Set-WpeAssignment -Type Group -Name 'Remote Desktop Users' -Sid 'S-1-5-32-555' -DisplayName 'Buchhaltung' -Printer "\\$server\WPE-Test-44" -Priority 20 -Comment '1. OG' | Out-Null
[void](Invoke-Agent -Once)
$adminShots = Join-Path $OutDir 'screenshots'
$ap = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$installDir\WePrintEasy-Admin.ps1`"", '-ScreenshotDir', "`"$adminShots`"") -PassThru
if (-not $ap.WaitForExit(300000)) { Stop-Process -Id $ap.Id -Force; Write-Host '  Verwaltung haengt - abgebrochen.' -ForegroundColor Red }
$msgs = if (Test-Path "$adminShots\gui-messages.txt") { Get-Content "$adminShots\gui-messages.txt" -Raw } else { '' }
Write-Host '    GUI-Meldungen:'; ($msgs -split "`n") | Where-Object { $_ -match 'admin|ERROR|MESSAGE' } | ForEach-Object { Write-Host "    | $_" }
$expected = 'admin-1-zuweisungen', 'admin-2-zuweisung-bearbeiten', 'admin-2b-zuweisung-neu', 'admin-3-druckerliste', 'admin-5-druckerliste-import', 'admin-4-benutzer-pruefen', 'admin-6-einrichtung', 'admin-7-einstellungen', 'admin-8-anleitung', 'admin-9-erzwingen', 'admin-10-info'
foreach ($e in $expected) { Assert "Verwaltung: Ansicht $e" { Test-Path (Join-Path $adminShots "$e.png") } }
Assert 'Verwaltung: keine Fehler in der Oberflaeche' { $msgs -notmatch 'ERROR' }

# Dieselben Ansichten auf Englisch (Bildschirmfotos fuer docs/screenshots/en, zusammen mit dem englischen Setup)
$enShots = Join-Path $OutDir 'screenshots-en'
New-Item -ItemType Directory -Path $enShots -Force | Out-Null
$ap = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$installDir\WePrintEasy-Admin.ps1`"", '-Language', 'en', '-ScreenshotDir', "`"$enShots`"") -PassThru
if (-not $ap.WaitForExit(300000)) { Stop-Process -Id $ap.Id -Force; Write-Host '  Verwaltung (englisch) haengt - abgebrochen.' -ForegroundColor Red }
$msgs = if (Test-Path "$enShots\gui-messages.txt") { Get-Content "$enShots\gui-messages.txt" -Raw } else { '' }
Assert 'Verwaltung englisch: alle Ansichten' { @($expected | Where-Object { Test-Path (Join-Path $enShots "$_.png") }).Count -eq $expected.Count }
Assert 'Verwaltung englisch: keine Fehler in der Oberflaeche' { $msgs -notmatch 'ERROR' }

# =============================================================================
}
Invoke-Section 'Aufraeumen' {
& (Join-Path $root 'Uninstall-WePrintEasy.ps1') -RemoveConfig -RemoveClientDefaultPrinterPolicy -Confirm:$false *>&1 | Out-Null
Get-Printer -Name "\\$server\WPE-Test-*" -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue

}

Write-Host ''
Write-Host "Integrationstests: $script:Passed bestanden, $script:Failed fehlgeschlagen" -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
"$script:Passed bestanden, $script:Failed fehlgeschlagen" | Out-File (Join-Path $OutDir 'summary.txt') -Encoding utf8
if ($script:Failed) { exit 1 }
