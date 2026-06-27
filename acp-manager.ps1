<#
.SYNOPSIS
    ACP Manager v4.2 - Bridge Management + Agent Detection Engine
.DESCRIPTION
    Gestione completa bridge ACP + rilevazione + installazione agenti.
    
    BRIDGE: Init, Install, Start, Stop, Restart, Status, Tunnel, Autostart
    DETECTION: Scan, AgentInfo, Registry, InstallAgent (37 agent dal registry ACP ufficiale)
    SISTEMA: Config, Diag, Logs, LogClear, Mobile, Help
.PARAMETER Action
    Azione: Init, Install, InstallAgent, Start, Stop, Restart, Status, Scan, AgentInfo,
            Registry, Tunnel, TunnelCreate, TunnelList, TunnelInfo, TunnelDelete,
            Update, Logs, LogClear, Config, Diag, Autostart, Mobile, Watch, RegistryUpdate, Help
.PARAMETER Bridge
    Bridge: opencode, kilocode, cursor, all
.PARAMETER AgentId
    ID agente dal registry ACP (es. gemini, claude-acp, devin)
.PARAMETER Port
    Porta personalizzata
.PARAMETER TunnelId
    ID DevTunnel
.PARAMETER OutputFormat
    Text | Json
.PARAMETER LogLines
    Righe log (default: 50)
.PARAMETER Profile
    Profilo config
.PARAMETER Anonymous
    Tunnel anonimo (switch)
.PARAMETER Disable
    Disabilita auto-avvio (switch)
.PARAMETER UpdateRegistry
    Forza aggiornamento registry (switch)
.PARAMETER Detailed
    Output dettagliato (switch)
#>

param(
    [ValidateSet('Init','Install','Start','Stop','Restart','Update','Status','Scan','AgentInfo','Registry','InstallAgent','Watch','RegistryUpdate',
                 'Tunnel','TunnelCreate','TunnelList','TunnelInfo','TunnelDelete',
                 'Logs','LogClear','Config','Diag','Autostart','Mobile','Help')]
    [string]$Action = 'Help',
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
# CONFIGURAZIONE
# ============================================================

$Script:Version = '4.2.0'
$Script:ConfigDir = "$env:USERPROFILE\.acp-bridges"
$Script:ConfigFile = "$Script:ConfigDir\config.json"
$Script:RegistryCacheFile = "$Script:ConfigDir\registry-cache.json"
$Script:RegistryUrl = 'https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json'
$Script:DefaultLogPath = "$env:TEMP\acp-bridges.log"
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
        $r = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet 2>$null
        return [bool]$r
    } catch { return $false }
}

# ============================================================
# CONFIGURAZIONE PERSISTENTE
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
        } catch { Write-Log "Config errato, uso default" -Level DEBUG }
    }
    return $null
}

