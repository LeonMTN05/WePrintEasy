#Requires -Version 5.1
<#
    WePrintEasy - gemeinsame Bausteine fuer die grafischen Oberflaechen
    (Verwaltungsprogramm und Setup). Wird per Dot-Sourcing eingebunden.
    Alle Texte kommen ueber Get-WpeText aus WePrintEasy.Strings.<Sprache>.psd1.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not (Get-Variable -Name WpeAppTitle -Scope Script -ErrorAction SilentlyContinue)) { $script:WpeAppTitle = 'WePrintEasy' }
# Wird nur fuer automatisierte Tests/Dokumentation gesetzt: Bildschirmfotos statt Benutzerinteraktion
if (-not (Get-Variable -Name WpeScreenshotDir -Scope Script -ErrorAction SilentlyContinue)) { $script:WpeScreenshotDir = $null }

$script:WpeAccent = [System.Drawing.Color]::FromArgb(0, 95, 184)
$script:WpeFont = New-Object System.Drawing.Font('Segoe UI', 9)
$script:WpeFontBold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

# App-Symbol (liegt neben dieser Datei; erzeugt mit tools\New-WpeIcon.ps1)
$script:WpeIcon = $null
try { $script:WpeIcon = New-Object System.Drawing.Icon((Join-Path $PSScriptRoot 'WePrintEasy.ico')) } catch { Write-Verbose "Symbol nicht ladbar: $($_.Exception.Message)" }

#region Meldungen -------------------------------------------------------------

function Write-WpeTestLog {
    param([string]$Text)
    if ($script:WpeScreenshotDir) {
        Add-Content -LiteralPath (Join-Path $script:WpeScreenshotDir 'gui-messages.txt') -Value ('{0:HH:mm:ss} {1}' -f (Get-Date), $Text) -Encoding UTF8
    }
}

function Show-WpeMessage {
    param([string]$Text, [ValidateSet('Info', 'Warning', 'Error')][string]$Icon = 'Info')
    if ($script:WpeScreenshotDir) { Write-WpeTestLog "MESSAGE[$Icon] $Text"; return }
    $i = switch ($Icon) {
        'Info' { [System.Windows.Forms.MessageBoxIcon]::Information }
        'Warning' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error' { [System.Windows.Forms.MessageBoxIcon]::Error }
    }
    [void][System.Windows.Forms.MessageBox]::Show($Text, $script:WpeAppTitle, [System.Windows.Forms.MessageBoxButtons]::OK, $i)
}

function Confirm-WpeAction {
    param([string]$Text)
    if ($script:WpeScreenshotDir) { Write-WpeTestLog "CONFIRM $Text"; return $false }
    $r = [System.Windows.Forms.MessageBox]::Show($Text, $script:WpeAppTitle, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-WpeWithWaitCursor {
    param([System.Windows.Forms.Control]$Control, [scriptblock]$Action)
    $old = $Control.Cursor
    $Control.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try { & $Action } finally { $Control.Cursor = $old }
}

#endregion

#region Steuerelemente --------------------------------------------------------

function Set-WpeFormIcon {
    <# Setzt das App-Symbol fuer Titelleiste und Taskleiste. #>
    param([System.Windows.Forms.Form]$Form)
    if ($script:WpeIcon) { $Form.Icon = $script:WpeIcon }
}

function New-WpeLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 120, [int]$Height = 20)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, ($Y + 3))
    $l.Size = New-Object System.Drawing.Size($Width, $Height)
    return $l
}

function New-WpeButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 110)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($Width, 28)
    return $b
}

function New-WpeHeader {
    <# Farbiger Kopfbereich mit Titel und Untertitel. #>
    param([string]$Title, [string]$Subtitle, [int]$Height = 62)
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Top'
    $p.Height = $Height
    $p.BackColor = $script:WpeAccent
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title
    $t.ForeColor = [System.Drawing.Color]::White
    $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $t.Location = New-Object System.Drawing.Point(16, 8)
    $t.AutoSize = $true
    $p.Controls.Add($t)
    $s = New-Object System.Windows.Forms.Label
    $s.Text = $Subtitle
    $s.ForeColor = [System.Drawing.Color]::FromArgb(220, 235, 250)
    $s.Location = New-Object System.Drawing.Point(18, 38)
    $s.AutoSize = $true
    $p.Controls.Add($s)
    return $p
}

function New-WpeRichText {
    <# Schreibgeschuetztes Textfeld fuer formatierte Anleitungen. #>
    $r = New-Object System.Windows.Forms.RichTextBox
    $r.ReadOnly = $true
    $r.BorderStyle = 'None'
    $r.BackColor = [System.Drawing.SystemColors]::Window
    $r.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $r.DetectUrls = $false
    return $r
}

