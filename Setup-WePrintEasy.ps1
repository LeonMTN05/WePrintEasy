#Requires -Version 5.1
<#
.SYNOPSIS
    WePrintEasy Setup-Assistent (grafisch). Start über Setup.cmd.

.DESCRIPTION
    Fragt zuerst die Sprache ab (Standard: Englisch) und führt dann Schritt für
    Schritt durch die Ersteinrichtung auf einem Terminalserver:
      1. Speicherort der Konfiguration (lokal oder zentral auf dem Fileserver)
      2. Drucker vom Druck-/Fileserver übernehmen (Vorauswahl: Treiber lokal vorhanden)
      3. Optionen (RDS-Richtlinie, Überwachung, ...)
      4. Installation (ruft Install-WePrintEasy.ps1 auf)
    Die gewählte Sprache gilt danach auch für Verwaltung und Agent-Protokoll
    (änderbar in der Verwaltung unter "Einstellungen").

.PARAMETER PrintServer
    Vorbelegung für den Druck-/Fileserver.

.PARAMETER Language
    Sprache (en, de). Ohne Angabe fragt das Setup danach.

.PARAMETER ScreenshotDir
    Nur für automatisierte Tests/Dokumentation: durchläuft alle Schritte
    inklusive Installation ohne Benutzerinteraktion und speichert Bildschirmfotos.