function Save-Config {
    param($Config)
    if (-not (Test-Path $Script:ConfigDir)) {
        New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 10 | Set-Content $Script:ConfigFile -Force
    Write-Log "Config salvato: $Script:ConfigFile" -Level OK
}

function New-DefaultConfig {
    return @{
        version = '4.0'; profile = 'default'
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
    Write-Log "Download registry ACP..." -Level INFO
    try {
        $tmpFile = Join-Path $env:TEMP "acp-registry-$([System.IO.Path]::GetRandomFileName()).json"
        Invoke-WebRequest -Uri $Script:RegistryUrl -OutFile $tmpFile -UseBasicParsing -TimeoutSec 15
        if (-not (Test-Path $Script:ConfigDir)) {
            New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null
        }
        Move-Item $tmpFile $Script:RegistryCacheFile -Force
        $reg = Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json
        Write-Log "Registry aggiornato: $($reg.agents.Count) agent" -Level OK
        return $reg
    } catch {
        Write-Log "Download registry fallito: $_" -Level WARN
        if (Test-Path $Script:RegistryCacheFile) {
            $reg = Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json
            Write-Log "Usata cache locale: $($reg.agents.Count) agent" -Level INFO
            return $reg
        }
        return $null
    }
}

function Get-CachedRegistry {
    if ($UpdateRegistry) { return Update-RegistryCache }
    if (Test-Path $Script:RegistryCacheFile) {
        $age = [int]((Get-Date) - (Get-Item $Script:RegistryCacheFile).CreationTime).TotalHours
        if ($age -gt 24) { Write-Log "Cache scaduta ($age h). Aggiorno..." -Level INFO; return Update-RegistryCache }
        try { return Get-Content $Script:RegistryCacheFile -Raw | ConvertFrom-Json }
        catch { Write-Log "Cache corrotta, ri-scarico..." -Level WARN; return Update-RegistryCache }
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
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
            "$env:USERPROFILE"
        )
        foreach ($sp in $searchPaths) {
            $found = Get-ChildItem -Path $sp -Filter "*$id*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $result.Installed = $true; $result.InstallMethod = 'KnownPath'
                $result.InstallDetail = $found.FullName
                break
            }
        }
        if (-not $result.Installed) {
            $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\DevTunnels" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $result.Installed = $true; $result.InstallMethod = 'KnownPath'; $result.InstallDetail = $found.FullName }
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
                $_.DisplayName -and ($_.DisplayName -match $id -or $_.DisplayName -match $name)
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
# AZIONE: INIT
# ============================================================

function Action-Init {
    Write-Section "Configurazione Iniziale"
    if (Test-Path $Script:ConfigFile) {
        Write-StatusDot 'INFO' 'INFO' "Config esistente: $Script:ConfigFile"
        $r = Read-Host "Sovrascrivere? (s/N)"
        if ($r -ne 's') { Write-Log "Init annullato." -Level INFO; return }
    }
    $cfg = New-DefaultConfig
    Write-Host "`nPorte bridge (invio per default):" -ForegroundColor Yellow
    foreach ($b in @('opencode','kilocode','cursor')) {
        $def = $Script:BridgePortsDefault[$b]; $r = Read-Host "  $b [$def]"
        if ($r -match '^\d+$') { $cfg.profiles.default.ports.$b = [int]$r }
    }
    $r = Read-Host "`nAbilitare auto-restart? (s/N)"; $cfg.profiles.default.auto_restart = ($r -eq 's')
    $r = Read-Host "Modalita mobile? (s/N)"; $cfg.profiles.default.mobile_mode = ($r -eq 's')
    $r = Read-Host "Tunnel anonimo default? (s/N)"; $cfg.profiles.default.anonymous_tunnel = ($r -eq 's')
    Save-Config $cfg; Write-Log "Configurazione completata!" -Level OK

    Write-Section "Verifica Prerequisiti"
    $allOk = $true
    foreach ($cmd in @('npm','node','winget','git')) {
        if (Test-Cmd $cmd) { Write-StatusDot 'OK' 'OK' $cmd } else { Write-StatusDot 'WARN' 'WARN' "$cmd non trovato"; $allOk = $false }
    }
    if (Test-Cmd 'devtunnel') { Write-StatusDot 'OK' 'OK' 'devtunnel CLI' }
    else { Write-StatusDot 'WARN' 'WARN' "devtunnel non installato" }
    if ($allOk) { Write-Log "Tutti i prerequisiti presenti!" -Level OK }
    else { Write-Log "Strumenti mancanti - installa con Install" -Level WARN }
    Write-Host "`n  Prossimi passi: .\acp-manager.ps1 -Action Scan /.\acp-manager.ps1 -Action Install -Bridge all`n" -ForegroundColor Cyan
}

# ============================================================
# AZIONE: INSTALL
# ============================================================

function Action-Install {
    Write-Section "Installazione Bridge"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor') } else { @($Bridge) }
    foreach ($b in $bridges) {
        $name = $Script:BridgeNames[$b]; $cmd = $Script:BridgeInstall[$b]
        if (-not $cmd) { Write-StatusDot 'INFO' 'INFO' "$name - incluso in Cursor v0.45+"; continue }
        $requires = if ($cmd -match '^npm') { 'npm' } else { 'npx' }
        if (-not (Test-Cmd $requires)) { Write-StatusDot 'ERR' 'ERR' "$requires necessario per $name"; continue }
        $checkCmd = ($Script:BridgeCmds[$b].check -split '\s')[0]
        if (Test-Cmd $checkCmd) { Write-StatusDot 'OK' 'OK' "$name gia installato"; continue }
        Write-Log "Installazione $name..." -Level INFO
        try {
            $r = Invoke-Expression $cmd 2>&1
            if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "$name installato"; Write-Log "$name installato" -Level OK }
            else { Write-StatusDot 'ERR' 'ERR' "${name}: $r"; Write-Log "Errore ${name}: $r" -Level ERROR }
        } catch { Write-StatusDot 'ERR' 'ERR' "${name}: $_"; Write-Log "Errore ${name}: $_" -Level ERROR }
    }
    Write-Section "DevTunnel"
    if (Test-Cmd 'devtunnel') { Write-StatusDot 'OK' 'OK' 'devtunnel CLI gia installato' }
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
        Write-StatusDot 'OK' 'OK' "DevTunnel installato"; return $true
    } catch { Write-StatusDot 'ERR' 'ERR' "Download fallito: $_"; return $false }
}

# ============================================================
# AZIONE: START / STOP / RESTART
# ============================================================

function Action-Start {
    Write-Section "Avvio Bridge"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor') } else { @($Bridge) }
    foreach ($b in $bridges) { Start-Bridge -Name $b -DisplayName $Script:BridgeNames[$b] -Port (Get-BridgePort -BridgeName $b) }
}

function Start-Bridge {
    param([string]$Name, [string]$DisplayName, [int]$Port)
    $check = $Script:BridgeCmds[$Name].check; $startCmd = $Script:BridgeCmds[$Name].start -f $Port; $checkExe = ($check -split '\s')[0]
    $existing = Get-ProcessByFilter -Filter $check
    if ($existing) { $mem = [Math]::Round($existing.WorkingSetSize/1MB,1); Write-StatusDot 'RUN' 'RUN' "${DisplayName} gia attivo (PID:$($existing.ProcessId) RAM:${mem}MB)"; return $existing }
    if (-not (Test-Cmd $checkExe)) { Write-StatusDot 'ERR' 'ERR' "${DisplayName} non installato"; return $null }
    try {
        if ($Name -eq 'cursor') { Write-StatusDot 'INFO' 'INFO' "${DisplayName} - configura da UI"; return $null }
        $lf = Join-Path $env:TEMP "bridge-$Name.log"
        $p = Start-Process cmd.exe -ArgumentList "/c $startCmd" -WindowStyle Hidden -PassThru -RedirectStandardOutput $lf -RedirectStandardError $lf
        Start-Sleep -Seconds 2
        if ($p -and !$p.HasExited) { Write-StatusDot 'RUN' 'RUN' "${DisplayName} avviato (PID:$($p.Id), porta:$Port)"; Write-Log "${DisplayName} avviato PID:$($p.Id)" -Level OK; return $p }
        else { Write-StatusDot 'ERR' 'ERR' "${DisplayName} avvio fallito"; return $null }
    } catch { Write-StatusDot 'ERR' 'ERR' "${DisplayName}: $_"; return $null }
}

function Action-Stop {
    Write-Section "Arresto Bridge"
    $bridges = if ($Bridge -eq 'all') { @('opencode','kilocode','cursor','devtunnel') } else { @($Bridge) }
    foreach ($b in $bridges) {
        if ($b -eq 'devtunnel') { $d = Get-Process -Name 'devtunnel' -ErrorAction SilentlyContinue; if ($d) { $d | Stop-Process -Force; Write-StatusDot 'STOP' 'STOP' 'DevTunnel fermato' } else { Write-StatusDot 'STOP' 'STOP' 'DevTunnel non attivo' }; continue }
        Stop-Bridge -Name $b
    }
}

function Stop-Bridge {
    param([string]$Name)
    $display = $Script:BridgeNames[$Name]; $check = $Script:BridgeCmds[$Name].check
    $p = Get-ProcessByFilter -Filter $check; if (-not $p) { $p = Get-Process -Name $Name -ErrorAction SilentlyContinue }
    if ($p) { foreach ($x in $p) { $pid = if ($x.ProcessId) { $x.ProcessId } else { $x.Id }; Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; Write-StatusDot 'STOP' 'STOP' "$display fermato (PID:$pid)"; Write-Log "$display fermato" -Level INFO } }
    else { Write-StatusDot 'STOP' 'STOP' "$display non attivo" }
}

function Action-Restart {
    Write-Section "Riavvio Bridge"; $savedBridge = $Bridge; Action-Stop; Start-Sleep -Seconds 2; $Bridge = $savedBridge; Action-Start
}

# ============================================================
# AZIONE: STATUS
# ============================================================

function Action-Status {
    Write-Section "Stato Bridge ACP"
    $bridges = @('opencode','kilocode','cursor'); $rows = @()
    foreach ($b in $bridges) {
        $name = $Script:BridgeNames[$b]; $check = $Script:BridgeCmds[$b].check
        $checkExe = ($check -split '\s')[0]; $bp = Get-BridgePort -BridgeName $b
        $p = Get-ProcessByFilter -Filter $check; $installed = Test-Cmd $checkExe
        if ($p) {
            $mem = [Math]::Round($p.WorkingSetSize/1MB,1); $uptime = Get-ProcessUptime -Process $p; $healthy = Test-PortOpen -Port $bp
            $healthIcon = if ($healthy) { 'TCP OK' } else { 'No resp.' }
            $rows += [PSCustomObject]@{ Bridge=$name; PID=$p.ProcessId; Porta=$bp; RAM="${mem}MB"; Stato='Attivo'; Salute=$healthIcon; Uptime=$uptime }
        } else { $stato = if ($installed) { 'Fermo' } else { 'Non install.' }
            $rows += [PSCustomObject]@{ Bridge=$name; PID='-'; Porta=$bp; RAM='-'; Stato=$stato; Salute='-'; Uptime='-' }
        }
    }
    Write-Table -Data $rows -Properties @('Bridge','PID','Porta','RAM','Stato','Salute','Uptime') -Headers @('Bridge','PID','Porta','RAM','Stato','Health','Uptime')
    $t = Get-Process -Name 'devtunnel' -ErrorAction SilentlyContinue
    if ($t) { Write-StatusDot 'RUN' 'RUN' "DevTunnel attivo (PID:$($t.Id))" }
    else { if (Test-Cmd 'devtunnel') { Write-StatusDot 'STOP' 'STOP' 'DevTunnel fermo' } else { Write-StatusDot 'INFO' 'INFO' 'DevTunnel non installato' } }

    $reg = Get-CachedRegistry
    if ($reg) {
        Write-Section "Agenti Registry ACP" "Cyan"
        $found = @()
        foreach ($a in $reg.agents) {
            $det = Get-EnhancedDetection -Agent $a
            if ($det.Installed) {
                $v = if ($det.InstalledVersion) { $det.InstalledVersion.Substring(0, [Math]::Min(12, $det.InstalledVersion.Length)) } else { '-' }
                $found += [PSCustomObject]@{ Agente=$det.Name; Stato=$det.StatusIcon; Versione=$v; Metodo=$det.InstallMethod }
            }
        }
        if ($found.Count -gt 0) { Write-Table -Data $found -Properties @('Agente','Stato','Versione','Metodo') }
        else { Write-StatusDot 'INFO' 'INFO' 'Nessun agente ACP aggiuntivo' }
    }
    Write-Host "`n  Log: $($Script:LogFile)" -ForegroundColor DarkGray; Write-Host "  Config: $($Script:ConfigFile)" -ForegroundColor DarkGray
}

# ============================================================
# AZIONE: SCAN
# ============================================================

function Action-Scan {
    Write-Section "ACP Agent Scan - Rilevazione Sistema"
    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry non disponibile'; return }

    $agents = $reg.agents; Write-Log "Scansione $($agents.Count) agent..." -Level INFO
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
    Write-Host "`n  Risultati:" -ForegroundColor Cyan
    Write-Host "    Agenti registry: $($agents.Count)" -ForegroundColor White
    Write-Host "    Installati: $($installed.Count)" -ForegroundColor Green
    Write-Host "    In esecuzione: $($running.Count)" -ForegroundColor Green
    Write-Host "    Tempo: $([Math]::Round($totalTime.TotalSeconds,1))s" -ForegroundColor DarkGray

    if ($Detailed) {
        Write-Section "Installati / In Esecuzione" "Green"
        if ($installed.Count -gt 0) { Write-Table -Data $installed -Properties @('Name','StatusIcon','Status','Version','VersionStatus','InstallMethod','RAM_MB','CPU_Pct','Ports','Uptime') -Headers @('Agente',' ','Stato','Versione','Agg.','Metodo','RAM','CPU','Porte','Uptime') }
        Write-Section "Tutti gli Agenti" "Cyan"
        Write-Table -Data $results -Properties @('Name','StatusIcon','Status','Version','License','InstallMethod') -Headers @('Agente',' ','Stato','Versione','Licenza','Installazione')
    } else {
        Write-Table -Data $results -Properties @('Name','StatusIcon','Status','Version','VersionStatus','InstallMethod') -Headers @('Agente',' ','Stato','Versione','Agg.','Installazione')
    }
    Write-Host "`n  Usa -Detailed per health check (CPU, rete, porte, I/O)." -ForegroundColor DarkGray
    Write-Host "  Usa -OutputFormat Json per output JSON." -ForegroundColor DarkGray
}

# ============================================================
# AZIONE: AGENTINFO
# ============================================================

function Action-AgentInfo {
    if (-not $AgentId) {
        Write-StatusDot 'ERR' 'ERR' "Specifica -AgentId"; $reg = Get-CachedRegistry
        if ($reg) { Write-Host "  Agenti disponibili:" -ForegroundColor Yellow; foreach ($a in $reg.agents) { Write-Host "    $($a.id) - $($a.name)" -ForegroundColor White } }
        return
    }
    $reg = Get-CachedRegistry; if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry non disponibile'; return }
    $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
    if (-not $agent) { Write-StatusDot 'ERR' 'ERR' "Agente '$AgentId' non trovato"; return }

    $det = Get-EnhancedDetection -Agent $agent -DeepScan:$true
    Write-Section "$($agent.name) ($($agent.id))" "Green"
    Write-Host "`n  Info Registry:" -ForegroundColor Yellow
    Write-Host "    Versione: $($agent.version)" -ForegroundColor White; Write-Host "    Licenza: $($agent.license)" -ForegroundColor White
    Write-Host "    Descrizione: $($agent.description)" -ForegroundColor Gray
    if ($agent.website) { Write-Host "    Website: $($agent.website)" -ForegroundColor Blue }
    if ($agent.repository) { Write-Host "    Repository: $($agent.repository)" -ForegroundColor Blue }
    Write-Host "`n  Distribuzione:" -ForegroundColor Yellow
    if ($agent.distribution.npx) { Write-Host "    npx: $($agent.distribution.npx.package)" -ForegroundColor White }
    if ($agent.distribution.uvx) { Write-Host "    uvx: $($agent.distribution.uvx.package)" -ForegroundColor White }
    if ($agent.distribution.binary) {
        Write-Host "    Binary: supportato" -ForegroundColor White
        if ($agent.distribution.binary.'windows-x86_64') { Write-Host "      Windows x64: $($agent.distribution.binary.'windows-x86_64'.cmd)" -ForegroundColor Gray }
    }
    Write-Host "`n  Rilevazione:" -ForegroundColor Yellow
    if ($det.Installed) {
        Write-StatusDot 'OK' 'OK' "Installato: $($det.InstallMethod) - $($det.InstallDetail)"
        if ($det.InstalledVersion) { Write-StatusDot 'OK' 'OK' "Versione: $($det.InstalledVersion)" }
    } else { Write-StatusDot 'STOP' 'STOP' 'Non installato' }
    if ($det.Running) {
        Write-StatusDot $det.StatusIcon $det.StatusIcon "$($det.Status) (PID:$($det.ProcessId))"
        if ($det.RAM_MB) { Write-StatusDot 'OK' 'OK' "RAM: $($det.RAM_MB) MB" }
        if ($det.CPU_Pct) { Write-StatusDot $det.StatusIcon $det.StatusIcon "CPU: $($det.CPU_Pct)%" }
        if ($det.Uptime) { Write-StatusDot 'OK' 'OK' "Uptime: $($det.Uptime)" }
        if ($det.PortListening) { Write-StatusDot 'RUN' 'RUN' 'In ascolto porta' }
        if ($det.NetworkActive) { Write-StatusDot 'WORK' 'WORK' 'Rete attiva' }
        if ($det.Working) { Write-StatusDot 'WORK' 'WORK' 'CPU attiva (lavorando)' }
    }
    if ($det.Ports.Count -gt 0) {
        Write-Host "`n  Porte:" -ForegroundColor Yellow; foreach ($p in $det.Ports) { Write-Host "    Porta $($p.Port) - $($p.State)" -ForegroundColor White }
    }
    if ($det.ConfigFiles.Count -gt 0) {
        Write-Host "`n  Config files:" -ForegroundColor Yellow; foreach ($cf in $det.ConfigFiles) { Write-Host "    $cf" -ForegroundColor White }
    }
}

# ============================================================
# AZIONE: REGISTRY
# ============================================================

function Action-Registry {
    Write-Section "ACP Registry"; $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry non disponibile'; return }
    Write-Host "  Versione registry: $($reg.version)" -ForegroundColor Cyan
    Write-Host "  Agenti: $($reg.agents.Count)" -ForegroundColor Cyan
    Write-Host "  Cache: $Script:RegistryCacheFile" -ForegroundColor DarkGray
    Write-Section "Lista Agenti" "Cyan"
    $rows = @()
    foreach ($a in $reg.agents) {
        $dt = @(); if ($a.distribution.npx) { $dt += 'npx' }; if ($a.distribution.uvx) { $dt += 'uvx' }; if ($a.distribution.binary) { $dt += 'binary' }
        $lic = if ($a.license) { $a.license.Substring(0, [Math]::Min(14, $a.license.Length)) } else { '-' }
        $rows += [PSCustomObject]@{ ID=$a.id; Name=$a.name; Version=$a.version; License=$lic; Distro=($dt -join ',') }
    }
    Write-Table -Data $rows -Properties @('ID','Name','Version','License','Distro') -Headers @('ID','Nome','Versione','Licenza','Distribuzione')
}

# ============================================================
# DEV TUNNEL
# ============================================================

function Action-Tunnel {
    Write-Section "DevTunnel + Bridge"
    if ($Bridge -eq 'all') { Write-StatusDot 'WARN' 'WARN' "Tunnel non supporta -Bridge all. Uso: opencode"; $Bridge = 'opencode' }
    $tunnelCfg = Get-Config
    if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'WARN' 'WARN' 'DevTunnel non installato. Installazione...'; Install-DevTunnel; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'Installazione fallita'; return } }
    $loginCheck = devtunnel user show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-StatusDot 'INFO' 'INFO' 'Login richiesto'; devtunnel user login
        if ($LASTEXITCODE -ne 0) { Write-StatusDot 'ERR' 'ERR' 'Login fallito. Usa: devtunnel user login -g'; return }
    }
    $bp = Get-BridgePort -BridgeName $Bridge
    if ($Bridge -ne 'cursor') { $p = Start-Bridge -Name $Bridge -DisplayName $Script:BridgeNames[$Bridge] -Port $bp; if (-not $p) { Write-StatusDot 'ERR' 'ERR' "Bridge $Bridge non avviato"; return } }
    else { Write-StatusDot 'INFO' 'INFO' 'Cursor - avvia da UI, porta 3000'; $bp = 3000 }

    $anonFromCfg = ($tunnelCfg -and $tunnelCfg.profiles.$Profile.anonymous_tunnel -eq $true)
    $anonFlag = if ($Anonymous -or $anonFromCfg) { ' --allow-anonymous' } else { '' }
    $tunnelArg = if ($TunnelId) { "host $TunnelId -p $bp --protocol http$anonFlag" } else { "host -p $bp --protocol http$anonFlag" }
    $lf = Join-Path $env:TEMP 'devtunnel-out.log'; Write-Log "Avvio DevTunnel porta $bp..." -Level INFO
    try {
        $tp = Start-Process cmd.exe -ArgumentList "/c devtunnel $tunnelArg" -WindowStyle Hidden -PassThru -RedirectStandardOutput $lf -RedirectStandardError $lf
        Start-Sleep -Seconds 4
        if (Test-Path $lf) {
            $o = Get-Content $lf -Raw; $m = [regex]::Match($o,'https?://[a-zA-Z0-9._-]+\.devtunnels\.ms:\d+')
            if ($m.Success) {
                Write-Host "`n"; Write-StatusDot 'OK' 'OK' 'Tunnel attivo!'
                Write-Host "  URL REMOTO: $($m.Value)" -ForegroundColor Green
                Write-Host "  Bridge: $Bridge su porta $bp" -ForegroundColor Cyan; Write-Host "  PID: $($tp.Id)" -ForegroundColor DarkGray
                if ($Anonymous -or $anonFromCfg) { Write-Host "  Accesso: ANONIMO" -ForegroundColor Yellow } else { Write-Host "  Accesso: Autenticato" -ForegroundColor DarkGray }
                Write-Log "Tunnel attivo: $($m.Value)" -Level OK
            } else { Write-StatusDot 'INFO' 'INFO' "DevTunnel avviato (PID:$($tp.Id))"; Write-Host "  Log: $lf" -ForegroundColor DarkGray }
        }
        Write-Host "  Premi Ctrl+C per fermare.`n" -ForegroundColor Yellow
    } catch { Write-StatusDot 'ERR' 'ERR' "Avvio tunnel: $_" }
}

