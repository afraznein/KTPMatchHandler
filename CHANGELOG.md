# KTP Match Handler - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.10.84] - 2026-02-25

### Fixed
- **No HTTP response code validation in Discord callbacks** — Both `discord_callback` and `discord_embed_callback` only checked `CURLcode` transport-level success, never the HTTP response code. Discord relay returning 401/500 was silently treated as success. Now checks `CURLINFO_RESPONSE_CODE` and logs HTTP errors with status code.
- **OT break state not cleared in force reset** — `execute_force_reset()` didn't clear `g_otBreakActive`, `g_otBreakTimeLeft`, `g_otBreakVotes[]`, `g_otBreakExtensions[]`, or remove OT break vote/tick tasks. Force-resetting during an OT break left stale state that could interfere with subsequent matches.
- **Dead conditions in Discord message escape logic** — Default branch in `send_discord_message()` escape switch checked `message[i] == 10 || message[i] == 13 || message[i] == 9`, but these values are already handled by explicit switch cases above and can never reach the default. Simplified to `message[i] >= 32`.

### Removed
- **`g_readyRequired` variable and `ktp_ready_required` cvar** — Variable was synced from cvar but `get_required_ready_count()` uses hardcoded values by match type (6 for KTP/KTP OT, 5 for all others), never referencing the cvar. Removed variable, cvar pointer, cvar registration, and cvar sync.
- **`send_discord_with_hostname()`** — Never called; replaced by embed-based messaging.
- **`send_player_roster_to_discord()`** (~90 lines) — Never called; replaced by consolidated embed system (`send_match_embed_create`/`send_match_embed_update`).

---

## [0.10.83] - 2026-02-25

### Fixed
- **Tied match incorrectly reported as Team 2 win** — `finalize_completed_second_half()` used a two-way if/else where the `else` clause caught both "team2 wins" and "tied" cases, reporting ties as Team 2 victories in Discord embeds and logs. Added three-way if/else-if/else with explicit tie case.
- **Variable shadowing in `OnPausedHUDUpdate()`** — Inner `new currentTime` shadowed the outer variable, causing the tech budget countdown to use a stale value. Removed the inner declaration.
- **Malformed backslash check in `exec_map_config()`** — Character literal `'\'` was a compiler-specific undefined behavior. Replaced with hex literal `0x5C`.
- **Match type lost across halftime map change** — `g_matchType` was never saved to localinfo, resetting to COMPETITIVE after map change. Draft/scrim/12man matches fired wrong match type in `ktp_match_start`/`ktp_match_end` forwards, affecting HLStatsX and HLTVRecorder. Added `_ktp_mtyp` localinfo persistence.
- **Discord channel ID not set for simple embeds** — `send_discord_simple_embed()` relied on callers to pre-populate `g_discordChannelIdBuf`. Moved `get_discord_channel_id()` call inside the function and removed all 7 caller-side calls.
- **Pipe delimiter collision in roster serialization** — Player names containing `|` or `;` could corrupt the `name|steamid;name|steamid` localinfo format. Added `sanitize_name_for_localinfo()` that strips these characters from names before serialization.

### Changed
- **OT break tasks use dedicated IDs** — Both OT break vote and tick tasks shared default ID 0, making `remove_task()` from `.otskip` unreliable. Assigned unique IDs 55617 and 55618.
- **Optimized roster restore** — Cached `strlen(buf)` before both roster restore loops to eliminate O(n²) rescanning on every iteration.
- **Dual static buffers in `safe_sid()`** — Alternating two buffers prevents stale pointer reuse when called twice in the same expression.
- **Removed unused `tname[16]` buffer** from `get_user_team_id()`.

### Removed
- **Dead code cleanup (~165 lines)** — Removed `start_changelevel_countdown()`/`task_changelevel_countdown()` (superseded by watchdog system), `cmd_client_pause()` (never registered), `unpause_reminder_tick()`/`start_unpause_reminder()`/`stop_unpause_reminder()` (superseded by `OnPausedHUDUpdate` real-time hook), `auto_confirmunpause_tick()` (never scheduled), and associated variables/call sites.
- **Unreachable tech budget deduction** — 57 lines in `countdown_tick()` that could never execute because AMXX tasks don't fire during engine pause.

### Refactored
- **Discord code extracted to `ktp_matchhandler_discord.inc`** — ~980 lines of Discord messaging, embeds, roster tracking, and config loading moved to a separate include file. Purely organizational — identical compiled output (561,212 bytes).
- **`compile.sh` updated** — Now copies local `.inc` files to the temp build directory with CR/LF stripping, and adds `-i.` for local include resolution.

---

## [0.10.82] - 2026-02-25

### Fixed
- **pfnChangeLevel hook firing millions of times during intermission** — Game DLL calls `pfnChangeLevel` for every map in the mapcycle during intermission (~9000 calls/sec). v0.10.78's rate-limiting only throttled logging but the hook handler still executed every call, generating 26M+ log entries and 3.7 GB log files on ATL1 alone. Added `g_pfnChangeLevelProcessed` debounce flag — only the first call per intermission cycle is processed, all subsequent calls return immediately with zero overhead. Flag resets on map load. Prestart/pending still blocks every call (HC_SUPERCEDE). Cleaned ~10 GB of bloated logs from ATL and NY.

---

## [0.10.81] - 2026-02-25

### Fixed
- **Discord score updates not posting (stack overflow in callback)** - v0.10.80 introduced `new responseBuffer[4096]` as a local variable inside `discord_embed_callback`. In Pawn, local arrays are stack-allocated — 4096 cells = 16KB, exceeding the available stack space. Every match embed POST crashed the callback with runtime error 3 (stack error) before it could parse the Discord message ID. Without the message ID, all subsequent edits (half-time scores, final scores, match complete status) were silently skipped. Moved to a 512-cell global buffer `g_discordResponseBuf`. Confirmed hitting ATL4 (3 crashes on Feb 24) and CHI2 (1 crash).

---

## [0.10.80] - 2026-02-23

### Fixed
- **Recurring discord_curl_write segfaults** - Eliminated Pawn-level `discord_curl_write` WRITEFUNCTION callback entirely. The `MF_ExecuteForward` → `amx_Allot` path could fail silently under memory pressure, writing response data to an uninitialized pointer and corrupting the heap. Now uses KTPAmxxCurl 1.3.0's built-in C++ response body capture (`curl_get_response_body` native) — response is buffered safely in `std::string` and read in the completion callback. Removes `g_discordResponseBuffer`, `g_discordResponseBufPos` globals and the `discord_curl_write` function.

### Changed
- **Requires KTPAmxxCurl 1.3.0-ktp** - Uses new `curl_get_response_body()` native for Discord embed response capture.

---

## [0.10.78] - 2026-02-22

### Fixed
- **1GB+/day AMXX log spam from pfnChangeLevel hook** - v0.10.72 added `RH_PF_changelevel_I` hook that logged every call. DoD game DLL calls pfnChangeLevel for every map in the mapcycle during intermission (~10 maps/frame × 900fps = ~9000 calls/sec), generating 6.85M log entries/day. Rate-limited to first 3 calls + every 10000th.
- **Stuck server after failed map change (no match active)** - Added 15-second general changelevel watchdog for the no-match passthrough case. If the engine's changelevel doesn't complete (SV_SpawnServer fails silently), the watchdog forces `map` command which uses a separate engine path. Previously only halftime had a watchdog.
- **Forcereset leaving dangling tasks** - `execute_force_reset()` didn't clean up `g_taskScoreRestoreId`, `g_taskMatchStartLogId`, `g_taskHalftimeWatchdogId`, or `g_taskGeneralWatchdogId`. Also didn't clear `g_pendingScoreAllies/Axis`, `g_delayedMatchId/Map/Half`, or reset `g_changeLevelHandled`. These stale tasks/state could interfere with a new match started within seconds of a forcereset.

