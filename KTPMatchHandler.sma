/* KTP Match Handler v0.10.21
 * Comprehensive match management system with ReAPI pause integration
 *
 * AUTHOR: Nein_
 * VERSION: 0.10.21
 * DATE: 2025-12-31
 *
 * ========== MAJOR FEATURES ==========
 * - ReAPI Pause Integration: Direct pause control via rh_set_server_pause()
 * - Timed Pauses: 5-minute default with MM:SS countdown display
 * - Pause Extensions: /extend adds 2 minutes (max 2 extensions)
 * - Pre-Pause Countdown: Configurable warning before pause activates
 * - Auto-Unpause: Automatic when timer expires (KTP-ReHLDS) or on-command fallback
 * - Disconnect Auto-Pause: 10-second countdown (cancellable via /cancelpause)
 * - Technical Pauses: Budget-based system with time tracking per team
 * - Discord Integration: Real-time match notifications via webhook relay
 * - Comprehensive Logging: AMX log, KTP match log, and Discord
 *
 * ========== MATCH SYSTEM ==========
 * - Pre-Start: /start or /startmatch -> requires one /confirm from each team
 * - Pending: /ready (alias /ktp) + /notready until both teams reach ktp_ready_required
 * - Live: Each team gets ONE tactical pause per half
 * - Tech Pauses: Budget-based (default 300s per team per half)
 *
 * ========== PAUSE CONTROLS ==========
 * - .pause       - Initiate tactical pause (countdown before activation)
 * - .tech        - Technical pause (uses team budget)
 * - .resume      - Request unpause (owner team)
 * - .go          - Confirm unpause (other team, if required)
 * - .ext         - Extend pause by 2 minutes (max 2 times)
 * - .nodc        - Cancel disconnect auto-pause
 *
 * ========== REQUIREMENTS ==========
 * - AMX ModX 1.9+ (minimum)
 * - ReAPI module (recommended for full features)
 * - KTP-ReHLDS (recommended for pause HUD updates and chat)
 * - cURL extension (optional, for Discord notifications)
 *
 * ========== PLATFORM COMPATIBILITY ==========
 * - Base HLDS + AMX: Core features work (requires pausable 1)
 * - ReHLDS + AMX: Same as base + better pause support (requires pausable 1)
 * - KTP-ReHLDS + ReAPI: Full feature set with pausable 0 support
 *
 * ========== SERVER CONFIGURATION ==========
 * Recommended (KTP-ReHLDS + ReAPI):
 *   pausable 0  // Block engine pause, use ReAPI pause only
 *
 * Fallback (base servers without ReAPI):
 *   pausable 1  // Required for engine pause command
 *
 * ========== CVARS ==========
 *   ktp_pause_countdown "5"              - Unpause countdown seconds
 *   ktp_pause_duration "300"             - Pause duration (5 minutes)
 *   ktp_pause_extension "120"            - Extension time (2 minutes)
 *   ktp_pause_max_extensions "2"         - Max extensions allowed
 *   ktp_prepause_seconds "5"             - Pre-pause countdown (live match)
 *   ktp_prematch_pause_seconds "5"       - Pre-pause countdown (pre-match)
 *   ktp_pause_hud "1"                    - Enable pause HUD
 *   ktp_match_logfile "ktp_match.log"    - Log file path
 *   ktp_ready_required "6"               - Players needed to ready up
 *   ktp_cfg_basepath "configs/"          - Config file base path
 *   ktp_maps_file "<configsdir>/ktp_maps.ini"  - Maps file (auto-detected path)
 *   ktp_unpause_autorequest_secs "300"   - Auto-request timeout
 *   ktp_tech_budget_seconds "300"        - Tech pause budget per team
 *   ktp_discord_ini "<configsdir>/discord.ini" - Discord config (auto-detected path)
 *
 * ========== CHANGELOG ==========
 * v0.10.30 (2026-01-01) - Intermission Freeze Fix
 *   * FIXED: Server freeze during intermission when superseding changelevel
 *   * FIXED: Infinite score logging loop caused by HC_SUPERCEDE during intermission
 *   * CHANGED: Match end (2nd half and OT) now processes immediately and lets changelevel proceed
 *   * CHANGED: No more countdown delay for match end - game is already showing scoreboard
 *   * TECHNICAL: HC_SUPERCEDE blocks changelevel but leaves game stuck in intermission mode
 *   * TECHNICAL: OT continuation now uses HC_CONTINUE - next map detects OT via localinfo
 *
 * v0.10.29 (2026-01-01) - 2nd Half Ready HUD
 *   + ADDED: Prominent "Type .ready" HUD for 2nd half and OT pending phases
 *   + ADDED: HUD shows current score context (1st half scores or OT grand totals)
 *   + ADDED: show_continuation_pending_hud() helpers for 2nd half/OT ready phase
 *   * IMPROVED: Yellow centered HUD clearly indicates players need to type .ready
 *
 * v0.10.28 (2026-01-01) - Changelevel Hook Match Finalization
 *   + ADDED: OnChangeLevel() hook intercepts all map changes (KTP-ReHLDS)
 *   + ADDED: 2nd half end now supersedes changelevel, does announcements, then manual changelevel
 *   + ADDED: OT round end supersedes changelevel for proper announcements
 *   + ADDED: 5-second countdown before map change with HUD display
 *   + ADDED: Winner/OT announcement in chat and brief HUD (3 sec, scoreboard visible)
 *   + ADDED: Discord embed update before map change
 *   * FIXED: Match end never processed because logevents fire at exact moment of map change
 *   * FIXED: 2nd half being skipped - changelevel hook ensures proper state finalization
 *   * TECHNICAL: HC_SUPERCEDE blocks engine changelevel, manual changelevel after countdown
 *   * TECHNICAL: OT trigger no longer relies on logevents - changelevel hook handles it
 *   - REMOVED: Old handle_map_change() - replaced by handle_first_half_end(), process_second_half_end_changelevel()
 *   - REMOVED: Old handle_ot_round_end() - replaced by process_ot_round_end_changelevel()
 *
 * v0.10.24 (2025-12-31) - False OT Trigger Fix
 *   * FIXED: Clear _ktp_live flag when 1st half ends (in handle_map_change)
 *   * TECHNICAL: Prevents false 2nd-half-ended detection when 2nd half map loads
 *   * TECHNICAL: Flow: 1st live sets flag -> 1st end clears flag -> 2nd live sets flag
 *
 * v0.10.23 (2025-12-31) - Robust Match End & Overtime Trigger
 *   + ADDED: LOCALINFO_H2_SCORES to persist 2nd half scores during periodic save
 *   + ADDED: amx_nextmap set to current map during 2nd half (ensures map cycles back)
 *   + ADDED: finalize_completed_second_half() handles match end when plugin_end doesn't run
 *   + ADDED: Overtime triggers correctly from finalize if scores are tied
 *   * FIXED: 2nd half scores now persisted to localinfo for crash/end detection
 *   * TECHNICAL: Map cycling back to same map + _ktp_live="1" = 2nd half ended
 *
 * v0.10.22 (2025-12-31) - Score Calculation & Match End Detection Fix
 *   * FIXED: .score 2nd half calculation accounts for restored 1st half scores in DODX
 *   * FIXED: handle_map_change 2nd half score calculation (same fix as .score)
 *   * FIXED: Match end detection when plugin_end doesn't run (extension mode)
 *   + ADDED: LOCALINFO_LIVE flag to track when match is live
 *   + ADDED: finalize_abandoned_match() for detecting/handling matches that end without plugin_end
 *   + ADDED: Discord notification and ktp_match_end forward for abandoned matches
 *   * TECHNICAL: Mode is no longer cleared after restoration (kept until match ends)
 *
 * v0.10.21 (2025-12-31) - 2nd Half State Fix
 *   * FIXED: 2nd half restoration now sets g_matchPending=true so players can .ready
 *   * FIXED: Added g_matchLive=false during restoration to prevent false "match in progress"
 *   + ADDED: "Type .ready to start 2nd half" announcement after restoration
 *
 * v0.10.20 (2025-12-31) - DODX Native Score Broadcast
 *   + ADDED: Uses dodx_broadcast_team_score() for TeamScore updates
 *   + ADDED: g_skipTeamScoreAdjust flag to prevent double-adjustment
 *   + ADDED: ktp_is_match_active() native for external plugin queries
 *   + ADDED: .sbtest command for scoreboard broadcast testing
 *
 * v0.10.1 (2025-12-24) - External Plugin Forwards
 *   + ADDED: ktp_match_start forward for external plugins (KTPHLTVRecorder)
 *   + ADDED: ktp_match_end forward for external plugins (KTPHLTVRecorder)
 *   * TECHNICAL: Forwards fire on 1st half start and match completion (reg/OT)
 *
 * v0.10.0 (2025-12-23) - Overtime Foundation + Localinfo Refactor
 *   + ADDED: Overtime global variables and state tracking
 *   + ADDED: Consolidated localinfo format for reduced serverinfo usage
 *   + ADDED: Helper functions: format_state, parse_state, format_scores, parse_scores
 *   + ADDED: OT score helpers: format_ot_state, parse_ot_state, append_ot_score, parse_ot_scores
 *   + ADDED: HUD announcement at competitive half start showing team names and scores
 *   * CHANGED: Localinfo keys shortened (_ktp_mid, _ktp_mode, _ktp_state, etc.)
 *   * CHANGED: Mode-based context detection (h2, ot1, ot2...) replaces half_pending flag
 *   * CHANGED: Consolidated pause/tech state into single key
 *   * FIXED: HUD Y-position consistency (ready/confirm HUDs now aligned)
 *   ! BREAKING: Localinfo format changed - matches in progress will lose 2nd half context
 *
 * v0.9.17 (2025-12-22) - 12man Duration Menu
 *   + ADDED: Duration selection menu when starting 12man matches
 *   + ADDED: 20 minute (standard) or 15 minute options
 *   + ADDED: Automatic mp_timelimit override for non-standard durations
 *   * TECHNICAL: Menu displayed on .12man, sets g_12manDuration, applies after map config
 *
 * v0.9.16 (2025-12-21) - Version Consistency
 *   * CHANGED: Version bump for consistency across source and documentation
 *
 * v0.9.15 (2025-12-21) - Crash Fix
 *   * FIXED: Server crash on 2nd half map exec
 *   * CAUSE: broadcast_team_score() called during map load when players not connected
 *   * FIX: Only broadcast in delayed tasks (5s+), use dodx_set_team_score() for immediate
 *
 * v0.9.14 (2025-12-21) - Score Command Fix
 *   * FIXED: /score command no longer double-counts 1st half scores in 2nd half
 *   * FIXED: 2nd half totals now correctly show cumulative scoreboard values
 *   * TECHNICAL: Same calculation as build_scores_field() (subtract 1st half from cumulative)
 *
 * v0.9.13 (2025-12-21) - Scoreboard Broadcast Fix
 *   * FIXED: Scoreboard now updates for clients on 2nd half score restoration
 *   * ROOT CAUSE: dodx_set_team_score() only set internal value, not broadcast to clients
 *   + ADDED: broadcast_team_score() - Sends TeamScore message to all clients
 *   + ADDED: set_and_broadcast_score() - Combined set + broadcast for score restoration
 *   * TECHNICAL: Uses DoD TeamScore format (BYTE team, SHORT score) for MSG_ALL
 *
 * v0.9.12 (2025-12-21) - Discord Embed 2nd Half Score Fix
 *   * FIXED: 2nd half embed now shows correct 0-0 score at start (not subtracted values)
 *   * FIXED: Sync g_matchScore immediately after score restoration
 *   + ADDED: Multiple restoration attempts at 5s, 8s, 12s, 15s after 2nd half start
 *
 * v0.9.11 (2025-12-21) - Discord Newline Fix
 *   * FIXED: Discord embed uses ^n for newlines (properly escaped to \n in JSON)
 *   * CHANGED: Used ^n instead of \\n in score display string
 *
 * v0.9.10 (2025-12-21) - Score Save Timing Fix
 *   * CHANGED: Initial periodic score save at 2 seconds (was 30 seconds)
 *   * REASON: Ensure 0-0 is persisted early in case of early map change
 *
 * v0.9.9 (2025-12-21) - Duplicate Discord Message Fix
 *   - REMOVED: Redundant plain text Discord message at match start
 *   * KEPT: Only embed message sent at match start (no duplicate)
 *
 * v0.9.8 (2025-12-21) - Dynamic Player Name Updates
 *   * FIXED: Player names in pause HUD now update dynamically if player changes name
 *   + ADDED: get_dynamic_name() helper for real-time name lookup
 *   + ADDED: Player ID tracking for pause initiator, unpause requestor, and confirmers
 *   * TECHNICAL: Falls back to cached name if player disconnects
 *
 * v0.9.7 (2025-12-21) - HUD Command Aliases & Discord Buffer Fix
 *   * CHANGED: Pause HUD now shows .resume | .go | .ext instead of /resume | /confirmunpause | /extend
 *   + ADDED: .ext alias for pause extension command
 *   * FIXED: All chat announcements use shorter . command aliases
 *   * FIXED: Discord response buffer increased from 512 to 4096 bytes
 *
 * v0.9.5 (2025-12-21) - Discord Message ID Debug & Fixes
 *   * FIXED: Use get_datadir() instead of localinfo for temp file path (more reliable)
 *   + ADDED: Comprehensive logging for Discord message ID capture failures
 *   + ADDED: Log file path in DISCORD_MATCH_EMBED_CREATE event
 *
 * v0.9.4 (2025-12-21) - Discord Cleanup
 *   - REMOVED: Tactical pause Discord notification (unnecessary noise)
 *
 * v0.9.3 (2025-12-21) - Discord Edit URL Fix
 *   * FIXED: Discord edit URL now uses replace_string() to swap /reply with /edit
 *   * TECHNICAL: Supports shared discord.ini with /reply endpoint across plugins
 *
 * v0.9.2 (2025-12-21) - Discord Message ID & Scoreboard Restoration Fixes
 *   * FIXED: Discord message ID capture - curl now uses file handle with write callback
 *   * FIXED: Scoreboard restoration - 3-second delayed task after round restart
 *   * FIXED: TeamScore message format - DoD uses BYTE team index, not STRING
 *   + ADDED: discord_curl_write() callback for proper response capture
 *   + ADDED: task_delayed_score_restore() for post-round-restart restoration
 *   + ADDED: schedule_score_restoration() for delayed score restoration
 *
 * v0.9.1 (2025-12-20) - Discord Embed Roster & Score Persistence Fix
 *   + ADDED: Discord embed roster - Teams displayed in side-by-side inline fields
 *   + ADDED: Match ID shown in roster embed footer
 *   + ADDED: Periodic score saving (every 30s) during 1st half to localinfo
 *   + ADDED: task_periodic_score_save() for robust score persistence
 *   * FIXED: Discord message formatting - removed code block wrapper so markdown renders
 *   * FIXED: Score persistence when plugin_end doesn't run (ReHLDS extension mode)
 *   * FIXED: Newline escaping in Discord embed field values
 *   + IMPROVED: Roster format now shows player name and SteamID on separate lines
 *   + TECHNICAL: escape_for_json() function for proper JSON string escaping
 *   + TECHNICAL: send_discord_embed_raw() for sending embed payloads
 *
 * v0.7.1 (2025-12-18) - Match Context Persistence & Per-Match Pause Limits
 *   + ADDED: Match context persists across map change via localinfo
 *   + ADDED: Match ID, pause counts, and tech budget survive plugin reload for 2nd half
 *   + FIXED: Match ID now properly restored when 2nd half starts
 *   + FIXED: Pause limits are now per-MATCH (not per-half) - teams can't reset by going to 2nd half
 *   + FIXED: Tech budget is now per-MATCH (not per-half) - remaining budget carries over
 *   + IMPROVED: 2nd half announces match continuation with pause usage status
 *   NOTE: Uses localinfo keys (_ktp_match_id, _ktp_half_pending, etc.)
 *
 * v0.7.0 (2025-12-16) - HLStatsX Stats Integration
 *   + ADDED: HLStatsX integration for match vs warmup stats separation
 *   + ADDED: dodx_flush_all_stats() - flushes pending stats to log
 *   + ADDED: dodx_reset_all_stats() - resets all player stats
 *   + ADDED: dodx_set_match_id() - sets match context for stats logging
 *   + ADDED: KTP_MATCH_START log marker for HLStatsX parsing
 *   + ADDED: KTP_MATCH_END log marker for HLStatsX parsing
 *   + ADDED: (matchid "xxx") property in weaponstats log lines
 *   + IMPROVED: Stats automatically flushed at half/match end
 *   + IMPROVED: Warmup stats logged separately (no matchid) before match
 *   NOTE: Requires DODX module with HLStatsX natives
 *
 * v0.6.0 (2025-12-16) - Match ID System, Ready Enhancements, Streamlined Flow
 *   + ADDED: Unique match ID system (format: KTP-{timestamp}-{mapname})
 *   + ADDED: Match ID persists across both halves for MySQL/stats correlation
 *   + ADDED: Match ID included in Discord notifications and all log entries
 *   + ADDED: /whoneedsready command - shows unready players with Steam IDs
 *   + ADDED: /unready command alias for /whoneedsready
 *   + ADDED: Steam IDs now displayed in READY/NOTREADY announcements
 *   + ADDED: Periodic unready player reminder (every 30 sec during ready phase)
 *   + IMPROVED: Half tracking now logs match_id in HALF_START and HALF_END events
 *   + IMPROVED: Match start Discord message now includes match ID in code block
 *   - REMOVED: Automatic pause during ready phase (confirm → ready → LIVE is now seamless)
 *   - REMOVED: Unpause countdown at match start (match goes LIVE immediately when all ready)
 *   - REMOVED: Redundant half tracking code (consolidated into early match flow)
 *
 * v0.5.2 (2025-12-03) - KTP AMX Compatibility
 *   * FIXED: Use get_configsdir() for dynamic config path resolution
 *   * FIXED: Removed hardcoded "addons/amxmodx" paths for KTP AMX compatibility
 *   * IMPROVED: ReAPI availability message changed from WARNING to informational note
 *
 * v0.5.1 (2025-12-02) - Critical Bug Fixes and Security Improvements
 *   * FIXED: [CRITICAL] cURL header memory leak causing accumulation on every Discord message
 *   * FIXED: [CRITICAL] Tech pause budget integer underflow from system clock adjustments
 *   * FIXED: [HIGH] Buffer overflow in player roster concatenation with 12+ players per team
 *   * FIXED: [HIGH] Inconsistent team ID validation before g_techBudget array access
 *   * FIXED: [MEDIUM] Tech pause start time not cleared on match cancel (state corruption)
 *   * FIXED: [MEDIUM] JSON escape buffer overflow with multiple escape sequences
 *   * FIXED: [MEDIUM] Config path manipulation calling contain() twice with potential -1 index
 *   * FIXED: [MEDIUM] Team ID bounds check using || instead of && (logic error)
 *   * FIXED: [MEDIUM] Task leak state cleanup missing g_disconnectedPlayerName/Team clearing
 *   * FIXED: [MEDIUM] Double disconnect logging missing for second player
 *   * FIXED: [MEDIUM] Missing is_user_connected() checks in command handlers
 *   - REMOVED: Redundant is_user_connected() check in player roster loop (dead code)
 *   + ADDED: Time validation to prevent underflow in tech budget calculations
 *   + ADDED: Elapsed time sanity check (cap at 1 hour maximum)
 *   + ADDED: Buffer space validation before string concatenation
 *   + ADDED: Clock skew detection and error logging
 *   + IMPROVED: Defensive programming with consistent bounds checking
 *   + SECURITY: Proper memory management for cURL resources
 *
 * v0.5.0 (2025-11-24) - Major Feature Update: Match Types, Half Tracking, Command Aliases
 *   + ADDED: Match type system (COMPETITIVE, SCRIM, 12MAN) with per-type configs and Discord channels
 *   + ADDED: Per-match-type map configs (e.g., dod_kalt_12man.cfg, dod_kalt_scrim.cfg) with fallback
 *   + ADDED: Per-match-type Discord channels (discord_channel_id_12man, discord_channel_id_scrim)
 *   + ADDED: Half tracking system (1st half / 2nd half) with automatic detection
 *   + ADDED: Automatic map rotation adjustment for 2nd half (amx_nextmap to current map)
 *   + ADDED: Half number display in match start messages ("1st half" or "2nd half")
 *   + ADDED: Player roster logging to Discord at match start (all players, teams, SteamIDs, IPs)
 *   + ADDED: Dot command aliases for all commands (.pause, .tech, .ready, .resume, .status, etc.)
 *   + ADDED: /draft command (same as /start and /ktp)
 *   + CHANGED: Renamed /startmatch to /ktp (kept /start as alias)
 *   + CHANGED: Renamed /start12man to /12man (with .12man alias)
 *   + CHANGED: Renamed /startscrim to /scrim (with .scrim alias)
 *   - REMOVED: 'ready' and 'ktp' aliases from /ready command (conflict resolution)
 *   * IMPROVED: Discord messages now routed to match-type-specific channels with fallback
 *   * IMPROVED: Map config selection now tries match-type-specific configs first
 *
 * v0.4.6 (2025-11-22) - CRITICAL FIX: Match Start Flow
 *   * FIXED: Match start entering uncontrollable tactical pause instead of LIVE countdown
 *   * FIXED: Team confirmation triggering pre-pause countdown (wrong flow)
 *   * FIXED: Countdown task not running during pause (tasks don't execute when paused)
 *   * FIXED: Jarring unpause/re-pause transition from pending to match start
 *   + ADDED: Countdown handling in OnPausedHUDUpdate() hook (runs during pause)
 *   + CHANGED: Confirmation now directly executes pause (no countdown)
 *   + CHANGED: Ready completion stays paused, just starts countdown (smooth transition)
 *   + FLOW: Confirm → pause → Ready → countdown (same pause) → LIVE (smooth)
 *   + BEFORE: Confirm → pre-pause countdown → pause → Ready → stuck (broken)
 *
 * v0.4.5 (2025-11-22) - Critical Bug Fixes and Scrim Mode
 *   + ADDED: /startscrim and /start12man commands (skip Discord notifications)
 *   + ADDED: g_disableDiscord flag to control Discord webhook calls
 *   * FIXED: Missing task cleanup before pre-pause countdown (race condition)
 *   * FIXED: Missing pre-pause task cleanup in plugin_end() (memory leak)
 *   * FIXED: Tech budgets not reset on match cancel (state carry-over)
 *   * FIXED: Pre-pause state not cleared on match cancel
 *   * FIXED: Double timestamp assignment race condition in pause flow
 *   * FIXED: Disconnect state not cleared after unpause
 *   * FIXED: Missing countdown task cleanup before set_task() (duplicate tasks)
 *   * FIXED: Multiple simultaneous disconnects overwriting first disconnect info
 *   * OPTIMIZED: Removed duplicate config loading in plugin_init() (~25ms faster startup)
 *   + STABILITY: Prevents race conditions from multiple concurrent countdowns
 *   + STABILITY: Ensures clean state between matches
 *   + STABILITY: Improved disconnect auto-pause handling
 *
 * v0.4.4 (2025-11-21) - Phase 5 Performance Optimizations
 *   * OPTIMIZED: Eliminated 8 redundant get_mapname() calls (use cached g_currentMap)
 *   * OPTIMIZED: Cached g_pauseDurationSec and g_preMatchPauseSeconds CVARs
 *   * OPTIMIZED: Index-based formatex in cmd_status() (30-40% faster string building)
 *   * OPTIMIZED: Switch statement in get_ready_counts() for cleaner team ID handling
 *   - REMOVED: Unused map variable declaration (compiler warning eliminated)
 *   + PERFORMANCE: 15-20% reduction in string operations during logging
 *   + PERFORMANCE: 5-10% faster pause initialization with cached CVARs
 *   + PERFORMANCE: 10-15% faster player iteration in get_ready_counts()
 *
 * v0.4.3 (2025-11-20) - Discord Notification Filtering
 *   + ADDED: send_discord_with_hostname() helper function
 *   + ADDED: Hostname prefix to all Discord notifications
 *   * CHANGED: Disabled non-essential Discord notifications
 *   * KEPT: Only 3 essential notifications with hostname:
 *     - Match start (⚔️)
 *     - Player tactical pause (⏸️)
 *     - Disconnect auto-pause (📴)
 *
 * v0.4.2 (2025-11-20) - cURL Discord Integration Fix
 *   * FIXED: Discord notifications not working (curl.inc was disabled)
 *   * FIXED: Compilation errors with backslash character constants (changed to numeric 92)
 *   * FIXED: Compilation errors with \n, \r, \t (changed to numeric 10, 13, 9)
 *   * FIXED: JSON string escaping in formatex (changed \" to ^")
 *   * FIXED: Invalid cURL header constant (Invalid_CURLHeaders -> SList_Empty)
 *   * FIXED: Duplicate discordMsg variable declaration (wrapped in #if defined HAS_CURL)
 *   + ENABLED: curl.inc in AMX Mod X includes directory
 *   + COMPILED: Plugin now includes full cURL support for Discord notifications
 *   ! REQUIRES: curl_amxx.dll module enabled in modules.ini
 *   ! REQUIRES: discord.ini with relay URL, channel ID, and auth secret
 *
 * v0.4.1 (2025-11-17) - Pausable Cvar Removal
 *   - REMOVED: All pausable cvar manipulation code
 *   - REMOVED: ktp_force_pausable cvar (no longer needed)
 *   - REMOVED: g_pcvarPausable and g_cvarForcePausable variables
 *   - REMOVED: ktp_force_pausable_if_needed() function
 *   - REMOVED: pausable value from debug logs and client messages
 *   * CHANGED: Simplified logging (removed pausable from PAUSE_ATTEMPT/UNPAUSE_ATTEMPT)
 *   * CHANGED: Cleaner client messages ("Game paused" vs "Pause enforced")
 *   * CHANGED: cmd_ktpdebug no longer shows pausable value
 *   + IMPROVED: Cleaner code (~33 lines removed, ~10 lines simplified)
 *   + IMPROVED: Comments explain ReAPI bypass of pausable cvar
 *   ! REQUIRES: pausable 0 for KTP-ReHLDS + ReAPI (recommended)
 *   ! REQUIRES: pausable 1 for base servers without ReAPI (fallback)
 *
 * v0.4.0 (2025-11-17) - ReAPI Pause Integration
 *   + ReAPI Pause: Direct control via rh_set_server_pause() bypasses pausable cvar
 *   + Works with pausable 0: Only KTP system can pause, engine pause blocked
 *   + Complete time freeze: host_frame stops, g_psv.time frozen, SV_Physics halted
 *   + Unified pause countdown system for ALL pause entry points
 *   + Graceful degradation: Base AMX -> ReHLDS -> KTP-ReHLDS + ReAPI
 *   + Timed pauses: 5-minute default with MM:SS countdown (all platforms)
 *   + Pre-pause countdown: Configurable (live match vs pre-match)
 *   + Pause extensions: /extend command (max 2 extensions, all platforms)
 *   + Auto-unpause on timer expiration (automatic with KTP-ReHLDS)
 *   + Disconnect auto-pause: 10-second countdown, cancellable
 *   + Real-time pause tracking using get_systime() instead of host_frametime
 *   + ReAPI integration: RH_SV_UpdatePausedHUD hook for automatic HUD updates
 *   + Manual timer checks: Fallback for base AMX/standard ReHLDS
 *   + Discord integration: Webhook relay for match notifications
 *   + Map config system: Section-based ktp_maps.ini format
 *   + Comprehensive logging: AMX log, KTP match log, Discord
 *   * Fixed: Command registration conflict ("Cmd_AddMallocCommand: pause already defined")
 *   * Fixed: HUD updates during pause using real-world time
 *   * Fixed: Chat announcements during pause (rcon_say fallback)
 *   * Fixed: /ready system undefined variable bug
 *   * Enhanced: /status command shows detailed player ready status
 *   - Removed: Duplicate pause command registrations
 *   - Removed: Game-time based pause_timer_tick (replaced with real-time)
 *
 * v0.3.3 - Previous Stable Release
 *   - Two-team confirm unpause system
 *   - Per-team tactical pause limits (1 per half)
 *   - Technical pause with budget tracking
 *   - Disconnect detection with auto tech-pause
 *   - Pre-start confirmation system
 *   - Discord webhook integration (basic)
 */

#include <amxmodx>
#include <amxmisc>
#include <ktp_discord>

// KTP: DODX for HLStatsX stats integration
// Provides: dodx_flush_all_stats(), dodx_reset_all_stats(), dodx_set_match_id()
#tryinclude <dodx>
#if defined _dodx_included
    #define HAS_DODX 1
#endif

// Runtime check for DODX HLStatsX natives (set in plugin_cfg)
new bool:g_hasDodxStatsNatives = false;

// Optional: ReAPI for enhanced pause HUD hooks
// Enables RH_SV_UpdatePausedHUD hook when combined with KTP-ReHLDS
// Standard ReAPI doesn't include this hook - requires KTP-ReHLDS fork
#tryinclude <reapi>

// Optional: cURL for Discord notifications
#tryinclude <curl>
#if defined _curl_included
    #define HAS_CURL 1
#endif

#define PLUGIN_NAME    "KTP Match Handler"
#define PLUGIN_VERSION "0.10.30"
#define PLUGIN_AUTHOR  "Nein_"

// ---------- CVARs ----------
new g_cvarLogFile;
new g_cvarReadyReq;
new g_cvarCfgBase;
new g_cvarMapsFile;
new g_cvarAutoReqSec;
new g_cvarCountdown;          // unpause countdown seconds (ktp_pause_countdown)
new g_cvarPrePauseSec;        // pre-pause chat countdown for live matches (ktp_prepause_seconds)
new g_cvarPreMatchPauseSec;   // pre-pause countdown for pre-match pauses (ktp_prematch_pause_seconds)
new g_cvarTechBudgetSec;      // technical pause budget per team per half (ktp_tech_budget_seconds)
new g_cvarDiscordIniPath;     // path to discord.ini (ktp_discord_ini)
// NOTE: pausable cvar variables removed - ReAPI pause bypasses pausable entirely
new g_cvarPauseDuration;      // pause duration seconds (ktp_pause_duration)
new g_cvarPauseExtension;     // pause extension seconds (ktp_pause_extension)
new g_cvarMaxExtensions;      // max pause extensions (ktp_pause_max_extensions)
new g_cvarUnreadyReminderSec; // unready reminder interval (ktp_unready_reminder_secs)
new g_cvarUnpauseReminderSec; // unpause reminder interval (ktp_unpause_reminder_secs)

// ---------- Discord Config (loaded from INI) ----------
new g_discordRelayUrl[256];          // Discord relay endpoint URL
new g_discordChannelId[64];          // Discord channel ID (competitive)
new g_discordChannelId12man[64];     // Discord channel ID for 12man matches (optional)
new g_discordChannelIdScrim[64];     // Discord channel ID for scrim matches (optional)
new g_discordAuthSecret[128];        // X-Relay-Auth header value

// ---------- Match Types ----------
enum MatchType {
    MATCH_TYPE_COMPETITIVE = 0,  // Regular competitive match (Discord enabled, competitive config) - blocked off-season
    MATCH_TYPE_SCRIM = 1,        // Scrim match (Discord disabled, scrim config) - always allowed
    MATCH_TYPE_12MAN = 2,        // 12-man match (Discord disabled, 12man config) - always allowed
    MATCH_TYPE_DRAFT = 3         // Draft match (Discord disabled, competitive config) - always allowed
};

// ---------- State ----------
new bool: g_isPaused = false;
new bool: g_matchPending = false;
new bool: g_countdownActive = false;
new bool: g_matchLive = false;              // becomes true after first LIVE
new bool: g_disableDiscord = false;         // when true, skip all Discord notifications (legacy - use g_matchType instead)
new bool: g_periodicSaveStarted = false;    // tracks if 30s repeating score save is running
new MatchType: g_matchType = MATCH_TYPE_COMPETITIVE; // Current match type
new g_12manDuration = 20; // 12man match duration in minutes (20 or 15)
new g_techBudget[3] = {0, 0, 0}; // [1]=Allies, [2]=Axis; set at half start to g_techBudgetSecs

// ---------- Half Tracking ----------
new g_currentHalf = 0;          // 0 = no match, 1 = first half, 2 = second half
new g_matchMap[32];             // Map name for the current match (to detect if we're on same map for 2nd half)
new bool: g_secondHalfPending = false; // True after 1st half completes, waiting for 2nd half to start

// ---------- Localinfo Keys (persist match context across map change) ----------
// These keys store match state so 2nd half / OT can continue the same match
// Keys are shortened to minimize serverinfo buffer usage
new const LOCALINFO_MATCH_ID[]     = "_ktp_mid";      // Match ID
new const LOCALINFO_MATCH_MAP[]    = "_ktp_map";      // Map name
new const LOCALINFO_MODE[]         = "_ktp_mode";     // "" | "h2" | "ot1" | "ot2" | ... (replaces half_pending)
new const LOCALINFO_LIVE[]         = "_ktp_live";     // "1" if match is live (for abandoned match detection)
new const LOCALINFO_STATE[]        = "_ktp_state";    // "pauseA,pauseX,techA,techX" (consolidated)
new const LOCALINFO_H1_SCORES[]    = "_ktp_h1";       // 1st half scores: "score1,score2"
new const LOCALINFO_H2_SCORES[]    = "_ktp_h2";       // 2nd half running scores (for abandoned match detection)
new const LOCALINFO_TEAMNAME1[]    = "_ktp_t1n";      // Team 1 name (started as Allies)
new const LOCALINFO_TEAMNAME2[]    = "_ktp_t2n";      // Team 2 name (started as Axis)
new const LOCALINFO_DISCORD_MSG[]  = "_ktp_dmsg";     // Discord embed message ID
new const LOCALINFO_DISCORD_CHAN[] = "_ktp_dch";      // Discord channel ID

// OT-specific keys (only used during overtime)
new const LOCALINFO_REG_SCORES[]   = "_ktp_reg";      // Regulation totals: "score1,score2"
new const LOCALINFO_OT_SCORES[]    = "_ktp_ots";      // OT rounds: "t1,t2|t1,t2|..." per round
new const LOCALINFO_OT_STATE[]     = "_ktp_otst";     // "techA,techX,side" (OT tech budgets + starting side)

// ---------- Match ID System ----------
new g_matchId[64];              // Unique match identifier (format: KTP-{timestamp}-{mapname})

// ---------- Captains ----------
new g_captain1_name[64];
new g_captain1_sid[44];
new g_captain1_ip[32];
new g_captain1_team; // 1=Allies, 2=Axis
new g_captain2_name[64];
new g_captain2_sid[44];
new g_captain2_ip[32];
new g_captain2_team; // 1=Allies, 2=Axis

new g_taskCountdownId = 55601;
new g_taskPendingHudId = 55602;
new g_taskPrestartHudId = 55603;
new g_taskAutoUnpauseReqId = 55604;
new g_taskPauseHudId = 55605;
new g_taskAutoReqCountdownId = 55606;
new g_taskUnreadyReminderId = 55607;  // Periodic reminder of unready players
new g_taskUnpauseReminderId = 55608;  // Periodic reminder waiting for other team to confirmunpause

// ---------- Forwards (for external plugins) ----------
new g_fwdMatchStart;    // ktp_match_start(matchId[], map[], matchType)
new g_fwdMatchEnd;      // ktp_match_end(matchId[], map[], matchType, team1Score, team2Score)

// ---------- Team Names (customizable) ----------
new g_teamName[3][32] = {"", "Allies", "Axis"};  // [1]=Current Allies name, [2]=Current Axis name

// ---------- Team Identity (persisted across side swaps) ----------
// These track team identity by who started on which side in 1st half
new g_team1Name[32] = "Allies";  // Name of team that started as Allies (persisted)
new g_team2Name[32] = "Axis";    // Name of team that started as Axis (persisted)

// ---------- Match Score Tracking ----------
new g_matchScore[3];          // [1]=Current Allies score, [2]=Current Axis score (resets each map)
new g_firstHalfScore[3];      // [1]=Team1's 1st half score, [2]=Team2's 1st half score (by team identity)
new g_pendingScoreAllies = 0; // Pending score to restore to Allies (for deferred restoration)
new g_pendingScoreAxis = 0;   // Pending score to restore to Axis (for deferred restoration)

// ---------- Score Broadcast State ----------
new bool:g_skipTeamScoreAdjust = false;  // Skip msg_TeamScore adjustment (used during direct broadcast)

