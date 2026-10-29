<#
    Einfache Tests fuer die plattformunabhaengige Logik des Moduls
    (Konfiguration, Zuweisungen, Aufloesung, Druckernamen-Vergleich).
    Aufruf:  powershell -File .\tests\Run-Tests.ps1
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\WePrintEasy.psm1') -Force
# Feste Sprache, unabhaengig von einer evtl. Installation auf diesem Rechner
Set-WpeLanguage en

$script:Failed = 0
$script:Passed = 0
function Assert {
    param([string]$Name, [scriptblock]$Condition)
    try { $ok = [bool](& $Condition) } catch { $ok = $false; $err = $_.Exception.Message }
    if ($ok) { $script:Passed++; Write-Host "  [OK]   $Name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  [FAIL] $Name $err" -ForegroundColor Red }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("wpe-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$cfgPath = Join-Path $tmp 'config.json'

try {
    Write-Host 'Konfiguration'
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'Fehlende Datei liefert Standardwerte' { $c.Settings.LogonPhaseSeconds -eq 120 -and $c.Assignments.Count -eq 0 }

    Set-Content -LiteralPath $cfgPath -Value '' -Encoding UTF8
    Assert 'Leere Datei liefert Standardwerte' { (Read-WpeConfig -Path $cfgPath).Settings.EnforceDuringSession -eq $true }

    Set-Content -LiteralPath $cfgPath -Value '{ "Settings": { "EnforceIntervalSeconds": 60 }, "Assignments": [ { "Type": "User", "Name": "DOM\\max", "Printer": "\\\\srv\\HP" }, { "Type": "Bogus", "Name": "x", "Printer": "y" } ] }' -Encoding UTF8
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'Teilweise Settings werden ergaenzt' { $c.Settings.EnforceIntervalSeconds -eq 60 -and $c.Settings.LogonPhaseSeconds -eq 120 }
    Assert 'Ungueltige Zuweisungen werden verworfen' { $c.Assignments.Count -eq 1 }
    Assert 'Domaenenpraefix wird entfernt' { $c.Assignments[0].Name -eq 'max' }
    Assert 'Einzelne Zuweisung ohne Prioritaet bekommt 100' { $c.Assignments[0].Priority -eq 100 }

    Set-Content -LiteralPath $cfgPath -Value '{ kaputt' -Encoding UTF8
    Assert 'Ungueltiges JSON wirft Fehler' { try { Read-WpeConfig -Path $cfgPath | Out-Null; $false } catch { $_.Exception.Message -like '*not valid JSON*' } }

    # Von Hand bearbeitete Datei mit falschen Typen: lesbar bleiben, Standard verwenden, Problem melden
    Set-Content -LiteralPath $cfgPath -Value '{ "Settings": { "LogonPhaseSeconds": "abc", "EnforceIntervalSeconds": "45", "EnforceDurationMinutes": -5, "EnforceDuringSession": "false", "ConnectNetworkPrinters": 0, "SetLegacyDefaultPrinterMode": "vielleicht" }, "Assignments": [ { "Type": "Group", "Name": "G1", "Printer": "P", "Priority": "hoch" }, { "Type": "Group", "Name": "G2", "Printer": "P", "Priority": "20" } ] }' -Encoding UTF8
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'Ungueltige Zahl ergibt Standardwert' { $c.Settings.LogonPhaseSeconds -eq 120 -and $c.Settings.LogonPhaseSeconds -is [int] }
    Assert 'Zahl als Text wird uebernommen' { $c.Settings.EnforceIntervalSeconds -eq 45 -and $c.Settings.EnforceIntervalSeconds -is [int] }
    Assert 'Negative Zahl ergibt Standardwert' { $c.Settings.EnforceDurationMinutes -eq 0 }
    Assert '"false" als Text ist $false (nicht $true)' { $c.Settings.EnforceDuringSession -eq $false }
    Assert '0 als Ja/Nein ist $false' { $c.Settings.ConnectNetworkPrinters -eq $false }
    Assert 'Ungueltiges Ja/Nein ergibt Standardwert' { $c.Settings.SetLegacyDefaultPrinterMode -eq $true }
    Assert 'Ungueltige Prioritaet: Zuweisung bleibt mit 100' { $c.Assignments.Count -eq 2 -and ($c.Assignments | Where-Object Name -eq 'G1').Priority -eq 100 -and ($c.Assignments | Where-Object Name -eq 'G2').Priority -eq 20 }
    Assert 'Ersetzte Werte werden gemeldet' { $c.Problems.Count -eq 4 -and ($c.Problems -join ' ') -like "*LogonPhaseSeconds*'abc'*" -and ($c.Problems -join ' ') -like "*'G1'*" }
    Assert 'Gueltige Datei meldet nichts' { (Read-WpeConfig -Path (Join-Path $tmp 'fehlt.json')).Problems.Count -eq 0 }
    Set-Content -LiteralPath (Join-Path $tmp 'quelle.json') -Value '{ "Settings": { "UserChoicePrinterSource": "catalog" } }' -Encoding UTF8
    Assert 'Druckerwahl-Quelle: Schreibweise wird vereinheitlicht' { (Read-WpeConfig -Path (Join-Path $tmp 'quelle.json')).Settings.UserChoicePrinterSource -ceq 'Catalog' }
    Set-Content -LiteralPath (Join-Path $tmp 'quelle.json') -Value '{ "Settings": { "UserChoicePrinterSource": "Alle" } }' -Encoding UTF8
    Assert 'Druckerwahl-Quelle: unbekannter Wert ergibt Standard und wird gemeldet' { $q = Read-WpeConfig -Path (Join-Path $tmp 'quelle.json'); $q.Settings.UserChoicePrinterSource -eq 'Both' -and ($q.Problems -join ' ') -like "*UserChoicePrinterSource*'Alle'*" }
    Assert 'Agent-Wartezeit mit ersetzten Werten' { (Get-WpeAgentSleepSeconds -Settings $c.Settings -ElapsedSeconds 500) -eq -1 }
    Save-WpeConfig -Config $c -Path $cfgPath -Confirm:$false
    Assert 'Problems wird nicht gespeichert' { -not ((Get-Content -LiteralPath $cfgPath -Raw) -match 'Problems') -and (Read-WpeConfig -Path $cfgPath).Problems.Count -eq 0 }
    Remove-Item -LiteralPath $cfgPath, "$cfgPath.bak" -ErrorAction SilentlyContinue

    Write-Host 'Zuweisungen'
    Set-WpeAssignment -Type User -Name 'mmuster' -Sid 'S-1-5-21-1-1-1-1001' -DisplayName 'Max Muster' -Printer '\\srv\HP-Buero' -ConfigPath $cfgPath | Out-Null
    Set-WpeAssignment -Type Group -Name 'Buchhaltung' -Sid 'S-1-5-21-1-1-1-2001' -Printer '\\srv\Kyocera-BH' -Priority 10 -ConfigPath $cfgPath | Out-Null
    Set-WpeAssignment -Type Group -Name 'Alle' -Sid 'S-1-5-21-1-1-1-2002' -Printer '\\srv\Flur' -Priority 50 -ConfigPath $cfgPath | Out-Null
    Assert 'Datei wird geschrieben (3 Zuweisungen)' { (Read-WpeConfig -Path $cfgPath).Assignments.Count -eq 3 }
    Assert 'JSON ist UTF-8 ohne BOM' { $b = [IO.File]::ReadAllBytes($cfgPath); -not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) }

    Set-WpeAssignment -Type User -Name 'DOM\mmuster' -Sid 'S-1-5-21-1-1-1-1001' -Printer '\\srv\HP-Neu' -ConfigPath $cfgPath | Out-Null
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'Aktualisieren ersetzt statt zu duplizieren' { @($c.Assignments | Where-Object Type -eq 'User').Count -eq 1 }
    Assert 'Neuer Drucker uebernommen' { ($c.Assignments | Where-Object Type -eq 'User').Printer -eq '\\srv\HP-Neu' }
    Assert 'Anzeigename bleibt beim Aktualisieren erhalten' { ($c.Assignments | Where-Object Type -eq 'User').DisplayName -eq 'Max Muster' }
    Assert 'Sicherungskopie .bak existiert' { Test-Path -LiteralPath "$cfgPath.bak" }
    Assert 'Keine temporaeren Dateien uebrig' { @(Get-ChildItem -LiteralPath $tmp -Filter '*.tmp').Count -eq 0 }
    Assert 'Get-WpeAssignment filtert nach Typ' { @(Get-WpeAssignment -Type Group -ConfigPath $cfgPath).Count -eq 2 }

    $csv = @"
Type;Name;Printer;Priority
User;anna;\\srv\Canon;
Group;Lager;\\srv\Lager;20
"@ | ConvertFrom-Csv -Delimiter ';'
    $csv | Set-WpeAssignment -ConfigPath $cfgPath -SkipSidLookup | Out-Null
    Assert 'Pipeline-/CSV-Import' { (Read-WpeConfig -Path $cfgPath).Assignments.Count -eq 5 }
    Assert 'Leere CSV-Prioritaet ergibt 100' { (Get-WpeAssignment -Name anna -ConfigPath $cfgPath).Priority -eq 100 }

    Set-WpeAssignment -Type Group -Name 'Buchhaltung' -Sid 'S-1-5-21-1-1-1-2001' -Printer '\\srv\Kyocera-Neu' -ConfigPath $cfgPath | Out-Null
    Assert 'Update ohne -Priority behaelt Prioritaet' { (Get-WpeAssignment -Name Buchhaltung -ConfigPath $cfgPath).Priority -eq 10 }

    Remove-WpeAssignment -Type User -Name 'anna' -ConfigPath $cfgPath
    Assert 'Entfernen' { (Read-WpeConfig -Path $cfgPath).Assignments.Count -eq 4 }

    Write-Host 'Aufloesung'
    $c = Read-WpeConfig -Path $cfgPath
    $r = Resolve-WpeAssignment -Config $c -UserSid 'S-1-5-21-1-1-1-1001' -UserName 'mmuster' -GroupSids @('S-1-5-21-1-1-1-2001')
    Assert 'Benutzerzuweisung geht vor Gruppe' { $r.Type -eq 'User' -and $r.Printer -eq '\\srv\HP-Neu' }
    $r = Resolve-WpeAssignment -Config $c -UserSid 'S-1-5-21-1-1-1-1009' -UserName 'other' -GroupSids @('S-1-5-21-1-1-1-2002', 's-1-5-21-1-1-1-2001')
    Assert 'Kleinste Gruppenprioritaet gewinnt (SID ohne Gross-/Kleinschreibung)' { $r.Name -eq 'Buchhaltung' }
    $r = Resolve-WpeAssignment -Config $c -UserSid 'S-1-5-21-1-1-1-1009' -UserName 'other' -GroupSids @()
    Assert 'Keine Zuweisung -> $null' { $null -eq $r }
    $r = Resolve-WpeAssignment -Config $c -UserSid 'S-1-5-21-9-9-9-9' -UserName 'mmuster' -GroupSids @()
    Assert 'SID hat Vorrang vor gleichem Namen (anderer Benutzer)' { $null -eq $r }
    [void]$c.Assignments.Add((New-WpeAssignmentObject -Type User -Name 'manuell' -Printer 'PDF'))
    $r = Resolve-WpeAssignment -Config $c -UserSid 'S-1-5-21-1-1-1-1010' -UserName 'manuell' -GroupSids @()
    Assert 'Zuweisung ohne SID greift per Anmeldename' { $r.Printer -eq 'PDF' }

    Write-Host 'Druckernamen'
    Assert 'Exakter Vergleich ohne Gross-/Kleinschreibung' { Test-WpePrinterMatch -Pattern '\\SRV\hp' -Name '\\srv\HP' }
    Assert 'Platzhalter fuer umgeleitete Drucker' { Test-WpePrinterMatch -Pattern 'HP LaserJet*(umgeleitet*' -Name 'HP LaserJet 400 (umgeleitet 3)' }
    Assert 'Kein Treffer bei anderem Namen' { -not (Test-WpePrinterMatch -Pattern 'Canon' -Name 'Canon 2') }
    Assert 'Klammern im Namen ohne Platzhalter' { Test-WpePrinterMatch -Pattern 'Drucker [EG]' -Name 'Drucker [EG]' }
    Assert 'Leerer Name ist kein Treffer' { -not (Test-WpePrinterMatch -Pattern 'X' -Name $null) }
    Assert 'Find-WpeInstalledPrinter' { (Find-WpeInstalledPrinter -Pattern 'Kyo*' -InstalledNames @('Microsoft Print to PDF', 'Kyocera (umgeleitet 2)')) -eq 'Kyocera (umgeleitet 2)' }
    Assert 'UNC-Pfad erkannt' { Test-WpeIsNetworkPrinterPath '\\srv\HP' }
    Assert 'Platzhalter ist kein UNC-Pfad' { -not (Test-WpeIsNetworkPrinterPath '\\srv\HP*') }
    Assert 'Lokaler Drucker ist kein UNC-Pfad' { -not (Test-WpeIsNetworkPrinterPath 'HP') }

    Write-Host 'Druckerliste (Katalog)'
    $remote = @(
        [pscustomobject]@{ Name = 'HP 1'; ShareName = 'HP-1'; Shared = $true; DriverName = 'HP Universal'; Location = '1. OG'; Comment = '' }
        [pscustomobject]@{ Name = 'Kyo'; ShareName = 'Kyo-BH'; Shared = $true; DriverName = 'Kyocera KX'; Location = ''; Comment = 'BH' }
        [pscustomobject]@{ Name = 'Intern'; ShareName = ''; Shared = $false; DriverName = 'X'; Location = ''; Comment = '' }
    )
    $cand = @(ConvertTo-WpePrintServerPrinter -Printers $remote -Server 'fs01' -LocalDrivers @('HP Universal'))
    Assert 'Nur freigegebene Drucker' { $cand.Count -eq 2 }
    Assert 'UNC-Pfad gebildet' { $cand[0].Path -eq '\\fs01\HP-1' }
    Assert 'Treiber lokal erkannt' { $cand[0].DriverInstalled -eq $true -and $cand[1].DriverInstalled -eq $false }
    Assert 'Ohne Treiberliste: unbekannt' { $null -eq @(ConvertTo-WpePrintServerPrinter -Printers $remote -Server 'fs01')[0].DriverInstalled }

    Set-WpePrinterCatalog -Printers $cand -ReplaceServer 'fs01' -ConfigPath $cfgPath
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'Katalog gespeichert' { $c.Printers.Count -eq 2 -and ($c.Printers | Where-Object Path -eq '\\fs01\HP-1').Location -eq '1. OG' }
    Assert 'Server/Freigabe abgeleitet' { $c.Printers[0].Server -eq 'fs01' -and $c.Printers[0].ShareName -eq 'HP-1' }
    Assert 'Zuweisungen bleiben beim Katalog-Import erhalten' { $c.Assignments.Count -eq 4 }
    Set-WpePrinterCatalog -Printers @('\\fs02\Lager') -ConfigPath $cfgPath
    Set-WpePrinterCatalog -Printers @($cand[0]) -ReplaceServer 'fs01' -ConfigPath $cfgPath
    $c = Read-WpeConfig -Path $cfgPath
    Assert 'ReplaceServer ersetzt nur Eintraege dieses Servers' { $c.Printers.Count -eq 2 -and @($c.Printers | Where-Object Server -eq 'fs02').Count -eq 1 }
    Set-WpePrinterCatalog -Printers @('\\fs02\Lager') -ConfigPath $cfgPath
    Assert 'Keine Duplikate' { (Read-WpeConfig -Path $cfgPath).Printers.Count -eq 2 }

    $many = 1..70 | ForEach-Object { [pscustomobject]@{ Name = "P$_"; ShareName = "Drucker-$_"; Shared = $true; DriverName = 'D'; Location = "Raum $_"; Comment = '' } }
    Set-WpePrinterCatalog -Printers @(ConvertTo-WpePrintServerPrinter -Printers $many -Server 'fs01' -LocalDrivers @('D')) -ReplaceServer 'fs01' -ConfigPath $cfgPath
    Assert '70 Drucker vom Fileserver' { @((Read-WpeConfig -Path $cfgPath).Printers | Where-Object Server -eq 'fs01').Count -eq 70 }

    Write-Host 'Druckerverbindungen (Freigabename / Druckername)'
    $conns = @(
        [pscustomobject]@{ Name = '\\fs01\HP LaserJet 2. OG'; Server = 'fs01.firma.local'; ShareName = 'HP-2OG' }
        [pscustomobject]@{ Name = '\\fs02\Kyocera'; Server = ''; ShareName = 'Kyo' }
    )
    Assert 'Kurzname: Domaene weg, IP-Adresse bleibt' { (ConvertTo-WpeShortHost '\\FS01.firma.local') -eq 'FS01' -and (ConvertTo-WpeShortHost '10.0.0.5') -eq '10.0.0.5' }
    Assert 'Verbindung ueber den Freigabenamen gefunden (Server mit/ohne Domaene)' { (Find-WpeConnectionByShare -Path '\\fs01\hp-2og' -Connections $conns) -eq '\\fs01\HP LaserJet 2. OG' -and (Find-WpeConnectionByShare -Path '\\fs01.firma.local\HP-2OG' -Connections $conns) -eq '\\fs01\HP LaserJet 2. OG' }
    Assert 'Server ohne Angabe: aus dem Verbindungsnamen' { (Find-WpeConnectionByShare -Path '\\fs02\Kyo' -Connections $conns) -eq '\\fs02\Kyocera' }
    Assert 'Gleiche Freigabe auf anderem Server passt nicht' { $null -eq (Find-WpeConnectionByShare -Path '\\fs03\HP-2OG' -Connections $conns) -and $null -eq (Find-WpeConnectionByShare -Path 'HP-2OG' -Connections $conns) }

    Write-Host 'Fenster der Druckerwahl: angebotene Drucker'
    $cat = @((New-WpeCatalogEntry -Path '\\fs01\HP-2OG' -Location '2. OG'), (New-WpeCatalogEntry -Path '\\fs01\Kyo-EG'), (New-WpeCatalogEntry -Path '\\fs01\Lager'), (New-WpeCatalogEntry -Path '\\fs01\Lager'))
    $inst = @('Microsoft Print to PDF', '\\fs01\HP LaserJet 2. OG', '\\fs01\Kyo-EG', 'Client (umgeleitet 3)')
    $both = @(Get-WpeChoicePrinterList -Source Both -Catalog $cat -InstalledNames $inst -Connections $conns)
    $hp = $both | Where-Object Path -eq '\\fs01\HP-2OG'
    Assert 'Beides: Druckerliste und Drucker der Sitzung, verbundene nur einmal' { $both.Count -eq 5 -and @($both | Where-Object Path).Count -eq 3 -and @($both | Where-Object { $_.Text -eq '\\fs01\HP LaserJet 2. OG' }).Count -eq 0 }
    Assert 'Verbundener Listendrucker: Name in der Sitzung, gespeichert wird die Freigabe' { $hp.Name -eq '\\fs01\HP LaserJet 2. OG' -and $hp.Value -eq '\\fs01\HP-2OG' -and $hp.Text -eq '\\fs01\HP-2OG  (2. OG)' }
    Assert 'Nicht verbundener Listendrucker: ohne Namen (wird bei Auswahl verbunden)' { ($both | Where-Object Path -eq '\\fs01\Lager').Name -eq '' }
    $sess = @(Get-WpeChoicePrinterList -Source Session -Catalog $cat -InstalledNames $inst -Connections $conns)
    Assert 'Nur Sitzung: alle Drucker der Sitzung, nichts aus der Liste' { $sess.Count -eq 4 -and @($sess | Where-Object Path).Count -eq 0 -and @($sess | Where-Object { $_.Value -ne $_.Name }).Count -eq 0 }
    $only = @(Get-WpeChoicePrinterList -Source Catalog -Catalog $cat -InstalledNames $inst -Connections $conns)
    Assert 'Nur Druckerliste: keine lokalen oder umgeleiteten Drucker' { $only.Count -eq 3 -and @($only | Where-Object { -not $_.Path }).Count -eq 0 }
    Assert 'Nur Druckerliste, Liste leer: kein Eintrag' { @(Get-WpeChoicePrinterList -Source Catalog -Catalog @() -InstalledNames $inst).Count -eq 0 }

    Write-Host 'Anmelde-Agent (simulierte Drucker)'
    $mod = Get-Module WePrintEasy
    # Windows-spezifische Funktionen im Modul durch Attrappen ersetzen
    & $mod {
        $script:FakeDefault = 'Client-Drucker (umgeleitet 2)'
        $script:FakeInstalled = @('Microsoft Print to PDF', 'Client-Drucker (umgeleitet 2)')
        $script:FakeConnectable = @('\\fs01\HP-1')
        # Freigabe -> Name, unter dem Windows die Verbindung fuehrt (Druckername auf dem Server)
        $script:FakeConnectAs = @{}
        $script:FakeConnections = @()
        $script:FakeCalls = New-Object System.Collections.ArrayList
        function script:Get-WpeDefaultPrinter { $script:FakeDefault }
        function script:Get-WpeInstalledPrinterNames { $script:FakeInstalled }
        function script:Set-WpeDefaultPrinter { param($Name, [switch]$Confirm) [void]$script:FakeCalls.Add("set:$Name"); if ($script:FakeInstalled -contains $Name) { $script:FakeDefault = $Name } }
        function script:Add-WpePrinterConnection {
            param($Name, [switch]$Confirm)
            [void]$script:FakeCalls.Add("connect:$Name")
            if ($script:FakeConnectable -notcontains $Name) { throw 'Zugriff verweigert' }
            $as = if ($script:FakeConnectAs.ContainsKey($Name)) { $script:FakeConnectAs[$Name] } else { $Name }
            $script:FakeInstalled += $as
            $script:FakeConnections += [pscustomobject]@{ Name = $as; Server = $Name.Split('\')[2]; ShareName = $Name.Split('\')[3] }
        }
        function script:Get-WpePrinterConnection { $script:FakeConnections }
        function script:Set-WpeLegacyDefaultPrinterMode { [void]$script:FakeCalls.Add('legacy'); $true }
        function script:Get-WpeAccountSid { param($Name) $null }
    }
    $agentCfg = Join-Path $tmp 'agent.json'
    Set-WpeAssignment -Type User -Name 'max' -Sid 'S-1-5-21-9-9-9-500' -Printer '\\fs01\HP-1' -ConfigPath $agentCfg | Out-Null
    # Der Agent uebernimmt die Sprache der Konfiguration (leer = Vorgabe dieses Rechners)
    $c = Read-WpeConfig -Path $agentCfg; $c.Settings.Language = 'en'; Save-WpeConfig -Config $c -Path $agentCfg
    $logLines = New-Object System.Collections.ArrayList
    $state = New-WpeAgentState -ConfigPath $agentCfg -UserSid 'S-1-5-21-9-9-9-500' -UserName 'max' -GroupSids @() -Log { param($m, $l) [void]$logLines.Add("[$l] $m") }
    Update-WpeAgentConfig -State $state
    Assert 'Agent findet Vorgabe' { $state.Target.Printer -eq '\\fs01\HP-1' }
    $r = Invoke-WpeAgentCheck -State $state
    Assert 'Fehlender Netzwerkdrucker wird verbunden und gesetzt' { $r -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq '\\fs01\HP-1' }
    Assert 'Legacy-Modus wurde gesetzt' { (& $mod { $script:FakeCalls }) -contains 'legacy' }
    Assert 'Protokoll enthaelt vorher/nachher' { ($logLines -join "`n") -match "set: '\\\\fs01\\HP-1' \(previously: 'Client-Drucker \(umgeleitet 2\)'\)" }
    $r = Invoke-WpeAgentCheck -State $state
    Assert 'Zweite Pruefung: alles OK, nichts gesetzt' { $r -eq 'Ok' -and @((& $mod { $script:FakeCalls }) | Where-Object { $_ -like 'set:*' }).Count -eq 1 }

    & $mod { $script:FakeDefault = 'Client-Drucker (umgeleitet 2)' }   # RDP-Umleitung verstellt den Drucker
    Assert 'Verstellter Drucker wird zurueckgesetzt' { (Invoke-WpeAgentCheck -State $state) -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq '\\fs01\HP-1' }

    Start-Sleep -Milliseconds 20
    Set-WpeAssignment -Type User -Name 'max' -Sid 'S-1-5-21-9-9-9-500' -Printer 'Client-Drucker*(umgeleitet*' -ConfigPath $agentCfg | Out-Null
    Update-WpeAgentConfig -State $state
    Assert 'Konfigurationsaenderung wird live uebernommen' { $state.Target.Printer -eq 'Client-Drucker*(umgeleitet*' }
    Assert 'Platzhalter-Vorgabe waehlt umgeleiteten Drucker' { (Invoke-WpeAgentCheck -State $state) -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq 'Client-Drucker (umgeleitet 2)' }

    Set-WpeAssignment -Type User -Name 'max' -Sid 'S-1-5-21-9-9-9-500' -Printer '\\fs01\Gibtsnicht' -ConfigPath $agentCfg | Out-Null
    Update-WpeAgentConfig -State $state
    $logLines.Clear()
    $r1 = Invoke-WpeAgentCheck -State $state
    $r2 = Invoke-WpeAgentCheck -State $state
    Assert 'Nicht verbindbarer Drucker: Failed' { $r1 -eq 'Failed' }
    Assert 'Kein zweiter Verbindungsversuch innerhalb 5 Min.' { $r2 -eq 'Missing' -and @((& $mod { $script:FakeCalls }) | Where-Object { $_ -eq 'connect:\\fs01\Gibtsnicht' }).Count -eq 1 }
    Assert 'Warnungen werden nicht wiederholt protokolliert' { @($logLines | Where-Object { $_ -like '`[WARN`]*' }).Count -eq 2 }

    # Windows fuehrt die Verbindung unter dem Druckernamen des Servers, nicht unter dem Freigabenamen
    & $mod { $script:FakeConnectable += '\\fs01\HP-2OG'; $script:FakeConnectAs['\\fs01\HP-2OG'] = '\\fs01\HP LaserJet 2. OG' }
    Set-WpeAssignment -Type User -Name 'max' -Sid 'S-1-5-21-9-9-9-500' -Printer '\\fs01\HP-2OG' -ConfigPath $agentCfg | Out-Null
    Update-WpeAgentConfig -State $state
    $logLines.Clear()
    $r1 = Invoke-WpeAgentCheck -State $state
    Assert 'Freigabe mit anderem Druckernamen: verbunden und gesetzt' { $r1 -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq '\\fs01\HP LaserJet 2. OG' }
    Assert 'Protokoll nennt den Namen in der Sitzung' { ($logLines -join "`n") -like '*HP LaserJet 2. OG*' -and @($logLines | Where-Object { $_ -like '`[WARN`]*' }).Count -eq 0 }
    $sets = @((& $mod { $script:FakeCalls }) | Where-Object { $_ -like 'set:*' }).Count
    Assert 'Naechste Pruefung: OK, nicht erneut gesetzt' { (Invoke-WpeAgentCheck -State $state) -eq 'Ok' -and @((& $mod { $script:FakeCalls }) | Where-Object { $_ -like 'set:*' }).Count -eq $sets }
    & $mod { $script:FakeDefault = 'Microsoft Print to PDF' }
    Assert 'Verstellt: wieder auf den Druckernamen gesetzt, ohne neue Verbindung' { (Invoke-WpeAgentCheck -State $state) -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq '\\fs01\HP LaserJet 2. OG' -and @((& $mod { $script:FakeCalls }) | Where-Object { $_ -eq 'connect:\\fs01\HP-2OG' }).Count -eq 1 }
    $state5 = New-WpeAgentState -ConfigPath $agentCfg -UserSid 'S-1-5-21-9-9-9-500' -UserName 'max' -GroupSids @() -Log { param($m, $l) }
    Update-WpeAgentConfig -State $state5
    & $mod { $script:FakeDefault = 'Microsoft Print to PDF' }
    Assert 'Neue Sitzung, Verbindung besteht schon: ohne erneutes Verbinden gefunden' { (Invoke-WpeAgentCheck -State $state5) -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq '\\fs01\HP LaserJet 2. OG' -and @((& $mod { $script:FakeCalls }) | Where-Object { $_ -eq 'connect:\\fs01\HP-2OG' }).Count -eq 1 }

    $state2 = New-WpeAgentState -ConfigPath $agentCfg -UserSid 'S-1-5-21-9-9-9-777' -UserName 'anna' -GroupSids @() -Log { param($m, $l) }
    Update-WpeAgentConfig -State $state2
    Assert 'Benutzer ohne Zuweisung: NoTarget' { (Invoke-WpeAgentCheck -State $state2) -eq 'NoTarget' }
    $state3 = New-WpeAgentState -ConfigPath (Join-Path $tmp 'fehlt\x.json') -UserSid 'S-1' -UserName 'x' -Log { param($m, $l) }
    Update-WpeAgentConfig -State $state3
    Assert 'Fehlende Konfiguration: kein Absturz, Warnung' { $null -eq $state3.Config -and $state3.LastProblem -like '*not reachable*' }

    # Der Agent ruft Write-WpeAgentProblem in seinem catch-Block auf - ausserhalb des Moduls
    $problemLines = New-Object System.Collections.ArrayList
    $state4 = New-WpeAgentState -ConfigPath $agentCfg -UserSid 'S-1' -UserName 'x' -Log { param($m, $l) [void]$problemLines.Add("[$l] $m") }
    Assert 'Write-WpeAgentProblem ist exportiert (Agent-catch)' { Write-WpeAgentProblem $state4 'Fehler: Test'; Write-WpeAgentProblem $state4 'Fehler: Test'; $problemLines.Count -eq 1 -and $problemLines[0] -eq '[WARN] Fehler: Test' }

    Write-Host 'Druckerwahl durch Benutzer'
    Assert 'Einstellung AllowUserPrinterChoice: Standard aus' { (Read-WpeConfig -Path (Join-Path $tmp 'neu.json')).Settings.AllowUserPrinterChoice -eq $false }
    $p = ConvertTo-WpeChoicePattern 'HP LaserJet (umgeleitet 3)'
    Assert 'Umgeleiteter Drucker: Sitzungsnummer wird Platzhalter' { $p -eq 'HP LaserJet (umgeleitet *)' -and (Test-WpePrinterMatch $p 'HP LaserJet (umgeleitet 7)') -and -not (Test-WpePrinterMatch $p 'HP LaserJet 2 (umgeleitet 7)') }
    Assert 'Aeltere Schreibweise "in Sitzung N"' { Test-WpePrinterMatch (ConvertTo-WpeChoicePattern 'Canon (von PC01) in Sitzung 4') 'Canon (von PC01) in Sitzung 12' }
    $p = ConvertTo-WpeChoicePattern 'Drucker [EG] (redirected 2)'
    Assert 'Klammern im Namen werden maskiert' { (Test-WpePrinterMatch $p 'Drucker [EG] (redirected 5)') -and -not (Test-WpePrinterMatch $p 'Drucker E (redirected 5)') }
    Assert 'Netzwerk- und lokale Drucker bleiben unveraendert' { (ConvertTo-WpeChoicePattern '\\fs01\HP-1') -eq '\\fs01\HP-1' -and (ConvertTo-WpeChoicePattern 'Microsoft Print to PDF') -eq 'Microsoft Print to PDF' }

    $choiceCfg = Join-Path $tmp 'choice\config.json'
    $mySid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Set-WpeAssignment -Type User -Name 'ich' -Sid $mySid -DisplayName 'Ich selbst' -Printer '\\fs01\Admin-Vorgabe' -Comment 'Buero 1' -ConfigPath $choiceCfg -SkipSidLookup | Out-Null
    Set-WpeAssignment -Type Group -Name 'Alle' -Sid 'S-1-5-21-9-9-9-2002' -Printer '\\fs01\Flur' -ConfigPath $choiceCfg -SkipSidLookup | Out-Null
    Assert 'Speichern ohne Ordner choices: verstaendlicher Fehler' { try { Save-WpeUserChoice -PrinterName 'X' -ConfigPath $choiceCfg -Confirm:$false; $false } catch { $_.Exception.Message -like '*choices*' } }
    Assert 'Systempruefung: ausgeschaltet keine Pruefung des Ordners' { -not (@(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoice') }
    $c = Read-WpeConfig -Path $choiceCfg; $c.Settings.AllowUserPrinterChoice = $true; Save-WpeConfig -Config $c -Path $choiceCfg
    Assert 'Systempruefung: Ordner fehlt -> Fehler mit Behebung' { $r = @(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoice'; $r.Status -eq 'Error' -and $r.Fix -eq 'ChoiceFolder' }
    Initialize-WpeChoiceDirectory -ConfigPath $choiceCfg -Confirm:$false
    Initialize-WpeChoiceDirectory -ConfigPath $choiceCfg -Confirm:$false
    $choiceDir = Get-WpeChoiceDirectory $choiceCfg
    Assert 'Ordner choices neben der Konfiguration, Rechte gesetzt (auch zweimal)' { $choiceDir -eq (Join-Path $tmp 'choice\choices') -and (Test-WpeChoiceDirectory -ConfigPath $choiceCfg).Status -eq 'OK' }
    $acl = Get-Acl -LiteralPath $choiceDir
    Assert 'Benutzer duerfen nur anlegen, ERSTELLER-BESITZER aendert die eigene Datei' {
        $rules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
        @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-11' -and $_.InheritanceFlags -eq 'None' -and -not ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete) }).Count -eq 1 -and
        @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-0' -and $_.PropagationFlags -eq 'InheritOnly' }).Count -eq 1
    }

    $pattern = Save-WpeUserChoice -PrinterName 'Client-Drucker (umgeleitet 2)' -ConfigPath $choiceCfg -Confirm:$false
    $own = @(Read-WpeUserChoice -ConfigPath $choiceCfg -UserSid $mySid)
    Assert 'Eigene Wahl gespeichert und gelesen (als Platzhalter)' { $pattern -eq 'Client-Drucker (umgeleitet *)' -and $own.Count -eq 1 -and $own[0].Printer -eq $pattern -and $own[0].PrinterName -eq 'Client-Drucker (umgeleitet 2)' -and $own[0].Account -eq (Get-WpeCurrentAccount) }
    Assert 'Datei ist UTF-8 ohne BOM' { $b = [IO.File]::ReadAllBytes((Join-Path $choiceDir "$mySid.json")); -not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) }
    # Fremde Datei: Name mit anderer SID, Besitzer ist dieser Benutzer - darf nicht gelten
    $foreign = Join-Path $choiceDir 'S-1-5-21-9-9-9-666.json'
    [IO.File]::WriteAllText($foreign, '{ "Sid": "S-1-5-21-9-9-9-666", "Name": "opfer", "Printer": "\\\\boese\\Drucker" }')
    $fa = Get-Acl -LiteralPath $foreign; $fa.SetOwner((New-Object System.Security.Principal.SecurityIdentifier($mySid))); Set-Acl -LiteralPath $foreign -AclObject $fa
    [IO.File]::WriteAllText((Join-Path $choiceDir 'S-1-5-21-9-9-9-667.json'), '{ kaputt')
    $all = @(Read-WpeUserChoice -ConfigPath $choiceCfg)
    Assert 'Fremde und defekte Dateien werden nicht beachtet' { $all.Count -eq 1 -and $all[0].Sid -eq $mySid }
    Assert 'Systempruefung warnt vor fremder Datei' { $r = @(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoice'; $r.Status -eq 'Warning' -and $r.Detail -like '*S-1-5-21-9-9-9-666.json*' }
    Remove-Item -LiteralPath $foreign, (Join-Path $choiceDir 'S-1-5-21-9-9-9-667.json')
    Assert 'Systempruefung: Ordner in Ordnung' { $r = @(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoice'; $r.Status -eq 'OK' -and $r.Detail -like '*1*' }
    Assert 'Einstellung UserChoicePrinterSource: Standard beides' { (Read-WpeConfig -Path $choiceCfg).Settings.UserChoicePrinterSource -eq 'Both' -and -not (@(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoiceCatalog') }
    $c = Read-WpeConfig -Path $choiceCfg; $c.Settings.UserChoicePrinterSource = 'Catalog'; Save-WpeConfig -Config $c -Path $choiceCfg
    Assert 'Systempruefung: nur Druckerliste, aber Liste leer -> Warnung' { $r = @(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoiceCatalog'; $r.Status -eq 'Warning' }
    Set-WpePrinterCatalog -Printers @('\\fs01\HP-1') -ConfigPath $choiceCfg -Confirm:$false
    Assert 'Systempruefung: Druckerliste gefuellt -> keine Warnung' { -not (@(Get-WpeSystemStatus -ConfigPath $choiceCfg) | Where-Object Id -eq 'UserChoiceCatalog') -and (Read-WpeConfig -Path $choiceCfg).Settings.UserChoicePrinterSource -eq 'Catalog' }
    $c = Read-WpeConfig -Path $choiceCfg; $c.Settings.UserChoicePrinterSource = 'Both'; Save-WpeConfig -Config $c -Path $choiceCfg

    $eff = Read-WpeEffectiveConfig -Path $choiceCfg
    $mine = @($eff.Assignments | Where-Object { $_.Type -eq 'User' -and $_.Sid -eq $mySid })
    Assert 'Wahl ersetzt die Benutzerzuweisung (kein Doppel)' { $mine.Count -eq 1 -and $mine[0].Printer -eq $pattern -and $eff.Assignments.Count -eq 2 }
    Assert 'Ersetzte Zuweisung: Vermerk, vorheriger Drucker, Name/Anzeigename/Kommentar bleiben' { (Test-WpeChangedByUser $mine[0]) -and $mine[0].PreviousPrinter -eq '\\fs01\Admin-Vorgabe' -and $mine[0].Name -eq 'ich' -and $mine[0].DisplayName -eq 'Ich selbst' -and $mine[0].Comment -eq 'Buero 1' -and $mine[0].ModifiedBy -eq (Get-WpeCurrentAccount) }
    Assert 'Gruppenzuweisung unveraendert, ohne Vermerk' { -not (Test-WpeChangedByUser ($eff.Assignments | Where-Object Type -eq 'Group')) }
    Assert 'Die Datei config.json bleibt unveraendert' { (Read-WpeConfig -Path $choiceCfg).Assignments | Where-Object { $_.Sid -eq $mySid -and $_.Printer -eq '\\fs01\Admin-Vorgabe' } }
    Assert 'Aufloesung: Wahl schlaegt Benutzerzuweisung' { (Resolve-WpeAssignment -Config $eff -UserSid $mySid -UserName 'ich' -GroupSids @('S-1-5-21-9-9-9-2002')).Printer -eq $pattern }
    $nameOnly = Read-WpeConfig -Path $choiceCfg
    [void]$nameOnly.Assignments.Add((New-WpeAssignmentObject -Type User -Name 'ich' -Printer 'NurName'))
    Assert 'Aufloesung: Wahl schlaegt auch Zuweisung ohne SID' { (Resolve-WpeAssignment -Config (Merge-WpeUserChoice -Config $nameOnly -Choices $own) -UserSid $mySid -UserName 'ich' -GroupSids @()).Printer -eq $pattern }
    Assert 'Wahl ohne Zuweisung kommt als Benutzerzuweisung hinzu' { $m = Merge-WpeUserChoice -Config (Read-WpeConfig -Path (Join-Path $tmp 'leer.json')) -Choices $own; $m.Assignments.Count -eq 1 -and $m.Assignments[0].Name -eq $env:USERNAME -and $m.Assignments[0].PreviousPrinter -eq '' }
    Assert 'Get-WpeAssignment zeigt die Wahl' { (Get-WpeAssignment -Type User -ConfigPath $choiceCfg).Printer -eq $pattern }
    Assert '"Benutzer pruefen" fuer einen Benutzer (-UserSid)' { @((Read-WpeEffectiveConfig -Path $choiceCfg -UserSid 'S-1-5-21-9-9-9-1').Assignments | Where-Object { Test-WpeChangedByUser $_ }).Count -eq 0 }

    $agentChoiceLines = New-Object System.Collections.ArrayList
    $stateC = New-WpeAgentState -ConfigPath $choiceCfg -UserSid $mySid -UserName 'ich' -GroupSids @() -Log { param($m, $l) [void]$agentChoiceLines.Add($m) }
    Update-WpeAgentConfig -State $stateC
    Assert 'Agent: eigene Wahl ist die Vorgabe (Protokoll nennt sie)' { $stateC.Target.Printer -eq $pattern -and ($agentChoiceLines -join "`n") -like "*$(Get-WpeText 'Agent.ViaChoice')*" }
    & $mod { $script:FakeDefault = 'Microsoft Print to PDF' }
    Assert 'Agent setzt den gewaehlten umgeleiteten Drucker' { (Invoke-WpeAgentCheck -State $stateC) -eq 'Set' -and (& $mod { $script:FakeDefault }) -eq 'Client-Drucker (umgeleitet 2)' }
    Start-Sleep -Milliseconds 20
    [void](Save-WpeUserChoice -PrinterName 'Microsoft Print to PDF' -ConfigPath $choiceCfg -Confirm:$false)
    Update-WpeAgentConfig -State $stateC
    Assert 'Agent: neue Wahl wird live uebernommen' { $stateC.Target.Printer -eq 'Microsoft Print to PDF' }
    $stateC.ForceReload = $true
    $agentChoiceLines.Clear()
    Update-WpeAgentConfig -State $stateC
    Assert 'Agent: ForceReload liest neu, ohne die Vorgabe erneut zu protokollieren' { -not $stateC.ForceReload -and $agentChoiceLines.Count -eq 0 }
    $c = Read-WpeConfig -Path $choiceCfg; $c.Settings.AllowUserPrinterChoice = $false; Save-WpeConfig -Config $c -Path $choiceCfg
    Update-WpeAgentConfig -State $stateC
    Assert 'Ausgeschaltet: wieder die Vorgabe des Administrators' { $stateC.Target.Printer -eq '\\fs01\Admin-Vorgabe' -and (Test-Path -LiteralPath (Join-Path $choiceDir "$mySid.json")) }
    $c.Settings.AllowUserPrinterChoice = $true; Save-WpeConfig -Config $c -Path $choiceCfg

    Set-WpeAssignment -Type User -Name 'ich' -Sid $mySid -Printer '\\fs01\Neu-vom-Admin' -ConfigPath $choiceCfg -SkipSidLookup | Out-Null
    Assert 'Aenderung durch den Administrator ersetzt die Wahl (Datei entfernt)' { -not (Test-Path -LiteralPath (Join-Path $choiceDir "$mySid.json")) -and (Get-WpeAssignment -Type User -ConfigPath $choiceCfg).Printer -eq '\\fs01\Neu-vom-Admin' }
    [void](Save-WpeUserChoice -PrinterName 'Microsoft Print to PDF' -ConfigPath $choiceCfg -Confirm:$false)
    Remove-WpeAssignment -Type User -Name 'ich' -Sid $mySid -ConfigPath $choiceCfg -Confirm:$false
    Assert 'Entfernen loescht Zuweisung und Wahl' { -not (Test-Path -LiteralPath (Join-Path $choiceDir "$mySid.json")) -and @(Get-WpeAssignment -Type User -ConfigPath $choiceCfg).Count -eq 0 }
    [void](Save-WpeUserChoice -PrinterName 'Microsoft Print to PDF' -ConfigPath $choiceCfg -Confirm:$false)
    $warn = $null
    Remove-WpeAssignment -Type User -Name 'ich' -Sid $mySid -ConfigPath $choiceCfg -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue
    Assert 'Entfernen einer reinen Wahl (ohne Zuweisung): ohne Warnung' { -not $warn -and -not (Test-Path -LiteralPath (Join-Path $choiceDir "$mySid.json")) }

    Write-Host 'Agent-Zeitsteuerung'
    $s = [pscustomobject](Get-WpeDefaultSettings)
    Assert 'Anmeldephase: alle 3 s' { (Get-WpeAgentSleepSeconds -Settings $s -ElapsedSeconds 10) -eq 3 }
    Assert 'Sitzungsphase: Intervall' { (Get-WpeAgentSleepSeconds -Settings $s -ElapsedSeconds 500) -eq 30 }
    $s.EnforceDuringSession = $false
    Assert 'Ohne Ueberwachung: Ende nach Anmeldephase' { (Get-WpeAgentSleepSeconds -Settings $s -ElapsedSeconds 500) -eq -1 }
    $s.EnforceDuringSession = $true; $s.EnforceDurationMinutes = 5
    Assert 'Ueberwachungsdauer begrenzt' { (Get-WpeAgentSleepSeconds -Settings $s -ElapsedSeconds 301) -eq -1 }
    $s.EnforceDurationMinutes = 0; $s.EnforceIntervalSeconds = 1
    Assert 'Mindestintervall 5 s' { (Get-WpeAgentSleepSeconds -Settings $s -ElapsedSeconds 500) -eq 5 }
    Import-Module (Join-Path $PSScriptRoot '..\src\WePrintEasy.psm1') -Force   # Attrappen verwerfen
    Set-WpeLanguage en

    Write-Host 'Hilfsfunktionen'
    Assert 'LDAP-Maskierung' { (ConvertTo-WpeLdapFilterValue 'a*(b)\c') -eq 'a\2a\28b\29\5cc' }
    Assert 'UPN wird zu Anmeldename' { (ConvertTo-WpeAccountName 'max@firma.local') -eq 'max' }
    Assert 'Tippfehler im Servernamen: Abstand 1 (srvts01 / SRVXTS01)' { (Measure-WpeEditDistance 'srvts01' 'SRVXTS01') -eq 1 }
    Assert 'Abstand: gleich = 0, leer = Laenge' { (Measure-WpeEditDistance 'TS01' 'ts01') -eq 0 -and (Measure-WpeEditDistance '' 'abc') -eq 3 }

    Write-Host 'Info / Fehler melden'
    $about = Get-WpeAboutInfo
    Assert 'Version im Format x.y.z' { $about.Version -match '^\d+\.\d+\.\d+$' }
    Assert 'Projekt-Link auf GitHub' { $about.ProjectUrl -like 'https://github.com/*' -and $about.IssuesUrl -eq "$($about.ProjectUrl)/issues" }
    Assert 'Lizenzdatei passt zur Angabe im Programm' { $about.License -eq 'MIT' -and (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\LICENSE') -TotalCount 1) -eq 'MIT License' }
    $sys = Get-WpeSystemInfo -ConfigPath $cfgPath
    $sysText = ($sys.Keys | ForEach-Object { "$_ $($sys[$_])" }) -join "`n"
    $names = @($env:COMPUTERNAME, $env:USERNAME, $env:USERDOMAIN) | Where-Object { $_ -and $_.Length -ge 3 }
    Assert 'Systeminfo: Version und Betriebssystem enthalten' { $sys['WePrintEasy'] -eq $about.Version -and $sys[(Get-WpeText 'SysInfo.OS')] }
    Assert 'Systeminfo: keine Rechner-, Benutzer- oder Domaenennamen' { @($names | Where-Object { $sysText -match [regex]::Escape($_) }).Count -eq 0 }
    $issue = Get-WpeIssueUrl -SystemInfo $sys
    Assert 'Issue-Link vorausgefuellt' { $issue.StartsWith("$($about.ProjectUrl)/issues/new?title=") -and [Uri]::UnescapeDataString($issue) -match 'System information' }
    Assert 'Issue-Link: keine Namen, nicht zu lang' { @($names | Where-Object { [Uri]::UnescapeDataString($issue) -match [regex]::Escape($_) }).Count -eq 0 -and $issue.Length -lt 8000 }

    Write-Host 'Sprache'
    $mod = Get-Module WePrintEasy
    $tables = @{}
    foreach ($l in (Get-WpeSupportedLanguage).Keys) { $tables[$l] = & $mod { param($x) Read-WpeStringTable $x } $l }
    Assert 'Englisch und Deutsch verfuegbar, Englisch zuerst' { @((Get-WpeSupportedLanguage).Keys) -join ',' -eq 'en,de' }
    Assert 'Alle Sprachen haben dieselben Schluessel' { @(Compare-Object @($tables['en'].Keys) @($tables['de'].Keys)).Count -eq 0 -and $tables['en'].Count -gt 400 }
    $placeholders = { param($v) (@(foreach ($l in @($v)) { [regex]::Matches([string]$l, '\{(\d+)') | ForEach-Object { $_.Groups[1].Value } }) | Sort-Object -Unique) -join ',' }
    Assert 'Platzhalter {0}, {1}, ... in allen Sprachen gleich' { @($tables['en'].Keys | Where-Object { (& $placeholders $tables['en'][$_]) -ne (& $placeholders $tables['de'][$_]) }).Count -eq 0 }
    $used = @(Get-ChildItem (Join-Path $PSScriptRoot '..\*'), (Join-Path $PSScriptRoot '..\src\*') -File -Include '*.ps1', '*.psm1' |
            Select-String -Pattern "Get-WpeText\s+'([^'$]+)'" -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Assert "Alle im Code verwendeten Texte sind definiert ($($used.Count))" { $used.Count -gt 300 -and @($used | Where-Object { -not $tables['en'].ContainsKey($_) }).Count -eq 0 }
    Assert 'Standardsprache Englisch' { (Get-WpeLanguage) -eq 'en' -and (Get-WpeText 'Common.Cancel') -eq 'Cancel' }
    Assert 'Platzhalter werden ersetzt (auch 0)' { (Get-WpeText 'Agent.Set' 'A' 'B') -eq "Default printer set: 'A' (previously: 'B')" -and (Get-WpeText 'Check.Assignments.Count' 0 0) -eq '0 users, 0 groups' }
    Assert 'Mehrzeilige Texte bleiben Arrays' { @(Get-WpeText 'Guide.Intro').Count -ge 2 -and @(Get-WpeText 'Setup.DoneText' 'X')[1] -like '*"X"*' }
    Assert 'Unbekannter Schluessel liefert den Schluessel' { (Get-WpeText 'Gibt.Es.Nicht') -eq 'Gibt.Es.Nicht' }
    Set-WpeLanguage de
    Assert 'Umstellen auf Deutsch' { (Get-WpeLanguage) -eq 'de' -and (Get-WpeText 'Common.Cancel') -eq 'Abbrechen' -and (Get-WpeText 'Agent.Set' 'A' 'B') -eq "Standarddrucker gesetzt: 'A' (vorher: 'B')" }
    Assert 'Umlaute korrekt gelesen (UTF-8)' { (Get-WpeText 'Common.Close') -eq "Schlie$([char]0xDF)en" }
    Set-WpeLanguage 'xx'
    Assert 'Unbekannte Sprache: Vorgabe des Servers bzw. Englisch' { (Get-WpeLanguage) -in (Get-WpeSupportedLanguage).Keys }
    Set-WpeLanguage en
    Assert 'Verknuepfung je Sprache, -All liefert alle' { @(Get-WpeShortcutPath -All | Sort-Object -Unique).Count -eq 2 -and (Get-WpeShortcutPath) -like '*\WePrintEasy Printer Management.lnk' }
    Assert 'Einstellung Language: Standard leer (= Vorgabe des Servers)' { (Get-WpeDefaultSettings).Contains('Language') -and (Read-WpeConfig -Path (Join-Path $tmp 'neu.json')).Settings.Language -eq '' }
    $langCfg = Join-Path $tmp 'lang.json'
    $c = Read-WpeConfig -Path $langCfg
    $c.Settings.Language = 'de'
    Save-WpeConfig -Config $c -Path $langCfg
    Assert 'Initialize-WpeLanguage liest die Sprache aus der Konfiguration' { Initialize-WpeLanguage -ConfigPath $langCfg; (Get-WpeLanguage) -eq 'de' }
    Set-WpeLanguage en
    $langLines = New-Object System.Collections.ArrayList
    $langState = New-WpeAgentState -ConfigPath $langCfg -UserSid 'S-1' -UserName 'x' -Log { param($m, $l) [void]$langLines.Add($m) }
    Update-WpeAgentConfig -State $langState
    Assert 'Agent protokolliert in der eingestellten Sprache' { (Get-WpeLanguage) -eq 'de' -and $langLines[0] -like 'Keine Druckerzuweisung*' }
    Set-WpeLanguage en

    Write-Host 'Update-Pruefung'
    Assert 'Versionen numerisch: 1.0.10 ist neuer als 1.0.9' { Test-WpeNewerVersion -Latest '1.0.10' -Current '1.0.9' }
    Assert 'Gleiche Version ist kein Update' { -not (Test-WpeNewerVersion -Latest '1.0.4' -Current '1.0.4') }
    Assert 'Aeltere Version ist kein Update' { -not (Test-WpeNewerVersion -Latest '1.0.3' -Current '1.0.4') }
    Assert 'Ungueltige Version ist kein Update' { -not (Test-WpeNewerVersion -Latest 'neu' -Current '1.0.4') }
    $latest = { param($v, $u, $s = ('a' * 64), $n = 2553552) ConvertTo-Json @{ version = $v; released = '2026-10-10T12:28:22Z'; url = $u; sha256 = $s; size = $n } }
    $ok = ConvertTo-WpeLatestRelease -Json (& $latest '1.0.4' 'https://dl.weprinteasy.com/WePrintEasy-Setup-1.0.4.exe')
    Assert 'latest.json: Version, Datei, Groesse und Datum' { $ok.Version -eq [version]'1.0.4' -and $ok.FileName -eq 'WePrintEasy-Setup-1.0.4.exe' -and $ok.Size -eq 2553552 -and $ok.Released.Year -eq 2026 }
    $rejected = {
        param($json)
        try { [void](ConvertTo-WpeLatestRelease -Json $json); $false } catch { $true }
    }
    Assert 'latest.json: Dateiname mit anderer Version wird abgelehnt' { & $rejected (& $latest '1.0.5' 'https://dl.weprinteasy.com/WePrintEasy-Setup-1.0.4.exe') }
    Assert 'latest.json: http statt https wird abgelehnt' { & $rejected (& $latest '1.0.4' 'http://dl.weprinteasy.com/WePrintEasy-Setup-1.0.4.exe') }
    Assert 'latest.json: fremder Server wird abgelehnt' { & $rejected (& $latest '1.0.4' 'https://example.com/WePrintEasy-Setup-1.0.4.exe') }
    Assert 'latest.json: ungueltige Pruefsumme wird abgelehnt' { & $rejected (& $latest '1.0.4' 'https://dl.weprinteasy.com/WePrintEasy-Setup-1.0.4.exe' 'xyz') }
    Assert 'latest.json: fehlende Version wird abgelehnt' { & $rejected '{ "url": "https://dl.weprinteasy.com/WePrintEasy-Setup-1.0.4.exe" }' }
    $dl = Join-Path $tmp 'WePrintEasy-Setup-9.9.9.exe'
    [IO.File]::WriteAllBytes($dl, [byte[]](1..200))
    $dlHash = (Get-FileHash -LiteralPath $dl -Algorithm SHA256).Hash
    Assert 'Download mit passender Pruefsumme wird angenommen' { Test-WpeDownload -Path $dl -Sha256 $dlHash -Size 200; $true }
    Assert 'Download mit falscher Pruefsumme wird abgelehnt' { try { Test-WpeDownload -Path $dl -Sha256 ('0' * 64) -Size 200; $false } catch { $_.Exception.Message -like '*SHA-256*' } }
    Assert 'Download mit falscher Groesse wird abgelehnt' { try { Test-WpeDownload -Path $dl -Sha256 $dlHash -Size 201; $false } catch { $true } }
    # Tagessperre (HKCU) - Wert des angemeldeten Benutzers sichern und wiederherstellen
    $userKey = 'HKCU:\Software\WePrintEasy'
    $savedCheck = Get-ItemProperty -LiteralPath $userKey -Name LastUpdateCheck -ErrorAction SilentlyContinue
    try {
        Set-WpeUpdateCheckTime
        Assert 'Update-Pruefung hoechstens einmal am Tag' { -not (Test-WpeUpdateCheckDue) -and (Test-WpeUpdateCheckDue -Interval ([TimeSpan]::Zero)) }
    } finally {
        if ($savedCheck) { Set-ItemProperty -LiteralPath $userKey -Name LastUpdateCheck -Value $savedCheck.LastUpdateCheck }
        else { Remove-ItemProperty -LiteralPath $userKey -Name LastUpdateCheck -ErrorAction SilentlyContinue }
    }

    Write-Host 'Letzte Aenderung rueckgaengig (config.json.bak)'
    $undoCfg = Join-Path $tmp 'undo\config.json'
    Assert 'Ohne Sicherung: Get-WpeConfigBackup liefert nichts' { $null -eq (Get-WpeConfigBackup -Path $undoCfg) }
    Assert 'Ohne Sicherung: Restore-WpeConfigBackup meldet einen Fehler' { try { Restore-WpeConfigBackup -Path $undoCfg -Confirm:$false; $false } catch { $_.Exception.Message -like '*.bak*' } }
    Set-WpeAssignment -Type User -Name 'a1' -Sid 'S-1-5-21-9-9-9-1' -Printer 'P1' -ConfigPath $undoCfg -SkipSidLookup | Out-Null
    Set-WpeAssignment -Type User -Name 'a2' -Sid 'S-1-5-21-9-9-9-2' -Printer 'P2' -ConfigPath $undoCfg -SkipSidLookup | Out-Null
    @([pscustomobject]@{ Type = 'User'; Name = 'a1'; Sid = 'S-1-5-21-9-9-9-1' }, [pscustomobject]@{ Type = 'User'; Name = 'a2'; Sid = 'S-1-5-21-9-9-9-2' }) |
        Remove-WpeAssignment -ConfigPath $undoCfg -Confirm:$false
    Assert 'Mehrere Zuweisungen in einem Vorgang entfernt' { (Read-WpeConfig -Path $undoCfg).Assignments.Count -eq 0 }
    $bk = Get-WpeConfigBackup -Path $undoCfg
    Assert 'Sicherung: Stand vor dem Entfernen (2 Benutzer), mit Zeitpunkt' { $bk.Users -eq 2 -and $bk.Groups -eq 0 -and $bk.Saved -is [datetime] }
    $before = (Get-Item -LiteralPath $undoCfg).LastWriteTimeUtc
    Start-Sleep -Milliseconds 50
    Restore-WpeConfigBackup -Path $undoCfg -Confirm:$false
    Assert 'Rueckgaengig: beide Zuweisungen wieder da' { (Read-WpeConfig -Path $undoCfg).Assignments.Count -eq 2 }
    Assert 'Rueckgaengig: Datei neu gestempelt (Agenten bemerken die Aenderung)' { (Get-Item -LiteralPath $undoCfg).LastWriteTimeUtc -gt $before }
    Assert 'Rueckgaengig: der vorherige Stand ist jetzt die Sicherung' { (Get-WpeConfigBackup -Path $undoCfg).Users -eq 0 }
    Restore-WpeConfigBackup -Path $undoCfg -Confirm:$false
    Assert 'Erneut rueckgaengig: Stand nach dem Entfernen wieder hergestellt' { (Read-WpeConfig -Path $undoCfg).Assignments.Count -eq 0 }
    Assert 'Keine temporaeren Dateien uebrig' { @(Get-ChildItem -LiteralPath (Split-Path $undoCfg) -Filter '*.tmp').Count -eq 0 }
    [IO.File]::WriteAllText("$undoCfg.bak", '{ kaputt')
    Assert 'Defekte Sicherung wird nicht eingespielt' { try { Restore-WpeConfigBackup -Path $undoCfg -Confirm:$false; $false } catch { (Read-WpeConfig -Path $undoCfg).Assignments.Count -eq 0 } }

    Write-Host 'Versionsuebersicht der Server (Farm)'
    $farmCfg = Join-Path $tmp 'farm\config.json'
    Assert 'Ohne Eintraege: keine Server' { @(Get-WpeHost -ConfigPath $farmCfg).Count -eq 0 }
    Register-WpeHost -ConfigPath $farmCfg -InstallPath 'C:\Program Files\WePrintEasy' -Version '1.0.10' -Confirm:$false
    $hostDir = Get-WpeHostDirectory $farmCfg
    $own = Join-Path $hostDir "$env:COMPUTERNAME.json"
    Assert 'Register-WpeHost legt hosts\<Rechner>.json neben der Konfiguration an' { (Test-Path -LiteralPath $own) -and $hostDir -eq (Join-Path $tmp 'farm\hosts') }
    Assert 'Eintrag ist UTF-8 ohne BOM' { $b = [IO.File]::ReadAllBytes($own); -not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) }
    [IO.File]::WriteAllText((Join-Path $hostDir 'TS02.json'), '{ "ComputerName": "TS02", "Version": "1.0.9", "Updated": "2026-10-01T08:00:00Z" }')
    [IO.File]::WriteAllText((Join-Path $hostDir 'kaputt.json'), '{ kaputt')
    $farm = @(Get-WpeHost -ConfigPath $farmCfg)
    Assert 'Get-WpeHost liest alle gueltigen Eintraege (defekte werden uebersprungen)' { $farm.Count -eq 2 -and ($farm | Where-Object ComputerName -eq 'TS02').Updated.Day -eq 1 }
    $hs = Get-WpeHostVersionStatus -Hosts $farm
    Assert 'Neueste Version numerisch (1.0.10 > 1.0.9), TS02 veraltet' { $hs.Newest -eq [version]'1.0.10' -and @($hs.Outdated).Count -eq 1 -and $hs.Outdated[0].ComputerName -eq 'TS02' }
    Assert 'Eintrag ohne Version gilt als veraltet' { @((Get-WpeHostVersionStatus -Hosts @($farm + [pscustomobject]@{ ComputerName = 'TS03'; Version = '' })).Outdated).Count -eq 2 }
    Assert 'Systempruefung warnt vor veraltetem Server' { $r = @(Get-WpeSystemStatus -ConfigPath $farmCfg) | Where-Object Id -eq 'Hosts'; $r.Status -eq 'Warning' -and $r.Detail -like '*TS02 (1.0.9)*1.0.10*' }
    Remove-Item -LiteralPath (Join-Path $hostDir 'TS02.json')
    Assert 'Systempruefung: alle Server aktuell' { (@(Get-WpeSystemStatus -ConfigPath $farmCfg) | Where-Object Id -eq 'Hosts').Status -eq 'OK' }
    Unregister-WpeHost -ConfigPath $farmCfg -Confirm:$false
    Assert 'Unregister-WpeHost entfernt nur den eigenen Eintrag' { -not (Test-Path -LiteralPath $own) -and (Test-Path -LiteralPath (Join-Path $hostDir 'kaputt.json')) }
    Assert 'Get-WpeAgentProcess laeuft ohne Fehler' { $null -eq (@(Get-WpeAgentProcess) | Where-Object { -not $_.ProcessId }) }
    $sessions = @(Get-WpeUserSession)
    Assert 'Get-WpeUserSession: je Sitzung ein Eintrag mit Benutzer und SID' { @($sessions | Where-Object { $_.SessionId -le 0 -or -not $_.UserSid -or -not $_.User }).Count -eq 0 -and @($sessions | Group-Object SessionId | Where-Object Count -gt 1).Count -eq 0 }

    Write-Host 'App-Symbol'
    $icoBytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..\src\WePrintEasy.ico'))
    Assert 'WePrintEasy.ico: Symboldatei mit 8 Groessen (16 bis 256)' { [BitConverter]::ToUInt16($icoBytes, 2) -eq 1 -and [BitConverter]::ToUInt16($icoBytes, 4) -eq 8 -and $icoBytes[6] -eq 16 -and $icoBytes[6 + 7 * 16] -eq 0 }

    Write-Host 'winget-Manifeste'
    $wingetTool = Join-Path $PSScriptRoot '..\tools\New-WingetManifest.ps1'
    $wingetDir = & $wingetTool -Version '9.9.9' -InstallerSha256 ('ab' * 32) -ReleaseDate '2026-01-02' -OutputDir (Join-Path $tmp 'winget') 6> $null
    $wingetFiles = @(Get-ChildItem -LiteralPath $wingetDir -Filter '*.yaml')
    $wingetText = @{}
    foreach ($f in $wingetFiles) { $wingetText[$f.Name] = [IO.File]::ReadAllText($f.FullName) }
    $wingetInstaller = $wingetText['WePrintEasy.WePrintEasy.installer.yaml']
    $iss = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\installer\WePrintEasy.iss'))
    Assert 'Ordner wie in winget-pkgs, 4 Manifeste' { $wingetDir -replace '\\', '/' -like '*/winget/manifests/w/WePrintEasy/WePrintEasy/9.9.9' -and $wingetFiles.Count -eq 4 }
    Assert 'Installer-URL, Pruefsumme und Datum eingesetzt' {
        $wingetInstaller -match '(?m)^  InstallerUrl: https://github\.com/LeonMTN05/WePrintEasy/releases/download/v9\.9\.9/WePrintEasy-Setup-9\.9\.9\.exe$' -and
        $wingetInstaller -match "(?m)^  InstallerSha256: $('AB' * 32)$" -and $wingetInstaller -match '(?m)^ReleaseDate: 2026-01-02$'
    }
    Assert 'Keine Platzhalter und Vorlagen-Kommentare, Schema passt zum ManifestType' {
        @($wingetText.Keys | Where-Object {
                $t = $wingetText[$_]
                $type = if ($t -match '(?m)^ManifestType: (\w+)$') { $Matches[1] } else { '?' }
                $t -match '__[A-Z0-9_]+__' -or @($t -split "`n" | Where-Object { $_ -like '#*' }).Count -ne 2 -or
                    $t -notmatch "(?m)^# yaml-language-server: \`$schema=https://aka\.ms/winget-manifest\.$type\.1\.12\.0\.schema\.json$" -or
                    $t -notmatch '(?m)^PackageVersion: 9\.9\.9$'
            }).Count -eq 0
    }
    Assert 'ProductCode = AppId des Installers und Schluessel der Deinstallation' {
        $null = $iss -match '#define AppId "([0-9A-F-]+)"'
        $code = "{$($Matches[1])}_is1"
        $uninstall = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Uninstall-WePrintEasy.ps1'))
        @([regex]::Matches($wingetInstaller, "(?m)ProductCode: '([^']+)'") | Where-Object { $_.Groups[1].Value -ne $code }).Count -eq 0 -and
            $uninstall.Contains("Uninstall\$code'")
    }
    Assert 'Herausgeber und Windows-Mindestversion wie im Installer' {
        $null = $iss -match '(?m)^AppPublisher=(.+?)\r?$'; $publisher = $Matches[1]
        $null = $iss -match '(?m)^MinVersion=(.+?)\r?$'; $minVersion = $Matches[1]
        $wingetInstaller -match "(?m)^  Publisher: $([regex]::Escape($publisher))$" -and $wingetInstaller -match "(?m)^MinimumOSVersion: $([regex]::Escape($minVersion))\.0$"
    }
    Assert 'Ungueltige Version wird abgelehnt' { try { & $wingetTool -Version '1.0' -InstallerSha256 ('ab' * 32) -OutputDir (Join-Path $tmp 'winget') 6> $null; $false } catch { $true } }

    Write-Host 'Drucker der Sitzung (Windows-API)'
    $names = @(Get-WpeInstalledPrinterNames)
    $expected = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Assert 'Get-WpeInstalledPrinterNames (EnumPrinters) liefert dieselben Drucker wie Get-Printer' { $names.Count -eq $expected.Count -and -not (Compare-Object $names $expected) }
    # Nicht mit Win32_Printer (Default) vergleichen: In RDP-Sitzungen mit umgeleiteten Druckern zeigt WMI
    # den globalen Wert (HKCU\...\Windows\Device), nicht den wirksamen Standarddrucker der Sitzung
    $default = Get-WpeDefaultPrinter
    Assert 'Get-WpeDefaultPrinter liefert einen Drucker dieser Sitzung' { ($null -eq $default -and $names.Count -eq 0) -or $names -contains $default }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:Passed bestanden, $script:Failed fehlgeschlagen" -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
if ($script:Failed) { exit 1 }
