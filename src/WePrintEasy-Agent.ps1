#Requires -Version 5.1
<#
.SYNOPSIS
    WePrintEasy Anmelde-Agent: setzt den im Verwaltungsprogramm hinterlegten
    Standarddrucker fuer den angemeldeten Benutzer und haelt ihn fest.

.DESCRIPTION
    Wird bei jeder Anmeldung und jeder Wiederverbindung einer RDP-Sitzung
    (geplante Aufgabe "\WePrintEasy\WePrintEasy Agent") im Kontext des
    Benutzers gestartet.

    Ablauf:
      1. Konfiguration lesen, passende Zuweisung ermitteln (Benutzer > Gruppe)
      2. "Windows verwaltet Standarddrucker" abschalten (optional)
      3. Netzwerkdrucker verbinden, falls noch nicht vorhanden (optional)
      4. Anmeldephase: alle 3 Sekunden pruefen und ggf. zuruecksetzen
         (umgeleitete RDP-Drucker erscheinen erst nach der Anmeldung)
      5. Sitzungsphase: im eingestellten Intervall pruefen (optional)

    Laeuft in der Sitzung bereits ein Agent, startet ein weiterer Aufruf
    (z. B. bei Wiederverbindung) dort nur die Anmeldephase neu und beendet sich.
    Aenderungen an der Konfiguration werden waehrend der Sitzung automatisch
    uebernommen. Protokoll: %LOCALAPPDATA%\WePrintEasy\agent.log

.PARAMETER Once
    Nur einmal pruefen/setzen und sofort beenden (zum Testen).

.PARAMETER ConfigPath
    Abweichender Pfad zur Konfigurationsdatei.
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WePrintEasy.psm1') -Force

$LogDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WePrintEasy'
$LogFile = Join-Path $LogDir 'agent.log'

$log = {
    param([string]$Message, [string]$Level)
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Verbose $line
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 1MB) {
            Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch {
        Write-Verbose (Get-WpeText 'Agent.LogNotWritable' $_.Exception.Message)
    }
}

# --- Nur eine Instanz pro Sitzung ---------------------------------------------
# Ein zweiter Aufruf weckt die laufende Instanz (Anmeldephase neu starten).
$wake = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\WePrintEasy.Agent.Wake')
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WePrintEasy.Agent', [ref]$createdNew)
if (-not $createdNew -and -not $Once) {
    [void]$wake.Set()
    Write-Verbose (Get-WpeText 'Agent.AlreadyRunning')
    $mutex.Dispose(); $wake.Dispose()
    exit 0
}

try {
    if (-not $ConfigPath) { $ConfigPath = Get-WpeConfigPath }
    # Protokoll in der eingestellten Sprache (Aenderungen waehrend der Sitzung uebernimmt Update-WpeAgentConfig)
    Initialize-WpeLanguage -ConfigPath $ConfigPath
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $state = New-WpeAgentState -ConfigPath $ConfigPath -UserSid $identity.User.Value -UserName $env:USERNAME `
        -GroupSids @($identity.Groups | ForEach-Object { $_.Value }) -Log $log

    & $log (Get-WpeText 'Agent.Start' (Get-WpeCurrentAccount) $state.UserSid ([Diagnostics.Process]::GetCurrentProcess().SessionId) $env:COMPUTERNAME $ConfigPath) 'INFO'

    $start = Get-Date
    $missingSince = $null
    while ($true) {
        $result = 'Failed'
        try {
            Update-WpeAgentConfig -State $state
            $result = Invoke-WpeAgentCheck -State $state
        } catch {
            Write-WpeAgentProblem $state (Get-WpeText 'Agent.Error' $_.Exception.Message)
        }
        if ($Once) {
            # Ausfuehrlicher, damit "Erzwingen" in der Verwaltung zeigen kann, woran es liegt
            try {
                & $log (Get-WpeText 'Agent.OnceResult' $result (Get-WpeDefaultPrinter)) 'INFO'
                if ($result -eq 'Missing') { & $log (Get-WpeText 'Agent.OnceAvailable' (@(Get-WpeInstalledPrinterNames) -join ' | ')) 'INFO' }
            } catch { Write-Verbose $_.Exception.Message }
            break
        }

        # Deinstalliert (Programmdatei weg)? Dann nicht weiter zuruecksetzen. Erst nach 10 s, damit
        # ein kurzes Fehlen beim Austausch der Dateien nicht zaehlt.
        if (Test-Path -LiteralPath $PSCommandPath) {
            $missingSince = $null
        } elseif (-not $missingSince) {
            $missingSince = Get-Date
        } elseif (((Get-Date) - $missingSince).TotalSeconds -ge 10) {
            & $log (Get-WpeText 'Agent.Uninstalled' $PSCommandPath) 'INFO'
            break
        }

        $elapsed = ((Get-Date) - $start).TotalSeconds
        try {
            $settings = if ($state.Config) { $state.Config.Settings } else { [pscustomobject](Get-WpeDefaultSettings) }
            $sleep = Get-WpeAgentSleepSeconds -Settings $settings -ElapsedSeconds $elapsed
        } catch {
            # Darf den Agenten nie beenden: dann mit den Standardwerten weiter
            Write-WpeAgentProblem $state (Get-WpeText 'Agent.Error' $_.Exception.Message)
            $sleep = Get-WpeAgentSleepSeconds -Settings ([pscustomobject](Get-WpeDefaultSettings)) -ElapsedSeconds $elapsed
        }
        if ($sleep -lt 0) { break }

        if ($wake.WaitOne([TimeSpan]::FromSeconds($sleep))) {
            & $log (Get-WpeText 'Agent.Reconnected') 'INFO'
            $start = Get-Date
        }
    }
    & $log (Get-WpeText 'Agent.Stopped') 'INFO'
} finally {
    if ($createdNew) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    $wake.Dispose()
}