#Requires -Version 5.1
<#
.SYNOPSIS
    WePrintEasy Printer Management / Druckerverwaltung - Standarddrucker fuer
    AD-Benutzer und -Gruppen auf dem Terminalserver fest hinterlegen.

.PARAMETER ConfigPath
    Abweichender Pfad zur Konfigurationsdatei (Standard: aus der Registry
    HKLM\SOFTWARE\WePrintEasy\ConfigPath bzw. C:\ProgramData\WePrintEasy\config.json).

.PARAMETER Language
    Sprache der Oberflaeche nur fuer diesen Start (en, de). Ohne Angabe gilt die
    Einstellung "Sprache" der Konfiguration bzw. die Vorgabe des Servers.

.PARAMETER ScreenshotDir
    Nur für automatisierte Tests/Dokumentation: öffnet alle Ansichten, speichert
    Bildschirmfotos in diesem Ordner und beendet sich ohne Benutzerinteraktion.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [ValidateSet('en', 'de')][string]$Language,
    [string]$ScreenshotDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WePrintEasy.psm1') -Force
if (-not $ConfigPath) { $ConfigPath = Get-WpeConfigPath }
if ($Language) { Set-WpeLanguage $Language } else { Initialize-WpeLanguage -ConfigPath $ConfigPath }
$script:WpeAppTitle = Get-WpeText 'Admin.WindowTitle'
$script:WpeScreenshotDir = $ScreenshotDir
. (Join-Path $PSScriptRoot 'WePrintEasy.Gui.ps1')

$script:ConfigPath = $ConfigPath
$script:Config = $null

# Natürliche Sortierung von Druckernamen (Drucker-2 vor Drucker-10)
$script:NaturalPath = @{ Expression = { [regex]::Replace([string]$_.Path, '\d+', { param($m) $m.Value.PadLeft(10, '0') }) } }

function Get-TypeLabel {
    param([string]$Type)
    if ($Type -eq 'User') { Get-WpeText 'Common.User' } else { Get-WpeText 'Common.Group' }
}

