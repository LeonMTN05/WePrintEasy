#Requires -Version 5.1
<#
    WePrintEasy - gemeinsames Modul
    Wird vom Verwaltungsprogramm (WePrintEasy-Admin.ps1) und vom
    Anmelde-Agenten (WePrintEasy-Agent.ps1) verwendet.

    Kann auch direkt in der PowerShell genutzt werden, z. B.:
        Import-Module 'C:\Program Files\WePrintEasy\WePrintEasy.psm1'
        Get-WpeAssignment
        Set-WpeAssignment -Type User -Name mmuster -Printer '\\printsrv\HP-Buero'
#>

Set-StrictMode -Version 2.0

$script:RegistryKey      = 'HKLM:\SOFTWARE\WePrintEasy'
$script:ConfigVersion    = 1
$script:PrinterRegKey    = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
$script:ComputerDomain   = ''   # Zwischenspeicher fuer Get-WpeLdapPrefix

# Version und Projekt - nur hier pflegen
$script:WpeVersion       = '1.0.3'
$script:WpeAuthor        = 'LeonMTN05'
$script:WpeAuthorUrl     = 'https://github.com/LeonMTN05'
$script:WpeProjectUrl    = 'https://github.com/LeonMTN05/WePrintEasy'
$script:WpeLicense       = 'MIT'

#region Sprache ---------------------------------------------------------------

# Unterstuetzte Sprachen (Kuerzel -> Name in der Sprache selbst). Texte: WePrintEasy.Strings.<Kuerzel>.psd1
$script:WpeLanguages     = [ordered]@{ en = 'English'; de = 'Deutsch' }
$script:WpeLanguage      = 'en'
$script:WpeStrings       = @{}
$script:WpeFallbackStrings = $null

function Get-WpeSupportedLanguage {
    <# Unterstuetzte Sprachen: Kuerzel -> Anzeigename (z. B. en -> English). #>
    $script:WpeLanguages
}

function Read-WpeStringTable {
    <#
        Liest eine Sprachdatei als Daten (es wird nichts ausgefuehrt). Nicht Import-PowerShellDataFile:
        das lehnt Hashtables mit mehr als 500 Eintraegen als "dynamischen Ausdruck" ab.
    #>
    param([Parameter(Mandatory)][string]$Language)
    $path = Join-Path $PSScriptRoot "WePrintEasy.Strings.$Language.psd1"
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors) { throw "${path}: $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))" }
    $ht = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $false)
    $table = @{}
    foreach ($pair in $ht.KeyValuePairs) { $table[[string]$pair.Item1.SafeGetValue()] = $pair.Item2.SafeGetValue() }
    $table
}

function Resolve-WpeLanguage {
    <#
        Liefert eine unterstuetzte Sprache: die gewuenschte, sonst die Vorgabe des Servers
        (HKLM\SOFTWARE\WePrintEasy\Language), sonst Englisch. Installationen aus der Zeit vor
        der Sprachauswahl (InstallPath ohne Language) waren deutsch und bleiben es.
    #>
    param([string]$Language)
    $reg = Get-ItemProperty -LiteralPath $script:RegistryKey -ErrorAction SilentlyContinue
    $machine = ''
    if ($reg -and $reg.PSObject.Properties['Language']) { $machine = [string]$reg.Language }
    elseif ($reg -and $reg.PSObject.Properties['InstallPath']) { $machine = 'de' }
    foreach ($l in $Language, $machine) {
        if ($l -and $script:WpeLanguages.Contains($l.Trim().ToLowerInvariant())) { return $l.Trim().ToLowerInvariant() }
    }
    return 'en'
}

function Set-WpeLanguage {
    <# Stellt die Sprache aller Texte um. Leer oder unbekannt: Vorgabe des Servers bzw. Englisch. #>
    param([string]$Language)
    $lang = Resolve-WpeLanguage $Language
    if (-not $script:WpeFallbackStrings) { $script:WpeFallbackStrings = Read-WpeStringTable 'en' }
    $script:WpeStrings = if ($lang -eq 'en') { $script:WpeFallbackStrings } else { Read-WpeStringTable $lang }
    $script:WpeLanguage = $lang
}

function Get-WpeLanguage {
    <# Kuerzel der aktuell eingestellten Sprache (en, de). #>
    $script:WpeLanguage
}

function Initialize-WpeLanguage {
    <# Sprache aus der Einstellung "Language" der Konfiguration, sonst Vorgabe des Servers, sonst Englisch. #>
    [CmdletBinding()]
    param([string]$ConfigPath = (Get-WpeConfigPath))
    $lang = ''
    try { $lang = [string](Read-WpeConfig -Path $ConfigPath).Settings.Language } catch { Write-Verbose (Get-WpeText 'Verbose.LanguageUnreadable' $_.Exception.Message) }
    Set-WpeLanguage $lang
}

function Get-WpeText {
    <#
        Text in der eingestellten Sprache (fehlt er, der englische). Weitere Argumente
        ersetzen {0}, {1}, ... - z. B.  Get-WpeText 'Agent.Connected' $printer
    #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(ValueFromRemainingArguments)][object[]]$Arguments
    )
    if (-not $script:WpeFallbackStrings) { Set-WpeLanguage '' }
    $text = $script:WpeStrings[$Key]
    if ($null -eq $text) { $text = $script:WpeFallbackStrings[$Key] }
    if ($null -eq $text) { return $Key }
    # Nicht "if ($Arguments)": ein einzelnes Argument 0 oder '' waere dann $false
    if ($null -eq $Arguments -or $Arguments.Count -eq 0) { return $text }
    # Mehrzeilige Texte (Arrays) zeilenweise ersetzen
    if ($text -is [array]) { return @(foreach ($line in $text) { $line -f $Arguments }) }
    return ($text -f $Arguments)
}

function Get-WpeShortcutPath {
    <# Verknuepfung unter Windows-Tools in der eingestellten Sprache. -All: alle Sprachvarianten. #>
    param([switch]$All)
    $dir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Administrative Tools'
    $names = if ($All) { foreach ($l in $script:WpeLanguages.Keys) { (Read-WpeStringTable $l)['App.ShortcutName'] } } else { Get-WpeText 'App.ShortcutName' }
    foreach ($n in $names) { Join-Path $dir "$n.lnk" }
}

function Rename-WpeShortcut {
    <# Benennt eine vorhandene Verknuepfung in die eingestellte Sprache um (Administratorrechte). #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $target = Get-WpeShortcutPath
    if (Test-Path -LiteralPath $target) { return }
    foreach ($p in Get-WpeShortcutPath -All) {
        if ($p -ne $target -and (Test-Path -LiteralPath $p) -and $PSCmdlet.ShouldProcess($p, $target)) {
            Move-Item -LiteralPath $p -Destination $target -ErrorAction Stop
            return
        }
    }
}

#endregion

#region Konfiguration ---------------------------------------------------------

function Get-WpeDefaultSettings {
    <# Standardwerte aller Einstellungen. Neue Einstellungen nur hier ergaenzen. #>
    [ordered]@{
        # Wie lange nach der Anmeldung (Sekunden) engmaschig geprueft wird.
        # In dieser Zeit tauchen umgeleitete RDP-Drucker auf und verstellen
        # gern den Standarddrucker.
        LogonPhaseSeconds           = 120
        # Danach waehrend der Sitzung weiter ueberwachen und zuruecksetzen?
        EnforceDuringSession        = $true
        EnforceIntervalSeconds      = 30
        # 0 = waehrend der gesamten Sitzung
        EnforceDurationMinutes      = 0
        # "Windows verwaltet Standarddrucker" fuer den Benutzer abschalten
        SetLegacyDefaultPrinterMode = $true
        # Fehlende Netzwerkdrucker (\\server\freigabe) automatisch verbinden
        ConnectNetworkPrinters      = $true
        # Vorbelegung im Verwaltungsprogramm
        DefaultPrintServer          = ''
        # Sprache von Verwaltung und Agent-Protokoll (en, de); leer = Vorgabe des Servers
        Language                    = ''
    }
}

function Get-WpeConfigPath {
    <# Liefert den Pfad der zentralen Konfigurationsdatei. #>
    [CmdletBinding()]
    param()
    try {
        $value = (Get-ItemProperty -LiteralPath $script:RegistryKey -Name ConfigPath -ErrorAction Stop).ConfigPath
        if ($value) { return [Environment]::ExpandEnvironmentVariables($value) }
    } catch {
        Write-Verbose (Get-WpeText 'Verbose.NoConfigPath' $script:RegistryKey)
    }
    $programData = [Environment]::GetFolderPath('CommonApplicationData')
    if (-not $programData) { $programData = $env:ProgramData }
    return (Join-Path (Join-Path $programData 'WePrintEasy') 'config.json')
}

function New-WpeAssignmentObject {
    <# Erzeugt ein normalisiertes Zuweisungsobjekt. #>
    param(
        [Parameter(Mandatory)][ValidateSet('User', 'Group')][string]$Type,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Printer,
        [string]$Sid = '',
        [string]$DisplayName = '',
        [int]$Priority = 100,
        [string]$Comment = '',
        [string]$ModifiedAt = '',
        [string]$ModifiedBy = ''
    )
    [pscustomobject][ordered]@{
        Type        = $Type
        Name        = (ConvertTo-WpeAccountName $Name)
        Sid         = [string]$Sid
        DisplayName = [string]$DisplayName
        Printer     = $Printer.Trim()
        Priority    = $Priority
        Comment     = [string]$Comment
        ModifiedAt  = [string]$ModifiedAt
        ModifiedBy  = [string]$ModifiedBy
    }
}

