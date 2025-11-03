#!/bin/bash
# dev.sh - Development helper script for battery CLI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATTERY_SCRIPT="$SCRIPT_DIR/battery.sh"
INSTALL_PATH="/usr/local/bin/battery"

case "$1" in
    install|i)
        echo "Installing battery.sh to $INSTALL_PATH..."

        # Check if there's a running maintain daemon
        daemon_was_running=false
        if [[ -f "$HOME/.battery/battery.pid" ]]; then
            pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
            if ps -p "$pid" > /dev/null 2>&1; then
                daemon_was_running=true
                echo "Stopping maintain daemon before installing..."
                battery maintain stop
                sleep 1
            fi
        fi

        sudo cp "$BATTERY_SCRIPT" "$INSTALL_PATH"
        sudo chmod +x "$INSTALL_PATH"
        echo "✅ Installed successfully"

        # Restart daemon if it was running
        if [[ "$daemon_was_running" == "true" ]]; then
            echo "Restarting maintain daemon with new version..."
            battery maintain recover
            echo "✅ Daemon restarted"
        fi

        echo ""
        echo "Test it with: battery version"
        ;;
    link|l)
        echo "Symlinking battery.sh for live development..."
        sudo ln -sf "$BATTERY_SCRIPT" "$INSTALL_PATH"
        echo "✅ Symlinked - one-off commands are now LIVE"
        echo ""
        echo "You can now edit battery.sh and test changes instantly:"
        echo "  battery status"
        echo "  battery charging on"
        echo "  battery logs 10"
        echo ""
        echo "📝 Note: The maintain daemon loads code into memory at startup."
        echo "   After editing battery.sh, restart the daemon to test changes:"
        echo "     $0 restart-daemon"
        echo ""

        # Check if there's a running daemon and inform the user
        if [[ -f "$HOME/.battery/battery.pid" ]]; then
            pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "⚠️  Daemon is currently running (PID $pid) with the old version"
                echo "   Run '$0 restart-daemon' after making changes to test them"
            fi
        fi
        ;;
    unlink|u)
        if [[ -L "$INSTALL_PATH" ]]; then
            # Check if there's a running maintain daemon
            daemon_was_running=false
            if [[ -f "$HOME/.battery/battery.pid" ]]; then
                pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
                if ps -p "$pid" > /dev/null 2>&1; then
                    daemon_was_running=true
                    echo "⚠️  Detected running maintain daemon"
                    echo "After unlinking, the daemon will be in an undefined state."
                    echo ""
                    read -p "Stop daemon now? [Y/n] " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        battery maintain stop
                        sleep 1
                    fi
                fi
            fi

            sudo rm "$INSTALL_PATH"
            echo "✅ Removed symlink from $INSTALL_PATH"
            echo ""
            echo "Run '$0 install' to reinstall battery CLI"

            if [[ "$daemon_was_running" == "true" ]]; then
                echo ""
                echo "💡 Tip: After reinstalling, run 'battery maintain recover' to resume maintenance"
            fi
        else
            echo "⚠️  $INSTALL_PATH is not a symlink"
            if [[ -f "$INSTALL_PATH" ]]; then
                echo "It appears to be a regular file (already installed normally)"
            else
                echo "Battery CLI is not installed"
            fi
        fi
        ;;
    test|t)
        shift
        echo "Running local battery.sh $@"
        echo "---"
        "$BATTERY_SCRIPT" "$@"
        ;;
    restart-daemon|restart|rd)
        if [[ ! -f "$HOME/.battery/battery.pid" ]]; then
            echo "❌ No daemon running (no PID file found)"
            echo ""
            echo "Start maintenance with: battery maintain 80"
            exit 1
        fi

        pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
        if ! ps -p "$pid" > /dev/null 2>&1; then
            echo "⚠️  Stale PID file detected (daemon not actually running)"
            rm "$HOME/.battery/battery.pid" 2>/dev/null
            echo ""
            echo "Start maintenance with: battery maintain 80"
            exit 1
        fi

        echo "Restarting daemon with current code..."
        echo "Stopping daemon (PID $pid)..."
        battery maintain stop
        sleep 1

        echo "Starting daemon with updated code..."
        battery maintain recover

        new_pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
        echo "✅ Daemon restarted (new PID $new_pid)"
        echo ""
        echo "Check status with: battery status"
        ;;
    status)
        echo "Checking installation status..."
        echo ""
        if [[ -L "$INSTALL_PATH" ]]; then
            target=$(readlink "$INSTALL_PATH")
            echo "🔗 Status: SYMLINKED (live development mode)"
            echo "   Target: $target"
            if [[ "$target" == "$BATTERY_SCRIPT" ]]; then
                echo "   ✅ Points to this repository"
            else
                echo "   ⚠️  Points to different location"
            fi
        elif [[ -f "$INSTALL_PATH" ]]; then
            echo "📦 Status: INSTALLED (normal mode)"
            echo "   Location: $INSTALL_PATH"
        else
            echo "❌ Status: NOT INSTALLED"
        fi

        if [[ -f "$INSTALL_PATH" ]]; then
            echo ""
            installed_version=$("$INSTALL_PATH" version 2>/dev/null || echo "unknown")
            local_version=$("$BATTERY_SCRIPT" version 2>/dev/null || echo "unknown")
            echo "Installed version: $installed_version"
            echo "Local version:     $local_version"
        fi

        # Check daemon status
        echo ""
        if [[ -f "$HOME/.battery/battery.pid" ]]; then
            pid=$(cat "$HOME/.battery/battery.pid" 2>/dev/null)
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "🔄 Daemon: RUNNING (PID $pid)"

                # Try to load metadata
                if [[ -f "$HOME/.battery/daemon.metadata" ]]; then
                    source "$HOME/.battery/daemon.metadata" 2>/dev/null

                    # Show version
                    if [[ -n "$version" ]]; then
                        echo "   Version: $version"
                    fi

                    # Show start time with elapsed time
                    if [[ -n "$start_date" ]]; then
                        echo "   Started: $start_date"
                    fi
                    if [[ -n "$start_time" ]]; then
                        current_time=$(date +%s)
                        elapsed=$((current_time - start_time))
                        hours=$((elapsed / 3600))
                        minutes=$(((elapsed % 3600) / 60))
                        if [[ $hours -gt 0 ]]; then
                            echo "   Uptime:  ${hours}h ${minutes}m"
                        else
                            echo "   Uptime:  ${minutes}m"
                        fi
                    fi

                    # Check if script has been modified since daemon started
                    if [[ -n "$script_mtime" && -f "$INSTALL_PATH" ]]; then
                        current_mtime=$(stat -f %m "$INSTALL_PATH" 2>/dev/null || echo "0")
                        if [[ "$current_mtime" -gt "$script_mtime" ]]; then
                            echo "   ⚠️  Script updated since daemon started"
                            echo "   💡 Run '$0 restart-daemon' to load new code"
                        elif [[ -L "$INSTALL_PATH" ]]; then
                            echo "   💡 Run '$0 restart-daemon' after editing to reload changes"
                        fi
                    fi
                else
                    # Fallback to ps if metadata missing
                    daemon_start=$(ps -p "$pid" -o lstart= 2>/dev/null || echo "unknown")
                    echo "   Started: $daemon_start"
                    echo "   Version: unknown (no metadata file)"
                    if [[ -L "$INSTALL_PATH" ]]; then
                        echo "   💡 Run '$0 restart-daemon' to reload code changes"
                    fi
                fi
            else
                echo "⚠️  Daemon: STALE PID (not actually running)"
            fi
        else
            echo "⏸️  Daemon: NOT RUNNING"
        fi
        ;;
    *)
        echo "Battery CLI Development Helper"
        echo ""
        echo "Usage: $0 {install|link|unlink|restart-daemon|test|status}"
        echo ""
        echo "Commands:"
        echo "  install (i)       - Copy battery.sh to $INSTALL_PATH"
        echo "  link (l)          - Symlink for live development"
        echo "  unlink (u)        - Remove symlink and restore to normal mode"
        echo "  restart-daemon (rd) - Restart maintain daemon with current code"
        echo "  test (t)          - Run local battery.sh without installing"
        echo "  status            - Check installation and daemon status"
        echo ""
        echo "Typical Development Workflow:"
        echo "  $0 link                  # Start live development mode"
        echo "  # Edit battery.sh..."
        echo "  battery status           # Test commands (live!)"
        echo "  $0 restart-daemon        # Reload daemon after changes"
        echo "  $0 unlink                # Exit development mode when done"
        echo ""
        echo "Other Examples:"
        echo "  $0 status                # Check current installation & daemon"
        echo "  $0 test status           # Test local version without installing"
        echo "  $0 install               # Copy install (for production)"
        exit 1
        ;;
esac
