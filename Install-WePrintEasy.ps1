#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installiert WePrintEasy auf einem Terminalserver (RD-Sitzungshost).
    Grafische Alternative: Setup.cmd

.DESCRIPTION
    - kopiert die Programmdateien nach "C:\Program Files\WePrintEasy"
    - legt die Konfiguration an (lokal oder zentral auf einer Freigabe)
    - setzt die Berechtigungen der lokalen Konfiguration
      (Benutzer: lesen, Administratoren + optionale Editor-Gruppe: aendern)
    - registriert die geplante Aufgabe "WePrintEasy Agent", die bei jeder
      Benutzeranmeldung und Wiederverbindung im Kontext des Benutzers startet
    - uebernimmt optional die freigegebenen Drucker eines Druck-/Fileservers
      in die Druckerliste und installiert fehlende Treiber
    - legt eine Verknuepfung unter "Windows-Tools" an
    - signiert optional alle Skripte (Authenticode); Agent und Verwaltung
      starten dann mit "-ExecutionPolicy AllSigned" statt "Bypass"

    Das Skript kann gefahrlos erneut ausgefuehrt werden (Update). Eine einmal
    eingerichtete Signierung bleibt bei Updates erhalten (Abschalten: -NoSigning).

.PARAMETER ConfigPath
    Pfad der Konfigurationsdatei. Bei mehreren Sitzungshosts eine zentrale
    Freigabe verwenden, z. B. \\fileserver\WePrintEasy$\config.json
    Standard: C:\ProgramData\WePrintEasy\config.json

.PARAMETER PrintServer
    Druck-/Fileserver, dessen freigegebene Drucker in die Druckerliste uebernommen werden.

.PARAMETER ImportPrinters
    Welche Drucker des PrintServers uebernommen werden:
    WithLocalDriver (Standard) = nur Drucker, deren Treiber hier schon installiert ist
    All = alle freigegebenen Drucker;  None = keine

.PARAMETER PrinterListFile
    Textdatei mit den zu uebernehmenden Druckern (eine Zeile je \\server\freigabe).
    Hat Vorrang vor -ImportPrinters.

.PARAMETER InstallMissingDrivers
    Fehlende Treiber der uebernommenen Drucker auf diesem Server installieren.

.PARAMETER EditorGroup
    Optionale AD-Gruppe, die Zuweisungen pflegen darf (nur bei lokaler
    Konfiguration; bei einer Freigabe die Rechte dort setzen). Ohne Angabe
    bleibt bei einem Update die bisherige Editor-Gruppe erhalten.

.PARAMETER DisableClientDefaultPrinter
    Setzt zusaetzlich die Richtlinie "Standardclientdrucker nicht als
    Standarddrucker in einer Sitzung festlegen" (HKLM, RDS). Empfohlen.

.PARAMETER SigningCertificateThumbprint
    Fingerabdruck eines vorhandenen Codesignatur-Zertifikats (mit privatem
    Schluessel in Cert:\LocalMachine\My oder Cert:\CurrentUser\My), z. B. aus
    der Firmen-CA. Das Zertifikat wird als vertrauenswuerdiger Herausgeber
    eingetragen (LocalMachine\TrustedPublisher).

.PARAMETER SelfSignedCertificate
    Erstellt ein selbstsigniertes Codesignatur-Zertifikat fuer diesen Server
    (5 Jahre gueltig, Schluessel nicht exportierbar) und vertraut ihm lokal
    (LocalMachine\Root + TrustedPublisher). Ein bereits von WePrintEasy erstelltes
    Zertifikat wird weiterverwendet und 30 Tage vor Ablauf automatisch erneuert.

