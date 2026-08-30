# KTPMatchHandler - Claude Code Context

**REQUIRED: Before writing or modifying any code in this repo, invoke the `plugin-dev` skill** (`.claude/skills/plugin-dev/SKILL.md`). It carries the state-machine safety rules and deploy workflow; do not edit the .sma without it loaded.

## Compile Command

**Production build:**
```bash
wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler' && bash compile.sh"
```

This will:
1. Compile `KTPMatchHandler.sma` using KTPAMXX compiler
2. Output to `compiled/KTPMatchHandler.amxx`
3. Auto-stage to `N:\Nein_\KTP Git Projects\KTP DoD Server\serverfiles\dod\addons\ktpamx\plugins\`

**Test-mode build** (KTPInfrastructure Tier 2 integration tests; 0.10.122+):
```bash
wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler' && KTP_TEST_MODE=1 bash compile.sh"
```

Outputs to `compiled/test/KTPMatchHandler.amxx`, NOT staged to production. Adds `amx_ktp_test_*` rcons for state-machine driving + readback. Production-mode binary byte-identical to no-flag build (test-mode block is `#if defined KTP_TEST_MODE`-gated).

## Project Structure
- `KTPMatchHandler.sma` - Main plugin source
- `compile.sh` - WSL compile script; the only supported build path. It generates
  `build_info.inc`, which is what bakes the git SHA into the `.amxx` for
  `amx_ktp_versions`. `compile.bat` was deleted 2026-08-11: it shelled out to WSL
  anyway and skipped that step, and the include falls back to
  `KTP_BUILD_SHA "unknown"` silently.
- `compiled/` - Compiled .amxx output
- `CHANGELOG.md` - Version history
- `README.md` - Documentation

## Server Deployment

Deploy compiled plugin to production servers using Python/Paramiko (preferred over shell SSH).

**Remote Path:** `~/dod-{port}/serverfiles/dod/addons/ktpamx/plugins/KTPMatchHandler.amxx`

See `N:\Nein_\KTP Git Projects\CLAUDE.md` for full paramiko SSH documentation and examples.
See `N:\Nein_\KTP Git Projects\KTPAmxxCurl\*.py` for working deployment scripts.

## Related Projects
- `N:\Nein_\KTP Git Projects\KTPAMXX` - Custom AMX Mod X fork (compiler source)
- `N:\Nein_\KTP Git Projects\KTP DoD Server` - Test server with staged plugins
- `N:\Nein_\KTP Git Projects\TODO.md` - Development TODO list

## Key Files to Update on Version Bump
1. `KTPMatchHandler.sma` - `#define PLUGIN_VERSION`
2. `CHANGELOG.md` - Add new version section
3. `README.md` - **four** version sites, not one: the header, "Current Version",
   the Quick Reference Card banner, and the footer line. The 0.10.146 and
   0.10.147 bumps each touched only the header and left the other three at
   0.10.145.
4. `N:\Nein_\KTP Git Projects\TODO.md` - Update completed/pending items

## Dependencies
- **KTP-ReHLDS 3.22.0+** - For `RH_PF_changelevel_I`, `RH_Host_Changelevel_f` hooks and `ktp_silent_pause` cvar
- **KTP-ReAPI 5.29.0.362-ktp+** - Hook exposure to AMXX
- **KTPAMXX 2.6.2+** - For DODX score natives

## Key Hooks Used
- `RH_PF_changelevel_I` - PRIMARY: Intercepts game DLL pfnChangeLevel (timelimit, objectives)
- `RH_Host_Changelevel_f` - SECONDARY: Intercepts console changelevel command (admin/RCON)
- `RH_SV_UpdatePausedHUD` - Real-time HUD updates during pause

