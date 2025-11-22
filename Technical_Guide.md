# KTP Competitive Infrastructure - Technical Guide

<div align="center">

**The Ultimate Day of Defeat Competitive Server Stack**

[![License](https://img.shields.io/badge/license-GPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![Engine](https://img.shields.io/badge/engine-GoldSrc%20%7C%20Half--Life-orange.svg)]()
[![Game](https://img.shields.io/badge/game-Day%20of%20Defeat-green.svg)]()

*A comprehensive ecosystem of custom engine modifications, ReAPI extensions, and match management plugins designed for competitive 6v6 Day of Defeat gameplay*

[Features](#-the-complete-stack) • [Installation](#-complete-installation-guide) • [Documentation](#-component-documentation) • [Repositories](#-github-repositories)

</div>

---

## 📦 The Complete Stack

<details open>
<summary><b>Four-Layer Architecture</b></summary>

```
┌─────────────────────────────────────────────────┐
│  Layer 4: KTPMatchHandler (AMX Plugin)          │
│  Match workflow, pause system, Discord          │
└─────────────────────────────────────────────────┘
                     ↓ Uses
┌─────────────────────────────────────────────────┐
│  Layer 3: Anti-Cheat Plugins (AMX Plugins)      │
│  • KTPCvarChecker v5.4 - Instant cvar checks    │
│  • KTPFileChecker - File consistency checking   │
└─────────────────────────────────────────────────┘
                     ↓ Uses
┌─────────────────────────────────────────────────┐
│  Layer 2: KTP-ReAPI (AMX Module)                │
│  Custom hooks, ReHLDS bridge                    │
└─────────────────────────────────────────────────┘
                     ↓ Uses
┌─────────────────────────────────────────────────┐
│  Layer 1: KTP-ReHLDS (Custom Engine)            │
│  Pause HUD updates, chat during pause           │
└─────────────────────────────────────────────────┘

                Supporting Infrastructure:
┌─────────────────────────────────────────────────┐
│  Discord Relay (Cloud Run Service)              │
│  Real-time match notifications via webhook      │
└─────────────────────────────────────────────────┘
```

</details>

---

## 🔧 Component Documentation

### Layer 1: KTP-ReHLDS (Engine)

<details>
<summary><b>🎯 Real-Time HUD Updates During Pause</b></summary>

**What it is:** Custom fork of ReHLDS (Half-Life Dedicated Server) with advanced pause functionality

**GitHub:** [afraznein/KTP-ReHLDS](https://github.com/afraznein/KTP-ReHLDS)

#### The Problem
- **Standard HLDS/ReHLDS:** HUD freezes when paused (nothing updates)
- **KTP-ReHLDS:** Updates HUD every frame during pause

#### The Solution
```cpp
// New hook chain: RH_SV_UpdatePausedHUD
// Called every frame when g_psv.paused == true
void SV_UpdatePausedHUD(void) {
    if (!g_psv.paused) return;

    // Call plugin hooks to update HUD
    g_RehldsHookchains.m_SV_UpdatePausedHUD.callChain(...);
}
```

#### Features Enabled
| Feature | Standard ReHLDS | KTP-ReHLDS |
|---------|----------------|------------|
| Live countdown timer | ❌ Frozen 00:00 | ✅ MM:SS format |
| Server messages | ❌ Frozen | ✅ Works |
| Plugin announcements | ❌ Frozen | ✅ Works |
| Join/leave events | ❌ Frozen | ✅ Works |
| Commands | ❌ Blocked | ✅ Full support |
| Auto-warnings | ❌ Manual | ✅ Automatic |

</details>

<details>
<summary><b>💬 Chat During Pause (Partial Functionality)</b></summary>

#### What Works
- ✅ **First chat message** per pause - Displays to all clients
- ✅ **Server-side messages** (`rcon say`, admin commands) - Work normally
- ✅ **Server events** (player join/leave notifications)
- ✅ **Plugin messages** (using direct buffer writes)
- ✅ **Commands** (`/cancel`, `/pause`, `/resume`, etc.)

#### Known Limitation
- ⚠️ **Subsequent chat messages** - Blocked by DoD game DLL flood protection
- Only first player chat message per pause displays
- 2nd, 3rd, 4th... messages are blocked
- **Workaround:** Use `rcon say` for additional messages

#### Why the Limitation Exists
The DoD game DLL has built-in flood protection using frozen game time. After the first message, all subsequent messages appear "instant" (0 time elapsed), triggering the DLL's internal flood detection.

**Fix requires:** DoD game DLL source code access

#### Technical Implementation

<details>
<summary>Frame-wide Temporary Unpause System</summary>

```cpp
// Frame-wide temporary unpause system
int wasPaused = g_psv.paused;
g_ktp_temporary_unpause = 0;

if (wasPaused) {
    g_psv.paused = 0;                    // Unpause for entire frame
    g_ktp_temporary_unpause = 1;         // Mark as temporary
}

// Process all commands, chat, and network messages
SV_Physics();                            // Skipped if shouldSimulate=false
SV_CheckTimeouts();
SV_SendClientMessages();                 // Messages sent here

// Restore pause AFTER message sending completes
if (wasPaused && g_ktp_temporary_unpause) {
    g_psv.paused = wasPaused;            // Restore pause state
}
```

</details>

<details>
<summary>Rate Limiter Bypass</summary>

```cpp
// Skip ReHLDS rate limiter during temporary unpause
if (!g_ktp_temporary_unpause) {
    g_StringCommandsRateLimiter.StringCommandIssued(pSenderClient - g_psvs.clients);
}
// Commands/chat now processed during pause
```

</details>

**Current Status:** First message works, commands work, RCON works. Subsequent messages require DoD DLL investigation.

</details>

<details>
<summary><b>❌ What's Frozen During Pause</b></summary>

- Physics (players/entities don't move)
- Game time (`g_psv.time` doesn't advance)
- Entity think functions
- Projectiles (grenades stop mid-air)

</details>

---

### Layer 2: KTP-ReAPI (Module)

<details>
<summary><b>🎯 Custom Hook: RH_SV_UpdatePausedHUD</b></summary>

**What it is:** Custom fork of ReAPI with KTP-ReHLDS hook support

**GitHub:** [afraznein/KTP-ReAPI](https://github.com/afraznein/KTP-ReAPI)

#### The Bridge Between Engine and Plugins

KTP-ReAPI adds the critical `RH_SV_UpdatePausedHUD` hook that connects KTP-ReHLDS's pause system to AMX plugins.

```c
// In your plugin (e.g., KTPMatchHandler)
#if defined RH_SV_UpdatePausedHUD
    RegisterHookChain(RH_SV_UpdatePausedHUD, "OnPausedHUDUpdate", .post = false);
#endif

public OnPausedHUDUpdate() {
    // Called EVERY FRAME while paused by KTP-ReHLDS
    // Update HUD for all players with live countdown

    for (new id = 1; id <= MaxClients; id++) {
        if (!is_user_connected(id)) continue;

        // Calculate elapsed/remaining time
        new elapsed = get_systime() - g_pauseStartTime;
        new remaining = g_pauseDurationSec - elapsed;

        // Display real-time HUD
        set_hudmessage(255, 255, 255, -1.0, 0.3, 0, 0.0, 0.1, 0.0, 0.0);
        show_hudmessage(id, "== GAME PAUSED ==^n^nElapsed: %d:%02d  |  Remaining: %d:%02d",
            elapsed / 60, elapsed % 60, remaining / 60, remaining % 60);
    }

    return HC_CONTINUE;
}
```

#### Why This is Critical
- ❌ **Standard ReHLDS:** No way for plugins to update HUD during pause
- ✅ **KTP-ReAPI:** Exposes the `RH_SV_UpdatePausedHUD` hook that KTP-ReHLDS calls every frame
- 🎯 **Result:** Real-time MM:SS countdown timer visible to players during pause

</details>

<details>
<summary><b>🔗 Standard ReAPI Features (Inherited)</b></summary>

#### Pause Control Natives
```c
// Direct pause state manipulation (bypasses engine command)
rh_set_server_pause(true);    // Freeze game
rh_set_server_pause(false);   // Resume game
bool:rh_is_server_paused();   // Check pause state
```

#### Why This Matters
- ❌ **Standard method:** `server_cmd("pause")` - conflicts with engine, requires `pausable 1`
- ✅ **ReAPI method:** Direct manipulation - no conflicts, works with `pausable 0`

#### Real-Time Cvar Detection Hook
```c
RegisterHookChain(RH_SV_CheckUserInfo, "OnUserInfoChange", false)

public OnUserInfoChange(id) {
    // Instantly detect when player changes client cvar
    // No polling delay (15-90 seconds on base AMX)
    return HC_CONTINUE;
}
```

</details>

<details>
<summary><b>📊 Feature Comparison</b></summary>

| Feature               | Standard ReAPI              | KTP-ReAPI                  |
|-----------------------|-----------------------------|----------------------------|
| Pause control natives | ✅ `rh_set_server_pause()`   | ✅ Same                     |
| Cvar detection hook   | ✅ `RH_SV_CheckUserInfo`     | ✅ Same                     |
| Pause HUD hook        | ❌ Not available             | ✅ `RH_SV_UpdatePausedHUD` |
| ReGameDLL hooks       | ✅ All standard hooks        | ✅ Same                     |
| Backward compatible   | N/A                         | ✅ Yes (works with std ReHLDS) |

</details>

---

### Layer 3: Anti-Cheat Plugins

<details>
<summary><b>⚡ KTPCvarChecker v5.4 - Client Cvar Enforcement</b></summary>

**GitHub:** [afraznein/KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)

**Version:** v5.4 (November 2025) - Major performance optimizations

#### 📋 57 Monitored Cvars

| Category | Examples | Purpose |
|----------|----------|---------|
| Graphics | `gl_*`, `r_*` | Prevent wallhacks, brightness exploits |
| Audio | `s_*`, `ambient_*` | Prevent sound advantages |
| Mouse | `m_pitch`, `m_side` | Prevent movement exploits |
| Network | `cl_updaterate`, `rate` | Fair play enforcement |
| Ranges | `lightgamma` (1.7-3.0), `ex_interp` (0-0.04), `fps_max` (60-500) | Validated ranges |

#### ⚡ Real-Time Detection (KTP-ReHLDS + ReAPI)

```c
RegisterHookChain(RH_SV_CheckUserInfo, "OnUserInfoChange", false)

public OnUserInfoChange(id) {
    // Player changed a userinfo cvar (cl_, rate, etc.)
    // Check value immediately, no waiting

    query_client_cvar(id, "cl_updaterate", "CvarCallback")
}
```

#### Performance Improvements (v5.4)
- ⚡ **Pre-converted float arrays** - Eliminates 57+ `floatstr()` conversions per check
- 🔧 **Optimized function calls** - ~60% fewer calls per check
- 🚀 **Eliminated linear search** - Replaced O(n) with O(1) direct array access
- 📊 **~1600 fewer string comparisons** per full check on non-ReAPI servers
- 🛡️ **Pause-compatible rate limiting** using system time

#### Platform Compatibility

| Feature | Base AMX | ReHLDS | KTP-ReHLDS + ReAPI |
|---------|----------|--------|---------------------|
| Detection speed | ⏱️ 15-90s delay | ⏱️ Same as base | ⚡ Instant (< 0.1s) |
| Initial check speed | ⏱️ 8.55 seconds | ⏱️ 8.55 seconds | ⚡ < 0.1 seconds (85x faster) |
| Cvar enforcement | ✅ 57 cvars | ✅ 57 cvars | ✅ 57 cvars |
| Auto-correction | ✅ | ✅ | ✅ |
| Performance (v5.4) | ✅ Optimized | ✅ Optimized | ✅ Fully optimized |

</details>

<details>
<summary><b>🛡️ KTPFileChecker - File Consistency</b></summary>

**GitHub:** [afraznein/KTPFileChecker](https://github.com/afraznein/KTPFileChecker) (Private)

#### 📁 File Consistency Checking
- Forces clients to use exact server-side files
- Prevents custom player models (wallhacks, visibility advantages)
- Prevents custom sounds (footstep/reload audio cheats)
- Validates weapon models, sprites, and HUD elements

#### 🔍 Two Model Checking Modes

| Mode | CVAR | Description |
|------|------|-------------|
| Exact Match | `fc_exactweapons 1` | File must be byte-for-byte identical |
| Same Bounds | `fc_exactweapons 0` | Model dimensions match (allows reskins) |

#### 🎯 Monitored Files
- **Player Models** (8 files)
- **Sounds** (56+ files - footsteps, headshots, weapons, ambient)
- **Weapon Models** (36+ files - first/third person, world models)
- **Sprites** (effects)

#### Detection Flow
```
Player connects → Plugin validates files in filescheck.ini →
Client file CRC compared to server → Mismatch detected →
Player kicked immediately → Violation logged →
Server announcement with player details
```

</details>

---

### Layer 4: KTPMatchHandler (Match Management)

<details>
<summary><b>🏆 Match Workflow</b></summary>

**GitHub:** [afraznein/KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)

```
1. PRE-START
   /start → Both teams /confirm

2. PENDING (Ready-Up)
   Players type /ready (6 per team)

3. LIVE COUNTDOWN
   "Match starting in 5..."

4. MATCH LIVE
   Map config auto-executes
   Pause system active
   Full logging enabled
```

</details>

<details>
<summary><b>⏸️ Advanced Pause System</b></summary>

#### Two Pause Types

| Type | Limit | Duration | Extensions | Budget |
|------|-------|----------|------------|--------|
| Tactical `/pause` | 1 per team/half | 5 minutes | 2× 2 min (9 min max) | No |
| Technical `/tech` | Unlimited | Varies | Unlimited | 5 min/team total |

#### Disconnect Auto-Pause
- Triggers when player disconnects during live match
- 10-second countdown (can be cancelled with `/cancelpause`)
- Uses team's technical pause budget
- Team-only cancel permission

#### Pause Flow Diagram

```
Player types: /pause
        ↓
5-second countdown ("Pausing in 5...")
        ↓
rh_set_server_pause(true)  ← ReAPI native
        ↓
GAME FREEZES (Physics stop, Time stops, Players can't move)
        ↓
SERVER MESSAGES WORK (KTP-ReHLDS feature)
  - rcon say displays normally
  - Join/leave events show
  - Plugin announcements work
        ↓
HUD UPDATES (KTP-ReHLDS feature)
  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  /resume  |  /confirmunpause  |  /extend
        ↓
Auto-warnings at 30s and 10s
        ↓
Team 1: /resume
Team 2: /confirmunpause
        ↓
5-second countdown ("Unpausing in 5...")
        ↓
rh_set_server_pause(false)  ← ReAPI native
        ↓
GAME RESUMES (LIVE!)
```

</details>

<details>
<summary><b>⏱️ Real-Time Timer System</b></summary>

Uses `get_systime()` for accuracy:

```c
// Store pause start time (Unix timestamp)
g_pauseStartTime = get_systime();

// Calculate elapsed time (works even when host_frametime = 0)
new elapsed = get_systime() - g_pauseStartTime;

// Calculate remaining time
new remaining = g_pauseDurationSec - elapsed;

// Display: "Elapsed: 2:34  |  Remaining: 2:26"
```

#### Why This Works
- `get_systime()` returns real-world time (not game time)
- Continues advancing even when `g_psv.time` is frozen
- Enables accurate countdown during pause
- Powers auto-warnings and auto-unpause

</details>

<details>
<summary><b>📝 Logging & Notifications</b></summary>

#### 1. AMX Log (Standard Half-Life logs)
```
L 11/17/2025 - 18:30:45: KTP: Game PAUSED by PlayerName (tactical_pause)
L 11/17/2025 - 18:33:15: KTP: Pause warning - 30 seconds remaining
L 11/17/2025 - 18:35:45: KTP: Game LIVE - Unpaused by PlayerName
```

#### 2. KTP Match Log (Structured event logging)
```
[2025-11-17 18:30:45] event=PAUSE_EXECUTED initiator='PlayerName' reason='tactical_pause' duration=300
[2025-11-17 18:32:15] event=PAUSE_EXTENDED player='PlayerName' extension=1/2 seconds=120
[2025-11-17 18:35:45] event=UNPAUSE_TOGGLE source=reapi reason='countdown'
```

#### 3. Discord Integration
See [Discord Relay](#supporting-infrastructure-discord-relay) section for complete details

</details>

---

### Supporting Infrastructure: Discord Relay

<details>
<summary><b>🔔 Real-Time Match Notifications</b></summary>

**GitHub:** [afraznein/discord-relay](https://github.com/afraznein/discord-relay)

Google Cloud Run service that bridges AMX plugins to Discord via webhooks

#### Architecture
```
KTPMatchHandler (AMX Plugin)
        ↓
HTTP POST: match event JSON
        ↓
Discord Relay (Cloud Run)
  - Validate auth secret
  - Format Discord embed
  - Rate limit protection
        ↓
Discord Webhook API
        ↓
Discord Channel (live notifications)
```

#### Active Notifications (v0.4.3 - Filtered)
- 🎮 **Match started** - Includes hostname, map, captains, teams
- ⏸️ **Player-initiated tactical pause** - Includes hostname, player, team, pause counts
- 📴 **Disconnect auto-pause** - Includes hostname, player, team, tech budget

**Rationale:** Focus on critical match events while reducing Discord channel noise. All notifications include server hostname for multi-server identification.

</details>

<details>
<summary><b>🔐 Security & Authentication</b></summary>

```javascript
// Relay validates secret before forwarding
app.post('/relay', async (req, res) => {
    const authHeader = req.headers['authorization'];
    const expectedAuth = `Bearer ${process.env.DISCORD_AUTH_SECRET}`;

    if (authHeader !== expectedAuth) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    // Forward to Discord
    await fetch(DISCORD_WEBHOOK_URL, {
        method: 'POST',
        body: JSON.stringify(req.body)
    });
});
```

#### Why This Matters
- ❌ **Direct approach:** Game server → Discord API (exposes webhook URL, rate limit risk)
- ✅ **Relay approach:** Game server → Cloud Run → Discord (auth required, rate limiting, URL hidden)

</details>

---

## 🚀 Complete Installation Guide

<details>
<summary><b>Step 1: Install AMX Mod X</b></summary>

```bash
# Download AMX ModX 1.10
# Install to server (addons/amxmodx/)
```

</details>

<details>
<summary><b>Step 2: Install KTP-ReAPI Module</b></summary>

```bash
# Download KTP-ReAPI module (custom fork with KTP hooks)
# GitHub: https://github.com/afraznein/KTP-ReAPI

# Copy to modules directory:
#   Windows: addons/amxmodx/modules/reapi_amxx.dll
#   Linux:   addons/amxmodx/modules/reapi_amxx_i386.so

# Enable in modules.ini:
echo "reapi_amxx.dll" >> addons/amxmodx/configs/modules.ini    # Windows
echo "reapi_amxx_i386.so" >> addons/amxmodx/configs/modules.ini # Linux
```

</details>

<details>
<summary><b>Step 3: Deploy KTP-ReHLDS Binaries</b></summary>

```bash
# Download KTP-ReHLDS builds
# Replace engine binaries:
#   - swds.dll (Windows) or engine_i486.so (Linux)
#   - hw.dll/hw.so
#   - filesystem_stdio.dll/.so
```

</details>

<details>
<summary><b>Step 4: Install Plugins</b></summary>

#### Compile
```bash
# Navigate to scripting directory
cd addons/amxmodx/scripting

# Compile plugins
./amxxpc KTPMatchHandler.sma -oKTPMatchHandler.amxx
./amxxpc ktp_cvar.sma -oktp_cvar.amxx
./amxxpc ktp_cvarconfig.sma -oktp_cvarconfig.amxx
./amxxpc filescheck.sma -ofilescheck.amxx
```

#### Install
```bash
# Copy to plugins folder
cp *.amxx ../plugins/

# Add to plugins.ini (order matters - anti-cheat first)
echo "ktp_cvar.amxx" >> ../configs/plugins.ini
echo "ktp_cvarconfig.amxx" >> ../configs/plugins.ini
echo "filescheck.amxx" >> ../configs/plugins.ini
echo "KTPMatchHandler.amxx" >> ../configs/plugins.ini
```

</details>

<details>
<summary><b>Step 5: Configure Server</b></summary>

#### server.cfg
```cfg
// ===== CRITICAL: Disable engine pause, use ReAPI only =====
pausable 0

// ===== KTPMatchHandler: Pause System =====
ktp_pause_duration "300"              // 5-minute base pause
ktp_pause_extension "120"             // 2-minute extensions
ktp_pause_max_extensions "2"          // Max 2 extensions
ktp_prepause_seconds "5"              // Countdown before pause
ktp_prematch_pause_seconds "5"        // Pre-match countdown

// ===== KTPMatchHandler: Match System =====
ktp_ready_required "6"                // Players needed to ready
ktp_tech_budget_seconds "300"         // 5-min tech budget per team

// ===== KTPMatchHandler: File Paths =====
ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"
ktp_discord_ini "addons/amxmodx/configs/discord.ini"

// ===== KTPCvarChecker: Enforcement =====
fcos_warn "1"                         // Enable warnings
fcos_attempt_num_warn "5"             // Warn after 5 violations
fcos_kick_or_ban "2"                  // 0=off, 1=kick, 2=ban
fcos_attempt_num_kickorban "15"       // Kick/ban after 15 violations
fcos_ban_time "60"                    // Ban for 60 minutes

// ===== KTPFileChecker: File Consistency =====
fc_exactweapons "1"                   // 1=exact match, 0=same bounds
fc_separatelog "2"                    // 0=engine, 1=AMX, 2=separate file
```

#### ktp_maps.ini
```ini
[dod_avalanche]
config = ktp_avalanche.cfg
name = Avalanche
type = competitive

[dod_flash]
config = ktp_flash.cfg
name = Flash
type = competitive
```

#### filescheck.ini
```ini
//Player Models
models/player/axis-inf/axis-inf.mdl
models/player/axis-inf/axis-infT.mdl
models/player/us-inf/us-inf.mdl
models/player/us-inf/us-infT.mdl

//Sounds
player/headshot1.wav
player/pl_step1.wav

//Grenade Models
models/p_grenade.mdl
models/v_grenade.mdl
models/w_grenade.mdl
```

#### discord.ini (optional)
```ini
discord_relay_url=https://your-relay.run.app/relay
discord_channel_id=1234567890123456789
discord_auth_secret=your-secret-here
```

</details>

<details>
<summary><b>Step 6: Restart Server</b></summary>

```bash
./hlds_run -game dod +maxplayers 16 +map dod_avalanche
```

</details>

---

## 📊 Feature Comparison Matrix

| Feature                  | Base AMX   | ReHLDS     | ReHLDS + ReAPI | **KTP Stack**      |
|--------------------------|------------|------------|----------------|---------------------|
| **Engine**               | HLDS       | ReHLDS     | ReHLDS         | **KTP-ReHLDS**      |
| **Module**               | None       | None       | Standard ReAPI | **KTP-ReAPI**       |
| Match Workflow           | ✅         | ✅         | ✅             | ✅                  |
| Pause System             | ⚠️ Basic   | ⚠️ Basic   | ✅ Good        | **✅ OPTIMAL**      |
| Pause Method             | server_cmd | server_cmd | ✅ ReAPI       | **✅ ReAPI**        |
| Pause HUD Hook           | ❌ None    | ❌ None    | ❌ None        | **✅ Custom Hook**  |
| HUD During Pause         | ❌ Frozen  | ❌ Frozen  | ❌ Frozen      | **✅ Real-time**    |
| Server Messages          | ✅ rcon say | ✅ rcon say | ✅ rcon say   | ✅ rcon say         |
| Player Chat              | ❌ Frozen  | ❌ Frozen  | ❌ Frozen      | **⚠️ Partial**      |
| Commands During Pause    | ❌         | ❌         | ⚠️            | **✅ Full**         |
| Auto-Warnings            | ❌ Manual  | ❌ Manual  | ⚠️ Limited    | **✅ Automatic**    |
| Cvar Detection           | ⏱️ 15-90s  | ⏱️ 15-90s  | ✅ Instant    | **✅ Instant**      |
| Cvar Check Performance   | ⏱️ 8.55s   | ⏱️ 8.55s   | ✅ Good       | **⚡ 85x faster**   |
| Cvar Enforcement         | ✅         | ✅         | ✅             | **✅ 57 cvars**     |
| File Consistency         | ✅ Basic   | ✅ Basic   | ✅ Basic       | **✅ Enhanced**     |
| Discord Webhooks         | ✅         | ✅         | ✅             | **✅ Cloud Run**    |
| `pausable 0` Compatible  | ❌         | ❌         | ✅             | **✅**              |

---

## 🎮 Command Reference

<details>
<summary><b>Match Control Commands</b></summary>

| Command | Description |
|---------|-------------|
| `/start` | Initiate pre-start sequence |
| `/confirm` | Confirm team ready for start |
| `/ready`, `/ktp` | Mark yourself ready |
| `/notready` | Mark yourself not ready |
| `/status` | View match status |
| `/cancel` | Cancel match/pre-start |

</details>

<details>
<summary><b>Pause Control Commands</b></summary>

| Command | Description | Access |
|---------|-------------|--------|
| `/pause` | Tactical pause (5-sec countdown) | Anyone |
| `/tech` | Technical pause | Anyone |
| `/resume` | Request unpause | Owner team |
| `/confirmunpause` | Confirm unpause | Other team |
| `/cresume`, `/cunpause` | Aliases for confirmunpause | Other team |
| `/extend` | Extend pause +2 minutes | Anyone |
| `/cancelpause` | Cancel disconnect pause | Affected team |

</details>

<details>
<summary><b>Admin Commands</b></summary>

| Command | Description |
|---------|-------------|
| `/fcosconfig` | Configure cvar checker |
| `/reloadmaps` | Reload map configuration |
| `/ktpconfig` | View current CVARs |
| `/ktpdebug` | Toggle debug mode |

</details>

---

## 📝 How They Work Together

```
KTP-ReHLDS (engine) calls SV_UpdatePausedHUD() every frame during pause
           ↓
KTP-ReAPI (module) exposes RH_SV_UpdatePausedHUD hook to plugins
           ↓
KTPMatchHandler (plugin) registers the hook and updates HUD with live timer
           ↓
Players see real-time MM:SS countdown while game is frozen
```

### The Innovation

<table>
<tr>
<th>Standard Setup (pausable 1)</th>
<th>KTP Stack (v0.4.3+)</th>
</tr>
<tr>
<td>

- ❌ Everything freezes (HUD, chat, time)
- ❌ No way to display timers
- ❌ Player chat completely frozen
- ❌ Server events don't display

</td>
<td>

- ✅ HUD updates every frame
- ✅ Real-time countdown timer
- ✅ Commands work during pause
- ✅ First chat message displays
- ✅ Automatic warnings (30s/10s)
- ✅ Instant anti-cheat (85x faster)
- ✅ Professional match workflow

</td>
</tr>
</table>

---

## 🔗 GitHub Repositories

### KTP Core Stack
- **[KTP-ReHLDS](https://github.com/afraznein/KTP-ReHLDS)** - Layer 1: Custom engine
- **[KTP-ReAPI](https://github.com/afraznein/KTP-ReAPI)** - Layer 2: Custom module
- **[KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)** - Layer 3: Anti-cheat
- **[KTPFileChecker](https://github.com/afraznein/KTPFileChecker)** - Layer 3: File validation (Private)
- **[KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)** - Layer 4: Match management

### Supporting Infrastructure
- **[Discord Relay](https://github.com/afraznein/discord-relay)** - Cloud Run webhook proxy
- **[KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)** - HLTV spectator management

### Upstream Projects
- **[ReAPI](https://github.com/s1lentq/reapi)** - Original ReAPI module
- **[ReHLDS](https://github.com/dreamstalker/rehlds)** - Original ReHLDS engine

---

## 👤 Author

**Nein_**
- GitHub: [@afraznein](https://github.com/afraznein)
- Project: KTP Competitive Infrastructure

---

## 🙏 Acknowledgments

- **s1lentq** - Original ReAPI and ReGameDLL development
- **dreamstalker** - Original ReHLDS project
- **ReHLDS Team** - Engine enhancements and architecture
- **ReAPI Team** - Module framework and hooks system
- **AMX Mod X Team** - Scripting platform
- **SubStream** - Original Force CAL Open Settings (FCOS)
- **KTP Community** - Testing, feedback, and competitive insights

---

<div align="center">

**Professional-grade match management for Day of Defeat**

*Real-time pause controls • Instant anti-cheat • Discord integration*

</div>
