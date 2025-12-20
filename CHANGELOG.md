# KTP Match Handler - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.9.1] - 2025-12-20

### Added
- **Discord Embed Roster** - Player roster now displays as a rich embed
  - Title shows date + team names: "12/20/2025 Team A vs Team B"
  - Teams shown in side-by-side inline fields with player counts
  - Players listed with bullet format: "- PlayerName (STEAM_0:1:xxx)"
  - Footer shows Match ID and Server hostname
- **Periodic Score Saving** - Scores saved to localinfo every 30 seconds during 1st half
  - `task_periodic_score_save()` runs during live 1st half
  - Ensures score persistence even if `plugin_end` doesn't run (ReHLDS extension mode)
  - New log event: `event=PERIODIC_SCORE_SAVE allies=X axis=Y half=1`
- **Score Sync to Game Ticks** - `msg_TeamScore` hook persists scores on every game scoring tick
  - Synced to `mp_clan_scoring_delay` (default 30 seconds)
  - Immediate persistence when game updates scores

### Fixed
- **Discord Message Formatting** - Removed code block wrapper so markdown renders properly
  - Bold text (`**text**`) and newlines now display correctly
- **Score Persistence in ReHLDS Extension Mode** - Scores now persist across map changes
  - Root cause: `plugin_end()` doesn't reliably fire in extension mode
  - Solution: Proactive score saving every game tick + periodic backup
- **Newline Escaping** - Proper JSON escape sequences for embed field values

### Verified
- **Full Match Flow Tested on VPS** - 1st half → map change → 2nd half restoration
  - Scores correctly restored (2-5 from 1st half)
  - Team names preserved across map change
  - Match ID persisted across halves
  - Tech budget and pause counts preserved

### Technical
- New function: `escape_for_json()` - Handles quotes, backslashes, and newlines for JSON strings
- New function: `send_discord_embed_raw()` - Sends raw JSON payload for embeds
- New function: `start_periodic_score_save()` / `stop_periodic_score_save()` - Task management
- New task ID: `g_taskScoreSaveId` (55612) for periodic score saves
- Global buffers: `g_rosterAlliesEscaped`, `g_rosterAxisEscaped`, `g_rosterEmbedPayload`, `g_serverHostnameEscaped`

---

## [0.9.0] - 2025-12-18

### Added
- **KTP Season Control** - Password-protected command to enable/disable competitive season
  - `/ktpseason` - Check current season status
  - `/ktpseason <password>` - Toggle season active/inactive
  - When off-season, `/start` and `/ktp` are disabled
  - `/draft`, `/12man`, and `/scrim` always available regardless of season
- **Match Password Protection** - Competitive matches require password
  - `/start <password>` and `/ktp <password>` require password entry
  - Failed attempts logged with player info for security audit
  - Prevents unauthorized match starts
- **MATCH_TYPE_DRAFT** - New match type category
  - `/draft` is now its own match type (separate from COMPETITIVE)
  - Always allowed regardless of season status
  - Uses competitive config but no Discord notifications

### Changed
- Match type system expanded from 3 to 4 types: COMPETITIVE, SCRIM, 12MAN, DRAFT
- `/draft` command now uses dedicated `cmd_start_draft` handler

### Security
- Season toggle password: Admin-only access
- Match password: Captain-only access (distributed to team captains)
- Failed password attempts logged with SteamID and IP

---

## [0.8.0] - 2025-12-18

### Added
- **Match Score Tracking** - Live score tracking via TeamScore message hook
  - Cumulative scores across both halves
  - First half scores saved at halftime
  - Final scores logged at match end
- **Discord Match End Notification** - Automatic Discord notification with final score
  - Shows team names, final score, and half breakdown
  - Winner announcement
- **Team Name Support** - Custom team names instead of Allies/Axis
  - `/setteamallies <name>` - Set custom name for Allies team
  - `/setteamaxis <name>` - Set custom name for Axis team
  - `/teamnames` - Show current team names
  - `/resetteamnames` - Reset to default Allies/Axis
  - Team names used in all announcements and Discord messages
- **Score Command** - `/score` shows current match score with half breakdown
- **Configurable Reminder Intervals**
  - `ktp_unready_reminder_secs` - Interval for unready player reminders (default 30s)
  - `ktp_unpause_reminder_secs` - Interval for unpause confirmation reminders (default 15s)
- **Unpause Reminder Notifications** - Periodic reminders when waiting for unpause confirmation
  - Reminds team that hasn't confirmed to `/confirmunpause` or `/resume`
- **Captain Team Name Prompt** - Captains are prompted to set team name when they `/confirm`
  - Only prompted if team name is still default (Allies/Axis)
  - Shows example usage: `/setteamallies KTP`

### Fixed
- **Side Swap Score Calculation** - Scores now correctly tracked when teams swap sides at halftime
  - Team identity preserved across halves via `g_team1Name` / `g_team2Name` variables
  - First half scores and team names persisted via localinfo
  - Final scores properly calculated: Team1 = 1st half (Allies) + 2nd half (Axis)
  - Discord notifications show correct team totals