function ConvertTo-WpeAccountName {
    <# Entfernt ein evtl. vorhandenes "DOMAENE\" bzw. "@domaene" vom Kontonamen. #>
    param([string]$Name)
    if (-not $Name) { return '' }
    $n = $Name.Trim()
    if ($n.Contains('\')) { $n = $n.Substring($n.LastIndexOf('\') + 1) }
    if ($n.Contains('@')) { $n = $n.Substring(0, $n.IndexOf('@')) }
    return $n
}

function ConvertTo-WpeConfig {
    <# Wandelt ein (aus JSON gelesenes) Objekt in eine vollstaendige Konfiguration um. #>
    param($Raw)

    $defaults = Get-WpeDefaultSettings
    $settings = [ordered]@{}
    $rawSettings = $null
    if ($Raw -and $Raw.PSObject.Properties['Settings']) { $rawSettings = $Raw.Settings }
    foreach ($key in $defaults.Keys) {
        $value = $defaults[$key]
        if ($rawSettings -and $rawSettings.PSObject.Properties[$key] -and $null -ne $rawSettings.$key) {
            $value = $rawSettings.$key
        }
        $settings[$key] = $value
    }

    $assignments = New-Object System.Collections.ArrayList
    if ($Raw -and $Raw.PSObject.Properties['Assignments']) {
        foreach ($a in @($Raw.Assignments)) {
            if (-not $a -or -not $a.PSObject.Properties['Type'] -or -not $a.PSObject.Properties['Name'] -or -not $a.PSObject.Properties['Printer']) { continue }
            if ($a.Type -notin 'User', 'Group' -or -not $a.Name -or -not $a.Printer) { continue }
            $p = @{ Type = [string]$a.Type; Name = [string]$a.Name; Printer = [string]$a.Printer }
            foreach ($opt in 'Sid', 'DisplayName', 'Comment', 'ModifiedAt', 'ModifiedBy') {
                if ($a.PSObject.Properties[$opt] -and $null -ne $a.$opt) { $p[$opt] = [string]$a.$opt }
            }
            if ($a.PSObject.Properties['Priority'] -and $null -ne $a.Priority) { $p.Priority = [int]$a.Priority }
            [void]$assignments.Add((New-WpeAssignmentObject @p))
        }
    }

    $printers = New-Object System.Collections.ArrayList
    if ($Raw -and $Raw.PSObject.Properties['Printers']) {
        foreach ($p in @($Raw.Printers)) {
            if (-not $p -or -not $p.PSObject.Properties['Path'] -or -not $p.Path) { continue }
            $e = @{ Path = [string]$p.Path }
            foreach ($opt in 'DriverName', 'Location', 'Comment') {
                if ($p.PSObject.Properties[$opt] -and $null -ne $p.$opt) { $e[$opt] = [string]$p.$opt }
            }
            [void]$printers.Add((New-WpeCatalogEntry @e))
        }
    }

    [pscustomobject][ordered]@{
        Version     = $script:ConfigVersion
        Settings    = [pscustomobject]$settings
        Assignments = $assignments
        # Druckerliste (Katalog) fuer die Auswahl im Verwaltungsprogramm
        Printers    = $printers
    }
}

function New-WpeCatalogEntry {
    <# Eintrag der Druckerliste. Server und Freigabename werden aus dem Pfad abgeleitet. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$DriverName = '',
        [string]$Location = '',
        [string]$Comment = ''
    )
    $server = ''; $share = $Path
    if ($Path -match '^\\\\([^\\]+)\\(.+)$') { $server = $Matches[1]; $share = $Matches[2] }
    [pscustomobject][ordered]@{
        Path       = $Path.Trim()
        Server     = $server
        ShareName  = $share
        DriverName = $DriverName
        Location   = $Location
        Comment    = $Comment
    }
}

function Read-WpeConfig {
    <# Liest die Konfiguration. Fehlt die Datei, wird eine leere Konfiguration geliefert. #>
    [CmdletBinding()]
    param([string]$Path = (Get-WpeConfigPath))
    # Lesefehler muessen abbrechen - sonst wuerde eine leere Konfiguration weiterverarbeitet
    # und ggf. ueber die echte gespeichert (Modulfunktionen erben die Einstellung des Aufrufers nicht)
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Verbose (Get-WpeText 'Verbose.ConfigMissing' $Path)
        return (ConvertTo-WpeConfig $null)
    }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) { return (ConvertTo-WpeConfig $null) }
    try {
        $raw = ConvertFrom-Json -InputObject $text -ErrorAction Stop
    } catch {
        throw (Get-WpeText 'Config.InvalidJson' $Path $_.Exception.Message)
    }
    return (ConvertTo-WpeConfig $raw)
}

function Save-WpeConfig {
    <# Speichert die Konfiguration atomar (temporaere Datei + Austausch) mit Sicherung (.bak). #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Path = (Get-WpeConfigPath)
    )
    $ErrorActionPreference = 'Stop'

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $out = [pscustomobject][ordered]@{
        Version     = $script:ConfigVersion
        Settings    = $Config.Settings
        Assignments = @($Config.Assignments | Sort-Object -Property Type, Name)
        Printers    = @($(if ($Config.PSObject.Properties['Printers']) { $Config.Printers }) | Where-Object { $_ } | Sort-Object -Property Path | ForEach-Object {
                [pscustomobject][ordered]@{ Path = $_.Path; DriverName = $_.DriverName; Location = $_.Location; Comment = $_.Comment }
            })
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6

    if (-not $PSCmdlet.ShouldProcess($Path, (Get-WpeText 'Config.SaveAction'))) { return }

    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($tmp, $Path, "$Path.bak")
        } else {
            [IO.File]::Move($tmp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Test-WpeConfigWritable {
    <# Prueft, ob im Konfigurationsordner geschrieben werden darf. #>
    param([string]$Path = (Get-WpeConfigPath))
    $dir = Split-Path -Parent $Path
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        $probe = Join-Path $dir ".write-test-$([Guid]::NewGuid().ToString('N'))"
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

#endregion

#region Zuweisungen verwalten -------------------------------------------------

function Test-WpeSameAccount {
    param($Assignment, [string]$Type, [string]$Name, [string]$Sid)
    if ($Assignment.Type -ne $Type) { return $false }
    if ($Sid -and $Assignment.Sid) { return ($Assignment.Sid -eq $Sid) }
    return ($Assignment.Name -eq (ConvertTo-WpeAccountName $Name))
}

function Get-WpeAssignment {
    <# Listet Zuweisungen auf (optional gefiltert, Platzhalter erlaubt). #>
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Group')][string]$Type,
        [string]$Name = '*',
        [string]$ConfigPath = (Get-WpeConfigPath)
    )
    $config = Read-WpeConfig -Path $ConfigPath
    $config.Assignments | Where-Object {
        (-not $Type -or $_.Type -eq $Type) -and ($_.Name -like $Name -or $_.DisplayName -like $Name)
    }
}

function Set-WpeAssignment {
    <#
        Legt eine Druckerzuweisung an oder aktualisiert sie.
        Unterstuetzt Pipeline-Eingabe, z. B. fuer einen CSV-Import:
            Import-Csv .\zuweisungen.csv -Delimiter ';' | Set-WpeAssignment
        (Spalten: Type;Name;Printer[;Priority;Comment])
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][ValidateSet('User', 'Group')][string]$Type,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Printer,
        [Parameter(ValueFromPipelineByPropertyName)][string]$Sid,
        [Parameter(ValueFromPipelineByPropertyName)][string]$DisplayName,
        [Parameter(ValueFromPipelineByPropertyName)][int]$Priority = 100,
        [Parameter(ValueFromPipelineByPropertyName)][string]$Comment,
        [string]$ConfigPath = (Get-WpeConfigPath),
        # Keine SID-Ermittlung im AD (z. B. fuer Tests oder ohne Domaenenverbindung)
        [switch]$SkipSidLookup
    )
    begin {
        $config = Read-WpeConfig -Path $ConfigPath
        $changed = $false
    }
    process {
        $accountName = ConvertTo-WpeAccountName $Name
        if (-not $Sid -and -not $SkipSidLookup) {
            $Sid = Get-WpeAccountSid -Name $accountName
            if (-not $Sid) { Write-Error (Get-WpeText 'Assign.AccountNotFound' $accountName); return }
        }

        $existing = $null
        foreach ($a in $config.Assignments) {
            if (Test-WpeSameAccount $a $Type $accountName $Sid) { $existing = $a; break }
        }
        if (-not $DisplayName -and $existing) { $DisplayName = $existing.DisplayName }
        if (-not $PSBoundParameters.ContainsKey('Comment') -and $existing) { $Comment = $existing.Comment }
        # Nicht angegeben bzw. leere CSV-Spalte (=0): vorhandene Prioritaet behalten, sonst 100
        $prio = $Priority
        if (-not $PSBoundParameters.ContainsKey('Priority') -or $prio -le 0) {
            $prio = if ($existing) { $existing.Priority } else { 100 }
        }

        $new = New-WpeAssignmentObject -Type $Type -Name $accountName -Printer $Printer -Sid $Sid `
            -DisplayName $DisplayName -Priority $prio -Comment $Comment `
            -ModifiedAt (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ModifiedBy (Get-WpeCurrentAccount)

        if ($PSCmdlet.ShouldProcess("$Type $accountName", (Get-WpeText 'Assign.SetAction' $Printer))) {
            if ($existing) { [void]$config.Assignments.Remove($existing) }
            [void]$config.Assignments.Add($new)
            $changed = $true
            $new
        }
    }
    end {
        if ($changed) { Save-WpeConfig -Config $config -Path $ConfigPath -Confirm:$false }
    }
}

function Remove-WpeAssignment {
    <# Entfernt eine Zuweisung. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][ValidateSet('User', 'Group')][string]$Type,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name,
        [Parameter(ValueFromPipelineByPropertyName)][string]$Sid,
        [string]$ConfigPath = (Get-WpeConfigPath)
    )
    begin {
        $config = Read-WpeConfig -Path $ConfigPath
        $changed = $false
    }
    process {
        $hits = @($config.Assignments | Where-Object { Test-WpeSameAccount $_ $Type $Name $Sid })
        if (-not $hits) { Write-Warning (Get-WpeText 'Assign.NotFound' $Type $Name); return }
        foreach ($h in $hits) {
            if ($PSCmdlet.ShouldProcess("$Type $($h.Name)", (Get-WpeText 'Assign.RemoveAction'))) {
                [void]$config.Assignments.Remove($h)
                $changed = $true
            }
        }
    }
    end {
        if ($changed) { Save-WpeConfig -Config $config -Path $ConfigPath -Confirm:$false }
    }
}

function Resolve-WpeAssignment {
    <#
        Ermittelt die gueltige Zuweisung fuer einen Benutzer:
          1. Direkte Benutzerzuweisung (per SID, sonst per Anmeldename)
          2. Gruppenzuweisung mit der kleinsten Prioritaetszahl
        Liefert $null, wenn nichts zutrifft.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$UserSid,
        [string]$UserName,
        [string[]]$GroupSids = @()
    )
    $userName = ConvertTo-WpeAccountName $UserName
    $all = @($Config.Assignments)

    foreach ($a in $all) {
        if ($a.Type -ne 'User') { continue }
        if ($a.Sid) {
            if ($UserSid -and $a.Sid -eq $UserSid) { return $a }
        } elseif ($userName -and $a.Name -eq $userName) {
            return $a
        }
    }

    $groupSet = @{}
    foreach ($g in $GroupSids) { if ($g) { $groupSet[$g.ToUpperInvariant()] = $true } }
    $groups = @($all | Where-Object { $_.Type -eq 'Group' -and $_.Sid -and $groupSet.ContainsKey($_.Sid.ToUpperInvariant()) } |
            Sort-Object -Property Priority, Name)
    if ($groups.Count -gt 0) { return $groups[0] }
    return $null
}

#endregion

#region Active Directory ------------------------------------------------------

function Get-WpeCurrentAccount {
    if ($env:USERDOMAIN) { return "$env:USERDOMAIN\$env:USERNAME" }
    return [string]$env:USERNAME
}

function ConvertTo-WpeLdapFilterValue {
    <# Maskiert Sonderzeichen fuer LDAP-Filter (RFC 4515). #>
    param([string]$Value)
    if (-not $Value) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Value.ToCharArray()) {
        switch ($c) {
            '\' { [void]$sb.Append('\5c') }
            '*' { [void]$sb.Append('\2a') }
            '(' { [void]$sb.Append('\28') }
            ')' { [void]$sb.Append('\29') }
            ([char]0) { [void]$sb.Append('\00') }
            default { [void]$sb.Append($c) }
        }
    }
    return $sb.ToString()
}

