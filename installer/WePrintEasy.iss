; WePrintEasy - Windows-Installer (Inno Setup 6)
;
; Bauen:  powershell -File .\tools\Build-Installer.ps1   ->  dist\WePrintEasy-Setup-<Version>.exe
;
; Ablauf:
;   - Neuinstallation: kopiert das Installationspaket nach "<Programmordner>\Setup" und startet
;     den Setup-Assistenten (Setup-WePrintEasy.ps1) in der Sprache des Installers.
;   - Vorhandene Installation (auch aus dem ZIP): Update mit allen bisherigen Einstellungen
;     (Update-WePrintEasy.ps1); optional anschliessend der Setup-Assistent.
;   - Deinstallation ueber "Apps" / "Programme und Features" (Uninstall-WePrintEasy.ps1).
;
; Unbeaufsichtigt:
;   WePrintEasy-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART [/LANG=de]
;       [/INSTALLARGS="-PrintServer fs01 -DisableClientDefaultPrinter"]
;   Neuinstallation: Install-WePrintEasy.ps1 mit den Parametern aus /INSTALLARGS; Update: wie oben.
;   Sprache: Die Auswahl beim Start gilt auch fuer WePrintEasy (bei einem Update wie in der Verwaltung
;   unter "Einstellungen"). Unbeaufsichtigt nur mit /LANG=, sonst bleibt die bisherige Sprache.
;   Rueckgabewert 0 = erfolgreich, 10 = Einrichtung/Update fehlgeschlagen (Protokoll: Setup\WePrintEasy-Setup.log).
;   unins000.exe /VERYSILENT [/REMOVECONFIG]  - /REMOVECONFIG loescht auch die lokale Konfiguration.
;   Microsoft Store (Pakettyp EXE): Silent-Parameter "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART".
;   Rueckgabewerte: 0 = erfolgreich, 10 = Einrichtung/Update fehlgeschlagen, 1-8 = Inno Setup
;   (u. a. 2/5 = abgebrochen, 3/4 = schwerer Fehler, 8 = Neustart noetig).
;
; Ein neues Setup ersetzt die alte Version: gleiche AppId, Programmordner aus der Registry
; (InstallPath), offene Druckerverwaltungen werden vorher geschlossen (CloseAdminConsoles).
; Die Update-Pruefung der Verwaltung (latest.json) startet dieses Setup mit /LANG=<Sprache>.

#ifndef RepoRoot
  #define RepoRoot AddBackslash(SourcePath) + ".."
#endif
; Version aus $script:WpeVersion = '1.0.3' in src\WePrintEasy.psm1 (auch beim Kompilieren direkt in Inno Setup)
#ifndef AppVersion
  #define AppVersion ""
  #define VersionLine ""
  #define ModuleFile FileOpen(RepoRoot + "\src\WePrintEasy.psm1")
  #if !ModuleFile
    #error src\WePrintEasy.psm1 nicht gefunden
  #endif
  ; In einem #sub wirkt nur #expr-Zuweisung auf die aeusseren Variablen, nicht #define
  #sub ReadVersionLine
    #expr VersionLine = FileRead(ModuleFile)
    #if Pos("$script:WpeVersion", VersionLine) == 1
      #expr VersionLine = Copy(VersionLine, Pos("'", VersionLine) + 1, 100)
      #expr AppVersion = Copy(VersionLine, 1, Pos("'", VersionLine) - 1)
    #endif
  #endsub
  #for {0; AppVersion == "" && !FileEof(ModuleFile); 0} ReadVersionLine
  #expr FileClose(ModuleFile)
  #if AppVersion == ""
    #error $script:WpeVersion in src\WePrintEasy.psm1 nicht gefunden
  #endif
#endif
#ifndef OutputDir
  #define OutputDir RepoRoot + "\dist"
#endif

; Muss mit $uninstallKey in Uninstall-WePrintEasy.ps1 uebereinstimmen
#define AppId "62BED98D-291F-401A-A240-5C8EC56F56F3"