### Technical
- TeamScore message hook for DoD score tracking
- Score reset at match start (1st half only)
- Team names reset to defaults after match ends
- New stock functions: `reset_match_scores()`, `save_first_half_scores()`, `get_match_score_string()`
- New localinfo keys: `_ktp_score_t1`, `_ktp_score_t2`, `_ktp_teamname1`, `_ktp_teamname2`
- Team identity variables: `g_team1Name`, `g_team2Name` (persisted across side swap)

---

## [0.7.1] - 2025-12-18

### Added
- Match context persistence via localinfo - Match ID, pause counts, and tech budget survive map changes
- Per-match pause limits - Tactical pauses and tech budget now persist across halves
- 2nd half announcements showing match ID and pause usage status

### Fixed
- Match ID now properly restored when 2nd half starts
- Pause count persistence - counts carry over from 1st to 2nd half
- Tech budget persistence - remaining budget carries over to 2nd half

### Technical
- Localinfo keys: `_ktp_match_id`, `_ktp_half_pending`, `_ktp_pause_allies/axis`, `_ktp_tech_allies/axis`
- Context saved in `handle_map_change()`, restored in `plugin_cfg()`

---

## [0.7.0] - 2025-12-17

### Added
- HLStatsX integration for clean separation of warmup vs match stats
- DODX natives: `dodx_flush_all_stats()`, `dodx_reset_all_stats()`, `dodx_set_match_id()`
- `KTP_MATCH_START` log marker for HLStatsX daemon parsing
- `KTP_MATCH_END` log marker for HLStatsX daemon parsing
- `(matchid "xxx")` property in weaponstats log lines

### Improved
- Automatic stats flushing at half/match end with appropriate matchid
- Warmup stats logged without matchid before match starts

### Requirements
- DODX module with HLStatsX natives (KTPAMXX)
- HLStatsX daemon with KTP event handlers (KTPHLStatsX)

---

## [0.6.0] - 2025-12-16

### Added
- Unique match ID system - Format: `KTP-{timestamp}-{mapname}`
- Match ID persistence across both halves for MySQL/stats correlation
- Match ID displayed in Discord notifications (code block)
- `/whoneedsready` command - shows unready players with Steam IDs
- `/unready` alias for `/whoneedsready`
- Steam IDs now displayed in READY/NOTREADY announcements
- Periodic unready player reminder every 30 seconds during ready phase

### Improved
- Half tracking now logs match_id in HALF_START and HALF_END events
- Streamlined match flow - goes LIVE immediately when all ready (no pause)

### Removed
- Automatic pause during ready phase
- Unpause countdown at match start

---

## [0.5.2] - 2025-12-03

### Fixed
- Dynamic config paths using `get_configsdir()` for automatic path resolution
- Removed hardcoded `addons/amxmodx` paths for KTP AMX compatibility
- ReAPI availability message changed from WARNING to informational note

### Improved
- Cross-platform support for both AMX Mod X and KTP AMX without modification
- Better user feedback when optional features are unavailable

---

## [0.5.1] - 2025-12-02

### Fixed
- **[CRITICAL]** cURL header memory leak causing accumulation on every Discord message
- **[CRITICAL]** Tech pause budget integer underflow from system clock adjustments
- **[HIGH]** Buffer overflow in player roster concatenation with 12+ players per team
- **[HIGH]** Inconsistent team ID validation before g_techBudget array access
- **[MEDIUM]** Various state cleanup and validation improvements

---

## [0.5.0] - 2025-11-24

### Added
- Match type system - COMPETITIVE, SCRIM, 12MAN modes with distinct behaviors
- Per-match-type configs - Auto-load `mapname_12man.cfg` or `mapname_scrim.cfg` with fallback
- Per-match-type Discord channels - Route to different channels based on match type
- Half tracking system - Automatic 1st/2nd half detection and logging
- Automatic map rotation - Sets next map to current map for 2nd half
- Half number in messages - Discord shows "(1st half)" or "(2nd half)"
- Player roster logging - Full team lineups logged to Discord at match start (competitive only)
- Dot command aliases - All commands now work with `.` prefix (`.pause`, `.ready`, etc.)
- `/draft` command - Alias for `/start` and `/ktp`

### Changed
- `/startmatch` renamed to `/ktp` (kept `/start`)
- `/start12man` renamed to `/12man` with `.12man` alias
- `/startscrim` renamed to `/scrim` with `.scrim` alias
- Removed `ready` and `ktp` word aliases (conflict resolution)

### Improved
- Discord routing with match-type-specific channels and graceful fallback
- Config selection tries match-type-specific configs first, falls back to standard
- Player accountability with full roster (SteamIDs and IPs) for competitive matches

---

## [0.4.6] - 2025-11-22

