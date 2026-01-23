# KTP Development History

> Development timeline for the KTP (Keep the Practice) competitive Day of Defeat server infrastructure.

| Metric | Value |
|--------|-------|
| **Project Duration** | October 2025 - Present |
| **Total Repositories** | 16 |
| **Estimated Development Hours** | 750-950 |
| **Last Updated** | 2026-01-22 |

---

## Table of Contents

- [Monthly Scope Summary](#monthly-scope-summary)
- [October 2025](#october-2025---foundation) - Foundation
- [November 2025](#november-2025---platform-development) - Platform Development
- [December 2025](#december-2025---feature-complete) - Feature Complete
- [January 2026](#january-2026---stability--polish) - Stability & Polish
- [Detailed Changelog](#detailed-january-2026-changelog)

---

## Monthly Scope Summary

| Month | Est. Hours | Focus Areas |
|-------|-----------|-------------|
| October 2025 | 120-150 | Foundation - initial plugins, Discord bots, relay service |
| November 2025 | 180-225 | Platform (C++ ReAPI/KTPAMXX), major plugin rewrites |
| December 2025 | 300-375 | Feature-complete push - overtime, extension mode, v1.0 releases |
| January 2026 | 120-150 | Stability, polish, explicit OT, admin tools |
| **Total** | **720-900** | |

### Repository Breakdown

| Category | Count | Projects |
|----------|-------|----------|
| Core Engine (C++) | 4 | KTPReHLDS, KTPAMXX, KTPReAPI, KTPAmxxCurl |
| Game Plugins (Pawn) | 7 | KTPMatchHandler, KTPCvarChecker, KTPFileChecker, KTPAdminAudit, KTPHLTVRecorder, KTPGrenadeLoadout, KTPPracticeMode |
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

### KTPMatchHandler v0.10.30-0.10.62

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

### Other Component Updates

| Component | Version | Key Changes |
|-----------|---------|-------------|
| **KTPAMXX** | v2.6.2-2.6.4 | DODX score broadcasting native, changelevel hooks, ktp_discord.inc v1.2.0, grenade ammo natives |
| **KTPReAPI** | v5.29.0.362 | Map change interception hooks (`RH_PF_changelevel_I`, `RH_Host_Changelevel_f`) |
| **KTPCvarChecker** | v7.8-7.11 | Debug cleanup, Discord toggle cvar, KTP emoji branding, notification grouping |
| **KTPFileChecker** | v2.2-2.3 | Discord notification grouping, fc_checkmodels cvar |
| **KTPAdminAudit** | v2.6.0-2.7.2 | Map change auditing, RCON quit/exit blocking, changelevel countdown, concurrent changemap fix |
| **KTPAmxxCurl** | v1.2.0-ktp | Use-after-free fix, handle allocation fix, socket map cleanup |
| **KTPFileDistributor** | v1.1.0 | Multi-channel Discord support |
| **KTPHLStatsX** | v0.1.0-0.2.1 | Player tracking, stats aggregation, half detection regex fix |

### New Plugins (January 2026)

| Component | Version | Description |
|-----------|---------|-------------|
| **KTPGrenadeLoadout** | v1.0.0 | Custom grenade loadouts for practice mode - save/load positions |
| **KTPPracticeMode** | v1.0.0 | Practice mode with unlimited ammo, grenade trails, and instant respawn |

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

## Detailed January 2026 Changelog

The following is a granular breakdown of January 2026 changes, organized by feature/fix.

---

### KTPMatchHandler v0.10.59 (2026-01-13)

**Hostname Timing Fix & Simplified Match IDs**

- **Demo filenames** - Fixed showing "Half_Life" instead of server hostname
- **Root cause** - Hostname cached in `plugin_cfg()` before `dodserver.cfg` executed
- **Fix** - Re-fetch hostname cvar in `generate_match_id()` to ensure current value
- **Match ID format simplified** - Shorter demo filenames
  - Old: `KTP-{timestamp}-{map}-{hostname}` (e.g., `KTP-1768174986-dod_armory-KTP_Atlanta_2`)
  - New: `{timestamp}-{shortHostname}` (e.g., `1768174986-ATL2`)
- **Short hostname codes** - `get_short_hostname_code()` converts hostname to city code (ATL, DAL, etc.)

---

### KTPHLTVRecorder v1.2.2 (2026-01-13)

**Orphaned Recording Cleanup**

- Sends `stoprecording` on plugin startup to cleanup any orphaned session from previous server crash
- Sends `stoprecording` on `plugin_end()` to finalize demo even if match didn't end cleanly

### KTPHLTVRecorder v1.2.1 (2026-01-13)

**Admin HLTV Restart Command**

- **`.hltvrestart`** - Restart paired HLTV instance from game server
- Requires `ADMIN_RCON` flag
- Sends Discord audit notification to audit channels
- Useful when HLTV disconnects or gets stuck

---

### Scheduled Server Restarts
- **Nightly game server restarts** - All Atlanta and Dallas game servers restart at 3:00 AM ET daily
  - Script: `ktp-scheduled-restart.sh` deployed to both server clusters
  - Uses LinuxGSM graceful stop with pkill fallback
  - Pauses monitor cron during restart to prevent race conditions
  - Discord notification with live-updating embed (orange "In Progress" → green "Complete")
  - Posts to both KTP Discord and 1.3 Discord channels
  - Uses `<:ktp:>` emoji in embed title matching KTPMatchHandler style
- **HLTV restart script updated** - `/usr/local/bin/hltv-restart-all.sh` now uses same embed format
  - Runs at 3:00 AM and 11:00 AM ET via systemd timer
  - Color-coded status: green (success), orange (partial), red (failure)

### LinuxGSM Tmux Session Bug Fix
- **"Old type tmux session" false positive** - Monitor cron incorrectly detecting new-style sessions as old
  - Symptoms: Random server restarts during matches, `quit` commands with no RCON source
  - Root cause: `pgrep -f` substring matching in `command_monitor.sh` lines 203-212
  - Fix: Commented out old-type detection block on all 10 instances (Atlanta + Dallas)
  - Note: Patch must be reapplied after `./dodserver update-lgsm`

### HLTV RTC Timing Fix
- **System::RunFrame time difference warnings** - HLTV spamming timing warnings in logs
- Root cause: RTC configured in local timezone instead of UTC
- Fix: `timedatectl set-local-rtc 0` + restart HLTVs
- Warnings during startup are normal GoldSrc behavior, should stop after connection established

### Server UDP Buffer Fix
- **RcvbufErrors causing packet drops** - 47,434 UDP receive buffer errors detected via `/proc/net/snmp`
- Default buffer size 212992 (208KB) too small for 5 game servers
- Fix: Increased to 26214400 (25MB) via `/etc/sysctl.conf`
- Documented in `KTP_GameServer_Setup.md` and `CLAUDE.md` for future servers

### KTPMatchHandler v0.10.55
- **Cancel command expansion** - `.cancel` now works during second half pending
  - Immediate cancel (no confirmation) - clears all match state
  - Announces first half score when cancelled
- **Discord embed uniformity** - All status notifications now use rich embeds
  - Matches `ktp_discord.inc` format for consistency with AdminAudit/CvarChecker
  - Color-coded: RED for cancellations, ORANGE for warnings/resets
  - Includes server hostname and map in footer

### KTPMatchHandler v0.10.54
- **Pause overlay disable (experimental)** - Sends `showpause 0` to hide pause screen overlay
  - Sends `showpause 1` on unpause to restore
  - Note: Client may reject if command is protected

### KTPMatchHandler v0.10.53
- **Auto-DC tuning** - Countdown increased from 10 to 30 seconds
- **Match-type filtering** - Auto-DC only triggers for competitive modes (.ktp, .ktpOT, .draft, .draftOT)
- **Password simplification** - Only .ktp and .ktpOT require password (not .draftOT)

### KTPMatchHandler v0.10.52
- **Changelevel guard flag fix** - First half end processing no longer skipped
  - Root cause: `g_changeLevelHandled` flag stuck when admin `.changemap` blocked changelevel
  - Fix: Reset flag when match goes live

### KTPMatchHandler v0.10.51
- **Roster cross-team duplicate fix** - Players no longer appear in both team rosters
  - `add_to_match_roster()` now checks BOTH rosters before adding

### KTPMatchHandler v0.10.50
- **2nd half ready counter fix** - `.rdy` counter now shows correct team names
  - Uses roster-based SteamID lookup for team identity during 2nd half pending

### KTPMatchHandler v0.10.49
- **Standard AMXX logging** - `log_ktp()` now uses `log_amx()` with [KTP] prefix
  - Logs auto-rotate daily via standard AMXX log rotation
  - Removed `ktp_match_logfile` cvar (no longer needed)

### KTPMatchHandler v0.10.48
- **Dead code cleanup** - Removed ~190 lines of unreachable/unused code
  - Old OT handler (`handle_ot_round_end_OLD`) wrapped in `#if 0` block
  - Unreachable tactical pause logic after early return
  - Unused legacy variables (`g_gameEndEventCount`, `g_gameEndTaskId`)
- **Compiler warnings fixed** - All warnings resolved with `#pragma unused`
- **Admin Commands in .commands** - `.forcereset` now shown in command list

### KTPMatchHandler v0.10.47
- **Force reset admin command** - `.forcereset` for recovering abandoned servers
  - Requires ADMIN_RCON flag (highest admin level)
  - Confirmation step: type command twice within 10 seconds
  - Clears ALL match state: live, pending, prestart, pause, scores, rosters, localinfo
  - Sends Discord notification when executed
- Updated users.ini and MOTD.txt with `.forcereset` documentation

### KTPMatchHandler v0.10.46
- **Match type-specific ready requirements**
  - KTP/KTP_OT: 6 players per team
  - All others (scrim, 12man, draft, draft OT): 5 players per team
- **Debug override command** `.override_ready_limits` for SteamID 0:1:25292511
- **2nd half team name fix** - Pause budget announcement now uses swapped team names correctly
- Updated `.commands` list with `.ktpOT`, `.draftOT`, `.whoneedsready`
- Updated MOTD.txt with current command list

### KTPAmxxCurl Segfault Fix
- **Use-after-free in async socket callbacks** - Raw SocketData* pointers passed to ASIO async callbacks could be deleted before callback executed
  - Fix: Changed to `shared_ptr<SocketData>` with `socket_data_map_` tracking
- **Handle allocation bug** - `count() > 1` always false (count returns 0 or 1), causing handle collisions
  - Fix: Changed to `count() != 0`
- **Stale socket map entries** - Non-ARES sockets weren't erased from socket_map_ on CURL_POLL_REMOVE
  - Fix: Always erase from socket_map_ regardless of socket type
- **Unvalidated callback execution** - MF_ExecuteForward called without checking callback registration
  - Fix: Added `.count()` validation before all 10 callback functions

### Full Player Load Test (6v6)
- 12man matches verified with full rosters on both teams
- Score tracking, pauses, half transitions all functional under load

### Map Config Verification
- All 30 maps in ktp_maps.ini verified with matching config files
- Logs confirm `MAPCFG status=exec` for non-anzio maps (armory, railroad2, etc.)

### KTPMatchHandler v0.10.45
- **Dynamic server hostname** - Hostname now reflects match state in real-time
  - Format: `{BaseHostname} - {MatchType} - {State}` (e.g., "KTP - Atlanta 1 - KTP - LIVE - 1ST HALF")
  - Match types: KTP, SCRIM, 12MAN, DRAFT, KTP OT, DRAFT OT
  - States: PENDING, PAUSED, LIVE - 1ST HALF, LIVE - 2ND HALF, LIVE - OT1, etc.
  - Match ID uses only base hostname (excludes dynamic suffixes)
  - Removed `servername.cfg` exec from ktpbasic.cfg

### KTPMatchHandler v0.10.44
- **Intermission auto-DC fix** - Players leaving during scoreboard no longer trigger auto tech pauses
- Added `g_inIntermission` flag and `is_in_intermission()` helper

### KTPMatchHandler v0.10.43
- **Explicit overtime commands** - `.ktpOT` and `.draftOT` for manually starting overtime
- Overtime no longer triggers automatically at end of tied 2nd halves
- New match types: `MATCH_TYPE_KTP_OT` and `MATCH_TYPE_DRAFT_OT`
- OT rounds use 5-minute timelimit, require same password as `.ktp`

### KTPMatchHandler v0.10.42
- **Persistent player roster tracking** - Discord match reports show all participants
- **Auto-DC disabled after match ends** - `g_matchEnded` flag prevents spurious pauses

### KTPHLTVRecorder v1.1.1
- Added explicit OT match types (ktpOT, draftOT) for demo naming

### KTPHLTVRecorder v1.1.0
- **Major rewrite: HTTP API communication** - Replaced UDP RCON with HTTP POST
- Commands sent to data server API (port 8087) which injects to HLTV via FIFO pipes
- Replaced Sockets module with Curl module
- Reliable command delivery (GoldSrc HLTV doesn't support standard UDP RCON)

### KTPMatchHandler v0.10.41
- **Map config prefix matching fix** - Longer map keys now match first (dod_railroad2_s9a before dod_railroad)
- Sort map keys by length descending after loading INI
- Added `.changemap` to `.commands` list

### KTPMatchHandler v0.10.40
- **First half changelevel recursion fix** - Same bug as OT recursion (guard reset causing multiple firings)
- **All match types stay on same map for 2nd half** - 12man, draft, scrim, competitive all properly redirect
- **Queue ID cancel option** - Type "cancel" or "abort" during Queue ID entry to restart

### KTPMatchHandler v0.10.38
- **1.3 Community 12man Queue ID support**
  - Match ID format: `1.3-{queueId}-{map}-{hostname}`
  - Captain enters Queue ID twice for confirmation
  - Integrates with 1.3 Community Discord bot match tracking
- **Allow all users to .changemap**
  - Any player can initiate map change during non-match state

### KTPMatchHandler v0.10.37
- **Match ID now includes server hostname**
  - Format: `KTP-{timestamp}-{map}-{hostname}`
  - Differentiates matches across multiple servers

### KTPMatchHandler v0.10.36
- **Discord support for 12man and draft matches**
  - `discord_channel_id_12man` config key
  - `discord_channel_id_draft` config key

### KTPMatchHandler v0.10.35
- Tactical pauses disabled (tech only)
- Pause extensions disabled by default

### KTPFileDistributor
- Multi-channel Discord support via `AdditionalChannelIds`

### Data Server Scripts
- HLTV restart script multi-channel Discord support
- `/etc/ktp/discord-relay.conf` external channel support

### Atlanta Server Cluster
- Atlanta 2-5 (ports 27016-27019) fully configured
- LinuxGSM instances, configs, HLStatsX, KTPFileDistributor
- UFW rules and monitor cron entries

### Data Server HLTV Instances
- HLTV 27021-27024 configs and systemd services
- Scheduled restart timer integration

### Admin Setup
- Discord audit channel configured for KTPAdminAudit

### KTPMatchHandler v0.10.39
- **OT recursion bug fix** - Prevented hook re-entry during OT round transitions
- **ktp_match_start forward** - Now fires on all halves/OT with `half` parameter

### KTPHLTVRecorder v1.0.7
- **Improved RCON reliability** - Tries simple RCON first, falls back to challenge-response
- Many HLTV versions accept simple RCON without challenge
- Assumes success if no response (HLTV often doesn't ack successful commands)
- Added extensive logging for debugging

### KTPHLTVRecorder v1.0.6
- **Challenge-response RCON** - Fixed RCON protocol to use challenge-based authentication
- HLTV was rejecting simple RCON ("Invalid rcon challenge")
- Now properly: request challenge -> parse response -> send command with challenge

### KTPHLTVRecorder v1.0.5
- Updated to handle new `ktp_match_start(matchId, map, type, half)` signature
- Idempotent recording - continues existing recording through map changes

---

## Related Documentation

- [TECHNICAL_GUIDE.md](./TECHNICAL_GUIDE.md) - Architecture and implementation details
- [README.md](./README.md) - Quick start and command reference
- [CHANGELOG.md](./CHANGELOG.md) - Detailed version history

---

*Last updated: 2026-01-22*
