#Requires -Version 5.1
<#
.SYNOPSIS
    WePrintEasy Druckerwahl: Symbol im Infobereich, ueber das Benutzer ihren
    Standarddrucker selbst waehlen.

.DESCRIPTION
    Startet der Agent in der Benutzersitzung, wenn in der Druckerverwaltung
    "Benutzer duerfen ihren Standarddrucker selbst waehlen" eingeschaltet ist.
    Ein Klick auf das Symbol oeffnet ein Fenster mit den Druckern der Sitzung -
    mehr kann der Benutzer hier nicht einstellen.

    Die Wahl gilt sofort, wird in choices\<SID>.json neben der Konfiguration
    gespeichert und ersetzt die Zuweisung des Benutzers (die Verwaltung zeigt
    sie mit dem Vermerk "Benutzer"). Der Agent haelt sie wie jede Zuweisung fest.

    Beendet sich, wenn die Einstellung ausgeschaltet oder WePrintEasy
    aktualisiert bzw. deinstalliert wird (der Agent startet es dann neu).

.PARAMETER ConfigPath
    Abweichender Pfad zur Konfigurationsdatei.

.PARAMETER ScreenshotDir
    Nur fuer automatisierte Tests/Dokumentation: oeffnet das Fenster, speichert
    ein Bildschirmfoto in diesem Ordner und beendet sich ohne Benutzerinteraktion.
#>
[CmdletBinding()]
param([string]$ConfigPath, [string]$ScreenshotDir)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WePrintEasy.psm1') -Force

# --- Nur eine Instanz pro Sitzung ---------------------------------------------
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WePrintEasy.Tray', [ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); exit 0 }

