$errors = @()
$null = [System.Management.Automation.Language.Parser]::ParseFile('acp-manager.ps1', [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    foreach ($e in $errors) {
        Write-Host ('Line ' + $e.Extent.StartLineNumber + ': ' + $e.Message) -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host 'SYNTAX OK' -ForegroundColor Green
    exit 0
}
