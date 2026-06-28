<#
.SYNOPSIS
    ACP Manager v4.2 - Bridge Management + Agent Detection Engine
.DESCRIPTION
    Complete ACP bridge management + agent detection + installation.
    
    BRIDGE: Init, Install, Start, Stop, Restart, Status, Tunnel, Autostart
    DETECTION: Scan, AgentInfo, Registry, InstallAgent (37 agents from official ACP registry)
    SYSTEM: Config, Diag, Logs, LogClear, Mobile, Interactive, Help
.PARAMETER Action
    Action: Init, Install, InstallAgent, Start, Stop, Restart, Status, Scan, AgentInfo,
            Registry, Tunnel, TunnelCreate, TunnelList, TunnelInfo, TunnelDelete,
            Update, Logs, LogClear, Config, Diag, Autostart, Mobile, Watch, Interactive, Help
.PARAMETER Bridge
    Bridge: opencode, kilocode, cursor, all
.PARAMETER AgentId
    Agent ID from ACP registry (e.g. gemini, claude-acp, devin)
.PARAMETER Port
    Custom port
.PARAMETER TunnelId
    DevTunnel ID
.PARAMETER OutputFormat
    Text | Json
.PARAMETER LogLines
    Log lines (default: 50)
.PARAMETER Profile
    Config profile
.PARAMETER Anonymous
    Anonymous tunnel (switch)
.PARAMETER Disable
    Disable auto-start (switch)
.PARAMETER UpdateRegistry
    Force registry update (switch)
.PARAMETER Detailed
    Detailed output (switch)
#>

param(
    [ValidateSet('Init','Install','Start','Stop','Restart','Update','Status','Scan','AgentInfo','Registry','InstallAgent','Watch',
                 'Tunnel','TunnelCreate','TunnelList','TunnelInfo','TunnelDelete',
                 'Logs','LogClear','Config','Diag','Autostart','Mobile','Interactive','Help')]
    [string]$Action = 'Interactive',
    [ValidateSet('opencode','kilocode','cursor','all')]
    [string]$Bridge = 'all',
    [string]$AgentId = '',
    [int]$Port = 0,
    [string]$TunnelId = '',
    [ValidateSet('Text','Json')]
    [string]$OutputFormat = 'Text',
    [int]$LogLines = 50,
    [string]$Profile = 'default',
    [switch]$Anonymous = $false,
    [switch]$Disable = $false,
    [switch]$UpdateRegistry = $false,
    [switch]$Detailed = $false
)

# ============================================================
# CONFIGURATION
# ============================================================

$Script:Version = '4.2.0'
$Script:ConfigDir = "$env:USERPROFILE\.acp-bridges"
$Script:ConfigFile = "$Script:ConfigDir\config.json"
$Script:RegistryCacheFile = "$Script:ConfigDir\registry-cache.json"
$Script:RegistryUrl = 'https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json'
$Script:DefaultLogPath = "$env:TEMP\acp-manager.log"
$Script:LogFile = $Script:DefaultLogPath
$Script:LogLevel = 'INFO'

$Script:BridgePortsDefault = @{ opencode=8081; kilocode=8082; cursor=8083 }
$Script:BridgeNames = @{ opencode='OpenCode AI'; kilocode='KiloCode'; cursor='Cursor' }
$Script:BridgeCmds = @{
    opencode = @{ check='opencode-acp'; start='opencode-acp --port {0}' }
    kilocode = @{ check='kilocode'; start='npx @kilocode/cli@latest acp' }
    cursor   = @{ check='cursor'; start='cursor --acp-port {0}' }
}
$Script:BridgeInstall = @{
    opencode = 'npm install -g opencode-acp'
    kilocode = 'npm install -g @kilocode/cli'
    cursor   = $null
}

# ============================================================
# FUNZIONI DI BASE
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level='INFO')
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$t] [$Level] $Message"
    $color = switch ($Level) {
        'ERROR' { 'Red' }; 'WARN' { 'Yellow' }; 'OK' { 'Green' }
        'DEBUG' { 'DarkGray' }; default { 'Gray' }
    }
    if ($Level -ne 'DEBUG' -or $Script:LogLevel -eq 'DEBUG') {
        Write-Host $line -ForegroundColor $color
    }
    if ($Script:LogFile) {
        Add-Content -Path $Script:LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

function Write-Section {
    param([string]$Title, [string]$Color='Cyan')
    $line = ('-' * 60)
    Write-Host "`n$line" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host "$line" -ForegroundColor DarkGray
}

function Write-StatusDot {
    param([string]$Label, [string]$Status, [string]$Detail='')
    $icon = switch ($Status) {
        'OK' { '[OK]' }; 'RUN' { '[RUN]' }; 'STOP' { '[STOP]' }
        'WARN' { '[WARN]' }; 'ERR' { '[ERR]' }
        'WORK' { '[WRK]' }; 'IDLE' { '[IDL]' }
        default { '[..]' }
    }
    $color = switch ($Status) {
        'OK' { 'Green' }; 'RUN' { 'Green' }; 'STOP' { 'DarkGray' }
        'WARN' { 'Yellow' }; 'ERR' { 'Red' }; 'WORK' { 'Green' }; 'IDLE' { 'Blue' }
        default { 'Gray' }
    }
    $d = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "  $icon $Label$d" -ForegroundColor $color
}

function Write-Table {
    param([array]$Data, [string[]]$Properties, [string[]]$Headers, [int]$MaxWidth=45)
    if ($OutputFormat -eq 'Json') { return $Data | ConvertTo-Json -Compress }
    $colWidths = @{}
    foreach ($prop in $Properties) {
        $max = $prop.Length
        foreach ($row in $Data) {
            $val = if ($row.$prop) { $row.$prop.ToString() } else { '' }
            if ($val.Length -gt $max) { $max = $val.Length }
        }
        $colWidths[$prop] = [Math]::Min($max + 2, $MaxWidth)
    }
    $headerLine = ''; $sepLine = ''
    for ($i = 0; $i -lt $Properties.Length; $i++) {
        $w = $colWidths[$Properties[$i]]
        $h = if ($Headers -and $i -lt $Headers.Length) { $Headers[$i] } else { $Properties[$i] }
        $headerLine += $h.PadRight($w)
        $sepLine += ('-' * $w)
    }
    Write-Host $headerLine -ForegroundColor Yellow
    Write-Host $sepLine -ForegroundColor DarkGray
    foreach ($row in $Data) {
        $line = ''
        foreach ($prop in $Properties) {
            $val = if ($row.$prop) { $row.$prop.ToString() } else { '-' }
            $line += $val.PadRight($colWidths[$prop])
        }
        Write-Host $line
    }
}

function Format-Duration {
    param([int]$Seconds)
    if ($Seconds -lt 60) { return "${Seconds}s" }
    $m = [Math]::Floor($Seconds / 60)
    if ($m -lt 60) { $s = $Seconds % 60; return "${m}m ${s}s" }
    $h = [Math]::Floor($m / 60); $m = $m % 60
    return "${h}h ${m}m"
}

function Test-Cmd { param([string]$C); return [bool](Get-Command $C -ErrorAction SilentlyContinue) }

function Get-ProcessByFilter {
    param([string]$Filter)
    return Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%$Filter%'" -ErrorAction SilentlyContinue
}

function Get-ProcessUptime {
    param($Process)
    try {
        if (-not $Process.CreationDate) { return '-' }
        $start = [Management.ManagementDateTimeConverter]::ToDateTime($Process.CreationDate)
        return Format-Duration -Seconds ([int]((Get-Date) - $start).TotalSeconds)
    } catch { return '-' }
}

function Test-PortOpen {
    param([int]$Port)
    if ($Port -le 0) { return $false }
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return [bool]$c
    } catch { return $false }
}

# ============================================================
# PERSISTENT CONFIGURATION
# ============================================================

function Get-Config {
    if (Test-Path $Script:ConfigFile) {
        try {
            $cfg = Get-Content $Script:ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($cfg.profiles.$Profile) {
                $p = $cfg.profiles.$Profile
                $Script:LogFile = if ($p.log_path) { $p.log_path } else { $Script:DefaultLogPath }
                $Script:LogLevel = if ($p.log_level) { $p.log_level } else { 'INFO' }
                return $cfg
            }
        } catch { Write-Log "Config invalid, using defaults" -Level DEBUG }
    }
    return $null
}