[Setup]
AppId={{{#AppId}}
AppName=WePrintEasy
AppVersion={#AppVersion}
AppVerName=WePrintEasy {#AppVersion}
AppPublisher=Leon-Elias Martin
AppPublisherURL=https://weprinteasy.com
AppSupportURL=https://github.com/LeonMTN05/WePrintEasy/issues
AppUpdatesURL=https://weprinteasy.com
AppCopyright=Copyright (c) 2026 Leon-Elias Martin - MIT License
VersionInfoVersion={#AppVersion}
VersionInfoProductName=WePrintEasy
VersionInfoDescription=WePrintEasy Setup
DefaultDirName={code:GetDefaultDir}
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows Server 2016 / Windows 10
MinVersion=10.0.14393
LicenseFile={#RepoRoot}\LICENSE
SetupIconFile={#RepoRoot}\src\WePrintEasy.ico
UninstallDisplayIcon={app}\Setup\src\WePrintEasy.ico
UninstallDisplayName=WePrintEasy
WizardStyle=modern
#ifdef WizardImages
WizardImageFile={#WizardImages}\wizard-100.bmp,{#WizardImages}\wizard-125.bmp,{#WizardImages}\wizard-150.bmp
WizardSmallImageFile={#WizardImages}\small-100.bmp,{#WizardImages}\small-125.bmp,{#WizardImages}\small-150.bmp
#endif
; Sprachauswahl beim Start immer anzeigen; vorausgewaehlt: Sprache der letzten Installation per .exe, sonst die von Windows
ShowLanguageDialog=yes
UsePreviousLanguage=yes
LanguageDetectionMethod=uilanguage
; Laufende Agenten nutzen die Dateien im Programmordner, nicht die im Setup-Ordner
CloseApplications=no
RestartApplications=no
SetupLogging=yes
OutputDir={#OutputDir}
OutputBaseFilename=WePrintEasy-Setup-{#AppVersion}
; Nur wenige MB - ohne Kompression startet das Setup sofort
Compression=none

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
en.TaskReconfigure=Run the setup assistant after the update (configuration storage, printers, options)
de.TaskReconfigure=Nach dem Update den Setup-Assistenten ausführen (Speicherort, Drucker, Optionen)
en.ReadyNew=New installation of WePrintEasy %1%n%nAfter the files have been copied, the setup assistant starts:%n    configuration storage, printers from the print server, options
de.ReadyNew=Neuinstallation von WePrintEasy %1%n%nNach dem Kopieren der Dateien startet der Setup-Assistent:%n    Speicherort der Konfiguration, Drucker vom Druckserver, Optionen
en.ReadyUpdate=Update of the existing installation: %1 -> %2%nProgram folder: %3%nLanguage of WePrintEasy: %4%n%nAll other settings are kept:%n    configuration, assignments and printer list%n    signing, policy and shortcut
de.ReadyUpdate=Update der vorhandenen Installation: %1 -> %2%nProgrammordner: %3%nSprache von WePrintEasy: %4%n%nAlle anderen Einstellungen bleiben erhalten:%n    Konfiguration, Zuweisungen und Druckerliste%n    Signierung, Richtlinie und Verknüpfung
en.ReadyAgents=Agents already running in user sessions are restarted%nwith the new version.
de.ReadyAgents=Bereits laufende Agenten in Benutzersitzungen werden mit der%nneuen Version neu gestartet.
en.Downgrade=The installed version %1 is newer than this setup (%2).%n%nInstall the older version anyway?
de.Downgrade=Die installierte Version %1 ist neuer als dieses Setup (%2).%n%nTrotzdem die ältere Version installieren?
en.LanguageName=English
de.LanguageName=Deutsch
en.VersionUnknown=unknown version
de.VersionUnknown=unbekannte Version
en.StatusUpdate=Updating the existing installation ...
de.StatusUpdate=Vorhandene Installation wird aktualisiert ...
en.StatusWizard=Setup assistant is running - please complete it in its own window ...
de.StatusWizard=Der Setup-Assistent läuft - bitte im eigenen Fenster abschließen ...
en.StatusInstall=Installing WePrintEasy ...
de.StatusInstall=WePrintEasy wird eingerichtet ...
en.DoneUpdate=WePrintEasy has been updated to version %1. All settings have been kept, the language is %2.%n%nThe administration is available under Windows Tools.
de.DoneUpdate=WePrintEasy wurde auf Version %1 aktualisiert. Alle Einstellungen wurden übernommen, die Sprache ist %2.%n%nDie Verwaltung finden Sie unter Windows-Tools.
en.DoneNew=WePrintEasy %1 is installed and set up.%n%nThe administration is available under Windows Tools.
de.DoneNew=WePrintEasy %1 ist installiert und eingerichtet.%n%nDie Verwaltung finden Sie unter Windows-Tools.
en.DoneIncomplete=The setup assistant was closed before the installation was completed - WePrintEasy is not set up yet.%n%nRun this setup again to start the setup assistant.
de.DoneIncomplete=Der Setup-Assistent wurde vor Abschluss der Installation beendet - WePrintEasy ist noch nicht eingerichtet.%n%nFühren Sie dieses Setup erneut aus, um den Setup-Assistenten zu starten.
en.DoneFailed=The installation could not be completed.%n%nDetails are in the log:%n%1
de.DoneFailed=Die Installation konnte nicht abgeschlossen werden.%n%nDetails stehen im Protokoll:%n%1
en.OpenAdmin=Open WePrintEasy administration
de.OpenAdmin=WePrintEasy-Verwaltung öffnen
en.ShowLog=Show log
de.ShowLog=Protokoll anzeigen
en.PowerShellFailed=Windows PowerShell could not be started:%n%1
de.PowerShellFailed=Windows PowerShell konnte nicht gestartet werden:%n%1
en.UninstallRemoveConfig=Also delete the configuration (assignments, printer list, settings)?%n%nOnly a local configuration in C:\ProgramData\WePrintEasy is deleted, a central configuration on a file share is always kept.%nChoose "No" if you want to reinstall WePrintEasy later.
de.UninstallRemoveConfig=Auch die Konfiguration löschen (Zuweisungen, Druckerliste, Einstellungen)?%n%nGelöscht wird nur eine lokale Konfiguration in C:\ProgramData\WePrintEasy, eine zentrale Konfiguration auf einer Freigabe bleibt immer erhalten.%nWählen Sie "Nein", wenn Sie WePrintEasy später wieder installieren möchten.
en.UninstallFailed=Removing WePrintEasy reported an error. Details are in the log:%n%1
de.UninstallFailed=Beim Entfernen von WePrintEasy ist ein Fehler aufgetreten. Details stehen im Protokoll:%n%1

[InstallDelete]
; Installationspaket der Vorversion vollstaendig ersetzen (entfernte Dateien nicht liegen lassen)
Type: filesandordirs; Name: "{app}\Setup"

[Files]
Source: "{#RepoRoot}\Setup.cmd"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\Setup-WePrintEasy.ps1"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\Install-WePrintEasy.ps1"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\Update-WePrintEasy.ps1"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\Uninstall-WePrintEasy.ps1"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\README.md"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\README.de.md"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\LICENSE"; DestDir: "{app}\Setup"; Flags: ignoreversion
Source: "{#RepoRoot}\src\*"; DestDir: "{app}\Setup\src"; Flags: ignoreversion recursesubdirs
Source: "{#RepoRoot}\examples\*"; DestDir: "{app}\Setup\examples"; Flags: ignoreversion recursesubdirs

[Tasks]
Name: "reconfigure"; Description: "{cm:TaskReconfigure}"; Flags: unchecked; Check: WasInstalled

[Run]
Filename: "{code:GetAdminFile}"; Parameters: "{code:GetAdminParams}"; Description: "{cm:OpenAdmin}"; Flags: postinstall nowait skipifsilent; Check: ShowOpenAdmin
Filename: "{win}\notepad.exe"; Parameters: """{app}\Setup\WePrintEasy-Setup.log"""; Description: "{cm:ShowLog}"; Flags: postinstall nowait skipifsilent unchecked; Check: ShowLogFile

[UninstallDelete]
; Vom PowerShell-Installer angelegte Dateien (signierte Kopien, WePrintEasy-Admin.cmd, Protokolle)
Type: filesandordirs; Name: "{app}"

[Code]
const
  RegKey = 'SOFTWARE\WePrintEasy';
  ExitCodeFailed = 10;

var
  InstalledBefore: Boolean;
  InstalledVersion: String;
  Outcome: String;   { '', 'Updated', 'Installed', 'Incomplete', 'Failed' }

function GetRegInstallPath: String;
begin
  if not RegQueryStringValue(HKLM, RegKey, 'InstallPath', Result) then Result := '';
end;

{ Installiert = Registry-Eintrag und Agent im Programmordner (wie Update-WePrintEasy.ps1) }
function IsProductInstalled: Boolean;
var
  Path: String;
begin
  Path := GetRegInstallPath;
  Result := (Path <> '') and FileExists(AddBackslash(Path) + 'WePrintEasy-Agent.ps1');
end;

function GetDefaultDir(Param: String): String;
begin
  Result := GetRegInstallPath;
  if Result = '' then Result := ExpandConstant('{commonpf}\WePrintEasy');
end;

function GetProductDir(Param: String): String;
begin
  Result := GetDefaultDir('');
end;

{ Version aus $script:WpeVersion = '1.0.3' im installierten Modul }
function ReadInstalledVersion: String;
var
  Text: AnsiString;
  S: String;
  P: Integer;
begin
  Result := '';
  if not LoadStringFromFile(AddBackslash(GetRegInstallPath) + 'WePrintEasy.psm1', Text) then Exit;
  S := String(Text);
  P := Pos('$script:WpeVersion', S);
  if P = 0 then Exit;
  Delete(S, 1, P);
  P := Pos('''', S);
  if P = 0 then Exit;
  Delete(S, 1, P);
  P := Pos('''', S);
  if (P > 1) and (P < 40) then Result := Copy(S, 1, P - 1);
end;

function WasInstalled: Boolean;
begin
  Result := InstalledBefore;
end;

function ShowOpenAdmin: Boolean;
begin
  Result := (Outcome = 'Updated') and FileExists(AddBackslash(GetProductDir('')) + 'WePrintEasy-Admin.ps1');
end;

function LogFile: String;
begin
  Result := ExpandConstant('{app}\Setup\WePrintEasy-Setup.log');
end;

function ShowLogFile: Boolean;
begin
  Result := (Outcome = 'Failed') and FileExists(LogFile);
end;

function PowerShellExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

{ Offene Druckerverwaltungen (alle Sitzungen) schliessen: erst "Schliessen" ans Fenster, nach 5 s beenden.
  Die Anmelde-Agenten der Benutzer laufen weiter (sie nutzen die neue Version ab der naechsten Anmeldung). }
procedure CloseAdminConsoles;
var
  ResultCode: Integer;
  Cmd: String;
begin
  { Ohne diesen Prozess selbst - seine Befehlszeile enthaelt den Suchbegriff ebenfalls }
  Cmd := '$p = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.Name -in ''powershell.exe'', ''pwsh.exe'' -and $_.CommandLine -like ''*WePrintEasy-Admin.ps1*'' }); ' +
    'if (-not $p) { exit 0 }; ' +
    'foreach ($x in $p) { try { [void](Get-Process -Id $x.ProcessId -ErrorAction Stop).CloseMainWindow() } catch {} }; ' +
    'for ($i = 0; $i -lt 10 -and @($p | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }).Count; $i++) { Start-Sleep -Milliseconds 500 }; ' +
    'foreach ($x in $p) { Stop-Process -Id $x.ProcessId -Force -ErrorAction SilentlyContinue }; exit $p.Count';
  Log('Closing open printer management windows');
  if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + Cmd + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log(Format('Printer management windows closed: %d', [ResultCode]));
end;

function HasSwitch(const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Name) = 0 then Result := True;
end;

function RunPowerShell(const Params: String; ShowCmd: Integer; var ResultCode: Integer): Boolean;
begin
  Log('powershell.exe ' + Params);
  Result := Exec(PowerShellExe, Params, ExpandConstant('{app}\Setup'), ShowCmd, ewWaitUntilTerminated, ResultCode);
  if Result then
    Log(Format('Exit code: %d', [ResultCode]))
  else
    Log('Start failed: ' + SysErrorMessage(ResultCode));
end;

{ Skript unsichtbar ausfuehren, alle Ausgaben (auch Write-Host) ins Protokoll.
  UsesExit: das Skript meldet Erfolg ueber "exit <Code>", sonst gilt: keine Ausnahme = Erfolg }
function RunScriptLogged(const Script, Args: String; UsesExit: Boolean): Boolean;
var
  Cmd, Done: String;
  ResultCode: Integer;
begin
  if UsesExit then Done := 'exit $LASTEXITCODE' else Done := 'exit 0';
  Cmd := Format('try { & ''%s'' %s *> ''%s''; %s } catch { ($_ | Out-String) | Out-File -LiteralPath ''%s'' -Append; exit 1 }', [
    ExpandConstant('{app}\Setup\') + Script, Args, LogFile, Done, LogFile]);
  Result := RunPowerShell('-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + Cmd + '"', SW_HIDE, ResultCode)
    and (ResultCode = 0);
end;

procedure SetStatus(const Text: String);
begin
  WizardForm.StatusLabel.Caption := Text;
  WizardForm.FilenameLabel.Caption := '';
  WizardForm.ProgressGauge.Style := npbstMarquee;
end;

function HasLangParam: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(Copy(ParamStr(I), 1, 6), '/LANG=') = 0 then Result := True;
end;

{ Gewaehlte Sprache auch fuer WePrintEasy uebernehmen - unbeaufsichtigt nur mit ausdruecklichem /LANG=,
  sonst wuerde die automatisch erkannte Windows-Sprache die bisherige ersetzen }
function ApplyLanguage: Boolean;
begin
  Result := not WizardSilent or HasLangParam;
end;

procedure RunUpdate;
var
  Args: String;
begin
  SetStatus(CustomMessage('StatusUpdate'));
  Args := '-NoPause';
  if ApplyLanguage then Args := Args + ' -Language ' + ActiveLanguage;
  if RunScriptLogged('Update-WePrintEasy.ps1', Args, True) then Outcome := 'Updated' else Outcome := 'Failed';
end;

procedure RunSilentInstall;
begin
  SetStatus(CustomMessage('StatusInstall'));
  if RunScriptLogged('Install-WePrintEasy.ps1', '-Language ' + ActiveLanguage + ' ' + ExpandConstant('{param:INSTALLARGS}'), False)
      and IsProductInstalled then
    Outcome := 'Installed'
  else
    Outcome := 'Failed';
end;

{ Fenster ohne Konsole: Mit SW_HIDE gestartet bliebe auch das Fenster selbst unsichtbar, und
  "-WindowStyle Hidden" laesst bei Windows Terminal als Standardkonsole ein leeres Fenster offen.
  conhost --headless (ab Build 20348) verbirgt nur die Konsole; aeltere Versionen: Konsole blitzt kurz auf.
  Wie Get-WpeHiddenLaunch in src\WePrintEasy.psm1 }
function UseHeadlessConhost: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := (Version.Build >= 20348) and FileExists(ExpandConstant('{sys}\conhost.exe'));
end;

function GuiLaunchFile: String;
begin
  if UseHeadlessConhost then Result := ExpandConstant('{sys}\conhost.exe') else Result := PowerShellExe;
end;

function GuiLaunchParams(const Params: String): String;
begin
  Result := '-WindowStyle Hidden ' + Params;
  if UseHeadlessConhost then Result := '--headless "' + PowerShellExe + '" ' + Result;
end;

function RunPowerShellGui(const Params: String; var ResultCode: Integer): Boolean;
begin
  Log(GuiLaunchFile + ' ' + GuiLaunchParams(Params));
  Result := Exec(GuiLaunchFile, GuiLaunchParams(Params), ExpandConstant('{app}\Setup'), SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode);
end;

{ Verwaltung nach dem Update oeffnen, mit der ExecutionPolicy der Installation }
function GetAdminFile(Param: String): String;
begin
  Result := GuiLaunchFile;
end;

function GetAdminParams(Param: String): String;
var
  Policy: String;
begin
  if not RegQueryStringValue(HKLM, RegKey, 'ExecutionPolicy', Policy) or (Policy <> 'AllSigned') then Policy := 'Bypass';
  Result := GuiLaunchParams('-NoProfile -ExecutionPolicy ' + Policy + ' -STA -File "' + AddBackslash(GetProductDir('')) + 'WePrintEasy-Admin.ps1"');
end;

procedure RunWizard;
var
  ResultCode: Integer;
begin
  SetStatus(CustomMessage('StatusWizard'));
  { Der Assistent fragt die Sprache nicht erneut ab; er laeuft mit den Rechten dieses Setups }
  if not RunPowerShellGui('-NoProfile -ExecutionPolicy Bypass -STA -File "' + ExpandConstant('{app}\Setup\Setup-WePrintEasy.ps1') +
      '" -Language ' + ActiveLanguage, ResultCode) then begin
    SaveStringToFile(LogFile, FmtMessage(CustomMessage('PowerShellFailed'), [SysErrorMessage(ResultCode)]), False);
    Outcome := 'Failed';
  end else if Outcome <> 'Updated' then begin
    { Nach einem Update ist das Ergebnis schon gesetzt; der Assistent hat dann nur Einstellungen geaendert }
    if IsProductInstalled then Outcome := 'Installed' else Outcome := 'Incomplete';
  end;
end;

{ Installierte Version neuer als dieses Setup? }
function IsDowngrade: Boolean;
var
  Installed, Own: Int64;
begin
  Result := StrToVersion(InstalledVersion, Installed) and StrToVersion('{#AppVersion}', Own) and
    (ComparePackedVersion(Installed, Own) > 0);
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  InstalledBefore := IsProductInstalled;
  if not InstalledBefore then Exit;
  InstalledVersion := ReadInstalledVersion;
  if IsDowngrade then begin
    Log(Format('Installed version %s is newer than %s', [InstalledVersion, '{#AppVersion}']));
    { Unbeaufsichtigt nie herabstufen; sonst nachfragen (Vorgabe: Nein) }
    Result := not WizardSilent and (MsgBox(FmtMessage(CustomMessage('Downgrade'), [InstalledVersion, '{#AppVersion}']),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES);
  end;
  if InstalledVersion = '' then InstalledVersion := CustomMessage('VersionUnknown');
end;

{ Vor dem Kopieren: eine laufende Druckerverwaltung schliessen, damit sie nicht mit der alten Version weiterlaeuft }
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if InstalledBefore then CloseAdminConsoles;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if InstalledBefore then begin
    Result := FmtMessage(CustomMessage('ReadyUpdate'), [InstalledVersion, '{#AppVersion}', GetProductDir(''), CustomMessage('LanguageName')]) + NewLine + NewLine +
      CustomMessage('ReadyAgents');
    if MemoTasksInfo <> '' then Result := Result + NewLine + NewLine + MemoTasksInfo;
  end else
    Result := FmtMessage(CustomMessage('ReadyNew'), ['{#AppVersion}']);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then Exit;
  if InstalledBefore then begin
    RunUpdate;
    if (Outcome = 'Updated') and not WizardSilent and WizardIsTaskSelected('reconfigure') then RunWizard;
  end else if WizardSilent then
    RunSilentInstall
  else
    RunWizard;
  WizardForm.ProgressGauge.Style := npbstNormal;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID <> wpFinished then Exit;
  if Outcome = 'Updated' then
    WizardForm.FinishedLabel.Caption := FmtMessage(CustomMessage('DoneUpdate'), ['{#AppVersion}', CustomMessage('LanguageName')])
  else if Outcome = 'Installed' then
    WizardForm.FinishedLabel.Caption := FmtMessage(CustomMessage('DoneNew'), ['{#AppVersion}'])
  else if Outcome = 'Incomplete' then
    WizardForm.FinishedLabel.Caption := CustomMessage('DoneIncomplete')
  else if Outcome = 'Failed' then
    WizardForm.FinishedLabel.Caption := FmtMessage(CustomMessage('DoneFailed'), [LogFile]);
end;

function GetCustomSetupExitCode: Integer;
begin
  if (Outcome = 'Failed') or (Outcome = 'Incomplete') then Result := ExitCodeFailed else Result := 0;
end;

{ --- Deinstallation --- }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Params, UninstallLog: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  UninstallLog := ExpandConstant('{%TEMP}\WePrintEasy-Uninstall.log');
  { Den Programmordner entfernt anschliessend die Deinstallation selbst ([UninstallDelete]) }
  Params := '-KeepInstallFolder';
  if HasSwitch('/REMOVECONFIG') or (not UninstallSilent and
      (MsgBox(CustomMessage('UninstallRemoveConfig'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES)) then
    Params := Params + ' -RemoveConfig';
  CloseAdminConsoles;
  Params := Format('-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try { & ''%s'' %s *> ''%s''; exit 0 } catch { ($_ | Out-String) | Out-File -LiteralPath ''%s'' -Append; exit 1 }"', [
    ExpandConstant('{app}\Setup\Uninstall-WePrintEasy.ps1'), Params, UninstallLog, UninstallLog]);
  Log('powershell.exe ' + Params);
  if not Exec(PowerShellExe, Params, ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then begin
    Log(Format('Uninstall script failed: %d', [ResultCode]));
    if not UninstallSilent then MsgBox(FmtMessage(CustomMessage('UninstallFailed'), [UninstallLog]), mbError, MB_OK);
  end;
end;
