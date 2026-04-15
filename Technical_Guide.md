# KTP Competitive Infrastructure - Technical Guide

*A comprehensive ecosystem of custom engine modifications, extension modules, match management plugins, and supporting services designed for competitive 6v6 Day of Defeat gameplay.*

**No Metamod Required** - Runs on Linux and Windows via ReHLDS Extension Mode

**Last Updated:** 2026-03-29

[Architecture](#six-layer-architecture) | [Components](#component-documentation) | [Installation](#complete-installation-guide) | [Repositories](#github-repositories)

---

## Six-Layer Architecture

The KTP stack eliminates Metamod dependency through a custom extension loading architecture. KTPAMXX loads directly as a ReHLDS extension, and modules like KTP-ReAPI interface through KTPAMXX's module API instead of Metamod hooks.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 6: Application Plugins (AMX Plugins)                                  │
│  KTPMatchHandler v0.10.110- Match workflow, pause, OT, Discord embeds,HLStatsX│
│  KTPHLTVRecorder v1.5.6   - Auto HLTV recording via HTTP API + health checks │
│  KTPCvarChecker v7.22     - Real-time cvar enforcement + Discord grouping    │
│  KTPFileChecker v2.5      - File consistency validation + Discord grouping   │
│  KTPAdminAudit v2.7.12    - Menu-based kick/ban/changemap + audit            │
│  KTPPracticeMode v1.3.2   - Practice mode with .grenade, noclip, HUD         │
│  KTPGrenadeLoadout v1.0.6 - Custom grenade loadouts per class via INI        │
│  KTPGrenadeDamage v1.0.3  - Grenade damage reduction by configurable %       │
│  stats_logging.sma v1.11.0- DODX weaponstats with match ID support           │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Forwards & Natives
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 5: Game Stats Modules (AMXX Modules)                                  │
│  DODX Module             - Day of Defeat stats, weapons, shot tracking       │
│  Stats: dodx_flush_all_stats, dodx_reset_all_stats, dodx_set_match_id       │
│  Stats: dodx_set_stats_paused (round-freeze filtering for HLStatsX accuracy)│
│  Player: dodx_give_grenade, dodx_set_user_noclip, dodx_set_user_class/team  │
│  Player: dodx_get/set_user_origin, dodx_get/set_user_angles, dodx_send_ammox│
│  Forward: dod_stats_flush(id), dod_damage_pre(att,vic,dmg,wpn,hit,TA)       │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Module API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 4: HTTP/Networking Modules (AMXX Modules)                             │
│  KTP AMXX Curl v1.3.6-ktp - Non-blocking HTTP/FTP via libcurl                │
│  Uses MF_RegModuleFrameFunc() for async processing                           │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses AMXX Module API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 3: Engine Bridge Modules (AMXX Modules)                               │
│  KTP-ReAPI v5.29.0.363-ktp - Exposes ReHLDS/ReGameDLL hooks to plugins       │
│  Extension Mode: No Metamod, uses KTPAMXX GetEngineFuncs()                   │
│  Custom Hooks: RH_SV_UpdatePausedHUD (pause HUD), RH_SV_Rcon (RCON audit)    │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ Uses ReHLDS Hookchains
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 2: Scripting Platform (ReHLDS Extension)                              │
│  KTPAMXX v2.7.4  - AMX Mod X fork with extension mode + HLStatsX integration │
│  Loads as ReHLDS extension, no Metamod required                              │
│  Provides: client_cvar_changed forward, MF_RegModuleFrameFunc()              │
│  Natives: ktp_drop_client, DODX score broadcasting, ktp_discord.inc v1.3.4   │
│  Natives: dod_damage_pre forward, grenade natives, player manipulation       │
│  v2.7.0: JIT/ASM32 re-enabled, security hardening, 60+ code review fixes    │
│  v2.7.4: Stats pause native, message hook fix, task use-after-realloc fix    │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ ReHLDS Extension API
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 1: Game Engine (KTP-ReHLDS v3.22.0.912)                               │
│  Custom ReHLDS fork with extension loader + KTP features                     │
│  Provides: SV_UpdatePausedHUD hook, SV_Rcon hook, pfnClientCvarChanged       │
│  Features: ktp_silent_pause cvar, SV_BroadcastPauseState(), frame profiler   │
│  Blocked: kick, banid, removeid, addip, removeip (use .kick/.ban instead)    │
│  Profiler: 6-phase frame timing, physics sub-phases, per-client send timing  │
│  Extension hooks: SV_ClientCommand, SV_InactivateClients, AlertMessage,      │
│                   PF_TraceLine, PF_SetClientKeyValue, SV_PlayerRunPreThink   │
└─────────────────────────────────────────────────────────────────────────────┘

                         Supporting Infrastructure:
┌─────────────────────────────────────────────────────────────────────────────┐
│  Cloud Services:                                                             │
│  - Discord Relay v1.0.1     - HTTP proxy for Discord webhooks (Cloud Run)   │
│  - KTPHLStatsX v0.3.2       - HLStatsX daemon with per-half stats + batching│
│                                                                              │
│  VPS Services:                                                               │
│  - KTPFileDistributor v1.1.1 - .NET 8 file sync daemon (SFTP distribution)  │
│  - HLTV Scheduled Restarts  - systemd timer (replaces KTPHLTVKicker)        │
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
<summary><b>Why No Metamod? The Wall Penetration Discovery</b></summary>

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
<summary><b>Extension Mode: How It Replaces Metamod</b></summary>

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

## Component Documentation

### Layer 1: KTP-ReHLDS (Engine)

**Repository:** [github.com/afraznein/KTPReHLDS](https://github.com/afraznein/KTPReHLDS)
**Version:** 3.22.0.912
**License:** MIT

<details>
<summary><b>Core Engine Features</b></summary>

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

#### Silent Pause Mode (v3.22.0+)

New cvar `ktp_silent_pause` controls client pause overlay:

| Value | Behavior |
|-------|----------|
| `0` (default) | Normal - clients receive `svc_setpause`, see "PAUSED" overlay |
| `1` | Silent - clients don't receive `svc_setpause`, custom HUD only |

**Use Case:** KTPMatchHandler sets `ktp_silent_pause 1` before pausing, enabling custom MM:SS countdown HUD without the blocky client overlay.

```cpp
// KTP-ReHLDS broadcasts pause state respecting cvar
void SV_BroadcastPauseState(qboolean paused) {
    if (ktp_silent_pause.value != 0.0f) {
        return;  // Skip broadcast - clients won't see overlay
    }
    // Normal broadcast to all connected clients
}
```

#### Frame Profiling System (v3.22.0.904+)

Low-overhead profiling built into the engine for diagnosing performance issues on live production servers.

**CVars:**

| Cvar | Default | Description |
|------|---------|-------------|
| `ktp_profile_frame` | `0` | Enable/disable frame profiling |
| `ktp_profile_interval` | `10` | Seconds between summary logs |
| `ktp_profile_spike_threshold` | `5.0` | Log `[KTP_SPIKE]` alert when any frame exceeds this ms (0 = disabled) |
| `ktp_profile_steam_detail` | `0` | Granular Steam_RunFrame() sub-timing |

**6-Phase Frame Timing:**

Each `SV_Frame_Internal()` call is broken into six phases:

| Phase | Function | What It Measures |
|-------|----------|-----------------|
| `read` | `SV_ReadPackets` | Network input, packet parsing |
| `phys` | `SV_Physics` | Game simulation, plugin hooks |
| `misc1` | `SV_RequestMissing` + `SV_CheckTimeouts` | Resource requests, timeout checks |
| `send` | `SV_SendClientMessages` | Network output to clients |
| `post` | Pause restore + `SV_GatherStatistics` | Post-frame housekeeping |
| `steam` | `Steam_RunFrame` | Steam callbacks, packet send |

**v3.22.0.912 additions:**
- Physics sub-phase timing — separates `pfnStartFrame` (AMXX plugins + game DLL) from entity physics loop
- Per-client send timing — identifies the worst (slowest) client each frame
- Profiler overhead optimization — eliminated 10,000+ cache-dirtying writes/sec on production by gating globals behind profiling flag, consolidated cvar dereferences into single `g_ktp_profiling_enabled` global

**Summary log output (every N seconds):**
```
[KTP_PROFILE] frames=9823 fps=982.3 edicts_max=156
[KTP_PROFILE] avg: read=0.120ms phys=0.450ms misc1=0.005ms send=0.080ms post=0.003ms steam=0.010ms full=0.680ms
[KTP_PROFILE] peak: read=0.450ms phys=1.200ms misc1=0.020ms send=0.300ms post=0.010ms steam=0.050ms full=2.100ms
[KTP_PROFILE] phys_detail: startframe=0.350ms entloop=0.100ms
[KTP_PROFILE] send_detail: worst_client=5(PlayerName) time=0.280ms clients_sent=12
```

**Spike alert output (immediate, rate-limited to 1/sec):**
```
[KTP_SPIKE] full=12.340ms read=0.150ms phys=0.500ms misc1=0.010ms send=0.100ms post=0.005ms steam=11.500ms gap=0.075ms
```

#### Extension Mode Hookchains (v3.16.0-3.22.0)

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
| `SV_Rcon` (v3.20.0+)       | RCON command interception            | KTPAdminAudit        |
| `Host_Changelevel_f` (v3.20.0+) | Console changelevel command     | KTPMatchHandler OT   |

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
<summary><b>pfnClientCvarChanged Callback</b></summary>

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
**Version:** 2.7.4
**License:** GPL v3
**Base:** AMX Mod X 1.10.0.5468-dev

<details>
<summary><b>Extension Mode Architecture</b></summary>

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
<summary><b>New Forward: client_cvar_changed</b></summary>

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
<summary><b>Module API Extensions (v2.4.0+)</b></summary>

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
| **DODFun** | N/A | Not loaded — natives ported to DODX |
| **SQLite** | ❌ Broken | Has Metamod-specific code paths |
| **MySQL** | ⚠️ Untested | May work, not verified |

</details>

<details>
<summary><b>KTP-Specific Natives (v2.6.0)</b></summary>

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
<summary><b>ktp_discord.inc - Shared Discord Integration</b></summary>

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
discord_channel_id_scrim=2222222222222222222
discord_channel_id_12man=3333333333333333333
discord_channel_id_draft=4444444444444444444

; Audit channels (for KTPAdminAudit, KTPCvarChecker, KTPFileChecker)
; All channels matching "discord_channel_id_audit*" receive audit messages
discord_channel_id_audit_main=5555555555555555555
discord_channel_id_audit_backup=6666666666666666666
discord_channel_id_admin=7777777777777777777
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
<summary><b>Path and Naming Changes</b></summary>

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
│   └── dodx_ktp.dll / dodx_ktp_i386.so
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
**Version:** 5.29.0.363-ktp
**License:** GPL v3
**Base:** ReAPI 5.26+

<details>
<summary><b>Extension Mode Operation</b></summary>

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
<summary><b>Custom KTP Hooks: RH_SV_UpdatePausedHUD & RH_SV_Rcon</b></summary>

#### Pause HUD Hook (RH_SV_UpdatePausedHUD)

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

#### RCON Audit Hook (RH_SV_Rcon) - v3.20.0+

```pawn
// In reapi_engine_const.inc
enum RehldsHook {
    // ... standard hooks ...

    /*
    * Called when an RCON command is received (KTP-ReHLDS v3.20.0+)
    * Params: (netadr, cmd, responseBuffer, responseBufferSize)
    * @note Use for auditing server control commands (quit, restart, etc.)
    * @note Return HC_SUPERCEDE to block the command
    */
    RH_SV_Rcon,
};
```

**Used By:** KTPAdminAudit v2.2.0+ for logging RCON quit/restart commands to Discord

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
**Version:** 1.3.6-ktp
**License:** MIT
**Base:** AmxxCurl by Polarhigh

**Key safety features (v1.3.x):**
- **`curl_get_response_body` native** (v1.3.0) - Retrieve HTTP response body from completed requests
- **Persistent header slist** (v1.3.0) - Shared `curl_slist` created once at init, preventing use-after-free with overlapping async requests
- **In-flight callback safety** (v1.3.4) - `IsAmxValid()` checks before calling into Pawn, deferred cleanup for in-flight handles
- **POSTFIELDS copy safety** (v1.3.5) - Auto-upgrades `CURLOPT_POSTFIELDS` to `CURLOPT_COPYPOSTFIELDS` for async requests
- **Detach cleanup** (v1.3.6) - `curl_global_cleanup` leak fix, wall-clock timeout for `OnAmxxDetach`, `CurlReset` re-binding fix

<details>
<summary><b>Non-Blocking HTTP Without Metamod</b></summary>

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
**Version:** 2.7.4
**Purpose:** Day of Defeat weapon stats, shot tracking, HLStatsX integration

<details>
<summary><b>DODX Extension Mode: The Complete Rewrite</b></summary>

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

#### Shot Tracking: CurWeapon Message Handler

Shot detection uses the `CurWeapon` message handler (clip-decrement detection) as the single authoritative source. The original button-state PreThink path was disabled in v2.7.1 because both methods ran simultaneously in extension mode, double-counting every shot and inflating HLStatsX accuracy stats.

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
<summary><b>HLStatsX Integration Natives (v2.5.0+)</b></summary>

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

// Pause/unpause stats collection (v2.7.4)
// When paused, kills, damage, shots, and ObjScore are not tracked
// Used by KTPMatchHandler for round-freeze filtering
native dodx_set_stats_paused(bool:paused);

// Set player's team name in private data
native dodx_set_pl_teamname(id, const szName[]);

// Broadcast TeamScore message to all clients (v2.6.2)
native dodx_broadcast_team_score(team, score);

// Set custom team name on scoreboard (v2.6.2)
// Note: Client-side DoD hardcodes "Allies"/"Axis" - this may not work
native dodx_set_scoreboard_team_name(team, const name[]);
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
**Version:** 0.10.110
**License:** MIT

<details>
<summary><b>Key Features & Recent Updates</b></summary>

#### Performance Architecture (v0.10.97+)

Match start, ready-up, and halftime transitions are deferred across multiple frames to avoid stalling the server:

| Operation | Technique | Frame Savings |
|-----------|-----------|---------------|
| Match start | 3-phase deferred work (state → stats → Discord) | ~160ms → ~60-80ms |
| Confirm → pending | Deferred to next frame via task | ~15-20ms |
| Say hook | Fast path: non-command chat returns after 4 bytes | ~99% of traffic skips parsing |
| Periodic score save | 120s interval, skip I/O when unchanged | Eliminated 5.1ms inter-frame gaps |

#### Score Tracking (v0.10.110)

Score persistence uses `dodx_get_team_score()` (gamerules memory read) instead of `dod_get_team_score()` (message-tracked). In extension mode, DODX's `Client_TeamScore` message handler never receives TeamScore messages, so the message-tracked path always returns 0. The gamerules read is always accurate regardless of message dispatch.

#### Round-State Filtering (v0.10.101)

Three-layer defense against phantom kills during round-freeze periods:
1. DODX `dodx_set_stats_paused()` native pauses C++ stat accumulation
2. `KTP_ROUND_FREEZE`/`KTP_ROUND_LIVE` log events for HLStatsX daemon
3. Event-driven match context setup (replaces fixed delays) with 5s safety timeout

#### Discord Integration

- Live-updating embeds with real-time scores during matches (v0.10.72+)
- Separate channel routing: competitive, draft, 12man, scrim, default (v0.10.98)
- OT round scores shown alongside regulation totals (v0.10.105)
- Roster embed buffer 2048→4096 for 12-player matches (v0.10.105)

#### Match Types

| Type | Command | Password | Ready Req | Half Duration |
|------|---------|----------|-----------|---------------|
| Competitive | `.ktp` | Required | 6 | Map config |
| Draft | `.draft` | None | 5 | 15 minutes |
| 12-Man | `.12man` | None | 5 | 20 or 15 min (menu) |
| Scrim | `.scrim` | None | 1 | 20 or 15 min (menu) |
| KTP OT | `.ktpOT` | Required | 6 | 5 minutes |
| Draft OT | `.draftOT` | None | 5 | 5 minutes |

OT is explicit: matches end at tie, captains manually start `.ktpOT` or `.draftOT`.

#### Notable Bug Fixes

- **Score persistence** (v0.10.110) — `dod_get_team_score()` returns 0 in extension mode; switched to gamerules read
- **Timelimit during ready-up** (v0.10.103) — Blocked changelevel caused 2000 lines/sec log spam (NY1 incident: 5.4GB logs)
- **pfnChangeLevel debounce** (v0.10.82) — 26M+ calls reduced to 1 per intermission
- **OT recursive loop crash** (v0.10.34) — Hook re-entry during OT round transitions
- **ClearPluginLibraries crash** (KTPAMXX v2.7.2) — `.changemap` freed executable thunk pages

</details>

<details>
<summary><b>Match Workflow System</b></summary>

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

5a. OVERTIME (explicit, v0.10.42+)
   - Matches end at tie with announcement: "Match tied X-X! Use .ktpOT or .draftOT"
   - Captain types `.ktpOT <password>` to start explicit OT match
   - 5-minute rounds, side swaps between OT rounds
   - First team ahead at round end wins
   - If still tied, captains run `.ktpOT` again for next OT round
   - Tech budget resets for OT
   - OT state persists via localinfo (_ktp_ots, _ktp_otst)
   - Match type persists via localinfo (_ktp_mtyp)

6. HALF END / MATCH END
   - dodx_flush_all_stats() - flush match stats
   - KTP_MATCH_END logged for HLStatsX
   - Discord notification with scores
```

#### Match Types

| Type        | Command      | Password | Season Required | Ready Req | Duration | Config               |
|-------------|--------------|----------|-----------------|-----------|----------|----------------------|
| Competitive | `.ktp`       | Required | Yes             | 6         | Map config | `mapname.cfg`        |
| Draft       | `.draft`     | None     | No              | 5         | 15 min   | `mapname.cfg`        |
| 12-Man      | `.12man`     | None     | No              | 5         | 20 or 15 min (menu) | `mapname_12man.cfg`  |
| Scrim       | `.scrim`     | None     | No              | 1         | 20 or 15 min (menu) | `mapname_scrim.cfg`  |
| KTP OT      | `.ktpOT`     | Required | No              | 6         | 5 min    | `competitive.cfg`    |
| Draft OT    | `.draftOT`   | None     | No              | 5         | 5 min    | `competitive.cfg`    |

#### Season Control

Season status is configured via `ktp.ini`. When season is OFF, `.ktp` is disabled.
Draft, 12man, and scrim are always available regardless of season status.

#### Score Tracking (v0.8.0+)

- Tracks scores per half via TeamScore hook
- Persists across map changes via localinfo
- Discord match end shows final score with half breakdown

</details>

<details>
<summary><b>Pause System (Tech-Only)</b></summary>

#### Pause Types

| Type          | Status       | Command        | Notes                                    |
|---------------|-------------|----------------|------------------------------------------|
| ~~Tactical~~  | **DISABLED** | ~~`.pause`/`.tac`~~ | Disabled since v0.10.35              |
| **Technical** | Active       | `.tech`        | Uses per-team budget (default 300s/half) |

**Technical Pause Budget:** 5 minutes per team per half (persists across halves via localinfo)

#### Pause Flow with Real-Time HUD

```
Player types .tech
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

  Type: TECHNICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26

  .resume  |  .go
```

</details>

---

#### KTPCvarChecker

**Repository:** [github.com/afraznein/KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)
**Version:** 7.22
**License:** GPL v2

<details>
<summary><b>Real-Time Cvar Enforcement Pipeline</b></summary>

#### Architecture

Pure enforcement anti-cheat — no punishments, just auto-correction and logging. Uses KTPAMXX's `client_cvar_changed` callback for real-time detection:

```
KTP Cvar Checker: queries cvars periodically
     │  Priority (9 cvars): every 2 seconds
     │  Standard (25 cvars): rotated every 10 seconds (5 per check)
     ▼
Game Client: responds with current cvar value
     ▼
KTP-ReHLDS: pfnClientCvarChanged callback
     ▼
KTPAMXX: client_cvar_changed forward
     ▼
KTP Cvar Checker: Trie lookup → validate → defer enforcement → Discord alert
```

#### 34 Monitored Cvars (9 Priority + 25 Standard)

**Priority (checked every 2 seconds):**

| Cvar | Enforcement | Notes |
|------|-------------|-------|
| `m_pitch` | Exact: `0.022` or `-0.022` | Inverted mouse allowed |
| `cl_pitchdown` | Exact: `89` | |
| `cl_pitchup` | Exact: `89` | |
| `cl_updaterate` | Range: `100-120` | Matches `sv_maxupdaterate 120` |
| `cl_cmdrate` | Range: `100-500` | |
| `rate` | Exact: `100000` | Locked value |
| `ex_interp` | Range: `0.01-0.05` | Floor prevents teleporting on jitter |
| `cl_lc` | Exact: `1` | Lag compensation required |
| `cl_lw` | Exact: `1` | Weapon prediction required |

**Standard (rotated, 5 per 10 seconds):** Graphics (`gl_*`, `r_fullbright`, `r_lightmap`, `texgamma`, `lightgamma`), audio (`s_show`), movement (`m_side`, `cl_pitch*`, `lookspring`), gameplay (`fps_max`, `hud_takesshots`).

**Dynamic enforcement:** `hud_takesshots` only enforced during competitive matches (`.ktp`, `.ktpOT`) via `ktp_match_competitive` cvar.

#### Enforcement Pipeline (v7.19+)

Violations are deferred to prevent frame stalls:

1. **`client_cvar_changed` callback** — Trie-based O(1) cvar name lookup (v7.21), replaces 34-entry linear scan
2. **Deferred enforcement queue** — Per-cvar bitmask accumulates all pending violations, processes on next frame via `set_task(0.0)`. Prevents the 160-185ms frame freeze discovered in Feb 2026 when enforcement ran inside the opcode handler
3. **Discord grouping** — 5-second batching window collects all violations per player into a single embed, with per-player task IDs to prevent duplicate notifications

#### Detection Speed

| Type | Count | Interval | Worst-Case Detection |
|------|-------|----------|---------------------|
| Priority cvars | 9 | Every 2s | < 2 seconds |
| Standard cvars | 25 | 5 per 10s | ~50 seconds |
| Initial check | All 34 | Parallel batches of 8 | ~2 seconds |

**Performance:** ~5 queries/sec per player (~160 q/s for 32 players, ~0.4% CPU, ~8 KB/s network).

#### cl_filterstuffcmd Detection

If a player has `cl_filterstuffcmd 1`, enforcement commands are silently dropped by the client. After 3 failed enforcement attempts for the same cvar, a warning is shown to the player.

</details>

---

#### KTPFileChecker

**Repository:** [github.com/afraznein/KTPFileChecker](https://github.com/afraznein/KTPFileChecker)
**Version:** 2.5
**License:** Custom

<details>
<summary><b>File Consistency Checking</b></summary>

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
**Version:** 2.7.12
**License:** MIT

<details>
<summary><b>Menu-Based Admin System</b></summary>

#### Features

- **Menu-based kick/ban** - Interactive player selection (no RCON needed)
- **Menu-based map change** (v2.6.0+) - Map selection from ktp_maps.ini with 5-second countdown
- **RCON quit/exit blocking** (v2.7.1+) - RCON quit/exit commands BLOCKED; must use `.quit` in-game
- **Admin flag permissions** - Requires ADMIN_KICK (c), ADMIN_BAN (d), or ADMIN_RCON (l)
- **Immunity protection** - Players with ADMIN_IMMUNITY (a) cannot be kicked/banned
- **Ban duration selection** - 1 hour, 1 day, 1 week, or permanent
- **Discord audit logging** - Real-time notifications to configured channels
- **RCON audit logging** (v2.2.0+) - Logs restart commands with source IP via RH_SV_Rcon hook
- **Console command audit** (v2.3.0+) - Catches all console commands including LinuxGSM via RH_ExecuteServerStringCmd
- **Admin server commands** (v2.3.0+) - `.restart` / `.quit` with ADMIN_RCON flag
- **HLTV kick support** (v2.3.0+) - HLTV proxies appear in kick menu
- **Match protection** - `.changemap` blocked during active matches (requires KTPMatchHandler)
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
<summary><b>HTTP Relay Architecture</b></summary>

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
**Version:** 0.3.2
**Platform:** HLStatsX:CE Fork (Perl daemon + MySQL)
**License:** GPL v2
**Base:** HLStatsX:CE by NomisCZ

**v0.3.x Architecture (Major Rewrite):**
- **Drain-then-process UDP** (v0.3.0) - Drains all available packets (up to 500) into a queue before processing any, preventing kernel buffer overflow during burst periods
- **Batched frag UPDATEs** (v0.3.0) - Roles/Weapons/Maps_Counts UPDATEs replaced with in-memory hash increments flushed every 30 seconds, reducing per-frag MySQL round-trips from 4 to 0
- **Event queue 10→100** (v0.3.0) - Reduces multi-row INSERT frequency with 30-second staleness flush
- **Per-half stat breakdown** (v0.3.1) - Event tables record `half` column (1=1st, 2=2nd, 3+=OT). `ktp_match_stats` aggregates per-half rows plus a `half=0` total row
- **Damage + score aggregation** (v0.3.1) - JOINs `hlstats_Events_Statsme` for total damage per player per half; accumulates objective scores from weaponstats
- **Headshot tracking fix** (v0.3.2) - `headshot_kill` handler was dead code (unreachable `elsif` branch); moved before generic action handling

<details>
<summary><b>Match-Based Statistics Tracking</b></summary>

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
**Version:** 1.1.1
**Platform:** .NET 8 Worker Service (Linux VPS)
**License:** MIT

<details>
<summary><b>Automated File Distribution</b></summary>

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

#### KTPHLTVRecorder

**Repository:** [github.com/afraznein/KTPHLTVRecorder](https://github.com/afraznein/KTPHLTVRecorder)
**Version:** 1.5.6
**Platform:** AMX/Pawn Plugin
**License:** GPL-3.0
**Requires:** KTPMatchHandler v0.10.4+ (for forwards), Curl module (for HTTP API)

**Key Features:**
- **Per-half demo files** (v1.3.0) - Each half records to `_h1`, `_h2`, `_ot1` suffixes
- **Pre-match HLTV health check** (v1.4.0) - Verifies HLTV API responds before recording, auto-recovery on failure
- **Recording verification** (v1.5.5) - In-game chat feedback confirming recording started successfully (HLTV API v2.1)
- **Admin `.hltvrestart` command** (v1.2.1) - Restart paired HLTV from game server (ADMIN_RCON), logged to Discord audit
- **Orphaned recording cleanup** (v1.2.2) - Sends `stoprecording` on plugin startup/shutdown

<details>
<summary><b>Automatic HLTV Demo Recording via HTTP API</b></summary>

#### Purpose

Automatically records HLTV demos when KTPMatchHandler matches start and stop. Eliminates manual demo recording and ensures consistent naming for match archives.

KTPHLTVRecorder:
1. Hooks KTPMatchHandler's `ktp_match_start` forward
2. Sends HTTP POST to HLTV API with `record` command
3. Hooks `ktp_match_end` forward
4. Sends `stoprecording` via HTTP API

#### Architecture (v1.1.0+ - HTTP API via FIFO pipes)

```
┌─────────────────────────────────────────────────────────────┐
│  KTPMatchHandler                                             │
│  - Fires ktp_match_start(matchid, map, type, half)          │
│  - Fires ktp_match_end(matchid, map)                         │
└─────────────────────────────┬───────────────────────────────┘
                              │ AMX Forward
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  KTPHLTVRecorder                                             │
│  - Receives match events                                     │
│  - Formats demo name: <type>_<matchid>.dem                  │
│  - Uses Curl module for HTTP POST to HLTV API               │
└─────────────────────────────┬───────────────────────────────┘
                              │ HTTP POST
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  HLTV API Service (port 8087)                                │
│  - Python HTTP server on data server                         │
│  - Authenticates via X-Auth-Key header                       │
│  - Writes commands to FIFO pipes                            │
└─────────────────────────────┬───────────────────────────────┘
                              │ FIFO pipe
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  HLTV Wrapper + HLTV Instance                                │
│  - hltv-wrapper.sh runs tail -f on FIFO                     │
│  - Commands fed to HLTV stdin                               │
│  - Receives: record ktpOT_KTP-1735052400-dod_anzio          │
│  - Receives: stoprecording                                   │
└─────────────────────────────────────────────────────────────┘
```

#### Data Server Components

1. **HLTV API Service** (`/home/hltvserver/hltv-api.py`)
   - Python HTTP server on port 8087
   - Receives commands via POST /hltv/<port>/command
   - Authenticates requests via X-Auth-Key header
   - Writes commands to FIFO pipes

2. **FIFO Pipes** (`/home/hltvserver/cmdpipes/hltv-<port>.pipe`)
   - One pipe per HLTV instance
   - Commands written to pipe are fed to HLTV stdin

3. **HLTV Wrapper** (`/home/hltvserver/hltv-wrapper.sh`)
   - Runs `tail -f` on FIFO pipe
   - Pipes output to HLTV process stdin

#### Configuration (hltv_recorder.ini)

```ini
; HLTV Recorder Configuration
hltv_enabled = 1
hltv_api_url = http://74.91.112.242:8087
hltv_api_key = YOUR_API_KEY_HERE
hltv_port = 27020
```

#### Demo Naming Format

`<matchtype>_<matchid>.dem` (matchId already contains map name)

Examples:
- `ktp_KTP-1735052400-dod_anzio.dem`
- `scrim_KTP-1735052400-dod_flash.dem`
- `draft_KTP-1735052400-dod_avalanche.dem`
- `ktpOT_KTP-1735052400-dod_anzio.dem` (explicit OT)
- `draftOT_KTP-1735052400-dod_avalanche.dem` (explicit OT)

#### HLTV Server Pairing

Each game server should have a 1:1 pairing with an HLTV instance. 25 game servers across 5 locations, each paired with an HLTV proxy on the data server:

| Game Server | Port | HLTV Port | Location |
|-------------|------|-----------|----------|
| Atlanta 1   | 27015 | 27020 | 74.91.121.9 |
| Atlanta 2   | 27016 | 27021 | 74.91.121.9 |
| Atlanta 3   | 27017 | 27022 | 74.91.121.9 |
| Atlanta 4   | 27018 | 27023 | 74.91.121.9 |
| Atlanta 5   | 27019 | 27024 | 74.91.121.9 |
| Dallas 1    | 27015 | 27025 | 74.91.126.55 |
| Dallas 2    | 27016 | 27026 | 74.91.126.55 |
| Dallas 3    | 27017 | 27027 | 74.91.126.55 |
| Dallas 4    | 27018 | 27028 | 74.91.126.55 |
| Dallas 5    | 27019 | 27029 | 74.91.126.55 |
| Denver 1    | 27015 | 27030 | 66.163.114.109 |
| Denver 2    | 27016 | 27031 | 66.163.114.109 |
| Denver 3    | 27017 | 27032 | 66.163.114.109 |
| Denver 4    | 27018 | 27033 | 66.163.114.109 |
| Denver 5    | 27019 | 27034 | 66.163.114.109 |
| New York 1  | 27015 | 27035 | 74.91.123.64 |
| New York 2  | 27016 | 27036 | 74.91.123.64 |
| New York 3  | 27017 | 27037 | 74.91.123.64 |
| New York 4  | 27018 | 27038 | 74.91.123.64 |
| New York 5  | 27019 | 27039 | 74.91.123.64 |
| Chicago 1   | 27015 | 27040 | 172.238.176.101 |
| Chicago 2   | 27016 | 27041 | 172.238.176.101 |
| Chicago 3   | 27017 | 27042 | 172.238.176.101 |
| Chicago 4   | 27018 | 27043 | 172.238.176.101 |
| Chicago 5   | 27019 | 27044 | 172.238.176.101 |

</details>

---

#### KTPHLTVKicker (DEFUNCT)

> **Note:** This project has been replaced by scheduled HLTV restarts via systemd timers.
> HLTV instances now restart at 3AM/11AM EST, which clears any stale connections.

**Repository:** [github.com/afraznein/KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)
**Version:** 5.9 (final)
**Status:** DEFUNCT

---

## Complete Installation Guide

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
; dodfun_ktp_i386.so  ; N/A - natives ported to DODX
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
discord_relay_url=https://your-relay.run.app/reply
discord_channel_id=1234567890123456789
discord_auth_secret=your-secret-here

; Match-type specific channels
discord_channel_id_competitive=1111111111111111111
discord_channel_id_scrim=2222222222222222222
discord_channel_id_12man=3333333333333333333
discord_channel_id_draft=4444444444444444444
discord_channel_id_audit_competitive=5555555555555555555
```

---

## Feature Comparison Matrix

| Feature              | Base AMX       | ReHLDS + ReAPI  | **KTP Stack**      |
|----------------------|----------------|-----------------|---------------------|
| **Engine**           | HLDS           | ReHLDS          | **KTP-ReHLDS**      |
| **Plugin Platform**  | AMX Mod X      | AMX Mod X       | **KTPAMXX**         |
| **API Module**       | None           | ReAPI + Metamod | **KTP-ReAPI**       |
| **Metamod Required** | No             | Yes             | **No**              |
| **Linux Support**    | Yes            | Via Metamod     | **Native**          |
| Pause Method         | `server_cmd`   | ReAPI           | **ReAPI**           |
| HUD During Pause     | ❌ Frozen      | ❌ Frozen       | **✅ Real-time**    |
| Cvar Detection       | Polling     | Polling      | **Callback + Trie** |
| Cvar Detection Speed | 15-90s         | 15-90s          | **<2s priority**    |
| HTTP Module          | External       | cURL + Metamod  | **KTP Curl**        |
| File Checking        | Basic          | Basic           | **✅ Enhanced**     |
| Discord Integration  | Manual         | Manual          | **✅ Cloud Relay**  |
| Stats Separation     | ❌ None        | ❌ None         | **✅ Match-based**  |
| HLStatsX Integration | ❌ None        | ❌ None         | **✅ Full**         |

---

## Command Reference

> **Note:** All commands work with both `.` and `/` prefixes. The `.` prefix is preferred as it's shorter.

### Match Control

| Command            | Description                 | Notes                    |
|--------------------|-----------------------------|--------------------------|
| `.ktp <pw>`        | Initiate competitive match  | Requires season + password|
| `.ktpOT <pw>`      | Start explicit KTP overtime | Requires KTP password    |
| `.draftOT`         | Start explicit draft overtime| No password required    |
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
| ~~`.pause`/`.tac`~~ | ~~Tactical pause~~     | **DISABLED**  |
| `.tech`           | Technical pause (5s countdown) | Anyone   |
| `.resume`         | Request unpause           | Owner team    |
| `.go`             | Confirm unpause           | Other team    |
| `.nodc`, `.stopdc`| Cancel disconnect pause   | Affected team |

### Team Names & Score

| Command              | Description               |
|----------------------|---------------------------|
| `.setallies <name>`  | Set Allies team name      |
| `.setaxis <name>`    | Set Axis team name        |
| `.names`             | View current team names   |
| `.resetnames`        | Reset to default names    |
| `.score`             | View current match score  |

### Help & Admin Commands

| Command                | Description                 |
|------------------------|-----------------------------|
| `.commands`, `.cmds`   | Show all commands (console) |
| `.cfg`                 | View current CVARs          |
| `.forcereset`          | Clear all match state (ADMIN_RCON, requires confirmation) |
| `ktp_pause`            | Server/RCON pause           |

### Admin Audit (KTPAdminAudit)

| Command           | Description              |
|-------------------|--------------------------|
| `.kick`           | Open kick menu           |
| `.ban`            | Open ban menu            |
| `.changemap`      | Open map selection menu  |
| `.restart`        | Restart server           |
| `.quit`           | Shutdown server          |
| `ktp_kick`        | Console kick command     |
| `ktp_ban`         | Console ban command      |
| `ktp_changemap`   | Console changemap command|

---

## GitHub Repositories

### KTP Core Stack

| Layer    | Repository                                              | Version       | Description                         |
|----------|---------------------------------------------------------|---------------|-------------------------------------|
| Engine   | [KTP-ReHLDS](https://github.com/afraznein/KTPReHLDS)    | 3.22.0.916    | Custom ReHLDS with extension loader + frame profiler |
| SDK      | [KTP HLSDK](https://github.com/afraznein/KTPhlsdk)      | 1.0.0         | SDK headers with callback support   |
| Platform | [KTPAMXX](https://github.com/afraznein/KTPAMXX)         | 2.7.9         | AMX Mod X extension mode fork + JIT |
| Bridge   | [KTP-ReAPI](https://github.com/afraznein/KTPReAPI)      | 5.29.0.364-ktp| ReAPI extension mode fork           |
| HTTP     | [KTP AMXX Curl](https://github.com/afraznein/KTPAmxxCurl)| 1.3.7-ktp    | Non-blocking HTTP module            |

### Application Plugins

| Plugin        | Repository                                                      | Version  | Description                    |
|---------------|-----------------------------------------------------------------|----------|--------------------------------|
| Match Handler | [KTPMatchHandler](https://github.com/afraznein/KTPMatchHandler) | 0.10.112 | Match workflow + explicit OT + HLStatsX |
| HLTV Recorder | [KTPHLTVRecorder](https://github.com/afraznein/KTPHLTVRecorder) | 1.5.6    | Auto HLTV demo recording via HTTP API |
| Cvar Checker  | [KTPCvarChecker](https://github.com/afraznein/KTPCvarChecker)   | 7.22     | Real-time cvar enforcement + deferred pipeline |
| File Checker  | [KTPFileChecker](https://github.com/afraznein/KTPFileChecker)   | 2.6      | File consistency + Discord     |
| Admin Audit   | [KTPAdminAudit](https://github.com/afraznein/KTPAdminAudit)     | 2.7.12   | Menu-based kick/ban/changemap + audit |
| Practice Mode | [KTPPracticeMode](https://github.com/afraznein/KTPPracticeMode) | 1.4.0    | Practice mode with noclip + grenades |
| Grenades      | [KTPGrenades](https://github.com/afraznein/KTPGrenades)         | 1.0.7/1.0.4 | Grenade loadout + damage reduction |
| Score Tracker | [KTPScoreTracker](https://github.com/afraznein/KTPScoreTracker) | 1.0.0    | Verbose capture scoring + HLStatsX |

### Supporting Infrastructure

| Service          | Repository                                                        | Version | Description                |
|------------------|-------------------------------------------------------------------|---------|----------------------------|
| Discord Relay    | [Discord Relay](https://github.com/afraznein/discord-relay)       | 1.0.1   | Cloud Run webhook proxy    |
| HLStatsX         | [KTPHLStatsX](https://github.com/afraznein/KTPHLStatsX)           | 0.3.3   | Per-half stats + batched processing |
| File Distributor | [KTPFileDistributor](https://github.com/afraznein/KTPFileDistributor) | 1.1.2 | SFTP file distribution + Discord |
| ~~HLTV Kicker~~  | [KTPHLTVKicker](https://github.com/afraznein/KTPHLTVKicker)       | 5.9     | DEFUNCT - replaced by systemd restarts |

### Upstream Projects

| Project   | Repository                                         | Description                 |
|-----------|----------------------------------------------------|-----------------------------|
| ReHLDS    | [rehlds](https://github.com/dreamstalker/rehlds)   | Original ReHLDS             |
| ReAPI     | [reapi](https://github.com/s1lentq/reapi)          | Original ReAPI module       |
| AMX Mod X | [amxmodx](https://github.com/alliedmodders/amxmodx)| Original scripting platform |
| AmxxCurl  | [AmxxCurl](https://github.com/Polarhigh/AmxxCurl)  | Original cURL module        |
| HLStatsX  | [hlstatsx](https://github.com/A1mDev/hlstatsx-community-edition) | Original HLStatsX |

---

## Author

**Nein_**
- GitHub: [@afraznein](https://github.com/afraznein)
- Project: KTP Competitive Infrastructure

---

## Acknowledgments

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

**Last Updated:** 2026-03-29

</div>