#>
[CmdletBinding()]
param(
    [string]$PrintServer,
    [ValidateSet('en', 'de')][string]$Language,
    [string]$ScreenshotDir
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
Import-Module (Join-Path $src 'WePrintEasy.psm1') -Force
$script:WpeAppTitle = 'WePrintEasy Setup'
$script:WpeScreenshotDir = $ScreenshotDir
. (Join-Path $src 'WePrintEasy.Gui.ps1')

# --- Administratorrechte ---------------------------------------------------------
$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($PrintServer) { $argList += @('-PrintServer', "`"$PrintServer`"") }
    if ($Language) { $argList += @('-Language', $Language) }
    try { Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs } catch { Show-WpeMessage (Get-WpeText 'Setup.NeedsAdmin') 'Error' }
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Sprache -----------------------------------------------------------------------
# Vorauswahl: Sprache einer vorhandenen Installation, sonst Englisch
if (-not $Language -and $script:WpeScreenshotDir) { $Language = Get-WpeLanguage }
if (-not $Language) {
    $Language = Show-WpeLanguageDialog -Selected (Get-WpeLanguage)
    if (-not $Language) { return }
}
Set-WpeLanguage $Language

# --- Vorhandene Installation / Vorbelegung -------------------------------------
$defaultLocal = Join-Path $env:ProgramData 'WePrintEasy\config.json'
$reg = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WePrintEasy' -ErrorAction SilentlyContinue
$existingPath = if ($reg -and $reg.PSObject.Properties['ConfigPath']) { [string]$reg.ConfigPath } else { '' }
$existingCfg = $null
try { $existingCfg = Read-WpeConfig -Path $(if ($existingPath) { $existingPath } else { $defaultLocal }) } catch { Write-Verbose $_.Exception.Message }
if (-not $PrintServer -and $existingCfg -and $existingCfg.Settings.DefaultPrintServer) { $PrintServer = [string]$existingCfg.Settings.DefaultPrintServer }
if (-not $PrintServer) { $PrintServer = @(Get-WpeKnownPrintServer) | Select-Object -First 1 }
$preselect = @()
if ($existingCfg) { $preselect = @($existingCfg.Printers | ForEach-Object { $_.Path }) }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'WePrintEasy Setup'
$form.Size = New-Object System.Drawing.Size(1000, 680)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = $script:WpeFont
Set-WpeFormIcon $form

# --- Seitenleiste ---
$side = New-Object System.Windows.Forms.Panel
$side.Dock = 'Left'
$side.Width = 220
$side.BackColor = [System.Drawing.Color]::FromArgb(0, 70, 140)
$sideLogo = New-Object System.Windows.Forms.PictureBox
$sideLogo.Location = New-Object System.Drawing.Point(18, 22)
$sideLogo.Size = New-Object System.Drawing.Size(48, 48)
$sideLogo.SizeMode = 'StretchImage'
if ($script:WpeIcon) { $sideLogo.Image = (New-Object System.Drawing.Icon($script:WpeIcon, 48, 48)).ToBitmap() }
$side.Controls.Add($sideLogo)
$sideTitle = New-Object System.Windows.Forms.Label
$sideTitle.Text = "WePrintEasy`nSetup"
$sideTitle.ForeColor = [System.Drawing.Color]::White
$sideTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$sideTitle.Location = New-Object System.Drawing.Point(74, 18)
$sideTitle.Size = New-Object System.Drawing.Size(140, 60)
$side.Controls.Add($sideTitle)

$stepNames = @(Get-WpeText 'Setup.Steps')
$stepLabels = @()
for ($i = 0; $i -lt $stepNames.Count; $i++) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "$($i + 1).  $($stepNames[$i])"
    $l.Location = New-Object System.Drawing.Point(20, (110 + $i * 36))
    $l.Size = New-Object System.Drawing.Size(195, 26)
    $side.Controls.Add($l)
    $stepLabels += $l
}
$infoLink = Get-WpeText 'Setup.InfoLink'
$lnkInfo = New-Object System.Windows.Forms.LinkLabel
$lnkInfo.Text = (Get-WpeText 'Setup.Version' (Get-WpeAboutInfo).Version) + '  -  ' + $infoLink
$lnkInfo.Dock = 'Bottom'
$lnkInfo.Height = 40
$lnkInfo.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0)
$lnkInfo.LinkArea = New-Object System.Windows.Forms.LinkArea(($lnkInfo.Text.Length - $infoLink.Length), $infoLink.Length)
$lnkInfo.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
$lnkInfo.LinkColor = [System.Drawing.Color]::White
$lnkInfo.ActiveLinkColor = [System.Drawing.Color]::White
$lnkInfo.Add_LinkClicked({ Show-WpeAboutDialog -ConfigPath $(if ($existingPath) { $existingPath } else { $defaultLocal }) -ScreenshotName 'setup-info' })
$side.Controls.Add($lnkInfo)

# --- Schaltflächen ---
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 54
$line = New-Object System.Windows.Forms.Label
$line.Dock = 'Top'
$line.Height = 1
$line.BackColor = [System.Drawing.Color]::Gainsboro
$bottom.Controls.Add($line)
$btnBack = New-WpeButton (Get-WpeText 'Setup.Back') 395 13 110
$btnNext = New-WpeButton (Get-WpeText 'Setup.Next') 511 13 120
$btnCancel = New-WpeButton (Get-WpeText 'Common.Cancel') 641 13 110
$btnNext.Font = $script:WpeFontBold
$bottom.Controls.AddRange(@($btnBack, $btnNext, $btnCancel))

# --- Inhalt ---
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 10)

$form.Controls.Add($content)
$form.Controls.Add($bottom)
$form.Controls.Add($side)
$content.BringToFront()

function New-Page {
    param([string]$Title, [string]$Subtitle)
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.Visible = $false
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title
    $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $t.ForeColor = $script:WpeAccent
    $t.Dock = 'Top'
    $t.Height = 34
    $s = New-Object System.Windows.Forms.Label
    $s.Text = $Subtitle
    $s.ForeColor = [System.Drawing.Color]::DimGray
    $s.Dock = 'Top'
    $s.Height = 40
    $p.Controls.Add($body)
    $p.Controls.Add($s)
    $p.Controls.Add($t)
    $body.BringToFront()
    $content.Controls.Add($p)
    return @{ Page = $p; Body = $body }
}

