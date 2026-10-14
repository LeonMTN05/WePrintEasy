# Security Policy

[English](#english) · [Deutsch](#deutsch)

## English

### Supported versions

Security fixes are released for the latest version only. Update via the printer management
(update check) or by running the current setup from [weprinteasy.com](https://weprinteasy.com).

| Version | Supported |
|---|---|
| latest 1.0.x | ✅ |
| older | ❌ |

### Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead:

- use GitHub's private reporting: [Report a vulnerability](https://github.com/LeonMTN05/WePrintEasy/security/advisories/new), or
- send an e-mail to **hello@weprinteasy.com** (subject: "Security").

Please include the version, the affected file or function and steps to reproduce. You will get an
answer within 7 days. Once a fix is released, the report is credited in the changelog unless you
prefer to stay anonymous.

### Antivirus false positives

WePrintEasy consists of plain, readable PowerShell scripts that start hidden (logon agent, scheduled
tasks). Some antivirus products flag this pattern. If your scanner reports WePrintEasy, compare the
SHA-256 checksum with the one on the download page and let us know which product and detection name
was reported - we submit the file to the vendor as a false positive.

## Deutsch

### Unterstützte Versionen

Sicherheitskorrekturen gibt es nur für die jeweils neueste Version. Aktualisieren über die
Druckerverwaltung (Update-Prüfung) oder mit dem aktuellen Setup von [weprinteasy.de](https://weprinteasy.de).

### Sicherheitslücke melden

Bitte **kein** öffentliches Issue für Sicherheitsprobleme anlegen, sondern:

- die private Meldung von GitHub nutzen: [Report a vulnerability](https://github.com/LeonMTN05/WePrintEasy/security/advisories/new), oder
- eine E-Mail an **hello@weprinteasy.com** schicken (Betreff: „Sicherheit“).

Bitte Version, betroffene Datei oder Funktion und Schritte zum Nachstellen angeben. Sie erhalten
innerhalb von 7 Tagen eine Antwort. Nach der Korrektur wird die Meldung im Changelog genannt, sofern
Sie nicht anonym bleiben möchten.

### Fehlalarme von Virenscannern

WePrintEasy besteht aus lesbaren PowerShell-Skripten, die unsichtbar starten (Anmelde-Agent, geplante
Aufgaben). Manche Virenscanner stufen dieses Muster als verdächtig ein. Meldet Ihr Scanner
WePrintEasy, vergleichen Sie bitte die SHA-256-Prüfsumme mit der auf der Download-Seite und teilen
Sie uns Produkt und Erkennungsnamen mit – wir melden die Datei dem Hersteller als Fehlalarm.
