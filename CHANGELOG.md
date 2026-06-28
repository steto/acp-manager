# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- **`Uninstall` action** — remove an ACP agent installed via npm, pip, uvx, cargo, winget, choco, scoop, dotnet or a known path.
- **`Version` action** — print the ACP Manager version (supports `-OutputFormat Json`).
- **`UpdateSelf` action** — download the latest release of the script with a syntax sanity check and a `.bak` backup.
- **`-Yes` switch** — skip confirmation prompts for automation / CI (Init, Update, InstallAgent, Uninstall, Autostart, UpdateSelf).
- **`-Interval` parameter** — configurable Watch refresh interval (default 10s).
- `LICENSE` (MIT).

### Changed
- Detection engine now caches **all** package managers (pip, uvx, choco, scoop, dotnet, go) instead of only npm/cargo/winget. Scan runs each manager at most once per session instead of once per agent.
- ID matching is now case-insensitive and word-boundary based, eliminating false positives for short ids (`go`, `uv`, `n8n`, ...).
- `Test-PortOpen` uses `Get-NetTCPConnection` (was slow `Test-NetConnection`).
- Coherent JSON output for `-Action Status` and `-Action Scan` (single structured document, console log silenced in JSON mode).
- `New-DefaultConfig` now derives the config `version` from the running script version instead of a hardcoded value.
- Interactive menus gained entries for Uninstall, Version and UpdateSelf.

### Fixed
- **Scoped npm packages were never detected/installed/updated.** `(@scope/name -split "@")[0]` returned an empty string; replaced by a `Get-NpmPackageName` helper (used by detection, install, update and uninstall).
- **Array-vs-scalar crashes/wrong data** when a process or registry query matched multiple results: `Status`, `Start-Bridge`, the devtunnel check and the registry uninstall-key lookup now take the first match (`Select-Object -First 1`) before reading `.ProcessId`/`.WorkingSetSize`/`.DisplayVersion`.
- **Garbage version strings** (`Traceback ...`, `node:internal ...`) captured when `--version` fails: a `Get-CleanVersion` helper now extracts a version-like token and skips error noise.
- **Cargo version regex was unanchored** and could capture a neighbour package's version; now anchored and regex-escaped.
- **`Compare-AgentVersions` returned `unknown`** for single-component (`1`) or 5+ component (`1.2.3.4.5`) versions and date versions; replaced `[System.Version]` with numeric segment comparison.
- **CPU% / Working never populated in detailed scan**: the performance-counter instance name included `.exe`; now stripped. Also normalized CIM `Win32_Process` vs `System.Diagnostics.Process` properties (RAM, PID, uptime).
- **`TunnelCreate` saved the wrong id** (matched the first word of devtunnel output, e.g. "Tunnel") and could fail silently; the id is now parsed from an "ID:" label or a long token, with a fallback message.
- **`Tunnel` used a hardcoded port 3000 for Cursor**, ignoring the configured port; now respects `Get-BridgePort`.
- **`Tunnel` reported success even when devtunnel exited immediately**; now checks `HasExited` after start.
- **`Restart -Bridge all` killed DevTunnel without restarting it**; restart now stops only bridges, leaving the tunnel running.
- **Stale `$LASTEXITCODE`** in the binary/script update and uninstall paths (cmdlets don't set it) reported false failures; success is now judged via `$?` after resetting `$LASTEXITCODE`.
- **Interactive "Download Registry" was a no-op**: `Invoke-InteractiveAction` did not propagate `UpdateRegistry` (and now also `Interval`).
- **`Get-AgentChoice` printed "... and 0 more"** with exactly 50 agents; gated on `Count > 50`.
- **`Action-Watch` left `$OutputFormat` mutated** if `Action-Status` threw; now restored in a `finally`.
- Single quotes / `$` in install paths could break the generated binary-update / remove script blocks; paths are now single-quote-escaped.
- Registry cache was re-downloaded on every run (`CreationTime` frozen by `Move-Item`); age now uses `LastWriteTime` and both timestamps are reset on refresh.
- Every agent was reported installed whenever the DevTunnels folder existed; the check is gated on an id match.
- Known-path search no longer scans all of `%USERPROFILE%` for ids shorter than 4 characters.
- Parameter-binding error in registry uninstall-key matching.

## [4.2.0] - 2026

- Interactive mode with sub-menus, English README, `b`/`q` navigation keys.
- Bridge management, DevTunnel, ACP registry install/update engine.
- GitHub Action for PowerShell syntax validation + PSScriptAnalyzer lint.

[Unreleased]: https://github.com/steto/acp-manager/compare/v4.2.0...HEAD
[4.2.0]: https://github.com/steto/acp-manager/releases/tag/v4.2.0
