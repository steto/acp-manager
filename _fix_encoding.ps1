$path = 'acp-manager.ps1'
$content = Get-Content $path -Raw
$content | Set-Content -Path $path -Encoding UTF8 -Force
Write-Host 'Converted to UTF-8 with BOM using Set-Content' -ForegroundColor Green