---

## [0.10.77] - 2026-02-21

### Fixed
- **Discord curl use-after-free causing crashes** - All 5 Discord send functions (`send_discord_message`, `send_discord_simple_embed`, `send_discord_embed_raw`, `send_match_embed_create`, `send_match_embed_update`) shared a single `g_curlHeaders` slist that was freed and recreated on every request. When async requests overlapped (e.g., match start fires embed create + stats flush simultaneously), the second request's `curl_slist_free_all` destroyed headers the first curl handle was still pointing to — use-after-free. Both callbacks (`discord_callback`, `discord_embed_callback`) also freed the shared headers. Fixed by creating headers once at plugin init and reusing the persistent slist. Same pattern as KTPHLTVRecorder v1.5.1 fix. NY1 crash at 22:01 ET (segfault in `_IO_flush_all_linebuffered`) was preceded by `discord_curl_write` memory errors earlier in the day — likely heap corruption from this bug.

---

## [0.10.76] - 2026-02-21

### Fixed
- **Half text truncation in KTP_MATCH_START log** - `g_delayedHalf[8]` buffer was too small for "1st half" (8 chars + null = 9 bytes needed). `charsmax()` returned 7, truncating to "1st hal". Increased to `g_delayedHalf[16]`. Affected HLStatsX match parsing.

---

## [0.10.75] - 2026-02-21

### Fixed
- **Menu crash from stale callback after map change** - `menu_12man_type_handler` and `menu_12man_duration_handler` could be invoked with garbage menu handles (e.g., -6989007) after a map change. Added `menu < 0` guard and broadened item validation from `== MENU_EXIT` to `< 0` to catch all negative sentinel values.

---

## [0.10.72] - 2026-02-17

### Fixed
- **Timelimit map changes bypassing match state handler** - The game DLL calls `pfnChangeLevel()` when timelimit expires, which queues a `changelevel` command via the command buffer. KTPMatchHandler only hooked `RH_Host_Changelevel_f` (the console command handler), which for unknown reasons never fired for these queued commands in some cases (e.g., match 1.3-5379 on ATL1). Added `RH_PF_changelevel_I` hook as the primary interception point — fires directly when the game DLL requests a level change, before the command buffer. The existing `Host_Changelevel_f` hook remains as a secondary handler for admin/RCON-initiated changelevel commands.

### Added
- **Prestart/pending map change guard** - When timelimit expires during match setup (prestart or pending state), the PF hook now redirects to the same map instead of dumping players to the mapcycle rotation. Players stay on the correct map and can re-initiate the match.

---

## [0.10.71] - 2026-02-17

### Fixed
- **12man/scrim/draft Discord embeds posting to competitive channel** - `cmd_say_hook` unconditionally set `g_matchType = MATCH_TYPE_COMPETITIVE` when anyone typed `.ktp`, even if a non-competitive match was already in progress. This silently corrupted the match type, causing `get_discord_channel_id` to route embeds to the competitive channel instead of the 12man/scrim/draft channel. The overwrite happened before `cmd_match_start` could check for an active match, and HLDS doesn't log say commands intercepted with `PLUGIN_HANDLED`, making this invisible in logs. Fixed by guarding the type assignment with match state checks.

### Added
- **Discord channel routing debug log** - `get_discord_channel_id` now logs `DISCORD_CHANNEL_ROUTE` for non-competitive match types, showing the resolved channel ID for easier diagnosis of misrouted embeds.

---

## [0.10.70] - 2026-02-16

### Fixed
- **Discord embed not updating for 12man matches** - The embed callback used `fgets()` to read the Discord API response from a temp file, but `fgets()` stops at the first newline character. Discord's JSON response contains literal `\n` in embed field values (player rosters), causing `fgets` to return empty. Message ID was never captured, so all subsequent updates (halftime, 2nd half, match end) edited the wrong message. Replaced with `fread_blocks()` to read the entire response file.

---

## [0.10.69] - 2026-02-05

### Added
- **KTP_HALF_END log event for HLStatsX** - Logs accurate H1 end timestamp
  - Fires at the moment gameplay ends (scoreboard appears), before map change/warmup
  - Allows HLStatsX to set H1's `end_time` correctly, preventing warmup kills from being attributed to H1
  - Format: `KTP_HALF_END (matchid "xxx") (map "xxx") (half "1st")`

---

## [0.10.68] - 2026-02-04

### Fixed
- **Team names not clearing on .forcereset** - Both `g_teamName[1]`/`g_teamName[2]` (display names) and `g_team1Name`/`g_team2Name` (persistent names) now reset to "Allies"/"Axis" when force resetting

### Added
- **`ktp_match_competitive` cvar** - Indicator for other plugins (KTPCvarChecker) to know match type
  - Set to 1 for competitive modes (`.ktp`, `.ktpOT`)
  - Set to 0 for casual modes (`.12man`, `.scrim`, `.draft`)
  - Reset to 0 on `.forcereset`
- **Debug logging for Discord curl write callback** - Traces response capture for 12man message ID investigation

---

## [0.10.67] - 2026-02-02

### Fixed
- **HLStatsX stats timing** - Reduced KTP_MATCH_START delay from 100ms to 10ms
  - Original 100ms delay caused 1-2 kills at match start to be missed
  - 10ms still provides buffer for engine stability while reducing lost kills window
- **Abandoned match stats loss** - Added `dodx_flush_all_stats()` before KTP_MATCH_END
  - Previously, abandoned matches (2nd half, OT) logged KTP_MATCH_END without flushing
  - Pending stats for abandoned matches are now properly captured
  - Affects: `finalize_abandoned_match()`, `finalize_completed_second_half()`

### Added
- **Enhanced changelevel debug logging** - Better diagnostics for map transition issues
  - Added `CHANGELEVEL_HOOK_FIRED` log for every hook call (confirms hook is firing)
  - Added `CHANGELEVEL_PASSTHROUGH` log when returning early due to !g_matchLive
  - Logs all relevant state (matchLive, half, handled, inOT) to diagnose failures
  - Logs all state (g_matchMap, g_currentMap, map) during first half end
  - Fallback: If g_matchMap is empty, uses g_currentMap to prevent redirect failure
  - Added pre-redirect logging to track SetHookChainArg behavior
  - Investigation on ATL3 VPS (01/31) showed hook not firing - this will help diagnose

---

## [0.10.66] - 2026-01-27

### Fixed
- **HLStatsX first half stats not recording** - KTP_MATCH_START log now uses delayed task
  - `log_message()` UDP send fails when called immediately after `dodx_flush_all_stats()`
  - Engine state/timing issue prevents reliable UDP transmission in that context
  - Added 0.1s delay via `set_task()` which allows engine to stabilize before sending
  - This ensures HLStatsX daemon receives KTP_MATCH_START for both halves

---

## [0.10.65] - 2026-01-24

