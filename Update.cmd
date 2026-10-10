@echo off
rem Aktualisiert eine vorhandene WePrintEasy-Installation (alle Einstellungen bleiben erhalten)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-WePrintEasy.ps1" %*