function ConvertTo-RowFilterValue {
    # Maskiert Benutzereingaben für DataView.RowFilter (LIKE)
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Text.ToCharArray()) {
        if ('[]*%'.IndexOf($c) -ge 0) { [void]$sb.Append('[').Append($c).Append(']') }
        elseif ($c -eq "'") { [void]$sb.Append("''") }
        else { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

function New-Grid {
    param([System.Data.DataTable]$Table)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.ReadOnly = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.SelectionMode = 'FullRowSelect'
    $g.MultiSelect = $false
    $g.RowHeadersVisible = $false
    $g.AutoSizeColumnsMode = 'Fill'
    $g.BackgroundColor = [System.Drawing.SystemColors]::Window
    $g.BorderStyle = 'FixedSingle'
    $g.ColumnHeadersDefaultCellStyle.Font = $script:WpeFontBold
    $g.EnableHeadersVisualStyles = $true
    $g.DataSource = $Table
    return $g
}

function Set-GridColumns {
    <# Spaltentitel (übersetzt) und Breitenverhältnis; nicht aufgeführte Spalten werden ausgeblendet. #>
    param([System.Windows.Forms.DataGridView]$Grid, [hashtable]$Columns)
    foreach ($col in $Grid.Columns) {
        $def = $Columns[$col.Name]
        if (-not $def) { $col.Visible = $false; continue }
        $col.HeaderText = Get-WpeText $def[0]
        $col.FillWeight = $def[1]
    }
}

function Restart-AdminProgram {
    <# Startet die Verwaltung neu (z. B. nach einem Sprachwechsel) - mit denselben Rechten. #>
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $argList = @('-NoProfile', '-ExecutionPolicy', (Get-WpeExecutionPolicy -Path $PSCommandPath), '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-ConfigPath', "`"$script:ConfigPath`"")
    Start-Process -FilePath $psExe -ArgumentList $argList
    $form.Close()
}

#region Dialog: Zuweisung anlegen/bearbeiten ----------------------------------

function Show-AssignmentDialog {
    <#
        $Type     : 'User' oder 'Group'
        $Existing : vorhandene Zuweisung (Bearbeiten) oder $null (Neu)
        Rückgabe  : Hashtable mit Type, Name, Sid, DisplayName, Printer, Priority, Comment - oder $null
    #>
    param([string]$Type, $Existing, $Config)

    $isUser = ($Type -eq 'User')
    $what = Get-TypeLabel $Type
    $result = @{ Value = $null }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($Existing) { Get-WpeText 'Assign.TitleEdit' $what $Existing.Name } elseif ($isUser) { Get-WpeText 'Assign.TitleNewUser' } else { Get-WpeText 'Assign.TitleNewGroup' }
    $dlg.Size = New-Object System.Drawing.Size(780, 640)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.Font = $script:WpeFont
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    Set-WpeFormIcon $dlg

    # --- 1. AD-Objekt ---
    $grpAd = New-Object System.Windows.Forms.GroupBox
    $grpAd.Text = if ($isUser) { Get-WpeText 'Assign.Step1User' } else { Get-WpeText 'Assign.Step1Group' }
    $grpAd.Location = New-Object System.Drawing.Point(12, 10)
    $grpAd.Size = New-Object System.Drawing.Size(740, 290)
    $dlg.Controls.Add($grpAd)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(15, 25)
    $txtSearch.Size = New-Object System.Drawing.Size(470, 23)
    $grpAd.Controls.Add($txtSearch)
    $btnSearch = New-WpeButton (Get-WpeText 'Assign.Search') 495 23 100
    $grpAd.Controls.Add($btnSearch)

    $lstAd = New-Object System.Windows.Forms.ListView
    $lstAd.Location = New-Object System.Drawing.Point(15, 58)
    $lstAd.Size = New-Object System.Drawing.Size(710, 190)
    $lstAd.View = 'Details'
    $lstAd.FullRowSelect = $true
    $lstAd.MultiSelect = $false
    $lstAd.HideSelection = $false
    [void]$lstAd.Columns.Add((Get-WpeText 'Assign.ColLogon'), 150)
    [void]$lstAd.Columns.Add((Get-WpeText 'Assign.ColDisplayName'), 210)
    [void]$lstAd.Columns.Add((Get-WpeText 'Assign.ColDescription'), 260)
    [void]$lstAd.Columns.Add((Get-WpeText 'Assign.ColStatus'), 70)
    $grpAd.Controls.Add($lstAd)

    $lblAdInfo = New-WpeLabel (Get-WpeText 'Assign.SearchHint') 15 255 710
    $grpAd.Controls.Add($lblAdInfo)

    if ($Existing) {
        $txtSearch.Text = $Existing.Name
        $txtSearch.Enabled = $false
        $btnSearch.Enabled = $false
        $item = New-Object System.Windows.Forms.ListViewItem($Existing.Name)
        [void]$item.SubItems.Add($Existing.DisplayName)
        [void]$item.SubItems.Add('')
        [void]$item.SubItems.Add('')
        $item.Tag = [pscustomobject]@{ Name = $Existing.Name; DisplayName = $Existing.DisplayName; Sid = $Existing.Sid }
        [void]$lstAd.Items.Add($item)
        $item.Selected = $true
        $lstAd.Enabled = $false
        $lblAdInfo.Text = "SID: $($Existing.Sid)"
    }

    $doSearch = {
        Invoke-WpeWithWaitCursor $dlg {
            $lstAd.Items.Clear()
            try {
                $found = @(Find-WpeAdObject -Type $Type -SearchText $txtSearch.Text)
            } catch {
                Show-WpeMessage (Get-WpeText 'Assign.SearchFailed' $_.Exception.Message) 'Error'
                return
            }
            foreach ($o in $found) {
                $item = New-Object System.Windows.Forms.ListViewItem($o.Name)
                [void]$item.SubItems.Add($o.DisplayName)
                $info = if ($o.Description) { $o.Description } else { $o.Mail }
                [void]$item.SubItems.Add($info)
                [void]$item.SubItems.Add($(if ($o.Enabled) { Get-WpeText 'Assign.Enabled' } else { Get-WpeText 'Assign.Disabled' }))
                if (-not $o.Enabled) { $item.ForeColor = [System.Drawing.Color]::Gray }
                $item.Tag = $o
                [void]$lstAd.Items.Add($item)
            }
            $lblAdInfo.Text = (Get-WpeText 'Assign.Hits' $found.Count) + $(if ($found.Count -ge 300) { Get-WpeText 'Assign.HitsLimited' } else { '' })
            if ($lstAd.Items.Count -eq 1) { $lstAd.Items[0].Selected = $true }
        }
    }
    $btnSearch.Add_Click($doSearch)
    $txtSearch.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $_.SuppressKeyPress = $true; & $doSearch }
        })

    # --- 2. Drucker ---
    $grpPrn = New-Object System.Windows.Forms.GroupBox
    $grpPrn.Text = Get-WpeText 'Assign.Step2'
    $grpPrn.Location = New-Object System.Drawing.Point(12, 308)
    $grpPrn.Size = New-Object System.Drawing.Size(740, 230)
    $dlg.Controls.Add($grpPrn)

    $grpPrn.Controls.Add((New-WpeLabel (Get-WpeText 'Assign.Printer') 15 28 90))
    $cboPrinter = New-Object System.Windows.Forms.ComboBox
    $cboPrinter.Location = New-Object System.Drawing.Point(110, 28)
    $cboPrinter.Size = New-Object System.Drawing.Size(615, 23)
    $cboPrinter.DropDownStyle = 'DropDown'
    $cboPrinter.MaxDropDownItems = 25
    $cboPrinter.AutoCompleteMode = 'SuggestAppend'
    $cboPrinter.AutoCompleteSource = 'ListItems'
    $grpPrn.Controls.Add($cboPrinter)

    $lblPrinterInfo = New-WpeLabel '' 110 55 615
    $lblPrinterInfo.ForeColor = $script:WpeAccent
    $grpPrn.Controls.Add($lblPrinterInfo)

    $hint = New-WpeLabel (Get-WpeText 'Assign.PrinterHint') 110 78 615 36
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $grpPrn.Controls.Add($hint)

    $grpPrn.Controls.Add((New-WpeLabel (Get-WpeText 'Assign.OtherPrinters') 15 120 95))
    $txtServer = New-Object System.Windows.Forms.TextBox
    $txtServer.Location = New-Object System.Drawing.Point(110, 120)
    $txtServer.Size = New-Object System.Drawing.Size(200, 23)
    $txtServer.Text = [string]$Config.Settings.DefaultPrintServer
    $grpPrn.Controls.Add($txtServer)
    $btnLoad = New-WpeButton (Get-WpeText 'Assign.LoadFromServer') 318 118 140
    $grpPrn.Controls.Add($btnLoad)

    $grpPrn.Controls.Add((New-WpeLabel (Get-WpeText 'Assign.Priority') 15 160 90))
    $numPrio = New-Object System.Windows.Forms.NumericUpDown
    $numPrio.Location = New-Object System.Drawing.Point(110, 160)
    $numPrio.Size = New-Object System.Drawing.Size(80, 23)
    $numPrio.Minimum = 1
    $numPrio.Maximum = 9999
    $numPrio.Value = 100
    $grpPrn.Controls.Add($numPrio)
    $lblPrio = New-WpeLabel (Get-WpeText 'Assign.PriorityHint') 200 160 525
    $lblPrio.ForeColor = [System.Drawing.Color]::DimGray
    $grpPrn.Controls.Add($lblPrio)
    if ($isUser) { $numPrio.Enabled = $false; $lblPrio.Text = Get-WpeText 'Assign.PriorityGroupsOnly' }

    $grpPrn.Controls.Add((New-WpeLabel (Get-WpeText 'Assign.Comment') 15 192 90))
    $txtComment = New-Object System.Windows.Forms.TextBox
    $txtComment.Location = New-Object System.Drawing.Point(110, 192)
    $txtComment.Size = New-Object System.Drawing.Size(615, 23)
    $grpPrn.Controls.Add($txtComment)

    # Druckerliste (Katalog) + lokal installierte Drucker
    $catalog = @{}
    foreach ($p in $Config.Printers) { $catalog[$p.Path.ToLowerInvariant()] = $p }
    $fillPrinters = {
        param([string[]]$Extra)
        $keep = $cboPrinter.Text
        $names = New-Object System.Collections.ArrayList
        foreach ($p in ($Config.Printers | Sort-Object $script:NaturalPath)) { [void]$names.Add($p.Path) }
        try { foreach ($n in @(Get-WpePrinterList)) { if (-not $names.Contains($n)) { [void]$names.Add($n) } } } catch { Write-Verbose $_.Exception.Message }
        foreach ($n in $Extra) { if ($n -and -not $names.Contains($n)) { [void]$names.Add($n) } }
        $cboPrinter.BeginUpdate()
        $cboPrinter.Items.Clear()
        foreach ($n in $names) { [void]$cboPrinter.Items.Add($n) }
        $cboPrinter.EndUpdate()
        $cboPrinter.Text = $keep
    }
    $cboPrinter.Add_TextChanged({
            $e = $catalog[$cboPrinter.Text.Trim().ToLowerInvariant()]
            $lblPrinterInfo.Text = if ($e) {
                $parts = @()
                if ($e.Location) { $parts += Get-WpeText 'Assign.InfoLocation' $e.Location }
                if ($e.Comment) { $parts += $e.Comment }
                if ($e.DriverName) { $parts += Get-WpeText 'Assign.InfoDriver' $e.DriverName }
                $parts -join '   |   '
            } else { '' }
        })
    $btnLoad.Add_Click({
            Invoke-WpeWithWaitCursor $dlg {
                $server = $txtServer.Text.Trim()
                if (-not $server) { return }
                try {
                    $remote = @(Get-WpePrintServerPrinter -PrintServer $server | ForEach-Object { $_.Path })
                } catch {
                    Show-WpeMessage (Get-WpeText 'Picker.LoadFailed' $server $_.Exception.Message) 'Error'
                    return
                }
                & $fillPrinters $remote
                $cboPrinter.DroppedDown = ($remote.Count -gt 0)
            }
        })

    if ($Existing) {
        $cboPrinter.Text = $Existing.Printer
        $numPrio.Value = [Math]::Min(9999, [Math]::Max(1, [int]$Existing.Priority))
        $txtComment.Text = $Existing.Comment
    }

    # --- Buttons ---
    $btnOk = New-WpeButton (Get-WpeText 'Common.Save') 526 552 110
    $btnCancel = New-WpeButton (Get-WpeText 'Common.Cancel') 642 552 110
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.Add($btnOk)
    $dlg.Controls.Add($btnCancel)

    $btnOk.Add_Click({
            if ($lstAd.SelectedItems.Count -ne 1) { Show-WpeMessage $(if ($isUser) { Get-WpeText 'Assign.SelectUser' } else { Get-WpeText 'Assign.SelectGroup' }) 'Warning'; return }
            $printer = $cboPrinter.Text.Trim()
            if (-not $printer) { Show-WpeMessage (Get-WpeText 'Assign.NoPrinter') 'Warning'; return }
            if ($printer.StartsWith('\\') -and -not (Test-WpeIsNetworkPrinterPath $printer) -and $printer.IndexOfAny([char[]]'*?') -lt 0) {
                Show-WpeMessage (Get-WpeText 'Assign.BadUnc') 'Warning'; return
            }
            $o = $lstAd.SelectedItems[0].Tag
            if (-not $o.Sid) { Show-WpeMessage (Get-WpeText 'Assign.NoSid') 'Error'; return }
            $result.Value = @{
                Type        = $Type
                Name        = $o.Name
                Sid         = $o.Sid
                DisplayName = $o.DisplayName
                Printer     = $printer
                Priority    = [int]$numPrio.Value
                Comment     = $txtComment.Text.Trim()
            }
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        })

    $dlg.Add_Shown({
            & $fillPrinters @()
            if (-not $Existing) { [void]$txtSearch.Focus() }
            if ($script:WpeScreenshotDir) {
                Save-WpeScreenshot $dlg $(if ($Existing) { 'admin-2-zuweisung-bearbeiten' } else { 'admin-2b-zuweisung-neu' })
                $dlg.Close()
            }
        })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $result.Value
}

function Show-ForceDialog {
    <# "Erzwingen": Standarddrucker eines Benutzers auf einem Terminalserver sofort setzen - mit Live-Protokoll. #>
    param([string]$UserName = '')
    $modulePath = Join-Path $PSScriptRoot 'WePrintEasy.psm1'
    $regUi = 'HKCU:\Software\WePrintEasy'

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = Get-WpeText 'ForceDlg.Title'
    $dlg.Size = New-Object System.Drawing.Size(1000, 660)
    $dlg.MinimumSize = New-Object System.Drawing.Size(800, 440)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = $script:WpeFont
    Set-WpeFormIcon $dlg

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = 104
    $top.Controls.Add((New-WpeLabel (Get-WpeText 'ForceDlg.Server') 10 12 105))
    $cboServer = New-Object System.Windows.Forms.ComboBox
    $cboServer.Location = New-Object System.Drawing.Point(118, 12)
    $cboServer.Size = New-Object System.Drawing.Size(220, 23)
    $top.Controls.Add((New-WpeLabel (Get-WpeText 'ForceDlg.User') 352 12 70))
    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(422, 12)
    $txtUser.Size = New-Object System.Drawing.Size(180, 23)
    $txtUser.Text = $UserName
    $btnCred = New-WpeButton (Get-WpeText 'ForceDlg.Credentials') 616 10 130
    $btnGo = New-WpeButton (Get-WpeText 'ForceDlg.Go') 756 10 130
    $btnGo.Font = $script:WpeFontBold
    $lblCred = New-WpeLabel (Get-WpeText 'ForceDlg.AccessAsCurrent' (Get-WpeCurrentAccount)) 10 44 960
    $lblInfo = New-WpeLabel (Get-WpeText 'ForceDlg.Info') 10 64 960 30
    $lblInfo.ForeColor = [System.Drawing.Color]::DimGray
    $top.Controls.AddRange(@($cboServer, $txtUser, $btnCred, $btnGo, $lblCred, $lblInfo))

    $rtf = New-Object System.Windows.Forms.RichTextBox
    $rtf.Dock = 'Fill'
    $rtf.ReadOnly = $true
    $rtf.BackColor = [System.Drawing.SystemColors]::Window
    $rtf.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $rtf.DetectUrls = $false

    $lblResult = New-Object System.Windows.Forms.Label
    $lblResult.Dock = 'Bottom'
    $lblResult.Height = 56
    $lblResult.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
    $lblResult.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
    $lblResult.Text = Get-WpeText 'ForceDlg.Ready'

    $dlg.Controls.Add($rtf)
    $dlg.Controls.Add($lblResult)
    $dlg.Controls.Add($top)
    $rtf.BringToFront()

    # Terminalserver: zuletzt verwendeter + Server aus dem AD (Namen mit "TS" zuerst)
    $last = ''
    try { $last = [string](Get-ItemProperty -LiteralPath $regUi -Name LastTerminalServer -ErrorAction Stop).LastTerminalServer } catch { Write-Verbose 'Kein zuletzt verwendeter Terminalserver.' }
    $names = @()
    try { $names = @(Get-WpeAdComputer -ServerOnly | Sort-Object -Property @{ Expression = { $_.Name -notmatch 'TS' } }, Name | ForEach-Object { $_.Name }) } catch { Write-Verbose $_.Exception.Message }
    foreach ($n in @($last) + $names) { if ($n -and -not $cboServer.Items.Contains($n)) { [void]$cboServer.Items.Add($n) } }
    $cboServer.Text = if ($last) { $last } elseif ($cboServer.Items.Count) { [string]$cboServer.Items[0] } else { '' }

    $state = @{ Ps = $null; Handle = $null; Queue = $null; Credential = $null }
    # Kennzeichen je Status (Invoke-WpeRemoteForce): Text der Spalte und Farbe
    $styles = @{
        OK      = @('[ OK ]', [System.Drawing.Color]::FromArgb(16, 124, 16))
        Success = @('[ OK ]', [System.Drawing.Color]::FromArgb(16, 124, 16))
        Error   = @((Get-WpeText 'ForceDlg.TagError'), [System.Drawing.Color]::Firebrick)
        Result  = @((Get-WpeText 'ForceDlg.TagError'), [System.Drawing.Color]::Firebrick)
        Warning = @('[ !! ]', [System.Drawing.Color]::FromArgb(176, 100, 0))
        Log     = @('  │   ', [System.Drawing.Color]::FromArgb(40, 80, 140))
        Info    = @('[ .. ]', [System.Drawing.Color]::DimGray)
    }
    $append = {
        param($Item)
        $st = $styles[[string]$Item.Status]
        if (-not $st) { $st = $styles['Info'] }
        $rtf.SelectionStart = $rtf.TextLength
        $rtf.SelectionLength = 0
        $rtf.SelectionColor = $st[1]
        $rtf.SelectionFont = if ($Item.Status -in 'Success', 'Result') { New-Object System.Drawing.Font('Consolas', 9.5, [System.Drawing.FontStyle]::Bold) } else { $rtf.Font }
        $rtf.AppendText(('{0:HH:mm:ss} {1} {2}' -f $Item.Time, $st[0], $Item.Text) + "`n")
        $rtf.ScrollToCaret()
    }
    $drain = {
        if (-not $state.Queue) { return }
        $item = $null
        while ($state.Queue.TryDequeue([ref]$item)) { & $append $item }
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({
            & $drain
            if (-not $state.Handle -or -not $state.Handle.IsCompleted) { return }
            $timer.Stop()
            $res = $null
            try {
                $out = $state.Ps.EndInvoke($state.Handle)
                $res = @($out | Where-Object { $_ -and $_.PSObject.Properties['Success'] }) | Select-Object -Last 1
            } catch {
                $res = [pscustomobject]@{ Success = $false; Message = (Get-WpeText 'Force.Aborted' $_.Exception.Message) }
            }
            foreach ($e in $state.Ps.Streams.Error) { & $append ([pscustomobject]@{ Time = Get-Date; Status = 'Error'; Text = [string]$e }) }
            & $drain
            $state.Ps.Dispose()
            $state.Ps = $null
            $state.Handle = $null
            if (-not $res) { $res = [pscustomobject]@{ Success = $false; Message = (Get-WpeText 'ForceDlg.NoResult') } }
            $lblResult.Text = $(if ($res.Success) { Get-WpeText 'ForceDlg.Success' } else { Get-WpeText 'ForceDlg.Failed' }) + $res.Message
            $lblResult.ForeColor = if ($res.Success) { [System.Drawing.Color]::FromArgb(16, 124, 16) } else { [System.Drawing.Color]::Firebrick }
            $btnGo.Enabled = $true
            $btnCred.Enabled = $true
        })

    $btnCred.Add_Click({
            $c = $null
            try { $c = Get-Credential -Message (Get-WpeText 'ForceDlg.CredentialPrompt') } catch { Write-Verbose $_.Exception.Message }
            if ($c) {
                $state.Credential = $c
                $lblCred.Text = Get-WpeText 'ForceDlg.AccessAs' $c.UserName
            }
        })

    $btnGo.Add_Click({
            $server = $cboServer.Text.Trim()
            $user = $txtUser.Text.Trim()
            if (-not $server -or -not $user) { Show-WpeMessage (Get-WpeText 'ForceDlg.Missing') 'Warning'; return }
            try {
                if (-not (Test-Path -LiteralPath $regUi)) { New-Item -Path $regUi -Force | Out-Null }
                Set-ItemProperty -LiteralPath $regUi -Name LastTerminalServer -Value $server
            } catch { Write-Verbose $_.Exception.Message }

            $rtf.Clear()
            $lblResult.Text = Get-WpeText 'ForceDlg.Running' $user $server
            $lblResult.ForeColor = $script:WpeAccent
            $btnGo.Enabled = $false
            $btnCred.Enabled = $false

            $state.Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
            $params = @{ ComputerName = $server; UserName = $user; ConfigPath = $script:ConfigPath; Queue = $state.Queue }
            if ($state.Credential) { $params.Credential = $state.Credential }
            # Eigener Runspace, damit das Fenster waehrend der Pruefung live aktualisiert wird (Sprache mitgeben)
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript('param($ModulePath, $Params, $Language) Import-Module $ModulePath -Force; Set-WpeLanguage $Language; Invoke-WpeRemoteForce @Params').AddArgument($modulePath).AddArgument($params).AddArgument((Get-WpeLanguage))
            $state.Ps = $ps
            $state.Handle = $ps.BeginInvoke()
            $timer.Start()
        })

    $dlg.Add_FormClosing({
            $timer.Stop()
            if ($state.Ps) { try { [void]$state.Ps.BeginStop($null, $null) } catch { Write-Verbose $_.Exception.Message } }
        })
    $dlg.Add_Shown({
            if ($script:WpeScreenshotDir) {
                # Das Hauptfenster steht im Bildschirmfoto-Modus im Vordergrund
                $dlg.TopMost = $true
                $dlg.Activate()
                Save-WpeScreenshot $dlg 'admin-9-erzwingen'
                $dlg.Close()
            }
        })
    $dlg.AcceptButton = $btnGo
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

#endregion

#region Hauptfenster ----------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:WpeAppTitle $((Get-WpeAboutInfo).Version)"
$form.Size = New-Object System.Drawing.Size(1120, 720)
$form.MinimumSize = New-Object System.Drawing.Size(940, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = $script:WpeFont
Set-WpeFormIcon $form

$header = New-WpeHeader (Get-WpeText 'Admin.Header') (Get-WpeText 'Admin.Subtitle' $script:ConfigPath)
# Breite vorab setzen, damit der rechts verankerte Info-Knopf richtig sitzt
$header.Width = $form.ClientSize.Width
$btnInfo = New-Object System.Windows.Forms.Button
$btnInfo.Text = Get-WpeText 'Admin.Info'
$btnInfo.FlatStyle = 'Flat'
$btnInfo.FlatAppearance.BorderColor = [System.Drawing.Color]::White
$btnInfo.ForeColor = [System.Drawing.Color]::White
$btnInfo.BackColor = $script:WpeAccent
$btnInfo.Size = New-Object System.Drawing.Size(90, 30)
$btnInfo.Location = New-Object System.Drawing.Point(($header.Width - 106), 16)
$btnInfo.Anchor = 'Top, Right'
$header.Controls.Add($btnInfo)
$btnInfo.Add_Click({ Show-WpeAboutDialog -ConfigPath $script:ConfigPath })
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = Get-WpeText 'UpdateCheck.Button'
$btnUpdate.FlatStyle = 'Flat'
$btnUpdate.FlatAppearance.BorderColor = [System.Drawing.Color]::White
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.BackColor = $script:WpeAccent
$btnUpdate.Size = New-Object System.Drawing.Size(160, 30)
$btnUpdate.Location = New-Object System.Drawing.Point(($header.Width - 274), 16)
$btnUpdate.Anchor = 'Top, Right'
$header.Controls.Add($btnUpdate)
$btnUpdate.Add_Click({ Start-WpeUpdateCheck -Owner $form -Manual -StatusLabel $statusLabel })
$form.KeyPreview = $true
$form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::F1) { $_.Handled = $true; Show-WpeAboutDialog -ConfigPath $script:ConfigPath }
        # Strg+Z: letzte Aenderung rueckgaengig - ausser in Textfeldern, dort gilt es fuer den Text
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Z -and $_.Control -and -not $_.Alt -and $form.ActiveControl -isnot [System.Windows.Forms.TextBoxBase]) {
            $_.Handled = $true; $_.SuppressKeyPress = $true; Invoke-UndoLastChange
        }
    })

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
[void]$status.Items.Add($statusLabel)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object System.Drawing.Point(14, 5)
$form.Controls.Add($tabs)
$form.Controls.Add($header)
$form.Controls.Add($status)
$tabs.BringToFront()

function New-Tab {
    param([string]$Text)
    $t = New-Object System.Windows.Forms.TabPage
    $t.Text = $Text
    $t.Padding = New-Object System.Windows.Forms.Padding(10)
    $t.UseVisualStyleBackColor = $true
    [void]$tabs.TabPages.Add($t)
    return $t
}

# ---- Tab: Zuweisungen ----
$tabAssign = New-Tab (Get-WpeText 'Admin.TabAssignments')

$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Dock = 'Top'
$pnlTop.Height = 42
$tabAssign.Controls.Add($pnlTop)

$pnlTop.Controls.Add((New-WpeLabel (Get-WpeText 'Admin.Filter') 0 7 52))
$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Object System.Drawing.Point(55, 7)
$txtFilter.Size = New-Object System.Drawing.Size(260, 23)
$pnlTop.Controls.Add($txtFilter)

$btnAddUser = New-WpeButton (Get-WpeText 'Admin.AssignUser') 330 5 150
$btnAddGroup = New-WpeButton (Get-WpeText 'Admin.AssignGroup') 486 5 140
$btnEdit = New-WpeButton (Get-WpeText 'Admin.Edit') 632 5 105
$btnRemove = New-WpeButton (Get-WpeText 'Admin.Remove') 743 5 95
$btnReload = New-WpeButton (Get-WpeText 'Admin.Reload') 844 5 95
$btnForce = New-WpeButton (Get-WpeText 'Admin.Force') 945 5 110
$btnAddUser.Font = $script:WpeFontBold
$pnlTop.Controls.AddRange(@($btnAddUser, $btnAddGroup, $btnEdit, $btnRemove, $btnReload, $btnForce))

# Spaltennamen sind feste Kennungen (RowFilter); die Titel kommen aus den Sprachdateien
$table = New-Object System.Data.DataTable
foreach ($c in 'TypeKey', 'Type', 'Name', 'DisplayName', 'Printer', 'Priority', 'Source', 'Comment', 'Modified', 'ModifiedBy', 'Sid', 'ChangedByUser') {
    [void]$table.Columns.Add($c)
}
$grid = New-Grid $table
# Mehrere Zuweisungen auf einmal entfernen (Strg/Umschalt); Bearbeiten und Erzwingen brauchen genau eine
$grid.MultiSelect = $true
$tabAssign.Controls.Add($grid)
$grid.BringToFront()

$grid.Add_DataBindingComplete({
        Set-GridColumns $grid @{
            Type = @('Admin.ColType', 50); Name = @('Admin.ColName', 90); DisplayName = @('Admin.ColDisplayName', 120); Printer = @('Admin.ColPrinter', 170)
            Priority = @('Admin.ColPriority', 45); Source = @('Admin.ColSource', 150); Comment = @('Admin.ColComment', 100); Modified = @('Admin.ColModified', 90); ModifiedBy = @('Admin.ColModifiedBy', 90)
        }
        # Vom Benutzer selbst gewaehlte Drucker hervorheben
        foreach ($r in $grid.Rows) {
            if ([string]$r.DataBoundItem.Row['ChangedByUser'] -eq '1') { $r.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 246, 214) }
        }
    })