### Added
- **Silent pause mode integration** - Uses KTP-ReHLDS `ktp_silent_pause` cvar
  - Sets `ktp_silent_pause 1` before pausing (skips `svc_setpause` to clients)
  - Sets `ktp_silent_pause 0` after unpausing (ready for next pause)
  - Prevents blocky "PAUSED" overlay while custom HUD countdown still works
  - Requires KTP-ReHLDS 3.22.0+

### Removed
- **Pause overlay restore** - No longer calls `showpause 1` on unpause
  - Silent pause mode eliminates need for overlay management
  - Cleaner pause experience with only custom HUD countdown

### Fixed
- **Debug code removed** - Re-enabled match live requirement for `.tech` pause
  - Tech budget check restored
  - Match `.go` confirmation requirement restored

---

## [0.10.64] - 2026-01-24

### Added
- **Pause chat relay** - Chat now works during pause via `client_print` bypass
  - Normal `say` broadcast is blocked by engine during pause
  - This relays chat using `client_print` which bypasses the block (same mechanism as HUD updates)
  - Team chat (`say_team`) relays only to teammates
  - Commands (starting with `.` or `/`) still processed normally
  - Registered after specific command handlers to avoid conflicts

### Changed
- **DEBUG: `.tech` match requirement removed** - Temporarily disabled for testing pause chat relay
  - `.tech` can now be called without a live match (for debugging only)
  - Re-enable the check before production deployment

---

## [0.10.63] - 2026-01-23

### Added
- **`.grenade` in `.commands`** - Practice mode commands now listed in help output

### Fixed
- **Hostname caching on startup** - Fixed hostname showing "Half-Life" on first load
  - Server configs run AFTER `plugin_cfg`, so hostname cvar wasn't set yet
  - Now uses delayed task (1 second) to refresh hostname after configs load

---

## [0.10.62] - 2026-01-22

### Added
- **Draft match duration** - `.draft` matches now use 15-minute halves instead of 20 minutes
  - Sets `mp_timelimit 15` after map config execution (same pattern as 12man duration)

---

## [0.10.61] - 2026-01-20

### Fixed
- **Ready team label display** - `.ready` message showed wrong team label in 2nd half
  - Previously displayed team identity name (e.g., "Axis") instead of current side name
  - Example: Player on Allies side in 2nd half saw "Axis 1/6" instead of "Allies 1/6"
  - Ready count labels now always show "Allies" / "Axis" (current side) instead of team identity names
  - Affected commands: `.ready`, `.unready`, `.status`, and all pending HUD displays
  - Reported by acetamino, January 20 2026

### Changed
- **Discord embed footers** - Now include map name in footer (Match: xxx | Map: xxx | Server: xxx)
- **HLStatsX logging** - Changed `log_amx` to `log_message` for KTP_MATCH_START/END events

---

## [0.10.60] - 2026-01-13

### Added
- **Expanded `.commands` output** - Added missing commands to help listing
  - Admin Commands: `.restarthalf`, `.hltvrestart`
  - New "Other KTP Plugin Commands" section: `.kick`, `.ban`, `.restart`, `.quit` (from KTPAdminAudit)

---

## [0.10.59] - 2026-01-13

### Changed
- **Version sync** - Aligned header comment with PLUGIN_VERSION define

---

## [0.10.58] - 2026-01-13

### Changed
- **Discord embed titles now include `:ktp:` emoji** - Consistent branding across all Discord notifications
  - Match Cancelled, Match Setup Cancelled, Server Force Reset embeds updated

---

## [0.10.57] - 2026-01-13

### Changed
- **`.tech` cancels active auto-DC countdown** - Manual `.tech` pause now supersedes auto-DC countdown
  - If a player disconnects and auto-DC countdown is active, calling `.tech` immediately cancels it
  - Logs cancellation event with previous countdown value and disconnected player info
  - Prevents confusing state where both manual tech pause and auto-DC countdown are running
- **Reduced auto-DC countdown reminder spam** - Messages now appear at key intervals only
  - Every 5 seconds when countdown > 10 (30, 25, 20, 15)
  - Every second for last 10 seconds (10, 9, 8, 7, 6, 5, 4, 3, 2, 1)
  - Reduces total messages from 30 to 14

---

## [0.10.56] - 2026-01-13

### Added
- **`.restarthalf` admin command** - Restart live 2nd half to 0-0 while preserving 1st half scores
  - Requires ADMIN_RCON permission
  - Two-step confirmation (type twice within 10 seconds)
  - Only works during live 2nd half (not OT)
  - Aliases: `.h2restart`, `/restarthalf`, `/h2restart`
  - Flushes and resets DODX stats for clean 2nd half
  - Sends Discord notification with score information

### Changed
- **`.cancel` blocked for `.ktp` matches during 2nd half pending** - Competitive matches can no longer be cancelled after 1st half
  - Players see helpful message directing them to `.forcereset`
  - Other match types (`.scrim`, `.draft`, `.12man`) can still use `.cancel`
  - Protects competitive match integrity after significant time investment

---

## [0.10.55] - 2026-01-13

### Added
- **`.cancel` now works during second half pending** - Players can cancel a match after first half ends but before second half starts
  - Immediate cancel (no confirmation required) - use `.forcereset` if confirmation is desired
  - Clears all match state including scores, team names, rosters, and localinfo persistence
  - Sends Discord embed notification with first half score
- **Uniform Discord embed format** - All status notifications now use rich embeds matching `ktp_discord.inc` format
  - Match cancelled (second half): Red embed with first half score
  - Match setup cancelled (pending): Orange embed
  - Server force reset: Orange embed
  - Includes server hostname and map in footer for consistency with AdminAudit/CvarChecker

### Changed
- **`.cancel` blocked during live match** - Players attempting to cancel during live match now receive helpful message pointing to `.forcereset` for admins
- **Match start commands improved** - `.ktp`/`.scrim`/`.12man`/`.draft` during live match now correctly points to `.forcereset` instead of `.cancel`

---

## [0.10.54] - 2026-01-12

### Added (Experimental)
- **Pause overlay disable** - Server now sends `showpause 0` to clients when pause activates
  - Attempts to hide the pause screen overlay that blocks players' view during pause
  - Sends `showpause 1` on unpause to restore default behavior
  - Note: This is experimental - clients may reject the command if it's protected

---

## [0.10.53] - 2026-01-12

### Changed
- **Auto-DC countdown increased to 30 seconds** - Players now have 30 seconds to reconnect before auto tech pause (was 10 seconds)
- **Auto-DC only for competitive match types** - Auto-DC pauses now only trigger for `.ktp`, `.ktpOT`, `.draft`, and `.draftOT` matches
  - Scrims (`.scrim`) and 12mans (`.12man`) no longer trigger auto-DC pauses on disconnect
  - Manual tech pauses (`.tech`) still available for all match types
- **`.draftOT` no longer requires password** - Only `.ktp` and `.ktpOT` require the KTP match password

### Added
- `is_auto_dc_enabled()` helper function for match-type-based auto-DC filtering

---

## [0.10.52] - 2026-01-12

### Fixed
- **Changelevel guard flag stuck bug** - First half end processing no longer skipped due to stale guard flag
  - Root cause: `g_changeLevelHandled` flag was not reset between matches
  - When KTPAdminAudit's `.changemap` blocked a changelevel with HC_SUPERCEDE during a match, KTPMatchHandler's hook still fired and set the flag, but the map never changed (plugin never reinit), leaving the flag stuck
  - On the next match's first half end, the changelevel hook saw the stale flag and skipped processing
  - Fix: Reset `g_changeLevelHandled = false` when match goes live
  - Reference: Atlanta 4 scrim bug 01/11/2026 - KTP-1768187394-dod_harrington