function Add-WpeRichText {
    <#
        Fuegt formatierten Text an. Zeilen-Praefixe:
          '# '  Ueberschrift      '## ' Zwischenueberschrift
          '- '  Aufzaehlung       '> '  Hinweis (farbig)
          '$ '  Befehl (Konsolenschrift)
    #>
    param([System.Windows.Forms.RichTextBox]$Box, [string[]]$Lines)
    foreach ($line in $Lines) {
        $text = $line; $font = New-Object System.Drawing.Font('Segoe UI', 10); $color = [System.Drawing.Color]::Black; $indent = 0
        if ($line.StartsWith('## ')) {
            $text = $line.Substring(3); $font = New-Object System.Drawing.Font('Segoe UI Semibold', 11); $color = $script:WpeAccent
        } elseif ($line.StartsWith('# ')) {
            $text = $line.Substring(2); $font = New-Object System.Drawing.Font('Segoe UI Semibold', 14); $color = $script:WpeAccent
        } elseif ($line.StartsWith('- ')) {
            $text = [char]0x2022 + ' ' + $line.Substring(2); $indent = 18
        } elseif ($line.StartsWith('> ')) {
            $text = $line.Substring(2); $color = [System.Drawing.Color]::FromArgb(160, 90, 0); $indent = 18
            $font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Italic)
        } elseif ($line.StartsWith('$ ')) {
            $text = $line.Substring(2); $font = New-Object System.Drawing.Font('Consolas', 9.5); $color = [System.Drawing.Color]::FromArgb(40, 40, 40); $indent = 18
        }
        $Box.SelectionStart = $Box.TextLength
        $Box.SelectionLength = 0
        $Box.SelectionFont = $font
        $Box.SelectionColor = $color
        $Box.SelectionIndent = $indent
        $Box.AppendText($text + "`n")
    }
    $Box.SelectionStart = 0
}

function Save-WpeScreenshot {
    <# Bildschirmfoto eines Fensters (nur im Test-/Dokumentationsmodus). #>
    param([System.Windows.Forms.Form]$Window, [string]$Name)
    if (-not $script:WpeScreenshotDir) { return }
    $Window.TopMost = $true
    $Window.BringToFront()
    $Window.Activate()
    $Window.Refresh()
    for ($i = 0; $i -lt 5; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 80 }
    $b = $Window.Bounds
    # 24 bit: GDI-Zeichnen setzt keinen Alphakanal - ein 32-bit-Bild waere sonst durchsichtig
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        # Das Fenster selbst zeichnen lassen (PW_RENDERFULLCONTENT): erfasst auch Teile ausserhalb des
        # Bildschirms - der Testrechner in GitHub Actions hat nur 1024 Pixel Breite, das Fenster 1120
        if (-not ('WePrintEasy.WindowCapture' -as [type])) {
            Add-Type -Namespace WePrintEasy -Name WindowCapture -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT rect, int size);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
        }
        $hdc = $g.GetHdc()
        try { $ok = [WePrintEasy.WindowCapture]::PrintWindow($Window.Handle, $hdc, 2) } finally { $g.ReleaseHdc($hdc) }
        if ($ok) {
            # Den unsichtbaren Rand (Windows 10/11: 7 px) malt PrintWindow schwarz - weiss uebermalen.
            # Die Bildgroesse bleibt (= Form.Bounds), website\scripts\screenshots.mjs schneidet den Rand ab.
            $r = New-Object WePrintEasy.WindowCapture+RECT
            if ([WePrintEasy.WindowCapture]::DwmGetWindowAttribute($Window.Handle, 9, [ref]$r, 16) -eq 0) {
                $region = New-Object System.Drawing.Region(New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height))
                $region.Exclude((New-Object System.Drawing.Rectangle(($r.Left - $b.Left), ($r.Top - $b.Top), ($r.Right - $r.Left), ($r.Bottom - $r.Top))))
                $g.FillRegion([System.Drawing.Brushes]::White, $region)
                $region.Dispose()
            }
        } else {
            $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        }
    } catch {
        $Window.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
    } finally {
        $g.Dispose()
    }
    $bmp.Save((Join-Path $script:WpeScreenshotDir "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-WpeTestLog "SCREENSHOT $Name"
}

#endregion

#region Sprachauswahl ---------------------------------------------------------

function Show-WpeLanguageDialog {
    <#
        Fragt die Sprache ab (Setup). Die Texte des Dialogs wechseln beim Auswaehlen mit.
        Rueckgabe: Sprachkuerzel (en, de) oder $null bei Abbruch.
    #>
    param([string]$Selected = 'en')
    $languages = Get-WpeSupportedLanguage
    $codes = @($languages.Keys)
    $result = @{ Value = $null }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Size = New-Object System.Drawing.Size(440, 220)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = $script:WpeFont
    Set-WpeFormIcon $dlg

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Location = New-Object System.Drawing.Point(20, 22)
    $pic.Size = New-Object System.Drawing.Size(48, 48)
    $pic.SizeMode = 'StretchImage'
    if ($script:WpeIcon) { $pic.Image = (New-Object System.Drawing.Icon($script:WpeIcon, 48, 48)).ToBitmap() }
    $lbl = New-WpeLabel '' 84 20 320 44
    $cbo = New-Object System.Windows.Forms.ComboBox
    $cbo.DropDownStyle = 'DropDownList'
    $cbo.Location = New-Object System.Drawing.Point(87, 72)
    $cbo.Size = New-Object System.Drawing.Size(220, 23)
    foreach ($code in $codes) { [void]$cbo.Items.Add($languages[$code]) }
    $btnOk = New-WpeButton '' 196 128 100
    $btnCancel = New-WpeButton '' 304 128 100
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.AddRange(@($pic, $lbl, $cbo, $btnOk, $btnCancel))

    $apply = {
        Set-WpeLanguage $codes[$cbo.SelectedIndex]
        $dlg.Text = Get-WpeText 'Language.DialogTitle'
        $lbl.Text = Get-WpeText 'Language.DialogText'
        $btnOk.Text = Get-WpeText 'Common.OK'
        $btnCancel.Text = Get-WpeText 'Common.Cancel'
    }
    $cbo.SelectedIndex = [Math]::Max(0, [array]::IndexOf($codes, $Selected))
    & $apply
    $cbo.Add_SelectedIndexChanged($apply)
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $result.Value = $codes[$cbo.SelectedIndex] }
    $dlg.Dispose()
    return $result.Value
}

