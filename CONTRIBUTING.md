# Contributing to WePrintEasy

[English](#english) · [Deutsch](#deutsch)

## English

Thank you for helping! Bug reports, ideas and pull requests are welcome.

### Report bugs and request features

- Open an [issue](https://github.com/LeonMTN05/WePrintEasy/issues) – easiest via **About → Report a bug
  on GitHub…** in the printer management, which fills in the system information.
- Security problems: please **do not** open a public issue, see [SECURITY.md](SECURITY.md).

### Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep it focused – one topic per pull request.
3. **Add tests:** new functionality and bug fixes need a test in `tests/Run-Tests.ps1` (core logic)
   or `tests/Integration.Windows.ps1` (installer, agent, user interface). Changes without tests are
   only accepted if testing is not possible automatically – please explain why in the pull request.
4. Run the checks locally (see below) and open the pull request against `main`.
   GitHub Actions runs the same checks on Windows Server 2025.

### Requirements for acceptable contributions

- **Compatibility:** Windows PowerShell 5.1 and PowerShell 7, Windows Server 2019/2022/2025.
  No additional modules or dependencies (no RSAT, no PowerShell Gallery modules at run time).
- **Code style:** follow the existing code – 4 spaces, approved verbs with the prefix `Wpe`
  (e.g. `Get-WpeLanguage`), `Set-StrictMode` compatible code.
- **Static analysis:** no findings from PSScriptAnalyzer with the rules in
  [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1).
- **Texts:** user-visible texts belong in `src/WePrintEasy.Strings.en.psd1` **and**
  `src/WePrintEasy.Strings.de.psd1`.
- **Line endings and encoding:** keep CRLF (see `.gitattributes`) and the existing encoding of each file.
- By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).

### Run the checks

```powershell
# Unit tests (Windows PowerShell 5.1 and PowerShell 7)
powershell -File .\tests\Run-Tests.ps1
pwsh -File .\tests\Run-Tests.ps1

# Static analysis
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

# Integration tests - ONLY on a test server (creates 70 test printers, installs/uninstalls WePrintEasy)
.\tests\Integration.Windows.ps1
```

## Deutsch

Danke für Ihre Hilfe! Fehlermeldungen, Ideen und Pull Requests sind willkommen.

- **Fehler und Wünsche:** als [Issue](https://github.com/LeonMTN05/WePrintEasy/issues) melden – am
  einfachsten über **Info → Fehler auf GitHub melden…** in der Druckerverwaltung.
- **Sicherheitsprobleme:** bitte **kein** öffentliches Issue, siehe [SECURITY.md](SECURITY.md).
- **Pull Requests:** Branch von `main`, ein Thema pro Pull Request. **Neue Funktionen und
  Fehlerkorrekturen brauchen einen Test** in `tests/Run-Tests.ps1` oder `tests/Integration.Windows.ps1`.
  Vorher die Tests und PSScriptAnalyzer ausführen (Befehle oben). Es gelten die Anforderungen oben:
  PowerShell 5.1 und 7, keine zusätzlichen Abhängigkeiten, Texte in beiden Sprachdateien, CRLF.