---

## [0.10.51] - 2026-01-12

### Fixed
- **Roster cross-team duplicate bug** - Players no longer appear in both team rosters on Discord
  - Issue: After halftime map change, players who hadn't switched game teams were added to the wrong roster
  - `add_to_match_roster()` now checks BOTH rosters before adding a player
  - Prevents the same SteamID from appearing under both Team 1 and Team 2 in Discord embeds

---

## [0.10.50] - 2026-01-11

### Fixed
- **2nd half ready counter bug** - `.rdy` command now correctly counts players by team identity
  - Previously, players who hadn't switched game teams after map change were counted under wrong team name
  - Now uses roster-based SteamID lookup to determine team identity during 2nd half pending
  - Added `get_player_roster_team()` helper for roster-based team lookup
  - Half captain tracking also uses roster-based identity in 2nd half
  - Roster addition for new players correctly handles side swap during 2nd half pending

---

## [0.10.49] - 2026-01-11

### Changed
- **Standard AMXX logging** - `log_ktp()` now uses `log_amx()` with [KTP] prefix
  - Logs now auto-rotate daily via standard AMXX log rotation
  - No more single large `ktp_match.log` file

### Removed
- **ktp_match_logfile cvar** - No longer needed with standard AMXX logging

---

## [0.10.48] - 2026-01-11

### Removed
- **Dead code cleanup** - Removed ~190 lines of unreachable/unused code
  - Old OT round handler (`handle_ot_round_end_OLD`) wrapped in `#if 0`
  - Unreachable tactical pause logic (disabled but code remained after early return)
  - Unused legacy variables (`g_gameEndEventCount`, `g_gameEndTaskId`)
  - Orphaned task removal code referencing deleted variables

### Fixed
- **Compiler warnings** - All warnings resolved
  - Added `#pragma unused` for intentionally unused parameters
  - Removed unreachable code blocks

### Added
- **Admin Commands in .commands** - `.forcereset` now appears in `.commands` output under "Admin Commands (RCON flag)" section

---

## [0.10.47] - 2026-01-10

### Added
- **Force reset admin command** - `.forcereset` command for recovering abandoned servers
  - Requires ADMIN_RCON flag (highest admin level)
  - Confirmation step required: type command twice within 10 seconds
  - Clears ALL match state: live, pending, prestart, pause, scores, rosters, localinfo
  - Sends Discord notification when executed
  - Logs all reset attempts and executions for audit trail

---

## [0.10.46] - 2026-01-10

### Added
- **Match type-specific ready requirements** - Different match types now require different player counts
  - KTP and KTP OT: 6 players per team
  - Scrim, 12man, Draft, Draft OT: 5 players per team
- **Debug ready override** - `.override_ready_limits` command for testing (restricted to SteamID 0:1:25292511)
  - Toggles requirement to 1 player per team for debug purposes
  - Logs enable/disable events for audit trail

---

## [0.10.45] - 2026-01-10

### Added
- **Dynamic server hostname** - Server hostname now reflects match state in real-time
  - Format: `{BaseHostname} - {MatchType} - {State}`
  - Match types: KTP, SCRIM, 12MAN, DRAFT, KTP OT, DRAFT OT
  - States: PENDING, PAUSED, LIVE - 1ST HALF, LIVE - 2ND HALF, LIVE - OT1, etc.
  - Base hostname cached at plugin init from `servernamedefault.cfg` pattern
  - Hostname resets to base when match ends or is cancelled
  - Match ID generation uses only base hostname (excludes dynamic suffixes)

### Changed
- **ktpbasic.cfg** - No longer execs `servername.cfg`; hostname managed dynamically by plugin

---

## [0.10.44] - 2026-01-10

### Fixed
- **Intermission auto-DC pauses** - Players leaving during intermission (scoreboard after timelimit) no longer trigger auto tech pauses
  - Added `g_inIntermission` flag set when changelevel hook detects second half end
  - Added `is_in_intermission()` helper that checks if timelimit has expired in 2nd half
  - Prevents spurious pause triggers when many players disconnect at match end

---

## [0.10.43] - 2026-01-10

### Added
- **Explicit overtime commands** - New `.ktpOT` and `.draftOT` commands for manually starting overtime rounds
  - Overtime is no longer triggered automatically at end of tied 2nd halves
  - Requires same password as `.ktp` (captains control OT initiation)
  - New match types: `MATCH_TYPE_KTP_OT` and `MATCH_TYPE_DRAFT_OT`
  - OT rounds use 5-minute timelimit with competitive.cfg
  - Independent OT rounds - no regulation score carryover
  - HLTV demos named `ktpOT_<matchid>.dem` or `draftOT_<matchid>.dem`

### Changed
- **Match flow simplified** - Regular matches are now h1 → h2 → done (no automatic OT detection)
- **Tie announcement** - When match ends in tie, announces "Match tied X-X! Use .ktpOT or .draftOT for overtime."

### Fixed
- **Changelevel recursion bug** - Removing automatic OT triggering eliminates the root cause of the recursion issues

---

## [0.10.42] - 2026-01-10

### Added
- **Persistent player roster tracking** - Discord match reports now show all players who participated, even if they disconnected before match end
  - Roster captured at match start and when players .ready mid-match
  - Player data stored as "Name|SteamID" format in arrays
  - Roster persists through map changes via localinfo
  - Resolves "No players" issue in final match reports

### Fixed
- **Auto-DC technicals disabled after match ends** - Players leaving after match conclusion no longer trigger automatic DC technical timeouts
  - New `g_matchEnded` flag set true in `end_match_cleanup()`
  - Flag cleared when new match goes live
  - Prevents spurious technical penalties during post-match departures

---

## [0.10.41] - 2026-01-09

### Fixed
- **Map config prefix matching bug** - Shorter map keys incorrectly matched before longer specific keys
  - Example: `dod_railroad` config matched for `dod_railroad2_s9a` because it appeared first in INI
  - Now sorts map keys by length descending after loading, so `dod_railroad2_s9a` matches before `dod_railroad`

---

## [0.10.40] - 2026-01-09

### Fixed
- **First half changelevel recursion bug** - Same issue as OT: guard flag was reset before hook returned, causing multiple firings
- **All match types now stay on same map for 2nd half** - 12man, draft, scrim, and competitive all properly redirect changelevel to same map

### Added
- **Queue ID cancel option** - Type "cancel" or "abort" during Queue ID entry to cancel and restart with .12man
- Cancel hint added to Queue ID prompts

---

## [0.10.39] - 2026-01-09

### Fixed
- **OT recursion bug** - Guard flag `g_changeLevelHandled` was being reset to `false` before returning `HC_CONTINUE` in the OT-still-tied path, allowing the hook to fire recursively
- When `SetHookChainArg` modified the target map and hook returned, it fired again with the guard already reset and `g_otRound` already incremented

### Changed
- **`ktp_match_start` forward now fires on all halves/OT** - Previously only fired on 1st half
- Forward signature updated to include 4th parameter `half` (1=1st half, 2=2nd half, 101+=OT rounds)

### Technical
- Plugins hooking `ktp_match_start` must handle new signature: `ktp_match_start(matchId[], map[], MatchType:type, half)`
- KTPHLTVRecorder updated to v1.0.5 for new forward signature with idempotent recording

