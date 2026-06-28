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
- **Registry cache was re-downloaded on every run.** `Get-CachedRegistry` used the file's `CreationTime`, which Windows freezes at first creation when `Move-Item -Force` overwrites an existing file. Cache age is now computed from `LastWriteTime`, and `Update-RegistryCache` resets both timestamps after each refresh.
- Every agent was reported installed whenever the DevTunnels folder existed; the check is now gated on an actual id match.
- Known-path search no longer scans all of `%USERPROFILE%` for ids shorter than 4 characters.
- Parameter-binding error in registry uninstall-key matching.

## [4.2.0] - 2026

- Interactive mode with sub-menus, English README, `b`/`q` navigation keys.
- Bridge management, DevTunnel, ACP registry install/update engine.
- GitHub Action for PowerShell syntax validation + PSScriptAnalyzer lint.

[Unreleased]: https://github.com/steto/acp-manager/compare/v4.2.0...HEAD
[4.2.0]: https://github.com/steto/acp-manager/releases/tag/v4.2.0
