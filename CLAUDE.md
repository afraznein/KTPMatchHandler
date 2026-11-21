# KTPMatchHandler - Claude Code Context

**REQUIRED: Before writing or modifying any code in this repo, invoke the `plugin-dev` skill** (`.claude/skills/plugin-dev/SKILL.md`). It carries the state-machine safety rules and deploy workflow; do not edit the .sma without it loaded.

**A design that ships as a document is NOT done** — every proposal in a docs-only PR becomes a
tracked board item in the same act (operator ruling 2026-09-14). See `DESIGN_DOCS_ARE_NOT_DONE.md`.

## Launch-time setup: the commit-sweep guard

Once per clone, before the first commit (linked worktrees share the setting):

```bash
git config core.hooksPath .githooks
```

The main checkout is shared by concurrent sessions, so its index is shared too: a bare `git commit` takes
whatever anyone else has staged, and `git commit -a` takes every modified tracked file. `.githooks/pre-commit`
refuses both in the main checkout whenever anything is staged. Commit by path instead:
`git commit -m "..." -- <paths>` builds a private index from just those paths (a new file still needs
`git add <path>` first). Linked worktrees have their own index and skip the check, so isolated work pays nothing.
Finishing a conflicted merge, revert or cherry-pick legitimately commits the index:
`KTP_COMMIT_SWEEP=1 git commit ...`. A hook already in `.git/hooks/pre-commit` still runs; the guard chains to it.
`core.hooksPath` would otherwise shadow `.git/hooks`, so `.githooks/pre-push` hands off to the pre-push gate
`scripts/install-hooks.sh` installs there.
Test: `sh .githooks/test-pre-commit.sh`.

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
- `lookup_cfg_for_map()` matches a map to a config by PREFIX, not by equality, and
  takes the FIRST row in `ktp_maps.ini` order that matches — `containi(lower, key) == 0`
  after the `.bsp` suffix is stripped and the name lowercased.
  - So removing a `[dod_x]` section also removes a silent fallback for every `dod_x*`
    variant on disk, and a new map whose stem extends an existing key inherits that
    key's config instead of getting none. Check what a chosen stem resolves to before
    shipping it.
  - Section ORDER is therefore load-bearing twice over: it is also the order
    `.changemap` renders, which `ktp_maps.ini` states in its own heading.
- **`ktp_maps.ini` is re-read at EVERY map change, not at plugin load.** `load_map_mappings()`
  has exactly one call site, inside `public plugin_cfg()`, and it clears the table and `fopen`s
  the file on each call. In extension mode `plugin_cfg` is fired per map by KTPAMXX's
  `KTPAMX_ReloadPlugins()`, which `SV_ActivateServer` calls whenever the map-change flag is set
  (`amxmodx/meta_api.cpp`) -- plugins stay loaded and only the forwards re-run.
  - So a pool edit activates at the next map change. ~20 minutes, not the 03:00 nightly.
  - The project `CLAUDE.md`'s *"extension mode never reloads plugins on map change"* is still
    true and is about the `.amxx` BINARY not being re-read, so a new BUILD does need the
    restart. A config file opened inside `plugin_cfg()` does not. Reading the first rule as
    covering the second is what parked `dpl-679f` on a restart it did not need.

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

### The pre-match HUDs are no longer baked into the demo — except under a pause