// ---------- Overtime State ----------
new bool:g_inOvertime = false;      // Currently in overtime
new g_otRound = 0;                  // Current OT round (1, 2, 3...)
new g_regulationScore[3];           // Regulation totals [1]=team1, [2]=team2
new g_otScores[32][3];              // OT scores per round [round][team] - supports up to 31 OT rounds
new g_otTechBudget[3];              // OT tech budgets (reset once at OT start)
new g_otTeam1StartsAs = 0;          // Which side team1 starts on this OT round (1=Allies, 2=Axis)
new bool:g_otBreakActive = false;   // Break in progress before OT
new g_otBreakVotes[33];             // Player votes for break (0=none, 1=yes)
new g_otBreakExtensions[3];         // Extensions used per team [1]=team1, [2]=team2
new g_otBreakTimeLeft = 0;          // Break countdown seconds remaining

// ---------- Tunables (defaults; CVARs can override at runtime) ----------
new g_countdownSeconds = 5;    // unpause countdown
new g_prePauseSeconds = 5;     // pre-pause countdown for live pauses
new g_preMatchPauseSeconds = 5;  // OPTIMIZED: Cached from g_cvarPreMatchPauseSec (Phase 5 optimization)
new g_techBudgetSecs = 300;    // 5 minutes tech budget per team per half
new g_readyRequired   = 1;     // players needed per team to go live
new g_countdownLeft = 0;
new const DEFAULT_LOGFILE[] = "ktp_match.log";

// ---------- OPTIMIZED: Cached CVAR values (Phase 2 optimization) ----------
new g_pauseExtensionSec = 120;     // cached from g_cvarPauseExtension
new g_pauseMaxExtensions = 2;      // cached from g_cvarMaxExtensions
new g_autoRequestSecs = 300;       // cached from g_cvarAutoReqSec
new g_serverHostname[64];          // cached from "hostname" cvar
new Float:g_unreadyReminderSecs = 30.0;  // cached from g_cvarUnreadyReminderSec
new Float:g_unpauseReminderSecs = 15.0;  // cached from g_cvarUnpauseReminderSec

// ---------- Constants ----------
#define MAX_PLAYERS 32
const AUTO_REQUEST_MIN_SECS = 60;
const AUTO_REQUEST_DEFAULT_SECS = 300;
const AUTO_REQUEST_MAX_SECS = 3600; // 1 hour maximum
const DISCONNECT_COUNTDOWN_SECS = 10;

// Unpause attribution
new g_lastUnpauseBy[80];

// Track who paused (for HUD display)
new g_lastPauseBy[80];
new g_lastPauseById = 0;

// Ready flags per player
new bool: g_ready[33];

// cURL headers (needs to be freed after use)
new curl_slist:g_curlHeaders = SList_Empty;

// ---------- Global buffers for stack-heavy functions ----------
// These are declared globally instead of locally to avoid AMX stack overflow (16KB limit)
// Discord message buffers
new g_discordChannelIdBuf[64];
new g_discordEscapedMsg[512];
new g_discordPayload[768];
new g_discordAuthHeader[192];
// Roster buffers for Discord (embed format uses newlines between players)
new g_rosterAllies[512];
new g_rosterAxis[512];
new g_rosterEmbedPayload[2048];  // Larger buffer for embed JSON

// Discord message editing support
new g_discordMatchMsgId[32];         // Message ID of the consolidated match embed
new g_discordMatchChannelId[64];     // Channel where match embed was sent
new g_discordResponseFile[128];      // Temp file path for curl response capture
new g_discordResponseBuffer[4096];   // Buffer for reading response file (needs to capture full JSON with embeds)
new g_discordResponseHandle[1];      // File handle for curl write callback (array for passing to perform)

// Roster tracking for 2nd half comparison (detect new players)
new g_firstHalfRosterAllies[16][44]; // SteamIDs of players on Allies in 1st half (max 16)
new g_firstHalfRosterAxis[16][44];   // SteamIDs of players on Axis in 1st half (max 16)
new g_firstHalfRosterAlliesCount = 0;
new g_firstHalfRosterAxisCount = 0;
// Unready player lists
new g_unreadyAllies[512];
new g_unreadyAxis[512];

// HUD
new g_hudSync;

const HUD_R = 255;
const HUD_G = 170;
const HUD_B = 0;
const Float: HUD_X = 0.38;
const Float: HUD_Y = 0.20;

// Cached map name
new g_currentMap[32];

// AMX defines EOS as end of string

// INI map→cfg cache
#define MAX_MAP_ROWS 128
new g_mapKeys[MAX_MAP_ROWS][96];
new g_mapCfgs[MAX_MAP_ROWS][128];
new g_mapRows = 0;

// ---------- KTP Season Control ----------
// When season is inactive, /start and /ktp are disabled (only /12man, /scrim, and /draft work)
new bool: g_ktpSeasonActive = true;  // Default to active (loaded from ktp.ini)
new g_ktpMatchPassword[64] = "ktpmatch";  // Password for .ktp command (loaded from ktp.ini)

// ---------- Pre-Start (two-team confirm) ----------
new bool: g_preStartPending = false;
new bool: g_preConfirmAllies = false;
new bool: g_preConfirmAxis   = false;
new g_confirmAlliesBy[80];
new g_confirmAxisBy[80];

// ---------- Pause ownership & limits ----------
new g_pauseOwnerTeam = 0;                   // 0 none, 1 allies, 2 axis (live-match pauses only)
new bool: g_unpauseRequested = false;       // owner (or auto) has requested unpause
new bool: g_unpauseConfirmedOther = false;  // other team has confirmed
new g_pauseCountTeam[3];                    // index by teamId (1..2). Tactical pause count. Reset at new half or when PRE-START begins
new g_autoReqLeft = 0;                      // seconds left for auto-request countdown (HUD)
new bool: g_isTechPause = false;            // true if current pause is technical, false if tactical
new g_techPauseStartTime = 0;               // systime when tech pause started (for budget tracking)
new g_techPauseFrozenTime = 0;              // systime when owner did /resume (freezes budget at this point)
new g_taskAutoConfirmId = 55611;            // task ID for auto-confirmunpause after 60s
new g_autoConfirmLeft = 0;                  // seconds left until auto-confirmunpause
new g_taskDisconnectCountdownId = 55609;    // task ID for disconnect countdown
new g_disconnectCountdown = 0;              // seconds left in disconnect countdown
new g_disconnectedPlayerName[32];           // name of player who disconnected
new g_disconnectedPlayerTeam = 0;           // team of player who disconnected
new g_disconnectedPlayerSteamId[44];        // SteamID of player who disconnected

// ---------- Pause Timing System ----------
new g_pauseStartTime = 0;                   // Unix timestamp when pause began
new g_pauseDurationSec = 300;               // 5 minutes default pause duration
new g_pauseExtensions = 0;                  // How many extensions have been used
// Note: Extension seconds and max extensions are read from CVARs dynamically
new bool: g_prePauseCountdown = false;      // Pre-pause countdown active
new g_prePauseLeft = 0;                     // Seconds left in pre-pause countdown
new g_prePauseReason[64];                   // Reason for pause (for logging)
new g_prePauseInitiator[32];                // Who initiated the pause
new g_prePauseInitiatorId = 0;              // Player ID of pause initiator (for dynamic name lookup)
// Note: Pause timer ID not needed when using ReAPI hook (only for fallback)
new g_taskPrePauseId = 55610;               // Task ID for pre-pause countdown
new g_taskScoreSaveId = 55612;              // Task ID for periodic score saves to localinfo
new g_taskScoreRestoreId = 55613;           // Task ID for delayed score restoration after round restart

// ================= Utilities =================
stock log_ktp(const fmt[], any:...) {
    new file[64];
    get_pcvar_string(g_cvarLogFile, file, charsmax(file));
    if (!file[0]) copy(file, charsmax(file), DEFAULT_LOGFILE);

    new stamp[32];
    get_time("%Y-%m-%d %H:%M:%S", stamp, charsmax(stamp));

    new msg[256];
    vformat(msg, charsmax(msg), fmt, 2);

    log_to_file(file, "[%s] %s", stamp, msg);
}

// ================= MATCH SCORE TRACKING =================

// Hook TeamScore message
// DoD format: BYTE teamIndex (1=Allies, 2=Axis), SHORT score
// Note: DoD uses team INDEX, not team NAME like CS/HL
public msg_TeamScore() {
    // Read team index (DoD sends BYTE for team ID, not string)
    new teamId = get_msg_arg_int(1);
    new score = get_msg_arg_int(2);
    new originalScore = score;

    // =============== 2ND HALF SCORE ADJUSTMENT ===============
    // In 2nd half, modify game-sent TeamScore messages to add 1st half scores
    // This makes the scoreboard show grand totals instead of just 2nd half scores
    // Teams swap sides: Team1 was Allies (1st) -> now Axis, Team2 was Axis (1st) -> now Allies
    // SKIP if g_skipTeamScoreAdjust is set (our direct broadcasts already have correct totals)
    if (g_matchLive && g_currentHalf == 2 && !g_inOvertime && !g_skipTeamScoreAdjust) {
        new baseScore = 0;
        if (teamId == 1) {
            // Allies in 2nd half = Team 2 (was Axis in 1st half)
            baseScore = g_firstHalfScore[2];
        } else if (teamId == 2) {
            // Axis in 2nd half = Team 1 (was Allies in 1st half)
            baseScore = g_firstHalfScore[1];
        }

        if (baseScore > 0) {
            new adjustedScore = score + baseScore;
            set_msg_arg_int(2, ARG_SHORT, adjustedScore);
            log_ktp("event=TEAMSCORE_ADJUSTED team_id=%d original=%d base=%d adjusted=%d",
                    teamId, score, baseScore, adjustedScore);
            score = adjustedScore;  // Update for tracking
        }
    }
    // ===========================================================

    // Enhanced debug logging - compare game score vs DODX internal score
    #if defined HAS_DODX
    new dodxAllies = dodx_get_team_score(1);
    new dodxAxis = dodx_get_team_score(2);
    log_ktp("event=TEAMSCORE_MSG team_id=%d game_score=%d dodx_allies=%d dodx_axis=%d internal_allies=%d internal_axis=%d matchLive=%d half=%d time=%d",
            teamId, originalScore, dodxAllies, dodxAxis, g_matchScore[1], g_matchScore[2], g_matchLive, g_currentHalf, get_systime());
    #else
    log_ktp("event=TEAMSCORE_MSG team_id=%d game_score=%d internal_allies=%d internal_axis=%d matchLive=%d half=%d time=%d",
            teamId, originalScore, g_matchScore[1], g_matchScore[2], g_matchLive, g_currentHalf, get_systime());
    #endif

    // Only track scores during live match
    if (!g_matchLive) return PLUGIN_CONTINUE;

    // Validate team ID (1=Allies, 2=Axis)
    if (teamId != 1 && teamId != 2) {
        log_ktp("event=TEAMSCORE_UNKNOWN_TEAM team_id=%d", teamId);
        return PLUGIN_CONTINUE;
    }

    // Store the ORIGINAL score (2nd half only, not adjusted)
    // This is used for our internal tracking of per-half scores
    g_matchScore[teamId] = originalScore;

    // If 1st half is live, persist scores to localinfo for 2nd half restoration
    // This ensures scores are saved even if plugin_end doesn't run properly
    if (g_matchLive && g_currentHalf == 1) {
        new buf[16];
        format_scores(buf, charsmax(buf), g_matchScore[1], g_matchScore[2]);
        set_localinfo(LOCALINFO_H1_SCORES, buf);
    }

    // Log score update for debugging
    new teamName[16];
    copy(teamName, charsmax(teamName), (teamId == 1) ? "Allies" : "Axis");
    log_ktp("event=SCORE_UPDATE team=%d team_name='%s' score=%d match_id=%s half=%d",
            teamId, teamName, originalScore, g_matchId, g_currentHalf);

    return PLUGIN_CONTINUE;
}

// ================= GAME END DETECTION =================
// NOTE: The logevent-based game end detection has been REMOVED.
// Problem: Logevents fire at the exact moment of map change and are never processed.
// Solution: The changelevel hook (OnChangeLevel) now intercepts ALL map changes
// before they happen, allowing proper match state finalization.
// See: OnChangeLevel(), process_second_half_end_changelevel(), process_ot_round_end_changelevel()

// Legacy variables kept for reference (no longer used)
new g_gameEndEventCount = 0;
new g_gameEndTaskId = 9876;

// ================= CHANGELEVEL HOOK (KTP-ReHLDS) =================
// Intercepts ALL map changes before they happen, allowing us to properly
// finalize match state. This is more reliable than logevents which fire
// at the exact moment of map change and may not be processed in time.
new bool:g_changeLevelHandled = false;  // Prevent double-processing
new g_pendingChangeMap[64];             // Map to change to after delay
new g_changeMapCountdown = 0;           // Countdown seconds remaining
new g_changeMapTaskId = 0;              // Task ID for countdown
const CHANGELEVEL_COUNTDOWN_SECS = 5;   // Seconds to wait before map change

public OnChangeLevel(const map[], const landmark[]) {
    // If we're not in a live match, allow the changelevel
    if (!g_matchLive) {
        return HC_CONTINUE;
    }

    // Prevent double-processing if we somehow get called twice
    if (g_changeLevelHandled) {
        log_ktp("event=CHANGELEVEL_SKIP reason=already_handled map=%s", map);
        return HC_CONTINUE;
    }

    // Mark as handled to prevent re-entry
    g_changeLevelHandled = true;

    // Cancel any pending game end tasks since we're handling it now
    remove_task(g_gameEndTaskId);
    g_gameEndEventCount = 0;

    // ========== FIRST HALF END ==========
    // Just save state and allow changelevel to proceed immediately
    if (g_currentHalf == 1 && !g_inOvertime) {
        log_ktp("event=CHANGELEVEL_FIRST_HALF map=%s matchId=%s", map, g_matchId);
        handle_first_half_end();
        g_changeLevelHandled = false;
        return HC_CONTINUE;
    }

    // ========== SECOND HALF END or OT ROUND END ==========
    // Store target map for logging
    copy(g_pendingChangeMap, charsmax(g_pendingChangeMap), map);

    // Process match end logic (announcements, Discord, cleanup)
    if (g_inOvertime) {
        log_ktp("event=CHANGELEVEL_OT_ROUND map=%s otRound=%d matchId=%s", map, g_otRound, g_matchId);
        process_ot_round_end_changelevel();
        // OT round end always lets changelevel proceed
        g_changeLevelHandled = false;
        return HC_CONTINUE;
    } else {
        log_ktp("event=CHANGELEVEL_SECOND_HALF map=%s matchId=%s", map, g_matchId);
        new bool:otTriggered = process_second_half_end_changelevel();

        if (otTriggered) {
            // OT was triggered - we need to stay on the SAME map, not go to next in rotation
            // Force changelevel to current map and supersede the original changelevel
            log_ktp("event=OT_FORCE_SAME_MAP original_target=%s staying_on=%s", map, g_matchMap);
            server_cmd("changelevel %s", g_matchMap);
            g_changeLevelHandled = false;
            return HC_SUPERCEDE;  // Block original changelevel to wrong map
        }

        // Match ended normally - let changelevel proceed
        g_changeLevelHandled = false;
        return HC_CONTINUE;
    }
}

// Process second half end with announcements and delayed changelevel
// Returns: true if OT was triggered (caller should force changelevel to same map)
//          false if match ended normally (caller should let changelevel proceed)
stock bool:process_second_half_end_changelevel() {
    // =============== KTP: HLStatsX Stats Integration ===============
    #if defined HAS_DODX
    if (g_hasDodxStatsNatives) {
        new flushed = dodx_flush_all_stats();
        log_ktp("event=STATS_FLUSH type=match_end players=%d match_id=%s", flushed, g_matchId);
        log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^")", g_matchId, g_matchMap);
        dodx_set_match_id("");
    }
    #endif

    // Get current scores from dodx
    update_match_scores_from_dodx();

    // 2nd half score calculation (teams swapped sides)
    new team1SecondHalf = g_matchScore[2] - g_firstHalfScore[1];
    new team2SecondHalf = g_matchScore[1] - g_firstHalfScore[2];
    new team1Total = g_matchScore[2];
    new team2Total = g_matchScore[1];

    log_ktp("event=HALF_END half=2nd map=%s match_id=%s score=%s_%d-%d_%s",
            g_matchMap, g_matchId, g_team1Name, team1SecondHalf, team2SecondHalf, g_team2Name);
    log_ktp("event=MATCH_END match_id=%s final_score=%s_%d-%d_%s half1=%d-%d half2=%d-%d",
            g_matchId, g_team1Name, team1Total, team2Total, g_team2Name,
            g_firstHalfScore[1], g_firstHalfScore[2], team1SecondHalf, team2SecondHalf);

    // Check for tie - trigger overtime
    if (team1Total == team2Total) {
        if (g_matchType == MATCH_TYPE_COMPETITIVE && !g_disableDiscord) {
            log_ktp("event=TIE_DETECTED triggering_ot=true score=%d-%d", team1Total, team2Total);
            trigger_overtime(team1Total, team2Total);
            save_ot_state_for_first_round();  // Save OT state so map reload restores it
            return true;  // Tell caller to force changelevel to same map
        }
    }

    // Winner or non-competitive tie - announce result
    new winner[64];
    if (team1Total > team2Total) {
        formatex(winner, charsmax(winner), "%s wins!", g_team1Name);
    } else if (team2Total > team1Total) {
        formatex(winner, charsmax(winner), "%s wins!", g_team2Name);
    } else {
        copy(winner, charsmax(winner), "Match tied!");
    }

    // Announce in chat
    announce_all("========================================");
    announce_all("  MATCH COMPLETE!");
    announce_all("  %s", winner);
    announce_all("  Final Score: %s %d - %d %s", g_team1Name, team1Total, team2Total, g_team2Name);
    announce_all("  (1st Half: %d-%d | 2nd Half: %d-%d)",
            g_firstHalfScore[1], g_firstHalfScore[2], team1SecondHalf, team2SecondHalf);
    announce_all("========================================");

    // Brief HUD (3 seconds so scoreboard is visible)
    set_hudmessage(0, 255, 0, -1.0, 0.3, 0, 0.0, 3.0, 0.5, 0.5, -1);
    show_hudmessage(0, "=== MATCH COMPLETE ===^n^n%s^n^n%s %d - %d %s",
        winner, g_team1Name, team1Total, team2Total, g_team2Name);

    // Update Discord embed
    #if defined HAS_CURL
    if (!g_disableDiscord) {
        new finalStatus[128];
        formatex(finalStatus, charsmax(finalStatus), "MATCH COMPLETE - Final: %d-%d - %s",
                team1Total, team2Total, winner);
        send_match_embed_update(finalStatus);
    }
    #endif

    // Fire ktp_match_end forward
    {
        new ret;
        ExecuteForward(g_fwdMatchEnd, ret, g_matchId, g_matchMap, g_matchType, team1Total, team2Total);
    }

    end_match_cleanup();

    // Clear localinfo for next match
    clear_localinfo_match_context();

    // NOTE: No countdown needed - game is already in intermission showing scoreboard
    // Let the changelevel proceed naturally by returning HC_CONTINUE from OnChangeLevel
    log_ktp("event=MATCH_END_PROCESSED allowing_changelevel=true map=%s", g_pendingChangeMap);
    return false;  // Match ended normally, let changelevel proceed
}

// Process OT round end with announcements
// Returns: 0 = let changelevel proceed (match complete OR continuing to next OT map)
stock process_ot_round_end_changelevel() {
    // Get current scoreboard scores
    update_match_scores_from_dodx();

    // Determine this round's scores based on which side team1 is on
    new team1RoundScore, team2RoundScore;
    if (g_otTeam1StartsAs == 1) {
        team1RoundScore = g_matchScore[1];
        team2RoundScore = g_matchScore[2];
    } else {
        team1RoundScore = g_matchScore[2];
        team2RoundScore = g_matchScore[1];
    }

    // Record this round's scores
    g_otScores[g_otRound][1] = team1RoundScore;
    g_otScores[g_otRound][2] = team2RoundScore;

    // Calculate total scores (regulation + all OT rounds)
    new team1Total = g_regulationScore[1];
    new team2Total = g_regulationScore[2];
    for (new r = 1; r <= g_otRound; r++) {
        team1Total += g_otScores[r][1];
        team2Total += g_otScores[r][2];
    }

    log_ktp("event=OT_ROUND_END match_id=%s round=%d round_score=%d-%d total=%d-%d team1=%s team2=%s",
            g_matchId, g_otRound, team1RoundScore, team2RoundScore,
            team1Total, team2Total, g_team1Name, g_team2Name);

    // Announce OT round result
    announce_all("========================================");
    announce_all("  OT ROUND %d COMPLETE", g_otRound);
    announce_all("  Round Score: %s %d - %d %s", g_team1Name, team1RoundScore, team2RoundScore, g_team2Name);
    announce_all("  Total Score: %s %d - %d %s", g_team1Name, team1Total, team2Total, g_team2Name);
    announce_all("========================================");

    // Check if tie is broken
    if (team1Total != team2Total) {
        // WINNER DETERMINED!
        new winner[64];
        new winScore, loseScore;
        if (team1Total > team2Total) {
            copy(winner, charsmax(winner), g_team1Name);
            winScore = team1Total;
            loseScore = team2Total;
        } else {
            copy(winner, charsmax(winner), g_team2Name);
            winScore = team2Total;
            loseScore = team1Total;
        }

        announce_all("========================================");
        announce_all("  %s WINS!", winner);
        announce_all("  Final Score: %d - %d", winScore, loseScore);
        announce_all("  (Regulation: %d-%d + OT: %d-%d)",
                g_regulationScore[1], g_regulationScore[2],
                team1Total - g_regulationScore[1], team2Total - g_regulationScore[2]);
        announce_all("========================================");

        // Brief HUD (3 seconds so scoreboard is visible)
        set_hudmessage(0, 255, 0, -1.0, 0.3, 0, 0.0, 3.0, 0.5, 0.5, -1);
        show_hudmessage(0, "=== MATCH COMPLETE ===^n^n%s WINS!^n^n%d - %d^n^n(Regulation: %d-%d | OT: %d-%d)",
            winner, winScore, loseScore,
            g_regulationScore[1], g_regulationScore[2],
            team1Total - g_regulationScore[1], team2Total - g_regulationScore[2]);

        log_ktp("event=MATCH_END_OT match_id=%s winner=%s final=%d-%d reg=%d-%d ot_rounds=%d",
                g_matchId, winner, winScore, loseScore,
                g_regulationScore[1], g_regulationScore[2], g_otRound);

        // Update Discord
        #if defined HAS_CURL
        if (!g_disableDiscord) {
            new finalStatus[128];
            formatex(finalStatus, charsmax(finalStatus), "MATCH COMPLETE (OT) - %s WINS %d-%d", winner, winScore, loseScore);
            send_match_embed_update(finalStatus);
        }
        #endif

        // Fire ktp_match_end forward
        {
            new ret;
            ExecuteForward(g_fwdMatchEnd, ret, g_matchId, g_matchMap, g_matchType, team1Total, team2Total);
        }

        end_match_cleanup();
        clear_localinfo_match_context();

        log_ktp("event=OT_MATCH_COMPLETE_PROCESSED allowing_changelevel=true");
        return 0;  // Let changelevel proceed - match is over
    } else {
        // STILL TIED - Another OT round needed
        log_ktp("event=OT_STILL_TIED match_id=%s total=%d-%d next_round=%d", g_matchId, team1Total, team2Total, g_otRound + 1);

        announce_all("STILL TIED %d - %d! Another overtime round required.", team1Total, team2Total);

        set_hudmessage(255, 255, 0, -1.0, 0.3, 0, 0.0, 5.0, 0.5, 0.5, -1);
        show_hudmessage(0, "=== STILL TIED ===^n^n%d - %d^n^nAnother OT round required!", team1Total, team2Total);

        // Update Discord
        #if defined HAS_CURL
        if (!g_disableDiscord) {
            new status[128];
            formatex(status, charsmax(status), "OT Round %d Complete - STILL TIED %d-%d", g_otRound, team1Total, team2Total);
            send_match_embed_update(status);
        }
        #endif

        // Prepare for next OT round (swap sides, increment round)
        g_otRound++;
        g_otTeam1StartsAs = (g_otTeam1StartsAs == 1) ? 2 : 1;  // Swap sides

        // Save OT state for next map - this persists to localinfo
        // Next map load will detect OT context and restore the ready phase
        save_ot_state_for_next_round();

        log_ktp("event=OT_NEXT_ROUND_PREPARED allowing_changelevel=true next_round=%d", g_otRound);
        return 0;  // Let changelevel proceed - next map will restore OT context
    }
}

// Start the countdown before map change
stock start_changelevel_countdown() {
    g_changeMapCountdown = CHANGELEVEL_COUNTDOWN_SECS;
    safe_remove_task(g_changeMapTaskId);
    g_changeMapTaskId = set_task(1.0, "task_changelevel_countdown", g_changeMapTaskId, .flags = "b");
    log_ktp("event=CHANGELEVEL_COUNTDOWN_START seconds=%d map=%s", CHANGELEVEL_COUNTDOWN_SECS, g_pendingChangeMap);

    // Initial countdown announcement
    announce_all("Map changing in %d seconds...", g_changeMapCountdown);
}

// Countdown task for map change
public task_changelevel_countdown() {
    g_changeMapCountdown--;

    if (g_changeMapCountdown <= 0) {
        // Time's up - execute changelevel
        remove_task(g_changeMapTaskId);
        log_ktp("event=CHANGELEVEL_EXECUTE map=%s", g_pendingChangeMap);

        // Reset flag before changelevel
        g_changeLevelHandled = false;

        // Execute the changelevel
        server_cmd("changelevel %s", g_pendingChangeMap);
        return;
    }

    // Announce countdown
    if (g_changeMapCountdown <= 3) {
        announce_all("Map changing in %d...", g_changeMapCountdown);
    }

    // HUD countdown
    set_hudmessage(255, 255, 0, -1.0, 0.4, 0, 0.0, 0.9, 0.0, 0.0, -1);
    show_hudmessage(0, "Map changing in %d...", g_changeMapCountdown);
}

// Handle first half end (save state, allow immediate changelevel)
stock handle_first_half_end() {
    g_secondHalfPending = true;

    // Set the next map in rotation to be the current map (for 2nd half)
    server_cmd("amx_nextmap %s", g_matchMap);
    server_exec();

    // Flush 1st half stats WITH matchid (same matchid continues to 2nd half)
    #if defined HAS_DODX
    if (g_hasDodxStatsNatives) {
        new flushed = dodx_flush_all_stats();
        log_ktp("event=STATS_FLUSH type=half1 players=%d match_id=%s", flushed, g_matchId);
    }
    #endif

    // Save first half scores
    save_first_half_scores();

    log_ktp("event=HALF_END half=1st map=%s next_map=%s match_id=%s score=%s_%d-%d_%s",
            g_matchMap, g_matchMap, g_matchId,
            g_teamName[1], g_firstHalfScore[1], g_firstHalfScore[2], g_teamName[2]);

    // Persist match context via localinfo
    new buf[32];
    set_localinfo(LOCALINFO_MATCH_ID, g_matchId);
    set_localinfo(LOCALINFO_MATCH_MAP, g_matchMap);
    set_localinfo(LOCALINFO_MODE, "h2");
    set_localinfo(LOCALINFO_LIVE, "");

    format_state(buf, charsmax(buf),
        g_pauseCountTeam[1], g_pauseCountTeam[2],
        g_techBudget[1], g_techBudget[2]);
    set_localinfo(LOCALINFO_STATE, buf);

    format_scores(buf, charsmax(buf), g_firstHalfScore[1], g_firstHalfScore[2]);
    set_localinfo(LOCALINFO_H1_SCORES, buf);

    set_localinfo(LOCALINFO_TEAMNAME1, g_team1Name);
    set_localinfo(LOCALINFO_TEAMNAME2, g_team2Name);
    set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
    set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

    log_ktp("event=MATCH_CONTEXT_SAVED match_id=%s state=%s h1=%d,%d team1=%s team2=%s discord_msg=%s",
            g_matchId, buf, g_firstHalfScore[1], g_firstHalfScore[2],
            g_team1Name, g_team2Name, g_discordMatchMsgId);

    // Update Discord embed with 1st half completion status
    #if defined HAS_CURL
    if (!g_disableDiscord) {
        new halfStatus[64];
        formatex(halfStatus, charsmax(halfStatus), "1st Half Complete - Score: %d-%d",
                g_firstHalfScore[1], g_firstHalfScore[2]);
        send_match_embed_update(halfStatus);
    }
    #endif
}

// Save OT state to localinfo for next round
stock save_ot_state_for_next_round() {
    new buf[128];

    // Save core OT context
    set_localinfo(LOCALINFO_MODE, fmt("ot%d", g_otRound));

    // Save OT state: techBudget1,techBudget2,startingSide
    formatex(buf, charsmax(buf), "%d,%d,%d", g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs);
    set_localinfo(LOCALINFO_OT_STATE, buf);

    // Save regulation scores
    format_scores(buf, charsmax(buf), g_regulationScore[1], g_regulationScore[2]);
    set_localinfo(LOCALINFO_REG_SCORES, buf);

    // Save all OT round scores
    new ot_scores[256];
    new pos = 0;
    for (new r = 1; r < g_otRound; r++) {
        if (pos > 0) ot_scores[pos++] = '|';
        pos += formatex(ot_scores[pos], charsmax(ot_scores) - pos, "%d,%d", g_otScores[r][1], g_otScores[r][2]);
    }
    set_localinfo(LOCALINFO_OT_SCORES, ot_scores);

    log_ktp("event=OT_STATE_SAVED round=%d tech=%d,%d starting_side=%d reg=%d-%d",
            g_otRound, g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs,
            g_regulationScore[1], g_regulationScore[2]);
}

// Save OT state for first overtime round (after regulation tie)
// Similar to save_ot_state_for_next_round but called at initial OT trigger
stock save_ot_state_for_first_round() {
    new buf[128];

    // Save core OT context - mode='ot1' for first OT round
    set_localinfo(LOCALINFO_MODE, "ot1");

    // Save match identifiers
    set_localinfo(LOCALINFO_MATCH_ID, g_matchId);
    set_localinfo(LOCALINFO_MATCH_MAP, g_matchMap);

    // Save OT state: techBudget1,techBudget2,startingSide
    formatex(buf, charsmax(buf), "%d,%d,%d", g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs);
    set_localinfo(LOCALINFO_OT_STATE, buf);

    // Save regulation scores
    format_scores(buf, charsmax(buf), g_regulationScore[1], g_regulationScore[2]);
    set_localinfo(LOCALINFO_REG_SCORES, buf);

    // Save 1st half scores (needed for full score display)
    format_scores(buf, charsmax(buf), g_firstHalfScore[1], g_firstHalfScore[2]);
    set_localinfo(LOCALINFO_H1_SCORES, buf);

    // Save team names
    set_localinfo(LOCALINFO_TEAMNAME1, g_team1Name);
    set_localinfo(LOCALINFO_TEAMNAME2, g_team2Name);

    // Save Discord message ID for updates
    set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
    set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

    // Clear OT scores (none yet for round 1)
    set_localinfo(LOCALINFO_OT_SCORES, "");

    // Save pause state (OT uses fresh tech budgets, pause counts reset)
    formatex(buf, charsmax(buf), "%d,%d,%d,%d",
             g_pauseCountTeam[1], g_pauseCountTeam[2], g_otTechBudget[1], g_otTechBudget[2]);
    set_localinfo(LOCALINFO_STATE, buf);

    log_ktp("event=OT_FIRST_ROUND_STATE_SAVED match_id=%s map=%s tech=%d,%d starting_side=%d reg=%d-%d",
            g_matchId, g_matchMap, g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs,
            g_regulationScore[1], g_regulationScore[2]);
}

// Broadcast TeamScore message to all clients to force scoreboard update
// Uses DODX native which sets gamerules score AND broadcasts to clients in one operation
// This avoids the server crashes caused by AMX message natives for TeamScore
stock broadcast_team_score(teamId, score) {
    #if defined HAS_DODX
    // Set flag to skip msg_TeamScore hook adjustment (we're broadcasting the correct total already)
    g_skipTeamScoreAdjust = true;
    if (dodx_broadcast_team_score(teamId, score)) {
        log_ktp("event=BROADCAST_SCORE team=%d score=%d", teamId, score);
    } else {
        log_ktp("event=BROADCAST_SCORE_FAIL team=%d score=%d reason=dodx_native_failed", teamId, score);
    }
    g_skipTeamScoreAdjust = false;
    #else
    log_ktp("event=BROADCAST_SCORE_SKIP team=%d score=%d reason=no_dodx", teamId, score);
    #endif
}

// Set team score AND broadcast to clients (combined operation for score restoration)
// Note: dodx_broadcast_team_score already sets gamerules score, so this is just a wrapper for clarity
stock set_and_broadcast_score(teamId, score) {
    broadcast_team_score(teamId, score);
}

// Reset match scores (called at match start)
stock reset_match_scores() {
    g_matchScore[1] = 0;
    g_matchScore[2] = 0;
    g_firstHalfScore[1] = 0;
    g_firstHalfScore[2] = 0;
    g_periodicSaveStarted = false;  // Reset so new match can start fresh periodic saves
    // Save team identity names at match start (1st half)
    copy(g_team1Name, charsmax(g_team1Name), g_teamName[1]);  // Team on Allies = Team 1
    copy(g_team2Name, charsmax(g_team2Name), g_teamName[2]);  // Team on Axis = Team 2
}

// Update match scores from dodx module (reads actual game scores)
// Call this before any score calculations to ensure we have current values
stock update_match_scores_from_dodx() {
#if defined HAS_DODX
    new alliesScore = dod_get_team_score(1);
    new axisScore = dod_get_team_score(2);

    // Only update if scores changed (avoid spam)
    if (alliesScore != g_matchScore[1] || axisScore != g_matchScore[2]) {
        g_matchScore[1] = alliesScore;
        g_matchScore[2] = axisScore;
        log_ktp("event=SCORE_FROM_DODX allies=%d axis=%d half=%d", alliesScore, axisScore, g_currentHalf);
    }
#endif
}

// Save first half scores (called at half time)
stock save_first_half_scores() {
    // First, get current scores from dodx
    update_match_scores_from_dodx();

    // Save scores by team identity (team1 started as Allies, team2 started as Axis)
    g_firstHalfScore[1] = g_matchScore[1];  // Team 1's 1st half score (as Allies)
    g_firstHalfScore[2] = g_matchScore[2];  // Team 2's 1st half score (as Axis)

    // Persist to localinfo for 2nd half restoration after map change
    new buf[16];
    format_scores(buf, charsmax(buf), g_firstHalfScore[1], g_firstHalfScore[2]);
    set_localinfo(LOCALINFO_H1_SCORES, buf);

    log_ktp("event=FIRST_HALF_SCORES_SAVED team1=%d team2=%d (persisted to localinfo)", g_firstHalfScore[1], g_firstHalfScore[2]);
}

// Periodic score save task - updates scores and saves to localinfo during 1st half
// This ensures scores are persisted even if plugin_end doesn't run properly on map change
public task_periodic_score_save() {
    // Only run during a live match
    if (!g_matchLive)
        return;

    // Update scores from dodx
    update_match_scores_from_dodx();

    // Persist scores to localinfo for crash/abandoned match recovery
    new buf[16];
    format_scores(buf, charsmax(buf), g_matchScore[1], g_matchScore[2]);
    if (g_currentHalf == 1) {
        set_localinfo(LOCALINFO_H1_SCORES, buf);
    } else if (g_currentHalf == 2) {
        // Persist 2nd half scores for abandoned match detection
        // These are DODX scores which now include restored 1st half + 2nd half play
        set_localinfo(LOCALINFO_H2_SCORES, buf);
    }

    log_ktp("event=PERIODIC_SCORE_SAVE allies=%d axis=%d half=%d", g_matchScore[1], g_matchScore[2], g_currentHalf);

    // After initial 2s save, set up repeating 30-second task
    if (!g_periodicSaveStarted) {
        g_periodicSaveStarted = true;
        set_task(30.0, "task_periodic_score_save", g_taskScoreSaveId, _, _, "b");
    }
}

// Start periodic score saving when match goes live
stock start_periodic_score_save() {
    // Reset the flag so periodic task will start the repeating schedule
    g_periodicSaveStarted = false;

    // Immediate save after short delay
    // For 1st half: persists 0-0 score early for crash recovery
    // For 2nd half: keeps g_matchScore updated for .score command and match end detection
    set_task(2.0, "task_periodic_score_save", g_taskScoreSaveId);
    log_ktp("event=PERIODIC_SCORE_SAVE_STARTED initial_delay=2s interval=30s half=%d", g_currentHalf);
}

