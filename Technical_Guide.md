# KTP Competitive Infrastructure - Technical Guide

<div align="center">

**The Ultimate Day of Defeat Competitive Server Stack**

[![License](https://img.shields.io/badge/license-Mixed-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![Engine](https://img.shields.io/badge/engine-GoldSrc%20%7C%20Half--Life-orange.svg)]()
[![Game](https://img.shields.io/badge/game-Day%20of%20Defeat-green.svg)]()

*A comprehensive ecosystem of custom engine modifications, extension modules, and match management plugins designed for competitive 6v6 Day of Defeat gameplay*

**No Metamod Required** - Runs on Linux and Windows via ReHLDS Extension Mode

[Architecture](#-five-layer-architecture) • [Components](#-component-documentation) • [Installation](#-complete-installation-guide) • [Repositories](#-github-repositories)

</div>

---

## 📦 Five-Layer Architecture

The KTP stack eliminates Metamod dependency through a custom extension loading architecture. KTPAMXX loads directly as a ReHLDS extension, and modules like KTP-ReAPI interface through KTPAMXX's module API instead of Metamod hooks.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 5: Application Plugins (AMX Plugins)                         │
│  KTPMatchHandler, KTPCvarChecker, KTPFileChecker, KTPAdminAudit     │
│  Match workflow, anti-cheat, file validation, admin logging         │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Forwards & Natives
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 4: HTTP/Networking Modules (AMXX Modules)                    │
│  KTP AMXX Curl - Non-blocking HTTP/FTP via libcurl                  │
│  Uses MF_RegModuleFrameFunc() for async processing                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Module API
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 3: Engine Bridge Modules (AMXX Modules)                      │
│  KTP-ReAPI - Exposes ReHLDS/ReGameDLL hooks to plugins              │
│  Extension Mode: No Metamod, uses KTPAMXX GetEngineFuncs()          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ Uses ReHLDS Hookchains
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 2: Scripting Platform (ReHLDS Extension)                     │
│  KTPAMXX v2.0 - AMX Mod X fork with extension mode                  │
│  Loads as ReHLDS extension, no Metamod required                     │
│  Provides: client_cvar_changed forward, MF_RegModuleFrameFunc()     │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ ReHLDS Extension API
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1: Game Engine (KTP-ReHLDS)                                  │
│  Custom ReHLDS fork with extension loader + KTP features            │
│  Provides: SV_UpdatePausedHUD hook, pfnClientCvarChanged callback   │
└─────────────────────────────────────────────────────────────────────┘

                         Supporting Infrastructure:
┌─────────────────────────────────────────────────────────────────────┐
│  Cloud Services: Discord Relay (Google Cloud Run)                   │
│  SDK Layer: KTP HLSDK (pfnClientCvarChanged callback headers)       │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Innovation: No Metamod Required

| Traditional Stack                                | KTP Stack                                        |
|--------------------------------------------------|--------------------------------------------------|
| ReHLDS → Metamod → AMX Mod X → ReAPI → Plugins   | KTP-ReHLDS → KTPAMXX → KTP-ReAPI → Plugins       |
| Metamod loads AMX Mod X as plugin                | KTPAMXX loads as ReHLDS extension directly       |
| ReAPI uses Metamod hooks                         | KTP-ReAPI uses ReHLDS hookchains via KTPAMXX     |
| Linux requires Metamod                           | **Linux works natively**                         |

---

## 🔧 Component Documentation

### Layer 1: KTP-ReHLDS (Engine)

**Repository:** [github.com/afraznein/KTPReHLDS](https://github.com/afraznein/KTPReHLDS)
**Version:** 3.15.0.891-dev+m
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

#### Custom Callback: `pfnClientCvarChanged`

Engine-level callback when clients respond to cvar queries:

```cpp
// NEW_DLL_FUNCTIONS addition
void (*pfnClientCvarChanged)(const edict_t *pEdict, const char *cvar, const char *value);
```

**Detection Flow:**
```
Server queries cvar → Client responds → KTP-ReHLDS receives →
pfnClientCvarChanged fires → KTPAMXX forwards to plugins →
client_cvar_changed() forward executes
```

</details>

<details>
<summary><b>⚙️ Technical Implementation</b></summary>

#### Frame-Wide Temporary Unpause (Chat During Pause)

```cpp
// Enable communication while keeping game frozen
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

**Current Status:**
- ✅ `rcon say` works
- ✅ Server events (join/leave) work
- ✅ Commands processed (`/cancel`, `/pause`)
- ✅ First player chat message works
- ⚠️ Subsequent chat blocked by DoD DLL flood protection

#### Modified Files

| File                                 | Purpose                               |
|--------------------------------------|---------------------------------------|
| `rehlds/public/rehlds/rehlds_api.h`  | Added `IRehldsHook_SV_UpdatePausedHUD`|
| `rehlds/rehlds/engine/sv_main.cpp`   | Hook call in `SV_Frame()`             |
| `rehlds/rehlds/engine/sv_user.cpp`   | Message flushing during pause         |
| `rehlds/public/rehlds/hookchains.h`  | Hook registry                         |

</details>

---

### Layer 2: KTPAMXX (Scripting Platform)

**Repository:** [github.com/afraznein/KTPAMXX](https://github.com/afraznein/KTPAMXX)
**Version:** 2.0.0
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

#### Extension Mode Initialization

```cpp
// Called by ReHLDS when loading extension
extern "C" DLLEXPORT void AMXX_RehldsExtensionInit() {
    g_bRehldsExtensionInit = true;
    g_bRunningWithMetamod = false;

    // Get engine interfaces directly from ReHLDS
    g_pGameEntityInterface = GetEntityInterface();

    // Register ReHLDS hooks
    RegisterHook(SV_DropClient, ...);
    RegisterHook(SV_ActivateServer, ...);
    RegisterHook(Cvar_DirectSet, ...);
    // ... more hooks

    // Initialize AMX subsystem
    AMXX_Initialize();
}
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

#### Example: Anti-Cheat Plugin

```pawn
public client_cvar_changed(id, const cvar[], const value[]) {
    if (!is_user_connected(id))
        return PLUGIN_CONTINUE

    // Enforce r_fullbright = 0
    if (equal(cvar, "r_fullbright") && floatstr(value) != 0.0) {
        client_cmd(id, "r_fullbright 0")
        log_amx("Enforced r_fullbright on player %d", id)
    }

    return PLUGIN_CONTINUE
}
```

#### Detection Architecture

```
┌─────────────────────────────────────────────────┐
│  AMX Plugin                                     │
│  - query_client_cvar(id, "r_fullbright", ...)   │
└────────────────┬────────────────────────────────┘
                 │ svc_sendcvarvalue2
                 ↓
┌─────────────────────────────────────────────────┐
│  Game Client                                    │
│  - Receives query, sends back value             │
└────────────────┬────────────────────────────────┘
                 │ clc_cvarvalue2
                 ↓
┌─────────────────────────────────────────────────┐
│  KTP-ReHLDS                                     │
│  - Calls pfnClientCvarChanged                   │
└────────────────┬────────────────────────────────┘
                 │ C++ callback
                 ↓
┌─────────────────────────────────────────────────┐
│  KTPAMXX                                        │
│  - Fires client_cvar_changed() forward          │
└────────────────┬────────────────────────────────┘
                 │ AMXX Forward
                 ↓
┌─────────────────────────────────────────────────┐
│  KTPCvarChecker Plugin                          │
│  - Validates and enforces correct value         │
└─────────────────────────────────────────────────┘
```

</details>

<details>
<summary><b>🔌 Module Frame Callback API</b></summary>

#### For Modules Requiring Per-Frame Processing

Modules like KTP AMXX Curl need per-frame callbacks for async I/O. Traditionally this required Metamod's `pfnStartFrame`. KTPAMXX provides a replacement:

```cpp
// Module registration (in module code)
MF_RegModuleFrameFunc(CurlFrameCallback);    // Register callback
MF_UnregModuleFrameFunc(CurlFrameCallback);  // Unregister on detach
```

```cpp
// KTPAMXX calls registered callbacks each frame
void KTPAMXX_FrameUpdate() {
    for (auto callback : g_ModuleFrameCallbacks) {
        callback();
    }
}
```

**Used By:**
- KTP AMXX Curl (async HTTP/FTP processing)
- Any module needing per-frame updates without Metamod

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
│   └── discord.ini
├── data/
├── logs/
├── modules/
│   ├── reapi_amxx.dll (KTP-ReAPI)
│   └── amxxcurl_amxx_i386.dll (KTP AMXX Curl)
├── plugins/
│   ├── KTPMatchHandler.amxx
│   ├── ktp_cvar.amxx
│   ├── ktp_file.amxx
│   └── KTPAdminAudit.amxx
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

#### Hook Registration Changes

| Traditional (Metamod)    | Extension Mode                  |
|--------------------------|---------------------------------|
| `ServerActivate_Post`    | `SV_ActivateServer` hookchain   |
| `OnFreeEntPrivateData`   | `ED_Free` hookchain             |
| Uses Metamod DLL hooks   | Uses ReHLDS hookchains          |

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

#### Standard ReAPI Features (Inherited)

All standard ReAPI functionality works:

```pawn
// Pause control
rh_set_server_pause(true);    // Freeze game
rh_set_server_pause(false);   // Resume game
rh_is_server_paused();        // Check state

// Cvar detection
RegisterHookChain(RH_SV_CheckUserInfo, "OnUserInfoChange", false);

// All ReGameDLL hooks
RegisterHookChain(RG_CBasePlayer_Spawn, ...);
RegisterHookChain(RG_CBasePlayer_TakeDamage, ...);
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

void OnPluginsUnloaded() {
    // KTP: Unregister frame callback
    if (MF_UnregModuleFrameFunc)
        MF_UnregModuleFrameFunc(CurlFrameCallback);
}

// Called every frame by KTPAMXX
void CurlFrameCallback() {
    // Process pending curl transfers
    curl_multi_perform(g_curlMulti, &running);
    // Handle completions, fire callbacks
}
```

#### Architecture

```
┌─────────────────────────────────────────────────┐
│  AMX Plugin                                     │
│  - curl_easy_perform(curl, "on_complete")       │
│  - Continues execution immediately              │
└────────────────┬────────────────────────────────┘
                 │ Native call
                 ↓
┌─────────────────────────────────────────────────┐
│  KTP AMXX Curl Module                           │
│  - Queues transfer with curl_multi              │
│  - ASIO polls for socket activity               │
│  - CurlFrameCallback() called each frame        │
└────────────────┬────────────────────────────────┘
                 │ MF_RegModuleFrameFunc (KTPAMXX)
                 ↓
┌─────────────────────────────────────────────────┐
│  KTPAMXX                                        │
│  - Calls registered frame callbacks each frame  │
└────────────────┬────────────────────────────────┘
                 │ On transfer complete
                 ↓
┌─────────────────────────────────────────────────┐
│  AMX Plugin Callback                            │
│  - on_complete(CURL:curl, CURLcode:code)        │
└─────────────────────────────────────────────────┘
```

</details>

<details>
<summary><b>📡 API Reference</b></summary>

#### Core Functions

```pawn
native CURL:curl_easy_init();
native curl_easy_perform(const CURL:handle, const callback[], const data[] = {}, const len = 0);
native CURLcode:curl_easy_setopt(const CURL:handle, const CURLoption:option, any:...);
native CURLcode:curl_easy_getinfo(const CURL:handle, const CURLINFO:info, any:...);
native curl_easy_cleanup(const CURL:handle);
native curl_easy_reset(const CURL:handle);
native curl_easy_escape(const CURL:handle, const url[], buffer[], const maxlen);
native curl_easy_unescape(const CURL:handle, const url[], buffer[], const maxlen);
native curl_slist:curl_slist_append(curl_slist:list, string[]);
native curl_slist_free_all(curl_slist:list);
native curl_easy_strerror(const CURLcode:code, buffer[], const maxlen);
native curl_version(buffer[], const maxlen);
```

#### Example: Discord Webhook

```pawn
public send_discord_webhook(const message[]) {
    new CURL:curl = curl_easy_init()
    if (!curl) return

    new curl_slist:headers = curl_slist_append(SList_Empty, "Content-Type: application/json")

    new json[512]
    formatex(json, charsmax(json), "{\"content\": \"%s\"}", message)

    curl_easy_setopt(curl, CURLOPT_URL, "https://discord.com/api/webhooks/...")
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers)
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json)
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0)

    curl_easy_perform(curl, "on_webhook_complete")
    curl_slist_free_all(headers)
}

public on_webhook_complete(CURL:curl, CURLcode:code) {
    if (code != CURLE_OK) {
        new error[128]
        curl_easy_strerror(code, error, charsmax(error))
        log_amx("Discord webhook failed: %s", error)
    }
    curl_easy_cleanup(curl)
}
```

</details>

---

### Layer 5: Application Plugins

#### KTPMatchHandler

**Repository:** [github.com/afraznein/KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)
**Version:** 0.5.2
**License:** MIT

<details>
<summary><b>🏆 Match Workflow System</b></summary>

```
1. PRE-START
   /start → Both teams /confirm (one captain per team)

2. PENDING (Ready-Up)
   Players type /ready (6 per team by default)

3. LIVE COUNTDOWN
   "Match starting in 5..."

4. MATCH LIVE
   Map config auto-executes
   Pause system active
   Full logging enabled
```

#### Match Types

| Type        | Command   | Discord            | Config               |
|-------------|-----------|--------------------|----------------------|
| Competitive | `/start`  | Full notifications | `mapname.cfg`        |
| 12-Man      | `/12man`  | Reduced            | `mapname_12man.cfg`  |
| Scrim       | `/scrim`  | Minimal            | `mapname_scrim.cfg`  |

</details>

<details>
<summary><b>⏸️ Advanced Pause System</b></summary>

#### Two Pause Types

| Type          | Limit           | Duration    | Extensions             | Command   |
|---------------|-----------------|-------------|------------------------|-----------|
| **Tactical**  | 1 per team/half | 5 minutes   | 2× 2 min (9 min max)   | `/pause`  |
| **Technical** | Unlimited       | Uses budget | Unlimited              | `/tech`   |

**Technical Pause Budget:** 5 minutes per team total

#### Pause Flow

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

#### Disconnect Auto-Pause

- Triggers when player disconnects during live match
- 10-second countdown (cancellable with `/cancelpause`)
- Uses team's technical pause budget
- Team-only cancel permission

</details>

---

#### KTPCvarChecker

**Repository:** [github.com/afraznein/KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)
**Version:** 7.4
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

#### Detection Architecture

```
┌─────────────────────────────────────────────────┐
│  KTPCvarChecker Plugin                          │
│  - Priority queries every 2 seconds (9 cvars)   │
│  - Standard rotation every 10s (5 cvars/check)  │
│  - query_client_cvar() triggers detection       │
└────────────────┬────────────────────────────────┘
                 │ Query + Response
                 ↓
┌─────────────────────────────────────────────────┐
│  KTPAMXX client_cvar_changed Forward            │
│  - Rate limiting (1 check/sec per player)       │
│  - Validation against whitelist                 │
│  - Auto-correction via client_cmd              │
│  - Logging + Discord webhook                    │
└─────────────────────────────────────────────────┘
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

**Repository:** [github.com/afraznein/KTPFileChecker](https://github.com/afraznein/KTPFileChecker) (Private)
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

#### Detection Flow

```
Player connects → Engine checks file hashes →
Mismatch detected → inconsistent_file() callback →
Plugin logs violation → Server announcement →
Admin can take action
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

#### Discord Configuration

```ini
# discord.ini
discord_channel_id_audit_competitive=1111111111111111111
discord_channel_id_audit_12man=2222222222222222222
discord_channel_id_audit_scrim=3333333333333333333
```

**Sends to ALL configured audit channels** - useful for mirroring to multiple Discord servers.

</details>

---

### Supporting Infrastructure

#### Discord Relay

**Repository:** [github.com/afraznein/discord-relay](https://github.com/afraznein/discord-relay)
**Platform:** Google Cloud Run
**License:** MIT

<details>
<summary><b>🔔 HTTP Relay Architecture</b></summary>

```
┌─────────────────────────┐
│  KTP Match Handler      │
│  (AMX Plugin via cURL)  │
└────────┬────────────────┘
         │ HTTPS + X-Relay-Auth
         ↓
┌─────────────────────────┐      ┌─────────────────────────┐
│  Discord Relay          │ ←──→ │  Discord API V10        │
│  (Cloud Run)            │      │                         │
│  - Auth validation      │      │                         │
│  - Retry logic          │      │                         │
│  - Rate limiting        │      │                         │
└─────────────────────────┘      └─────────────────────────┘
```

**Why Use a Relay:**
- ✅ Hides Discord webhook URL from game server
- ✅ Handles rate limiting with retry logic
- ✅ Centralized auth secret management
- ✅ Works around Cloudflare challenges
- ✅ Scales to zero when not in use

</details>

---

#### KTP HLSDK

**Repository:** [github.com/afraznein/KTPhlsdk](https://github.com/afraznein/KTPhlsdk)
**License:** Valve HL1 SDK License

<details>
<summary><b>📚 SDK Header Modifications</b></summary>

#### Added Callback: `pfnClientCvarChanged`

```cpp
// engine/eiface.h - NEW_DLL_FUNCTIONS structure
typedef struct {
    // ... existing functions ...

    // KTP Addition: Client cvar change callback
    void (*pfnClientCvarChanged)(const edict_t *pEdict, const char *cvar, const char *value);

} NEW_DLL_FUNCTIONS;
```

**Purpose:**
- Required for KTP-ReHLDS to compile with callback support
- Required for KTPAMXX to receive cvar change events
- Header-only SDK (no compilation needed)
- Fully backwards compatible

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

### Step 3: Install KTP-ReAPI Module

```bash
# Download KTP-ReAPI from releases
# https://github.com/afraznein/KTPReAPI/releases

# Install module
# Windows:
copy reapi_amxx.dll <game>\addons\ktpamx\modules\
# Linux:
cp reapi_amxx_i386.so <game>/addons/ktpamx/modules/

# Enable in modules.ini
# addons/ktpamx/configs/modules.ini:
reapi_amxx.dll     ; Windows
; OR
reapi_amxx_i386.so ; Linux
```

---

### Step 4: Install KTP AMXX Curl Module

```bash
# Download KTP AMXX Curl from releases
# https://github.com/afraznein/KTPAMXXCurl/releases

# Install module
# Windows:
copy amxxcurl_amxx_i386.dll <game>\addons\ktpamx\modules\
# Linux:
cp amxxcurl_amxx_i386.so <game>/addons/ktpamx/modules/

# Enable in modules.ini
amxxcurl_amxx_i386.dll  ; Windows
; OR
amxxcurl_amxx_i386.so   ; Linux
```

---

### Step 5: Install Plugins

```bash
# Compile plugins
cd addons/ktpamx/scripting
./amxxpc KTPMatchHandler.sma -oKTPMatchHandler.amxx
./amxxpc ktp_cvar.sma -oktp_cvar.amxx
./amxxpc ktp_file.sma -oktp_file.amxx
./amxxpc KTPAdminAudit.sma -oKTPAdminAudit.amxx

# Install plugins
cp *.amxx ../plugins/

# Enable in plugins.ini (order matters)
# addons/ktpamx/configs/plugins.ini:
ktp_cvar.amxx
ktp_file.amxx
KTPAdminAudit.amxx
KTPMatchHandler.amxx
```

---

### Step 6: Configure Server

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

#### discord.ini

```ini
discord_relay_url=https://your-relay.run.app/reply
discord_channel_id=1234567890123456789
discord_auth_secret=your-secret-here

; Optional: Match-type specific channels
discord_channel_id_competitive=1111111111111111111
discord_channel_id_12man=2222222222222222222
discord_channel_id_audit_competitive=3333333333333333333
```

---

### Step 7: Verify Installation

```bash
# Start server
./hlds_run -game dod +maxplayers 16 +map dod_avalanche

# Check console output:
# KTP AMX v2.0.0 loaded
# Core mode: JIT+ASM32
# Running as: ReHLDS Extension

# Check modules loaded:
amxx modules

# Check plugins loaded:
amxx list

# Test pause system:
# Join server, type /pause
# Should see countdown and real-time HUD
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

---

## 🎮 Command Reference

### Match Control

| Command          | Description              |
|------------------|--------------------------|
| `/start`, `/ktp` | Initiate match workflow  |
| `/12man`         | Start 12-man match       |
| `/scrim`         | Start scrim match        |
| `/confirm`       | Confirm team ready       |
| `/ready`         | Mark yourself ready      |
| `/notready`      | Mark yourself not ready  |
| `/status`        | View match status        |
| `/cancel`        | Cancel match/pre-start   |

### Pause Control

| Command           | Description               | Access        |
|-------------------|---------------------------|---------------|
| `/pause`          | Tactical pause            | Anyone        |
| `/tech`           | Technical pause           | Anyone        |
| `/resume`         | Request unpause           | Owner team    |
| `/confirmunpause` | Confirm unpause           | Other team    |
| `/extend`         | Extend pause +2 min       | Anyone        |
| `/cancelpause`    | Cancel disconnect pause   | Affected team |

### Admin Commands

| Command        | Description              |
|----------------|--------------------------|
| `/reloadmaps`  | Reload map configuration |
| `/ktpconfig`   | View current CVARs       |
| `/ktpdebug`    | Toggle debug mode        |
| `/cvar`        | Manual cvar check        |

---

## 🔗 GitHub Repositories

### KTP Core Stack

| Layer    | Repository                                              | Description                        |
|----------|---------------------------------------------------------|------------------------------------|
| Engine   | [KTP-ReHLDS](https://github.com/afraznein/KTPReHLDS)    | Custom ReHLDS with extension loader|
| SDK      | [KTP HLSDK](https://github.com/afraznein/KTPhlsdk)      | SDK headers with callback support  |
| Platform | [KTPAMXX](https://github.com/afraznein/KTPAMXX)         | AMX Mod X extension mode fork      |
| Bridge   | [KTP-ReAPI](https://github.com/afraznein/KTPReAPI)      | ReAPI extension mode fork          |
| HTTP     | [KTP AMXX Curl](https://github.com/afraznein/KTPAMXXCurl)| Non-blocking HTTP module          |

### Application Plugins

| Plugin        | Repository                                                      | Description                   |
|---------------|-----------------------------------------------------------------|-------------------------------|
| Match Handler | [KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler) | Match workflow + pause system |
| Cvar Checker  | [KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)   | Client cvar enforcement       |
| File Checker  | [KTPFileChecker](https://github.com/afraznein/KTPFileChecker)   | File consistency (Private)    |
| Admin Audit   | [KTPAdminAudit](https://github.com/afraznein/KTPAdminAudit)     | Admin action logging          |

### Supporting Infrastructure

| Service       | Repository                                                  | Description               |
|---------------|-------------------------------------------------------------|---------------------------|
| Discord Relay | [discord-relay](https://github.com/afraznein/discord-relay) | Cloud Run webhook proxy   |
| HLTV Kicker   | [KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)  | HLTV spectator management |

### Upstream Projects

| Project   | Repository                                         | Description                 |
|-----------|----------------------------------------------------|-----------------------------|
| ReHLDS    | [rehlds](https://github.com/dreamstalker/rehlds)   | Original ReHLDS             |
| ReAPI     | [reapi](https://github.com/s1lentq/reapi)          | Original ReAPI module       |
| AMX Mod X | [amxmodx](https://github.com/alliedmodders/amxmodx)| Original scripting platform |
| AmxxCurl  | [AmxxCurl](https://github.com/Polarhigh/AmxxCurl)  | Original cURL module        |

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

*No Metamod Required • Real-time Pause Controls • Instant Anti-Cheat • Discord Integration*

*Cross-platform: Windows + Linux*

</div>