---

## [0.10.38] - 2026-01-07

### Added
- **1.3 Community Discord 12man support** - New option when starting 12man matches
  - Initial menu asks: "Standard 12man" vs "1.3 Community Discord 12man"
  - If 1.3 Community selected, captain enters Queue ID in chat
  - Queue ID must be entered twice for confirmation (prevents typos)
  - HUD displays "12man QUEUE ID: {id}" during input and after confirmation
  - Match ID format changes from `KTP-{timestamp}` to `1.3-{queueId}`
  - Example: `1.3-ABC123-dod_anzio-KTP_Atlanta_1`
  - Length validation ensures match ID stays under 64 chars
  - Input sanitized to alphanumeric, dash, underscore only

### Technical
- New globals: `g_is13CommunityMatch`, `g_13QueueId`, `g_13QueueIdFirst`, `g_13InputState`, `g_13CaptainId`
- Chat input intercepted via `cmd_say_hook` when `g_13InputState > 0`
- `generate_match_id()` checks `g_is13CommunityMatch` flag for format selection
- `clear_match_id()` now also resets 1.3 Community state

---

## [0.10.37] - 2026-01-07

### Changed
- **Match ID now includes server hostname** - Format changed from `KTP-{timestamp}-{map}` to `KTP-{timestamp}-{map}-{hostname}`
  - Allows differentiation between matches on different servers (e.g., Atlanta 1 vs New York 1)
  - Example: `KTP-1736280000-dod_anzio-KTP_Atlanta_1`

### Added
- `sanitize_hostname_for_match_id()` function that:
  - Strips dynamic suffixes: "- LIVE", "- PAUSED", "- Match in Progress", "- PRE-MATCH", "- WARMUP", "- OT", "- OVERTIME", "[LIVE]", "[PAUSED]", "[MATCH]"
  - Replaces spaces and special characters with underscores
  - Collapses consecutive underscores into one
  - Trims leading/trailing underscores

---

## [0.10.36] - 2026-01-06

### Added
- **Discord support for 12man matches** - Sends to `discord_channel_id_12man` if configured
- **Discord support for draft matches** - Sends to `discord_channel_id_draft` if configured
- New config key `discord_channel_id_draft` in discord.ini

### Changed
- 12man/draft/scrim matches no longer fall back to default Discord channel
  - They require explicit channel config; if not configured, Discord is silently skipped
- Removed `g_disableDiscord = true` for 12man and draft match types

---

## [0.10.35] - 2026-01-06

### Changed
- **Tactical pauses disabled** - Only tech pauses (`.tech`) allowed; `.pause`/`.tac` now rejected
  - Players see: "[KTP] Tactical pauses are disabled. Use .tech for technical issues."
- **Pause extensions disabled** - `ktp_pause_max_extensions` default changed from 2 to 0
  - Can be re-enabled via server cvar if needed
- **Tech budget is per-match** - 5 minutes total for regulation (1st half + 2nd half), reset at overtime
  - This was already the behavior; documenting for clarity

### Notes
- Tech pause budget stops counting when pause owner types `.resume` (not when game actually unpauses)
- This freeze-on-resume behavior was already implemented in v0.10.x

---

## [0.10.34] - 2026-01-06

### Fixed
- **OT recursive loop crash (for real this time)** - Replaced `server_cmd` + guard flag with `SetHookChainArg`
  - Root cause: `server_cmd("changelevel")` is **asynchronous** - queues command for later execution
  - Guard flag fired for the **wrong map** (original target, not our redirect)
  - After guard cleared, the queued changelevel triggered another hook call → infinite loop
  - Solution: Use `SetHookChainArg(1, ATYPE_STRING, g_matchMap)` to modify the map **in-place**
  - Then return `HC_CONTINUE` to let the changelevel proceed with modified target
  - No recursive changelevel calls, no guard flags needed, clean single map change

### Changed
- Removed `g_otForcedChangelevel` guard flag variable (no longer needed)
- `OT_FORCE_SAME_MAP` log event renamed to `OT_REDIRECT_CHANGELEVEL`

---

## [0.10.33] - 2026-01-06

### Added
- **Half captain tracking** - First `.ready` player per team becomes "half captain" for that half
  - Tracks who actually readied up first (may differ from original captains)
  - Logged in `MATCH_START` event as `half_captain1`/`half_captain2`
  - Original captains preserved for Discord embed and chat announcements

- **Original captain persistence** - Captains who started the match are preserved across map changes
  - New `LOCALINFO_CAPTAINS` key stores `name1|sid1|name2|sid2`
  - Restored on 2nd half and OT round continuation
  - Ensures Discord always shows who initiated the match

### Changed
- `MATCH_START` log event now shows `half_captain1`/`half_captain2` instead of original captains
- Chat announcement "All players ready. Captains: ..." still uses original captains

---

## [0.10.32] - 2026-01-05

### Fixed
- **OT recursive loop crash** - OT rounds no longer process in infinite loop when tied
  - Root cause: `server_cmd("changelevel")` triggers `OnChangeLevel` hook **synchronously** before `HC_SUPERCEDE` returns
  - Previous fix (v0.10.31) set `g_changeLevelHandled = false` before returning, allowing recursive calls
  - Solution: New `g_otForcedChangelevel` guard flag checked FIRST in `OnChangeLevel()`
  - Guard flag set before `server_cmd`, cleared when forced changelevel passes through
  - Prevents runaway score accumulation and array index out of bounds crash at round 32

- **OT Discord embed creates new message** - OT rounds now update existing embed instead of creating new
  - Root cause: OT sets `g_currentHalf = 1` which triggered `send_match_embed_create()`
  - Solution: Check `g_inOvertime` first and use `send_match_embed_update()` for OT rounds

- **Abandoned match pending state** - Match state now properly cleared after abandoned match detection
  - Root cause: `finalize_abandoned_match()` didn't reset state flags (g_matchPending, etc.)
  - Solution: Reset all match state flags to ensure `ktp_is_match_active()` returns false
  - Allows `.changemap` to work after match is abandoned

### Changed
- `process_ot_round_end_changelevel()` returns `bool` - true if OT continues (still tied)
- `OnChangeLevel()` now checks `g_otForcedChangelevel` flag before any other processing
- Guard flag pattern prevents hook re-entry during forced changelevel execution

---

## [0.10.30] - 2026-01-01

### Added
- **`.commands` / `.cmds` command** - Prints categorized command list to console
  - Match Setup, Ready System, Pause System, Overtime, Team Names, Status & Info sections
  - Chat message directs player to check console
- **HLTV reminders** - Added connection reminders before match start
  - Pre-start phase: Reminder when `.ktp` command is used
  - Pending phase: Reminder when entering pending phase
  - 2nd half/OT: Reminder to verify HLTV still connected before resuming
- **2nd half pending HUD** - Repeating HUD shows "=== 2ND HALF - Type .ready ===" with scores
  - HUD task now properly started during 2nd half restoration
  - Shows team names and 1st half scores while waiting for readies

### Fixed
- **Intermission freeze** - Server no longer freezes at end of 2nd half/OT
  - Root cause: `HC_SUPERCEDE` during intermission blocked changelevel, leaving game stuck
  - Solution: Use `HC_CONTINUE` and let changelevel proceed after processing