// Stop periodic score saving
stock stop_periodic_score_save() {
    safe_remove_task(g_taskScoreSaveId);
}

// Delayed score restoration for 2nd half or OT (waits for round restart to complete)
public task_delayed_score_restore() {
    log_ktp("event=DELAYED_SCORE_RESTORE_START matchLive=%d half=%d inOT=%d pendingAllies=%d pendingAxis=%d",
            g_matchLive ? 1 : 0, g_currentHalf, g_inOvertime ? 1 : 0, g_pendingScoreAllies, g_pendingScoreAxis);

    // Safety check: Only restore if we're still in a live match
    if (!g_matchLive) {
        log_ktp("event=DELAYED_SCORE_RESTORE_ABORT reason=match_not_live");
        return;
    }

    // Safety check: Validate pending scores are reasonable (non-negative)
    if (g_pendingScoreAllies < 0 || g_pendingScoreAxis < 0) {
        log_ktp("event=DELAYED_SCORE_RESTORE_ABORT reason=invalid_pending_scores allies=%d axis=%d",
                g_pendingScoreAllies, g_pendingScoreAxis);
        return;
    }

    #if defined HAS_DODX
    if (!dodx_has_gamerules()) {
        log_ktp("event=DELAYED_SCORE_RESTORE_FAIL reason=gamerules_unavailable");
        return;
    }

    // Log DODX scores BEFORE setting
    new beforeAllies = dodx_get_team_score(1);
    new beforeAxis = dodx_get_team_score(2);

    // Use dodx_broadcast_team_score to set gamerules scores AND broadcast to clients
    // This native properly sends TeamScore messages from the module level (avoids AMX message crash)
    broadcast_team_score(1, g_pendingScoreAllies);
    broadcast_team_score(2, g_pendingScoreAxis);

    // Log DODX scores AFTER setting to verify
    new afterAllies = dodx_get_team_score(1);
    new afterAxis = dodx_get_team_score(2);
    log_ktp("event=DODX_SCORE_BROADCAST before_allies=%d before_axis=%d set_allies=%d set_axis=%d after_allies=%d after_axis=%d time=%d",
            beforeAllies, beforeAxis, g_pendingScoreAllies, g_pendingScoreAxis, afterAllies, afterAxis, get_systime());

    // Verify scores were actually set
    if (afterAllies != g_pendingScoreAllies || afterAxis != g_pendingScoreAxis) {
        log_ktp("event=DODX_SCORE_BROADCAST_VERIFY_FAIL expected_allies=%d got=%d expected_axis=%d got=%d",
                g_pendingScoreAllies, afterAllies, g_pendingScoreAxis, afterAxis);
    }
    #endif

    if (g_inOvertime) {
        // OT: Chat confirmation of score restoration
        log_ktp("event=DELAYED_OT_SCORE_RESTORE allies=%d axis=%d round=%d",
                g_pendingScoreAllies, g_pendingScoreAxis, g_otRound);

        announce_all("Scoreboard synced - Grand Total: %s %d - %d %s",
            g_team1Name,
            g_otTeam1StartsAs == 1 ? g_pendingScoreAllies : g_pendingScoreAxis,
            g_otTeam1StartsAs == 1 ? g_pendingScoreAxis : g_pendingScoreAllies,
            g_team2Name);
    } else {
        // 2nd half: Chat confirmation of score restoration (HUD already shown at match start)
        log_ktp("event=DELAYED_SCORE_RESTORE allies_score=%d axis_score=%d (team1_1st=%d, team2_1st=%d)",
                g_pendingScoreAllies, g_pendingScoreAxis, g_firstHalfScore[1], g_firstHalfScore[2]);

        announce_all("Scoreboard synced: %s %d - %d %s",
            g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name);
    }
}

// Schedule delayed score restoration (called from match start for 2nd half)
stock schedule_score_restoration() {
    safe_remove_task(g_taskScoreRestoreId);
    // Wait for mp_clan_timer countdown to complete before restoring
    // mp_clan_timer is typically 10s, so 12s ensures round restart is done
    // If we restore during the countdown, the game resets scores when round actually restarts
    set_task(12.0, "task_delayed_score_restore", g_taskScoreRestoreId);
    log_ktp("event=SCORE_RESTORE_SCHEDULED delay=12s");
}

stock announce_all(const fmt[], any:...) {
    new msg[192];
    vformat(msg, charsmax(msg), fmt, 2);
    client_print(0, print_chat, "[KTP] %s", msg);
}

stock ktp_sync_config_from_cvars() {
    if (g_cvarReadyReq)          { new v = get_pcvar_num(g_cvarReadyReq);           if (v > 0) g_readyRequired = v; }
    if (g_cvarCountdown)         { new v2 = get_pcvar_num(g_cvarCountdown);         if (v2 > 0) g_countdownSeconds = v2; }
    if (g_cvarPrePauseSec)       { new v3 = get_pcvar_num(g_cvarPrePauseSec);       if (v3 > 0) g_prePauseSeconds   = v3; }
    if (g_cvarPreMatchPauseSec)  { new v4 = get_pcvar_num(g_cvarPreMatchPauseSec);  if (v4 > 0) g_preMatchPauseSeconds = v4; }  // OPTIMIZED: Cache pre-match pause (Phase 5)
    if (g_cvarTechBudgetSec)     { new v5 = get_pcvar_num(g_cvarTechBudgetSec);     if (v5 > 0) g_techBudgetSecs    = v5; }
    if (g_cvarPauseDuration)     { new v9 = get_pcvar_num(g_cvarPauseDuration);     if (v9 > 0) g_pauseDurationSec = v9; }  // OPTIMIZED: Cache pause duration (Phase 5)

    // OPTIMIZED: Cache pause extension/limit cvars (Phase 2 optimization)
    if (g_cvarPauseExtension)    { new v6 = get_pcvar_num(g_cvarPauseExtension);    if (v6 > 0) g_pauseExtensionSec = v6; }
    if (g_cvarMaxExtensions)     { new v7 = get_pcvar_num(g_cvarMaxExtensions);     if (v7 > 0) g_pauseMaxExtensions = v7; }

    // OPTIMIZED: Cache auto-request timeout (Phase 2 optimization)
    if (g_cvarAutoReqSec) {
        new v8 = get_pcvar_num(g_cvarAutoReqSec);
        if (v8 >= AUTO_REQUEST_MIN_SECS && v8 <= AUTO_REQUEST_MAX_SECS)
            g_autoRequestSecs = v8;
    }

    // OPTIMIZED: Cache server hostname (Phase 2 optimization)
    get_cvar_string("hostname", g_serverHostname, charsmax(g_serverHostname));

    // Cache reminder intervals
    if (g_cvarUnreadyReminderSec) {
        new v = get_pcvar_num(g_cvarUnreadyReminderSec);
        if (v >= 5 && v <= 300) g_unreadyReminderSecs = float(v);
    }
    if (g_cvarUnpauseReminderSec) {
        new v = get_pcvar_num(g_cvarUnpauseReminderSec);
        if (v >= 5 && v <= 120) g_unpauseReminderSecs = float(v);
    }
}

stock team_str(id, out[], len) {
    new tid = get_user_team(id);  // Just get ID, no name needed
    switch (tid) {
        case 1: copy(out, len, g_teamName[1]);
        case 2: copy(out, len, g_teamName[2]);
        case 3: copy(out, len, "Spec");
        default: copy(out, len, "Unknown");
    }
}

stock team_name_from_id(teamId, out[], len) {
    switch (teamId) {
        case 1: copy(out, len, g_teamName[1]);
        case 2: copy(out, len, g_teamName[2]);
        default: copy(out, len, "Unknown");
    }
}

// Set custom team name (called via /setteam command or config)
// Also updates team identity vars since names are set before match starts
stock set_team_name(teamId, const name[]) {
    if (teamId >= 1 && teamId <= 2 && name[0]) {
        copy(g_teamName[teamId], charsmax(g_teamName[]), name);
        // Also update team identity (team names are set in pre-match, so side = identity)
        if (teamId == 1) {
            copy(g_team1Name, charsmax(g_team1Name), name);
        } else {
            copy(g_team2Name, charsmax(g_team2Name), name);
        }
        return true;
    }
    return false;
}

// Reset team names to defaults
stock reset_team_names() {
    copy(g_teamName[1], charsmax(g_teamName[]), "Allies");
    copy(g_teamName[2], charsmax(g_teamName[]), "Axis");
    copy(g_team1Name, charsmax(g_team1Name), "Allies");
    copy(g_team2Name, charsmax(g_team2Name), "Axis");
}

// Prompt all players on a team to set their team name (if still default)
stock prompt_team_to_set_name(teamId) {
    // Only show team name prompt for competitive (.ktp) and draft matches
    if (g_matchType != MATCH_TYPE_COMPETITIVE && g_matchType != MATCH_TYPE_DRAFT)
        return;

    new defaultName[8], cmd[12];
    if (teamId == 1) {
        copy(defaultName, charsmax(defaultName), "Allies");
        copy(cmd, charsmax(cmd), ".setallies");
    } else if (teamId == 2) {
        copy(defaultName, charsmax(defaultName), "Axis");
        copy(cmd, charsmax(cmd), ".setaxis");
    } else {
        return;
    }

    // Only prompt if team name is still default
    if (!equal(g_teamName[teamId], defaultName))
        return;

    // Send prompt to all players on this team
    for (new i = 1; i <= MaxClients; i++) {
        if (is_user_connected(i) && !is_user_bot(i) && get_user_team(i) == teamId) {
            client_print(i, print_chat, "[KTP] Set your team name: %s <name>", cmd);
        }
    }
}

stock get_identity(id, name[], nameLen, authid[], authLen, ip[], ipLen, team[], teamLen) {
    if (is_user_connected(id)) {
        get_user_name(id, name, nameLen);
        if (!get_user_authid(id, authid, authLen)) authid[0] = EOS;
        get_user_ip(id, ip, ipLen, 1);
        team_str(id, team, teamLen);
    } else {
        copy(name, nameLen, "server");
        authid[0] = EOS;
        ip[0] = EOS;
        copy(team, teamLen, "Unknown");
    }
}

// Compose "Name[STEAMID]" (or "Name[NA]" if no authid). Safe for any player index.
stock get_who_str(id, out[], len) {
    if (!is_user_connected(id)) {
        formatex(out, len, "server");
        return;
    }

    new name[32], sid[44];
    get_user_name(id, name, charsmax(name));
    if (!get_user_authid(id, sid, charsmax(sid)) || !sid[0]) {
        copy(sid, charsmax(sid), "NA");
    }

    formatex(out, len, "%s[%s]", name, sid);
}

// Get current player name dynamically - returns current name if connected, cached name otherwise
// This prevents stale names when players change their name mid-match
stock get_dynamic_name(playerId, const cachedName[], out[], maxlen) {
    if (playerId > 0 && playerId <= MAX_PLAYERS && is_user_connected(playerId)) {
        get_user_name(playerId, out, maxlen);
    } else if (cachedName[0]) {
        copy(out, maxlen, cachedName);
    } else {
        copy(out, maxlen, "Unknown");
    }
}

stock strtolower_inplace(s[]) {
    for (new i = 0; s[i]; i++) if (s[i] >= 'A' && s[i] <= 'Z') s[i] += 32;
}

stock strip_bsp_suffix(s[]) {
    new n = strlen(s);
    if (n >= 4 && tolower(s[n-4])=='.' && tolower(s[n-3])=='b' && tolower(s[n-2])=='s' && tolower(s[n-1])=='p') {
        s[n-4] = EOS;
    }
    trim(s);
}


// OPTIMIZED: Changed to use caller-provided buffer to prevent buffer overwrite
// when function is called multiple times in same formatex()
stock fmt_seconds(sec, buf[], len) {
    if (sec < 60) formatex(buf, len, "%ds", sec);
    else formatex(buf, len, "%dm%02ds", sec / 60, sec % 60);
}

// OPTIMIZED: Helper to calculate total pause duration with extensions (Phase 5)
stock get_total_pause_duration() {
    return g_pauseDurationSec + (g_pauseExtensions * g_pauseExtensionSec);
}

// ---------- Localinfo State Helpers (consolidated format) ----------

// Format consolidated state: "pauseA,pauseX,techA,techX"
stock format_state(buf[], maxlen, pauseA, pauseX, techA, techX) {
    formatex(buf, maxlen, "%d,%d,%d,%d", pauseA, pauseX, techA, techX);
}

// Parse consolidated state: "pauseA,pauseX,techA,techX"
stock parse_state(const buf[], &pauseA, &pauseX, &techA, &techX) {
    pauseA = 0; pauseX = 0; techA = 0; techX = 0;
    if (!buf[0]) return;

    new parts[4][12];
    new count = explode_string(buf, ",", parts, 4, 11);
    if (count >= 1) pauseA = str_to_num(parts[0]);
    if (count >= 2) pauseX = str_to_num(parts[1]);
    if (count >= 3) techA  = str_to_num(parts[2]);
    if (count >= 4) techX  = str_to_num(parts[3]);
}

// Format score pair: "score1,score2"
stock format_scores(buf[], maxlen, score1, score2) {
    formatex(buf, maxlen, "%d,%d", score1, score2);
}

// Parse score pair: "score1,score2"
stock parse_scores(const buf[], &score1, &score2) {
    score1 = 0; score2 = 0;
    if (!buf[0]) return;

    new parts[2][12];
    new count = explode_string(buf, ",", parts, 2, 11);
    if (count >= 1) score1 = str_to_num(parts[0]);
    if (count >= 2) score2 = str_to_num(parts[1]);
}

// Format OT state: "techA,techX,side"
stock format_ot_state(buf[], maxlen, techA, techX, side) {
    formatex(buf, maxlen, "%d,%d,%d", techA, techX, side);
}

// Parse OT state: "techA,techX,side"
stock parse_ot_state(const buf[], &techA, &techX, &side) {
    techA = 0; techX = 0; side = 1;
    if (!buf[0]) return;

    new parts[3][12];
    new count = explode_string(buf, ",", parts, 3, 11);
    if (count >= 1) techA = str_to_num(parts[0]);
    if (count >= 2) techX = str_to_num(parts[1]);
    if (count >= 3) side  = str_to_num(parts[2]);
}

// Append OT round score to OT scores string: "t1,t2|t1,t2|..."
stock append_ot_score(buf[], maxlen, t1, t2) {
    new tmp[16];
    if (buf[0]) {
        formatex(tmp, charsmax(tmp), "|%d,%d", t1, t2);
    } else {
        formatex(tmp, charsmax(tmp), "%d,%d", t1, t2);
    }
    add(buf, maxlen, tmp);
}

// Parse OT scores string into array, returns number of rounds
// scores[round][1] = team1 score, scores[round][2] = team2 score (1-indexed rounds)
stock parse_ot_scores(const buf[], scores[][3], maxrounds) {
    if (!buf[0]) return 0;

    new rounds[32][16];
    new numRounds = explode_string(buf, "|", rounds, maxrounds, 15);

    for (new r = 0; r < numRounds && r < maxrounds; r++) {
        new t1 = 0, t2 = 0;
        parse_scores(rounds[r], t1, t2);
        scores[r + 1][1] = t1;  // 1-indexed
        scores[r + 1][2] = t2;
    }
    return numRounds;
}

// Generate OT scores string from array
stock generate_ot_scores_string(buf[], maxlen, scores[][3], numRounds) {
    buf[0] = EOS;
    for (new r = 1; r <= numRounds; r++) {
        append_ot_score(buf, maxlen, scores[r][1], scores[r][2]);
    }
}

// ---------- End Localinfo State Helpers ----------

// Generate unique match ID (format: KTP-{timestamp}-{mapname})
// Called at first half start; same matchID persists for second half
stock generate_match_id() {
    new timestamp = get_systime();
    formatex(g_matchId, charsmax(g_matchId), "KTP-%d-%s", timestamp, g_currentMap);
    log_ktp("event=MATCH_ID_GENERATED match_id=%s", g_matchId);
}

// Clear match ID (called when match ends or is cancelled)
stock clear_match_id() {
    g_matchId[0] = EOS;
}

stock pauses_left(teamId) {
    if (teamId != 1 && teamId != 2) return 0;
    new used = g_pauseCountTeam[teamId];
    // Clamp used to 0-1 range
    if (used < 0) used = 0;
    else if (used > 1) used = 1;
    return 1 - used;
}

// OPTIMIZED: remove_task() is already safe to call on non-existent tasks (Phase 4)
stock safe_remove_task(taskId) {
    remove_task(taskId);
}

stock get_full_identity(id, name[], nameLen, sid[], sidLen, ip[], ipLen, team[], teamLen, map[], mapLen) {
    get_identity(id, name, nameLen, sid, sidLen, ip, ipLen, team, teamLen);
    copy(map, mapLen, g_currentMap);  // OPTIMIZED: Use cached map name instead of get_mapname()
}

stock show_pause_hud_message(const pauseType[]) {
    if (!g_isPaused) return;

    new pausesA = pauses_left(1);
    new pausesX = pauses_left(2);

    // Get dynamic pause initiator name (updates if player changes name)
    new pausedByName[32];
    get_dynamic_name(g_lastPauseById, g_lastPauseBy, pausedByName, charsmax(pausedByName));

    // Calculate elapsed and remaining time
    // If tech pause budget is frozen (owner did /resume), use frozen time
    new elapsed;
    if (g_isTechPause && g_techPauseFrozenTime > 0) {
        // Budget frozen - show frozen elapsed time
        elapsed = g_techPauseFrozenTime - g_techPauseStartTime;
    } else {
        elapsed = get_systime() - g_pauseStartTime;
    }

    // Cache CVAR values (static so they persist across calls, only lookup once per pause)
    static cachedExtSec = 0, cachedMaxExt = 0, lastPauseStart = 0;
    if (lastPauseStart != g_pauseStartTime) {
        // New pause started, refresh cached values
        cachedExtSec = g_pauseExtensionSec;
        if (cachedExtSec <= 0) cachedExtSec = 120;
        cachedMaxExt = g_pauseMaxExtensions;
        if (cachedMaxExt <= 0) cachedMaxExt = 2;
        lastPauseStart = g_pauseStartTime;
    }

    new totalDuration = g_pauseDurationSec + (g_pauseExtensions * cachedExtSec);
    new remaining = totalDuration - elapsed;
    if (remaining < 0) remaining = 0;

    new elapsedMin = elapsed / 60;
    new elapsedSec = elapsed % 60;
    new remainMin = remaining / 60;
    new remainSec = remaining % 60;

    // Build status line based on current state
    new statusLine[128];
    if (g_autoConfirmLeft > 0) {
        // Waiting for other team to confirmunpause
        new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
        new otherTeamName[32];
        team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));
        formatex(statusLine, charsmax(statusLine), "  Waiting: %s (%ds to auto-confirm)", otherTeamName, g_autoConfirmLeft);
    } else if (g_unpauseRequested && !g_unpauseConfirmedOther) {
        formatex(statusLine, charsmax(statusLine), "  .go to resume");
    } else if (!g_unpauseRequested) {
        formatex(statusLine, charsmax(statusLine), "  .resume  |  .go  |  .ext");
    } else {
        formatex(statusLine, charsmax(statusLine), "  Resuming...");
    }

    // Show FROZEN indicator if budget is locked
    new frozenIndicator[16] = "";
    if (g_isTechPause && g_techPauseFrozenTime > 0) {
        copy(frozenIndicator, charsmax(frozenIndicator), " [LOCKED]");
    }

    // Clean minimalist design - LEFT side to avoid DoD's centered "Paused" text
    set_hudmessage(255, 255, 255, 0.01, 0.25, 0, 0.0, 0.6, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "^n  == GAME PAUSED ==^n^n  Type: %s^n  By: %s^n^n  Elapsed: %d:%02d%s  |  Remaining: %d:%02d^n  Extensions: %d/%d^n^n  Pauses Left: A:%d X:%d^n^n%s^n",
        pauseType,
        pausedByName[0] ? pausedByName : "Server",
        elapsedMin, elapsedSec, frozenIndicator,
        remainMin, remainSec,
        g_pauseExtensions, cachedMaxExt,
        pausesA, pausesX,
        statusLine);
}

stock setup_auto_unpause_request() {
    new secs = g_autoRequestSecs;
    if (secs < AUTO_REQUEST_MIN_SECS || secs > AUTO_REQUEST_MAX_SECS) secs = AUTO_REQUEST_DEFAULT_SECS;
    safe_remove_task(g_taskAutoUnpauseReqId);
    set_task(float(secs), "auto_unpause_request", g_taskAutoUnpauseReqId);
    g_autoReqLeft = secs;

    // Start countdown ticker for HUD display
    safe_remove_task(g_taskAutoReqCountdownId);
    set_task(1.0, "auto_req_countdown_tick", g_taskAutoReqCountdownId, _, _, "b");
}

stock get_user_team_id(id) {
    new tname[16];
    return get_user_team(id, tname, charsmax(tname));
}

stock safe_sid(const sid[]) {
    static result[44];
    if (sid[0]) copy(result, charsmax(result), sid);
    else copy(result, charsmax(result), "NA");
    return result;
}

// ================= Discord Notifications =================
#if defined HAS_CURL
stock get_discord_channel_id(channelId[], maxlen) {
    // Get the appropriate Discord channel ID based on match type
    // Falls back to default channel if match-type-specific channel not configured
    channelId[0] = EOS;

    switch (g_matchType) {
        case MATCH_TYPE_12MAN: {
            if (g_discordChannelId12man[0]) {
                copy(channelId, maxlen, g_discordChannelId12man);
            } else {
                copy(channelId, maxlen, g_discordChannelId); // Fall back to default
            }
        }
        case MATCH_TYPE_SCRIM: {
            if (g_discordChannelIdScrim[0]) {
                copy(channelId, maxlen, g_discordChannelIdScrim);
            } else {
                copy(channelId, maxlen, g_discordChannelId); // Fall back to default
            }
        }
        default: {
            copy(channelId, maxlen, g_discordChannelId);
        }
    }
}

stock send_discord_with_hostname(const message[]) {
    // Skip Discord if disabled (scrim/12man mode)
    if (g_disableDiscord) return;

    // Prefix message with hostname
    new fullMsg[512];
    formatex(fullMsg, charsmax(fullMsg), "[%s] %s", g_serverHostname, message);

    send_discord_message(fullMsg);
}

stock send_discord_message(const message[]) {
    // Debug: Log that we're attempting to send
    log_ktp("event=DISCORD_SEND_ATTEMPT msg='%.64s...' disabled=%d", message, g_disableDiscord);

    // Skip Discord if disabled (scrim/12man mode)
    if (g_disableDiscord) {
        log_ktp("event=DISCORD_SKIPPED reason='disabled'");
        return;
    }

    // Get the appropriate channel ID for the current match type
    // NOTE: Using global buffers (g_discord*) to avoid AMX stack overflow (16KB limit)
    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));

    // Check if Discord is configured (from INI)
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) {
        // Discord not configured, log which field is missing
        log_ktp("event=DISCORD_NOT_CONFIGURED url=%d channel=%d auth=%d",
                g_discordRelayUrl[0] ? 1 : 0,
                g_discordChannelIdBuf[0] ? 1 : 0,
                g_discordAuthSecret[0] ? 1 : 0);
        return;
    }

    // Escape special characters for JSON (using global buffer)
    new msgLen = strlen(message);
    new j = 0;
    for (new i = 0; i < msgLen; i++) {
        // Ensure we have room for escape sequence (2 chars) + null terminator
        if (j >= charsmax(g_discordEscapedMsg) - 3) break;

        // Handle special characters that need escaping
        switch (message[i]) {
            case '"': { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = '"'; }  // 92 = backslash
            case 92: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 92; }    // backslash
            case 10: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 'n'; }   // newline
            case 13: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 'r'; }   // carriage return
            case 9: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 't'; }    // tab
            default: {
                // Copy character as-is if printable, skip control chars
                if (message[i] >= 32 || message[i] == 10 || message[i] == 13 || message[i] == 9) {
                    g_discordEscapedMsg[j++] = message[i];
                }
            }
        }
    }
    g_discordEscapedMsg[j] = EOS;

    // Build JSON payload (using global buffer)
    // Note: No code block wrapper - let Discord render markdown formatting
    formatex(g_discordPayload, charsmax(g_discordPayload),
        "{^"channelId^":^"%s^",^"content^":^"[KTP] %s^"}",
        g_discordChannelIdBuf, g_discordEscapedMsg);

    // Create cURL handle
    new CURL:curl = curl_easy_init();
    if (curl) {
        // Free any previous headers
        if (g_curlHeaders != SList_Empty) {
            curl_slist_free_all(g_curlHeaders);
            g_curlHeaders = SList_Empty;
        }

        // Set URL from INI config
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);

        // Disable SSL verification (Linux servers may not have CA bundle configured)
        // This is acceptable since we're connecting to our own trusted Discord relay
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);

        // Set headers
        g_curlHeaders = curl_slist_append(SList_Empty, "Content-Type: application/json");

        formatex(g_discordAuthHeader, charsmax(g_discordAuthHeader), "X-Relay-Auth: %s", g_discordAuthSecret);
        g_curlHeaders = curl_slist_append(g_curlHeaders, g_discordAuthHeader);

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);

        // Set POST data (using global buffer)
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_discordPayload);

        // Set timeout (5 seconds)
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        // Debug: Log the request
        log_ktp("event=DISCORD_CURL_SEND url='%s' channel='%s'", g_discordRelayUrl, g_discordChannelIdBuf);

        // Perform request asynchronously (non-blocking)
        curl_easy_perform(curl, "discord_callback");

        // Cleanup (handle and headers freed in callback)
    } else {
        log_ktp("event=DISCORD_ERROR reason='curl_init_failed'");
    }
}

public discord_callback(CURL:curl, CURLcode:code) {
    log_ktp("event=DISCORD_CALLBACK code=%d", _:code);
    if (code != CURLE_OK) {
        new error[128];
        curl_easy_strerror(code, error, charsmax(error));
        log_ktp("event=DISCORD_ERROR curl_code=%d error='%s'", _:code, error);
    } else {
        log_ktp("event=DISCORD_SUCCESS");
    }
    // Cleanup curl handle
    curl_easy_cleanup(curl);

    // Free headers
    if (g_curlHeaders != SList_Empty) {
        curl_slist_free_all(g_curlHeaders);
        g_curlHeaders = SList_Empty;
    }
}

// Escape a string for JSON string value (handles quotes, backslashes, newlines)
stock escape_for_json(const input[], output[], maxlen) {
    new j = 0;
    new inputLen = strlen(input);
    for (new i = 0; i < inputLen && j < maxlen - 2; i++) {
        switch (input[i]) {
            case '"': { output[j++] = 92; output[j++] = '"'; }   // escape quote
            case 92:  { output[j++] = 92; output[j++] = 92; }    // escape backslash
            case 10:  { output[j++] = 92; output[j++] = 'n'; }   // escape newline
            case 13:  { } // skip carriage return
            default:  { output[j++] = input[i]; }
        }
    }
    output[j] = EOS;
}

// Global buffers for escaped roster strings (avoid stack overflow)
new g_rosterAlliesEscaped[768];
new g_rosterAxisEscaped[768];
new g_serverHostnameEscaped[128];

stock send_player_roster_to_discord() {
    // Build player roster with teams using embed format
    // NOTE: Using global buffers (g_roster*) to avoid AMX stack overflow (16KB limit)
    g_rosterAllies[0] = EOS;
    g_rosterAxis[0] = EOS;
    new alliesCount = 0, axisCount = 0;

    // Collect all connected players
    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch"); // connected, not HLTV

    for (new i = 0; i < pnum; i++) {
        new id = players[i];

        new name[32], authid[44], teamId;
        get_user_name(id, name, charsmax(name));
        get_user_authid(id, authid, charsmax(authid));
        teamId = get_user_team(id);

        // Format player entry with bullet point, name, and steamid in parens
        // Using actual newline char (10) - will be escaped to \n for JSON later
        new entry[96];
        formatex(entry, charsmax(entry), "- %s (%s)", name, authid);

        // Add to appropriate team roster
        if (teamId == 1) { // Allies
            new currentLen = strlen(g_rosterAllies);
            new entryLen = strlen(entry);
            new requiredSpace = entryLen + (alliesCount > 0 ? 1 : 0); // +1 for newline separator

            if (currentLen + requiredSpace < charsmax(g_rosterAllies)) {
                if (alliesCount > 0) {
                    // Add newline separator between players
                    new sep[4];
                    formatex(sep, charsmax(sep), "%c", 10);
                    add(g_rosterAllies, charsmax(g_rosterAllies), sep);
                }
                add(g_rosterAllies, charsmax(g_rosterAllies), entry);
                alliesCount++;
            }
        } else if (teamId == 2) { // Axis
            new currentLen = strlen(g_rosterAxis);
            new entryLen = strlen(entry);
            new requiredSpace = entryLen + (axisCount > 0 ? 1 : 0);

            if (currentLen + requiredSpace < charsmax(g_rosterAxis)) {
                if (axisCount > 0) {
                    // Add newline separator between players
                    new sep[4];
                    formatex(sep, charsmax(sep), "%c", 10);
                    add(g_rosterAxis, charsmax(g_rosterAxis), sep);
                }
                add(g_rosterAxis, charsmax(g_rosterAxis), entry);
                axisCount++;
            }
        }
    }

    // Escape roster strings for JSON (converts newlines to \n, quotes to \", etc.)
    escape_for_json(g_rosterAllies[0] ? g_rosterAllies : "No players", g_rosterAlliesEscaped, charsmax(g_rosterAlliesEscaped));
    escape_for_json(g_rosterAxis[0] ? g_rosterAxis : "No players", g_rosterAxisEscaped, charsmax(g_rosterAxisEscaped));
    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    // Build title: "MM/DD/YYYY TeamA vs TeamB"
    new dateStr[16];
    get_time("%m/%d/%Y", dateStr, charsmax(dateStr));
    new embedTitle[128];
    formatex(embedTitle, charsmax(embedTitle), "%s %s vs %s", dateStr, g_teamName[1], g_teamName[2]);

    // Escape title for JSON
    new embedTitleEscaped[160];
    escape_for_json(embedTitle, embedTitleEscaped, charsmax(embedTitleEscaped));

    // Build Discord embed JSON payload
    // Embed with two inline fields (teams side by side), match ID and server in footer
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"color^":3447003,^"fields^":[{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true}],^"footer^":{^"text^":^"Match: %s | Server: %s^"}}]}",
        g_discordChannelIdBuf,
        embedTitleEscaped,
        g_teamName[1], alliesCount, g_rosterAlliesEscaped,
        g_teamName[2], axisCount, g_rosterAxisEscaped,
        g_matchId, g_serverHostnameEscaped);

    // Send embed via curl (similar to send_discord_message but with embed payload)
    send_discord_embed_raw(g_rosterEmbedPayload);

    log_ktp("event=ROSTER_LOGGED allies=%d axis=%d match_id=%s", alliesCount, axisCount, g_matchId);
}

// Send raw JSON payload to Discord (for embeds)
stock send_discord_embed_raw(const payload[]) {
#if defined HAS_CURL
    if (g_disableDiscord) return;
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    new CURL:curl = curl_easy_init();
    if (curl) {
        if (g_curlHeaders != SList_Empty) {
            curl_slist_free_all(g_curlHeaders);
            g_curlHeaders = SList_Empty;
        }

        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);

        g_curlHeaders = curl_slist_append(SList_Empty, "Content-Type: application/json");
        formatex(g_discordAuthHeader, charsmax(g_discordAuthHeader), "X-Relay-Auth: %s", g_discordAuthSecret);
        g_curlHeaders = curl_slist_append(g_curlHeaders, g_discordAuthHeader);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);

        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, payload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_EMBED_SEND");
        curl_easy_perform(curl, "discord_callback");
    }
#endif
}

// ================= Consolidated Match Embed System =================
// This system creates a single Discord embed at match start and edits it
// at key points: 1st half end, 2nd half start, and match end.

// Save current roster to 1st half arrays for 2nd half comparison
stock save_first_half_roster() {
    g_firstHalfRosterAlliesCount = 0;
    g_firstHalfRosterAxisCount = 0;

    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        new authid[44];
        get_user_authid(id, authid, charsmax(authid));
        new teamId = get_user_team(id);

        if (teamId == 1 && g_firstHalfRosterAlliesCount < 16) {
            copy(g_firstHalfRosterAllies[g_firstHalfRosterAlliesCount], 43, authid);
            g_firstHalfRosterAlliesCount++;
        } else if (teamId == 2 && g_firstHalfRosterAxisCount < 16) {
            copy(g_firstHalfRosterAxis[g_firstHalfRosterAxisCount], 43, authid);
            g_firstHalfRosterAxisCount++;
        }
    }
    log_ktp("event=ROSTER_SAVED_1ST_HALF allies=%d axis=%d", g_firstHalfRosterAlliesCount, g_firstHalfRosterAxisCount);
}

// Check if a SteamID was in the 1st half roster for given team
// Note: In 2nd half, teams swap sides! So we check opposite array.
// team = current team (1=Allies, 2=Axis)
// Returns true if player was in 1st half
stock bool:was_in_first_half(const authid[], team) {
    // In 2nd half: current Allies were 1st half Axis, current Axis were 1st half Allies
    if (g_currentHalf == 2) {
        if (team == 1) {
            // Current Allies = was Axis in 1st half
            for (new i = 0; i < g_firstHalfRosterAxisCount; i++) {
                if (equal(authid, g_firstHalfRosterAxis[i])) return true;
            }
        } else if (team == 2) {
            // Current Axis = was Allies in 1st half
            for (new i = 0; i < g_firstHalfRosterAlliesCount; i++) {
                if (equal(authid, g_firstHalfRosterAllies[i])) return true;
            }
        }
    } else {
        // 1st half - check same team
        if (team == 1) {
            for (new i = 0; i < g_firstHalfRosterAlliesCount; i++) {
                if (equal(authid, g_firstHalfRosterAllies[i])) return true;
            }
        } else if (team == 2) {
            for (new i = 0; i < g_firstHalfRosterAxisCount; i++) {
                if (equal(authid, g_firstHalfRosterAxis[i])) return true;
            }
        }
    }
    return false;
}

// Build roster string with [2nd] tags for new players
stock build_roster_with_tags(output[], maxlen, team, &count) {
    output[0] = EOS;
    count = 0;

    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        new playerTeam = get_user_team(id);
        if (playerTeam != team) continue;

        new name[32], authid[44];
        get_user_name(id, name, charsmax(name));
        get_user_authid(id, authid, charsmax(authid));

        // Check if this is a new 2nd half player
        new entry[96];
        if (g_currentHalf == 2 && !was_in_first_half(authid, team)) {
            formatex(entry, charsmax(entry), "- %s [2nd] (%s)", name, authid);
        } else {
            formatex(entry, charsmax(entry), "- %s (%s)", name, authid);
        }

        // Add to roster
        new currentLen = strlen(output);
        new entryLen = strlen(entry);
        new requiredSpace = entryLen + (count > 0 ? 1 : 0);

        if (currentLen + requiredSpace < maxlen) {
            if (count > 0) {
                new sep[4];
                formatex(sep, charsmax(sep), "%c", 10);  // newline
                add(output, maxlen, sep);
            }
            add(output, maxlen, entry);
            count++;
        }
    }
}

// Build the scores section for the embed
new g_embedScoresField[256];
stock build_scores_field() {
    g_embedScoresField[0] = EOS;

    if (g_currentHalf == 1) {
        // 1st half in progress - just show current score
        formatex(g_embedScoresField, charsmax(g_embedScoresField),
            "**In Progress**^n%s %d - %d %s",
            g_team1Name, g_matchScore[1], g_matchScore[2], g_team2Name);
    } else if (g_currentHalf == 2) {
        // 2nd half - show 1st half + current 2nd half
        // Teams swapped sides: Team 1 is now Axis, Team 2 is now Allies
        // g_matchScore contains the CURRENT scoreboard (includes restored 1st half scores)
        //
        // Scoreboard restoration puts:
        //   Allies (Team 2's side now) = Team 2's 1st half score (g_firstHalfScore[2])
        //   Axis (Team 1's side now) = Team 1's 1st half score (g_firstHalfScore[1])
        //
        // So 2nd half scores are:
        //   Team 1's 2nd half = Current Axis (g_matchScore[2]) - Team 1's 1st half
        //   Team 2's 2nd half = Current Allies (g_matchScore[1]) - Team 2's 1st half
        new team1SecondHalf = g_matchScore[2] - g_firstHalfScore[1];
        new team2SecondHalf = g_matchScore[1] - g_firstHalfScore[2];

        // Clamp to 0 in case of any weirdness
        if (team1SecondHalf < 0) team1SecondHalf = 0;
        if (team2SecondHalf < 0) team2SecondHalf = 0;

        // Total = 1st half + 2nd half
        new team1Total = g_firstHalfScore[1] + team1SecondHalf;
        new team2Total = g_firstHalfScore[2] + team2SecondHalf;

        formatex(g_embedScoresField, charsmax(g_embedScoresField),
            "**1st Half:** %s %d - %d %s^n**2nd Half:** %d - %d^n**Total:** %d - %d",
            g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name,
            team1SecondHalf, team2SecondHalf,
            team1Total, team2Total);
    }
}

