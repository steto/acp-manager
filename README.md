# 🚀 ACP Manager — Gestione Completa Agenti ACP su Windows

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![ACP Registry](https://img.shields.io/badge/ACP-Registry-purple)](https://github.com/agentclientprotocol/registry)

**ACP Manager** è uno script PowerShell che unifica **rilevazione, installazione, aggiornamento e gestione** di tutti gli agent compatibili con l'[Agent Client Protocol](https://agentclientprotocol.com) (ACP). Non è solo un manager per bridge — è un **centro di controllo completo** per il tuo ecosistema di coding agent.

> Un singolo comando per vedere cosa hai, cosa manca, cosa è vecchio — e installarlo o aggiornarlo.

---

## 📋 Indice

- [✨ Cosa Fa](#-cosa-fa)
- [⚡ Installazione](#-installazione)
- [🎯 Azioni Disponibili](#-azioni-disponibili)
- [🔍 Rilevazione Agenti](#-rilevazione-agenti)
- [📦 Installazione Agenti dal Registry](#-installazione-agenti-dal-registry)
- [🔄 Aggiornamento Agenti](#-aggiornamento-agenti)
- [🔌 Bridge Management](#-bridge-management)
- [🌐 DevTunnel](#-devtunnel)
- [📊 Scan Completo](#-scan-completo)
- [📈 Watch Mode](#-watch-mode)
- [⚙️ Configurazione](#️-configurazione)
- [🔄 Registry Auto-Update](#-registry-auto-update)
- [📝 Log](#-log)
- [🖥️ Auto-Avvio Windows](#️-auto-avvio-windows)
- [📱 Mobile](#-mobile)
- [🏗️ Architettura](#️-architettura)
- [🧪 Esempi Completi](#-esempi-completi)
- [🤝 Contribuire](#-contribuire)
- [📄 Licenza](#-licenza)

---

## ✨ Cosa Fa

| Categoria | Cosa fa |
|---|---|
| **🔍 Scansiona** | 37+ agent ACP — rileva installati, in esecuzione, versione, health |
| **📦 Installa** | Qualsiasi agente ACP dal registry ufficiale (npm, binary, uvx, cargo) |
| **🔄 Aggiorna** | Tutti gli agenti obsoleti con un comando |
| **🔌 Bridge** | Avvia/ferma/gestisci bridge opencode, kilocode, cursor |
| **🌐 Tunnel** | Tunnel remoti via DevTunnel per accesso da mobile/cloud |
| **📊 Diagnostica** | Sistema, rete, prerequisiti, porte, processi |

---

## ⚡ Installazione

### 1. Scarica

```powershell
# Opzione A: Download diretto
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/steto/acp-manager/main/acp-manager.ps1" -OutFile "acp-manager.ps1"

# Opzione B: Clona il repository
git clone https://github.com/steto/acp-manager
cd script-acp
```

### 2. Prima configurazione

```powershell
.\acp-manager.ps1 -Action Init
```

Questo avvia una configurazione guidata interattiva per:
- Porte bridge (default: opencode=8081, kilocode=8082, cursor=8083)
- Auto-restart
- Modalità mobile
- Tunnel anonimo

### 3. Verifica

```powershell
.\acp-manager.ps1 -Action Status    # Stato bridge + agenti rilevati
.\acp-manager.ps1 -Action Diag      # Diagnostica sistema
.\acp-manager.ps1 -Action Scan      # Scansione completa 37+ agent
```

---

## 🎯 Azioni Disponibili

### Rilevazione

| Azione | Parametro | Descrizione |
|---|---|---|
| `Scan` | `[-Detailed]` `[-OutputFormat Json]` | Scansione completa di tutti gli agent |
| `AgentInfo` | `-AgentId <id>` | Info dettagliate su un agente specifico |
| `Registry` | `[-UpdateRegistry]` | Mostra il registry ACP ufficiale |
| `InstallAgent` | `-AgentId <id>` | Installa un agente dal registry |
| `Update` | `-AgentId <id \| all>` | Aggiorna agenti alla versione più recente |

### Gestione Bridge

| Azione | Parametro | Descrizione |
|---|---|---|
| `Status` | | Stato bridge + agenti rilevati |
| `Install` | `-Bridge <nome \| all>` | Installa bridge ACP |
| `Start` | `-Bridge <nome \| all>` | Avvia bridge in background |
| `Stop` | `-Bridge <nome \| all>` | Ferma bridge |
| `Restart` | `-Bridge <nome \| all>` | Riavvia bridge |
| `Init` | | Configurazione guidata iniziale |

### DevTunnel

| Azione | Parametro | Descrizione |
|---|---|---|
| `Tunnel` | `-Bridge <nome>` `[-Anonymous]` `[-TunnelId]` | Bridge + tunnel remoto |
| `TunnelCreate` | `[-Anonymous]` | Crea tunnel persistente |
| `TunnelList` | | Lista tunnel |
| `TunnelInfo` | `[-TunnelId]` | Dettagli tunnel |
| `TunnelDelete` | `-TunnelId <id>` | Elimina tunnel |

### Sistema

| Azione | Parametro | Descrizione |
|---|---|---|
| `Config` | `[-Profile]` | Mostra configurazione |
| `Diag` | | Diagnostica sistema |
| `Logs` | `[-LogLines N]` | Mostra log |
| `LogClear` | | Pulisci log |
| `Autostart` | `-Bridge <nome>` `[-Disable]` | Auto-avvio Windows |
| `Mobile` | `[-Anonymous]` | Guida integrazione mobile |
| `Watch` | | Monitoraggio continuo ogni 10s |
| `RegistryUpdate` | `[-Disable]` | Configura auto-update settimanale registry |
| `Help` | | Questa guida |

---

## 🔍 Rilevazione Agenti

Il cuore di ACP Manager è il **Detection Engine**, un sistema multi-metodo che scansiona il tuo sistema con 12+ tecniche per trovare ogni agente ACP installato.

### Metodi di rilevazione

```
1. PATH / Binary     → Get-Command per ogni eseguibile
2. npm global        → npm list -g --depth=0 (cache 120s)
3. cargo             → cargo install --list (cache 120s)
4. pip               → pip list --format=json
5. uvx               → uv tool list
6. winget            → winget list (cache 30min)
7. choco             → choco list -li
8. scoop             → scoop list
9. dotnet            → dotnet tool list -g
10. go               → go env GOBIN + ricerca binari
11. Registry         → Uninstall keys (HKLM, HKCU)
12. KnownPaths       → Ricerca ricorsiva in ProgramFiles, LocalAppData, USERPROFILE
```

### Esempio di scan

```powershell
# Scan veloce (solo installazione)
.\acp-manager.ps1 -Action Scan

# Scan completo con health check (CPU, RAM, porte, rete)
.\acp-manager.ps1 -Action Scan -Detailed

# Output JSON per scripting
.\acp-manager.ps1 -Action Scan -OutputFormat Json
```

### Health check avanzato (con `-Detailed`)

Quando usi `-Detailed`, per ogni agente in esecuzione rileva:
- **CPU**: % Processor Time via Performance Counters
- **RAM**: Working Set in MB
- **Porte**: TCP listening e connessioni stabilite
- **Stato**: Working (CPU attiva), Idle (in ascolto), Idle (fermo)
- **Rete**: Connessioni TCP attive
- **Uptime**: Da quanto è in esecuzione

---

## 📦 Installazione Agenti dal Registry

Puoi installare **qualsiasi agente ACP** direttamente dal registry ufficiale.

### Registry ACP ufficiale

Il registry contiene 37+ agent con metadati completi:
- Nome, versione, licenza, descrizione
- Metodi di distribuzione (npm, binary, uvx, cargo)
- URL repository e website
- Configurazioni e dipendenze

### Installare un agente

```powershell
# Vedi tutti gli agent disponibili
.\acp-manager.ps1 -Action Registry

# Installa un agente
.\acp-manager.ps1 -Action InstallAgent -AgentId gemini
```

Lo script automaticamente:
1. Cerca l'agente nel registry ACP
2. Mostra i metodi di installazione disponibili
3. Sceglie il miglior metodo (npx > binary > uvx > cargo)
4. Chiede conferma
5. Esegue l'installazione
6. Verifica che l'agente sia stato installato correttamente

### Esempi

```powershell
# Installa Gemini CLI
.\acp-manager.ps1 -Action InstallAgent -AgentId gemini

# Installa Claude Agent
.\acp-manager.ps1 -Action InstallAgent -AgentId claude-acp

# Installa Devin
.\acp-manager.ps1 -Action InstallAgent -AgentId devin
```

---

## 🔄 Aggiornamento Agenti

Mantieni tutti i tuoi agent all'ultima versione.

```powershell
# Aggiorna TUTTI gli agent installati
.\acp-manager.ps1 -Action Update -AgentId all

# Aggiorna un agente specifico
.\acp-manager.ps1 -Action Update -AgentId gemini
```

Il confronto versioni usa `[System.Version]` per determinare:
- **current** → versione locale = registry
- **outdated** → versione locale < registry (da aggiornare)
- **newer** → versione locale > registry (sei più avanti del registry!)
- **unknown** → non confrontabile (versione non standard)

---

## 🔌 Bridge Management

### Installazione bridge

```powershell
# Installa tutti i bridge
.\acp-manager.ps1 -Action Install -Bridge all

# Installa un bridge specifico
.\acp-manager.ps1 -Action Install -Bridge opencode
```

### Avvio/Arresto

```powershell
# Avvia tutti i bridge
.\acp-manager.ps1 -Action Start -Bridge all

# Avvia un bridge specifico su porta custom
.\acp-manager.ps1 -Action Start -Bridge opencode -Port 9090

# Ferma tutti
.\acp-manager.ps1 -Action Stop -Bridge all

# Riavvia
.\acp-manager.ps1 -Action Restart -Bridge opencode
```

### Stato

```powershell
.\acp-manager.ps1 -Action Status
```

Output esempio:
```
  Bridge         PID   Porta  RAM     Stato   Health   Uptime
  ------------------------------------------------------------
  OpenCode AI    1234  8081   45.2MB  Attivo  TCP OK   2h 15m
  KiloCode       -     8082   -      Fermo   -        -
  Cursor         -     8083   -      Non install. -        -

  DevTunnel fermo

  Agenti Registry ACP:
  Agente         Stato  Versione     Metodo
  --------------------------------------------
  Gemini CLI     STOP   -            KnownPath
  Cursor         STOP   2026.05.28   PATH
```

---

## 🌐 DevTunnel

Esponi i tuoi bridge su internet per accesso remoto o integrazione mobile.

```powershell
# Tunnel + bridge (anonimo)
.\acp-manager.ps1 -Action Tunnel -Bridge opencode -Anonymous

# Tunnel con ID persistente
.\acp-manager.ps1 -Action Tunnel -Bridge kilocode -TunnelId mio-tunnel

# Crea un tunnel persistente
.\acp-manager.ps1 -Action TunnelCreate -Anonymous
```

---

## 📊 Scan Completo

Lo **Scan** è l'azione principale per il detection engine. Scansiona tutti i 37+ agent del registry ACP.

```powershell
# Scan rapido
.\acp-manager.ps1 -Action Scan

# Scan dettagliato (più lento ma completo)
.\acp-manager.ps1 -Action Scan -Detailed

# Output in JSON
.\acp-manager.ps1 -Action Scan -OutputFormat Json
```

### Cosa mostra

| Colonna | Descrizione |
|---|---|
| Agente | Nome dell'agente |
| Stato | RUN, STOP, WORK, IDLE |
| Versione | Versione installata |
| Agg. | current / outdated / newer |
| Installazione | PATH, npm, cargo, KnownPath, pip, winget... |

---

## 📈 Watch Mode

Monitoraggio continuo dello stato con refresh automatico.

```powershell
.\acp-manager.ps1 -Action Watch
```

- Aggiorna lo stato ogni 10 secondi
- Mostra bridge, DevTunnel e agenti rilevati
- Premi `Ctrl+C` per uscire

---

## ⚙️ Configurazione

```powershell
# Mostra configurazione attuale
.\acp-manager.ps1 -Action Config

# Mostra un profilo specifico
.\acp-manager.ps1 -Action Config -Profile production
```

### File di configurazione

La configurazione è salvata in `%USERPROFILE%\.acp-managers\config.json`:

```json
{
  "version": "4.2",
  "profile": "default",
  "profiles": {
    "default": {
      "ports": {
        "opencode": 8081,
        "kilocode": 8082,
        "cursor": 8083
      },
      "tunnel_id": "",
      "log_path": "%TEMP%\\acp-managers.log",
      "log_level": "INFO",
      "auto_restart": false,
      "anonymous_tunnel": false,
      "mobile_mode": false
    }
  }
}
```

---

## 🔄 Registry Auto-Update

Configura un aggiornamento automatico settimanale del registry ACP.

```powershell
# Configura auto-update (domenica alle 3:00 AM)
.\acp-manager.ps1 -Action RegistryUpdate

# Rimuovi auto-update
.\acp-manager.ps1 -Action RegistryUpdate -Disable

# Forza aggiornamento manuale
.\acp-manager.ps1 -Action Registry -UpdateRegistry
```

### Cache registry

- Il registry viene cachato in `%USERPROFILE%\.acp-managers\registry-cache.json`
- Scade dopo 24 ore
- Si aggiorna automaticamente allo scadere
- Puoi forzare l'aggiornamento con `-UpdateRegistry`

---

## 📝 Log

```powershell
# Mostra ultime 50 righe di log
.\acp-manager.ps1 -Action Logs

# Mostra ultime 200 righe
.\acp-manager.ps1 -Action Logs -LogLines 200

# Pulisci log
.\acp-manager.ps1 -Action LogClear
```

### Livelli di log

- `ERROR` → Rosso
- `WARN` → Giallo
- `OK` → Verde
- `INFO` → Grigio (default)
- `DEBUG` → Grigio scuro (solo se configurato)

---

## 🖥️ Auto-Avvio Windows

Avvia automaticamente un bridge al login di Windows.

```powershell
# Configura auto-avvio per opencode
.\acp-manager.ps1 -Action Autostart -Bridge opencode

# Rimuovi auto-avvio
.\acp-manager.ps1 -Action Autostart -Disable
```

Usa il Task Scheduler di Windows (non è richiesta esecuzione come Amministratore).

---

## 📱 Mobile

Guida per connetterti da mobile ai tuoi bridge ACP.

```powershell
.\acp-manager.ps1 -Action Mobile
```

Passi:
1. Installa un'app ACP (es. Agmente su iOS)
2. Avvia bridge + tunnel
3. Usa l'URL remoto mostrato

---

## 🏗️ Architettura

```
acp-manager.ps1
├── Config
│   ├── Profili multipli (default, production...)
│   ├── Porte configurabili
│   └── Log level
├── Registry
│   ├── Download da cdn.agentclientprotocol.com
│   ├── Cache 24h con auto-expiry
│   └── Auto-update via scheduled task
├── Detection Engine
│   ├── Get-AgentDetection (12+ metodi)
│   ├── Get-EnhancedDetection (wrapper con extra methods)
│   ├── Caching intelligente (npm 120s, cargo 120s, winget 30min)
│   └── Version comparison (current/outdated/newer)
├── Bridge Management
│   ├─┬ opencode
│   │ └── Start/Stop/Restart/Status
│   ├─┬ kilocode
│   │ └── Start/Stop/Restart/Status
│   └─┬ cursor
│     └── Start/Stop/Restart/Status
├── DevTunnel
│   ├── Host bridge
│   ├── Create/List/Info/Delete
│   └── Anonimo o autenticato
├── Update Engine
│   ├── Multi-method (npm, cargo, pip, binary...)
│   └── Binary re-download
└── UX
    ├── Formattazione ANSI
    ├── Tab completion
    ├── Write-Progress
    └── JSON output
```

---

## 🧪 Esempi Completi

```powershell
# 1. Configurazione iniziale
.\acp-manager.ps1 -Action Init

# 2. Scansione completo sistema
.\acp-manager.ps1 -Action Scan

# 3. Info su un agente specifico
.\acp-manager.ps1 -Action AgentInfo -AgentId gemini

# 4. Installa un agente dal registry
.\acp-manager.ps1 -Action InstallAgent -AgentId claude-acp

# 5. Installa i bridge
.\acp-manager.ps1 -Action Install -Bridge all

# 6. Avvia bridge
.\acp-manager.ps1 -Action Start -Bridge opencode

# 7. Stato
.\acp-manager.ps1 -Action Status

# 8. Tunnel per accesso remoto
.\acp-manager.ps1 -Action Tunnel -Bridge opencode -Anonymous

# 9. Aggiorna tutti gli agent
.\acp-manager.ps1 -Action Update -AgentId all

# 10. Diagnostica
.\acp-manager.ps1 -Action Diag

# 11. Registry
.\acp-manager.ps1 -Action Registry

# 12. Log
.\acp-manager.ps1 -Action Logs -LogLines 100
```

---

## 🤝 Contribuire

Contribuzioni benvenute! Ecco come puoi aiutare:

1. **Aggiungi un agente al registry** — apri una PR su [github.com/agentclientprotocol/registry](https://github.com/agentclientprotocol/registry)
2. **Migliora il detection engine** — apri una issue o PR su questo repository
3. **Segnala bug** — apri una issue con la diagnostica (`-Action Diag`)
4. **Suggerisci funzionalità** — nuove azioni, metodi di detection, integrazioni

### Sviluppo

Lo script è un singolo file PowerShell per semplicità di distribuzione. Le sezioni principali sono organizzate per azione.

---

## 📄 Licenza

MIT License — vedi [LICENSE](LICENSE) per i dettagli.

---

<div align="center">
  <sub>Built with ❤️ for the ACP ecosystem</sub>
  <br>
  <sub>Parte del progetto <a href="https://github.com/agentclientprotocol">Agent Client Protocol</a></sub>
</div>