#endregion

#region Druckerauswahl vom Druck-/Fileserver -----------------------------------

function New-WpePrinterPicker {
    <#
        Panel zur Auswahl der freigegebenen Drucker eines Druckservers.
        Rueckgabe: Hashtable mit Panel und Steuerelementen; Bedienung ueber
        Import-WpePickerPrinters und Get-WpePickerSelection.
    #>
    param([string]$Server = '', [string[]]$PreselectPaths = @())

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Fill'

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = 40
    $top.Controls.Add((New-WpeLabel (Get-WpeText 'Picker.Server') 0 8 120))
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(122, 8)
    $txt.Size = New-Object System.Drawing.Size(220, 23)
    $txt.Text = $Server
    $top.Controls.Add($txt)
    $btnLoad = New-WpeButton (Get-WpeText 'Picker.Load') 352 6 130
    $top.Controls.Add($btnLoad)

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'
    $bottom.Height = 66
    $btnAll = New-WpeButton (Get-WpeText 'Picker.All') 0 6 70
    $btnNone = New-WpeButton (Get-WpeText 'Picker.None') 76 6 70
    $btnLocal = New-WpeButton (Get-WpeText 'Picker.LocalOnly') 152 6 180
    $lblCount = New-WpeLabel (Get-WpeText 'Picker.NothingLoaded') 345 8 420
    $chkDrivers = New-Object System.Windows.Forms.CheckBox
    $chkDrivers.Text = Get-WpeText 'Picker.InstallDrivers'
    $chkDrivers.Location = New-Object System.Drawing.Point(2, 40)
    $chkDrivers.Size = New-Object System.Drawing.Size(760, 24)
    $bottom.Controls.AddRange(@($btnAll, $btnNone, $btnLocal, $lblCount, $chkDrivers))

    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.CheckBoxes = $true
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    [void]$list.Columns.Add((Get-WpeText 'Picker.ColPrinter'), 215)
    [void]$list.Columns.Add((Get-WpeText 'Picker.ColDriver'), 150)
    [void]$list.Columns.Add((Get-WpeText 'Picker.ColLocation'), 95)
    [void]$list.Columns.Add((Get-WpeText 'Picker.ColComment'), 105)
    [void]$list.Columns.Add((Get-WpeText 'Picker.ColLocalDriver'), 85)

    $panel.Controls.Add($list)
    $panel.Controls.Add($top)
    $panel.Controls.Add($bottom)
    $list.BringToFront()

    $picker = @{
        Panel = $panel; Server = $txt; LoadButton = $btnLoad; List = $list; CountLabel = $lblCount
        InstallDrivers = $chkDrivers; Preselect = $PreselectPaths; LoadedServer = ''
    }
    foreach ($c in @($btnLoad, $btnAll, $btnNone, $btnLocal, $list, $txt)) { $c.Tag = $picker }

    $btnLoad.Add_Click({ Import-WpePickerPrinters -Picker $this.Tag })
    $txt.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $_.SuppressKeyPress = $true; Import-WpePickerPrinters -Picker $this.Tag } })
    $btnAll.Add_Click({ Set-WpePickerChecks -Picker $this.Tag -Mode All })
    $btnNone.Add_Click({ Set-WpePickerChecks -Picker $this.Tag -Mode None })
    $btnLocal.Add_Click({ Set-WpePickerChecks -Picker $this.Tag -Mode Local })
    $list.Add_ItemChecked({ Update-WpePickerCount -Picker $this.Tag })
    return $picker
}

