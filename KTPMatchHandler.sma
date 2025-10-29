/* KTP Match Handler (confirm-unpause + per-team pause limits + pause HUD)
 * - Chat-only control: server/RCON 'pause'/'unpause' blocked (logged)
 * - Pre-Start: /start or /startmatch -> requires one /confirm from each team
 * - Pending: /ready (alias /ktp) + /notready until both teams reach ktp_ready_required
 * - After LIVE: each team gets ONE pause per half (per "match" run)
 * - Pause owner must request unpause; other team must /confirmunpause; OR auto-request after timeout; then countdown → LIVE
 * - Synced HUD; INI-based map→cfg; /reloadmaps; normalized key=value logs
 * - Pause HUD shows owner, who paused, request/confirm states, auto-request timer, countdown seconds, and pauses remaining
 *
 * CVARs:
 *   ktp_pause_countdown "5"
 *   ktp_pause_hud "1"
 *   ktp_match_logfile "ktp_match.log"
 *   ktp_ready_required "6"
 *   ktp_cfg_basepath "dod/"
 *   ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"
 *   ktp_unpause_autorequest_secs "300"
 */

#include <amxmodx>
#include <amxmisc>

// Optional: cURL for Discord notifications
#tryinclude <curl>
#if defined _curl_included
    #define HAS_CURL
#endif

#define PLUGIN_NAME    "KTP Match Handler"
#define PLUGIN_VERSION "0.3.3"
#define PLUGIN_AUTHOR  "Nein_"

// ---------- CVARs ----------
new g_cvarHud;
new g_cvarLogFile;
new g_cvarReadyReq;
new g_cvarCfgBase;
new g_cvarMapsFile;
new g_cvarAutoReqSec;
new g_cvarCountdown;          // unpause countdown seconds (ktp_pause_countdown)
new g_cvarPrePauseSec;        // pre-pause chat countdown (ktp_prepause_seconds)
new g_cvarTechBudgetSec;      // technical pause budget per team per half (ktp_tech_budget_seconds)
new g_cvarForcePausable;      // ktp_force_pausable
new g_cvarDiscordIniPath;     // path to discord.ini (ktp_discord_ini)
new g_pcvarPausable;          // pointer to engine "pausable" cvar

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
new g_countdownSeconds = 5;   // unpause countdown
new g_prePauseSeconds = 5;    // pre-pause countdown for live pauses
new g_techBudgetSecs = 300;   // 5 minutes tech budget per team per half
new g_readyRequired   = 1;    // players needed per team to go live
new g_countdownLeft = 0;
new const DEFAULT_LOGFILE[] = "ktp_match.log";

// ---------- Constants ----------
const MAX_PLAYERS = 32;
const AUTO_REQUEST_MIN_SECS = 60;
const AUTO_REQUEST_DEFAULT_SECS = 300;
const AUTO_REQUEST_MAX_SECS = 3600; // 1 hour maximum
const DISCONNECT_COUNTDOWN_SECS = 5;

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

    client_print(0, print_chat, "[KTP] %s", msg);
    client_print(0, print_console, "[KTP] %s", msg);

    if (get_pcvar_num(g_cvarHud)) {
        set_hudmessage(HUD_R, HUD_G, HUD_B, HUD_X, HUD_Y, 0, 0.0, 2.0, 0.0, 0.0, -1);
        ClearSyncHud(0, g_hudSync);
        ShowSyncHudMsg(0, g_hudSync, "%s", msg);
    }
}

stock ktp_sync_config_from_cvars() {
    if (g_cvarReadyReq)      { new v = get_pcvar_num(g_cvarReadyReq);       if (v > 0) g_readyRequired = v; }
    if (g_cvarCountdown)     { new v2 = get_pcvar_num(g_cvarCountdown);     if (v2 > 0) g_countdownSeconds = v2; }
    if (g_cvarPrePauseSec)   { new v3 = get_pcvar_num(g_cvarPrePauseSec);   if (v3 > 0) g_prePauseSeconds   = v3; }
    if (g_cvarTechBudgetSec) { new v4 = get_pcvar_num(g_cvarTechBudgetSec); if (v4 > 0) g_techBudgetSecs    = v4; }
}

