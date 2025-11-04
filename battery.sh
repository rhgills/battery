#!/bin/bash

# Set process name for Activity Monitor (only if not already set)
if [[ -z "$BATTERY_PROCESS_NAME_SET" ]]; then
	export BATTERY_PROCESS_NAME_SET=1
	exec -a battery bash "$0" "$@"
fi

## ###############
## Update management
## variables are used by this binary as well at the update script
## ###############
BATTERY_CLI_VERSION="v1.3.2-rhgills-development"

# Path fixes for unexpected environments
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

## ###############
## Variables
## ###############
binfolder=/usr/local/bin
visudo_folder=/private/etc/sudoers.d
visudo_file=${visudo_folder}/battery
configfolder=$HOME/.battery
pidfile=$configfolder/battery.pid
logfile=$configfolder/battery.log
maintain_percentage_tracker_file=$configfolder/maintain.percentage
maintain_voltage_tracker_file=$configfolder/maintain.voltage
daemon_path=$HOME/Library/LaunchAgents/battery.plist
calibrate_pidfile=$configfolder/calibrate.pid

# Voltage limits
voltage_min="10.5"
voltage_max="12.6"
voltage_hyst_min="0.1"
voltage_hyst_max="2"

## ###############
## Housekeeping
## ###############

# Create config folder if needed
mkdir -p $configfolder

# create logfile if needed
touch $logfile

# Trim logfile if needed
logsize=$(stat -f%z "$logfile")
max_logsize_bytes=5000000
if ((logsize > max_logsize_bytes)); then
	tail -n 100 $logfile >$logfile
fi

# CLI help message
helpmessage="
Battery CLI utility $BATTERY_CLI_VERSION

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery version
    show the current version of the battery utility

  battery info
    show detailed system information (version, daemon status, configuration)

  battery logs LINES[integer, optional]
    output logs of the battery CLI and GUI
	eg: battery logs 100

  battery debug
    cross-check battery state between SMC and system (pmset), show raw SMC values

  battery doctor
    comprehensive health check of battery tool installation and configuration

  battery maintain PERCENTAGE[1-100,stop,recover] or RANGE[lower-upper]
    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
	it has the option of a --force-discharge flag that discharges even when plugged in (this does NOT work well with clamshell mode)
    eg: battery maintain 80           # maintain at 80%
    eg: battery maintain 70-80        # maintain between 70-80%
    eg: battery maintain stop
    eg: battery maintain recover      # resume previous setting

  battery maintain VOLTAGE[${voltage_min}V-${voltage_max}V,stop] (HYSTERESIS[${voltage_hyst_min}V-${voltage_hyst_max}V])
    reboot-persistent battery level maintenance: keep battery at a certain voltage
  default hysteresis: 0.1V
    eg: battery maintain 11.4V       # keeps battery between 11.3V and 11.5V
    eg: battery maintain 11.4V 0.3V  # keeps battery between 11.1V and 11.7V

  battery charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: battery charging on

  battery adapter SETTING[on/off]
    manually set the adapter to (not) charge even when plugged in
    eg: battery adapter off

  battery calibrate
    calibrate the battery by discharging it to 15%, then recharging it to 100%, and keeping it there for 1 hour

  battery charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: battery charge 90

  battery discharge LEVEL[1-100]
    block power input from the adapter until battery falls to this level
    eg: battery discharge 90

  battery visudo
    ensure you don't need to call battery with sudo
    This is already used in the setup script, so you should't need it.

  battery update
    update the battery utility to the latest version

  battery reinstall
    reinstall the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging, remove the smc tool, and the battery script

"

# Visudo instructions
visudoconfig="
# Visudo settings for the battery utility installed from https://github.com/actuallymentor/battery
# intended to be placed in $visudo_file on a mac
Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02, $binfolder/smc -k CH0C -w 02, $binfolder/smc -k CHTE -w 01000000, $binfolder/smc -k CH0B -r, $binfolder/smc -k CH0C -r, $binfolder/smc -k CHTE -r
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00, $binfolder/smc -k CH0C -w 00, $binfolder/smc -k CHTE -w 00000000
Cmnd_Alias      DISCHARGEOFF = $binfolder/smc -k CH0I -w 00, $binfolder/smc -k CH0I -r, $binfolder/smc -k CH0J -w 00, $binfolder/smc -k CH0J -r, $binfolder/smc -k CH0K -w 00, $binfolder/smc -k CH0K -r, $binfolder/smc -d off
Cmnd_Alias      DISCHARGEON = $binfolder/smc -k CH0I -w 01, $binfolder/smc -k CH0J -w 01, $binfolder/smc -k CH0K -w 01, $binfolder/smc -d on
Cmnd_Alias      LEDCONTROL = $binfolder/smc -k ACLC -w 04, $binfolder/smc -k ACLC -w 03, $binfolder/smc -k ACLC -w 02, $binfolder/smc -k ACLC -w 01, $binfolder/smc -k ACLC -w 00, $binfolder/smc -k ACLC -r
Cmnd_Alias      CHTE = $binfolder/smc -k CHTE -r, $binfolder/smc -k CHTE -w 00000000, $binfolder/smc -k CHTE -w 01000000
Cmnd_Alias      CHIE = $binfolder/smc -k CHIE -r, $binfolder/smc -k CHIE -w 08, $binfolder/smc -k CHIE -w 00
Cmnd_Alias      CH0J = $binfolder/smc -k CH0J -r, $binfolder/smc -k CH0J -w 01, $binfolder/smc -k CH0J -w 00
Cmnd_Alias      SMCREAD = $binfolder/smc -k BCLM -r, $binfolder/smc -k ACEN -r, $binfolder/smc -k CHWA -r, $binfolder/smc -k BFCL -r, $binfolder/smc -k ACFP -r
ALL ALL = NOPASSWD: BATTERYOFF
ALL ALL = NOPASSWD: BATTERYON
ALL ALL = NOPASSWD: DISCHARGEOFF
ALL ALL = NOPASSWD: DISCHARGEON
ALL ALL = NOPASSWD: LEDCONTROL
ALL ALL = NOPASSWD: CHTE
ALL ALL = NOPASSWD: CHIE
ALL ALL = NOPASSWD: CH0J
ALL ALL = NOPASSWD: SMCREAD
"

# Test commands for visudo verification (read-only, safe to run)
# Format: "command:description"
declare -a visudo_test_commands=(
	"smc -k CH0B -r:Legacy charging control (CH0B)"
	"smc -k CHTE -r:Tahoe charging (CHTE)"
	"smc -k CH0I -r:Legacy discharging (CH0I)"
	"smc -k CH0J -r:Adapter control (CH0J)"
	"smc -k CHIE -r:Tahoe adapter (CHIE)"
	"smc -k ACLC -r:MagSafe LED control"
	"smc -k BCLM -r:Intel charge limit"
)

# Get parameters
battery_binary=$0
action=$1
setting=$2
subsetting=$3

# check the availability of SMC keys
[[ $(smc -k BCLM -r) =~ "no data" ]] && has_BCLM=false || has_BCLM=true;
[[ $(smc -k CH0B -r) =~ "no data" ]] && has_CH0B=false || has_CH0B=true;
[[ $(smc -k CH0C -r) =~ "no data" ]] && has_CH0C=false || has_CH0C=true;
[[ $(smc -k CH0I -r) =~ "no data" ]] && has_CH0I=false || has_CH0I=true;
[[ $(smc -k CH0J -r) =~ "no data" ]] && has_CH0J=false || has_CH0J=true;
[[ $(smc -k CH0K -r) =~ "no data" ]] && has_CH0K=false || has_CH0K=true;
[[ $(smc -k ACEN -r) =~ "no data" ]] && has_ACEN=false || has_ACEN=true;
[[ $(smc -k ACLC -r) =~ "no data" ]] && has_ACLC=false || has_ACLC=true;
[[ $(smc -k CHWA -r) =~ "no data" ]] && has_CHWA=false || has_CHWA=true;
[[ $(smc -k BFCL -r) =~ "no data" ]] && has_BFCL=false || has_BFCL=true;
[[ $(smc -k ACFP -r) =~ "no data" ]] && has_ACFP=false || has_ACFP=true;
[[ $(smc -k CHTE -r) =~ "no data" ]] && has_CHTE=false || has_CHTE=true;

## ###############
## Helpers
## ###############

function log() {
	echo -e "$(date +%D-%T) - $1"
}

function log_from_function() {
	func_name=$1
	shift
	log "[$func_name] $*"
}

