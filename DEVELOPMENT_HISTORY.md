# KTP Development History

> Development timeline for the KTP (Keep the Practice) competitive Day of Defeat server infrastructure.

| Metric | Value |
|--------|-------|
| **Project Duration** | October 2025 - Present |
| **Total Repositories** | 16 |
| **Estimated Development Hours** | 830-1040 |
| **Last Updated** | 2026-02-06 |

---

## Table of Contents

- [Monthly Scope Summary](#monthly-scope-summary)
- [October 2025](#october-2025---foundation) - Foundation
- [November 2025](#november-2025---platform-development) - Platform Development
- [December 2025](#december-2025---feature-complete) - Feature Complete
- [January 2026](#january-2026---stability--polish) - Stability & Polish
- [February 2026](#february-2026---bare-metal--performance) - Bare Metal & Performance

---

## Monthly Scope Summary

| Month | Est. Hours | Focus Areas |
|-------|-----------|-------------|
| October 2025 | 120-150 | Foundation - initial plugins, Discord bots, relay service |
| November 2025 | 180-225 | Platform (C++ ReAPI/KTPAMXX), major plugin rewrites |
| December 2025 | 300-375 | Feature-complete push - overtime, extension mode, v1.0 releases |
| January 2026 | 120-150 | Stability, polish, explicit OT, admin tools |
| February 2026 | 80-120 | Bare metal migration, performance optimization, codebase review |
| **Total** | **830-1040** | |

### Repository Breakdown

| Category | Count | Projects |
|----------|-------|----------|
| Core Engine (C++) | 4 | KTPReHLDS, KTPAMXX, KTPReAPI, KTPAmxxCurl |
| Game Plugins (Pawn) | 8 | KTPMatchHandler, KTPCvarChecker, KTPFileChecker, KTPAdminAudit, KTPHLTVRecorder, KTPPracticeMode, KTPGrenadeLoadout, KTPGrenadeDamage |
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

### Other Updates

| Component | Version | Changes |
|-----------|---------|---------|
| KTPGrenadeLoadout | v1.0.5 | Batch spawn processing fix (196ms spike eliminated) |
| KTPHLStatsX | v0.2.5 | KTP_HALF_END handler for accurate H1 end_time |
| KTPCvarChecker | v7.12 | Emoji removal from headers, documentation cleanup |

### Codebase Review

Systematic review across all 16+ KTP projects:
- Documentation cleanup: emoji removal from headers, stale version fixes
- Dead code removal and unused variable cleanup
- CLAUDE.md gitignore audit across all projects
- README/CHANGELOG consistency pass

### Infrastructure Optimizations Applied

All bare metal servers now have:
- Lowlatency kernel (1000Hz) + pingboost 2
- CPU mitigations disabled (`mitigations=off`)
- ALL C-states disabled (`max_cstate=0`)
- 25MB UDP buffers
- Real-time scheduling via systemd timer
- Persistent optimizations via `/etc/rc.local`

---

## Related Documentation

> For granular per-version changelogs, see the `CHANGELOG.md` in each project's repository.

- [technical_guide.md](./technical_guide.md) - Architecture and implementation details
- [README.md](./README.md) - Quick start and command reference
- [CHANGELOG.md](./CHANGELOG.md) - Detailed version history

---

*Last updated: 2026-02-06*
