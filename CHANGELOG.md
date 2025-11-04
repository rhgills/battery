# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.3.2-rhgills-development] - 2025-11-03

### Added
- **`sudo_smc()` wrapper function**: All sudo smc calls now go through a labeled wrapper that logs the reason for sudo invocations
  - Provides context like "🔐 sudo smc: Write 08 to SMC key CHIE"
  - Only logs writes and debug mode to reduce noise
  - Makes debugging permission issues much easier
- **visudo test command array**: New `visudo_test_commands` array defines specific SMC commands to test for passwordless access
  - Tests one representative command from each permission group
  - Makes it easy to add new tests as the visudo config evolves
- **Enhanced state detection**: `battery doctor` and `battery debug` now recognize "maintaining" and "charged" states
  - "maintaining": Charging disabled, using AC power, battery not draining (target maintenance state)
  - "charged": Battery fully charged or at target, charging disabled
  - Previously showed confusing "unknown" state during normal maintenance
  - Cross-check now correctly identifies when maintenance is active and working

### Fixed
- **False positive visudo warning**: `battery doctor` no longer incorrectly reports "SMC requires password"
  - Previously tested `smc -l` which isn't whitelisted in visudo
  - Now tests actual SMC read commands that are used by the tool (CH0B, CHTE, CH0I, CH0J, CHIE, ACLC, BCLM)
  - Shows specifically which commands fail if visudo is misconfigured
- **pmset state parsing bug**: Fixed grep matching multiple states (e.g., "AC attached" + "charging" on separate lines)
  - Added "not charging" to recognized states
  - Added `head -1` to only capture first match
  - Reordered pattern to prioritize specific states over generic ones
- **Permission denied on `battery` commands**: Fixed missing execute permissions on battery.sh after rebase
  - Added `chmod +x battery.sh`
  - All commands now work without "Permission denied" errors

### Changed
- **Code clarity refactoring**: Added clear wrapper functions and extensive documentation for discharging control
  - Created self-documenting wrapper functions: `force_battery_discharge()` and `allow_ac_passthrough()`
  - Added extensive comments to `enable_discharging()` and `disable_discharging()` explaining they only affect behavior when AC adapter is connected
  - Updated callsites throughout codebase to use clearer function names
  - Root functions remain unchanged to minimize drift from upstream for easier merges
  - Maintains full backward compatibility while dramatically improving code readability
- **Improved visudo configuration**: Added `SMCREAD` alias with read-only SMC commands for capability detection

## [v1.3.1-rhgills-development] - 2025-11-03

### Added
- **Enhanced `battery status` output**: Now provides detailed state analysis explaining the relationship between current charge, maintenance target, and current state
  - Shows exact difference from target (e.g., "20% above target")
  - Explains current charging/discharging state with context
  - Provides actionable suggestions (e.g., "battery discharge 80")
  - Makes it easy to verify the tool is working correctly
- **Hardware metrics in `battery debug`**: Added adapter wattage and power flow with direction indicators
  - Shows real-time power flow with direction: (charging), (discharging), or (idle/maintaining)
  - Helps validate inconsistencies between SMC, pmset, and hardware state
- **Comprehensive hardware details in `battery doctor`**: Added Section 8 with detailed battery metrics from ioreg
  - Adapter wattage
  - Power flow (watts, amperage, voltage)
  - Temperature
  - Battery health with status indicators
  - Cycle count with usage percentage
  - Individual cell voltages
- **Git tracking in `dev.sh status`**: When symlinked (dev mode), shows git commit SHA and dirty state warnings

### Fixed
- **Confusing log message during daemon stop**: Removed misleading "No valid maintain percentage set" message that appeared during daemon restart
- **Power flow calculation bug**: Fixed two's complement overflow when parsing negative amperage values from ioreg during battery discharge
  - Previously showed corrupted values like `231838679518381600.0W`
  - Now correctly shows negative values like `-25.5W (-2.05A @ 12.46V)`

### Changed
- Power flow now includes direction indicators for clarity: (charging), (discharging), (idle/maintaining)

## [v1.3.0-rhgills-development] - 2025-11-03

### Changed
- Rebased on upstream main to incorporate latest fixes and improvements from main repository

## [v1.2.9-rhgills-development] - 2025-11-03

### Added
- **`battery version` command**: Quick version check supporting `battery version`, `battery --version`, and `battery -v`
- **`battery info` command**: Comprehensive system information including version, installation details, daemon status, and warnings for version mismatches
- **Enhanced `battery status`**: Now shows daemon info (version and uptime) when maintenance is active
- **Development helper script (`dev.sh`)**: Streamlines development workflow with commands for:
  - `link` - Symlink for live development
  - `install` - Copy install to system
  - `restart-daemon` - Restart daemon with current code
  - `status` - Check installation and daemon status
  - `test` - Run local version without installing
- **Daemon metadata tracking**: Daemon now writes version, PID, start time, and script mtime to `~/.battery/daemon.metadata` for monitoring
- **Process name in Activity Monitor**: Scripts now show as "battery" instead of "bash" using `exec -a`

### Fixed
- **Critical SMC write bug**: Fixed `write_smc_labeled()` using `-l` (list) instead of `-w` (write), which caused SMC data dumps during daemon operations
- **"recover%" logging bug**: `battery maintain recover` now logs the actual recovered percentage (e.g., "80%") instead of the literal string "recover%"
- **PID parsing bug**: Fixed launchctl output parsing that included trailing semicolon in PID, causing status checks to fail

### Changed
- **Major daemon architecture refactor**: Migrated from `nohup` to native macOS `launchd` management
  - Daemon now properly managed by launchd (appears as PPID=1 in process tree)
  - Uses `launchctl bootstrap/kickstart` to start daemon instead of background process spawning
  - Uses `launchctl bootout` to stop daemon cleanly
  - Provides better macOS integration and follows platform conventions
  - Daemon remains independent of shell session (no longer uses nohup)
- **Daemon status detection**: `dev.sh status` now shows detailed daemon information including version, uptime, and staleness warnings
- **Automatic daemon restart**: `dev.sh install` and `dev.sh link` now intelligently handle running daemons

### Documentation
- **CLAUDE.md**: Added comprehensive development documentation for future Claude Code instances
- **`battery maintain recover` documented**: Now appears in help message with example

## [v1.2.8-rhgills-development] - 2025-11-03

### Fixed
- **Stale PID detection in `battery status`**: Now properly detects when the maintain daemon has stopped running, even when a PID file exists. Previously, the tool would incorrectly report that battery maintenance was active when the daemon process was no longer running.
  - Added process verification to check if PID is actually running
  - Added verification that the running process is actually a battery maintain process (prevents false positives from PID reuse)
  - Automatically cleans up stale PID files
  - Provides clear user guidance on how to recover

### Added
- **Enhanced SMC logging**: New `write_smc_labeled()` function provides better traceability by logging human-readable labels alongside SMC operations (e.g., "Enable Charging", "Disable Discharging", "MagSafe LED: Green")
- **Improved helper functions**: Added `log_from_function()` to prefix log messages with function names for better debugging
- **Documentation for `battery maintain recover`**: The `recover` command is now documented in the help message, making it easier for users to restart maintenance with previous settings

### Changed
- All SMC write operations now use labeled logging for improved debugging on different macOS versions

## [v1.2.7-rhgills-development]

### Fixed
- Initial work on restoring functionality for macOS 26 (Tahoe)