function Import-WpePickerPrinters {
    param([hashtable]$Picker)
    $server = $Picker.Server.Text.Trim().TrimStart('\').TrimEnd('\')
    if (-not $server) { Show-WpeMessage (Get-WpeText 'Picker.EnterServer') 'Warning'; return }
    $list = $Picker.List
    Invoke-WpeWithWaitCursor $Picker.Panel {
        try {
            $printers = @(Get-WpePrintServerPrinter -PrintServer $server)
        } catch {
            Show-WpeMessage (Get-WpeText 'Picker.LoadFailed' $server $_.Exception.Message) 'Error'
            return
        }
        $list.BeginUpdate()
        $list.Items.Clear()
        $pre = @($Picker.Preselect | Where-Object { $_ })
        foreach ($p in $printers) {
            $item = New-Object System.Windows.Forms.ListViewItem($p.Path)
            [void]$item.SubItems.Add($p.DriverName)
            [void]$item.SubItems.Add($p.Location)
            [void]$item.SubItems.Add($p.Comment)
            $local = if ($null -eq $p.DriverInstalled) { '?' } elseif ($p.DriverInstalled) { Get-WpeText 'Common.Yes' } else { Get-WpeText 'Common.No' }
            [void]$item.SubItems.Add($local)
            if ($p.DriverInstalled -eq $false) { $item.ForeColor = [System.Drawing.Color]::FromArgb(176, 96, 0) }
            $item.Tag = $p
            [void]$list.Items.Add($item)
            # Vorauswahl erst nach dem Einfuegen setzen (vorher gesetzte Haekchen verwirft die ListView):
            # bereits in der Druckerliste - sonst alle, deren Treiber hier schon installiert ist
            $item.Checked = if ($pre.Count -gt 0) { $pre -contains $p.Path } else { $p.DriverInstalled -ne $false }
        }
        $list.EndUpdate()
        $Picker.LoadedServer = $server
        Update-WpePickerCount -Picker $Picker
    }
}

function Set-WpePickerChecks {
    param([hashtable]$Picker, [ValidateSet('All', 'None', 'Local')][string]$Mode)
    $Picker.List.BeginUpdate()
    foreach ($item in $Picker.List.Items) {
        $item.Checked = switch ($Mode) { 'All' { $true } 'None' { $false } 'Local' { $item.Tag.DriverInstalled -ne $false } }
    }
    $Picker.List.EndUpdate()
    Update-WpePickerCount -Picker $Picker
}

function Update-WpePickerCount {
    param([hashtable]$Picker)
    $total = $Picker.List.Items.Count
    $checked = $Picker.List.CheckedItems.Count
    $noDriver = 0
    foreach ($item in $Picker.List.CheckedItems) { if ($item.Tag.DriverInstalled -eq $false) { $noDriver++ } }
    $text = Get-WpeText 'Picker.Count' $total $checked
    if ($noDriver) { $text += Get-WpeText 'Picker.CountNoDriver' $noDriver }
    $Picker.CountLabel.Text = $text
}

function Get-WpePickerSelection {
    <# Liefert die angehakten Drucker (Objekte von Get-WpePrintServerPrinter). #>
    param([hashtable]$Picker)
    foreach ($item in $Picker.List.CheckedItems) { $item.Tag }
}

function Invoke-WpeDriverInstallBatch {
    <# Installiert fehlende Treiber fuer die uebergebenen Drucker. $Progress: { param($Text) } #>
    param([object[]]$Printers, [scriptblock]$Progress)
    $todo = @($Printers | Where-Object { $_.DriverInstalled -eq $false })
    $ok = 0; $failed = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($p in $todo) {
        $n++
        if ($Progress) { & $Progress (Get-WpeText 'Picker.DriverProgress' $n $todo.Count $p.Path $p.DriverName) }
        try {
            Install-WpePrinterDriver -Path $p.Path -Confirm:$false
            $p.DriverInstalled = $true
            $ok++
        } catch {
            [void]$failed.Add("$($p.Path): $($_.Exception.Message)")
        }
    }
    [pscustomobject]@{ Requested = $todo.Count; Installed = $ok; Failed = $failed }
}

function Show-WpePrinterImportDialog {
    <#
        Dialog "Druckerliste vom Druckserver aktualisieren".
        Rueckgabe: @{ Server; Printers; InstallDrivers } oder $null.
    #>
    param([string]$Server, [string[]]$PreselectPaths = @())
    $result = @{ Value = $null }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = Get-WpeText 'Import.Title'
    $dlg.Size = New-Object System.Drawing.Size(900, 640)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.Font = $script:WpeFont
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    Set-WpeFormIcon $dlg

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = 'Fill'
    $content.Padding = New-Object System.Windows.Forms.Padding(12)
    $picker = New-WpePrinterPicker -Server $Server -PreselectPaths $PreselectPaths
    $content.Controls.Add($picker.Panel)

    $buttons = New-Object System.Windows.Forms.Panel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 46
    $btnOk = New-WpeButton (Get-WpeText 'Import.Apply') 640 8 110
    $btnCancel = New-WpeButton (Get-WpeText 'Common.Cancel') 758 8 110
    $btnOk.Font = $script:WpeFontBold
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttons.Controls.AddRange(@($btnOk, $btnCancel))
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.Add($content)
    $dlg.Controls.Add($buttons)
    $dlg.Controls.Add((New-WpeHeader (Get-WpeText 'Import.Header') (Get-WpeText 'Import.Subtitle')))
    $content.BringToFront()

    $btnOk.Tag = @{ Picker = $picker; Result = $result; Dialog = $dlg }
    $btnOk.Add_Click({
            $ctx = $this.Tag
            if (-not $ctx.Picker.LoadedServer) { Show-WpeMessage (Get-WpeText 'Import.LoadFirst') 'Warning'; return }
            $ctx.Result.Value = @{
                Server         = $ctx.Picker.LoadedServer
                Printers       = @(Get-WpePickerSelection -Picker $ctx.Picker)
                InstallDrivers = $ctx.Picker.InstallDrivers.Checked
            }
            $ctx.Dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $ctx.Dialog.Close()
        })
    $dlg.Tag = $picker
    $dlg.Add_Shown({
            $p = $this.Tag
            if ($p.Server.Text) { Import-WpePickerPrinters -Picker $p }
            if ($script:WpeScreenshotDir) { Save-WpeScreenshot $this 'admin-5-druckerliste-import'; $this.Close() }
        })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $result.Value
}

#endregion

#region Info ------------------------------------------------------------------

function Get-WpeDisclaimerText {
    @(Get-WpeText 'About.Disclaimer') -join "`r`n"
}

function Open-WpeUrl {
    <# Oeffnet einen Link im Standardbrowser; geht das nicht, wird er in die Zwischenablage kopiert. #>
    param([string]$Url)
    if ($script:WpeScreenshotDir) { Write-WpeTestLog "OPEN $Url"; return }
    try {
        Start-Process -FilePath $Url
    } catch {
        [System.Windows.Forms.Clipboard]::SetText($Url)
        Show-WpeMessage (Get-WpeText 'About.BrowserFailed' $Url) 'Warning'
    }
}

function Show-WpeAboutDialog {
    <# Info: Version, Credits, Systeminformationen, Fehler melden, Haftungsausschluss. #>
    param([string]$ConfigPath = (Get-WpeConfigPath), [string]$ScreenshotName = 'admin-10-info')
    $about = Get-WpeAboutInfo
    $sysInfo = Get-WpeSystemInfo -ConfigPath $ConfigPath
    $sysText = (@(foreach ($k in $sysInfo.Keys) { '{0,-16} {1}' -f "${k}:", $sysInfo[$k] })) -join "`r`n"

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = Get-WpeText 'About.Title' $about.Version
    $dlg.Size = New-Object System.Drawing.Size(760, 754)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.Font = $script:WpeFont
    Set-WpeFormIcon $dlg

    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'

    # --- Credits ---
    $lblBy = New-WpeLabel (Get-WpeText 'About.DevelopedBy') 18 14 110
    $lnkAuthor = New-Object System.Windows.Forms.LinkLabel
    $lnkAuthor.Text = Get-WpeText 'About.AuthorOnGitHub' $about.Author
    $lnkAuthor.Location = New-Object System.Drawing.Point(130, 17)
    $lnkAuthor.AutoSize = $true
    $lnkAuthor.Font = $script:WpeFontBold
    $lnkAuthor.Tag = $about.AuthorUrl
    $lblProject = New-WpeLabel (Get-WpeText 'About.Project') 18 38 110
    $lnkProject = New-Object System.Windows.Forms.LinkLabel
    $lnkProject.Text = $about.ProjectUrl
    $lnkProject.Location = New-Object System.Drawing.Point(130, 41)
    $lnkProject.AutoSize = $true
    $lnkProject.Tag = $about.ProjectUrl
    $lblLicense = New-WpeLabel (Get-WpeText 'About.License') 18 62 110
    $lnkLicense = New-Object System.Windows.Forms.LinkLabel
    $licenseName = Get-WpeText 'About.LicenseName' $about.License
    $lnkLicense.Text = Get-WpeText 'About.LicenseText' $licenseName
    $lnkLicense.LinkArea = New-Object System.Windows.Forms.LinkArea(0, $licenseName.Length)
    $lnkLicense.Location = New-Object System.Drawing.Point(130, 65)
    $lnkLicense.AutoSize = $true
    $lnkLicense.Tag = $about.LicenseUrl
    foreach ($l in $lnkAuthor, $lnkProject, $lnkLicense) { $l.Add_LinkClicked({ Open-WpeUrl $this.Tag }) }
    $lblThanks = New-WpeLabel (Get-WpeText 'About.Thanks') 18 90 700 20
    $lblThanks.ForeColor = [System.Drawing.Color]::DimGray

    # --- Systeminformationen / Fehler melden ---
    $grpSys = New-Object System.Windows.Forms.GroupBox
    $grpSys.Text = Get-WpeText 'About.SystemInfo'
    $grpSys.Location = New-Object System.Drawing.Point(15, 122)
    $grpSys.Size = New-Object System.Drawing.Size(715, 262)
    $txtSys = New-Object System.Windows.Forms.TextBox
    $txtSys.Multiline = $true
    $txtSys.ReadOnly = $true
    $txtSys.ScrollBars = 'Vertical'
    $txtSys.BackColor = [System.Drawing.SystemColors]::Window
    $txtSys.Font = New-Object System.Drawing.Font('Consolas', 9)
    $txtSys.Location = New-Object System.Drawing.Point(12, 24)
    $txtSys.Size = New-Object System.Drawing.Size(690, 158)
    $txtSys.Text = $sysText
    $btnCopy = New-WpeButton (Get-WpeText 'About.Copy') 12 190 110
    $btnIssue = New-WpeButton (Get-WpeText 'About.ReportIssue') 128 190 210
    $btnIssue.Font = $script:WpeFontBold
    $lblIssue = New-WpeLabel (Get-WpeText 'About.ReportIssueHint') 12 222 690 34
    $lblIssue.ForeColor = [System.Drawing.Color]::DimGray
    $grpSys.Controls.AddRange(@($txtSys, $btnCopy, $btnIssue, $lblIssue))
    $btnCopy.Tag = $sysText
    $btnCopy.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($this.Tag); $this.Text = Get-WpeText 'About.Copied' })
    $btnIssue.Tag = $sysInfo
    $btnIssue.Add_Click({ Open-WpeUrl (Get-WpeIssueUrl -SystemInfo $this.Tag) })

    # --- Haftungsausschluss ---
    $grpLegal = New-Object System.Windows.Forms.GroupBox
    $grpLegal.Text = Get-WpeText 'About.DisclaimerTitle'
    $grpLegal.Location = New-Object System.Drawing.Point(15, 394)
    $grpLegal.Size = New-Object System.Drawing.Size(715, 200)
    $txtLegal = New-Object System.Windows.Forms.TextBox
    $txtLegal.Multiline = $true
    $txtLegal.ReadOnly = $true
    $txtLegal.ScrollBars = 'Vertical'
    $txtLegal.BorderStyle = 'None'
    $txtLegal.BackColor = [System.Drawing.SystemColors]::Control
    $txtLegal.Location = New-Object System.Drawing.Point(12, 24)
    $txtLegal.Size = New-Object System.Drawing.Size(690, 166)
    $txtLegal.Text = Get-WpeDisclaimerText
    $grpLegal.Controls.Add($txtLegal)

    $body.Controls.AddRange(@($lblBy, $lnkAuthor, $lblProject, $lnkProject, $lblLicense, $lnkLicense, $lblThanks, $grpSys, $grpLegal))

    $buttons = New-Object System.Windows.Forms.Panel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 46
    $btnClose = New-WpeButton (Get-WpeText 'Common.Close') 620 6 110
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttons.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $dlg.Controls.Add($body)
    $dlg.Controls.Add($buttons)
    $dlg.Controls.Add((New-WpeHeader "WePrintEasy $($about.Version)" (Get-WpeText 'App.Tagline')))
    $body.BringToFront()

    $dlg.Tag = $ScreenshotName
    $dlg.Add_Shown({
            $this.ActiveControl = $this.CancelButton
            if ($script:WpeScreenshotDir) { Save-WpeScreenshot $this $this.Tag; $this.Close() }
        })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