function Action-TunnelCreate {
    Write-Section "Crea Tunnel Persistente"
    if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel non installato'; return }
    $anonFlag = if ($Anonymous) { ' --allow-anonymous' } else { '' }
    try {
        $r = devtunnel create $anonFlag 2>&1
        if ($LASTEXITCODE -eq 0) {
            $idMatch = [regex]::Match($r,'[a-zA-Z0-9_-]+')
            if ($idMatch.Success -and $idMatch.Value.Length -gt 3) {
                Write-StatusDot 'OK' 'OK' "Tunnel creato: $($idMatch.Value)"
                $cfg = Get-Config; if (-not $cfg) { $cfg = New-DefaultConfig }
                $cfg.profiles.$Profile.tunnel_id = $idMatch.Value; Save-Config $cfg
                Write-Host "  Salvato nel profilo '$Profile'" -ForegroundColor DarkGray
                Write-Host "`n  Dettagli:" -ForegroundColor Cyan; devtunnel show $idMatch.Value 2>&1 | ForEach-Object { Write-Host "    $_" }
            }
        } else { Write-StatusDot 'ERR' 'ERR' "Creazione fallita: $r" }
    } catch { Write-StatusDot 'ERR' 'ERR' "Errore: $_" }
}

function Action-TunnelList {
    Write-Section "Tunnel Esistenti"; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel non installato'; return }
    try { $r = devtunnel list 2>&1; if ($LASTEXITCODE -eq 0 -and $r) { Write-Host $r -ForegroundColor White } else { Write-StatusDot 'INFO' 'INFO' 'Nessun tunnel' } } catch { Write-StatusDot 'ERR' 'ERR' "Errore: $_" }
}