- **OT trigger stays on same map** - Match now correctly stays on current map for overtime
  - Root cause: Changelevel proceeded to next map in rotation instead of same map
  - Solution: When OT triggered, save OT state to localinfo, force changelevel to same map with `HC_SUPERCEDE`
  - New function: `save_ot_state_for_first_round()` - Persists OT state for map reload

### Removed
- **Debug commands** - Removed `.sbtest` and `.teamtest` admin commands (no longer needed)

### Technical
- `process_second_half_end_changelevel()` now returns `bool` - true if OT triggered
- `OnChangeLevel()` handles OT case specially - forces changelevel to same map
- Pending HUD task started during 2nd half and OT restoration in `check_match_context()`

---

## [0.10.28] - 2026-01-01

### Added
- **Delayed changelevel with announcements** - Complete match finalization before map change
  - 2nd half and OT round ends now SUPERSEDE the engine changelevel (`HC_SUPERCEDE`)
  - Winner/OT announcement in chat with detailed score breakdown
  - Brief HUD (3 seconds) so players can see scoreboard
  - Discord embed update with match result BEFORE map change
  - 5-second countdown before manual map change with HUD display
  - Manual changelevel after countdown using `server_cmd("changelevel %s")`

### Fixed
- **Match end never processed** - Logevents fire at exact moment of map change
  - Root cause: Logevent-based detection was unreliable (events never processed)
  - Solution: Changelevel hook intercepts BEFORE map change, not during
  - 2nd half being skipped is now FIXED - state is finalized before map change

### Changed
- Removed logevent-based game end detection (was source of the bug)
- `handle_map_change()` replaced by specialized functions:
  - `handle_first_half_end()` - 1st half, allows immediate changelevel
  - `process_second_half_end_changelevel()` - 2nd half, supersedes with countdown
  - `process_ot_round_end_changelevel()` - OT rounds, supersedes with countdown
- `handle_ot_round_end()` replaced by `process_ot_round_end_changelevel()`

### Technical
- `OnChangeLevel()` now branches based on match state (1st half vs 2nd/OT)
- Uses `g_pendingChangeMap` to store target map during countdown
- Countdown task `task_changelevel_countdown()` shows HUD and executes changelevel
- OT tie (another round needed) saves state and immediately changelevel (no countdown)

---

## [0.10.27] - 2026-01-01

### Added
- **Changelevel hook integration** - Reliable match state finalization
  - Uses new `RH_PF_changelevel_I` hook from KTP-ReHLDS/KTP-ReAPI
  - Intercepts ALL map changes BEFORE they happen (not after like logevents)
  - Guarantees `handle_map_change()` runs before map actually changes
  - Extensive logging: `CHANGELEVEL_HOOK`, `CHANGELEVEL_INTERCEPT`, `CHANGELEVEL_FINALIZED`
  - ~~Fallback: Logevent detection still active as backup~~ (Removed in 0.10.28)

### Technical
- Hook registered in `plugin_init()` via `RegisterHookChain(RH_PF_changelevel_I, ...)`
- `OnChangeLevel(map[], landmark[])` handler properly finalizes match state
- Prevents double-processing with `g_changeLevelHandled` flag
- Cancels pending logevent tasks when changelevel hook fires first

---

## [0.10.26] - 2025-12-31

### Fixed
- **False overtime trigger after 1st half** - Critical bug fix
  - Root cause: Logevents for "scored" fire at exact moment of map change, never processed by plugin
  - Previous fixes (0.10.24, 0.10.25) relied on `handle_map_change()` running, but it never does
  - New detection: Check for `_ktp_h2` scores to distinguish 1st half end from 2nd half end
  - If `mode='h2'` + `live='1'` but NO h2 scores → 1st half just ended, restore for 2nd half
  - If `mode='h2'` + `live='1'` AND has h2 scores → 2nd half ended, finalize match

---

## [0.10.25] - 2025-12-31

### Fixed
- **Race condition in game end detection** - Critical bug fix
  - Previous fix (0.10.24) didn't work because `handle_map_change()` never ran
  - Root cause: Map changes in same second as scored events, 0.5s delayed task never executes
  - Fix: Call `handle_map_change()` synchronously on 2nd scored event instead of via delayed task
  - Backup task still scheduled on 1st event in case 2nd event is missed

---

## [0.10.24] - 2025-12-31

### Fixed
- **False overtime trigger on 2nd half load** - Critical bug fix
  - `_ktp_live` flag now cleared when 1st half ends (in `handle_map_change()`)
  - Prevents false "2nd half ended" detection when 2nd half map loads
  - Flow: 1st live sets flag → 1st end clears flag → 2nd live sets flag

---

## [0.10.23] - 2025-12-31

### Added
- **Robust match end detection** - Handles matches when `plugin_end()` doesn't run (extension mode)
  - `LOCALINFO_H2_SCORES` (`_ktp_h2`) - Persists 2nd half running scores during periodic save
  - `amx_nextmap` set to current map during 2nd half start - ensures map cycles back
  - `finalize_completed_second_half()` - Full match finalization with OT support
  - Overtime triggers correctly from finalize if scores are tied
- **Custom team name native** - `dodx_set_scoreboard_team_name(team, name[])` in DODX module
  - Sends TeamInfo message to all clients for each player on specified team
  - `.teamtest` admin command to test custom team names

### Technical
- Map cycling back to same map + `_ktp_live="1"` = 2nd half ended (not pending)
- 2nd half scores now persisted to localinfo every 30 seconds for crash/end detection

---

## [0.10.22] - 2025-12-31

### Fixed
- **Score calculation for 2nd half** - Accounts for restored 1st half scores in DODX
  - `.score` command now correctly subtracts restored 1st half from DODX totals
  - `handle_map_change()` 2nd half score calculation fixed (same formula)
  - Formula: `team1SecondHalf = g_matchScore[2] - g_firstHalfScore[1]`

### Added
- `LOCALINFO_LIVE` (`_ktp_live`) - Tracks when match is live for abandoned match detection
- `finalize_abandoned_match()` - Handles matches that end on different map
- Discord notification and `ktp_match_end` forward for abandoned matches

### Technical
- Mode is no longer cleared after restoration (kept until match actually ends)
- Enables detection of abandoned matches when plugin loads on new map

---

## [0.10.21] - 2025-12-31

### Fixed
- **2nd half restoration** - Players can now `.ready` after map change
  - `g_matchPending = true` set during 2nd half restoration
  - `g_matchLive = false` set explicitly to prevent "match in progress" error
  - Captain display fixed to show correct team names after side swap

### Added
- "Type .ready to start 2nd half" announcement after restoration
- OT restoration also sets `g_matchPending = true` for consistency

---

## [0.10.20] - 2025-12-31

### Fixed
- **TeamScore broadcast now works** - Proper scoreboard updates for 2nd half
  - Added `dodx_broadcast_team_score()` native to DODX module (C++ level)
  - Native properly sends TeamScore messages from module level (avoids AMX crash)
  - Native sets gamerules score AND broadcasts to clients in one operation
  - Updated `broadcast_team_score()` to use new native
  - Added `g_skipTeamScoreAdjust` flag to prevent double-adjustment
  - Scoreboard now shows correct cumulative scores immediately after 2nd half start

### Technical
- DODX module now exports `dodx_broadcast_team_score(team, score)` native
- Message format: BYTE(team) + SHORT(score) sent via MESSAGE_BEGIN/MESSAGE_END
- Avoids server crashes that occurred with AMX message_begin/write_byte/message_end

---

## [0.10.19] - 2025-12-31

