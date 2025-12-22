# KTP Competitive Infrastructure - Technical Guide

<div align="center">

**The Ultimate Day of Defeat Competitive Server Stack**

[![License](https://img.shields.io/badge/license-Mixed-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![Engine](https://img.shields.io/badge/engine-GoldSrc%20%7C%20Half--Life-orange.svg)]()
[![Game](https://img.shields.io/badge/game-Day%20of%20Defeat-green.svg)]()

*A comprehensive ecosystem of custom engine modifications, extension modules, match management plugins, and supporting services designed for competitive 6v6 Day of Defeat gameplay*

**No Metamod Required** - Runs on Linux and Windows via ReHLDS Extension Mode

**Last Updated:** 2025-12-22

[Architecture](#-six-layer-architecture) • [Components](#-component-documentation) • [Installation](#-complete-installation-guide) • [Repositories](#-github-repositories)

</div>

---

## 📦 Six-Layer Architecture

The KTP stack eliminates Metamod dependency through a custom extension loading architecture. KTPAMXX loads directly as a ReHLDS extension, and modules like KTP-ReAPI interface through KTPAMXX's module API instead of Metamod hooks.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 6: Application Plugins (AMX Plugins)                                  │
│  KTPMatchHandler v0.9.16 - Match workflow, pause system, HLStatsX integration│
│  KTPCvarChecker v7.7     - Real-time cvar enforcement                        │
│  KTPFileChecker v2.1     - File consistency validation + Discord             │
│  KTPAdminAudit v2.1.0    - Menu-based kick/ban with audit logging            │
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
│  KTPAMXX v2.6.0 - AMX Mod X fork with extension mode + HLStatsX integration  │
│  Loads as ReHLDS extension, no Metamod required                              │
│  Provides: client_cvar_changed forward, MF_RegModuleFrameFunc()              │
│  New: ktp_drop_client native, ktp_discord.inc shared integration             │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ ReHLDS Extension API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 1: Game Engine (KTP-ReHLDS v3.19.0+)                                  │
│  Custom ReHLDS fork with extension loader + KTP features                     │
│  Provides: SV_UpdatePausedHUD hook, pfnClientCvarChanged callback            │
│  Blocked: kick, banid, removeid, addip, removeip (use .kick/.ban instead)    │
│  Extension hooks: SV_ClientCommand, SV_InactivateClients, AlertMessage,      │
│                   PF_TraceLine, PF_SetClientKeyValue, SV_PlayerRunPreThink   │
└─────────────────────────────────────────────────────────────────────────────┘

                         Supporting Infrastructure:
┌─────────────────────────────────────────────────────────────────────────────┐
│  Cloud Services:                                                             │
│  - Discord Relay v1.0.1     - HTTP proxy for Discord webhooks (Cloud Run)   │
│  - KTPHLStatsX v0.1.0       - Modified HLStatsX daemon with match tracking   │
│                                                                              │
│  VPS Services:                                                               │
│  - KTPFileDistributor       - .NET 8 file sync daemon (SFTP distribution)   │
│  - KTPHLTVKicker v5.9       - Java HLTV spectator management                │
│                                                                              │
│  SDK Layer:                                                                  │
│  - KTP HLSDK v1.0.0         - pfnClientCvarChanged callback headers          │
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

<details>
<summary><b>🔧 Extension Mode: How It Replaces Metamod</b></summary>

#### The Problem Metamod Solves

Metamod exists because the GoldSrc engine has a single "game DLL" slot. Without Metamod:
- Engine loads ONE game DLL (e.g., `dod.dll`)
- No way to inject additional code
- No hooks, no plugins, no AMX Mod X

Metamod intercepts this by pretending to be the game DLL, then loading the real game DLL plus plugins.

#### What KTP Extension Mode Does Instead

KTP-ReHLDS adds an **extension loading system** that runs parallel to the game DLL:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KTP-ReHLDS Engine                                    │
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │  Game DLL Slot  │    │ Extension Slot 1│    │ Extension Slot 2│   ...    │
│  │    (dod.dll)    │    │   (ktpamx.dll)  │    │  (future use)   │          │
│  └────────┬────────┘    └────────┬────────┘    └─────────────────┘          │
│           │                      │                                           │
│           │    ┌─────────────────┴─────────────────┐                        │
│           │    │       ReHLDS Hookchain API        │                        │
│           │    │  (SV_ClientCommand, AlertMessage, │                        │
│           │    │   SV_DropClient, TraceLine, etc.) │                        │
│           │    └───────────────────────────────────┘                        │
│           │                      │                                           │
│           ▼                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐        │
│  │                    Engine Core (sv_main.cpp)                     │        │
│  │  - Calls hookchains at key points                                │        │
│  │  - Extensions can intercept/modify behavior                      │        │
│  │  - Game DLL runs normally, unaware of extensions                 │        │
│  └─────────────────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Extension Loading Sequence

**1. Engine Startup (`Sys_InitGame`)**
```cpp
// KTP-ReHLDS loads extensions from rehlds/extensions.ini
void LoadExtensions() {
    // Parse extensions.ini
    // For each extension DLL:
    LoadLibrary("ktpamx.dll");

    // Call extension entry point
    AMXX_RehldsExtensionInit();
}
```

**2. Extension Initialization**
```cpp
// In KTPAMXX's extension entry point
extern "C" DLLEXPORT void AMXX_RehldsExtensionInit() {
    // Get ReHLDS API
    g_RehldsApi = GetRehldsApi();
    g_RehldsFuncs = g_RehldsApi->GetFuncs();
    g_RehldsHookchains = g_RehldsApi->GetHookchains();

    // Register for engine events via hookchains
    g_RehldsHookchains->SV_DropClient()->registerHook(&OnClientDisconnect);
    g_RehldsHookchains->SV_ClientCommand()->registerHook(&OnClientCommand);
    g_RehldsHookchains->SV_ActivateServer()->registerHook(&OnServerActivate);
    // ... etc

    // Store engine pointers for module use
    g_pEngineFuncs = g_RehldsFuncs->GetEngineFuncs();
    g_pGlobalVars = g_RehldsFuncs->GetGlobalVars();
}
```

**3. Game DLL Loads Normally**
```cpp
// Engine loads dod.dll via standard GiveFnptrsToDll
// DoD receives ORIGINAL engine functions
// No Metamod wrapper in the chain
// Wall penetration works correctly
```

#### What Extensions Can Do (That Metamod Did)

| Metamod Capability | Extension Mode Equivalent |
|-------------------|---------------------------|
| Hook engine functions | ReHLDS hookchains |
| Hook game DLL functions | ReHLDS hookchains (limited) |
| Load plugins | KTPAMXX module system |
| Intercept messages | `PF_RegUserMsg_I` hookchain |
| Modify client commands | `SV_ClientCommand` hookchain |
| Track connections | `ClientConnected` hookchain |

#### Linux Support: Why Extension Mode Matters

**The Linux Problem:**
- Linux game servers need plugins for competitive play
- AMX Mod X on Linux traditionally requires Metamod
- Metamod + ReHLDS + DoD = broken wall penetration
- **Result:** No viable Linux competitive servers

**The Extension Mode Solution:**
- KTPAMXX loads as ReHLDS extension (no Metamod)
- ReHLDS provides all necessary hookchains
- DoD loads directly (no wrapper DLL)
- **Result:** Full Linux support with working gameplay

```bash
# Linux server setup (extension mode)
rehlds/
├── hlds_linux
├── engine_i486.so          # KTP-ReHLDS engine
├── dod/
│   ├── dlls/
│   │   └── dod.so          # Original game DLL (no wrapper!)
│   └── addons/
│       └── ktpamx/
│           ├── dlls/
│           │   └── ktpamx_i386.so   # Loaded as extension
│           └── modules/
│               ├── reapi_ktp_i386.so
│               └── dodx_ktp_i386.so
└── rehlds/
    └── extensions.ini      # Lists ktpamx_i386.so
```

</details>

---

## 🔧 Component Documentation

### Layer 1: KTP-ReHLDS (Engine)

**Repository:** [github.com/afraznein/KTPReHLDS](https://github.com/afraznein/KTPReHLDS)
**Version:** 3.19.0+
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

### KTP HLSDK (SDK Layer)

**Repository:** [github.com/afraznein/KTPhlsdk](https://github.com/afraznein/KTPhlsdk)
**Version:** 1.0.0
**License:** Valve Half-Life 1 SDK License (non-commercial)
**Base:** Half-Life 1 SDK by Valve

<details>
<summary><b>🎯 pfnClientCvarChanged Callback</b></summary>

#### The Missing Callback

Standard Half-Life SDK does not expose client cvar query responses to game DLLs or plugins. When a server queries a client's cvar value, the response arrives at the engine but there's no standard way to notify plugins.

**The KTP HLSDK Solution:**

Added `pfnClientCvarChanged` callback to `NEW_DLL_FUNCTIONS` structure:

```cpp
// engine/eiface.h - KTP modification
typedef struct
{
    // ... existing functions ...

    // KTP Addition: Client cvar change callback
    void (*pfnClientCvarChanged)(const edict_t *pEdict, const char *cvar, const char *value);

} NEW_DLL_FUNCTIONS;
```

#### Data Flow

```
┌─────────────────────────────────────┐
│  Game Client                        │
│  - Server queries cvar              │
│  - Client responds with value       │
└────────────────┬────────────────────┘
                 │ Network packet
                 ↓
┌─────────────────────────────────────┐
│  KTP-ReHLDS (Modified Engine)       │
│  - Uses NEW_DLL_FUNCTIONS           │
│  - Calls pfnClientCvarChanged       │
└────────────────┬────────────────────┘
                 │ Callback
                 ↓
┌─────────────────────────────────────┐
│  KTPAMXX (Extension Mode)           │
│  - Receives callback                │
│  - Fires client_cvar_changed forward│
└────────────────┬────────────────────┘
                 │ Forward
                 ↓
┌─────────────────────────────────────┐
│  AMX Plugin (KTPCvarChecker)        │
│  - Validates cvar value             │
│  - Enforces correct value           │
└─────────────────────────────────────┘
```

#### Why This Matters

**Without this callback:**
- Cvar detection relies on periodic polling
- Players can change cvars between queries
- Detection delays of 15-90 seconds possible
- Sophisticated cheats can evade detection

**With pfnClientCvarChanged:**
- Real-time notification when client responds
- Sub-second detection (typically <2 seconds)
- No polling gaps to exploit
- Zero performance impact (callback-driven)

#### Engine Implementation

```cpp
// In KTP-ReHLDS, when client responds to cvar query:
void SV_ParseCvarValue(client_t *cl, sizebuf_t *msg) {
    const char* cvarName = MSG_ReadString(msg);
    const char* cvarValue = MSG_ReadString(msg);

    // KTP: Notify game DLL via callback
    if (gNewDLLFunctions.pfnClientCvarChanged) {
        edict_t* pEdict = EDICT_NUM(cl->id + 1);
        gNewDLLFunctions.pfnClientCvarChanged(pEdict, cvarName, cvarValue);
    }
}
```

#### Compatibility

| Component | Status | Notes |
|-----------|--------|-------|
| Standard HLDS | ❌ | Callback not called |
| ReHLDS (stock) | ❌ | Callback not called |
| KTP-ReHLDS | ✅ | Full support |
| Existing mods | ✅ | Callback is optional, backwards compatible |

</details>

---

### Layer 2: KTPAMXX (Scripting Platform)

**Repository:** [github.com/afraznein/KTPAMXX](https://github.com/afraznein/KTPAMXX)
**Version:** 2.6.0
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

#### The Module API Problem

In traditional AMX Mod X with Metamod:
- Modules use Metamod's `gpGlobals` and `g_engfuncs` directly
- Metamod provides these via its DLL interface
- Modules call `GET_HOOK_TABLES()` during `Meta_Query()`

In extension mode, there's no Metamod. KTPAMXX must provide these APIs itself.

#### New Module API Functions

```cpp
// amxxmodule.h - New exports for extension mode

// Get engine function table (replaces Metamod's g_engfuncs)
enginefuncs_t* MF_GetEngineFuncs();

// Get global variables (replaces Metamod's gpGlobals)
globalvars_t* MF_GetGlobalVars();

// Get user message ID by name (extension mode message tracking)
int MF_GetUserMsgId(const char* name);

// Register module message handler (for HUD messages, etc.)
void MF_RegModuleMsgHandler(int msgId, pfnMsgHandler handler);

// Register per-frame callback (replaces Metamod's StartFrame hook)
void MF_RegModuleFrameFunc(void (*callback)());

// Get ReHLDS API pointer (for modules needing hookchain access)
IRehldsApi* MF_GetRehldsApi();
```

#### How Modules Use It

```cpp
// In module's AMXX_Attach() or OnPluginsLoaded()
void OnAmxxAttach() {
    // Get engine access (would normally come from Metamod)
    g_engfuncs = MF_GetEngineFuncs();
    gpGlobals = MF_GetGlobalVars();

    if (!g_engfuncs || !gpGlobals) {
        MF_Log("ERROR: Engine functions not available");
        return;
    }

    // Now module can call engine functions
    g_engfuncs->pfnServerPrint("Module loaded!\n");
}
```

#### Module Compatibility Matrix

| Module | Extension Mode | Notes |
|--------|---------------|-------|
| **KTP-ReAPI** | ✅ Full | Uses `MF_GetEngineFuncs()`, registers ReHLDS hooks |
| **KTP AMXX Curl** | ✅ Full | Uses `MF_RegModuleFrameFunc()` for async |
| **DODX** | ✅ Full | Uses `MF_GetEngineFuncs()` + PreThink hookchain |
| **DODFun** | ✅ Full | Entity manipulation works |
| **SQLite** | ❌ Broken | Has Metamod-specific code paths |
| **MySQL** | ⚠️ Untested | May work, not verified |

</details>

<details>
<summary><b>🎮 KTP-Specific Natives (v2.6.0)</b></summary>

#### ktp_drop_client Native

Drops a client via ReHLDS API, bypassing blocked kick command:

```pawn
/**
 * Drop a client from the server via ReHLDS DropClient API.
 * Works even when kick console command is blocked at engine level.
 *
 * @param id        Client index (1-32)
 * @param reason    Disconnect reason shown to client (optional)
 * @return          1 on success, 0 if client not connected
 */
native ktp_drop_client(id, const reason[] = "");
```

**Implementation in KTPAMXX:**
```cpp
// In ktp_natives.cpp
static cell AMX_NATIVE_CALL ktp_drop_client(AMX *amx, cell *params) {
    int client = params[1];

    if (!MF_IsPlayerIngame(client))
        return 0;

    char reason[128];
    MF_GetAmxString(amx, params[2], 0, reason, sizeof(reason));

    // Call ReHLDS DropClient directly
    IGameClient* pClient = g_RehldsApi->GetClientByIndex(client - 1);
    if (pClient) {
        g_RehldsFuncs->DropClient(pClient, false, reason);
        return 1;
    }

    return 0;
}
```

**Why This Native Exists:**

KTP-ReHLDS blocks `kick`, `banid`, and related commands to prevent untraceable RCON kicks.
This native provides an audited alternative that:
1. Can only be called from plugins (not RCON)
2. Plugins can log who initiated the kick
3. Works with KTPAdminAudit for full accountability

</details>

<details>
<summary><b>📡 ktp_discord.inc - Shared Discord Integration (v2.6.0)</b></summary>

#### Purpose

Multiple KTP plugins need Discord integration:
- KTPMatchHandler (match notifications)
- KTPAdminAudit (kick/ban logging)
- KTPCvarChecker (violation alerts)
- KTPFileChecker (file inconsistencies)

Instead of each plugin loading its own config, `ktp_discord.inc` provides shared functionality.

#### Include File

```pawn
// ktp_discord.inc - Shared Discord integration for KTP plugins

// Color constants for embed messages
#define KTP_DISCORD_COLOR_GREEN   0x00FF00
#define KTP_DISCORD_COLOR_RED     0xFF0000
#define KTP_DISCORD_COLOR_ORANGE  0xFF8C00
#define KTP_DISCORD_COLOR_BLUE    0x0080FF

/**
 * Load Discord configuration from discord.ini
 * Call this in plugin_cfg()
 */
stock ktp_discord_load_config();

/**
 * Check if Discord integration is enabled
 * @return true if relay URL and auth are configured
 */
stock bool:ktp_discord_is_enabled();

/**
 * Send an embed message to all audit channels
 * Audit channels: discord_channel_id_audit*, discord_channel_id_admin
 *
 * @param title         Embed title
 * @param description   Embed body (supports ^n for newlines)
 * @param color         Embed color (use KTP_DISCORD_COLOR_* constants)
 */
stock ktp_discord_send_embed_audit(const title[], const description[], color);

/**
 * Send an embed message to a specific channel
 *
 * @param channel_id    Discord channel ID
 * @param title         Embed title
 * @param description   Embed body
 * @param color         Embed color
 */
stock ktp_discord_send_embed(const channel_id[], const title[], const description[], color);

/**
 * Get a specific channel ID from config
 *
 * @param key           Config key (e.g., "discord_channel_id_competitive")
 * @param output        Buffer for channel ID
 * @param maxlen        Buffer size
 * @return              true if found
 */
stock bool:ktp_discord_get_channel(const key[], output[], maxlen);
```

#### Configuration File (`discord.ini`)

```ini
; Discord Relay Configuration
; Path: <configsdir>/discord.ini

; Required: Relay server URL and authentication
discord_relay_url=https://your-relay.run.app/reply
discord_auth_secret=your-shared-secret-here

; Default channel for general notifications
discord_channel_id=1234567890123456789

; Match-type specific channels (for KTPMatchHandler)
discord_channel_id_competitive=1111111111111111111
discord_channel_id_12man=2222222222222222222
discord_channel_id_draft=3333333333333333333

; Audit channels (for KTPAdminAudit, KTPCvarChecker, KTPFileChecker)
; All channels matching "discord_channel_id_audit*" receive audit messages
discord_channel_id_audit_main=4444444444444444444
discord_channel_id_audit_backup=5555555555555555555
discord_channel_id_admin=6666666666666666666
```

#### Usage Example

```pawn
#include <amxmodx>
#include <ktp_discord>

public plugin_cfg() {
    ktp_discord_load_config();
}

public OnPlayerViolation(id, const cvar[], const value[]) {
    if (!ktp_discord_is_enabled())
        return;

    new name[32], steamid[35];
    get_user_name(id, name, charsmax(name));
    get_user_authid(id, steamid, charsmax(steamid));

    new description[256];
    formatex(description, charsmax(description),
        "**Player:** %s^n**SteamID:** %s^n**Cvar:** %s^n**Value:** %s",
        name, steamid, cvar, value);

    ktp_discord_send_embed_audit("Cvar Violation", description, KTP_DISCORD_COLOR_RED);
}
```

#### HTTP Request Format

The include sends requests to the Discord relay:

```json
{
    "channel_id": "1234567890123456789",
    "embeds": [{
        "title": "Cvar Violation",
        "description": "**Player:** Cheater\n**SteamID:** STEAM_0:1:12345\n**Cvar:** r_fullbright\n**Value:** 1",
        "color": 16711680
    }],
    "auth_secret": "your-shared-secret-here"
}
```

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
**Version:** 2.6.0
**Purpose:** Day of Defeat weapon stats, shot tracking, HLStatsX integration

<details>
<summary><b>🔧 DODX Extension Mode: The Complete Rewrite</b></summary>

#### Why DODX Needed Rewriting

Original DODX relied heavily on Metamod:
- Used Metamod's `pfnPlayerPreThink` hook for shot detection
- Called `gpGlobals` directly via Metamod
- Registered for `TraceLine` via Metamod hooks
- Used Metamod's `StartFrame` for entity cleanup

**In extension mode, none of these work.** DODX v2.4.0+ was completely rewritten.

#### New ReHLDS Hook Handlers

```cpp
// dodx_hooks.cpp - Extension mode hook registrations

void DODX_RegisterHooks() {
    // Player lifecycle
    g_RehldsHookchains->ClientConnected()->registerHook(&DODX_OnClientConnected);
    g_RehldsHookchains->SV_DropClient()->registerHook(&DODX_OnSV_DropClient);

    // Map changes (critical for preventing stale pointer crashes)
    g_RehldsHookchains->SV_InactivateClients()->registerHook(&DODX_OnChangelevel);

    // Stats tracking loop
    g_RehldsHookchains->SV_PlayerRunPreThink()->registerHook(&DODX_OnPlayerPreThink);

    // Hit detection and aiming statistics
    g_RehldsHookchains->PF_TraceLine()->registerHook(&DODX_OnTraceLine);

    // Client spawn handling
    g_RehldsHookchains->SV_Spawn_f()->registerHook(&DODX_OnSV_Spawn_f);
}
```

#### Shot Tracking: Button State Monitoring

Original DODX used weapon fire events. Extension mode monitors IN_ATTACK button state:

```cpp
void DODX_OnPlayerPreThink(IGameClient* client) {
    int id = client->GetId() + 1;
    edict_t* pEdict = MF_GetPlayerEdict(id);

    if (!pEdict || pEdict->free)
        return;

    // Get current button state
    int buttons = pEdict->v.button;
    int oldbuttons = pEdict->v.oldbuttons;

    // Detect IN_ATTACK rising edge (button just pressed)
    if ((buttons & IN_ATTACK) && !(oldbuttons & IN_ATTACK)) {
        // Get current weapon
        int weaponId = GetCurrentWeapon(pEdict);

        // Check fire rate delay (prevents counting held trigger as multiple shots)
        float curTime = gpGlobals->time;
        float lastShot = g_players[id].lastShotTime[weaponId];

        if (curTime - lastShot >= g_weaponFireRates[weaponId]) {
            g_players[id].shots[weaponId]++;
            g_players[id].lastShotTime[weaponId] = curTime;
        }
    }
}
```

**Fire Rate Delays by Weapon:**

| Weapon Category | Delay | Examples |
|----------------|-------|----------|
| Machine Guns | 0.05s | MG42, MG34, .30 Cal |
| SMGs | 0.10s | MP40, Thompson, Sten |
| Semi-Auto Rifles | 0.50s | Garand, K43, Carbine |
| Bolt-Action | 1.00s | Kar98, Springfield, Enfield |
| Pistols | 0.20s | Colt, Luger, Webley |

#### Safety Hardening

Extension mode required extensive safety checks:

```cpp
// ENTINDEX_SAFE: Uses pointer arithmetic instead of engine calls
inline int ENTINDEX_SAFE(edict_t* pEdict) {
    if (!pEdict) return 0;
    if (!g_pEdicts) return 0;
    return ((int)pEdict - (int)g_pEdicts) / sizeof(edict_t);
}

// g_bServerActive: Prevents processing during map changes
bool g_bServerActive = false;

void DODX_OnChangelevel() {
    g_bServerActive = false;  // Stop all processing
    // Flush any pending stats
    FlushAllStats();
}

void DODX_OnServerActivate() {
    g_bServerActive = true;   // Resume processing
}

// CHECK_PLAYER: Rewritten to use players[] array directly
#define CHECK_PLAYER(id) \
    if (id < 1 || id > gpGlobals->maxClients) return 0; \
    if (!g_players[id].connected) return 0; \
    if (g_players[id].pEdict->free) return 0;
```

</details>

<details>
<summary><b>📊 HLStatsX Integration Natives (v2.5.0+)</b></summary>

#### Stats Separation: Warmup vs Match

The key innovation is separating warmup kills from match kills:

```pawn
// Flush all player stats to log (for warmup → match transition)
// Stats are logged WITHOUT match_id, then cleared
native dodx_flush_all_stats();

// Reset all player stats (clear counters without logging)
native dodx_reset_all_stats();

// Set match ID for correlation with HLStatsX
// All subsequent log lines will include this ID
native dodx_set_match_id(const matchId[]);

// Get current match ID
native dodx_get_match_id(output[], maxlen);

// Set player's team name in private data
native dodx_set_pl_teamname(id, const szName[]);
```

#### Match Workflow Integration

```pawn
// In KTPMatchHandler - when match goes LIVE
public OnMatchStart() {
    // 1. Flush warmup stats (logged without match_id)
    dodx_flush_all_stats();

    // 2. Clear all counters for fresh start
    dodx_reset_all_stats();

    // 3. Set match context for HLStatsX
    new matchId[64];
    formatex(matchId, charsmax(matchId), "KTP-%d-%s", get_systime(), g_szMapName);
    dodx_set_match_id(matchId);

    // From now on, all kills/deaths logged with match_id
}

public OnMatchEnd() {
    // Flush match stats (logged WITH match_id)
    dodx_flush_all_stats();

    // Clear match context
    dodx_set_match_id("");
}
```

#### Log Line Format

**Without match_id (warmup):**
```
"Player<uid><STEAM_ID><Allies>" triggered "weaponstats" (weapon "garand") (shots "15") (hits "8") (kills "2") (headshots "1") (tks "0") (damage "312") (deaths "1") (score "4")
```

**With match_id (during match):**
```
"Player<uid><STEAM_ID><Allies>" triggered "weaponstats" (weapon "garand") (shots "15") (hits "8") (kills "2") (headshots "1") (tks "0") (damage "312") (deaths "1") (score "4") (matchid "KTP-1734355200-dod_charlie")
```

#### New Forward

```pawn
/**
 * Called for each player when stats are flushed.
 * Use this to perform additional logging or processing.
 *
 * @param id    Player index
 */
forward dod_stats_flush(id);
```

</details>

---

### Layer 6: Application Plugins

#### KTPMatchHandler

**Repository:** [github.com/afraznein/KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler)
**Version:** 0.9.16
**License:** MIT

<details>
<summary><b>🏆 Match Workflow System</b></summary>

```
1. PRE-START
   .ktp <password> → Both teams .confirm

2. PENDING (Ready-Up)
   Players type .ready (6 per team by default)
   Periodic reminders every 30 seconds
   .status to see match status

3. MATCH START
   - Match ID generated: KTP-{timestamp}-{mapname}
   - dodx_flush_all_stats() - flush warmup stats
   - dodx_reset_all_stats() - clear for fresh match
   - dodx_set_match_id() - set match context
   - KTP_MATCH_START logged for HLStatsX

4. LIVE COUNTDOWN
   "Match starting in 3..."

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

#### Match Types

| Type        | Command      | Password | Season Required | Config               |
|-------------|--------------|----------|-----------------|----------------------|
| Competitive | `.ktp`       | Required | Yes             | `mapname.cfg`        |
| Draft       | `.draft`     | None     | No              | `mapname.cfg`        |
| 12-Man      | `.12man`     | None     | No              | `mapname_12man.cfg`  |
| Scrim       | `.scrim`     | None     | No              | `mapname_scrim.cfg`  |

#### Season Control

Season status is configured via `ktp.ini`. When season is OFF, `.ktp` is disabled.
Draft, 12man, and scrim are always available regardless of season status.

#### Score Tracking (v0.8.0+)

- Tracks scores per half via TeamScore hook
- Persists across map changes via localinfo
- Discord match end shows final score with half breakdown

</details>

<details>
<summary><b>⏸️ Advanced Pause System</b></summary>

#### Two Pause Types

| Type          | Limit              | Duration    | Extensions             | Command   |
|---------------|--------------------|-------------|------------------------|-----------|
| **Tactical**  | 1 per team/match   | 5 minutes   | 2× 2 min (9 min max)   | `.pause`  |
| **Technical** | Unlimited          | Uses budget | Unlimited              | `.tech`   |

**Technical Pause Budget:** 5 minutes per team per match (persists across halves via localinfo)

#### Pause Flow with Real-Time HUD

```
Player types .pause
        ↓
3-second countdown ("Pausing in 3...")
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

  .resume  |  .go  |  .ext
```

</details>

---

#### KTPCvarChecker

**Repository:** [github.com/afraznein/KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)
**Version:** 7.7
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

**Repository:** [github.com/afraznein/KTPFileChecker](https://github.com/afraznein/KTPFileChecker)
**Version:** 2.1
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
**Version:** 2.1.0
**License:** MIT

<details>
<summary><b>🔐 Menu-Based Admin System</b></summary>

#### Features

- **Menu-based kick/ban** - Interactive player selection (no RCON needed)
- **Admin flag permissions** - Requires ADMIN_KICK (c) or ADMIN_BAN (d)
- **Immunity protection** - Players with ADMIN_IMMUNITY (a) cannot be kicked/banned
- **Ban duration selection** - 1 hour, 1 day, 1 week, or permanent
- **Discord audit logging** - Real-time notifications to configured channels
- **ReHLDS integration** - Uses `ktp_drop_client` native to bypass blocked kick command

#### Why ktp_drop_client?

KTP-ReHLDS blocks the `kick` console command to prevent untraceable RCON/HLSW kicks.
The `ktp_drop_client` native calls ReHLDS's `DropClient` API directly, bypassing the
blocked command while still going through the audited plugin system.

</details>

---

### Supporting Infrastructure

#### Discord Relay

**Repository:** [github.com/afraznein/discord-relay](https://github.com/afraznein/discord-relay)
**Version:** 1.0.1
**Platform:** Google Cloud Run (Node.js/Express)
**License:** MIT

<details>
<summary><b>🔔 HTTP Relay Architecture</b></summary>

#### Purpose

Game servers need to send notifications to Discord, but:
- Direct Discord API calls face Cloudflare challenges
- Exposing webhook URLs on game servers is insecure
- Rate limiting needs proper handling with retries
- Multiple services need Discord access (plugins, scripts)

The relay acts as a stateless, secure proxy between KTP services and Discord API V10.

#### Design Philosophy

**Stateless Operation:**
- Each request is independent/asynchronous
- No sessions or background processes
- Scales to zero automatically (cost-effective)

**Transparent Forwarding:**
- Minimal transformation of data
- All business logic lives in client applications
- Relay only handles auth, rate limits, and retries

#### Clients

```
┌─────────────────────────┐
│  KTP Match Handler      │
│  (AMX ModX Plugin)      │
│  - Pause events         │
│  - Match notifications  │
│  - Player disconnects   │
└────────┬────────────────┘
         │ HTTPS + X-Relay-Auth
         ↓
┌─────────────────────────┐      ┌─────────────────────────┐
│  KTP Discord Relay      │ ←──→ │  Discord API V10        │
│  (Cloud Run)            │      │  - Channels             │
│  - Auth validation      │      │  - Messages             │
│  - Request forwarding   │      │  - Reactions            │
│  - Retry logic          │      │                         │
└────────┬────────────────┘      └─────────────────────────┘
         ↑ HTTPS + X-Relay-Auth
┌────────┴────────────────┐         ┌─────────────────────────┐
│  KTP Score Parser       │         │  KTPScoreBot-           │
│  (Google Apps Script)   │         │  WeeklyMatches          │
│  - Match statistics     │         │  (Google Apps Script)   │
└─────────────────────────┘         │  - Weekly recaps        │
                                    │  - Leaderboards         │
                                    └─────────────────────────┘
```

#### API Endpoints

| Endpoint                    | Method | Purpose                          |
|-----------------------------|--------|----------------------------------|
| `/reply`                    | POST   | Send message to Discord channel  |
| `/edit`                     | POST   | Edit existing message            |
| `/delete/:channelId/:msgId` | DELETE | Delete message                   |
| `/react`                    | POST   | Add reaction to message          |
| `/reactions`                | GET    | List users who reacted           |
| `/messages`                 | GET    | Fetch recent messages            |
| `/message/:channelId/:msgId`| GET    | Fetch specific message           |
| `/channel/:channelId`       | GET    | Get channel information          |
| `/dm`                       | POST   | Send direct message to user      |
| `/health`                   | GET    | Health check                     |
| `/whoami`                   | GET    | Get bot identity (authenticated) |
| `/whoami-public`            | GET    | Get bot identity (public)        |
| `/httpcheck`                | GET    | Test Discord gateway connectivity|

#### Request Format

**Send message (POST /reply):**
```json
{
  "channelId": "1234567890123456789",
  "content": "Message text",
  "embeds": [{
    "title": "Match Started",
    "description": "Map: dod_charlie",
    "color": 65280
  }],
  "referenceMessageId": "987654321098765432"
}
```

**Authentication:**
- Header: `X-Relay-Auth: your-shared-secret`
- Validated against `RELAY_SHARED_SECRET` env var

#### Retry Logic

Built-in exponential backoff with Discord rate limit awareness:

```javascript
async function fetchWithRetries(url, options, maxRetries = 3) {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const response = await fetch(url, options);

    if (response.status === 429) {
      // Rate limited - honor Retry-After header
      const retryAfter = response.headers.get('Retry-After');
      await sleep(retryAfter * 1000);
      continue;
    }

    if (response.ok) return response;

    // Exponential backoff for other errors
    await sleep(Math.pow(2, attempt) * 1000);
  }
}
```

#### Deployment

```bash
gcloud run deploy ktp-relay \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "RELAY_SHARED_SECRET=xxx,DISCORD_BOT_TOKEN=xxx" \
  --memory 256Mi \
  --concurrency 80 \
  --timeout 30s
```

</details>

---

#### KTPHLStatsX

**Repository:** [github.com/afraznein/KTPHLStatsX](https://github.com/afraznein/KTPHLStatsX)
**Version:** 0.1.0
**Platform:** HLStatsX:CE Fork (Perl daemon + MySQL)
**License:** GPL v2
**Base:** HLStatsX:CE by NomisCZ

<details>
<summary><b>📊 Match-Based Statistics Tracking</b></summary>

#### The Problem

Standard HLStatsX tracks **all player activity** regardless of context:
- Warmup kills mixed with match kills
- Practice rounds counted in stats
- No way to query "stats from match X"
- Impossible to generate per-match leaderboards

#### Architecture Position

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 5: KTP HLStatsX Web (PHP) ← Future                   │
│  Match-aware leaderboards and statistics display            │
└─────────────────────────────────────────────────────────────┘
                     ↑ Reads from MySQL
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: KTP HLStatsX Daemon (Perl) ← THIS COMPONENT       │
│  - Processes KTP_MATCH_START/END events                     │
│  - Tags events with match_id                                │
│  - Stores match metadata                                    │
└─────────────────────────────────────────────────────────────┘
                     ↑ Receives log events via UDP
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: DODX Module (KTPAMXX)                             │
│  - Flushes stats on match end                               │
│  - Logs KTP_MATCH_START/END to server log                   │
└─────────────────────────────────────────────────────────────┘
                     ↑ Plugin natives
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: KTP Match Handler (AMX Plugin)                    │
│  - Triggers match start/end                                 │
│  - Generates unique match IDs                               │
│  - Calls dodx_set_match_id(), dodx_flush_all_stats()        │
└─────────────────────────────────────────────────────────────┘
```

#### Data Flow

```
WARMUP PHASE:
  Players join, practice
  Stats accumulate in DODX memory
  [Nothing logged to HLStatsX yet]

MATCH START (all players .ready):
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

#### KTP Event Handlers

**Event Type 600: KTP_MATCH_START**
```perl
sub doEvent_KTPMatchStart {
    my ($matchId, $mapName, $half) = @_;

    # Set match context for this server
    $g_ktpMatchContext{$s_addr} = {
        match_id => $matchId,
        map => $mapName,
        half => $half,
        start_time => time()
    };

    # Insert match record into database
    # INSERT INTO ktp_matches ...
}
```

**Event Type 601: KTP_MATCH_END**
```perl
sub doEvent_KTPMatchEnd {
    my ($matchId, $mapName) = @_;

    # Update match end time
    # UPDATE ktp_matches SET end_time = NOW() ...

    # Clear match context for this server
    delete $g_ktpMatchContext{$s_addr};
}
```

#### Log Event Format

**From KTP Match Handler:**
```
L 12/17/2025 - 14:30:00: KTP_MATCH_START (matchid "KTP-1734355200-dod_charlie") (map "dod_charlie") (half "1st")
L 12/17/2025 - 15:05:00: KTP_MATCH_END (matchid "KTP-1734355200-dod_charlie") (map "dod_charlie")
```

#### MySQL Schema

**Add match_id to existing event tables:**
```sql
ALTER TABLE hlstats_Events_Frags
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL AFTER map;

CREATE INDEX idx_match_id ON hlstats_Events_Frags (match_id);
```

**New KTP tables:**
```sql
-- Match metadata
CREATE TABLE ktp_matches (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    server_id INT NOT NULL,
    map_name VARCHAR(32) NOT NULL,
    half TINYINT DEFAULT 1,
    start_time DATETIME NOT NULL,
    end_time DATETIME DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_match_id_half (match_id, half)
);

-- Match participants
CREATE TABLE ktp_match_players (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    steam_id VARCHAR(32) NOT NULL,
    player_name VARCHAR(64) NOT NULL,
    team TINYINT NOT NULL,
    joined_at DATETIME NOT NULL,
    PRIMARY KEY (id)
);

-- Aggregated match stats
CREATE TABLE ktp_match_stats (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    kills INT DEFAULT 0,
    deaths INT DEFAULT 0,
    headshots INT DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uk_match_player (match_id, player_id)
);
```

#### SQL Views

**Match leaderboard with K/D ratio:**
```sql
CREATE VIEW ktp_match_leaderboard AS
SELECT
    m.match_id,
    m.map_name,
    m.start_time,
    p.lastName AS player_name,
    COALESCE(ms.kills, 0) AS kills,
    COALESCE(ms.deaths, 0) AS deaths,
    ROUND(COALESCE(ms.kills, 0) / NULLIF(ms.deaths, 0), 2) AS kd_ratio
FROM ktp_matches m
JOIN ktp_match_players mp ON m.match_id = mp.match_id
JOIN hlstats_Players p ON mp.player_id = p.playerId
LEFT JOIN ktp_match_stats ms ON m.match_id = ms.match_id
ORDER BY m.start_time DESC, ms.kills DESC;
```

#### Sample Queries

**Count match vs non-match kills:**
```sql
SELECT
    CASE WHEN match_id IS NULL THEN 'Warmup/Practice' ELSE 'Match' END AS type,
    COUNT(*) AS kill_count
FROM hlstats_Events_Frags
WHERE eventTime > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY (match_id IS NULL);
```

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

When plugins are compiled on the build server, they need to be deployed to multiple game servers. Manual copying is error-prone and time-consuming.

KTPFileDistributor automatically:
1. Watches for new/modified files
2. Debounces rapid changes
3. Distributes via SFTP to all configured servers
4. Notifies Discord on success/failure

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Build Server                                                │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  WSL Compiler   │ →  │  /opt/ktp/build/*.amxx          │ │
│  │  (compile.bat)  │    │  (FileSystemWatcher monitors)    │ │
│  └─────────────────┘    └─────────────┬───────────────────┘ │
└───────────────────────────────────────┼─────────────────────┘
                                        │ File changed
                                        ↓
┌─────────────────────────────────────────────────────────────┐
│  KTPFileDistributor (.NET 8 Worker Service)                  │
│  - Debounce (5s default)                                     │
│  - SSH.NET SFTP client                                       │
│  - Multi-server parallel distribution                        │
└───────────────┬─────────────────────┬───────────────────────┘
                │ SFTP                │ SFTP
                ↓                     ↓
┌───────────────────────┐   ┌───────────────────────┐
│  KTP NY Server        │   │  KTP CHI Server       │   ...
│  /home/ktp/dod/       │   │  /home/ktp/dod/       │
│  addons/ktpamx/       │   │  addons/ktpamx/       │
│  plugins/             │   │  plugins/             │
└───────────────────────┘   └───────────────────────┘
                │
                ↓ Discord notification
┌───────────────────────┐
│  Discord Channel      │
│  "✅ KTPMatchHandler   │
│   deployed to 5       │
│   servers"            │
└───────────────────────┘
```

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
    },
    {
      "Name": "KTP CHI",
      "Host": "chi.example.com",
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

#### Systemd Service

```ini
# /etc/systemd/system/ktp-distributor.service
[Unit]
Description=KTP File Distributor
After=network.target

[Service]
Type=notify
ExecStart=/opt/ktp/distributor/KTPFileDistributor
WorkingDirectory=/opt/ktp/distributor
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
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

HLTV spectator bots consume player slots on game servers. They're used for recording demos but should be removed when not needed to free slots for actual players.

KTPHLTVKicker automatically:
1. Connects to configured game servers via RCON
2. Lists connected players
3. Identifies HLTV spectator bots (by name pattern)
4. Kicks them to free the slot

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Windows Task Scheduler                                      │
│  - Trigger: Daily at 4:00 AM                                 │
│  - Action: Run KTPHLTVKicker.jar                             │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  KTPHLTVKicker (Java)                                        │
│  - Reads .env for server list                                │
│  - Uses Steam Condenser for GoldSrc RCON                     │
│  - Handles offline servers gracefully                        │
└─────────────────────────────┬───────────────────────────────┘
                              │ RCON (UDP)
                              ↓
┌───────────────────┐   ┌───────────────────┐   ┌─────────────┐
│  KTP NY Server    │   │  KTP CHI Server   │   │  KTP DAL... │
│  - status         │   │  - status         │   │             │
│  - kick HLTV      │   │  - kick HLTV      │   │             │
└───────────────────┘   └───────────────────┘   └─────────────┘
```

#### Configuration (.env)

```bash
# Server list (comma-separated)
SERVERS=ny.example.com:27015,chi.example.com:27015,dal.example.com:27015

# RCON passwords (server-specific or shared)
RCON_PASSWORD_NY=secret1
RCON_PASSWORD_CHI=secret2
RCON_PASSWORD_DEFAULT=defaultsecret

# HLTV detection pattern
HLTV_NAME_PATTERN=HLTV.*|TV-.*

# Timeout for offline servers (seconds)
CONNECT_TIMEOUT=5
```

#### Steam Condenser Usage

```java
// Using Steam Condenser library for GoldSrc RCON
GoldSrcServer server = new GoldSrcServer(address);
server.rconAuth(password);

// Get player list
String status = server.rconExec("status");

// Parse and kick HLTV players
for (String player : parseHLTVPlayers(status)) {
    server.rconExec("kick " + player);
    log.info("Kicked HLTV: " + player);
}
```

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
ktp_prepause_seconds "3"              // Countdown before pause (live match)
ktp_prematch_pause_seconds "3"        // Countdown before pause (pre-match)
ktp_pause_countdown "5"               // Unpause countdown duration
ktp_tech_budget_seconds "300"         // 5-min tech budget per team
ktp_unready_reminder_secs "30"        // Unready reminder interval
ktp_unpause_reminder_secs "15"        // Unpause reminder interval

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

> **Note:** All commands work with both `.` and `/` prefixes. The `.` prefix is preferred as it's shorter.

### Match Control

| Command            | Description                 | Notes                    |
|--------------------|-----------------------------|--------------------------|
| `.ktp <pw>`        | Initiate competitive match  | Requires season + password|
| `.draft`           | Start draft match           | Always available         |
| `.12man`           | Start 12-man match          | Always available         |
| `.scrim`           | Start scrim match           | Always available         |
| `.confirm`         | Confirm team ready          |                          |
| `.ready`, `.rdy`   | Mark yourself ready         |                          |
| `.notready`        | Mark yourself not ready     |                          |
| `.status`          | View match status           |                          |
| `.prestatus`       | View pre-start status       |                          |
| `.cancel`          | Cancel match/pre-start      |                          |

### Pause Control

| Command           | Description               | Access        |
|-------------------|---------------------------|---------------|
| `.pause`, `.tac`  | Tactical pause (3s countdown) | Anyone     |
| `.tech`           | Technical pause           | Anyone        |
| `.resume`         | Request unpause           | Owner team    |
| `.go`             | Confirm unpause           | Other team    |
| `.ext`, `.extend` | Extend pause +2 min       | Anyone        |
| `.nodc`, `.stopdc`| Cancel disconnect pause   | Affected team |

### Team Names & Score

| Command              | Description               |
|----------------------|---------------------------|
| `.setallies <name>`  | Set Allies team name      |
| `.setaxis <name>`    | Set Axis team name        |
| `.names`             | View current team names   |
| `.resetnames`        | Reset to default names    |
| `.score`             | View current match score  |

### Admin Commands

| Command           | Description              |
|-------------------|--------------------------|
| `.cfg`            | View current CVARs       |
| `ktp_pause`       | Server/RCON pause        |

### Admin Audit (KTPAdminAudit)

| Command           | Description              |
|-------------------|--------------------------|
| `.kick`           | Open kick menu           |
| `.ban`            | Open ban menu            |
| `ktp_kick`        | Console kick command     |
| `ktp_ban`         | Console ban command      |

---

## 🔗 GitHub Repositories

### KTP Core Stack

| Layer    | Repository                                              | Version       | Description                         |
|----------|---------------------------------------------------------|---------------|-------------------------------------|
| Engine   | [KTP-ReHLDS](https://github.com/afraznein/KTPReHLDS)    | 3.19.0+       | Custom ReHLDS with extension loader |
| SDK      | [KTP HLSDK](https://github.com/afraznein/KTPhlsdk)      | 1.0.0         | SDK headers with callback support   |
| Platform | [KTPAMXX](https://github.com/afraznein/KTPAMXX)         | 2.6.0         | AMX Mod X extension mode fork       |
| Bridge   | [KTP-ReAPI](https://github.com/afraznein/KTPReAPI)      | 5.25.0.0-ktp  | ReAPI extension mode fork           |
| HTTP     | [KTP AMXX Curl](https://github.com/afraznein/KTPAmxxCurl)| 1.1.1-ktp    | Non-blocking HTTP module            |

### Application Plugins

| Plugin        | Repository                                                      | Version | Description                    |
|---------------|-----------------------------------------------------------------|---------|--------------------------------|
| Match Handler | [KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler) | 0.9.16  | Match workflow + HLStatsX      |
| Cvar Checker  | [KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)   | 7.7     | Client cvar enforcement        |
| File Checker  | [KTPFileChecker](https://github.com/afraznein/KTPFileChecker)   | 2.1     | File consistency + Discord     |
| Admin Audit   | [KTPAdminAudit](https://github.com/afraznein/KTPAdminAudit)     | 2.1.0   | Menu-based kick/ban + audit    |

### Supporting Infrastructure

| Service          | Repository                                                        | Version | Description                |
|------------------|-------------------------------------------------------------------|---------|----------------------------|
| Discord Relay    | [Discord Relay](https://github.com/afraznein/discord-relay)       | 1.0.1   | Cloud Run webhook proxy    |
| HLStatsX         | [KTPHLStatsX](https://github.com/afraznein/KTPHLStatsX)           | 0.1.0   | Match-based stats tracking |
| File Distributor | [KTPFileDistributor](https://github.com/afraznein/KTPFileDistributor) | -   | SFTP file distribution     |
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

**Last Updated:** 2025-12-22

</div>
