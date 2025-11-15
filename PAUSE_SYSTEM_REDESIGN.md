# KTP Pause System Redesign

## New Pause Flow

### When ANY pause is initiated:
1. **Pre-pause countdown** (3 seconds)
   - Chat: "Pausing in 3..."
   - Chat: "Pausing in 2..."
   - Chat: "Pausing in 1..."
   - HUD countdown visible
2. **Pause activates**
   - Server executes `pause` command
   - Start 5-minute timer
   - Begin HUD updates (every 0.5s via ReHLDS hook)
3. **During pause**
   - HUD shows: elapsed time, remaining time, who paused, extension status
   - Chat works (thanks to ReHLDS modifications)
   - `/extend` available to request more time
4. **Unpause process**
   - Owner types `/resume` OR 5-minute timer expires
   - Other team types `/confirmunpause`
   - 3-second countdown: "Unpausing in 3... 2... 1... LIVE!"
   - Game resumes

## New Variables Needed

```pawn
// Pause timing
new g_pauseStartTime;           // When pause began (Unix timestamp)
new g_pauseDurationSec = 300;   // 5 minutes default
new g_pauseExtensions = 0;      // How many extensions used
new g_pauseExtensionSec = 120;  // 2 minutes per extension
new g_maxPauseExtensions = 2;   // Max 2 extensions (9 minutes total)

// Pre-pause countdown
new bool: g_prePauseCountdown = false;
new g_prePauseLeft = 0;
new g_prePauseReason[64];
new g_prePauseInitiator[32];

// Pause timer HUD
new g_taskPauseTimerId = 55606;
```

## New CVARs

```pawn
// In plugin_init():
g_cvarPauseDuration    = register_cvar("ktp_pause_duration", "300");      // 5 minutes
g_cvarPauseExtension   = register_cvar("ktp_pause_extension", "120");     // 2 minute extensions
g_cvarMaxExtensions    = register_cvar("ktp_pause_max_extensions", "2");  // Max 2 extensions
g_cvarPrePauseSec      = register_cvar("ktp_prepause_countdown", "3");    // 3 second pre-pause countdown
```

## Modified Functions

### 1. Intercept ALL Pause Commands

```pawn
// Block native pause, trigger our system instead
public cmd_block_pause(id) {
    // If it's our internal pause, allow it
    if (g_allowInternalPause || id == 0) return PLUGIN_CONTINUE;

    // Otherwise, trigger our controlled pause system
    new name[32];
    get_user_name(id, name, charsmax(name));

    trigger_pause_countdown(name, "client command");
    return PLUGIN_HANDLED;
}

public cmd_block_pause_srv() {
    if (g_allowInternalPause) return PLUGIN_CONTINUE;

    // RCON pause - trigger our system
    trigger_pause_countdown("Server", "rcon command");
    return PLUGIN_HANDLED;
}
```

### 2. Pre-Pause Countdown

```pawn
stock trigger_pause_countdown(const who[], const reason[]) {
    if (g_isPaused) {
        client_print(0, print_chat, "[KTP] Game is already paused.");
        return;
    }

    if (g_prePauseCountdown) {
        client_print(0, print_chat, "[KTP] Pause countdown already in progress.");
        return;
    }

    copy(g_prePauseInitiator, charsmax(g_prePauseInitiator), who);
    copy(g_prePauseReason, charsmax(g_prePauseReason), reason);

    g_prePauseLeft = get_pcvar_num(g_cvarPrePauseSec);
    g_prePauseCountdown = true;

    set_task(1.0, "prepause_countdown_tick", g_taskPrePauseId, _, _, "b");

    client_print(0, print_chat, "[KTP] %s initiated pause. Pausing in %d seconds...", who, g_prePauseLeft);
    log_ktp("event=PREPAUSE_START initiator='%s' reason='%s' countdown=%d", who, reason, g_prePauseLeft);
}

public prepause_countdown_tick() {
    if (!g_prePauseCountdown) {
        remove_task(g_taskPrePauseId);
        return;
    }

    if (g_prePauseLeft <= 0) {
        // Actually pause now
        remove_task(g_taskPrePauseId);
        g_prePauseCountdown = false;

        client_print(0, print_chat, "[KTP] === PAUSING NOW ===");
        execute_pause(g_prePauseInitiator, g_prePauseReason);
        return;
    }

    // Countdown message
    client_print(0, print_chat, "[KTP] Pausing in %d...", g_prePauseLeft);

    g_prePauseLeft--;
}
```