function Action-TunnelInfo {
    Write-Section "Dettagli Tunnel"; if (-not (Test-Cmd 'devtunnel')) { Write-StatusDot 'ERR' 'ERR' 'DevTunnel non installato'; return }
    $tid = $TunnelId; if (-not $tid) { $cfg = Get-Config; if ($cfg) { $tid = $cfg.profiles.$Profile.tunnel_id } }
    if (-not $tid) { try { $list = devtunnel list 2>&1; $m = [regex]::Match($list,'([a-zA-Z0-9_-]{10,})'); if ($m.Success) { $tid = $m.Value } } catch {} }
    if ($tid) { devtunnel show $tid 2>&1 | ForEach-Object { Write-Host "  $_" } } else { Write-StatusDot 'WARN' 'WARN' 'Nessun tunnel. Usa -TunnelId o TunnelCreate' }
}

function Action-TunnelDelete {
    Write-Section "Elimina Tunnel"; $tid = $TunnelId; if (-not $tid) { $cfg = Get-Config; if ($cfg) { $tid = $cfg.profiles.$Profile.tunnel_id } }
    if (-not $tid) { Write-StatusDot 'ERR' 'ERR' 'Specifica -TunnelId'; return }
    try { $r = devtunnel delete $tid 2>&1; if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "Tunnel $tid eliminato"; $cfg = Get-Config; if ($cfg -and $cfg.profiles.$Profile.tunnel_id -eq $tid) { $cfg.profiles.$Profile.tunnel_id = ''; Save-Config $cfg } } else { Write-StatusDot 'ERR' 'ERR' "Eliminazione fallita: $r" } } catch { Write-StatusDot 'ERR' 'ERR' "Errore: $_" }
}