🔻 **FIXED in 0.10.179 (#55, fielded 2026-10-23) — this section asserted the
pre-fix state and is corrected in place.** `prestart_hud_tick`, `pending_hud_tick`
and `show_continuation_pending_hud_internal` now send through `get_players(..., "ch")`,
which drops HLTV proxies and bots in one call, so the 1-second re-arm no longer
reaches the proxy and no longer lands in the recording.

✅ **Measured by effect on the demos themselves, not from the version banner:**
the literal pre-start HUD text occurs **192** times in the last pre-swap half
(`12man_1.3-7102-ATL1_h1`, 2026-10-23 00:31) and **21** times in a second pre-swap
half on another host, against **0** in four post-swap halves across ATL1, DAL1 and
NY1 — with a nonsense-token control at 0 in every file, so the zero is a
measurement and not a blind probe.

⚠️ **THE ONE CASE THAT STILL BAKES: a PAUSED pre-match.** AMXX tasks do not run
during a pause, so a paused ready-up is served by the pause hook rather than the
task tick, and that path still broadcasts to recipient `0` by ruling — deliberately,
so the caster keeps the pause countdown and the TECHNICAL/TACTICAL label, which his
own feed (`/api/hq`) does not carry. ⛔ **So a long lead-in that was PAUSED is not
covered by #55**, and the four post-swap demos above carry no pause, so they do not
test it. 🔑 **`show_pause_hud_message` is a FIFTH `ShowSyncHudMsg(0, …)` site**,
also left broadcasting — re-derive the count rather than reading it here.

🔴 **AND A DEMO CANNOT PROVE THAT PAUSED BROADCAST DID NOT HAPPEN — it
reaches the recording only SOMETIMES.** Across four paused halves only **2**
recorded the pause HUD at all, and never more than **once**, despite multi-minute
pauses whose text changes every second — one real 2m19s live pause carries the
pause CHAT in its demo and reads **0** for the HUD. The proxy nearly stops
sampling frames while the server is paused.
⛔ **So a single demo reading 0 for a pause-era HUD marker is NOT evidence of
absence**, and because the broadcast above is deliberate, reading that 0 as
*fixed* inverts the finding.
➡️ **Repeat the capture across several paused halves, or measure the server
side instead — one capture is inconclusive by construction.**

🔑 **Still true and still load-bearing: ⚠️ a long lead-in is almost always PENDING, not pre-start** — measured over
585 completed pre-starts across all 24 instances (2026-08-17 → 09-28), pre-start
runs p50 24 s / p90 145 s while pending runs p50 115 s / p90 282 s. The match that
prompted the original complaint had a **7-second** pre-start.

➡️ **So attribute a long lead-in by measuring both phases, never by trusting the one
the report names.** Pre-start exits only on `.confirm` from both teams, `.cancel`,
`.forcereset` or a `changelevel`, so an abandoned session reads as a multi-hour
pre-start nobody sat through — exclude those before quoting a percentile.

### Tech pause budget

`.pause`/`.tac` are DISABLED — only `.tech` is allowed. Tech pauses use a team budget (default 300s
per team **per match**, not per half). It is set once at match start and carried across the halftime
side swap — a team that spends 4:00 in H1 starts H2 with 1:00. OT gets its own separate budget.

### The AC roster announce at go-live — a FLOOR, not a census

`send_ac_roster_report()` runs on the match-start path and reads who has a live anti-cheat session
once, as the period goes live. 🔑 **It is a REPORT and nothing in it can refuse a go-live** — every
path returns without touching match state. Public chat prints only who IS live, deliberately: naming
who is not is accusation-adjacent, and the live list tells captains the same thing while labelling nobody.

🔑 **Since 0.10.186 the not-live names go to ADMINS ONLY** (operator ruling). After the public output,
`ac_roster_tell_admins()` sends `No live AC session (admins only):` to each connected `ADMIN_RCON`
holder with `client_print(id, ...)`, through the same `ac_roster_announce_names()` wrapping and
`AC_ROSTER_MAX_LINES` cap (target `0` is the public path, any other value is one client). With no
admin connected, nothing goes to chat. ⛔ **Never pass that list target `0` or route it through
`announce_all`** — the tests assert the public labels never name absence and the admin helper never
reaches client 0. A not-live player is named only if his slot still holds the same authid.
⚠️ **No Discord copy, on purpose:** `send_discord_admin_embed()` posts to the ops channel and falls
back to the competitive match channel when that is unset, so it cannot promise an admin-only audience.

📋 **Per-player audit line, since 0.10.186:** every reading that passes the currency and echo gates
logs one `event=AC_ROSTER_PLAYER match_id=<id> steamid=<id as sent> state=live|capture_blind|no_session
slot=present|left|changed` per on-team player. `state` is the API's answer for the id; `slot` is
whether chat could still name him (so a `live` row with `slot=left` is absent from the chat list by
design). A reply that fails either gate logs NO per-player line, so their absence beside an
`AC_ROSTER_ECHO_MISMATCH` or `AC_ROSTER_DISCARDED` is correct. Nothing downstream parses `AC_ROSTER_*`;
`log_ktp` goes through `log_amx` and the fleet runs `amxx_logging 1`, so these lines live in
`addons/ktpamx/logs` only; HLStatsX never ingests them, and an empty HLStatsX search is expected.

⚠️ **A reading is a LOWER BOUND on who is running the client, not a census.** The roster refreshes on
its own beat while a session stays live for a longer staleness window, so a client started shortly
before go-live is absent from the announce and present in reality. The chat line says so out loud,
and the same caveat binds anyone reading the log afterwards. ➡️ **Re-read before acting on a zero** —
one reading cannot tell *not running* from *not yet published*.

⛔ **`captureBlind` is a THIRD state, and a boolean hides it.** *AC live, capture blind* is neither
compliant nor absent, which is why it gets its own announce list instead of being folded into the
live one; collapsing the report to a yes/no silently files a blind-capture player under one of the
other two. 🔑 **And `blind=0` is a measurement only while `blind_unparsed=0`** — the parse counts a
row whose flag key is present but matches none of `true`, `false` or `null`, because a wire spelling
that moved would otherwise read as nobody being blind. `null` is a legitimate spelling here: the
route answers for every id sent, so a player with no session gets a row with a null flag.

🔑 **Since 0.10.183 the reading asks BY PLAYER ID (`POST /api/ac/live-sessions`), not by server
endpoint.** The endpoint a session carries is asserted by the client and verified by nothing, and a
client that cannot tell which server it is on guesses — so the endpoint-scoped read it replaced
described people live somewhere else and missed the people actually on the server. An id-scoped
question cannot be wrong about an endpoint it never consults.
⛔ **So nothing in this path may reason about `serverEndpoint`** — filtering on it client-side
rebuilds the old defect behind a correct API. Rows are matched on the exact bytes this server sent
(that is what the echo is for), and the universe digit is NOT folded here: a fold on this side is a
second identity path that can disagree with the API's own.

🔴 **Under id scoping, `matched=0` behind the contract gate IS the reading** — nobody on a team is
running the client. There is deliberately no "rows present, none matched" fault event any more,
because flagging it would make a correct answer look like a broken call. ➡️ **What tells a broken
call apart is the contract, so judge `AC_ROSTER_PARSE` on it before believing `matched`:**
`rows == on_teams == echoed` and `active_missing=0`. Any break logs `AC_ROSTER_ECHO_MISMATCH` and the
announce says the reading is unavailable rather than printing a count. `AC_ROSTER_ACTIVE_MISSING`
means the liveness key moved — the one failure that would otherwise read as a plausible *nobody is
live* — and it gates the reading instead of only logging. `AC_ROSTER_NO_IDS` means objects arrived
but no id parsed. `AC_ROSTER_REFUSED` is a 4xx: a definite refusal, not an unreachable API.

⛔ **A pre-0.10.183 log line is not a reading of anyone.** Lines carrying `endpoint=`,
`endpoint_echo=`, `sessions=` or `AC_ROSTER_NONE_MATCHED` came from the endpoint-scoped read, which
measurably reported a small fraction of the players who were provably live on the server — including
on fires that returned an EMPTY roster, not only on the ones that returned the wrong people. **Never
quote those lines as an adoption or compliance figure.** The universe-digit explanation once given
for them is also wrong: the old matcher compared only the part after the first colon, so that digit
was never compared at all.

✅ **Since 0.10.184 `AC_ROSTER_PARSE` arrives whole.** The slot counters (`ordinal_off`,
`slots_not_connected`, `slots_authid_changed`, `unsendable_ids`) moved to their own
`AC_ROSTER_SLOTS` line, logged right after it with the same `match_id`, and `log_ktp` now formats
into a static `msg[512]`. `tests/config_parse/test_log_ktp_buffer.py` renders every `log_ktp` call at
its worst case and fails if one stops fitting, so a new field that overruns is caught in CI rather
than in the log. `unsendable_ids` is also on the `AC_ROSTER_SEND` line.
⛔ **A 0.10.183-or-older PARSE line that ends early is the old 256-cell overrun, not a malformed
reply** — it cut `slots_authid_changed` and `unsendable_ids` on every fire, while every contract field
sat before the cut. ⚠️ **The `truncated=` field on the line is the HTTP reply's flag (the body filled
its buffer), not the log line's** — `truncated=no` says nothing about whether the line itself is
whole; its length and its last field do.

