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

#define PLUGIN_NAME    "KTP Match Handler"
#define PLUGIN_VERSION "0.2.7"
#define PLUGIN_AUTHOR  "Nein_"

// ---------- CVARs ----------
new g_cvarPrePauseSec;
new g_cvarTechBudgetSec;
new g_cvarCountdown;
new g_cvarHud;
new g_cvarLogFile;
new g_cvarReadyReq;
new g_cvarCfgBase;
new g_cvarMapsFile;
new g_cvarAutoReqSec;

// ---------- State ----------
new g_prePauseSeconds = 5;
new bool: g_isPaused = false;
new bool: g_matchPending = false;
new bool: g_countdownActive = false;
new bool: g_matchLive = false;              // becomes true after first LIVE

new g_taskCountdownId = 55601;
new g_taskPendingHudId = 55602;
new g_taskPrestartHudId = 55603;
new g_taskAutoUnpauseReqId = 55604;
new g_taskPauseHudId = 55605;


// ==== Easy-tweak config (authoritative defaults) ====
new g_readyRequired   = 1;  // players needed per team to go live
new g_countdownSeconds = 10; // unpause/live countdown seconds
new g_countdownLeft = 0;
new const DEFAULT_LOGFILE[] = "ktp_match.log";

// Unpause attribution
new g_lastUnpauseBy[80];

// Track who paused (for HUD display)
new g_lastPauseBy[80];

// Internal allow-list to let our own pause toggle through the srv hook
new bool: g_allowInternalPause = false;

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
new g_pauseCountTeam[3];                    // index by teamId (1..2). Reset at new half or when PRE-START begins
new g_autoReqLeft = 0;                      // seconds left for auto-request countdown (HUD)

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
    if (g_cvarPrePauseSec) { 
        new v3 = get_pcvar_num(g_cvarPrePauseSec); 
        if (v3 > 0) g_prePauseSeconds = v3; 
    }
    if (g_cvarTechBudgetSec) { 
        new v4 = get_pcvar_num(g_cvarTechBudgetSec); 
        if (v4 > 0) g_techBudgetSecs = v4; 
    }
    if (g_cvarReadyReq) {
        new v = get_pcvar_num(g_cvarReadyReq);
        if (v > 0) g_readyRequired = v;
    }
    if (g_cvarCountdown) {
        new v2 = get_pcvar_num(g_cvarCountdown);
        if (v2 > 0) g_countdownSeconds = v2;
    }
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
    if (n >= 4 && equali(s[n-4], ".bsp")) {
        s[n-4] = EOS;
    }
    trim(s);
}