# ---- Tab: Druckerliste ----
$tabPrinters = New-Tab (Get-WpeText 'Admin.TabPrinters')
$pnlPrnTop = New-Object System.Windows.Forms.Panel
$pnlPrnTop.Dock = 'Top'
$pnlPrnTop.Height = 42
$tabPrinters.Controls.Add($pnlPrnTop)
$btnImport = New-WpeButton (Get-WpeText 'Admin.ImportPrinters') 0 5 260
$btnImport.Font = $script:WpeFontBold
$btnPrnRemove = New-WpeButton (Get-WpeText 'Admin.RemoveFromList') 266 5 150
$lblPrnInfo = New-WpeLabel (Get-WpeText 'Admin.PrintersHint') 430 7 600
$pnlPrnTop.Controls.AddRange(@($btnImport, $btnPrnRemove, $lblPrnInfo))

$prnTable = New-Object System.Data.DataTable
foreach ($c in 'Printer', 'Location', 'Comment', 'Driver', 'Assigned') { [void]$prnTable.Columns.Add($c) }
$prnGrid = New-Grid $prnTable
$prnGrid.MultiSelect = $true
$tabPrinters.Controls.Add($prnGrid)
$prnGrid.BringToFront()
$prnGrid.Add_DataBindingComplete({
        Set-GridColumns $prnGrid @{
            Printer = @('Admin.ColPrinter', 160); Location = @('Admin.ColLocation', 110); Comment = @('Admin.ColComment', 130)
            Driver = @('Admin.ColDriver', 150); Assigned = @('Admin.ColAssigned', 60)
        }
    })