function Get-WpeAccountSid {
    <# Ermittelt die SID eines Domaenenkontos (Benutzer oder Gruppe). #>
    param([Parameter(Mandatory)][string]$Name)
    $candidates = @()
    if ($Name.Contains('\')) { $candidates += $Name } else {
        if ($env:USERDOMAIN) { $candidates += "$env:USERDOMAIN\$Name" }
        $candidates += $Name
    }
    foreach ($c in $candidates) {
        try {
            return (New-Object System.Security.Principal.NTAccount($c)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        } catch {
            Write-Verbose (Get-WpeText 'Verbose.SidFailed' $c $_.Exception.Message)
        }
    }
    return $null
}

function Get-WpeLdapPrefix {
    <#
        LDAP-Praefix fuer AD-Abfragen. Ohne Server bindet .NET an die Domaene des
        angemeldeten Benutzers - bei einem lokalen Konto (z. B. .\Administrator)
        gibt es die nicht. Dann wird die Domaene des Computers verwendet.
    #>
    if (-not $env:USERDOMAIN -or $env:USERDOMAIN -ine $env:COMPUTERNAME) { return 'LDAP://' }
    if (-not $script:ComputerDomain) {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -Property Domain, PartOfDomain -ErrorAction SilentlyContinue
        $script:ComputerDomain = if ($cs -and $cs.PartOfDomain) { [string]$cs.Domain } else { '' }
    }
    if (-not $script:ComputerDomain) { throw (Get-WpeText 'Ad.NoDomain') }
    return "LDAP://$($script:ComputerDomain)/"
}

function Find-WpeAdObject {
    <# Sucht Benutzer oder Gruppen im AD der aktuellen Domaene (ohne RSAT). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('User', 'Group')][string]$Type,
        [string]$SearchText = '',
        [switch]$Exact,
        [int]$MaxResults = 300
    )
    $value = ConvertTo-WpeLdapFilterValue $SearchText.Trim()
    $classFilter = if ($Type -eq 'User') { '(objectCategory=person)(objectClass=user)' } else { '(objectCategory=group)' }
    $textFilter = ''
    if ($Exact) {
        $textFilter = "(sAMAccountName=$value)"
    } elseif ($value) {
        $textFilter = "(|(sAMAccountName=*$value*)(displayName=*$value*)(cn=*$value*)(mail=*$value*))"
    }

    $searcher = New-Object System.DirectoryServices.DirectorySearcher
    $prefix = Get-WpeLdapPrefix
    if ($prefix -ne 'LDAP://') { $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry($prefix.TrimEnd('/')) }
    $searcher.Filter = "(&$classFilter$textFilter)"
    $searcher.SizeLimit = $MaxResults
    foreach ($p in 'samaccountname', 'displayname', 'objectsid', 'distinguishedname', 'description', 'useraccountcontrol', 'mail') {
        [void]$searcher.PropertiesToLoad.Add($p)
    }

    $results = $searcher.FindAll()
    try {
        $list = foreach ($r in $results) {
            $props = $r.Properties
            $first = { param($n) if ($props[$n] -and $props[$n].Count -gt 0) { $props[$n][0] } else { $null } }
            # Typfeste Variable: als Ausgabe (Skriptblock, if) wuerde das byte[] in Einzelwerte zerlegt
            [byte[]]$sidBytes = $null
            if ($props['objectsid'] -and $props['objectsid'].Count -gt 0) { $sidBytes = $props['objectsid'][0] }
            $uac = & $first 'useraccountcontrol'
            [pscustomobject]@{
                Type              = $Type
                Name              = [string](& $first 'samaccountname')
                DisplayName       = [string](& $first 'displayname')
                Description       = [string](& $first 'description')
                Mail              = [string](& $first 'mail')
                DistinguishedName = [string](& $first 'distinguishedname')
                Sid               = if ($sidBytes) { [System.Security.Principal.SecurityIdentifier]::new($sidBytes, 0).Value } else { '' }
                Enabled           = if ($null -ne $uac) { -not ([int]$uac -band 2) } else { $true }
            }
        }
    } finally {
        $results.Dispose()
        $searcher.Dispose()
    }
    $list | Sort-Object -Property Name
}

function Get-WpeAdUserGroupSids {
    <# Liefert alle (auch verschachtelten) Sicherheitsgruppen-SIDs eines AD-Benutzers. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserSid)
    $entry = New-Object System.DirectoryServices.DirectoryEntry("$(Get-WpeLdapPrefix)<SID=$UserSid>")
    try {
        $entry.RefreshCache([string[]]@('tokenGroups'))
        foreach ($bytes in $entry.Properties['tokenGroups']) {
            [System.Security.Principal.SecurityIdentifier]::new([byte[]]$bytes, 0).Value
        }
    } finally {
        $entry.Dispose()
    }
}

#endregion

#region Drucker ---------------------------------------------------------------

function Test-WpePrinterMatch {
    <# Vergleicht einen Druckernamen mit der Vorgabe (Platzhalter * und ? erlaubt). #>
    param([string]$Pattern, [string]$Name)
    if (-not $Pattern -or -not $Name) { return $false }
    if ($Pattern.IndexOfAny([char[]]'*?') -ge 0) {
        $wc = New-Object System.Management.Automation.WildcardPattern($Pattern, [System.Management.Automation.WildcardOptions]::IgnoreCase)
        return $wc.IsMatch($Name)
    }
    return [string]::Equals($Pattern, $Name, [StringComparison]::OrdinalIgnoreCase)
}

function Find-WpeInstalledPrinter {
    <# Sucht in einer Liste installierter Drucker den passenden zur Vorgabe. #>
    param([string]$Pattern, [string[]]$InstalledNames)
    foreach ($n in $InstalledNames) {
        if (Test-WpePrinterMatch -Pattern $Pattern -Name $n) { return $n }
    }
    return $null
}

function Test-WpeIsNetworkPrinterPath {
    param([string]$Name)
    return ($Name -match '^\\\\[^\\]+\\[^\\]+$' -and $Name.IndexOfAny([char[]]'*?') -lt 0)
}

function Initialize-WpeSpoolerApi {
    <#
        Windows-API GetDefaultPrinter/SetDefaultPrinter (winspool). Nur sie beruecksichtigt den
        Standarddrucker der RDP-Sitzung (HKCU\...\Windows\SessionDefaultDevices\<Anmelde-SID>).
        HKCU\...\Windows\Device und WScript.Network.SetDefaultPrinter kennen nur den globalen
        Wert, der in einer RDP-Sitzung von einem umgeleiteten Drucker ueberdeckt wird.
    #>
    if ('WePrintEasy.Spooler' -as [type]) { return }
    Add-Type -Namespace WePrintEasy -Name Spooler -MemberDefinition @'
[DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool GetDefaultPrinter(System.Text.StringBuilder buffer, ref int size);
[DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SetDefaultPrinter(string name);
'@
}

function Get-WpeDefaultPrinter {
    <# Aktueller Standarddrucker des angemeldeten Benutzers (auch in RDP-Sitzungen korrekt). #>
    Initialize-WpeSpoolerApi
    $size = 260
    $buffer = New-Object System.Text.StringBuilder $size
    if ([WePrintEasy.Spooler]::GetDefaultPrinter($buffer, [ref]$size)) { return $buffer.ToString() }
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($err -eq 122) {
        # ERROR_INSUFFICIENT_BUFFER: $size enthaelt jetzt die benoetigte Laenge
        $buffer = New-Object System.Text.StringBuilder $size
        if ([WePrintEasy.Spooler]::GetDefaultPrinter($buffer, [ref]$size)) { return $buffer.ToString() }
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    }
    # 2 = ERROR_FILE_NOT_FOUND: kein Standarddrucker gesetzt
    if ($err -ne 2) { Write-Verbose (Get-WpeText 'Verbose.DefaultUnreadable' (New-Object ComponentModel.Win32Exception $err).Message) }
    return $null
}

function Get-WpeInstalledPrinterNames {
    <# Alle Drucker, die in der aktuellen Sitzung sichtbar sind (inkl. umgeleiteter). #>
    @(Get-CimInstance -ClassName Win32_Printer -Property Name -ErrorAction Stop | ForEach-Object { $_.Name })
}

function Set-WpeDefaultPrinter {
    <# Setzt den Standarddrucker des angemeldeten Benutzers. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    if (-not $PSCmdlet.ShouldProcess($Name, (Get-WpeText 'Printer.SetDefaultAction'))) { return }
    # Nicht WScript.Network oder WMI: beide aendern in einer RDP-Sitzung nicht den wirksamen Standarddrucker
    Initialize-WpeSpoolerApi
    if (-not [WePrintEasy.Spooler]::SetDefaultPrinter($Name)) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw (Get-WpeText 'Printer.SetDefaultFailed' (New-Object ComponentModel.Win32Exception $err).Message $err)
    }
}

function Add-WpePrinterConnection {
    <# Verbindet einen freigegebenen Netzwerkdrucker (\\server\freigabe) fuer den Benutzer. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    if (-not $PSCmdlet.ShouldProcess($Name, (Get-WpeText 'Printer.ConnectAction'))) { return }
    try {
        $net = New-Object -ComObject WScript.Network
        $net.AddWindowsPrinterConnection($Name)
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($net)
    } catch {
        $first = $_.Exception.Message.Trim()
        Write-Verbose (Get-WpeText 'Verbose.WScriptFailed' $first)
        try {
            Add-Printer -ConnectionName $Name -ErrorAction Stop
        } catch {
            # Windows-Fehlercode mit ausgeben (z. B. 0x00000bcb = Treiber fehlt, 0x00000709 = Name ungueltig)
            $code = if ($_.FullyQualifiedErrorId -match 'HRESULT (0x[0-9a-fA-F]+)') { " [$($Matches[1])]" } else { '' }
            throw "$($_.Exception.Message.Trim())$code / WScript: $first"
        }
    }
}

function Get-WpePrinterList {
    <#
        Druckerliste fuer die Auswahl im Verwaltungsprogramm:
        lokal installierte Drucker + Freigaben eines Druckservers.
    #>
    [CmdletBinding()]
    param([string]$PrintServer)
    $names = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($p in Get-Printer -ErrorAction Stop) {
            # Umgeleitete RDP-Drucker sind sitzungsabhaengig und daher nicht sinnvoll auswaehlbar
            if ($p.Name -notmatch '\((umgeleitet|redirected) \d+\)|in (Sitzung|session) \d+') {
                $names.Add($p.Name)
            }
        }
    } catch {
        Write-Verbose (Get-WpeText 'Verbose.LocalPrintersFailed' $_.Exception.Message)
    }
    if ($PrintServer) {
        $server = $PrintServer.Trim().TrimStart('\')
        foreach ($p in Get-Printer -ComputerName $server -ErrorAction Stop) {
            if ($p.Shared -and $p.ShareName) { $names.Add("\\$server\$($p.ShareName)") }
        }
    }
    $names | Sort-Object -Unique
}

function ConvertTo-WpePrintServerPrinter {
    <# Wandelt Get-Printer-Objekte eines Druckservers in Katalog-Kandidaten um (nur freigegebene). #>
    param([object[]]$Printers, [Parameter(Mandatory)][string]$Server, [string[]]$LocalDrivers)
    $haveDriverList = $PSBoundParameters.ContainsKey('LocalDrivers') -and $null -ne $LocalDrivers
    foreach ($p in $Printers) {
        if (-not $p -or -not $p.Shared -or -not $p.ShareName) { continue }
        [pscustomobject][ordered]@{
            Path            = "\\$Server\$($p.ShareName)"
            ShareName       = [string]$p.ShareName
            Name            = [string]$p.Name
            DriverName      = [string]$p.DriverName
            Location        = [string]$p.Location
            Comment         = [string]$p.Comment
            DriverInstalled = if ($haveDriverList) { $LocalDrivers -contains [string]$p.DriverName } else { $null }
        }
    }
}

function Get-WpePrintServerPrinter {
    <#
        Liest alle freigegebenen Drucker eines Druck-/Fileservers und prueft,
        ob der jeweilige Treiber auf diesem Server bereits installiert ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PrintServer)
    $server = $PrintServer.Trim().TrimStart('\').TrimEnd('\')
    $remote = @(Get-Printer -ComputerName $server -ErrorAction Stop)
    $drivers = $null
    try { $drivers = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { Write-Verbose (Get-WpeText 'Verbose.DriversUnavailable') }
    # Natuerliche Sortierung (Drucker-2 vor Drucker-10)
    $natural = @{ Expression = { [regex]::Replace($_.ShareName, '\d+', { param($m) $m.Value.PadLeft(10, '0') }) } }
    if ($null -ne $drivers) {
        ConvertTo-WpePrintServerPrinter -Printers $remote -Server $server -LocalDrivers $drivers | Sort-Object $natural
    } else {
        ConvertTo-WpePrintServerPrinter -Printers $remote -Server $server | Sort-Object $natural
    }
}

function Get-WpeKnownPrintServer {
    <# Druckserver, zu denen auf diesem Rechner bereits Druckerverbindungen bestehen (haeufigster zuerst). #>
    try {
        Get-Printer -ErrorAction Stop | Where-Object { $_.Name -match '^\\\\[^\\]+\\' } |
            ForEach-Object { $_.Name.TrimStart('\').Split('\')[0] } |
            Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name }
    } catch {
        Write-Verbose (Get-WpeText 'Verbose.LocalPrintersFailed' $_.Exception.Message)
    }
}

function Set-WpePrinterCatalog {
    <#
        Uebernimmt Drucker in die Druckerliste der Konfiguration.
        Mit -ReplaceServer werden vorhandene Eintraege dieses Servers vorher entfernt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Printers,
        [string]$ReplaceServer,
        [string]$ConfigPath = (Get-WpeConfigPath)
    )
    $config = Read-WpeConfig -Path $ConfigPath
    if ($ReplaceServer) {
        $srv = $ReplaceServer.TrimStart('\')
        foreach ($old in @($config.Printers | Where-Object { $_.Server -eq $srv })) { [void]$config.Printers.Remove($old) }
    }
    foreach ($p in $Printers) {
        $path = if ($p -is [string]) { $p } else { [string]$p.Path }
        if (-not $path) { continue }
        foreach ($dup in @($config.Printers | Where-Object { $_.Path -eq $path })) { [void]$config.Printers.Remove($dup) }
        $e = @{ Path = $path }
        if ($p -isnot [string]) {
            foreach ($opt in 'DriverName', 'Location', 'Comment') { if ($p.PSObject.Properties[$opt] -and $p.$opt) { $e[$opt] = [string]$p.$opt } }
        }
        [void]$config.Printers.Add((New-WpeCatalogEntry @e))
    }
    if ($PSCmdlet.ShouldProcess($ConfigPath, (Get-WpeText 'Catalog.SaveAction' $config.Printers.Count))) {
        Save-WpeConfig -Config $config -Path $ConfigPath -Confirm:$false
    }
}

function Install-WpePrinterDriver {
    <#
        Installiert den Treiber eines freigegebenen Druckers auf diesem Server,
        indem der Drucker einmal als Administrator verbunden wird. Eine dabei neu
        angelegte Verbindung wird anschliessend wieder entfernt (der Treiber bleibt).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    if (-not $PSCmdlet.ShouldProcess($Path, (Get-WpeText 'Printer.InstallDriverAction'))) { return }
    $existed = [bool](Get-Printer -Name $Path -ErrorAction SilentlyContinue)
    Add-Printer -ConnectionName $Path -ErrorAction Stop
    if (-not $existed) { Remove-Printer -Name $Path -ErrorAction SilentlyContinue }
}

#endregion

#region Anmelde-Agent (Kernlogik) ----------------------------------------------

function Set-WpeLegacyDefaultPrinterMode {
    <# Schaltet "Windows verwaltet Standarddrucker" fuer den angemeldeten Benutzer ab. Liefert $true bei Aenderung. #>
    $current = Get-ItemProperty -LiteralPath $script:PrinterRegKey -Name LegacyDefaultPrinterMode -ErrorAction SilentlyContinue
    if ($current -and $current.LegacyDefaultPrinterMode -eq 1) { return $false }
    if (-not (Test-Path -LiteralPath $script:PrinterRegKey)) { New-Item -Path $script:PrinterRegKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $script:PrinterRegKey -Name LegacyDefaultPrinterMode -Value 1 -Type DWord
    return $true
}

function New-WpeAgentState {
    <# Zustand des Agenten fuer eine Benutzersitzung. $Log: { param($Message, $Level) ... } #>
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [string]$UserSid,
        [string]$UserName,
        [string[]]$GroupSids = @(),
        [scriptblock]$Log = { param($Message, $Level) Write-Verbose "[$Level] $Message" }
    )
    @{
        ConfigPath  = $ConfigPath
        UserSid     = $UserSid
        UserName    = $UserName
        GroupSids   = $GroupSids
        Log         = $Log
        Stamp       = $null
        Config      = $null
        Target      = $null
        Connected   = @{}
        LegacySet   = $false
        LastProblem = $null
    }
}

function Write-WpeAgentLog {
    param([hashtable]$State, [string]$Message, [string]$Level = 'INFO')
    & $State.Log $Message $Level
}

function Write-WpeAgentProblem {
    <# Warnungen, die sich in jeder Runde wiederholen wuerden, nur bei Aenderung protokollieren. #>
    param([hashtable]$State, [string]$Message)
    if ($State.LastProblem -ne $Message) {
        Write-WpeAgentLog $State $Message 'WARN'
        $State.LastProblem = $Message
    }
}

function Get-WpeAssignmentSource {
    <# "Benutzerzuweisung" bzw. "Gruppe 'X'" - woher eine Vorgabe stammt. #>
    param([Parameter(Mandatory)]$Assignment)
    if ($Assignment.Type -eq 'User') { Get-WpeText 'Agent.ViaUser' } else { Get-WpeText 'Agent.ViaGroup' $Assignment.Name }
}

function Update-WpeAgentConfig {
    <# Laedt die Konfiguration neu, wenn sich die Datei geaendert hat, und ermittelt die Vorgabe. #>
    param([Parameter(Mandatory)][hashtable]$State)
    try {
        $item = Get-Item -LiteralPath $State.ConfigPath -ErrorAction Stop
        $stamp = '{0}|{1}' -f $item.LastWriteTimeUtc.Ticks, $item.Length
    } catch {
        if (-not $State.Config) { Write-WpeAgentProblem $State (Get-WpeText 'Agent.ConfigUnreachable' $State.ConfigPath $_.Exception.Message) }
        return
    }
    if ($stamp -eq $State.Stamp) { return }

    try {
        $config = Read-WpeConfig -Path $State.ConfigPath
    } catch {
        Write-WpeAgentProblem $State (Get-WpeText 'Agent.ConfigUnreadable' $_.Exception.Message)
        return
    }
    # Sprache des Protokolls folgt der Einstellung - auch bei Aenderung waehrend der Sitzung
    $lang = Resolve-WpeLanguage ([string]$config.Settings.Language)
    if ($lang -ne $script:WpeLanguage) { Set-WpeLanguage $lang }

    # Von Hand eingetragene Zuweisungen ohne SID nachtraeglich aufloesen
    foreach ($a in $config.Assignments) {
        if (-not $a.Sid) {
            $sid = Get-WpeAccountSid -Name $a.Name
            if ($sid) { $a.Sid = $sid }
        }
    }

    $target = Resolve-WpeAssignment -Config $config -UserSid $State.UserSid -UserName $State.UserName -GroupSids $State.GroupSids
    $old = if ($State.Target) { $State.Target.Printer } else { $null }
    $new = if ($target) { $target.Printer } else { $null }
    if ($null -eq $State.Stamp -or $old -ne $new) {
        if ($target) {
            Write-WpeAgentLog $State (Get-WpeText 'Agent.Target' $target.Printer (Get-WpeAssignmentSource $target))
        } else {
            Write-WpeAgentLog $State (Get-WpeText 'Agent.NoAssignment')
        }
    }
    $State.Stamp = $stamp
    $State.Config = $config
    $State.Target = $target
    $State.LastProblem = $null
}

function Invoke-WpeAgentCheck {
    <#
        Prueft den Standarddrucker und setzt ihn bei Abweichung zurueck.
        Rueckgabe: 'NoTarget', 'Ok', 'Set', 'Missing' oder 'Failed'
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    if (-not $State.Target) { return 'NoTarget' }
    $settings = $State.Config.Settings
    $pattern = $State.Target.Printer

    if ([bool]$settings.SetLegacyDefaultPrinterMode -and -not $State.LegacySet) {
        try {
            if (Set-WpeLegacyDefaultPrinterMode) { Write-WpeAgentLog $State (Get-WpeText 'Agent.LegacyDisabled') }
            $State.LegacySet = $true
        } catch {
            Write-WpeAgentProblem $State (Get-WpeText 'Agent.LegacyFailed' $_.Exception.Message)
        }
    }

    $current = Get-WpeDefaultPrinter
    if (Test-WpePrinterMatch -Pattern $pattern -Name $current) { $State.LastProblem = $null; return 'Ok' }

    $installed = @(Get-WpeInstalledPrinterNames)
    $match = Find-WpeInstalledPrinter -Pattern $pattern -InstalledNames $installed

    if (-not $match -and [bool]$settings.ConnectNetworkPrinters -and (Test-WpeIsNetworkPrinterPath $pattern)) {
        # Verbindungsversuch hoechstens alle 5 Minuten wiederholen
        $last = $State.Connected[$pattern]
        if (-not $last -or ((Get-Date) - $last).TotalMinutes -ge 5) {
            $State.Connected[$pattern] = Get-Date
            try {
                Add-WpePrinterConnection -Name $pattern -Confirm:$false
                Write-WpeAgentLog $State (Get-WpeText 'Agent.Connected' $pattern)
                $installed = @(Get-WpeInstalledPrinterNames)
                $match = Find-WpeInstalledPrinter -Pattern $pattern -InstalledNames $installed
            } catch {
                Write-WpeAgentProblem $State (Get-WpeText 'Agent.ConnectFailed' $pattern $_.Exception.Message)
                return 'Failed'
            }
        }
    }

    if (-not $match) {
        Write-WpeAgentProblem $State (Get-WpeText 'Agent.Missing' $pattern)
        return 'Missing'
    }

    try {
        Set-WpeDefaultPrinter -Name $match -Confirm:$false
    } catch {
        Write-WpeAgentProblem $State (Get-WpeText 'Agent.SetFailed' $match $_.Exception.Message)
        return 'Failed'
    }
    $now = Get-WpeDefaultPrinter
    if (Test-WpePrinterMatch -Pattern $pattern -Name $now) {
        Write-WpeAgentLog $State (Get-WpeText 'Agent.Set' $match $current)
        $State.LastProblem = $null
        return 'Set'
    }
    Write-WpeAgentProblem $State (Get-WpeText 'Agent.NotApplied' $match $now)
    return 'Failed'
}

function Get-WpeAgentSleepSeconds {
    <#
        Wartezeit bis zur naechsten Pruefung. -1 = Agent beenden.
        Anmeldephase: alle 3 s; danach Sitzungsueberwachung im eingestellten Intervall.
    #>
    param([Parameter(Mandatory)]$Settings, [double]$ElapsedSeconds)
    if ($ElapsedSeconds -lt [int]$Settings.LogonPhaseSeconds) { return 3 }
    if (-not [bool]$Settings.EnforceDuringSession) { return -1 }
    $limit = [int]$Settings.EnforceDurationMinutes
    if ($limit -gt 0 -and $ElapsedSeconds -ge ($limit * 60)) { return -1 }
    return [Math]::Max(5, [int]$Settings.EnforceIntervalSeconds)
}

#endregion

function Get-WpeAgentLogPath {
    <# Pfad des Agent-Protokolls eines Benutzers auf diesem Server (ueber das Benutzerprofil). #>
    param([Parameter(Mandatory)][string]$UserSid)
    $prof = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSid" -ErrorAction SilentlyContinue
    if (-not $prof -or -not $prof.ProfileImagePath) { return $null }
    $root = [Environment]::ExpandEnvironmentVariables($prof.ProfileImagePath)
    return (Join-Path $root 'AppData\Local\WePrintEasy\agent.log')
}

#region Erzwingen auf einem Terminalserver ------------------------------------

function Measure-WpeEditDistance {
    <# Levenshtein-Abstand ohne Gross-/Kleinschreibung (Vorschlaege bei Tippfehlern im Servernamen). #>
    param([string]$First, [string]$Second)
    $s = ([string]$First).ToLowerInvariant()
    $t = ([string]$Second).ToLowerInvariant()
    $prev = New-Object int[] ($t.Length + 1)
    for ($j = 0; $j -le $t.Length; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $s.Length; $i++) {
        $cur = New-Object int[] ($t.Length + 1)
        $cur[0] = $i
        for ($j = 1; $j -le $t.Length; $j++) {
            $cost = if ($s[$i - 1] -ceq $t[$j - 1]) { 0 } else { 1 }
            $cur[$j] = [Math]::Min([Math]::Min($prev[$j] + 1, $cur[$j - 1] + 1), $prev[$j - 1] + $cost)
        }
        $prev = $cur
    }
    return $prev[$t.Length]
}

function Get-WpeAdComputer {
    <# Computer der Domaene. -ServerOnly: nur Windows Server (Auswahl der Terminalserver). #>
    [CmdletBinding()]
    param([switch]$ServerOnly)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher
    $prefix = Get-WpeLdapPrefix
    if ($prefix -ne 'LDAP://') { $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry($prefix.TrimEnd('/')) }
    $searcher.Filter = if ($ServerOnly) { '(&(objectCategory=computer)(operatingSystem=*Server*))' } else { '(objectCategory=computer)' }
    $searcher.PageSize = 500
    foreach ($p in 'name', 'dnshostname', 'operatingsystem') { [void]$searcher.PropertiesToLoad.Add($p) }
    $results = $searcher.FindAll()
    try {
        foreach ($r in $results) {
            $props = $r.Properties
            [pscustomobject]@{
                Name            = [string]$props['name'][0]
                DnsHostName     = if ($props['dnshostname'].Count) { [string]$props['dnshostname'][0] } else { '' }
                OperatingSystem = if ($props['operatingsystem'].Count) { [string]$props['operatingsystem'][0] } else { '' }
            }
        }
    } finally {
        $results.Dispose()
        $searcher.Dispose()
    }
}

function Get-WpeRemoteRegString {
    <# Liest einen Zeichenfolgenwert ueber CIM (StdRegProv) aus der Registry eines anderen Rechners. #>
    param($CimSession, [uint32]$Hive, [string]$Key, [string]$Name)
    foreach ($method in 'GetStringValue', 'GetExpandedStringValue') {
        $r = Invoke-CimMethod -CimSession $CimSession -Namespace 'root\default' -ClassName StdRegProv -MethodName $method `
            -Arguments @{ hDefKey = $Hive; sSubKeyName = $Key; sValueName = $Name }
        $p = $r.PSObject.Properties['sValue']
        if ($r.ReturnValue -eq 0 -and $p -and $p.Value) { return [string]$p.Value }
    }
    return ''
}

function Get-WpeRemoteRegSubKey {
    <# Unterschluessel ueber CIM (StdRegProv) auf einem anderen Rechner. #>
    param($CimSession, [uint32]$Hive, [string]$Key)
    $r = Invoke-CimMethod -CimSession $CimSession -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumKey `
        -Arguments @{ hDefKey = $Hive; sSubKeyName = $Key }
    $p = $r.PSObject.Properties['sNames']
    if ($r.ReturnValue -eq 0 -and $p -and $p.Value) { return [string[]]$p.Value }
    return @()
}

function ConvertTo-WpeAdminSharePath {
    <# C:\Pfad auf Rechner X -> \\X\C$\Pfad #>
    param([string]$ComputerName, [string]$LocalPath)
    if ($LocalPath -match '^([A-Za-z]):\\?(.*)$') { return ('\\{0}\{1}$\{2}' -f $ComputerName, $Matches[1], $Matches[2]) }
    return $LocalPath
}

function Invoke-WpeRemoteForce {
    <#
        Setzt den zugewiesenen Standarddrucker eines Benutzers sofort in seiner Sitzung auf
        einem Terminalserver durch und meldet jeden Schritt live: AD-Benutzer, Zuweisung,
        Server, Installation, Konfiguration, Sitzung, Agent, Agent-Protokoll und Ergebnis.

        Dazu wird auf dem Terminalserver eine einmalige Aufgabe angelegt, die den Agenten
        (-Once) in der Sitzung des Benutzers startet, und danach wieder entfernt.
        Benoetigt Administratorrechte auf dem Terminalserver (CIM und Admin-Freigabe).

        Meldungen (Time, Status, Text) gehen an -Queue (ConcurrentQueue fuer die Oberflaeche),
        sonst farbig an die Konsole. Status: OK, Success, Error, Result, Warning, Log, Info.
        Rueckgabe: Objekt mit Success und Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$UserName,
        [string]$ConfigPath = (Get-WpeConfigPath),
        [System.Management.Automation.PSCredential]$Credential,
        [int]$TimeoutSeconds = 90,
        $Queue
    )
    $ErrorActionPreference = 'Stop'
    $report = {
        param([string]$Status, [string]$Text)
        $o = [pscustomobject]@{ Time = Get-Date; Status = $Status; Text = $Text }
        if ($Queue) {
            $Queue.Enqueue($o)
        } else {
            $color = switch ($Status) { 'OK' { 'Green' } 'Success' { 'Green' } 'Error' { 'Red' } 'Result' { 'Red' } 'Warning' { 'Yellow' } 'Log' { 'DarkCyan' } default { 'Gray' } }
            Write-Host ('{0:HH:mm:ss} {1,-8} {2}' -f $o.Time, (Get-WpeText "Status.$Status"), $Text) -ForegroundColor $color
        }
    }
    $finish = {
        param([bool]$Success, [string]$Message)
        & $report $(if ($Success) { 'Success' } else { 'Result' }) $Message
        [pscustomobject]@{ Success = $Success; Message = $Message }
    }
    $HKLM = [uint32]2147483650
    $HKU = [uint32]2147483651
    $taskPath = '\WePrintEasy\'
    $taskName = ''
    $registered = $false
    $cim = $null
    $drive = $null

    try {
        # 1. Benutzer im AD
        $name = ConvertTo-WpeAccountName $UserName
        & $report 'Info' (Get-WpeText 'Force.SearchUser' $name)
        $user = @(Find-WpeAdObject -Type User -SearchText $name -Exact) | Select-Object -First 1
        if (-not $user) { return (& $finish $false (Get-WpeText 'Force.UserNotFound' $name)) }
        $account = $user.Name
        try { $account = ([System.Security.Principal.SecurityIdentifier]$user.Sid).Translate([System.Security.Principal.NTAccount]).Value } catch { Write-Verbose $_.Exception.Message }
        & $report 'OK' (Get-WpeText 'Force.User' $account $user.DisplayName)

        # 2. Zuweisung laut dieser Konfiguration
        $config = Read-WpeConfig -Path $ConfigPath
        $groupSids = @()
        try { $groupSids = @(Get-WpeAdUserGroupSids -UserSid $user.Sid) } catch { & $report 'Warning' (Get-WpeText 'Force.GroupsFailed' $_.Exception.Message) }
        $target = Resolve-WpeAssignment -Config $config -UserSid $user.Sid -UserName $user.Name -GroupSids $groupSids
        if (-not $target) { return (& $finish $false (Get-WpeText 'Force.NoAssignment' $account $ConfigPath)) }
        & $report 'OK' (Get-WpeText 'Agent.Target' $target.Printer (Get-WpeAssignmentSource $target))

        # 3. Server
        & $report 'Info' (Get-WpeText 'Force.SearchServer' $ComputerName)
        try {
            $fqdn = [System.Net.Dns]::GetHostEntry($ComputerName).HostName
        } catch {
            $hint = ''
            try {
                $short = $ComputerName.Split('.')[0]
                $similar = @(Get-WpeAdComputer | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Distance = (Measure-WpeEditDistance $_.Name $short) } } |
                        Where-Object { $_.Distance -le 2 } | Sort-Object -Property Distance, Name | ForEach-Object { $_.Name })
                if ($similar) { $hint = ' ' + (Get-WpeText 'Force.DidYouMean' ($similar -join ', ')) }
            } catch { Write-Verbose $_.Exception.Message }
            return (& $finish $false ((Get-WpeText 'Force.ServerUnknown' $ComputerName) + $hint))
        }
        & $report 'OK' (Get-WpeText 'Force.ServerFound' $fqdn)

        # 4. Verbindung (DCOM nutzt auch die Anmeldung eines lokalen Kontos, WSMan braucht ein Domaenenkonto)
        $errors = @()
        $protocol = ''
        foreach ($proto in 'Dcom', 'Wsman') {
            $p = @{ ComputerName = $fqdn; SessionOption = (New-CimSessionOption -Protocol $proto); ErrorAction = 'Stop' }
            if ($Credential) { $p.Credential = $Credential }
            try {
                $cim = New-CimSession @p
                $os = Get-CimInstance -CimSession $cim -ClassName Win32_OperatingSystem
                $protocol = $proto
                break
            } catch {
                $errors += "${proto}: $($_.Exception.Message)"
                if ($cim) { Remove-CimSession $cim; $cim = $null }
            }
        }
        if (-not $cim) {
            return (& $finish $false (Get-WpeText 'Force.NoConnection' $fqdn ($errors -join ' | ')))
        }
        $as = if ($Credential) { $Credential.UserName } else { Get-WpeCurrentAccount }
        & $report 'OK' (Get-WpeText 'Force.Connected' $protocol.ToUpper() $as $os.Caption)

        $sysDrive = ([string]$os.SystemDrive).TrimEnd(':')
        $shareRoot = '\\{0}\{1}$' -f $fqdn, $sysDrive
        if ($Credential) {
            try {
                $drive = New-PSDrive -Name ('Wpe' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) -PSProvider FileSystem -Root $shareRoot -Credential $Credential
            } catch { Write-Verbose $_.Exception.Message }
        }
        $shareOk = Test-Path -LiteralPath (Join-Path $shareRoot 'Windows')
        if (-not $shareOk) { & $report 'Warning' (Get-WpeText 'Force.ShareUnreachable' $shareRoot) }

        # 5. Installation auf dem Terminalserver
        $tsInstall = Get-WpeRemoteRegString $cim $HKLM 'SOFTWARE\WePrintEasy' 'InstallPath'
        $tsConfig = Get-WpeRemoteRegString $cim $HKLM 'SOFTWARE\WePrintEasy' 'ConfigPath'
        $tsPolicy = Get-WpeRemoteRegString $cim $HKLM 'SOFTWARE\WePrintEasy' 'ExecutionPolicy'
        if (-not $tsInstall) {
            $suggest = if ($ConfigPath.StartsWith('\\')) { $ConfigPath } else { Get-WpeText 'Force.SuggestCentralPath' $env:COMPUTERNAME }
            return (& $finish $false (Get-WpeText 'Force.NotInstalled' $fqdn $suggest))
        }
        if ($tsPolicy -ne 'AllSigned') { $tsPolicy = 'Bypass' }
        $agentPath = Join-Path $tsInstall 'WePrintEasy-Agent.ps1'
        if ($shareOk -and -not (Test-Path -LiteralPath (ConvertTo-WpeAdminSharePath $fqdn $agentPath))) {
            return (& $finish $false (Get-WpeText 'Force.AgentFileMissing' $fqdn $agentPath))
        }
        & $report 'OK' (Get-WpeText 'Force.Installed' $tsInstall $tsPolicy)

        # 6. Anmelde-Aufgabe
        try {
            $task = Get-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName 'WePrintEasy Agent' -ErrorAction Stop
            if ([string]$task.State -eq 'Disabled') {
                & $report 'Error' (Get-WpeText 'Force.TaskDisabled')
            } else {
                & $report 'OK' (Get-WpeText 'Force.TaskOk')
            }
        } catch {
            & $report 'Error' (Get-WpeText 'Force.TaskMissing')
        }

        # 7. Liest der Terminalserver dieselbe Konfiguration?
        $isLocal = $fqdn.Split('.')[0] -ieq $env:COMPUTERNAME
        if (-not $tsConfig) {
            & $report 'Error' (Get-WpeText 'Force.NoConfigPath')
        } elseif ($tsConfig -ieq $ConfigPath -and ($isLocal -or $tsConfig.StartsWith('\\'))) {
            & $report 'OK' (Get-WpeText 'Force.SameConfig' $tsConfig)
        } elseif ($tsConfig.StartsWith('\\')) {
            try {
                if ((Get-FileHash -LiteralPath $tsConfig).Hash -eq (Get-FileHash -LiteralPath $ConfigPath).Hash) {
                    & $report 'OK' (Get-WpeText 'Force.SameContent' $tsConfig $ConfigPath)
                } else {
                    & $report 'Error' (Get-WpeText 'Force.DifferentContent' $tsConfig $ConfigPath)
                }
            } catch {
                & $report 'Warning' (Get-WpeText 'Force.ConfigUncheckable' $tsConfig $_.Exception.Message)
            }
        } else {
            & $report 'Error' (Get-WpeText 'Force.LocalConfig' $tsConfig $ConfigPath)
        }

        # 8. Sitzung des Benutzers
        $sessions = @()
        try {
            $lines = & { $ErrorActionPreference = 'Continue'; & quser.exe $user.Name "/server:$fqdn" 2>&1 } | ForEach-Object { [string]$_ }
            foreach ($l in $lines) {
                $tokens = @($l.Trim().TrimStart('>') -split '\s+')
                if ($tokens.Count -lt 3 -or $tokens[0] -ine $user.Name) { continue }
                for ($k = 1; $k -lt $tokens.Count - 1; $k++) {
                    if ($tokens[$k] -match '^\d+$') { $sessions += [pscustomobject]@{ Id = [int]$tokens[$k]; State = $tokens[$k + 1] }; break }
                }
            }
        } catch { Write-Verbose $_.Exception.Message }
        if ($sessions) {
            & $report 'OK' (Get-WpeText 'Force.LoggedOn' (($sessions | ForEach-Object { Get-WpeText 'Force.Session' $_.Id $_.State }) -join ', '))
        } elseif (@(Get-WpeRemoteRegSubKey $cim $HKU '') -contains $user.Sid) {
            & $report 'OK' (Get-WpeText 'Force.ProfileLoaded')
        } else {
            return (& $finish $false (Get-WpeText 'Force.NotLoggedOn' $account $fqdn))
        }

        # 9. Zustand vorher
        $winKey = "$($user.Sid)\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        # In RDP-Sitzungen gilt der Wert unter SessionDefaultDevices\<Anmelde-SID> (leer = globaler Wert)
        $readDefault = {
            $device = ''
            foreach ($s in @(Get-WpeRemoteRegSubKey $cim $HKU "$winKey\SessionDefaultDevices")) {
                $device = Get-WpeRemoteRegString $cim $HKU "$winKey\SessionDefaultDevices\$s" 'Device'
                if ($device) { break }
            }
            if (-not $device) { $device = Get-WpeRemoteRegString $cim $HKU $winKey 'Device' }
            $device -replace ',[^,]*,[^,]*$', ''
        }
        $before = & $readDefault
        & $report 'Info' (Get-WpeText 'Force.CurrentDefault' $before)
        if (Test-WpeIsNetworkPrinterPath $target.Printer) {
            $conns = @(Get-WpeRemoteRegSubKey $cim $HKU "$($user.Sid)\Printers\Connections" | ForEach-Object { $_.Replace(',', '\') })
            if (@($conns | Where-Object { Test-WpePrinterMatch -Pattern $target.Printer -Name $_ }).Count) {
                & $report 'OK' (Get-WpeText 'Force.PrinterConnected' $target.Printer)
            } else {
                & $report 'Info' (Get-WpeText 'Force.PrinterNotConnected' $target.Printer)
            }
        }

        # 10. Laeuft der Agent (dauerhafte Ueberwachung) in der Sitzung?
        $findAgent = {
            $agents = @(Get-CimInstance -CimSession $cim -ClassName Win32_Process -Filter "Name='powershell.exe' AND CommandLine LIKE '%WePrintEasy-Agent.ps1%'" |
                    Where-Object { $_.CommandLine -notmatch '\s-Once\b' })
            @(foreach ($proc in $agents) {
                    try { if ((Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid).Sid -eq $user.Sid) { $proc } } catch { Write-Verbose $_.Exception.Message }
                })
        }
        $mine = @(& $findAgent)
        if ($mine) {
            & $report 'OK' (Get-WpeText 'Force.AgentRunning' $mine[0].SessionId $mine[0].CreationDate)
        } else {
            & $report 'Warning' (Get-WpeText 'Force.NoAgent')
        }

        # 11. Agent einmalig in der Sitzung des Benutzers ausfuehren
        $logPath = $null
        $offset = [long]0
        $profilePath = Get-WpeRemoteRegString $cim $HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($user.Sid)" 'ProfileImagePath'
        $profilePath = $profilePath -replace '^%SystemDrive%', "${sysDrive}:"
        if ($shareOk -and $profilePath) {
            $logPath = Join-Path (ConvertTo-WpeAdminSharePath $fqdn $profilePath) 'AppData\Local\WePrintEasy\agent.log'
            if (Test-Path -LiteralPath $logPath) { $offset = (Get-Item -LiteralPath $logPath).Length }
        }

        $winDir = [string]$os.WindowsDirectory
        $psExe = Join-Path $winDir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Agent ueber die Aufgabenplanung in der Sitzung des Benutzers starten (wie bei der Anmeldung)
        $startTask = {
            param([string]$Name, [string]$AgentArgs, [TimeSpan]$Limit, [string]$Description)
            $psArgs = "-NoProfile -NonInteractive -ExecutionPolicy $tsPolicy -WindowStyle Hidden -File `"$agentPath`"$AgentArgs"
            $action = if ([int]$os.BuildNumber -ge 20348) {
                New-ScheduledTaskAction -Execute (Join-Path $winDir 'System32\conhost.exe') -Argument "--headless `"$psExe`" $psArgs"
            } else {
                New-ScheduledTaskAction -Execute $psExe -Argument $psArgs
            }
            $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit $Limit
            $taskObj = New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Description $Description
            [void](Register-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName $Name -InputObject $taskObj -Force)
            Start-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName $Name
        }
        # Reste frueherer Laeufe entfernen (beendete Ueberwachungen, nicht geloeschte Einmal-Aufgaben;
        # "Erzwingen *" stammt von Versionen vor der Sprachauswahl)
        $ConfirmPreference = 'None'
        foreach ($old in @(Get-ScheduledTask -CimSession $cim -TaskPath $taskPath -ErrorAction SilentlyContinue | Where-Object { ($_.TaskName -like 'Force *' -or $_.TaskName -like 'Erzwingen *') -and [string]$_.State -ne 'Running' })) {
            try { Unregister-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName $old.TaskName } catch { Write-Verbose $_.Exception.Message }
        }
        $taskName = 'Force {0} {1:yyyyMMdd-HHmmss}' -f $user.Name, (Get-Date)
        $registered = $true
        & $startTask $taskName ' -Once' (New-TimeSpan -Minutes 5) (Get-WpeText 'Force.TaskDescriptionOnce')
        & $report 'Info' (Get-WpeText 'Force.AgentStarted' $account)

        $newLines = New-Object System.Collections.ArrayList
        $readLog = {
            if (-not $logPath) { return }
            try {
                $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                try {
                    if ($fs.Length -lt $script:WpeForceOffset) { $script:WpeForceOffset = 0 }
                    if ($fs.Length -gt $script:WpeForceOffset) {
                        [void]$fs.Seek($script:WpeForceOffset, [System.IO.SeekOrigin]::Begin)
                        $buf = New-Object byte[] ($fs.Length - $script:WpeForceOffset)
                        $n = $fs.Read($buf, 0, $buf.Length)
                        $script:WpeForceOffset += $n
                        $script:WpeForcePending += [Text.Encoding]::UTF8.GetString($buf, 0, $n)
                    }
                } finally { $fs.Dispose() }
            } catch { return }
            while (($i = $script:WpeForcePending.IndexOf("`n")) -ge 0) {
                $line = $script:WpeForcePending.Substring(0, $i).Trim().Trim([char]0xFEFF)
                $script:WpeForcePending = $script:WpeForcePending.Substring($i + 1)
                if ($line) { [void]$newLines.Add($line); & $report 'Log' $line }
            }
        }
        $script:WpeForceOffset = $offset
        $script:WpeForcePending = ''

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $nextPoll = Get-Date
        $done = $false
        $lastResult = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 700
            & $readLog
            if ((Get-Date) -lt $nextPoll) { continue }
            $nextPoll = (Get-Date).AddSeconds(2)
            $t = Get-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName $taskName
            $info = Get-ScheduledTaskInfo -CimSession $cim -TaskPath $taskPath -TaskName $taskName
            if ([string]$t.State -notin 'Running', 'Queued' -and $info.LastRunTime) {
                $lastResult = [int64]$info.LastTaskResult
                Start-Sleep -Milliseconds 800
                & $readLog
                $done = $true
                break
            }
        }

        if (-not $done) {
            & $report 'Warning' (Get-WpeText 'Force.Timeout' $TimeoutSeconds)
        } elseif ($lastResult -ne 0) {
            $code = '0x{0:X8}' -f ($lastResult -band 0xFFFFFFFFL)
            $why = switch ($code) {
                '0x800710E0' { ' - ' + (Get-WpeText 'Force.CodeRejected') }
                '0x00000001' { ' - ' + (Get-WpeText 'Force.CodeScriptError') }
                default { '' }
            }
            & $report 'Error' ((Get-WpeText 'Force.AgentExitCode' $code) + $why)
        } else {
            & $report 'OK' (Get-WpeText 'Force.AgentDone')
        }
        if (-not $mine) {
            # Dauerhafte Ueberwachung: eigene Aufgabe ohne Zeitlimit. Sie bleibt bestehen, solange der
            # Agent laeuft (bis zur Abmeldung), und wird beim naechsten Erzwingen danach entfernt.
            $monitorName = 'Force monitor {0} {1:yyyyMMdd-HHmmss}' -f $user.Name, (Get-Date)
            & $startTask $monitorName '' ([TimeSpan]::Zero) (Get-WpeText 'Force.TaskDescriptionMonitor')
            $deadline = (Get-Date).AddSeconds(20)
            do { Start-Sleep -Seconds 1; & $readLog; $now = @(& $findAgent) } while (-not $now -and (Get-Date) -lt $deadline)
            if ($now) {
                & $report 'OK' (Get-WpeText 'Force.MonitorRunning' $now[0].SessionId)
            } else {
                & $report 'Warning' (Get-WpeText 'Force.MonitorNotRunning')
            }
        }

        # 12. Ergebnis
        $after = & $readDefault
        if (Test-WpePrinterMatch -Pattern $target.Printer -Name $after) {
            $msg = if ($before -eq $after) { Get-WpeText 'Force.AlreadyCorrect' $account $after } else { Get-WpeText 'Force.NowSet' $account $after $before }
            return (& $finish $true $msg)
        }
        $msg = Get-WpeText 'Force.StillWrong' $account $after $target.Printer
        $reason = @($newLines | Where-Object { $_ -match '\[(WARN|ERROR)\]' }) | Select-Object -Last 1
        if ($reason) {
            $msg += ' ' + (Get-WpeText 'Force.ReasonAgent' ($reason -replace '^\S+ \S+ \[\w+\] ', ''))
        } elseif ($logPath -and $newLines.Count -eq 0) {
            $msg += ' ' + (Get-WpeText 'Force.AgentSilent')
        }
        return (& $finish $false $msg)
    } catch {
        return (& $finish $false (Get-WpeText 'Force.Aborted' $_.Exception.Message))
    } finally {
        if ($registered -and $cim) {
            # Kein -Confirm: wird ueber DCOM nicht unterstuetzt (ConfirmPreference = None verhindert die Rueckfrage)
            $ConfirmPreference = 'None'
            try { Unregister-ScheduledTask -CimSession $cim -TaskPath $taskPath -TaskName $taskName } catch { & $report 'Warning' (Get-WpeText 'Force.TempTaskNotRemoved' "$taskPath$taskName" $_.Exception.Message) }
        }
        if ($cim) { Remove-CimSession $cim }
        if ($drive) { Remove-PSDrive -Name $drive.Name -Force -ErrorAction SilentlyContinue }
    }
}

#endregion

function Get-WpeExecutionPolicy {
    <#
        ExecutionPolicy fuer den Start der installierten Skripte: AllSigned, wenn
        bei der Installation signiert wurde (und -Path gueltig signiert ist), sonst Bypass.
    #>
    param([string]$Path)
    $policy = ''
    try { $policy = [string](Get-ItemProperty -LiteralPath $script:RegistryKey -Name ExecutionPolicy -ErrorAction Stop).ExecutionPolicy } catch { Write-Verbose (Get-WpeText 'Verbose.NoExecutionPolicy') }
    if ($policy -ne 'AllSigned') { return 'Bypass' }
    # z. B. Start aus dem Quellordner: unsignierte Dateien wuerden unter AllSigned nicht laufen
    if ($Path -and (Get-AuthenticodeSignature -LiteralPath $Path).Status -ne 'Valid') { return 'Bypass' }
    return 'AllSigned'
}

function Get-WpeSignatureStatus {
    <# Signaturstatus aller Skripte im Installationsordner. #>
    param([Parameter(Mandatory)][string]$InstallPath)
    Get-ChildItem -LiteralPath $InstallPath -File | Where-Object { $_.Extension -in '.ps1', '.psm1' } | ForEach-Object {
        $sig = Get-AuthenticodeSignature -LiteralPath $_.FullName
        [pscustomobject]@{
            Name        = $_.Name
            Status      = [string]$sig.Status
            NotAfter    = if ($sig.SignerCertificate) { $sig.SignerCertificate.NotAfter } else { $null }
            TimeStamped = $null -ne $sig.TimeStamperCertificate
        }
    }
}

#region Info / Fehler melden -------------------------------------------------

function Get-WpeAboutInfo {
    <# Version, Autor und Projekt-Links (Info-Dialog). #>
    [pscustomobject][ordered]@{
        Version    = $script:WpeVersion
        Author     = $script:WpeAuthor
        AuthorUrl  = $script:WpeAuthorUrl
        ProjectUrl = $script:WpeProjectUrl
        IssuesUrl  = "$($script:WpeProjectUrl)/issues"
        License    = $script:WpeLicense
        # HEAD = Standardzweig des Repositorys
        LicenseUrl = "$($script:WpeProjectUrl)/blob/HEAD/LICENSE"
    }
}

function Get-WpeSystemInfo {
    <#
        Systeminformationen fuer Fehlermeldungen (Name -> Wert). Enthaelt bewusst keine Rechner-,
        Domaenen-, Benutzer- oder Servernamen: der Text landet in einem oeffentlichen GitHub-Issue.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath = (Get-WpeConfigPath))
    $info = [ordered]@{}
    $info['WePrintEasy'] = $script:WpeVersion

    $installPath = $null
    try { $installPath = (Get-ItemProperty -LiteralPath $script:RegistryKey -Name InstallPath -ErrorAction Stop).InstallPath } catch { Write-Verbose (Get-WpeText 'Verbose.NotInstalled') }
    $info[(Get-WpeText 'SysInfo.Installed')] = if ($installPath -and (Test-Path -LiteralPath (Join-Path $installPath 'WePrintEasy-Agent.ps1'))) { Get-WpeText 'SysInfo.InstalledYes' $installPath } else { Get-WpeText 'SysInfo.No' }
    $info[(Get-WpeText 'SysInfo.Execution')] = if ((Get-WpeExecutionPolicy) -eq 'AllSigned') { Get-WpeText 'SysInfo.Signed' } else { Get-WpeText 'SysInfo.Unsigned' }

    $where = if ($ConfigPath.StartsWith('\\')) { Get-WpeText 'SysInfo.ConfigShare' } else { Get-WpeText 'SysInfo.ConfigLocal' }
    try {
        $cfg = Read-WpeConfig -Path $ConfigPath
        $u = @($cfg.Assignments | Where-Object { $_.Type -eq 'User' }).Count
        $g = @($cfg.Assignments | Where-Object { $_.Type -eq 'Group' }).Count
        $info[(Get-WpeText 'SysInfo.Config')] = Get-WpeText 'SysInfo.ConfigValue' $where $u $g $cfg.Printers.Count
    } catch {
        $info[(Get-WpeText 'SysInfo.Config')] = Get-WpeText 'SysInfo.ConfigUnreadable' $where
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption, Version, OSArchitecture -ErrorAction SilentlyContinue
    $info[(Get-WpeText 'SysInfo.OS')] = if ($os) { '{0} ({1}, {2})' -f $os.Caption, $os.Version, $os.OSArchitecture } else { [Environment]::OSVersion.VersionString }
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -Property DomainRole -ErrorAction SilentlyContinue
    if ($cs) {
        $role = switch ([int]$cs.DomainRole) { 0 { 'WorkstationStandalone' } 1 { 'WorkstationMember' } 2 { 'ServerStandalone' } 3 { 'ServerMember' } default { 'DomainController' } }
        $info[(Get-WpeText 'SysInfo.Role')] = Get-WpeText "SysInfo.Role.$role"
    }
    # SESSIONNAME fehlt in manchen Startwegen (z. B. geplante Aufgabe) - dann aus der fluechtigen Umgebung der Sitzung
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $sessionName = $env:SESSIONNAME
    if (-not $sessionName) { $sessionName = (Get-ItemProperty -LiteralPath "HKCU:\Volatile Environment\$sessionId" -Name SESSIONNAME -ErrorAction SilentlyContinue).SESSIONNAME }
    $session = if ($sessionId -eq 0) { 'Service' } elseif ($sessionName -like 'RDP-*') { 'Remote' } elseif ($sessionName) { 'Console' } else { 'Unknown' }
    $info[(Get-WpeText 'SysInfo.Session')] = Get-WpeText "SysInfo.Session.$session"
    $info['PowerShell'] = '{0} ({1})' -f $PSVersionTable.PSVersion, $(if ($PSVersionTable.PSObject.Properties['PSEdition']) { $PSVersionTable.PSEdition } else { 'Desktop' })
    $release = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
    if ($release) {
        $net = if ($release -ge 533320) { '4.8.1' } elseif ($release -ge 528040) { '4.8' } else { Get-WpeText 'SysInfo.NetOlder' }
        $info['.NET Framework'] = "$net (Release $release)"
    }
    $info[(Get-WpeText 'SysInfo.Language')] = Get-WpeText 'SysInfo.LanguageValue' (Get-Culture).Name (Get-UICulture).Name $script:WpeLanguage
    $info
}

function Get-WpeIssueUrl {
    <# Link "Neues Issue" auf GitHub, vorausgefuellt mit einer Vorlage und den Systeminformationen. #>
    param([System.Collections.IDictionary]$SystemInfo = (Get-WpeSystemInfo))
    $lines = foreach ($k in $SystemInfo.Keys) { "- ${k}: $($SystemInfo[$k])" }
    $body = Get-WpeText 'Issue.Body' '```' ($lines -join "`n")
    '{0}/issues/new?title={1}&body={2}' -f $script:WpeProjectUrl, [Uri]::EscapeDataString((Get-WpeText 'Issue.Title')), [Uri]::EscapeDataString(($body -replace "`r", ''))
}

#endregion

#region Systempruefung --------------------------------------------------------

function Get-WpeSystemStatus {
    <#
        Prueft die Einrichtung auf diesem Server. Liefert Objekte mit
        Id (feste Kennung der Pruefung), Status (OK / Warning / Error / Info),
        Check (Bezeichnung), Detail und Fix (Kennung fuer eine Behebung).
        Check und Detail sind in der eingestellten Sprache.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath = (Get-WpeConfigPath))

    $results = New-Object System.Collections.ArrayList
    function Add-Result([string]$Id, [string]$Status, [string]$Detail, [string]$Fix = '', [string]$Check = (Get-WpeText "Check.$Id")) {
        [void]$results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Check = $Check; Detail = $Detail; Fix = $Fix })
    }

    # 1. Installation
    $installPath = $null
    try { $installPath = (Get-ItemProperty -LiteralPath $script:RegistryKey -Name InstallPath -ErrorAction Stop).InstallPath } catch { Write-Verbose (Get-WpeText 'Verbose.NotInstalled') }
    if ($installPath -and (Test-Path -LiteralPath (Join-Path $installPath 'WePrintEasy-Agent.ps1'))) {
        Add-Result 'Install' 'OK' $installPath
    } else {
        Add-Result 'Install' 'Error' (Get-WpeText 'Check.Install.Missing') 'Install'
        $installPath = $null
    }

    # 1b. Signatur
    if ($installPath) {
        if ((Get-WpeExecutionPolicy) -eq 'AllSigned') {
            $sigs = @(Get-WpeSignatureStatus -InstallPath $installPath)
            $bad = @($sigs | Where-Object { $_.Status -ne 'Valid' })
            $expiring = @($sigs | Where-Object { -not $_.TimeStamped -and $_.NotAfter -and $_.NotAfter -lt (Get-Date).AddDays(60) } | Select-Object -First 1)
            if ($bad) {
                Add-Result 'Signature' 'Error' (Get-WpeText 'Check.Signature.Invalid' (($bad | ForEach-Object { "$($_.Name) ($($_.Status))" }) -join ', ')) 'Install'
            } elseif ($expiring) {
                Add-Result 'Signature' 'Warning' (Get-WpeText 'Check.Signature.Expiring' $expiring[0].NotAfter) 'Install'
            } else {
                Add-Result 'Signature' 'OK' (Get-WpeText 'Check.Signature.Ok' $sigs.Count)
            }
        } else {
            Add-Result 'Signature' 'Info' (Get-WpeText 'Check.Signature.Unsigned')
        }
    }

    # 2. Geplante Aufgabe
    try {
        $task = Get-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent' -ErrorAction Stop
        if ([string]$task.State -eq 'Disabled') {
            Add-Result 'Task' 'Error' (Get-WpeText 'Check.Task.Disabled') 'EnableTask'
        } else {
            Add-Result 'Task' 'OK' (Get-WpeText 'Check.Task.Ok' @($task.Triggers).Count)
        }
    } catch {
        Add-Result 'Task' 'Error' (Get-WpeText 'Check.Task.Missing') 'Install'
    }

    # 3. Konfiguration
    $config = $null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $config = Read-WpeConfig -Path $ConfigPath
            Add-Result 'ConfigRead' 'OK' $ConfigPath
        } catch {
            Add-Result 'ConfigRead' 'Error' $_.Exception.Message
        }
    } else {
        Add-Result 'ConfigRead' 'Error' (Get-WpeText 'Check.ConfigRead.Missing' $ConfigPath)
    }
    if (Test-WpeConfigWritable -Path $ConfigPath) {
        Add-Result 'ConfigWrite' 'OK' (Get-WpeText 'Check.ConfigWrite.Ok')
    } else {
        Add-Result 'ConfigWrite' 'Warning' (Get-WpeText 'Check.ConfigWrite.No')
    }

    # 4. Zuweisungen
    if ($config) {
        $u = @($config.Assignments | Where-Object { $_.Type -eq 'User' }).Count
        $g = @($config.Assignments | Where-Object { $_.Type -eq 'Group' }).Count
        if ($u + $g -eq 0) {
            Add-Result 'Assignments' 'Warning' (Get-WpeText 'Check.Assignments.None')
        } else {
            Add-Result 'Assignments' 'OK' (Get-WpeText 'Check.Assignments.Count' $u $g)
        }
    }

    # 5. RDS-Richtlinien
    $tsKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    $ts = Get-ItemProperty -LiteralPath $tsKey -ErrorAction SilentlyContinue
    if ($ts -and $ts.PSObject.Properties['fForceClientLptDef'] -and $ts.fForceClientLptDef -eq 0) {
        Add-Result 'ClientDefault' 'OK' (Get-WpeText 'Check.ClientDefault.Ok')
    } else {
        Add-Result 'ClientDefault' 'Warning' (Get-WpeText 'Check.ClientDefault.Recommend') 'Policy'
    }
    if ($ts -and $ts.PSObject.Properties['fDisableCpm'] -and $ts.fDisableCpm -eq 1) {
        Add-Result 'Redirection' 'Info' (Get-WpeText 'Check.Redirection.Off')
    } else {
        Add-Result 'Redirection' 'Info' (Get-WpeText 'Check.Redirection.On')
    }

    # 6. Netzwerkdrucker: Druckserver erreichbar und Treiber lokal vorhanden?
    if ($config) {
        $byServer = @{}
        foreach ($a in $config.Assignments) {
            if (Test-WpeIsNetworkPrinterPath $a.Printer) {
                $parts = $a.Printer.TrimStart('\').Split('\')
                if (-not $byServer.ContainsKey($parts[0])) { $byServer[$parts[0]] = New-Object System.Collections.ArrayList }
                if (-not $byServer[$parts[0]].Contains($parts[1])) { [void]$byServer[$parts[0]].Add($parts[1]) }
            }
        }
        $localDrivers = $null
        try { $localDrivers = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { Write-Verbose (Get-WpeText 'Verbose.DriversUnavailable') }
        foreach ($server in ($byServer.Keys | Sort-Object)) {
            $label = Get-WpeText 'Check.PrintServer' $server
            try {
                $remote = @(Get-Printer -ComputerName $server -ErrorAction Stop)
            } catch {
                Add-Result 'PrintServer' 'Error' (Get-WpeText 'Check.PrintServer.Unreachable' $_.Exception.Message) -Check $label
                continue
            }
            $missingShares = @(); $missingDrivers = @()
            foreach ($share in $byServer[$server]) {
                $p = $remote | Where-Object { $_.ShareName -eq $share } | Select-Object -First 1
                if (-not $p) { $missingShares += $share; continue }
                if ($null -ne $localDrivers -and $localDrivers -notcontains $p.DriverName) { $missingDrivers += "$share ($($p.DriverName))" }
            }
            if ($missingShares) {
                Add-Result 'PrintServer' 'Error' (Get-WpeText 'Check.PrintServer.MissingShares' ($missingShares -join ', ')) -Check $label
            } elseif ($missingDrivers) {
                Add-Result 'PrintServer' 'Warning' (Get-WpeText 'Check.PrintServer.MissingDrivers' ($missingDrivers -join ', ')) -Check $label
            } else {
                Add-Result 'PrintServer' 'OK' (Get-WpeText 'Check.PrintServer.Ok' $byServer[$server].Count) -Check $label
            }
        }
    }

    $results
}

function Set-WpeClientDefaultPrinterPolicy {
    <# Setzt die RDS-Richtlinie "Standardclientdrucker nicht als Standarddrucker in einer Sitzung festlegen" (Admin). #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $tsKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    if ($PSCmdlet.ShouldProcess($tsKey, 'fForceClientLptDef = 0')) {
        if (-not (Test-Path -LiteralPath $tsKey)) { New-Item -Path $tsKey -Force | Out-Null }
        Set-ItemProperty -LiteralPath $tsKey -Name fForceClientLptDef -Value 0 -Type DWord
    }
}