stock strtolower_inplace(s[]) {
    for (new i = 0; s[i]; i++) if (s[i] >= 'A' && s[i] <= 'Z') s[i] += 32;
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
    if (used < 0) used = 0;
    if (used > 1) used = 1;
    return 1 - used;
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

        strip_bsp_suffix(key);

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
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
    strip_bsp_suffix(lower);
    copy(lower, charsmax(lower), map);
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
    if (!g_isPaused) {
        g_allowInternalPause = true;
        server_cmd("pause");
        server_exec();
        g_allowInternalPause = false;
        g_isPaused = true;
        log_ktp("event=PAUSE_TOGGLE source=plugin reason='%s'", reason);
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
    announce_all("Live! (Unpaused by %s)", g_lastUnpauseBy[0] ? g_lastUnpauseBy : "unknown");

    ktp_pause_now("auto")
    g_isPaused = false;

    // Clear pause-session state
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    if (task_exists(g_taskAutoUnpauseReqId)) remove_task(g_taskAutoUnpauseReqId);
    if (task_exists(g_taskPauseHudId)) remove_task(g_taskPauseHudId);
}

public pause_hud_tick() {
    // Only show during a paused, LIVE match
    if (!g_isPaused || !g_matchLive) { remove_task(g_taskPauseHudId); return; }

    // Decrement auto-request time while owner hasn't requested yet
    if (!g_unpauseRequested && g_autoReqLeft > 0) g_autoReqLeft--;

    new ownerName[16]; team_name_from_id(g_pauseOwnerTeam, ownerName, charsmax(ownerName));

    new otherTeamId = (g_pauseOwnerTeam == 1) ? 2 : 1;
    new needTeamName[16]; team_name_from_id(otherTeamId, needTeamName, charsmax(needTeamName));

    // Pauses remaining per team (0–1), clamped
    new alliesLeft = pauses_left(1);
    new axisLeft   = pauses_left(2);

    set_hudmessage(100, 200, 255, 0.02, 0.25, 0, 0.0, 1.0, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);

    if (g_countdownActive) {
        ShowSyncHudMsg(0, g_hudSync,
            "KTP Pause^nOwner: %s^nPaused by: %s^nStatus: COUNTDOWN^nSeconds: %d^nPauses left — Allies:%d Axis:%d",
            ownerName,
            g_lastPauseBy[0] ? g_lastPauseBy : "Unknown",
            g_countdownLeft,
            alliesLeft, axisLeft);
    } else {
        ShowSyncHudMsg(0, g_hudSync,
            "KTP Pause^nOwner: %s^nPaused by: %s^nOwner requested: %s^nOther team (%s) confirmed: %s^nAuto-request in: %s^nPauses left — Allies:%d Axis:%d",
            ownerName,
            g_lastPauseBy[0] ? g_lastPauseBy : "Unknown",
            g_unpauseRequested ? "Yes" : "No",
            needTeamName,
            g_unpauseConfirmedOther ? "Yes" : "No",
            g_unpauseRequested ? "-" : (g_autoReqLeft > 0 ? fmt_seconds(g_autoReqLeft) : "0s"),
            alliesLeft, axisLeft);
    }
}

// ================= Pre-Start HUD =================
public pending_hud_tick() {
    if (!g_matchPending) { remove_task(g_taskPendingHudId); return; }
    new ap, xp, ar, xr; get_ready_counts(ap, xp, ar, xr);
    new techA = g_techBudget[1]; new techX = g_techBudget[2];
    new need = g_readyRequired;

    set_hudmessage(0, 255, 140, 0.01, 0.12, 0, 0.0, 1.2, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,"KTP Match Pending^nAllies: %d/%d ready^nAxis: %d/%d ready^nNeed %d/team^nType /ready when ready.", ar, ap, xr, xp, need);
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
    if (task_exists(g_taskPrestartHudId)) remove_task(g_taskPrestartHudId);

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

    new tmpCountdown[8];
    new tmpReady[8];
    new tmpPre[8];
    new tmpTech[8];

    num_to_str(g_countdownSeconds, tmpCountdown, charsmax(tmpCountdown));
    num_to_str(g_readyRequired,   tmpReady,     charsmax(tmpReady));
    num_to_str(g_prePauseSeconds, tmpPre, charsmax(tmpPre));
    num_to_str(g_techBudgetSecs, tmpTech, charsmax(tmpTech));

    g_cvarCountdown      = register_cvar("ktp_pause_countdown", tmpCountdown);
    g_cvarReadyReq       = register_cvar("ktp_ready_required", tmpReady);
    g_cvarPrePauseSec    = register_cvar("ktp_prepause_seconds", tmpPre);
    g_cvarTechBudgetSec  = register_cvar("ktp_tech_budget_seconds", tmpTech);
    g_cvarLogFile        = register_cvar("ktp_match_logfile", DEFAULT_LOGFILE);
    g_cvarForcePausable  = register_cvar("ktp_force_pausable", "1");
    g_cvarHud            = register_cvar("ktp_pause_hud", "1");
    g_cvarCfgBase        = register_cvar("ktp_cfg_basepath", "dod/");
    g_cvarMapsFile       = register_cvar("ktp_maps_file", "addons/amxmodx/configs/ktp_maps.ini");
    g_cvarAutoReqSec     = register_cvar("ktp_unpause_autorequest_secs", "300");

    ktp_sync_config_from_cvars();

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

    // Block client console "pause" and attribute it
    register_clcmd("pause", "cmd_client_pause");

    // Block server/RCON pause/unpause entirely
    // AMXX seems unable to block server rcon. Would need other modules for this
    //register_srvcmd("pause",   "srv_block_pause");
    //register_srvcmd("unpause", "srv_block_unpause");

    g_hudSync = CreateHudSyncObj();
    g_pcvarPausable = get_cvar_pointer("pausable");
    g_lastUnpauseBy[0] = EOS;
    g_lastPauseBy[0] = EOS;

    // Announce on load
    ktp_banner_enabled();
    load_map_mappings();
}

public plugin_cfg() { 
    ktp_sync_config_from_cvars();
    load_map_mappings(); 
}

public plugin_end() {
    if (task_exists(g_taskCountdownId)) remove_task(g_taskCountdownId);
    if (task_exists(g_taskPendingHudId)) remove_task(g_taskPendingHudId);
    if (task_exists(g_taskPrestartHudId)) remove_task(g_taskPrestartHudId);
    if (task_exists(g_taskAutoUnpauseReqId)) remove_task(g_taskAutoUnpauseReqId);
    if (task_exists(g_taskPauseHudId)) remove_task(g_taskPauseHudId);
}

// Shared handler
stock on_client_left(id) {
    if (id >= 1 && id <= 32) g_ready[id] = false;
}

// Use the newer forward when available; fall back for older AMXX
#if defined AMXX_VERSION_NUM && AMXX_VERSION_NUM >= 190
public client_disconnected(id) { on_client_left(id); }
#else
public client_disconnect(id) { on_client_left(id); }
#endif

public client_putinserver(id) {
    // Quick heads-up in chat for late joiners
    client_print(id, print_chat,
        "[KTP] need=%d | unpause_countdown=%d | prepause=%d | tech_budget=%d | Allies %d/%d (tech:%ds), Axis %d/%d (tech:%ds) | map=%s cfg=%s (%s)",
        g_readyRequired, g_countdownSeconds, g_prePauseSeconds, g_techBudgetSecs,
        ar, ap, techA, xr, xp, techX, map, found?cfg:"-", found?"found":"MISS");
    client_print(id, print_console, "[KTP] %s v%s by %s enabled", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}


// ================= Counts & commands =================
stock get_ready_counts(&alliesPlayers, &axisPlayers, &alliesReady, &axisReady) {
    alliesPlayers = 0; axisPlayers = 0; alliesReady = 0; axisReady = 0;
    new ids[32], num; get_players(ids, num, "ch");
    for (new i = 0; i < num; i++) {
        new id = ids[i], tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
        if (tid == 1) { alliesPlayers++; if (g_ready[id]) alliesReady++; }
        else if (tid == 2) { axisPlayers++; if (g_ready[id]) axisReady++; }
    }
}

// ===== Map reload =====
public cmd_reload_maps(id) {
    load_map_mappings();
    new name[32], sid[44], ip[32], team[16], map[32];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_mapname(map, charsmax(map));
    log_ktp("event=MAPS_RELOAD by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);
    client_print(id, print_chat, "[KTP] Map mappings reloaded.");
    return PLUGIN_HANDLED;
}

// ===== Client console 'pause' =====
public cmd_client_pause(id) {
    new name[32], sid[44], ip[32], team[16], map[32];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_mapname(map, charsmax(map));
    log_ktp("event=PAUSE_BLOCK_CLIENT player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);
    announce_all("Blocked client 'pause' from %s[%s] (%s). Use /pause or /resume.", name, sid, ip[0]?ip:"NA");
    return PLUGIN_HANDLED;
}

// ===== Chat pause/resume with ownership & confirm =====
public cmd_chat_toggle(id) {
    // If a countdown is active, only the pause-owning team can cancel it by typing /pause again.
    if (g_countdownActive) {
        new tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
        if (tid != g_pauseOwnerTeam) {
            client_print(id, print_chat, "[KTP] Only the pause-owning team can cancel the unpause countdown.");
            return PLUGIN_HANDLED;
        }
        remove_task(g_taskCountdownId); g_countdownActive = false;
        new name[32], sid[44], ip[32], team[16], map[32];
        get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
        get_mapname(map, charsmax(map));
        log_ktp("event=UNPAUSE_CANCEL player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);
        announce_all("Unpause countdown cancelled by %s. Staying paused.", name);

        // Re-arm auto-request and reset flag; HUD keeps running
        g_unpauseRequested = false;
        new secs = get_pcvar_num(g_cvarAutoReqSec);
        if (secs < 60) secs = 300;
        g_autoReqLeft = secs;
        if (!task_exists(g_taskAutoUnpauseReqId)) set_task(float(secs), "auto_unpause_request", g_taskAutoUnpauseReqId);
        return PLUGIN_HANDLED;
    }

    // Normal toggle behavior depending on current paused state
    new name2[32], sid2[44], ip2[32], team2[16], map2[32];
    get_identity(id, name2, charsmax(name2), sid2, charsmax(sid2), ip2, charsmax(ip2), team2, charsmax(team2));
    get_mapname(map2, charsmax(map2));

    new tname2[16]; new tid2 = get_user_team(id, tname2, charsmax(tname2));

    if (!g_isPaused) {
        // Enforce per-team pause limits only AFTER the match is live
        if (g_matchLive) {
            if (tid2 != 1 && tid2 != 2) { client_print(id, print_chat, "[KTP] Spectators cannot pause."); return PLUGIN_HANDLED; }
            if (g_pauseCountTeam[tid2] >= 1) {
                log_ktp("event=PAUSE_DENY_LIMIT team=%d player=\'%s\' steamid=%s", tid2, name2, sid2[0]?sid2:"NA");
                client_print(id, print_chat, "[KTP] Your team has already used its pause.");
                return PLUGIN_HANDLED;
            }
            g_pauseCountTeam[tid2]++;           // consume the team pause
            g_pauseOwnerTeam = tid2;            // set ownership
            g_unpauseRequested = false;
            g_unpauseConfirmedOther = false;

            // schedule auto-unpause request if owner forgets to /resume
            new secs = get_pcvar_num(g_cvarAutoReqSec);
            if (secs < 60) secs = 300; // sane default
            if (task_exists(g_taskAutoUnpauseReqId)) remove_task(g_taskAutoUnpauseReqId);
            set_task(float(secs), "auto_unpause_request", g_taskAutoUnpauseReqId);
            g_autoReqLeft = secs;

            log_ktp("event=PAUSE_AUTOREQ_ARM team=%d seconds=%d", g_pauseOwnerTeam, secs);
        } else {
            // This is the pre-start/pending pause (doesn't count)
            g_pauseOwnerTeam = 0;
            if (task_exists(g_taskAutoUnpauseReqId)) remove_task(g_taskAutoUnpauseReqId);
            g_autoReqLeft = 0;
        }

        // Actually pause
        ktp_pause_now("auto")

        // record who paused for HUD
        formatex(g_lastPauseBy, charsmax(g_lastPauseBy), "%s", name2);

        // start HUD ticker only for live match pauses
        if (g_matchLive && !task_exists(g_taskPauseHudId)) {
            set_task(1.0, "pause_hud_tick", g_taskPauseHudId, _, _, "b");
        }

        log_ktp("event=PAUSE_BY_CHAT player=\'%s\' steamid=%s ip=%s team=%s map=%s live=%d team_pause_used=%d/%d",
                name2, sid2[0]?sid2:"NA", ip2[0]?ip2:"NA", team2, map2, g_matchLive ? 1 : 0,
                (tid2==1)?g_pauseCountTeam[1]:g_pauseCountTeam[2], 1);

        if (g_matchLive) {
            announce_all("Match paused by %s. Only %s may /resume. Other team must /confirmunpause. (1 pause per team)",
                         name2, team2);
            client_print(id, print_chat, "[KTP] Your team pauses left after this: %d.", pauses_left(tid2));
        } else {
            announce_all("Match paused by %s. (pre-start/pending phase; does not count)", name2);
        }
    } else {
        // Server is paused. Only the owning team can request unpause.
        if (g_matchPending || g_preStartPending) {
            client_print(id, print_chat, "[KTP] Match is pending. Use /ready; server will resume automatically.");
            return PLUGIN_HANDLED;
        }

        if (g_pauseOwnerTeam == 0 && g_matchLive) {
            // Edge: somehow no owner recorded; recover by assigning on first /resume attempt
            g_pauseOwnerTeam = (tid2==1 || tid2==2) ? tid2 : 0;
        }

        if (g_matchLive) {
            if (tid2 != g_pauseOwnerTeam) {
                client_print(id, print_chat, "[KTP] Only the pause-owning team may /resume. Other team should /confirmunpause.");
                return PLUGIN_HANDLED;
            }
        }
        // Owner requests unpause
        g_unpauseRequested = true;
        g_autoReqLeft = 0; // stop HUD timer
        copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), name2);
        log_ktp("event=UNPAUSE_REQUEST_OWNER team=%d by=\'%s\' steamid=%s", g_pauseOwnerTeam, name2, sid2[0]?sid2:"NA");
        announce_all("%s requested unpause. Waiting for the other team to /confirmunpause.", team2);

        // If the other team has pre-confirmed (rare), start the countdown now
        if (g_unpauseConfirmedOther) {
            start_unpause_countdown(g_lastUnpauseBy);
        }
    }
    return PLUGIN_HANDLED;
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

    new tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
    if (tid != 1 && tid != 2) { client_print(id, print_chat, "[KTP] Spectators can’t confirm unpause."); return PLUGIN_HANDLED; }

    if (g_pauseOwnerTeam == 0) { client_print(id, print_chat, "[KTP] No pause owner registered."); return PLUGIN_HANDLED; }
    if (tid == g_pauseOwnerTeam) { client_print(id, print_chat, "[KTP] Your team owns this pause; use /resume."); return PLUGIN_HANDLED; }

    new name[32], sid[44], ip[32], team[16];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));

    g_unpauseConfirmedOther = true;
    log_ktp("event=UNPAUSE_CONFIRM_OTHER team=%d by=\'%s\' steamid=%s", tid, name, sid[0]?sid:"NA");
    announce_all("%s confirmed unpause.", team);

    // If owner already requested (or auto-request fired), we can start countdown
    if (g_unpauseRequested) {
        start_unpause_countdown(g_lastUnpauseBy[0] ? g_lastUnpauseBy : team);
    } else {
        client_print(id, print_chat, "[KTP] Waiting for the pause-owning team to /resume (or auto-request).");
    }
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

// ===== Start / Pre-Start =====
public cmd_match_start(id) {
    if (g_matchPending || g_preStartPending) {
        client_print(id, print_chat, "[KTP] A match is already starting or pending.");
        return PLUGIN_HANDLED;
    }

    g_preStartPending = true; g_preConfirmAllies = false; g_preConfirmAxis = false;
    g_confirmAlliesBy[0] = EOS; g_confirmAxisBy[0] = EOS;

    // Pre-start pause (does NOT count)
    if (!g_isPaused) {
        ktp_pause_now("auto")
        g_isPaused = true;
        log_ktp("event=PRESTART_AUTOPAUSE");
    }

    // Reset pause limits for the new half
    g_pauseCountTeam[1] = 0;
    g_pauseCountTeam[2] = 0;
    g_pauseOwnerTeam = 0;
    g_unpauseRequested = false;
    g_unpauseConfirmedOther = false;
    g_matchLive = false;
    if (task_exists(g_taskPauseHudId)) remove_task(g_taskPauseHudId);

    new name[32], sid[44], ip[32], team[16], map[32];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_mapname(map, charsmax(map));

    log_ktp("event=PRESTART_BEGIN by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);
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
    if (!g_preStartPending) { client_print(id, print_chat, "[KTP] Not in pre-start. Use /start."); return PLUGIN_HANDLED; }
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new who[80]; new name[32], sid[44], ip[32], team[16];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_who_str(id, who, charsmax(who));

    new tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
    if (tid == 1) {
        if (g_preConfirmAllies) { client_print(id, print_chat, "[KTP] Allies already confirmed by %s.", g_confirmAlliesBy); return PLUGIN_HANDLED; }
        g_preConfirmAllies = true; copy(g_confirmAlliesBy, charsmax(g_confirmAlliesBy), who);
        log_ktp("event=PRECONFIRM team=Allies player=\'%s\' steamid=%s ip=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA");
        announce_all("Pre-Start: Allies confirmed by %s.", who);
    } else if (tid == 2) {
        if (g_preConfirmAxis) { client_print(id, print_chat, "[KTP] Axis already confirmed by %s.", g_confirmAxisBy); return PLUGIN_HANDLED; }
        g_preConfirmAxis = true; copy(g_confirmAxisBy, charsmax(g_confirmAxisBy), who);
        log_ktp("event=PRECONFIRM team=Axis player=\'%s\' steamid=%s ip=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA");
        announce_all("Pre-Start: Axis confirmed by %s.", who);
    } else {
        client_print(id, print_chat, "[KTP] You must be on Allies or Axis to confirm.");
        return PLUGIN_HANDLED;
    }

    if (g_preConfirmAllies && g_preConfirmAxis) {
        announce_all("Pre-Start complete. Proceeding to Ready phase.");
        log_ktp("event=PRESTART_COMPLETE");
        prestart_reset();

        ktp_pause_now("pending_enforce");
        arrayset(g_ready, 0, sizeof g_ready);

        if (!task_exists(g_taskPendingHudId)) set_task(1.0, "pending_hud_tick", g_taskPendingHudId, _, _, "b");

        new map[32]; get_mapname(map, charsmax(map));
        new alliesTag[64], axisTag[64];
        if (!infer_team_tag(1, alliesTag, charsmax(alliesTag))) copy(alliesTag, charsmax(alliesTag), "Allies");
        if (!infer_team_tag(2, axisTag,   charsmax(axisTag)))   copy(axisTag,   charsmax(axisTag),   "Axis");
        log_ktp("event=PENDING_BEGIN allies=\'%s\' axis=\'%s\' map=%s need=%d", alliesTag, axisTag, map, g_readyRequired);
        announce_all("Match pending: %s vs %s on %s. Each team type /ready (need %d).",
                     alliesTag, axisTag, map, g_readyRequired);
    }
    return PLUGIN_HANDLED;
}

public cmd_pre_notconfirm(id) {
    if (!g_preStartPending) return PLUGIN_HANDLED;
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new who[80]; get_who_str(id, who, charsmax(who));
    new name[32], sid[44], ip[32], team[16]; get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));

    new tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
    if (tid == 1) {
        if (!g_preConfirmAllies) { client_print(id, print_chat, "[KTP] Allies had not confirmed yet."); return PLUGIN_HANDLED; }
        g_preConfirmAllies = false; g_confirmAlliesBy[0] = EOS;
        log_ktp("event=PRENOTCONFIRM team=Allies player=\'%s\' steamid=%s ip=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA");
        announce_all("Pre-Start: Allies not confirmed (reset by %s).", who);
    } else if (tid == 2) {
        if (!g_preConfirmAxis) { client_print(id, print_chat, "[KTP] Axis had not confirmed yet."); return PLUGIN_HANDLED; }
        g_preConfirmAxis = false; g_confirmAxisBy[0] = EOS;
        log_ktp("event=PRENOTCONFIRM team=Axis player=\'%s\' steamid=%s ip=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA");
        announce_all("Pre-Start: Axis not confirmed (reset by %s).", who);
    }
    return PLUGIN_HANDLED;
}

public cmd_cancel(id) {
    if (g_preStartPending) {
        new name[32], sid[44], ip[32], team[16], map[32];
        get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
        get_mapname(map, charsmax(map));
        prestart_reset();
        log_ktp("event=PRESTART_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);
        announce_all("Pre-Start cancelled by %s.", name);
        return PLUGIN_HANDLED;
    }

    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }

    g_matchPending = false;
    arrayset(g_ready, 0, sizeof g_ready);
    if (task_exists(g_taskPendingHudId)) remove_task(g_taskPendingHudId);

    new name2[32], sid2[44], ip2[32], team2[16], map2[32];
    get_identity(id, name2, charsmax(name2), sid2, charsmax(sid2), ip2, charsmax(ip2), team2, charsmax(team2));
    get_mapname(map2, charsmax(map2));
    log_ktp("event=PENDING_CANCEL by=\'%s\' steamid=%s ip=%s team=%s map=%s", name2, sid2[0]?sid2:"NA", ip2[0]?ip2:"NA", team2, map2);
    announce_all("Match pending cancelled by %s.", name2);
    return PLUGIN_HANDLED;
}

// ----- Ready / NotReady / Status -----
public cmd_ready(id) {
    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match. Use /start to begin."); return PLUGIN_HANDLED; }
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (g_ready[id]) { client_print(id, print_chat, "[KTP] You are already READY."); return PLUGIN_HANDLED; }

    g_ready[id] = true;

    new name[32], sid[44], ip[32], team[16], map[32];
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_mapname(map, charsmax(map));
    log_ktp("event=READY player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);

    new ap, xp, ar, xr; get_ready_counts(ap, xp, ar, xr);
    new need = g_readyRequired;
    announce_all("%s is READY. Allies %d/%d | Axis %d/%d (need %d each).", name, ar, ap, xr, xp, need);

    if (ar >= need && xr >= need) {
        exec_map_config();

        new alliesTag[64], axisTag[64];
        if (!infer_team_tag(1, alliesTag, charsmax(alliesTag))) copy(alliesTag, charsmax(alliesTag), "Allies");
        if (!infer_team_tag(2, axisTag,   charsmax(axisTag)))   copy(axisTag,   charsmax(axisTag),   "Axis");

        log_ktp("event=MATCH_START allies=\'%s\' axis=\'%s\' map=%s allies_ready=%d axis_ready=%d", alliesTag, axisTag, map, ar, xr);
        announce_all("All players ready. %s vs %s", alliesTag, axisTag);

        g_matchPending = false;
        arrayset(g_ready, 0, sizeof g_ready);
        if (task_exists(g_taskPendingHudId)) remove_task(g_taskPendingHudId);

        if (!g_isPaused) { ktp_pause_now("auto") }
        if (!g_lastUnpauseBy[0]) copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), "system");

        // First LIVE of this half → mark match live and reset pause-session vars
        g_countdownLeft = max(1, g_countdownSeconds);
        g_countdownActive = true;
        g_matchLive = true;
        g_pauseOwnerTeam = 0;
        g_unpauseRequested = false;
        g_unpauseConfirmedOther = false;
        if (task_exists(g_taskAutoUnpauseReqId)) remove_task(g_taskAutoUnpauseReqId);
        if (task_exists(g_taskPauseHudId)) remove_task(g_taskPauseHudId);

        log_ktp("event=COUNTDOWN begin=%d requested_by=\'%s\'", g_countdownLeft, g_lastUnpauseBy);
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
    get_identity(id, name, charsmax(name), sid, charsmax(sid), ip, charsmax(ip), team, charsmax(team));
    get_mapname(map, charsmax(map));
    log_ktp("event=NOTREADY player=\'%s\' steamid=%s ip=%s team=%s map=%s", name, sid[0]?sid:"NA", ip[0]?ip:"NA", team, map);

    new ap, xp, ar, xr; get_ready_counts(ap, xp, ar, xr);
    new need = g_readyRequired;
    announce_all("%s is NOT READY. Allies %d/%d | Axis %d/%d (need %d each).", name, ar, ap, xr, xp, need);
    return PLUGIN_HANDLED;
}

public cmd_status(id) {
    if (!g_matchPending) { client_print(id, print_chat, "[KTP] No pending match."); return PLUGIN_HANDLED; }
    new ap, xp, ar, xr; get_ready_counts(ap, xp, ar, xr);
    new need = g_readyRequired;
    client_print(id, print_chat, "[KTP] Allies %d/%d | Axis %d/%d (need %d each).", ar, ap, xr, xp, need);
    return PLUGIN_HANDLED;
}

// ================= Server/Client pause blocking =================
//public srv_block_pause() {
//    if (g_allowInternalPause) return PLUGIN_CONTINUE;
//    log_ktp("event=PAUSE_BLOCK_SERVER context=server_or_rcon");
//    announce_all("Blocked server/RCON 'pause' (no player context). Use /pause or /resume.");
//    return PLUGIN_HANDLED;
//}

//public srv_block_unpause() {
//    if (g_allowInternalPause) return PLUGIN_CONTINUE;
//    log_ktp("event=UNPAUSE_BLOCK_SERVER context=server_or_rcon");
//    announce_all("Blocked server/RCON 'unpause' (no player context). Use /resume.");
//    return PLUGIN_HANDLED;
//}

// ================= Name Sanitizers and Team Team tag inference (compact) =================
stock lcp(const namesLower[][], total, out[], outLen) {
    if (total <= 0) { out[0] = EOS; return; }

    new i, pos = 0;

    // Loop while the first string still has characters
    while (namesLower[0][pos] != EOS) {
        new ch = namesLower[0][pos];

        // Verify all other strings share this character at 'pos'
        for (i = 1; i < total; i++) {
            if (namesLower[i][pos] == EOS || namesLower[i][pos] != ch) {
                out[pos] = EOS;
                return;
            }
        }

        // Append if room remains; otherwise stop and terminate
        if (pos < outLen - 1) {
            out[pos++] = ch;
        } else {
            break;
        }
    }

    out[pos] = EOS;
}


stock lcs(const namesLower[][], total, out[], outLen) {
    if (total <= 0) { out[0] = EOS; return; }
    new i, minlen = 9999, len;
    for (i = 0; i < total; i++) { len = strlen(namesLower[i]); if (len < minlen) minlen = len; }

    new pos = 0;
    while (pos < minlen) {
        new ch = namesLower[0][strlen(namesLower[0]) - 1 - pos];
        for (i = 1; i < total; i++) {
            if (namesLower[i][strlen(namesLower[i]) - 1 - pos] != ch) {
                new rev[64], j;
                for (j = 0; j < pos && j < outLen - 1; j++) rev[j] = namesLower[0][strlen(namesLower[0]) - pos + j];
                rev[j] = EOS; copy(out, outLen, rev); return;
            }
        }
        pos++; if (pos >= outLen - 1) break;
    }

    new rev2[64], k;
    for (k = 0; k < pos && k < outLen - 1; k++) rev2[k] = namesLower[0][strlen(namesLower[0]) - pos + k];
    rev2[k] = EOS; copy(out, outLen, rev2);
}

stock project_case_from_sample(const sampleOrig[], const tagLower[], out[], outLen, bool:useSuffix) {
    new soLen = strlen(sampleOrig), tLen = strlen(tagLower);
    if (!tLen) { out[0] = EOS; return; }
    if (!useSuffix) {
        new i, w = 0;
        for (i = 0; i < soLen && w < tLen && w < outLen - 1; i++) {
            new c = sampleOrig[i];
            new lower = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
            if (lower == tagLower[w]) out[w++] = c;
        }
        out[w] = EOS;
    } else {
        if (soLen >= tLen) copy(out, outLen, sampleOrig[soLen - tLen]);
        else copy(out, outLen, tagLower);
    }
}

stock infer_team_tag(teamId, outTag[], outLen, bool:preferSuffix = true) {
    new ids[32], num; get_players(ids, num, "ch");
    new lower[32][64], orig[32][64], total = 0;

    for (new i = 0; i < num && total < 32; i++) {
        new id = ids[i], tname[16]; new tid = get_user_team(id, tname, charsmax(tname));
        if (tid != teamId) continue;
        new pname[64]; get_user_name(id, pname, charsmax(pname));
        sanitize_name(pname, lower[total], orig[total], 64);
        if (strlen(lower[total]) < 2) continue;
        total++;
    }

    if (total <= 0) { outTag[0] = EOS; return 0; }

    new pfx[64], sfx[64]; lcp(lower, total, pfx, 64); lcs(lower, total, sfx, 64); trim(pfx); trim(sfx);

    new best[64];
    if (preferSuffix && strlen(sfx) >= 2 && strlen(sfx) >= strlen(pfx)) project_case_from_sample(orig[0], sfx, best, 64, true);
    else if (strlen(pfx) >= 2) project_case_from_sample(orig[0], pfx, best, 64, false);
    else if (strlen(sfx) >= 2) project_case_from_sample(orig[0], sfx, best, 64, true);
    else { outTag[0] = EOS; return 0; }

    copy(outTag, outLen, best); trim(outTag); return strlen(outTag);
}

stock sanitize_name(const src[], outLower[], outOrig[], outLen) {
    new i = 0, jLower = 0, jOrig = 0, c;

    // Leave space for EOS in both outputs
    while ((c = src[i]) && jLower < outLen - 1 && jOrig < outLen - 1) {
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            c == ' ' || c == '.' || c == '_' || c == '-' ||
            c == '[' || c == ']' || c == '(' || c == ')' ||
            c == '{' || c == '}' || c == '|' || c == '<' || c == '>') {

            outOrig[jOrig++] = c;

            if (c >= 'A' && c <= 'Z') c += 32; // tolower
            outLower[jLower++] = c;
        }
        i++;
    }

    outOrig[jOrig]   = EOS;
    outLower[jLower] = EOS;
}


public cmd_ktpconfig(id) {
    new ap, xp, ar, xr; get_ready_counts(ap, xp, ar, xr);
    new map[32]; get_mapname(map, charsmax(map));
    new cfg[128]; new found = lookup_cfg_for_map(map, cfg, charsmax(cfg));
    client_print(id, print_chat,
        "[KTP] need=%d | unpause_countdown=%d | prepause=%d | tech_budget=%d | Allies %d/%d, Axis %d/%d | map=%s cfg=%s (%s)",
        g_readyRequired, g_countdownSeconds, g_prePauseSeconds, g_techBudgetSecs,
        ar, ap, xr, xp, map, found?cfg:"-", found?"found":"MISS");
    return PLUGIN_HANDLED;
}