#endregion

#region Update-Pruefung -------------------------------------------------------

$script:WpeUpdateJob = $null
$script:WpeUpdateDownload = $null

function Start-WpeUpdateCheck {
    <#
        Prueft im Hintergrund, ob es eine neue Version gibt (latest.json, Timeout 10 s), ohne das
        Fenster zu blockieren. Automatisch hoechstens einmal am Tag; Fehler werden still ignoriert.
        -Manual ("Nach Updates suchen"): immer pruefen und das Ergebnis bzw. den Fehler anzeigen.
    #>
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Owner,
        [switch]$Manual,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    if ($script:WpeScreenshotDir -or $script:WpeUpdateJob) { return }
    if ($script:WpeUpdateDownload) {
        # Laeuft schon ein Download: nur wieder anzeigen, dass er laeuft
        if ($Manual -and $StatusLabel) { $StatusLabel.Text = $script:WpeUpdateDownload.Text }
        return
    }
    if (-not $Manual) {
        if (-not (Test-WpeUpdateCheckDue)) { return }
        Set-WpeUpdateCheckTime
    }
    # Eigener Runspace mit dem Modul: Abruf und Pruefung von latest.json (Get-WpeLatestRelease)
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
            param($ModulePath, $Language)
            try {
                Import-Module $ModulePath -Force -ErrorAction Stop
                Set-WpeLanguage $Language
                @{ Release = (Get-WpeLatestRelease -TimeoutSec 10); Error = '' }
            } catch { @{ Release = $null; Error = $_.Exception.Message } }
        }.ToString()).AddArgument((Get-Module WePrintEasy).Path).AddArgument((Get-WpeLanguage))
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $script:WpeUpdateJob = @{ PS = $ps; Handle = $ps.BeginInvoke(); Timer = $timer; Owner = $Owner; Manual = [bool]$Manual; Started = Get-Date; Status = $StatusLabel }
    if ($Manual -and $StatusLabel) { $StatusLabel.Text = Get-WpeText 'UpdateCheck.Checking' }
    $timer.Add_Tick({ Complete-WpeUpdateCheck })
    $timer.Start()
}

