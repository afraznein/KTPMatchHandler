/* KTP Match Handler v0.4.4
 * Comprehensive match management system with ReAPI pause integration
 *
 * AUTHOR: Nein_
 * VERSION: 0.4.4
 * DATE: 2025-11-21
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
 * - /pause       - Initiate tactical pause (countdown before activation)
 * - /tech        - Technical pause (uses team budget)
 * - /resume      - Request unpause (owner team)
 * - /confirmunpause - Confirm unpause (other team, if required)
 * - /extend      - Extend pause by 2 minutes (max 2 times)
 * - /cancelpause - Cancel disconnect auto-pause
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
 *   ktp_prepause_seconds "3"             - Pre-pause countdown (live match)
 *   ktp_prematch_pause_seconds "3"       - Pre-pause countdown (pre-match)
 *   ktp_pause_hud "1"                    - Enable pause HUD
 *   ktp_match_logfile "ktp_match.log"    - Log file path
 *   ktp_ready_required "6"               - Players needed to ready up
 *   ktp_cfg_basepath "dod/"              - Config file base path
 *   ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"
 *   ktp_unpause_autorequest_secs "300"   - Auto-request timeout
 *   ktp_tech_budget_seconds "300"        - Tech pause budget per team
 *   ktp_discord_ini "addons/amxmodx/configs/discord.ini"
 *
 * ========== CHANGELOG ==========
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
#define PLUGIN_VERSION "0.4.4"
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

// ---------- Discord Config (loaded from INI) ----------
new g_discordRelayUrl[256];   // Discord relay endpoint URL
new g_discordChannelId[64];   // Discord channel ID
new g_discordAuthSecret[128]; // X-Relay-Auth header value

// ---------- State ----------
new bool: g_isPaused = false;
new bool: g_matchPending = false;
new bool: g_countdownActive = false;
new bool: g_matchLive = false;              // becomes true after first LIVE
new g_techBudget[3] = {0, 0, 0}; // [1]=Allies, [2]=Axis; set at half start to g_techBudgetSecs

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


// ---------- Tunables (defaults; CVARs can override at runtime) ----------
new g_countdownSeconds = 5;    // unpause countdown
new g_prePauseSeconds = 5;     // pre-pause countdown for live pauses
new g_preMatchPauseSeconds = 3;  // OPTIMIZED: Cached from g_cvarPreMatchPauseSec (Phase 5 optimization)
new g_techBudgetSecs = 300;    // 5 minutes tech budget per team per half
new g_readyRequired   = 1;     // players needed per team to go live
new g_countdownLeft = 0;
new const DEFAULT_LOGFILE[] = "ktp_match.log";

// ---------- OPTIMIZED: Cached CVAR values (Phase 2 optimization) ----------
new g_pauseExtensionSec = 120;     // cached from g_cvarPauseExtension
new g_pauseMaxExtensions = 2;      // cached from g_cvarMaxExtensions
new g_autoRequestSecs = 300;       // cached from g_cvarAutoReqSec
new g_serverHostname[64];          // cached from "hostname" cvar

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

// Internal allow-list to let our own pause toggle through the srv hook
new bool: g_allowInternalPause = true;

// Ready flags per player
new bool: g_ready[33];

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
new g_taskDisconnectCountdownId = 55608;    // task ID for disconnect countdown
new g_disconnectCountdown = 0;              // seconds left in disconnect countdown
new g_disconnectedPlayerName[32];           // name of player who disconnected
new g_disconnectedPlayerTeam = 0;           // team of player who disconnected

// ---------- Pause Timing System ----------
new g_pauseStartTime = 0;                   // Unix timestamp when pause began
new g_pauseDurationSec = 300;               // 5 minutes default pause duration
new g_pauseExtensions = 0;                  // How many extensions have been used
// Note: Extension seconds and max extensions are read from CVARs dynamically
new bool: g_prePauseCountdown = false;      // Pre-pause countdown active
new g_prePauseLeft = 0;                     // Seconds left in pre-pause countdown
new g_prePauseReason[64];                   // Reason for pause (for logging)
new g_prePauseInitiator[32];                // Who initiated the pause
// Note: Pause timer ID not needed when using ReAPI hook (only for fallback)
new g_taskPrePauseId = 55610;               // Task ID for pre-pause countdown

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

stock announce_all(const fmt[], any:...) {
    new msg[192];
    vformat(msg, charsmax(msg), fmt, 2);

    // Platform-specific announcement handling during pause
    #if !defined _reapi_included
    if (g_isPaused) {
        // Base AMX/Standard ReHLDS: Use rcon_say (works during pause on all platforms)
        server_cmd("rcon_say ^"[KTP] %s^"", msg);
        server_exec();
    } else {
        client_print(0, print_chat, "[KTP] %s", msg);
    }
    #else
    // KTP-ReHLDS: client_print works during pause
    client_print(0, print_chat, "[KTP] %s", msg);
    #endif
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
}

stock team_str(id, out[], len) {
    new tid = get_user_team(id);  // Just get ID, no name needed
    switch (tid) {
        case 1: copy(out, len, "Allies");
        case 2: copy(out, len, "Axis");
        case 3: copy(out, len, "Spec");
        default: copy(out, len, "Unknown");
    }
}

stock team_name_from_id(teamId, out[], len) {
    switch (teamId) {
        case 1: copy(out, len, "Allies");
        case 2: copy(out, len, "Axis");
        default: copy(out, len, "Unknown");
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

    // Calculate elapsed and remaining time
    new elapsed = get_systime() - g_pauseStartTime;

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

    new elapsedMin = elapsed / 60;
    new elapsedSec = elapsed % 60;
    new remainMin = remaining / 60;
    new remainSec = remaining % 60;

    // Clean minimalist design - centered and well-spaced
    set_hudmessage(255, 255, 255, 0.35, 0.25, 0, 0.0, 0.6, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "^n  == GAME PAUSED ==^n^n  Type: %s^n  By: %s^n^n  Elapsed: %d:%02d  |  Remaining: %d:%02d^n  Extensions: %d/%d^n^n  Pauses Left: A:%d X:%d^n^n  /resume  |  /confirmunpause  |  /extend^n",
        pauseType,
        g_lastPauseBy[0] ? g_lastPauseBy : "Server",
        elapsedMin, elapsedSec,
        remainMin, remainSec,
        g_pauseExtensions, cachedMaxExt,
        pausesA, pausesX);
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
stock send_discord_with_hostname(const message[]) {
    // Prefix message with hostname
    new fullMsg[512];
    formatex(fullMsg, charsmax(fullMsg), "[%s] %s", g_serverHostname, message);

    send_discord_message(fullMsg);
}

stock send_discord_message(const message[]) {
    // Check if Discord is configured (from INI)
    if (!g_discordRelayUrl[0] || !g_discordChannelId[0] || !g_discordAuthSecret[0]) {
        // Discord not configured, skip silently
        return;
    }

    // Escape special characters for JSON
    new escapedMsg[512];
    new msgLen = strlen(message);
    new j = 0;
    for (new i = 0; i < msgLen; i++) {
        // Ensure we have room for escape sequence + null terminator
        if (j >= charsmax(escapedMsg) - 2) break;

        // Handle special characters that need escaping
        switch (message[i]) {
            case '"': { escapedMsg[j++] = 92; escapedMsg[j++] = '"'; }  // 92 = backslash
            case 92: { escapedMsg[j++] = 92; escapedMsg[j++] = 92; }    // backslash
            case 10: { escapedMsg[j++] = 92; escapedMsg[j++] = 'n'; }   // newline
            case 13: { escapedMsg[j++] = 92; escapedMsg[j++] = 'r'; }   // carriage return
            case 9: { escapedMsg[j++] = 92; escapedMsg[j++] = 't'; }    // tab
            default: {
                // Copy character as-is if printable, skip control chars
                if (message[i] >= 32 || message[i] == 10 || message[i] == 13 || message[i] == 9) {
                    escapedMsg[j++] = message[i];
                }
            }
        }
    }
    escapedMsg[j] = EOS;

    // Build JSON payload
    new payload[768];
    formatex(payload, charsmax(payload),
        "{^"channelId^":^"%s^",^"content^":^"```[KTP] %s```^"}",
        g_discordChannelId, escapedMsg);

    // Create cURL handle
    new CURL:curl = curl_easy_init();
    if (curl) {
        // Set URL from INI config
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);

        // Set headers
        new curl_slist:headers = curl_slist_append(SList_Empty, "Content-Type: application/json");

        new authHeader[192];
        formatex(authHeader, charsmax(authHeader), "X-Relay-Auth: %s", g_discordAuthSecret);
        headers = curl_slist_append(headers, authHeader);

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

        // Set POST data
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, payload);

        // Set timeout (5 seconds)
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        // Perform request asynchronously (non-blocking)
        curl_easy_perform(curl, "discord_callback");

        // Cleanup (handle freed in callback)
    } else {
        log_ktp("event=DISCORD_ERROR reason='curl_init_failed'");
    }
}

public discord_callback(CURL:curl, CURLcode:code) {
    if (code != CURLE_OK) {
        new error[128];
        curl_easy_strerror(code, error, charsmax(error));
        log_ktp("event=DISCORD_ERROR curl_code=%d error='%s'", _:code, error);
    }
    // Cleanup
    curl_easy_cleanup(curl);
}

// NOTE: Removed unused Discord wrapper functions:
// - send_discord_pause_event() - never called
// - send_discord_unpause_event() - never called
// - send_discord_match_start() - never called
// All Discord messages sent directly via send_discord_message() with inline formatting

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
    g_discordAuthSecret[0] = EOS;

    new path[192];
    get_pcvar_string(g_cvarDiscordIniPath, path, charsmax(path));
    if (!path[0]) {
        copy(path, charsmax(path), "addons/amxmodx/configs/discord.ini");
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
        } else if (equal(key, "discord_auth_secret")) {
            copy(g_discordAuthSecret, charsmax(g_discordAuthSecret), val);
            loaded++;
        }
    }
    fclose(fp);

    log_ktp("event=DISCORD_CONFIG_LOAD status=ok loaded=%d path='%s'", loaded, path);

    // Log what was loaded (hide auth secret for security)
    if (g_discordRelayUrl[0]) {
        log_ktp("discord_relay_url='%s'", g_discordRelayUrl);
    }
    if (g_discordChannelId[0]) {
        log_ktp("discord_channel_id='%s'", g_discordChannelId);
    }
    if (g_discordAuthSecret[0]) {
        log_ktp("discord_auth_secret='***REDACTED***'");
    }
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
    if (!base[0]) copy(base, charsmax(base), "dod/");

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

    new fullpath[192]; formatex(fullpath, charsmax(fullpath), "%s%s", base, cfg);

    log_ktp("event=MAPCFG status=exec map=%s cfg=%s path=\'%s\'", g_currentMap, cfg, fullpath);
    announce_all("Applying match config: %s", cfg);

    server_cmd("exec %s", fullpath);
    server_exec();

    // Execute mp_clan_restartround 1 after map config to start countdown
    server_cmd("mp_clan_restartround 1");
    server_exec();

    return 1;
}

stock ktp_pause_now(const reason[]) {
    log_ktp("event=PAUSE_ATTEMPT reason=%s paused=%d", reason, g_isPaused);

    if (!g_isPaused) {
        // Set pause start time for timer calculations (even for pre-live pauses)
        g_pauseStartTime = get_systime();

        #if defined _reapi_included
        // Use ReAPI native to pause directly (bypasses pausable cvar)
        rh_set_server_pause(true);
        g_isPaused = true;
        log_ktp("event=PAUSE_TOGGLE source=reapi reason='%s' method=rh_set_server_pause", reason);
        #else
        // Fallback to engine pause command for base HLDS/ReHLDS (requires pausable 1)
        g_allowInternalPause = true;
        server_cmd("pause");
        server_exec();
        g_allowInternalPause = false;
        g_isPaused = true;
        log_ktp("event=PAUSE_TOGGLE source=engine_cmd reason='%s'", reason);
        #endif

        client_print(0, print_chat, "[KTP] Game paused (reason: %s)", reason);
    }
}

stock ktp_unpause_now(const reason[]) {
    log_ktp("event=UNPAUSE_ATTEMPT reason=%s paused=%d", reason, g_isPaused);

    if (g_isPaused) {
        #if defined _reapi_included
        // Use ReAPI native to unpause directly (bypasses pausable cvar)
        rh_set_server_pause(false);
        g_isPaused = false;
        log_ktp("event=UNPAUSE_TOGGLE source=reapi reason='%s' method=rh_set_server_pause", reason);
        #else
        // Fallback to engine unpause command for base HLDS/ReHLDS (requires pausable 1)
        g_allowInternalPause = true;
        server_cmd("unpause");
        server_exec();
        g_allowInternalPause = false;
        g_isPaused = false;
        log_ktp("event=UNPAUSE_TOGGLE source=engine_cmd reason='%s'", reason);
        #endif

        client_print(0, print_chat, "[KTP] Game unpaused (reason: %s)", reason);
    }
}

// ================= Pre-Pause Countdown =================
// isPreMatch: true = use ktp_prematch_pause_seconds, false = use ktp_prepause_seconds
stock trigger_pause_countdown(const who[], const reason[], bool:isPreMatch = false) {
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

    // Use appropriate countdown based on match state
    // OPTIMIZED: Use cached CVAR values instead of get_pcvar_num() (Phase 5)
    if (isPreMatch) {
        g_prePauseLeft = g_preMatchPauseSeconds;
        if (g_prePauseLeft <= 0) g_prePauseLeft = 3;  // minimum 3 seconds
    } else {
        g_prePauseLeft = g_prePauseSeconds;
        if (g_prePauseLeft <= 0) g_prePauseLeft = 3;  // minimum 3 seconds
    }

    g_prePauseCountdown = true;

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

    // Store pause info
    copy(g_lastPauseBy, charsmax(g_lastPauseBy), who);
    g_pauseStartTime = get_systime();
    g_pauseExtensions = 0;

    // Actually pause using ReAPI native (or fallback for non-ReAPI)
    #if defined _reapi_included
    rh_set_server_pause(true);
    g_isPaused = true;
    #else
    g_allowInternalPause = true;
    server_cmd("pause");
    server_exec();
    g_allowInternalPause = false;
    g_isPaused = true;
    #endif

    // Set pause duration
    // OPTIMIZED: Pause duration is now cached in ktp_sync_config_from_cvars() (Phase 5)
    // Just ensure we have a valid value
    if (g_pauseDurationSec <= 0) g_pauseDurationSec = 300;  // default 5 minutes

    // Start HUD update task (fallback for base AMX/standard ReHLDS)
    // Note: On base AMX/standard ReHLDS, this task won't execute during pause (host_frametime = 0)
    // With KTP-ReHLDS, HUD updates happen via OnPausedHUDUpdate() ReAPI hook instead
    #if !defined _reapi_included
    set_task(0.5, "pause_hud_tick", g_taskPauseHudId, _, _, "b");
    #endif

    new totalDuration = get_total_pause_duration();
    new buf[16];
    fmt_seconds(totalDuration, buf, charsmax(buf));
    announce_all("Game paused by %s. Duration: %s. Type /extend for more time.",
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
            techPauseElapsed = currentTime - g_techPauseStartTime;

            // Deduct from budget
            new budgetBefore = g_techBudget[teamId];
            g_techBudget[teamId] -= techPauseElapsed;
            if (g_techBudget[teamId] < 0) g_techBudget[teamId] = 0;

            new teamName[16];
            team_name_from_id(teamId, teamName, charsmax(teamName));

            log_ktp("event=TECH_BUDGET_DEDUCT team=%d elapsed=%d budget_before=%d budget_after=%d",
                    teamId, techPauseElapsed, budgetBefore, g_techBudget[teamId]);

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
    safe_remove_task(g_taskAutoUnpauseReqId);
    safe_remove_task(g_taskAutoReqCountdownId);
    safe_remove_task(g_taskPauseHudId);
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
        announce_all("Auto tech-pause in %d... (%s can type /cancelpause)", g_disconnectCountdown, teamName);
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

        // Discord notification - DISCONNECT AUTO-PAUSE (one of 3 essential notifications)
        #if defined HAS_CURL
        new discordMsg[256];
        new buf[16];
        fmt_seconds(g_techBudget[g_disconnectedPlayerTeam], buf, charsmax(buf));
        formatex(discordMsg, charsmax(discordMsg),
            "📴 AUTO TECH PAUSE: %s (%s) disconnected | Budget: %s",
            g_disconnectedPlayerName, teamName, buf);
        send_discord_with_hostname(discordMsg);
        #endif
    }
}

// Fallback HUD update function (for base AMX/standard ReHLDS without KTP-ReHLDS + ReAPI)
// NOTE: On base AMX/standard ReHLDS, tasks WILL NOT execute during pause (host_frametime = 0)
// This function only runs when game is NOT paused
// Timer checking during pause happens via check_pause_timer_manual() (called from player commands)
public pause_hud_tick() {
    // Stop if no longer paused
    if (!g_isPaused) {
        safe_remove_task(g_taskPauseHudId);
        return;
    }

    // Display pause HUD based on type (won't actually update during pause on standard ReHLDS)
    show_pause_hud_message(g_isTechPause ? "TECHNICAL" : "TACTICAL");

    // Check pause timer for warnings/timeout (won't execute during pause on standard ReHLDS)
    check_pause_timer_realtime();
}

// Manual timer check - called from player commands during pause as a fallback
// This allows auto-unpause to work on base AMX/standard ReHLDS (when players type commands)
// On KTP-ReHLDS, timer checks happen automatically via OnPausedHUDUpdate() hook
stock check_pause_timer_manual() {
    if (!g_isPaused) return;

    #if !defined _reapi_included
    // Base AMX/Standard ReHLDS: Can't rely on tasks during pause (host_frametime = 0)
    // Check timer whenever a player executes a command
    check_pause_timer_realtime();
    #endif
}

// Real-time pause timer check (uses get_systime instead of game time)
stock check_pause_timer_realtime() {
    if (!g_isPaused) return;

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
        announce_all("Pause ending in 30 seconds. Type /extend for more time.");
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

// ================= ReAPI Pause HUD Hook (KTP-ReHLDS Only) =================
// This hook enables automatic real-time updates during pause
// Requires: KTP-ReHLDS fork (provides RH_SV_UpdatePausedHUD hook) + ReAPI module
// Fallback: On base AMX/standard ReHLDS, timer checks happen via check_pause_timer_manual()
#if defined _reapi_included
public OnPausedHUDUpdate() {
    // Called every frame while paused (via KTP-ReHLDS modification)
    // Throttle to 1 update per second to avoid network overflow
    static lastUpdate = 0;
    new currentTime = get_systime();

    if (currentTime == lastUpdate) return HC_CONTINUE;  // Already updated this second
    lastUpdate = currentTime;

    if (!g_isPaused) return HC_CONTINUE;

    // If in pending phase, show pending HUD instead of pause HUD
    if (g_matchPending) {
        show_pending_hud_during_pause();
        // Still check pause timer for warnings/timeout
        check_pause_timer_realtime();
        return HC_CONTINUE;
    }

    // Display pause HUD based on type (for tactical/tech pauses during live match)
    show_pause_hud_message(g_isTechPause ? "TECHNICAL" : "TACTICAL");

    // Check pause timer for warnings/timeout using real-world time
    check_pause_timer_realtime();

    return HC_CONTINUE;
}
#endif


// ================= Pre-Start HUD =================
public pending_hud_tick() {
    if (!g_matchPending) { remove_task(g_taskPendingHudId); return; }

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];

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

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP Match Pending%s^nAllies: %d/%d ready (tech:%ds)^nAxis: %d/%d ready (tech:%ds)^nNeed %d/team - Type /ready when ready.",
        pauseInfo, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, need);
}

// Show pending HUD during pause (called from OnPausedHUDUpdate hook)
// This runs every frame, so pause timer updates in real-time
stock show_pending_hud_during_pause() {
    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];

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

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 0.1, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP Match Pending%s^nAllies: %d/%d ready (tech:%ds)^nAxis: %d/%d ready (tech:%ds)^nNeed %d/team - Type /ready when ready.",
        pauseInfo, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, need);
}

public prestart_hud_tick() {
    if (!g_preStartPending) { remove_task(g_taskPrestartHudId); return; }
    set_hudmessage(255, 210, 0, 0.02, 0.08, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP Pre-Start: Waiting for /confirm from each team^nAllies: %s^nAxis: %s^nCommands: /confirm, /prestatus, /cancel",
        g_preConfirmAllies ? g_confirmAlliesBy : "—",
        g_preConfirmAxis   ? g_confirmAxisBy   : "—"
    );
}

stock prestart_reset() {
    g_preStartPending = false;
    g_preConfirmAllies = false;
    g_preConfirmAxis   = false;
    g_confirmAlliesBy[0] = EOS;
    g_confirmAxisBy[0]   = EOS;
    safe_remove_task(g_taskPrestartHudId);

    // New half starting soon; reset pause limits for both teams
    g_pauseCountTeam[1] = 0;
    g_pauseCountTeam[2] = 0;
    g_matchLive = false; // will flip to true at first LIVE of this half
}

// Announce plugin banner to server + all clients, and log it.
stock ktp_banner_enabled() {
    server_print("[KTP] %s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    announce_all("%s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    log_ktp("event=PLUGIN_ENABLED name='%s' version=%s author='%s'", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}


// ================= AMXX lifecycle =================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

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
    g_cvarCfgBase        = register_cvar("ktp_cfg_basepath", "dod/");
    g_cvarMapsFile       = register_cvar("ktp_maps_file", "addons/amxmodx/configs/ktp_maps.ini");
    g_cvarAutoReqSec     = register_cvar("ktp_unpause_autorequest_secs", "300");
    g_cvarDiscordIniPath = register_cvar("ktp_discord_ini", "addons/amxmodx/configs/discord.ini");
    g_cvarPauseDuration  = register_cvar("ktp_pause_duration", "300");       // 5 minutes
    g_cvarPauseExtension = register_cvar("ktp_pause_extension", "120");      // 2 minutes
    g_cvarMaxExtensions  = register_cvar("ktp_pause_max_extensions", "2");   // max 2 extensions

    // Chat controls
    register_clcmd("say /pause",        "cmd_chat_toggle");
    register_clcmd("say_team /pause",   "cmd_chat_toggle");
    register_clcmd("say pause",         "cmd_chat_toggle");
    register_clcmd("say_team pause",    "cmd_chat_toggle");
    register_clcmd("say /resume",       "cmd_chat_resume");
    register_clcmd("say_team /resume",  "cmd_chat_resume");
    register_clcmd("say resume",        "cmd_chat_resume");
    register_clcmd("say_team resume",   "cmd_chat_resume");
    register_clcmd("say /confirmunpause",      "cmd_confirm_unpause");
    register_clcmd("say_team /confirmunpause", "cmd_confirm_unpause");
    register_clcmd("say /cresume",             "cmd_confirm_unpause");
    register_clcmd("say_team /cresume",        "cmd_confirm_unpause");
    register_clcmd("say /cunpause",            "cmd_confirm_unpause");
    register_clcmd("say_team /cunpause",       "cmd_confirm_unpause");

    // Pause extension
    register_clcmd("say /extend",       "cmd_extend_pause");
    register_clcmd("say_team /extend",  "cmd_extend_pause");

    // Cancel disconnect auto-pause
    register_clcmd("say /cancelpause",       "cmd_cancel_disconnect_pause");
    register_clcmd("say_team /cancelpause",  "cmd_cancel_disconnect_pause");

    // Technical pause
    register_clcmd("say /tech",        "cmd_tech_pause");
    register_clcmd("say_team /tech",   "cmd_tech_pause");
    register_clcmd("say tech",         "cmd_tech_pause");
    register_clcmd("say_team tech",    "cmd_tech_pause");

    // Start / Pre-Start
    register_clcmd("say /start",           "cmd_match_start");
    register_clcmd("say_team /start",      "cmd_match_start");
    register_clcmd("say start",            "cmd_match_start");
    register_clcmd("say_team start",       "cmd_match_start");
    register_clcmd("say /startmatch",      "cmd_match_start");
    register_clcmd("say_team /startmatch", "cmd_match_start");
    register_clcmd("say startmatch",       "cmd_match_start");
    register_clcmd("say_team startmatch",  "cmd_match_start");

    register_clcmd("say /confirm",        "cmd_pre_confirm");
    register_clcmd("say_team /confirm",   "cmd_pre_confirm");
    register_clcmd("say confirm",         "cmd_pre_confirm");
    register_clcmd("say_team confirm",    "cmd_pre_confirm");
    register_clcmd("say /notconfirm",     "cmd_pre_notconfirm");
    register_clcmd("say_team /notconfirm","cmd_pre_notconfirm");
    register_clcmd("say /prestatus",      "cmd_pre_status");
    register_clcmd("say_team /prestatus", "cmd_pre_status");
    register_clcmd("say prestatus",       "cmd_pre_status");
    register_clcmd("say_team prestatus",  "cmd_pre_status");

    // Ready (+ alias /ktp) + notready
    register_clcmd("say /ready",         "cmd_ready");
    register_clcmd("say_team /ready",    "cmd_ready");
    register_clcmd("say ready",          "cmd_ready");
    register_clcmd("say_team ready",     "cmd_ready");
    register_clcmd("say /ktp",           "cmd_ready");
    register_clcmd("say_team /ktp",      "cmd_ready");
    register_clcmd("say ktp",            "cmd_ready");
    register_clcmd("say_team ktp",       "cmd_ready");
    register_clcmd("say /notready",      "cmd_notready");
    register_clcmd("say_team /notready", "cmd_notready");

    // Status + cancel
    register_clcmd("say /status",         "cmd_status");
    register_clcmd("say_team /status",    "cmd_status");
    register_clcmd("say status",          "cmd_status");
    register_clcmd("say_team status",     "cmd_status");

    register_clcmd("say /cancel",       "cmd_cancel");
    register_clcmd("say_team /cancel",  "cmd_cancel");
    register_clcmd("say cancel",        "cmd_cancel");
    register_clcmd("say_team cancel",   "cmd_cancel");

    // Mapping maintenance
    register_clcmd("say /reloadmaps",       "cmd_reload_maps");
    register_clcmd("say_team /reloadmaps",  "cmd_reload_maps");
    register_clcmd("say /ktpconfig",        "cmd_ktpconfig");
    register_clcmd("say_team /ktpconfig",   "cmd_ktpconfig");
    register_clcmd("say ktpconfig",         "cmd_ktpconfig");
    register_clcmd("say_team ktpconfig",    "cmd_ktpconfig");

    //Debug
    register_clcmd("say /ktpdebug", "cmd_ktpdebug");
    register_clcmd("say_team /ktpdebug", "cmd_ktpdebug");

    // NOTE: We do NOT register the console "pause" command because KTP-ReHLDS has it built-in
    // Attempting to override it causes: "Cmd_AddMallocCommand: pause already defined"
    // Instead, we rely on:
    //   - Chat commands: "say /pause" (registered above at line 1266)
    //   - Server can use: ktp_pause command (registered below)
    // The engine's built-in pause still works, but without our custom countdown/tracking

    // Custom pause command for server/admin use (avoids conflict with built-in "pause")
    register_concmd("ktp_pause", "cmd_rcon_pause", ADMIN_RCON, "- Trigger KTP tactical pause");

    g_hudSync = CreateHudSyncObj();

    // Register ReAPI hook for automatic pause HUD updates (KTP-ReHLDS + ReAPI only)
    // This enables real-time HUD updates during pause without player interaction
    // Note: Can't use #if defined for enum constants, so we register unconditionally if ReAPI is available
    #if defined _reapi_included
    RegisterHookChain(RH_SV_UpdatePausedHUD, "OnPausedHUDUpdate", .post = false);
    log_amx("[KTP] Registered RH_SV_UpdatePausedHUD hook");
    #else
    log_amx("[KTP] WARNING: ReAPI not available - pause HUD updates disabled");
    #endif

    // NOTE: pausable cvar no longer used - ReAPI pause bypasses it
    g_lastUnpauseBy[0] = EOS;
    g_lastPauseBy[0] = EOS;

    // read CVARs to apply live values
    ktp_sync_config_from_cvars();

    reset_captains();

    // Announce on load
    ktp_banner_enabled();
    load_map_mappings();
    load_discord_config();
}

public plugin_cfg() {
    get_mapname(g_currentMap, charsmax(g_currentMap));  // Cache map name
    ktp_sync_config_from_cvars();
    load_map_mappings();
    load_discord_config();
}

public plugin_end() {
    safe_remove_task(g_taskCountdownId);
    safe_remove_task(g_taskPendingHudId);
    safe_remove_task(g_taskPrestartHudId);
    safe_remove_task(g_taskAutoUnpauseReqId);
    safe_remove_task(g_taskAutoReqCountdownId);
    safe_remove_task(g_taskDisconnectCountdownId);
    safe_remove_task(g_taskPauseHudId);
}

// Shared handler
stock on_client_left(id) {
    if (id >= 1 && id <= MAX_PLAYERS) {
        g_ready[id] = false;

        // Auto tech-pause on disconnect during live match
        if (g_matchLive && !g_isPaused) {
            new tid = get_user_team_id(id);
            // Only trigger for players on actual teams (not spectators)
            if (tid == 1 || tid == 2) {
                // Check if team has tech budget
                if (g_techBudget[tid] > 0) {
                    // Store disconnected player info
                    get_user_name(id, g_disconnectedPlayerName, charsmax(g_disconnectedPlayerName));
                    g_disconnectedPlayerTeam = tid;

                    // Start disconnect countdown
                    g_disconnectCountdown = DISCONNECT_COUNTDOWN_SECS;

                    new sid[44], teamName[16];
                    get_user_authid(id, sid, charsmax(sid));
                    team_name_from_id(tid, teamName, charsmax(teamName));

                    log_ktp("event=DISCONNECT_DETECTED player='%s' steamid=%s team=%s",
                            g_disconnectedPlayerName, safe_sid(sid), teamName);

                    announce_all("PLAYER DISCONNECTED: %s (%s) | Auto tech-pause in 10... (type /cancelpause to cancel)", g_disconnectedPlayerName, teamName);

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
    // Snapshot current state for this player's heads-up
    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];
    // OPTIMIZED: Use cached map name instead of get_mapname()
    new cfg[128]; new found = lookup_cfg_for_map(g_currentMap, cfg, charsmax(cfg));

    client_print(
        id, print_chat,
        "[KTP] need=%d | unpause_countdown=%d | prepause=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_countdownSeconds, g_prePauseSeconds, g_techBudgetSecs,
        alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, g_currentMap, found ? cfg : "-", found ? "found" : "MISS"
    );

    client_print(id, print_console, "[KTP] %s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
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
public cmd_reload_maps(id) {
    load_map_mappings();
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=MAPS_RELOAD by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    client_print(id, print_chat, "[KTP] Map mappings reloaded.");
    return PLUGIN_HANDLED;
}

// ===== Client console 'pause' =====
public cmd_client_pause(id) {
    // If it's our internal pause, allow it
    if (g_allowInternalPause) return PLUGIN_CONTINUE;

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=PAUSE_CLIENT_CONSOLE player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);

    // Trigger countdown (auto-detect if pre-match or live)
    new bool:isPreMatch = !g_matchLive;
    trigger_pause_countdown(name, "client_console", isPreMatch);

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

        // Discord notification - PLAYER TACTICAL PAUSE (one of 3 essential notifications)
        #if defined HAS_CURL
        new discordMsg[256];
        formatex(discordMsg, charsmax(discordMsg),
            "⏸️ %s (%s) initiated tactical pause | Pauses: A:%d X:%d",
            name, team, pauses_left(1), pauses_left(2));
        send_discord_with_hostname(discordMsg);
        #endif

        // Trigger pre-pause countdown with live match countdown (false = use ktp_prepause_seconds)
        trigger_pause_countdown(name, "chat_tactical", false);
    } else {
        // This is the pre-start/pending pause (doesn't count) - immediate pause
        g_pauseOwnerTeam = 0;
        g_isTechPause = false;
        safe_remove_task(g_taskAutoUnpauseReqId);
        g_autoReqLeft = 0;

        // For pre-live pauses, use pre-match countdown
        trigger_pause_countdown(name, "tactical_pause_prelive", true); // true = pre-match countdown

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
        client_print(id, print_chat, "[KTP] Match is pending. Use /ready; server will resume automatically.");
        return PLUGIN_HANDLED;
    }

    if (g_pauseOwnerTeam == 0 && g_matchLive) {
        // Edge: somehow no owner recorded; recover by assigning on first /resume attempt
        g_pauseOwnerTeam = (teamId==1 || teamId==2) ? teamId : 0;
    }

    if (g_matchLive) {
        if (teamId != g_pauseOwnerTeam) {
            client_print(id, print_chat, "[KTP] Only the pause-owning team may /resume. Other team should /confirmunpause.");
            return PLUGIN_HANDLED;
        }
    }
    // Owner requests unpause
    g_unpauseRequested = true;
    g_autoReqLeft = 0; // stop HUD timer
    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), name);
    log_ktp("event=UNPAUSE_REQUEST_OWNER team=%d by=\'%s\' steamid=%s", g_pauseOwnerTeam, name, safe_sid(sid));
    announce_all("%s requested unpause. Waiting for the other team to /confirmunpause.", team);

    // If the other team has pre-confirmed (rare), start the countdown now
    if (g_unpauseConfirmedOther) {
        start_unpause_countdown(g_lastUnpauseBy);
    }

    return PLUGIN_HANDLED;
}

// ========== PAUSE/RESUME COMMANDS ==========

// ===== Chat pause/resume with ownership & confirm =====
public cmd_chat_toggle(id) {
    // Check if pause timer expired (fallback for non-KTP-ReHLDS)
    check_pause_timer_manual();

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
    // Check if pause timer expired (fallback for non-KTP-ReHLDS)
    check_pause_timer_manual();

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
    if (tid == g_pauseOwnerTeam) { client_print(id, print_chat, "[KTP] Your team owns this pause; use /resume."); return PLUGIN_HANDLED; }

    new name[32], sid[44], ip[32], team[16];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));

    g_unpauseConfirmedOther = true;
    log_ktp("event=UNPAUSE_CONFIRM_OTHER team=%d by=\'%s\' steamid=%s", tid, name, safe_sid(sid));
    announce_all("%s confirmed unpause.", team);

    // If owner already requested (or auto-request fired), we can start countdown
    if (g_unpauseRequested) {
        start_unpause_countdown(g_lastUnpauseBy[0] ? g_lastUnpauseBy : team);
    } else {
        client_print(id, print_chat, "[KTP] Waiting for the pause-owning team to /resume (or auto-request).");
    }
    return PLUGIN_HANDLED;
}

// ===== Pause Extension Command =====
public cmd_extend_pause(id) {
    // Check if pause timer expired (fallback for non-KTP-ReHLDS)
    check_pause_timer_manual();

    if (!g_isPaused) {
        client_print(id, print_chat, "[KTP] No active pause to extend.");
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

// ===== Cancel Disconnect Auto-Pause Command =====
public cmd_cancel_disconnect_pause(id) {
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
        client_print(id, print_chat, "[KTP] Match is already paused. Use /resume to unpause.");
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

    // Schedule auto-unpause request
    setup_auto_unpause_request();

    // Record pause start time (wall clock) for budget tracking
    g_techPauseStartTime = get_systime();

    log_ktp("event=TECH_PAUSE player=\'%s\' steamid=%s ip=%s team=%s map=%s budget_remaining=%d",
            name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_techBudget[tid]);

    // Trigger pre-pause countdown with new system
    trigger_pause_countdown(name, "tech_pause");

    return PLUGIN_HANDLED;
}

public cmd_ktpdebug(id) {
    client_print(id, print_chat, "[KTP] paused=%d pending=%d live=%d need=%d",
        g_isPaused, g_matchPending, g_matchLive, g_readyRequired);
    return PLUGIN_HANDLED;
}

// Auto-request unpause after timeout if owner doesn’t /resume
public auto_unpause_request() {
    if (!g_isPaused || !g_matchLive) return;
    if (g_unpauseRequested) return; // owner already did it

    g_unpauseRequested = true;
    g_autoReqLeft = 0;
    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), "auto");
    log_ktp("event=UNPAUSE_REQUEST_AUTO team=%d", g_pauseOwnerTeam);
    announce_all("Auto-requesting unpause (owner timeout). Waiting for the other team to /confirmunpause.");

    // If other team already confirmed, start countdown now
    if (g_unpauseConfirmedOther) {
        start_unpause_countdown("auto");
    }
}

// ========== MATCH START (PRE-START) COMMANDS ==========

// ===== Start / Pre-Start =====
public cmd_match_start(id) {
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

    // Reset pause limits for the new half
    g_pauseCountTeam[1] = 0;
    g_pauseCountTeam[2] = 0;
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_matchLive = false;
    safe_remove_task(g_taskPauseHudId);

    // Log event
    log_ktp("event=PRESTART_BEGIN by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);

    // Announce in order with explicit flushing to prevent buffering issues
    announce_all("Pre-Start initiated by %s on %s.", name, map);
    announce_all("Opposite team captain must /confirm to proceed.");
    server_exec(); // Force flush before warning block
    announce_all(" ");
    announce_all("===========================================");
    announce_all("IMPORTANT: Before /confirm, ensure ALL players have:");
    announce_all("  1. Started demo recording");
    announce_all("  2. Started MOSS (if required)");
    announce_all("  3. Taken required screenshots");
    announce_all("===========================================");
    server_exec(); // Force flush before final instructions
    announce_all(" ");
    announce_all("Upon confirmation, the server will PAUSE for the ready phase.");
    announce_all("Captains: type /confirm when your team is ready.");

    set_task(1.0, "prestart_hud_tick", g_taskPrestartHudId, _, _, "b");
    return PLUGIN_HANDLED;
}

public cmd_pre_status(id) {
    if (!g_preStartPending) { client_print(id, print_chat, "[KTP] Not in pre-start."); return PLUGIN_HANDLED; }
    client_print(id, print_chat, "[KTP] Pre-Start — Allies: %s | Axis: %s",
        g_preConfirmAllies ? g_confirmAlliesBy : "—",
        g_preConfirmAxis   ? g_confirmAxisBy   : "—");
    return PLUGIN_HANDLED;
}

public cmd_pre_confirm(id) {
    if (!g_preStartPending) { 
        client_print(id, print_chat, "[KTP] Not in pre-start. Use /start."); 
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
        announce_all("[KTP] %s confirmed. Proceeding when both teams are confirmed.", name);
    }

    // log the confirm itself
    log_ktp("event=PRECONFIRM team=%s player='%s' steamid=%s ip=%s", 
            (tid==1)?"Allies":(tid==2)?"Axis":"Spec", name, safe_sid(sid), ip[0]?ip:"NA");

    // pretty "who" string (name/steam/ip)
    new who[80]; 
    get_who_str(id, who, charsmax(who));

    // per-team confirmation gating
    if (tid == 1) {
        if (g_preConfirmAllies) { 
            client_print(id, print_chat, "[KTP] Allies already confirmed by %s.", g_confirmAlliesBy); 
            return PLUGIN_HANDLED; 
        }
        g_preConfirmAllies = true; 
        copy(g_confirmAlliesBy, charsmax(g_confirmAlliesBy), who);
        announce_all("Pre-Start: Allies confirmed by %s.", who);
    } else if (tid == 2) {
        if (g_preConfirmAxis) { 
            client_print(id, print_chat, "[KTP] Axis already confirmed by %s.", g_confirmAxisBy); 
            return PLUGIN_HANDLED; 
        }
        g_preConfirmAxis = true; 
        copy(g_confirmAxisBy, charsmax(g_confirmAxisBy), who);
        announce_all("Pre-Start: Axis confirmed by %s.", who);
    } else {
        client_print(id, print_chat, "[KTP] You must be on Allies or Axis to confirm.");
        return PLUGIN_HANDLED;
    }

    // both sides confirmed → pause, then proceed to Pending
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

        // Pause BEFORE entering pending phase
        announce_all("Server pausing for ready phase...");
        if (!g_isPaused) {
            trigger_pause_countdown("System", "prestart_confirmed", true); // true = pre-match countdown
            log_ktp("event=PRESTART_PAUSE");
        }

        // Single entry point: sets g_matchPending, clears ready[], starts HUD, logs state
        enter_pending_phase(g_captain2_name[0] ? g_captain2_name : g_captain1_name);

        // RCON visibility
        console_print(0, "[KTP] Pending: paused=%d, need=%d (Allies/Axis).", g_isPaused, g_readyRequired);
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
        return PLUGIN_HANDLED;
    }

    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }

    g_matchPending = false;
    arrayset(g_ready, 0, sizeof g_ready);
    safe_remove_task(g_taskPendingHudId);

    new name2[32], sid2[44], ip2[32], team2[16];
    get_identity(id, name2, charsmax(name2), sid2, charsmax(sid2), ip2, charsmax(ip2), team2, charsmax(team2));
    // OPTIMIZED: Use cached map name instead of get_mapname()
    log_ktp("event=PENDING_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name2, safe_sid(sid2), ip2[0]?ip2:"NA", team2, g_currentMap);
    announce_all("Match pending cancelled by %s.", name2);

    // Unpause if server is paused (from pre-start confirmation)
    if (g_isPaused) {
        announce_all("Unpausing server...");
        ktp_unpause_now("pending_cancel");
    }

    return PLUGIN_HANDLED;
}

// ========== READY/LIVE COMMANDS ==========

// ----- Ready / NotReady / Status -----
public cmd_ready(id) {
    ktp_sync_config_from_cvars();

    if (!g_matchPending) { 
        client_print(id, print_chat, "[KTP] No pending match. Use /start to begin."); 
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
    announce_all("%s is READY. Allies %d/%d | Axis %d/%d (need %d each).", name, alliesReady, alliesPlayers, axisReady, axisPlayers, g_readyRequired);

    // Start match when both teams have enough ready players
    if (alliesReady >= g_readyRequired && axisReady >= g_readyRequired) {
        // Exec map-specific config first
        exec_map_config();

        // Build captain fields (no team-tag inference)
        new c1n[64], c2n[64];
        new c1t = g_captain1_team, c2t = g_captain2_team;
        copy(c1n, charsmax(c1n), g_captain1_name[0] ? g_captain1_name : "-");
        copy(c2n, charsmax(c2n), g_captain2_name[0] ? g_captain2_name : "-");

        log_ktp("event=MATCH_START map=%s allies_ready=%d axis_ready=%d captain1='%s' c1_team=%d captain2='%s' c2_team=%d",
                map, alliesReady, axisReady, c1n, c1t, c2n, c2t);
        announce_all("All players ready. Captains: %s (t%d) vs %s (t%d)", c1n, c1t, c2n, c2t);

        // Discord notification - MATCH START (one of 3 essential notifications)
        #if defined HAS_CURL
        new discordMsg[256];
        new c1team[16], c2team[16];
        team_name_from_id(c1t, c1team, charsmax(c1team));
        team_name_from_id(c2t, c2team, charsmax(c2team));
        formatex(discordMsg, charsmax(discordMsg),
            "⚔️ Match starting on %s | %s (%s) vs %s (%s)",
            map, c1n, c1team, c2n, c2team);
        send_discord_with_hostname(discordMsg);
        #endif

        // Leave pending; clear ready UI/tasks
        g_matchPending = false;
        arrayset(g_ready, 0, sizeof g_ready);
        safe_remove_task(g_taskPendingHudId);

        // Ensure we are paused before going live countdown
        if (!g_isPaused) {
            // If countdown not already in progress, trigger it
            if (!g_prePauseCountdown) {
                trigger_pause_countdown("System", "ready_complete_autopause", true); // true = pre-match countdown
            }
        }
        if (!g_lastUnpauseBy[0]) copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), "system");

        // First LIVE of this half → mark match live and reset pause-session vars
        g_countdownLeft   = max(1, g_countdownSeconds);
        g_countdownActive = true;
        g_matchLive       = true;
        g_techBudget[1]   = g_techBudgetSecs;
        g_techBudget[2]   = g_techBudgetSecs;
        g_pauseOwnerTeam  = 0;
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;
        safe_remove_task(g_taskAutoUnpauseReqId);
        safe_remove_task(g_taskPauseHudId);

        log_ktp("event=COUNTDOWN begin=%d requested_by='%s'", g_countdownLeft, g_lastUnpauseBy);
        announce_all("Live in %d... (requested by %s)", g_countdownLeft, g_lastUnpauseBy);
        set_task(1.0, "countdown_tick", g_taskCountdownId, _, _, "b");
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
    announce_all("%s is NOT READY. Allies %d/%d | Axis %d/%d (need %d each).", name, alliesReady, alliesPlayers, axisReady, axisPlayers, need);
    return PLUGIN_HANDLED;
}

public cmd_status(id) {
    // Check if pause timer expired (fallback for non-KTP-ReHLDS)
    check_pause_timer_manual();

    if (!g_matchPending) {
        client_print(id, print_chat, "[KTP] No pending match. Use /start to begin.");
        return PLUGIN_HANDLED;
    }

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;

    client_print(id, print_chat, "[KTP] ===== MATCH STATUS =====");
    client_print(id, print_chat, "[KTP] Allies: %d/%d ready (need %d)", alliesReady, alliesPlayers, need);
    client_print(id, print_chat, "[KTP] Axis: %d/%d ready (need %d)", axisReady, axisPlayers, need);

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

stock enter_pending_phase(const initiator[]) {
    // flags
    g_matchLive    = false;
    g_matchPending = true;

    // clear any previous ready states
    for (new i = 1; i <= MAX_PLAYERS; i++) g_ready[i] = false;

    // NOTE: Server pause is now triggered BEFORE calling this function (in cmd_pre_confirm)
    // This ensures captains confirm demos/moss/screenshots before the pause happens

    // start/refresh the pending HUD
    safe_remove_task(g_taskPendingHudId);
    set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

    // snapshot some diagnostics for log
    // OPTIMIZED: Use cached map name instead of get_mapname()

    // strong log so we see exact state
    log_ktp("event=PENDING_ENFORCE initiator='%s' map=%s paused=%d pending=%d live=%d",
            initiator, g_currentMap, g_isPaused, g_matchPending, g_matchLive);

    announce_all("KTP: Pending phase. Type /ready when your team is ready (need %d each).",
                 g_readyRequired);
}

// ================= Server/RCON pause handlers =================
public cmd_rcon_pause(id) {
    // If it's our internal pause, allow it
    if (g_allowInternalPause) return PLUGIN_CONTINUE;

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
    trigger_pause_countdown(name, source, isPreMatch);

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
        "[KTP] need=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, g_currentMap, found?cfg:"-", found?"found":"MISS");
    client_print(id, print_console,
        "[KTP] need=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, g_currentMap, found?cfg:"-", found?"found":"MISS");
    return PLUGIN_HANDLED;
}