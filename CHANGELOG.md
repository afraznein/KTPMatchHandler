# KTP Match Handler - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0] - 2025-01-15

### Major Overhaul: Unified Pause System with Graceful Platform Degradation

This release completely redesigns the pause system with unified countdown handling, proper platform attribution, and graceful degradation across base AMX, standard ReHLDS, and KTP-ReHLDS platforms.

### Added
- **Unified Pause Countdown System**
  - ALL pause entry points now use countdown system (chat, console, RCON, server commands)
  - Separate configurable countdowns for live matches vs pre-match pauses
  - Pre-pause countdown works on ALL platforms (base AMX, ReHLDS, KTP-ReHLDS)
  - Intercepts client `pause` console command, server `pause`, and RCON `pause`
  - Proper `register_srvcmd()` and `register_concmd()` for comprehensive coverage

- **Graceful Platform Degradation**
  - Base AMX: Core features work, timer checks on player commands
  - Standard ReHLDS: Same as base AMX with `rcon_say` announcements during pause
  - KTP-ReHLDS + ReAPI: Full feature set with automatic real-time updates
  - Manual timer check system (`check_pause_timer_manual()`) for non-KTP-ReHLDS
  - `announce_all()` automatically uses `rcon_say` during pause on base platforms

- **ReAPI Integration (Optional Enhancement)**
  - `RH_SV_UpdatePausedHUD` hook for automatic real-time HUD updates (KTP-ReHLDS only)
  - HUD updates every frame during pause using real-world time (`get_systime()`)
  - Automatic pause timer checks without player interaction (KTP-ReHLDS only)

- **Comprehensive Pause System** (Works on ALL platforms)
  - Timed pauses: 5-minute default with MM:SS countdown display
  - Extension system: `/extend` adds 2 minutes (max 2 extensions = 9 minutes total)
  - Auto-unpause when timer expires (automatic on KTP-ReHLDS, on-command elsewhere)
  - Real-time pause tracking using `get_systime()` (works everywhere)
  - Pause timer warnings at 30s and 10s remaining

- **New CVARs**
  - `ktp_pause_duration "300"` - Pause duration in seconds (default: 5 minutes)
  - `ktp_pause_extension "120"` - Extension duration in seconds (default: 2 minutes)
  - `ktp_pause_max_extensions "2"` - Maximum number of extensions allowed
  - `ktp_prepause_seconds "5"` - Pre-pause countdown for live matches
  - `ktp_prematch_pause_seconds "5"` - Pre-pause countdown for pre-match pauses

- **New Commands**
  - `/extend` - Extend current pause by configured time (max extensions limited)
  - `/cancelpause` - Cancel disconnect auto-pause countdown (team-only)

- **Map Configuration System**
  - New INI section-based format for `ktp_maps.ini`
  - Supports `[mapname]`, `config=`, `name=`, `type=` fields
  - More maintainable and extensible than simple key=value format
  - Automatic `.bsp` suffix stripping and lowercase conversion

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
  - ALL pause functions now route through unified `trigger_pause_countdown()`
  - Replaced instant pauses with countdown system (configurable duration)
  - Pre-match pauses now use separate countdown (`ktp_prematch_pause_seconds`)
  - Real-time timer system uses `get_systime()` instead of frozen game time
  - Client console `pause`, server `pause`, and RCON `pause` all intercepted
  - `cmd_client_pause()` now triggers countdown instead of blocking

- **Platform-Specific Handling**
  - `announce_all()` automatically selects `rcon_say` or `client_print` based on pause state
  - Conditional compilation for ReAPI-specific features
  - Fallback timer checks via `check_pause_timer_manual()` on player commands
  - All broadcast messages now use `announce_all()` for pause compatibility

- **Ready System**
  - Simplified ready check logic (removed redundant player count checks)
  - Now only checks: `alliesReady >= g_readyRequired && axisReady >= g_readyRequired`
  - Cleaner, more efficient condition

- **Documentation**
  - Updated all comments to correctly attribute features to platforms:
    - "Base AMX" for features that work on HLDS + AMX ModX
    - "Standard ReHLDS" for ReHLDS-specific features
    - "KTP-ReHLDS" for custom build features
  - Header now shows graceful degradation across platforms
  - Changelog reflects true platform requirements

- **HUD Updates**
  - Redesigned pause HUD with clean minimalist layout
  - Shows elapsed time (MM:SS format)
  - Shows remaining time (MM:SS format)
  - Shows extensions used (X/max)
  - Displays available commands: /resume, /confirmunpause, /extend
  - Updates automatically on KTP-ReHLDS, static on other platforms

- **Disconnect Handling**
  - Auto-pause countdown increased from 5 to 10 seconds
  - Uses new countdown system for consistency
  - Enhanced messages show team name and cancel instructions

### Fixed
- **Platform-Specific Announcements During Pause**
  - Fixed announcements during pause on base AMX/standard ReHLDS using `rcon_say`
  - Countdown timers now use `get_systime()` (real-world time) on all platforms
  - Timer checks work on base AMX via player command interaction

- **Pause Entry Point Coverage**
  - Now intercepts ALL pause commands: client console, server, RCON, chat
  - Proper `register_srvcmd()` and `register_concmd()` registration
  - Unified countdown system prevents instant pauses from any source

- **Ready System Logic**
  - Fixed redundant player count checks in ready condition
  - More efficient condition evaluation

- **Chat During Pause (KTP-ReHLDS)**
  - Works correctly with KTP-ReHLDS modifications
  - `client_print` works during pause on KTP-ReHLDS
  - Automatic fallback to `rcon_say` on other platforms

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
- **Minimum:** AMX ModX 1.9+ (base functionality)
- **Recommended:** Standard ReHLDS (no additional features, but better compatibility)
- **Optimal:** KTP-ReHLDS + ReAPI module (full feature set with automatic updates)
- **Optional:** cURL extension for Discord notifications

### Platform Support
- **Base AMX (HLDS):** ✅ Core features, manual timer checks
- **Standard ReHLDS:** ✅ Same as base AMX with `rcon_say` support
- **KTP-ReHLDS + ReAPI:** ✅ Full automatic real-time updates

### Breaking Changes
- None - fully backward compatible with graceful degradation
- New map INI format (old format still supported via parser)
- `ktp_prematch_pause_seconds` CVAR added (defaults to 5)

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