function Save-Config {
    param($Config)
    if (-not (Test-Path $Script:ConfigDir)) {
        New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 10 | Set-Content $Script:ConfigFile -Force
    Write-Log "Config saved: $Script:ConfigFile" -Level OK
}

function New-DefaultConfig {
    return @{
        version = $Script:Version; profile = 'default'
        profiles = @{
            default = @{
                ports = @{ opencode=8081; kilocode=8082; cursor=8083 }
                tunnel_id = ''; log_path = $Script:DefaultLogPath; log_level = 'INFO'
                auto_restart = $false; anonymous_tunnel = $false; mobile_mode = $false
            }
        }
    }
}

function Get-BridgePort {
    param([string]$BridgeName)
    if ($Port -gt 0) { return $Port }
    $cfg = Get-Config
    if ($cfg) {
        $p = $cfg.profiles.$Profile
        if ($p -and $p.ports.$BridgeName) { return [int]$p.ports.$BridgeName }
    }
    return $Script:BridgePortsDefault[$BridgeName]
}

# ============================================================
# ACP REGISTRY MANAGEMENT
# ============================================================

function Update-RegistryCache {
    Write-Log "Downloading ACP registry..." -Level INFO
    try {
        $tmpFile = Join-Path $env:TEMP "acp-registry-$([System.IO.Path]::GetRandomFileName()).json"
        Invoke-WebRequest -Uri $Script:RegistryUrl -OutFile $tmpFile -UseBasicParsing -TimeoutSec 15
        if (-not (Test-Path $Script:ConfigDir)) {
            New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null
        }
        Move-Item $tmpFile $Script:RegistryCacheFile -Force
        $reg = Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json
        Write-Log "Registry updated: $($reg.agents.Count) agents" -Level OK
        return $reg
    } catch {
        Write-Log "Registry download failed: $_" -Level WARN
        if (Test-Path $Script:RegistryCacheFile) {
            $reg = Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json
            Write-Log "Using local cache: $($reg.agents.Count) agents" -Level INFO
            return $reg
        }
        return $null
    }
}

function Get-CachedRegistry {
    if ($UpdateRegistry) { return Update-RegistryCache }
    if (Test-Path $Script:RegistryCacheFile) {
        $age = [int]((Get-Date) - (Get-Item $Script:RegistryCacheFile).CreationTime).TotalHours
        if ($age -gt 24) { Write-Log "Cache expired ($age h). Updating..." -Level INFO; return Update-RegistryCache }
        try { return Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json }
        catch { Write-Log "Cache corrupted, re-downloading..." -Level WARN; return Update-RegistryCache }
    }
    return Update-RegistryCache
}

# ============================================================
# DETECTION ENGINE
# ============================================================

function Get-AgentDetection {
    param([object]$Agent, [switch]$DeepScan)

    $id = $Agent.id; $name = $Agent.name; $dist = $Agent.distribution

    $result = @{
        AgentId = $id; Name = $name; Version = $Agent.version; License = $Agent.license
        Website = $Agent.website; Repository = $Agent.repository
        Installed = $false; InstallMethod = $null; InstallDetail = $null; InstalledVersion = $null
        Running = $false; ProcessCount = 0; ProcessId = $null
        RAM_MB = $null; CPU_Pct = $null; Uptime = $null
        Working = $false; NetworkActive = $false; PortListening = $false
        Ports = @(); ConfigFiles = @(); Status = 'Not installed'; StatusIcon = 'STOP'
    }

    # ---- MULTI-METHOD INSTALL DETECTION ----

    # 1. PATH / Binary detection
    $exeCandidates = @()
    if ($dist.binary) {
        foreach ($arch in @('windows-x86_64','windows-aarch64')) {
            if ($dist.binary.$arch) {
                $cmd = $dist.binary.$arch.cmd
                $exeName = $cmd -replace '^\./', '' -replace '^\.\\\\', ''
                $exeName = $exeName.Split('/')[-1].Split('\\')[-1]
                if ($exeName) { $exeCandidates += $exeName }
            }
        }
    }
    $exeCandidates += "$id.exe", "$id"

    foreach ($exe in $exeCandidates | Select-Object -Unique) {
        $cmdInfo = Get-Command $exe -ErrorAction SilentlyContinue
        if ($cmdInfo) {
            $result.Installed = $true; $result.InstallMethod = 'PATH'
            $result.InstallDetail = $cmdInfo.Source
            try { $v = & $exe --version 2>&1 | Select-Object -First 1; if ($v) { $result.InstalledVersion = "$v".Trim() } } catch {}
            break
        }
    }

    # 2. npm global packages
    if (-not $result.Installed -and $dist.npx) {
        $npmPkg = ($dist.npx.package -split '@')[0]
        try {
            $npmList = Get-CachedNpmList
            if ($npmList -and $npmList.dependencies.$npmPkg) {
                $result.Installed = $true; $result.InstallMethod = 'npm'
                $result.InstalledVersion = $npmList.dependencies.$npmPkg.version
                $result.InstallDetail = "npm global: $npmPkg"
            }
        } catch {}
    }

    # 3. cargo installs
    if (-not $result.Installed -and (Test-Cmd 'cargo')) {
        try {
            $cargoList = Get-CachedCargoList
            if ($cargoList) {
                # Match full package names (avoid substring false positives)
                $cargoPattern = "(?im)^\s*$id\s+v?[\d.]+"
                if ($cargoList -match $cargoPattern) {
                $result.Installed = $true; $result.InstallMethod = 'cargo'
                $result.InstallDetail = "cargo install: $id"
                $m = [regex]::Match($cargoList, "$id\s+v?([\d.]+)")
                if ($m.Success) { $result.InstalledVersion = $m.Groups[1].Value }
            }
            }
        } catch {}
    }

    # 4. Known install paths (recursive)
    if (-not $result.Installed) {
        $searchPaths = @(
            "$env:LOCALAPPDATA\Programs",
            "$env:ProgramFiles",
            "${env:ProgramFiles(x86)}",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        )
        # Short ids (e.g. go, uv, n8n) produce false positives on substring
        # matches, so only broaden the search to USERPROFILE for longer ids.
        if ($id.Length -ge 4) { $searchPaths += "$env:USERPROFILE" }
        foreach ($sp in $searchPaths) {
            $found = Get-ChildItem -Path $sp -Filter "*$id*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                if ($id.Length -lt 4 -and ($found.Name -cne $id -and $found.Name -cne "$id.exe")) { continue }
                $result.Installed = $true; $result.InstallMethod = 'KnownPath'
                $result.InstallDetail = $found.FullName
                break
            }
        }
        if (-not $result.Installed) {
            $dtPath = "$env:LOCALAPPDATA\Microsoft\DevTunnels"
            if ((Test-Path $dtPath) -and (Test-IdMatch -Token $id -Text $dtPath)) {
                $found = Get-ChildItem -Path $dtPath -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) { $result.Installed = $true; $result.InstallMethod = 'KnownPath'; $result.InstallDetail = $found.FullName }
            }
        }
    }

    # 5. Registry uninstall keys
    if (-not $result.Installed) {
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($rp in $regPaths) {
            $entries = Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -and (Test-IdMatch -Token $id -Text $_.DisplayName -or Test-IdMatch -Token $name -Text $_.DisplayName)
            }
            if ($entries) {
                $result.Installed = $true; $result.InstallMethod = 'Registry'
                $result.InstalledVersion = $entries.DisplayVersion; $result.InstallDetail = $entries.DisplayName
                break
            }
        }
    }

    # ---- CONFIG FILES ----
    $configPaths = @(
        "$env:USERPROFILE\.$id*", "$env:USERPROFILE\.config\$id*",
        "$env:USERPROFILE\AppData\Roaming\$id*", "$env:LOCALAPPDATA\$id*"
    )
    foreach ($cp in $configPaths) {
        $cfgs = Resolve-Path $cp -ErrorAction SilentlyContinue
        if ($cfgs) { $result.ConfigFiles += ($cfgs | ForEach-Object { $_.Path }) }
    }

    # ---- PROCESS DETECTION ----
    if ($DeepScan) {
        $procNames = @($id)
        $procNames += $exeCandidates | ForEach-Object { $_ -replace '\.exe$', '' }
        $procNames = $procNames | Select-Object -Unique

        $allProcs = @()
        foreach ($pn in $procNames) {
            $procs = Get-ProcessByFilter -Filter $pn
            if ($procs) { $allProcs += $procs }
            $procs2 = Get-Process -Name $pn -ErrorAction SilentlyContinue
            if ($procs2) { $allProcs += $procs2 }
        }

        if ($allProcs) {
            $result.Running = $true; $result.ProcessCount = $allProcs.Count
            $firstProc = $allProcs | Select-Object -First 1
            $result.ProcessId = $firstProc.ProcessId
            $result.RAM_MB = [Math]::Round($firstProc.WorkingSetSize / 1MB, 1)
            $result.Uptime = Get-ProcessUptime -Process $firstProc
            $result.Status = 'Running'; $result.StatusIcon = 'RUN'

            if ($Detailed) {
                try {
                    $counter = Get-Counter "\Process($($firstProc.Name))*\% Processor Time" -ErrorAction SilentlyContinue
                    if ($counter) {
                        $cpuVal = ($counter.CounterSamples | Where-Object { $_.Status -eq 0 } | Measure-Object CookedValue -Average).Average
                        $result.CPU_Pct = [Math]::Round($cpuVal, 1); $result.Working = ($cpuVal -gt 0.5)
                    }
                } catch {}
                try {
                    $tcpConns = Get-NetTCPConnection -OwningProcess $firstProc.ProcessId -ErrorAction SilentlyContinue
                    if ($tcpConns) {
                        $result.NetworkActive = ($tcpConns.State -contains 'Established')
                        foreach ($conn in $tcpConns) { $result.Ports += @{ Port = $conn.LocalPort; State = $conn.State } }
                        $result.PortListening = ($tcpConns.State -contains 'Listen')
                    }
                } catch {}
                if ($result.Working -or $result.NetworkActive) { $result.Status = 'Working'; $result.StatusIcon = 'WORK' }
                elseif ($result.PortListening) { $result.Status = 'Idle (listening)'; $result.StatusIcon = 'IDLE' }
                else { $result.Status = 'Idle'; $result.StatusIcon = 'IDLE' }
            }
        } elseif ($result.Installed) { $result.Status = 'Installed (stopped)'; $result.StatusIcon = 'STOP' }
    }
    return $result
}

# ============================================================
# ACTION: INIT
# ============================================================

function Action-Init {
    Write-Section "Initial Setup"
    if (Test-Path $Script:ConfigFile) {
        Write-StatusDot 'INFO' 'INFO' "Existing config: $Script:ConfigFile"
        $r = Read-Host "Overwrite? (y/N)"
        if ($r -ne 'y' -and $r -ne 's') { Write-Log "Init cancelled." -Level INFO; return }
    }
    $cfg = New-DefaultConfig
    Write-Host "`nBridge ports (Enter for default):" -ForegroundColor Yellow
    foreach ($b in @('opencode','kilocode','cursor')) {
        $def = $Script:BridgePortsDefault[$b]; $r = Read-Host "  $b [$def]"
        if ($r -match '^\d+$') { $cfg.profiles.default.ports.$b = [int]$r }
    }
    $r = Read-Host "`nEnable auto-restart? (y/N)"; $cfg.profiles.default.auto_restart = ($r -eq 'y' -or $r -eq 's')
    $r = Read-Host "Mobile mode? (y/N)"; $cfg.profiles.default.mobile_mode = ($r -eq 'y' -or $r -eq 's')
    $r = Read-Host "Anonymous tunnel default? (y/N)"; $cfg.profiles.default.anonymous_tunnel = ($r -eq 'y' -or $r -eq 's')
    Save-Config $cfg; Write-Log "Configuration complete!" -Level OK

    Write-Section "Prerequisites Check"
    $allOk = $true
    foreach ($cmd in @('npm','node','winget','git')) {
        if (Test-Cmd $cmd) { Write-StatusDot 'OK' 'OK' $cmd } else { Write-StatusDot 'WARN' 'WARN' "$cmd not found"; $allOk = $false }
    }
    if (Test-Cmd 'devtunnel') { Write-StatusDot 'OK' 'OK' 'devtunnel CLI' }
    else { Write-StatusDot 'WARN' 'WARN' "devtunnel not installed" }
    if ($allOk) { Write-Log "All prerequisites available!" -Level OK }
    else { Write-Log "Missing tools - install with Install action" -Level WARN }
    Write-Host "`n  Next steps: .\acp-manager.ps1 -Action Scan / .\acp-manager.ps1 -Action Install -Bridge all`n" -ForegroundColor Cyan
}

# ============================================================
# ACTION: INSTALL
# ============================================================

function Action-Install {
    Write-Section "Bridge Installation"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor') } else { @($Bridge) }
    foreach ($b in $bridges) {
        $name = $Script:BridgeNames[$b]; $cmd = $Script:BridgeInstall[$b]
        if (-not $cmd) { Write-StatusDot 'INFO' 'INFO' "$name - included in Cursor v0.45+"; continue }
        $requires = if ($cmd -match '^npm') { 'npm' } else { 'npx' }
        if (-not (Test-Cmd $requires)) { Write-StatusDot 'ERR' 'ERR' "$requires required for $name"; continue }
        $checkCmd = ($Script:BridgeCmds[$b].check -split '\s')[0]
        if (Test-Cmd $checkCmd) { Write-StatusDot 'OK' 'OK' "$name already installed"; continue }
        Write-Log "Installing $name..." -Level INFO
        try {
            $r = Invoke-Expression $cmd 2>&1
            if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "$name installed"; Write-Log "$name installed" -Level OK }
            else { Write-StatusDot 'ERR' 'ERR' "${name}: $r"; Write-Log "Error ${name}: $r" -Level ERROR }
        } catch { Write-StatusDot 'ERR' 'ERR' "${name}: $_"; Write-Log "Error ${name}: $_" -Level ERROR }
    }
    Write-Section "DevTunnel"
    if (Test-Cmd 'devtunnel') { Write-StatusDot 'OK' 'OK' 'devtunnel CLI already installed' }
    else { Install-DevTunnel }
}