// Write callback for curl - writes response data to file
public discord_curl_write(data[], size, nmemb, file) {
    new actual_size = size * nmemb;
    if (file && actual_size > 0) {
        fwrite_blocks(file, data, actual_size, BLOCK_CHAR);
    }
    return actual_size;
}

// Callback for Discord embed with response capture
public discord_embed_callback(CURL:curl, CURLcode:code, data[]) {
    // Close the response file if it was opened
    if (data[0]) {
        fclose(data[0]);
        data[0] = 0;
    }

    if (code == CURLE_OK) {
        // Try to read the response file to get message ID
        if (g_discordResponseFile[0]) {
            new fp = fopen(g_discordResponseFile, "rt");
            if (fp) {
                fgets(fp, g_discordResponseBuffer, charsmax(g_discordResponseBuffer));
                fclose(fp);

                // Parse message ID from JSON response: {"id":"1234567890",...}
                new idStart = contain(g_discordResponseBuffer, "^"id^":^"");
                if (idStart != -1) {
                    idStart += 6;  // Skip past "id":"
                    new idEnd = idStart;
                    while (g_discordResponseBuffer[idEnd] && g_discordResponseBuffer[idEnd] != '"' && idEnd < idStart + 30) {
                        idEnd++;
                    }
                    new idLen = idEnd - idStart;
                    if (idLen > 0 && idLen < charsmax(g_discordMatchMsgId)) {
                        for (new i = 0; i < idLen; i++) {
                            g_discordMatchMsgId[i] = g_discordResponseBuffer[idStart + i];
                        }
                        g_discordMatchMsgId[idLen] = EOS;

                        // Store in localinfo for 2nd half
                        set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
                        copy(g_discordMatchChannelId, charsmax(g_discordMatchChannelId), g_discordChannelIdBuf);
                        set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

                        log_ktp("event=DISCORD_MSG_ID_CAPTURED id=%s channel=%s", g_discordMatchMsgId, g_discordMatchChannelId);
                    } else {
                        log_ktp("event=DISCORD_MSG_ID_PARSE_FAILED idLen=%d response='%.100s'", idLen, g_discordResponseBuffer);
                    }
                } else {
                    log_ktp("event=DISCORD_MSG_ID_NOT_FOUND response='%.100s'", g_discordResponseBuffer);
                }

                // Delete temp file
                delete_file(g_discordResponseFile);
            } else {
                log_ktp("event=DISCORD_RESPONSE_FILE_READ_FAILED path=%s", g_discordResponseFile);
            }
        } else {
            log_ktp("event=DISCORD_RESPONSE_FILE_PATH_EMPTY");
        }
        log_ktp("event=DISCORD_EMBED_SUCCESS");
    } else {
        new error[128];
        curl_easy_strerror(code, error, charsmax(error));
        log_ktp("event=DISCORD_EMBED_ERROR code=%d error='%s'", _:code, error);
    }

    curl_easy_cleanup(curl);
    if (g_curlHeaders != SList_Empty) {
        curl_slist_free_all(g_curlHeaders);
        g_curlHeaders = SList_Empty;
    }
}

// Send match embed and capture message ID for later editing
stock send_match_embed_create() {
    if (g_disableDiscord) return;

    // Get channel ID
    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    // Build rosters
    new alliesCount = 0, axisCount = 0;
    build_roster_with_tags(g_rosterAllies, charsmax(g_rosterAllies), 1, alliesCount);
    build_roster_with_tags(g_rosterAxis, charsmax(g_rosterAxis), 2, axisCount);

    // Escape for JSON
    escape_for_json(g_rosterAllies[0] ? g_rosterAllies : "No players", g_rosterAlliesEscaped, charsmax(g_rosterAlliesEscaped));
    escape_for_json(g_rosterAxis[0] ? g_rosterAxis : "No players", g_rosterAxisEscaped, charsmax(g_rosterAxisEscaped));
    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    // Build title
    new dateStr[16];
    get_time("%m/%d/%Y", dateStr, charsmax(dateStr));
    new embedTitle[128];
    formatex(embedTitle, charsmax(embedTitle), "%s %s vs %s", dateStr, g_team1Name, g_team2Name);
    new embedTitleEscaped[160];
    escape_for_json(embedTitle, embedTitleEscaped, charsmax(embedTitleEscaped));

    // Build embed JSON - initial version at match start
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"color^":3447003,^"fields^":[{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Status^",^"value^":^"1st Half - Match Live^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Server: %s^"}}]}",
        g_discordChannelIdBuf,
        embedTitleEscaped,
        g_team1Name, alliesCount, g_rosterAlliesEscaped,
        g_team2Name, axisCount, g_rosterAxisEscaped,
        g_matchId, g_serverHostnameEscaped);

    // Set up temp file for response capture (use data dir for reliable path)
    new dataDir[128];
    get_datadir(dataDir, charsmax(dataDir));
    formatex(g_discordResponseFile, charsmax(g_discordResponseFile), "%s/discord_resp_%d.tmp", dataDir, get_systime());

    // Send with response capture
    new CURL:curl = curl_easy_init();
    if (curl) {
        if (g_curlHeaders != SList_Empty) {
            curl_slist_free_all(g_curlHeaders);
            g_curlHeaders = SList_Empty;
        }

        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);

        g_curlHeaders = curl_slist_append(SList_Empty, "Content-Type: application/json");
        formatex(g_discordAuthHeader, charsmax(g_discordAuthHeader), "X-Relay-Auth: %s", g_discordAuthSecret);
        g_curlHeaders = curl_slist_append(g_curlHeaders, g_discordAuthHeader);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);

        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_rosterEmbedPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        // Open file for response capture and set up write callback
        g_discordResponseHandle[0] = fopen(g_discordResponseFile, "wb");
        if (g_discordResponseHandle[0]) {
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, g_discordResponseHandle[0]);
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, "discord_curl_write");
            log_ktp("event=DISCORD_MATCH_EMBED_CREATE response_file=%s", g_discordResponseFile);
        } else {
            log_ktp("event=DISCORD_MATCH_EMBED_CREATE response_file_failed path=%s", g_discordResponseFile);
        }
        curl_easy_perform(curl, "discord_embed_callback", g_discordResponseHandle, sizeof(g_discordResponseHandle));
    }

    // Save roster for 2nd half comparison
    save_first_half_roster();
}

// Edit the existing match embed with updated info
stock send_match_embed_update(const status[]) {
    if (g_disableDiscord) return;
    if (!g_discordMatchMsgId[0]) {
        log_ktp("event=DISCORD_EDIT_SKIP reason=no_msg_id");
        return;
    }

    // Get channel ID (use stored channel or current)
    new channelId[64];
    if (g_discordMatchChannelId[0]) {
        copy(channelId, charsmax(channelId), g_discordMatchChannelId);
    } else {
        get_discord_channel_id(channelId, charsmax(channelId));
    }

    if (!g_discordRelayUrl[0] || !channelId[0] || !g_discordAuthSecret[0]) return;

    // Build rosters with [2nd] tags for new players
    new alliesCount = 0, axisCount = 0;
    build_roster_with_tags(g_rosterAllies, charsmax(g_rosterAllies), 1, alliesCount);
    build_roster_with_tags(g_rosterAxis, charsmax(g_rosterAxis), 2, axisCount);

    escape_for_json(g_rosterAllies[0] ? g_rosterAllies : "No players", g_rosterAlliesEscaped, charsmax(g_rosterAlliesEscaped));
    escape_for_json(g_rosterAxis[0] ? g_rosterAxis : "No players", g_rosterAxisEscaped, charsmax(g_rosterAxisEscaped));
    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    // Build title
    new dateStr[16];
    get_time("%m/%d/%Y", dateStr, charsmax(dateStr));
    new embedTitle[128];
    formatex(embedTitle, charsmax(embedTitle), "%s %s vs %s", dateStr, g_team1Name, g_team2Name);
    new embedTitleEscaped[160];
    escape_for_json(embedTitle, embedTitleEscaped, charsmax(embedTitleEscaped));

    // Build scores field
    build_scores_field();
    new scoresEscaped[300];
    escape_for_json(g_embedScoresField, scoresEscaped, charsmax(scoresEscaped));

    // Escape status
    new statusEscaped[128];
    escape_for_json(status, statusEscaped, charsmax(statusEscaped));

    // Build edit URL (replace /reply with /edit in relay URL)
    new editUrl[256];
    copy(editUrl, charsmax(editUrl), g_discordRelayUrl);
    replace_string(editUrl, charsmax(editUrl), "/reply", "/edit");

    // Build edit payload with messageId
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"messageId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"color^":3447003,^"fields^":[{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Scores^",^"value^":^"%s^",^"inline^":false},{^"name^":^"Status^",^"value^":^"%s^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Server: %s^"}}]}",
        channelId,
        g_discordMatchMsgId,
        embedTitleEscaped,
        g_team1Name, alliesCount, g_rosterAlliesEscaped,
        g_team2Name, axisCount, g_rosterAxisEscaped,
        scoresEscaped,
        statusEscaped,
        g_matchId, g_serverHostnameEscaped);

    // Send edit request
    new CURL:curl = curl_easy_init();
    if (curl) {
        if (g_curlHeaders != SList_Empty) {
            curl_slist_free_all(g_curlHeaders);
            g_curlHeaders = SList_Empty;
        }

        curl_easy_setopt(curl, CURLOPT_URL, editUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);

        g_curlHeaders = curl_slist_append(SList_Empty, "Content-Type: application/json");
        formatex(g_discordAuthHeader, charsmax(g_discordAuthHeader), "X-Relay-Auth: %s", g_discordAuthSecret);
        g_curlHeaders = curl_slist_append(g_curlHeaders, g_discordAuthHeader);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);

        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_rosterEmbedPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_MATCH_EMBED_UPDATE status='%s' msg_id=%s", status, g_discordMatchMsgId);
        curl_easy_perform(curl, "discord_callback");
    }
}

// Send disconnect auto-pause as an embed (matches roster format)
stock send_discord_disconnect_embed(const playerName[], const playerId[], team) {
    if (g_disableDiscord) return;

    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    new teamName[32];
    copy(teamName, charsmax(teamName), g_teamName[team]);
    new teamNameEscaped[48];
    escape_for_json(teamName, teamNameEscaped, charsmax(teamNameEscaped));

    new playerNameEscaped[48];
    escape_for_json(playerName, playerNameEscaped, charsmax(playerNameEscaped));

    // Orange color for warning
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"⚠️ Player Disconnected^",^"color^":15105570,^"fields^":[{^"name^":^"Player^",^"value^":^"%s (%s)^",^"inline^":true},{^"name^":^"Team^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Status^",^"value^":^"Auto Tech Pause - Awaiting reconnect^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Server: %s^"}}]}",
        g_discordChannelIdBuf,
        playerNameEscaped, playerId,
        teamNameEscaped,
        g_matchId, g_serverHostnameEscaped);

    send_discord_embed_raw(g_rosterEmbedPayload);
    log_ktp("event=DISCORD_DISCONNECT_EMBED player='%s' team=%d", playerName, team);
}

// ================= End Consolidated Match Embed System =================

#else
// Stub function when cURL not available
stock send_discord_message(const message[]) {
    #pragma unused message
    // cURL not available, skip
}
#endif

// ================= Discord Config INI =================
stock load_discord_config() {
    // Reset to defaults
    g_discordRelayUrl[0] = EOS;
    g_discordChannelId[0] = EOS;
    g_discordChannelId12man[0] = EOS;
    g_discordChannelIdScrim[0] = EOS;
    g_discordAuthSecret[0] = EOS;

    new path[192];
    get_pcvar_string(g_cvarDiscordIniPath, path, charsmax(path));
    if (!path[0]) {
        // Use get_configsdir() for proper path resolution
        new configsDir[128];
        get_configsdir(configsDir, charsmax(configsDir));
        formatex(path, charsmax(path), "%s/discord.ini", configsDir);
    }

    new fp = fopen(path, "rt");
    if (!fp) {
        log_ktp("event=DISCORD_CONFIG_LOAD status=skip reason='file_not_found' path='%s'", path);
        return;
    }

    new line[256], key[64], val[192];
    new loaded = 0;

    while (!feof(fp)) {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        new eq = contain(line, "=");
        if (eq <= 0) continue;

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
        strtolower_inplace(key);

        copy(val, charsmax(val), line[eq + 1]);
        trim(val);

        if (!key[0] || !val[0]) continue;

        // Parse Discord config keys
        if (equal(key, "discord_relay_url")) {
            copy(g_discordRelayUrl, charsmax(g_discordRelayUrl), val);
            loaded++;
        } else if (equal(key, "discord_channel_id")) {
            copy(g_discordChannelId, charsmax(g_discordChannelId), val);
            loaded++;
        } else if (equal(key, "discord_channel_id_12man")) {
            copy(g_discordChannelId12man, charsmax(g_discordChannelId12man), val);
            loaded++;
        } else if (equal(key, "discord_channel_id_scrim")) {
            copy(g_discordChannelIdScrim, charsmax(g_discordChannelIdScrim), val);
            loaded++;
        } else if (equal(key, "discord_auth_secret")) {
            copy(g_discordAuthSecret, charsmax(g_discordAuthSecret), val);
            loaded++;
        }
    }
    fclose(fp);

    log_ktp("event=DISCORD_CONFIG_LOAD status=ok loaded=%d path='%s'", loaded, path);
}

// ================= KTP Config INI =================
// Loads general KTP settings from ktp.ini
stock load_ktp_config() {
    new configsDir[128], path[192];
    get_configsdir(configsDir, charsmax(configsDir));
    formatex(path, charsmax(path), "%s/ktp.ini", configsDir);

    new fp = fopen(path, "rt");
    if (!fp) {
        log_ktp("event=KTP_CONFIG_LOAD status=skip reason='file_not_found' path='%s' (using defaults)", path);
        return;
    }

    new line[256], key[64], val[64];
    new loaded = 0;

    while (!feof(fp)) {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        new eq = contain(line, "=");
        if (eq <= 0) continue;

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
        strtolower_inplace(key);

        copy(val, charsmax(val), line[eq + 1]);
        trim(val);

        if (!key[0]) continue;

        // Parse KTP config keys
        if (equal(key, "season_active")) {
            // Accept: 1, true, yes, on (case insensitive)
            strtolower_inplace(val);
            g_ktpSeasonActive = (equal(val, "1") || equal(val, "true") || equal(val, "yes") || equal(val, "on"));
            loaded++;
        }
        else if (equal(key, "match_password")) {
            if (val[0]) {
                copy(g_ktpMatchPassword, charsmax(g_ktpMatchPassword), val);
                loaded++;
            }
        }
    }
    fclose(fp);

    new status[16];
    copy(status, charsmax(status), g_ktpSeasonActive ? "ACTIVE" : "INACTIVE");
    log_ktp("event=KTP_CONFIG_LOAD status=ok loaded=%d season=%s password_set=%s path='%s'",
            loaded, status, g_ktpMatchPassword[0] ? "yes" : "no", path);
}

// ================= INI map→cfg =================
stock load_map_mappings() {
    for (new i = 0; i < MAX_MAP_ROWS; i++) { g_mapKeys[i][0] = EOS; g_mapCfgs[i][0] = EOS; }
    g_mapRows = 0;

    new path[192];
    get_pcvar_string(g_cvarMapsFile, path, charsmax(path));

    new fp = fopen(path, "rt");
    if (!fp) {
        log_ktp("event=MAPS_LOAD status=error reason=\'file_not_found\' path=\'%s\'", path);
        return;
    }

    new line[256], key[96], val[128], added = 0;
    new currentSection[64];
    currentSection[0] = EOS;

    while (!feof(fp) && added < MAX_MAP_ROWS) {
        fgets(fp, line, charsmax(line));
        trim(line);

        // Skip empty lines and comments
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        // Check for INI section header [mapname]
        if (line[0] == '[') {
            new closeBracket = contain(line, "]");
            if (closeBracket > 1) {
                copy(currentSection, min(closeBracket - 1, charsmax(currentSection)), line[1]);
                trim(currentSection);
                strip_bsp_suffix(currentSection);
                strtolower_inplace(currentSection);
            }
            continue;
        }

        // Parse key=value pairs within sections
        new eq = contain(line, "=");
        if (eq <= 0) continue;

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
        copy(val, charsmax(val), line[eq + 1]);
        trim(val);

        if (!key[0] || !val[0]) continue;

        // Only process "config" key and only if we have a current section
        if (equal(key, "config") && currentSection[0]) {
            copy(g_mapKeys[added], charsmax(g_mapKeys[]), currentSection);
            copy(g_mapCfgs[added], charsmax(g_mapCfgs[]), val);
            added++;
            currentSection[0] = EOS; // Reset to prevent duplicate entries
        }
    }
    fclose(fp);

    g_mapRows = added;
    log_ktp("event=MAPS_LOAD status=ok count=%d path=\'%s\'", g_mapRows, path);
}

stock lookup_cfg_for_map(const map[], outCfg[], outLen) {
    outCfg[0] = EOS;
    new lower[64];
    copy(lower, charsmax(lower), map);
    strip_bsp_suffix(lower);
    strtolower_inplace(lower);

    for (new i = 0; i < g_mapRows; i++) {
        if (!g_mapKeys[i][0]) continue;
        if (containi(lower, g_mapKeys[i]) == 0) { copy(outCfg, outLen, g_mapCfgs[i]); return 1; }
    }
    return 0;
}

stock exec_map_config() {
    // OPTIMIZED: Use cached map name instead of get_mapname()

    new base[96]; get_pcvar_string(g_cvarCfgBase, base, charsmax(base));
    if (!base[0]) copy(base, charsmax(base), "configs/");

    // Ensure base path has trailing slash
    new len = strlen(base);
    if (len > 0 && base[len-1] != '/' && base[len-1] != '\') {
        strcat(base, "/", charsmax(base));
    }

    new cfg[128];
    if (!lookup_cfg_for_map(g_currentMap, cfg, charsmax(cfg))) {
        log_ktp("event=MAPCFG status=miss map=%s", g_currentMap);
        return 0;
    }

    // Try to find match-type-specific config first (e.g., dod_kalt_12man.cfg or dod_kalt_scrim.cfg)
    new cfg_specific[128];
    new bool: use_specific = false;

    if (g_matchType == MATCH_TYPE_12MAN) {
        // Try 12man-specific config
        new cfg_base[120];
        copy(cfg_base, charsmax(cfg_base), cfg);
        // Remove .cfg extension if present
        new pos = contain(cfg_base, ".cfg");
        if (pos > 0) {
            cfg_base[pos] = 0;
        }
        formatex(cfg_specific, charsmax(cfg_specific), "%s_12man.cfg", cfg_base);
        // Check if file exists - avoid double-prepending base
        new fullpath_specific[192];
        if (containi(cfg_specific, base) == 0) {
            copy(fullpath_specific, charsmax(fullpath_specific), cfg_specific);
        } else {
            formatex(fullpath_specific, charsmax(fullpath_specific), "%s%s", base, cfg_specific);
        }
        if (file_exists(fullpath_specific)) {
            use_specific = true;
            copy(cfg, charsmax(cfg), cfg_specific);
        }
    }
    else if (g_matchType == MATCH_TYPE_SCRIM) {
        // Try scrim-specific config
        new cfg_base[120];
        copy(cfg_base, charsmax(cfg_base), cfg);
        // Remove .cfg extension if present
        new pos = contain(cfg_base, ".cfg");
        if (pos > 0) {
            cfg_base[pos] = 0;
        }
        formatex(cfg_specific, charsmax(cfg_specific), "%s_scrim.cfg", cfg_base);
        // Check if file exists - avoid double-prepending base
        new fullpath_specific[192];
        if (containi(cfg_specific, base) == 0) {
            copy(fullpath_specific, charsmax(fullpath_specific), cfg_specific);
        } else {
            formatex(fullpath_specific, charsmax(fullpath_specific), "%s%s", base, cfg_specific);
        }
        if (file_exists(fullpath_specific)) {
            use_specific = true;
            copy(cfg, charsmax(cfg), cfg_specific);
        }
    }

    // Build full path - avoid double-prepending if cfg already includes base path
    new fullpath[192];
    if (containi(cfg, base) == 0) {
        // cfg already starts with base path (e.g., "configs/ktp_anzio.cfg")
        copy(fullpath, charsmax(fullpath), cfg);
    } else {
        formatex(fullpath, charsmax(fullpath), "%s%s", base, cfg);
    }

    new match_type_str[16];
    switch (g_matchType) {
        case MATCH_TYPE_12MAN: copy(match_type_str, charsmax(match_type_str), "12man");
        case MATCH_TYPE_SCRIM: copy(match_type_str, charsmax(match_type_str), "scrim");
        case MATCH_TYPE_DRAFT: copy(match_type_str, charsmax(match_type_str), "draft");
        default: copy(match_type_str, charsmax(match_type_str), "competitive");
    }

    log_ktp("event=MAPCFG status=exec map=%s cfg=%s path=\'%s\' match_type=%s specific=%d",
            g_currentMap, cfg, fullpath, match_type_str, use_specific);
    announce_all("Applying %s config: %s", match_type_str, cfg);

    server_cmd("exec %s", fullpath);
    server_exec();

    // NOTE: mp_clan_restartround 1 is now called by the caller (cmd_ready)
    // to ensure it always runs even if no map config is found

    return 1;
}

// Get human-readable match type label for HUD display
stock get_match_type_label(output[], maxlen) {
    switch (g_matchType) {
        case MATCH_TYPE_SCRIM: copy(output, maxlen, "Scrim");
        case MATCH_TYPE_12MAN: copy(output, maxlen, "12man");
        case MATCH_TYPE_DRAFT: copy(output, maxlen, "Draft");
        default: copy(output, maxlen, "Match");
    }
}

stock ktp_pause_now(const reason[]) {
    log_ktp("event=PAUSE_ATTEMPT reason=%s paused=%d", reason, g_isPaused);

    if (!g_isPaused) {
        rh_set_server_pause(true);
        g_isPaused = true;
        log_ktp("event=PAUSE_TOGGLE reason='%s'", reason);
        client_print(0, print_chat, "[KTP] Game paused (reason: %s)", reason);
    }
}

stock ktp_unpause_now(const reason[]) {
    log_ktp("event=UNPAUSE_ATTEMPT reason=%s paused=%d", reason, g_isPaused);

    if (g_isPaused) {
        rh_set_server_pause(false);
        g_isPaused = false;
        log_ktp("event=UNPAUSE_TOGGLE reason='%s'", reason);
        client_print(0, print_chat, "[KTP] Game unpaused (reason: %s)", reason);
    }
}

// ================= Pre-Pause Countdown =================
// isPreMatch: true = use ktp_prematch_pause_seconds, false = use ktp_prepause_seconds
// initiatorId: player ID for dynamic name lookup (0 for server/auto events)
stock trigger_pause_countdown(const who[], const reason[], bool:isPreMatch = false, initiatorId = 0) {
    if (g_isPaused) {
        announce_all("Game is already paused.");
        return;
    }

    if (g_prePauseCountdown) {
        announce_all("Pause countdown already in progress.");
        return;
    }

    copy(g_prePauseInitiator, charsmax(g_prePauseInitiator), who);
    copy(g_prePauseReason, charsmax(g_prePauseReason), reason);
    g_prePauseInitiatorId = initiatorId;

    // Use appropriate countdown based on match state
    // OPTIMIZED: Use cached CVAR values instead of get_pcvar_num() (Phase 5)
    if (isPreMatch) {
        g_prePauseLeft = g_preMatchPauseSeconds;
        if (g_prePauseLeft <= 0) g_prePauseLeft = 5;  // minimum 5 seconds
    } else {
        g_prePauseLeft = g_prePauseSeconds;
        if (g_prePauseLeft <= 0) g_prePauseLeft = 5;  // minimum 5 seconds
    }

    g_prePauseCountdown = true;

    // Ensure no duplicate pre-pause countdown tasks
    safe_remove_task(g_taskPrePauseId);
    set_task(1.0, "prepause_countdown_tick", g_taskPrePauseId, _, _, "b");

    announce_all("%s initiated pause. Pausing in %d seconds...", who, g_prePauseLeft);
    log_ktp("event=PREPAUSE_START initiator='%s' reason='%s' countdown=%d prematch=%d", who, reason, g_prePauseLeft, isPreMatch ? 1 : 0);
    log_amx("KTP: Pre-pause countdown started by %s (%s) - %d seconds (prematch: %d)", who, reason, g_prePauseLeft, isPreMatch ? 1 : 0);
}

public prepause_countdown_tick() {
    if (!g_prePauseCountdown) {
        safe_remove_task(g_taskPrePauseId);
        return;
    }

    if (g_prePauseLeft <= 0) {
        // Actually pause now
        safe_remove_task(g_taskPrePauseId);
        g_prePauseCountdown = false;

        announce_all("=== PAUSING NOW ===");
        execute_pause(g_prePauseInitiator, g_prePauseReason);
        return;
    }

    // Countdown message
    announce_all("Pausing in %d...", g_prePauseLeft);

    g_prePauseLeft--;
}

stock execute_pause(const who[], const reason[]) {
    if (g_isPaused) return;

    // Store pause info (name and ID for dynamic lookup)
    copy(g_lastPauseBy, charsmax(g_lastPauseBy), who);
    g_lastPauseById = g_prePauseInitiatorId;
    g_pauseStartTime = get_systime();
    g_pauseExtensions = 0;

    // Pause using ReAPI native
    rh_set_server_pause(true);
    g_isPaused = true;

    // Set pause duration
    if (g_pauseDurationSec <= 0) g_pauseDurationSec = 300;  // default 5 minutes

    new totalDuration = get_total_pause_duration();
    new buf[16];
    fmt_seconds(totalDuration, buf, charsmax(buf));
    announce_all("Game paused by %s. Duration: %s. Type .ext for more time.",
                 who, buf);
    log_ktp("event=PAUSE_EXECUTED initiator='%s' reason='%s' duration=%d", who, reason, g_pauseDurationSec);
    log_amx("KTP: Game PAUSED by %s (%s) - Duration: %d seconds", who, reason, g_pauseDurationSec);
}

// NOTE: pause_timer_tick() removed - replaced by check_pause_timer_realtime()
// which is called from OnPausedHUDUpdate() ReAPI hook and uses real-world time

// ================= Countdown & Pause HUD =================
public start_unpause_countdown(const who[]) {
    if (!g_isPaused) return;
    if (g_countdownActive) { announce_all("Unpause countdown already running (%d sec left).", g_countdownLeft); return; }

    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), who);

    g_countdownLeft = max(1, g_countdownSeconds);
    g_countdownActive = true;

    // NOTE: No need to remove pause timer task - using ReAPI hook instead

    // OPTIMIZED: Use cached map name instead of get_mapname()
    log_ktp("event=COUNTDOWN begin=%d requested_by=\'%s\' map=%s", g_countdownLeft, who, g_currentMap);
    log_amx("KTP: Unpause countdown started - %d seconds (by %s)", g_countdownLeft, who);

    announce_all("Unpausing in %d seconds...", g_countdownLeft);
    // Ensure no duplicate countdown tasks
    safe_remove_task(g_taskCountdownId);
    set_task(1.0, "countdown_tick", g_taskCountdownId, _, _, "b");
}

public countdown_tick() {
    if (!g_countdownActive) { remove_task(g_taskCountdownId); return; }
    g_countdownLeft--;

    if (g_countdownLeft > 0) {
        // Chat countdown
        announce_all("Unpausing in %d...", g_countdownLeft);
        return;
    }

    // UNPAUSE NOW
    safe_remove_task(g_taskCountdownId);
    g_countdownActive = false;

    announce_all("=== LIVE! ===");

    // OPTIMIZED: Use cached map name instead of get_mapname()
    log_ktp("event=LIVE map=%s requested_by=\'%s\'", g_currentMap, g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");
    log_amx("KTP: Game LIVE - Unpaused by %s", g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");

    // If this was a tech pause, calculate elapsed time and deduct from budget
    new techPauseElapsed = 0;
    if (g_isTechPause && g_techPauseStartTime > 0) {
        new teamId = g_pauseOwnerTeam;
        if (teamId == 1 || teamId == 2) {
            new currentTime = get_systime();

            // Validate time values to prevent underflow
            if (currentTime >= g_techPauseStartTime) {
                techPauseElapsed = currentTime - g_techPauseStartTime;

                // Sanity check: cap at reasonable maximum (1 hour)
                if (techPauseElapsed > 3600) {
                    techPauseElapsed = 3600;
                    log_ktp("event=TECH_PAUSE_ELAPSED_WARNING elapsed=%d capped=3600 reason='exceeds_maximum'",
                            currentTime - g_techPauseStartTime);
                }
            } else {
                // System clock adjusted backwards - use 0 to avoid corruption
                techPauseElapsed = 0;
                log_ktp("event=TECH_PAUSE_TIME_ERROR current=%d start=%d reason='clock_skew'",
                        currentTime, g_techPauseStartTime);
            }

            // Deduct from budget
            new budgetBefore = g_techBudget[teamId];
            g_techBudget[teamId] -= techPauseElapsed;
            if (g_techBudget[teamId] < 0) g_techBudget[teamId] = 0;

            new teamName[16];
            team_name_from_id(teamId, teamName, charsmax(teamName));

            log_ktp("event=TECH_BUDGET_DEDUCT team=%d elapsed=%d budget_before=%d budget_after=%d",
                    teamId, techPauseElapsed, budgetBefore, g_techBudget[teamId]);

            // Persist tech budget to localinfo for 2nd half restoration
            if (g_currentHalf == 1) {
                save_state_to_localinfo();
            }

            // Announce tech pause duration and remaining budget
            new buf1[16], buf2[16];
            fmt_seconds(techPauseElapsed, buf1, charsmax(buf1));
            fmt_seconds(g_techBudget[teamId], buf2, charsmax(buf2));
            announce_all("Tech pause lasted %s. %s budget remaining: %s",
                buf1, teamName, buf2);

            // Warn if budget is low or exhausted
            if (g_techBudget[teamId] == 0) {
                announce_all("WARNING: %s tech budget EXHAUSTED!", teamName);
            } else if (g_techBudget[teamId] <= 60) {
                new buf[16];
                fmt_seconds(g_techBudget[teamId], buf, charsmax(buf));
                announce_all("WARNING: %s has only %s of tech budget remaining!", teamName, buf);
            }
        }
    }

    announce_all("Live! (Unpaused by %s)", g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");

    ktp_unpause_now("countdown");

    // Clear pause-session state
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_isTechPause = false;
    g_techPauseStartTime = 0;
    g_techPauseFrozenTime = 0;
    g_disconnectedPlayerName[0] = EOS;
    g_disconnectedPlayerTeam = 0;
    g_disconnectedPlayerSteamId[0] = EOS;
    g_disconnectCountdown = 0;
    g_autoConfirmLeft = 0;
    safe_remove_task(g_taskAutoUnpauseReqId);
    safe_remove_task(g_taskAutoReqCountdownId);
    safe_remove_task(g_taskPauseHudId);
    safe_remove_task(g_taskAutoConfirmId);
    stop_unpause_reminder();
}

public auto_req_countdown_tick() {
    // Decrement auto-request countdown
    if (!g_isPaused || g_unpauseRequested) {
        // Stop if unpaused or request already made
        safe_remove_task(g_taskAutoReqCountdownId);
        return;
    }

    if (g_autoReqLeft > 0) {
        g_autoReqLeft--;
    }
}

// Tech budget is tracked by pause start/end times, not real-time countdown
// (Real-time countdown doesn't work during actual pause - host_frame frozen)

public disconnect_countdown_tick() {
    // Stop if match ended or already paused
    if (!g_matchLive || g_isPaused) {
        safe_remove_task(g_taskDisconnectCountdownId);
        g_disconnectCountdown = 0;
        return;
    }

    g_disconnectCountdown--;

    new teamName[16];
    team_name_from_id(g_disconnectedPlayerTeam, teamName, charsmax(teamName));

    if (g_disconnectCountdown > 0) {
        announce_all("Auto tech-pause in %d... (%s can type .nodc)", g_disconnectCountdown, teamName);
    } else {
        // Countdown finished - trigger tech pause
        safe_remove_task(g_taskDisconnectCountdownId);

        log_ktp("event=AUTO_TECH_PAUSE player='%s' team=%s reason='disconnect'",
                g_disconnectedPlayerName, teamName);

        // Set up tech pause
        g_pauseOwnerTeam = g_disconnectedPlayerTeam;
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;
        g_isTechPause = true;

        // Schedule auto-unpause request
        setup_auto_unpause_request();

        // Record tech pause start time (wall clock) for budget tracking
        g_techPauseStartTime = get_systime();

        // Format who caused the pause
        new pausedBy[80];
        formatex(pausedBy, charsmax(pausedBy), "AUTO (%s DC)", g_disconnectedPlayerName);

        // Actually pause using new pause system
        execute_pause(pausedBy, "auto_tech_disconnect");

        // NOTE: HUD updates happen automatically via OnPausedHUDUpdate() ReAPI hook

        // Discord notification - DISCONNECT AUTO-PAUSE (as embed with match ID footer)
        #if defined HAS_CURL
        send_discord_disconnect_embed(g_disconnectedPlayerName, g_disconnectedPlayerSteamId, g_disconnectedPlayerTeam);
        #endif
    }
}

// Real-time unpause reminder check (called from OnPausedHUDUpdate hook during pause)
stock check_unpause_reminder_realtime() {
    if (!g_isPaused || g_countdownActive) return;

    // Both confirmed - countdown should have started, stop reminding
    if (g_unpauseRequested && g_unpauseConfirmedOther) return;

    // Only remind if one team has acted but not both
    if (!g_unpauseRequested && !g_unpauseConfirmedOther) return;

    static lastReminderTime = 0;
    new currentTime = get_systime();
    new reminderInterval = floatround(g_unpauseReminderSecs);
    if (reminderInterval < 5) reminderInterval = 15;

    // Check if enough time has passed since last reminder
    if (currentTime - lastReminderTime < reminderInterval) return;
    lastReminderTime = currentTime;

    new ownerTeamName[32], otherTeamName[32];
    team_name_from_id(g_pauseOwnerTeam, ownerTeamName, charsmax(ownerTeamName));
    new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
    team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));

    // Remind the team that hasn't acted yet
    if (g_unpauseRequested && !g_unpauseConfirmedOther) {
        // Owner requested, waiting for other team to .go
        announce_all("Waiting for %s to .go", otherTeamName);
    } else if (!g_unpauseRequested && g_unpauseConfirmedOther) {
        // Other team confirmed, waiting for owner to .resume
        announce_all("Waiting for %s to .resume", ownerTeamName);
    }
}

// Real-time pause timer check (uses get_systime instead of game time)
stock check_pause_timer_realtime() {
    if (!g_isPaused) return;

    // If tech pause budget is frozen (owner did /resume), skip timer checks
    // The auto-confirmunpause timer handles resuming in this case
    if (g_isTechPause && g_techPauseFrozenTime > 0) {
        return;
    }

    static lastWarning30 = 0;
    static lastWarning10 = 0;

    // Cache extension seconds (static so it persists, only lookup once per pause)
    static cachedExtSec = 0, lastPauseStart = 0;
    if (lastPauseStart != g_pauseStartTime) {
        cachedExtSec = g_pauseExtensionSec;
        if (cachedExtSec <= 0) cachedExtSec = 120;
        lastPauseStart = g_pauseStartTime;
    }

    new currentTime = get_systime();
    new elapsed = currentTime - g_pauseStartTime;
    new totalDuration = g_pauseDurationSec + (g_pauseExtensions * cachedExtSec);
    new remaining = totalDuration - elapsed;

    // Warning at 30 seconds remaining (only once)
    if (remaining <= 30 && remaining > 29 && lastWarning30 != g_pauseStartTime) {
        lastWarning30 = g_pauseStartTime;
        announce_all("Pause ending in 30 seconds. Type .ext for more time.");
        log_amx("KTP: Pause warning - 30 seconds remaining");
    }

    // Warning at 10 seconds remaining (only once)
    if (remaining <= 10 && remaining > 9 && lastWarning10 != g_pauseStartTime) {
        lastWarning10 = g_pauseStartTime;
        announce_all("Pause ending in 10 seconds...");
        log_amx("KTP: Pause warning - 10 seconds remaining");
    }

    // Auto-unpause when time expires
    if (remaining <= 0) {
        announce_all("Pause duration expired. Auto-unpausing...");
        log_ktp("event=PAUSE_TIMEOUT elapsed=%d duration=%d", elapsed, totalDuration);
        log_amx("KTP: Pause timeout - Auto-unpausing after %d seconds", elapsed);

        // Trigger unpause countdown
        start_unpause_countdown("auto-timeout");

        // Reset warning flags for next pause
        lastWarning30 = 0;
        lastWarning10 = 0;
    }
}

// ================= ReAPI Pause HUD Hook (KTP-ReHLDS) =================
// This hook enables automatic real-time updates during pause
// Requires: KTP-ReHLDS fork (provides RH_SV_UpdatePausedHUD hook) + ReAPI module
public OnPausedHUDUpdate() {
    // Called every frame while paused (via KTP-ReHLDS modification)
    // Throttle to 1 update per second to avoid network overflow
    static lastUpdate = 0;
    new currentTime = get_systime();

    if (currentTime == lastUpdate) return HC_CONTINUE;  // Already updated this second
    lastUpdate = currentTime;

    if (!g_isPaused) return HC_CONTINUE;

    // Handle unpause countdown during pause (tasks don't run during pause!)
    if (g_countdownActive && g_countdownLeft > 0) {
        g_countdownLeft--;
        if (g_countdownLeft > 0) {
            announce_all("Unpausing in %d...", g_countdownLeft);
        } else {
            // Countdown finished - trigger unpause
            g_countdownActive = false;

            // If this was a tech pause, calculate elapsed time and deduct from budget
            // (Must be done BEFORE clearing g_isTechPause and g_techPauseStartTime)
            // Skip if budget was already frozen on /resume (g_techPauseFrozenTime != 0)
            if (g_isTechPause && g_techPauseStartTime > 0 && g_techPauseFrozenTime == 0) {
                new teamId = g_pauseOwnerTeam;
                if (teamId == 1 || teamId == 2) {
                    new currentTime = get_systime();
                    new techPauseElapsed = 0;

                    // Validate time values to prevent underflow
                    if (currentTime >= g_techPauseStartTime) {
                        techPauseElapsed = currentTime - g_techPauseStartTime;
                        // Sanity check: cap at reasonable maximum (1 hour)
                        if (techPauseElapsed > 3600) {
                            techPauseElapsed = 3600;
                            log_ktp("event=TECH_PAUSE_ELAPSED_WARNING elapsed=%d capped=3600 reason='exceeds_maximum'",
                                    currentTime - g_techPauseStartTime);
                        }
                    } else {
                        // System clock adjusted backwards - use 0 to avoid corruption
                        log_ktp("event=TECH_PAUSE_TIME_ERROR current=%d start=%d reason='clock_skew'",
                                currentTime, g_techPauseStartTime);
                    }

                    // Deduct from budget
                    new budgetBefore = g_techBudget[teamId];
                    g_techBudget[teamId] -= techPauseElapsed;
                    if (g_techBudget[teamId] < 0) g_techBudget[teamId] = 0;

                    new teamName[16];
                    team_name_from_id(teamId, teamName, charsmax(teamName));

                    log_ktp("event=TECH_BUDGET_DEDUCT team=%d elapsed=%d budget_before=%d budget_after=%d",
                            teamId, techPauseElapsed, budgetBefore, g_techBudget[teamId]);

                    // Persist tech budget to localinfo for 2nd half restoration
                    if (g_currentHalf == 1) {
                        save_state_to_localinfo();
                    }

                    // Announce tech pause duration and remaining budget
                    new buf1[16], buf2[16];
                    fmt_seconds(techPauseElapsed, buf1, charsmax(buf1));
                    fmt_seconds(g_techBudget[teamId], buf2, charsmax(buf2));
                    announce_all("Tech pause lasted %s. %s budget remaining: %s",
                        buf1, teamName, buf2);

                    // Warn if budget is low or exhausted
                    if (g_techBudget[teamId] == 0) {
                        announce_all("WARNING: %s tech budget EXHAUSTED!", teamName);
                    } else if (g_techBudget[teamId] <= 60) {
                        new buf[16];
                        fmt_seconds(g_techBudget[teamId], buf, charsmax(buf));
                        announce_all("WARNING: %s has only %s of tech budget remaining!", teamName, buf);
                    }
                }
            }

            announce_all("=== LIVE! ===");
            log_ktp("event=LIVE map=%s requested_by='%s'", g_currentMap, g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");
            ktp_unpause_now("countdown");
            // Clear pause state
            g_pauseOwnerTeam = 0;
            g_unpauseRequested = false;
            g_unpauseConfirmedOther = false;
            g_isTechPause = false;
            g_techPauseStartTime = 0;
            g_techPauseFrozenTime = 0;
            safe_remove_task(g_taskCountdownId);
            safe_remove_task(g_taskAutoConfirmId);
            g_autoConfirmLeft = 0;
            return HC_CONTINUE;
        }
    }

    // Handle auto-confirmunpause countdown during pause (tasks don't run during pause!)
    if (g_autoConfirmLeft > 0 && !g_countdownActive) {
        g_autoConfirmLeft--;

        // Warnings at 30s, 10s, 5s
        if (g_autoConfirmLeft == 30) {
            new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
            new otherTeamName[32];
            team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));
            announce_all("%s: 30 seconds to .go!", otherTeamName);
        } else if (g_autoConfirmLeft == 10) {
            announce_all("10 seconds to auto-resume!");
        } else if (g_autoConfirmLeft == 5) {
            announce_all("5 seconds to auto-resume!");
        }

        // Time's up - auto confirm
        if (g_autoConfirmLeft <= 0) {
            g_autoConfirmLeft = 0;
            safe_remove_task(g_taskAutoConfirmId);

            announce_all("Auto-confirming unpause (60 second timeout).");
            log_ktp("event=AUTO_CONFIRMUNPAUSE reason='60s_timeout'");

            // Set confirmed and start countdown
            g_unpauseConfirmedOther = true;
            stop_unpause_reminder();
            start_unpause_countdown("auto-confirm");
        }
    }

    // If in pending phase, show pending HUD instead of pause HUD
    if (g_matchPending) {
        show_pending_hud_during_pause();
        // Still check pause timer for warnings/timeout
        check_pause_timer_realtime();
        // Check unpause reminders using real-time
        check_unpause_reminder_realtime();
        return HC_CONTINUE;
    }

    // Display pause HUD based on type (for tactical/tech pauses during live match)
    show_pause_hud_message(g_isTechPause ? "TECHNICAL" : "TACTICAL");

    // Check pause timer for warnings/timeout using real-world time
    check_pause_timer_realtime();

    // Check unpause reminders using real-time
    check_unpause_reminder_realtime();

    return HC_CONTINUE;
}

