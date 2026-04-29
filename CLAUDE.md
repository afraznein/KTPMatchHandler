# KTPMatchHandler - Claude Code Context

## Compile Command
To compile this plugin, use:
```bash
wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler' && bash compile.sh"
```

This will:
1. Compile `KTPMatchHandler.sma` using KTPAMXX compiler
2. Output to `compiled/KTPMatchHandler.amxx`
3. Auto-stage to `N:\Nein_\KTP Git Projects\KTP DoD Server\serverfiles\dod\addons\ktpamx\plugins\`

## Project Structure
- `KTPMatchHandler.sma` - Main plugin source
- `compile.sh` - WSL compile script (use this, not compile.bat from Claude)
- `compile.bat` - Windows batch compile (works interactively, output capture issues from Claude)
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
3. `README.md` - Update version in header
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
- `.pause` / `.tac` - **DISABLED** - Only `.tech` allowed
- `.tech` - Technical pause (uses team budget)

## 1.3 Community 12man (v0.10.38+)
When starting a 12man, player selects "1.3 Community Discord" option:
1. Prompted to enter Queue ID from Discord
2. Must enter Queue ID twice for confirmation
3. Match ID format: `1.3-{queueId}-{map}-{hostname}`
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