function Install-DevTunnel {
    if (Test-Cmd 'winget') {
        try { $r = winget install Microsoft.devtunnel 2>&1; if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' 'DevTunnel (winget)'; return $true } } catch { }
    }
    $tmp = Join-Path $env:TEMP 'devtunnel.exe'; $dest = "$env:LOCALAPPDATA\Microsoft\DevTunnels\devtunnel.exe"; $destDir = Split-Path $dest
    try {
        Invoke-WebRequest -Uri 'https://aka.ms/TunnelsCliDownload/win-x64' -OutFile $tmp -UseBasicParsing
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null; Move-Item $tmp $dest -Force
        $p = [Environment]::GetEnvironmentVariable('PATH','User')
        if ($p -notlike "*$destDir*") { [Environment]::SetEnvironmentVariable('PATH',"$p;$destDir",'User'); $env:PATH+=";$destDir" }
        Write-StatusDot 'OK' 'OK' "DevTunnel installed"; return $true
    } catch { Write-StatusDot 'ERR' 'ERR' "Download failed: $_"; return $false }
}

# ============================================================
# ACTION: START / STOP / RESTART
# ============================================================

function Action-Start {
    Write-Section "Starting Bridge"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor') } else { @($Bridge) }
    foreach ($b in $bridges) { Start-Bridge -Name $b -DisplayName $Script:BridgeNames[$b] -Port (Get-BridgePort -BridgeName $b) }
}

function Start-Bridge {
    param([string]$Name, [string]$DisplayName, [int]$Port)
    $check = $Script:BridgeCmds[$Name].check; $startCmd = $Script:BridgeCmds[$Name].start -f $Port; $checkExe = ($check -split '\s')[0]
    $existing = Get-ProcessByFilter -Filter $check
    if ($existing) { $mem = [Math]::Round($existing.WorkingSetSize/1MB,1); Write-StatusDot 'RUN' 'RUN' "${DisplayName} already active (PID:$($existing.ProcessId) RAM:${mem}MB)"; return $existing }
    if (-not (Test-Cmd $checkExe)) { Write-StatusDot 'ERR' 'ERR' "${DisplayName} not installed"; return $null }
    try {
        if ($Name -eq 'cursor') { Write-StatusDot 'INFO' 'INFO' "${DisplayName} - configure from UI"; return $null }
        $lf = Join-Path $env:TEMP "bridge-$Name.log"
        $p = Start-Process cmd.exe -ArgumentList "/c $startCmd" -WindowStyle Hidden -PassThru -RedirectStandardOutput $lf -RedirectStandardError $lf
        Start-Sleep -Seconds 2
        if ($p -and !$p.HasExited) { Write-StatusDot 'RUN' 'RUN' "${DisplayName} started (PID:$($p.Id), port:$Port)"; Write-Log "${DisplayName} started PID:$($p.Id)" -Level OK; return $p }
        else { Write-StatusDot 'ERR' 'ERR' "${DisplayName} start failed"; return $null }
    } catch { Write-StatusDot 'ERR' 'ERR' "${DisplayName}: $_"; return $null }
}

function Action-Stop {
    Write-Section "Stopping Bridge"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor','devtunnel') } else { @($Bridge) }
    foreach ($b in $bridges) {
        if ($b -eq 'devtunnel') { $d = Get-Process -Name 'devtunnel' -ErrorAction SilentlyContinue; if ($d) { $d | Stop-Process -Force; Write-StatusDot 'STOP' 'STOP' 'DevTunnel stopped' } else { Write-StatusDot 'STOP' 'STOP' 'DevTunnel not active' }; continue }
        Stop-Bridge -Name $b
    }
}

function Stop-Bridge {
    param([string]$Name)
    $display = $Script:BridgeNames[$Name]; $check = $Script:BridgeCmds[$Name].check
    $p = Get-ProcessByFilter -Filter $check; if (-not $p) { $p = Get-Process -Name $Name -ErrorAction SilentlyContinue }
    if ($p) { foreach ($x in $p) { $pid = if ($x.ProcessId) { $x.ProcessId } else { $x.Id }; Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; Write-StatusDot 'STOP' 'STOP' "$display stopped (PID:$pid)"; Write-Log "$display stopped" -Level INFO } }
    else { Write-StatusDot 'STOP' 'STOP' "$display not active" }
}

function Action-Restart {
    Write-Section "Restarting Bridge"; $savedBridge = $Bridge; Action-Stop; Start-Sleep -Seconds 2; $Bridge = $savedBridge; Action-Start
}

# ============================================================
# ACTION: STATUS
# ============================================================

function Action-Status {
    Write-Section "ACP Bridge Status"
    $bridges = @('opencode','kilocode','cursor'); $rows = @()
    foreach ($b in $bridges) {
        $name = $Script:BridgeNames[$b]; $check = $Script:BridgeCmds[$b].check
        $checkExe = ($check -split '\s')[0]; $bp = Get-BridgePort -BridgeName $b
        $p = Get-ProcessByFilter -Filter $check; $installed = Test-Cmd $checkExe
        if ($p) {
            $mem = [Math]::Round($p.WorkingSetSize/1MB,1); $uptime = Get-ProcessUptime -Process $p; $healthy = Test-PortOpen -Port $bp
            $healthIcon = if ($healthy) { 'TCP OK' } else { 'No response' }
            $rows += [PSCustomObject]@{ Bridge=$name; PID=$p.ProcessId; Port=$bp; RAM="${mem}MB"; Status='Running'; Health=$healthIcon; Uptime=$uptime }
        } else { $stato = if ($installed) { 'Stopped' } else { 'Not installed' }
            $rows += [PSCustomObject]@{ Bridge=$name; PID='-'; Port=$bp; RAM='-'; Status=$stato; Health='-'; Uptime='-' }
        }
    }
    Write-Table -Data $rows -Properties @('Bridge','PID','Port','RAM','Status','Health','Uptime') -Headers @('Bridge','PID','Port','RAM','Status','Health','Uptime')
    $t = Get-Process -Name 'devtunnel' -ErrorAction SilentlyContinue
    if ($t) { Write-StatusDot 'RUN' 'RUN' "DevTunnel running (PID:$($t.Id))" }
    else { if (Test-Cmd 'devtunnel') { Write-StatusDot 'STOP' 'STOP' 'DevTunnel stopped' } else { Write-StatusDot 'INFO' 'INFO' 'DevTunnel not installed' } }

    $reg = Get-CachedRegistry
    if ($reg) {
        Write-Section "ACP Registry Agents" "Cyan"
        $found = @()
        foreach ($a in $reg.agents) {
            $det = Get-EnhancedDetection -Agent $a
            if ($det.Installed) {
                $v = if ($det.InstalledVersion) { $det.InstalledVersion.Substring(0, [Math]::Min(12, $det.InstalledVersion.Length)) } else { '-' }
                $found += [PSCustomObject]@{ Agent=$det.Name; Status=$det.StatusIcon; Version=$v; Method=$det.InstallMethod }
            }
        }
        if ($found.Count -gt 0) { Write-Table -Data $found -Properties @('Agent','Status','Version','Method') }
        else { Write-StatusDot 'INFO' 'INFO' 'No additional ACP agents found' }
    }
    Write-Host "`n  Log: $($Script:LogFile)" -ForegroundColor DarkGray; Write-Host "  Config: $($Script:ConfigFile)" -ForegroundColor DarkGray
}

# ============================================================
# ACTION: SCAN
# ============================================================

function Action-Scan {
    Write-Section "ACP Agent Scan - System Detection"
    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry not available'; return }

    $agents = $reg.agents; Write-Log "Scanning $($agents.Count) agents..." -Level INFO
    $results = @()
    $totalTime = Measure-Command {
        $count = 0
        foreach ($agent in $agents) {
            $count++; Write-ScanProgress -Current $count -Total $agents.Count -AgentName $agent.name
            $det = Get-EnhancedDetection -Agent $agent -DeepScan:$Detailed
            $results += [PSCustomObject]$det
        }
    }
    Clear-ScanProgress
    $installed = $results | Where-Object { $_.Installed }; $running = $results | Where-Object { $_.Running }
    Write-Host "`n  Results:" -ForegroundColor Cyan
    Write-Host "    Registry agents: $($agents.Count)" -ForegroundColor White
    Write-Host "    Installed: $($installed.Count)" -ForegroundColor Green
    Write-Host "    Running: $($running.Count)" -ForegroundColor Green
    Write-Host "    Time: $([Math]::Round($totalTime.TotalSeconds,1))s" -ForegroundColor DarkGray

    if ($Detailed) {
        Write-Section "Installed / Running" "Green"
        if ($installed.Count -gt 0) { Write-Table -Data $installed -Properties @('Name','StatusIcon','Status','Version','VersionStatus','InstallMethod','RAM_MB','CPU_Pct','Ports','Uptime') -Headers @('Agent',' ','Status','Version','Update','Method','RAM','CPU','Ports','Uptime') }
        Write-Section "All Agents" "Cyan"
        Write-Table -Data $results -Properties @('Name','StatusIcon','Status','Version','License','InstallMethod') -Headers @('Agent',' ','Status','Version','License','Installation')
    } else {
        Write-Table -Data $results -Properties @('Name','StatusIcon','Status','Version','VersionStatus','InstallMethod') -Headers @('Agent',' ','Status','Version','Update','Installation')
    }
    Write-Host "`n  Use -Detailed for health check (CPU, network, ports, I/O)." -ForegroundColor DarkGray
    Write-Host "  Use -OutputFormat Json for JSON output." -ForegroundColor DarkGray
}

# ============================================================
# ACTION: AGENTINFO
# ============================================================

function Action-AgentInfo {
    if (-not $AgentId) {
        Write-StatusDot 'ERR' 'ERR' "Specify -AgentId"; $reg = Get-CachedRegistry
        if ($reg) { Write-Host "  Available agents:" -ForegroundColor Yellow; foreach ($a in $reg.agents) { Write-Host "    $($a.id) - $($a.name)" -ForegroundColor White } }
        return
    }
    $reg = Get-CachedRegistry; if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry not available'; return }
    $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
    if (-not $agent) { Write-StatusDot 'ERR' 'ERR' "Agent '$AgentId' not found"; return }

    $det = Get-EnhancedDetection -Agent $agent -DeepScan:$true
    Write-Section "$($agent.name) ($($agent.id))" "Green"
    Write-Host "`n  Registry Info:" -ForegroundColor Yellow
    Write-Host "    Version: $($agent.version)" -ForegroundColor White; Write-Host "    License: $($agent.license)" -ForegroundColor White
    Write-Host "    Description: $($agent.description)" -ForegroundColor Gray
    if ($agent.website) { Write-Host "    Website: $($agent.website)" -ForegroundColor Blue }
    if ($agent.repository) { Write-Host "    Repository: $($agent.repository)" -ForegroundColor Blue }
    Write-Host "`n  Distribution:" -ForegroundColor Yellow
    if ($agent.distribution.npx) { Write-Host "    npx: $($agent.distribution.npx.package)" -ForegroundColor White }
    if ($agent.distribution.uvx) { Write-Host "    uvx: $($agent.distribution.uvx.package)" -ForegroundColor White }
    if ($agent.distribution.binary) {
        Write-Host "    Binary: supported" -ForegroundColor White
        if ($agent.distribution.binary.'windows-x86_64') { Write-Host "      Windows x64: $($agent.distribution.binary.'windows-x86_64'.cmd)" -ForegroundColor Gray }
    }
    Write-Host "`n  Detection:" -ForegroundColor Yellow
    if ($det.Installed) {
        Write-StatusDot 'OK' 'OK' "Installed: $($det.InstallMethod) - $($det.InstallDetail)"
        if ($det.InstalledVersion) { Write-StatusDot 'OK' 'OK' "Version: $($det.InstalledVersion)" }
    } else { Write-StatusDot 'STOP' 'STOP' 'Not installed' }
    if ($det.Running) {
        Write-StatusDot $det.StatusIcon $det.StatusIcon "$($det.Status) (PID:$($det.ProcessId))"
        if ($det.RAM_MB) { Write-StatusDot 'OK' 'OK' "RAM: $($det.RAM_MB) MB" }
        if ($det.CPU_Pct) { Write-StatusDot $det.StatusIcon $det.StatusIcon "CPU: $($det.CPU_Pct)%" }
        if ($det.Uptime) { Write-StatusDot 'OK' 'OK' "Uptime: $($det.Uptime)" }
        if ($det.PortListening) { Write-StatusDot 'RUN' 'RUN' 'Listening on port' }
        if ($det.NetworkActive) { Write-StatusDot 'WORK' 'WORK' 'Network active' }
        if ($det.Working) { Write-StatusDot 'WORK' 'WORK' 'CPU active (working)' }
    }
    if ($det.Ports.Count -gt 0) {
        Write-Host "`n  Ports:" -ForegroundColor Yellow; foreach ($p in $det.Ports) { Write-Host "    Port $($p.Port) - $($p.State)" -ForegroundColor White }
    }
    if ($det.ConfigFiles.Count -gt 0) {
        Write-Host "`n  Config files:" -ForegroundColor Yellow; foreach ($cf in $det.ConfigFiles) { Write-Host "    $cf" -ForegroundColor White }
    }
}


# ============================================================
# ACTION: REGISTRY
# ============================================================

function Action-Registry {
    Write-Section "ACP Registry"; $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry not available'; return }
    Write-Host "  Registry version: $($reg.version)" -ForegroundColor Cyan
    Write-Host "  Agents: $($reg.agents.Count)" -ForegroundColor Cyan
    Write-Host "  Cache: $Script:RegistryCacheFile" -ForegroundColor DarkGray
    Write-Section "Agent List" "Cyan"
    $rows = @()
    foreach ($a in $reg.agents) {
        $dt = @(); if ($a.distribution.npx) { $dt += 'npx' }; if ($a.distribution.uvx) { $dt += 'uvx' }; if ($a.distribution.binary) { $dt += 'binary' }
        $lic = if ($a.license) { $a.license.Substring(0, [Math]::Min(14, $a.license.Length)) } else { '-' }
        $rows += [PSCustomObject]@{ ID=$a.id; Name=$a.name; Version=$a.version; License=$lic; Distro=($dt -join ',') }
    }
    Write-Table -Data $rows -Properties @('ID','Name','Version','License','Distro') -Headers @('ID','Name','Version','License','Distribution')
}

# ============================================================
# DEV TUNNEL
# ============================================================

function Action-Tunnel {
    Write-Section "DevTunnel + Bridge"
    if ($Bridge -eq 'all') { Write-StatusDot 'WARN' 'WARN' "Tunnel does not support -Bridge all. Using: opencode"; $Bridge = 'opencode' }
    $tunnelCfg = Get-Config
    if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'WARN' 'WARN' 'DevTunnel not installed. Installing...'; Install-DevTunnel; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'Installation failed'; return } }
    $loginCheck = devtunnel user show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-StatusDot 'INFO' 'INFO' 'Login required'; devtunnel user login
        if ($LASTEXITCODE -ne 0) { Write-StatusDot 'ERR' 'ERR' 'Login failed. Use: devtunnel user login -g'; return }
    }
    $bp = Get-BridgePort -BridgeName $Bridge
    if ($Bridge -ne 'cursor') { $p = Start-Bridge -Name $Bridge -DisplayName $Script:BridgeNames[$Bridge] -Port $bp; if (-not $p) { Write-StatusDot 'ERR' 'ERR' "Bridge $Bridge not started"; return } }
    else { Write-StatusDot 'INFO' 'INFO' 'Cursor - start from UI, port 3000'; $bp = 3000 }

    $anonFromCfg = ($tunnelCfg -and $tunnelCfg.profiles.$Profile.anonymous_tunnel -eq $true)
    $anonFlag = if ($Anonymous -or $anonFromCfg) { ' --allow-anonymous' } else { '' }
    $tunnelArg = if ($TunnelId) { "host $TunnelId -p $bp --protocol http$anonFlag" } else { "host -p $bp --protocol http$anonFlag" }
    $lf = Join-Path $env:TEMP 'devtunnel-out.log'; Write-Log "Starting DevTunnel on port $bp..." -Level INFO
    try {
        $tp = Start-Process cmd.exe -ArgumentList "/c devtunnel $tunnelArg" -WindowStyle Hidden -PassThru -RedirectStandardOutput $lf -RedirectStandardError $lf
        Start-Sleep -Seconds 4
        if (Test-Path $lf) {
            $o = Get-Content $lf -Raw; $m = [regex]::Match($o,'https?://[a-zA-Z0-9._-]+\.devtunnels\.ms:\d+')
            if ($m.Success) {
                Write-Host "`n"; Write-StatusDot 'OK' 'OK' 'Tunnel active!'
                Write-Host "  REMOTE URL: $($m.Value)" -ForegroundColor Green
                Write-Host "  Bridge: $Bridge on port $bp" -ForegroundColor Cyan; Write-Host "  PID: $($tp.Id)" -ForegroundColor DarkGray
                if ($Anonymous -or $anonFromCfg) { Write-Host "  Access: ANONYMOUS" -ForegroundColor Yellow } else { Write-Host "  Access: Authenticated" -ForegroundColor DarkGray }
                Write-Log "Tunnel active: $($m.Value)" -Level OK
            } else { Write-StatusDot 'INFO' 'INFO' "DevTunnel started (PID:$($tp.Id))"; Write-Host "  Log: $lf" -ForegroundColor DarkGray }
        }
        Write-Host "  Press Ctrl+C to stop.`n" -ForegroundColor Yellow
    } catch { Write-StatusDot 'ERR' 'ERR' "Tunnel start failed: $_" }
}

