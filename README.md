# KTP Match Handler

**Version 0.10.1** - Advanced competitive match management system for Day of Defeat servers

A feature-rich AMX ModX plugin providing structured match workflows, ReAPI-powered pause controls with real-time HUD updates, Discord integration, HLStatsX stats integration, match type differentiation, half tracking with context persistence, and comprehensive logging capabilities.

> **Compatible with both AMX Mod X and KTP AMX** - The plugin automatically detects the correct configs directory.

---

## 🎮 Key Features

### Match Management
- **Structured Match Workflow**: Pre-start → Pending → Ready-up → LIVE
- **Match Type System**: Competitive, Scrim, 12-man, and Draft modes with distinct configs
- **Season Control**: Password-protected season toggle - disable competitive matches off-season
- **Match Password Protection**: Competitive matches require password entry
- **Half Tracking**: Automatic 1st/2nd half detection with map rotation adjustment
- **Overtime System**: Automatic OT when regulation ties - 5-min rounds, side swaps, break voting
- **Match Context Persistence**: Match ID, pause counts, tech budget, and OT state survive map changes via localinfo
- **Unique Match IDs**: Format `KTP-{timestamp}-{mapname}` for stats correlation
- **Captain System**: Team confirmation before ready-up phase
- **Ready-Up System**: Configurable player count per team (default: 6)
- **Auto-Config Execution**: Map-specific AND match-type-specific server settings
- **Player Roster Logging**: Full team rosters with SteamIDs and IPs logged to Discord
- **Match State Tracking**: Full visibility into match progress

### HLStatsX Integration (v0.7.0+)
- **Stats Separation**: Clean separation of warmup vs match stats
- **Match Context**: All stats logged with `(matchid "xxx")` property
- **Automatic Flushing**: Stats flushed at half/match end
- **KTP_MATCH_START/END**: Log markers for HLStatsX daemon parsing
- **Per-Match Tracking**: Same match ID persists across both halves

### Advanced Pause System (ReAPI Native)
- **ReAPI Pause Integration**: Direct pause control via `rh_set_server_pause()` - bypasses engine
- **Complete Time Freeze**: `host_frame` stops, `g_psv.time` frozen, physics halted
- **Works with `pausable 0`**: Block engine pause, only KTP system works
- **Unified Countdown**: 5-second pre-pause countdown, 5-second unpause countdown
- **Real-Time HUD Updates**: MM:SS timer during pause (KTP-ReHLDS + KTP-ReAPI)
- **Server Messages Work**: rcon say, join/leave events display during pause
- **Player Chat**: Server processes, client rendering WIP (KTP-ReHLDS feature)
- **Two Pause Types**: Tactical (1 per team) and Technical (5-min budget)
- **Pause Extensions**: Up to 2× 2-minute extensions (9 minutes max)
- **Auto-Warnings**: 30-second and 10-second countdown alerts
- **Two-Team Unpause**: Both teams must confirm to resume
- **Disconnect Protection**: Auto-pause with 10-second cancellable countdown

### Logging & Notifications
- **Triple Logging**: AMX log + KTP match log + Discord webhooks
- **Discord Integration**: Real-time notifications with emoji-rich formatting
- **Per-Match-Type Channels**: Route competitive, scrim, and 12-man matches to different Discord channels
- **Player Roster Logging**: Complete team lineups logged at match start (competitive only)
- **Structured Event Logs**: Key=value format for easy parsing
- **Player Tracking**: SteamID, IP, team recorded for all events

### Platform Compatibility
- **Optimal**: KTP-ReHLDS + KTP-ReAPI (full feature set)
- **Good**: Standard ReHLDS + Standard ReAPI (ReAPI pause works, limited HUD)
- **Basic**: Base AMX ModX (fallback mode, basic features)

---

## 🚀 Quick Start

### Requirements