# ---- Seite 1: Willkommen ----
$pgWelcome = New-Page (Get-WpeText 'Setup.WelcomeTitle') (Get-WpeText 'Setup.WelcomeSubtitle')
$rtfWelcome = New-WpeRichText
$rtfWelcome.Dock = 'Fill'
$pgWelcome.Body.Controls.Add($rtfWelcome)
$os = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue)
$existingText = if ($existingPath) { Get-WpeText 'Setup.ExistingYes' $existingPath } else { Get-WpeText 'Common.No' }
$welcome = @(Get-WpeText 'Setup.WelcomeText') + @(
    "- $(Get-WpeText 'Setup.ServerName' $env:COMPUTERNAME)"
    "- $(Get-WpeText 'Setup.ServerOs' $(if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString }))"
    "- $(Get-WpeText 'Setup.ServerUser' (Get-WpeCurrentAccount))"
    "- $(Get-WpeText 'Setup.ServerExisting' $existingText)"
    "- $(Get-WpeText 'Setup.ServerLanguage' (Get-WpeSupportedLanguage)[$Language])"
)
Add-WpeRichText $rtfWelcome $welcome

# ---- Seite 2: Konfiguration ----
$pgConfig = New-Page (Get-WpeText 'Setup.ConfigTitle') (Get-WpeText 'Setup.ConfigSubtitle')
$rbLocal = New-Object System.Windows.Forms.RadioButton
$rbLocal.Text = Get-WpeText 'Setup.ConfigLocal' $defaultLocal
$rbLocal.Location = New-Object System.Drawing.Point(0, 10)
$rbLocal.Size = New-Object System.Drawing.Size(700, 26)
$rbCentral = New-Object System.Windows.Forms.RadioButton
$rbCentral.Text = Get-WpeText 'Setup.ConfigCentral'
$rbCentral.Location = New-Object System.Drawing.Point(0, 44)
$rbCentral.Size = New-Object System.Drawing.Size(700, 26)
$txtCentral = New-Object System.Windows.Forms.TextBox
$txtCentral.Location = New-Object System.Drawing.Point(22, 76)
$txtCentral.Size = New-Object System.Drawing.Size(460, 23)
$btnTestPath = New-WpeButton (Get-WpeText 'Setup.ConfigTest') 492 74 90
$lblPathResult = New-WpeLabel '' 22 108 700 40
$cfgHint = New-WpeLabel (@(Get-WpeText 'Setup.ConfigHint') -join "`n") 22 160 720 60
$cfgHint.ForeColor = [System.Drawing.Color]::DimGray
$pgConfig.Body.Controls.AddRange(@($rbLocal, $rbCentral, $txtCentral, $btnTestPath, $lblPathResult, $cfgHint))
if ($existingPath -and $existingPath.StartsWith('\\')) { $rbCentral.Checked = $true; $txtCentral.Text = $existingPath } else { $rbLocal.Checked = $true }
$syncCentral = { $txtCentral.Enabled = $rbCentral.Checked; $btnTestPath.Enabled = $rbCentral.Checked }
$rbLocal.Add_CheckedChanged($syncCentral)
$rbCentral.Add_CheckedChanged($syncCentral)
& $syncCentral

function Get-ChosenConfigPath {
    if ($rbCentral.Checked) {
        $p = $txtCentral.Text.Trim()
        if ($p -and -not $p.EndsWith('.json')) { $p = Join-Path $p 'config.json' }
        return $p
    }
    return $defaultLocal
}

function Test-ChosenConfigPath {
    $p = Get-ChosenConfigPath
    if (-not $p) { $lblPathResult.Text = Get-WpeText 'Setup.ConfigEmpty'; $lblPathResult.ForeColor = [System.Drawing.Color]::Firebrick; return $false }
    if ($rbCentral.Checked -and -not $p.StartsWith('\\')) { $lblPathResult.Text = Get-WpeText 'Setup.ConfigNotUnc'; $lblPathResult.ForeColor = [System.Drawing.Color]::Firebrick; return $false }
    if (Test-WpeConfigWritable -Path $p) {
        $exists = Test-Path -LiteralPath $p
        $lblPathResult.Text = if ($exists) { Get-WpeText 'Setup.ConfigReuse' $p } else { Get-WpeText 'Setup.ConfigNew' $p }
        $lblPathResult.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 16)
        return $true
    }
    $lblPathResult.Text = Get-WpeText 'Setup.ConfigNoWrite' $p
    $lblPathResult.ForeColor = [System.Drawing.Color]::Firebrick
    return $false
}
$btnTestPath.Add_Click({ [void](Test-ChosenConfigPath) })

