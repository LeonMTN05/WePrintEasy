<div align="center">

<img src="docs/weprinteasy-icon.png" alt="WePrintEasy" width="120">

# WePrintEasy

**A fixed default printer per AD user and group on your terminal server.**<br>
Set at every logon – and, if you like, kept in place for the entire session.

[![Tests](https://github.com/LeonMTN05/WePrintEasy/actions/workflows/tests.yml/badge.svg)](https://github.com/LeonMTN05/WePrintEasy/actions/workflows/tests.yml)
[![Version](https://img.shields.io/badge/Version-1.0.9-00468C)](https://github.com/LeonMTN05/WePrintEasy)
[![License: MIT](https://img.shields.io/badge/License-MIT-F0A500)](LICENSE)
<br>
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%20%7C%202022%20%7C%202025-0078D4)](#-requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](#-requirements)
[![Dependencies](https://img.shields.io/badge/Dependencies-none-2EA043)](#-requirements)
[![Languages](https://img.shields.io/badge/Languages-English%20%7C%20Deutsch-555555)](#-language)

**English** · [Deutsch](README.de.md)

[**Quick start**](#-quick-start) · [Features](#-features) · [Screenshots](#-screenshots) · [Usage](#-usage) · [Troubleshooting](#-troubleshooting) · [Website](https://weprinteasy.com)

<img src="docs/screenshots/admin-1-zuweisungen.png" alt="WePrintEasy Printer Management" width="820">

</div>

---

On terminal servers (RD Session Hosts), users' default printers keep changing: Windows picks the
printer that was used last, RDP redirection brings along the default printer of the user's own PC,
and applications change it on the side. **WePrintEasy** assigns a fixed default printer per AD user
or AD group – and makes sure it stays that way.

## ✨ Features

- 🎯 **Fixed default printer** per AD user or AD group – with priorities and nested groups
- 🔁 **Set and kept in place** – at logon, at reconnect and, optionally, during the entire session
- 🖨️ **Printer list from your file server** – load all shared printers with one click and install missing drivers right away
- 🧙 **Graphical setup wizard** – installed in about 2 minutes, updated with a double-click
- ⚡ **"Enforce now (live)"** – sets the printer immediately in a user's session and shows every step
- 🖱️ **Optional: users choose themselves** – icon in the notification area, the choice replaces their assignment and is visible in printer management
- 🩺 **Health check with traffic lights** – finds configuration problems and fixes them at the push of a button
- 🏢 **Ready for RDS farms** – one central configuration for any number of terminal servers
- 🔏 **Optionally signed** (Authenticode, `AllSigned`) – fewer false alarms from virus scanners
- 🌐 **English and German** – user interface and logs, switchable in the settings
- 📦 **No dependencies** – only the built-in Windows PowerShell 5.1, no RSAT, no AD schema extension

## 📸 Screenshots

<table>
  <tr>
    <td width="50%"><b>Setup wizard: printers from the file server</b><br><img src="docs/screenshots/setup-3-drucker.png" alt="Setup – printers from the file server"></td>
    <td width="50%"><b>Edit assignment</b><br><img src="docs/screenshots/admin-2-zuweisung-bearbeiten.png" alt="Edit assignment"></td>
  </tr>
  <tr>
    <td><b>Setup check (health check)</b><br><img src="docs/screenshots/admin-6-einrichtung.png" alt="Setup check"></td>
    <td><b>Log of a user</b><br><img src="docs/screenshots/admin-4-benutzer-pruefen.png" alt="Check user"></td>
  </tr>
  <tr>
    <td><b>Built-in guide</b><br><img src="docs/screenshots/admin-8-anleitung.png" alt="Guide"></td>
    <td><b>Printer list</b><br><img src="docs/screenshots/admin-3-druckerliste.png" alt="Printer list"></td>
  </tr>
</table>

<sub>Captured by the automated test on Windows Server 2025 (70 test printers simulating a file server) with the German user interface. All images: <a href="docs/screenshots"><code>docs/screenshots</code></a></sub>

## 🤔 Why does the default printer change in the first place?

| Cause | What WePrintEasy does about it |
|---|---|
| **"Let Windows manage my default printer"** – Windows automatically makes the last used printer the default | The agent turns this option off per user (`LegacyDefaultPrinterMode = 1`) |
| **RDP printer redirection** – the default printer of the client PC becomes the session's default printer after logon (with a delay!) | After logon, the agent checks every 3 seconds for 2 minutes and resets it; optionally also the policy `fForceClientLptDef = 0` |
| Applications or users change the default printer during the session | Optional monitoring during the entire session (default: every 30 seconds) |
| The network printer is not (yet) connected after logon | The agent connects `\\server\share` automatically |

## 📋 Requirements

| | |
|---|---|
| **Operating system** | Windows Server 2025, 2022 or 2019 with the Remote Desktop Session Host role |
| **Runtime** | Windows PowerShell 5.1 (included with Windows) |
| **Active Directory** | The server is a domain member – no RSAT, no schema extension |
| **Permissions** | Administrator for the installation; users only need read access to the configuration (with [printer choice by users](#️-printer-choice-by-users): create files in the `choices` folder) |

## 🚀 Quick start

1. Download the repository as a ZIP ([download](https://github.com/LeonMTN05/WePrintEasy/archive/HEAD.zip) or [website](https://weprinteasy.com)) and extract it on the terminal server.
2. Double-click **`Setup.cmd`** (asks for administrator rights).
3. Choose the **language** – English is preselected; when updating, the previous language.
4. Follow the wizard, done. Then assign printers in the Start menu under **Windows Tools → WePrintEasy Printer Management**.

> [!TIP]
> With several terminal servers, run the setup on each server and specify the same central
> configuration path, e.g. `\\fs01\WePrintEasy$\config.json` – see [RDS farm](#multiple-session-hosts-rds-farm).

<details>
<summary><b>The steps of the setup wizard in detail</b></summary>
<br>

| Step | Content |
|---|---|
| Welcome | Overview, detects an existing installation (assignments are kept) |
| Configuration | "This server only" or centrally on the file server (`\\fs01\WePrintEasy$\config.json`) – with a write test |
| Printers from file server | Enter the print/file server → **Load printers**: all shared printers (e.g. 70) appear with driver, location and comment. **Preselected are the printers whose driver is already installed locally on the terminal server.** Buttons *All / None / Only with local driver*; optionally *Install missing drivers now* |
| Options | RDS policy, monitoring during the session, turn off "Let Windows manage my default printer", connect network printers, shortcut, editor group, script signing (see [code signing](#-code-signing-virus-scanners)) |
| Installation | Summary → **Install** with live log → Done (opens printer management if desired) |

</details>

### 📦 Windows installer (`WePrintEasy-Setup-<version>.exe`)

Alternative to the ZIP: a single `.exe` with an entry under **Apps / Programs and Features**.

- **New installation:** copies the installation package to `C:\Program Files\WePrintEasy\Setup` and starts the setup wizard in the installer's language.
- **Existing installation** (also from the ZIP): update with all settings, like `Update.cmd`; optionally followed by the setup wizard.
- **Uninstall** via *Apps* – asks whether the local configuration should be deleted as well.

```powershell
# Unattended (exit code 0 = success, 10 = failed, log: C:\Program Files\WePrintEasy\Setup\WePrintEasy-Setup.log)
WePrintEasy-Setup-1.0.9.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LANG=en /INSTALLARGS="-PrintServer fs01 -DisableClientDefaultPrinter"
& 'C:\Program Files\WePrintEasy\unins000.exe' /VERYSILENT [/REMOVECONFIG]
```

`/INSTALLARGS` only applies to new installations and takes parameters of [`Install-WePrintEasy.ps1`](#️-command-line-installation)
(values in single quotes). Build it yourself: install [Inno Setup 6](https://jrsoftware.org/isinfo.php)
(`winget install --id JRSoftware.InnoSetup -e`), then `.\tools\Build-Installer.ps1` → `dist\`.

The same silent parameters apply to the **Microsoft Store** (package type EXE): `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`.
A new setup replaces the existing version (same app ID, same program folder) and closes open printer management windows first.

### 🔔 Update check

At start, printer management queries `https://dl.weprinteasy.com/latest.json` in the background – at most once a day,
with a 10-second timeout; without internet access it keeps working normally. If there is a newer version, **"New version X available"** appears:
*Update now* downloads the setup to a temp folder, verifies its SHA-256 checksum, starts it and closes printer management.
Manually: **Check for updates** button in the header.

Turn it off for a server (the manual check stays available):

```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\WePrintEasy' -Name DisableUpdateCheck -Value 1 -Type DWord
```

## 🔄 Update

Extract the new version (or copy it into the previous folder) and double-click **`Update.cmd`**
(asks for administrator rights). The updater reinstalls the program files and keeps all previous
settings: configuration path, assignments, printer list, language, signing, editor group, RDS policy
and shortcut. At the end it shows the health check.

> [!NOTE]
> Agents already running in user sessions are restarted with the new version – disconnected sessions included.
> Installations from before the language selection stay German.
> For automated updates: `.\Update-WePrintEasy.ps1 -NoPause`

## ⌨️ Command-line installation

An alternative to the setup wizard, e.g. for automated installations. Open PowerShell
**as administrator** and run in the extracted folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-WePrintEasy.ps1 -PrintServer fs01 -DisableClientDefaultPrinter
```

That's it. The installation

- copies the program files to `C:\Program Files\WePrintEasy`,
- creates the configuration `C:\ProgramData\WePrintEasy\config.json`
  (users may only **read** it, administrators may modify it),
- imports the shared printers of the file server into the printer list with `-PrintServer`
  (default: only those with a locally installed driver; `-ImportPrinters All` for all,
  `-InstallMissingDrivers` installs missing drivers),
- registers the scheduled task **`\WePrintEasy\WePrintEasy Agent`**
  (triggers: logon and reconnect of an RDP session, runs as the respective user, invisible),
- creates the shortcut **"WePrintEasy Printer Management"** (German: **"WePrintEasy Druckerverwaltung"**)
  under **Windows Tools**, with the app icon,
- sets the language with `-Language en` (default) or `-Language de`,
- sets the policy *"Do not set default client printer to be default printer in a session"*
  with `-DisableClientDefaultPrinter` (alternatively [via GPO](#alternative-to-the-installer-policy-gpo)).

The script can simply be run again for updates – existing assignments are kept.

### Multiple session hosts (RDS farm)

So that all servers use the same assignments, store the configuration centrally:

1. Create a share, e.g. `\\fs01\WePrintEasy$`
   - NTFS/share: **Domain Users: Read**, admins (or a group "Printer admins"): **Modify**
2. Install on **every** session host:

   ```powershell
   .\Install-WePrintEasy.ps1 -ConfigPath '\\fs01\WePrintEasy$\config.json' -PrintServer fs01 -DisableClientDefaultPrinter
   ```

Every server registers itself with its version in the `hosts` folder next to the configuration during
installation and update. The **Setup check** tab of every server then shows where in the farm an older
version is still running (servers with a version before 1.0.6 only appear after their update).

With a local configuration, `-EditorGroup 'COMPANY\PrinterAdmins'` grants a group the right to
maintain assignments without administrator rights.

<details>
<summary><b>All installer parameters</b></summary>
<br>

| Parameter | Meaning |
|---|---|
| `-ConfigPath` | Path of the configuration file (local or UNC). Default: `C:\ProgramData\WePrintEasy\config.json` |
| `-PrintServer` | Print/file server whose shared printers are imported into the printer list |
| `-ImportPrinters` | `WithLocalDriver` (default), `All` or `None` |
| `-PrinterListFile` | Text file with one `\\server\share` per line (instead of `-ImportPrinters`) |
| `-InstallMissingDrivers` | Install missing drivers of the imported printers |
| `-EditorGroup` | AD group with write access to the local configuration |
| `-DisableClientDefaultPrinter` | Set the RDS policy so that the client's default printer is not used |
| `-InstallPath` | Installation folder (default: `C:\Program Files\WePrintEasy`) |
| `-NoShortcut` | Do not create a shortcut under Windows Tools |
| `-SelfSignedCertificate` | Sign the scripts with a self-signed certificate of this server (see below) |
| `-SigningCertificateThumbprint` | Sign the scripts with an existing code signing certificate (e.g. company CA) |
| `-TimestampServer` | Timestamp service for the signature, e.g. `http://timestamp.digicert.com` (requires internet access) |
| `-NoSigning` | Do not sign, or turn off existing signing |
| `-Language` | Language of installer, management program and agent log: `en` (default) or `de`. If omitted, an update keeps the previous language |

</details>

### 🔏 Code signing (virus scanners)

Without a signature, the logon task starts the agent invisibly with `-ExecutionPolicy Bypass`.
Some virus scanners (e.g. Panda) classify this pattern as suspicious. With signing, all installed
scripts are signed via Authenticode, and the task, the shortcut and `WePrintEasy-Admin.cmd` start
with **`-ExecutionPolicy AllSigned`**.

```powershell
# Self-signed (one server, no CA required)
.\Install-WePrintEasy.ps1 -SelfSignedCertificate

# Company CA certificate ("Code Signing" template, with private key in LocalMachine\My or CurrentUser\My)
.\Install-WePrintEasy.ps1 -SigningCertificateThumbprint 'A1B2C3...' -TimestampServer 'http://timestamp.digicert.com'
```

- **Self-signed:** The certificate `CN=WePrintEasy Codesignatur (<server>)` is valid for 5 years and
  its key cannot be exported. It is trusted on this server only (`LocalMachine\Root` and
  `LocalMachine\TrustedPublisher`). From 30 days before expiry, an update renews it automatically.
  Uninstalling removes it again.
- **Company CA:** The installer adds the certificate to `LocalMachine\TrustedPublisher`. The server
  must already trust the CA (usual in a domain).
- Signing is kept across updates. `-NoSigning` turns it off.
- If signing fails, the installer installs unsigned (`Bypass`) with a warning, so the agent keeps working.

> [!IMPORTANT]
> If you modify the installed scripts afterwards, their signature becomes invalid and the agent no
> longer starts. Run the installer again afterwards – it signs again. The "Setup check" tab shows
> the state under **Signature**.

> [!WARNING]
> A signature makes false alarms less likely but does not rule them out. If it doesn't help, exclude
> the folders `C:\Program Files\WePrintEasy` and `C:\ProgramData\WePrintEasy` in your virus scanner.
> Never exclude `powershell.exe` itself.

## 💻 Usage

Start via **Windows Tools → WePrintEasy Printer Management** or
`C:\Program Files\WePrintEasy\WePrintEasy-Admin.cmd`. If write access is missing, the program offers
to restart as administrator.

**About** (button at the top right or <kbd>F1</kbd>) shows the version, project page, system information
and the disclaimer. **Report a bug on GitHub…** opens a pre-filled issue – the system information
contains no computer, user, domain or server names.

| Tab | What for |
|---|---|
| **Assignments** | Assign printers to users and groups, edit, remove, enforce |
| **Printer list** | Printers available when assigning – update from the print/file server |
| **Check user** | Which printer is set, and why? View the agent's log |
| **Setup check** | Health check with traffic lights, fix problems at the push of a button |
| **Settings** | Logon phase, monitoring, print server, language |
| **Guide** | Step-by-step instructions inside the program |

<details>
<summary><b>"Assignments" tab</b></summary>
<br>

- **Assign user…** – search for a user in AD (name, logon name or e-mail),
  select, choose a printer, save.
- **Assign group…** – the same for an AD group. The **priority** decides which group wins
  if a user is in several groups (lowest number wins). Nested groups are taken into account.
- **Edit…** (or double-click), **Remove** (or <kbd>Del</kbd>), **Search** filter. <kbd>Ctrl</kbd>- or
  <kbd>Shift</kbd>-click selects several assignments to remove at once (the printer list works the same way).
- <kbd>Ctrl</kbd>+<kbd>Z</kbd> or **Setup check → Undo last change…** restores the state before the last save
  (assignments, printer list and settings; running it again brings back the current state).

**Order:** direct user assignment → group assignment with the lowest priority → no change.

**Specifying the printer:**

- Choose from the **printer list** (the printers imported from the file server during setup; location/comment are shown)
- Any network printer: `\\printsrv01\HP-Office` – or enter a server and click **Load from server**
- A printer installed locally on the terminal server: simply its name
- A redirected printer from the client PC (the name contains the session number): use a wildcard,
  e.g. `Brother HL-L2350DW*(redirected*` (on German Windows: `*(umgeleitet*`)

</details>

<details>
<summary><b>"Printer list" tab</b></summary>
<br>

The printers available when assigning (with location, driver and number of assignments).
**Update from print/file server…** reloads the server's shares – e.g. when new printers have been
added – and can install missing drivers.

</details>

<details>
<summary><b>"Check user" tab</b></summary>
<br>

- **Resolve** shows for a logon name which printer will be set at the next logon and via which
  assignment (including all matching groups).
- **Show log** shows what the agent did for this user on this server
  (e.g. "Default printer set: … (previously: …)" – this also shows you *what* changed the printer).

</details>

<details>
<summary><b>"Setup check" tab</b></summary>
<br>

Health check with traffic lights: installation and version, logon task, configuration, write access,
versions of the other servers using the same configuration, assignments, RDS policies and, for every print server in use: reachable, shares present, drivers
installed locally. **Fix selected item** sets e.g. the RDS policy. **Run agent for me now** tests the
agent in your own session.

</details>

### ⚙️ Settings

| Setting | Default | Meaning |
|---|---|---|
| Logon phase | 120 s | For this long after logon, a check runs every 3 s (redirected printers appear with a delay) |
| Monitor during the session | on | The default printer keeps being monitored and reset afterwards |
| Check interval | 30 s | Interval of the monitoring |
| Monitoring duration | 0 | Minutes, 0 = entire session |
| Disable "Let Windows manage my default printer" | on | recommended |
| Connect network printers automatically | on | missing `\\server\share` printers are connected |
| Default print server | – | Pre-filled in the assignment dialog |
| Language | as chosen during setup | see [Language](#-language) |
| Users may choose their default printer themselves | off | icon in the session's notification area, see [Printer choice by users](#️-printer-choice-by-users) |

Changes to assignments and settings are **applied automatically** by running sessions (at the latest
after one check interval) – no need to log on again. Only changed **group memberships** in AD take
effect after the next logon.

> [!TIP]
> If users should be allowed to change their default printer themselves during the session, turn off
> "Monitor during the session". The printer is then only set at logon.
> If their own choice should stick, turn on [printer choice by users](#️-printer-choice-by-users) instead.

### 🖱️ Printer choice by users

With **Settings → "Users may choose their default printer themselves"** (default: off), every session gets a
WePrintEasy icon in the notification area. Clicking it opens a small window with the session's printers –
select a printer, **Set as default printer**, done. Users cannot change anything else there.

- The choice applies **right away and at every logon** and is kept in place by the agent like an assignment.
- It **replaces the user's assignment** (including a direct user assignment) and is listed in printer
  management under **Assignments** with the source **"Chosen by user (previously: …)"** (highlighted in yellow).
- If the administrator changes or removes that assignment, their setting applies again – until the user chooses again.
- Redirected printers (`… (redirected 3)`) are stored without the session number and are found again in the next session.
- Turning it off: the icon disappears within 30 seconds and the assignments apply again.
  Stored choices are kept and apply again when the setting is turned back on.

Each user's choice is stored in `choices\<SID>.json` next to the configuration – `config.json` stays
read-only for users. In the `choices` folder, *Authenticated Users* may only create files and *CREATOR OWNER*
may only change their own file; a file that does not belong to the user it is named after is ignored. Printer
management sets these permissions when the setting is saved (as do setup and update; the health check verifies them).

> [!IMPORTANT]
> With a **central configuration** (`\\fs01\WePrintEasy$`), users need the **Change** permission on the
> **share** (instead of Read). The NTFS permissions limit writing to the `choices` folder and their own file.

### 🌐 Language

User interface, installer and agent logs are available in **English** (default) and **German**.
The language is chosen during setup (or via `-Language en|de`) and can be changed at any time in
printer management under **Settings → Language**. It is stored in the configuration and therefore
applies to all servers sharing that configuration; running agents log in the new language from their
next check on.

## 📜 Bulk management with PowerShell / CSV

```powershell
Import-Module 'C:\Program Files\WePrintEasy\WePrintEasy.psm1'

# Show
Get-WpeAssignment | Format-Table Type, Name, DisplayName, Printer, Priority

# Set / remove individually
Set-WpeAssignment -Type User  -Name jdoe -Printer '\\printsrv01\HP-Office'
Set-WpeAssignment -Type Group -Name GG_Warehouse -Printer '\\printsrv01\Zebra-Warehouse' -Priority 20
Remove-WpeAssignment -Type User -Name jdoe

# CSV import (columns: Type;Name;Printer;Priority;Comment) – see examples\zuweisungen.example.csv
Import-Csv .\assignments.csv -Delimiter ';' | Set-WpeAssignment
```

### Alternative to the installer policy: GPO

`Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services →
Remote Desktop Session Host → Printer Redirection →`
**"Do not set default client printer to be default printer in a session" = Enabled**

## 🔧 Troubleshooting

### Enforce now (live)

"Assignments" tab → select an assignment → **Enforce now…** (or "Check user" tab →
**Enforce now (live)…**). Choose the terminal server. The window then checks step by step and shows
the result live:

1. User in AD and a valid assignment (direct or via a group)
2. Terminal server: DNS (with a suggestion for typos), connection, WePrintEasy installed (and which version), logon task enabled
3. Does the terminal server read **the same configuration** as the management program?
4. Is the user logged on? Current default printer, printer connection, is the agent running in the session?
5. Starts the agent **once, immediately, in the user's session** (temporary scheduled task,
   removed afterwards) and shows its log live
6. Result: the new default printer, otherwise the reason according to the agent

Requirement: administrator rights on the terminal server. **Credentials…** lets you specify a domain
admin, e.g. if the management program runs under a local account.
In PowerShell: `Invoke-WpeRemoteForce -ComputerName TS01 -UserName jdoe`

### More tips

- **Log per user:** `%LOCALAPPDATA%\WePrintEasy\agent.log`
  (e.g. `C:\Users\jdoe\AppData\Local\WePrintEasy\agent.log`) – contains the target printer,
  every correction ("Default printer set: … (previously: …)") and errors.
- **Test the agent manually in the user session:**
  ```powershell
  powershell -ExecutionPolicy Bypass -File 'C:\Program Files\WePrintEasy\WePrintEasy-Agent.ps1' -Once -Verbose
  ```
- **Scheduled task:** check it in Task Scheduler under `\WePrintEasy\` (enable "History").
- **A network printer cannot be connected:** since the PrintNightmare updates, standard users may not
  install printer drivers. Preinstall the drivers on the terminal server (or configure Package Point
  and Print / "Approved servers" via GPO).
- **Printer "not (yet) available" in the log:** for redirected printers, the client PC is not
  connected or the name does not match – use a wildcard and check the exact name with `Get-Printer`
  in the session.

## 🗑️ Uninstall

```powershell
.\Uninstall-WePrintEasy.ps1                     # the configuration is kept
.\Uninstall-WePrintEasy.ps1 -RemoveConfig -RemoveClientDefaultPrinterPolicy
```

Agents still running in user sessions are stopped. A certificate created with `-SelfSignedCertificate` is always removed as well.
Set up with the Windows installer: uninstall via *Apps / Programs and Features*.

## 📁 Project structure

```
Setup.cmd                       Graphical setup wizard (recommended) – just double-click
Setup-WePrintEasy.ps1           Setup wizard (started by Setup.cmd)
Update.cmd                      Update an existing installation – just double-click
Update-WePrintEasy.ps1          Updater (started by Update.cmd)
Install-WePrintEasy.ps1         Installation / update from the command line (e.g. for scripts)
Uninstall-WePrintEasy.ps1       Uninstallation
src\WePrintEasy-Admin.ps1       Management program (graphical)
src\WePrintEasy-Agent.ps1       Logon agent (runs in the context of each user)
src\WePrintEasy-Tray.ps1        Notification area icon for printer choice by users (started by the agent)
src\WePrintEasy.psm1            Shared module (also usable in scripts)
src\WePrintEasy.Gui.ps1         Shared user interface building blocks
src\WePrintEasy.Strings.*.psd1  Texts per language (en = English, de = German)
src\WePrintEasy.ico             App icon
examples\                       Sample configuration and CSV template
tools\New-WpeIcon.ps1           Generates the app icon (src\WePrintEasy.ico, docs\weprinteasy-icon.png)
tools\Build-Installer.ps1       Builds the Windows installer dist\WePrintEasy-Setup-<version>.exe
installer\WePrintEasy.iss       Inno Setup script of the Windows installer
tests\                          Unit and integration tests (Windows Server 2025)
LICENSE                         MIT License
```

## 🧪 Technical details and tests

- Assignments are stored with the **SID** of the AD object – renaming users/groups is harmless.
- The agent determines group memberships from the logon token (including nested groups) – no AD queries at logon.
- At most one agent instance runs per session; it uses practically no resources when idle.
- The default printer is read and set via the Windows API (`GetDefaultPrinter`/`SetDefaultPrinter`).
  In RDP sessions, Windows stores it per session (`HKCU\…\Windows\SessionDefaultDevices`); the value
  `HKCU\…\Windows\Device` and `WScript.Network` do not reflect the effective default printer there.
- The configuration is written atomically; the previous version is kept next to it as `config.json.bak`.

**Tests**

- Core logic: `powershell -File .\tests\Run-Tests.ps1` (Windows PowerShell 5.1 and PowerShell 7)
- Integration tests (installer, setup wizard, agent with real printers, all views of the user interface
  in both languages) run automatically on **Windows Server 2025** on every push
  ([GitHub Actions](https://github.com/LeonMTN05/WePrintEasy/actions/workflows/tests.yml); running it manually
  with "Bildschirmfotos committen" updates `docs/screenshots`).
- Not testable automatically: AD search (no domain controller in the test) and connecting a network
  printer (Windows does not allow a printer connection to the local computer).

> [!CAUTION]
> Run `.\tests\Integration.Windows.ps1` on a **test server** only – the script creates 70 test
> printers and installs/uninstalls WePrintEasy including its configuration.

## 🤝 Report bugs and contribute

Please report bugs and feature requests as an [issue](https://github.com/LeonMTN05/WePrintEasy/issues) –
easiest via **About → Report a bug on GitHub…** in printer management, which fills in the system
information for you. Pull requests are welcome; please run the tests first.

Like WePrintEasy? The author is happy about a ⭐ on GitHub.

## 📄 License and liability

WePrintEasy is licensed under the [MIT License](LICENSE): use, distribution and modification are
free, the copyright notice must be retained. The software is provided without warranty; use is at
your own risk. WePrintEasy is an independent project and is not affiliated with Microsoft Corporation.

<div align="center">
<sub>Developed by <a href="https://github.com/LeonMTN05">LeonMTN05</a> · <a href="https://weprinteasy.com">weprinteasy.com</a></sub>
</div>