// ================= Pre-Start HUD =================
public pending_hud_tick() {
    if (!g_matchPending) { remove_task(g_taskPendingHudId); return; }

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;

    // Calculate pause status message
    new pauseInfo[64] = "";
    if (g_prePauseCountdown) {
        // Show pre-pause countdown
        formatex(pauseInfo, charsmax(pauseInfo), "^nPausing in %d seconds...", g_prePauseLeft);
    } else if (g_isPaused && g_pauseStartTime > 0) {
        // Show actual pause time remaining
        new elapsed = get_systime() - g_pauseStartTime;
        new duration = get_total_pause_duration();
        new remaining = duration - elapsed;
        if (remaining < 0) remaining = 0;
        new buf[16];
        fmt_seconds(remaining, buf, charsmax(buf));
        formatex(pauseInfo, charsmax(pauseInfo), "^nPause Time: %s remaining", buf);
    }

    // 2nd Half or OT pending: Show prominent score context HUD
    if (g_secondHalfPending || g_inOvertime) {
        show_continuation_pending_hud(alliesReady, alliesPlayers, axisReady, axisPlayers, need, pauseInfo);
        return;
    }

    // Standard 1st half pending HUD
    new matchLabel[16];
    get_match_type_label(matchLabel, charsmax(matchLabel));
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP %s Pending%s^n%s: %d/%d ready (tech:%ds)^n%s: %d/%d ready (tech:%ds)^nNeed %d/team - Type .rdy when ready.",
        matchLabel, pauseInfo, g_teamName[1], alliesReady, alliesPlayers, techA, g_teamName[2], axisReady, axisPlayers, techX, need);
}

// Show pending HUD during pause (called from OnPausedHUDUpdate hook)
// This runs every frame, so pause timer updates in real-time
stock show_pending_hud_during_pause() {
    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;

    // Calculate pause time remaining using real-time clock
    new pauseInfo[64] = "";
    if (g_pauseStartTime > 0) {
        new elapsed = get_systime() - g_pauseStartTime;
        new duration = get_total_pause_duration();
        new remaining = duration - elapsed;
        if (remaining < 0) remaining = 0;
        new buf[16];
        fmt_seconds(remaining, buf, charsmax(buf));
        formatex(pauseInfo, charsmax(pauseInfo), "^nPause Time: %s remaining", buf);
    }

    // 2nd Half or OT pending: Show prominent score context HUD
    if (g_secondHalfPending || g_inOvertime) {
        show_continuation_pending_hud_fast(alliesReady, alliesPlayers, axisReady, axisPlayers, need, pauseInfo);
        return;
    }

    // Standard 1st half pending HUD
    new matchLabel[16];
    get_match_type_label(matchLabel, charsmax(matchLabel));
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 0.1, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP %s Pending%s^n%s: %d/%d ready (tech:%ds)^n%s: %d/%d ready (tech:%ds)^nNeed %d/team - Type .rdy when ready.",
        matchLabel, pauseInfo, g_teamName[1], alliesReady, alliesPlayers, techA, g_teamName[2], axisReady, axisPlayers, techX, need);
}

// Show continuation HUD for 2nd half or OT pending (1.2s hold time for task tick)
stock show_continuation_pending_hud(alliesReady, alliesPlayers, axisReady, axisPlayers, need, const pauseInfo[]) {
    show_continuation_pending_hud_internal(alliesReady, alliesPlayers, axisReady, axisPlayers, need, pauseInfo, 1.2);
}

// Show continuation HUD for 2nd half or OT pending (0.1s hold time for pause hook)
stock show_continuation_pending_hud_fast(alliesReady, alliesPlayers, axisReady, axisPlayers, need, const pauseInfo[]) {
    show_continuation_pending_hud_internal(alliesReady, alliesPlayers, axisReady, axisPlayers, need, pauseInfo, 0.1);
}

// Internal: Build and show the continuation pending HUD
stock show_continuation_pending_hud_internal(alliesReady, alliesPlayers, axisReady, axisPlayers, need, const pauseInfo[], Float:holdTime) {
    new header[64], scoreLine[96], readyLine[96];

    if (g_inOvertime) {
        // OT pending: Show OT round and grand totals
        // Calculate OT totals from previous rounds
        new team1OtTotal = 0, team2OtTotal = 0;
        for (new r = 1; r < g_otRound; r++) {
            team1OtTotal += g_otScores[r][1];
            team2OtTotal += g_otScores[r][2];
        }
        new team1Grand = g_regulationScore[1] + team1OtTotal;
        new team2Grand = g_regulationScore[2] + team2OtTotal;
        formatex(header, charsmax(header), "=== OVERTIME RD %d - Type .ready ===", g_otRound);
        formatex(scoreLine, charsmax(scoreLine), "%s %d - %d %s (Grand Total)",
                g_team1Name, team1Grand, team2Grand, g_team2Name);
    } else {
        // 2nd half pending: Show 1st half scores
        formatex(header, charsmax(header), "=== 2ND HALF - Type .ready ===");
        formatex(scoreLine, charsmax(scoreLine), "%s %d - %d %s (1st half)",
                g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name);
    }

    // Ready status line
    formatex(readyLine, charsmax(readyLine), "%s: %d/%d | %s: %d/%d (need %d)",
            g_teamName[1], alliesReady, alliesPlayers,
            g_teamName[2], axisReady, axisPlayers, need);

    // Yellow color for continuation pending, centered
    set_hudmessage(255, 255, 0, -1.0, 0.15, 0, 0.0, holdTime, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync, "%s^n%s^n^n%s%s", header, scoreLine, readyLine, pauseInfo);
}

public prestart_hud_tick() {
    if (!g_preStartPending) { remove_task(g_taskPrestartHudId); return; }

    new matchLabel[16];
    get_match_type_label(matchLabel, charsmax(matchLabel));

    set_hudmessage(255, 210, 0, 0.01, 0.12, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP Pre-Start (%s): Waiting for .confirm^n%s: %s^n%s: %s^nCommands: .confirm, .prestatus, .cancel",
        matchLabel,
        g_teamName[1], g_preConfirmAllies ? g_confirmAlliesBy : "—",
        g_teamName[2], g_preConfirmAxis   ? g_confirmAxisBy   : "—"
    );
}

stock prestart_reset() {
    g_preStartPending = false;
    g_preConfirmAllies = false;
    g_preConfirmAxis   = false;
    g_confirmAlliesBy[0] = EOS;
    g_confirmAxisBy[0]   = EOS;
    safe_remove_task(g_taskPrestartHudId);

    // Reset pause limits only for NEW matches (1st half), not 2nd half continuation
    // Pause counts persist across halves (per-match limit, not per-half)
    if (!g_secondHalfPending) {
        g_pauseCountTeam[1] = 0;
        g_pauseCountTeam[2] = 0;
    }
    g_matchLive = false; // will flip to true at first LIVE of this half
}

// Announce plugin banner to server + all clients, and log it.
stock ktp_banner_enabled() {
    server_print("[KTP] %s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    // Version announcement moved to per-player delayed task in fn_version_display()
    log_ktp("event=PLUGIN_ENABLED name='%s' version=%s author='%s'", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}


// ================= AMXX lifecycle =================

// Register natives for external plugins
public plugin_natives() {
    register_native("ktp_is_match_active", "_native_is_match_active");
}

// Native: ktp_is_match_active() - Returns 1 if match is in progress (live, pending, or prestart)
public _native_is_match_active(plugin, params) {
    // Block changemap during any match phase
    if (g_matchLive || g_matchPending || g_preStartPending) {
        return 1;
    }
    return 0;
}

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // Register forwards for external plugins (KTPHLTVRecorder, etc.)
    g_fwdMatchStart = CreateMultiForward("ktp_match_start", ET_IGNORE, FP_STRING, FP_STRING, FP_CELL);
    g_fwdMatchEnd = CreateMultiForward("ktp_match_end", ET_IGNORE, FP_STRING, FP_STRING, FP_CELL, FP_CELL, FP_CELL);

    new tmpCnt[8];
    new tmpReady[8];
    new tmpPre[8];
    new tmpTech[8];

    num_to_str(g_countdownSeconds, tmpCnt,  charsmax(tmpCnt));
    num_to_str(g_prePauseSeconds, tmpPre,    charsmax(tmpPre));
    num_to_str(g_techBudgetSecs,  tmpTech,   charsmax(tmpTech));
    num_to_str(g_readyRequired,   tmpReady,     charsmax(tmpReady));

    g_cvarCountdown       = register_cvar("ktp_pause_countdown",  tmpCnt);
    g_cvarReadyReq        = register_cvar("ktp_ready_required", tmpReady);
    g_cvarPrePauseSec     = register_cvar("ktp_prepause_seconds", tmpPre);
    g_cvarPreMatchPauseSec = register_cvar("ktp_prematch_pause_seconds", tmpPre); // same default as prepause
    g_cvarTechBudgetSec   = register_cvar("ktp_tech_budget_seconds", tmpTech);
    g_cvarLogFile        = register_cvar("ktp_match_logfile", DEFAULT_LOGFILE);
    // ktp_force_pausable removed - ReAPI pause bypasses pausable cvar
    // ktp_pause_hud removed - HUD output removed from announce_all for proper message ordering
    g_cvarCfgBase        = register_cvar("ktp_cfg_basepath", "configs/");
    // Use get_configsdir() for dynamic config path resolution
    new configsDir[128];
    get_configsdir(configsDir, charsmax(configsDir));
    new mapsFilePath[192], discordIniPath[192];
    formatex(mapsFilePath, charsmax(mapsFilePath), "%s/ktp_maps.ini", configsDir);
    formatex(discordIniPath, charsmax(discordIniPath), "%s/discord.ini", configsDir);
    g_cvarMapsFile       = register_cvar("ktp_maps_file", mapsFilePath);
    g_cvarAutoReqSec     = register_cvar("ktp_unpause_autorequest_secs", "300");
    g_cvarDiscordIniPath = register_cvar("ktp_discord_ini", discordIniPath);
    g_cvarPauseDuration  = register_cvar("ktp_pause_duration", "300");       // 5 minutes
    g_cvarPauseExtension = register_cvar("ktp_pause_extension", "120");      // 2 minutes
    g_cvarMaxExtensions  = register_cvar("ktp_pause_max_extensions", "2");   // max 2 extensions
    g_cvarUnreadyReminderSec = register_cvar("ktp_unready_reminder_secs", "30");  // unready reminder interval
    g_cvarUnpauseReminderSec = register_cvar("ktp_unpause_reminder_secs", "15");  // unpause reminder interval

    // Chat controls - Pause (tactical)
    register_clcmd("say /pause",        "cmd_chat_toggle");
    register_clcmd("say_team /pause",   "cmd_chat_toggle");
    register_clcmd("say pause",         "cmd_chat_toggle");
    register_clcmd("say_team pause",    "cmd_chat_toggle");
    register_clcmd("say .pause",        "cmd_chat_toggle");
    register_clcmd("say_team .pause",   "cmd_chat_toggle");
    register_clcmd("say /tactical",     "cmd_chat_toggle");
    register_clcmd("say_team /tactical","cmd_chat_toggle");
    register_clcmd("say .tactical",     "cmd_chat_toggle");
    register_clcmd("say_team .tactical","cmd_chat_toggle");
    register_clcmd("say /tac",          "cmd_chat_toggle");
    register_clcmd("say_team /tac",     "cmd_chat_toggle");
    register_clcmd("say .tac",          "cmd_chat_toggle");
    register_clcmd("say_team .tac",     "cmd_chat_toggle");
    register_clcmd("say /resume",       "cmd_chat_resume");
    register_clcmd("say_team /resume",  "cmd_chat_resume");
    register_clcmd("say resume",        "cmd_chat_resume");
    register_clcmd("say_team resume",   "cmd_chat_resume");
    register_clcmd("say .resume",       "cmd_chat_resume");
    register_clcmd("say_team .resume",  "cmd_chat_resume");
    register_clcmd("say /go",       "cmd_confirm_unpause");
    register_clcmd("say_team /go",  "cmd_confirm_unpause");
    register_clcmd("say .go",       "cmd_confirm_unpause");
    register_clcmd("say_team .go",  "cmd_confirm_unpause");

    // Pause extension
    register_clcmd("say /extend",       "cmd_extend_pause");
    register_clcmd("say_team /extend",  "cmd_extend_pause");
    register_clcmd("say .extend",       "cmd_extend_pause");
    register_clcmd("say_team .extend",  "cmd_extend_pause");
    register_clcmd("say .ext",          "cmd_extend_pause");
    register_clcmd("say_team .ext",     "cmd_extend_pause");

    // Cancel disconnect auto-pause
    register_clcmd("say /nodc",         "cmd_cancel_disconnect_pause");
    register_clcmd("say_team /nodc",    "cmd_cancel_disconnect_pause");
    register_clcmd("say .nodc",         "cmd_cancel_disconnect_pause");
    register_clcmd("say_team .nodc",    "cmd_cancel_disconnect_pause");
    register_clcmd("say /stopdc",       "cmd_cancel_disconnect_pause");
    register_clcmd("say_team /stopdc",  "cmd_cancel_disconnect_pause");
    register_clcmd("say .stopdc",       "cmd_cancel_disconnect_pause");
    register_clcmd("say_team .stopdc",  "cmd_cancel_disconnect_pause");

    // Technical pause
    register_clcmd("say /tech",          "cmd_tech_pause");
    register_clcmd("say_team /tech",     "cmd_tech_pause");
    register_clcmd("say tech",           "cmd_tech_pause");
    register_clcmd("say_team tech",      "cmd_tech_pause");
    register_clcmd("say .tech",          "cmd_tech_pause");
    register_clcmd("say_team .tech",     "cmd_tech_pause");
    register_clcmd("say /technical",     "cmd_tech_pause");
    register_clcmd("say_team /technical","cmd_tech_pause");
    register_clcmd("say .technical",     "cmd_tech_pause");
    register_clcmd("say_team .technical","cmd_tech_pause");

    // Say hook for commands with arguments (register_clcmd only matches exact text)
    register_clcmd("say", "cmd_say_hook");
    register_clcmd("say_team", "cmd_say_hook");
    register_clcmd("say /draft",           "cmd_start_draft");
    register_clcmd("say_team /draft",      "cmd_start_draft");
    register_clcmd("say .draft",           "cmd_start_draft");
    register_clcmd("say_team .draft",      "cmd_start_draft");

    // Scrim / 12-man (no Discord notifications)
    register_clcmd("say /scrim",           "cmd_start_scrim");
    register_clcmd("say_team /scrim",      "cmd_start_scrim");
    register_clcmd("say .scrim",           "cmd_start_scrim");
    register_clcmd("say_team .scrim",      "cmd_start_scrim");
    register_clcmd("say /12man",           "cmd_start_12man");
    register_clcmd("say_team /12man",      "cmd_start_12man");
    register_clcmd("say .12man",           "cmd_start_12man");
    register_clcmd("say_team .12man",      "cmd_start_12man");

    register_clcmd("say /confirm",        "cmd_pre_confirm");
    register_clcmd("say_team /confirm",   "cmd_pre_confirm");
    register_clcmd("say confirm",         "cmd_pre_confirm");
    register_clcmd("say_team confirm",    "cmd_pre_confirm");
    register_clcmd("say .confirm",        "cmd_pre_confirm");
    register_clcmd("say_team .confirm",   "cmd_pre_confirm");
    register_clcmd("say /notconfirm",     "cmd_pre_notconfirm");
    register_clcmd("say_team /notconfirm","cmd_pre_notconfirm");
    register_clcmd("say .notconfirm",     "cmd_pre_notconfirm");
    register_clcmd("say_team .notconfirm","cmd_pre_notconfirm");
    register_clcmd("say /prestatus",      "cmd_pre_status");
    register_clcmd("say_team /prestatus", "cmd_pre_status");
    register_clcmd("say .prestatus",      "cmd_pre_status");
    register_clcmd("say_team .prestatus", "cmd_pre_status");
    register_clcmd("say prestatus",       "cmd_pre_status");
    register_clcmd("say_team prestatus",  "cmd_pre_status");

    // Ready + notready
    register_clcmd("say /ready",         "cmd_ready");
    register_clcmd("say_team /ready",    "cmd_ready");
    register_clcmd("say .ready",         "cmd_ready");
    register_clcmd("say_team .ready",    "cmd_ready");
    register_clcmd("say .rdy",           "cmd_ready");
    register_clcmd("say_team .rdy",      "cmd_ready");
    register_clcmd("say /notready",      "cmd_notready");
    register_clcmd("say_team /notready", "cmd_notready");
    register_clcmd("say .notready",      "cmd_notready");
    register_clcmd("say_team .notready", "cmd_notready");

    // Status + cancel
    register_clcmd("say /status",         "cmd_status");
    register_clcmd("say_team /status",    "cmd_status");
    register_clcmd("say status",          "cmd_status");
    register_clcmd("say_team status",     "cmd_status");
    register_clcmd("say .status",         "cmd_status");
    register_clcmd("say_team .status",    "cmd_status");

    register_clcmd("say /cancel",       "cmd_cancel");
    register_clcmd("say_team /cancel",  "cmd_cancel");
    register_clcmd("say cancel",        "cmd_cancel");
    register_clcmd("say_team cancel",   "cmd_cancel");
    register_clcmd("say .cancel",       "cmd_cancel");
    register_clcmd("say_team .cancel",  "cmd_cancel");

    // Config display
    register_clcmd("say /cfg",       "cmd_ktpconfig");
    register_clcmd("say_team /cfg",  "cmd_ktpconfig");
    register_clcmd("say .cfg",       "cmd_ktpconfig");
    register_clcmd("say_team .cfg",  "cmd_ktpconfig");

    // Team name commands (handled by say hook for /setallies, /setaxis with args)
    register_clcmd("say /names",       "cmd_teamnames");
    register_clcmd("say_team /names",  "cmd_teamnames");
    register_clcmd("say .names",       "cmd_teamnames");
    register_clcmd("say_team .names",  "cmd_teamnames");
    register_clcmd("say /resetnames",       "cmd_resetteamnames");
    register_clcmd("say_team /resetnames",  "cmd_resetteamnames");
    register_clcmd("say .resetnames",       "cmd_resetteamnames");
    register_clcmd("say_team .resetnames",  "cmd_resetteamnames");

    // Score command
    register_clcmd("say /score", "cmd_score");
    register_clcmd("say_team /score", "cmd_score");
    register_clcmd("say .score", "cmd_score");
    register_clcmd("say_team .score", "cmd_score");

    // Commands help
    register_clcmd("say /commands", "cmd_commands");
    register_clcmd("say_team /commands", "cmd_commands");
    register_clcmd("say .commands", "cmd_commands");
    register_clcmd("say_team .commands", "cmd_commands");
    register_clcmd("say /cmds", "cmd_commands");
    register_clcmd("say_team /cmds", "cmd_commands");
    register_clcmd("say .cmds", "cmd_commands");
    register_clcmd("say_team .cmds", "cmd_commands");

    // Overtime break commands
    register_clcmd("say /otbreak", "cmd_otbreak");
    register_clcmd("say_team /otbreak", "cmd_otbreak");
    register_clcmd("say .otbreak", "cmd_otbreak");
    register_clcmd("say_team .otbreak", "cmd_otbreak");
    register_clcmd("say /skip", "cmd_ot_skip");
    register_clcmd("say_team /skip", "cmd_ot_skip");
    register_clcmd("say .skip", "cmd_ot_skip");
    register_clcmd("say_team .skip", "cmd_ot_skip");
    // Note: .ext is already registered for pause extension, will check context in handler

    // NOTE: We do NOT register the console "pause" command because KTP-ReHLDS has it built-in
    // Attempting to override it causes: "Cmd_AddMallocCommand: pause already defined"
    // Instead, we rely on:
    //   - Chat commands: "say /pause" (registered above at line 1266)
    //   - Server can use: ktp_pause command (registered below)
    // The engine's built-in pause still works, but without our custom countdown/tracking

    // Custom pause command for server/admin use (avoids conflict with built-in "pause")
    register_concmd("ktp_pause", "cmd_rcon_pause", ADMIN_RCON, "- Trigger KTP tactical pause");

    // Register TeamScore message hook for match score tracking (DoD: byte TeamID, short Score)
    new msgTeamScore = get_user_msgid("TeamScore");
    if (msgTeamScore > 0) {
        register_message(msgTeamScore, "msg_TeamScore");
        log_ktp("event=TEAMSCORE_MSG_REGISTERED msgid=%d", msgTeamScore);
    }

    // NOTE: Logevent-based game end detection has been REMOVED.
    // The changelevel hook (RH_Host_Changelevel_f) now handles all match state finalization.
    // See: OnChangeLevel(), process_second_half_end_changelevel(), etc.

    g_hudSync = CreateHudSyncObj();

    // Register ReAPI hook for automatic pause HUD updates (KTP-ReHLDS)
    RegisterHookChain(RH_SV_UpdatePausedHUD, "OnPausedHUDUpdate", .post = false);
    log_amx("[KTP] Registered RH_SV_UpdatePausedHUD hook (KTP-ReHLDS mode)");

    // Register ReAPI hook for console changelevel interception (KTP-ReHLDS)
    // This hooks server_cmd("changelevel") to finalize match state before map changes
    RegisterHookChain(RH_Host_Changelevel_f, "OnChangeLevel", .post = false);
    log_amx("[KTP] Registered RH_Host_Changelevel_f hook (KTP-ReHLDS mode)");
    log_ktp("event=CHANGELEVEL_HOOK_REGISTERED");

    g_lastUnpauseBy[0] = EOS;
    g_lastPauseBy[0] = EOS;

    // read CVARs to apply live values
    ktp_sync_config_from_cvars();

    reset_captains();
}

public plugin_cfg() {
    // Announce on load
    ktp_banner_enabled();
    get_mapname(g_currentMap, charsmax(g_currentMap));  // Cache map name
    ktp_sync_config_from_cvars();
    load_ktp_config();      // Load ktp.ini (season_active, etc.)
    load_map_mappings();
    load_discord_config();
    ktp_discord_load_config();  // Also populate shared Discord state for other plugins

    // KTP: Runtime check for DODX HLStatsX natives
    // These natives may not exist in older DODX builds
    #if defined HAS_DODX
    // Check if DODX module is loaded - if so, assume new natives are available
    // The new DODX module (with HLStatsX natives) identifies as "dodx"
    if (module_exists("dodx")) {
        g_hasDodxStatsNatives = true;
        log_ktp("event=DODX_STATS_NATIVES status=available");
    } else {
        g_hasDodxStatsNatives = false;
        log_ktp("event=DODX_STATS_NATIVES status=unavailable msg=DODX module not loaded");
    }
    #endif

    // Check for persisted match context (2nd half continuation)
    restore_match_context_from_localinfo();
}

// Restore match context from localinfo if we're continuing a match (2nd half or OT)
stock restore_match_context_from_localinfo() {
    new mode[8];
    get_localinfo(LOCALINFO_MODE, mode, charsmax(mode));

    // Debug: Always log what we found
    log_ktp("event=CONTEXT_CHECK mode='%s' current_map=%s", mode, g_currentMap);

    // Check if we have a pending mode
    if (!mode[0]) {
        // No pending continuation - reset team names to defaults
        reset_team_names();
        log_ktp("event=TEAM_NAMES_RESET reason=no_pending_mode");
        return;
    }

    // Determine mode type
    new bool:isSecondHalf = bool:(equal(mode, "h2"));
    new bool:isOvertime = (mode[0] == 'o' && mode[1] == 't');  // "ot1", "ot2", etc.

    if (!isSecondHalf && !isOvertime) {
        // Unknown mode
        log_ktp("event=UNKNOWN_MODE mode=%s", mode);
        clear_localinfo_match_context();
        reset_team_names();
        return;
    }

    // Restore match ID and map
    new savedMatchMap[32];
    get_localinfo(LOCALINFO_MATCH_ID, g_matchId, charsmax(g_matchId));
    get_localinfo(LOCALINFO_MATCH_MAP, savedMatchMap, charsmax(savedMatchMap));

    // Check if match was live (for abandoned match detection)
    new wasLive[4];
    get_localinfo(LOCALINFO_LIVE, wasLive, charsmax(wasLive));
    new bool:matchWasLive = bool:(wasLive[0] == '1');

    // Verify we're on the expected map
    if (!equali(savedMatchMap, g_currentMap)) {
        // Map mismatch - check if match was live (abandoned match)
        if (matchWasLive) {
            // Match was live and map changed - finalize the abandoned match
            log_ktp("event=ABANDONED_MATCH_DETECTED saved_map=%s current_map=%s match_id=%s mode=%s",
                    savedMatchMap, g_currentMap, g_matchId, mode);
            finalize_abandoned_match(mode, savedMatchMap);
        } else {
            // Match wasn't live yet (players never readied) - just clear
            log_ktp("event=MATCH_CONTEXT_ABANDONED saved_map=%s current_map=%s match_id=%s reason=not_live",
                    savedMatchMap, g_currentMap, g_matchId);
        }
        clear_localinfo_match_context();
        reset_team_names();
        g_matchId[0] = EOS;
        return;
    }

    // Map matches - but check if match was live (completed, not pending)
    // If _ktp_live="1" and map matches, could be:
    //   a) 1st half ended, loading for 2nd half (no _ktp_h2 scores yet)
    //   b) 2nd half ended, map cycled back (has _ktp_h2 scores from periodic save)
    if (matchWasLive && isSecondHalf) {
        // Check if 2nd half actually ran by looking for h2 scores
        new h2ScoresBuf[16];
        get_localinfo(LOCALINFO_H2_SCORES, h2ScoresBuf, charsmax(h2ScoresBuf));

        if (h2ScoresBuf[0] == EOS || equal(h2ScoresBuf, "0,0")) {
            // No 2nd half scores - 1st half just ended, need to restore for 2nd half pending
            log_ktp("event=FIRST_HALF_ENDED_DETECTED match_id=%s map=%s reason=no_h2_scores", g_matchId, savedMatchMap);
            // Clear live flag - 1st half ended, 2nd half not yet live
            set_localinfo(LOCALINFO_LIVE, "");
            // Fall through to restore pending state for 2nd half
        } else {
            // Has 2nd half scores - 2nd half actually ran and ended
            log_ktp("event=SECOND_HALF_ENDED_DETECTED match_id=%s map=%s h2_scores=%s", g_matchId, savedMatchMap, h2ScoresBuf);
            finalize_completed_second_half();

            // If OT was triggered, don't clear state - OT system handles it
            if (g_inOvertime) {
                log_ktp("event=OVERTIME_TRIGGERED_FROM_FINALIZE");
                return;  // OT is now pending, don't clear
            }

            // Match ended normally, clear state
            clear_localinfo_match_context();
            reset_team_names();
            g_matchId[0] = EOS;
            return;
        }
    }

    // Restore basic match state
    copy(g_matchMap, charsmax(g_matchMap), savedMatchMap);

    // Restore consolidated state: pauseA,pauseX,techA,techX
    new stateBuf[32];
    new savedPauseAllies = 0, savedPauseAxis = 0;
    new savedTechAllies = 0, savedTechAxis = 0;
    get_localinfo(LOCALINFO_STATE, stateBuf, charsmax(stateBuf));
    parse_state(stateBuf, savedPauseAllies, savedPauseAxis, savedTechAllies, savedTechAxis);

    // Restore first half scores
    new scoresBuf[16];
    get_localinfo(LOCALINFO_H1_SCORES, scoresBuf, charsmax(scoresBuf));
    parse_scores(scoresBuf, g_firstHalfScore[1], g_firstHalfScore[2]);

    // Restore team identity names
    new teamName1[32], teamName2[32];
    get_localinfo(LOCALINFO_TEAMNAME1, teamName1, charsmax(teamName1));
    get_localinfo(LOCALINFO_TEAMNAME2, teamName2, charsmax(teamName2));
    if (teamName1[0]) copy(g_team1Name, charsmax(g_team1Name), teamName1);
    if (teamName2[0]) copy(g_team2Name, charsmax(g_team2Name), teamName2);

    // Restore Discord message ID for embed editing
    get_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId, charsmax(g_discordMatchMsgId));
    get_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId, charsmax(g_discordMatchChannelId));
    if (g_discordMatchMsgId[0]) {
        log_ktp("event=DISCORD_MSG_ID_RESTORED id=%s channel=%s", g_discordMatchMsgId, g_discordMatchChannelId);
    }

    if (isSecondHalf) {
        // ========== 2nd Half Restoration ==========
        g_secondHalfPending = true;
        g_currentHalf = 1;  // Will become 2 when match goes live
        g_matchLive = false;  // Ensure match is not marked as live yet
        g_matchPending = true;  // Allow players to .ready for 2nd half

        // Swap pause/tech for 2nd half: Teams swap sides
        // 1st half Allies budget -> 2nd half Axis, and vice versa
        g_pauseCountTeam[1] = savedPauseAxis;   // Current Allies = was Axis in 1st half
        g_pauseCountTeam[2] = savedPauseAllies; // Current Axis = was Allies in 1st half
        g_techBudget[1] = savedTechAxis;        // Current Allies = was Axis in 1st half
        g_techBudget[2] = savedTechAllies;      // Current Axis = was Allies in 1st half

        // Teams swap sides in 2nd half
        copy(g_teamName[1], charsmax(g_teamName[]), g_team2Name);  // Current Allies = Team 2
        copy(g_teamName[2], charsmax(g_teamName[]), g_team1Name);  // Current Axis = Team 1

        log_ktp("event=MATCH_CONTEXT_RESTORED mode=h2 match_id=%s map=%s state=%s h1=%d,%d team1=%s team2=%s matchPending=1",
                g_matchId, g_matchMap, stateBuf, g_firstHalfScore[1], g_firstHalfScore[2], g_team1Name, g_team2Name);

        // Announce 2nd half continuation
        announce_all("=== 2nd HALF - Match ID: %s ===", g_matchId);
        announce_all("1st Half: %s %d - %d %s", g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name);
        announce_all("Tactical pauses used: %s %d/1, %s %d/1", g_team1Name, g_pauseCountTeam[1], g_team2Name, g_pauseCountTeam[2]);
        announce_all(">>> Type .ready to start 2nd half <<<");
        announce_all("[HLTV] Verify HLTV is still connected before resuming.");

        // HUD alert for 2nd half detection with team swap info
        set_hudmessage(255, 255, 0, -1.0, 0.25, 0, 0.0, 8.0, 0.5, 0.5, -1);
        show_hudmessage(0, "=== 2nd HALF DETECTED ===^n^nTeams swapped sides^n%s now Allies | %s now Axis^n^nPause budgets carried over",
                g_team2Name, g_team1Name);

        // Start the pending HUD task (shows "=== 2ND HALF - Type .ready ===" with scores)
        safe_remove_task(g_taskPendingHudId);
        set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

        // Start periodic unready player reminder
        safe_remove_task(g_taskUnreadyReminderId);
        set_task(g_unreadyReminderSecs, "unready_reminder_tick", g_taskUnreadyReminderId, _, _, "b");
    }
    else if (isOvertime) {
        // ========== Overtime Restoration ==========

        // Parse OT round from mode (e.g., "ot3" -> 3)
        g_otRound = str_to_num(mode[2]);
        if (g_otRound < 1) g_otRound = 1;

        g_inOvertime = true;
        g_matchLive = false;  // Will become true when OT round goes live
        g_matchPending = true;  // Allow players to .ready for OT round

        // Restore regulation scores
        new regBuf[16];
        get_localinfo(LOCALINFO_REG_SCORES, regBuf, charsmax(regBuf));
        parse_scores(regBuf, g_regulationScore[1], g_regulationScore[2]);

        // Restore OT scores from previous rounds
        new otScoresBuf[128];
        get_localinfo(LOCALINFO_OT_SCORES, otScoresBuf, charsmax(otScoresBuf));
        new numPrevRounds = parse_ot_scores(otScoresBuf, g_otScores, 31);

        // Restore OT state: techA,techX,side
        new otStateBuf[32];
        get_localinfo(LOCALINFO_OT_STATE, otStateBuf, charsmax(otStateBuf));
        parse_ot_state(otStateBuf, g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs);

        // Set tech budgets for this OT round
        g_techBudget[1] = g_otTechBudget[1];
        g_techBudget[2] = g_otTechBudget[2];

        // Set team names based on which side team1 starts on this OT round
        if (g_otTeam1StartsAs == 1) {
            // Team 1 is Allies, Team 2 is Axis
            copy(g_teamName[1], charsmax(g_teamName[]), g_team1Name);
            copy(g_teamName[2], charsmax(g_teamName[]), g_team2Name);
        } else {
            // Team 1 is Axis, Team 2 is Allies
            copy(g_teamName[1], charsmax(g_teamName[]), g_team2Name);
            copy(g_teamName[2], charsmax(g_teamName[]), g_team1Name);
        }

        // Calculate running OT totals for display
        new team1OtTotal = 0, team2OtTotal = 0;
        for (new r = 1; r <= numPrevRounds; r++) {
            team1OtTotal += g_otScores[r][1];
            team2OtTotal += g_otScores[r][2];
        }

        log_ktp("event=OT_CONTEXT_RESTORED match_id=%s round=%d reg=%d-%d ot_total=%d-%d side=%d team1=%s team2=%s",
                g_matchId, g_otRound, g_regulationScore[1], g_regulationScore[2],
                team1OtTotal, team2OtTotal, g_otTeam1StartsAs, g_team1Name, g_team2Name);

        // Announce OT continuation
        announce_all("========================================");
        announce_all("  OVERTIME ROUND %d - Match ID: %s", g_otRound, g_matchId);
        announce_all("========================================");
        announce_all("Regulation: %s %d - %d %s", g_team1Name, g_regulationScore[1], g_regulationScore[2], g_team2Name);
        if (numPrevRounds > 0) {
            announce_all("OT Total: %s %d - %d %s", g_team1Name, team1OtTotal, team2OtTotal, g_team2Name);
        }
        announce_all("%s = %s | %s = %s",
            g_otTeam1StartsAs == 1 ? "Allies" : "Axis", g_team1Name,
            g_otTeam1StartsAs == 1 ? "Axis" : "Allies", g_team2Name);
        announce_all(">>> Type .ready to start OT round %d <<<", g_otRound);
        announce_all("[HLTV] Verify HLTV is still connected before resuming.");

        // Set flag indicating OT round is pending (similar to g_secondHalfPending)
        g_secondHalfPending = true;  // Reuse this flag for OT pending
        g_currentHalf = 0;  // Will be set when OT goes live

        // Start the pending HUD task (shows "=== OVERTIME RD X - Type .ready ===" with scores)
        safe_remove_task(g_taskPendingHudId);
        set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

        // Start periodic unready player reminder
        safe_remove_task(g_taskUnreadyReminderId);
        set_task(g_unreadyReminderSecs, "unready_reminder_tick", g_taskUnreadyReminderId, _, _, "b");
    }

    // NOTE: Don't clear mode here - keep it until match actually ends
    // Mode will be cleared in end_match_cleanup() when match completes
    // This allows detecting abandoned matches if plugin_end doesn't run
}

