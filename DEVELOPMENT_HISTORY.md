# KTP Development History

> Development timeline for the KTP (Keep the Practice) competitive Day of Defeat server infrastructure.

| Metric | Value |
|--------|-------|
| **Project Duration** | October 2025 - Present |
| **Total Repositories** | 17 |
| **Estimated Development Hours** | 1210-1520 |
| **Last Updated** | 2026-03-29 |

---

## Table of Contents

- [Monthly Scope Summary](#monthly-scope-summary)
- [October 2025](#october-2025---foundation) - Foundation
- [November 2025](#november-2025---platform-development) - Platform Development
- [December 2025](#december-2025---feature-complete) - Feature Complete
- [January 2026](#january-2026---stability--polish) - Stability & Polish
- [February 2026](#february-2026---bare-metal--performance) - Bare Metal & Performance
- [March 2026](#march-2026---jit--code-review) - JIT & Code Review

---

## Monthly Scope Summary

| Month | Est. Hours | Focus Areas |
|-------|-----------|-------------|
| October 2025 | 120-150 | Foundation - initial plugins, Discord bots, relay service |
| November 2025 | 180-225 | Platform (C++ ReAPI/KTPAMXX), major plugin rewrites |
| December 2025 | 300-375 | Feature-complete push - overtime, extension mode, v1.0 releases |
| January 2026 | 120-150 | Stability, polish, explicit OT, admin tools |
| February 2026 | 240-320 | Bare metal migration, performance optimization, lag investigation, CPU isolation, bug audit, 2 new server deployments |
| March 2026 | 220-280 | JIT re-enablement, 3-round KTPAMXX code review (60+ fixes), fleet-wide plugin audit, match system performance, score persistence fix, engine profiler optimization |
| **Total** | **1210-1520** | |

### Repository Breakdown

| Category | Count | Projects |
|----------|-------|----------|
| Core Engine (C++) | 4 | KTPReHLDS, KTPAMXX, KTPReAPI, KTPAmxxCurl |
| Game Plugins (Pawn) | 9 | KTPMatchHandler, KTPCvarChecker, KTPFileChecker, KTPAdminAudit, KTPHLTVRecorder, KTPPracticeMode, KTPGrenadeLoadout, KTPGrenadeDamage, KTPScoreTracker |
| Backend Services | 3 | Discord Relay, KTPFileDistributor, KTPHLStatsX |
| Discord Bots | 2 | KTPScoreBot-ScoreParser, KTPScoreBot-WeeklyMatches |

---

## October 2025 - Foundation

**Initial Project Setup & Foundation**

This month established the core infrastructure for the KTP competitive server stack. Work included designing the overall architecture, setting up development environments for both Windows and Linux (WSL), and creating the foundational plugins that would later be expanded.

- **KTPMatchHandler**: Built the initial match workflow system from scratch, including the two-phase pre-start confirmation flow (captain initiates → opponent confirms), the ready system requiring minimum players per team, tactical and technical pause infrastructure with per-team budgets, map configuration loading from custom INI format, and initial Discord webhook integration for match notifications. Extensive research into DoD game mechanics and AMX Mod X plugin development.

- **KTPCvarChecker**: Adapted my existing CVAR checker for AMX 1.10. Developed versions 1.0 through 5.0 of the client variable enforcement system. Created the cvar monitoring architecture, violation detection and kick logic, player notification systems, and the configuration file format for defining monitored cvars with allowed value ranges.

- **KTPScoreBot-ScoreParser** (Discord Bot): Built a Node.js Discord bot that uses text extraction, score pattern matching, and formatted response generation to parse match scores in Discord channels.

- **KTPScoreBot-WeeklyMatches** (Discord Bot): Created a Discord bot for weekly match announcements with significant iteration - went through 4 major rewrites (v1-v4) to handle Discord embed limits, table formatting challenges, and timezone issues. Parses match schedules from web sources and generates formatted announcements.

- **Discord Relay**: Deployed a Google Cloud Run service acting as a webhook proxy between game servers and Discord API. Handles authentication, rate limiting, and provides a stable endpoint for the curl-based game server integrations. Required learning GCP deployment, Cloud Run configuration, and Discord API integration.

- **KTPFileChecker**: Adapted my existing File checker for AMX 1.10. Developed new version of client-side file consistency validation to detect modified game files (sprites, models, sounds) that could provide unfair advantages.

---

## November 2025 - Platform Development

**Focus: C++ Engine Work**

This month involved significant C++ development work on the core engine components. The focus was building custom forks of ReAPI and AMX Mod X to support features not available in upstream versions, particularly around the pause system and real-time cvar detection.

- **KTPMatchHandler v0.4.0-0.5.0**: Major pause system overhaul representing a complete rewrite of pause handling. Integrated with ReAPI for native `rh_set_server_pause()` control that works even with `pausable 0`. Implemented real-time HUD countdown updates during pause via the `RH_SV_UpdatePausedHUD` hook (required custom ReHLDS/ReAPI development). Added disconnect auto-pause with cancellable 10-second countdown. Created the match type system supporting COMPETITIVE, SCRIM, and 12MAN modes with per-type configurations and Discord channel routing. Implemented half tracking for automatic 1st/2nd half detection. Built player roster logging with SteamID and IP capture for competitive accountability.

- **KTPAMXX** (Custom AMX Mod X Fork): Forked AMX Mod X and added the `client_cvar_changed` forward that fires in real-time when clients respond to cvar queries - this required understanding the AMXX plugin callback system and the HL engine's cvar query mechanism. Set up cross-platform build system for both Windows (Visual Studio) and Linux (GCC via WSL). Created initial documentation and established the fork's divergence from upstream.

- **KTPReAPI** (ReAPI Fork): Forked ReAPI and integrated KTP-ReHLDS custom headers. Added the `RH_SV_UpdatePausedHUD` hook that fires every frame during server pause - this required reverse engineering the ReHLDS pause implementation and adding a new hook point. Ensured Windows XP compatibility for legacy server deployments. This C++ work required deep understanding of the ReHLDS/ReAPI architecture and GoldSrc engine internals.

- **KTPCvarChecker v5.4-7.5**: Achieved 60% reduction in function calls through major performance optimization pass. Implemented priority-based periodic monitoring that checks high-risk cvars more frequently. Updated for ReHLDS compatibility and the new real-time cvar detection via KTPAMXX's `client_cvar_changed` forward.

- **KTPScoreBot-WeeklyMatches v3.0-4.1**: Complete rewrite of the weekly match bot. Added playoff bracket parser for tournament phases. Fixed timezone offset issues causing wrong match dates/times. Improved week detection logic for current week window handling.

- **KTPAdminAudit**: Initial versions of the admin action logging plugin. Menu-based interface for kick/ban operations with audit trail logging to Discord.

---

## December 2025 - Feature Complete

**Focus: Feature-Complete Release Push (Largest Development Month)**

December represented the most intensive development period, pushing all major components to feature-complete status. The crown achievement was the complete overtime system in KTPMatchHandler along with the "extension mode" architecture that allows KTPAMXX to run without Metamod.

- **KTPMatchHandler v0.5.1-0.10.1**: This version range represents approximately 50 micro-releases with extensive feature development. v0.5.1-0.5.2 fixed critical bugs including a cURL header memory leak and tech pause budget integer underflow. v0.6.0 added unique match ID system (`KTP-{timestamp}-{map}`) and the `/whoneedsready` command. v0.7.0-0.7.1 integrated with HLStatsX for clean warmup vs match stats separation, added match context persistence via localinfo keys that survive map changes. v0.8.0 added match score tracking via TeamScore message hooks, Discord match-end notifications with winner announcement, and custom team name support. v0.9.0 introduced KTP season control with password protection and the DRAFT match type. v0.9.1-0.9.16 refined Discord embed formatting, periodic score saving, and score restoration after round restarts. **v0.10.1 delivered the complete Overtime System**: automatic OT trigger on tied regulation, 60-second break voting period, 5-minute OT rounds with team side swaps, tech budget reset at OT start, infinite rounds until winner, and full state persistence across map changes via localinfo.

- **KTPAMXX v2.0-2.6.1**: Massive development on the custom AMX Mod X fork. v2.0 established the KTP AMX foundation. v2.1.0 added map change support and client commands in extension mode. v2.2.0 enabled event and logevent support in extension mode. v2.4.0 was a complete rewrite of the DODX module for extension mode compatibility. v2.5.0 added HLStatsX integration natives (`dodx_flush_all_stats`, `dodx_reset_all_stats`, `dodx_set_match_id`) and fixed `get_user_msgid`. v2.6.0 added `ktp_drop_client` native and gamerules access. v2.6.1 introduced `ktp_discord.inc` shared include and the `RH_SV_Rcon` hook for RCON audit logging. The extension mode architecture allows KTPAMXX to load as a ReHLDS extension directly, bypassing Metamod entirely - this was critical because Metamod breaks wall penetration in DoD.

- **KTPReAPI v5.25-5.29**: v5.25.0 achieved "Extension Mode" - the ability to run without Metamod by loading as a ReHLDS extension. Added 10 ReHLDS extension mode hooks required for AMXX/DODX compatibility. v5.29 added the `RH_SV_Rcon` hook that fires on every RCON command for audit logging purposes.

- **KTPAmxxCurl**: Forked the upstream AMXX curl module and removed all Metamod dependencies. Integrated with KTPAMXX's `MF_RegModuleFrameFunc()` frame callback API for non-blocking HTTP operations. This enables Discord webhook calls from plugins without blocking the game server.

- **KTPHLTVRecorder v1.0.0**: Initial release of automatic HLTV recording triggered by KTPMatchHandler forwards. Sends UDP RCON commands to paired HLTV server instances. Demo files named by match type and ID for easy organization.

- **KTPCvarChecker v7.5-7.7**: Added `cl_filterstuffcmd` detection - this client cvar can be abused to ignore server cvar queries. Integrated shared Discord notification via `ktp_discord.inc`.

- **KTPAdminAudit v1.2-2.2**: v1.2.0 established initial admin audit logging. v2.1.0 added menu-based kick/ban interface with ReHLDS integration for reliable client dropping. v2.2.0 added RCON audit logging via the new `RH_SV_Rcon` hook.

- **KTPFileDistributor v1.0.0**: Initial release of the file distribution server. Node.js service that serves game files to servers clients and notifies Discord when files are downloaded. Helps track which servers have successfully received the uploads. Used for rapid deployment of updates (maps, configs, plugin updates, etc.)

- **KTPHLStatsX**: Set up HLStatsX:CE (Community Edition) with KTP-specific modifications. Added match ID tracking support so stats can be correlated to specific matches. Integrated with KTPMatchHandler's `KTP_MATCH_START` and `KTP_MATCH_END` log markers.

- **Discord Relay v1.0.1**: Bug fix for `fetchWithRetries()` argument format.

---

## January 2026 - Stability & Polish

**Focus: Production Hardening & Administrative Tools**

January focused on production stability, fixing edge cases discovered during real matches, and adding administrative tools. The explicit overtime command system was a significant rework based on player feedback.

### KTPMatchHandler v0.10.30-0.10.65

| Version Range | Key Changes |
|---------------|-------------|
| v0.10.27-28 | Changelevel hooks (`RH_PF_changelevel_I`) for reliable match state finalization |
| v0.10.30 | `.commands` help listing, HLTV reminders, 2nd half pending HUD |
| v0.10.32-34 | Critical OT recursive loop crash fix |
| v0.10.35 | Tactical pauses disabled (tech-only policy) |
| v0.10.36 | Discord channel routing for 12man/draft matches |
| v0.10.37 | Server hostname in match IDs |
| **v0.10.38** | **1.3 Community Discord 12man integration** with Queue ID |
| v0.10.41 | Map config prefix matching fix (longer keys first) |
| **v0.10.43** | **Explicit `.ktpOT` and `.draftOT` commands** (replaces automatic OT) |
| v0.10.44 | Intermission auto-DC fix |
| v0.10.45 | Dynamic server hostname reflecting match state |
| v0.10.46 | Match-type-specific ready requirements (6v6 KTP, 5v5 others) |
| **v0.10.47** | **`.forcereset` admin command** for recovering abandoned servers |
| v0.10.48 | ~190 lines dead code cleanup, compiler warnings fixed |
| v0.10.49 | Standard AMXX logging for daily rotation |
| v0.10.50-52 | Roster and ready counter bugs after halftime |
| **v0.10.53** | **Auto-DC tuning** (30s delay, competitive-only) |
| v0.10.54 | Experimental pause overlay disable (`showpause 0`) |
| **v0.10.55** | **`.cancel` during 2nd half pending**, Discord embed uniformity |
| **v0.10.59** | **Simplified match IDs** (`{timestamp}-{shortHostname}`), hostname timing fix |
| v0.10.60 | Expanded `.commands` output with admin/other plugin commands |
| **v0.10.61** | **Ready team label fix** - shows "Allies"/"Axis" not team identity in 2nd half |
| **v0.10.62** | **Draft match duration** - 15-minute halves (was 20 minutes) |
| v0.10.63 | `.grenade` in `.commands` help, hostname caching fix (1s delay) |
| v0.10.64 | Pause chat relay via `client_print` bypass |
| **v0.10.65** | **Silent pause mode** - `ktp_silent_pause` cvar hides client overlay |

### Other Component Updates

| Component | Version | Key Changes |
|-----------|---------|-------------|
| **KTP-ReHLDS** | v3.22.0.904 | Silent pause mode (`ktp_silent_pause`), hostname broadcast hooks |
| **KTPAMXX** | v2.6.7 | `dod_damage_pre` forward, grenade natives, player manipulation natives, noclip |
| **KTPReAPI** | v5.29.0.362-ktp | Map change interception hooks (`RH_PF_changelevel_I`, `RH_Host_Changelevel_f`) |
| **KTPCvarChecker** | v7.12 | Debug cleanup, Discord toggle cvar, KTP emoji branding, notification grouping |
| **KTPFileChecker** | v2.3 | Discord notification grouping, fc_checkmodels cvar |
| **KTPAdminAudit** | v2.7.3 | Map change auditing, RCON quit/exit blocking, changemap countdown fix |
| **KTPAmxxCurl** | v1.2.0-ktp | Use-after-free fix, handle allocation fix, socket map cleanup |
| **KTPFileDistributor** | v1.1.0 | Multi-channel Discord support |
| **KTPHLStatsX** | v0.2.2 | Player tracking, stats aggregation, half detection regex, debug logging |

### New Plugins (January 2026)

| Component | Version | Description |
|-----------|---------|-------------|
| **KTPPracticeMode** | v1.3.0 | Practice mode with infinite grenades, HUD indicator, `.grenade` command |
| **KTPGrenadeLoadout** | v1.0.3 | Custom grenade loadouts per class via INI config |
| **KTPGrenadeDamage** | v1.0.2 | Grenade damage reduction by configurable percentage |

### KTPHLTVRecorder v1.0.4-1.3.0

| Version | Changes |
|---------|---------|
| v1.0.4 | Config parsing fix, improved logging |
| **v1.1.0-1.1.1** | **Major rewrite: HTTP API** replaces UDP RCON via FIFO pipes |
| v1.2.0 | Match type support for all KTPMatchHandler types |
| **v1.2.1** | **`.hltvrestart` admin command** with Discord audit notification |
| **v1.2.2** | Orphaned recording cleanup on plugin startup/shutdown |
| **v1.3.0** | **Per-half demo files** - each half gets `_h1`, `_h2`, `_ot1` suffix |

- **KTPCvarChecker v7.8-7.9**: v7.8 cleaned up debug logging. v7.9 added Discord toggle cvar for enabling/disabling notifications.

- **KTPAdminAudit v2.6.0**: Added map change command auditing, server control command tracking, and console command audit logging.

- **KTPAmxxCurl**: Fixed critical segfaults in async curl handling - use-after-free bugs where raw pointers were passed to ASIO async callbacks and could be deleted before callback execution. Changed to `shared_ptr` tracking. Fixed handle allocation collision bug and stale socket map entries.

- **KTPFileDistributor v1.1.0**: Added multi-channel Discord support via `AdditionalChannelIds` configuration.

- **Server Infrastructure**: Deployed Atlanta 2-5 server cluster (ports 27016-27019) with full LinuxGSM configuration, HLStatsX integration, and KTPFileDistributor setup. Configured HLTV instances 27021-27024 with systemd services and scheduled restart timers. Diagnosed and fixed UDP buffer exhaustion issue (47k+ RcvbufErrors) by increasing kernel buffer sizes from 208KB to 25MB. Documented server setup procedures for future deployments. **Deployed Dallas game server cluster** (74.91.114.178, ports 27015-27019) with identical configuration. **Added nightly scheduled restarts** at 3 AM ET for both Atlanta and Dallas game servers with Discord embed notifications (live-updating: shows "In Progress" then edits to "Complete"). Fixed LinuxGSM "old type tmux session" bug that caused spurious server restarts by patching `command_monitor.sh` on all instances.

---

## February 2026 - Bare Metal & Performance

**Focus: Infrastructure Migration & Performance Optimization**

February marked the transition from VPS hosting to dedicated bare metal servers, eliminating CPU steal issues that plagued competitive matches. Significant performance optimization research led to new engine-level profiling capabilities.

### Bare Metal Deployment

| Server | IP | Hardware | Status |
|--------|-----|----------|--------|
| Denver | 66.163.114.109 | Xeon E3-1240 V2, 16GB | Deployed 01/30 |
| Atlanta | 74.91.121.9 | Xeon E3-1271v3, 32GB | Deployed 02/01 |
| Dallas | 74.91.126.55 | Xeon E3-1271v3, 32GB | Deployed 02/03 |

**Why Bare Metal:** GoldSrc's 1000 tick rate is especially vulnerable to CPU steal. A 20ms steal at 1000 tick means 20 missed ticks, while the same steal at 64 tick (CS2) only misses ~1 tick.

### KTP-ReHLDS v3.22.0.904

**Frame Profiling System:**
- `ktp_profile_frame` cvar - Enable/disable frame time profiling
- `ktp_profile_interval` cvar - Seconds between summary logs (default: 10)
- Tracks: SV_ReadPackets, SV_Physics, SV_SendClientMessages, peak edict count
- Low overhead: accumulates per-frame, logs summary every N seconds

**Host_FilterTime FPS Fix:**
- Original: `1.0f / (fps + 1.0f)` capped servers at sys_ticrate - 1
- Fixed: `1.0 / fps` allows true 1000 fps at sys_ticrate 1000
- Changed `fps` variable from float to double for precision

### KTPAMXX v2.6.8-2.6.9

**v2.6.9:**
- Runtime pdata offset detection - auto-detects Linux offsets for grenade manipulation
- Ubuntu 22.04: +5 offset adjustment, Ubuntu 24.04: +4 offset adjustment
- Eliminates need for separate binaries per OS version
- Admin flag accumulation bug fix - admin flags now accumulate correctly across multiple entries

**v2.6.8 - Extension Mode Header Stubs:**
- Complete Metamod-free compilation support for third-party modules
- Enables modules like amxxcurl to compile without Metamod SDK headers

### KTPMatchHandler v0.10.66-0.10.69

**v0.10.69:**
- `ktp_match_competitive` cvar for programmatic match state detection
- `KTP_HALF_END` log event for accurate first-half end time in HLStatsX
- Team name reset on match end (prevents stale names carrying over)

**v0.10.68:**
- Team name reset fix for match cleanup

**v0.10.67:**
- HLStatsX stats timing - Reduced KTP_MATCH_START delay from 100ms to 10ms
- Abandoned match stats fix - Added `dodx_flush_all_stats()` before KTP_MATCH_END
- Enhanced changelevel debug logging for map transition diagnostics

**v0.10.66:**
- HLStatsX first half stats fix - KTP_MATCH_START log now uses delayed task

### KTPHLTVRecorder v1.4.0

- Pre-match HLTV health check before starting recording
- Automatic recovery attempt if health check fails
- Discord + in-game chat alerts when recording may not work
- Callback failure detection for recording command errors

### KTPAmxxCurl v1.2.1-ktp

- Forward registration validation prevents silent callback failures
- Detailed callback logging with forward ID
- WriteCallback diagnostics and graceful fallback

### KTPInfrastructure v1.1.0-1.2.0

**v1.2.0:**
- Comprehensive performance optimizations in `provision-gameserver.sh`
- Ubuntu 24.04 support with auto-detection
- Memory optimizations: THP, KSM, compaction disabled
- Network optimizations: GRO/LRO/TSO disabled, conntrack bypass
- `ktp-chrt.timer` - Auto-applies real-time scheduling every 30 seconds

**v1.1.0:**
- LinuxGSM monitor bug fix documentation (HIGH PRIORITY)
- Ubuntu optimization research documentation

### Other Updates (Feb 1-6)

| Component | Version | Changes |
|-----------|---------|---------|
| KTPGrenadeLoadout | v1.0.5 | Batch spawn processing fix (196ms spike eliminated) |
| KTPHLStatsX | v0.2.5 | KTP_HALF_END handler for accurate H1 end_time |
| KTPCvarChecker | v7.12 | Emoji removal from headers, documentation cleanup |

### Codebase Review (Feb 1-6)

Systematic review across all 16+ KTP projects:
- Documentation cleanup: emoji removal from headers, stale version fixes
- Dead code removal and unused variable cleanup
- CLAUDE.md gitignore audit across all projects
- README/CHANGELOG consistency pass

### Feb 7-19: Frame Profiling & Lag Investigation

Deep investigation into recurring lag spikes reported by players during competitive matches. Built comprehensive profiling tools at the engine level.

**KTP-ReHLDS Frame Profiling:**
- 6-phase frame timing: read (SV_ReadPackets), phys (SV_Physics), misc1, send (SV_SendClientMessages), post, steam
- `[KTP_SPIKE]` log alerts when any phase exceeds configurable thresholds
- Per-opcode instrumentation for granular packet processing analysis
- SV_ParseMove CPU-time profiling to isolate per-client processing costs

**Engine Changes:**
- MAX_RATE raised from 100,000 to 1,000,000 in net.h (allows higher client rate settings)
- HLTV interp buffer reduced from 50ms to 15ms for lower latency spectating
- MAX_PROXY_UPDATERATE raised to 200

**Key Findings:**
- Discovered `clc_cvarvalue2` causing 160-185ms frame freezes (KTPCvarChecker bug - synchronous cvar queries blocking the frame loop)
- Steam API processing confirmed negligible (<0.055ms)
- Spikes are 100% in `read` phase (SV_ReadPackets) - single client packets taking 3-6ms to process
- `profiling-report.py` tool built for multi-server spike analysis across all locations

### Feb 17-19: New York & Chicago Deployments

Expanded server fleet with two new locations for scrim play.

| Server | IP | Hardware | Branding |
|--------|-----|----------|----------|
| New York 1-5 | 74.91.123.64 | Baremetal | KTPSCRIM - New York 1-5 |
| Chicago 1-5 | 172.238.176.101 | KVM VPS | KTPSCRIM - Chicago 1-5 |

- Total fleet: **25 game servers** across 5 locations (Atlanta, Dallas, Denver, New York, Chicago)
- 25 HLTV proxy instances on data server (ports 27020-27044)
- Full KTP stack deployment with clone-ktp-stack.sh provisioning
- LinuxGSM monitor bug patch applied to all new instances

### Feb 17: KTPAMXX v2.6.10 - plugin_init Memory Leak Fix

Critical extension mode bug where subsystem re-registration on every map change caused unbounded memory growth.

**Problem:** In extension mode, `plugin_init` re-registered all commands, forwards, events, log events, messages, and menus on each map change without cleanup. Growth rate: ~2ms per map change, reaching 107ms+ after 50 map changes.

**Two-pronged fix:**
1. `modules_callPluginsUnloading()` called before `plugin_init` - lets ReAPI clear hookchain vectors (100% plugin-owned)
2. Dedup-at-registration for all 7 subsystems: commands, SP forwards, multi-forwards, events, log events, messages, menus

**Result:** `plugin_init` flat at ~0.9ms regardless of map changes (120x improvement over post-leak state).

**Critical lesson learned:** No subsystem cleanup (`g_commands.clear()` etc.) is safe because C++ modules register state during `AMXX_Attach`. Dedup-at-registration is the correct approach.

### Feb 20-24: KTPMatchHandler v0.10.70-0.10.82

| Version | Key Changes |
|---------|-------------|
| v0.10.72-73 | Discord consolidated embeds with live-updating scores during match |
| **v0.10.74** | **Halftime changelevel watchdog** - fixes NY5 infinite changelevel loop |
| **v0.10.75** | **Menu crash fix** - ATL1 segfault from menu callback during map change |
| **v0.10.77** | **Discord curl use-after-free fix** - shared header slist across async requests |
| **v0.10.78** | **pfnChangeLevel rate limiting** - 6.8M daily log lines from changelevel spam |
| **v0.10.82** | **pfnChangeLevel debounce** - 26M+ calls reduced to 1 per intermission, 11 crashes fixed, ~10GB logs cleaned |

### Feb 20-24: Infrastructure Optimization

Comprehensive performance tuning across all bare metal servers.

**Rate Settings Standardized (all 25 servers):**
- `sv_maxrate 1000000` (was mixed values)
- `sv_maxupdaterate 120` (reverted from 200 - DoD client.dll clamps, breaks above 120)

**CPU Isolation & Pinning:**
- Kernel boot params: `isolcpus=2,3,5,6,7 nohz_full=2,3,5,6,7 rcu_nocbs=2,3,5,6,7`
- IRQ affinity steering to housekeeping CPUs 0,1,4 (bitmask 0x13) via rc.local
- Per-port CPU pinning: 27015→CPU2, 27016→CPU3, 27017→CPU5, 27018→CPU6, 27019→CPU7
- Chicago (4 vCPU, no isolcpus): 27015→1, 27016→2, 27017→3, 27018+27019→0
- `SCHED_FIFO` priority 50 (upgraded from `SCHED_RR` 20)
- `ktp-apply-chrt.sh` runs every 30s via `ktp-chrt.timer`
- `ktp-scheduled-restart.sh` applies pinning immediately after server start

**Result:** OS scheduling stalls reduced from 9,445 to 0.

### Feb 25-27: Systematic Bug Audit

**Phase 1 - Six Components:**

| Component | Version | Key Fixes |
|-----------|---------|-----------|
| **KTPAmxxCurl** | v1.3.0-1.3.1-ktp | `curl_get_response_body` native added, 4 bug fixes |
| **KTPAMXX** | v2.6.11 | SP forward dedup crash fix, null guards, infinite loop fix, bounds fix |
| **KTPCvarChecker** | v7.17 | Range enforcement fix (clamps to nearest valid bound instead of rejecting) |
| **KTPAdminAudit** | v2.7.5 | Changemap race condition fix, menu buffer size increase |
| **KTPHLStatsX** | v0.2.7 | 4 data integrity fixes: headshot flush timing, duplicate player handling, start_time accuracy, TK/suicide aggregation |
| **KTPHLTVRecorder** | v1.5.2 | HTTP response validation, auth header fix, demo cutoff fix |

**Phase 2 - KTPMatchHandler + Full Deploy:**

- **KTPMatchHandler v0.10.83:** Discord code extraction (~980 lines into helper functions), 6 bug fixes, ~165 lines dead code removed
- **KTPMatchHandler v0.10.84:** HTTP response validation for all curl callbacks, OT break state cleanup, additional dead code removal
- Full stack recompile + deploy to all 25 servers (325 file uploads via paramiko SFTP)

### Feb 27: Critical Crash Fix (Post-Deploy)

4 segfaults (3x New York, 1x Atlanta) traced to SP forward dedup parameter type mismatch in KTPAMXX `CForward.cpp`.

**Root Cause:** Same Pawn function registered as both a menu callback (`FP_CELL`) and a curl callback (`FP_STRING`). The dedup logic matched on function name alone, so when the curl callback fired, it found the menu forward (registered first) and passed a string pointer where an integer was expected. Integer menu selection value `1` cast to `char*` → `strlen(0x1)` → segfault.

**Fix:** Added `numParams` + `paramTypes` comparison via `memcmp` to both `registerSPForward` overloads. Forwards with the same function name but different signatures are now correctly treated as distinct forwards.

Rebuilt KTPAMXX v2.6.11, deployed to all 25 servers, verified stable.

### Other Updates (Feb 7-28)

| Component | Version | Changes |
|-----------|---------|---------|
| KTPHLTVRecorder | v1.5.2 | Demo cutoff fix, use-after-free fix, HTTP response validation |
| KTPCvarChecker | v7.17 | Fixed cvar polling, async enforcement, range correction |
| KTPAdminAudit | v2.7.5 | Changemap race condition, menu buffer increase |
| KTPAmxxCurl | v1.3.1-ktp | Response body capture native, 4 bug fixes |
| KTPHLStatsX | v0.2.7 | Headshot flush, duplicate players, TK/suicide aggregation |
| KTPInfrastructure | v1.4.0 | CPU isolation, per-port pinning, SCHED_FIFO 50 |
| KTPGrenadeLoadout | v1.0.5 | (unchanged) |
| KTPGrenadeDamage | v1.0.2 | (unchanged) |
| KTPPracticeMode | v1.3.0 | (unchanged) |

### Infrastructure Optimizations Applied

All bare metal servers (Atlanta, Dallas, Denver, New York) now have:
- Lowlatency kernel (1000Hz) + pingboost 2
- CPU mitigations disabled (`mitigations=off`)
- ALL C-states disabled (`max_cstate=0`)
- 25MB UDP buffers
- Real-time scheduling via systemd timer
- Persistent optimizations via `/etc/rc.local`
- **CPU isolation:** `isolcpus` + `nohz_full` + `rcu_nocbs` on game server CPUs
- **IRQ affinity:** All hardware interrupts steered to housekeeping CPUs (0, 1, 4)
- **Per-port CPU pinning:** Each game server instance pinned to a dedicated CPU core
- **SCHED_FIFO 50:** Real-time scheduling priority for all game server processes
- **ktp-chrt.timer:** Systemd timer re-applies CPU pinning + scheduling every 30 seconds

Chicago (KVM VPS, 4 vCPU) has all optimizations except `isolcpus` (insufficient cores) with adjusted CPU pinning layout.

---

## March 2026 - JIT & Code Review

**Focus: KTPAMXX Code Review, JIT Re-Enablement, Fleet-Wide Plugin Audit**

March centered on a comprehensive three-round code review of the KTPAMXX engine (the platform all plugins run on), producing 60+ fixes across all layers of the stack. The headline discovery was that JIT compilation had been disabled since the KTP fork was created — every plugin had been running through the slow C interpreter since launch.

### KTPAMXX v2.6.16-2.7.2 — Engine Code Review + JIT

**v2.6.16-2.6.18 (Mar 7-13):** Pre-review fixes including DODX pdata offset auto-detection rewrite (two-phase write-then-verify), halftime score zeroing fix (scores were being reset to 0 before KTPMatchHandler could read them), and DODX detection log spam cleanup.

**v2.7.0 (Mar 13) — Code Review Round 1 + JIT Re-Enablement:**

Three rounds of code review across the entire KTPAMXX codebase covering core runtime, module SDK, DODX module, and build system. All reviewed through the lens of extension mode operation (no Metamod).

| Category | Findings |
|----------|----------|
| Critical | 8 (7 fixed, 1 was not a bug) |
| Warning | 17 (12 fixed, 2 not bugs, 3 deferred) |

**JIT/ASM32 Re-Enablement (Critical #1):** The JIT compiler and x86 ASM dispatcher were disabled with a "KTP DEBUG" label since the initial fork to get extension mode working. All Pawn plugins had been running through the slow C interpreter since day one. Re-enabled native x86 JIT compilation and hand-optimized ASM dispatcher.

Measured impact — fleet-wide profiling data (~290k pre-JIT intervals vs ~65k post-JIT):
```
                    Before      After
Avg frame time      0.026ms     0.020ms   (-23%)
Worst spike         1.84ms      0.17ms    (-91%)
Min FPS floor       351         845       (+141%)
```

Other critical fixes: security hardening (`-fstack-protector-strong`, `FORTIFY_SOURCE=2`, full RELRO), module SDK double-free in `rewriteNativeLists`, stale frame callbacks after module detach, DODX weapon ID bounds checks, `C_ClientCvarChanged` player guard.

**v2.7.1 (Mar 13) — Code Review Round 2:**
5 criticals and 8 warnings. Key fix: **shot double-counting** — both button-state detection AND CurWeapon clip-decrement detection were running simultaneously, inflating HLStatsX accuracy stats since extension mode was enabled. Other fixes: SP forward null deref, `dod_weaponlist` OOB, event parser off-by-one, entity leak in `dodx_give_grenade`.

**v2.7.2 (Mar 13) — Code Review Round 3:**
CLogEvent last-char trim (silently dropped closing `"` on all DoD log events in extension mode), MessageHook_Handler null chain propagation, say/say_team prefix list separation.

### KTPAMXX — ClearPluginLibraries Crash Fix (Mar 14)

`.changemap` command intermittently crashed servers with segfault at page-aligned addresses. Core dump analysis revealed native function pointer `0xea35e000` pointed to `munmap`'d memory. Root cause: `ClearPluginLibraries()` freed executable thunk pages allocated by `register_native()` for cross-plugin natives, but `plugin_natives()` is never re-called during reload. Fix: removed `ClearPluginLibraries()` from the reload path.

### KTPMatchHandler v0.10.91-0.10.100

| Version | Key Changes |
|---------|-------------|
| v0.10.91 | Idle command hint (120s interval, suppressed during matches) |
| **v0.10.92** | **12 fixes**: OT tech budget persistence, auto-DC pause duration, stale state cleanup, pause warning timing |
| v0.10.93 | OT score display fix (`.score` showed swapped teams), auto-confirm leak |
| **v0.10.96** | **OT timing fix** (timelimit before restart), **roster SteamID exact match**, pause cache monotonic counter, roster buffer overflow fix |
| **v0.10.97** | **Deferred match start** — split ~160ms synchronous work into 3 phases across multiple frames |
| v0.10.98 | Discord channel routing (separate default channel for non-match notifications) |
| v0.10.99 | Deferred pending phase — confirm command frame reduced by ~15-20ms |
| **v0.10.100** | **Say hook fast path** — ordinary chat (~99% of say traffic) returns after reading 4 bytes |

### Fleet-Wide Plugin Code Review (Mar 14)

Systematic security/correctness review of all KTP plugins. Seven plugins scanned clean, three required fixes:

| Plugin | Version | Fixes |
|--------|---------|-------|
| KTPFileChecker | v2.4 | Command injection via player names in `server_cmd("say")`, task ID collision |
| KTPGrenadeLoadout | v1.0.6 | `log_amx` format string vuln, map change state reset, task ID safety |
| KTPPracticeMode | v1.3.1 | Task ID raw player ID → constant offset |

### Other Component Updates (Mar 7-14)

| Component | Version | Key Changes |
|-----------|---------|-------------|
| **KTPAmxxCurl** | v1.3.4-1.3.5-ktp | In-flight AMX validity checks, `CURLOPT_COPYPOSTFIELDS` auto-upgrade for async, deferred cleanup, 64KB response cap |
| **KTPCvarChecker** | v7.18-7.20 | Enforcement accuracy (rate limiter was dropping legitimate events), deferred enforcement queue, Discord task leak (doubled notifications) |
| **KTPAdminAudit** | v2.7.9-2.7.11 | Slot recycling TOCTOU fix (validates SteamID at execution), deferred ban file flush, task ID safety |
| **KTPHLTVRecorder** | v1.5.3-1.5.4 | Second half demo cutoff fix, delayed recording task ID, 35s recovery delay (was 5s), concurrent `.hltvrestart` fix |
| **KTPGrenadeDamage** | v1.0.3 | TK damage incorrectly reduced by damage reduction setting |
| **KTP-ReHLDS** | v3.22.0.908-909 | Spawn sub-phase profiling (`[KTP_SPAWN]`, `[KTP_WRITESPAWN]` log lines for HLTV connect overhead diagnosis) |
| **ktp_discord.inc** | v1.3.4 | Embed description truncation fix (383→2200 char buffer), payload buffer 1024→3072 |
| **KTPHLStatsX** | v0.3.0-0.3.2 | Major performance optimizations (drain-then-process UDP, batched frag UPDATEs, event queue 10→100), per-half stat breakdown, headshot tracking fix |
| **KTPInfrastructure** | v1.4.1-1.5.0 | Variable server count support (`--num-servers`), co-located HLTV (`--with-hltv`), `noatime` mount option, CPU pinning audit fixes |
| **KTPFileDistributor** | v1.1.1 | Shutdown Discord notification now uses embed format |

### Infrastructure Updates (Mar 11)

- **New York & Chicago rebranded** from "KTPSCRIM" to "KTP" with join password "KTP"
- **CPU isolation layout updated** on all baremetals: `isolcpus=2,3,4,5,6,7` (was 2,3,5,6,7), IRQ affinity bitmask 0x03 (was 0x13), game server pinning: 27015→CPU2, 27016→CPU5, 27017→CPU4, 27018→CPU3, 27019→CPU7 (HT-aware)
- All 5 locations rebooted with updated kernel parameters

### Mar 16-19: KTPMatchHandler v0.10.101-0.10.103

| Version | Key Changes |
|---------|-------------|
| **v0.10.101** | **Round-state filtering for HLStatsX** — hooks `RoundState` message to pause DODX stats during freeze periods, eliminating ~1% phantom kill over-counting. Three-layer defense: DODX native, log events, event-driven match context setup with 5s timeout |
| **v0.10.102** | **Periodic score save fix** — 30s repeating task was silently dying after initial one-shot due to SP forward dedup sharing the same forward handle. Split into separate one-shot/repeating functions |
| v0.10.102 | **HLTV recording fix** — Practice Mode hostname suffix broke match ID extraction, causing space in demo filename that HLTV rejected |
| v0.10.102 | **Phase 0 frame stall reduction** — Deferred roster snapshot + hostname update to Phase 2, saving ~25-60ms from `.ready` command frame |
| **v0.10.103** | **Timelimit expiry during ready-up fix** — If `mp_timelimit` expired during pending state, changelevel hook blocked indefinitely; game DLL logged `"TeamName" scored` every frame (~2000 lines/sec). NY1 incident: 35M scored lines, 5.4GB logs over 11 hours. Now detects and allows map change |

### Mar 19: KTP-ReHLDS v3.22.0.910

- Raised `sv_unlagsamples` cap from 16 to 64 (full `SV_UPDATE_BACKUP` frame buffer). At 1000Hz, the old 16-sample cap only covered 16ms of ping history — insufficient for meaningful smoothing
- Scaled jitter detection window in `SV_CalcClientTime()` to match the averaging window

### Mar 17: KTPHLTVRecorder v1.5.5

- Recording verification with in-game chat feedback after `record` command
- Curl timeout for record commands increased from 5s to 8s
- HLTV API updated to v2.1

### Mar 23-26: KTPMatchHandler v0.10.104-0.10.110

| Version | Key Changes |
|---------|-------------|
| **v0.10.104** | **Periodic score save caused 5.1ms inter-frame gaps** every 30s on isolated CPUs from `log_amx()` filesystem I/O. Increased interval to 120s, skip I/O when scores unchanged |
| **v0.10.105** | **`.scrim` duration menu** — scrims now offer 20min/15min selection like `.12man`. **Queue ID 60s auto-timeout** — prevents stuck 1.3 Community input flow. Discord embed buffer 2048→4096 for 12-player rosters. Negative 2nd-half score clamping. OT round limit (31) now fires match end forward. OT score display fix for Discord embeds. O(n²) `strlen` eliminated in roster builds |
| v0.10.106 | **`msg_TeamScore` early exit** — hoisted `!g_matchLive` guard before all work, eliminating processing during ~9000/sec intermission storm. Removed debug `log_ktp` calls from message handler and Discord routing |
| v0.10.107 | **Score tracking regression fix** — v0.10.106 early exit blocked score tracking during intermission when final TeamScore messages arrive |
| v0.10.108 | Halftime score save fix — removed `update_match_scores_from_dodx()` call (wrong diagnosis, see v0.10.110) |
| v0.10.109 | Diagnostic logging for score tracking (`PERIODIC_SCORE_DEBUG`, `HALFTIME_SCORE_DEBUG`) |
| **v0.10.110** | **Score persistence root cause found** — `dod_get_team_score()` returns 0 in extension mode because DODX's `Client_TeamScore` message handler never receives TeamScore messages. Switched to `dodx_get_team_score()` which reads directly from gamerules memory. Removed incorrect v0.10.108 fix and v0.10.109 diagnostics |

### Mar 24: KTPAMXX v2.7.4

| Fix | Details |
|-----|---------|
| **Message Hook RemoveHook wrong index** | `m_Forwards.remove(forward)` removed at position `forward` (SP forward ID) instead of position `i` (matched entry). Stale forward IDs accumulated every map change cycle |
| **Client_ObjScore stale player pointer** | Static `CPlayer*` used across message parse states without revalidation — freed edict between states corrupted memory |
| **PreThink fallback init removed** | `ENTINDEX()` engine call during early init replaced with hard guard |
| **CPlayer::Disconnect missing edict free check** | `ignoreBots(pEdict)` dereferenced freed entity flags during crash sequences |
| **Event/LogEvent dedup O(n) eliminated** | Added `m_HandleId` field for O(1) handle lookup during dedup |
| **Rank save skipped in extension mode** | Unnecessary file I/O during `ServerDeactivate` |
| **CTaskMngr::startFrame use-after-realloc** | Cached task reference invalidated if callback called `set_task()` → vector reallocation |
| **`dodx_set_stats_paused` native added** | Allows plugins to pause/unpause DODX stats collection (used for round-freeze filtering) |

### Mar 24: KTP-ReHLDS v3.22.0.911-912

**v3.22.0.912 — Profiler overhead optimization:**
- Physics sub-phase timing (separates `pfnStartFrame` from entity loop)
- Per-client send timing (identifies worst client per frame)
- Double `Sys_FloatTime()` in SV_RunCmd boundaries eliminated
- 10 unconditional global writes gated on profiling flag (10,000 cache-dirtying writes/sec eliminated on production)
- Cvar dereference consolidated into single `g_ktp_profiling_enabled` global (10,000+ reads/sec eliminated)
- Steam/frame-end profiling blocks merged (redundant syscall removed)

**v3.22.0.911 — Profiling accuracy + pause efficiency:**
- Pause force-send limited to clients with pending data (was forcing ALL clients every frame at 1000Hz)
- Rate limiter clock source unified (`Sys_FloatTime()` everywhere)
- Double `Sys_FloatTime()` eliminated in per-packet profiling
- String command rate limiter bypass scoped to current client only
- Interframe average now uses dedicated frame counter

### Mar 24: Fleet-Wide Plugin Hardening Pass

Systematic correctness review and performance optimization across all KTP plugins:

| Component | Version | Key Changes |
|-----------|---------|-------------|
| **KTPCvarChecker** | v7.21-7.22 | Trie-based cvar lookup (performance), `rate` locked to exact 100000, `cl_updaterate` max lowered to 120, `ex_interp` range adjusted 0.01-0.05, `lightgamma` floor corrected, `cl_smoothtime` enforcement removed |
| **KTPFileChecker** | v2.5 | Server broadcast no longer reveals file paths/SteamIDs, `.mdl` case-sensitive compare, `MAX_FILENAME_LEN` 64→128, `plugin_end` cancels pending Discord instead of flushing |
| **KTPAdminAudit** | v2.7.12 | Ban duration menu shows wrong name if target disconnected (fixed), `task_flush_banlist` accumulation guard, changelevel hook blocked match-end changelevel during countdown (fixed) |
| **KTPPracticeMode** | v1.3.2 | `client_death` clears noclip engine state, hostname restore race fix (1.5s vs 0.5s), British team support in `.grenade`, repeating task accumulation guard, hostname buffer 64→128 |
| **KTPHLTVRecorder** | v1.5.6 | Delayed stop preservation fix, `init_curl_headers` use-after-free fix, `g_hltvApiUrl` buffer 128→256, dead port validation guard removed |
| **KTPAmxxCurl** | v1.3.6-ktp | `curl_global_cleanup` leak on detach, `curl_formadd` params array bounds fix, `OnAmxxDetach` timeout using wall-clock timing, `CurlReset` re-binding WriteCallback |

---

### Apr 3-5: KTPMatchHandler v0.10.111, KTPPracticeMode v1.4.0, KTPAMXX v2.7.5-2.7.6

| Version | Key Changes |
|---------|-------------|
| **v0.10.111** | **Pause chat relay fix** — `handle_pause_chat_relay` was silently broken by KTPAMXX's command registration dedup system. `registerCommand()` dedup prevents same plugin from registering two handlers for "say" — merged relay logic into `cmd_say_hook` and `cmd_say_team_hook` |
| **KTPAMXX v2.7.5** | **DODX extension mode player init** — `g_pFirstEdict` NULL on first map (SV_ActivateServer hook registered too late). Fallback `INDEXENT(0)` init. Also: `isModuleActive()` gate moved after player init in PreThink |
| **KTPAMXX v2.7.6** | **Discord TLS handshake fix** — 164ms freeze on first Discord notification. Added connection keepalive, DNS caching, prewarm health check |
| **KTPPracticeMode v1.4.0** | **`.grenade`, `.noclip`, explosion refill fixed** — all broken by DODX CPlayer not initializing on first map. `.grenade` now always calls `dodx_give_grenade` + `dodx_set_grenade_ammo` + `dodx_send_ammox` (game removes weapon entity when last grenade thrown) |

### Apr 13: KTP-ReHLDS v3.22.0.913 (Background Steam Thread)

Steam API calls (`SteamGameServer_RunCallbacks` and `GetNextOutgoingPacket`) moved to a dedicated background thread via lock-free SPSC ring buffer. Previously blocked the main game thread for 3-13ms every 100ms. Now `steam=0.000ms` across all servers. Frag update interval increased from 1s to 5s.

### Apr 14: Full Stack Optimization Pass

#### KTP-ReHLDS v3.22.0.914-916

| Version | Key Changes |
|---------|-------------|
| **v914** | **Lag compensation per-packet** — `SV_SetupMove`/`SV_RestoreMove` moved from per-cmd (SV_RunCmd) to per-packet (SV_ParseMove). ~90% reduction in lag comp overhead. **Entity early-break** in SV_SetupMove. **Nodelta during pause** limited to 3 transition frames. **IPTOS_LOWDELAY** always-on. Compiler: `-march=ivybridge -flto -fno-math-errno` |
| **v915** | **REHLDS_OPT_PEDANTIC re-enabled** with wallbang-safe overrides — `shouldCollide()` kept early, `AddToFullPack` pre-filter removed. Enables: iterative BSP traversal, model hash map, delta JIT, challenge circular buffer, usercmd delta caching, packet entity pre-allocation |
| **v916** | Per-frame cvar caching (`sv_timeout`) |

#### KTP-ReAPI v5.29.0.364-ktp

Compiler optimizations: `-march=ivybridge -flto -fno-math-errno`.

#### KTPAMXX v2.7.7-2.7.9

| Version | Key Changes |
|---------|-------------|
| **v2.7.7** | Compiler: `-O3` (was `-O2`), `-march=ivybridge`, `-flto`, `-fno-math-errno` |
| **v2.7.8** | `g_putinserver` vector → `uint32_t` bitmask. Module frame callback length cache. DODX TraceLine `strcmp` → `ALLOC_STRING` integer comparison |
| **v2.7.9** | Event vault pre-allocation (no dynamic growth). `WeaponsCheck` XOR + `__builtin_ctz` (42 iterations → ~2-3). Grenade linked list → 32-entry fixed pool |

#### KTPAmxxCurl v1.3.7-ktp

CMake migration (replaced Premake5). Compiler optimizations. 5 bug fixes: `strcpy` overflow, memory leak catch-all, `SetSock` UB (exception in libcurl callback), `AddCurl` exception safety, detach busy-spin. **Critical: missing `amx_curl_callback_class.cc` in CMakeLists.txt caused `TryInterrupt` undefined symbol — curl module failed to load, breaking all plugins using `ktp_discord.inc`.**

#### KTPMatchHandler v0.10.112

OT scores buffer overflow: `ot_scores[256]` too small for `MAX_OT_ROUNDS` (31) × ~12 bytes = 372 bytes. Increased to 512. Triggered in extended OT (round 16+).

#### KTPFileChecker v2.6

Discord slot reuse race condition (compare authid not slot ID). Log message buffer 256→512. Discord truncation `pos +=` fix.

#### KTPFileDistributor v1.1.2

`ChangeDebouncer` `async void` → `async Task` (crash prevention). `BuildRemotePath` path traversal rejection. `EnsureRemoteDirectoryExists` specific exception catching.

#### Profiler Results (Post-Optimization)

Average frame time: **0.012ms** (12 microseconds). Server FPS: 980+. Steam: 0.000ms. 2 spikes in 5.5 hours (kernel scheduling). Interframe jitter: avg 1.007ms, peak 1.134ms. **98.8% of each frame is idle.**

---

## Related Documentation

> For granular per-version changelogs, see the `CHANGELOG.md` in each project's repository.

- [technical_guide.md](./technical_guide.md) - Architecture and implementation details
- [README.md](./README.md) - Quick start and command reference
- [CHANGELOG.md](./CHANGELOG.md) - Detailed version history

---

*Last updated: 2026-04-14*
