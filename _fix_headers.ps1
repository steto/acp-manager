$path = 'acp-manager.ps1'
$lines = Get-Content $path
$newLines = @()
$lineNum = 0

foreach ($line in $lines) {
    $lineNum++
    $replaced = $false
    
    # Check if this is a corrupted sub-menu header line
    if ($line -match 'Write-Host\s+"\s*\|\s+.*(?:Scan & Detection|Install & Update|Bridge Management|DevTunnel|System)\s+\|"') {
        if ($line -match 'Scan & Detection') {
            $newLines += '        Write-Host "  |         SCAN AND DETECTION               |" -ForegroundColor Cyan'
            $replaced = $true
        }
        elseif ($line -match 'Install & Update') {
            $newLines += '        Write-Host "  |         INSTALL AND UPDATE               |" -ForegroundColor Cyan'
            $replaced = $true
        }
        elseif ($line -match 'Bridge Management') {
            $newLines += '        Write-Host "  |         BRIDGE MANAGEMENT                |" -ForegroundColor Cyan'
            $replaced = $true
        }
        elseif ($line -match 'DevTunnel') {
            $newLines += '        Write-Host "  |         DEV TUNNEL                      |" -ForegroundColor Cyan'
            $replaced = $true
        }
        elseif ($line -match 'System') {
            $newLines += '        Write-Host "  |         SYSTEM                           |" -ForegroundColor Cyan'
            $replaced = $true
        }
    }
    
    if (-not $replaced) {
        $newLines += $line
    }
}

$newLines -join "`r`n" | Set-Content -Path $path -Encoding UTF8 -Force
Write-Host "Done. Lines processed: $lineNum" -ForegroundColor Green