function Complete-WpeUpdateCheck {
    <# Timer: wertet die fertige Hintergrundpruefung aus und bietet ggf. das Update an. #>
    $job = $script:WpeUpdateJob
    if (-not $job) { return }
    $timedOut = ((Get-Date) - $job.Started).TotalSeconds -ge 20
    if (-not $job.Handle.IsCompleted -and -not $timedOut) { return }
    $job.Timer.Stop()
    $job.Timer.Dispose()
    $script:WpeUpdateJob = $null
    if ($job.Manual -and $job.Status) { $job.Status.Text = '' }
    $result = $null
    if ($job.Handle.IsCompleted) {
        try { $result = @($job.PS.EndInvoke($job.Handle))[0] } catch { $result = @{ Release = $null; Error = $_.Exception.Message } }
        $job.PS.Dispose()
    } else {
        # Haengt z. B. an einem Proxy: aufgeben, die Verwaltung laeuft normal weiter
        [void]$job.PS.BeginStop($null, $null)
        $result = @{ Release = $null; Error = 'Timeout' }
    }
    if ($job.Owner.IsDisposed) { return }
    $release = if ($result) { $result.Release } else { $null }
    if (-not $release) {
        if ($job.Manual) { Show-WpeMessage (Get-WpeText 'UpdateCheck.Failed' $(if ($result -and $result.Error) { $result.Error } else { 'no response' })) 'Warning' }
        return
    }
    if (-not (Test-WpeNewerVersion -Latest $release.Version)) {
        if ($job.Manual) { Show-WpeMessage (Get-WpeText 'UpdateCheck.UpToDate' (Get-WpeAboutInfo).Version) }
        return
    }
    if (Show-WpeUpdatePrompt -Release $release -Owner $job.Owner) {
        Invoke-WpeUpdate -Release $release -Owner $job.Owner -StatusLabel $job.Status
    }
}