# ---- Seite 3: Drucker ----
$pgPrinters = New-Page (Get-WpeText 'Setup.PrintersTitle') (Get-WpeText 'Setup.PrintersSubtitle')
$picker = New-WpePrinterPicker -Server $PrintServer -PreselectPaths $preselect
$pgPrinters.Body.Controls.Add($picker.Panel)

# ---- Seite 4: Optionen ----
$pgOptions = New-Page (Get-WpeText 'Setup.OptionsTitle') (Get-WpeText 'Setup.OptionsSubtitle')
function New-OptionCheck {
    param([string]$Text, [string]$Hint, [int]$Y, [bool]$Checked = $true)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Font = $script:WpeFontBold
    $c.Checked = $Checked
    $c.Location = New-Object System.Drawing.Point(0, $Y)
    $c.Size = New-Object System.Drawing.Size(720, 24)
    $h = New-WpeLabel $Hint 20 ($Y + 22) 700 36
    $h.ForeColor = [System.Drawing.Color]::DimGray
    $pgOptions.Body.Controls.AddRange(@($c, $h))
    return $c
}
$s0 = if ($existingCfg) { $existingCfg.Settings } else { [pscustomobject](Get-WpeDefaultSettings) }
$optPolicy = New-OptionCheck (Get-WpeText 'Setup.OptPolicy') (Get-WpeText 'Setup.OptPolicyHint') 0
$optEnforce = New-OptionCheck (Get-WpeText 'Setup.OptEnforce') (Get-WpeText 'Setup.OptEnforceHint') 62 ([bool]$s0.EnforceDuringSession)
$optLegacy = New-OptionCheck (Get-WpeText 'Setup.OptLegacy') (Get-WpeText 'Setup.OptLegacyHint') 124 ([bool]$s0.SetLegacyDefaultPrinterMode)
$optConnect = New-OptionCheck (Get-WpeText 'Setup.OptConnect') (Get-WpeText 'Setup.OptConnectHint') 186 ([bool]$s0.ConnectNetworkPrinters)
$optShortcut = New-OptionCheck (Get-WpeText 'Setup.OptShortcut' (Get-WpeText 'App.ShortcutName')) (Get-WpeText 'Setup.OptShortcutHint') 248
$lblEditor = New-WpeLabel (Get-WpeText 'Setup.EditorGroup') 0 316 700
$txtEditor = New-Object System.Windows.Forms.TextBox
$txtEditor.Location = New-Object System.Drawing.Point(20, 342)
$txtEditor.Size = New-Object System.Drawing.Size(300, 23)
$editorHint = New-WpeLabel (Get-WpeText 'Setup.EditorGroupHint') 330 342 400
$editorHint.ForeColor = [System.Drawing.Color]::DimGray
$pgOptions.Body.Controls.AddRange(@($lblEditor, $txtEditor, $editorHint))

# Signierung: vorhandene Codesignatur-Zertifikate (z. B. aus der Firmen-CA) anbieten
$prevSignThumb = if ($reg -and $reg.PSObject.Properties['SigningThumbprint']) { [string]$reg.SigningThumbprint } else { '' }
$prevSignCreated = [bool]($prevSignThumb -and $reg.PSObject.Properties['SigningCertCreated'] -and $reg.SigningCertCreated -eq 1)
$signChoices = @(
    @{ Kind = 'None'; Text = (Get-WpeText 'Setup.SignNone') }
    @{ Kind = 'Self'; Text = $(if ($prevSignCreated) { Get-WpeText 'Setup.SignSelfReuse' } else { Get-WpeText 'Setup.SignSelfNew' }) }
)
$signCerts = @(foreach ($store in 'Cert:\LocalMachine\My', 'Cert:\CurrentUser\My') {
        Get-ChildItem -Path $store -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) }
    }) | Sort-Object Thumbprint -Unique | Where-Object { -not ($prevSignCreated -and $_.Thumbprint -eq $prevSignThumb) }