try {
    if (-not $ConfigPath) { $ConfigPath = Get-WpeConfigPath }
    Initialize-WpeLanguage -ConfigPath $ConfigPath
    $script:WpeAppTitle = Get-WpeText 'Tray.Title'
    $script:WpeScreenshotDir = $ScreenshotDir
    . (Join-Path $PSScriptRoot 'WePrintEasy.Gui.ps1')

    $script:ConfigPath = $ConfigPath
    $script:ConfigStamp = $null
    $script:Window = $null
    # Aendert sich die eigene Datei (Update) oder fehlt sie (Deinstallation), beenden
    $script:SelfPath = $PSCommandPath
    $script:SelfStamp = (Get-Item -LiteralPath $script:SelfPath).LastWriteTimeUtc

    function Get-ConfigStamp {
        try { $i = Get-Item -LiteralPath $script:ConfigPath -ErrorAction Stop; '{0}|{1}' -f $i.LastWriteTimeUtc.Ticks, $i.Length } catch { '' }
    }

    function Test-ChoiceAllowed {
        <# Einstellung der Verwaltung; ist die Konfiguration gerade nicht lesbar, bleibt das Symbol. #>
        try { return [bool](Read-WpeConfig -Path $script:ConfigPath).Settings.AllowUserPrinterChoice } catch { return $true }
    }

    function Get-CurrentPrinter {
        try { [string](Get-WpeDefaultPrinter) } catch { '' }
    }

    function Update-TrayText {
        # NotifyIcon.Text darf hoechstens 63 Zeichen lang sein
        $t = Get-WpeText 'Tray.Tooltip' (Get-CurrentPrinter)
        if ($t.Length -gt 63) { $t = $t.Substring(0, 60) + '...' }
        $script:Tray.Text = $t
    }

    function Send-AgentReload {
        # Laufender Agent liest die Wahl sofort neu (sonst setzte er bis zur naechsten Runde die alte Vorgabe)
        $e = $null
        if ([System.Threading.EventWaitHandle]::TryOpenExisting('Local\WePrintEasy.Agent.Reload', [ref]$e)) {
            try { [void]$e.Set() } finally { $e.Dispose() }
        }
    }

    function Get-OwnDisplayName {
        try {
            $u = @(Find-WpeAdObject -Type User -SearchText $env:USERNAME -Exact) | Select-Object -First 1
            if ($u) { return [string]$u.DisplayName }
        } catch { Write-Verbose $_.Exception.Message }
        return ''
    }

    function Set-ChosenPrinter {
        <# Speichert die Wahl und setzt den Drucker sofort. $true bei Erfolg. #>
        param([string]$Name)
        try {
            # Erst speichern: Ginge das nicht, setzte der Agent den Drucker gleich wieder zurueck
            [void](Save-WpeUserChoice -PrinterName $Name -ConfigPath $script:ConfigPath -DisplayName (Get-OwnDisplayName) -Confirm:$false)
        } catch {
            Show-WpeMessage (Get-WpeText 'Tray.SaveFailed' $_.Exception.Message) 'Error'
            return $false
        }
        Send-AgentReload
        try {
            Set-WpeDefaultPrinter -Name $Name -Confirm:$false
        } catch {
            Show-WpeMessage (Get-WpeText 'Tray.SetFailed' $Name $_.Exception.Message) 'Warning'
        }
        Update-TrayText
        return $true
    }

    function Show-ChoiceWindow {
        if ($script:Window -and -not $script:Window.IsDisposed) {
            $script:Window.WindowState = 'Normal'
            $script:Window.Activate()
            return
        }
        $current = Get-CurrentPrinter
        $names = @()
        try { $names = @(Get-WpeInstalledPrinterNames | Sort-Object) } catch { Write-Verbose $_.Exception.Message }

        # Nicht modal (das Symbol bleibt bedienbar): Die Ereignisse laufen nach dem Ende dieser Funktion,
        # deshalb liegen die Steuerelemente in Skriptvariablen
        $f = New-Object System.Windows.Forms.Form
        $f.Text = Get-WpeText 'Tray.Title'
        $f.ClientSize = New-Object System.Drawing.Size(460, 430)
        $f.StartPosition = 'CenterScreen'
        $f.FormBorderStyle = 'FixedDialog'
        $f.MaximizeBox = $false
        $f.MinimizeBox = $false
        $f.Font = $script:WpeFont
        $f.TopMost = $true
        Set-WpeFormIcon $f

        $f.Controls.Add((New-WpeHeader (Get-WpeText 'Tray.Heading') (Get-WpeText 'Tray.Subtitle')))

        $lblCurrent = New-WpeLabel (Get-WpeText 'Tray.Current' $(if ($current) { $current } else { Get-WpeText 'Tray.None' })) 16 72 430 20
        $lblCurrent.Font = $script:WpeFontBold
        $lblCurrent.AutoEllipsis = $true
        $f.Controls.Add($lblCurrent)
        $f.Controls.Add((New-WpeLabel (Get-WpeText 'Tray.Choose') 16 98 430 20))

        $script:List = New-Object System.Windows.Forms.ListBox
        $script:List.Location = New-Object System.Drawing.Point(16, 124)
        $script:List.Size = New-Object System.Drawing.Size(428, 240)
        $script:List.IntegralHeight = $false
        $script:List.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        foreach ($n in $names) { [void]$script:List.Items.Add($n) }
        if ($current) { $script:List.SelectedItem = $current }
        $f.Controls.Add($script:List)

        $script:OkButton = New-WpeButton (Get-WpeText 'Tray.SetDefault') 16 384 250
        $script:OkButton.Font = $script:WpeFontBold
        $btnCancel = New-WpeButton (Get-WpeText 'Common.Cancel') 334 384 110
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnCancel.Add_Click({ $script:Window.Close() })
        $f.Controls.AddRange(@($script:OkButton, $btnCancel))
        $f.AcceptButton = $script:OkButton
        $f.CancelButton = $btnCancel

        $script:OkButton.Enabled = $null -ne $script:List.SelectedItem
        $script:List.Add_SelectedIndexChanged({ $script:OkButton.Enabled = $null -ne $script:List.SelectedItem })
        $apply = {
            if ($null -eq $script:List.SelectedItem) { return }
            $name = [string]$script:List.SelectedItem
            # Auch den schon eingestellten Drucker speichern: Dann gilt er bei jeder Anmeldung
            if (Set-ChosenPrinter $name) {
                $script:Window.Close()
                $script:Tray.ShowBalloonTip(4000, (Get-WpeText 'Tray.Title'), (Get-WpeText 'Tray.Done' $name), [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
        $script:OkButton.Add_Click($apply)
        $script:List.Add_DoubleClick($apply)
        $f.Add_FormClosed({ $script:Window = $null })
        $f.Add_Shown({ $script:Window.Activate(); [void]$script:List.Focus() })

        if (-not $names) { $script:List.Enabled = $false; $lblCurrent.Text = Get-WpeText 'Tray.NoPrinters' }
        $script:Window = $f
        $f.Show()
    }

    # --- Symbol im Infobereich ---------------------------------------------------
    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Icon = if ($script:WpeIcon) { $script:WpeIcon } else { [System.Drawing.SystemIcons]::Application }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $item = $menu.Items.Add((Get-WpeText 'Tray.MenuChoose'))
    $item.Font = $script:WpeFontBold
    $item.Add_Click({ Show-ChoiceWindow })
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Add_MouseClick({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-ChoiceWindow } })
    Update-TrayText
    $script:Tray.Visible = $true

    $context = New-Object System.Windows.Forms.ApplicationContext
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 30000
    $timer.Add_Tick({
            try {
                $selfGone = -not (Test-Path -LiteralPath $script:SelfPath) -or (Get-Item -LiteralPath $script:SelfPath).LastWriteTimeUtc -ne $script:SelfStamp
                $stamp = Get-ConfigStamp
                if ($stamp -and $stamp -ne $script:ConfigStamp) {
                    $script:ConfigStamp = $stamp
                    if (-not (Test-ChoiceAllowed)) { $selfGone = $true }
                }
                if ($selfGone) {
                    $timer.Stop()
                    if ($script:Window) { $script:Window.Close() }
                    $script:Tray.Visible = $false
                    $context.ExitThread()
                    return
                }
                Update-TrayText
            } catch { Write-Verbose $_.Exception.Message }
        })
    $script:ConfigStamp = Get-ConfigStamp
    $timer.Start()
    if ($script:WpeScreenshotDir) {
        # Test-/Dokumentationsmodus: Fenster fotografieren und beenden
        Show-ChoiceWindow
        $script:Window.Add_Shown({
                try { Save-WpeScreenshot $script:Window 'tray-1-druckerwahl' } catch { Write-WpeTestLog "ERROR tray: $($_.Exception.Message)" }
                $script:Window.Close()
                $script:Tray.Visible = $false
                $context.ExitThread()
            })
    }
    [System.Windows.Forms.Application]::Run($context)
    $timer.Dispose()
    $script:Tray.Dispose()
} finally {
    if ($createdNew) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