### AC auto-start arm and the ready-up nudge (0.10.187)

`.ktp`/`.ktpOT` only. From the password accept through go-live the plugin POSTs
`/api/ac/arm` (`serverEndpoint`, `matchType`, `phase`, `nonce`, up to 32 `steamIds`) so a
signed-in AC client can start its own session before the period is live. It arms at the
password, not at go-live, because go-live is instant on the last `.ready`.

🔑 **It is a REPORT, exactly like the roster read.** No path touches match state, waits on
the reply or acts on it; `AC_ARM_FAILED`/`AC_ARM_REFUSED` are logged and the next beat
retries. ⛔ **Never let the arm reply gate a `.confirm`, a `.ready` or a go-live.**

⚠️ **The beat rides `prestart_hud_tick` and `pending_hud_tick`** (30 s, or a roster change
no sooner than 5 s after the last send) — so it stops during a pause, because AMXX tasks
do, and it stops at go-live. After go-live the arm lapses on the API's TTL; that is the
design, not a dropped heartbeat.

🔑 **Nonce rule:** `ac_arm_on_prestart()` mints one at the password accept;
`ac_arm_on_pending()` keeps it only when the episode's marker is still `prestart` (the
1st-half pending the `.ktp` led into) and mints a fresh one for every other pending phase
(2nd-half and OT restores). The client keys its *do not auto-start again after a manual
stop* on the nonce, so changing this rule changes what a manual stop means.