foreach ($c in $signCerts) {
    $signChoices += @{ Kind = 'Cert'; Thumb = $c.Thumbprint; Text = (Get-WpeText 'Setup.SignCert' $c.Subject $c.Issuer $c.NotAfter) }
}
$lblSign = New-WpeLabel (Get-WpeText 'Setup.Sign') 0 384 700
$cboSign = New-Object System.Windows.Forms.ComboBox
$cboSign.DropDownStyle = 'DropDownList'
$cboSign.Location = New-Object System.Drawing.Point(20, 408)
$cboSign.Size = New-Object System.Drawing.Size(600, 23)
foreach ($s in $signChoices) { [void]$cboSign.Items.Add($s.Text) }
$cboSign.SelectedIndex = 0
if ($prevSignCreated) { $cboSign.SelectedIndex = 1 }
for ($i = 2; $i -lt $signChoices.Count; $i++) { if ($signChoices[$i].Thumb -eq $prevSignThumb) { $cboSign.SelectedIndex = $i } }
$signHint = New-WpeLabel (Get-WpeText 'Setup.SignHint') 20 436 720
$signHint.ForeColor = [System.Drawing.Color]::DimGray
$pgOptions.Body.Controls.AddRange(@($lblSign, $cboSign, $signHint))

# ---- Seite 5: Installation ----
$pgInstall = New-Page (Get-WpeText 'Setup.InstallTitle') (Get-WpeText 'Setup.InstallSubtitle')
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = 'Fill'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Dock = 'Bottom'
$progress.Height = 18
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 0
$pgInstall.Body.Controls.Add($txtLog)
$pgInstall.Body.Controls.Add($progress)
$txtLog.BringToFront()

# ---- Seite 6: Fertig ----
$pgDone = New-Page (Get-WpeText 'Setup.DoneTitle') (Get-WpeText 'Setup.DoneSubtitle')
$rtfDone = New-WpeRichText
$rtfDone.Dock = 'Fill'
$chkOpenAdmin = New-Object System.Windows.Forms.CheckBox
$chkOpenAdmin.Text = Get-WpeText 'Setup.OpenAdmin'
$chkOpenAdmin.Font = $script:WpeFontBold
$chkOpenAdmin.Checked = $true
$chkOpenAdmin.Dock = 'Bottom'
$chkOpenAdmin.Height = 30
$pgDone.Body.Controls.Add($rtfDone)
$pgDone.Body.Controls.Add($chkOpenAdmin)
$rtfDone.BringToFront()

$pages = @($pgWelcome, $pgConfig, $pgPrinters, $pgOptions, $pgInstall, $pgDone)
$script:Page = 0
$script:InstallState = 'NotStarted'   # NotStarted, Running, Done, Failed
$script:InstalledConfigPath = $null

function Show-Page {
    param([int]$Index)
    $script:Page = $Index
    for ($i = 0; $i -lt $pages.Count; $i++) {
        $pages[$i].Page.Visible = ($i -eq $Index)
        $stepLabels[$i].Font = if ($i -eq $Index) { New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold) } else { New-Object System.Drawing.Font('Segoe UI', 10) }
        $stepLabels[$i].ForeColor = if ($i -eq $Index) { [System.Drawing.Color]::White } elseif ($i -lt $Index) { [System.Drawing.Color]::FromArgb(170, 210, 245) } else { [System.Drawing.Color]::FromArgb(120, 160, 200) }
    }
    $btnBack.Enabled = ($Index -ge 1 -and $Index -le 3) -or ($Index -eq 4 -and $script:InstallState -in 'NotStarted', 'Failed')
    $btnCancel.Enabled = ($Index -lt 5) -and $script:InstallState -ne 'Running'
    $btnNext.Enabled = $script:InstallState -ne 'Running'
    $btnNext.Text = switch ($Index) {
        4 { if ($script:InstallState -eq 'Done') { Get-WpeText 'Setup.Next' } else { Get-WpeText 'Setup.Install' } }
        5 { Get-WpeText 'Setup.Finish' }
        default { Get-WpeText 'Setup.Next' }
    }
    if ($Index -eq 2 -and $picker.List.Items.Count -eq 0 -and $picker.Server.Text) { Import-WpePickerPrinters -Picker $picker }
    if ($Index -eq 4 -and $script:InstallState -eq 'NotStarted') { $txtLog.Text = (Get-Summary) -join "`r`n" }
}