function Action-TunnelCreate {
    Write-Section "Create Persistent Tunnel"
    if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel not installed'; return }
    $anonFlag = if ($Anonymous) { ' --allow-anonymous' } else { '' }
    try {
        $r = devtunnel create $anonFlag 2>&1
        if ($LASTEXITCODE -eq 0) {
            $idMatch = [regex]::Match($r,'[a-zA-Z0-9_-]+')
            if ($idMatch.Success -and $idMatch.Value.Length -gt 3) {
                Write-StatusDot 'OK' 'OK' "Tunnel created: $($idMatch.Value)"
                $cfg = Get-Config; if (-not $cfg) { $cfg = New-DefaultConfig }
                $cfg.profiles.$Profile.tunnel_id = $idMatch.Value; Save-Config $cfg
                Write-Host "  Saved to profile '$Profile'" -ForegroundColor DarkGray
                Write-Host "`n  Details:" -ForegroundColor Cyan; devtunnel show $idMatch.Value 2>&1 | ForEach-Object { Write-Host "    $_" }
            }
        } else { Write-StatusDot 'ERR' 'ERR' "Creation failed: $r" }
    } catch { Write-StatusDot 'ERR' 'ERR' "Error: $_" }
}

function Action-TunnelList {
    Write-Section "Existing Tunnels"; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel not installed'; return }
    try { $r = devtunnel list 2>&1; if ($LASTEXITCODE -eq 0 -and $r) { Write-Host $r -ForegroundColor White } else { Write-StatusDot 'INFO' 'INFO' 'No tunnels' } } catch { Write-StatusDot 'ERR' 'ERR' "Error: $_" }
}

function Action-TunnelInfo {
    Write-Section "Tunnel Details"; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel not installed'; return }
    $tid = $TunnelId; if (-not $tid) { $cfg = Get-Config; if ($cfg) { $tid = $cfg.profiles.$Profile.tunnel_id } }
    if (-not $tid) { try { $list = devtunnel list 2>&1; $m = [regex]::Match($list,'([a-zA-Z0-9_-]{10,})'); if ($m.Success) { $tid = $m.Value } } catch {} }
    if ($tid) { devtunnel show $tid 2>&1 | ForEach-Object { Write-Host "  $_" } } else { Write-StatusDot 'WARN' 'WARN' 'No tunnel found. Use -TunnelId or TunnelCreate' }
}

function Action-TunnelDelete {
    Write-Section "Delete Tunnel"; $tid = $TunnelId; if (-not $tid) { $cfg = Get-Config; if ($cfg) { $tid = $cfg.profiles.$Profile.tunnel_id } }
    if (-not $tid) { Write-StatusDot 'ERR' 'ERR' 'Specify -TunnelId'; return }
    try { $r = devtunnel delete $tid 2>&1; if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "Tunnel $tid deleted"; $cfg = Get-Config; if ($cfg -and $cfg.profiles.$Profile.tunnel_id -eq $tid) { $cfg.profiles.$Profile.tunnel_id = ''; Save-Config $cfg } } else { Write-StatusDot 'ERR' 'ERR' "Delete failed: $r" } } catch { Write-StatusDot 'ERR' 'ERR' "Error: $_" }
}

# ============================================================
# LOG MANAGEMENT
# ============================================================

function Action-Logs {
    Write-Section "Log ($LogLines lines)"; $logPath = $Script:LogFile
    if (-not (Test-Path $logPath)) { Write-StatusDot 'INFO' 'INFO' "No log at $logPath"; return }
    $content = Get-Content $logPath -Tail $LogLines; $totalLines = (Get-Content $logPath).Count
    Write-Host "  File: $logPath ($totalLines lines)" -ForegroundColor DarkGray; Write-Host "  Last $LogLines lines:`n" -ForegroundColor DarkGray
    foreach ($line in $content) { $color = 'Gray'; if ($line -match '\[ERROR\]') { $color = 'Red' } elseif ($line -match '\[WARN\]') { $color = 'Yellow' } elseif ($line -match '\[OK\]') { $color = 'Green' }; Write-Host "  $line" -ForegroundColor $color }
}

function Action-LogClear { $logPath = $Script:LogFile; if (Test-Path $logPath) { Clear-Content $logPath; Write-StatusDot 'OK' 'OK' 'Logs cleared' } else { Write-StatusDot 'INFO' 'INFO' 'No logs' } }

# ============================================================
# CONFIG / DIAG / AUTOSTART / MOBILE
# ============================================================

function Action-Config {
    Write-Section "Configuration"; if (-not (Test-Path $Script:ConfigFile)) { Write-StatusDot 'INFO' 'INFO' "No config. Run Init first."; return }
    Write-Host "  File: $Script:ConfigFile" -ForegroundColor DarkGray; Write-Host "`n$(Get-Content $Script:ConfigFile -Raw)" -ForegroundColor Cyan
    Write-Host "`n  Ports:" -ForegroundColor Yellow; foreach ($b in @('opencode','kilocode','cursor')) { Write-Host "    $($Script:BridgeNames[$b]) -> $(Get-BridgePort -BridgeName $b)" -ForegroundColor White }
}

function Action-Diag {
    Write-Section "Diagnostics"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "  OS: $($os.Caption) - Build $($os.BuildNumber)" -ForegroundColor White
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor White
    Write-Host "  RAM: $([Math]::Round($os.FreePhysicalMemory/1MB,1)) GB free / $([Math]::Round($os.TotalVisibleMemorySize/1MB,1)) GB total" -ForegroundColor White
    Write-Host "`n  Prerequisites:" -ForegroundColor Yellow
    foreach ($c in @(@{n='Node.js';c='node --version'},@{n='npm';c='npm --version'},@{n='Git';c='git --version'},@{n='Winget';c='winget --version'},@{n='DevTunnel';c='devtunnel --version'})) {
        try { $v = Invoke-Expression "$($c.c) 2>&1" -ErrorAction SilentlyContinue; if ($v) { Write-StatusDot 'OK' 'OK' "$($c.n): $($v -join ' ')" } else { Write-StatusDot 'WARN' 'WARN' "$($c.n): not found" } } catch { Write-StatusDot 'WARN' 'WARN' "$($c.n): not found" }
    }
    Write-Host "`n  Network:" -ForegroundColor Yellow
    try { $null = [System.Net.Dns]::GetHostEntry('devtunnels.ms'); Write-StatusDot 'OK' 'OK' 'DNS devtunnels.ms OK' } catch { Write-StatusDot 'ERR' 'ERR' 'DNS devtunnels.ms NOT RESOLVABLE' }
    try { $h = Invoke-WebRequest -Uri 'https://devtunnels.ms' -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue; if ($h.StatusCode -eq 200) { Write-StatusDot 'OK' 'OK' 'Connection devtunnels.ms OK' } } catch { Write-StatusDot 'ERR' 'ERR' 'Connection devtunnels.ms FAILED' }
    Write-Host "`n  ACP Registry: $(if (Test-Path $Script:RegistryCacheFile) { 'Cached' } else { 'Not downloaded' })" -ForegroundColor White
    Write-Host "`n  Run: .\acp-manager.ps1 -Action Scan for full scan." -ForegroundColor Cyan
}

function Action-Autostart {
    $taskName = 'ACP-Manager'; $scriptPath = (Get-Item $PSCommandPath).FullName
    Write-Section "Windows Auto-Start"; Write-Host "  Task: $taskName" -ForegroundColor DarkGray; Write-Host "  Script: $scriptPath`n" -ForegroundColor DarkGray
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($Disable) { if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-StatusDot 'OK' 'OK' 'Auto-start removed' } else { Write-StatusDot 'INFO' 'INFO' 'No auto-start configured' }; return }
    if ($existing) { Write-StatusDot 'INFO' 'INFO' 'Auto-start already configured'; $r = Read-Host "Remove it? (y/N)"; if ($r -eq 'y' -or $r -eq 's') { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-StatusDot 'OK' 'OK' 'Removed' } else { Write-StatusDot 'INFO' 'INFO' 'Kept' }; return }
    $autostartBridge = if ($Bridge -eq 'all') { 'opencode' } else { $Bridge }
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Action Start -Bridge $autostartBridge"
        $trigger = New-ScheduledTaskTrigger -AtLogOn; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "ACP Manager - $autostartBridge" -Force
        Write-StatusDot 'OK' 'OK' "Auto-start configured for $autostartBridge"
    } catch { Write-StatusDot 'ERR' 'ERR' "Registration failed: $_"; Write-Host "  Run PowerShell as Administrator." -ForegroundColor Yellow }
}

function Action-Mobile {
    Write-Section "Mobile Integration"
    $mobileCfg = Get-Config; $anonMode = $Anonymous -or ($mobileCfg -and $mobileCfg.profiles.$Profile.anonymous_tunnel -eq $true)
    Write-Host @"
  To connect from mobile to ACP bridge:

  1. Install an ACP app (e.g. Agmente on iOS)
  2. Start bridge + tunnel:
     .\acp-manager.ps1 -Action Tunnel -Bridge $Bridge
  3. Use the remote URL shown in the app

  Access: $(if ($anonMode) { 'ANONYMOUS' } else { 'AUTHENTICATED (Microsoft/GitHub)' })
"@
    $tid = $TunnelId; if (-not $tid -and $mobileCfg) { $tid = $mobileCfg.profiles.$Profile.tunnel_id }
    if ($tid) { Write-Host "`n  Persistent tunnel: $tid" -ForegroundColor Cyan }
    Write-Host "`n  Examples:" -ForegroundColor White
    Write-Host "    .\acp-manager.ps1 -Action Tunnel -Bridge opencode" -ForegroundColor White
    Write-Host "    .\acp-manager.ps1 -Action Tunnel -Bridge kilocode`n" -ForegroundColor White
}

# ============================================================
# HELP
# ============================================================

function Format-HelpAction { param([string]$A,[string]$D); return "    $($A.PadRight(15))$D" }