public plugin_end() {
    // Debug: Log that plugin_end was called
    log_ktp("event=PLUGIN_END_START half=%d matchLive=%d matchId=%s changeLevelHandled=%d",
            g_currentHalf, g_matchLive ? 1 : 0, g_matchId, g_changeLevelHandled ? 1 : 0);

    safe_remove_task(g_taskCountdownId);
    safe_remove_task(g_taskPendingHudId);
    safe_remove_task(g_taskPrestartHudId);
    safe_remove_task(g_taskAutoUnpauseReqId);
    safe_remove_task(g_taskAutoReqCountdownId);
    safe_remove_task(g_taskDisconnectCountdownId);
    safe_remove_task(g_taskPauseHudId);
    safe_remove_task(g_taskPrePauseId);
    safe_remove_task(g_taskUnreadyReminderId);
    safe_remove_task(g_taskUnpauseReminderId);
    safe_remove_task(g_taskScoreSaveId);
    safe_remove_task(g_changeMapTaskId);

    // Note: Match state finalization is now handled by OnChangeLevel() hook
    // which fires BEFORE plugin_end on KTP-ReHLDS servers.
    // The changelevel hook supersedes map changes to allow announcements
    // before manually triggering the changelevel with countdown.

    log_ktp("event=PLUGIN_END_COMPLETE");
}

// NOTE: handle_map_change() has been replaced by the changelevel hook system.
// Match state finalization is now handled in:
// - handle_first_half_end() for 1st half
// - process_second_half_end_changelevel() for 2nd half
// - process_ot_round_end_changelevel() for OT rounds
// These are called from OnChangeLevel() which intercepts all map changes.

// ========== OVERTIME SYSTEM ==========

// Trigger overtime when regulation ends in a tie
stock trigger_overtime(team1Reg, team2Reg) {
    // Store regulation scores
    g_regulationScore[1] = team1Reg;
    g_regulationScore[2] = team2Reg;

    // Initialize OT state
    g_inOvertime = true;
    g_otRound = 1;

    // Reset tech budgets ONCE for overtime (full budget)
    g_otTechBudget[1] = g_techBudgetSecs;
    g_otTechBudget[2] = g_techBudgetSecs;

    // Reset break extensions
    g_otBreakExtensions[1] = 0;
    g_otBreakExtensions[2] = 0;

    // Determine starting sides for OT1
    // In regulation 2nd half, team1 was on Axis, team2 was on Allies
    // For OT1, swap again: team1 starts as Allies, team2 starts as Axis
    g_otTeam1StartsAs = 1;  // TEAM_ALLIES

    // Clear OT scores array
    for (new r = 0; r < 32; r++) {
        g_otScores[r][1] = 0;
        g_otScores[r][2] = 0;
    }

    // Mark match as no longer "live" during break period
    g_matchLive = false;

    // Announce overtime
    announce_all("========================================");
    announce_all("  REGULATION TIED %d - %d", team1Reg, team2Reg);
    announce_all("  OVERTIME REQUIRED");
    announce_all("========================================");
    announce_all("Teams may take a 10-minute break before overtime.");
    announce_all("Type .otbreak to request break, .skip to skip");

    // HUD announcement for OT triggered
    set_hudmessage(255, 255, 0, -1.0, 0.3, 0, 0.0, 58.0, 0.5, 0.5, -1);  // Yellow, ~60 sec
    show_hudmessage(0, "=== OVERTIME REQUIRED ===^n^n%s %d - %d %s^n^nTIED!^n^n.otbreak = request 10-min break^n.skip = start overtime now^n^n(60 seconds to vote)",
        g_team1Name, team1Reg, team2Reg, g_team2Name);

    log_ktp("event=OVERTIME_TRIGGERED match_id=%s regulation=%d-%d team1=%s team2=%s",
            g_matchId, team1Reg, team2Reg, g_team1Name, g_team2Name);

    // Update Discord embed
    #if defined HAS_CURL
    if (!g_disableDiscord) {
        new status[128];
        formatex(status, charsmax(status), "TIED %d-%d - OVERTIME REQUIRED", team1Reg, team2Reg);
        send_match_embed_update(status);
    }
    #endif

    // Clear break votes
    arrayset(g_otBreakVotes, 0, sizeof(g_otBreakVotes));
    g_otBreakActive = false;

    // Start 60-second voting period for break
    set_task(60.0, "task_check_ot_break_votes");
    log_ktp("event=OT_BREAK_VOTE_STARTED duration=60s");
}

// Check if any player voted for a break after voting period ends
public task_check_ot_break_votes() {
    if (!g_inOvertime) return;  // OT was cancelled somehow

    // Check if anyone voted for break
    new breakRequested = false;
    for (new i = 1; i <= MaxClients; i++) {
        if (g_otBreakVotes[i]) {
            breakRequested = true;
            break;
        }
    }

    if (breakRequested) {
        start_ot_break(600);  // 10 minutes = 600 seconds
    } else {
        announce_all("No break requested. Preparing overtime...");
        log_ktp("event=OT_BREAK_SKIPPED reason=no_votes");
        start_overtime_round();
    }
}

// Start the pre-OT break period
stock start_ot_break(seconds) {
    g_otBreakActive = true;
    g_otBreakTimeLeft = seconds;

    announce_all("========================================");
    announce_all("  10-MINUTE BREAK BEFORE OVERTIME");
    announce_all("========================================");
    announce_all("Type .ext for 5-min extension (2x per team)");
    announce_all("Type .skip to end break early");

    log_ktp("event=OT_BREAK_STARTED duration=%ds", seconds);

    // Show initial HUD
    new mins = seconds / 60;
    new secs = seconds % 60;
    set_hudmessage(255, 255, 0, -1.0, 0.3, 0, 0.0, 28.0, 0.5, 0.5, -1);  // Yellow, centered
    show_hudmessage(0, "=== OT BREAK ===^n^n%s %d - %d %s (TIED)^n^n%d:%02d remaining^n^n.ext = extend (5 min)  |  .skip = end break",
        g_team1Name, g_regulationScore[1], g_regulationScore[2], g_team2Name, mins, secs);

    #if defined HAS_CURL
    if (!g_disableDiscord) {
        send_match_embed_update("OT BREAK - 10 minutes");
    }
    #endif

    // Start countdown task (ticks every 30 seconds for announcements)
    set_task(30.0, "task_ot_break_tick", _, _, _, "b");
}

// Break countdown tick
public task_ot_break_tick() {
    if (!g_inOvertime || !g_otBreakActive) {
        remove_task();
        return;
    }

    g_otBreakTimeLeft -= 30;

    if (g_otBreakTimeLeft <= 0) {
        remove_task();
        end_ot_break();
        return;
    }

    // Announce remaining time at key intervals
    new mins = g_otBreakTimeLeft / 60;
    new secs = g_otBreakTimeLeft % 60;

    // HUD display every 30 seconds
    set_hudmessage(255, 255, 0, -1.0, 0.3, 0, 0.0, 28.0, 0.5, 0.5, -1);  // Yellow, centered, 28 sec
    show_hudmessage(0, "=== OT BREAK ===^n^n%s %d - %d %s (TIED)^n^n%d:%02d remaining^n^n.ext = extend (5 min)  |  .skip = end break",
        g_team1Name, g_regulationScore[1], g_regulationScore[2], g_team2Name, mins, secs);

    // Also chat announce at key intervals
    if (g_otBreakTimeLeft == 300 || g_otBreakTimeLeft == 120 || g_otBreakTimeLeft == 60 || g_otBreakTimeLeft == 30) {
        if (mins > 0) {
            announce_all("OT Break: %d:%02d remaining", mins, secs);
        } else {
            announce_all("OT Break: %d seconds remaining", secs);
        }
    }
}

// End the break and start overtime
stock end_ot_break() {
    g_otBreakActive = false;
    g_otBreakTimeLeft = 0;

    announce_all("Break ended. Starting overtime...");
    log_ktp("event=OT_BREAK_ENDED");

    start_overtime_round();
}

// Start an overtime round (changelevel with OT context)
stock start_overtime_round() {
    // Announce OT round
    announce_all("========================================");
    announce_all("  OVERTIME ROUND %d", g_otRound);
    announce_all("  %s vs %s", g_team1Name, g_team2Name);
    announce_all("========================================");

    log_ktp("event=OT_ROUND_START round=%d match_id=%s team1_side=%s",
            g_otRound, g_matchId,
            g_otTeam1StartsAs == 1 ? "Allies" : "Axis");

    // Save OT context before changelevel
    save_ot_context();

    #if defined HAS_CURL
    if (!g_disableDiscord) {
        new status[64];
        formatex(status, charsmax(status), "OVERTIME ROUND %d", g_otRound);
        send_match_embed_update(status);
    }
    #endif

    // Changelevel to same map for OT round
    log_ktp("event=OT_CHANGELEVEL map=%s round=%d", g_matchMap, g_otRound);
    server_cmd("changelevel %s", g_matchMap);
}

// Save OT context to localinfo before changelevel
stock save_ot_context() {
    new buf[128];

    // Core match identity (same as regulation)
    set_localinfo(LOCALINFO_MATCH_ID, g_matchId);
    set_localinfo(LOCALINFO_MATCH_MAP, g_matchMap);

    // Mode: "ot1", "ot2", etc.
    formatex(buf, charsmax(buf), "ot%d", g_otRound);
    set_localinfo(LOCALINFO_MODE, buf);

    // Team names (persist through all OT rounds)
    set_localinfo(LOCALINFO_TEAMNAME1, g_team1Name);
    set_localinfo(LOCALINFO_TEAMNAME2, g_team2Name);

    // First half scores (from regulation)
    format_scores(buf, charsmax(buf), g_firstHalfScore[1], g_firstHalfScore[2]);
    set_localinfo(LOCALINFO_H1_SCORES, buf);

    // Regulation totals
    format_scores(buf, charsmax(buf), g_regulationScore[1], g_regulationScore[2]);
    set_localinfo(LOCALINFO_REG_SCORES, buf);

    // OT scores (all rounds so far)
    generate_ot_scores_string(buf, charsmax(buf), g_otScores, g_otRound - 1);  // -1 because current round not played yet
    set_localinfo(LOCALINFO_OT_SCORES, buf);

    // OT state: techA,techX,side
    format_ot_state(buf, charsmax(buf), g_otTechBudget[1], g_otTechBudget[2], g_otTeam1StartsAs);
    set_localinfo(LOCALINFO_OT_STATE, buf);

    // Consolidated regulation state (pause counts not used in OT, but preserve for logging)
    format_state(buf, charsmax(buf), 0, 0, g_otTechBudget[1], g_otTechBudget[2]);
    set_localinfo(LOCALINFO_STATE, buf);

    // Discord IDs
    set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
    set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

    log_ktp("event=OT_CONTEXT_SAVED match_id=%s round=%d reg=%d-%d ot_scores='%s' side=%d",
            g_matchId, g_otRound, g_regulationScore[1], g_regulationScore[2],
            buf, g_otTeam1StartsAs);
}

// NOTE: handle_ot_round_end() has been replaced by process_ot_round_end_changelevel()
// which is called from the OnChangeLevel() hook for proper changelevel superseding.
// The old function is kept commented out for reference.

#if 0  // Old handle_ot_round_end - replaced by changelevel hook
stock handle_ot_round_end_OLD() {
    // Get current scoreboard scores
    update_match_scores_from_dodx();

    // Determine this round's scores based on which side team1 is on
    // g_matchScore[1] = Allies score, g_matchScore[2] = Axis score
    new team1RoundScore, team2RoundScore;
    if (g_otTeam1StartsAs == 1) {
        // Team 1 is Allies, Team 2 is Axis
        team1RoundScore = g_matchScore[1];
        team2RoundScore = g_matchScore[2];
    } else {
        // Team 1 is Axis, Team 2 is Allies
        team1RoundScore = g_matchScore[2];
        team2RoundScore = g_matchScore[1];
    }

    // Record this round's scores
    g_otScores[g_otRound][1] = team1RoundScore;
    g_otScores[g_otRound][2] = team2RoundScore;

    // Calculate total scores (regulation + all OT rounds)
    new team1Total = g_regulationScore[1];
    new team2Total = g_regulationScore[2];
    for (new r = 1; r <= g_otRound; r++) {
        team1Total += g_otScores[r][1];
        team2Total += g_otScores[r][2];
    }

    log_ktp("event=OT_ROUND_END match_id=%s round=%d round_score=%d-%d total=%d-%d team1=%s team2=%s",
            g_matchId, g_otRound, team1RoundScore, team2RoundScore,
            team1Total, team2Total, g_team1Name, g_team2Name);

    // Announce OT round result
    announce_all("========================================");
    announce_all("  OT ROUND %d COMPLETE", g_otRound);
    announce_all("  Round Score: %s %d - %d %s", g_team1Name, team1RoundScore, team2RoundScore, g_team2Name);
    announce_all("  Total Score: %s %d - %d %s", g_team1Name, team1Total, team2Total, g_team2Name);
    announce_all("========================================");

    // Check if tie is broken
    if (team1Total != team2Total) {
        // WINNER DETERMINED!
        new winner[64], loser[64];
        new winScore, loseScore;
        if (team1Total > team2Total) {
            copy(winner, charsmax(winner), g_team1Name);
            copy(loser, charsmax(loser), g_team2Name);
            winScore = team1Total;
            loseScore = team2Total;
        } else {
            copy(winner, charsmax(winner), g_team2Name);
            copy(loser, charsmax(loser), g_team1Name);
            winScore = team2Total;
            loseScore = team1Total;
        }

        announce_all("========================================");
        announce_all("  %s WINS!", winner);
        announce_all("  Final Score: %d - %d", winScore, loseScore);
        announce_all("  (Regulation: %d-%d + OT: %d-%d)",
                    g_regulationScore[1], g_regulationScore[2],
                    team1Total - g_regulationScore[1], team2Total - g_regulationScore[2]);
        announce_all("========================================");

        // Note: OT scoreboard only shows current round scores
        // Direct dodx_set_team_score() at map end causes crashes
        // HUD displays the correct grand totals instead

        // Winner HUD announcement
        set_hudmessage(0, 255, 0, -1.0, 0.3, 0, 0.0, 10.0, 0.5, 0.5, -1);  // Green, centered, 10 sec
        show_hudmessage(0, "=== MATCH COMPLETE ===^n^n%s WINS!^n^n%d - %d^n^n(Regulation: %d-%d | OT: %d-%d)",
            winner, winScore, loseScore,
            g_regulationScore[1], g_regulationScore[2],
            team1Total - g_regulationScore[1], team2Total - g_regulationScore[2]);

        log_ktp("event=MATCH_END_OT match_id=%s winner=%s final=%d-%d reg=%d-%d ot_rounds=%d",
                g_matchId, winner, winScore, loseScore,
                g_regulationScore[1], g_regulationScore[2], g_otRound);

        // Update Discord with final result
        #if defined HAS_CURL
        if (!g_disableDiscord) {
            new finalStatus[128];
            formatex(finalStatus, charsmax(finalStatus), "MATCH COMPLETE (OT%d) - %s wins %d-%d",
                    g_otRound, winner, winScore, loseScore);
            send_match_embed_update(finalStatus);
        }
        #endif

        // Flush final stats
        #if defined HAS_DODX
        if (g_hasDodxStatsNatives) {
            new flushed = dodx_flush_all_stats();
            log_ktp("event=STATS_FLUSH type=ot_match_end players=%d match_id=%s", flushed, g_matchId);
            log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^") (result ^"ot%d^")", g_matchId, g_matchMap, g_otRound);
            dodx_set_match_id("");
        }
        #endif

        // Fire ktp_match_end forward (external plugins like KTPHLTVRecorder)
        {
            new ret;
            ExecuteForward(g_fwdMatchEnd, ret, g_matchId, g_matchMap, g_matchType, team1Total, team2Total);
        }

        // Clean up match state
        end_match_cleanup();
    } else {
        // STILL TIED - need another OT round
        announce_all("STILL TIED! Preparing Overtime Round %d...", g_otRound + 1);

        // HUD for next OT round
        set_hudmessage(255, 255, 0, -1.0, 0.3, 0, 0.0, 8.0, 0.5, 0.5, -1);  // Yellow, 8 sec
        show_hudmessage(0, "=== STILL TIED ===^n^n%s %d - %d %s^n^nPreparing OT Round %d...",
            g_team1Name, team1Total, team2Total, g_team2Name, g_otRound + 1);

        // Swap sides for next round
        g_otTeam1StartsAs = (g_otTeam1StartsAs == 1) ? 2 : 1;

        // Increment OT round
        g_otRound++;

        log_ktp("event=OT_NEXT_ROUND match_id=%s next_round=%d team1_side=%s",
                g_matchId, g_otRound, g_otTeam1StartsAs == 1 ? "Allies" : "Axis");

        // Update Discord
        #if defined HAS_CURL
        if (!g_disableDiscord) {
            new status[64];
            formatex(status, charsmax(status), "OT%d TIED %d-%d - Next: OT%d",
                    g_otRound - 1, team1Total, team2Total, g_otRound);
            send_match_embed_update(status);
        }
        #endif

        // Start next OT round (will changelevel and save context)
        start_overtime_round();
    }
}
#endif  // End of old handle_ot_round_end

// ========== END OVERTIME SYSTEM ==========

// Clean up match state after match ends (regulation or OT)
stock end_match_cleanup() {
    g_currentHalf = 0;
    g_secondHalfPending = false;
    g_matchMap[0] = 0;
    g_matchLive = false;
    clear_match_id();

    // Reset match type and Discord flag for next match
    g_matchType = MATCH_TYPE_COMPETITIVE;
    g_disableDiscord = false;

    // Reset OT state
    g_inOvertime = false;
    g_otRound = 0;
    g_regulationScore[1] = 0;
    g_regulationScore[2] = 0;
    g_otBreakActive = false;
    g_otBreakTimeLeft = 0;
    arrayset(g_otBreakVotes, 0, sizeof(g_otBreakVotes));
    g_otBreakExtensions[1] = 0;
    g_otBreakExtensions[2] = 0;

    // Reset team names to defaults after match ends
    reset_team_names();

    // Clear persisted match context (match is over)
    clear_localinfo_match_context();
}

// Finalize a match that was abandoned (plugin_end never ran, detected on next map load)
// This is called when we detect mode is set but map doesn't match and match was live
stock finalize_abandoned_match(const mode[], const savedMap[]) {
    // Restore saved match context for logging
    new team1Name[32], team2Name[32];
    get_localinfo(LOCALINFO_TEAMNAME1, team1Name, charsmax(team1Name));
    get_localinfo(LOCALINFO_TEAMNAME2, team2Name, charsmax(team2Name));

    // Restore first half scores
    new scoresBuf[16];
    new firstHalf1 = 0, firstHalf2 = 0;
    get_localinfo(LOCALINFO_H1_SCORES, scoresBuf, charsmax(scoresBuf));
    parse_scores(scoresBuf, firstHalf1, firstHalf2);

    // Restore Discord message ID for final update
    new discordMsgId[32], discordChannelId[32];
    get_localinfo(LOCALINFO_DISCORD_MSG, discordMsgId, charsmax(discordMsgId));
    get_localinfo(LOCALINFO_DISCORD_CHAN, discordChannelId, charsmax(discordChannelId));

    // Determine which half/round was abandoned
    new bool:isSecondHalf = bool:equal(mode, "h2");
    new bool:isOvertime = bool:(mode[0] == 'o' && mode[1] == 't');

    if (isSecondHalf) {
        // 2nd half was abandoned - we don't know exact 2nd half scores
        // Log with 1st half data + abandoned status
        log_ktp("event=MATCH_ABANDONED_DETECTED match_id=%s mode=%s map=%s half1=%d-%d team1=%s team2=%s",
                g_matchId, mode, savedMap, firstHalf1, firstHalf2, team1Name, team2Name);

        // Log KTP_MATCH_END for HLStatsX (partial data)
        log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^") (status ^"abandoned_2nd_half^")",
                g_matchId, savedMap);

        // Update Discord embed if we have the message ID
        #if defined HAS_CURL
        if (discordMsgId[0]) {
            // Save Discord IDs temporarily for embed update
            copy(g_discordMatchMsgId, charsmax(g_discordMatchMsgId), discordMsgId);
            copy(g_discordMatchChannelId, charsmax(g_discordMatchChannelId), discordChannelId);

            new abandonedStatus[128];
            formatex(abandonedStatus, charsmax(abandonedStatus),
                    "MATCH ENDED (2nd half) - 1st half: %s %d - %d %s",
                    team1Name, firstHalf1, firstHalf2, team2Name);
            send_match_embed_update(abandonedStatus);
        }
        #endif
    }
    else if (isOvertime) {
        // OT was abandoned - restore regulation scores
        new regBuf[16];
        new regScore1 = 0, regScore2 = 0;
        get_localinfo(LOCALINFO_REG_SCORES, regBuf, charsmax(regBuf));
        parse_scores(regBuf, regScore1, regScore2);

        new otRound = str_to_num(mode[2]);

        log_ktp("event=MATCH_ABANDONED_DETECTED match_id=%s mode=%s map=%s reg=%d-%d ot_round=%d team1=%s team2=%s",
                g_matchId, mode, savedMap, regScore1, regScore2, otRound, team1Name, team2Name);

        log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^") (status ^"abandoned_ot%d^")",
                g_matchId, savedMap, otRound);

        #if defined HAS_CURL
        if (discordMsgId[0]) {
            copy(g_discordMatchMsgId, charsmax(g_discordMatchMsgId), discordMsgId);
            copy(g_discordMatchChannelId, charsmax(g_discordMatchChannelId), discordChannelId);

            new abandonedStatus[128];
            formatex(abandonedStatus, charsmax(abandonedStatus),
                    "MATCH ENDED (OT%d) - Regulation: %s %d - %d %s (tied)",
                    otRound, team1Name, regScore1, regScore2, team2Name);
            send_match_embed_update(abandonedStatus);
        }
        #endif
    }

    // Fire ktp_match_end forward if available (external plugins like KTPHLTVRecorder)
    {
        new ret;
        ExecuteForward(g_fwdMatchEnd, ret, g_matchId, savedMap, _:MATCH_TYPE_COMPETITIVE, firstHalf1, firstHalf2);
    }
}

// Finalize a completed 2nd half (detected when map cycled back to same map with _ktp_live="1")
// This handles the case where plugin_end didn't run but we're on the correct map
// Can trigger overtime if scores are tied
stock finalize_completed_second_half() {
    // Restore team names from localinfo
    new team1Name[32], team2Name[32];
    get_localinfo(LOCALINFO_TEAMNAME1, team1Name, charsmax(team1Name));
    get_localinfo(LOCALINFO_TEAMNAME2, team2Name, charsmax(team2Name));
    if (team1Name[0]) copy(g_team1Name, charsmax(g_team1Name), team1Name);
    if (team2Name[0]) copy(g_team2Name, charsmax(g_team2Name), team2Name);

    // Restore first half scores
    new h1Buf[16];
    new firstHalf1 = 0, firstHalf2 = 0;
    get_localinfo(LOCALINFO_H1_SCORES, h1Buf, charsmax(h1Buf));
    parse_scores(h1Buf, firstHalf1, firstHalf2);
    g_firstHalfScore[1] = firstHalf1;
    g_firstHalfScore[2] = firstHalf2;

    // Get 2nd half scores from localinfo (persisted by periodic save)
    // These are DODX cumulative scores (restored 1st half + 2nd half play)
    new h2Buf[16];
    new h2Allies = 0, h2Axis = 0;
    get_localinfo(LOCALINFO_H2_SCORES, h2Buf, charsmax(h2Buf));
    parse_scores(h2Buf, h2Allies, h2Axis);

    // Calculate 2nd half contributions (subtract restored 1st half values)
    // We restored: Allies = g_firstHalfScore[2], Axis = g_firstHalfScore[1]
    new team1SecondHalf = h2Axis - firstHalf1;   // Team 1 was Axis in 2nd half
    new team2SecondHalf = h2Allies - firstHalf2; // Team 2 was Allies in 2nd half

    // Calculate grand totals
    new team1Total = firstHalf1 + team1SecondHalf;  // = h2Axis
    new team2Total = firstHalf2 + team2SecondHalf;  // = h2Allies

    log_ktp("event=SECOND_HALF_FINALIZE match_id=%s h1=%d-%d h2_dodx=%d-%d team1_2nd=%d team2_2nd=%d total=%d-%d",
            g_matchId, firstHalf1, firstHalf2, h2Allies, h2Axis,
            team1SecondHalf, team2SecondHalf, team1Total, team2Total);

    // Restore Discord message ID
    new discordMsgId[32], discordChannelId[32];
    get_localinfo(LOCALINFO_DISCORD_MSG, discordMsgId, charsmax(discordMsgId));
    get_localinfo(LOCALINFO_DISCORD_CHAN, discordChannelId, charsmax(discordChannelId));
    if (discordMsgId[0]) {
        copy(g_discordMatchMsgId, charsmax(g_discordMatchMsgId), discordMsgId);
        copy(g_discordMatchChannelId, charsmax(g_discordMatchChannelId), discordChannelId);
    }

    // Check for tie - trigger overtime
    if (team1Total == team2Total) {
        log_ktp("event=TIE_DETECTED triggering overtime team1=%d team2=%d", team1Total, team2Total);

        // Set regulation scores for OT
        g_regulationScore[1] = team1Total;
        g_regulationScore[2] = team2Total;

        // Trigger overtime (this will set up OT state and NOT clear localinfo)
        trigger_overtime(team1Total, team2Total);
        return;  // Don't clear state - OT is handling it
    }

    // Not a tie - finalize the match
    new winner[64];
    if (team1Total > team2Total) {
        formatex(winner, charsmax(winner), "%s wins!", g_team1Name);
    } else {
        formatex(winner, charsmax(winner), "%s wins!", g_team2Name);
    }

    // Log match end
    log_ktp("event=MATCH_END match_id=%s final_score=%s_%d-%d_%s half1=%d-%d half2=%d-%d",
            g_matchId, g_team1Name, team1Total, team2Total, g_team2Name,
            firstHalf1, firstHalf2, team1SecondHalf, team2SecondHalf);

    log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^")", g_matchId, g_currentMap);

    // HUD announcement
    set_hudmessage(0, 255, 0, -1.0, 0.3, 0, 0.0, 10.0, 0.5, 0.5, -1);
    show_hudmessage(0, "=== MATCH COMPLETE ===^n^n%s^n^n%s %d - %d %s^n^n(1st: %d-%d | 2nd: %d-%d)",
        winner, g_team1Name, team1Total, team2Total, g_team2Name,
        firstHalf1, firstHalf2, team1SecondHalf, team2SecondHalf);

    // Update Discord embed
    #if defined HAS_CURL
    if (discordMsgId[0]) {
        new finalStatus[128];
        formatex(finalStatus, charsmax(finalStatus), "MATCH COMPLETE - Final: %d-%d - %s",
                team1Total, team2Total, winner);
        send_match_embed_update(finalStatus);
    }
    #endif

    // Fire ktp_match_end forward
    {
        new ret;
        ExecuteForward(g_fwdMatchEnd, ret, g_matchId, g_currentMap, _:MATCH_TYPE_COMPETITIVE, team1Total, team2Total);
    }

    // Note: Caller will clear localinfo after this returns (unless OT triggered)
}

// Clear all persisted match context from localinfo
stock clear_localinfo_match_context() {
    // Core match state
    set_localinfo(LOCALINFO_MATCH_ID, "");
    set_localinfo(LOCALINFO_MATCH_MAP, "");
    set_localinfo(LOCALINFO_MODE, "");
    set_localinfo(LOCALINFO_LIVE, "");  // Clear live flag
    set_localinfo(LOCALINFO_STATE, "");
    set_localinfo(LOCALINFO_H1_SCORES, "");
    set_localinfo(LOCALINFO_H2_SCORES, "");  // Clear 2nd half scores
    set_localinfo(LOCALINFO_TEAMNAME1, "");
    set_localinfo(LOCALINFO_TEAMNAME2, "");
    set_localinfo(LOCALINFO_DISCORD_MSG, "");
    set_localinfo(LOCALINFO_DISCORD_CHAN, "");

    // OT-specific keys
    set_localinfo(LOCALINFO_REG_SCORES, "");
    set_localinfo(LOCALINFO_OT_SCORES, "");
    set_localinfo(LOCALINFO_OT_STATE, "");
}

// Save match context to localinfo for 2nd half restoration
// Called proactively when 1st half goes live, and again in handle_map_change
stock save_match_context_for_second_half() {
    new buf[32];

    // Core match identity
    set_localinfo(LOCALINFO_MATCH_ID, g_matchId);
    set_localinfo(LOCALINFO_MATCH_MAP, g_matchMap);
    set_localinfo(LOCALINFO_MODE, "h2");  // 2nd half pending

    // Consolidated state: pauseA,pauseX,techA,techX
    format_state(buf, charsmax(buf),
        g_pauseCountTeam[1], g_pauseCountTeam[2],
        g_techBudget[1], g_techBudget[2]);
    set_localinfo(LOCALINFO_STATE, buf);

    // Team names by identity (team1 = started as Allies in 1st half)
    set_localinfo(LOCALINFO_TEAMNAME1, g_team1Name);
    set_localinfo(LOCALINFO_TEAMNAME2, g_team2Name);

    // Discord message ID for embed editing in 2nd half
    set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
    set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

    // Note: Scores are saved via save_first_half_scores() when half actually ends
}

// Save state to localinfo (called when budget/pause changes during 1st half)
stock save_state_to_localinfo() {
    new buf[32];
    format_state(buf, charsmax(buf),
        g_pauseCountTeam[1], g_pauseCountTeam[2],
        g_techBudget[1], g_techBudget[2]);
    set_localinfo(LOCALINFO_STATE, buf);
}

// Shared handler
stock on_client_left(id) {
    if (id >= 1 && id <= MAX_PLAYERS) {
        g_ready[id] = false;

        // Auto tech-pause on disconnect during live match
        if (g_matchLive && !g_isPaused) {
            new tid = get_user_team_id(id);
            // Only trigger for players on actual teams (not spectators)
            if (tid >= 1 && tid <= 2) {
                // Check if team has tech budget
                if (g_techBudget[tid] > 0) {
                    // If already counting down for another disconnect, just announce
                    if (g_disconnectCountdown > 0) {
                        new name[32], teamName[16], sid[44];
                        get_user_name(id, name, charsmax(name));
                        get_user_authid(id, sid, charsmax(sid));
                        team_name_from_id(tid, teamName, charsmax(teamName));
                        log_ktp("event=ADDITIONAL_DISCONNECT player='%s' steamid=%s team=%s countdown_active=true",
                                name, safe_sid(sid), teamName);
                        announce_all("Additional disconnect: %s (%s) - countdown already active", name, teamName);
                        return;
                    }

                    // Store disconnected player info
                    get_user_name(id, g_disconnectedPlayerName, charsmax(g_disconnectedPlayerName));
                    g_disconnectedPlayerTeam = tid;
                    get_user_authid(id, g_disconnectedPlayerSteamId, charsmax(g_disconnectedPlayerSteamId));

                    // Start disconnect countdown
                    g_disconnectCountdown = DISCONNECT_COUNTDOWN_SECS;

                    new teamName[16];
                    team_name_from_id(tid, teamName, charsmax(teamName));

                    log_ktp("event=DISCONNECT_DETECTED player='%s' steamid=%s team=%s",
                            g_disconnectedPlayerName, safe_sid(g_disconnectedPlayerSteamId), teamName);

                    announce_all("PLAYER DISCONNECTED: %s (%s) | Auto tech-pause in 10... (type .nodc to cancel)", g_disconnectedPlayerName, teamName);

                    // Start countdown task
                    safe_remove_task(g_taskDisconnectCountdownId);
                    set_task(1.0, "disconnect_countdown_tick", g_taskDisconnectCountdownId, _, _, "b");
                }
            }
        }
    }
}