.PARAMETER TimestampServer
    Optionaler Zeitstempeldienst (z. B. http://timestamp.digicert.com). Mit
    Zeitstempel bleiben Signaturen auch nach Ablauf des Zertifikats gueltig.
    Benoetigt Internetzugang des Servers.

.PARAMETER NoSigning
    Skripte nicht signieren (bzw. eine vorhandene Signierung abschalten).

.PARAMETER Language
    Sprache von Installer, Verwaltung und Agent-Protokoll: en (Standard) oder de.
    Ohne Angabe bleibt bei einem Update die bisherige Sprache erhalten.

.EXAMPLE
    .\Install-WePrintEasy.ps1 -PrintServer fs01 -DisableClientDefaultPrinter

.EXAMPLE
    .\Install-WePrintEasy.ps1 -PrintServer fs01 -DisableClientDefaultPrinter -SelfSignedCertificate

.EXAMPLE
    .\Install-WePrintEasy.ps1 -ConfigPath '\\fs01\WePrintEasy$\config.json' -PrintServer fs01 -ImportPrinters All -InstallMissingDrivers -DisableClientDefaultPrinter
#>
[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:ProgramFiles 'WePrintEasy'),
    [string]$ConfigPath,
    [string]$PrintServer,
    [ValidateSet('WithLocalDriver', 'All', 'None')][string]$ImportPrinters = 'WithLocalDriver',
    [string]$PrinterListFile,
    [switch]$InstallMissingDrivers,
    [string]$EditorGroup,
    [switch]$DisableClientDefaultPrinter,
    [switch]$NoShortcut,
    [string]$SigningCertificateThumbprint,
    [switch]$SelfSignedCertificate,
    [string]$TimestampServer,
    [switch]$NoSigning,
    [ValidateSet('en', 'de')][string]$Language
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'src'
$taskName = 'WePrintEasy Agent'
$taskPath = '\WePrintEasy\'
$regKey = 'HKLM:\SOFTWARE\WePrintEasy'
$warnings = 0

# Texte schon vor dem Kopieren aus dem Quellordner; ohne -Language gilt die bisherige Sprache des Servers (sonst Englisch)
Import-Module (Join-Path $source 'WePrintEasy.psm1') -Force
if (-not $Language) { $Language = Get-WpeLanguage }
Set-WpeLanguage $Language

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Warn([string]$Text) { Write-Host "    $(Get-WpeText 'Install.WarningPrefix') $Text" -ForegroundColor Yellow; $script:warnings++ }

function Get-SigningCertificate([string]$Thumbprint) {
    # Beim Kopieren aus der Zertifikatsanzeige geraten oft Leer- und Steuerzeichen mit hinein
    $t = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    foreach ($store in 'Cert:\LocalMachine\My', 'Cert:\CurrentUser\My') {
        $c = Get-ChildItem -Path $store -CodeSigningCert |
            Where-Object { $_.Thumbprint -eq $t -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } | Select-Object -First 1
        if ($c) { return $c }
    }
    return $null
}

function Add-MachineCertificate($Certificate, [string]$StoreName) {
    # Nur den oeffentlichen Teil eintragen
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, 'LocalMachine')
    $store.Open('ReadWrite')
    try {
        if ($store.Certificates.Find('FindByThumbprint', $Certificate.Thumbprint, $false).Count -eq 0) {
            $store.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $Certificate.RawData)))
        }
    } finally { $store.Close() }
}

function Remove-CreatedCertificate([string]$Thumbprint) {
    foreach ($s in 'My', 'Root', 'TrustedPublisher') {
        $p = "Cert:\LocalMachine\$s\$Thumbprint"
        if (-not (Test-Path -LiteralPath $p)) { continue }
        if ($s -eq 'My') { Remove-Item -LiteralPath $p -DeleteKey } else { Remove-Item -LiteralPath $p }
    }
}

if (@(@([bool]$SigningCertificateThumbprint, $SelfSignedCertificate.IsPresent, $NoSigning.IsPresent) -eq $true).Count -gt 1) {
    throw (Get-WpeText 'Install.SigningParamConflict')
}

$defaultConfig = Join-Path $env:ProgramData 'WePrintEasy\config.json'
if (-not $ConfigPath) {
    # Bei einem Update den bisherigen Pfad beibehalten
    $existing = Get-ItemProperty -LiteralPath $regKey -Name ConfigPath -ErrorAction SilentlyContinue
    $ConfigPath = if ($existing -and $existing.ConfigPath) { $existing.ConfigPath } else { $defaultConfig }
}
$isUnc = $ConfigPath.StartsWith('\\')