# ---- Tab: Benutzer prüfen ----
$tabTest = New-Tab (Get-WpeText 'Admin.TabCheckUser')
$tabTest.Controls.Add((New-WpeLabel (Get-WpeText 'Admin.LogonName') 10 12 100))
$txtTestUser = New-Object System.Windows.Forms.TextBox
$txtTestUser.Location = New-Object System.Drawing.Point(115, 12)
$txtTestUser.Size = New-Object System.Drawing.Size(220, 23)
$tabTest.Controls.Add($txtTestUser)
$btnTest = New-WpeButton (Get-WpeText 'Admin.Resolve') 345 10 110
$btnUserLog = New-WpeButton (Get-WpeText 'Admin.ShowLog') 461 10 150
$btnForceTest = New-WpeButton (Get-WpeText 'Admin.ForceLive') 617 10 150
$tabTest.Controls.AddRange(@($btnTest, $btnUserLog, $btnForceTest))

$txtTestResult = New-Object System.Windows.Forms.TextBox
$txtTestResult.Location = New-Object System.Drawing.Point(10, 50)
$txtTestResult.Size = New-Object System.Drawing.Size(1070, 470)
$txtTestResult.Anchor = 'Top, Left, Right, Bottom'
$txtTestResult.Multiline = $true
$txtTestResult.ReadOnly = $true
$txtTestResult.ScrollBars = 'Both'
$txtTestResult.WordWrap = $false
$txtTestResult.BackColor = [System.Drawing.SystemColors]::Window
$txtTestResult.Font = New-Object System.Drawing.Font('Consolas', 10)
$txtTestResult.Text = @(Get-WpeText 'Admin.CheckUserHelp') -join "`r`n"
$tabTest.Controls.Add($txtTestResult)

# ---- Tab: Einrichtung ----
$tabSetup = New-Tab (Get-WpeText 'Admin.TabSetup')
$pnlSetupTop = New-Object System.Windows.Forms.Panel
$pnlSetupTop.Dock = 'Top'
$pnlSetupTop.Height = 42
$tabSetup.Controls.Add($pnlSetupTop)
$btnCheck = New-WpeButton (Get-WpeText 'Admin.Recheck') 0 5 120
$btnFix = New-WpeButton (Get-WpeText 'Admin.Fix') 126 5 200
$btnRunAgent = New-WpeButton (Get-WpeText 'Admin.RunAgent') 332 5 220
$btnMyLog = New-WpeButton (Get-WpeText 'Admin.MyLog') 558 5 120
$btnUndo = New-WpeButton (Get-WpeText 'Admin.Undo') 684 5 230
$btnRestartAll = New-WpeButton (Get-WpeText 'Admin.RestartAll') 920 5 160
$pnlSetupTop.Controls.AddRange(@($btnCheck, $btnFix, $btnRunAgent, $btnMyLog, $btnUndo, $btnRestartAll))