### Fixed
- Match start entering uncontrollable tactical pause instead of LIVE countdown
- Team confirmation triggering pre-pause countdown (wrong flow)
- Countdown task not running during pause (tasks don't execute when paused)

### Changed
- Countdown handling moved to `OnPausedHUDUpdate()` hook (runs during pause)
- Confirmation now directly executes pause (no countdown)
- Ready completion stays paused, starts countdown for smooth transition

---

## [0.4.5] - 2025-11-22

### Added
- `/startscrim` and `/start12man` commands (skip Discord notifications)
- `g_disableDiscord` flag to control Discord webhook calls

### Fixed
- Missing task cleanup before pre-pause countdown (race condition)
- Missing pre-pause task cleanup in `plugin_end()` (memory leak)
- Tech budgets not reset on match cancel (state carry-over)
- Pre-pause state not cleared on match cancel
- Double timestamp assignment race condition in pause flow
- Disconnect state not cleared after unpause
- Missing countdown task cleanup before `set_task()` (duplicate tasks)
- Multiple simultaneous disconnects overwriting first disconnect info

### Optimized
- Removed duplicate config loading in `plugin_init()` (~25ms faster startup)

---

## [0.4.4] - 2025-11-21

### Optimized
- Eliminated 8 redundant `get_mapname()` calls (use cached `g_currentMap`)
- Cached `g_pauseDurationSec` and `g_preMatchPauseSeconds` CVARs
- Index-based `formatex` in `cmd_status()` (30-40% faster string building)
- Switch statement in `get_ready_counts()` for cleaner team ID handling
- 15-20% reduction in string operations during logging
- 5-10% faster pause initialization with cached CVARs

---

## [0.4.3] - 2025-11-20

### Added
- `send_discord_with_hostname()` helper function
- Hostname prefix to all Discord notifications

### Changed
- Disabled non-essential Discord notifications
- Only 3 essential notifications kept: Match start, Player pause, Disconnect auto-pause

---

## [0.4.2] - 2025-11-20

### Fixed
- Discord notifications not working (curl.inc was disabled)
- Compilation errors with backslash character constants
- JSON string escaping in formatex
- Invalid cURL header constant

### Requirements
- `curl_amxx.dll` module enabled in `modules.ini`
- `discord.ini` with relay URL, channel ID, and auth secret

---

## [0.4.1] - 2025-11-17

### Removed
- All pausable cvar manipulation code (no longer needed with ReAPI)
- `ktp_force_pausable` cvar
- `g_pcvarPausable` and `g_cvarForcePausable` variables

### Improved
- Cleaner code (~33 lines removed)
- Simpler client messages ("Game paused" vs "Pause enforced")

---

## [0.4.0] - 2025-11-17

### Added
- ReAPI pause natives - `rh_set_server_pause()` for direct control
- Works with `pausable 0` - Block engine pause, use KTP system only
- Unified countdown system - ALL pause entry points use countdown
- Pre-pause countdown - 5-second warning before pause
- Pause extensions - `/extend` adds 2 minutes (max 2x)
- Real-time HUD updates - MM:SS timer via ReAPI hook
- Auto-warnings at 30-second and 10-second marks
- Auto-unpause when timer expires
- Disconnect auto-pause with 10-second cancellable countdown
- Discord relay integration for webhooks
- New section-based map INI format
- Comprehensive logging (AMX + KTP log + Discord)

### Changed
- Pause implementation uses ReAPI natives instead of `server_cmd("pause")`
- Removed `pause` command registration (no conflicts)
- Platform degradation with graceful fallback for non-ReAPI servers

### Fixed
- `Cmd_AddMallocCommand` error - No more pause command conflicts
- HUD during pause - Real-time updates using `get_systime()`
- Server messages during pause - rcon say and events work with KTP-ReHLDS
- Ready system bugs - Undefined variable warnings
- Unsafe task removal - All `remove_task()` calls now safe

### Performance
- CVAR caching - Reduced ~180 lookups/sec during pause
- Static variables to prevent duplicate warnings
- Optimized HUD - Only updates when needed

### Documentation
- `DISCORD_GUIDE.md` - Complete KTP stack guide
- `REAPI_PAUSE_IMPLEMENTATION.md` - ReAPI pause technical guide
- `SERVER_TROUBLESHOOTING.md` - Debugging guide
- `PAUSE_SYSTEM_REDESIGN.md` - v0.4.0 pause system overview

---

## [0.3.3] - Previous Stable

- Two-team unpause confirmation
- Per-team tactical pause limits
- Technical pause budget system
- Disconnect detection
- Pre-start confirmation
- Discord webhook integration (direct)

---

[0.9.1]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/afraznein/KTPMatchHandler/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/afraznein/KTPMatchHandler/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/afraznein/KTPMatchHandler/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.6...v0.5.0
[0.4.6]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.5...v0.4.6
[0.4.5]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/afraznein/KTPMatchHandler/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/afraznein/KTPMatchHandler/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/afraznein/KTPMatchHandler/releases/tag/v0.3.3