function Show-WpeUpdatePrompt {
    <# Dialog "Neue Version X verfuegbar" mit "Jetzt aktualisieren" / "Spaeter"; $true = jetzt aktualisieren. #>
    param([Parameter(Mandatory)]$Release, [System.Windows.Forms.Form]$Owner)
    $culture = [Globalization.CultureInfo]::GetCultureInfo($(if ((Get-WpeLanguage) -eq 'de') { 'de-DE' } else { 'en-US' }))
    $released = if ($Release.Released) { Get-WpeText 'UpdateCheck.Released' $Release.Released.LocalDateTime.ToString('d', $culture) } else { '' }
    $size = '{0} MB' -f ($Release.Size / 1MB).ToString('N1', $culture)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = Get-WpeText 'UpdateCheck.Title' $Release.Version
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 196)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.Font = $script:WpeFont
    Set-WpeFormIcon $dlg

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Location = New-Object System.Drawing.Point(20, 20)
    $pic.Size = New-Object System.Drawing.Size(48, 48)
    $pic.SizeMode = 'StretchImage'
    if ($script:WpeIcon) { $pic.Image = (New-Object System.Drawing.Icon($script:WpeIcon, 48, 48)).ToBitmap() }
    $title = New-WpeLabel (Get-WpeText 'UpdateCheck.Title' $Release.Version) 84 14 456 26
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $title.ForeColor = $script:WpeAccent
    $text = New-WpeLabel ((@(Get-WpeText 'UpdateCheck.Text' $Release.Version (Get-WpeAboutInfo).Version $released $size)) -join "`r`n") 84 46 456 96
    $btnNow = New-WpeButton (Get-WpeText 'UpdateCheck.Now') 274 152 160
    $btnNow.Font = $script:WpeFontBold
    $btnNow.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnLater = New-WpeButton (Get-WpeText 'UpdateCheck.Later') 440 152 100
    $btnLater.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.AddRange(@($pic, $title, $text, $btnNow, $btnLater))
    $dlg.AcceptButton = $btnNow
    $dlg.CancelButton = $btnLater
    $r = if ($Owner -and -not $Owner.IsDisposed) { $dlg.ShowDialog($Owner) } else { $dlg.ShowDialog() }
    $dlg.Dispose()
    return ($r -eq [System.Windows.Forms.DialogResult]::OK)
}