## Key Commands
- `.ktp <password>` - Start competitive match (password required)
- `.draft` - Start draft match (no password)
- `.12man` - Start 12-man (Standard or 1.3 Community Discord with Queue ID)
- `.scrim` - Start scrim match
- `.ktpOT <password>` - Start KTP overtime round
- `.draftOT` - Start draft overtime round (no password)
- `.forcereset` - Admin command to recover abandoned servers (ADMIN_RCON, requires confirmation)
- `.restarthalf` / `.h2restart` - Restart 2nd half to 0-0, keeping 1st half scores (ADMIN_RCON, requires confirmation)
- `.override_ready_limits` - Toggle the ready-count go-live requirement. Gated by a SteamID allowlist (`OVERRIDE_ADMIN_SIDS`), NOT an admin flag
- `.pause` / `.tac` - **DISABLED** - Only `.tech` allowed
- `.tech` - Technical pause (uses team budget)

## 1.3 Community 12man (v0.10.38+)
When starting a 12man, player selects "1.3 Community Discord" option:
1. Prompted to enter Queue ID from Discord
2. Must enter Queue ID twice for confirmation
3. Match ID format: `1.3-{queueId}-{shortHostname}` (e.g. `1.3-5031-ATL2`). The
   map is deliberately NOT included — HLTV appends it when recording.
4. Type "cancel" or "abort" during entry to restart

## Auto-DC Behavior (v0.10.53+)
- Only triggers for competitive modes: `.ktp`, `.ktpOT`, `.draft`, `.draftOT`
- Does NOT trigger for scrims or 12mans
- 30-second countdown (was 10s)
- Cancellable via `.nodc`

## Known Limitations
- **Scoreboard Team Names** - CANNOT BE CHANGED
  - Tried `dodx_set_scoreboard_team_name()` - no effect on client scoreboard
  - DoD scoreboard team names ("Allies"/"Axis") are hardcoded client-side
  - No known method to change them via server-side code

## Technical Notes
- Score broadcasting now uses `dodx_broadcast_team_score()` native (v0.10.20+)
  - AMX message natives crashed; DODX native works from C++ level
- OT stays on same map via `SetHookChainArg()` to modify map in-place (v0.10.34+)
- Match ID format: `{timestamp}-{shortHostname}` (e.g., `1768174986-ATL2`)
- Tactical pauses disabled (v0.10.35) - only `.tech` allowed

## Match Flow

*(Relocated 2026-08-29 from the operator's global project context — this plugin is its one home.)*

```
Match Types:
- .ktp <password>  - Competitive (password required)
- .ktpOT <password> - KTP overtime (password required)
- .draft           - Draft match
- .draftOT         - Draft overtime
- .12man           - 12-man (Standard or 1.3 Community with Queue ID)
- .scrim           - Scrim match

Flow:
1. Pre-start: Start command → Both teams .confirm
2. Pending: Players .ready (6 per team default)
3. Match Start:
   - dodx_flush_all_stats() - flush warmup stats
   - dodx_reset_all_stats() - clear for fresh match
   - dodx_set_match_id() - set match context
4. Live: Map config executes, tech pause system active (.pause disabled, .tech only)
5. Half/Match End:
   - dodx_flush_all_stats() - flush match stats
   - KTP_MATCH_END logged for HLStatsX

Admin Commands:
- .forcereset - Clear all match state (ADMIN_RCON, requires confirmation)
```

### Tech pause budget

`.pause`/`.tac` are DISABLED — only `.tech` is allowed. Tech pauses use a team budget (default 300s
per team **per match**, not per half). It is set once at match start and carried across the halftime
side swap — a team that spends 4:00 in H1 starts H2 with 1:00. OT gets its own separate budget.

## Score Restoration

- Direct `dodx_set_team_score()` can crash if called during map changes
- Use deferred restoration: set `g_pendingScoreAllies/Axis`, call `schedule_score_restoration()`
- Scoreboard updates on "next flag touch" event

## Localinfo Persistence

Match state survives map changes via localinfo keys:
- `_ktp_mid` - Match ID
- `_ktp_map` - Map name
- `_ktp_mode` - Mode ("h2", "ot1", "ot2", etc.)
- `_ktp_state` - Consolidated state (pause/tech counts)
- `_ktp_h1` - First half scores
- `_ktp_t1n`/`_ktp_t2n` - Team names
- `_ktp_reg` - Regulation totals (OT)
- `_ktp_ots` - OT scores per round
- `_ktp_otst` - OT state (tech budgets + starting side)