### Fixed
- **Disabled TeamScore broadcast** - Prevents server crashes
  - Both `write_byte(teamnum)` and `write_string("teamname")` formats caused crashes
  - DODX `dodx_set_team_score()` still sets internal gamerules score
  - Scoreboard updates naturally on next flag touch or round event
  - Chat confirmation message still works

---

## [0.10.18] - 2025-12-31

### Added
- **Match start protection** - Prevents starting a new match when one is in progress
  - Blocks `.ktp`, `.scrim`, `.12man`, `.draft` during live matches
  - Blocks during pre-start phase (waiting for confirms)
  - Blocks during pending phase (waiting for readies)
  - 2nd half and OT still work (g_matchLive=false between halves)

---

## [0.10.17] - 2025-12-31

### Fixed
- **Critical**: Server crash on TeamScore broadcast - wrong message format
  - DoD TeamScore expects `write_string("Allies")` not `write_byte(1)`
  - Was using byte team number instead of team name string
- **Overlapping HUD messages at 2nd half start**
  - Removed redundant "RESTORING 1ST HALF SCORES" HUD (match start HUD already shows scores)
  - Shortened "2nd HALF DETECTED" prestart HUD from 8s to 4s
  - Changed delayed score confirmation from HUD to chat message

---

## [0.10.16] - 2025-12-31

### Fixed
- **Critical**: Score restoration timing - increased delay from 5s to 12s
  - Root cause: `mp_clan_timer=10` means round actually restarts 10s after trigger
  - With 5s delay, scores were restored DURING countdown, then reset on round restart
  - Now waits 12s to ensure round restart has completed

### Added
- **Comprehensive safety checks in score restoration**
  - `DELAYED_SCORE_RESTORE_START` - logs all state before starting
  - `DELAYED_SCORE_RESTORE_ABORT` - if match not live or invalid scores
  - `DODX_SCORE_SET` - logs before/after values for DODX set_team_score
  - `DODX_SCORE_SET_VERIFY_FAIL` - if verification fails
  - `BROADCAST_SCORE_PRECHECK` - logs connected count and msgid
  - `BROADCAST_SCORE_ATTEMPT` - logs all values before broadcast
  - `BROADCAST_SCORE_SENT` - after each TeamScore message
  - `BROADCAST_SCORE_COMPLETE` - when done
- Re-enabled TeamScore broadcast (was disabled in v0.9.15 due to crashes)
  - With 12s delay, clients are connected and round restart is done
  - Validates msgId and connected player count before broadcast

---

## [0.10.15] - 2025-12-31

### Fixed
- **Critical**: Periodic score tracking now runs in 2nd half (was only 1st half)
  - `PERIODIC_SCORE_SAVE_STARTED` now logs for both halves
  - Keeps `g_matchScore` updated for `.score` command and match end detection

### Added
- **Game end logevent hook** as backup for `plugin_end()` which may not fire in KTPAMXX extension mode
  - Hooks team "scored" logevents at map end ("Allies" scored "X" with "Y" players)
  - Triggers `handle_map_change()` to finalize match, update Discord, flush stats
  - Logs: `GAME_END_LOGEVENT`, `GAME_END_DETECTED`

---

## [0.10.14] - 2025-12-31

### Changed
- `.score` command now broadcasts to all players instead of just the requester
- Captain display now uses actual team names instead of generic "t1/t2"
  - Before: `All players ready. Captains: nein_ (t1) vs scurryfunge (t2)`
  - After: `All players ready. Captains: nein_ (Team1Name) vs scurryfunge (Team2Name)`

---

## [0.10.12] - 2025-12-31

### Fixed
- **Critical**: `.score` command math in 2nd half was completely wrong
  - DODX resets on `mp_clan_restartround`, so `g_matchScore` is 2nd-half-only, not cumulative
  - Was subtracting 1st half from 2nd-half-only scores (always showed 0 until exceeding 1st half)
  - Now correctly: `total = firstHalfScore + secondHalfScore`
- **Critical**: Match end score calculation had the same bug
  - Final scores were calculated incorrectly
  - Discord embed never updated with correct final score

### Added
- Debug logging in `plugin_end()` to trace why match completion wasn't triggering
  - `PLUGIN_END_START` and `PLUGIN_END_COMPLETE` events

---

## [0.10.11] - 2025-12-30

### Added
- **2nd half HUD alert on prestart** - Shows HUD again when match command is used
  - Players who missed map load announcement now see it on `.ktp`/`.12man`/etc.
  - Same "2nd HALF DETECTED" message with team swap info

---

## [0.10.10] - 2025-12-30

### Added
- **2nd half detection HUD alert** - Prominent center-screen notification on map load
  - Shows "2nd HALF DETECTED" with team swap info
  - Displays which team is now Allies/Axis
  - Notes that pause budgets carried over
  - Yellow text, 8 second display duration

---

## [0.10.9] - 2025-12-30

### Added
- **Enhanced TeamScore debug logging** - Diagnose scoreboard sync issues
  - Logs game score vs DODX internal score on every TeamScore message
  - Logs before/after DODX scores in delayed score restore
  - Includes timestamps for timing analysis

---

## [0.10.8] - 2025-12-30

### Added
- **Match type in HUD messages** - Pre-Start and Pending HUD now shows match type
  - Pre-Start: "KTP Pre-Start (12man): Waiting for .confirm..."
  - Pending: "KTP 12man Pending..." / "KTP Scrim Pending..." / etc.
- Added `get_match_type_label()` helper function for consistent type display

---

## [0.10.7] - 2025-12-30

### Reverted
- **REVERTED**: `broadcast_team_score()` calls - caused server crashes
  - TeamScore MSG_ALL crashes server even with 5s delay
  - Scoreboard will update via game's native flag touch events instead
  - Added HUD note: "Scoreboard syncs on flag touch"

---

## [0.10.6] - 2025-12-30

### Fixed
- **Critical**: Config path doubled (`configs/configs/ktp_anzio.cfg`) causing map configs to fail
  - `ktp_maps.ini` entries already include `configs/` prefix
  - `exec_map_config()` was prepending it again
  - Match would start without proper timelimit/restart

---

## [0.10.5] - 2025-12-30

### Fixed
- **Critical**: Task ID collision between pause reminder and disconnect countdown tasks
  - Both used ID 55608, causing tasks to overwrite each other
  - Disconnect countdown now uses 55609
- **Bug**: Regulation HUD argument order was swapped (`score2, g_team2Name` instead of `g_team2Name, score2`)
  - Caused wrong scores displayed next to team names during 2nd half
- Updated version header comment to match PLUGIN_VERSION

### Changed
- Removed 4 unused variables (dead code cleanup):
  - `g_lastUnpauseById`, `g_confirmAlliesById`, `g_confirmAxisById` (never read)
  - `g_ktpDiscordConfigLoaded` (redundant with `g_ktpDiscordEnabled`)
- Fixed tag mismatch warning in mode detection
- Compiles with zero warnings

---

## [0.10.4] - 2025-12-30

### Changed
- 12man duration selection now announces to all players (not just the captain)
  - Example: `[KTP] PlayerName started a 12man match (20 minutes)`

### Fixed
- Fixed 21 instances of duplicate `[KTP][KTP]` prefix in announcements
  - All `announce_all()` calls with embedded `[KTP]` prefix now use bare messages
  - Affected: pause/unpause messages, OT break messages, team name reset, pre-confirm

---

