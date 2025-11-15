# KTP Match Handler - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0] - 2025-01-15

### Major Overhaul: Comprehensive Pause System with ReAPI Integration

This release completely redesigns the pause system to work properly with real-time updates during pause, using ReAPI hooks and the custom KTP-ReHLDS build.

### Added
- **ReAPI Integration**
  - Added `RH_SV_UpdatePausedHUD` hook for real-time HUD updates during pause
  - HUD now updates every frame during pause using real-world time instead of frozen game time
  - No longer relies on AMX ModX `set_task()` which freezes during pause

- **Comprehensive Pause System**
  - Pre-pause countdown (3 seconds configurable) before pause activates
  - Intercepts ALL pause commands (client console pause, RCON pause, chat /pause)
  - 5-minute default pause duration with visible countdown timer
  - Extension system: `/extend` command adds 2 minutes (max 2 extensions = 9 minutes total)
  - Auto-unpause when timer expires with countdown
  - Real-time elapsed/remaining time display in MM:SS format
  - Chat notifications work during pause (via KTP-ReHLDS modifications)

- **New CVARs**
  - `ktp_pause_duration "300"` - Pause duration in seconds (default: 5 minutes)
  - `ktp_pause_extension "120"` - Extension duration in seconds (default: 2 minutes)
  - `ktp_pause_max_extensions "2"` - Maximum number of extensions allowed

- **New Commands**
  - `/extend` - Extend current pause by configured time (max extensions limited)
  - `/cancelpause` - Cancel disconnect auto-pause countdown (team-only)

- **Enhanced Disconnect Auto-Pause**
  - Increased countdown from 5 to 10 seconds
  - Team can cancel auto-pause with `/cancelpause` command
  - Integrated with new pause system for real-time HUD updates
  - Shows team name and cancel option in countdown messages

- **Comprehensive Logging**
  - AMX log entries for all pause events
  - Discord webhook notifications for:
    - Pause initiated with countdown
    - Pause activated with duration and extension info
    - 30-second warning before timeout
    - Pause timeout and auto-unpause
    - Pause extensions
    - Unpause countdown
    - Match LIVE with total pause duration
    - Auto-pause cancelled

### Changed
- **Pause System Architecture**
  - Replaced game-time based `pause_timer_tick()` with real-time `check_pause_timer_realtime()`
  - Removed `set_task()` calls for pause HUD and timer (now handled by ReAPI hook)
  - `execute_pause()` function now handles all pause logic consistently
  - `cmd_block_pause()` now triggers countdown instead of blocking
  - Pause HUD displays elapsed/remaining time instead of static info

- **HUD Updates**
  - Redesigned pause HUD with clean minimalist layout
  - Shows elapsed time (MM:SS format)
  - Shows remaining time (MM:SS format)
  - Shows extensions used (X/max)
  - Displays available commands: /resume, /confirmunpause, /extend
  - Updates in real-time via ReAPI hook

- **Disconnect Handling**
  - Auto-pause countdown increased from 5 to 10 seconds
  - Uses new `execute_pause()` instead of `ktp_pause_now()`
  - Removed manual HUD task scheduling (handled by ReAPI hook)
  - Enhanced messages show team name and cancel instructions

### Fixed
- **Critical: Pause HUD Updates During Pause**
  - HUD now updates properly during pause using ReAPI hook
  - Countdown timers work during pause using `get_systime()` (real-world time)
  - Fixed issue where AMX tasks wouldn't execute because game time was frozen

- **Chat During Pause**
  - Works correctly with KTP-ReHLDS modifications
  - Message sending forced during pause state
  - Commands process with frametime manipulation

### Technical Details
- **ReAPI Hook Implementation**
  - `OnPausedHUDUpdate()` called every frame during pause
  - `check_pause_timer_realtime()` uses `get_systime()` for accuracy
  - Static variables prevent duplicate warnings
  - Integrates seamlessly with KTP-ReHLDS `SV_UpdatePausedHUD()` hook

- **Real-Time Calculations**
  ```pawn
  new elapsed = get_systime() - g_pauseStartTime;
  new remaining = totalDuration - elapsed;
  ```

### Requirements
- **ReAPI** module required (https://github.com/s1lentq/reapi)
- **KTP-ReHLDS** build with selective pause modifications
- **AMX ModX** 1.9 or higher
- **Optional: cURL** for Discord notifications

### Breaking Changes
- ReAPI is now **required** for pause system to function
- Old `pause_timer_tick()` function removed
- Plugin will assert/fail to compile without ReAPI

---

## [0.3.3] - Previous Release

### Features
- Two-team confirm unpause system
- Per-team tactical pause limits (1 per half)
- Technical pause with budget system
- Auto-request unpause after timeout
- Disconnect detection with auto tech-pause
- Pre-start confirmation system
- Ready-up system for match start
- Map configuration via INI file
- Discord webhook integration (optional)
- Comprehensive logging to KTP match log

### Commands
- `/pause`, `/resume` - Tactical pause/unpause
- `/tech` - Technical pause
- `/confirmunpause` - Confirm unpause from other team
- `/start`, `/startmatch` - Initiate pre-start
- `/confirm` - Confirm team ready for start
- `/ready`, `/ktp` - Mark player as ready
- `/notready` - Unmark player as ready
- `/status` - Show current match status
- `/cancel` - Cancel match/pre-start
- `/reloadmaps` - Reload map configurations

---

## Version History Summary

- **0.4.0** - Complete pause system overhaul with ReAPI integration
- **0.3.3** - Stable release with tactical/technical pause system
- **0.3.x** - Initial development versions
- **0.2.x** - Early beta versions
- **0.1.x** - Alpha versions

---

## Migration Guide: 0.3.3 → 0.4.0

### Server Requirements
1. Install ReAPI module if not already installed
2. Update to KTP-ReHLDS build (required for chat during pause)
3. No CVAR changes required (new CVARs have sensible defaults)

### New Features to Communicate
- Teams can now extend pauses with `/extend` (max 2 times)
- All pauses now have visible countdown timers
- Disconnect auto-pause can be cancelled with `/cancelpause`
- Real-time HUD updates during pause

### Removed/Changed
- Manual HUD task scheduling removed (automatic via ReAPI)
- `pause_timer_tick()` removed (replaced by real-time system)
- Pause duration is now configurable and enforced with auto-unpause

---

## Future Plans

### Planned Features
- Configurable pre-pause countdown duration
- Pause statistics and analytics
- Admin override commands for pause management
- Pause reason logging
- Enhanced Discord embed formatting

### Known Issues
- None currently reported

---

## Credits

**Author:** Nein_
**Engine:** AMX ModX 1.9+ with ReAPI
**Server:** KTP-ReHLDS (Modified ReHLDS for selective pause)

### Special Thanks
- ReAPI developers for hook chain system
- s1lentq for ReHLDS
- AMX Mod X team

---

## Links

- **GitHub Issues:** (Add your repository URL)
- **ReAPI:** https://github.com/s1lentq/reapi
- **ReHLDS:** https://github.com/dreamstalker/rehlds
- **KTP-ReHLDS:** (Add your fork URL)