function valid_percentage() {
	if ! [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" -lt 0 ]] || [[ "$1" -gt 100 ]]; then
		return 1
	else
		return 0
	fi
}

function valid_percentage_range() {
	# Check if input matches range format: NUMBER-NUMBER
	if ! [[ "$1" =~ ^[0-9]+-[0-9]+$ ]]; then
		return 1
	fi

	# Extract lower and upper bounds
	local lower="${1%-*}"
	local upper="${1#*-}"

	# Validate both numbers are valid percentages
	if ! valid_percentage "$lower" || ! valid_percentage "$upper"; then
		return 1
	fi

	# Check lower < upper
	if [[ "$lower" -ge "$upper" ]]; then
		return 1
	fi

	# Check bounds are reasonable (lower >= 10, upper <= 100)
	if [[ "$lower" -lt 10 ]] || [[ "$upper" -gt 100 ]]; then
		return 1
	fi

	return 0
}

function valid_voltage() {
	if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?V$ ]]; then
		return 0
	fi
	return 1
}

function sudo_smc() {
	local label="$1"
	shift

	# Only log if in debug mode or if command might fail
	if [[ "${DEBUG:-}" == "1" ]] || [[ "$1" == "-w" ]]; then
		log "🔐 sudo smc: $label"
	fi

	sudo smc "$@"
}

