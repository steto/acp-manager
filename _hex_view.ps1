$path = 'acp-manager.ps1'
$lines = Get-Content $path
$targets = @(1594, 1595, 1596, 1620, 1621, 1646, 1647, 1648, 1674, 1675, 1676, 1709, 1710, 1711, 1744, 1745, 1746)
foreach ($i in $targets) {
    if ($i -lt $lines.Count) {
        $line = $lines[$i]
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $hex = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Host "Line $($i+1):"
        Write-Host "  HEX: $hex"
        Write-Host "  TXT: $line"
        Write-Host ""
    }
}