# --- 1. Dateien ----------------------------------------------------------------
Write-Step (Get-WpeText 'Install.CopyFiles' $InstallPath)
if (-not (Test-Path -LiteralPath $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath | Out-Null }
$files = @('WePrintEasy.psm1', 'WePrintEasy.Gui.ps1', 'WePrintEasy-Agent.ps1', 'WePrintEasy-Admin.ps1', 'WePrintEasy.ico') +
    @(Get-ChildItem -LiteralPath $source -Filter 'WePrintEasy.Strings.*.psd1' | ForEach-Object { $_.Name })
foreach ($f in $files) {
    Copy-Item -LiteralPath (Join-Path $source $f) -Destination $InstallPath -Force
}
# Die MIT-Lizenz verlangt, dass ihr Text jeder Kopie beiliegt
$license = Join-Path $PSScriptRoot 'LICENSE'
if (Test-Path -LiteralPath $license) { Copy-Item -LiteralPath $license -Destination $InstallPath -Force }
# Aus dem Internet geladene Dateien entsperren (Zone.Identifier)
Get-ChildItem -LiteralPath $InstallPath -File | Unblock-File

# --- 2. Signatur -----------------------------------------------------------------
$reg = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
$prevThumb = if ($reg -and $reg.PSObject.Properties['SigningThumbprint']) { [string]$reg.SigningThumbprint } else { '' }
$prevCreated = [bool]($prevThumb -and $reg.PSObject.Properties['SigningCertCreated'] -and $reg.SigningCertCreated -eq 1)
if (-not $TimestampServer -and $reg -and $reg.PSObject.Properties['TimestampServer']) { $TimestampServer = [string]$reg.TimestampServer }

$cert = $null
$certCreated = $false
$newCert = $null
try {
    if ($NoSigning) {
        Write-Step (Get-WpeText 'Install.NoSigning')
    } elseif ($SigningCertificateThumbprint) {
        $cert = Get-SigningCertificate $SigningCertificateThumbprint
        if (-not $cert) { throw (Get-WpeText 'Install.CertNotFound' $SigningCertificateThumbprint) }
        $certCreated = $prevCreated -and $cert.Thumbprint -eq $prevThumb
    } elseif ($SelfSignedCertificate -or $prevCreated) {
        if ($prevCreated) { $cert = Get-SigningCertificate $prevThumb }
        if ($cert -and $cert.NotAfter -lt (Get-Date).AddDays(30)) {
            Write-Step (Get-WpeText 'Install.CertRenew' $cert.NotAfter.ToString('d'))
            $cert = $null
        }
        if (-not $cert) {
            Write-Step (Get-WpeText 'Install.CertCreate')
            $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=WePrintEasy Codesignatur ($env:COMPUTERNAME)" `
                -CertStoreLocation 'Cert:\LocalMachine\My' -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
                -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5)
            $newCert = $cert
        }
        $certCreated = $true
    } elseif ($prevThumb) {
        $cert = Get-SigningCertificate $prevThumb
        if (-not $cert) { throw (Get-WpeText 'Install.CertGone' $prevThumb) }
    }

    if ($cert) {
        Write-Step (Get-WpeText 'Install.Signing' $cert.Subject $cert.NotAfter.ToString('d'))
        # AllSigned startet nur Skripte vertrauenswuerdiger Herausgeber ohne Rueckfrage
        if ($cert.Subject -eq $cert.Issuer) { Add-MachineCertificate $cert 'Root' }
        Add-MachineCertificate $cert 'TrustedPublisher'
        foreach ($f in Get-ChildItem -LiteralPath $InstallPath -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
            $sigParams = @{ FilePath = $f.FullName; Certificate = $cert; HashAlgorithm = 'SHA256' }
            if ($TimestampServer) { $sigParams.TimestampServer = $TimestampServer }
            $sig = Set-AuthenticodeSignature @sigParams
            if ($sig.Status -ne 'Valid') { throw "'$($f.Name)': $($sig.Status) - $($sig.StatusMessage)" }
        }
    }
} catch {
    Write-Warn (Get-WpeText 'Install.SigningFailed' $_.Exception.Message)
    if ($newCert) { Remove-CreatedCertificate $newCert.Thumbprint }
    $cert = $null
    $certCreated = $false
}
$execPolicy = if ($cert) { 'AllSigned' } else { 'Bypass' }
if ($prevCreated -and (-not $cert -or $cert.Thumbprint -ne $prevThumb)) {
    Write-Step (Get-WpeText 'Install.CertRemoveOld')
    Remove-CreatedCertificate $prevThumb
}

