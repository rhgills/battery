# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Battery is a charge limiter for Apple Silicon Macbooks. It consists of:
1. **CLI Tool** (`battery.sh`) - Bash script that controls battery charging via SMC (System Management Controller)
2. **GUI App** (`app/`) - Electron-based tray application that wraps the CLI
3. **SMC Binary** (`dist/smc`) - Pre-compiled tool from hholtmann/smcFanControl for low-level hardware access

The tool keeps batteries at a configurable limit (default 80%) to prolong battery longevity.

## Development Commands

### GUI App (Electron)
```bash
cd app
npm install                    # Install dependencies
npm start                      # Run app in development mode
npm run start:watch            # Run with auto-reload via nodemon
npm run build                  # Build macOS ARM64 dmg
npm run lint                   # Run ESLint
```

### CLI Tool
The CLI (`battery.sh`) is a standalone bash script. Test directly:
```bash
./battery.sh status            # Check battery status
./battery.sh maintain 80       # Set 80% limit (requires smc binary)
./battery.sh logs              # View CLI logs (default: last 100 lines)
./battery.sh logs gui 50       # View GUI logs (last 50 lines)
./battery.sh logs all          # View all logs + config + status
```

### Installation Testing
```bash
./setup.sh                     # Install CLI + smc to /usr/local/bin
./update.sh                    # Update existing installation
```

### Development Workflow (dev.sh)
The `dev.sh` helper script streamlines development and testing:
```bash
./dev.sh link                  # Symlink for live development (instant testing)
./dev.sh install               # Copy install (production mode)
./dev.sh restart-daemon        # Reload daemon after code changes
./dev.sh status                # Check installation type & daemon status
./dev.sh test status           # Test local version without installing
```

**Development workflow:**
1. `./dev.sh link` - Creates symlink at `/usr/local/bin/battery` → one-off commands are live
2. Edit `battery.sh` and test instantly with `battery status`, `battery logs`, etc.
3. `./dev.sh restart-daemon` - Restart daemon to test maintain functionality changes
4. `./dev.sh install` - Switch to production install when done (removes symlink first)

**Note:** `./dev.sh install` properly handles existing symlinks by removing them before copying, making transitions between development and production modes seamless.

## Architecture

### Battery Control Flow

**CLI (`battery.sh`)**:
- Interacts with SMC via the `smc` binary using specific keys:
  - `CH0B`/`CH0C` - Control charging on/off (Apple Silicon)
  - `CH0I`/`CH0J`/`CH0K` - Control discharging/adapter blocking
  - `ACLC` - MagSafe LED color control
  - `BCLM` - Battery charge limit (Intel Macs)
- Stores configuration in `~/.battery/`:
  - `battery.pid` - PID of maintain daemon
  - `maintain.percentage` - Target percentage
  - `maintain.voltage` - Target voltage (alternative mode)
  - `battery.log` - CLI logs
- Uses LaunchAgent (`~/Library/LaunchAgents/battery.plist`) for persistence across reboots
- Requires sudoers configuration at `/private/etc/sudoers.d/battery` for passwordless SMC access

**GUI (`app/`)**:
- `main.js` - Electron entry point, hides dock, sets up tray
- `modules/interface.js` - Tray menu management, refresh timers
- `modules/battery.js` - Executes CLI commands via `exec()`
- `modules/settings.js` - Electron-store for GUI settings (force-discharge preference)
- `modules/theme.js` - Battery icon generation based on percentage/state
- `modules/helpers.js` - Logging and alert utilities

The GUI wraps CLI commands and adds:
- Visual tray icon with battery percentage
- Menu-based interaction
- Auto-update via `update-electron-app`
- One-time installation flow with sudo prompts

### Key Integration Points

1. **GUI → CLI**: All battery control flows through bash script execution
2. **SMC Key Detection**: Script checks key availability with `has_CH0B`, `has_CH0I`, etc. flags
3. **State Management**: CLI maintains daemon runs in background, GUI polls for status
4. **Logs**: CLI writes to `~/.battery/battery.log`, GUI to `~/.battery/gui.log`

## Platform-Specific Considerations

### macOS Version Compatibility
The current branch (`fix/charging-and-discharging-macos-tahoe`) addresses macOS 26 (Tahoe) compatibility issues. SMC key availability varies by macOS version:
- Some keys (`BCLM`) only exist on Intel Macs
- `CHTE` is a fallback when `CH0B` is unavailable
- Key detection happens at script startup (lines 131-142 in battery.sh)

### CPU Architecture
- Script uses `get_cpu_type()` to differentiate Apple Silicon vs Intel
- Detection based on `BCLM` SMC key presence (Intel has it, Apple Silicon doesn't)
- Different SMC keys used for each architecture

## Important Notes

- **No test suite exists** - manual testing required
- **Notarization**: Build hooks in `app/build_hooks/afterSign.js` handle Apple notarization
- **Version tracking**: CLI version in `battery.sh:7`, GUI in `app/package.json`
- **Update mechanism**: GUI auto-updates via Electron, CLI self-updates via `battery update`
- **PATH handling**: Scripts prepend common bin paths since Electron environment may have limited PATH
- **Visudo updates**: When adding new sudo commands, increment visudo logic in `battery.sh` (lines 108-474)

## Common Development Tasks

1. **Adding new SMC functionality**:
   - Add key detection in battery.sh (around line 131)
   - Add commands to visudo configuration (line 112)
   - Implement function using `write_smc`/`read_smc` helpers

2. **GUI changes**:
   - Tray menu: Edit `generate_app_menu()` in `modules/interface.js`
   - Icons: Modify `modules/theme.js` (uses nativeImage from png assets)
   - Settings: Use electron-store via `modules/settings.js`

3. **Testing on new macOS**:
   - Check SMC key availability: `smc -k CH0B -r` (should not return "no data")
   - Verify visudo: `sudo -n /usr/local/bin/smc -k CH0B -r` (should work without password)
   - Test both percentage and voltage modes