$lstStatus = New-Object System.Windows.Forms.ListView
$lstStatus.Dock = 'Fill'
$lstStatus.View = 'Details'
$lstStatus.FullRowSelect = $true
$lstStatus.MultiSelect = $false
$lstStatus.HideSelection = $false
$lstStatus.GridLines = $true
[void]$lstStatus.Columns.Add((Get-WpeText 'Admin.ColStatus'), 90)
[void]$lstStatus.Columns.Add((Get-WpeText 'Admin.ColCheck'), 200)
[void]$lstStatus.Columns.Add((Get-WpeText 'Admin.ColResult'), 760)
$tabSetup.Controls.Add($lstStatus)

$txtSetupHint = New-Object System.Windows.Forms.Label
$txtSetupHint.Dock = 'Bottom'
$txtSetupHint.Height = 48
$txtSetupHint.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$txtSetupHint.ForeColor = [System.Drawing.Color]::DimGray
$txtSetupHint.Text = Get-WpeText 'Admin.SetupHint'
$tabSetup.Controls.Add($txtSetupHint)
$lstStatus.BringToFront()

# ---- Tab: Einstellungen ----
$tabSettings = New-Tab (Get-WpeText 'Admin.TabSettings')

function New-Number {
    param([int]$X, [int]$Y, [int]$Min, [int]$Max)
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Location = New-Object System.Drawing.Point($X, $Y)
    $n.Size = New-Object System.Drawing.Size(90, 23)
    $n.Minimum = $Min
    $n.Maximum = $Max
    return $n
}
function New-Check {
    param([string]$Text, [int]$X, [int]$Y)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size(800, 24)
    return $c
}

$y = 15
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.LogonPhase') 15 $y 260))
$numLogon = New-Number 280 $y 0 3600
$tabSettings.Controls.Add($numLogon)
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.LogonPhaseHint') 380 $y 700))
$y += 40
$chkEnforce = New-Check (Get-WpeText 'Settings.Enforce') 15 $y
$tabSettings.Controls.Add($chkEnforce)
$y += 35
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.Interval') 35 $y 240))
$numInterval = New-Number 280 $y 5 3600
$tabSettings.Controls.Add($numInterval)
$y += 35
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.Duration') 35 $y 240))
$numDuration = New-Number 280 $y 0 1440
$tabSettings.Controls.Add($numDuration)
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.DurationHint') 380 $y 300))
$y += 45
$chkLegacy = New-Check (Get-WpeText 'Settings.Legacy') 15 $y
$tabSettings.Controls.Add($chkLegacy)
$y += 35
$chkConnect = New-Check (Get-WpeText 'Settings.Connect') 15 $y
$tabSettings.Controls.Add($chkConnect)
$y += 35
$chkUserChoice = New-Check (Get-WpeText 'Settings.UserChoice') 15 $y
$tabSettings.Controls.Add($chkUserChoice)
$y += 26
$lblUserChoiceHint = New-WpeLabel (Get-WpeText 'Settings.UserChoiceHint') 35 $y 1040 36
$lblUserChoiceHint.ForeColor = [System.Drawing.Color]::DimGray
$tabSettings.Controls.Add($lblUserChoiceHint)
$y += 50
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.DefaultServer') 15 $y 260))
$txtDefServer = New-Object System.Windows.Forms.TextBox
$txtDefServer.Location = New-Object System.Drawing.Point(280, $y)
$txtDefServer.Size = New-Object System.Drawing.Size(250, 23)
$tabSettings.Controls.Add($txtDefServer)
$y += 40
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.Language') 15 $y 260))
$cboLanguage = New-Object System.Windows.Forms.ComboBox
$cboLanguage.DropDownStyle = 'DropDownList'
$cboLanguage.Location = New-Object System.Drawing.Point(280, $y)
$cboLanguage.Size = New-Object System.Drawing.Size(250, 23)
$script:LanguageCodes = @((Get-WpeSupportedLanguage).Keys)
foreach ($code in $script:LanguageCodes) { [void]$cboLanguage.Items.Add((Get-WpeSupportedLanguage)[$code]) }
$tabSettings.Controls.Add($cboLanguage)
$tabSettings.Controls.Add((New-WpeLabel (Get-WpeText 'Settings.LanguageHint') 545 $y 520))
$y += 50
$btnSaveSettings = New-WpeButton (Get-WpeText 'Settings.Save') 15 $y 190
$btnSaveSettings.Font = $script:WpeFontBold
$tabSettings.Controls.Add($btnSaveSettings)

# ---- Tab: Anleitung ----
$tabHelp = New-Tab (Get-WpeText 'Admin.TabGuide')
$rtfHelp = New-WpeRichText
$rtfHelp.Dock = 'Fill'
$tabHelp.Controls.Add($rtfHelp)
Add-WpeRichText $rtfHelp (Get-WpeGuideLines)

#endregion

#region Logik -----------------------------------------------------------------

function Update-All {
    try {
        # Mit der Druckerwahl der Benutzer (wenn erlaubt) - so, wie sie in den Sitzungen gilt
        $script:Config = Read-WpeEffectiveConfig -Path $script:ConfigPath
    } catch {
        Show-WpeMessage $_.Exception.Message 'Error'
        return
    }
    $table.Rows.Clear()
    foreach ($a in ($script:Config.Assignments | Sort-Object -Property @{ Expression = { $_.Type -eq 'Group' } }, Priority, Name)) {
        $prio = if ($a.Type -eq 'Group') { [string]$a.Priority } else { '' }
        $byUser = Test-WpeChangedByUser $a
        $source = if (-not $byUser) { Get-WpeText 'Admin.SourceAdmin' } elseif ($a.PreviousPrinter) { Get-WpeText 'Admin.SourceUserPrevious' $a.PreviousPrinter } else { Get-WpeText 'Admin.SourceUser' }
        [void]$table.Rows.Add($a.Type, (Get-TypeLabel $a.Type), $a.Name, $a.DisplayName, $a.Printer, $prio, $source, $a.Comment, $a.ModifiedAt, $a.ModifiedBy, $a.Sid, $(if ($byUser) { '1' } else { '' }))
    }
    Update-Filter

    $usage = @{}
    foreach ($a in $script:Config.Assignments) { $k = $a.Printer.ToLowerInvariant(); $usage[$k] = 1 + [int]$usage[$k] }
    $prnTable.Rows.Clear()
    foreach ($p in ($script:Config.Printers | Sort-Object $script:NaturalPath)) {
        $n = [int]$usage[$p.Path.ToLowerInvariant()]
        [void]$prnTable.Rows.Add($p.Path, $p.Location, $p.Comment, $p.DriverName, $(if ($n) { "$n x" } else { '' }))
    }
    $lblPrnInfo.Text = Get-WpeText 'Admin.PrintersCount' $script:Config.Printers.Count

    $users = @($script:Config.Assignments | Where-Object { $_.Type -eq 'User' }).Count
    $groups = @($script:Config.Assignments | Where-Object { $_.Type -eq 'Group' }).Count
    $statusLabel.Text = Get-WpeText 'Admin.StatusLoaded' $users $groups $script:Config.Printers.Count (Get-Date -Format 'HH:mm:ss')
    Update-SettingsTab
}

function Update-Filter {
    $t = $txtFilter.Text.Trim()
    if ($t) {
        $v = ConvertTo-RowFilterValue $t
        $table.DefaultView.RowFilter = "Name LIKE '*$v*' OR DisplayName LIKE '*$v*' OR Printer LIKE '*$v*' OR Comment LIKE '*$v*' OR Source LIKE '*$v*'"
    } else {
        $table.DefaultView.RowFilter = ''
    }
}

function Get-SelectedAssignments {
    <# Alle markierten Zuweisungen (in der angezeigten Reihenfolge). #>
    $rows = @($grid.SelectedRows | Sort-Object -Property Index | ForEach-Object { $_.DataBoundItem.Row })
    foreach ($row in $rows) {
        foreach ($a in $script:Config.Assignments) {
            if ($a.Type -eq $row['TypeKey'] -and $a.Name -eq $row['Name'] -and $a.Sid -eq $row['Sid']) { $a; break }
        }
    }
}

function Get-SelectedAssignment {
    <# Die eine markierte Zuweisung; $null bei keiner oder mehreren. #>
    if ($grid.SelectedRows.Count -ne 1) { return $null }
    @(Get-SelectedAssignments) | Select-Object -First 1
}

function Show-SelectOneAssignment {
    if ($grid.SelectedRows.Count -gt 1) { Show-WpeMessage (Get-WpeText 'Admin.SelectOneAssignment') 'Warning' }
    else { Show-WpeMessage (Get-WpeText 'Admin.SelectAssignment') 'Warning' }
}

function Format-WpeList {
    <# Mehrzeilige Aufzaehlung fuer Rueckfragen, hoechstens $Max Zeilen plus "... und N weitere". #>
    param([string[]]$Lines, [int]$Max = 12)
    $shown = @($Lines | Select-Object -First $Max | ForEach-Object { "  $_" })
    if ($Lines.Count -gt $Max) { $shown += '  ' + (Get-WpeText 'Admin.AndMore' ($Lines.Count - $Max)) }
    $shown -join "`n"
}