# Startdatei der Verwaltung mit passender ExecutionPolicy (.cmd-Dateien lassen sich nicht signieren)
$cmd = [IO.File]::ReadAllText((Join-Path $source 'WePrintEasy-Admin.cmd'))
[IO.File]::WriteAllText((Join-Path $InstallPath 'WePrintEasy-Admin.cmd'), $cmd.Replace('-ExecutionPolicy Bypass', "-ExecutionPolicy $execPolicy"), [Text.Encoding]::ASCII)

# --- 3. Registry ---------------------------------------------------------------
Write-Step (Get-WpeText 'Install.Registry' $ConfigPath)
if (-not (Test-Path -LiteralPath $regKey)) { New-Item -Path $regKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $regKey -Name ConfigPath -Value $ConfigPath
Set-ItemProperty -LiteralPath $regKey -Name InstallPath -Value $InstallPath
Set-ItemProperty -LiteralPath $regKey -Name ExecutionPolicy -Value $execPolicy
Set-ItemProperty -LiteralPath $regKey -Name Language -Value $Language
if ($cert) {
    Set-ItemProperty -LiteralPath $regKey -Name SigningThumbprint -Value $cert.Thumbprint
    Set-ItemProperty -LiteralPath $regKey -Name SigningCertCreated -Value ([int]$certCreated) -Type DWord
} else {
    Remove-ItemProperty -LiteralPath $regKey -Name SigningThumbprint, SigningCertCreated -ErrorAction SilentlyContinue
}
if ($cert -and $TimestampServer) {
    Set-ItemProperty -LiteralPath $regKey -Name TimestampServer -Value $TimestampServer
} else {
    Remove-ItemProperty -LiteralPath $regKey -Name TimestampServer -ErrorAction SilentlyContinue
}

# --- 4. Konfiguration ------------------------------------------------------------
Import-Module (Join-Path $InstallPath 'WePrintEasy.psm1') -Force
Set-WpeLanguage $Language
$configDir = Split-Path -Parent $ConfigPath

# Rechte zuerst setzen: neue Dateien erben sie, und eine vorhandene Datei mit
# defekter Zugriffsliste (aeltere Installer-Versionen) wird dabei repariert
if (-not $isUnc) {
    if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    Write-Step (Get-WpeText 'Install.Permissions' $configDir)
    $grants = @(
        '*S-1-5-18:(OI)(CI)F',      # SYSTEM
        '*S-1-5-32-544:(OI)(CI)F',  # Administratoren
        '*S-1-5-32-545:(OI)(CI)RX'  # Benutzer (nur lesen)
    )
    $editorSid = ''
    if ($EditorGroup) {
        $editorSid = (New-Object System.Security.Principal.NTAccount($EditorGroup)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    } else {
        # Update: bisherige Editor-Gruppe beibehalten (Registry bzw. aeltere Installationen: vorhandene Ordnerrechte)
        $editorSid = if ($reg -and $reg.PSObject.Properties['EditorGroupSid']) { [string]$reg.EditorGroupSid } else { '' }
        if (-not $editorSid -and (Test-Path -LiteralPath $configDir)) {
            $known = 'S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545'
            $editorSid = (Get-Acl -LiteralPath $configDir).Access | Where-Object { -not $_.IsInherited -and $_.AccessControlType -eq 'Allow' -and
                ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) -eq [System.Security.AccessControl.FileSystemRights]::Modify } |
                ForEach-Object { try { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { Write-Verbose $_.Exception.Message } } |
                Where-Object { $_ -and $known -notcontains $_ } | Select-Object -First 1
        }
        if ($editorSid) { Write-Host "    $(Get-WpeText 'Install.EditorKept' $editorSid)" }
    }
    if ($editorSid) { $grants += "*$($editorSid):(OI)(CI)M" }
    # Nur den Ordner setzen und die Dateien darin erben lassen: "/grant (OI)(CI) /T" hinterlaesst
    # bei Dateien eine leere Zugriffsliste (dann darf niemand mehr die config.json lesen)
    & icacls.exe $configDir /inheritance:r /grant:r @grants /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn (Get-WpeText 'Install.IcaclsFailed' 'icacls' $LASTEXITCODE) }
    if (Get-ChildItem -LiteralPath $configDir -Force) {
        & icacls.exe (Join-Path $configDir '*') /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn (Get-WpeText 'Install.IcaclsFailed' 'icacls /reset' $LASTEXITCODE) }
    }
    if ($editorSid) {
        Set-ItemProperty -LiteralPath $regKey -Name EditorGroupSid -Value $editorSid
    } else {
        Remove-ItemProperty -LiteralPath $regKey -Name EditorGroupSid -ErrorAction SilentlyContinue
    }
} elseif ($EditorGroup) {
    Write-Warn (Get-WpeText 'Install.EditorOnShare')
}