function Get-Summary {
    $sel = @(Get-WpePickerSelection -Picker $picker)
    $noDrv = @($sel | Where-Object { $_.DriverInstalled -eq $false }).Count
    $drvText = ''
    if ($noDrv) {
        $drvText = if ($picker.InstallDrivers.Checked) { Get-WpeText 'Setup.SumNoDriverInstall' $noDrv } else { Get-WpeText 'Setup.SumNoDriver' $noDrv }
    }
    $yesNo = { param([bool]$Value) if ($Value) { Get-WpeText 'Common.Yes' } else { Get-WpeText 'Common.No' } }
    # Spaltenbreite der Zusammenfassung nach der längsten Bezeichnung
    $rows = [ordered]@{
        (Get-WpeText 'Setup.SumConfig')     = Get-ChosenConfigPath
        (Get-WpeText 'Setup.SumServer')     = $(if ($picker.LoadedServer) { $picker.LoadedServer } else { Get-WpeText 'Setup.SumNone' })
        (Get-WpeText 'Setup.SumPrinters')   = (Get-WpeText 'Setup.SumPrinterCount' $sel.Count) + $drvText
        (Get-WpeText 'Setup.SumPolicy')     = $(if ($optPolicy.Checked) { Get-WpeText 'Setup.SumSet' } else { Get-WpeText 'Setup.SumUnchanged' })
        (Get-WpeText 'Setup.SumEnforce')    = & $yesNo $optEnforce.Checked
        (Get-WpeText 'Setup.SumLegacy')     = $(if ($optLegacy.Checked) { Get-WpeText 'Setup.SumTurnOff' } else { Get-WpeText 'Setup.SumUnchanged' })
        (Get-WpeText 'Setup.SumConnect')    = & $yesNo $optConnect.Checked
        (Get-WpeText 'Setup.SumShortcut')   = $(if ($optShortcut.Checked) { Get-WpeText 'Setup.SumWindowsTools' } else { Get-WpeText 'Common.No' })
        (Get-WpeText 'Setup.SumEditor')     = $(if ($txtEditor.Text.Trim()) { $txtEditor.Text.Trim() } else { '-' })
        (Get-WpeText 'Setup.SumSigning')    = $cboSign.Text
        (Get-WpeText 'Setup.SumLanguage')   = (Get-WpeSupportedLanguage)[$Language]
    }
    $width = ($rows.Keys | Measure-Object -Property Length -Maximum).Maximum
    $title = Get-WpeText 'Setup.SumTitle'
    @($title, ('=' * $title.Length), '')
    foreach ($k in $rows.Keys) { '{0} : {1}' -f $k.PadRight($width), $rows[$k] }
    ''
    Get-WpeText 'Setup.SumInstallDir' (Join-Path $env:ProgramFiles 'WePrintEasy')
}