function Invoke-UndoLastChange {
    <# Letzte gespeicherte Aenderung rueckgaengig machen (config.json.bak), mit Rueckfrage. #>
    try {
        $backup = Get-WpeConfigBackup -Path $script:ConfigPath
        $current = Read-WpeConfig -Path $script:ConfigPath
    } catch {
        Show-WpeMessage (Get-WpeText 'Admin.UndoFailed' $_.Exception.Message) 'Error'
        return
    }
    if (-not $backup) { Show-WpeMessage (Get-WpeText 'Admin.UndoNone'); return }
    $culture = [Globalization.CultureInfo]::GetCultureInfo($(if ((Get-WpeLanguage) -eq 'de') { 'de-DE' } else { 'en-US' }))
    $when = $backup.Saved.ToString('g', $culture)
    $u = @($current.Assignments | Where-Object { $_.Type -eq 'User' }).Count
    $g = @($current.Assignments | Where-Object { $_.Type -eq 'Group' }).Count
    if (-not (Confirm-WpeAction (Get-WpeText 'Admin.UndoConfirm' $when $backup.Users $backup.Groups $backup.Printers $u $g $current.Printers.Count))) { return }
    try {
        Restore-WpeConfigBackup -Path $script:ConfigPath -Confirm:$false
    } catch {
        Show-WpeMessage (Get-WpeText 'Admin.UndoFailed' $_.Exception.Message) 'Error'
        return
    }
    Update-All
    $statusLabel.Text = Get-WpeText 'Admin.UndoDone' $when
}

function Invoke-RestartAll {
    <# "Alles neu starten": Agenten und Symbole in allen Sitzungen dieses Servers neu starten (mit Rueckfrage). #>
    $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { Show-WpeMessage (Get-WpeText 'Admin.RestartAllNoAdmin') 'Warning'; return }
    if (-not (Confirm-WpeAction (Get-WpeText 'Admin.RestartAllConfirm' $env:COMPUTERNAME))) { return }
    $installPath = $PSScriptRoot
    try { $p = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WePrintEasy' -Name InstallPath -ErrorAction Stop).InstallPath; if ($p -and (Test-Path -LiteralPath (Join-Path $p 'WePrintEasy-Agent.ps1'))) { $installPath = $p } } catch { Write-Verbose $_.Exception.Message }
    $r = $null
    try {
        Invoke-WpeWithWaitCursor $form {
            $statusLabel.Text = Get-WpeText 'Admin.RestartAllRunning'
            [System.Windows.Forms.Application]::DoEvents()
            $script:RestartResult = Restart-WpeAll -InstallPath $installPath -Confirm:$false
        }
        $r = $script:RestartResult
    } catch {
        Show-WpeMessage (Get-WpeText 'Admin.RestartAllFailed' $_.Exception.Message) 'Error'
        return
    }
    $ok = @($r.Agents | Where-Object { $_.Status -in 'Restarted', 'Started' })
    $lines = @($r.Agents | ForEach-Object { '{0} ({1}): {2}{3}' -f $_.User, $_.SessionId, (Get-WpeText "Admin.RestartStatus.$($_.Status)"), $(if ($_.Message) { " - $($_.Message)" } else { '' }) })
    $text = Get-WpeText 'Admin.RestartAllDone' $ok.Count @($r.Agents).Count $r.Trays
    if ($lines) { $text += "`n`n" + (Format-WpeList $lines 20) } else { $text += "`n`n" + (Get-WpeText 'Admin.RestartAllNoSessions') }
    $icon = if (@($r.Agents).Count -gt $ok.Count) { 'Warning' } else { 'Info' }
    Show-WpeMessage $text $icon
    $statusLabel.Text = Get-WpeText 'Admin.RestartAllStatus' $ok.Count @($r.Agents).Count
}

function Save-Assignment {
    param([hashtable]$Data)
    $msg = ''
    try {
        Set-WpeAssignment @Data -ConfigPath $script:ConfigPath -Confirm:$false | Out-Null
        $msg = Get-WpeText 'Admin.Saved' (Get-TypeLabel $Data.Type) $Data.Name $Data.Printer
    } catch {
        Show-WpeMessage (Get-WpeText 'Common.SaveFailed' $_.Exception.Message) 'Error'
    }
    Update-All
    # Erst nach Update-All - das ueberschreibt die Statuszeile mit "geladen ..."
    if ($msg) { $statusLabel.Text = $msg }
}

function Invoke-AddAssignment {
    param([string]$Type)
    $data = Show-AssignmentDialog -Type $Type -Existing $null -Config $script:Config
    if (-not $data) { return }
    $dup = $script:Config.Assignments | Where-Object { $_.Type -eq $Type -and $_.Sid -eq $data.Sid } | Select-Object -First 1
    if ($dup -and -not (Confirm-WpeAction (Get-WpeText 'Admin.ReplaceConfirm' (Get-TypeLabel $Type) $data.Name $dup.Printer $data.Printer))) { return }
    Save-Assignment $data
}

function Invoke-EditAssignment {
    $a = Get-SelectedAssignment
    if (-not $a) { Show-SelectOneAssignment; return }
    $data = Show-AssignmentDialog -Type $a.Type -Existing $a -Config $script:Config
    if ($data) { Save-Assignment $data }
}

function Invoke-PrinterImport {
    $server = [string]$script:Config.Settings.DefaultPrintServer
    if (-not $server) { $server = @(Get-WpeKnownPrintServer) | Select-Object -First 1 }
    $pre = @($script:Config.Printers | ForEach-Object { $_.Path })
    $r = Show-WpePrinterImportDialog -Server $server -PreselectPaths $pre
    if (-not $r) { return }
    try {
        Invoke-WpeWithWaitCursor $form {
            if ($r.InstallDrivers) {
                $res = Invoke-WpeDriverInstallBatch -Printers $r.Printers -Progress { param($t) $statusLabel.Text = $t; [System.Windows.Forms.Application]::DoEvents() }
                if ($res.Failed.Count) { Show-WpeMessage (Get-WpeText 'Admin.DriversPartial' $res.Installed $res.Requested ($res.Failed -join "`n")) 'Warning' }
            }
            Set-WpePrinterCatalog -Printers $r.Printers -ReplaceServer $r.Server -ConfigPath $script:ConfigPath -Confirm:$false
            $cfg = Read-WpeConfig -Path $script:ConfigPath
            if (-not $cfg.Settings.DefaultPrintServer) {
                $cfg.Settings.DefaultPrintServer = $r.Server
                Save-WpeConfig -Config $cfg -Path $script:ConfigPath -Confirm:$false
            }
        }
        Update-All
        $statusLabel.Text = Get-WpeText 'Admin.PrintersUpdated' $r.Printers.Count $r.Server
    } catch {
        Show-WpeMessage (Get-WpeText 'Admin.PrintersSaveFailed' $_.Exception.Message) 'Error'
    }
}

function Update-StatusList {
    Invoke-WpeWithWaitCursor $form {
        $lstStatus.BeginUpdate()
        $lstStatus.Items.Clear()
        try {
            $checks = @(Get-WpeSystemStatus -ConfigPath $script:ConfigPath)
        } catch {
            $checks = @([pscustomobject]@{ Id = 'SystemCheck'; Status = 'Error'; Check = (Get-WpeText 'Admin.SystemCheck'); Detail = $_.Exception.Message; Fix = '' })
        }
        foreach ($c in $checks) {
            $item = New-Object System.Windows.Forms.ListViewItem((Get-WpeText "Status.$($c.Status)"))
            [void]$item.SubItems.Add($c.Check)
            [void]$item.SubItems.Add($c.Detail)
            $item.UseItemStyleForSubItems = $false
            $item.Font = $script:WpeFontBold
            $item.ForeColor = switch ($c.Status) {
                'OK' { [System.Drawing.Color]::FromArgb(16, 124, 16) }
                'Warning' { [System.Drawing.Color]::FromArgb(176, 96, 0) }
                'Error' { [System.Drawing.Color]::FromArgb(196, 30, 30) }
                default { [System.Drawing.Color]::FromArgb(0, 95, 184) }
            }
            $item.Tag = $c
            [void]$lstStatus.Items.Add($item)
        }
        $lstStatus.EndUpdate()
        $bad = @($checks | Where-Object { $_.Status -in 'Error', 'Warning' }).Count
        $statusLabel.Text = if ($bad) { Get-WpeText 'Admin.SetupIssues' $bad } else { Get-WpeText 'Admin.SetupOk' }
    }
}

function Show-AgentLog {
    param([string]$Path, [string]$Title)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        $txtTestResult.Text = Get-WpeText 'Admin.NoLog' $Title $Path
    } else {
        $lines = @(Get-Content -LiteralPath $Path -Tail 300 -Encoding UTF8)
        [array]::Reverse($lines)
        $txtTestResult.Text = (Get-WpeText 'Admin.LogHeader' $Title $Path) + "`r`n`r`n" + ($lines -join "`r`n")
    }
    $tabs.SelectedTab = $tabTest
}