**Required:**
- AMX Mod X 1.9+ / KTP AMX 2.0+ (1.10 / 2.0 recommended)
- [KTP-ReAPI](https://github.com/afraznein/KTP-ReAPI) (custom ReAPI fork with `RH_SV_UpdatePausedHUD` hook) - *optional but recommended*
- [KTP-ReHLDS](https://github.com/afraznein/KTP-ReHLDS) (custom ReHLDS fork - HUD updates during pause)

**Optional:**
- cURL extension (for Discord webhook notifications)
- ReAPI module (for enhanced pause HUD updates - plugin works without it)

### Installation

1. **Compile** the plugin:
   ```bash
   amxxpc KTPMatchHandler.sma -oKTPMatchHandler.amxx
   ```

2. **Install** to your server:
   - AMX Mod X: `addons/amxmodx/plugins/KTPMatchHandler.amxx`
   - KTP AMX: `addons/ktpamx/plugins/KTPMatchHandler.amxx`

3. **Add to** `plugins.ini`:
   ```
   KTPMatchHandler.amxx
   ```

4. **Configure** maps in `<configsdir>/ktp_maps.ini`:
   ```ini
   [dod_avalanche]
   config = ktp_avalanche.cfg
   name = Avalanche
   type = competitive
   ```

5. **Configure** Discord (optional) in `<configsdir>/discord.ini`:
   ```ini
   discord_relay_url=https://your-relay.run.app/reply
   discord_channel_id=1234567890123456789
   discord_auth_secret=your-secret-here
   ```

6. **Add to** `server.cfg`:
   ```
   // CRITICAL: Disable engine pause, use ReAPI pause only
   pausable 0

   // Pause System
   ktp_pause_duration "300"              // 5-minute base pause
   ktp_pause_extension "120"             // 2-minute extensions
   ktp_pause_max_extensions "2"          // Max 2 extensions
   ktp_prepause_seconds "5"              // Countdown before pause (live match)
   ktp_prematch_pause_seconds "5"        // Countdown before pause (pre-match)
   ktp_pause_countdown "5"               // Unpause countdown duration
   ktp_unpause_autorequest_secs "300"    // Auto-request unpause after 5 min

   // Match System
   ktp_ready_required "6"                // Players needed to ready
   ktp_tech_budget_seconds "300"         // 5-min tech budget per team
   ktp_unready_reminder_secs "30"        // Unready reminder interval
   ktp_unpause_reminder_secs "15"        // Unpause reminder interval

   // File Paths (auto-detected, only set if using custom paths)
   // ktp_maps_file "<configsdir>/ktp_maps.ini"
   // ktp_discord_ini "<configsdir>/discord.ini"
   ```

> **Note:** The `ktp_maps_file` and `ktp_discord_ini` CVARs are automatically set to use `get_configsdir()` at runtime. You only need to override them if using non-standard paths.

7. **Deploy** KTP-ReHLDS server binaries

8. **Restart** server

---

## 📖 Usage

### Starting a Match

```
Player types: .ktp <password>    (password required for competitive)
     ↓
Both teams type: .confirm (one captain per team)
     ↓
Players type: .ready (6 per team by default)
     ↓
Match goes LIVE! (5-second countdown)
     ↓
Map config auto-executes
```

**Alternative Match Types (no password required):**
- `.draft` - Draft match (always available, competitive config)
- `.12man` - 12-man match (casual play)
- `.scrim` - Scrim match (practice)

### Pause System

**To Pause:**
```
.pause          Tactical pause (5-sec countdown → PAUSED)
.tech           Technical pause (uses team budget)
```

**During Pause (shows real-time HUD):**
```
  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  .resume  |  .go  |  .ext
```

**To Unpause:**
```
Team 1: .resume    ← Initiates unpause request
Team 2: .go        ← Confirms (both teams must agree)
     ↓
5-second countdown → LIVE!
```

**Pause Features:**
- `.ext` - Add 2 minutes (max 2× = 4 minutes total)
- Auto-warnings at 30s and 10s remaining
- Auto-unpause when timer expires
- `.nodc` - Cancel disconnect auto-pause (10-sec window)

### All Commands

> **Note:** All commands work with both `/` and `.` prefixes (e.g., `.pause` or `/pause`). The `.` prefix is preferred as it's shorter.

#### Match Control
```
.ktp <pw>               Initiate competitive match (password required)
.draft                  Initiate draft match (no password, always available)
.12man                  Initiate 12-man match (no password)
.scrim                  Initiate scrim match (no password)
.confirm                Confirm team ready for start
.notconfirm             Remove team confirmation
.ready, .rdy            Mark yourself ready
.notready               Mark yourself not ready
.status                 View detailed match status
.prestatus              View pre-start confirmation status
.cancel                 Cancel match/pre-start
```

#### Pause Control
```
.pause, .tac            Tactical pause (5-sec countdown)
.tech, .technical       Technical pause (uses team budget)
.resume                 Request unpause (owner team)
.go                     Confirm unpause (other team)
.ext, .extend           Extend pause +2 minutes
.nodc, .stopdc          Cancel disconnect auto-pause
```

#### Team Names & Score
```
.setallies <name>       Set custom Allies team name
.setaxis <name>         Set custom Axis team name
.names                  Show current team names
.resetnames             Reset to default (Allies/Axis)
.score                  Show current match score
```

#### Admin Commands
```
ktp_pause               Server/RCON pause (same as .pause)
.cfg                    View current CVARs
```

#### Additional Aliases
All commands also work with the `/` prefix and some have additional forms:
- `pause`, `resume`, `confirm`, `cancel`, `status` (without prefix)
- `/tactical`, `.tactical` (same as `.pause`)
- `/technical` (same as `.tech`)

---

## ⏸️ Advanced Pause System

### ReAPI Pause Implementation (NEW in v0.4.0)

The plugin uses **ReAPI's `rh_set_server_pause()` native** instead of the engine's `pause` command:

**Benefits:**
- ✅ **No command conflicts** - No `Cmd_AddMallocCommand` errors
- ✅ **Works with `pausable 0`** - Completely blocks engine pause
- ✅ **Direct state control** - Sets `g_psv.paused` directly via ReHLDS
- ✅ **Complete time freeze** - `SV_Physics()` doesn't run, `g_psv.time` frozen
- ✅ **Full feature support** - Countdown, tracking, extensions, Discord all work

**How it works:**
```pawn
// ReAPI pause (recommended - KTP-ReHLDS + ReAPI)
rh_set_server_pause(true);   // Pause
rh_set_server_pause(false);  // Unpause

// Fallback (base HLDS/ReHLDS without ReAPI)
server_cmd("pause");         // Requires pausable 1
```

**What gets frozen when paused:**
- ✅ Physics (`SV_Physics()` - entities don't move)
- ✅ Time (`g_psv.time` - server time frozen)
- ✅ Player movement (blocked)
- ✅ Projectiles (stop mid-air)
- ✅ Entity think functions (don't execute)

**What still works (KTP-ReHLDS + KTP-ReAPI features):**
- ✅ HUD updates (via `RH_SV_UpdatePausedHUD` hook in KTP-ReAPI)
- ✅ Server messages (rcon say, join/leave events, plugin announcements)
- ✅ Network messages (pause info displayed)
- ✅ Plugin tasks (timer checks, warnings)
- ⚠️ Player chat (server processes, client rendering WIP)

### Pause Types

| Type | Limit | Duration | Extensions | Command | Budget |
|------|-------|----------|------------|---------|--------|
| **Tactical** | 1 per team/match | 5 min | 2× 2 min | `.pause` | No |
| **Technical** | Unlimited | Uses budget | Unlimited | `.tech` | 5 min/team/match |
| **Disconnect** | Auto | Uses budget | Unlimited | Auto | From tech |

> **Note (v0.7.1):** Tactical pause limits and tech budgets are now per-MATCH, not per-half. Teams cannot reset their pause allowance by going to 2nd half.

### Pause Flow

```
Player types .pause
         ↓
5-second countdown
  "Pausing in 5..."
  "Pausing in 4..."
  ...
         ↓
rh_set_server_pause(true)
         ↓
Game FREEZES
  - Physics stop
  - Time stops
  - HUD updates (ReAPI)
  - Chat works (KTP-ReHLDS)
         ↓
Real-time timer counts up
  - Elapsed: 0:05, 0:06, ...
  - Remaining: 4:55, 4:54, ...
         ↓
Warnings at 30s and 10s
         ↓
Auto-unpause OR .resume → .go
         ↓
5-second countdown
  "Unpausing in 5..."
         ↓
rh_set_server_pause(false)
         ↓
Game RESUMES (LIVE!)
```

---

## 🔧 Configuration

### Map Configuration (`ktp_maps.ini`)

**New section-based format (v0.4.0+):**

```ini
[dod_avalanche]
config = ktp_avalanche.cfg
name = Avalanche
type = competitive

[dod_flash]
config = ktp_flash.cfg
name = Flash
type = competitive

[dod_donner]
config = ktp_donner.cfg
name = Donner
type = competitive
```

**On match start**, the plugin automatically executes the map's config file.

### Discord Configuration (`discord.ini`)

**Relay-based integration:**

```ini
; Discord Relay Service URL (with /reply endpoint)
discord_relay_url=https://discord-relay-XXXXX.run.app/reply

; Discord Channel ID (18-digit snowflake)
discord_channel_id=1234567890123456789

; Authentication Secret (must match relay's RELAY_SHARED_SECRET)
discord_auth_secret=your-secret-here
```

**Discord notifications sent for:**
- ⏸️ Pause initiated (with countdown)
- ⏸️➕ Pause extended (+2 min)
- ▶️ Unpause countdown started
- ✅ Game LIVE (after unpause)
- ⚠️ Pause warnings (30s, 10s)
- ⏱️ Pause timeout (auto-unpause)
- 📴 Disconnect auto-pause
- ❌ Pause cancelled
- 🎮 Match start/end events

**Setup Guide:** See `DISCORD_GUIDE.md` for complete Discord relay setup.

### All CVARs

```
// ===== Pause System =====
ktp_pause_duration "300"              // Base pause duration (seconds) - Default: 5 min
ktp_pause_extension "120"             // Extension time per .ext - Default: 2 min
ktp_pause_max_extensions "2"          // Max extensions allowed - Default: 2
ktp_prepause_seconds "5"              // Countdown before pause (live match)
ktp_prematch_pause_seconds "5"        // Countdown before pause (pre-match)
ktp_pause_countdown "5"               // Unpause countdown duration
ktp_unpause_autorequest_secs "300"    // Auto-request unpause after N seconds
ktp_unpause_reminder_secs "15"        // Reminder interval for unpause confirmation

// ===== Match System =====
ktp_ready_required "6"                // Players needed to ready per team
ktp_tech_budget_seconds "300"         // Technical pause budget per team (5 min)
ktp_unready_reminder_secs "30"        // Reminder interval for unready players

// ===== File Paths (auto-detected, override only if needed) =====
ktp_maps_file "<configsdir>/ktp_maps.ini"    // Auto-detected at runtime
ktp_discord_ini "<configsdir>/discord.ini"   // Auto-detected at runtime
ktp_match_logfile "ktp_match.log"
ktp_cfg_basepath "dod/"               // Base path for map configs
```

---

## 📊 Logging

### 1. AMX Log
**Location:** `<logsdir>/L[MMDD].log` (e.g., `addons/ktpamx/logs/` or `addons/amxmodx/logs/`)

Standard Half-Life log format with timestamps:
```
L 11/17/2025 - 18:30:45: KTP: Game PAUSED by PlayerName (tactical_pause)
L 11/17/2025 - 18:33:15: KTP: Pause warning - 30 seconds remaining
L 11/17/2025 - 18:35:45: KTP: Game LIVE - Unpaused by PlayerName
```

### 2. KTP Match Log
**Location:** Configurable (default: `ktp_match.log`)

Structured event-based log with key=value pairs:
```
[2025-11-17 18:30:45] event=PAUSE_EXECUTED initiator='PlayerName' reason='tactical_pause' duration=300
[2025-11-17 18:32:15] event=PAUSE_EXTENDED player='PlayerName' extension=1/2 seconds=120
[2025-11-17 18:35:45] event=UNPAUSE_TOGGLE source=reapi reason='countdown'
[2025-11-17 18:40:00] event=MATCH_START map=dod_avalanche allies_ready=6 axis_ready=6
```

**Event types logged:**
- `PLUGIN_ENABLED` - Plugin initialization
- `MAPS_LOAD` - Map configuration loaded
- `DISCORD_CONFIG_LOAD` - Discord integration loaded
- `PAUSE_ATTEMPT` - Pause requested
- `PAUSE_TOGGLE` - Pause state changed (source=reapi or source=engine_cmd)
- `PAUSE_EXECUTED` - Pause started
- `PAUSE_EXTENDED` - Pause extended
- `UNPAUSE_ATTEMPT` - Unpause requested
- `UNPAUSE_TOGGLE` - Unpause executed
- `MAPCFG` - Map config executed
- `DISCORD_ERROR` - Discord notification failed

### 3. Discord Webhooks (Optional)
**Requirements:** cURL module + Discord relay service

Rich notifications with:
- 🎨 Emoji-based status indicators
- 📋 Structured message formatting
- ⏱️ Real-time event updates
- 📊 Player/team information

**See `DISCORD_GUIDE.md` for setup instructions.**

---

## 🏗️ Technical Architecture

### ReAPI Integration

**Pause Control:**
```pawn
// Direct pause state manipulation (bypasses engine command)
rh_set_server_pause(true);   // Freeze game
rh_set_server_pause(false);  // Resume game
bool:rh_is_server_paused();  // Check state
```

**HUD Updates During Pause:**
```pawn
// KTP-ReAPI custom hook (exposes KTP-ReHLDS pause HUD updates)
#if defined _reapi_included && defined RH_SV_UpdatePausedHUD
RegisterHookChain(RH_SV_UpdatePausedHUD, "OnPausedHUDUpdate", .post = false);
#endif

public OnPausedHUDUpdate() {
    // Called every frame while paused by KTP-ReHLDS
    // Update HUD for all players
    // Shows elapsed/remaining time, extensions, commands
    return HC_CONTINUE;
}
```

### Timing System

**Real-time tracking using `get_systime()`:**
```pawn
// Store pause start time (Unix timestamp)
g_pauseStartTime = get_systime();

// Calculate elapsed time (works even when host_frametime = 0)
new elapsed = get_systime() - g_pauseStartTime;

// Calculate remaining time
new remaining = g_pauseDurationSec - elapsed;
```

**Why this works:**
- `get_systime()` returns real-world time (not game time)
- Continues advancing even when `g_psv.time` is frozen
- Enables accurate timer during pause
- Powers auto-warnings and auto-unpause

### KTP-ReHLDS Modifications

**Custom ReHLDS changes for pause functionality:**

1. **Message Sending During Pause:**
   ```cpp
   // Force send_message = TRUE during pause
   if (g_psv.paused && cl->active && cl->spawned)
       cl->send_message = TRUE;
   ```

2. **HUD Update Hook:**
   ```cpp
   // New hook chain for pause HUD updates
   void SV_UpdatePausedHUD(void) {
       if (!g_psv.paused) return;
       g_RehldsHookchains.m_SV_UpdatePausedHUD.callChain(...);
   }
   ```

3. **Pause State Query:**
   ```cpp
   bool IsPaused(void) {
       return g_psv.paused != FALSE;
   }
   ```

### Performance Optimizations (v0.4.0)

**CVAR Caching:**
- Cache CVAR pointers on `plugin_init()`
- Use `get_pcvar_num()` instead of `get_cvar_num()`
- Reduces ~180 CVAR lookups per second during pause

**Safe Task Management:**
```pawn
// Check task exists before removing
if (task_exists(taskId)) {
    remove_task(taskId);
}
```

**Static Variables:**
```pawn
// Prevent duplicate warnings
static bool:warned_30sec = false;
static bool:warned_10sec = false;
```

---

## 🎯 Platform Support

### ✅ Optimal: KTP-ReHLDS + KTP-ReAPI

**All features work:**
- ✅ ReAPI pause natives (`rh_set_server_pause()`)
- ✅ Real-time HUD updates during pause (via `RH_SV_UpdatePausedHUD` hook)
- ✅ Server messages work (rcon say, join/leave events)
- ⚠️ Player chat (server processes, client rendering WIP)
- ✅ Automatic timer checks (no player interaction needed)
- ✅ Complete time freeze
- ✅ Discord notifications
- ✅ All pause features (countdown, extensions, tracking)

### ⬆️ Good: Standard ReHLDS + Standard ReAPI

**Most features work:**
- ✅ ReAPI pause natives work
- ✅ Complete time freeze
- ✅ Discord notifications
- ❌ HUD updates limited (no `RH_SV_UpdatePausedHUD` hook)
- ❌ Chat frozen during pause (server messages and player chat)
- ⚠️ Timer checks require player commands

### ⚠️ Basic: Base AMX ModX

**Fallback mode:**
- ⚠️ Uses `server_cmd("pause")` fallback
- ⚠️ Requires `pausable 1`
- ⚠️ HUD frozen during pause
- ⚠️ Chat frozen during pause
- ⚠️ Timer checks require player commands
- ✅ Discord notifications still work
- ✅ Pause tracking works

---

## 📝 Changelog

### v0.7.1 (2025-12-18) - Match Context Persistence & Per-Match Pause Limits

**Added:**
- ✅ **Match context persistence** - Match ID, pause counts, and tech budget survive map changes via localinfo
- ✅ **Per-match pause limits** - Tactical pauses and tech budget now persist across halves (teams can't reset by going to 2nd half)
- ✅ **2nd half announcements** - Shows match ID and pause usage status when continuing a match

**Fixed:**
- 🔧 **Match ID restoration** - Match ID now properly restored when 2nd half starts
- 🔧 **Pause count persistence** - Pause counts carry over from 1st to 2nd half
- 🔧 **Tech budget persistence** - Remaining tech budget carries over to 2nd half

**Technical:**
- Uses localinfo keys: `_ktp_match_id`, `_ktp_half_pending`, `_ktp_pause_allies/axis`, `_ktp_tech_allies/axis`
- Context saved in `handle_map_change()`, restored in `plugin_cfg()`

### v0.7.0 (2025-12-17) - HLStatsX Stats Integration

**Added:**
- ✅ **HLStatsX integration** - Clean separation of warmup vs match stats
- ✅ **DODX natives** - `dodx_flush_all_stats()`, `dodx_reset_all_stats()`, `dodx_set_match_id()`
- ✅ **KTP_MATCH_START** - Log marker for HLStatsX daemon parsing
- ✅ **KTP_MATCH_END** - Log marker for HLStatsX daemon parsing
- ✅ **Match ID in stats** - `(matchid "xxx")` property in weaponstats log lines

**Improved:**
- 🎯 **Automatic stats flushing** - Stats flushed at half/match end with appropriate matchid
- 🎯 **Warmup separation** - Warmup stats logged without matchid before match starts

**Requires:**
- DODX module with HLStatsX natives (KTPAMXX)
- HLStatsX daemon with KTP event handlers (KTPHLStatsX)

### v0.6.0 (2025-12-16) - Match ID System & Ready Enhancements

**Added:**
- ✅ **Unique match ID system** - Format: `KTP-{timestamp}-{mapname}`
- ✅ **Match ID persistence** - Same ID for both halves (MySQL/stats correlation)
- ✅ **Match ID in Discord** - Displayed in code block notifications
- ✅ **`/whoneedsready` command** - Shows unready players with Steam IDs
- ✅ **`/unready` alias** - Alias for `/whoneedsready`
- ✅ **Steam IDs in announcements** - READY/NOTREADY messages include Steam IDs
- ✅ **Periodic unready reminders** - Every 30 seconds during ready phase

**Improved:**
- 🎯 **Half tracking** - Logs match_id in HALF_START and HALF_END events
- 🎯 **Streamlined flow** - Match goes LIVE immediately when all ready (no pause)

**Removed:**
- ❌ Automatic pause during ready phase
- ❌ Unpause countdown at match start

### v0.5.2 (2025-12-03) - KTP AMX Compatibility

**Fixed:**
- 🔧 **Dynamic config paths** - Use `get_configsdir()` for automatic path resolution
- 🔧 **Removed hardcoded paths** - No more `addons/amxmodx` assumptions
- 🔧 **ReAPI message** - Changed from WARNING to informational note (ReAPI is optional)

**Improved:**
- 🎯 **Cross-platform support** - Works with both AMX Mod X and KTP AMX without modification
- 🎯 **Better user feedback** - Clearer messaging when optional features are unavailable

### v0.5.1 (2025-12-02) - Critical Bug Fixes

**Fixed:**
- 🔧 **[CRITICAL]** cURL header memory leak causing accumulation on every Discord message
- 🔧 **[CRITICAL]** Tech pause budget integer underflow from system clock adjustments
- 🔧 **[HIGH]** Buffer overflow in player roster concatenation with 12+ players per team
- 🔧 **[HIGH]** Inconsistent team ID validation before g_techBudget array access
- 🔧 **[MEDIUM]** Various state cleanup and validation improvements

### v0.5.0 (2025-11-24) - Major Feature Update

**Added:**
- ✅ **Match type system** - COMPETITIVE, SCRIM, 12MAN modes with distinct behaviors
- ✅ **Per-match-type configs** - Auto-load `mapname_12man.cfg` or `mapname_scrim.cfg` with fallback
- ✅ **Per-match-type Discord channels** - Route to different channels based on match type
- ✅ **Half tracking system** - Automatic 1st/2nd half detection and logging
- ✅ **Automatic map rotation** - Sets next map to current map for 2nd half
- ✅ **Half number in messages** - Discord shows "(1st half)" or "(2nd half)"
- ✅ **Player roster logging** - Full team lineups logged to Discord at match start (competitive only)
- ✅ **Dot command aliases** - All commands now work with `.` prefix (`.pause`, `.ready`, etc.)
- ✅ **`/draft` command** - Alias for `/start` and `/ktp`

**Changed:**
- 🔄 **`/startmatch` → `/ktp`** - Main match start command renamed (kept `/start`)
- 🔄 **`/start12man` → `/12man`** - Shorter command name with `.12man` alias
- 🔄 **`/startscrim` → `/scrim`** - Shorter command name with `.scrim` alias
- 🔄 **Removed `/ready` aliases** - Removed 'ready' and 'ktp' word aliases (conflict resolution)

**Improved:**
- 🎯 **Discord routing** - Match-type-specific channels with graceful fallback
- 🎯 **Config selection** - Tries match-type-specific configs first, falls back to standard
- 🎯 **Player accountability** - Full roster with SteamIDs and IPs logged for competitive matches

### v0.4.6 (2025-11-22) - Match Start Flow Fix

**Fixed:**
- 🐛 Match start entering uncontrollable tactical pause instead of LIVE countdown
- 🐛 Team confirmation triggering pre-pause countdown (wrong flow)
- 🐛 Countdown task not running during pause (tasks don't execute when paused)

**Changed:**
- 🔄 Countdown handling moved to `OnPausedHUDUpdate()` hook (runs during pause)
- 🔄 Confirmation now directly executes pause (no countdown)
- 🔄 Ready completion stays paused, starts countdown for smooth transition

### v0.4.5 (2025-11-22) - Critical Bug Fixes and Scrim Mode

**Added:**
- ✅ `/startscrim` and `/start12man` commands (skip Discord notifications)
- ✅ `g_disableDiscord` flag to control Discord webhook calls

**Fixed:**
- 🐛 Missing task cleanup before pre-pause countdown (race condition)
- 🐛 Missing pre-pause task cleanup in `plugin_end()` (memory leak)
- 🐛 Tech budgets not reset on match cancel (state carry-over)
- 🐛 Pre-pause state not cleared on match cancel
- 🐛 Double timestamp assignment race condition in pause flow
- 🐛 Disconnect state not cleared after unpause
- 🐛 Missing countdown task cleanup before `set_task()` (duplicate tasks)
- 🐛 Multiple simultaneous disconnects overwriting first disconnect info

**Optimized:**
- 📈 Removed duplicate config loading in `plugin_init()` (~25ms faster startup)

### v0.4.4 (2025-11-21) - Performance Optimizations

**Optimized:**
- 📈 Eliminated 8 redundant `get_mapname()` calls (use cached `g_currentMap`)
- 📈 Cached `g_pauseDurationSec` and `g_preMatchPauseSeconds` CVARs
- 📈 Index-based `formatex` in `cmd_status()` (30-40% faster string building)
- 📈 Switch statement in `get_ready_counts()` for cleaner team ID handling
- 📈 15-20% reduction in string operations during logging
- 📈 5-10% faster pause initialization with cached CVARs

### v0.4.3 (2025-11-20) - Discord Notification Filtering

**Added:**
- ✅ `send_discord_with_hostname()` helper function
- ✅ Hostname prefix to all Discord notifications

**Changed:**
- 🔄 Disabled non-essential Discord notifications
- 🔄 Only 3 essential notifications kept: Match start, Player pause, Disconnect auto-pause

### v0.4.2 (2025-11-20) - cURL Discord Integration Fix

**Fixed:**
- 🐛 Discord notifications not working (curl.inc was disabled)
- 🐛 Compilation errors with backslash character constants
- 🐛 JSON string escaping in formatex
- 🐛 Invalid cURL header constant

**Requires:**
- `curl_amxx.dll` module enabled in `modules.ini`
- `discord.ini` with relay URL, channel ID, and auth secret

### v0.4.1 (2025-11-17) - Pausable Cvar Removal

**Removed:**
- ❌ All pausable cvar manipulation code (no longer needed with ReAPI)
- ❌ `ktp_force_pausable` cvar
- ❌ `g_pcvarPausable` and `g_cvarForcePausable` variables

**Improved:**
- 🎯 Cleaner code (~33 lines removed)
- 🎯 Simpler client messages ("Game paused" vs "Pause enforced")

### v0.4.0 (2025-11-17) - ReAPI Pause + Major Overhaul

**Added:**
- ✅ **ReAPI pause natives** - `rh_set_server_pause()` for direct control
- ✅ **Works with `pausable 0`** - Block engine pause, use KTP system only
- ✅ **Unified countdown system** - ALL pause entry points use countdown
- ✅ **Pre-pause countdown** - 5-second warning before pause
- ✅ **Pause extensions** - `.ext` adds 2 minutes (max 2×)
- ✅ **Real-time HUD updates** - MM:SS timer via ReAPI hook
- ✅ **Auto-warnings** - 30-second and 10-second alerts
- ✅ **Auto-unpause** - When timer expires
- ✅ **Disconnect auto-pause** - 10-second cancellable countdown
- ✅ **Discord relay integration** - Relay service for webhooks
- ✅ **New map INI format** - Section-based configuration
- ✅ **Comprehensive logging** - AMX + KTP log + Discord

**Changed:**
- 🔄 **Pause implementation** - ReAPI natives replace `server_cmd("pause")`
- 🔄 **Main method** - Now `async Task Main` for ReAPI support
- 🔄 **Command registration** - Removed `pause` command (no conflicts)
- 🔄 **Platform degradation** - Graceful fallback for non-ReAPI servers

**Fixed:**
- 🐛 **`Cmd_AddMallocCommand` error** - No more pause command conflicts
- 🐛 **HUD during pause** - Real-time updates using `get_systime()`
- 🐛 **Server messages during pause** - rcon say and events work with KTP-ReHLDS
- 🐛 **Ready system bugs** - Undefined variable warnings
- 🐛 **Unsafe task removal** - All `remove_task()` calls now safe

**Performance:**
- 📈 **CVAR caching** - Reduced ~180 lookups/sec during pause
- 📈 **Static variables** - Prevent duplicate warnings
- 📈 **Optimized HUD** - Only updates when needed

**Documentation:**
- 📚 `DISCORD_GUIDE.md` - Complete KTP stack guide (ReHLDS + ReAPI + plugins)
- 📚 `REAPI_PAUSE_IMPLEMENTATION.md` - ReAPI pause technical guide
- 📚 `SERVER_TROUBLESHOOTING.md` - Debugging guide
- 📚 `PAUSE_SYSTEM_REDESIGN.md` - v0.4.0 pause system overview

### v0.3.3 - Previous Stable

- Two-team unpause confirmation
- Per-team tactical pause limits
- Technical pause budget system
- Disconnect detection
- Pre-start confirmation
- Discord webhook integration (direct)

**[Full Changelog](CHANGELOG.md)**

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly on KTP-ReHLDS + ReAPI
5. Commit changes (`git commit -m 'Add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open a pull request

**Areas for contribution:**
- 🎯 Additional pause features (e.g., coach system)
- 📊 Enhanced statistics tracking
- 🎨 Improved Discord embed formatting
- 🐛 Bug fixes and optimizations
- 📖 Documentation improvements
- 🧪 Unit tests and benchmarks

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🔗 Links

**KTP Projects:**
- **GitHub Repository**: [KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)
- **GitHub Issues**: [Report Bugs](https://github.com/afraznein/KTPMatchHandler/issues)
- **KTP-ReHLDS**: [Custom ReHLDS Fork](https://github.com/afraznein/KTP-ReHLDS)
- **KTP-ReAPI**: [Custom ReAPI Fork](https://github.com/afraznein/KTP-ReAPI)

**Upstream Projects:**
- **ReAPI**: [Original ReAPI](https://github.com/s1lentq/reapi)
- **ReHLDS**: [Original ReHLDS](https://github.com/dreamstalker/rehlds)
- **AMX Mod X**: [Official Website](https://www.amxmodx.org/)

---

## 📚 Documentation

- **[REAPI_PAUSE_IMPLEMENTATION.md](REAPI_PAUSE_IMPLEMENTATION.md)** - Complete guide to ReAPI pause system
- **[DISCORD_GUIDE.md](DISCORD_GUIDE.md)** - Discord relay setup and configuration
- **[SERVER_TROUBLESHOOTING.md](SERVER_TROUBLESHOOTING.md)** - Server setup and debugging
- **[PAUSE_SYSTEM_REDESIGN.md](PAUSE_SYSTEM_REDESIGN.md)** - v0.4.0 pause system architecture
- **[FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)** - Complete feature list
- **[CHANGELOG.md](CHANGELOG.md)** - Full version history

---

## 👤 Author

**Nein_**
- GitHub: [@afraznein](https://github.com/afraznein)
- Project: KTP Competitive Infrastructure

For support and questions, please open an issue on GitHub.

---

## 🙏 Acknowledgments

- **s1lentq** - Original ReAPI and ReGameDLL development
- **dreamstalker** - Original ReHLDS project
- **ReHLDS Team** - Engine enhancements and architecture
- **ReAPI Team** - Module framework and hooks system
- **AMX Mod X Team** - Scripting platform
- **KTP Community** - Testing, feedback, and competitive insights
- **Discord Relay Project** - Webhook relay service

---

## 🔒 Security Notes

**Important:**
- Never commit `discord.ini` to git (contains auth secrets)
- Keep `RELAY_SHARED_SECRET` private
- Use `.gitignore` to protect sensitive configs
- Restrict server file permissions appropriately

---

## 🚦 Status

- **Current Version**: v0.9.16
- **Status**: Stable (Score persistence and Discord embeds verified on VPS)
- **Tested On**: KTP-ReHLDS + KTP-ReAPI + AMX ModX 1.10 / KTP AMX 2.5
- **Last Updated**: December 21, 2025
- **Platforms**: Day of Defeat 1.3

---

## ⚡ Quick Reference Card

```
╔════════════════════════════════════════════════════════════╗
║             KTP MATCH HANDLER v0.9.16                      ║
║              Quick Command Reference                       ║
╠════════════════════════════════════════════════════════════╣
║  MATCH CONTROL                                             ║
║  .ktp <pw>      Start competitive match (password req)     ║
║  .draft         Start draft match (no password)            ║
║  .12man         Start 12-man match (no password)           ║
║  .scrim         Start scrim match (no password)            ║
║  .confirm       Confirm team ready                         ║
║  .ready         Mark yourself ready                        ║
║  .status        View match status                          ║
║  .score         View current match score                   ║
║                                                            ║
║  PAUSE CONTROL                                             ║
║  .pause         Tactical pause (5-sec countdown)           ║
║  .tech          Technical pause                            ║
║  .resume        Request unpause (your team)                ║
║  .go            Confirm unpause (other team)               ║
║  .ext           Add 2 minutes (max 2×)                     ║
║  .nodc          Cancel disconnect auto-pause               ║
║                                                            ║
║  TEAM NAMES                                                ║
║  .setallies     Set Allies team name                       ║
║  .setaxis       Set Axis team name                         ║
║  .names         Show current team names                    ║
║                                                            ║
║  MATCH TYPES                                               ║
║  COMPETITIVE    .ktp (password + season required)          ║
║  DRAFT          .draft (always allowed, no Discord)        ║
║  12MAN          .12man (always allowed, no Discord)        ║
║  SCRIM          .scrim (always allowed, no Discord)        ║
╚════════════════════════════════════════════════════════════╝
```

---

**KTP Match Handler v0.9.16** - Making competitive Day of Defeat matches better, one pause at a time. ⏸️