# ============================================================
# LOG MANAGEMENT
# ============================================================

function Action-Logs {
    Write-Section "Log ($LogLines righe)"; $logPath = $Script:LogFile
    if (-not (Test-Path $logPath)) { Write-StatusDot 'INFO' 'INFO' "Nessun log in $logPath"; return }
    $content = Get-Content $logPath -Tail $LogLines; $totalLines = (Get-Content $logPath).Count
    Write-Host "  File: $logPath ($totalLines righe)" -ForegroundColor DarkGray; Write-Host "  Ultime $LogLines righe:`n" -ForegroundColor DarkGray
    foreach ($line in $content) { $color = 'Gray'; if ($line -match '\[ERROR\]') { $color = 'Red' } elseif ($line -match '\[WARN\]') { $color = 'Yellow' } elseif ($line -match '\[OK\]') { $color = 'Green' }; Write-Host "  $line" -ForegroundColor $color }
}

function Action-LogClear { $logPath = $Script:LogFile; if (Test-Path $logPath) { Clear-Content $logPath; Write-StatusDot 'OK' 'OK' 'Log puliti' } else { Write-StatusDot 'INFO' 'INFO' 'Nessun log' } }

# ============================================================
# CONFIG / DIAG / AUTOSTART / MOBILE
# ============================================================

function Action-Config {
    Write-Section "Configurazione"; if (-not (Test-Path $Script:ConfigFile)) { Write-StatusDot 'INFO' 'INFO' "Nessuna config. Esegui Init."; return }
    Write-Host "  File: $Script:ConfigFile" -ForegroundColor DarkGray; Write-Host "`n$(Get-Content $Script:ConfigFile -Raw)" -ForegroundColor Cyan
    Write-Host "`n  Porte:" -ForegroundColor Yellow; foreach ($b in @('opencode','kilocode','cursor')) { Write-Host "    $($Script:BridgeNames[$b]) -> $(Get-BridgePort -BridgeName $b)" -ForegroundColor White }
}

function Action-Diag {
    Write-Section "Diagnostica"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "  OS: $($os.Caption) - Build $($os.BuildNumber)" -ForegroundColor White
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor White
    Write-Host "  RAM: $([Math]::Round($os.FreePhysicalMemory/1MB,1)) GB liberi / $([Math]::Round($os.TotalVisibleMemorySize/1MB,1)) GB" -ForegroundColor White
    Write-Host "`n  Prerequisiti:" -ForegroundColor Yellow
    foreach ($c in @(@{n='Node.js';c='node --version'},@{n='npm';c='npm --version'},@{n='Git';c='git --version'},@{n='Winget';c='winget --version'},@{n='DevTunnel';c='devtunnel --version'})) {
        try { $v = Invoke-Expression "$($c.c) 2>&1" -ErrorAction SilentlyContinue; if ($v) { Write-StatusDot 'OK' 'OK' "$($c.n): $($v -join ' ')" } else { Write-StatusDot 'WARN' 'WARN' "$($c.n): non trovato" } } catch { Write-StatusDot 'WARN' 'WARN' "$($c.n): non trovato" }
    }
    Write-Host "`n  Rete:" -ForegroundColor Yellow
    try { $null = [System.Net.Dns]::GetHostEntry('devtunnels.ms'); Write-StatusDot 'OK' 'OK' 'DNS devtunnels.ms OK' } catch { Write-StatusDot 'ERR' 'ERR' 'DNS devtunnels.ms NON risolvibile' }
    try { $h = Invoke-WebRequest -Uri 'https://devtunnels.ms' -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue; if ($h.StatusCode -eq 200) { Write-StatusDot 'OK' 'OK' 'Connessione devtunnels.ms OK' } } catch { Write-StatusDot 'ERR' 'ERR' 'Connessione devtunnels.ms FALLITA' }
    Write-Host "`n  Registry ACP: $(if (Test-Path $Script:RegistryCacheFile) { 'In cache' } else { 'Non scaricato' })" -ForegroundColor White
    Write-Host "`n  Usa: .\acp-manager.ps1 -Action Scan per scansione completa." -ForegroundColor Cyan
}

function Action-Autostart {
    $taskName = 'ACP-Manager'; $scriptPath = (Get-Item $PSCommandPath).FullName
    Write-Section "Auto-Avvio Windows"; Write-Host "  Task: $taskName" -ForegroundColor DarkGray; Write-Host "  Script: $scriptPath`n" -ForegroundColor DarkGray
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($Disable) { if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-StatusDot 'OK' 'OK' 'Auto-avvio rimosso' } else { Write-StatusDot 'INFO' 'INFO' 'Nessun auto-avvio' }; return }
    if ($existing) { Write-StatusDot 'INFO' 'INFO' 'Auto-avvio gia configurato'; $r = Read-Host "Rimuoverlo? (s/N)"; if ($r -eq 's') { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-StatusDot 'OK' 'OK' 'Rimosso' } else { Write-StatusDot 'INFO' 'INFO' 'Mantenuto' }; return }
    $autostartBridge = if ($Bridge -eq 'all') { 'opencode' } else { $Bridge }
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Action Start -Bridge $autostartBridge"
        $trigger = New-ScheduledTaskTrigger -AtLogOn; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "ACP Manager - $autostartBridge" -Force
        Write-StatusDot 'OK' 'OK' "Auto-avvio configurato per $autostartBridge"
    } catch { Write-StatusDot 'ERR' 'ERR' "Registrazione fallita: $_"; Write-Host "  Esegui PowerShell come Amministratore." -ForegroundColor Yellow }
}