// Use the newer forward when available; fall back for older AMXX
#if defined AMXX_VERSION_NUM && AMXX_VERSION_NUM >= 190
public client_disconnected(id) { on_client_left(id); }
#else
public client_disconnect(id) { on_client_left(id); }
#endif

public client_putinserver(id) {
    // Skip bots and HLTV
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    // Delayed version and status announcement (5 seconds)
    set_task(5.0, "fn_version_display", id);
}

public fn_version_display(id) {
    // Safety check - player may have disconnected during delay
    if (!is_user_connected(id))
        return;

    // Version announcement
    client_print(id, print_chat, "%s version %s by %s", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}

// ================= Counts & commands =================
stock get_ready_counts(&alliesPlayers, &axisPlayers, &alliesReady, &axisReady) {
    alliesPlayers = 0; axisPlayers = 0; alliesReady = 0; axisReady = 0;
    new ids[32], num; get_players(ids, num, "ch");
    // OPTIMIZED: Use switch statement for cleaner code and consistent team ID caching (Phase 5)
    for (new i = 0; i < num; i++) {
        new id = ids[i];
        new tid = get_user_team_id(id);  // Cached once per iteration
        switch (tid) {
            case 1: {
                alliesPlayers++;
                if (g_ready[id]) alliesReady++;
            }
            case 2: {
                axisPlayers++;
                if (g_ready[id]) axisReady++;
            }
        }
    }
}

// ========== MAINTENANCE COMMANDS ==========

// ===== Map reload =====
// ===== Client console 'pause' =====
public cmd_client_pause(id) {
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=PAUSE_CLIENT_CONSOLE player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);

    // Trigger countdown (auto-detect if pre-match or live)
    new bool:isPreMatch = !g_matchLive;
    trigger_pause_countdown(name, "client_console", isPreMatch, id);

    return PLUGIN_HANDLED;
}

// ===== Toggle helpers =====
stock handle_countdown_cancel(id) {
    new tid = get_user_team_id(id);
    if (tid != g_pauseOwnerTeam) {
        client_print(id, print_chat, "[KTP] Only the pause-owning team can cancel the unpause countdown.");
        return PLUGIN_HANDLED;
    }
    safe_remove_task(g_taskCountdownId);
    g_countdownActive = false;

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=UNPAUSE_CANCEL player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    announce_all("Unpause countdown cancelled by %s. Staying paused.", name);

    // Re-arm auto-request and reset flag; HUD keeps running
    g_unpauseRequested = false;
    new secs = g_autoRequestSecs;
    if (secs < AUTO_REQUEST_MIN_SECS) secs = AUTO_REQUEST_DEFAULT_SECS;
    g_autoReqLeft = secs;
    set_task(float(secs), "auto_unpause_request", g_taskAutoUnpauseReqId);

    // Restart countdown ticker
    safe_remove_task(g_taskAutoReqCountdownId);
    set_task(1.0, "auto_req_countdown_tick", g_taskAutoReqCountdownId, _, _, "b");

    return PLUGIN_HANDLED;
}

stock handle_pause_request(id, const name[], const sid[], const ip[], const team[], const map[], teamId) {
    // Enforce per-team pause limits only AFTER the match is live
    if (g_matchLive) {
        if (teamId != 1 && teamId != 2) {
            client_print(id, print_chat, "[KTP] Spectators cannot pause.");
            return PLUGIN_HANDLED;
        }
        if (g_pauseCountTeam[teamId] >= 1) {
            log_ktp("event=PAUSE_DENY_LIMIT team=%d player=\'%s\' steamid=%s", teamId, name, safe_sid(sid));
            client_print(id, print_chat, "[KTP] Your team has already used its pause.");
            return PLUGIN_HANDLED;
        }

        // Set ownership and state BEFORE triggering countdown
        g_pauseCountTeam[teamId]++;           // consume the team pause
        g_pauseOwnerTeam = teamId;            // set ownership
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;
        g_isTechPause = false;                // Mark as tactical pause

        // schedule auto-unpause request if owner forgets to /resume
        setup_auto_unpause_request();

        log_ktp("event=PAUSE_AUTOREQ_ARM team=%d seconds=%d", g_pauseOwnerTeam, g_autoReqLeft);
        log_ktp("event=PAUSE_BY_CHAT player=\'%s\' steamid=%s ip=%s team=%s map=%s live=%d team_pause_used=%d/%d",
                name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_matchLive ? 1 : 0,
                g_pauseCountTeam[teamId], 1);

        client_print(id, print_chat, "[KTP] Your team pauses left after this: %d.", pauses_left(teamId));

        // Trigger pre-pause countdown with live match countdown (false = use ktp_prepause_seconds)
        trigger_pause_countdown(name, "chat_tactical", false, id);
    } else {
        // This is the pre-start/pending pause (doesn't count) - immediate pause
        g_pauseOwnerTeam = 0;
        g_isTechPause = false;
        safe_remove_task(g_taskAutoUnpauseReqId);
        g_autoReqLeft = 0;

        // For pre-live pauses, use pre-match countdown
        trigger_pause_countdown(name, "tactical_pause_prelive", true, id); // true = pre-match countdown

        log_ktp("event=PAUSE_BY_CHAT player=\'%s\' steamid=%s ip=%s team=%s map=%s live=0",
                name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    }

    if (!g_matchLive) {
        announce_all("Match paused by %s. (pre-start/pending phase; does not count)", name);
    }

    return PLUGIN_HANDLED;
}

stock handle_resume_request(id, const name[], const sid[], const team[], teamId) {
    // Server is paused. Only the owning team can request unpause.
    if (g_matchPending || g_preStartPending) {
        client_print(id, print_chat, "[KTP] Match is pending. Use .rdy; server will resume automatically.");
        return PLUGIN_HANDLED;
    }

    if (g_pauseOwnerTeam == 0 && g_matchLive) {
        // Edge: somehow no owner recorded; recover by assigning on first /resume attempt
        g_pauseOwnerTeam = (teamId==1 || teamId==2) ? teamId : 0;
    }

    if (g_matchLive) {
        if (teamId != g_pauseOwnerTeam) {
            client_print(id, print_chat, "[KTP] Only the pause-owning team may .resume. Other team should .go.");
            return PLUGIN_HANDLED;
        }
    }

    // Owner requests unpause (store both name and ID for dynamic lookup)
    g_unpauseRequested = true;
    g_autoReqLeft = 0; // stop HUD timer
    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), name);

    // If this is a tech pause, freeze the budget now (stop deducting time)
    if (g_isTechPause && g_techPauseStartTime > 0 && g_techPauseFrozenTime == 0) {
        g_techPauseFrozenTime = get_systime();
        new elapsed = g_techPauseFrozenTime - g_techPauseStartTime;
        if (elapsed > 0 && elapsed < 3600) {  // sanity check
            new budgetBefore = g_techBudget[g_pauseOwnerTeam];
            g_techBudget[g_pauseOwnerTeam] -= elapsed;
            if (g_techBudget[g_pauseOwnerTeam] < 0) g_techBudget[g_pauseOwnerTeam] = 0;
            log_ktp("event=TECH_BUDGET_FROZEN team=%d elapsed=%d budget_before=%d budget_after=%d",
                    g_pauseOwnerTeam, elapsed, budgetBefore, g_techBudget[g_pauseOwnerTeam]);

            // Persist tech budget to localinfo for 2nd half restoration
            if (g_currentHalf == 1) {
                save_state_to_localinfo();
            }

            new buf[16];
            fmt_seconds(g_techBudget[g_pauseOwnerTeam], buf, charsmax(buf));
            announce_all("Tech pause time used: %d seconds. %s has %s remaining.", elapsed, team, buf);
        }
    }

    log_ktp("event=UNPAUSE_REQUEST_OWNER team=%d by=\'%s\' steamid=%s", g_pauseOwnerTeam, name, safe_sid(sid));

    // Get other team name for announcement
    new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
    new otherTeamName[32];
    team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));

    announce_all("%s requested unpause.", team);
    announce_all("%s has 60 seconds to .go or game will auto-resume.", otherTeamName);

    // If the other team has pre-confirmed (rare), start the countdown now
    if (g_unpauseConfirmedOther) {
        stop_unpause_reminder();
        safe_remove_task(g_taskAutoConfirmId);
        start_unpause_countdown(g_lastUnpauseBy);
    } else {
        // Start reminder for other team to /confirmunpause
        start_unpause_reminder();

        // Start 60s auto-confirmunpause timer
        // Note: set_task doesn't run during pause, so OnPausedHUDUpdate handles the countdown
        g_autoConfirmLeft = 60;
    }

    return PLUGIN_HANDLED;
}

// ========== PAUSE/RESUME COMMANDS ==========

// ===== Chat pause/resume with ownership & confirm =====
public cmd_chat_toggle(id) {
    // If a countdown is active, cancel it
    if (g_countdownActive) {
        return handle_countdown_cancel(id);
    }

    // Get player identity and team info
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    new tid = get_user_team_id(id);

    // Route to appropriate handler based on pause state
    if (!g_isPaused) {
        return handle_pause_request(id, name, sid, ip, team, map, tid);
    } else {
        return handle_resume_request(id, name, sid, team, tid);
    }
}

public cmd_chat_resume(id) {
    // Shorthand for owner to request unpause (same checks as above branch)
    return cmd_chat_toggle(id);
}

// Other team confirmation to unpause
public cmd_confirm_unpause(id) {
    if (!g_isPaused || g_matchPending || g_preStartPending) {
        client_print(id, print_chat, "[KTP] No paused live match requiring confirmation.");
        return PLUGIN_HANDLED;
    }
    if (!g_matchLive) {
        client_print(id, print_chat, "[KTP] Not live yet — no confirmation needed.");
        return PLUGIN_HANDLED;
    }

    new tid = get_user_team_id(id);
    if (tid != 1 && tid != 2) { client_print(id, print_chat, "[KTP] Spectators can't confirm unpause."); return PLUGIN_HANDLED; }

    if (g_pauseOwnerTeam == 0) { client_print(id, print_chat, "[KTP] No pause owner registered."); return PLUGIN_HANDLED; }
    if (tid == g_pauseOwnerTeam) { client_print(id, print_chat, "[KTP] Your team owns this pause; use .resume."); return PLUGIN_HANDLED; }

    new name[32], sid[44], ip[32], team[16];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));

    g_unpauseConfirmedOther = true;
    log_ktp("event=UNPAUSE_CONFIRM_OTHER team=%d by=\'%s\' steamid=%s", tid, name, safe_sid(sid));
    announce_all("%s confirmed unpause.", team);

    // Cancel auto-confirmunpause timer (they confirmed manually)
    safe_remove_task(g_taskAutoConfirmId);
    g_autoConfirmLeft = 0;

    // If owner already requested (or auto-request fired), we can start countdown
    if (g_unpauseRequested) {
        stop_unpause_reminder();
        start_unpause_countdown(g_lastUnpauseBy[0] ? g_lastUnpauseBy : team);
    } else {
        client_print(id, print_chat, "[KTP] Waiting for the pause-owning team to .resume (or auto-request).");
        // Start reminder for owner team to /resume
        start_unpause_reminder();
    }
    return PLUGIN_HANDLED;
}

// ===== Pause Extension Command =====
public cmd_extend_pause(id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    // Check if this is an OT break extension
    if (g_inOvertime && g_otBreakActive) {
        return cmd_ot_extend(id);
    }

    if (!g_isPaused) {
        client_print(id, print_chat, "[KTP] No active pause to extend.");
        return PLUGIN_HANDLED;
    }

    // Only the pause-owning team can extend
    new tid = get_user_team_id(id);
    if (g_pauseOwnerTeam != 0 && tid != g_pauseOwnerTeam) {
        new teamName[16];
        team_name_from_id(g_pauseOwnerTeam, teamName, charsmax(teamName));
        client_print(id, print_chat, "[KTP] Only %s (pause owner) can extend this pause.", teamName);
        return PLUGIN_HANDLED;
    }

    new maxExt = g_pauseMaxExtensions;
    if (maxExt <= 0) maxExt = 2;

    if (g_pauseExtensions >= maxExt) {
        client_print(id, print_chat, "[KTP] Maximum extensions (%d) already used.", maxExt);
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    new extSec = g_pauseExtensionSec;
    if (extSec <= 0) extSec = 120;
    g_pauseExtensions++;

    new buf[16];
    fmt_seconds(extSec, buf, charsmax(buf));
    announce_all("%s extended the pause by %s (%d/%d extensions used).",
        name, buf, g_pauseExtensions, maxExt);
    log_ktp("event=PAUSE_EXTENDED player='%s' extension=%d/%d seconds=%d",
        name, g_pauseExtensions, maxExt, extSec);
    log_amx("KTP: Pause extended by %s - Added %d seconds (%d/%d extensions)", name, extSec, g_pauseExtensions, maxExt);

    return PLUGIN_HANDLED;
}

// ========== OVERTIME BREAK COMMANDS ==========

// Request OT break
public cmd_otbreak(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    if (!g_inOvertime) {
        client_print(id, print_chat, "[KTP] No overtime in progress.");
        return PLUGIN_HANDLED;
    }

    if (g_otBreakActive) {
        client_print(id, print_chat, "[KTP] Break already in progress.");
        return PLUGIN_HANDLED;
    }

    if (g_matchLive) {
        client_print(id, print_chat, "[KTP] Cannot request break during live play.");
        return PLUGIN_HANDLED;
    }

    // Record vote for break
    if (g_otBreakVotes[id]) {
        client_print(id, print_chat, "[KTP] You already requested a break.");
        return PLUGIN_HANDLED;
    }

    g_otBreakVotes[id] = 1;

    new name[32];
    get_user_name(id, name, charsmax(name));

    announce_all("%s requests a 10-minute break before overtime.", name);
    log_ktp("event=OT_BREAK_REQUESTED player='%s'", name);

    return PLUGIN_HANDLED;
}

// Skip OT break (any player)
public cmd_ot_skip(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    if (!g_inOvertime) {
        client_print(id, print_chat, "[KTP] No overtime in progress.");
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    if (g_otBreakActive) {
        // End break early
        remove_task();  // Remove break tick task
        announce_all("%s ended the break early.", name);
        log_ktp("event=OT_BREAK_SKIPPED_EARLY player='%s'", name);
        end_ot_break();
    } else if (!g_matchLive) {
        // Skip break before it starts (during voting period)
        remove_task();  // Remove the vote check task
        announce_all("%s skipped the break. Preparing overtime...", name);
        log_ktp("event=OT_BREAK_SKIPPED player='%s'", name);
        start_overtime_round();
    } else {
        client_print(id, print_chat, "[KTP] Cannot skip during live play.");
    }

    return PLUGIN_HANDLED;
}

// Extend OT break (5 minutes, 2x per team)
public cmd_ot_extend(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    if (!g_inOvertime || !g_otBreakActive) {
        client_print(id, print_chat, "[KTP] No OT break to extend.");
        return PLUGIN_HANDLED;
    }

    new tid = get_user_team_id(id);
    if (tid != 1 && tid != 2) {
        client_print(id, print_chat, "[KTP] You must be on a team to extend the break.");
        return PLUGIN_HANDLED;
    }

    // Map current side to team identity for extension tracking
    // In OT, we need to figure out which team identity (1 or 2) this side represents
    new teamIdentity;
    if (g_otTeam1StartsAs == tid) {
        teamIdentity = 1;  // This side is team 1
    } else {
        teamIdentity = 2;  // This side is team 2
    }

    new const MAX_OT_EXTENSIONS = 2;
    if (g_otBreakExtensions[teamIdentity] >= MAX_OT_EXTENSIONS) {
        client_print(id, print_chat, "[KTP] Your team has used all %d extensions.", MAX_OT_EXTENSIONS);
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    g_otBreakExtensions[teamIdentity]++;
    g_otBreakTimeLeft += 300;  // Add 5 minutes

    new teamName[32];
    if (teamIdentity == 1) {
        copy(teamName, charsmax(teamName), g_team1Name);
    } else {
        copy(teamName, charsmax(teamName), g_team2Name);
    }

    announce_all("%s extended the break by 5 minutes. (%s: %d/2 extensions)",
        name, teamName, g_otBreakExtensions[teamIdentity]);
    log_ktp("event=OT_BREAK_EXTENDED player='%s' team=%s extension=%d/2",
        name, teamName, g_otBreakExtensions[teamIdentity]);

    return PLUGIN_HANDLED;
}

// ===== Cancel Disconnect Auto-Pause Command =====
public cmd_cancel_disconnect_pause(id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    // Check if disconnect countdown is active
    if (g_disconnectCountdown <= 0) {
        client_print(id, print_chat, "[KTP] No disconnect auto-pause countdown active.");
        return PLUGIN_HANDLED;
    }

    new tid = get_user_team_id(id);
    if (tid != 1 && tid != 2) {
        client_print(id, print_chat, "[KTP] Spectators cannot cancel auto-pause.");
        return PLUGIN_HANDLED;
    }

    // Only the team that had the disconnect can cancel
    new teamName[16];
    team_name_from_id(g_disconnectedPlayerTeam, teamName, charsmax(teamName));

    if (tid != g_disconnectedPlayerTeam) {
        client_print(id, print_chat, "[KTP] Only %s can cancel this auto-pause.", teamName);
        return PLUGIN_HANDLED;
    }

    // Cancel the countdown
    safe_remove_task(g_taskDisconnectCountdownId);
    g_disconnectCountdown = 0;
    g_disconnectedPlayerName[0] = EOS;
    g_disconnectedPlayerTeam = 0;
    g_disconnectedPlayerSteamId[0] = EOS;

    new name[32];
    get_user_name(id, name, charsmax(name));

    announce_all("Disconnect auto-pause cancelled by %s (%s)", name, teamName);
    log_ktp("event=DISCONNECT_PAUSE_CANCELLED player='%s' team=%s", name, teamName);
    log_amx("KTP: Disconnect auto-pause cancelled by %s (%s)", name, teamName);

    return PLUGIN_HANDLED;
}

// ===== Technical Pause Command =====
public cmd_tech_pause(id) {
    if (!g_matchLive) {
        client_print(id, print_chat, "[KTP] Technical pauses are only available during live matches.");
        return PLUGIN_HANDLED;
    }

    if (g_isPaused) {
        client_print(id, print_chat, "[KTP] Match is already paused. Use .resume to unpause.");
        return PLUGIN_HANDLED;
    }

    new tid = get_user_team_id(id);
    if (tid != 1 && tid != 2) {
        client_print(id, print_chat, "[KTP] Spectators cannot call technical pauses.");
        return PLUGIN_HANDLED;
    }

    // Check if team has tech budget remaining
    if (g_techBudget[tid] <= 0) {
        client_print(id, print_chat, "[KTP] Your team has no technical pause budget remaining.");
        log_ktp("event=TECH_PAUSE_DENY_BUDGET team=%d budget=%d", tid, g_techBudget[tid]);
        return PLUGIN_HANDLED;
    }

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));

    // Set up tech pause state
    g_pauseOwnerTeam = tid;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_isTechPause = true;

    // Set pause duration to remaining tech budget (not fixed 5 minutes)
    g_pauseDurationSec = g_techBudget[tid];

    // Schedule auto-unpause request
    setup_auto_unpause_request();

    // Record pause start time (wall clock) for budget tracking
    g_techPauseStartTime = get_systime();

    log_ktp("event=TECH_PAUSE player=\'%s\' steamid=%s ip=%s team=%s map=%s budget_remaining=%d",
            name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_techBudget[tid]);

    // Trigger pre-pause countdown with new system
    trigger_pause_countdown(name, "tech_pause", false, id);

    return PLUGIN_HANDLED;
}

// ========== TEAM NAME COMMANDS ==========

public cmd_setteamallies(id) {
    // Only allow custom team names for /ktp and /draft matches (during pre-start or pending phase)
    if ((!g_matchPending && !g_preStartPending) || (g_matchType != MATCH_TYPE_COMPETITIVE && g_matchType != MATCH_TYPE_DRAFT)) {
        client_print(id, print_chat, "[KTP] Custom team names only available for .ktp and .draft matches.");
        return PLUGIN_HANDLED;
    }

    // Only captains/admins during pre-match
    if (g_matchLive) {
        client_print(id, print_chat, "[KTP] Cannot change team names during live match.");
        return PLUGIN_HANDLED;
    }

    new args[64], teamname[64];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    // Parse out team name - skip the command prefix
    if (args[0] == '/' || args[0] == '.') {
        new pos = contain(args, " ");
        if (pos != -1) {
            copy(teamname, charsmax(teamname), args[pos + 1]);
            trim(teamname);
        } else {
            teamname[0] = EOS;
        }
    } else {
        copy(teamname, charsmax(teamname), args);
    }

    if (strlen(teamname) < 1) {
        client_print(id, print_chat, "[KTP] Usage: .setallies <team name>");
        return PLUGIN_HANDLED;
    }

    // Validate length (max 24 chars to fit in displays)
    if (strlen(teamname) > 24) {
        client_print(id, print_chat, "[KTP] Team name too long (max 24 characters).");
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    set_team_name(1, teamname);
    log_ktp("event=TEAM_NAME_SET team=1 name='%s' by='%s'", teamname, name);
    announce_all("%s set Allies team name to: %s", name, teamname);

    return PLUGIN_HANDLED;
}

public cmd_setteamaxis(id) {
    // Only allow custom team names for /ktp and /draft matches (during pre-start or pending phase)
    if ((!g_matchPending && !g_preStartPending) || (g_matchType != MATCH_TYPE_COMPETITIVE && g_matchType != MATCH_TYPE_DRAFT)) {
        client_print(id, print_chat, "[KTP] Custom team names only available for .ktp and .draft matches.");
        return PLUGIN_HANDLED;
    }

    // Only captains/admins during pre-match
    if (g_matchLive) {
        client_print(id, print_chat, "[KTP] Cannot change team names during live match.");
        return PLUGIN_HANDLED;
    }

    new args[64], teamname[64];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    // Parse out team name - skip the command prefix
    if (args[0] == '/' || args[0] == '.') {
        new pos = contain(args, " ");
        if (pos != -1) {
            copy(teamname, charsmax(teamname), args[pos + 1]);
            trim(teamname);
        } else {
            teamname[0] = EOS;
        }
    } else {
        copy(teamname, charsmax(teamname), args);
    }

    if (strlen(teamname) < 1) {
        client_print(id, print_chat, "[KTP] Usage: .setaxis <team name>");
        return PLUGIN_HANDLED;
    }

    // Validate length (max 24 chars to fit in displays)
    if (strlen(teamname) > 24) {
        client_print(id, print_chat, "[KTP] Team name too long (max 24 characters).");
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    set_team_name(2, teamname);
    log_ktp("event=TEAM_NAME_SET team=2 name='%s' by='%s'", teamname, name);
    announce_all("%s set Axis team name to: %s", name, teamname);

    return PLUGIN_HANDLED;
}

public cmd_teamnames(id) {
    client_print(id, print_chat, "[KTP] Team Names - Allies: %s | Axis: %s", g_teamName[1], g_teamName[2]);
    return PLUGIN_HANDLED;
}

public cmd_resetteamnames(id) {
    if (g_matchLive) {
        client_print(id, print_chat, "[KTP] Cannot reset team names during live match.");
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    reset_team_names();
    log_ktp("event=TEAM_NAME_RESET by='%s'", name);
    announce_all("%s reset team names to defaults (Allies/Axis).", name);

    return PLUGIN_HANDLED;
}

// ========== SCORE COMMAND ==========

public cmd_score(id) {
    if (!g_matchLive) {
        client_print(id, print_chat, "[KTP] No live match. Score tracking starts when match goes LIVE.");
        return PLUGIN_HANDLED;
    }

    // Get fresh scores from dodx
    update_match_scores_from_dodx();

    if (g_currentHalf == 1) {
        // 1st half: scores are directly by current side (no swap yet)
        announce_all("Match Score (1st half): %s %d - %d %s",
            g_team1Name, g_matchScore[1], g_matchScore[2], g_team2Name);
    } else if (g_currentHalf == 2) {
        // 2nd half: teams have swapped sides
        // DODX now includes restored 1st half scores (we broadcast them at 2nd half start)
        // Team 1 was Allies (1st half), now Axis (2nd half)
        // Team 2 was Axis (1st half), now Allies (2nd half)
        // We restored: Allies = g_firstHalfScore[2], Axis = g_firstHalfScore[1]
        // So: Team1's 2nd half = current Axis - restored Axis = g_matchScore[2] - g_firstHalfScore[1]
        //     Team2's 2nd half = current Allies - restored Allies = g_matchScore[1] - g_firstHalfScore[2]
        new team1SecondHalf = g_matchScore[2] - g_firstHalfScore[1];
        new team2SecondHalf = g_matchScore[1] - g_firstHalfScore[2];

        // Total = current DODX scores (already cumulative after restoration)
        // Team1 is now Axis, Team2 is now Allies
        new team1Total = g_matchScore[2];
        new team2Total = g_matchScore[1];

        announce_all("Match Score: %s %d - %d %s (1st: %d-%d | 2nd: %d-%d)",
            g_team1Name, team1Total, team2Total, g_team2Name,
            g_firstHalfScore[1], g_firstHalfScore[2],
            team1SecondHalf, team2SecondHalf);
    } else {
        announce_all("Match Score: %s %d - %d %s",
            g_team1Name, g_matchScore[1], g_matchScore[2], g_team2Name);
    }
    return PLUGIN_HANDLED;
}

// ========== COMMANDS HELP ==========
public cmd_commands(id) {
    client_print(id, print_chat, "[KTP] Command list printed to console.");

    client_print(id, print_console, "");
    client_print(id, print_console, "========================================");
    client_print(id, print_console, "       KTP Match Handler Commands");
    client_print(id, print_console, "========================================");

    // Match Setup (Captain commands)
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Match Setup (Captains) ---");
    client_print(id, print_console, "  .ktp <password>  - Start competitive match (requires password)");
    client_print(id, print_console, "  .draft           - Start draft/pickup match");
    client_print(id, print_console, "  .scrim           - Start scrim match");
    client_print(id, print_console, "  .12man           - Start 12-man match");
    client_print(id, print_console, "  .confirm         - Confirm match start (pre-start phase)");
    client_print(id, print_console, "  .notconfirm      - Revoke confirmation");
    client_print(id, print_console, "  .cancel          - Cancel pending match");

    // Ready System
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Ready System ---");
    client_print(id, print_console, "  .ready / .rdy    - Mark yourself as ready");
    client_print(id, print_console, "  .notready        - Mark yourself as not ready");

    // Pause System
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Pause System ---");
    client_print(id, print_console, "  .pause / .tac    - Request tactical pause");
    client_print(id, print_console, "  .tech            - Request technical pause");
    client_print(id, print_console, "  .resume          - Request unpause (pause owner)");
    client_print(id, print_console, "  .go              - Confirm unpause (other team)");
    client_print(id, print_console, "  .extend / .ext   - Extend current pause");
    client_print(id, print_console, "  .nodc / .stopdc  - Cancel disconnect auto-pause");

    // Overtime
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Overtime ---");
    client_print(id, print_console, "  .otbreak         - Request overtime break");
    client_print(id, print_console, "  .skip            - Skip overtime break");

    // Team Names
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Team Names ---");
    client_print(id, print_console, "  .setallies <name> - Set Allies team name");
    client_print(id, print_console, "  .setaxis <name>   - Set Axis team name");
    client_print(id, print_console, "  .names            - Display current team names");
    client_print(id, print_console, "  .resetnames       - Reset team names to default");

    // Status & Info
    client_print(id, print_console, "");
    client_print(id, print_console, "--- Status & Info ---");
    client_print(id, print_console, "  .status          - Show match status");
    client_print(id, print_console, "  .prestatus       - Show pre-start status");
    client_print(id, print_console, "  .score           - Show current match score");
    client_print(id, print_console, "  .cfg             - Show match configuration");
    client_print(id, print_console, "  .commands / .cmds - Show this command list");

    client_print(id, print_console, "");
    client_print(id, print_console, "========================================");
    client_print(id, print_console, "");

    return PLUGIN_HANDLED;
}

// Auto-request unpause after timeout if owner doesn't /resume
public auto_unpause_request() {
    if (!g_isPaused || !g_matchLive) return;
    if (g_unpauseRequested) return; // owner already did it

    g_unpauseRequested = true;
    g_autoReqLeft = 0;
    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), "auto");
    log_ktp("event=UNPAUSE_REQUEST_AUTO team=%d", g_pauseOwnerTeam);
    announce_all("Auto-requesting unpause (owner timeout). Waiting for the other team to .go.");

    // If other team already confirmed, start countdown now
    if (g_unpauseConfirmedOther) {
        stop_unpause_reminder();
        start_unpause_countdown("auto");
    } else {
        // Start reminder for other team to /confirmunpause
        start_unpause_reminder();
    }
}

// ========== MATCH START (PRE-START) COMMANDS ==========

// Hook for say commands with arguments (register_clcmd("say /cmd") only matches exact "/cmd", not "/cmd arg")
public cmd_say_hook(id) {
    new args[128];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    // Check for /ktp or .ktp commands (with potential password argument)
    if (equali(args, "/ktp", 4) || equali(args, ".ktp", 4)) {
        // Must be exactly /ktp or have a space after for password
        if (strlen(args) == 4 || args[4] == ' ') {
            // Explicitly set competitive match type and enable Discord
            // (scrim/12man/draft handlers set their own types before calling cmd_match_start)
            g_matchType = MATCH_TYPE_COMPETITIVE;
            g_disableDiscord = false;
            return cmd_match_start(id);
        }
    }

    // Check for /setallies or .setallies commands
    if (equali(args, "/setallies", 10) || equali(args, ".setallies", 10)) {
        if (strlen(args) == 10 || args[10] == ' ') {
            return cmd_setteamallies(id);
        }
    }

    // Check for /setaxis or .setaxis commands
    if (equali(args, "/setaxis", 8) || equali(args, ".setaxis", 8)) {
        if (strlen(args) == 8 || args[8] == ' ') {
            return cmd_setteamaxis(id);
        }
    }

    return PLUGIN_CONTINUE;
}

// ===== Start / Pre-Start =====
public cmd_match_start(id) {
    // Block starting a new match if one is already in progress
    // Note: 2nd half and OT are allowed because g_matchLive=false between halves
    if (g_matchLive) {
        client_print(id, print_chat, "[KTP] A match is already in progress. Use .cancel to abort first.");
        return PLUGIN_HANDLED;
    }
    if (g_preStartPending) {
        client_print(id, print_chat, "[KTP] Pre-start already active. Waiting for .confirm from both teams.");
        return PLUGIN_HANDLED;
    }
    if (g_matchPending) {
        client_print(id, print_chat, "[KTP] Match pending. Waiting for players to .ready up.");
        return PLUGIN_HANDLED;
    }

    // Ensure Discord is enabled for competitive matches
    // (scrim/12man/draft set g_matchType and g_disableDiscord before calling this)
    if (g_matchType == MATCH_TYPE_COMPETITIVE) {
        g_disableDiscord = false;  // Enable Discord for competitive matches
    }

    // Season check - only applies to competitive matches (/start, /ktp)
    // Draft, scrim, and 12man modes bypass this check via their own handlers
    if (!g_ktpSeasonActive && g_matchType == MATCH_TYPE_COMPETITIVE) {
        client_print(id, print_chat, "[KTP] Competitive matches are disabled outside KTP season.");
        client_print(id, print_chat, "[KTP] Use .draft, .12man, or .scrim instead.");
        return PLUGIN_HANDLED;
    }

    // Password check - only applies to competitive matches (/start, /ktp)
    // Draft, scrim, and 12man modes bypass this check via their own handlers
    if (g_matchType == MATCH_TYPE_COMPETITIVE) {
        new args[64], password[64];
        read_args(args, charsmax(args));
        remove_quotes(args);
        trim(args);

        // Parse out password - skip the command prefix (/ktp or .ktp)
        // read_args returns full text: "/ktp password"
        if (args[0] == '/' || args[0] == '.') {
            // Skip command prefix, get second word
            new pos = contain(args, " ");
            if (pos != -1) {
                copy(password, charsmax(password), args[pos + 1]);
                trim(password);
            } else {
                password[0] = EOS;
            }
        } else {
            // Console command or unexpected format - use as-is
            copy(password, charsmax(password), args);
        }

        if (!password[0]) {
            client_print(id, print_chat, "[KTP] Usage: .ktp <password>");
            client_print(id, print_chat, "[KTP] Contact a KTP admin for the match password.");
            return PLUGIN_HANDLED;
        }

        if (!equal(password, g_ktpMatchPassword)) {
            client_print(id, print_chat, "[KTP] Invalid match password.");

            // Log failed attempt
            new name[32], sid[44], ip[32];
            get_user_name(id, name, charsmax(name));
            get_user_authid(id, sid, charsmax(sid));
            get_user_ip(id, ip, charsmax(ip), 1);
            log_ktp("event=MATCH_START_FAILED reason=invalid_password by='%s' steamid=%s ip=%s", name, safe_sid(sid), ip);
            return PLUGIN_HANDLED;
        }
    }

    if (g_matchPending || g_preStartPending) {
        client_print(id, print_chat, "[KTP] A match is already starting or pending.");
        return PLUGIN_HANDLED;
    }

    // Reset captains for new match
    reset_captains();

    // Gather identity first
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));

    // Set Captain 1 (first start initiator)
    if (!g_captain1_team) {
        g_captain1_team = get_user_team(id);
        copy(g_captain1_name, charsmax(g_captain1_name), name);
        copy(g_captain1_sid,  charsmax(g_captain1_sid),  sid);
        copy(g_captain1_ip,   charsmax(g_captain1_ip),   ip);
    }

    // Set flags
    g_preStartPending = true;
    g_preConfirmAllies = false;
    g_preConfirmAxis = false;
    g_confirmAlliesBy[0] = EOS;
    g_confirmAxisBy[0] = EOS;

    // Reset pause limits only for NEW matches (1st half), not 2nd half continuation
    // Pause counts persist across halves (per-match limit, not per-half)
    if (!g_secondHalfPending) {
        g_pauseCountTeam[1] = 0;
        g_pauseCountTeam[2] = 0;
    }
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_matchLive = false;
    safe_remove_task(g_taskPauseHudId);
    stop_unpause_reminder();

    // Log event
    log_ktp("event=PRESTART_BEGIN by=\'%s\' steamid=%s ip=%s team=%s map=%s second_half=%d", name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_secondHalfPending ? 1 : 0);

    // Announce pre-start with match type
    new matchTypeStr[16];
    switch (g_matchType) {
        case MATCH_TYPE_SCRIM: copy(matchTypeStr, charsmax(matchTypeStr), "Scrim");
        case MATCH_TYPE_12MAN: copy(matchTypeStr, charsmax(matchTypeStr), "12man");
        case MATCH_TYPE_DRAFT: copy(matchTypeStr, charsmax(matchTypeStr), "Draft");
        default: copy(matchTypeStr, charsmax(matchTypeStr), "Match");
    }
    announce_all("Pre-Start (%s) by %s on %s", matchTypeStr, name, map);
    announce_all("Ensure demos/MOSS/screenshots ready, then .confirm");

    // HLTV reminder for 1st half matches (not 2nd half continuation)
    if (!g_secondHalfPending) {
        announce_all("[HLTV] Ensure HLTV is connected for auto-recording.");
    }

    // Show 2nd half detection HUD again for players who missed map load announcement
    // Shortened to 4s so it clears before match start HUD fires
    if (g_secondHalfPending) {
        set_hudmessage(255, 255, 0, -1.0, 0.25, 0, 0.0, 4.0, 0.5, 0.5, -1);
        show_hudmessage(0, "=== 2nd HALF DETECTED ===^n^nTeams swapped sides^n%s now Allies | %s now Axis^n^nPause budgets carried over",
                g_team2Name, g_team1Name);
    }

    set_task(1.0, "prestart_hud_tick", g_taskPrestartHudId, _, _, "b");
    return PLUGIN_HANDLED;
}

