@echo off
rem Startet die WePrintEasy Druckerverwaltung
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0WePrintEasy-Admin.ps1" %*