$btnAddUser.Add_Click({ Invoke-AddAssignment 'User' })
$btnAddGroup.Add_Click({ Invoke-AddAssignment 'Group' })
$btnEdit.Add_Click({ Invoke-EditAssignment })
$grid.Add_CellDoubleClick({ if ($_.RowIndex -ge 0) { Invoke-EditAssignment } })
$btnReload.Add_Click({ Update-All })
$btnForce.Add_Click({
        $a = Get-SelectedAssignment
        Show-ForceDialog -UserName $(if ($a -and $a.Type -eq 'User') { $a.Name } else { '' })
    })
$txtFilter.Add_TextChanged({ Update-Filter })
$btnRemove.Add_Click({
        $sel = @(Get-SelectedAssignments)
        if (-not $sel) { Show-WpeMessage (Get-WpeText 'Admin.SelectAssignment') 'Warning'; return }
        if ($sel.Count -eq 1) {
            $question = Get-WpeText 'Admin.RemoveConfirm' (Get-TypeLabel $sel[0].Type) $sel[0].Name $sel[0].Printer
        } else {
            $question = Get-WpeText 'Admin.RemoveManyConfirm' $sel.Count (Format-WpeList @($sel | ForEach-Object { '{0} {1} ({2})' -f (Get-TypeLabel $_.Type), $_.Name, $_.Printer }))
        }
        if (-not (Confirm-WpeAction $question)) { return }
        $msg = ''
        try {
            # Ein Lese-/Speichervorgang fuer alle - so macht "Rueckgaengig" auch alle auf einmal rueckgaengig
            $sel | Select-Object Type, Name, Sid | Remove-WpeAssignment -ConfigPath $script:ConfigPath -Confirm:$false
            $msg = if ($sel.Count -eq 1) { Get-WpeText 'Admin.Removed' (Get-TypeLabel $sel[0].Type) $sel[0].Name } else { Get-WpeText 'Admin.RemovedMany' $sel.Count }
        } catch {
            Show-WpeMessage (Get-WpeText 'Common.RemoveFailed' $_.Exception.Message) 'Error'
        }
        Update-All
        if ($msg) { $statusLabel.Text = $msg }
    })
$grid.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete) { $btnRemove.PerformClick() } })

$btnImport.Add_Click({ Invoke-PrinterImport })
$btnPrnRemove.Add_Click({
        $paths = @($prnGrid.SelectedRows | Sort-Object -Property Index | ForEach-Object { [string]$_.DataBoundItem.Row['Printer'] })
        if (-not $paths) { Show-WpeMessage (Get-WpeText 'Admin.SelectPrinter') 'Warning'; return }
        $question = if ($paths.Count -eq 1) { Get-WpeText 'Admin.RemovePrinterConfirm' $paths[0] } else { Get-WpeText 'Admin.RemovePrintersConfirm' $paths.Count (Format-WpeList $paths) }
        if (-not (Confirm-WpeAction $question)) { return }
        $msg = ''
        try {
            $cfg = Read-WpeConfig -Path $script:ConfigPath
            foreach ($p in @($cfg.Printers | Where-Object { $paths -contains $_.Path })) { [void]$cfg.Printers.Remove($p) }
            Save-WpeConfig -Config $cfg -Path $script:ConfigPath -Confirm:$false
            $msg = Get-WpeText 'Admin.PrintersRemoved' $paths.Count
        } catch {
            Show-WpeMessage (Get-WpeText 'Common.RemoveFailed' $_.Exception.Message) 'Error'
        }
        Update-All
        if ($msg) { $statusLabel.Text = $msg }
    })

$doTest = {
    Invoke-WpeWithWaitCursor $form {
        $name = ConvertTo-WpeAccountName $txtTestUser.Text
        if (-not $name) { return }
        $lines = New-Object System.Collections.ArrayList
        try {
            $u = @(Find-WpeAdObject -Type User -SearchText $name -Exact) | Select-Object -First 1
            if (-not $u) { $txtTestResult.Text = Get-WpeText 'Force.UserNotFound' $name; return }
            $groupSids = @(Get-WpeAdUserGroupSids -UserSid $u.Sid)
            $config = Read-WpeEffectiveConfig -Path $script:ConfigPath -UserSid $u.Sid
            $hit = Resolve-WpeAssignment -Config $config -UserSid $u.Sid -UserName $u.Name -GroupSids $groupSids

            [void]$lines.Add((Get-WpeText 'Admin.ResultUser' $u.Name $u.DisplayName))
            [void]$lines.Add((Get-WpeText 'Admin.ResultSid' $u.Sid))
            [void]$lines.Add((Get-WpeText 'Admin.ResultGroups' $groupSids.Count))
            [void]$lines.Add('')
            if ($hit) {
                $via = if (Test-WpeChangedByUser $hit) { Get-WpeText 'Admin.ResultViaChoice' $hit.ModifiedAt }
                elseif ($hit.Type -eq 'User') { Get-WpeText 'Admin.ResultViaUser' } else { Get-WpeText 'Admin.ResultViaGroup' $hit.Name $hit.Priority }
                [void]$lines.Add((Get-WpeText 'Admin.ResultPrinter' $hit.Printer))
                [void]$lines.Add((Get-WpeText 'Admin.ResultVia' $via))
            } else {
                [void]$lines.Add((Get-WpeText 'Admin.ResultNone'))
            }
            $set = @{}; foreach ($g in $groupSids) { $set[$g] = $true }
            $groupHits = @($config.Assignments | Where-Object { $_.Type -eq 'Group' -and $set.ContainsKey($_.Sid) } | Sort-Object Priority, Name)
            if ($groupHits.Count -gt 0) {
                [void]$lines.Add('')
                [void]$lines.Add((Get-WpeText 'Admin.ResultGroupHits'))
                foreach ($g in $groupHits) { [void]$lines.Add(('  {0,5}  {1,-30} {2}' -f $g.Priority, $g.Name, $g.Printer)) }
            }
        } catch {
            [void]$lines.Add((Get-WpeText 'Admin.ResultError' $_.Exception.Message))
        }
        $txtTestResult.Text = $lines -join "`r`n"
    }
}
$btnTest.Add_Click($doTest)
$btnForceTest.Add_Click({ Show-ForceDialog -UserName (ConvertTo-WpeAccountName $txtTestUser.Text) })
$txtTestUser.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $_.SuppressKeyPress = $true; & $doTest } })
$btnUserLog.Add_Click({
        $name = ConvertTo-WpeAccountName $txtTestUser.Text
        if (-not $name) { Show-WpeMessage (Get-WpeText 'Admin.EnterLogonName') 'Warning'; return }
        $sid = Get-WpeAccountSid -Name $name
        if (-not $sid) { Show-WpeMessage (Get-WpeText 'Admin.UserNotFound' $name) 'Warning'; return }
        Show-AgentLog -Path (Get-WpeAgentLogPath -UserSid $sid) -Title (Get-WpeText 'Admin.LogOf' $name $env:COMPUTERNAME)
    })

$btnCheck.Add_Click({ Update-StatusList })
$btnUndo.Add_Click({ Invoke-UndoLastChange })
$btnRestartAll.Add_Click({ Invoke-RestartAll })
$btnFix.Add_Click({
        if ($lstStatus.SelectedItems.Count -ne 1) { Show-WpeMessage (Get-WpeText 'Admin.SelectCheck') 'Warning'; return }
        $c = $lstStatus.SelectedItems[0].Tag
        try {
            switch ($c.Fix) {
                'Policy' {
                    if (Confirm-WpeAction (Get-WpeText 'Admin.FixPolicyConfirm')) {
                        Set-WpeClientDefaultPrinterPolicy -Confirm:$false
                        Show-WpeMessage (Get-WpeText 'Admin.FixPolicyDone')
                    }
                }
                'EnableTask' {
                    Enable-ScheduledTask -TaskPath '\WePrintEasy\' -TaskName 'WePrintEasy Agent' | Out-Null
                    Show-WpeMessage (Get-WpeText 'Admin.FixTaskDone')
                }
                'ShareAccess' {
                    $sa = Get-WpeShareAccess -ConfigPath $script:ConfigPath
                    if (Confirm-WpeAction (Get-WpeText 'Admin.FixShareConfirm' "\\$($sa.Server)\$($sa.Share)" ($sa.ReadOnly -join ', '))) {
                        Set-WpeShareChangeAccess -ConfigPath $script:ConfigPath -Confirm:$false
                        Show-WpeMessage (Get-WpeText 'Admin.FixShareDone' "\\$($sa.Server)\$($sa.Share)")
                    }
                }
                'ChoiceFolder' {
                    Initialize-WpeChoiceDirectory -ConfigPath $script:ConfigPath -Confirm:$false
                    Show-WpeMessage (Get-WpeText 'Admin.FixChoiceDone' (Get-WpeChoiceDirectory $script:ConfigPath))
                }
                'Install' { Show-WpeMessage (Get-WpeText 'Admin.FixInstall') }
                default { Show-WpeMessage (Get-WpeText 'Admin.FixNone') }
            }
        } catch {
            Show-WpeMessage (Get-WpeText 'Admin.FixFailed' $_.Exception.Message) 'Error'
        }
        Update-StatusList
    })