stock team_str(id, out[], len) {
    new tname[16];
    new tid = get_user_team(id, tname, charsmax(tname));
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


stock fmt_seconds(sec) {
    static buf[16];
    if (sec < 60) formatex(buf, charsmax(buf), "%ds", sec);
    else formatex(buf, charsmax(buf), "%dm%02ds", sec / 60, sec % 60);
    return buf;
}

stock pauses_left(teamId) {
    if (teamId != 1 && teamId != 2) return 0;
    new used = g_pauseCountTeam[teamId];
    // Clamp used to 0-1 range
    if (used < 0) used = 0;
    else if (used > 1) used = 1;
    return 1 - used;
}

stock safe_remove_task(taskId) {
    if (task_exists(taskId)) remove_task(taskId);
}

stock get_full_identity(id, name[], nameLen, sid[], sidLen, ip[], ipLen, team[], teamLen, map[], mapLen) {
    get_identity(id, name, nameLen, sid, sidLen, ip, ipLen, team, teamLen);
    get_mapname(map, mapLen);
}

stock show_pause_hud_message(const pauseType[]) {
    new ownerTeam = g_pauseOwnerTeam;
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];
    new pausesA = pauses_left(1);
    new pausesX = pauses_left(2);

    set_hudmessage(255, 255, 255, 0.02, 0.18, 0, 0.0, 1.1, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP: %s PAUSE^nOwner: %s (t%d)^nTactical pauses left A:%d X:%d^nTech budget A:%ds X:%ds^n/resume (owner) + /confirmunpause (other)^nAuto-req in: %ds",
        pauseType,
        g_lastPauseBy[0] ? g_lastPauseBy : "unknown",
        ownerTeam,
        pausesA, pausesX,
        techA, techX,
        g_autoReqLeft);
}