function Start-Installation {
    $cfgPath = Get-ChosenConfigPath
    $sel = @(Get-WpePickerSelection -Picker $picker)
    $params = @{ ConfigPath = $cfgPath; Language = $Language }
    if ($picker.LoadedServer) {
        $listFile = Join-Path ([IO.Path]::GetTempPath()) 'WePrintEasy-Druckerliste.txt'
        [IO.File]::WriteAllLines($listFile, [string[]]@($sel | ForEach-Object { $_.Path }), (New-Object System.Text.UTF8Encoding($false)))
        $params.PrintServer = $picker.LoadedServer
        $params.PrinterListFile = $listFile
        if ($picker.InstallDrivers.Checked) { $params.InstallMissingDrivers = $true }
    }
    if ($optPolicy.Checked) { $params.DisableClientDefaultPrinter = $true }
    if (-not $optShortcut.Checked) { $params.NoShortcut = $true }
    if ($txtEditor.Text.Trim() -and -not $cfgPath.StartsWith('\\')) { $params.EditorGroup = $txtEditor.Text.Trim() }
    $sign = $signChoices[$cboSign.SelectedIndex]
    switch ($sign.Kind) {
        'None' { $params.NoSigning = $true }
        'Self' { $params.SelfSignedCertificate = $true }
        'Cert' { $params.SigningCertificateThumbprint = $sign.Thumb }
    }

    $txtLog.Text = ''
    $script:InstallState = 'Running'
    $script:InstalledConfigPath = $cfgPath
    $progress.MarqueeAnimationSpeed = 30
    Show-Page 4

    # Installer in eigenem Runspace ausführen, damit das Fenster reagiert
    $script:InstallPs = [PowerShell]::Create()
    [void]$script:InstallPs.AddCommand((Join-Path $PSScriptRoot 'Install-WePrintEasy.ps1')).AddParameters($params)
    $script:InstallHandle = $script:InstallPs.BeginInvoke()
    $script:InfoIndex = 0
    $script:InstallTimer.Start()
}

function Receive-InstallOutput {
    $ps = $script:InstallPs
    $info = $ps.Streams.Information
    $sb = New-Object System.Text.StringBuilder
    while ($script:InfoIndex -lt $info.Count) {
        $rec = $info[$script:InfoIndex]
        $script:InfoIndex++
        $data = $rec.MessageData
        if ($data -is [System.Management.Automation.HostInformationMessage]) {
            [void]$sb.Append($data.Message)
            if (-not $data.NoNewLine) { [void]$sb.Append("`r`n") }
        } else {
            [void]$sb.Append([string]$data).Append("`r`n")
        }
    }
    if ($sb.Length) { $txtLog.AppendText($sb.ToString()) }
}

$script:InstallTimer = New-Object System.Windows.Forms.Timer
$script:InstallTimer.Interval = 300
$script:InstallTimer.Add_Tick({
        Receive-InstallOutput
        if (-not $script:InstallHandle.IsCompleted) { return }
        $script:InstallTimer.Stop()
        $failed = $false
        try {
            [void]$script:InstallPs.EndInvoke($script:InstallHandle)
        } catch {
            $failed = $true
            $txtLog.AppendText("`r`n" + (Get-WpeText 'Setup.Error' "$($_.Exception.InnerException.Message)$($_.Exception.Message)") + "`r`n")
        }
        Receive-InstallOutput
        foreach ($e in $script:InstallPs.Streams.Error) { $failed = $true; $txtLog.AppendText((Get-WpeText 'Setup.Error' $e) + "`r`n") }
        $script:InstallPs.Dispose()

        if (-not $failed) {
            try {
                # Optionen, die die Konfiguration betreffen
                $cfg = Read-WpeConfig -Path $script:InstalledConfigPath
                $cfg.Settings.EnforceDuringSession = $optEnforce.Checked
                $cfg.Settings.SetLegacyDefaultPrinterMode = $optLegacy.Checked
                $cfg.Settings.ConnectNetworkPrinters = $optConnect.Checked
                $cfg.Settings.Language = $Language
                if ($picker.LoadedServer) { $cfg.Settings.DefaultPrintServer = $picker.LoadedServer }
                Save-WpeConfig -Config $cfg -Path $script:InstalledConfigPath -Confirm:$false
                $txtLog.AppendText((Get-WpeText 'Setup.SettingsSaved' $cfg.Printers.Count) + "`r`n")
            } catch {
                $failed = $true
                $txtLog.AppendText((Get-WpeText 'Setup.SettingsFailed' $_.Exception.Message) + "`r`n")
            }
        }
        $progress.MarqueeAnimationSpeed = 0
        $progress.Style = 'Continuous'
        $progress.Value = if ($failed) { 0 } else { 100 }
        $script:InstallState = if ($failed) { 'Failed' } else { 'Done' }
        if ($failed) {
            $txtLog.AppendText("`r`n" + (Get-WpeText 'Setup.InstallFailed') + "`r`n")
        } else {
            $txtLog.AppendText("`r`n" + (Get-WpeText 'Setup.InstallDone') + "`r`n")
        }
        Show-Page 4
    })