$configOk = $false
try {
    if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Step (Get-WpeText 'Install.ConfigNew')
        Save-WpeConfig -Config (Read-WpeConfig -Path $ConfigPath) -Path $ConfigPath -Confirm:$false
    } else {
        Write-Step (Get-WpeText 'Install.ConfigKept')
    }
    $configOk = $true
} catch {
    Write-Warn (Get-WpeText 'Install.ConfigUnreachable' $ConfigPath $_.Exception.Message)
}

if ($configOk -and -not $isUnc) {
    try {
        [void](Read-WpeConfig -Path $ConfigPath)
    } catch {
        Write-Warn (Get-WpeText 'Install.ConfigUnreadable' $_.Exception.Message)
        $configOk = $false
    }
}

# --- 5. Drucker vom Druck-/Fileserver -------------------------------------------
if ($configOk -and ($PrintServer -or $PrinterListFile)) {
    $selected = @()
    $server = if ($PrintServer) { $PrintServer.Trim().TrimStart('\').TrimEnd('\') } else { '' }
    $available = @()
    if ($server) {
        Write-Step (Get-WpeText 'Install.QueryServer' $server)
        try {
            $available = @(Get-WpePrintServerPrinter -PrintServer $server)
            $withDriver = @($available | Where-Object { $_.DriverInstalled -ne $false }).Count
            Write-Host "    $(Get-WpeText 'Install.ServerFound' $available.Count $withDriver)"
        } catch {
            Write-Warn (Get-WpeText 'Install.ServerFailed' $server $_.Exception.Message)
        }
    }
    if ($PrinterListFile) {
        $wanted = @(Get-Content -LiteralPath $PrinterListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        foreach ($w in $wanted) {
            $hit = $available | Where-Object { $_.Path -eq $w } | Select-Object -First 1
            $selected += if ($hit) { $hit } else { [pscustomobject]@{ Path = $w; DriverName = ''; Location = ''; Comment = ''; DriverInstalled = $null } }
        }
    } elseif ($ImportPrinters -eq 'All') {
        $selected = $available
    } elseif ($ImportPrinters -eq 'WithLocalDriver') {
        $selected = @($available | Where-Object { $_.DriverInstalled -ne $false })
    }

    if ($InstallMissingDrivers) {
        $missing = @($selected | Where-Object { $_.DriverInstalled -eq $false })
        if ($missing.Count) {
            Write-Step (Get-WpeText 'Install.Drivers' $missing.Count)
            $i = 0
            foreach ($p in $missing) {
                $i++
                Write-Host ("    [{0}/{1}] {2} ({3}) ... " -f $i, $missing.Count, $p.Path, $p.DriverName) -NoNewline
                try {
                    Install-WpePrinterDriver -Path $p.Path -Confirm:$false
                    $p.DriverInstalled = $true
                    Write-Host 'OK' -ForegroundColor Green
                } catch {
                    Write-Host (Get-WpeText 'Install.Failed') -ForegroundColor Red
                    Write-Warn "$($p.Path): $($_.Exception.Message)"
                }
            }
        }
    }

    if ($selected.Count -gt 0 -or $server) {
        Write-Step (Get-WpeText 'Install.SaveCatalog' $selected.Count)
        Set-WpePrinterCatalog -Printers $selected -ReplaceServer $server -ConfigPath $ConfigPath -Confirm:$false
        if ($server) {
            $cfg = Read-WpeConfig -Path $ConfigPath
            if (-not $cfg.Settings.DefaultPrintServer) {
                $cfg.Settings.DefaultPrintServer = $server
                Save-WpeConfig -Config $cfg -Path $ConfigPath -Confirm:$false
            }
        }
    }
}

# --- 6. Geplante Aufgabe -----------------------------------------------------------
Write-Step (Get-WpeText 'Install.Task' "$taskPath$taskName" $execPolicy)
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$agent = Join-Path $InstallPath 'WePrintEasy-Agent.ps1'
$psArgs = "-NoProfile -NonInteractive -ExecutionPolicy $execPolicy -WindowStyle Hidden -File `"$agent`""
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
if ([Environment]::OSVersion.Version.Build -ge 20348 -and (Test-Path -LiteralPath $conhost)) {
    # conhost --headless verhindert das kurze Aufblitzen eines Konsolenfensters
    $action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$psExe`" $psArgs"
} else {
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $psArgs
}
$triggers = @(New-ScheduledTaskTrigger -AtLogOn)
try {
    # Zusaetzlich bei Wiederverbindung einer RDP-Sitzung (neue Client-Drucker!)
    $stateClass = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
    $reconnect = New-CimInstance -CimClass $stateClass -ClientOnly
    $reconnect.StateChange = 3   # TASK_SESSION_REMOTE_CONNECT
    $reconnect.Enabled = $true
    $triggers += $reconnect
} catch {
    Write-Warn (Get-WpeText 'Install.ReconnectTrigger' $_.Exception.Message)
}
$usersGroup = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')).Translate([System.Security.Principal.NTAccount]).Value
$principal = New-ScheduledTaskPrincipal -GroupId $usersGroup -RunLevel Limited
# Parallel: jede Benutzeranmeldung bekommt eine eigene Instanz
$settings = New-ScheduledTaskSettingsSet -MultipleInstances Parallel -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Compatibility Win8
$task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
    -Description (Get-WpeText 'Install.TaskDescription')
Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task -Force | Out-Null

# --- 7. RDS-Richtlinie --------------------------------------------------------------
if ($DisableClientDefaultPrinter) {
    Write-Step (Get-WpeText 'Install.Policy')
    Set-WpeClientDefaultPrinterPolicy -Confirm:$false
}

# --- 8. Verknuepfung -----------------------------------------------------------------
$shortcut = Get-WpeShortcutPath
if (-not $NoShortcut) {
    $toolsDir = Split-Path -Parent $shortcut
    if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
    Write-Step (Get-WpeText 'Install.Shortcut' (Get-WpeText 'App.ShortcutName'))
    # Verknuepfung in einer anderen Sprache (fruehere Installation) ersetzen
    foreach ($old in Get-WpeShortcutPath -All) { if ($old -ne $shortcut -and (Test-Path -LiteralPath $old)) { Remove-Item -LiteralPath $old -Force } }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($shortcut)
    $lnk.TargetPath = $psExe
    $lnk.Arguments = "-NoProfile -ExecutionPolicy $execPolicy -STA -WindowStyle Hidden -File `"$(Join-Path $InstallPath 'WePrintEasy-Admin.ps1')`""
    $lnk.WorkingDirectory = $InstallPath
    $lnk.IconLocation = "$(Join-Path $InstallPath 'WePrintEasy.ico'),0"
    $lnk.Description = Get-WpeText 'Install.ShortcutDescription'
    $lnk.Save()
}

Write-Host ''
if (-not $configOk) {
    throw (Get-WpeText 'Install.ConfigUnusable' $ConfigPath)
}
if ($warnings) {
    Write-Host (Get-WpeText 'Install.DoneWarnings' $warnings) -ForegroundColor Yellow
} else {
    Write-Host (Get-WpeText 'Install.Done') -ForegroundColor Green
}
Write-Host (Get-WpeText 'Install.SumAdmin' (Get-WpeText 'App.ShortcutName') "$InstallPath\WePrintEasy-Admin.cmd")
Write-Host (Get-WpeText 'Install.SumConfig' $ConfigPath)
if ($cert) {
    Write-Host (Get-WpeText 'Install.SumSigned' $cert.Subject $cert.NotAfter.ToString('d'))
    Write-Host (Get-WpeText 'Install.SumSignedHint')
} else {
    Write-Host (Get-WpeText 'Install.SumUnsigned')
}
Write-Host (Get-WpeText 'Install.SumLog')
Write-Host (Get-WpeText 'Install.SumUsers')
Write-Host (Get-WpeText 'Install.SumLanguage' (Get-WpeSupportedLanguage)[$Language])
if (-not $DisableClientDefaultPrinter) {
    Write-Host ''
    foreach ($l in @(Get-WpeText 'Install.TipPolicy')) { Write-Host $l -ForegroundColor Yellow }
}