function Show-Help {
    Write-Host @"

  ============================================================
    ACP Manager v$($Script:Version)
    Bridge Management + Agent Detection Engine
  ============================================================

  INTERACTIVE MODE:
$(Format-HelpAction 'Interactive'  'Launch interactive menu (default when no args)')

  DETECTION:
$(Format-HelpAction 'Scan'          'Scan 37+ ACP agents (installed, running, working)')
$(Format-HelpAction 'AgentInfo'     'Detailed info on an agent (-AgentId)')
$(Format-HelpAction 'Registry'      'Show/update official ACP registry')
$(Format-HelpAction 'InstallAgent'  'Install an ACP agent from registry (-AgentId)')
$(Format-HelpAction 'Update'        'Update ACP agents (-AgentId name | all)')

  BRIDGE MANAGEMENT:
$(Format-HelpAction 'Status'      'Bridge status + detected agents')
$(Format-HelpAction 'Install'     'Install ACP bridges (opencode, kilocode, cursor)')
$(Format-HelpAction 'Start'       'Start bridge in background')
$(Format-HelpAction 'Stop'        'Stop bridge')
$(Format-HelpAction 'Restart'     'Restart bridge')
$(Format-HelpAction 'Init'        'Guided initial setup')

  DEV TUNNEL:
$(Format-HelpAction 'Tunnel'      'Bridge + remote tunnel')
$(Format-HelpAction 'TunnelCreate' 'Create persistent tunnel')
$(Format-HelpAction 'TunnelList'  'List tunnels')
$(Format-HelpAction 'TunnelInfo'  'Tunnel details')
$(Format-HelpAction 'TunnelDelete''Delete tunnel')

  SYSTEM:
$(Format-HelpAction 'Config'      'Show configuration')
$(Format-HelpAction 'Diag'        'System diagnostics')
$(Format-HelpAction 'Logs'        'Show logs (-LogLines N)')
$(Format-HelpAction 'LogClear'    'Clear logs')
$(Format-HelpAction 'Autostart'   'Windows auto-start (-Disable to remove)')
$(Format-HelpAction 'Mobile'      'Mobile integration guide')
$(Format-HelpAction 'Help'        'This help screen')

  PARAMETERS:
    -Action        Init | Install | InstallAgent | Start | Stop | Restart | Update |
                   Status | Scan | AgentInfo | Registry | Interactive | Help |
                   Tunnel | TunnelCreate | TunnelList | TunnelInfo | TunnelDelete |
                   Logs | LogClear | Config | Diag | Autostart | Mobile | Watch
    -AgentId       Registry agent ID (e.g. gemini, claude-acp, devin)
    -Bridge        opencode | kilocode | cursor | all
    -Port          Custom port
    -TunnelId      DevTunnel ID
    -OutputFormat  Text | Json
    -Profile       Config profile
    -LogLines      Log lines (default: 50)
    -Anonymous     Anonymous tunnel (switch)
    -Detailed      Detailed output (switch)
    -UpdateRegistry Force registry update (switch)
    -Disable       Disable auto-start (switch)

  EXAMPLES:
    .\acp-manager.ps1                        # Interactive mode
    .\acp-manager.ps1 -Action Scan
    .\acp-manager.ps1 -Action Scan -Detailed
    .\acp-manager.ps1 -Action Scan -OutputFormat Json
    .\acp-manager.ps1 -Action AgentInfo -AgentId gemini
    .\acp-manager.ps1 -Action InstallAgent -AgentId gemini
    .\acp-manager.ps1 -Action Registry
    .\acp-manager.ps1 -Action Update -AgentId all
    .\acp-manager.ps1 -Action Install -Bridge all
    .\acp-manager.ps1 -Action Tunnel -Bridge kilocode -Anonymous
    .\acp-manager.ps1 -Action Status
    .\acp-manager.ps1 -Action Diag
    .\acp-manager.ps1 -Action Autostart -Bridge opencode

"@
}


# ============================================================
# ENHANCEMENTS: Progress, Caching, Detection+, Watch
# ============================================================

# ---- Write-Progress Wrapper ----
function Write-ScanProgress {
    param([int]$Current, [int]$Total, [string]$AgentName)
    $pct = [int]($Current / $Total * 100)
    Write-Progress -Activity "Scanning ACP agents" -Status "$AgentName ($Current/$Total)" -PercentComplete $pct
}
function Clear-ScanProgress { Write-Progress -Activity "Scanning ACP agents" -Completed }