⛔ **Do not arm a non-official type.** `.scrim/.12man/.draft/.draftOT` take no password, so
an arm there lets anyone start recording on every signed-in client on the server. Every
entry point re-checks `is_official_match_type(g_matchType)`, and the episode latch
(`g_acArmActive`) is cleared by `ac_arm_state_reset()` from `ac_announce_state_reset()`
(every identity clear), the pre-start `.cancel` branch, and `plugin_init()`.
⚠️ **`g_matchType` defaults to `MATCH_TYPE_COMPETITIVE` after a cancel**, which is why the
official check alone is not the gate — the latch is.

**The nudge** is the fallback for clients that cannot auto-start. In an official pending
phase, each beat asks `/api/ac/live-sessions` about the on-team players not yet told this
phase, behind the same contract gate as the go-live reading, and sends each no-session
player ONE `client_print(slot, ...)` line. ⛔ **Never route it through `announce_all` or
client 0, and never name the player to anyone else** — the 2026-11-21 ruling widened the
0.10.186 admin-only rule to this one private line and no further. A reply that fails the
gate, or lands after the nonce moved, nudges nobody (the safe direction: telling a player
who IS running the client to start it is the wrong way to fail). It parses into the shared
`g_acRosterBody`, which is safe only because each callback fills and parses it in one
synchronous call.

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
