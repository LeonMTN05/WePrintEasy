@{
    # PSScriptAnalyzer (.github/workflows/lint.yml): Fehler und Warnungen
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Konsolen- und Protokollausgaben mit Write-Host sind gewollt (Installer, Setup, Tests)
        'PSAvoidUsingWriteHost',
        # Interne Hilfsfunktionen; Bestaetigung uebernehmen die Oberflaechen
        'PSUseShouldProcessForStateChangingFunctions',
        # Funktionsnamen wie Get-WpeAssignments sind Teil der dokumentierten Schnittstelle
        'PSUseSingularNouns',
        # Fehlalarme bei Parametern, die nur in Skriptbloecken verwendet werden
        'PSReviewUnusedParameter',
        # Bricht mit einer Ausnahme ab bei den Ersatzfunktionen (Mocks) in tests\Run-Tests.ps1
        'PSUseSupportsShouldProcess'
    )
}
