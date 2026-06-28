$path = 'acp-manager.ps1'
$content = Get-Content $path -Raw

# Replace the corrupted sub-menu header lines with clean ASCII versions
$replacements = @{
    'Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   %emoji%  Scan and Detection               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   [Scan and Detection]               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
'@
    'Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   %emoji%  Install and Update               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   [Install and Update]               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
'@
    'Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   %emoji%  Bridge Management              |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   [Bridge Management]                |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
'@
    'Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   %emoji%  DevTunnel                      |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   [DevTunnel]                        |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
'@
    'Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   %emoji%   System                         |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |   [System]                           |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
'@
    'Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan
        Write-Host "|         ACP Manager v$($Script:Version) - Interactive          |" -ForegroundColor Cyan
        Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan' = @'
        Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan
        Write-Host "|         ACP Manager v$($Script:Version) - Interactive          |" -ForegroundColor Cyan
        Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan
'@
}

# Actually this is getting too complex with the matching. Let me just rewrite the whole sub-menu sections.
# The issue is corrupted emoji bytes. Let me instead read each line, detect corrupted bytes, and replace them.

Write-Host "Trying simpler approach..." -ForegroundColor Yellow
$path