#endregion

# Sprache beim Laden: Vorgabe des Servers bzw. Englisch (Programme stellen danach ggf. per Initialize-WpeLanguage um)
Set-WpeLanguage ''

Export-ModuleMember -Function @(
    'Get-WpeSupportedLanguage', 'Set-WpeLanguage', 'Get-WpeLanguage', 'Initialize-WpeLanguage', 'Get-WpeText',
    'Get-WpeShortcutPath', 'Rename-WpeShortcut', 'Get-WpeAssignmentSource',
    'Get-WpeDefaultSettings', 'Get-WpeConfigPath', 'Read-WpeConfig', 'Save-WpeConfig', 'Test-WpeConfigWritable',
    'New-WpeAssignmentObject', 'ConvertTo-WpeAccountName',
    'Get-WpeAssignment', 'Set-WpeAssignment', 'Remove-WpeAssignment', 'Resolve-WpeAssignment',
    'Get-WpeCurrentAccount', 'ConvertTo-WpeLdapFilterValue', 'Get-WpeAccountSid', 'Find-WpeAdObject', 'Get-WpeAdUserGroupSids',
    'Test-WpePrinterMatch', 'Find-WpeInstalledPrinter', 'Test-WpeIsNetworkPrinterPath',
    'Get-WpeDefaultPrinter', 'Get-WpeInstalledPrinterNames', 'Set-WpeDefaultPrinter', 'Add-WpePrinterConnection', 'Get-WpePrinterList',
    'Set-WpeLegacyDefaultPrinterMode', 'New-WpeAgentState', 'Update-WpeAgentConfig', 'Invoke-WpeAgentCheck', 'Get-WpeAgentSleepSeconds',
    'Write-WpeAgentLog', 'Write-WpeAgentProblem',
    'Get-WpeSystemStatus', 'Set-WpeClientDefaultPrinterPolicy',
    'New-WpeCatalogEntry', 'ConvertTo-WpePrintServerPrinter', 'Get-WpePrintServerPrinter', 'Get-WpeKnownPrintServer',
    'Set-WpePrinterCatalog', 'Install-WpePrinterDriver', 'Get-WpeAgentLogPath',
    'Get-WpeExecutionPolicy', 'Get-WpeSignatureStatus',
    'Measure-WpeEditDistance', 'Get-WpeAdComputer', 'Invoke-WpeRemoteForce',
    'Get-WpeAboutInfo', 'Get-WpeSystemInfo', 'Get-WpeIssueUrl'
)