function Action-Mobile {
    Write-Section "Integrazione Mobile"
    $mobileCfg = Get-Config; $anonMode = $Anonymous -or ($mobileCfg -and $mobileCfg.profiles.$Profile.anonymous_tunnel -eq $true)
    Write-Host @"
  Per connetterti da mobile al bridge ACP:

  1. Installa un'app ACP (es. Agmente su iOS)
  2. Avvia bridge + tunnel: .\ACP-Bridges.ps1 -Action Tunnel -Bridge $Bridge
  3. Usa l'URL remoto mostrato nell'app

  Accesso: $(if ($anonMode) { 'ANONIMO' } else { 'AUTENTICATO (Microsoft/GitHub)' })
"@
    $tid = $TunnelId; if (-not $tid -and $mobileCfg) { $tid = $mobileCfg.profiles.$Profile.tunnel_id }
    if ($tid) { Write-Host "`n  Tunnel persistente: $tid" -ForegroundColor Cyan }
    Write-Host "`n  Esempi:" -ForegroundColor White
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

  RILEVAZIONE:
$(Format-HelpAction 'Scan'          'Scansione 37+ agent ACP (installati, running, working)')
$(Format-HelpAction 'AgentInfo'     'Info dettagliate su un agente (-AgentId)')
$(Format-HelpAction 'Registry'      'Mostra/aggiorna registry ACP ufficiale')
$(Format-HelpAction 'InstallAgent'  'Installa un agente ACP dal registry (-AgentId)')
$(Format-HelpAction 'Update'        'Aggiorna agenti ACP (-AgentId nome | all)')

  GESTIONE BRIDGE:
$(Format-HelpAction 'Status'      'Stato bridge + agenti rilevati')
$(Format-HelpAction 'Install'     'Installa bridge ACP (opencode, kilocode, cursor)')
$(Format-HelpAction 'Start'       'Avvia bridge in background')
$(Format-HelpAction 'Stop'        'Ferma bridge')
$(Format-HelpAction 'Restart'     'Riavvia bridge')
$(Format-HelpAction 'Init'        'Configurazione guidata iniziale')

  DEV TUNNEL:
$(Format-HelpAction 'Tunnel'      'Bridge + tunnel remoto')
$(Format-HelpAction 'TunnelCreate' 'Crea tunnel persistente')
$(Format-HelpAction 'TunnelList'  'Lista tunnel')
$(Format-HelpAction 'TunnelInfo'  'Dettagli tunnel')
$(Format-HelpAction 'TunnelDelete''Elimina tunnel')

  SISTEMA:
$(Format-HelpAction 'Config'      'Mostra configurazione')
$(Format-HelpAction 'Diag'        'Diagnostica sistema')
$(Format-HelpAction 'Logs'        'Mostra log (-LogLines N)')
$(Format-HelpAction 'LogClear'    'Pulisci log')
$(Format-HelpAction 'Autostart'   'Auto-avvio Windows (-Disable per rimuovere)')
$(Format-HelpAction 'Mobile'      'Guida integrazione mobile')
$(Format-HelpAction 'Help'        'Questa guida')

  PARAMETRI:
    -AgentId       ID agente registry (es. gemini, claude-acp, devin)
    -Bridge        opencode | kilocode | cursor | all
    -Port          Porta personalizzata
    -TunnelId      ID DevTunnel
    -OutputFormat  Text | Json
    -Profile       Profilo config
    -LogLines      Righe log (default: 50)
    -Anonymous     Tunnel anonimo (switch)
    -Detailed      Output dettagliato (switch)
    -UpdateRegistry Forza aggiornamento registry (switch)
    -Disable       Disabilita auto-avvio (switch)

  ESEMPI:
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
# v4.0 ENHANCEMENTS: Progress, Caching, Detection+, Watch
# ============================================================

# ---- Write-Progress Wrapper ----
function Write-ScanProgress {
    param([int]$Current, [int]$Total, [string]$AgentName)
    $pct = [int]($Current / $Total * 100)
    Write-Progress -Activity "Scansione agent ACP" -Status "$AgentName ($Current/$Total)" -PercentComplete $pct
}
function Clear-ScanProgress { Write-Progress -Activity "Scansione agent ACP" -Completed }

# ---- Caching System ----
$Script:NpmCache = $null; $Script:CargoCache = $null; $Script:WingetCache = $null; $Script:CacheTime = @{}
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

# ---- Expanded Detection Methods ----
function Test-AgentPip { param([string]$Id, [string]$Pkg)
    if (-not (Test-Cmd 'pip')) { return $null }
    try { $list = pip list --format=json 2>$null | ConvertFrom-Json; if ($list) { $f = $list | Where-Object { $_.name -eq $Pkg -or $_.name -eq $Id }; if ($f) { return @{Installed=$true;Version=$f.version;Method='pip';Detail="pip: $($f.name) $($f.version)"} } } } catch {}; return $null }
function Test-AgentUvx { param([string]$Id, [string]$Pkg)
    if (-not (Test-Cmd 'uv')) { return $null }
    try { $list = uv tool list 2>$null; if ($list -match $Id -or $list -match $Pkg) { return @{Installed=$true;Version='';Method='uvx';Detail="uv tool: $Id"} } } catch {}; return $null }
function Test-AgentWinget { param([string]$Id)
    if (-not (Test-Cmd 'winget')) { return $null }
    try { $list = Get-CachedWingetList; if ($list -match $Id) { return @{Installed=$true;Version='';Method='winget';Detail="winget: $Id"} } } catch {}; return $null }
function Test-AgentChoco { param([string]$Id)
    if (-not (Test-Cmd 'choco')) { return $null }
    try { $list = choco list -li --limit-output 2>$null; if ($list -match $Id) { return @{Installed=$true;Version='';Method='choco';Detail="choco: $Id"} } } catch {}; return $null }
function Test-AgentScoop { param([string]$Id)
    if (-not (Test-Cmd 'scoop')) { return $null }
    try { $list = scoop list 2>$null; if ($list -match $Id) { return @{Installed=$true;Version='';Method='scoop';Detail="scoop: $Id"} } } catch {}; return $null }
function Test-AgentDotnet { param([string]$Id)
    if (-not (Test-Cmd 'dotnet')) { return $null }
    try { $list = dotnet tool list -g 2>$null; if ($list -match $Id) { return @{Installed=$true;Version='';Method='dotnet';Detail="dotnet tool: $Id"} } } catch {}; return $null }
function Test-AgentGo { param([string]$Name)
    if (-not (Test-Cmd 'go')) { return $null }
    try { $bin = go env GOBIN 2>$null; if (-not $bin) { $gp = go env GOPATH 2>$null; if ($gp) { $bin = Join-Path $gp 'bin' } }; if ($bin -and (Test-Path $bin)) { $f = Get-ChildItem $bin -Filter "*$Name*" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { return @{Installed=$true;Version='';Method='go';Detail="go: $($f.Name)"} } } } catch {}; return $null }

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
            return @{ Cmd = $null; Label = "$InstallMethod (manuale)" }
        }
        default {
            # Registry install method or unknown
            if ($Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                return @{ Cmd = "npm install -g $npmPkg@latest 2>&1"; Label = "npm: $npmPkg" }
            }
            return @{ Cmd = $null; Label = "$InstallMethod (manuale)" }
        }
    }
}