# ---- Caching System ----
$Script:NpmCache = $null; $Script:CargoCache = $null; $Script:WingetCache = $null
$Script:PipCache = $null; $Script:UvxCache = $null; $Script:ChocoCache = $null
$Script:ScoopCache = $null; $Script:DotnetCache = $null; $Script:GoBinCache = $null
$Script:CacheTime = @{}
function Get-CachedNpmList {
    $now = Get-Date
    if ($Script:NpmCache -and $Script:CacheTime.Npm -and (($now - $Script:CacheTime.Npm).TotalSeconds -lt 120)) { return $Script:NpmCache }
    try { $Script:NpmCache = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json; $Script:CacheTime.Npm = $now } catch { $Script:NpmCache = $null }
    return $Script:NpmCache
}
function Get-CachedCargoList {
    $now = Get-Date
    if ($Script:CargoCache -and $Script:CacheTime.Cargo -and (($now - $Script:CacheTime.Cargo).TotalSeconds -lt 120)) { return $Script:CargoCache }
    try { $Script:CargoCache = cargo install --list 2>$null; $Script:CacheTime.Cargo = $now } catch { $Script:CargoCache = $null }
    return $Script:CargoCache
}
function Get-CachedWingetList {
    $now = Get-Date
    if ($Script:WingetCache -and $Script:CacheTime.Winget -and (($now - $Script:CacheTime.Winget).TotalMinutes -lt 30)) { return $Script:WingetCache }
    try { $Script:WingetCache = winget list --accept-source-agreements 2>$null; $Script:CacheTime.Winget = $now } catch { $Script:WingetCache = $null }
    return $Script:WingetCache
}
function Get-CachedPipList {
    $now = Get-Date
    if ($Script:PipCache -and $Script:CacheTime.Pip -and (($now - $Script:CacheTime.Pip).TotalSeconds -lt 120)) { return $Script:PipCache }
    try { $Script:PipCache = pip list --format=json 2>$null | ConvertFrom-Json; $Script:CacheTime.Pip = $now } catch { $Script:PipCache = $null }
    return $Script:PipCache
}
function Get-CachedUvxList {
    $now = Get-Date
    if ($Script:UvxCache -and $Script:CacheTime.Uvx -and (($now - $Script:CacheTime.Uvx).TotalSeconds -lt 120)) { return $Script:UvxCache }
    try { $Script:UvxCache = uv tool list 2>$null; $Script:CacheTime.Uvx = $now } catch { $Script:UvxCache = $null }
    return $Script:UvxCache
}
function Get-CachedChocoList {
    $now = Get-Date
    if ($Script:ChocoCache -and $Script:CacheTime.Choco -and (($now - $Script:CacheTime.Choco).TotalSeconds -lt 120)) { return $Script:ChocoCache }
    try { $Script:ChocoCache = choco list -li --limit-output 2>$null; $Script:CacheTime.Choco = $now } catch { $Script:ChocoCache = $null }
    return $Script:ChocoCache
}
function Get-CachedScoopList {
    $now = Get-Date
    if ($Script:ScoopCache -and $Script:CacheTime.Scoop -and (($now - $Script:CacheTime.Scoop).TotalSeconds -lt 120)) { return $Script:ScoopCache }
    try { $Script:ScoopCache = scoop list 2>$null; $Script:CacheTime.Scoop = $now } catch { $Script:ScoopCache = $null }
    return $Script:ScoopCache
}
function Get-CachedDotnetList {
    $now = Get-Date
    if ($Script:DotnetCache -and $Script:CacheTime.Dotnet -and (($now - $Script:CacheTime.Dotnet).TotalSeconds -lt 120)) { return $Script:DotnetCache }
    try { $Script:DotnetCache = dotnet tool list -g 2>$null; $Script:CacheTime.Dotnet = $now } catch { $Script:DotnetCache = $null }
    return $Script:DotnetCache
}
function Get-CachedGoBin {
    $now = Get-Date
    if ($Script:GoBinCache -and $Script:CacheTime.GoBin -and (($now - $Script:CacheTime.GoBin).TotalSeconds -lt 120)) { return $Script:GoBinCache }
    try {
        $bin = go env GOBIN 2>$null
        if (-not $bin) { $gp = go env GOPATH 2>$null; if ($gp) { $bin = Join-Path $gp 'bin' } }
        if ($bin -and (Test-Path $bin)) { $Script:GoBinCache = @(Get-ChildItem $bin -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
        else { $Script:GoBinCache = @() }
        $Script:CacheTime.GoBin = $now
    } catch { $Script:GoBinCache = @() }
    return $Script:GoBinCache
}

# ---- Expanded Detection Methods ----

# Word-boundary, case-insensitive token match. Prevents short ids such as
# 'go', 'uv', 'n8n' from matching 'good', 'uvue', 'xn8n2'.
function Test-IdMatch {
    param([string]$Token, [string]$Text)
    if (-not $Token -or -not $Text) { return $false }
    $pattern = '(?i)(?<![a-z0-9])' + [regex]::Escape($Token) + '(?![a-z0-9])'
    return [bool]($Text -match $pattern)
}
function Test-AgentPip { param([string]$Id, [string]$Pkg)
    if (-not (Test-Cmd 'pip')) { return $null }
    try {
        $list = Get-CachedPipList
        if ($list) { $f = $list | Where-Object { $_.name -eq $Pkg -or $_.name -eq $Id -or (Test-IdMatch -Token $Pkg -Text $_.name) } | Select-Object -First 1; if ($f) { return @{Installed=$true;Version=$f.version;Method='pip';Detail="pip: $($f.name) $($f.version)"} } }
    } catch {}; return $null }
function Test-AgentUvx { param([string]$Id, [string]$Pkg)
    if (-not (Test-Cmd 'uv')) { return $null }
    try {
        $list = Get-CachedUvxList
        if ($list) {
            foreach ($line in $list) {
                $pkgToken = (($line -replace '^\s+','') -split '\s+' | Select-Object -First 1)
                if ((Test-IdMatch -Token $Pkg -Text $pkgToken) -or (Test-IdMatch -Token $Id -Text $pkgToken)) { return @{Installed=$true;Version='';Method='uvx';Detail="uv tool: $pkgToken"} }
            }
        }
    } catch {}; return $null }
function Test-AgentWinget { param([string]$Id)
    if (-not (Test-Cmd 'winget')) { return $null }
    try { $list = Get-CachedWingetList; if ($list) { $hit = $list | Where-Object { Test-IdMatch -Token $Id -Text $_ } | Select-Object -First 1; if ($hit) { return @{Installed=$true;Version='';Method='winget';Detail="winget: $Id"} } } } catch {}; return $null }
function Test-AgentChoco { param([string]$Id)
    if (-not (Test-Cmd 'choco')) { return $null }
    try {
        $list = Get-CachedChocoList
        if ($list) {
            foreach ($line in $list) { $nameToken = ($line -split '\|')[0]; if (Test-IdMatch -Token $Id -Text $nameToken) { return @{Installed=$true;Version='';Method='choco';Detail="choco: $nameToken"} } }
        }
    } catch {}; return $null }
function Test-AgentScoop { param([string]$Id)
    if (-not (Test-Cmd 'scoop')) { return $null }
    try { $list = Get-CachedScoopList; if ($list) { $hit = $list | Where-Object { Test-IdMatch -Token $Id -Text $_ } | Select-Object -First 1; if ($hit) { return @{Installed=$true;Version='';Method='scoop';Detail="scoop: $Id"} } } } catch {}; return $null }
function Test-AgentDotnet { param([string]$Id)
    if (-not (Test-Cmd 'dotnet')) { return $null }
    try { $list = Get-CachedDotnetList; if ($list) { $hit = $list | Where-Object { Test-IdMatch -Token $Id -Text $_ } | Select-Object -First 1; if ($hit) { return @{Installed=$true;Version='';Method='dotnet';Detail="dotnet tool: $Id"} } } } catch {}; return $null }
function Test-AgentGo { param([string]$Name)
    if (-not (Test-Cmd 'go')) { return $null }
    try {
        $bins = Get-CachedGoBin
        if ($bins) {
            $f = $bins | Where-Object { $base = $_ -replace '\.exe$',''; ($base -eq $Name) -or (Test-IdMatch -Token $Name -Text $base) } | Select-Object -First 1
            if ($f) { return @{Installed=$true;Version='';Method='go';Detail="go: $f"} }
        }
    } catch {}; return $null }

# ---- Version Comparison ----
function Compare-AgentVersions {
    param([string]$L, [string]$R)
    if (-not $L -or -not $R) { return 'unknown' }
    try { $lv = [System.Version]($L -replace '[^0-9.]',''); $rv = [System.Version]($R -replace '[^0-9.]',''); if ($lv -lt $rv) { return 'outdated' }; if ($lv -gt $rv) { return 'newer' }; return 'current' } catch { return 'unknown' }
}

# ---- Enhanced Detection Wrapper ----
function Get-EnhancedDetection {
    param([object]$Agent, [switch]$DeepScan)
    $det = Get-AgentDetection -Agent $Agent -DeepScan:$DeepScan
    if (-not $det.Installed) {
        $id = $Agent.id; $pkgName = $id
        if ($Agent.distribution.npx) { $pkgName = ($Agent.distribution.npx.package -split '@')[0] }
        elseif ($Agent.distribution.uvx) { $pkgName = ($Agent.distribution.uvx.package -split '==')[0] }
        $methods = @({Test-AgentPip -Id $id -Pkg $pkgName},{Test-AgentUvx -Id $id -Pkg $pkgName},{Test-AgentWinget -Id $id},{Test-AgentChoco -Id $id},{Test-AgentScoop -Id $id},{Test-AgentDotnet -Id $id},{Test-AgentGo -Name $Agent.name})
        foreach ($m in $methods) { $r = & $m; if ($r -and $r.Installed) { $det.Installed=$true; $det.InstallMethod=$r.Method; $det.InstallDetail=$r.Detail; if ($r.Version) { $det.InstalledVersion=$r.Version }; break } }
    }
    $det.VersionStatus = if ($det.Installed -and $det.InstalledVersion) { Compare-AgentVersions -L $det.InstalledVersion -R $Agent.version } else { 'unknown' }
    return $det
}

# ---- UPDATE AGENT ----
function Get-UpdateCommand {
    param([object]$Agent, [string]$InstallMethod, [string]$InstallDetail)

    $id = $Agent.id
    $pkg = $id
    $module = $id

    # Extract package name from registry distribution
    if ($Agent.distribution.npx) { $pkg = ($Agent.distribution.npx.package -split '@')[0] }
    elseif ($Agent.distribution.uvx) { $pkg = ($Agent.distribution.uvx.package -split '==')[0] }

    # Extract binary paths for re-download
    $binaryCmd = $null
    if ($Agent.distribution.binary) {
        foreach ($arch in @('windows-x86_64','windows-aarch64')) {
            if ($Agent.distribution.binary.$arch) {
                $binaryCmd = $Agent.distribution.binary.$arch.cmd
                $uri = $Agent.distribution.binary.$arch.uri
                break
            }
        }
    }

    switch ($InstallMethod) {
        'npm' {
            $nameParts = $Agent.distribution.npx.package -split '@'
            $npmPkg = $nameParts[0]
            return @{ Cmd = "npm install -g $npmPkg@latest 2>&1"; Label = "npm: $npmPkg" }
        }
        'cargo' {
            return @{ Cmd = "cargo install $id --force 2>&1"; Label = "cargo: $id" }
        }
        'pip' {
            return @{ Cmd = "pip install --upgrade $pkg 2>&1"; Label = "pip: $pkg" }
        }
        'uvx' {
            return @{ Cmd = "uv tool install --upgrade $pkg 2>&1"; Label = "uvx: $pkg" }
        }
        'winget' {
            return @{ Cmd = "winget upgrade $id --accept-package-agreements --accept-source-agreements 2>&1"; Label = "winget: $id" }
        }
        'choco' {
            return @{ Cmd = "choco upgrade $id -y 2>&1"; Label = "choco: $id" }
        }
        'scoop' {
            return @{ Cmd = "scoop update $id 2>&1"; Label = "scoop: $id" }
        }
        'dotnet' {
            return @{ Cmd = "dotnet tool update -g $pkg 2>&1"; Label = "dotnet: $pkg" }
        }
        'go' {
            $moduleName = if ($Agent.distribution.uvx -or $Agent.distribution.npx) { $pkg } else { "github.com/${id}/${id}@latest" }
            return @{ Cmd = "go install ${moduleName}@latest 2>&1"; Label = "go: $moduleName" }
        }
        'KnownPath' {
            # Try to infer update method from registry
            if ($Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                return @{ Cmd = "npm install -g $npmPkg@latest 2>&1"; Label = "npm: $npmPkg" }
            }
            elseif ($Agent.distribution.uvx) {
                return @{ Cmd = "uv tool install --upgrade $pkg 2>&1"; Label = "uvx: $pkg" }
            }
            elseif ($binaryCmd) {
                # Re-download binary to known path
                $destName = ($binaryCmd -replace '^\\.\\', '') -split '[/\\]' | Select-Object -Last 1
                $destDir = Split-Path $InstallDetail -Parent
                $tmpFile = Join-Path $env:TEMP "update-${id}-$([System.IO.Path]::GetRandomFileName()).exe"
                return @{ Cmd = @"
`$tmp = '$tmpFile'
Invoke-WebRequest -Uri '$uri' -OutFile `$tmp -UseBasicParsing
Move-Item `$tmp '$destDir\$destName' -Force
"@; Label = "binary: $destName"; IsScript = $true }
            }
            return @{ Cmd = "winget upgrade $id --accept-package-agreements --accept-source-agreements 2>&1"; Label = "winget: $id"; Fallback = $true }
        }
        'PATH' {
            # Maybe the tool has a --version to verify but we need npm/cargo/etc.
            if ($Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                return @{ Cmd = "npm install -g $npmPkg@latest 2>&1"; Label = "npm: $npmPkg" }
            }
            elseif ($Agent.distribution.uvx) {
                return @{ Cmd = "uv tool install --upgrade $pkg 2>&1"; Label = "uvx: $pkg" }
            }
            return @{ Cmd = $null; Label = "$InstallMethod (manual)" }
        }
        default {
            # Registry install method or unknown
            if ($Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                return @{ Cmd = "npm install -g $npmPkg@latest 2>&1"; Label = "npm: $npmPkg" }
            }
            return @{ Cmd = $null; Label = "$InstallMethod (manual)" }
        }
    }
}

function Update-Agent {
    param([object]$Agent, [switch]$Quiet)

    $id = $Agent.id; $name = $Agent.name
    $det = Get-EnhancedDetection -Agent $Agent

    if (-not $det.Installed) {
        if (-not $Quiet) { Write-StatusDot 'STOP' 'STOP' "$name not installed" }
        return $false
    }

    $updCmd = Get-UpdateCommand -Agent $Agent -InstallMethod $det.InstallMethod -InstallDetail $det.InstallDetail

    if (-not $updCmd.Cmd) {
        if (-not $Quiet) {
            Write-StatusDot 'WARN' 'WARN' "${name}: auto-update not supported for $($det.InstallMethod)"
            Write-Host "    Visit: $($Agent.website)" -ForegroundColor Blue
        }
        # Try fallback: winget or npm
        return $false
    }

    $oldVer = $det.InstalledVersion
    Write-Log "Updating $name ($($updCmd.Label))..." -Level INFO
    if (-not $Quiet) { Write-Host "  >> $($updCmd.Label)" -ForegroundColor DarkGray }

    try {
        if ($updCmd.IsScript) {
            # Execute multi-line script (binary download)
            $sb = [ScriptBlock]::Create($updCmd.Cmd)
            & $sb 2>&1 | Out-Null
        } else {
            $r = Invoke-Expression $updCmd.Cmd 2>&1
        }

        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            # Re-detect to get new version
            Start-Sleep -Seconds 1
            $det2 = Get-EnhancedDetection -Agent $Agent
            $newVer = $det2.InstalledVersion
            if ($newVer -and $newVer -ne $oldVer) {
                Write-StatusDot 'OK' 'OK' "${name}: $oldVer -> $newVer ($($updCmd.Label))"
                Write-Log "$name updated: $oldVer -> $newVer" -Level OK
            } else {
                Write-StatusDot 'OK' 'OK' "${name}: $newVer ($($updCmd.Label))"
                Write-Log "$name updated" -Level OK
            }
            return $true
        } else {
            $errMsg = if ($r) { "$r".Trim().Split("`n")[0] } else { "exit code $LASTEXITCODE" }
            if (-not $Quiet) { Write-StatusDot 'ERR' 'ERR' "${name}: $errMsg" }
        Write-Log "Update error ${name}: $errMsg" -Level ERROR

        # Try fallback: npm install if original method was PATH/KnownPath
            if ($updCmd.Fallback -and $Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                if (-not $Quiet) { Write-Host "    Falling back to: npm install -g $npmPkg@latest" -ForegroundColor Yellow }
                try {
                    $r2 = npm install -g $npmPkg@latest 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "${name}: updated via npm"; return $true }
                } catch {}
            }
            return $false
        }
    } catch {
        $errMsg = "$_".Trim().Split("`n")[0]
        if (-not $Quiet) { Write-StatusDot 'ERR' 'ERR' "${name}: $errMsg" }
        Write-Log "Update error ${name}: $errMsg" -Level ERROR
        return $false
    }
}

function Action-Update {
    Write-Section "Updating ACP Agents"

    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry not available'; return }

    # Determine which agents to update
    $targets = @()

    if ($AgentId) {
        if ($AgentId -eq 'all') {
            # Update ALL installed agents
            $targets = $reg.agents
        } else {
            $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
            if (-not $agent) { Write-StatusDot 'ERR' 'ERR' "Agent '$AgentId' not found"; return }
            $targets = @($agent)
        }
    } elseif ($Bridge -ne 'all') {
        # Update a specific bridge
        $agent = $reg.agents | Where-Object { $_.id -eq $Bridge } | Select-Object -First 1
        if ($agent) { $targets = @($agent) } else { Write-StatusDot 'ERR' 'ERR' "Bridge '$Bridge' not found in registry"; return }
    } else {
        # Default: update all installed
        $targets = $reg.agents
    }

    # First pass: detect which are installed
    Write-Host "  Detecting installed agents..." -ForegroundColor DarkGray
    $installed = @()
    $count = 0
    foreach ($a in $targets) {
        $count++
        Write-ScanProgress -Current $count -Total $targets.Count -AgentName $a.name
        $det = Get-EnhancedDetection -Agent $a
        if ($det.Installed) {
            $installed += [PSCustomObject]@{ Agent = $a; Detection = $det }
        }
    }
    Clear-ScanProgress

    if ($installed.Count -eq 0) {
        Write-StatusDot 'INFO' 'INFO' 'No installed agents to update'
        return
    }

    Write-Host "  Found $($installed.Count) agents to update`n" -ForegroundColor Cyan

    # Show summary table
    $summary = $installed | ForEach-Object {
        $a = $_.Agent; $d = $_.Detection
        [PSCustomObject]@{
            Agent = $a.name; Version = if ($d.InstalledVersion) { $d.InstalledVersion.Substring(0, [Math]::Min(16, $d.InstalledVersion.Length)) } else { '-' }
            Registry = $a.version; Method = $d.InstallMethod
        }
    }
    Write-Table -Data $summary -Properties @('Agent','Version','Registry','Method') -Headers @('Agent','Local Version','Registry Version','Method')

    # Confirm unless -AgentId specified a single agent
    if ($installed.Count -gt 1) {
        Write-Host "`n"
        $confirm = Read-Host "Update all $($installed.Count) agents? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y' -and $confirm -ne 's' -and $confirm -ne 'S') { Write-Log "Update cancelled." -Level INFO; return }
    }

    Write-Host "`n"

    # Execute updates
    $success = 0; $failed = 0
    $totalTime = Measure-Command {
        $count = 0
        foreach ($item in $installed) {
            $count++
            $a = $item.Agent; $d = $item.Detection
            Write-Progress -Activity "Updating ACP agents" -Status "$($a.name) ($count/$($installed.Count))" -PercentComplete ([int]($count / $installed.Count * 100))
            Write-Host "  [$count/$($installed.Count)] " -NoNewline -ForegroundColor DarkGray
            if (Update-Agent -Agent $a) { $success++ } else { $failed++ }
        }
    }
    Write-Progress -Activity "Updating ACP agents" -Completed

    Write-Host "`n"
    Write-Section "Update Summary" "Green"
    Write-Host "  Succeeded: $success" -ForegroundColor Green
    Write-Host "  Failed:    $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'DarkGray' })
    Write-Host "  Time:      $([Math]::Round($totalTime.TotalSeconds,1))s" -ForegroundColor DarkGray
    if ($failed -gt 0) {
        Write-Host "`n  For manual updates, visit the agent's website." -ForegroundColor Yellow
    }
}

# ============================================================
# ACTION: INSTALLAGENT (from ACP Registry)
# ============================================================

function Action-InstallAgent {
    Write-Section "Installing ACP Agent from Registry"
    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry not available. Use -UpdateRegistry to download'; return }

    # List available agents if no -AgentId specified
    if (-not $AgentId) {
        Write-Host "  Use -AgentId to specify an agent. Available:`n" -ForegroundColor Yellow
        $rows = @()
        foreach ($a in $reg.agents) {
            $dt = @(); if ($a.distribution.npx) { $dt += 'npx' }; if ($a.distribution.uvx) { $dt += 'uvx' }
            if ($a.distribution.binary) { $dt += 'binary' }; if ($a.distribution.cargo) { $dt += 'cargo' }
            $rows += [PSCustomObject]@{ ID=$a.id; Name=$a.name; Version=$a.version; Install=($dt -join ', ') }
        }
        Write-Table -Data $rows -Properties @('ID','Name','Version','Install') -Headers @('ID','Name','Version','Install Methods')
        Write-Host "`n  Example: .\acp-manager.ps1 -Action InstallAgent -AgentId gemini`n" -ForegroundColor Cyan
        return
    }

    # Look up agent in registry
    $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
    if (-not $agent) {
        Write-StatusDot 'ERR' 'ERR' "Agent '$AgentId' not found in registry"
        Write-Host "  Use .\acp-manager.ps1 -Action Registry to see all agents." -ForegroundColor Yellow
        return
    }

    $name = $agent.name; $id = $agent.id; $ver = $agent.version

    # Check if already installed
    $det = Get-EnhancedDetection -Agent $agent
    if ($det.Installed) {
        $v = if ($det.InstalledVersion) { $det.InstalledVersion } else { '?' }
        Write-StatusDot 'OK' 'OK' "$name already installed ($v) via $($det.InstallMethod)"
        $r = Read-Host "  Reinstall/update it? (y/N)"
        if ($r -ne 'y' -and $r -ne 'Y' -and $r -ne 's' -and $r -ne 'S') { Write-Log "Install cancelled." -Level INFO; return }
        Write-Host ""
    } else {
        Write-StatusDot 'INFO' 'INFO' "$name ($id) v$ver - not installed"
    }

    # Determine available install methods
    $methods = @()
    if ($agent.distribution.npx) {
        $pkg = $agent.distribution.npx.package
        $npmPkg = ($pkg -split '@')[0]
        $methods += @{ Method='npx'; Cmd="npm install -g $npmPkg@latest 2>&1"; Label="npm install -g $npmPkg@latest"; Req='npm'; Priority=1 }
    }
    if ($agent.distribution.binary) {
        foreach ($arch in @('windows-x86_64','windows-aarch64')) {
            if ($agent.distribution.binary.$arch) {
                $binary = $agent.distribution.binary.$arch
                $uri = $binary.uri; $cmd = $binary.cmd
                $destName = ($cmd -replace '^\\./', '' -replace '^\\.\\\\', '') -split '[/\\]' | Select-Object -Last 1
                $methods += @{ Method='binary'; Cmd="binary:$uri"; Label="download binary ($destName)"; Req=$null; Priority=2 }
                break
            }
        }
    }
    if ($agent.distribution.uvx) {
        $pkg = ($agent.distribution.uvx.package -split '==')[0]
        $methods += @{ Method='uvx'; Cmd="uv tool install $pkg 2>&1"; Label="uv tool install $pkg"; Req='uv'; Priority=3 }
    }
    if ($agent.distribution.cargo) {
        $methods += @{ Method='cargo'; Cmd="cargo install $id 2>&1"; Label="cargo install $id"; Req='cargo'; Priority=4 }
    }

    if ($methods.Count -eq 0) {
        Write-StatusDot 'ERR' 'ERR' "No install methods available for $name in registry"
        if ($agent.website) { Write-Host "    Visit: $($agent.website)" -ForegroundColor Blue }
        return
    }

    # Show available methods
    Write-Host "  Available install methods:`n" -ForegroundColor Yellow
    $methodTable = $methods | Sort-Object Priority | ForEach-Object {
        $ok = if (-not $_.Req -or (Test-Cmd $_.Req)) { 'OK' } else { 'NO' }
        [PSCustomObject]@{ Priority=$_.Priority; Method=$_.Method; Command=$_.Label; Prereq="$($_.Req) [$ok]" }
    }
    Write-Table -Data $methodTable -Properties @('Priority','Method','Command','Prereq') -Headers @('#','Method','Command','Prerequisite')

    # Pick best method: try best available that has prereqs
    $chosen = $null
    foreach ($m in ($methods | Sort-Object Priority)) {
        if (-not $m.Req -or (Test-Cmd $m.Req)) { $chosen = $m; break }
    }
    if (-not $chosen) {
        Write-StatusDot 'ERR' 'ERR' "No prerequisites available to install $name"
        Write-Host "    Need: $($methods.Req -join ', ')" -ForegroundColor Yellow
        return
    }

    # Confirm
    Write-Host "`n"
    Write-Host "  Chosen method: $($chosen.Label)" -ForegroundColor Cyan
    $r = Read-Host "  Install $name? (y/N)"
    if ($r -ne 'y' -and $r -ne 'Y' -and $r -ne 's' -and $r -ne 'S') { Write-Log "Install cancelled." -Level INFO; return }
    Write-Host ""

    # Execute installation
    $success = $false
    try {
        Write-Log "Installing $name via $($chosen.Method)..." -Level INFO
        Write-Host "  >> $($chosen.Label)" -ForegroundColor DarkGray

        if ($chosen.Method -eq 'binary') {
            # Binary download: download to temp, move to destination
            $destDir = "$env:LOCALAPPDATA\ACP-Binaries\$id"
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            $tmpFile = Join-Path $env:TEMP "install-${id}-$([System.IO.Path]::GetRandomFileName()).exe"
            $uriToUse = $uri
            Invoke-WebRequest -Uri $uriToUse -OutFile $tmpFile -UseBasicParsing -TimeoutSec 60
            Move-Item $tmpFile "$destDir\$destName" -Force
            # Add to PATH if not already there
            $p = [Environment]::GetEnvironmentVariable('PATH','User')
            if ($p -notlike "*$destDir*") {
                [Environment]::SetEnvironmentVariable('PATH', "$p;$destDir", 'User')
                $env:PATH += ";$destDir"
            }
            Write-StatusDot 'OK' 'OK' "$name installed to $destDir"
            $success = $true
        } else {
            $r = Invoke-Expression $chosen.Cmd 2>&1
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
                Write-StatusDot 'OK' 'OK' "$name installed ($($chosen.Label))"
                Write-Log "$name installed successfully" -Level OK
                $success = $true
            } else {
                $errMsg = if ($r) { "$r".Trim().Split("`n")[0] } else { "exit code $LASTEXITCODE" }
                Write-StatusDot 'ERR' 'ERR' "Install failed: $errMsg"
                Write-Log "Install $name failed: $errMsg" -Level ERROR
            }
        }
    } catch {
        Write-StatusDot 'ERR' 'ERR' "Install error: $_"
        Write-Log "Install error ${name}: $_" -Level ERROR
    }

    # Verify installation
    if ($success) {
        Start-Sleep -Seconds 2
        Write-Host "`n  Verifying installation..." -ForegroundColor DarkGray
        $det2 = Get-EnhancedDetection -Agent $agent
        if ($det2.Installed) {
            $v = if ($det2.InstalledVersion) { $det2.InstalledVersion } else { 'OK' }
            Write-StatusDot 'OK' 'OK' "$name verified ($v) via $($det2.InstallMethod)"
            if ($det2.VersionStatus -eq 'outdated') {
                Write-StatusDot 'WARN' 'WARN' "Installed version ($v) < registry ($ver). Try: .\acp-manager.ps1 -Action Update -AgentId $id"
            }
        } else {
            Write-StatusDot 'WARN' 'WARN' "$name installed but not detected. Try restarting your terminal."
        }
    }
}

# ---- WATCH MODE ----
function Action-Watch {
    param([int]$Interval = 10)
    Write-Section "Watch Mode - Ctrl+C to exit"
    Write-Host "  Refreshing every ${Interval}s" -ForegroundColor DarkGray
    Write-Host "`n"
    while ($true) {
        $savedFormat = $OutputFormat
        $OutputFormat = 'Text'
        Action-Status
        $OutputFormat = $savedFormat
        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] Next refresh in ${Interval}s... (Ctrl+C to stop)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Interval
        Clear-Host
    }
}

# ---- TAB COMPLETION ----
Register-ArgumentCompleter -CommandName '*acp-manager*','*ACP-Manager*','*acp-bridge*','*ACP-Bridges*' -ParameterName AgentId -ScriptBlock {
    param($cmd, $param, $wordToComplete, $ast, $fakeBoundParams)$cacheFile = "$env:USERPROFILE\.acp-bridges\registry-cache.json"
    if (Test-Path $cacheFile) {
        $reg = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $reg.agents | Where-Object { $_.id -like "*$wordToComplete*" -or $_.name -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.id, "$($_.id) [$($_.name)]", 'ParameterValue', "$($_.name) v$($_.version)")
        }
    }
}