function Invoke-WpeUpdate {
    <#
        Laedt das Setup im Hintergrund (SHA-256 geprueft), ohne das Fenster zu blockieren - bei
        langsamer Leitung dauert das. Danach startet es in der eingestellten Sprache und beendet das Programm.
    #>
    param([Parameter(Mandatory)]$Release, [Parameter(Mandatory)][System.Windows.Forms.Form]$Owner, [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel)
    if ($script:WpeUpdateDownload) { return }
    $text = Get-WpeText 'UpdateCheck.Downloading' $Release.Version
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
            param($ModulePath, $Language, $Release)
            try {
                Import-Module $ModulePath -Force -ErrorAction Stop
                Set-WpeLanguage $Language
                @{ Path = (Save-WpeUpdate -Release $Release); Error = '' }
            } catch { @{ Path = $null; Error = $_.Exception.Message } }
        }.ToString()).AddArgument((Get-Module WePrintEasy).Path).AddArgument((Get-WpeLanguage)).AddArgument($Release)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $script:WpeUpdateDownload = @{ PS = $ps; Handle = $ps.BeginInvoke(); Timer = $timer; Owner = $Owner; Status = $StatusLabel; Text = $text }
    if ($StatusLabel) { $StatusLabel.Text = $text }
    $timer.Add_Tick({ Complete-WpeUpdate })
    $timer.Start()
}

function Complete-WpeUpdate {
    <# Timer: startet nach dem Download das Setup (oder meldet den Fehler). #>
    $job = $script:WpeUpdateDownload
    if (-not $job -or -not $job.Handle.IsCompleted) { return }
    # Ist gerade ein Dialog offen (Hauptfenster gesperrt), erst nach dessen Schliessen weitermachen
    if (-not $job.Owner.IsDisposed -and -not $job.Owner.Enabled) { return }
    $job.Timer.Stop()
    $job.Timer.Dispose()
    $script:WpeUpdateDownload = $null
    try { $result = @($job.PS.EndInvoke($job.Handle))[0] } catch { $result = @{ Path = $null; Error = $_.Exception.Message } }
    $job.PS.Dispose()
    # Statuszeile nur leeren, wenn sie noch den Download anzeigt (das Fenster blieb ja bedienbar)
    if ($job.Status -and $job.Status.Text -eq $job.Text) { $job.Status.Text = '' }
    $Owner = $job.Owner
    if ($Owner.IsDisposed) { return }
    $path = if ($result) { $result.Path } else { $null }
    if (-not $path) {
        Show-WpeMessage (Get-WpeText 'UpdateCheck.DownloadFailed' $(if ($result -and $result.Error) { $result.Error } else { 'no response' })) 'Error'
        return
    }
    try {
        # Das Setup braucht Administratorrechte; es erkennt die Installation und aktualisiert sie
        Start-Process -FilePath $path -ArgumentList "/LANG=$(Get-WpeLanguage)" -Verb RunAs -ErrorAction Stop
    } catch {
        Show-WpeMessage (Get-WpeText 'UpdateCheck.StartFailed' $_.Exception.Message) 'Error'
        return
    }
    $Owner.Close()
}

#endregion

#region Anleitung -------------------------------------------------------------

function Get-WpeGuideLines {
    <# Text der Anleitung (Formatierung siehe Add-WpeRichText). -Section: All, Server, Assign, User, Troubleshooting #>
    param([ValidateSet('All', 'Server', 'Assign', 'User', 'Troubleshooting')][string]$Section = 'All')
    if ($Section -eq 'All') {
        foreach ($s in 'Intro', 'Server', 'Assign', 'User', 'Troubleshooting') { Get-WpeText "Guide.$s" }
    } else {
        Get-WpeText "Guide.$Section"
    }
}

#endregion