function Update-Agent {
    param([object]$Agent, [switch]$Quiet)

    $id = $Agent.id; $name = $Agent.name
    $det = Get-EnhancedDetection -Agent $Agent

    if (-not $det.Installed) {
        if (-not $Quiet) { Write-StatusDot 'STOP' 'STOP' "$name non installato" }
        return $false
    }

    $updCmd = Get-UpdateCommand -Agent $Agent -InstallMethod $det.InstallMethod -InstallDetail $det.InstallDetail

    if (-not $updCmd.Cmd) {
        if (-not $Quiet) {
            Write-StatusDot 'WARN' 'WARN' "${name}: aggiornamento automatico non supportato per $($det.InstallMethod)"
            Write-Host "    Visita: $($Agent.website)" -ForegroundColor Blue
        }
        # Try fallback: winget or npm
        return $false
    }

    $oldVer = $det.InstalledVersion
    Write-Log "Aggiornamento $name ($($updCmd.Label))..." -Level INFO
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
                Write-Log "$name aggiornato: $oldVer -> $newVer" -Level OK
            } else {
                Write-StatusDot 'OK' 'OK' "${name}: $newVer ($($updCmd.Label))"
                Write-Log "$name aggiornato" -Level OK
            }
            return $true
        } else {
            $errMsg = if ($r) { "$r".Trim().Split("`n")[0] } else { "exit code $LASTEXITCODE" }
            if (-not $Quiet) { Write-StatusDot 'ERR' 'ERR' "${name}: $errMsg" }
        Write-Log "Errore aggiornamento ${name}: $errMsg" -Level ERROR

        # Try fallback: npm install if original method was PATH/KnownPath
            if ($updCmd.Fallback -and $Agent.distribution.npx) {
                $nameParts = $Agent.distribution.npx.package -split '@'
                $npmPkg = $nameParts[0]
                if (-not $Quiet) { Write-Host "    Ripiego con: npm install -g $npmPkg@latest" -ForegroundColor Yellow }
                try {
                    $r2 = npm install -g $npmPkg@latest 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-StatusDot 'OK' 'OK' "${name}: aggiornato via npm"; return $true }
                } catch {}
            }
            return $false
        }
    } catch {
        $errMsg = "$_".Trim().Split("`n")[0]
        if (-not $Quiet) { Write-StatusDot 'ERR' 'ERR' "${name}: $errMsg" }
        Write-Log "Errore aggiornamento ${name}: $errMsg" -Level ERROR
        return $false
    }
}

function Action-Update {
    Write-Section "Aggiornamento Agenti ACP"

    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry non disponibile'; return }

    # Determine which agents to update
    $targets = @()

    if ($AgentId) {
        if ($AgentId -eq 'all') {
            # Update ALL installed agents
            $targets = $reg.agents
        } else {
            $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
            if (-not $agent) { Write-StatusDot 'ERR' 'ERR' "Agente '$AgentId' non trovato"; return }
            $targets = @($agent)
        }
    } elseif ($Bridge -ne 'all') {
        # Update a specific bridge
        $agent = $reg.agents | Where-Object { $_.id -eq $Bridge } | Select-Object -First 1
        if ($agent) { $targets = @($agent) } else { Write-StatusDot 'ERR' 'ERR' "Bridge '$Bridge' non trovato nel registry"; return }
    } else {
        # Default: update all installed
        $targets = $reg.agents
    }

    # First pass: detect which are installed
    Write-Host "  Rilevamento agenti installati..." -ForegroundColor DarkGray
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
        Write-StatusDot 'INFO' 'INFO' 'Nessun agente installato da aggiornare'
        return
    }

    Write-Host "  Trovati $($installed.Count) agenti da aggiornare`n" -ForegroundColor Cyan

    # Show summary table
    $summary = $installed | ForEach-Object {
        $a = $_.Agent; $d = $_.Detection
        [PSCustomObject]@{
            Agente = $a.name; Versione = if ($d.InstalledVersion) { $d.InstalledVersion.Substring(0, [Math]::Min(16, $d.InstalledVersion.Length)) } else { '-' }
            Registry = $a.version; Method = $d.InstallMethod
        }
    }
    Write-Table -Data $summary -Properties @('Agente','Versione','Registry','Method') -Headers @('Agente','Versione Locale','Versione Registry','Metodo')

    # Confirm unless -AgentId specified a single agent
    if ($installed.Count -gt 1) {
        Write-Host "`n"
        $confirm = Read-Host "Aggiornare tutti i $($installed.Count) agenti? (S/N)"
        if ($confirm -ne 'S' -and $confirm -ne 's') { Write-Log "Aggiornamento annullato." -Level INFO; return }
    }

    Write-Host "`n"

    # Execute updates
    $success = 0; $failed = 0
    $totalTime = Measure-Command {
        $count = 0
        foreach ($item in $installed) {
            $count++
            $a = $item.Agent; $d = $item.Detection
            Write-Progress -Activity "Aggiornamento agenti ACP" -Status "$($a.name) ($count/$($installed.Count))" -PercentComplete ([int]($count / $installed.Count * 100))
            Write-Host "  [$count/$($installed.Count)] " -NoNewline -ForegroundColor DarkGray
            if (Update-Agent -Agent $a) { $success++ } else { $failed++ }
        }
    }
    Write-Progress -Activity "Aggiornamento agenti ACP" -Completed

    Write-Host "`n"
    Write-Section "Riepilogo Aggiornamento" "Green"
    Write-Host "  Riusciti: $success" -ForegroundColor Green
    Write-Host "  Falliti:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'DarkGray' })
    Write-Host "  Tempo:    $([Math]::Round($totalTime.TotalSeconds,1))s" -ForegroundColor DarkGray
    if ($failed -gt 0) {
        Write-Host "`n  Per aggiornamenti manuali, visita il sito dell'agente." -ForegroundColor Yellow
    }
}

# ============================================================
# AZIONE: INSTALLAGENT (dal Registry ACP)
# ============================================================