### 3. Execute Pause with Timer

```pawn
stock execute_pause(const who[], const reason[]) {
    ktp_force_pausable_if_needed();

    if (g_isPaused) return;

    // Store pause info
    copy(g_lastPauseBy, charsmax(g_lastPauseBy), who);
    g_pauseStartTime = get_systime();
    g_pauseExtensions = 0;

    // Actually pause
    g_allowInternalPause = true;
    server_cmd("pause");
    server_exec();
    g_allowInternalPause = false;

    g_isPaused = true;

    // Start pause timer and HUD
    g_pauseDurationSec = get_pcvar_num(g_cvarPauseDuration);
    set_task(0.5, "pause_timer_tick", g_taskPauseTimerId, _, _, "b");
    set_task(0.5, "pause_hud_tick", g_taskPauseHudId, _, _, "b");

    client_print(0, print_chat, "[KTP] Game paused by %s. Duration: %d seconds. Type /extend for more time.", who, g_pauseDurationSec);
    log_ktp("event=PAUSE_EXECUTED initiator='%s' reason='%s' duration=%d", who, reason, g_pauseDurationSec);
}
```

### 4. Pause Timer (Auto-Unpause)

```pawn
public pause_timer_tick() {
    if (!g_isPaused) {
        remove_task(g_taskPauseTimerId);
        return;
    }

    new elapsed = get_systime() - g_pauseStartTime;
    new totalDuration = g_pauseDurationSec + (g_pauseExtensions * get_pcvar_num(g_cvarPauseExtension));
    new remaining = totalDuration - elapsed;

    // Warning at 30 seconds remaining
    if (remaining == 30) {
        client_print(0, print_chat, "[KTP] Pause ending in 30 seconds. Type /extend for more time.");
    }

    // Warning at 10 seconds remaining
    if (remaining == 10) {
        client_print(0, print_chat, "[KTP] Pause ending in 10 seconds...");
    }

    // Auto-unpause
    if (remaining <= 0) {
        remove_task(g_taskPauseTimerId);
        client_print(0, print_chat, "[KTP] Pause duration expired. Auto-unpausing...");
        log_ktp("event=PAUSE_TIMEOUT elapsed=%d duration=%d", elapsed, totalDuration);

        // Trigger unpause countdown
        start_unpause_countdown("auto-timeout");
    }
}
```

### 5. Updated Pause HUD

```pawn
stock show_pause_hud_message(const pauseType[]) {
    if (!g_isPaused) return;

    new elapsed = get_systime() - g_pauseStartTime;
    new totalDuration = g_pauseDurationSec + (g_pauseExtensions * get_pcvar_num(g_cvarPauseExtension));
    new remaining = totalDuration - elapsed;

    new elapsedMin = elapsed / 60;
    new elapsedSec = elapsed % 60;
    new remainMin = remaining / 60;
    new remainSec = remaining % 60;

    new pausesA = pauses_left(1);
    new pausesX = pauses_left(2);

    set_hudmessage(255, 255, 255, 0.35, 0.25, 0, 0.0, 0.6, 0.0, 0.0, -1);
    ClearSyncHud(0, g_hudSync);
    ShowSyncHudMsg(0, g_hudSync,
        "^n  == GAME PAUSED ==^n^n  Type: %s^n  By: %s^n^n  Elapsed: %d:%02d  |  Remaining: %d:%02d^n  Extensions: %d/%d^n^n  Pauses Left: A:%d X:%d^n^n  /resume  |  /confirmunpause  |  /extend^n",
        pauseType,
        g_lastPauseBy[0] ? g_lastPauseBy : "Server",
        elapsedMin, elapsedSec,
        remainMin, remainSec,
        g_pauseExtensions, get_pcvar_num(g_cvarMaxExtensions),
        pausesA, pausesX);
}
```

