# KTP Competitive Infrastructure - Technical Guide

<div align="center">

**The Ultimate Day of Defeat Competitive Server Stack**

[![License](https://img.shields.io/badge/license-Mixed-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![Engine](https://img.shields.io/badge/engine-GoldSrc%20%7C%20Half--Life-orange.svg)]()
[![Game](https://img.shields.io/badge/game-Day%20of%20Defeat-green.svg)]()

*A comprehensive ecosystem of custom engine modifications, extension modules, match management plugins, and supporting services designed for competitive 6v6 Day of Defeat gameplay*

**No Metamod Required** - Runs on Linux and Windows via ReHLDS Extension Mode

**Last Updated:** 2025-12-18

[Architecture](#-six-layer-architecture) • [Components](#-component-documentation) • [Installation](#-complete-installation-guide) • [Repositories](#-github-repositories)

</div>

---

## 📦 Six-Layer Architecture

The KTP stack eliminates Metamod dependency through a custom extension loading architecture. KTPAMXX loads directly as a ReHLDS extension, and modules like KTP-ReAPI interface through KTPAMXX's module API instead of Metamod hooks.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 6: Application Plugins (AMX Plugins)                                  │
│  KTPMatchHandler v0.9.0  - Match workflow, pause system, HLStatsX integration│
│  KTPCvarChecker v7.5     - Real-time cvar enforcement                        │
│  KTPFileChecker v2.0     - File consistency validation                       │
│  KTPAdminAudit v1.2.0    - Admin action logging                              │
│  stats_logging.sma       - DODX weaponstats with match ID support            │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Forwards & Natives
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 5: Game Stats Modules (AMXX Modules)                                  │
│  DODX Module             - Day of Defeat stats, weapons, shot tracking       │
│  New natives: dodx_flush_all_stats, dodx_reset_all_stats, dodx_set_match_id  │
│  New forward: dod_stats_flush(id)                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Module API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 4: HTTP/Networking Modules (AMXX Modules)                             │
│  KTP AMXX Curl v1.1.1-ktp - Non-blocking HTTP/FTP via libcurl                │
│  Uses MF_RegModuleFrameFunc() for async processing                           │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Module API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 3: Engine Bridge Modules (AMXX Modules)                               │
│  KTP-ReAPI v5.25.0.0-ktp - Exposes ReHLDS/ReGameDLL hooks to plugins         │
│  Extension Mode: No Metamod, uses KTPAMXX GetEngineFuncs()                   │
│  Custom Hook: RH_SV_UpdatePausedHUD for real-time pause HUD                  │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses ReHLDS Hookchains
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 2: Scripting Platform (ReHLDS Extension)                              │
│  KTPAMXX v2.5.0 - AMX Mod X fork with extension mode + HLStatsX integration  │
│  Loads as ReHLDS extension, no Metamod required                              │
│  Provides: client_cvar_changed forward, MF_RegModuleFrameFunc()              │
│  New: MF_GetEngineFuncs(), MF_GetGlobalVars(), MF_GetUserMsgId()             │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ ReHLDS Extension API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 1: Game Engine (KTP-ReHLDS v3.18.0.894)                               │
│  Custom ReHLDS fork with extension loader + KTP features                     │
│  Provides: SV_UpdatePausedHUD hook, pfnClientCvarChanged callback            │
│  Extension hooks: SV_ClientCommand, SV_InactivateClients, AlertMessage       │
│                   PF_TraceLine, PF_SetClientKeyValue, SV_PlayerRunPreThink   │
└─────────────────────────────────────────────────────────────────────────────┘

                         Supporting Infrastructure:
┌─────────────────────────────────────────────────────────────────────────────┐
│  Cloud Services:                                                             │
│  - Discord Relay v1.0.0     - HTTP proxy for Discord webhooks (Cloud Run)   │
│  - KTPHLStatsX v0.1.0       - Modified HLStatsX daemon with match tracking   │
│                                                                              │
│  VPS Services:                                                               │
│  - KTPFileDistributor v1.0.0 - .NET 8 file sync daemon (SFTP distribution)  │
│  - KTPHLTVKicker v5.9        - Java HLTV spectator management               │
│                                                                              │
│  SDK Layer:                                                                  │
│  - KTP HLSDK               - pfnClientCvarChanged callback headers           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Innovation: No Metamod Required

| Traditional Stack                                | KTP Stack                                        |
|--------------------------------------------------|--------------------------------------------------|
| ReHLDS → Metamod → AMX Mod X → ReAPI → Plugins   | KTP-ReHLDS → KTPAMXX → KTP-ReAPI → Plugins       |
| Metamod loads AMX Mod X as plugin                | KTPAMXX loads as ReHLDS extension directly       |
| ReAPI uses Metamod hooks                         | KTP-ReAPI uses ReHLDS hookchains via KTPAMXX     |
| DODX requires Metamod for PreThink               | DODX uses SV_PlayerRunPreThink hookchain         |
| Linux requires Metamod                           | **Linux works natively**                         |

<details>
<summary><b>🔬 Why No Metamod? The Wall Penetration Discovery</b></summary>

#### The Critical Problem

Wall penetration (bullets passing through surfaces) **breaks** when using ReHLDS + Metamod together - any version of Metamod. This is game-breaking for competitive Day of Defeat where wall bangs are a core mechanic.

| Configuration | Wall Penetration |
|--------------|------------------|
| ReHLDS + DoD (no Metamod) | **WORKS** |
| Vanilla HLDS + Metamod + DoD | **WORKS** |
| ReHLDS + Metamod + DoD | **BROKEN** |

**Symptoms:** Bullets stop at first surface. No exit holes, no penetration effects.

#### Debug Analysis

Debug logging in ReHLDS `PF_traceline_DLL` revealed the issue:

**With Metamod (broken):**
```
Trace #1: frac=0.0496 ss=0 as=0  (bullet hits wall)
Trace #2: frac=0.0000 ss=1 as=0  (inside wall)
Trace #3: frac=0.0600 ss=0 as=0  (exit point found)
-- DoD stops here --
```

**Without Metamod (working):**
```
Trace #1: frac=0.0496 ss=0 as=0  (bullet hits wall)
Trace #2: frac=0.0000 ss=1 as=0  (inside wall)
Trace #3: frac=0.0600 ss=0 as=0  (exit point found)
Trace #4: frac=0.XXXX ss=0 as=0  (penetration continues)
Trace #5: frac=0.XXXX ss=0 as=0  (damage calculation)
```

The trace results are identical through trace 3. Same fractions, same positions, same flags. But DoD makes a different internal decision - with Metamod present, it stops after finding the exit point instead of continuing to traces 4 and 5 (actual penetration).

#### What Was Ruled Out

Systematic bypass testing:

| Test | Result |
|------|--------|
| Bypass individual trace wrappers | Still broken |
| Bypass ALL trace wrappers | Still broken |
| Pass original enginefuncs_t directly to DoD | Still broken |
| Pass original DLL_FUNCTIONS to engine | Still broken |
| Pass original NEW_DLL_FUNCTIONS to engine | Still broken |
| All three tables bypassed simultaneously | **Still broken** |

Even with complete API bypass - DoD receiving original ReHLDS functions, engine receiving original DoD functions, no Metamod wrappers in the call chain - wall penetration still fails.

#### Root Cause

**The mere presence of Metamod in the DLL loading chain changes DoD's internal state.**

The issue is not in the API tables. It's in the loading process itself:

1. ReHLDS calls `GiveFnptrsToDll` to Metamod (thinking it's the game DLL)
2. Metamod calls `GiveFnptrsToDll` to the real DoD
3. DoD receives the enginefuncs table from Metamod's address space

DoD appears to be making decisions based on something other than the function pointers themselves - possibly the address of the table, module addresses, initialization timing, or memory layout assumptions.

Vanilla HLDS + Metamod works because they were developed together and whatever assumptions DoD makes are satisfied. ReHLDS, as a reimplementation, has subtle differences that break this.

#### The Solution

Bypass Metamod entirely via KTP-ReHLDS extension loader:

```
Previous (BROKEN):
ReHLDS → Metamod → AMXX → DoD

Solution (WORKING):
ReHLDS → DoD
   ↓
KTPAMXX (loaded via extensions.ini)
```

**This discovery drove the entire KTP architecture.** Rather than a preference, eliminating Metamod is a technical requirement for competitive Day of Defeat on ReHLDS.

*Full analysis: [WallPenetrationDebugSummary.md](WallPenetrationDebugSummary.md)*

</details>

---

## 🔧 Component Documentation

### Layer 1: KTP-ReHLDS (Engine)

**Repository:** [github.com/afraznein/KTPReHLDS](https://github.com/afraznein/KTPReHLDS)
**Version:** 3.18.0.894-dev+m
**License:** MIT

<details>
<summary><b>🎯 Core Engine Features</b></summary>

#### Extension Loading System

KTP-ReHLDS provides the foundation for loading KTPAMXX without Metamod:

```cpp
// ReHLDS extension entry point (used by KTPAMXX)
extern "C" DLLEXPORT void AMXX_RehldsExtensionInit();
extern "C" DLLEXPORT void AMXX_RehldsExtensionShutdown();
```

**What This Enables:**
- KTPAMXX loads directly into ReHLDS process
- Full access to ReHLDS hookchains and APIs
- Cross-platform operation (Windows + Linux)
- No Metamod DLL required

#### Selective Pause System

Standard GoldSrc pause freezes everything. KTP-ReHLDS provides selective freeze:

| What Gets Frozen                     | What Keeps Working                 |
|--------------------------------------|------------------------------------|
| Physics (`SV_Physics()` skipped)     | Network I/O                        |
| Game time (`g_psv.time` frozen)      | HUD messages                       |
| Player movement                      | Server messages (`rcon say`)       |
| Entity thinking                      | Commands (`/pause`, `/resume`)     |
| Projectiles                          | Client message buffers             |

#### Extension Mode Hookchains (v3.16.0-3.18.0)

| Hook                       | Purpose                              | Used By              |
|----------------------------|--------------------------------------|----------------------|
| `SV_ClientCommand`         | Chat commands, menus                 | `register_clcmd`     |
| `SV_InactivateClients`     | Map change cleanup                   | `plugin_end`         |
| `SV_ClientUserInfoChanged` | Client info changes                  | `client_infochanged` |
| `PF_RegUserMsg_I`          | Message ID capture                   | HUD drawing          |
| `PF_changelevel_I`         | Level change                         | `server_changelevel` |
| `AlertMessage`             | Engine log messages                  | `register_logevent`  |
| `PF_TraceLine`             | TraceLine interception               | DODX `TraceLine`     |
| `PF_SetClientKeyValue`     | Client key/value changes             | DODX stats           |
| `SV_PlayerRunPreThink`     | Player PreThink loop                 | DODX shot tracking   |

#### Custom Hook: `SV_UpdatePausedHUD`

Called every frame (~60-100 Hz) during pause:

```cpp
// In KTP-ReHLDS sv_main.cpp
void SV_Frame() {
    if (g_psv.paused) {
        // Call pause HUD hook for plugins to update displays
        g_RehldsHookchains.m_SV_UpdatePausedHUD->callChain();
    }
}
```

**Enables:**
- Real-time MM:SS countdown during pause
- Warning messages (30s, 10s remaining)
- Unpause countdown (5...4...3...2...1)
- Server announcements during pause

</details>

---

### Layer 2: KTPAMXX (Scripting Platform)

**Repository:** [github.com/afraznein/KTPAMXX](https://github.com/afraznein/KTPAMXX)
**Version:** 2.5.0
**License:** GPL v3
**Base:** AMX Mod X 1.10.0.5468-dev

<details>
<summary><b>🎯 Extension Mode Architecture</b></summary>

#### Dual-Mode Operation

KTPAMXX automatically detects environment and adapts:

```cpp
// Global flags set during initialization
bool g_bRunningWithMetamod;      // True if Metamod present
bool g_bRehldsExtensionInit;     // True if loaded as extension

// Entry points
void Meta_Attach();              // Traditional Metamod mode
void AMXX_RehldsExtensionInit(); // Extension mode (no Metamod)
```

#### ReHLDS Hooks (Extension Mode)

| Hook                                   | Purpose                      |
|----------------------------------------|------------------------------|
| `SV_DropClient`                        | Client disconnect handling   |
| `SV_ActivateServer`                    | Map load / server activation |
| `Cvar_DirectSet`                       | Cvar change monitoring       |
| `SV_WriteFullClientUpdate`             | Client info updates          |
| `ED_Alloc` / `ED_Free`                 | Entity allocation            |
| `SV_StartSound`                        | Sound emission               |
| `ClientConnected` / `SV_ConnectClient` | Connection handling          |
| `SV_ClientCommand`                     | Chat commands, menus         |
| `SV_InactivateClients`                 | Map change plugin_end        |
| `AlertMessage`                         | Log events (logevent)        |

</details>

<details>
<summary><b>⚡ New Forward: client_cvar_changed</b></summary>

#### Real-Time Cvar Monitoring

```pawn
/**
 * Called when a client responds to ANY cvar query.
 * Requires KTP-ReHLDS for full functionality.
 *
 * @param id        Client index (1-32)
 * @param cvar      Name of the queried cvar
 * @param value     Value returned by client (string)
 */
forward client_cvar_changed(id, const cvar[], const value[]);
```

</details>

<details>
<summary><b>🔌 Module API Extensions (v2.4.0+)</b></summary>

#### For Modules Requiring Engine Access

```cpp
// Module can request engine functions from KTPAMXX
enginefuncs_t* MF_GetEngineFuncs();    // Get engine function table
globalvars_t*  MF_GetGlobalVars();     // Get global variables
int            MF_GetUserMsgId(const char* name);  // Get message ID
void           MF_RegModuleMsgHandler(...);  // Register message handler
void           MF_RegModuleFrameFunc(callback);   // Per-frame callback
```

**Used By:**
- KTP-ReAPI (engine access without Metamod)
- KTP AMXX Curl (async HTTP processing)
- DODX (stats tracking via PreThink)

</details>

<details>
<summary><b>📂 Path and Naming Changes</b></summary>

#### KTP Branding

| Component         | Standard AMX Mod X         | KTPAMXX                           |
|-------------------|----------------------------|-----------------------------------|
| Main binary       | `amxmodx_mm.dll/.so`       | `ktpamx.dll` / `ktpamx_i386.so`   |
| Module suffix     | `*_amxx.dll/.so`           | `*_ktp.dll` / `*_ktp_i386.so`     |
| Configs directory | `addons/amxmodx/`          | `addons/ktpamx/`                  |
| Plugins directory | `addons/amxmodx/plugins/`  | `addons/ktpamx/plugins/`          |

#### Directory Structure

```
addons/ktpamx/
├── dlls/
│   └── ktpamx.dll (or ktpamx_i386.so)
├── configs/
│   ├── amxx.cfg
│   ├── plugins.ini
│   ├── modules.ini
│   ├── users.ini
│   ├── ktp_maps.ini
│   ├── discord.ini
│   └── ktp_file.ini
├── data/
├── logs/
├── modules/
│   ├── reapi_ktp.dll / reapi_ktp_i386.so
│   ├── amxxcurl_ktp.dll / amxxcurl_ktp_i386.so
│   ├── dodx_ktp.dll / dodx_ktp_i386.so
│   └── dodfun_ktp.dll / dodfun_ktp_i386.so
├── plugins/
│   ├── KTPMatchHandler.amxx
│   ├── ktp_cvar.amxx
│   ├── ktp_file.amxx
│   ├── KTPAdminAudit.amxx
│   └── stats_logging.amxx
└── scripting/
```

</details>

---

### Layer 3: KTP-ReAPI (Engine Bridge Module)

**Repository:** [github.com/afraznein/KTPReAPI](https://github.com/afraznein/KTPReAPI)
**Version:** 5.25.0.0-ktp
**License:** GPL v3
**Base:** ReAPI 5.26+

<details>
<summary><b>🎯 Extension Mode Operation</b></summary>

#### No Metamod Required

KTP-ReAPI operates in extension mode via `REAPI_NO_METAMOD` compile flag:

```cpp
// extension_mode.h
#define REAPI_NO_METAMOD

// Stubs for Metamod macros
#define SET_META_RESULT(x)
#define RETURN_META(x) return
#define RETURN_META_VALUE(x, y) return y
```

#### Engine Access via KTPAMXX

```cpp
// KTP-ReAPI gets engine functions from KTPAMXX, not Metamod
void OnAmxxAttach() {
    // KTPAMXX provides these APIs
    enginefuncs_t* pEngFuncs = g_amxxapi.GetEngineFuncs();
    globalvars_t* pGlobals = g_amxxapi.GetGlobalVars();

    // Initialize ReAPI with engine access
    ReAPI_Initialize(pEngFuncs, pGlobals);
}
```

</details>

<details>
<summary><b>⚡ Custom KTP Hook: RH_SV_UpdatePausedHUD</b></summary>

#### The Critical Hook for Real-Time Pause HUD

```pawn
// In reapi_engine_const.inc
enum RehldsHook {
    // ... standard hooks ...

    /*
    * Called during pause to allow HUD updates (KTP-ReHLDS custom hook)
    * Params: ()
    * @note This is a KTP-ReHLDS specific hook, not available in standard ReHLDS
    */
    RH_SV_UpdatePausedHUD,
};
```

#### Plugin Usage

```pawn
#include <amxmodx>
#include <reapi>

public plugin_init() {
    #if defined RH_SV_UpdatePausedHUD
        RegisterHookChain(RH_SV_UpdatePausedHUD, "OnPausedHUDUpdate", .post = false);
    #endif
}

#if defined RH_SV_UpdatePausedHUD
public OnPausedHUDUpdate() {
    if (!g_bIsPaused) return HC_CONTINUE;

    // Calculate time remaining
    new iElapsed = get_systime() - g_iPauseStartTime;
    new iRemaining = g_iPauseDuration - iElapsed;
    new iMinutes = iRemaining / 60;
    new iSeconds = iRemaining % 60;

    // Update HUD for all players
    set_hudmessage(255, 255, 0, -1.0, 0.35, 0, 0.0, 0.1, 0.0, 0.0, -1);
    show_hudmessage(0, "== PAUSED ==^n%02d:%02d remaining", iMinutes, iSeconds);

    return HC_CONTINUE;
}
#endif
```

</details>

---

### Layer 4: KTP AMXX Curl (HTTP Module)

**Repository:** [github.com/afraznein/KTPAMXXCurl](https://github.com/afraznein/KTPAMXXCurl)
**Version:** 1.1.1-ktp
**License:** MIT
**Base:** AmxxCurl by Polarhigh

<details>
<summary><b>🎯 Non-Blocking HTTP Without Metamod</b></summary>

#### Uses KTPAMXX Frame Callback API

Original AmxxCurl used Metamod's `pfnStartFrame` for async processing. KTP fork uses KTPAMXX's module frame callback:

```cpp
// In callbacks.cc
void OnPluginsLoaded() {
    // KTP: Register frame callback for async processing
    if (MF_RegModuleFrameFunc)
        MF_RegModuleFrameFunc(CurlFrameCallback);
}

// Called every frame by KTPAMXX
void CurlFrameCallback() {
    // Process pending curl transfers
    curl_multi_perform(g_curlMulti, &running);
    // Handle completions, fire callbacks
}
```

</details>

---

### Layer 5: DODX Stats Module

**Included in:** KTPAMXX
**Version:** 2.5.0
**Purpose:** Day of Defeat weapon stats, shot tracking, HLStatsX integration

<details>
<summary><b>📊 Extension Mode Stats Tracking</b></summary>

#### New HLStatsX Integration Natives (v2.5.0)

```pawn
// Flush all player stats to log (for warmup → match transition)
native dodx_flush_all_stats();

// Reset all player stats (clear warmup stats before match)
native dodx_reset_all_stats();

// Set match ID for correlation with HLStatsX
native dodx_set_match_id(const matchId[]);

// Get current match ID
native dodx_get_match_id(output[], maxlen);
```

#### New Forward

```pawn
// Called for each player when stats are flushed
forward dod_stats_flush(id);
```

#### Shot Tracking via SV_PlayerRunPreThink

DODX uses the new `SV_PlayerRunPreThink` hookchain for shot detection:

```cpp
// Per-weapon fire rate delays for accurate tracking
// MG42: 0.05s | SMGs: 0.1s | Semi-auto rifles: 0.5s (rising edge only)
```

#### Match ID in weaponstats Logs

When match ID is set, all log lines include it:

```
"Player<uid><STEAM_ID><TEAM>" triggered "weaponstats" (weapon "kar") (shots "5") ... (matchid "KTP-1734355200-dod_charlie")
```

</details>

---

### Layer 6: Application Plugins

#### KTPMatchHandler

**Repository:** [github.com/afraznein/KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)
**Version:** 0.9.0
**License:** MIT

<details>
<summary><b>🏆 Match Workflow System</b></summary>

```
1. PRE-START
   /start <password> or /ktp <password> → Both teams /confirm

2. PENDING (Ready-Up)
   Players type /ready (6 per team by default)
   Periodic reminders every 30 seconds
   /whoneedsready to see unready players

3. MATCH START
   - Match ID generated: KTP-{timestamp}-{mapname}
   - dodx_flush_all_stats() - flush warmup stats
   - dodx_reset_all_stats() - clear for fresh match
   - dodx_set_match_id() - set match context
   - KTP_MATCH_START logged for HLStatsX

4. LIVE COUNTDOWN
   "Match starting in 5..."

5. MATCH LIVE
   Map config auto-executes
   Pause system active
   Full logging with match ID
   Score tracking per half

6. HALF END / MATCH END
   - dodx_flush_all_stats() - flush match stats
   - KTP_MATCH_END logged for HLStatsX
   - Discord notification with scores
```

#### Match Types (v0.9.0)

| Type        | Command      | Password | Season Required | Config               |
|-------------|--------------|----------|-----------------|----------------------|
| Competitive | `/start`     | Required | Yes             | `mapname.cfg`        |
| Draft       | `/draft`     | None     | No              | `mapname.cfg`        |
| 12-Man      | `/12man`     | None     | No              | `mapname_12man.cfg`  |
| Scrim       | `/scrim`     | None     | No              | `mapname_scrim.cfg`  |

#### Season Control (v0.9.0)

```pawn
/ktpseason <admin_password>   // Toggle competitive availability
```

- When season is OFF, `/start` and `/ktp` are disabled
- Draft, 12man, and scrim always available
- Prevents accidental competitive matches during off-season

#### Score Tracking (v0.8.0+)

- Tracks scores per half via TeamScore hook
- Persists across map changes via localinfo
- Discord match end shows final score with half breakdown

</details>

<details>
<summary><b>⏸️ Advanced Pause System</b></summary>

#### Two Pause Types

| Type          | Limit           | Duration    | Extensions             | Command   |
|---------------|-----------------|-------------|------------------------|-----------|
| **Tactical**  | 1 per team/half | 5 minutes   | 2× 2 min (9 min max)   | `/pause`  |
| **Technical** | Unlimited       | Uses budget | Unlimited              | `/tech`   |

**Technical Pause Budget:** 5 minutes per team total (persists across halves via localinfo)

#### Pause Flow with Real-Time HUD

```
Player types /pause
        ↓
5-second countdown ("Pausing in 5...")
        ↓
rh_set_server_pause(true)  ← ReAPI native
        ↓
GAME FREEZES
  - Physics stop
  - Time stops
  - Players can't move
        ↓
KTP-ReHLDS calls SV_UpdatePausedHUD every frame
        ↓
KTP-ReAPI forwards to OnPausedHUDUpdate hook
        ↓
KTPMatchHandler updates HUD:

  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  /resume  |  /confirmunpause  |  /extend
```

</details>

---

#### KTPCvarChecker

**Repository:** [github.com/afraznein/KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)
**Version:** 7.5
**License:** GPL v2

<details>
<summary><b>⚡ Priority-Based Cvar Monitoring</b></summary>

#### 59 Monitored Cvars (9 Priority + 50 Standard)

**Priority Cvars (checked every 2 seconds):**
```
m_pitch, cl_yawspeed, cl_pitchspeed, lightgamma, cl_bob,
cl_updaterate, cl_cmdrate, rate, ex_interp
```

**Standard Cvars (rotated every 10 seconds):**
```
Graphics: gl_*, r_fullbright, r_lightmap, texgamma, etc. (33 cvars)
Audio: s_show, ambient_* (2 cvars)
Movement: m_side, cl_pitch*, lookspring, etc. (7 cvars)
Gameplay: cl_lc, cl_lw, fps_max, etc. (8 cvars)
```

#### Performance

- **~5 queries/second per player** (~160 q/s for 32 players)
- **~0.4% CPU usage**
- **~8 KB/s network overhead**
- **Priority cvars detected in <2 seconds**
- **Standard cvars full cycle ~100 seconds**

</details>

---

#### KTPFileChecker

**Repository:** Private
**Version:** 2.0
**License:** Custom

<details>
<summary><b>📁 File Consistency Checking</b></summary>

#### Monitored File Types

| Type          | Examples                        | Purpose                            |
|---------------|---------------------------------|------------------------------------|
| Player Models | `axis-inf.mdl`, `us-para.mdl`   | Prevent bright/transparent textures|
| Sounds        | `pl_step*.wav`, `headshot1.wav` | Prevent amplified audio            |
| Weapon Models | `v_grenade.mdl`, `p_mills.mdl`  | Prevent model exploits             |
| Sprites       | `crosshairs.spr`                | Optional, usually harmless         |

#### Two Validation Modes

```cfg
fc_exactweapons "1"  // Exact file hash match (competitive)
fc_exactweapons "0"  // Same hitbox bounds allowed (public servers)
```

</details>

---

#### KTPAdminAudit

**Repository:** [github.com/afraznein/KTPAdminAudit](https://github.com/afraznein/KTPAdminAudit)
**Version:** 1.2.0
**License:** MIT

<details>
<summary><b>🔐 Administrative Action Monitoring</b></summary>

#### Features

- RCON kick monitoring
- Admin identity tracking (SteamID, name, IP)
- Target player tracking
- Multi-channel Discord notifications
- Per-match-type audit channels

</details>

---

### Supporting Infrastructure

#### Discord Relay

**Repository:** [github.com/afraznein/discord-relay](https://github.com/afraznein/discord-relay)
**Version:** 1.0.0
**Platform:** Google Cloud Run
**License:** MIT

<details>
<summary><b>🔔 HTTP Relay Architecture</b></summary>

#### 14 API Endpoints

| Endpoint                    | Purpose                          |
|-----------------------------|----------------------------------|
| `POST /relay`               | Send message to Discord channel  |
| `POST /relay/embed`         | Send rich embed message          |
| `POST /relay/edit`          | Edit existing message            |
| `POST /relay/delete`        | Delete message                   |
| `POST /relay/reaction/add`  | Add reaction to message          |
| `POST /relay/reaction/remove`| Remove reaction                 |
| `POST /relay/thread`        | Create thread                    |
| `POST /relay/thread/message`| Send message to thread           |
| `POST /relay/pin`           | Pin message                      |
| `POST /relay/unpin`         | Unpin message                    |
| `GET /relay/messages`       | Fetch recent messages            |
| `GET /relay/message/:id`    | Fetch specific message           |
| `GET /health`               | Health check                     |
| `GET /`                     | Service info                     |

**Why Use a Relay:**
- Hides Discord webhook URL from game server
- Handles rate limiting with retry logic
- Centralized auth secret management
- Works around Cloudflare challenges
- Scales to zero when not in use

</details>

---

#### KTPHLStatsX

**Repository:** [github.com/afraznein/KTPHLStatsX](https://github.com/afraznein/KTPHLStatsX)
**Version:** 0.1.0
**Platform:** HLStatsX:CE Fork (Perl daemon + MySQL)
**License:** GPL v2

<details>
<summary><b>📊 Match-Based Statistics Tracking</b></summary>

#### Purpose

Separates competitive match stats from warmup/practice stats. Standard HLStatsX tracks all kills equally - KTPHLStatsX tracks match context.

#### Data Flow

```
WARMUP PHASE:
  Players join, practice
  Stats accumulate in DODX memory
  [Nothing logged to HLStatsX yet]

MATCH START (all players /ready):
  1. dodx_flush_all_stats()     → Log warmup stats (NO matchid)
  2. dodx_reset_all_stats()     → Clear all counters
  3. dodx_set_match_id(id)      → Set match context
  4. log "KTP_MATCH_START"      → HLStatsX creates ktp_matches row

DURING MATCH:
  Kills/deaths logged WITH match_id
  HLStatsX stores events with match_id column populated

MATCH END:
  1. dodx_flush_all_stats()     → Log match stats (WITH matchid)
  2. log "KTP_MATCH_END"        → HLStatsX updates end_time
  3. dodx_set_match_id("")      → Clear context

POST-MATCH:
  Future stats have match_id = NULL again
```

#### MySQL Schema Additions

- `ktp_matches` - Match metadata (start/end time, map, server)
- `ktp_match_players` - Players per match with teams
- `ktp_match_stats` - Aggregated per-player stats per match
- `match_id` column added to `hlstats_Events_*` tables

</details>

---

#### KTPFileDistributor

**Repository:** [github.com/afraznein/KTPFileDistributor](https://github.com/afraznein/KTPFileDistributor)
**Version:** 1.0.0
**Platform:** .NET 8 Worker Service (Linux VPS)
**License:** MIT

<details>
<summary><b>📤 Automated File Distribution</b></summary>

#### Purpose

Automatically distributes compiled plugins and configs from build server to multiple game servers via SFTP.

#### Features

- FileSystemWatcher with debounce
- SFTP distribution via SSH.NET
- Multi-server support
- Discord notifications
- Systemd service for Ubuntu 24

#### Configuration

```json
{
  "FileDistributor": {
    "WatchPath": "/opt/ktp/build",
    "WatchFilter": "*.amxx",
    "DebounceSeconds": 5
  },
  "Servers": [
    {
      "Name": "KTP NY",
      "Host": "ny.example.com",
      "Port": 22,
      "Username": "ktp",
      "PrivateKeyPath": "/root/.ssh/ktp_deploy",
      "RemotePath": "/home/ktp/dod/addons/ktpamx/plugins"
    }
  ],
  "Discord": {
    "Enabled": true,
    "WebhookUrl": "https://discord.com/api/webhooks/..."
  }
}
```

</details>

---

#### KTPHLTVKicker

**Repository:** [github.com/afraznein/KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)
**Version:** 5.9
**Platform:** Java (Windows Task Scheduler)
**License:** MIT

<details>
<summary><b>📺 HLTV Spectator Management</b></summary>

#### Purpose

Automatically detects and kicks HLTV spectators from game servers to free slots.

#### Features

- Multi-server support (NY, CHI, DAL, ATL, LA regions)
- Steam Condenser for GoldSrc RCON
- Environment-based configuration (.env)
- Graceful timeout handling for offline servers
- Windows Task Scheduler integration (daily at 4:00 AM)

</details>

---

## 🚀 Complete Installation Guide

### Prerequisites

- **KTP-ReHLDS** - Custom engine binary
- **KTPAMXX** - Extension mode AMX Mod X
- **KTP-ReAPI** - Extension mode ReAPI module
- **KTP AMXX Curl** - HTTP module (for Discord integration)

**NOT Required:**
- ❌ Metamod
- ❌ Standard AMX Mod X
- ❌ Standard ReAPI

---

### Step 1: Install KTP-ReHLDS

```bash
# Backup existing engine
# Linux:
cp <hlds>/engine_i486.so <hlds>/engine_i486.so.backup
# Windows:
copy <hlds>\swds.dll <hlds>\swds.dll.backup

# Download KTP-ReHLDS from releases
# https://github.com/afraznein/KTPReHLDS/releases

# Install
# Linux:
cp engine_i486.so <hlds>/
# Windows:
copy swds.dll <hlds>\
```

---

### Step 2: Install KTPAMXX

```bash
# Download KTPAMXX from releases
# https://github.com/afraznein/KTPAMXX/releases

# Extract to game directory
# Creates: addons/ktpamx/

# Structure should be:
addons/ktpamx/
├── dlls/
│   └── ktpamx.dll (or ktpamx_i386.so)
├── configs/
│   ├── amxx.cfg
│   ├── plugins.ini
│   └── modules.ini
├── modules/
├── plugins/
└── scripting/
```

---

### Step 3: Install Modules

```bash
# Install KTP-ReAPI
cp reapi_ktp_i386.so <game>/addons/ktpamx/modules/

# Install KTP AMXX Curl
cp amxxcurl_ktp_i386.so <game>/addons/ktpamx/modules/

# Install DODX (included with KTPAMXX)
cp dodx_ktp_i386.so <game>/addons/ktpamx/modules/

# Enable in modules.ini
# addons/ktpamx/configs/modules.ini:
reapi_ktp_i386.so
amxxcurl_ktp_i386.so
dodx_ktp_i386.so
dodfun_ktp_i386.so
```

---

### Step 4: Install Plugins

```bash
# Enable in plugins.ini (order matters)
# addons/ktpamx/configs/plugins.ini:
stats_logging.amxx      ; DODX stats with match ID support
ktp_cvar.amxx           ; Cvar checker
ktp_file.amxx           ; File checker
KTPAdminAudit.amxx      ; Admin audit
KTPMatchHandler.amxx    ; Match handler (load last - uses DODX natives)
```

---

### Step 5: Configure Server

#### server.cfg

```cfg
// ===== CRITICAL: Disable engine pause =====
pausable 0

// ===== KTPMatchHandler: Pause System =====
ktp_pause_duration "300"              // 5-minute base pause
ktp_pause_extension "120"             // 2-minute extensions
ktp_pause_max_extensions "2"          // Max 2 extensions
ktp_prepause_seconds "5"              // Countdown before pause
ktp_tech_budget_seconds "300"         // 5-min tech budget per team

// ===== KTPMatchHandler: Match System =====
ktp_ready_required "6"                // Players needed to ready

// ===== KTPFileChecker =====
fc_exactweapons "1"                   // Exact file matching
fc_separatelog "2"                    // Separate log file
```

#### discord.ini

```ini
discord_relay_url=https://your-relay.run.app/relay
discord_channel_id=1234567890123456789
discord_auth_secret=your-secret-here

; Match-type specific channels
discord_channel_id_competitive=1111111111111111111
discord_channel_id_12man=2222222222222222222
discord_channel_id_audit_competitive=3333333333333333333
```

---

## 📊 Feature Comparison Matrix

| Feature              | Base AMX       | ReHLDS + ReAPI  | **KTP Stack**      |
|----------------------|----------------|-----------------|---------------------|
| **Engine**           | HLDS           | ReHLDS          | **KTP-ReHLDS**      |
| **Plugin Platform**  | AMX Mod X      | AMX Mod X       | **KTPAMXX**         |
| **API Module**       | None           | ReAPI + Metamod | **KTP-ReAPI**       |
| **Metamod Required** | No             | Yes             | **No**              |
| **Linux Support**    | Yes            | Via Metamod     | **Native**          |
| Pause Method         | `server_cmd`   | ReAPI           | **ReAPI**           |
| HUD During Pause     | ❌ Frozen      | ❌ Frozen       | **✅ Real-time**    |
| Cvar Detection       | ⏱️ Polling     | ⏱️ Polling      | **⚡ Callback**     |
| Cvar Detection Speed | 15-90s         | 15-90s          | **<2s priority**    |
| HTTP Module          | External       | cURL + Metamod  | **KTP Curl**        |
| File Checking        | Basic          | Basic           | **✅ Enhanced**     |
| Discord Integration  | Manual         | Manual          | **✅ Cloud Relay**  |
| Stats Separation     | ❌ None        | ❌ None         | **✅ Match-based**  |
| HLStatsX Integration | ❌ None        | ❌ None         | **✅ Full**         |

---

## 🎮 Command Reference

### Match Control

| Command            | Description                 | Notes                    |
|--------------------|-----------------------------|--------------------------|
| `/start <pw>`      | Initiate competitive match  | Requires season + password|
| `/ktp <pw>`        | Alias for /start            | Requires season + password|
| `/draft`           | Start draft match           | Always available         |
| `/12man`           | Start 12-man match          | Always available         |
| `/scrim`           | Start scrim match           | Always available         |
| `/confirm`         | Confirm team ready          |                          |
| `/ready`           | Mark yourself ready         |                          |
| `/notready`        | Mark yourself not ready     |                          |
| `/whoneedsready`   | Show unready players        | With SteamIDs            |
| `/status`          | View match status           |                          |
| `/cancel`          | Cancel match/pre-start      |                          |

### Pause Control

| Command           | Description               | Access        |
|-------------------|---------------------------|---------------|
| `/pause`          | Tactical pause            | Anyone        |
| `/tech`           | Technical pause           | Anyone        |
| `/resume`         | Request unpause           | Owner team    |
| `/confirmunpause` | Confirm unpause           | Other team    |
| `/extend`         | Extend pause +2 min       | Anyone        |
| `/cancelpause`    | Cancel disconnect pause   | Affected team |

### Team Control (v0.8.0+)

| Command              | Description               |
|----------------------|---------------------------|
| `/setteamallies <n>` | Set Allies team name      |
| `/setteamaxis <n>`   | Set Axis team name        |
| `/teamnames`         | View current team names   |

### Admin Commands

| Command           | Description              |
|-------------------|--------------------------|
| `/ktpseason <pw>` | Toggle season on/off     |
| `/reloadmaps`     | Reload map configuration |
| `/ktpconfig`      | View current CVARs       |
| `/ktpdebug`       | Toggle debug mode        |
| `/cvar`           | Manual cvar check        |

---

## 🔗 GitHub Repositories

### KTP Core Stack

| Layer    | Repository                                              | Version       | Description                         |
|----------|---------------------------------------------------------|---------------|-------------------------------------|
| Engine   | [KTP-ReHLDS](https://github.com/afraznein/KTPReHLDS)    | 3.18.0.894    | Custom ReHLDS with extension loader |
| SDK      | [KTP HLSDK](https://github.com/afraznein/KTPhlsdk)      | -             | SDK headers with callback support   |
| Platform | [KTPAMXX](https://github.com/afraznein/KTPAMXX)         | 2.5.0         | AMX Mod X extension mode fork       |
| Bridge   | [KTP-ReAPI](https://github.com/afraznein/KTPReAPI)      | 5.25.0.0-ktp  | ReAPI extension mode fork           |
| HTTP     | [KTP AMXX Curl](https://github.com/afraznein/KTPAMXXCurl)| 1.1.1-ktp    | Non-blocking HTTP module            |

### Application Plugins

| Plugin        | Repository                                                      | Version | Description                    |
|---------------|-----------------------------------------------------------------|---------|--------------------------------|
| Match Handler | [KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler) | 0.9.0   | Match workflow + HLStatsX      |
| Cvar Checker  | [KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)   | 7.5     | Client cvar enforcement        |
| File Checker  | [KTPFileChecker](https://github.com/afraznein/KTPFileChecker)   | 2.0     | File consistency               |
| Admin Audit   | [KTPAdminAudit](https://github.com/afraznein/KTPAdminAudit)     | 1.2.0   | Admin action logging           |

### Supporting Infrastructure

| Service          | Repository                                                        | Version | Description                |
|------------------|-------------------------------------------------------------------|---------|----------------------------|
| Discord Relay    | [Discord Relay](https://github.com/afraznein/discord-relay)       | 1.0.0   | Cloud Run webhook proxy    |
| HLStatsX         | [KTPHLStatsX](https://github.com/afraznein/KTPHLStatsX)           | 0.1.0   | Match-based stats tracking |
| File Distributor | [KTPFileDistributor](https://github.com/afraznein/KTPFileDistributor) | 1.0.0 | SFTP file distribution   |
| Cvar Checker FTP | [KTPCvarCheckerFTP](https://github.com/afraznein/KTPCvarCheckerFTP) | 2.0.0 | FTP deployment & log processing |
| HLTV Kicker      | [KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)       | 5.9     | HLTV spectator management  |

### Upstream Projects

| Project   | Repository                                         | Description                 |
|-----------|----------------------------------------------------|-----------------------------|
| ReHLDS    | [rehlds](https://github.com/dreamstalker/rehlds)   | Original ReHLDS             |
| ReAPI     | [reapi](https://github.com/s1lentq/reapi)          | Original ReAPI module       |
| AMX Mod X | [amxmodx](https://github.com/alliedmodders/amxmodx)| Original scripting platform |
| AmxxCurl  | [AmxxCurl](https://github.com/Polarhigh/AmxxCurl)  | Original cURL module        |
| HLStatsX  | [hlstatsx](https://github.com/A1mDev/hlstatsx-community-edition) | Original HLStatsX |

---

## 👤 Author

**Nein_**
- GitHub: [@afraznein](https://github.com/afraznein)
- Project: KTP Competitive Infrastructure

---

## 🙏 Acknowledgments

**KTP Stack Development:**
- **Nein_** - Architecture design, all KTP forks and modifications

**Upstream Projects:**
- **dreamstalker** - Original ReHLDS project
- **s1lentq** - Original ReAPI and ReGameDLL
- **AlliedModders** - AMX Mod X platform
- **Polarhigh** - Original AmxxCurl module
- **SubStream** - Original FCOS cvar checker
- **ConnorMcLeod** - Original file checker code
- **Valve** - GoldSrc engine and Half-Life SDK

**Community:**
- **KTP Community** - Testing, feedback, and competitive insights
- **Day of Defeat Community** - Continued support for competitive play

---

<div align="center">

**Professional-grade match management for Day of Defeat**

*No Metamod Required • Real-time Pause Controls • Instant Anti-Cheat • Discord Integration • Match-Based Stats*

*Cross-platform: Windows + Linux*

**Last Updated:** 2025-12-18

</div>