$btnRunAgent.Add_Click({
        Invoke-WpeWithWaitCursor $form {
            $agent = Join-Path $PSScriptRoot 'WePrintEasy-Agent.ps1'
            $psExe = Join-Path $PSHOME 'powershell.exe'
            if (-not (Test-Path -LiteralPath $psExe)) { $psExe = (Get-Process -Id $PID).Path }
            $p = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', (Get-WpeExecutionPolicy -Path $agent), '-File', "`"$agent`"", '-Once', '-ConfigPath', "`"$script:ConfigPath`"") `
                -WindowStyle Hidden -PassThru -Wait
            $statusLabel.Text = Get-WpeText 'Admin.AgentRan' $p.ExitCode (Get-WpeDefaultPrinter)
        }
        Show-AgentLog -Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WePrintEasy\agent.log') -Title (Get-WpeText 'Admin.MyLog')
    })
$btnMyLog.Add_Click({ Show-AgentLog -Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WePrintEasy\agent.log') -Title (Get-WpeText 'Admin.MyLog') })

$chkEnforce.Add_CheckedChanged({ $numInterval.Enabled = $chkEnforce.Checked; $numDuration.Enabled = $chkEnforce.Checked })

function Set-NumberValue {
    param($Control, $Value)
    $v = [decimal][int]$Value
    $Control.Value = [Math]::Min($Control.Maximum, [Math]::Max($Control.Minimum, $v))
}

function Update-SettingsTab {
    $s = $script:Config.Settings
    Set-NumberValue $numLogon $s.LogonPhaseSeconds
    Set-NumberValue $numInterval $s.EnforceIntervalSeconds
    Set-NumberValue $numDuration $s.EnforceDurationMinutes
    $chkEnforce.Checked = [bool]$s.EnforceDuringSession
    $chkLegacy.Checked = [bool]$s.SetLegacyDefaultPrinterMode
    $chkConnect.Checked = [bool]$s.ConnectNetworkPrinters
    $chkUserChoice.Checked = [bool]$s.AllowUserPrinterChoice
    $txtDefServer.Text = [string]$s.DefaultPrintServer
    # Angezeigt wird die Sprache, in der das Programm gerade läuft
    $cboLanguage.SelectedIndex = [Math]::Max(0, [array]::IndexOf($script:LanguageCodes, (Get-WpeLanguage)))
    $numInterval.Enabled = $chkEnforce.Checked
    $numDuration.Enabled = $chkEnforce.Checked
}

$btnSaveSettings.Add_Click({
        $oldLanguage = Get-WpeLanguage
        $newLanguage = $script:LanguageCodes[$cboLanguage.SelectedIndex]
        try {
            # Frisch einlesen, damit parallele Änderungen an Zuweisungen erhalten bleiben
            $cfg = Read-WpeConfig -Path $script:ConfigPath
            $cfg.Settings.LogonPhaseSeconds = [int]$numLogon.Value
            $cfg.Settings.EnforceDuringSession = $chkEnforce.Checked
            $cfg.Settings.EnforceIntervalSeconds = [int]$numInterval.Value
            $cfg.Settings.EnforceDurationMinutes = [int]$numDuration.Value
            $cfg.Settings.SetLegacyDefaultPrinterMode = $chkLegacy.Checked
            $cfg.Settings.ConnectNetworkPrinters = $chkConnect.Checked
            $cfg.Settings.AllowUserPrinterChoice = $chkUserChoice.Checked
            $cfg.Settings.DefaultPrintServer = $txtDefServer.Text.Trim().TrimStart('\')
            $cfg.Settings.Language = $newLanguage
            Save-WpeConfig -Config $cfg -Path $script:ConfigPath -Confirm:$false
        } catch {
            Show-WpeMessage (Get-WpeText 'Common.SaveFailed' $_.Exception.Message) 'Error'
            return
        }
        # Ordner, in dem die Benutzer ihre Wahl speichern (nur eigene Datei schreibbar)
        if ($chkUserChoice.Checked) {
            try {
                Initialize-WpeChoiceDirectory -ConfigPath $script:ConfigPath -Confirm:$false
            } catch {
                Show-WpeMessage (Get-WpeText 'Settings.UserChoiceFolderFailed' (Get-WpeChoiceDirectory $script:ConfigPath) $_.Exception.Message) 'Warning'
            }
        }
        if ($newLanguage -eq $oldLanguage) {
            Update-All
            $statusLabel.Text = Get-WpeText 'Settings.Saved'
            return
        }
        Set-WpeLanguage $newLanguage
        # Sprache auch als Vorgabe dieses Servers (Installer, Update) und für die Verknüpfung - nur mit Administratorrechten
        try {
            Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WePrintEasy' -Name Language -Value $newLanguage -ErrorAction Stop
            Rename-WpeShortcut -Confirm:$false
        } catch { Write-Verbose $_.Exception.Message }
        if (Confirm-WpeAction (Get-WpeText 'Settings.LanguageRestart')) { Restart-AdminProgram; return }
        # Ohne Neustart bleibt die Oberfläche in der bisherigen Sprache
        Set-WpeLanguage $oldLanguage
        Update-All
        $statusLabel.Text = Get-WpeText 'Settings.Saved'
    })

$tabs.Add_SelectedIndexChanged({ if ($tabs.SelectedTab -eq $tabSetup -and $lstStatus.Items.Count -eq 0) { Update-StatusList } })

#endregion

#region Start -----------------------------------------------------------------

[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not $script:WpeScreenshotDir -and -not (Test-WpeConfigWritable -Path $script:ConfigPath)) {
    $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and (Confirm-WpeAction (Get-WpeText 'Admin.NoWriteRestart' $script:ConfigPath))) {
        $psExe = Join-Path $PSHOME 'powershell.exe'
        $argList = @('-NoProfile', '-ExecutionPolicy', (Get-WpeExecutionPolicy -Path $PSCommandPath), '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-ConfigPath', "`"$script:ConfigPath`"")
        Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs
        return
    }
    Show-WpeMessage (Get-WpeText 'Admin.NoWriteWarning' $script:ConfigPath) 'Warning'
}

$form.Add_Shown({
        Update-All
        $form.Activate()
        if (-not $script:WpeScreenshotDir) {
            if ($script:Config.Assignments.Count -eq 0 -and $script:Config.Printers.Count -eq 0) { $tabs.SelectedTab = $tabHelp }
            # Neue Version? Im Hintergrund, hoechstens einmal am Tag; Fehler werden ignoriert
            try { Start-WpeUpdateCheck -Owner $form -StatusLabel $statusLabel } catch { Write-Verbose $_.Exception.Message }
            return
        }
        # --- Test-/Dokumentationsmodus: alle Ansichten fotografieren -------------
        $form.TopMost = $true
        $steps = @(
            @{ Name = 'admin-1-zuweisungen'; Action = { $tabs.SelectedTab = $tabAssign; if ($grid.Rows.Count) { $grid.Rows[0].Selected = $true } } }
            @{ Name = ''; Action = { $a = $script:Config.Assignments | Where-Object { $_.Type -eq 'User' } | Select-Object -First 1; if ($a) { [void](Show-AssignmentDialog -Type 'User' -Existing $a -Config $script:Config) } } }
            @{ Name = ''; Action = { [void](Show-AssignmentDialog -Type 'Group' -Existing $null -Config $script:Config) } }
            @{ Name = 'admin-3-druckerliste'; Action = { $tabs.SelectedTab = $tabPrinters } }
            @{ Name = ''; Action = { Invoke-PrinterImport } }
            @{ Name = 'admin-4-benutzer-pruefen'; Action = { $tabs.SelectedTab = $tabTest; $txtTestUser.Text = $env:USERNAME; Show-AgentLog -Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WePrintEasy\agent.log') -Title (Get-WpeText 'Admin.LogOf' $env:USERNAME $env:COMPUTERNAME) } }
            @{ Name = ''; Action = { Show-ForceDialog -UserName $env:USERNAME } }
            @{ Name = 'admin-6-einrichtung'; Action = { $tabs.SelectedTab = $tabSetup; Update-StatusList } }
            @{ Name = 'admin-7-einstellungen'; Action = { $tabs.SelectedTab = $tabSettings } }
            @{ Name = 'admin-8-anleitung'; Action = { $tabs.SelectedTab = $tabHelp } }
            @{ Name = ''; Action = { Show-WpeAboutDialog -ConfigPath $script:ConfigPath } }
        )
        foreach ($s in $steps) {
            try {
                & $s.Action
                if ($s.Name) { Save-WpeScreenshot $form $s.Name }
            } catch {
                Write-WpeTestLog "ERROR $($s.Name): $($_.Exception.Message) $($_.ScriptStackTrace)"
            }
        }
        $form.Close()
    })
[void]$form.ShowDialog()
$form.Dispose()

#endregion