function Action-InstallAgent {
    Write-Section "Installazione Agente ACP dal Registry"
    $reg = Get-CachedRegistry
    if (-not $reg) { Write-StatusDot 'ERR' 'ERR' 'Registry non disponibile. Usa -UpdateRegistry per scaricarlo'; return }

    # List available agents if no -AgentId specified
    if (-not $AgentId) {
        Write-Host "  Usa -AgentId per specificare un agente. Disponibili:`n" -ForegroundColor Yellow
        $rows = @()
        foreach ($a in $reg.agents) {
            $dt = @(); if ($a.distribution.npx) { $dt += 'npx' }; if ($a.distribution.uvx) { $dt += 'uvx' }
            if ($a.distribution.binary) { $dt += 'binary' }; if ($a.distribution.cargo) { $dt += 'cargo' }
            $rows += [PSCustomObject]@{ ID=$a.id; Name=$a.name; Versione=$a.version; Installa=($dt -join ', ') }
        }
        Write-Table -Data $rows -Properties @('ID','Name','Versione','Installa') -Headers @('ID','Nome','Versione','Metodi Installazione')
        Write-Host "`n  Esempio: .\acp-manager.ps1 -Action InstallAgent -AgentId gemini`n" -ForegroundColor Cyan
        return
    }

    # Look up agent in registry
    $agent = $reg.agents | Where-Object { $_.id -eq $AgentId } | Select-Object -First 1
    if (-not $agent) {
        Write-StatusDot 'ERR' 'ERR' "Agente '$AgentId' non trovato nel registry"
        Write-Host "  Usa .\acp-manager.ps1 -Action Registry per vedere tutti gli agenti." -ForegroundColor Yellow
        return
    }

    $name = $agent.name; $id = $agent.id; $ver = $agent.version

    # Check if already installed
    $det = Get-EnhancedDetection -Agent $agent
    if ($det.Installed) {
        $v = if ($det.InstalledVersion) { $det.InstalledVersion } else { '?' }
        Write-StatusDot 'OK' 'OK' "$name gia installato ($v) via $($det.InstallMethod)"
        $r = Read-Host "  Reinstallare/aggiornare lo stesso? (S/N)"
        if ($r -ne 'S' -and $r -ne 's') { Write-Log "Installazione annullata." -Level INFO; return }
        Write-Host ""
    } else {
        Write-StatusDot 'INFO' 'INFO' "$name ($id) v$ver - non installato"
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
        Write-StatusDot 'ERR' 'ERR' "Nessun metodo di installazione disponibile per $name nel registry"
        if ($agent.website) { Write-Host "    Visita: $($agent.website)" -ForegroundColor Blue }
        return
    }

    # Show available methods
    Write-Host "  Metodi di installazione disponibili:`n" -ForegroundColor Yellow
    $methodTable = $methods | Sort-Object Priority | ForEach-Object {
        $ok = if (-not $_.Req -or (Test-Cmd $_.Req)) { 'OK' } else { 'NO' }
        [PSCustomObject]@{ Priority=$_.Priority; Metodo=$_.Method; Comando=$_.Label; Prereq="$($_.Req) [$ok]" }
    }
    Write-Table -Data $methodTable -Properties @('Priority','Metodo','Comando','Prereq') -Headers @('#','Metodo','Comando','Prerequisito')

    # Pick best method: try best available that has prereqs
    $chosen = $null
    foreach ($m in ($methods | Sort-Object Priority)) {
        if (-not $m.Req -or (Test-Cmd $m.Req)) { $chosen = $m; break }
    }
    if (-not $chosen) {
        Write-StatusDot 'ERR' 'ERR' "Nessun prerequisito disponibile per installare $name"
        Write-Host "    Servono: $($methods.Req -join ', ')" -ForegroundColor Yellow
        return
    }

    # Confirm
    Write-Host "`n"
    Write-Host "  Metodo scelto: $($chosen.Label)" -ForegroundColor Cyan
    $r = Read-Host "  Installare $name? (S/N)"
    if ($r -ne 'S' -and $r -ne 's') { Write-Log "Installazione annullata." -Level INFO; return }
    Write-Host ""

    # Execute installation
    $success = $false
    try {
        Write-Log "Installazione $name via $($chosen.Method)..." -Level INFO
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
            Write-StatusDot 'OK' 'OK' "$name installato in $destDir"
            $success = $true
        } else {
            $r = Invoke-Expression $chosen.Cmd 2>&1
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
                Write-StatusDot 'OK' 'OK' "$name installato ($($chosen.Label))"
                Write-Log "$name installato con successo" -Level OK
                $success = $true
            } else {
                $errMsg = if ($r) { "$r".Trim().Split("`n")[0] } else { "exit code $LASTEXITCODE" }
                Write-StatusDot 'ERR' 'ERR' "Installazione fallita: $errMsg"
                Write-Log "Installazione $name fallita: $errMsg" -Level ERROR
            }
        }
    } catch {
        Write-StatusDot 'ERR' 'ERR' "Errore installazione: $_"
        Write-Log "Errore installazione ${name}: $_" -Level ERROR
    }

    # Verify installation
    if ($success) {
        Start-Sleep -Seconds 2
        Write-Host "`n  Verifica installazione..." -ForegroundColor DarkGray
        $det2 = Get-EnhancedDetection -Agent $agent
        if ($det2.Installed) {
            $v = if ($det2.InstalledVersion) { $det2.InstalledVersion } else { 'OK' }
            Write-StatusDot 'OK' 'OK' "$name verificato ($v) via $($det2.InstallMethod)"
            if ($det2.VersionStatus -eq 'outdated') {
                Write-StatusDot 'WARN' 'WARN' "Versione installata ($v) < registry ($ver). Prova: .\acp-manager.ps1 -Action Update -AgentId $id"
            }
        } else {
            Write-StatusDot 'WARN' 'WARN' "$name installato ma non rilevato. Forse serve riavviare il terminale."
        }
    }
}

# ---- WATCH MODE ----
function Action-Watch {
    param([int]$Interval = 10)
    Write-Section "Watch Mode - Ctrl+C per uscire"
    Write-Host "  Aggiornamento ogni ${Interval}s" -ForegroundColor DarkGray
    Write-Host "`n"
    while ($true) {
        $savedFormat = $OutputFormat
        $OutputFormat = 'Text'
        Action-Status
        $OutputFormat = $savedFormat
        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] Prossimo aggiornamento tra ${Interval}s... (Ctrl+C per fermare)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Interval
        Clear-Host
    }
}

# ---- REGISTRY AUTO-UPDATE ----
function Action-RegistryUpdate {
    Write-Section "Registry Auto-Update"
    $taskName = 'ACP-Registry-Update'; $scriptPath = (Get-Item $PSCommandPath).FullName
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($Disable) {
        if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-StatusDot 'OK' 'OK' 'Registry auto-update rimosso' }
        else { Write-StatusDot 'INFO' 'INFO' 'Nessun auto-update configurato' }
        return
    }
    if ($existing) { Write-StatusDot 'OK' 'OK' 'Registry auto-update gia configurato'; return }
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Action Registry -UpdateRegistry"
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00AM'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "ACP Registry auto-update (weekly)" -Force
        Write-StatusDot 'OK' 'OK' 'Registry auto-update configurato (settimanale)'
    } catch { Write-StatusDot 'ERR' 'ERR' "Registrazione fallita: $_" }
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
    'RegistryUpdate' { Action-RegistryUpdate }
    'Help'          { Show-Help }
}