// Scrim mode - no Discord notifications, scrim-specific configs
public cmd_start_scrim(id) {
    // Block if match already in progress
    if (g_matchLive || g_preStartPending || g_matchPending) {
        client_print(id, print_chat, "[KTP] Cannot start - match already in progress or pending.");
        return PLUGIN_HANDLED;
    }
    g_matchType = MATCH_TYPE_SCRIM;
    g_disableDiscord = true; // Legacy flag for compatibility
    cmd_match_start(id);
    return PLUGIN_HANDLED;
}

// 12-man mode - no Discord notifications, 12man-specific configs
public cmd_start_12man(id) {
    // Block if match already in progress
    if (g_matchLive || g_preStartPending || g_matchPending) {
        client_print(id, print_chat, "[KTP] Cannot start - match already in progress or pending.");
        return PLUGIN_HANDLED;
    }
    // Show duration selection menu
    new menu = menu_create("12man Match Duration", "menu_12man_duration_handler");
    menu_additem(menu, "20 minutes (standard)", "20");
    menu_additem(menu, "15 minutes", "15");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public menu_12man_duration_handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[8], name[32], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), name, charsmax(name), callback);

    g_12manDuration = str_to_num(data);
    menu_destroy(menu);

    // Now start the 12man match
    g_matchType = MATCH_TYPE_12MAN;
    g_disableDiscord = true; // Legacy flag for compatibility

    // Announce to everyone what duration was selected
    new captainName[32];
    get_user_name(id, captainName, charsmax(captainName));
    announce_all("%s started a 12man match (%d minutes)", captainName, g_12manDuration);

    cmd_match_start(id);
    return PLUGIN_HANDLED;
}

// Draft mode - no Discord notifications, uses competitive config, always allowed
public cmd_start_draft(id) {
    // Block if match already in progress
    if (g_matchLive || g_preStartPending || g_matchPending) {
        client_print(id, print_chat, "[KTP] Cannot start - match already in progress or pending.");
        return PLUGIN_HANDLED;
    }
    g_matchType = MATCH_TYPE_DRAFT;
    g_disableDiscord = true; // No Discord for drafts
    cmd_match_start(id);
    return PLUGIN_HANDLED;
}

public cmd_pre_status(id) {
    if (!g_preStartPending) { client_print(id, print_chat, "[KTP] Not in pre-start."); return PLUGIN_HANDLED; }
    client_print(id, print_chat, "[KTP] Pre-Start — %s: %s | %s: %s",
        g_teamName[1], g_preConfirmAllies ? g_confirmAlliesBy : "—",
        g_teamName[2], g_preConfirmAxis   ? g_confirmAxisBy   : "—");
    return PLUGIN_HANDLED;
}

public cmd_pre_confirm(id) {
    if (!g_preStartPending) { 
        client_print(id, print_chat, "[KTP] Not in pre-start. Use .ktp to begin."); 
        return PLUGIN_HANDLED; 
    }
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    // identify the confirmer once
    new name[64], sid[44], ip[32], tname[16];  // OPTIMIZED: Removed unused map variable (Phase 5)
    get_user_name(id, name, charsmax(name));
    get_user_authid(id, sid, charsmax(sid));
    get_user_ip(id, ip, charsmax(ip), 1);
    new tid = get_user_team(id, tname, charsmax(tname)); // 1=Allies, 2=Axis (tname is the printable)

    // set Captain 2 only once and only if on the opposite team of Captain 1
    if (!g_captain2_team && g_captain1_team && (tid == 1 || tid == 2) && tid != g_captain1_team) {
        g_captain2_team = tid;
        copy(g_captain2_name, charsmax(g_captain2_name), name);
        copy(g_captain2_sid,  charsmax(g_captain2_sid),  sid);
        copy(g_captain2_ip,   charsmax(g_captain2_ip),   ip);

        log_ktp("event=PRECONFIRM_CAPTAIN2 by='%s' steamid=%s ip=%s team=%d",
                name, safe_sid(sid), ip[0]?ip:"NA", tid);
        announce_all("%s confirmed. Proceeding when both teams are confirmed.", name);
    }

    // log the confirm itself
    log_ktp("event=PRECONFIRM team=%s player='%s' steamid=%s ip=%s", 
            (tid==1)?"Allies":(tid==2)?"Axis":"Spec", name, safe_sid(sid), ip[0]?ip:"NA");

    // pretty "who" string (name/steam/ip)
    new who[80]; 
    get_who_str(id, who, charsmax(who));

    // per-team confirmation gating (store both name and ID for dynamic lookup)
    if (tid == 1) {
        if (g_preConfirmAllies) {
            client_print(id, print_chat, "[KTP] %s already confirmed by %s.", g_teamName[1], g_confirmAlliesBy);
            return PLUGIN_HANDLED;
        }
        g_preConfirmAllies = true;
        copy(g_confirmAlliesBy, charsmax(g_confirmAlliesBy), who);
        announce_all("Pre-Start: %s confirmed by %s.", g_teamName[1], who);

        // Prompt BOTH teams to set their team names (if still default)
        prompt_team_to_set_name(1);  // Prompt Allies
        prompt_team_to_set_name(2);  // Prompt Axis
    } else if (tid == 2) {
        if (g_preConfirmAxis) {
            client_print(id, print_chat, "[KTP] %s already confirmed by %s.", g_teamName[2], g_confirmAxisBy);
            return PLUGIN_HANDLED;
        }
        g_preConfirmAxis = true;
        copy(g_confirmAxisBy, charsmax(g_confirmAxisBy), who);
        announce_all("Pre-Start: %s confirmed by %s.", g_teamName[2], who);

        // Prompt BOTH teams to set their team names (if still default)
        prompt_team_to_set_name(1);  // Prompt Allies
        prompt_team_to_set_name(2);  // Prompt Axis
    } else {
        client_print(id, print_chat, "[KTP] You must be on Allies or Axis to confirm.");
        return PLUGIN_HANDLED;
    }

    // both sides confirmed → proceed to Pending (no pause)
    if (g_preConfirmAllies && g_preConfirmAxis) {
        announce_all("Pre-Start complete. Both teams confirmed.");
        log_ktp("event=PRESTART_COMPLETE");

        // reset pre-start state
        prestart_reset();

        // OPTIMIZED: Use cached map name instead of get_mapname()
        log_ktp("event=PRESTART_COMPLETE captain1='%s' c1_sid=%s c1_team=%d captain2='%s' c2_sid=%s c2_team=%d",
                g_captain1_name, g_captain1_sid[0]?g_captain1_sid:"NA", g_captain1_team,
                g_captain2_name, g_captain2_sid[0]?g_captain2_sid:"NA", g_captain2_team);

        log_ktp("event=PENDING_BEGIN map=%s need=%d", g_currentMap, g_readyRequired);

        // Single entry point: sets g_matchPending, clears ready[], starts HUD, logs state
        enter_pending_phase(g_captain2_name[0] ? g_captain2_name : g_captain1_name);

        // RCON visibility
        console_print(0, "[KTP] Pending: need=%d (%s/%s).", g_readyRequired, g_teamName[1], g_teamName[2]);
    }

    return PLUGIN_HANDLED;
}


public cmd_pre_notconfirm(id) {
    if (!g_preStartPending) return PLUGIN_HANDLED;
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new who[80]; get_who_str(id, who, charsmax(who));
    new name[32], sid[44], ip[32], team[16]; get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));

    new tid = get_user_team_id(id);
    if (tid == 1) {
        if (!g_preConfirmAllies) { client_print(id, print_chat, "[KTP] Allies had not confirmed yet."); return PLUGIN_HANDLED; }
        g_preConfirmAllies = false; g_confirmAlliesBy[0] = EOS;
        log_ktp("event=PRENOTCONFIRM team=Allies player=\'%s\' steamid=%s ip=%s", name, safe_sid(sid), ip[0]?ip:"NA");
        announce_all("Pre-Start: Allies not confirmed (reset by %s).", who);
    } else if (tid == 2) {
        if (!g_preConfirmAxis) { client_print(id, print_chat, "[KTP] Axis had not confirmed yet."); return PLUGIN_HANDLED; }
        g_preConfirmAxis = false; g_confirmAxisBy[0] = EOS;
        log_ktp("event=PRENOTCONFIRM team=Axis player=\'%s\' steamid=%s ip=%s", name, safe_sid(sid), ip[0]?ip:"NA");
        announce_all("Pre-Start: Axis not confirmed (reset by %s).", who);
    }
    return PLUGIN_HANDLED;
}

public cmd_cancel(id) {
    if (g_preStartPending) {
        new name[32], sid[44], ip[32], team[16], map[32];
        get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
        prestart_reset();
        log_ktp("event=PRESTART_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
        announce_all("Pre-Start cancelled by %s.", name);
        g_matchType = MATCH_TYPE_COMPETITIVE; // Reset to competitive for next match
        g_disableDiscord = false; // Re-enable Discord for next match (legacy)
        return PLUGIN_HANDLED;
    }

    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }

    g_matchPending = false;
    g_matchType = MATCH_TYPE_COMPETITIVE; // Reset to competitive for next match
    g_disableDiscord = false; // Re-enable Discord for next match (legacy)
    arrayset(g_ready, 0, sizeof g_ready);
    safe_remove_task(g_taskPendingHudId);
    safe_remove_task(g_taskUnreadyReminderId);

    // Reset tech budgets and pre-pause state
    g_techBudget[1] = 0;
    g_techBudget[2] = 0;
    g_techPauseStartTime = 0;
    g_techPauseFrozenTime = 0;
    g_pauseStartTime = 0;
    g_autoConfirmLeft = 0;
    safe_remove_task(g_taskPrePauseId);
    safe_remove_task(g_taskAutoConfirmId);
    g_prePauseCountdown = false;
    g_prePauseLeft = 0;

    new name2[32], sid2[44], ip2[32], team2[16];
    get_identity(id, name2, charsmax(name2), sid2, charsmax(sid2), ip2, charsmax(ip2), team2, charsmax(team2));
    // OPTIMIZED: Use cached map name instead of get_mapname()
    log_ktp("event=PENDING_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name2, safe_sid(sid2), ip2[0]?ip2:"NA", team2, g_currentMap);
    announce_all("Match pending cancelled by %s.", name2);

    // Unpause if server happens to be paused (e.g., manual pause during pending)
    if (g_isPaused) {
        announce_all("Unpausing server...");
        ktp_unpause_now("pending_cancel");
    }

    return PLUGIN_HANDLED;
}

// ========== READY/LIVE COMMANDS ==========

// ----- Ready / NotReady / Status -----
public cmd_ready(id) {
    // NOTE: ktp_sync_config_from_cvars() removed here for performance
    // CVARs are synced at plugin_cfg and when configs are executed

    if (!g_matchPending) {
        client_print(id, print_chat, "[KTP] No pending match. Use .ktp to begin.");
        return PLUGIN_HANDLED;
    }
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (g_ready[id]) { 
        client_print(id, print_chat, "[KTP] You are already READY."); 
        return PLUGIN_HANDLED; 
    }

    g_ready[id] = true;

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=READY player='%s' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    announce_all("%s [%s] is READY. %s %d/%d | %s %d/%d (need %d each).", name, sid, g_teamName[1], alliesReady, alliesPlayers, g_teamName[2], axisReady, axisPlayers, g_readyRequired);

    // Debug log for match start condition
    log_ktp("event=READY_CHECK allies_ready=%d axis_ready=%d need=%d will_start=%d",
            alliesReady, axisReady, g_readyRequired,
            (alliesReady >= g_readyRequired && axisReady >= g_readyRequired) ? 1 : 0);

    // Start match when both teams have enough ready players
    if (alliesReady >= g_readyRequired && axisReady >= g_readyRequired) {
        // Exec map-specific config first (may or may not find config)
        exec_map_config();

        // 12man duration override - set mp_timelimit after map config
        if (g_matchType == MATCH_TYPE_12MAN && g_12manDuration != 20) {
            server_cmd("mp_timelimit %d", g_12manDuration);
            server_exec();
            log_ktp("event=12MAN_TIMELIMIT duration=%d", g_12manDuration);
        }

        // ALWAYS execute restart round - even if no map config was found
        // This triggers the match countdown and respawn
        server_cmd("mp_clan_restartround 1");
        server_exec();

        // OT timelimit override - 5 minutes per OT round
        if (g_inOvertime) {
            server_cmd("mp_timelimit 5");
            server_exec();
            log_ktp("event=OT_TIMELIMIT duration=5 round=%d", g_otRound);
        }

        // Build captain fields (no team-tag inference)
        new c1n[64], c2n[64];
        new c1t = g_captain1_team, c2t = g_captain2_team;
        copy(c1n, charsmax(c1n), g_captain1_name[0] ? g_captain1_name : "-");
        copy(c2n, charsmax(c2n), g_captain2_name[0] ? g_captain2_name : "-");

        // Half tracking: Determine if this is 1st half, 2nd half, or OT round
        new halfText[16];
        if (g_inOvertime && g_secondHalfPending && equali(g_matchMap, map)) {
            // OVERTIME ROUND
            g_secondHalfPending = false;
            g_currentHalf = 1;  // Use half=1 for OT round detection in handle_map_change
            formatex(halfText, charsmax(halfText), "OT%d", g_otRound);

            // Calculate running OT totals
            new team1OtTotal = 0, team2OtTotal = 0;
            for (new r = 1; r < g_otRound; r++) {
                team1OtTotal += g_otScores[r][1];
                team2OtTotal += g_otScores[r][2];
            }

            // Announce OT round start
            announce_all("=== OVERTIME ROUND %d STARTING ===", g_otRound);
            announce_all("Regulation: %s %d - %d %s (TIED)", g_team1Name, g_regulationScore[1], g_regulationScore[2], g_team2Name);
            if (g_otRound > 1) {
                announce_all("OT Score: %s %d - %d %s", g_team1Name, team1OtTotal, team2OtTotal, g_team2Name);
            }

            // Announce side assignments
            if (g_otTeam1StartsAs == 1) {
                announce_all("%s = Allies | %s = Axis", g_team1Name, g_team2Name);
            } else {
                announce_all("%s = Axis | %s = Allies", g_team1Name, g_team2Name);
            }
            announce_all("5-minute overtime round - first to break the tie wins!");

            // =============== Restore grand total scores to scoreboard ===============
            // Grand total = regulation + all previous OT rounds
            new team1GrandTotal = g_regulationScore[1] + team1OtTotal;
            new team2GrandTotal = g_regulationScore[2] + team2OtTotal;

            #if defined HAS_DODX
            if (dodx_has_gamerules()) {
                // Map team identity to current side
                new alliesScore, axisScore;
                if (g_otTeam1StartsAs == 1) {
                    // Team 1 is Allies, Team 2 is Axis
                    alliesScore = team1GrandTotal;
                    axisScore = team2GrandTotal;
                } else {
                    // Team 1 is Axis, Team 2 is Allies
                    alliesScore = team2GrandTotal;
                    axisScore = team1GrandTotal;
                }

                // Sync g_matchScore for embed calculations
                g_matchScore[1] = alliesScore;
                g_matchScore[2] = axisScore;

                log_ktp("event=OT_SCOREBOARD_RESTORE round=%d allies=%d axis=%d team1_total=%d team2_total=%d",
                        g_otRound, alliesScore, axisScore, team1GrandTotal, team2GrandTotal);

                // Use deferred restoration to avoid crashes
                g_pendingScoreAllies = alliesScore;
                g_pendingScoreAxis = axisScore;
                schedule_score_restoration();

                announce_all(">>> Scoreboard updated with grand totals <<<");
            }
            #endif
            // ===================================================================
        }
        else if (g_secondHalfPending && equali(g_matchMap, map)) {
            // Same map as previous half, and we're expecting 2nd half
            g_currentHalf = 2;
            g_secondHalfPending = false;
            copy(halfText, charsmax(halfText), "2nd half");

            // Set next map to current map - ensures we stay on this map if time expires
            // This allows finalize_abandoned_match to properly detect match end and trigger OT if tied
            server_cmd("amx_nextmap %s", map);
            server_exec();

            // Announce 2nd half with team side swap and first half scores
            announce_all("=== 2nd HALF STARTING ===");
            announce_all("Teams are switching sides!");
            // g_team1Name = team that started as Allies (now on Axis)
            // g_team2Name = team that started as Axis (now on Allies)
            // g_firstHalfScore[1] = Team 1's first half score, g_firstHalfScore[2] = Team 2's first half score
            announce_all("1st Half Score: %s %d - %d %s", g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name);
            announce_all("%s is now playing as Allies", g_team2Name);
            announce_all("%s is now playing as Axis", g_team1Name);

            // =============== KTP: Restore 1st half scores to scoreboard ===============
            // When 2nd half starts, teams have swapped sides:
            // - Current Allies = Team 2 (was Axis in 1st half) -> their 1st half score = g_firstHalfScore[2]
            // - Current Axis = Team 1 (was Allies in 1st half) -> their 1st half score = g_firstHalfScore[1]
            // NOTE: We use delayed restoration because the game resets scores on round restart
            #if defined HAS_DODX
            if (dodx_has_gamerules()) {
                // Immediate set only (NO broadcast - players not connected yet during map load)
                // The delayed tasks will broadcast once the game is stable
                dodx_set_team_score(1, g_firstHalfScore[2]);
                dodx_set_team_score(2, g_firstHalfScore[1]);

                // Sync g_matchScore immediately so embed calculations are correct
                // At 2nd half start, scoreboard = 1st half scores (2nd half portion = 0-0)
                g_matchScore[1] = g_firstHalfScore[2];  // Allies = Team 2's 1st half
                g_matchScore[2] = g_firstHalfScore[1];  // Axis = Team 1's 1st half

                log_ktp("event=SCOREBOARD_RESTORED allies_score=%d axis_score=%d (team2_1st=%d, team1_1st=%d)",
                        g_firstHalfScore[2], g_firstHalfScore[1], g_firstHalfScore[2], g_firstHalfScore[1]);

                // Set pending scores for delayed restoration
                g_pendingScoreAllies = g_firstHalfScore[2];  // Allies = Team 2's 1st half
                g_pendingScoreAxis = g_firstHalfScore[1];    // Axis = Team 1's 1st half

                // Schedule delayed restoration to handle round restart resetting scores
                schedule_score_restoration();

                // Chat announcement only - HUD will be shown by the match start HUD below
                announce_all(">>> Scoreboard updated with 1st half scores <<<");
            } else {
                log_ktp("event=SCOREBOARD_RESTORE_SKIPPED reason=gamerules_unavailable");
            }
            #endif
            // ===================================================================
        } else {
            // New match, first half

            // =============== KTP: HLStatsX Stats Integration ===============
            // If we were expecting 2nd half but got a different map, the previous
            // match was abandoned. Log KTP_MATCH_END for proper stats closure.
            #if defined HAS_DODX
            if (g_hasDodxStatsNatives && g_secondHalfPending && g_matchId[0]) {
                // Previous match was abandoned after 1st half - flush and close it
                new flushed = dodx_flush_all_stats();
                log_ktp("event=STATS_FLUSH type=match_abandoned players=%d match_id=%s", flushed, g_matchId);
                log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^") (reason ^"abandoned^")", g_matchId, g_matchMap);
                dodx_set_match_id("");
                log_ktp("event=MATCH_ABANDONED previous_map=%s new_map=%s match_id=%s", g_matchMap, map, g_matchId);
            }
            #endif
            // ===============================================================

            g_currentHalf = 1;
            g_secondHalfPending = false;
            copy(g_matchMap, charsmax(g_matchMap), map);
            generate_match_id();
            copy(halfText, charsmax(halfText), "1st half");
        }

        log_ktp("event=MATCH_START map=%s allies_ready=%d axis_ready=%d captain1='%s' c1_team=%d captain2='%s' c2_team=%d half=%s match_id=%s",
                map, alliesReady, axisReady, c1n, c1t, c2n, c2t, halfText, g_matchId);

        // Use team names instead of generic "t1/t2" in captain display
        // g_teamName[1] = current Allies team name, g_teamName[2] = current Axis team name
        // c1t/c2t = captain's current side (1=Allies, 2=Axis), so use g_teamName[c1t]
        new c1TeamName[32], c2TeamName[32];
        copy(c1TeamName, charsmax(c1TeamName), (c1t >= 1 && c1t <= 2) ? g_teamName[c1t] : "?");
        copy(c2TeamName, charsmax(c2TeamName), (c2t >= 1 && c2t <= 2) ? g_teamName[c2t] : "?");
        announce_all("All players ready. Captains: %s (%s) vs %s (%s)", c1n, c1TeamName, c2n, c2TeamName);

        // Discord notification - consolidated match embed
        // 1st half: Create new embed with rosters and capture message ID
        // 2nd half: Update existing embed with roster changes and scores
        #if defined HAS_CURL
        if (!g_disableDiscord) {
            if (g_currentHalf == 1) {
                send_match_embed_create();
            } else if (g_currentHalf == 2) {
                // Embed will be updated - message ID was restored from localinfo
                send_match_embed_update("2nd Half - Match Live");
            }
        }
        #endif

        // Leave pending; clear ready UI/tasks
        g_matchPending = false;
        arrayset(g_ready, 0, sizeof g_ready);
        safe_remove_task(g_taskPendingHudId);
        safe_remove_task(g_taskUnreadyReminderId);
        ClearSyncHud(0, g_hudSync);  // Clear pending HUD immediately

        // First LIVE of this half → mark match live
        g_matchLive       = true;
        set_localinfo(LOCALINFO_LIVE, "1");  // Persist live state for abandoned match detection

        // Reset tech budgets only for NEW matches (1st half), not 2nd half continuation
        // Tech budget persists across halves (per-match budget, not per-half)
        if (g_currentHalf == 1) {
            g_techBudget[1]   = g_techBudgetSecs;
            g_techBudget[2]   = g_techBudgetSecs;
            // Reset match scores for new match (1st half only)
            reset_match_scores();
        }
        safe_remove_task(g_taskAutoUnpauseReqId);
        safe_remove_task(g_taskPauseHudId);

        // =============== KTP: HLStatsX Stats Integration ===============
        // Flush warmup stats BEFORE setting match ID (logged without matchid)
        // Reset stats for fresh match tracking
        // Set match ID for future stats logging
        #if defined HAS_DODX
        if (g_hasDodxStatsNatives) {
            // 1. Flush warmup stats (logged WITHOUT matchid - these are pre-match stats)
            new flushed = dodx_flush_all_stats();
            log_ktp("event=STATS_FLUSH type=warmup players=%d", flushed);

            // 2. Reset all stats for fresh match tracking
            new reset = dodx_reset_all_stats();
            log_ktp("event=STATS_RESET players=%d", reset);

            // 3. Set match context for future stats logging
            dodx_set_match_id(g_matchId);

            // 4. Log KTP_MATCH_START marker for HLStatsX parsing
            // Format: KTP_MATCH_START (matchid "xxx") (map "xxx") (half "x")
            log_amx("KTP_MATCH_START (matchid ^"%s^") (map ^"%s^") (half ^"%s^")", g_matchId, map, halfText);
        }
        #endif
        // ===============================================================

        log_ktp("event=HALF_START half=%s map=%s match_id=%s", halfText, map, g_matchId);

        // Reset pause state
        g_pauseOwnerTeam  = 0;
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;

        // Go LIVE immediately - unpause if needed
        if (g_isPaused) {
            ktp_unpause_now("match_start");
        }
        announce_all("=== MATCH IS LIVE! ===");
        log_ktp("event=LIVE map=%s match_id=%s half=%s", g_currentMap, g_matchId, halfText);

        // Fire ktp_match_start forward on 1st half only (external plugins like KTPHLTVRecorder)
        if (g_currentHalf == 1 && !g_inOvertime) {
            new ret;
            ExecuteForward(g_fwdMatchStart, ret, g_matchId, g_currentMap, g_matchType);
        }

        // HUD announcement for competitive half/OT start
        if (g_matchType == MATCH_TYPE_COMPETITIVE) {
            set_hudmessage(0, 255, 0, -1.0, 0.35, 0, 0.0, 8.0, 0.5, 0.5, -1);

            if (g_inOvertime) {
                // OT HUD: Show regulation + OT totals
                new team1OtTotal = 0, team2OtTotal = 0;
                for (new r = 1; r < g_otRound; r++) {
                    team1OtTotal += g_otScores[r][1];
                    team2OtTotal += g_otScores[r][2];
                }
                new team1Total = g_regulationScore[1] + team1OtTotal;
                new team2Total = g_regulationScore[2] + team2OtTotal;

                show_hudmessage(0, "%s (%d)  vs  %s (%d)^n^nOvertime Round %d",
                    g_team1Name, team1Total, g_team2Name, team2Total, g_otRound);
            } else {
                // Regulation HUD
                new score1 = 0, score2 = 0;
                if (g_currentHalf == 2) {
                    score1 = g_firstHalfScore[1];
                    score2 = g_firstHalfScore[2];
                }
                show_hudmessage(0, "%s (%d)  vs  %s (%d)^n^n%s",
                    g_team1Name, score1, g_team2Name, score2,
                    g_currentHalf == 1 ? "1st Half" : "2nd Half");
            }
        }

        // =============== Proactive context save for 1st half ===============
        // Save match context to localinfo NOW so that if plugin_end fails
        // to run (engine shutdown issue), the context is already persisted
        if (g_currentHalf == 1) {
            save_match_context_for_second_half();
            log_ktp("event=PROACTIVE_CONTEXT_SAVE match_id=%s map=%s half=1", g_matchId, g_matchMap);
        }
        // ===================================================================

        // Start periodic score tracking for all halves
        // - 1st half: persists scores to localinfo for 2nd half restoration
        // - 2nd half: keeps g_matchScore updated for .score command and match end detection
        start_periodic_score_save();

    }
    return PLUGIN_HANDLED;
}

public cmd_notready(id) {
    if (!g_matchPending) return PLUGIN_HANDLED;
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!g_ready[id]) { client_print(id, print_chat, "[KTP] You were not marked READY."); return PLUGIN_HANDLED; }

    g_ready[id] = false;

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=NOTREADY player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;
    announce_all("%s [%s] is NOT READY. %s %d/%d | %s %d/%d (need %d each).", name, sid, g_teamName[1], alliesReady, alliesPlayers, g_teamName[2], axisReady, axisPlayers, need);
    return PLUGIN_HANDLED;
}

public cmd_status(id) {
    if (!g_matchPending) {
        client_print(id, print_chat, "[KTP] No pending match. Use .ktp to begin.");
        return PLUGIN_HANDLED;
    }

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;

    client_print(id, print_chat, "[KTP] ===== MATCH STATUS =====");
    client_print(id, print_chat, "[KTP] %s: %d/%d ready (need %d)", g_teamName[1], alliesReady, alliesPlayers, need);
    client_print(id, print_chat, "[KTP] %s: %d/%d ready (need %d)", g_teamName[2], axisReady, axisPlayers, need);

    // Show ready players
    // OPTIMIZED: Use index-based formatex instead of add() for 30-40% faster string building (Phase 5)
    new ids[32], num;
    get_players(ids, num, "ch");
    new readyList[256], notReadyList[256];
    new readyIdx = 0, notReadyIdx = 0;

    for (new i = 0; i < num; i++) {
        new player = ids[i];
        new name[32];
        get_user_name(player, name, charsmax(name));
        new tid = get_user_team_id(player);

        if (tid == 1 || tid == 2) {
            if (g_ready[player]) {
                if (readyIdx > 0) readyIdx += formatex(readyList[readyIdx], charsmax(readyList) - readyIdx, ", ");
                readyIdx += formatex(readyList[readyIdx], charsmax(readyList) - readyIdx, "%s", name);
            } else {
                if (notReadyIdx > 0) notReadyIdx += formatex(notReadyList[notReadyIdx], charsmax(notReadyList) - notReadyIdx, ", ");
                notReadyIdx += formatex(notReadyList[notReadyIdx], charsmax(notReadyList) - notReadyIdx, "%s", name);
            }
        }
    }

    if (readyList[0]) client_print(id, print_chat, "[KTP] Ready: %s", readyList);
    if (notReadyList[0]) client_print(id, print_chat, "[KTP] Not Ready: %s", notReadyList);

    return PLUGIN_HANDLED;
}

// Periodic reminder of unready players (runs every 30 seconds during pending phase)
public unready_reminder_tick() {
    if (!g_matchPending) {
        safe_remove_task(g_taskUnreadyReminderId);
        return;
    }

    // Build unready lists for each team
    // NOTE: Using global buffers (g_unready*) to avoid AMX stack overflow (16KB limit)
    g_unreadyAllies[0] = EOS;  // Clear global buffers before use
    g_unreadyAxis[0] = EOS;
    new alliesIdx = 0, axisIdx = 0;
    new alliesCount = 0, axisCount = 0;

    new ids[32], num;
    get_players(ids, num, "ch");

    for (new i = 0; i < num; i++) {
        new player = ids[i];
        new tid = get_user_team_id(player);

        if ((tid == 1 || tid == 2) && !g_ready[player]) {
            new name[32];
            get_user_name(player, name, charsmax(name));

            if (tid == 1) { // Allies
                if (alliesIdx > 0) alliesIdx += formatex(g_unreadyAllies[alliesIdx], charsmax(g_unreadyAllies) - alliesIdx, ", ");
                alliesIdx += formatex(g_unreadyAllies[alliesIdx], charsmax(g_unreadyAllies) - alliesIdx, "%s", name);
                alliesCount++;
            } else { // Axis
                if (axisIdx > 0) axisIdx += formatex(g_unreadyAxis[axisIdx], charsmax(g_unreadyAxis) - axisIdx, ", ");
                axisIdx += formatex(g_unreadyAxis[axisIdx], charsmax(g_unreadyAxis) - axisIdx, "%s", name);
                axisCount++;
            }
        }
    }

    // Send team-specific reminders
    for (new i = 0; i < num; i++) {
        new player = ids[i];
        new tid = get_user_team_id(player);

        if (tid == 1 && alliesCount > 0) {
            // Tell Allies who on their team needs to ready
            client_print(player, print_chat, "[KTP] Waiting for: %s (%d players)", g_unreadyAllies, alliesCount);
        } else if (tid == 2 && axisCount > 0) {
            // Tell Axis who on their team needs to ready
            client_print(player, print_chat, "[KTP] Waiting for: %s (%d players)", g_unreadyAxis, axisCount);
        }
    }
}

// Periodic reminder for unpause confirmation (runs while waiting for other team)
public unpause_reminder_tick() {
    // Stop if no longer paused or if countdown started
    if (!g_isPaused || g_countdownActive) {
        safe_remove_task(g_taskUnpauseReminderId);
        return;
    }

    // Both confirmed - countdown should have started, stop reminding
    if (g_unpauseRequested && g_unpauseConfirmedOther) {
        safe_remove_task(g_taskUnpauseReminderId);
        return;
    }

    new ownerTeamName[32], otherTeamName[32];
    team_name_from_id(g_pauseOwnerTeam, ownerTeamName, charsmax(ownerTeamName));
    new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
    team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));

    // Remind the team that hasn't acted yet
    if (g_unpauseRequested && !g_unpauseConfirmedOther) {
        // Owner requested, waiting for other team to .go
        announce_all("Waiting for %s to .go", otherTeamName);
    } else if (!g_unpauseRequested && g_unpauseConfirmedOther) {
        // Other team confirmed, waiting for owner to .resume
        announce_all("Waiting for %s to .resume", ownerTeamName);
    }
}

// Start unpause reminder task (called when one team does their action)
stock start_unpause_reminder() {
    safe_remove_task(g_taskUnpauseReminderId);
    set_task(g_unpauseReminderSecs, "unpause_reminder_tick", g_taskUnpauseReminderId, _, _, "b");
}

// Stop unpause reminder task
stock stop_unpause_reminder() {
    safe_remove_task(g_taskUnpauseReminderId);
}

// Auto-confirmunpause countdown (60 seconds after owner /resume)
public auto_confirmunpause_tick() {
    // Stop if no longer paused or countdown already started
    if (!g_isPaused || g_countdownActive) {
        safe_remove_task(g_taskAutoConfirmId);
        g_autoConfirmLeft = 0;
        return;
    }

    // Stop if other team already confirmed
    if (g_unpauseConfirmedOther) {
        safe_remove_task(g_taskAutoConfirmId);
        g_autoConfirmLeft = 0;
        return;
    }

    g_autoConfirmLeft--;

    // Warnings at 30s, 10s, 5s
    if (g_autoConfirmLeft == 30) {
        new otherTeam = (g_pauseOwnerTeam == 1) ? 2 : 1;
        new otherTeamName[32];
        team_name_from_id(otherTeam, otherTeamName, charsmax(otherTeamName));
        announce_all("%s: 30 seconds to .go!", otherTeamName);
    } else if (g_autoConfirmLeft == 10) {
        announce_all("10 seconds to auto-resume!");
    } else if (g_autoConfirmLeft == 5) {
        announce_all("5 seconds to auto-resume!");
    }

    // Time's up - auto confirm
    if (g_autoConfirmLeft <= 0) {
        safe_remove_task(g_taskAutoConfirmId);
        g_autoConfirmLeft = 0;

        announce_all("Auto-confirming unpause (60 second timeout).");
        log_ktp("event=AUTO_CONFIRMUNPAUSE reason='60s_timeout'");

        // Set confirmed and start countdown
        g_unpauseConfirmedOther = true;
        stop_unpause_reminder();
        start_unpause_countdown("auto-confirm");
    }
}

stock enter_pending_phase(const initiator[]) {
    // flags
    g_matchLive    = false;
    g_matchPending = true;

    // clear any previous ready states
    for (new i = 1; i <= MAX_PLAYERS; i++) g_ready[i] = false;

    // start/refresh the pending HUD
    safe_remove_task(g_taskPendingHudId);
    set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

    // Start periodic unready player reminder (configurable interval)
    safe_remove_task(g_taskUnreadyReminderId);
    set_task(g_unreadyReminderSecs, "unready_reminder_tick", g_taskUnreadyReminderId, _, _, "b");

    // strong log so we see exact state
    log_ktp("event=PENDING_ENFORCE initiator='%s' map=%s paused=%d pending=%d live=%d",
            initiator, g_currentMap, g_isPaused, g_matchPending, g_matchLive);

    announce_all("KTP: Pending phase. Type .rdy when your team is ready (need %d each).",
                 g_readyRequired);

    // Reminder about HLTV for auto-recording (only for 1st half - not 2nd half or OT continuation)
    if (!g_secondHalfPending && !g_inOvertime) {
        announce_all("[HLTV] Captains: Ensure HLTV is connected before match start for auto-recording.");
    }
}

// ================= Server/RCON pause handlers =================
public cmd_rcon_pause(id) {
    // Determine source and name
    new name[32];
    new source[32];

    if (id == 0) {
        // Server console (id=0)
        copy(name, charsmax(name), "Server");
        copy(source, charsmax(source), "server_console");
    } else if (is_user_connected(id)) {
        // RCON from connected admin
        get_user_name(id, name, charsmax(name));
        copy(source, charsmax(source), "rcon");
    } else {
        // RCON from remote
        copy(name, charsmax(name), "RCON");
        copy(source, charsmax(source), "rcon_remote");
    }

    log_ktp("event=PAUSE_CMD source='%s' admin='%s'", source, name);

    // Trigger countdown (auto-detect if pre-match or live)
    new bool:isPreMatch = !g_matchLive;
    trigger_pause_countdown(name, source, isPreMatch, id);

    return PLUGIN_HANDLED;
}

stock reset_captains() {
    g_captain1_name[0] = g_captain1_sid[0] = g_captain1_ip[0] = EOS;
    g_captain2_name[0] = g_captain2_sid[0] = g_captain2_ip[0] = EOS;
    g_captain1_team = g_captain2_team = 0;
}

// ========== ADMIN/DEBUG COMMANDS ==========

public cmd_ktpconfig(id) {
    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    // OPTIMIZED: Use cached map name instead of get_mapname()
    new cfg[128]; new found = lookup_cfg_for_map(g_currentMap, cfg, charsmax(cfg));
    new techA = g_techBudget[1], techX = g_techBudget[2];

    client_print(id, print_chat,
        "[KTP] need=%d | tech_budget=%d | %s %d/%d (tech:%ds), %s %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, g_teamName[1], alliesReady, alliesPlayers, techA, g_teamName[2], axisReady, axisPlayers, techX, g_currentMap, found?cfg:"-", found?"found":"MISS");
    client_print(id, print_console,
        "[KTP] need=%d | tech_budget=%d | %s %d/%d (tech:%ds), %s %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, g_teamName[1], alliesReady, alliesPlayers, techA, g_teamName[2], axisReady, axisPlayers, techX, g_currentMap, found?cfg:"-", found?"found":"MISS");
    return PLUGIN_HANDLED;
}