function smc_read_hex() {
	key=$1
	line=$(echo $(sudo_smc "Read SMC key $key" -k $key -r))
	if [[ $line =~ "no data" ]]; then
		echo
	else
		echo ${line#*bytes} | tr -d ' ' | tr -d ')'
	fi
}

function smc_write_hex() {
	local key=$1
	local hex_value=$2
	if ! sudo_smc "Write $hex_value to SMC key $key" -k "$key" -w "$hex_value" >/dev/null 2>&1; then
		log "⚠️ Failed to write $hex_value to $key"
		return 1
	fi
	return 0
}

## #########################
## Detect supported SMC keys
## #########################
[[ $(sudo_smc "Detect CHTE support" -k CHTE -r) =~ "no data" ]] && smc_supports_tahoe=false || smc_supports_tahoe=true;
[[ $(sudo_smc "Detect CH0B support" -k CH0B -r) =~ "no data" ]] && smc_supports_legacy=false || smc_supports_legacy=true;
[[ $(sudo_smc "Detect CHIE support" -k CHIE -r) =~ "no data" ]] && smc_supports_adapter_chie=false || smc_supports_adapter_chie=true;
[[ $(sudo_smc "Detect CH0I support" -k CH0I -r) =~ "no data" ]] && smc_supports_adapter_ch0i=false || smc_supports_adapter_ch0i=true;
ch0j_result=$(sudo_smc "Detect CH0J support" -k CH0J -r)
[[ "$ch0j_result" =~ "no data" || "$ch0j_result" =~ "Error" ]] && smc_supports_adapter_ch0j=false || smc_supports_adapter_ch0j=true;

function log_smc_capabilities() {
	log "SMC capabilities: tahoe=$smc_supports_tahoe legacy=$smc_supports_legacy CHIE=$smc_supports_adapter_chie CH0I=$smc_supports_adapter_ch0i CH0J=$smc_supports_adapter_ch0j"
}

## #################
## SMC Manipulation
## #################

# Change magsafe color
# see community sleuthing: https://github.com/actuallymentor/battery/issues/71
function change_magsafe_led_color() {
	log "MagSafe LED function invoked"
	color=$1

	# Check whether user can run color changes without password (required for backwards compatibility)
	if sudo -n smc -k ACLC -r &>/dev/null; then
		log "💡 Setting magsafe LED to $color"
	else
		log "🚨 Your version of battery is using an old visudo file, please run 'battery visudo' to fix this, until you do battery cannot change magsafe led colors"
		return
	fi

	if [[ "$color" == "green" ]]; then
		log "setting LED to green"
		smc_write_hex ACLC 03
	elif [[ "$color" == "orange" ]]; then
		log "setting LED to orange"
		smc_write_hex ACLC 04
	else
		# Default action: reset. Value 00 is a guess and needs confirmation
		log "resetting LED"
		smc_write_hex ACLC 00
	fi
}

function enable_discharging() {
	# IMPORTANT: This function forces the Mac to use battery power EVEN WHEN AC ADAPTER IS CONNECTED
	#
	# Normal behavior: When AC adapter is plugged in, Mac uses AC power and battery doesn't discharge
	# This function changes that: Forces Mac to use battery power and discharge despite AC being connected
	#
	# Use cases:
	# - Intentionally draining battery to a lower percentage (e.g., battery discharge 80)
	# - Testing battery drain scenarios
	# - The "battery adapter on" command uses this
	#
	# NOTE: This ONLY affects behavior when AC adapter is connected. If unplugged, battery
	# discharges normally regardless of this setting.
	#
	# See: https://github.com/actuallymentor/battery/issues/20#issuecomment-1364540704

	log "🔽🪫 Enabling battery discharging"

	disable_charging

	# Re:discharging, we're using keys uncovered by @howie65
	# Priority: CHIE > CH0J > CH0I
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		smc_write_hex CHIE 08
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		smc_write_hex CH0J 01
	else
		smc_write_hex CH0I 01
	fi
	smc_write_hex ACLC 01

	sleep 1
}

function disable_discharging() {
	# IMPORTANT: This function restores normal Mac behavior: USE AC POWER WHEN ADAPTER IS CONNECTED
	#
	# Normal behavior: When AC adapter is plugged in, Mac uses AC power (battery doesn't discharge)
	# This function ensures that normal behavior is active (counterpart to enable_discharging)
	#
	# Confusing name clarification:
	# - "disable_discharging" sounds like "stop the battery from discharging"
	# - What it really means: "disable FORCED discharging mode" = "allow AC passthrough"
	# - Result: When AC is connected, Mac uses AC power (battery idle/maintaining)
	#
	# Use cases:
	# - Returning to normal state after using "battery discharge" command
	# - The "battery adapter off" command uses this
	# - Called by enable_charging() to ensure AC power is used
	#
	# NOTE: This ONLY affects behavior when AC adapter is connected. If unplugged, battery
	# discharges normally regardless of this setting.

	log "🔼🪫 Disabling battery discharging"

	# Disable discharging - Priority: CHIE > CH0J > CH0I
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		smc_write_hex CHIE 00
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		smc_write_hex CH0J 00
	elif [[ "$smc_supports_adapter_ch0i" == "true" ]]; then
		smc_write_hex CH0I 00
	else
		smc_write_hex CH0I 00
	fi

	# Keep track of status
	is_charging=$(get_smc_charging_status)

	if ! valid_percentage "$setting"; then

		# When called without a maintain context (e.g., during daemon stop or from enable_charging),
		# just ensure charging is enabled without logging a potentially confusing message
		_enable_charging_internal
		change_magsafe_led_color "orange"

	elif [[ "$battery_percentage" -ge "$setting" && "$is_charging" == "enabled" ]]; then

		log "Disabling discharging: Charge above $setting, disabling charging"
		disable_charging
		change_magsafe_led_color "green"

	elif [[ "$battery_percentage" -lt "$setting" && "$is_charging" == "disabled" ]]; then

		log "Disabling discharging: Charge below $setting, enabling charging"

		# use direct commands since enable_charging also calls disable_discharging, and causes an eternal loop
		_enable_charging_internal

		change_magsafe_led_color "orange"
	fi

	sleep 1
	battery_percentage=$(get_battery_percentage)
}

# Clear, descriptive wrapper functions for better code readability
# These call the underlying enable/disable_discharging functions
# but with names that better express intent

function force_battery_discharge() {
	# Forces Mac to use battery power even when AC adapter is connected
	# Use case: Intentionally drain battery (e.g., battery discharge 80)
	# Result: Battery discharges despite being plugged into AC power
	enable_discharging
}

function allow_ac_passthrough() {
	# Allows Mac to use AC power when adapter is connected (normal behavior)
	# Disables forced battery discharge mode
	# Result: When plugged in, Mac uses AC power and battery doesn't discharge
	disable_discharging
}

function enable_charging() {
	log "🔌🔋 Enabling battery charging"

	disable_discharging

	_enable_charging_internal

	# magic sleep? added from BatteryOptimizerMac fork
	sleep 1
}

# internal function to send only the correct SMC commands to enable charging, and do nothing else.
# for example, does not first disable discharging, which should be done by the caller, if applicable.
# this does not sleep after sending the commands, either.
function _enable_charging_internal() {
	# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
	# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
	# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging

	if [[ "$smc_supports_tahoe" == "true" ]]; then
		smc_write_hex CHTE 00000000
	elif [[ "$smc_supports_legacy" == "true" ]]; then
		smc_write_hex CH0B 00
		smc_write_hex CH0C 00
	else
		log "⚠️ Unable to determine SMC keys for enabling charging"
	fi
}

function disable_charging() {
	log "🔌🪫 Disabling battery charging"

	if [[ "$smc_supports_tahoe" == "true" ]]; then
		smc_write_hex CHTE 01000000
	elif [[ "$smc_supports_legacy" == "true" ]]; then
		smc_write_hex CH0B 02
		smc_write_hex CH0C 02
	else
		log "⚠️ Unable to determine SMC keys for disabling charging"
	fi

	# magic sleep? added from BatteryOptimizerMac fork
	sleep 1
}

function get_smc_charging_status() {
	local status_key="CH0B"
	if [[ "$smc_supports_tahoe" == "true" ]]; then
		status_key="CHTE"
	fi
	hex_status=$(smc_read_hex "$status_key")
	if [[ -z "$hex_status" ]]; then
		echo "unknown"
		return
	fi
	if [[ "$smc_supports_tahoe" == "true" ]]; then
		if [[ "$hex_status" == "00000000" ]]; then
			echo "enabled"
		else
			echo "disabled"
		fi
	elif [[ "$hex_status" == "00" ]]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function get_smc_discharging_status() {
	# Priority: CHIE > CH0J > CH0I
	local status_key="CH0I"
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		status_key="CHIE"
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		status_key="CH0J"
	fi
	hex_status=$(smc_read_hex "$status_key")
	if [[ -z "$hex_status" ]]; then
		echo "unknown"
		return
	fi
	if [[ "$hex_status" == "0" || "$hex_status" == "00" ]]; then
		echo "not discharging"
	else
		echo "discharging"
	fi
}

## ###############
## Statistics
## ###############

function get_battery_percentage() {
	battery_percentage=$(pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::)
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=$(pmset -g batt | tail -n1 | awk '{print $5}')
	echo "$time_remaining"
}

function get_charger_state() {
	# Check for AC Power in first line or "AC attached" in battery line
	pmset_output=$(pmset -g batt)
	if echo "$pmset_output" | head -1 | grep -q "'AC Power'"; then
		echo "1"
	elif echo "$pmset_output" | tail -n1 | grep -q "AC attached"; then
		echo "1"
	else
		echo "0"
	fi
}

function get_cpu_type() {
	if [[ $(smc -k BCLM -r) == *"no data"* ]]; then
		echo "apple"
	else
		echo "intel"
	fi
    #if [[ $(sysctl -n machdep.cpu.brand_string) == *"Intel"* ]]; then
    #    echo "intel"
    #else
    #    echo "apple"
    #fi
}

function get_maintain_percentage() {
	maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
	echo "$maintain_percentage"
}

function get_voltage() {
	voltage=$(ioreg -l -n AppleSmartBattery -r | grep "\"Voltage\" =" | awk '{ print $3/1000 }' | tr ',' '.')
	echo "$voltage"
}

## ###############
## Actions
## ###############

# Help message
if [ -z "$action" ] || [[ "$action" == "help" ]]; then
	echo -e "$helpmessage"
	exit 0
fi

# Version message
if [[ "$action" == "version" ]] || [[ "$action" == "-v" ]] || [[ "$action" == "--version" ]]; then
	echo "battery $BATTERY_CLI_VERSION"
	exit 0
fi

# Info command - comprehensive system information
if [[ "$action" == "info" ]]; then
	echo "Battery Utility Information"
	echo ""
	echo "Version: battery $BATTERY_CLI_VERSION"
	echo ""

	echo "Installation:"
	echo "  Binary path:   $binfolder/battery"
	echo "  SMC path:      $binfolder/smc"
	echo "  Config folder: $configfolder"
	echo "  Log file:      $logfile"
	echo ""

	# Check if symlinked (best effort detection)
	if [[ -L "$binfolder/battery" ]]; then
		symlink_target=$(readlink "$binfolder/battery")
		echo "  Type: Symlinked (development mode)"
		echo "  Target: $symlink_target"
		echo ""
	fi

	echo "System:"
	echo "  CPU type:      $(get_cpu_type)"
	battery_percentage=$(get_battery_percentage)
	echo "  Battery:       $battery_percentage%"
	echo "  Voltage:       $(get_voltage)V"
	charging_status=$(get_smc_charging_status)
	discharging_status=$(get_smc_discharging_status)
	echo "  Charging:      $charging_status"
	echo "  Discharging:   $discharging_status"
	echo ""

	# Add pmset cross-check
	echo "System View (pmset):"
	pmset_output=$(pmset -g batt)
	power_source=$(echo "$pmset_output" | head -1 | grep -o "'[^']*'" | tr -d "'")
	pmset_state=$(echo "$pmset_output" | grep InternalBattery | grep -o "not charging\|finishing charge\|AC attached\|discharging\|charging\|charged" | head -1 || echo "unknown")
	pmset_pct=$(echo "$pmset_output" | grep InternalBattery | grep -o "[0-9]*%" | tr -d '%')

	echo "  Power Source:  $power_source"
	echo "  Battery:       ${pmset_pct}%"
	echo "  State:         $pmset_state"

	# Quick validation check
	our_state="unknown"
	if [[ "$charging_status" == "enabled" ]]; then
		our_state="charging"
	elif [[ "$discharging_status" == "discharging" ]]; then
		our_state="discharging"
	fi

	if [[ "$our_state" != "unknown" && "$pmset_state" != "unknown" && "$our_state" != "$pmset_state" ]]; then
		echo "  ⚠️  Mismatch: SMC shows '$our_state' but system shows '$pmset_state'"
		echo "     Run 'battery debug' for detailed cross-check"
	fi
	echo ""

	echo "Daemon Status:"
	if test -f $pidfile; then
		pid=$(cat $pidfile 2>/dev/null)
		if ps -p $pid -o command= 2>/dev/null | grep -q "battery.*maintain"; then
			echo "  Status: RUNNING (PID $pid)"

			daemon_metadata_file="$configfolder/daemon.metadata"
			if command -v jq >/dev/null 2>&1 && [[ -f "$daemon_metadata_file" ]]; then
				version=$(jq -r '.version // ""' "$daemon_metadata_file" 2>/dev/null)
				start_date=$(jq -r '.start_date // ""' "$daemon_metadata_file" 2>/dev/null)
				start_time=$(jq -r '.start_time // ""' "$daemon_metadata_file" 2>/dev/null)
				script_mtime=$(jq -r '.script_mtime // ""' "$daemon_metadata_file" 2>/dev/null)

				if [[ -n "$version" ]]; then
					echo "  Version: $version"
				fi

				if [[ -n "$start_date" ]]; then
					echo "  Started: $start_date"
				fi

				if [[ -n "$start_time" ]]; then
					current_time=$(date +%s)
					elapsed=$((current_time - start_time))
					hours=$((elapsed / 3600))
					minutes=$(((elapsed % 3600) / 60))
					if [[ $hours -gt 0 ]]; then
						echo "  Uptime:  ${hours}h ${minutes}m"
					else
						echo "  Uptime:  ${minutes}m"
					fi
				fi

				# Check for version mismatch
				if [[ -n "$version" && "$version" != "$BATTERY_CLI_VERSION" ]]; then
					echo "  ⚠️  Warning: Daemon version ($version) differs from installed version ($BATTERY_CLI_VERSION)"
					echo "              Run 'battery maintain recover' to restart with current version"
				fi

				# Check if script modified since daemon start
				if [[ -n "$script_mtime" && -f "$binfolder/battery" ]]; then
					current_mtime=$(stat -f %m "$binfolder/battery" 2>/dev/null || echo "0")
					if [[ "$current_mtime" -gt "$script_mtime" ]]; then
						echo "  ⚠️  Warning: Script updated since daemon started"
						echo "              Run 'battery maintain recover' to reload"
					fi
				fi
			else
				if ! command -v jq >/dev/null 2>&1; then
					echo "  Metadata: Not available (jq required - install: brew install jq)"
				else
					echo "  Metadata: Not available (daemon may be from older version)"
				fi
			fi

			# Show maintenance level
			maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
			if [[ $maintain_percentage ]]; then
				echo "  Maintaining: $maintain_percentage%"
			else
				maintain_voltage=$(cat $maintain_voltage_tracker_file 2>/dev/null)
				if [[ $maintain_voltage ]]; then
					echo "  Maintaining: $maintain_voltage"
				fi
			fi
		else
			echo "  Status: STALE (PID $pid not running)"
			echo "  Run 'battery maintain recover' to restart"
		fi
	else
		echo "  Status: NOT RUNNING"
		echo "  Run 'battery maintain <percentage>' to start"
	fi

	exit 0
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then

	# User to set folder ownership to is $setting if it is defined and $USER otherwise
	if [[ -z "$setting" ]]; then
		setting=$USER
	fi

	# Set visudo tempfile ownership to current user
	log "Setting visudo file permissions to $setting"
	sudo chown -R $setting $configfolder

	# Write the visudo file to a tempfile
	visudo_tmpfile="$configfolder/visudo.tmp"
	sudo rm visudo_tmpfile 2>/dev/null
	echo -e "$visudoconfig" >$visudo_tmpfile

	# If the visudo file is the same (no error, exit code 0), set the permissions just
	if sudo cmp $visudo_file $visudo_tmpfile &>/dev/null; then

		echo "The existing battery visudo file is what it should be for version $BATTERY_CLI_VERSION"

		# Check if file permissions are correct, if not, set them
		current_visudo_file_permissions=$(stat -f "%Lp" $visudo_file)
		if [[ "$current_visudo_file_permissions" != "440" ]]; then
			sudo chmod 440 $visudo_file
		fi

		# exit because no changes are needed
		exit 0

	fi

	# Validate that the visudo tempfile is valid
	if sudo visudo -c -f $visudo_tmpfile &>/dev/null; then

		# If the visudo folder does not exist, make it
		if ! test -d "$visudo_folder"; then
			sudo mkdir -p "$visudo_folder"
		fi

		# Copy the visudo file from tempfile to live location
		sudo cp $visudo_tmpfile $visudo_file

		# Delete tempfile
		rm $visudo_tmpfile

		# Set correct permissions on visudo file
		sudo chmod 440 $visudo_file

		echo "Visudo file updated successfully"

	else
		echo "Error validating visudo file, this should never happen:"
		sudo visudo -c -f $visudo_tmpfile
	fi

	exit 0
fi

# Reinstall helper
if [[ "$action" == "reinstall" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
	exit 0
fi

# Update helper
if [[ "$action" == "update" ]]; then

	# Check if we have the most recent version
	if curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/battery.sh | grep -q "$BATTERY_CLI_VERSION"; then
		echo "No need to update, offline version number $BATTERY_CLI_VERSION matches remote version number"
	else
		echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash"
		if [[ ! "$setting" == "silent" ]]; then
			echo "Press any key to continue"
			read
		fi
		curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash
	fi
	exit 0
fi

# Uninstall helper
if [[ "$action" == "uninstall" ]]; then

	if [[ ! "$setting" == "silent" ]]; then
		echo "This will enable charging, and remove the smc tool and battery script"
		echo "Press any key to continue"
		read
	fi
	enable_charging
	allow_ac_passthrough
	$battery_binary remove_daemon
	sudo rm -v "$binfolder/smc" "$binfolder/battery" $visudo_file
	sudo rm -v -r "$configfolder"
	pkill -f "/usr/local/bin/battery.*"
	exit 0
fi

# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	$battery_binary maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	else
		log "Error: $setting is not \"on\" or \"off\"."
		exit 1
	fi

	exit 0

fi

# Discharge on/off controller
if [[ "$action" == "adapter" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	$battery_binary maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		force_battery_discharge
	elif [[ "$setting" == "off" ]]; then
		allow_ac_passthrough
	else
		log "Error: $setting is not \"on\" or \"off\"."
		exit 1
	fi

	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	if ! valid_percentage "$setting"; then
		log "Error: $setting is not a valid setting for battery charge. Please use a number between 0 and 100"
		exit 1
	fi

	# Disable running daemon
	$battery_binary maintain stop

	# Disable charge blocker if enabled
	$battery_binary adapter on

	# Start charging
	battery_percentage=$(get_battery_percentage)
	log "Charging to $setting% from $battery_percentage%"
	enable_charging # also disables discharging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		if [[ "$battery_percentage" -ge "$((setting - 3))" ]]; then
			sleep 20
		else
			caffeinate -is sleep 60
		fi

	done

	disable_charging
	log "Charging completed at $battery_percentage%"

	exit 0

fi

# Discharging on/off controller
if [[ "$action" == "discharge" ]]; then

	if ! valid_percentage "$setting"; then
		log "Error: $setting is not a valid setting for battery discharge. Please use a number between 0 and 100"
		exit 1
	fi

	# Start charging
	battery_percentage=$(get_battery_percentage)
	log "Discharging to $setting% from $battery_percentage%"
	force_battery_discharge

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -gt "$setting" ]]; do

		log "Battery at $battery_percentage% (target $setting%)"
		caffeinate -is sleep 60
		battery_percentage=$(get_battery_percentage)

	done

	allow_ac_passthrough
	log "Discharging completed at $battery_percentage%"

fi

# Maintain at level
if [[ "$action" == "maintain_synchronous" ]]; then

	log_smc_capabilities

	# Checking if the calibration process is running
	if test -f "$calibrate_pidfile"; then
		pid=$(cat "$calibrate_pidfile" 2>/dev/null)
		kill $calibrate_pidfile &>/dev/null
		log "🚨 Calibration process have been stopped"
	fi

	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then

		# Before doing anything, log out environment details as a debugging trail
		log "Debug trail. User: $USER, config folder: $configfolder, logfile: $logfile, file called with 1: $1, 2: $2"

		maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
		if [[ $maintain_percentage ]]; then
			log "Recovering maintenance percentage $maintain_percentage"
			setting=$(echo $maintain_percentage)
		else
			log "No setting to recover, exiting"
			exit 0
		fi
	fi

	# Write daemon metadata for version tracking and monitoring
	daemon_metadata_file="$configfolder/daemon.metadata"
	if command -v jq >/dev/null 2>&1; then
		cat > "$daemon_metadata_file" <<EOF
{
  "version": "$BATTERY_CLI_VERSION",
  "pid": $$,
  "start_time": $(date +%s),
  "start_date": "$(date)",
  "script_mtime": $(stat -f %m "$0" 2>/dev/null || echo "0")
}
EOF
		log "Wrote daemon metadata: version=$BATTERY_CLI_VERSION, pid=$$"
	else
		log "jq not found - skipping metadata (install: brew install jq)"
	fi

	if valid_percentage_range "$setting"; then
		# Range format: lower-upper
		is_range=true
		lower_bound="${setting%-*}"
		upper_bound="${setting#*-}"
	elif valid_percentage "$setting"; then
		# Single value format (backward compatible)
		is_range=false
		lower_bound="$setting"
		upper_bound="$setting"
	else
		log "Error: $setting is not a valid setting for battery maintain. Please use a number between 0 and 100, or a range like 70-80"
		exit 1
	fi

	# Check if the user requested that the battery maintenance first discharge to the desired level
	if [[ "$subsetting" == "--force-discharge" ]]; then
		# Before we start maintaining the battery level, first discharge to the target level
		local discharge_target="$lower_bound"
		log "Triggering discharge to $discharge_target before enabling charging limiter"
		$battery_binary discharge "$discharge_target"
		log "Discharge pre battery-maintenance complete, continuing to battery maintenance loop"
	else
		log "Not triggering discharge as it is not requested"
	fi

	# Start charging
	battery_percentage=$(get_battery_percentage)

	if [[ "$is_range" == true ]]; then
		log "Maintaining battery between $lower_bound% and $upper_bound% from $battery_percentage%"
	else
		log "Charging to and maintaining at $setting% from $battery_percentage%"
	fi

	# Loop until battery percent is exceeded
	while true; do

		# Keep track of status
		is_charging=$(get_smc_charging_status)
		ac_attached=$(get_charger_state)

		if [[ "$battery_percentage" -ge "$upper_bound" && ("$is_charging" == "enabled" || "$ac_attached" == "1") ]]; then

			log "Charge at or above $upper_bound%"
			if [[ "$is_charging" == "enabled" ]]; then
				disable_charging
			fi
			change_magsafe_led_color "green"

		elif [[ "$battery_percentage" -lt "$lower_bound" && "$is_charging" == "disabled" ]]; then

			log "Charge below $lower_bound%"
			enable_charging
			change_magsafe_led_color "orange"

		fi

		sleep 60

		battery_percentage=$(get_battery_percentage)

	done

	exit 0

fi

# Maintain at voltage
if [[ "$action" == "maintain_voltage_synchronous" ]]; then

	log_smc_capabilities

	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then

		# Before doing anything, log out environment details as a debugging trail

		maintain_voltage=$(cat $maintain_voltage_tracker_file 2>/dev/null)
		if [[ $maintain_voltage ]]; then
			log "Recovering maintenance voltage $maintain_voltage"
			setting=$(echo $maintain_voltage | awk '{print $1}')
			subsetting=$(echo $maintain_voltage | awk '{print $2}')
		else
			log "No setting to recover, exiting"
			exit 0
		fi
	fi

	voltage=$(get_voltage)
	lower_voltage=$(echo "$setting - $subsetting" | bc -l)
	upper_voltage=$(echo "$setting + $subsetting" | bc -l)
	log "Keeping voltage between ${lower_voltage}V and ${upper_voltage}V"

	# Loop
	while true; do
		is_charging=$(get_smc_charging_status)

		if (($(echo "$voltage < $lower_voltage" | bc -l))) && [[ "$is_charging" == "disabled" ]]; then
			log "Battery at ${voltage}V"
			enable_charging
		fi
		if (($(echo "$voltage >= $upper_voltage" | bc -l))) && [[ "$is_charging" == "enabled" ]]; then
			log "Battery at ${voltage}V"
			disable_charging
		fi

		sleep 60

		voltage=$(get_voltage)

	done

	exit 0

fi

# Asynchronous battery level maintenance
if [[ "$action" == "maintain" ]]; then

	# Kill old process silently
	if test -f "$pidfile"; then
		log "Killing old maintain process at $(cat $pidfile)"
		pid=$(cat "$pidfile" 2>/dev/null)
		kill $pid &>/dev/null
	fi

	if test -f "$calibrate_pidfile"; then
		pid=$(cat "$calibrate_pidfile" 2>/dev/null)
		kill $calibrate_pidfile &>/dev/null
		log "🚨 Calibration process have been stopped"
	fi

	if [[ "$setting" == "stop" ]]; then
		log "Stopping maintain daemon & enabling charging as default state"

		# Stop via launchctl
		launchd_label="gui/$(id -u $USER)/com.battery.app"
		if launchctl list | grep -q "com.battery.app"; then
			log "Stopping daemon via launchctl"
			launchctl bootout "$launchd_label" 2>/dev/null || launchctl unload "$daemon_path" 2>/dev/null
		fi

		# Clean up
		rm $pidfile 2>/dev/null
		rm "$configfolder/daemon.metadata" 2>/dev/null
		$battery_binary disable_daemon
		enable_charging
		$battery_binary status
		exit 0
	fi

	# Check if setting is a voltage
	is_voltage=false
	if valid_voltage "$setting"; then
		setting="${setting//V/}"

		if valid_voltage "$subsetting"; then
			subsetting="${subsetting//V/}"
		else
			subsetting="0.1"
		fi

		if (($(echo "$setting < $voltage_min" | bc -l) || $(echo "$setting > $voltage_max" | bc -l))); then
			log "Error: ${setting}V is not a valid setting. Please use a value between ${voltage_min}V and ${voltage_max}V"
			exit 1
		fi
		if (($(echo "$subsetting < $voltage_hyst_min" | bc -l) || $(echo "$subsetting > $voltage_max" | bc -l))); then
			log "Error: ${subsetting}V is not a valid setting. Please use a value between ${voltage_hyst_min}V and ${voltage_hyst_max}V"
			exit 1
		fi

		is_voltage=true

	# Check if setting is a percentage range or single value
	elif ! valid_percentage "$setting" && ! valid_percentage_range "$setting"; then
		log "Called with $setting $action"
		# If setting is not a valid percentage/range and not a special keyword, exit with an error.
		if ! { [[ "$setting" == "stop" ]] || [[ "$setting" == "recover" ]]; }; then
			log "Error: $setting is not a valid setting for battery maintain. Please use a number between 0 and 100, a range like 70-80, or an action keyword like 'stop' or 'recover'."
			exit 1
		fi

	fi

	# Resolve and log the settings
	if [ "$is_voltage" = true ]; then
		if [[ "$setting" == "recover" ]]; then
			maintain_voltage=$(cat $maintain_voltage_tracker_file 2>/dev/null)
			if [[ $maintain_voltage ]]; then
				recovered_setting=$(echo $maintain_voltage | awk '{print $1}')
				recovered_subsetting=$(echo $maintain_voltage | awk '{print $2}')
				log "Starting battery maintenance at ${recovered_setting}V ±${recovered_subsetting}V (recovered)"
			else
				log "Starting battery maintenance (recovering voltage settings)"
			fi
		else
			log "Starting battery maintenance at ${setting}V ±${subsetting}V"
		fi
	else
		if [[ "$setting" == "recover" ]]; then
			maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
			if [[ $maintain_percentage ]]; then
				log "Starting battery maintenance at $maintain_percentage% (recovered)"
			else
				log "Starting battery maintenance (recovering percentage settings)"
			fi
		elif valid_percentage_range "$setting"; then
			log "Starting battery maintenance between ${setting/-/% and }%"
		else
			log "Starting battery maintenance at $setting% $subsetting"
		fi
	fi

	# Save settings to tracker files (unless recovering)
	if ! [[ "$setting" == "recover" ]]; then
		if [[ "$is_voltage" = true ]]; then
			rm "$maintain_percentage_tracker_file" 2>/dev/null
			echo "$setting $subsetting" >$maintain_voltage_tracker_file
			log "Saved voltage settings: ${setting}V ±${subsetting}V"
		else
			rm "$maintain_voltage_tracker_file" 2>/dev/null
			echo $setting >$maintain_percentage_tracker_file
			if valid_percentage_range "$setting"; then
				log "Saved percentage range: ${setting/-/% to }%"
			else
				log "Saved percentage setting: $setting%"
			fi
		fi
	fi

	# Create/update and start the daemon via launchd
	$battery_binary create_daemon

	# Start daemon via launchctl
	launchd_label="gui/$(id -u $USER)/com.battery.app"

	# Check if already loaded
	if launchctl list | grep -q "com.battery.app"; then
		log "Restarting daemon via launchctl"
		launchctl kickstart -k "$launchd_label" 2>/dev/null
	else
		log "Starting daemon via launchctl"
		launchctl bootstrap "$launchd_label" "$daemon_path" 2>/dev/null || launchctl load "$daemon_path" 2>/dev/null
	fi

	# Wait a moment for daemon to start and write PID
	sleep 1

	# Get PID from launchctl (strip trailing semicolon)
	daemon_pid=$(launchctl list com.battery.app 2>/dev/null | awk '/PID/ {print $NF}' | tr -d ';')
	if [[ -n "$daemon_pid" && "$daemon_pid" != "-" ]]; then
		echo $daemon_pid > $pidfile
		log "Daemon started with PID $daemon_pid"
	else
		log "Warning: Could not determine daemon PID"
	fi

	exit 0

fi

# Battery calibration
if [[ "$action" == "calibrate_synchronous" ]]; then
	log "Starting calibration"

	# Stop the maintaining
	battery maintain stop

	# Discharge battery to 15%
	battery discharge 15

	while true; do
		log "checking if at 100%"
		# Check if battery level has reached 100%
		if battery status | head -n 1 | grep -q "Battery at 100%"; then
			break
		else
			sleep 300
			continue
		fi
	done

	# Wait before discharging to target level
	log "reached 100%, maintaining for 1 hour"
	sleep 3600

	# Discharge battery to 80%
	battery discharge 80

	# Recover old maintain status
	battery maintain recover
	exit 0
fi

# Asynchronous battery level maintenance
if [[ "$action" == "calibrate" ]]; then
	# Kill old process silently
	if test -f "$calibrate_pidfile"; then
		pid=$(cat "$calibrate_pidfile" 2>/dev/null)
		kill $pid &>/dev/null
	fi

	if [[ "$setting" == "stop" ]]; then
		log "Killing running calibration daemon"
		kill $calibrate_pidfile &>/dev/null
		rm $calibrate_pidfile 2>/dev/null

		exit 0
	fi

	# Start calibration script
	log "Starting calibration script"
	nohup battery calibrate_synchronous >>$logfile &

	# Store pid of calibration process and setting
	echo $! >$calibrate_pidfile
	pid=$(cat "$calibrate_pidfile" 2>/dev/null)
fi

# Status logger
if [[ "$action" == "status" ]]; then

	battery_pct=$(get_battery_percentage)
	charging_status=$(get_smc_charging_status)
	discharging_status=$(get_smc_discharging_status)
	ac_attached=$(get_charger_state)

	log "Battery at ${battery_pct}% ($(get_remaining_time) remaining), $(get_voltage)V, smc charging $charging_status"

	if test -f $pidfile; then
		pid=$(cat $pidfile 2>/dev/null)

		# Check if process exists AND is actually battery
		if ps -p $pid -o command= 2>/dev/null | grep -q "battery.*maintain"; then
			maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
			if [[ $maintain_percentage ]]; then
				if valid_percentage_range "$maintain_percentage"; then
					maintain_level="${maintain_percentage/-/% - }%"
					lower_bound="${maintain_percentage%-*}"
					upper_bound="${maintain_percentage#*-}"
				else
					maintain_level="$maintain_percentage%"
					lower_bound="$maintain_percentage"
					upper_bound="$maintain_percentage"
				fi
			else
				maintain_level=$(cat $maintain_voltage_tracker_file 2>/dev/null)
				maintain_level=$(echo "$maintain_level" | awk '{print $1 "V ±" $2 "V"}')
				# For voltage maintenance, we don't show the detailed state analysis
				lower_bound=""
			fi
			log "Your battery is currently being maintained at $maintain_level"

			# Show detailed state analysis for percentage-based maintenance
			if [[ -n "$lower_bound" ]]; then
				log ""

				# Determine relationship to target
				if [[ "$battery_pct" -gt "$upper_bound" ]]; then
					diff=$((battery_pct - upper_bound))
					log "  State: ${diff}% above target"
					log "  • Charging: disabled (preventing further charge)"

					if [[ "$discharging_status" == "discharging" ]]; then
						log "  • Actively discharging to target (using battery power)"
					elif [[ "$ac_attached" == "1" ]]; then
						log "  • Using AC power (not discharging)"
						log "  ℹ️  Battery will discharge to ${upper_bound}% when unplugged"
						log "     Or force discharge now: battery discharge ${upper_bound}"
					else
						log "  • Not plugged in - naturally discharging to target"
					fi

				elif [[ "$battery_pct" -lt "$lower_bound" ]]; then
					diff=$((lower_bound - battery_pct))
					log "  State: ${diff}% below target"

					if [[ "$charging_status" == "enabled" ]]; then
						log "  • Charging: enabled (charging to target)"
						log "  • Will stop charging at ${upper_bound}%"
					else
						log "  • Charging: disabled (unexpected)"
						log "  ⚠️  Should be charging but isn't - check AC connection"
					fi

				else
					log "  State: ✅ Within target range"

					if [[ "$charging_status" == "enabled" ]]; then
						log "  • Charging: enabled"
						log "  • Will stop charging at ${upper_bound}%"
					else
						log "  • Charging: disabled (at/above target)"
					fi

					if [[ "$ac_attached" == "1" && "$discharging_status" != "discharging" ]]; then
						log "  • Using AC power (battery maintaining)"
					elif [[ "$discharging_status" == "discharging" ]]; then
						log "  • Actively discharging (using battery power)"
					fi
				fi
			fi

			# Show basic daemon info
			log ""
			daemon_metadata_file="$configfolder/daemon.metadata"
			if command -v jq >/dev/null 2>&1 && [[ -f "$daemon_metadata_file" ]]; then
				version=$(jq -r '.version // ""' "$daemon_metadata_file" 2>/dev/null)
				start_time=$(jq -r '.start_time // ""' "$daemon_metadata_file" 2>/dev/null)
				uptime_str=""
			if [[ -n "$start_time" ]]; then
				current_time=$(date +%s)
				elapsed=$((current_time - start_time))
				hours=$((elapsed / 3600))
				minutes=$(((elapsed % 3600) / 60))
				if [[ $hours -gt 0 ]]; then
					uptime_str="${hours}h ${minutes}m"
				else
					uptime_str="${minutes}m"
				fi
			fi
			log "Daemon: running (${version:-unknown}, uptime ${uptime_str:-unknown})"
		else
			log "Daemon: running (PID $pid)"
		fi
		else
			log "⚠️  Battery maintenance is NOT active (stale PID $pid)"
			log "The maintain daemon appears to have stopped."
			log "Run 'battery maintain recover' to restart, or 'battery maintain 80' to set a new limit."
			rm $pidfile 2>/dev/null  # Clean up stale PID file
		fi
	else
		log "Your battery is not being actively maintained."
		log "Run 'battery maintain <percentage>' to enable charge limiting."
	fi
	exit 0

fi

# Status logger in csv format
if [[ "$action" == "status_csv" ]]; then

	echo "$(get_battery_percentage),$(get_remaining_time),$(get_smc_charging_status),$(get_smc_discharging_status),$(get_maintain_percentage)"

fi

# launchd daemon creator, inspiration: https://www.launchd.info/
if [[ "$action" == "create_daemon" ]]; then

	call_action="maintain_synchronous"
	if test -f "$maintain_voltage_tracker_file"; then
		call_action="maintain_voltage_synchronous"
	fi

	daemon_definition="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
	<dict>
		<key>Label</key>
		<string>com.battery.app</string>
		<key>ProgramArguments</key>
		<array>
			<string>$binfolder/battery</string>
			<string>$call_action</string>
			<string>recover</string>
		</array>
		<key>StandardOutPath</key>
		<string>$logfile</string>
		<key>StandardErrorPath</key>
		<string>$logfile</string>
		<key>RunAtLoad</key>
		<true/>
	</dict>
</plist>
"

	mkdir -p "${daemon_path%/*}"

	# check if daemon already exists
	if test -f "$daemon_path"; then

		log "Daemon already exists, checking for differences"
		daemon_definition_difference=$(diff --brief --ignore-space-change --strip-trailing-cr --ignore-blank-lines <(cat "$daemon_path" 2>/dev/null) <(echo "$daemon_definition"))

		# remove leading and trailing whitespaces
		daemon_definition_difference=$(echo "$daemon_definition_difference" | xargs)
		if [[ "$daemon_definition_difference" != "" ]]; then

			log "daemon_definition changed: replace with new definitions"
			echo "$daemon_definition" >"$daemon_path"

		fi
	else

		# daemon not available, create new launch deamon
		log "Daemon does not yet exist, creating daemon file at $daemon_path"
		echo "$daemon_definition" >"$daemon_path"

	fi

	# Enable daemon to run at login
	launchd_label="gui/$(id -u $USER)/com.battery.app"
	launchctl enable "$launchd_label" 2>/dev/null

	log "Daemon plist created/updated at $daemon_path"
	exit 0

fi

# Disable daemon
if [[ "$action" == "disable_daemon" ]]; then

	launchd_label="gui/$(id -u $USER)/com.battery.app"
	log "Disabling daemon at $launchd_label"

	# Bootout if loaded
	if launchctl list | grep -q "com.battery.app"; then
		launchctl bootout "$launchd_label" 2>/dev/null || launchctl unload "$daemon_path" 2>/dev/null
	fi

	# Disable from auto-starting
	launchctl disable "$launchd_label" 2>/dev/null
	exit 0

fi

# Remove daemon
if [[ "$action" == "remove_daemon" ]]; then

	launchd_label="gui/$(id -u $USER)/com.battery.app"

	# Bootout if loaded
	if launchctl list | grep -q "com.battery.app"; then
		launchctl bootout "$launchd_label" 2>/dev/null || launchctl unload "$daemon_path" 2>/dev/null
	fi

	# Remove plist file
	rm $daemon_path 2>/dev/null
	log "Daemon removed"
	exit 0

fi

# Display logs
if [[ "$action" == "logs" ]]; then

	amount="${2:-100}"

	echo -e "👾 Battery CLI logs:\n"
	tail -n $amount $logfile

	echo -e "\n🖥️	Battery GUI logs:\n"
	tail -n $amount "$configfolder/gui.log"

	echo -e "\n📁 Config folder details:\n"
	ls -lah $configfolder

	echo -e "\n⚙️	Battery data:\n"
	$battery_binary status
	$battery_binary | grep -E "v\d.*"

	exit 0

fi

# Debug command - cross-check battery state
if [[ "$action" == "debug" ]]; then

	echo "🔍 Battery Debug Information"
	echo ""
	echo "Our Tool (via SMC):"

	# Get our view
	charging_status=$(get_smc_charging_status)
	discharging_status=$(get_smc_discharging_status)
	battery_pct=$(get_battery_percentage)
	voltage=$(get_voltage)

	echo "  Charging:     $charging_status"
	echo "  Discharging:  $discharging_status"
	echo "  Battery:      $battery_pct%"
	echo "  Voltage:      ${voltage}V"

	# Get raw SMC values using internal function
	echo ""
	echo "Raw SMC Keys:"
	ch0b=$(smc_read_hex CH0B 2>/dev/null || echo "N/A")
	ch0c=$(smc_read_hex CH0C 2>/dev/null || echo "N/A")
	ch0i=$(smc_read_hex CH0I 2>/dev/null || echo "N/A")
	ch0j=$(smc_read_hex CH0J 2>/dev/null || echo "N/A")
	aclc=$(smc_read_hex ACLC 2>/dev/null || echo "N/A")
	echo "  CH0B: $ch0b  CH0C: $ch0c  CH0I: $ch0i  CH0J: $ch0j  ACLC: $aclc"

	# Get hardware metrics from ioreg
	echo ""
	echo "Hardware (ioreg):"
	ioreg_output=$(ioreg -rc AppleSmartBattery 2>/dev/null)

	if [[ -n "$ioreg_output" ]]; then
		# Parse adapter info
		adapter_watts=$(echo "$ioreg_output" | grep '"AdapterDetails"' | grep -o '"Watts"=[0-9]*' | cut -d= -f2)

		# Parse power flow metrics
		voltage_mv=$(echo "$ioreg_output" | grep '"Voltage" = ' | grep -o '[0-9]*' | head -1)
		amperage_ma=$(echo "$ioreg_output" | grep '"Amperage" = ' | grep -o '\-\?[0-9]*' | head -1)

		# Display adapter
		if [[ -n "$adapter_watts" && "$adapter_watts" -gt 0 ]]; then
			echo "  Adapter:      ${adapter_watts}W"
		else
			echo "  Adapter:      Not connected or unknown"
		fi

		# Calculate and display power flow
		if [[ -n "$voltage_mv" && -n "$amperage_ma" ]]; then
			# ioreg returns amperage as unsigned 64-bit int. Negative values (discharging)
			# are represented as very large numbers (two's complement).
			# If value > 2^63, convert to signed by subtracting 2^64
			# Use awk for the comparison and conversion since bash can't handle 64-bit ints
			amperage_ma=$(awk -v amp="$amperage_ma" 'BEGIN {
				if (amp > 9223372036854775807) {
					printf "%.0f", amp - 18446744073709551616
				} else {
					printf "%.0f", amp
				}
			}')

			voltage_v=$(awk "BEGIN {printf \"%.2f\", $voltage_mv / 1000}")
			amperage_a=$(awk "BEGIN {printf \"%.2f\", $amperage_ma / 1000}")
			power_w=$(awk "BEGIN {printf \"%.1f\", ($voltage_mv * $amperage_ma) / 1000000}")

			# Determine power direction
			if [[ "${power_w:0:1}" == "-" ]]; then
				power_direction="(discharging)"
			elif [[ "$power_w" == "0.0" || "$power_w" == "-0.0" ]]; then
				power_direction="(idle/maintaining)"
			else
				power_direction="(charging)"
			fi

			echo "  Power Flow:   ${power_w}W ${power_direction}"
			echo "                ${amperage_a}A @ ${voltage_v}V"
		else
			echo "  Power Flow:   Unable to read"
		fi
	else
		echo "  Unable to read ioreg data"
	fi

	# Get system view via pmset
	echo ""
	echo "System (pmset -g batt):"
	pmset_output=$(pmset -g batt)
	echo "$pmset_output" | grep -v "^$" | sed 's/^/  /'

	# Parse pmset for cross-check
	echo ""
	power_source=$(echo "$pmset_output" | head -1 | grep -o "'[^']*'" | tr -d "'")
	pmset_state=$(echo "$pmset_output" | grep InternalBattery | grep -o "not charging\|finishing charge\|AC attached\|discharging\|charging\|charged" | head -1 || echo "unknown")
	pmset_pct=$(echo "$pmset_output" | grep InternalBattery | grep -o "[0-9]*%" | tr -d '%')

	# Cross-check logic
	ac_attached=$(get_charger_state)
	our_state="unknown"

	if [[ "$charging_status" == "enabled" ]]; then
		our_state="charging"
	elif [[ "$discharging_status" == "discharging" ]]; then
		our_state="discharging"
	elif [[ "$charging_status" == "disabled" && "$discharging_status" != "discharging" && "$ac_attached" == "1" ]]; then
		our_state="maintaining"  # Charging off, not discharging, on AC = maintaining
	elif [[ "$charging_status" == "disabled" ]]; then
		our_state="charged"      # Charging off, not on AC = fully charged
	fi

	# Determine match status
	if [[ "$pmset_state" == "unknown" ]]; then
		match_icon="⚠️"
		match_msg="Cannot parse pmset state"
	elif [[ "$our_state" == "unknown" ]]; then
		match_icon="⚠️"
		match_msg="Cannot determine SMC state"
	elif [[ "$our_state" == "$pmset_state" ]]; then
		match_icon="✅"
		match_msg="States match"
	elif [[ ("$our_state" == "maintaining" || "$our_state" == "charged") && ("$pmset_state" == "charged" || "$pmset_state" == "finishing charge" || "$pmset_state" == "not charging" || "$pmset_state" == "AC attached") ]]; then
		match_icon="✅"
		match_msg="States match (SMC: $our_state, pmset: $pmset_state) - maintenance active"
	else
		match_icon="⚠️"
		match_msg="States differ (expected with maintain active)"
	fi

	echo "Cross-Check:"
	echo "  Our state:    $our_state"
	echo "  pmset state:  $pmset_state"
	echo "  Status:       $match_icon $match_msg"

	exit 0

fi

# Doctor command - comprehensive health check
if [[ "$action" == "doctor" ]]; then

	echo "🩺 Battery Tool Health Check"
	echo ""

	# 1. Check SMC access
	echo "1. Checking SMC access..."
	if command -v smc >/dev/null 2>&1; then
		if smc -l >/dev/null 2>&1; then
			echo "   ✅ SMC accessible"
		else
			echo "   ⚠️  SMC command found but cannot read keys"
			echo "      This may require sudo access or system permissions"
		fi
	else
		echo "   ❌ SMC command not found in PATH"
		echo "      Expected at: $binfolder/smc"
	fi
	echo ""

	# 2. Check pmset access
	echo "2. Checking pmset access..."
	if command -v pmset >/dev/null 2>&1; then
		if pmset -g batt >/dev/null 2>&1; then
			echo "   ✅ pmset accessible"
		else
			echo "   ⚠️  pmset found but cannot read battery info"
		fi
	else
		echo "   ❌ pmset command not found"
	fi
	echo ""

	# 3. Compare charging states
	echo "3. Comparing battery states..."
	charging_status=$(get_smc_charging_status)
	discharging_status=$(get_smc_discharging_status)
	ac_attached=$(get_charger_state)
	our_state="unknown"

	if [[ "$charging_status" == "enabled" ]]; then
		our_state="charging"
	elif [[ "$discharging_status" == "discharging" ]]; then
		our_state="discharging"
	elif [[ "$charging_status" == "disabled" && "$discharging_status" != "discharging" && "$ac_attached" == "1" ]]; then
		our_state="maintaining"  # Charging off, not discharging, on AC = maintaining
	elif [[ "$charging_status" == "disabled" ]]; then
		our_state="charged"      # Charging off, not on AC = fully charged
	fi

	pmset_output=$(pmset -g batt 2>/dev/null)
	pmset_state=$(echo "$pmset_output" | grep InternalBattery | grep -o "not charging\|finishing charge\|AC attached\|discharging\|charging\|charged" | head -1 || echo "unknown")

	echo "   SMC state:    $our_state"
	echo "   pmset state:  $pmset_state"

	if [[ "$pmset_state" == "unknown" ]]; then
		echo "   ⚠️  Cannot parse pmset state"
		echo "      pmset may be reporting an unexpected battery state"
		echo "      Run 'pmset -g batt' to see raw output"
	elif [[ "$our_state" == "unknown" ]]; then
		echo "   ⚠️  Cannot determine SMC state"
		echo "      This may indicate an issue with SMC access"
	elif [[ "$our_state" == "$pmset_state" ]]; then
		echo "   ✅ States match"
	elif [[ ("$our_state" == "maintaining" || "$our_state" == "charged") && ("$pmset_state" == "charged" || "$pmset_state" == "finishing charge" || "$pmset_state" == "not charging" || "$pmset_state" == "AC attached") ]]; then
		echo "   ✅ States match (SMC: $our_state, pmset: $pmset_state)"
		echo "      Battery maintenance is active and working correctly"
	else
		echo "   ⚠️  MISMATCH detected"
		echo "      This may indicate SMC control is active (expected with maintain)"
	fi
	echo ""

	# 4. Check daemon
	echo "4. Checking daemon..."
	if test -f $pidfile; then
		pid=$(cat $pidfile 2>/dev/null)
		if ps -p $pid -o command= 2>/dev/null | grep -q "battery.*maintain"; then
			echo "   ✅ Daemon running (PID $pid)"

			# Check metadata
			daemon_metadata_file="$configfolder/daemon.metadata"
			if command -v jq >/dev/null 2>&1 && [[ -f "$daemon_metadata_file" ]]; then
				version=$(jq -r '.version // ""' "$daemon_metadata_file" 2>/dev/null)
				if [[ -n "$version" ]]; then
					echo "   ✅ Metadata present (version: $version)"
					if [[ "$version" != "$BATTERY_CLI_VERSION" ]]; then
						echo "      ⚠️  Version mismatch: daemon=$version, installed=$BATTERY_CLI_VERSION"
					fi
				fi
			else
				if ! command -v jq >/dev/null 2>&1; then
					echo "   ⚠️  Metadata unavailable (jq not installed)"
				else
					echo "   ⚠️  Metadata file missing"
				fi
			fi
		else
			echo "   ⚠️  PID file exists but daemon not running (stale PID)"
		fi
	else
		echo "   ℹ️  No daemon running (not maintaining)"
	fi
	echo ""

	# 5. Check file permissions
	echo "5. Checking file permissions..."
	if [[ -f "$binfolder/battery" ]]; then
		owner=$(ls -l "$binfolder/battery" | awk '{print $3}')
		echo "   ✅ Binary exists ($binfolder/battery)"
		echo "      Owner: $owner"
	else
		echo "   ❌ Binary not found at $binfolder/battery"
	fi

	if [[ -d "$configfolder" ]]; then
		owner=$(ls -ld "$configfolder" | awk '{print $3}')
		echo "   ✅ Config folder exists ($configfolder)"
		echo "      Owner: $owner"
	else
		echo "   ⚠️  Config folder missing: $configfolder"
	fi

	if [[ -f "$logfile" ]]; then
		echo "   ✅ Log file exists"
	else
		echo "   ℹ️  Log file will be created on first use"
	fi
	echo ""

	# 6. Check sudoers configuration
	echo "6. Checking sudoers configuration..."
	visudo_ok=true
	failed_commands=()

	for test_cmd_entry in "${visudo_test_commands[@]}"; do
		cmd="${test_cmd_entry%%:*}"
		label="${test_cmd_entry##*:}"

		if ! sudo -n $cmd >/dev/null 2>&1; then
			visudo_ok=false
			failed_commands+=("$label")
		fi
	done

	if [[ "$visudo_ok" == "true" ]]; then
		echo "   ✅ All SMC commands work without password"
	else
		echo "   ⚠️  Some SMC commands require password:"
		for failed in "${failed_commands[@]}"; do
			echo "      - $failed"
		done
		echo "   Run: battery visudo"
	fi
	echo ""

	# 7. Check for common issues
	echo "7. Checking for common issues..."
	issues_found=false

	# Check CPU type compatibility
	cpu_type=$(get_cpu_type)
	if [[ "$cpu_type" == "apple" ]]; then
		echo "   ✅ Apple Silicon detected (supported)"
	elif [[ "$cpu_type" == "intel" ]]; then
		echo "   ✅ Intel CPU detected (supported)"
	else
		echo "   ⚠️  Unknown CPU type: $cpu_type"
		issues_found=true
	fi

	# Check if maintain is active but percentage is above target
	if test -f $pidfile; then
		maintain_pct=$(cat $maintain_percentage_tracker_file 2>/dev/null)
		if [[ -n "$maintain_pct" ]]; then
			battery_pct=$(get_battery_percentage)
			if [[ $battery_pct -gt $maintain_pct ]]; then
				echo "   ℹ️  Battery ($battery_pct%) above maintain target ($maintain_pct%)"
				echo "      This is normal - tool prevents charging above target"
			fi
		fi
	fi

	if ! $issues_found; then
		echo "   ✅ No common issues detected"
	fi
	echo ""

	# 8. Battery Hardware Details from ioreg
	echo "8. Battery Hardware Details (ioreg)..."
	ioreg_output=$(ioreg -rc AppleSmartBattery 2>/dev/null)

	if [[ -n "$ioreg_output" ]]; then
		# Parse adapter info
		adapter_watts=$(echo "$ioreg_output" | grep '"AdapterDetails"' | grep -o '"Watts"=[0-9]*' | cut -d= -f2)

		# Parse battery metrics
		voltage_mv=$(echo "$ioreg_output" | grep '"Voltage" = ' | grep -o '[0-9]*' | head -1)
		amperage_ma=$(echo "$ioreg_output" | grep '"Amperage" = ' | grep -o '\-\?[0-9]*' | head -1)
		temp_decideg=$(echo "$ioreg_output" | grep '"Temperature" = ' | grep -o '[0-9]*' | head -1)

		# Parse capacity info
		current_cap=$(echo "$ioreg_output" | grep '"AppleRawCurrentCapacity" = ' | grep -o '[0-9]*' | head -1)
		design_cap=$(echo "$ioreg_output" | grep '"DesignCapacity" = ' | grep -o '[0-9]*' | head -1)
		max_cap=$(echo "$ioreg_output" | grep '"AppleRawMaxCapacity" = ' | grep -o '[0-9]*' | head -1)
		cycle_count=$(echo "$ioreg_output" | grep '"CycleCount" = ' | grep -o '[0-9]*' | head -1)
		design_cycles=$(echo "$ioreg_output" | grep '"DesignCycleCount9C"' | grep -o '[0-9]*' | tail -1)

		# Parse cell voltages
		cell_voltages=$(echo "$ioreg_output" | grep '"CellVoltage"=(' | sed 's/.*"CellVoltage"=(\([^)]*\)).*/\1/' | tr ',' ' ')

		# Calculate values
		if [[ -n "$voltage_mv" && -n "$amperage_ma" ]]; then
			# ioreg returns amperage as unsigned 64-bit int. Negative values (discharging)
			# are represented as very large numbers (two's complement).
			# If value > 2^63, convert to signed by subtracting 2^64
			# Use awk for the comparison and conversion since bash can't handle 64-bit ints
			amperage_ma=$(awk -v amp="$amperage_ma" 'BEGIN {
				if (amp > 9223372036854775807) {
					printf "%.0f", amp - 18446744073709551616
				} else {
					printf "%.0f", amp
				}
			}')

			voltage_v=$(awk "BEGIN {printf \"%.2f\", $voltage_mv / 1000}")
			amperage_a=$(awk "BEGIN {printf \"%.2f\", $amperage_ma / 1000}")
			power_w=$(awk "BEGIN {printf \"%.1f\", ($voltage_mv * $amperage_ma) / 1000000}")
		fi

		if [[ -n "$temp_decideg" ]]; then
			temp_c=$(awk "BEGIN {printf \"%.0f\", $temp_decideg / 100}")
		fi

		if [[ -n "$current_cap" && -n "$design_cap" && "$design_cap" -gt 0 ]]; then
			health_pct=$(awk "BEGIN {printf \"%.0f\", ($current_cap / $design_cap) * 100}")
		fi

		# Display results
		if [[ -n "$adapter_watts" ]]; then
			echo "   Adapter:          ${adapter_watts}W"
		fi

		if [[ -n "$voltage_v" && -n "$amperage_a" ]]; then
			echo "   Power Flow:       ${power_w}W (${amperage_a}A @ ${voltage_v}V)"
		fi

		if [[ -n "$temp_c" ]]; then
			echo "   Temperature:      ${temp_c}°C"
		fi

		if [[ -n "$health_pct" && -n "$current_cap" && -n "$design_cap" ]]; then
			echo "   Health:           ${health_pct}% (${current_cap}/${design_cap} mAh)"
			if [[ $health_pct -ge 80 ]]; then
				echo "                     ✅ Good battery health"
			elif [[ $health_pct -ge 60 ]]; then
				echo "                     ⚠️  Battery showing age"
			else
				echo "                     ⚠️  Consider battery replacement"
			fi
		fi

		if [[ -n "$cycle_count" && -n "$design_cycles" ]]; then
			echo "   Cycle Count:      ${cycle_count} / ${design_cycles}"
			cycles_pct=$(awk "BEGIN {printf \"%.0f\", ($cycle_count / $design_cycles) * 100}")
			if [[ $cycles_pct -lt 50 ]]; then
				echo "                     ✅ ${cycles_pct}% of design cycles used"
			elif [[ $cycles_pct -lt 80 ]]; then
				echo "                     ${cycles_pct}% of design cycles used"
			else
				echo "                     ⚠️  ${cycles_pct}% of design cycles used"
			fi
		fi

		# Cell voltages
		if [[ -n "$cell_voltages" ]]; then
			echo "   Cell Voltages:"
			cell_num=1
			for cell_mv in $cell_voltages; do
				cell_v=$(awk "BEGIN {printf \"%.3f\", $cell_mv / 1000}")
				echo "     Cell $cell_num:         ${cell_v}V"
				((cell_num++))
			done
		fi
	else
		echo "   ⚠️  Could not read battery hardware details from ioreg"
	fi
	echo ""

	echo "📋 Summary:"
	echo "   Run 'battery debug' for detailed SMC/pmset comparison"
	echo "   Run 'battery logs 50' to view recent activity"
	echo "   Run 'battery status' for current battery state"

	exit 0

fi