Register-ArgumentCompleter -CommandName '*acp-manager*','*ACP-Manager*','*acp-bridge*','*ACP-Bridges*' -ParameterName Profile -ScriptBlock {
    param($cmd, $param, $wordToComplete, $ast, $fakeBoundParams)
    $cfgFile = "$env:USERPROFILE\.acp-bridges\config.json"
    if (Test-Path $cfgFile) {
        $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
        $cfg.profiles.PSObject.Properties.Name | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Profile: $_")
        }
    }
}


# ============================================================
# INTERACTIVE MODE
# ============================================================

function Invoke-InteractiveAction {
    param([string]$ActionName, [hashtable]$Params = @{})
    $savedAction = $Action; $savedBridge = $Bridge; $savedAgentId = $AgentId
    $savedPort = $Port; $savedTunnelId = $TunnelId; $savedAnonymous = $Anonymous; $savedDetailed = $Detailed; $savedDisable = $Disable
    $savedLogLines = $LogLines
    $script:Action = $ActionName
    if ($Params.ContainsKey('Bridge')) { $script:Bridge = $Params.Bridge }
    if ($Params.ContainsKey('AgentId')) { $script:AgentId = $Params.AgentId }
    if ($Params.ContainsKey('Port')) { $script:Port = $Params.Port }
    if ($Params.ContainsKey('TunnelId')) { $script:TunnelId = $Params.TunnelId }
    if ($Params.ContainsKey('Anonymous')) { $script:Anonymous = $Params.Anonymous }
    if ($Params.ContainsKey('Detailed')) { $script:Detailed = $Params.Detailed }
    if ($Params.ContainsKey('Disable')) { $script:Disable = $Params.Disable }
    if ($Params.ContainsKey('LogLines')) { $script:LogLines = $Params.LogLines }
    switch ($ActionName) {
        'Scan' { Action-Scan }; 'AgentInfo' { Action-AgentInfo }; 'Registry' { Action-Registry }
        'InstallAgent' { Action-InstallAgent }; 'Update' { Action-Update }
        'Install' { Action-Install }; 'Start' { Action-Start }; 'Stop' { Action-Stop }
        'Restart' { Action-Restart }; 'Status' { Action-Status }
        'Tunnel' { Action-Tunnel }; 'TunnelCreate' { Action-TunnelCreate }
        'TunnelList' { Action-TunnelList }; 'TunnelInfo' { Action-TunnelInfo }
        'TunnelDelete' { Action-TunnelDelete }
        'Config' { Action-Config }; 'Diag' { Action-Diag }; 'Logs' { Action-Logs }
        'LogClear' { Action-LogClear }; 'Autostart' { Action-Autostart }
        'Mobile' { Action-Mobile }; 'Watch' { Action-Watch }
    }
    $script:Action = $savedAction; $script:Bridge = $savedBridge; $script:AgentId = $savedAgentId
    $script:Port = $savedPort; $script:TunnelId = $savedTunnelId; $script:Anonymous = $savedAnonymous
    $script:Detailed = $savedDetailed; $script:Disable = $savedDisable; $script:LogLines = $savedLogLines
}

