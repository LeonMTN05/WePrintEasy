@echo off
rem WePrintEasy Setup-Assistent starten (fragt nach Administratorrechten)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Setup-WePrintEasy.ps1" %*