### 6. Extension System

```pawn
// Register command
register_clcmd("say /extend", "cmd_extend_pause");
register_clcmd("say_team /extend", "cmd_extend_pause");

public cmd_extend_pause(id) {
    if (!g_isPaused) {
        client_print(id, print_chat, "[KTP] No active pause to extend.");
        return PLUGIN_HANDLED;
    }

    new maxExt = get_pcvar_num(g_cvarMaxExtensions);
    if (g_pauseExtensions >= maxExt) {
        client_print(id, print_chat, "[KTP] Maximum extensions (%d) already used.", maxExt);
        return PLUGIN_HANDLED;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    new extSec = get_pcvar_num(g_cvarPauseExtension);
    g_pauseExtensions++;

    client_print(0, print_chat, "[KTP] %s extended the pause by %d seconds (%d/%d extensions used).",
        name, extSec, g_pauseExtensions, maxExt);
    log_ktp("event=PAUSE_EXTENDED player='%s' extension=%d/%d seconds=%d",
        name, g_pauseExtensions, maxExt, extSec);

    return PLUGIN_HANDLED;
}
```

### 7. Unpause Countdown (Already Exists, Enhance It)

```pawn
public start_unpause_countdown(const who[]) {
    if (!g_isPaused) return;
    if (g_countdownActive) {
        announce_all("Unpause countdown already running (%d sec left).", g_countdownLeft);
        return;
    }

    copy(g_lastUnpauseBy, charsmax(g_lastUnpauseBy), who);

    g_countdownLeft = max(1, g_countdownSeconds);
    g_countdownActive = true;

    // Stop pause timer
    remove_task(g_taskPauseTimerId);

    new map[32]; get_mapname(map, charsmax(map));
    log_ktp("event=COUNTDOWN begin=%d requested_by='%s' map=%s", g_countdownLeft, who, map);

    // Countdown task already exists, just needs to send chat messages
    set_task(1.0, "countdown_tick", g_taskCountdownId, _, _, "b");

    client_print(0, print_chat, "[KTP] Unpausing in %d seconds...", g_countdownLeft);
}

public countdown_tick() {
    if (!g_countdownActive) {
        remove_task(g_taskCountdownId);
        return;
    }

    if (g_countdownLeft <= 0) {
        // UNPAUSE
        remove_task(g_taskCountdownId);
        g_countdownActive = false;

        client_print(0, print_chat, "[KTP] === LIVE! ===");
        ktp_unpause_now("countdown complete");
        return;
    }

    // Chat countdown
    client_print(0, print_chat, "[KTP] Unpausing in %d...", g_countdownLeft);

    g_countdownLeft--;
}
```

## Summary of Changes

### New Commands:
- `/extend` - Extend pause by 2 minutes (max 2 extensions)

### Enhanced Commands:
- `pause` (console) - Triggers 3-second countdown, then pauses for 5 minutes
- `/pause` (chat) - Same as above
- `/resume` - Triggers unpause countdown (if confirmed)
- `/confirmunpause` - Confirms unpause (triggers countdown)

### New HUD Features:
- Elapsed time (MM:SS)
- Remaining time (MM:SS)
- Extensions used (X/2)
- Commands shown

### Timers:
- **Pre-pause**: 3 seconds (configurable)
- **Pause duration**: 5 minutes (configurable)
- **Extensions**: 2 minutes each, max 2 (configurable)
- **Unpause countdown**: 3-5 seconds (existing)

### Total Possible Pause Time:
- Base: 5 minutes
- With 2 extensions: 9 minutes total

## Implementation Steps

1. Add new variables and CVARs
2. Modify `cmd_block_pause` functions to trigger countdown
3. Add `trigger_pause_countdown()` and `prepause_countdown_tick()`
4. Add `execute_pause()` with timer start
5. Add `pause_timer_tick()` for auto-unpause
6. Update `show_pause_hud_message()` with timer info
7. Add `/extend` command and handler
8. Enhance `countdown_tick()` with chat messages
9. Test thoroughly!