## [0.10.3] - 2025-12-29

### Fixed
- **Critical**: Match start now always triggers `mp_clan_restartround 1` even if no map config is found
  - Previously, if map config lookup failed, players wouldn't respawn and timelimit wasn't set
  - Affected 12man/scrim matches on maps without dedicated config files

---

## [0.10.2] - 2025-12-29

### Changed
- Pre-Start announcement now includes match type (Match/Scrim/12man/Draft)
  - Example: `[KTP] Pre-Start (Scrim) by Player on dod_anzio`

### Fixed
- Removed duplicate `[KTP]` prefix from Pre-Start announcements
- Team name prompt (`.setallies`/`.setaxis`) now only shown for `.ktp` and `.draft` matches
  - Scrims and 12mans no longer prompt for custom team names

---

## [0.10.1] - 2025-12-23

### Added
- **Overtime System** - Complete OT implementation for competitive matches
  - Triggers automatically when regulation ends tied
  - 60-second voting period for optional 10-minute break (`.otbreak` / `.skip`)
  - 5-minute extensions during break (`.ext`, 2x per team max)
  - 5-minute OT rounds (mp_timelimit 5)
  - Teams swap sides each OT round (OT1: Team1=Allies, OT2: Team1=Axis, etc.)
  - Tech budget resets once at OT start (full budget for both teams)
  - Infinite OT rounds until winner determined
  - Grand total scores carried over to scoreboard each OT round
  - Full state persistence across map changes via localinfo

- **OT Localinfo Keys** - New keys for OT state persistence
  - `_ktp_reg` - Regulation totals
  - `_ktp_ots` - OT scores per round (pipe-separated)
  - `_ktp_otst` - OT state (tech budgets + starting side)

- **OT Commands**
  - `.otbreak` - Vote for 10-minute break before OT
  - `.skip` - Skip break voting or end break early
  - `.ext` - Extend break by 5 minutes (2x per team)

- **HUD Announcements**
  - OT triggered with voting options (60 sec display)
  - OT break countdown (updates every 30 sec)
  - OT round start with grand totals
  - OT winner announcement with score breakdown
  - Regulation winner HUD announcement

### Fixed
- OT HUD argument order (team names and scores)
- Score restoration unified for 2nd half and OT using pending score variables

### Technical
- New globals: `g_inOvertime`, `g_otRound`, `g_regulationScore[]`, `g_otScores[][]`
- New globals: `g_otTechBudget[]`, `g_otTeam1StartsAs`, `g_otBreakExtensions[]`
- New globals: `g_pendingScoreAllies`, `g_pendingScoreAxis`
- Functions: `trigger_overtime()`, `handle_ot_round_end()`, `save_ot_context()`
- Functions: `start_ot_break()`, `task_ot_break_tick()`, `end_ot_break()`
- Functions: `cmd_otbreak()`, `cmd_ot_skip()`, `cmd_ot_extend()`
- Helper functions for OT score string formatting/parsing

---

## [0.9.16] - 2025-12-21

### Changed
- Version bump for consistency across source and documentation

---

## [0.9.15] - 2025-12-21

### Fixed
- **Server Crash on 2nd Half Start** - Fixed crash during map exec
  - Cause: `broadcast_team_score()` sending network messages during map load when players not connected
  - Solution: Only broadcast in delayed tasks (5s+), use `dodx_set_team_score()` for immediate set

---

## [0.9.14] - 2025-12-21

### Fixed
- **/score Command Double-Counting** - Command no longer double-counts 1st half scores in 2nd half
  - Root cause: Treated cumulative scoreboard as 2nd-half-only, then added 1st half again
  - Solution: Use same calculation as `build_scores_field()` - subtract 1st half from cumulative

---

## [0.9.13] - 2025-12-21

### Fixed
- **Scoreboard Client Update** - Scoreboard now updates for all clients on 2nd half score restoration
  - Root cause: `dodx_set_team_score()` only set internal server value, not broadcast to clients
  - Clients only saw update when next flag was capped (triggering game's TeamScore message)
  - Solution: Send TeamScore message to all clients after setting internal score

### Added
- `broadcast_team_score()` - Sends TeamScore message (MSG_ALL) to force client scoreboard update
- `set_and_broadcast_score()` - Combined function for score restoration (set + broadcast)

### Technical
- Uses DoD TeamScore format: BYTE team (1=Allies, 2=Axis), SHORT score
- Called after each `dodx_set_team_score()` in delayed restoration tasks

---

## [0.9.12] - 2025-12-21

### Fixed
- **Discord Embed 2nd Half Score** - Embed now shows correct 0-0 score at 2nd half start
  - Root cause: Subtraction logic caused wrong values (e.g., 10-6 became 4 instead of 0)
  - Solution: Sync `g_matchScore` immediately after score restoration

### Changed
- Multiple restoration attempts at 5s, 8s, 12s, 15s after 2nd half start

---

## [0.9.11] - 2025-12-21

### Fixed
- **Discord Newlines** - Embed uses `^n` for newlines (properly escaped to `\n` in JSON)

---

## [0.9.10] - 2025-12-21

### Changed
- **Score Save Timing** - Initial periodic score save at 2 seconds (was 30 seconds)
  - Ensures 0-0 is persisted early in case of early map change

---

## [0.9.9] - 2025-12-21

### Removed
- Redundant plain text Discord message at match start (only embed message sent now)

---

## [0.9.2] - 2025-12-21

### Fixed
- **Discord Message ID Capture** - Fixed curl response handling for embed editing
  - Root cause: `CURLOPT_WRITEDATA` was passed file path string instead of file handle
  - Solution: Open file with `fopen()`, set `CURLOPT_WRITEFUNCTION` callback, pass handle to curl
  - Discord message ID now properly captured and stored in localinfo for 2nd half editing
  - New function: `discord_curl_write()` - Writes response data to file handle
  - New global: `g_discordResponseHandle[]` - File handle array for curl callback

- **Scoreboard Restoration After Round Restart** - Scores now persist after 2nd half starts
  - Root cause: DoD round restart resets scoreboard immediately after `dodx_set_team_score()` call
  - Solution: 3-second delayed restoration task runs after round restart completes
  - New function: `task_delayed_score_restore()` - Restores scores after round restart
  - New function: `schedule_score_restoration()` - Schedules delayed restoration
  - New task ID: `g_taskScoreRestoreId` (55613)

- **TeamScore Message Format** - Fixed DoD-specific message parsing
  - Root cause: Code used `get_msg_arg_string()` expecting team name like CS/HL
  - Reality: DoD sends BYTE team index (1=Allies, 2=Axis), not string
  - Fix: Changed to `get_msg_arg_int(1)` for correct team index parsing
  - `TEAMSCORE_RAW` and `SCORE_UPDATE` events now properly logged

### Technical
- Curl write callback properly integrated with AMX curl module
- File handle cleanup in `discord_embed_callback()` prevents resource leaks
- Score restoration uses task-based delay for timing consistency

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

[0.9.16]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.15...v0.9.16
[0.9.15]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.14...v0.9.15
[0.9.14]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.13...v0.9.14
[0.9.13]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.12...v0.9.13
[0.9.12]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.11...v0.9.12
[0.9.11]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.10...v0.9.11
[0.9.10]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.9...v0.9.10
[0.9.9]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.2...v0.9.9
[0.9.2]: https://github.com/afraznein/KTPMatchHandler/compare/v0.9.1...v0.9.2
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