function Get-AgentChoice {
    $reg = Get-CachedRegistry
    if (-not $reg) { return $null }
    Write-Host "`n  Available agents:" -ForegroundColor Yellow
    $i = 1; $list = @()
    foreach ($a in $reg.agents) {
        Write-Host "  [$i] $($a.id) - $($a.name) v$($a.version)" -ForegroundColor White
        $list += $a.id; $i++
        if ($i -gt 50) { Write-Host "  ... and $($reg.agents.Count - 50) more"; break }
    }
    Write-Host "  [0/b] Back"
    $choice = Read-Host "`n  Select agent [# or ID]"
    if ($choice -eq '0' -or $choice -eq 'b' -or $choice -eq 'B' -or -not $choice) { return $null }
    if ($choice -match '^\d+$') { $num = [int]$choice; if ($num -ge 1 -and $num -le $list.Count) { return $list[$num-1] } }
    $exact = $reg.agents | Where-Object { $_.id -eq $choice } | Select-Object -First 1
    if ($exact) { return $exact.id }
    $fuzzy = $reg.agents | Where-Object { $_.id -like "*$choice*" -or $_.name -like "*$choice*" } | Select-Object -First 1
    if ($fuzzy) { return $fuzzy.id }
    Write-StatusDot 'ERR' 'ERR' "Agent '$choice' not found"; return $null
}

function Get-BridgeChoice {
    Write-Host "`n  Select bridge:" -ForegroundColor Yellow
    Write-Host "  [1] opencode" -ForegroundColor White
    Write-Host "  [2] kilocode" -ForegroundColor White
    Write-Host "  [3] cursor" -ForegroundColor White
    Write-Host "  [4] all" -ForegroundColor White
    Write-Host "  [0/b] Back"
    $choice = Read-Host "`n  Select [1-4]"
    switch ($choice) {
        '1' { return 'opencode' }; '2' { return 'kilocode' }; '3' { return 'cursor' }; '4' { return 'all' }
        '0' { return $null }
        'b' { return $null }
        'B' { return $null }
        default { return $null }
    }
}

function Get-YesNo {
    param([string]$Prompt)
    $r = Read-Host "$Prompt (y/N)"
    return ($r -eq 'y' -or $r -eq 'Y' -or $r -eq 's' -or $r -eq 'S')
}

function Press-Enter { Write-Host "`n  Press Enter to continue..." -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null }

function Show-ScanMenu {
    do {
        Clear-Host
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |         SCAN AND DETECTION               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "`n  [1] Quick Scan (installed/running only)"
        Write-Host "  [2] Detailed Scan (with health check)"
        Write-Host "  [3] Agent Info (detailed info on one agent)"
        Write-Host "  [4] Registry (show official ACP registry)"
        Write-Host "  [5] Download Registry (force update cache)"
        Write-Host "  [0/b] Back to Main Menu"
        $c = Read-Host "`n  Select [0-5]"
        switch ($c) {
            '1' { $Detailed=$false; Invoke-InteractiveAction -ActionName 'Scan'; Press-Enter }
            '2' { Invoke-InteractiveAction -ActionName 'Scan' -Params @{Detailed=$true}; Press-Enter }
            '3' { $aid = Get-AgentChoice; if ($aid) { Invoke-InteractiveAction -ActionName 'AgentInfo' -Params @{AgentId=$aid}; Press-Enter } }
            '4' { Invoke-InteractiveAction -ActionName 'Registry'; Press-Enter }
            '5' { Invoke-InteractiveAction -ActionName 'Registry' -Params @{UpdateRegistry=$true}; Press-Enter }
            '0' { return }
            'b' { return }
            'B' { return }
        }
    } while ($true)
}

function Show-InstallMenu {
    do {
        Clear-Host
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |         INSTALL AND UPDATE               |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "`n  [1] List Registry (all available agents)"
        Write-Host "  [2] Install an agent from registry"
        Write-Host "  [3] Update ALL installed agents"
        Write-Host "  [4] Update a specific agent"
        Write-Host "  [5] Install bridges (opencode/kilocode/cursor)"
        Write-Host "  [0/b] Back to Main Menu"
        $c = Read-Host "`n  Select [0-5]"
        switch ($c) {
            '1' { Invoke-InteractiveAction -ActionName 'Registry'; Press-Enter }
            '2' { $aid = Get-AgentChoice; if ($aid) { Invoke-InteractiveAction -ActionName 'InstallAgent' -Params @{AgentId=$aid}; Press-Enter } }
            '3' { Invoke-InteractiveAction -ActionName 'Update' -Params @{AgentId='all'}; Press-Enter }
            '4' { $aid = Get-AgentChoice; if ($aid) { Invoke-InteractiveAction -ActionName 'Update' -Params @{AgentId=$aid}; Press-Enter } }
            '5' { $b = Get-BridgeChoice; if ($b) { Invoke-InteractiveAction -ActionName 'Install' -Params @{Bridge=$b}; Press-Enter } }
            '0' { return }
            'b' { return }
            'B' { return }
        }
    } while ($true)
}

function Show-BridgeMenu {
    do {
        Clear-Host
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |         BRIDGE MANAGEMENT                |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "`n  [1] Status (bridges + detected agents)"
        Write-Host "  [2] Start bridge(s)"
        Write-Host "  [3] Stop bridge(s)"
        Write-Host "  [4] Restart bridge(s)"
        Write-Host "  [5] Install bridges"
        Write-Host "  [6] Initial Setup (Init)"
        Write-Host "  [0/b] Back to Main Menu"
        $c = Read-Host "`n  Select [0-6]"
        switch ($c) {
            '1' { Invoke-InteractiveAction -ActionName 'Status'; Press-Enter }
            '2' { $b = Get-BridgeChoice; if ($b) { Invoke-InteractiveAction -ActionName 'Start' -Params @{Bridge=$b}; Press-Enter } }
            '3' { $b = Get-BridgeChoice; if ($b) { Invoke-InteractiveAction -ActionName 'Stop' -Params @{Bridge=$b}; Press-Enter } }
            '4' { $b = Get-BridgeChoice; if ($b) { Invoke-InteractiveAction -ActionName 'Restart' -Params @{Bridge=$b}; Press-Enter } }
            '5' { $b = Get-BridgeChoice; if ($b) { Invoke-InteractiveAction -ActionName 'Install' -Params @{Bridge=$b}; Press-Enter } }
            '6' { Invoke-InteractiveAction -ActionName 'Init'; Press-Enter }
            '0' { return }
            'b' { return }
            'B' { return }
        }
    } while ($true)
}

function Show-TunnelMenu {
    do {
        Clear-Host
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |         DEV TUNNEL                      |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "`n  [1] Tunnel + Bridge (start tunnel + bridge)"
        Write-Host "  [2] Create Persistent Tunnel"
        Write-Host "  [3] List Tunnels"
        Write-Host "  [4] Tunnel Info"
        Write-Host "  [5] Delete Tunnel"
        Write-Host "  [0/b] Back to Main Menu"
        $c = Read-Host "`n  Select [0-5]"
        switch ($c) {
            '1' { $b = Get-BridgeChoice; if ($b -and $b -ne 'all') {
                    $anon = Get-YesNo "  Use anonymous tunnel?"
                    Invoke-InteractiveAction -ActionName 'Tunnel' -Params @{Bridge=$b; Anonymous=$anon}
                    Press-Enter
                } elseif ($b -eq 'all') { Write-StatusDot 'WARN' 'WARN' 'Tunnel requires a specific bridge (not all)'; Start-Sleep 2 } }
            '2' { $anon = Get-YesNo "  Anonymous tunnel?"
                  Invoke-InteractiveAction -ActionName 'TunnelCreate' -Params @{Anonymous=$anon}; Press-Enter }
            '3' { Invoke-InteractiveAction -ActionName 'TunnelList'; Press-Enter }
            '4' { $tid = Read-Host "  Tunnel ID (Enter to auto-detect)"
                  if ($tid) { Invoke-InteractiveAction -ActionName 'TunnelInfo' -Params @{TunnelId=$tid} }
                  else { Invoke-InteractiveAction -ActionName 'TunnelInfo' }
                  Press-Enter }
            '5' { $tid = Read-Host "  Tunnel ID to delete"
                  if ($tid) { Invoke-InteractiveAction -ActionName 'TunnelDelete' -Params @{TunnelId=$tid}; Press-Enter } }
            '0' { return }
            'b' { return }
            'B' { return }
        }
    } while ($true)
}

function Show-SystemMenu {
    do {
        Clear-Host
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |         SYSTEM                           |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
        Write-Host "`n  [1] Show Configuration"
        Write-Host "  [2] System Diagnostics"
        Write-Host "  [3] Show Logs"
        Write-Host "  [4] Clear Logs"
        Write-Host "  [5] Configure Auto-start"
        Write-Host "  [6] Remove Auto-start"
        Write-Host "  [7] Mobile Integration Guide"
        Write-Host "  [8] Watch Mode (live monitoring)"
        Write-Host "  [0/b] Back to Main Menu"
        $c = Read-Host "`n  Select [0-8]"
        switch ($c) {
            '1' { Invoke-InteractiveAction -ActionName 'Config'; Press-Enter }
            '2' { Invoke-InteractiveAction -ActionName 'Diag'; Press-Enter }
            '3' { $lines = Read-Host "  Number of log lines [50]"; if (-not $lines) { $lines = 50 }
                  Invoke-InteractiveAction -ActionName 'Logs' -Params @{LogLines=[int]$lines}; Press-Enter }
            '4' { Invoke-InteractiveAction -ActionName 'LogClear'; Press-Enter }
            '5' { $b = Get-BridgeChoice; if ($b -and $b -ne 'all') {
                    Invoke-InteractiveAction -ActionName 'Autostart' -Params @{Bridge=$b}
                  } elseif ($b -eq 'all') {
                    Invoke-InteractiveAction -ActionName 'Autostart' -Params @{Bridge='opencode'}
                  }; Press-Enter }
            '6' { Invoke-InteractiveAction -ActionName 'Autostart' -Params @{Disable=$true}; Press-Enter }
            '7' { Invoke-InteractiveAction -ActionName 'Mobile'; Press-Enter }
            '8' { Invoke-InteractiveAction -ActionName 'Watch'; Press-Enter }
            '0' { return }
            'b' { return }
            'B' { return }
        }
    } while ($true)
}

function Action-Interactive {
    do {
        Clear-Host
        Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan
        Write-Host "|         ACP Manager v$($Script:Version) - Interactive          |" -ForegroundColor Cyan
        Write-Host "+-----------------------------------------------+" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] Scan and Detection    - Scan 37+ agents, agent info, registry"
        Write-Host "  [2] Install and Update    - Install/update agents from registry"
        Write-Host "  [3] Bridge Management   - Start, stop, restart, status, install"
        Write-Host "  [4] DevTunnel           - Tunnel, create, list, info, delete"
        Write-Host "  [5] System              - Config, diag, logs, autostart, mobile"
        Write-Host "  [6] Help                - Show complete help"
        Write-Host "  [7/q] Exit"
        Write-Host ""
        $choice = Read-Host "  Select [1-7]"
        switch ($choice) {
            '1' { Show-ScanMenu }
            '2' { Show-InstallMenu }
            '3' { Show-BridgeMenu }
            '4' { Show-TunnelMenu }
            '5' { Show-SystemMenu }
            '6' { Clear-Host; Show-Help; Press-Enter }
            '7' { Write-Host ''; Write-Host '  Goodbye!' -ForegroundColor Green; return }
            'q' { Write-Host ''; Write-Host '  Goodbye!' -ForegroundColor Green; return }
            'Q' { Write-Host ''; Write-Host '  Goodbye!' -ForegroundColor Green; return }
        }
    } while ($true)
}
# ============================================================
# ACTION ROUTER
# ============================================================

$null = Get-Config

switch ($Action) {
    'Init'          { Action-Init }
    'Install'       { Action-Install }
    'Start'         { Action-Start }
    'Stop'          { Action-Stop }
    'Restart'       { Action-Restart }
    'Status'        { Action-Status }
    'Scan'          { Action-Scan }
    'AgentInfo'     { Action-AgentInfo }
    'Registry'      { Action-Registry }
    'Tunnel'        { Action-Tunnel }
    'TunnelCreate'  { Action-TunnelCreate }
    'TunnelList'    { Action-TunnelList }
    'TunnelInfo'    { Action-TunnelInfo }
    'TunnelDelete'  { Action-TunnelDelete }
    'Logs'          { Action-Logs }
    'LogClear'      { Action-LogClear }
    'Config'        { Action-Config }
    'Diag'          { Action-Diag }
    'Autostart'     { Action-Autostart }
    'Mobile'        { Action-Mobile }
    'InstallAgent'  { Action-InstallAgent }
    'Update'        { Action-Update }
    'Watch'         { Action-Watch }
    'Interactive'   { Action-Interactive }
    'Help'          { Show-Help }
}

