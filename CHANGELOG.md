# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

### Changed
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
