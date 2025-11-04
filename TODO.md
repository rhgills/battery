# TODO List

## High Priority

### Consistency Across Commands
- [ ] **Unify power flow display across doctor, info, status, and debug**
  - Currently `battery doctor` shows detailed power flow from ioreg
  - `battery debug` shows power flow with direction indicators
  - `battery info` and `battery status` don't show power flow at all
  - Goal: Consistent display of actual power consumption/generation across all commands

- [ ] **Make charging state more consistent across all commands**
  - Different commands show state differently (charging/discharging/maintaining/idle/charged)
  - Need unified language and detection logic
  - Should clearly distinguish between:
    - Actual battery state (charging, discharging, idle)
    - Maintenance mode state (above target, below target, within range)
    - SMC control state (charging enabled/disabled, forced discharge enabled/disabled)

- [ ] **Show actual power draw in battery status**
  - Add power flow to `battery status` output
  - Examples: "+15W charging", "-8W discharging", "0W maintaining"
  - Quick visibility into actual power consumption without running debug/doctor
  - Helps users quickly verify the system is doing what they expect

### Code Quality

- [ ] **Refactor duplicate state detection logic into shared helper function**
  - Similar state detection logic exists in:
    - `battery info` (lines ~632-638)
    - `battery debug` (lines ~1629-1641)
    - `battery doctor` (lines ~1700-1710)
    - `battery status` (maintenance state detection)
  - Create `get_battery_state()` helper that returns unified state
  - Reduces duplication, improves maintainability
  - Makes state detection logic easier to fix/enhance in one place

- [ ] **Investigate and handle SMC read errors gracefully**
  - Seeing `Error:SMCReadKey(=e00002c1` in debug output for some keys
  - This appears when reading CH0J and other keys on some systems
  - Should:
    - Understand what this error means (permission? unsupported key? hardware issue?)
    - Handle gracefully instead of showing raw error in output
    - Provide helpful message if it indicates a problem
    - Fall back to alternative methods if available

## Nice to Have

- [ ] **Consider adding 'battery quick' command**
  - Minimal output for scripts/status bars
  - Just battery percentage and state
  - Example: `95% discharging (-10W)`
  - Useful for integration with tmux, shell prompts, status bars
  - Should be very fast (minimal SMC queries)

- [ ] **Update CHANGELOG.md for v1.3.2 completion**
  - Document recent commits:
    - Clarified "Discharging" → "Forced Discharge" label
    - Changed status values to enabled/disabled for consistency
    - All the clarity improvements
  - Consider bumping to v1.3.3 if substantial changes

## Future Enhancements

- [ ] **Better error messages for common issues**
  - When daemon isn't running but should be
  - When SMC access fails
  - When visudo isn't configured

- [ ] **Add validation mode**
  - `battery validate` - runs through all checks and reports issues
  - Combines doctor + debug + additional validation
  - Reports what's working, what's not, and how to fix

- [ ] **Improve forced discharge UX**
  - Current `battery adapter on` name is confusing
  - Consider alias: `battery force-discharge on/off`
  - Or: `battery discharge --force` to force discharge even when plugged in

## Notes

- **Design principle**: Minimize drift from upstream while improving clarity
  - Keep root functions unchanged where possible
  - Use wrapper functions and helper functions
  - Extensive comments explaining confusing parts
  - Makes merging upstream changes easier

- **User confusion points addressed so far**:
  - ✅ "Discharging: not discharging" → "Forced Discharge: disabled"
  - ✅ Function names (enable_discharging → force_battery_discharge wrapper)
  - ✅ Enhanced status output explaining relationship to target
  - ✅ Power flow calculation overflow bug fixed

- **Testing checklist for changes**:
  - [ ] Run `bash -n battery.sh` for syntax check
  - [ ] Test `battery status` with daemon running
  - [ ] Test `battery info` while on battery and on AC
  - [ ] Test `battery debug` and verify cross-check logic
  - [ ] Test `battery doctor` and verify all checks pass
  - [ ] Verify daemon restart works: `./dev.sh restart-daemon`