stock setup_auto_unpause_request() {
    new secs = get_pcvar_num(g_cvarAutoReqSec);
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
            case '"': { escapedMsg[j++] = '\'; escapedMsg[j++] = '"'; }
            case '\': { escapedMsg[j++] = '\'; escapedMsg[j++] = '\'; }
            case '\n': { escapedMsg[j++] = '\'; escapedMsg[j++] = 'n'; }
            case '\r': { escapedMsg[j++] = '\'; escapedMsg[j++] = 'r'; }
            case '\t': { escapedMsg[j++] = '\'; escapedMsg[j++] = 't'; }
            default: {
                // Copy character as-is if printable, skip control chars
                if (message[i] >= 32 || message[i] == '\n' || message[i] == '\r' || message[i] == '\t') {
                    escapedMsg[j++] = message[i];
                }
            }
        }
    }
    escapedMsg[j] = EOS;

    // Build JSON payload
    new payload[768];
    formatex(payload, charsmax(payload),
        "{\"channelId\":\"%s\",\"content\":\"```[KTP] %s```\"}",
        g_discordChannelId, escapedMsg);

    // Create cURL handle
    new CURL:curl = curl_easy_init();
    if (curl) {
        // Set URL from INI config
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);

        // Set headers
        new CURLHeaders:headers = curl_slist_append(Invalid_CURLHeaders, "Content-Type: application/json");

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

// Discord message helpers
stock send_discord_pause_event(const emoji[], const eventType[], const playerName[], const teamName[]) {
    new msg[256];
    formatex(msg, charsmax(msg),
        "%s %s by %s (%s) | Pauses left: Allies %d, Axis %d",
        emoji, eventType, playerName, teamName, pauses_left(1), pauses_left(2));
    send_discord_message(msg);
}

stock send_discord_unpause_event(const emoji[], const playerName[]) {
    new msg[256];
    formatex(msg, charsmax(msg),
        "%s Match LIVE! Unpaused by %s | Tech budget: Allies %ds, Axis %ds",
        emoji, playerName, g_techBudget[1], g_techBudget[2]);
    send_discord_message(msg);
}

stock send_discord_match_start(const captain1[], const captain2[]) {
    new msg[256];
    formatex(msg, charsmax(msg),
        "⚔️ Match starting! Captains: %s vs %s",
        captain1, captain2);
    send_discord_message(msg);
}
#else
// Stub function when cURL not available
stock send_discord_message(const message[]) {
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
    while (!feof(fp) && added < MAX_MAP_ROWS) {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        new eq = contain(line, "=");
        if (eq <= 0) continue;

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
        strip_bsp_suffix(key);
        strtolower_inplace(key);
        copy(val, charsmax(val), line[eq + 1]);
        trim(val);

        if (!key[0] || !val[0]) continue;

        copy(g_mapKeys[added], charsmax(g_mapKeys[]), key);
        copy(g_mapCfgs[added], charsmax(g_mapCfgs[]), val);
        added++;
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
    new map[32]; get_mapname(map, charsmax(map));

    new base[96]; get_pcvar_string(g_cvarCfgBase, base, charsmax(base));
    if (!base[0]) copy(base, charsmax(base), "dod/");

    // Ensure base path has trailing slash
    new len = strlen(base);
    if (len > 0 && base[len-1] != '/' && base[len-1] != '\') {
        strcat(base, "/", charsmax(base));
    }

    new cfg[128];
    if (!lookup_cfg_for_map(map, cfg, charsmax(cfg))) {
        log_ktp("event=MAPCFG status=miss map=%s", map);
        return 0;
    }

    new fullpath[192]; formatex(fullpath, charsmax(fullpath), "%s%s", base, cfg);

    log_ktp("event=MAPCFG status=exec map=%s cfg=%s path=\'%s\'", map, cfg, fullpath);
    announce_all("Applying match config: %s", cfg);

    server_cmd("exec %s", fullpath);
    server_exec();
    return 1;
}

stock ktp_force_pausable_if_needed() {
    if (!get_pcvar_num(g_cvarForcePausable)) return;
    if (g_pcvarPausable) {
        if (get_pcvar_num(g_pcvarPausable) != 1) set_pcvar_num(g_pcvarPausable, 1);
    } else {
        if (get_cvar_num("pausable") != 1) set_cvar_num("pausable", 1);
    }
}

stock ktp_pause_now(const reason[]) {
    ktp_force_pausable_if_needed();

    // DEBUG visibility
    new pausable = g_pcvarPausable ? get_pcvar_num(g_pcvarPausable) : get_cvar_num("pausable");
    log_ktp("event=PAUSE_ATTEMPT reason=%s paused=%d pausable=%d allow=%d",
            reason, g_isPaused, pausable, g_allowInternalPause);

    if (!g_isPaused) {
        g_allowInternalPause = true;          // allow our server_cmd through the block
        server_cmd("pause");
        server_exec();
        g_allowInternalPause = false;

        // we don't assume success blindly—double-check:
        pausable = g_pcvarPausable ? get_pcvar_num(g_pcvarPausable) : get_cvar_num("pausable");
        // engine doesn't expose a "paused" cvar; we trust the toggle and set our flag:
        g_isPaused = true;

        log_ktp("event=PAUSE_TOGGLE source=plugin reason='%s' pausable=%d", reason, pausable);
        client_print(0, print_chat, "[KTP] Pause enforced (reason: %s). pausable=%d", reason, pausable);
        client_print(0, print_console, "[KTP] Pause enforced (reason: %s). pausable=%d", reason, pausable);
    }
}

stock ktp_unpause_now(const reason[]) {
    // DEBUG visibility
    new pausable = g_pcvarPausable ? get_pcvar_num(g_pcvarPausable) : get_cvar_num("pausable");
    log_ktp("event=UNPAUSE_ATTEMPT reason=%s paused=%d pausable=%d allow=%d",
            reason, g_isPaused, pausable, g_allowInternalPause);

    if (g_isPaused) {
        g_allowInternalPause = true;          // allow our server_cmd through the block
        server_cmd("unpause");
        server_exec();
        g_allowInternalPause = false;

        // engine doesn't expose a "paused" cvar; we trust the toggle and set our flag:
        g_isPaused = false;

        log_ktp("event=UNPAUSE_TOGGLE source=plugin reason='%s' pausable=%d", reason, pausable);
        client_print(0, print_chat, "[KTP] Unpause executed (reason: %s). pausable=%d", reason, pausable);
        client_print(0, print_console, "[KTP] Unpause executed (reason: %s). pausable=%d", reason, pausable);
    }
}

// ================= Countdown & Pause HUD =================
public start_unpause_countdown(const who[]) {
    if (!g_isPaused) return;
    if (g_countdownActive) { announce_all("Unpause countdown already running (%d sec left).", g_countdownLeft); return; }

    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), who);

    g_countdownLeft = max(1, g_countdownSeconds);
    g_countdownActive = true;

    new map[32]; get_mapname(map, charsmax(map));
    log_ktp("event=COUNTDOWN begin=%d requested_by=\'%s\' map=%s", g_countdownLeft, who, map);
    announce_all("Live in %d... (requested by %s)", g_countdownLeft, who);
    set_task(1.0, "countdown_tick", g_taskCountdownId, _, _, "b");
}

public countdown_tick() {
    if (!g_countdownActive) { remove_task(g_taskCountdownId); return; }
    g_countdownLeft--;

    if (g_countdownLeft > 0) {
        announce_all("Unpause in %d... (requested by %s)", g_countdownLeft, g_lastUnpauseBy);
        return;
    }

    remove_task(g_taskCountdownId);
    g_countdownActive = false;

    new map[32]; get_mapname(map, charsmax(map));
    log_ktp("event=LIVE map=%s requested_by=\'%s\'", map, g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");

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
            announce_all("Tech pause lasted %s. %s budget remaining: %s",
                fmt_seconds(techPauseElapsed), teamName, fmt_seconds(g_techBudget[teamId]));

            // Warn if budget is low or exhausted
            if (g_techBudget[teamId] == 0) {
                announce_all("WARNING: %s tech budget EXHAUSTED!", teamName);
            } else if (g_techBudget[teamId] <= 60) {
                announce_all("WARNING: %s has only %s of tech budget remaining!", teamName, fmt_seconds(g_techBudget[teamId]));
            }
        }
    }

    announce_all("Live! (Unpaused by %s)", g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");

    // Discord notification
    new discordMsg[256];
    if (g_isTechPause && techPauseElapsed > 0) {
        new teamName[16];
        team_name_from_id(g_pauseOwnerTeam, teamName, charsmax(teamName));
        formatex(discordMsg, charsmax(discordMsg),
            "▶️ Match LIVE! Tech pause lasted %s | %s budget: %s",
            fmt_seconds(techPauseElapsed), teamName, fmt_seconds(g_techBudget[g_pauseOwnerTeam]));
    } else {
        formatex(discordMsg, charsmax(discordMsg),
            "▶️ Match LIVE! Unpaused by %s",
            g_lastUnpauseBy[0] ? g_lastUnpauseBy : "system");
    }
    send_discord_message(discordMsg);

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

    if (g_disconnectCountdown > 0) {
        announce_all("Auto tech-pause in %d...", g_disconnectCountdown);
    } else {
        // Countdown finished - trigger tech pause
        safe_remove_task(g_taskDisconnectCountdownId);

        new teamName[16];
        team_name_from_id(g_disconnectedPlayerTeam, teamName, charsmax(teamName));

        log_ktp("event=AUTO_TECH_PAUSE player='%s' team=%s reason='disconnect'",
                g_disconnectedPlayerName, teamName);

        // Set up tech pause
        g_pauseOwnerTeam = g_disconnectedPlayerTeam;
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;
        g_isTechPause = true;

        // Schedule auto-unpause request
        setup_auto_unpause_request();

        // Record pause start time (wall clock)
        g_techPauseStartTime = get_systime();

        // Actually pause
        ktp_pause_now("auto_tech_disconnect");

        // Record who/what caused pause
        formatex(g_lastPauseBy, charsmax(g_lastPauseBy), "AUTO (%s DC)", g_disconnectedPlayerName);

        // Start HUD ticker
        if (!task_exists(g_taskPauseHudId)) {
            set_task(1.0, "pause_hud_tick", g_taskPauseHudId, _, _, "b");
        }

        // NOTE: Can't use announce_all here - server is now paused!
        // Players will see it in HUD and Discord

        // Discord notification
        new discordMsg[256];
        formatex(discordMsg, charsmax(discordMsg),
            "🔧 AUTO TECH PAUSE: %s (%s) disconnected | Budget: %s",
            g_disconnectedPlayerName, teamName, fmt_seconds(g_techBudget[g_disconnectedPlayerTeam]));
        send_discord_message(discordMsg);
    }
}

public pause_hud_tick() {
    // Stop if no longer paused
    if (!g_isPaused) {
        safe_remove_task(g_taskPauseHudId);
        return;
    }

    // Display pause HUD based on type
    show_pause_hud_message(g_isTechPause ? "TECHNICAL" : "TACTICAL");
}


// ================= Pre-Start HUD =================
public pending_hud_tick() {
    if (!g_matchPending) { remove_task(g_taskPendingHudId); return; }

    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;
    new techA = g_techBudget[1];
    new techX = g_techBudget[2];

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "KTP Match Pending^nAllies: %d/%d ready (tech:%ds)^nAxis: %d/%d ready (tech:%ds)^nNeed %d/team^nType /ready when ready.",
        alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, need);
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

    g_cvarCountdown      = register_cvar("ktp_pause_countdown",  tmpCnt);
    g_cvarReadyReq       = register_cvar("ktp_ready_required", tmpReady);
    g_cvarPrePauseSec    = register_cvar("ktp_prepause_seconds", tmpPre);
    g_cvarTechBudgetSec  = register_cvar("ktp_tech_budget_seconds", tmpTech);
    g_cvarLogFile        = register_cvar("ktp_match_logfile", DEFAULT_LOGFILE);
    g_cvarForcePausable  = register_cvar("ktp_force_pausable", "1");
    g_cvarHud            = register_cvar("ktp_pause_hud", "1");
    g_cvarCfgBase        = register_cvar("ktp_cfg_basepath", "dod/");
    g_cvarMapsFile       = register_cvar("ktp_maps_file", "addons/amxmodx/configs/ktp_maps.ini");
    g_cvarAutoReqSec     = register_cvar("ktp_unpause_autorequest_secs", "300");
    g_cvarDiscordIniPath = register_cvar("ktp_discord_ini", "addons/amxmodx/configs/discord.ini");

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

    // Block client console "pause" and attribute it
    register_clcmd("pause", "cmd_client_pause");

    g_hudSync = CreateHudSyncObj();

    // engine pointer for "pausable"
    g_pcvarPausable = get_cvar_pointer("pausable");
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

                    new name[32], sid[44], teamName[16];
                    get_user_name(id, name, charsmax(name));
                    get_user_authid(id, sid, charsmax(sid));
                    team_name_from_id(tid, teamName, charsmax(teamName));

                    log_ktp("event=DISCONNECT_DETECTED player='%s' steamid=%s team=%s",
                            name, safe_sid(sid), teamName);

                    announce_all("PLAYER DISCONNECTED: %s (%s) | Auto tech-pause in 5...", name, teamName);

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
    new map[32]; get_mapname(map, charsmax(map));
    new cfg[128]; new found = lookup_cfg_for_map(map, cfg, charsmax(cfg));

    client_print(
        id, print_chat,
        "[KTP] need=%d | unpause_countdown=%d | prepause=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_countdownSeconds, g_prePauseSeconds, g_techBudgetSecs,
        alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, map, found ? cfg : "-", found ? "found" : "MISS"
    );

    client_print(id, print_console, "[KTP] %s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}



// ================= Counts & commands =================
stock get_ready_counts(&alliesPlayers, &axisPlayers, &alliesReady, &axisReady) {
    alliesPlayers = 0; axisPlayers = 0; alliesReady = 0; axisReady = 0;
    new ids[32], num; get_players(ids, num, "ch");
    for (new i = 0; i < num; i++) {
        new id = ids[i];
        new tid = get_user_team_id(id);
        if (tid == 1) { alliesPlayers++; if (g_ready[id]) alliesReady++; }
        else if (tid == 2) { axisPlayers++; if (g_ready[id]) axisReady++; }
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
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=PAUSE_BLOCK_CLIENT player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    announce_all("Blocked client 'pause' from %s[%s] (%s). Use /pause or /resume.", name, sid, ip[0]?ip:"NA");
    return PLUGIN_HANDLED;
}

// ===== Toggle helpers =====
stock handle_countdown_cancel(id) {
    new tid = get_user_team_id(id);
    if (tid != g_pauseOwnerTeam) {
        client_print(id, print_chat, "[KTP] Only the pause-owning team can cancel the unpause countdown.");
        return PLUGIN_HANDLED;
    }
    remove_task(g_taskCountdownId); g_countdownActive = false;
    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));
    log_ktp("event=UNPAUSE_CANCEL player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    announce_all("Unpause countdown cancelled by %s. Staying paused.", name);

    // Re-arm auto-request and reset flag; HUD keeps running
    g_unpauseRequested = false;
    new secs = get_pcvar_num(g_cvarAutoReqSec);
    if (secs < AUTO_REQUEST_MIN_SECS) secs = AUTO_REQUEST_DEFAULT_SECS;
    g_autoReqLeft = secs;
    if (!task_exists(g_taskAutoUnpauseReqId)) set_task(float(secs), "auto_unpause_request", g_taskAutoUnpauseReqId);

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
        g_pauseCountTeam[teamId]++;           // consume the team pause
        g_pauseOwnerTeam = teamId;            // set ownership
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;

        // schedule auto-unpause request if owner forgets to /resume
        setup_auto_unpause_request();

        log_ktp("event=PAUSE_AUTOREQ_ARM team=%d seconds=%d", g_pauseOwnerTeam, g_autoReqLeft);
    } else {
        // This is the pre-start/pending pause (doesn't count)
        g_pauseOwnerTeam = 0;
        safe_remove_task(g_taskAutoUnpauseReqId);
        g_autoReqLeft = 0;
    }

    // Actually pause
    ktp_pause_now("tactical_pause");

    // Mark as tactical pause (not tech)
    g_isTechPause = false;

    // record who paused for HUD
    formatex(g_lastPauseBy, charsmax(g_lastPauseBy), "%s", name);

    // start HUD ticker only for live match pauses
    if (g_matchLive && !task_exists(g_taskPauseHudId)) {
        set_task(1.0, "pause_hud_tick", g_taskPauseHudId, _, _, "b");
    }

    log_ktp("event=PAUSE_BY_CHAT player=\'%s\' steamid=%s ip=%s team=%s map=%s live=%d team_pause_used=%d/%d",
            name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_matchLive ? 1 : 0,
            (teamId==1)?g_pauseCountTeam[1]:g_pauseCountTeam[2], 1);

    if (g_matchLive) {
        announce_all("Match paused by %s. Only %s may /resume. Other team must /confirmunpause. (1 pause per team)",
                     name, team);
        client_print(id, print_chat, "[KTP] Your team pauses left after this: %d.", pauses_left(teamId));

        // Discord notification
        send_discord_pause_event("⏸️", "Match PAUSED", name, team);
    } else {
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

    // Set up tech pause
    g_pauseOwnerTeam = tid;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_isTechPause = true;

    // Schedule auto-unpause request
    setup_auto_unpause_request();

    // Record pause start time (wall clock)
    g_techPauseStartTime = get_systime();

    // Actually pause
    ktp_pause_now("technical_pause");

    // Record who paused
    formatex(g_lastPauseBy, charsmax(g_lastPauseBy), "%s", name);

    // Start HUD ticker
    if (!task_exists(g_taskPauseHudId)) {
        set_task(1.0, "pause_hud_tick", g_taskPauseHudId, _, _, "b");
    }

    log_ktp("event=TECH_PAUSE player=\'%s\' steamid=%s ip=%s team=%s map=%s budget_remaining=%d",
            name, safe_sid(sid), ip[0]?ip:"NA", team, map, g_techBudget[tid]);

    announce_all("Technical pause called by %s (%s). Tech budget: %s", name, team, fmt_seconds(g_techBudget[tid]));

    // Discord notification
    new discordMsg[256];
    formatex(discordMsg, charsmax(discordMsg),
        "🔧 TECHNICAL PAUSE by %s (%s) | Budget: Allies %ds, Axis %ds",
        name, team, g_techBudget[1], g_techBudget[2]);
    send_discord_message(discordMsg);

    return PLUGIN_HANDLED;
}

public cmd_ktpdebug(id) {
    new pausable = g_pcvarPausable ? get_pcvar_num(g_pcvarPausable) : get_cvar_num("pausable");
    client_print(id, print_chat, "[KTP] paused=%d pending=%d live=%d pausable=%d need=%d",
        g_isPaused, g_matchPending, g_matchLive, pausable, g_readyRequired);
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

    // set Captain 1 (first start initiator)
    if (!g_captain1_team) {
        new name[64], sid[44], ip[32];
        get_user_name(id, name, charsmax(name));
        get_user_authid(id, sid, charsmax(sid));
        get_user_ip(id, ip, charsmax(ip), 1);

        g_captain1_team = get_user_team(id);
        copy(g_captain1_name, charsmax(g_captain1_name), name);
        copy(g_captain1_sid,  charsmax(g_captain1_sid),  sid);
        copy(g_captain1_ip,   charsmax(g_captain1_ip),   ip);

        new map[32]; get_mapname(map, charsmax(map));
        log_ktp("event=PRESTART_BEGIN by='%s' steamid=%s ip=%s team=%d map=%s",
                name, safe_sid(sid), ip[0]?ip:"NA", g_captain1_team, map);
        announce_all("[KTP] Match start initiated by %s. Opposite team must /confirm.", name);
    }


    g_preStartPending = true; g_preConfirmAllies = false; g_preConfirmAxis = false;
    g_confirmAlliesBy[0] = EOS; g_confirmAxisBy[0] = EOS;

    // Pre-start pause (does NOT count)
    if (!g_isPaused) {
        ktp_pause_now("prestart");
        log_ktp("event=PRESTART_AUTOPAUSE");
    }

    // Reset pause limits for the new half
    g_pauseCountTeam[1] = 0;
    g_pauseCountTeam[2] = 0;
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_matchLive = false;
    safe_remove_task(g_taskPauseHudId);

    new name[32], sid[44], ip[32], team[16], map[32];
    get_full_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team), map, charsmax(map));

    log_ktp("event=PRESTART_BEGIN by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, safe_sid(sid), ip[0]?ip:"NA", team, map);
    announce_all("Pre-Start initiated by %s on %s.", name, map);
    announce_all("Procedure: captains from each team type /confirm when your SS procedure is complete.");

    if (!task_exists(g_taskPrestartHudId)) set_task(1.0, "prestart_hud_tick", g_taskPrestartHudId, _, _, "b");
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
    new name[64], sid[44], ip[32], tname[16], map[32];
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

    // both sides confirmed → proceed to Pending
    if (g_preConfirmAllies && g_preConfirmAxis) {
        announce_all("Pre-Start complete. Proceeding to Ready phase.");
        log_ktp("event=PRESTART_COMPLETE");

        // reset pre-start state, then enter Pending (which enforces pause & starts HUD)
        prestart_reset();

        get_mapname(map, charsmax(map));
        log_ktp("event=PRESTART_COMPLETE captain1='%s' c1_sid=%s c1_team=%d captain2='%s' c2_sid=%s c2_team=%d",
                g_captain1_name, g_captain1_sid[0]?g_captain1_sid:"NA", g_captain1_team,
                g_captain2_name, g_captain2_sid[0]?g_captain2_sid:"NA", g_captain2_team);

        log_ktp("event=PENDING_BEGIN map=%s need=%d", map, g_readyRequired);

        // Discord notification
        new discordMsg[256];
        new c1team[16], c2team[16];
        team_name_from_id(g_captain1_team, c1team, charsmax(c1team));
        team_name_from_id(g_captain2_team, c2team, charsmax(c2team));
        formatex(discordMsg, charsmax(discordMsg),
            "✅ Pre-Start confirmed | Captains: %s (%s) vs %s (%s) | Waiting for players to /ready",
            g_captain1_name, c1team, g_captain2_name, c2team);
        send_discord_message(discordMsg);

        // Single entry point: sets g_matchPending, clears ready[], pauses, starts HUD, logs state
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

        new discordMsg[128];
        formatex(discordMsg, charsmax(discordMsg), "⚠️ Pre-Start: Allies not confirmed (reset by %s)", who);
        send_discord_message(discordMsg);
    } else if (tid == 2) {
        if (!g_preConfirmAxis) { client_print(id, print_chat, "[KTP] Axis had not confirmed yet."); return PLUGIN_HANDLED; }
        g_preConfirmAxis = false; g_confirmAxisBy[0] = EOS;
        log_ktp("event=PRENOTCONFIRM team=Axis player=\'%s\' steamid=%s ip=%s", name, safe_sid(sid), ip[0]?ip:"NA");
        announce_all("Pre-Start: Axis not confirmed (reset by %s).", who);

        new discordMsg[128];
        formatex(discordMsg, charsmax(discordMsg), "⚠️ Pre-Start: Axis not confirmed (reset by %s)", who);
        send_discord_message(discordMsg);
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

        new discordMsg[128];
        formatex(discordMsg, charsmax(discordMsg), "❌ Pre-Start cancelled by %s", name);
        send_discord_message(discordMsg);
        return PLUGIN_HANDLED;
    }

    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }

    g_matchPending = false;
    arrayset(g_ready, 0, sizeof g_ready);
    safe_remove_task(g_taskPendingHudId);

    new name2[32], sid2[44], ip2[32], team2[16], map2[32];
    get_identity(id, name2, charsmax(name2), sid2, charsmax(sid2), ip2, charsmax(ip2), team2, charsmax(team2));
    get_mapname(map2, charsmax(map2));
    log_ktp("event=PENDING_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name2, safe_sid(sid2), ip2[0]?ip2:"NA", team2, map2);
    announce_all("Match pending cancelled by %s.", name2);

    new discordMsg[128];
    formatex(discordMsg, charsmax(discordMsg), "❌ Match pending cancelled by %s", name2);
    send_discord_message(discordMsg);
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

    if (alliesReady >= g_readyRequired && axisReady >= g_readyRequired && alliesPlayers >= g_readyRequired && axisPlayers >= g_readyRequired) {
        // Exec map-specific config first
        exec_map_config();

        // Build captain fields (no team-tag inference)
        new c1n[64], c2n[64];
        new c1t = g_captain1_team, c2t = g_captain2_team;
        copy(c1n, charsmax(c1n), g_captain1_name[0] ? g_captain1_name : "-");
        copy(c2n, charsmax(c2n), g_captain2_name[0] ? g_captain2_name : "-");

        log_ktp("event=MATCH_START map=%s allies_ready=%d axis_ready=%d captain1='%s' c1_team=%d captain2='%s' c2_team=%d",
                map, ar, xr, c1n, c1t, c2n, c2t);
        announce_all("All players ready. Captains: %s (t%d) vs %s (t%d)", c1n, c1t, c2n, c2t);

        // Discord notification
        new discordMsg[256];
        new c1team[16], c2team[16];
        team_name_from_id(c1t, c1team, charsmax(c1team));
        team_name_from_id(c2t, c2team, charsmax(c2team));
        formatex(discordMsg, charsmax(discordMsg),
            "⚔️ Match starting on %s | %s (%s) vs %s (%s)",
            map, c1n, c1team, c2n, c2team);
        send_discord_message(discordMsg);

        // Leave pending; clear ready UI/tasks
        g_matchPending = false;
        arrayset(g_ready, 0, sizeof g_ready);
        safe_remove_task(g_taskPendingHudId);

        // Ensure we are paused before going live countdown
        if (!g_isPaused) { 
            ktp_pause_now("auto"); 
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
        if (task_exists(g_taskPauseHudId))      remove_task(g_taskPauseHudId);

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
    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }
    new alliesPlayers, axisPlayers, alliesReady, axisReady;
    get_ready_counts(alliesPlayers, axisPlayers, alliesReady, axisReady);
    new need = g_readyRequired;
    client_print(id, print_chat, "[KTP] Allies %d/%d | Axis %d/%d (need %d each).", alliesReady, alliesPlayers, axisReady, axisPlayers, need);
    return PLUGIN_HANDLED;
}

stock enter_pending_phase(const initiator[]) {
    // flags
    g_matchLive    = false;
    g_matchPending = true;

    // clear any previous ready states
    for (new i = 1; i <= MAX_PLAYERS; i++) g_ready[i] = false;

    // enforce server pause (guarantee pausable=1 then toggle pause)
    ktp_pause_now("pending_enforce");

    // start/refresh the pending HUD
    safe_remove_task(g_taskPendingHudId);
    set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

    // snapshot some diagnostics for log
    new map[32]; get_mapname(map, charsmax(map));
    new pausable = g_pcvarPausable ? get_pcvar_num(g_pcvarPausable) : get_cvar_num("pausable");

    // strong log so we see exact state
    log_ktp("event=PENDING_ENFORCE initiator='%s' map=%s paused=%d pausable=%d pending=%d live=%d",
            initiator, map, g_isPaused, pausable, g_matchPending, g_matchLive);

    announce_all("KTP: Pending phase. Server paused. Type /ready when your team is ready (need %d each).",
                 g_readyRequired);
}

// ================= Server/Client pause blocking =================
public cmd_block_pause(id) {
    // allow if plugin is intentionally pausing, or if this is the server (id==0)
    if (g_allowInternalPause || id == 0) return PLUGIN_CONTINUE;

    // block everyone else
    new who[64]; get_who_str(id, who, charsmax(who)); // your helper, or build name/steam/ip here
    log_ktp("event=PAUSE_BLOCK src=client who=%s", who);
    client_print(id, print_chat, "[KTP] Console pause is disabled. Use /pause in chat.");
    return PLUGIN_HANDLED;
}

public cmd_block_pause_srv() {
    // server console has no id; our safeguard is the internal flag
    if (g_allowInternalPause) return PLUGIN_CONTINUE;

    log_ktp("event=PAUSE_BLOCK src=server");
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
    new map[32]; get_mapname(map, charsmax(map));
    new cfg[128]; new found = lookup_cfg_for_map(map, cfg, charsmax(cfg));
    new techA = g_techBudget[1], techX = g_techBudget[2];

    client_print(id, print_chat,
        "[KTP] need=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, map, found?cfg:"-", found?"found":"MISS");
    client_print(id, print_console,
        "[KTP] need=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_techBudgetSecs, alliesReady, alliesPlayers, techA, axisReady, axisPlayers, techX, map, found?cfg:"-", found?"found":"MISS");
    return PLUGIN_HANDLED;
}