function Complete-Setup {
    if ($chkOpenAdmin.Checked -and -not $script:WpeScreenshotDir) {
        $admin = Join-Path $env:ProgramFiles 'WePrintEasy\WePrintEasy-Admin.ps1'
        # Nicht "Start-Process -WindowStyle Hidden": das verbirgt auch das Fenster der Verwaltung
        $launch = Get-WpeHiddenLaunch "-NoProfile -ExecutionPolicy $(Get-WpeExecutionPolicy -Path $admin) -STA -WindowStyle Hidden -File `"$admin`""
        Start-Process -FilePath $launch.FilePath -ArgumentList $launch.Arguments
    }
    $form.Close()
}

$btnNext.Add_Click({
        switch ($script:Page) {
            1 { if (-not (Test-ChosenConfigPath)) { return } }
            2 {
                if (-not $picker.LoadedServer) {
                    if (-not (Confirm-WpeAction (Get-WpeText 'Setup.NoPrintersLoaded'))) { return }
                } elseif ($picker.List.CheckedItems.Count -eq 0) {
                    if (-not (Confirm-WpeAction (Get-WpeText 'Setup.NoPrinterSelected'))) { return }
                }
            }
            4 {
                if ($script:InstallState -ne 'Done') { Start-Installation; return }
            }
            5 { Complete-Setup; return }
        }
        Show-Page ($script:Page + 1)
    })
$btnBack.Add_Click({ if ($script:Page -eq 4) { $script:InstallState = 'NotStarted' }; Show-Page ($script:Page - 1) })
$btnCancel.Add_Click({ if (Confirm-WpeAction (Get-WpeText 'Setup.CancelConfirm')) { $form.Close() } })

Add-WpeRichText $rtfDone (@(Get-WpeText 'Setup.DoneText' (Get-WpeText 'App.ShortcutName')) + @('') + (Get-WpeGuideLines -Section User))

# --- Test-/Dokumentationsmodus ---------------------------------------------------
function Invoke-ScreenshotRun {
    $form.TopMost = $true
    $shots = @(
        @{ Page = 0; Name = 'setup-1-willkommen' }
        @{ Page = 1; Name = 'setup-2-konfiguration' }
        @{ Page = 2; Name = 'setup-3-drucker' }
        @{ Page = 3; Name = 'setup-4-optionen' }
        @{ Page = 4; Name = 'setup-5-zusammenfassung' }
    )
    foreach ($s in $shots) {
        try {
            Show-Page $s.Page
            if ($s.Page -eq 1) { [void](Test-ChosenConfigPath) }
            Save-WpeScreenshot $form $s.Name
        } catch { Write-WpeTestLog "ERROR $($s.Name): $($_.Exception.Message)" }
    }
    try {
        Start-Installation
        $deadline = (Get-Date).AddMinutes(10)
        while ($script:InstallState -eq 'Running' -and (Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        Write-WpeTestLog "INSTALLSTATE $($script:InstallState)"
        Add-Content -LiteralPath (Join-Path $script:WpeScreenshotDir 'setup-install.log') -Value $txtLog.Text -Encoding UTF8
        Save-WpeScreenshot $form 'setup-6-installation'
        Show-Page 5
        Save-WpeScreenshot $form 'setup-7-fertig'
    } catch { Write-WpeTestLog "ERROR install: $($_.Exception.Message) $($_.ScriptStackTrace)" }
    $form.Close()
}

$form.Add_Shown({
        Show-Page 0
        $form.Activate()
        if ($script:WpeScreenshotDir) { Invoke-ScreenshotRun }
    })
[void]$form.ShowDialog()
$form.Dispose()
