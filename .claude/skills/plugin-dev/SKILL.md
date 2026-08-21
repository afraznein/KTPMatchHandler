---
name: plugin-dev
description: Use BEFORE writing or modifying any KTPMatchHandler Pawn code — match state-machine safety rules, teardown-exit coverage, async-callback identity revalidation, and the compile/review/stage/verify workflow. Also use when planning a change, to know which invariants it touches.
---

# KTPMatchHandler Development

This plugin runs live competitive matches on a production fleet (24 instances).
A bug here ruins real matches. Follow every rule below; when a rule and your
instinct disagree, the rule wins — each one was paid for with a production incident.

## Hard safety rules
- **NEVER restart game servers** or issue LinuxGSM control commands without the
  operator's explicit permission in the current conversation.
- Deploys are staged as `KTPMatchHandler.amxx.new` in each instance's plugins dir
  and swap at the 03:00 ET nightly restart. Never hot-swap the live `.amxx`.
- Run the `ktp-code-review` agent on any nontrivial change BEFORE compiling for deploy.

## Architecture constraints
- **Extension mode**: KTPAMXX loads as a ReHLDS extension — there is NO Metamod and
  NO fakemeta. Engine hooks come only from KTP-ReAPI (`RH_*` hook chains) and DODX
  natives. Never add a fakemeta/engine-module dependency.
- **Nothing may sit between the engine and `dod_i386.so`.** DODX finds
  `g_pGameRules` by scanning the game DLL's symbols at runtime, and that scan fails
  through a gamedll wrapper (the Metamod shape, and every bot mod built on it). The
  score natives then no-op **silently** — half-end and match-end persistence stop
  working with no error. This rules the shim out on a test host too, not just in
  production.
- **Read scores with `dodx_get_team_score()`, never `dod_get_team_score()`.** The
  latter reads DODX's message-tracked counters, which are filled by a C++ message
  handler that message dispatch never reaches without Metamod. It does not error —
  it returns a plausible `0` forever. The gamerules-memory read is correct in every
  engine mode.
- Match state survives map changes via localinfo keys (`_ktp_mid`, `_ktp_map`,
  `_ktp_mode`, `_ktp_state`, `_ktp_h1`, `_ktp_t1n`/`_ktp_t2n`, `_ktp_reg`,
  `_ktp_ots`, `_ktp_otst`). Any new persistent state needs a localinfo key AND a
  clear on every teardown exit (see below).
- **A localinfo value has a hard 127-char ceiling and overflow is silent.**
  `set_localinfo` resolves to the engine's `Info_SetValueForStarKey`, which rejects
  any write at or past `MAX_KV_LEN` outright while AMXX still returns success at the
  Pawn boundary — and a rejected write leaves the *old* value in place, so the
  failure presents as stale data rather than missing data. Any key that can grow
  (OT score lists, roster chunks) needs a writer that cuts at a valid record
  boundary and logs when it does.
- Score writes during map change crash: never call `dodx_set_team_score()` directly
  in a changelevel window — set `g_pendingScoreAllies/Axis` and use
  `schedule_score_restoration()` (applies on next flag touch).
- **`msg_TeamScore` must record into `g_matchScore` above any `!g_matchLive` early
  exit.** The scores that get persisted for the second half arrive during DoD's
  intermission — after the match is no longer live — so hoisting the liveness guard
  to the top of the handler as a hot-path win makes every halftime save 0-0. Only
  the adjustment and the localinfo write may be gated on liveness. The mirror-image
  trap: `save_first_half_scores()` must not re-read DODX at halftime, because DODX
  has already zeroed its own counters by the time changelevel processing runs.

## Engine behaviour that reads as a plugin bug

Four engine facts that each cost a live match before anyone believed them. None of
them raise an error; every one of them presents as the plugin misbehaving.

- **A paused server does not stop running usercmds — it zeroes them.** The engine
  still executes every command while paused, with `msec = 0` and `buttons = 0`, so
  `svtimebase` freezes and no elapsed-*gametime* check can ever trip inside a pause
  window. AMXX tasks do not run either. A pause-scoped timeout written as `set_task`
  or as "have N seconds passed" is dead code: drive it from the per-frame
  `RH_SV_UpdatePausedHUD` hook and real time (`get_systime()`), which is why the
  existing pause timers are built that way.
- **A changelevel clears tasks but not globals, and restarts gametime near 1.0.**
  `KTPAMX_ReloadPlugins()` clears the task list *before* `FF_PluginInit`, so nothing
  scheduled survives a map change — while every Pawn global does, and `SV_SpawnServer`
  resets both `g_psv.time` and `g_psv.paused` underneath them. The two halves bite in
  opposite directions: a latch mirroring engine state is now lying, and any deadline
  expressed in gametime is *already satisfied* on the next map, so a confirm window
  can fire a destructive command nobody confirmed. Reset latches in `plugin_init()`;
  treat a negative or wrapped elapsed time as expired, never as "not yet due".
- **`SV_SpawnServer` can fail silently and the engine will loop the mapcycle
  forever.** The changelevel hook still returns `HC_CONTINUE` and looks healthy, but
  the map never loads, so `plugin_init` never runs and any debounce latch cleared
  only there stays set for the life of the process — every later changelevel is then
  skipped. Recovery has to force the `map` command, which takes a different engine
  path. Any changelevel path this plugin owns needs a watchdog that retries that way
  when the expected map load does not arrive.
- **Nothing announced from `plugin_cfg` reaches a human.** It runs before any client
  has reconnected to the new map, and HL1/DoD never replays chat to a late joiner, so
  a broadcast there goes to an empty server. Returning players also land in DoD's
  role-select VGUI, which covers HUD text — chat overlays that menu and HUDs do not.
  Post-map-change prompts must therefore be chat, and deferred a few seconds past
  `plugin_cfg`, with reminders rather than a single shot.

## The teardown-exit invariant (most important rule in this file)
The match state machine has **~10 distinct teardown/exit paths**, not one:
`cmd_cancel` alone has 3 branches; the map-load restore family can bypass
`end_match_cleanup` entirely; add changelevel interception, `.forcereset`,
half-end, match-end, OT transitions, and failed-start aborts.

When you add ANY match-scoped state (a task, a hook toggle, a latch, a localinfo
key, an armed timer):
1. Enumerate the exits **from the state machine transitions**, not from function
   names — grep every site that leaves the live/pending states.
2. Route cleanup through one central teardown function and make every exit call
   it. Do not sprinkle per-exit resets.
3. Verify the map-load restore paths too — they resurrect state without running
   the normal end-of-match code.

**Grepping for emit sites is NOT enumerating exits.** The 0.10.146 work searched
for `KTP_MATCH_END` / `send_ac_match_end` call sites and built a coverage table
from them. That method is blind by construction to an exit that emits *neither* —
and one existed (`restore_match_context_from_localinfo`'s not-live branch), which
was the single largest hole. Enumerate from the state flags and the
`LOCALINFO_LIVE` lifecycle instead.

### The one teardown function: `ktp_match_teardown_notify()`
Every match-teardown exit closes the match through this stock. **Do not hand-roll
the block again** — that is precisely how the two P1s in 0.10.146 happened.

Two independent sinks must learn a match ended, and they are easy to get half-right:
- **HLStatsX** — via the `log_message("KTP_MATCH_END ...")` line. hlstats.pl parses
  only `matchid` and `map` (`getProperties`); the `status`/`reason` key is
  human-facing. **Firing the `ktp_match_end` forward does NOT reach HLStatsX** — a
  comment once claimed it did, and OT ends shipped broken on that belief.
  An **empty** quoted field is worse than no line at all: `getProperties` slurps
  past the empty quote pair to the next quote and mints a phantom match id out of
  the rest of the line, which then spreads across every stats table that joins on
  it. Refuse to go live with an empty `g_matchId` rather than logging one.
- **KTPAntiCheat API** — via `send_ac_match_end()`. Every match that went live was
  announced, so an exit that skips this orphans the row: `ended_at` stays NULL
  forever and `/api/match/current` re-serves the dead match to clients.

**Step order inside the stock is load-bearing:** flush → log → **AC close** →
context clear. `send_ac_match_end()` drains the final weapon-timeline batch, and
that drain reads `dodx_get_match_id()` to tag its rows — clearing the context first
silently discards the last flush interval (30s) of events, i.e. the end of the
deciding round. Never move the clear above the close.

It is **deliberately not idempotent**: `/api/match/end` already dedups server-side
(`WHERE ended_at IS NULL`, enqueue gated on `affected>0`), and a client-side latch
would suppress a legitimate re-close.

Known incident classes this prevents:
- `g_pfnChangeLevelProcessed` latched for the whole process (comment claimed AMXX
  reinit cleared it — false), silently disabling the primary match-end path.
  **Latches must be reset in `plugin_init()`**: plugin globals live for the whole
  server process, not per map.
- OT init block re-ran on every all-ready, clobbering round/scores/side-swap
  mid-match — one-shot blocks need an explicit guard (`!g_inOvertime` style).

## Async-boundary identity rule
A player **slot index is not an identity**. Any slot captured before a curl
request, `set_task`, menu, or confirmation window may point at a different person
when the callback fires (slots recycle on disconnect; `is_user_connected()` only
proves the slot is occupied). Capture the **authid alongside the slot** and
re-verify it at callback time. Suppressing the action on mismatch is the safe
direction; log the outcome unconditionally.

## OT correctness
- All OT side/roster/ready/captain mappings must key on `g_otTeam1StartsAs`,
  never on a hardcoded 2nd-half swap assumption (breaks on odd OT rounds).
- OT stays on the same map via `SetHookChainArg()` on the changelevel hook.

## Pawn checklist (apply to every diff)
- `charsmax(buf)` for every format/copy; watch truncation on composed strings.
- Every `set_task` with an id: unique id range, `remove_task` on disconnect AND
  on every teardown exit.
- Check return values of natives that can fail (file/curl/localinfo reads).
- Discord embeds: route user-supplied text through `ktp_discord_escape_json`.
- Any HUD that can share the screen with an AMXX menu goes on the **right**.
  `show_menu()` renders as a fixed left-side overlay with no positioning API, so the
  HUD is the only side with a degree of freedom — a left-positioned one made the
  `.kick` menu and the pause HUD mutually unreadable mid-match.
- Comments: short, explain *why*, no ticket/finding IDs, never delete a tripwire
  fact while editing near it.

## Never run a destructive simulation inside the working tree
Verifying a fix often means simulating the failure — writing a fake `build.sh`, a
fake artifact, a fake staging dir. Do it in a **verified** scratch dir, never in
the repo:

```bash
T="$(mktemp -d)" || exit 1
[ -n "$T" ] && [ -d "$T" ] || exit 1   # verify BEFORE you cd — this is the whole rule
cd "$T" || exit 1
```

`cd "$T"` with an empty `$T` **silently succeeds and leaves you where you were** —
in the repo. A simulation that then writes `build.sh` overwrites the real one. On
2026-07-16 exactly that truncated a tracked 60-line upstream file to 2 lines and
dropped a junk `.so` into `build/`, where a `find | head -1` could have staged it.
It was caught only because `git status` showed a modification nobody made.

So: verify the scratch dir before `cd`, and **run `git status` after any test that
touches the filesystem** — an unexpected change is the tell. Prefer copying inputs
out to the scratch dir over running tools "in place".

## Workflow
1. **Version bump** (every shipped change): `#define PLUGIN_VERSION` in the .sma,
   new `CHANGELOG.md` section, README header version, TODO.md if applicable.
2. **Commit BEFORE the build you intend to ship.** `compile.sh` generates
   `build_info.inc` from `git rev-parse --short HEAD` and appends **`-dirty`** when
   the tree has uncommitted changes; `ktp_version_reporter` then broadcasts that
   string fleet-wide. Staging a build made from a dirty tree puts a binary on 24
   production instances that **advertises itself as dirty and maps to no commit** —
   the exact traceability the version reporter exists to provide. Order is:
   commit → rebuild → stage that rebuild.
   **The rebuild changes the md5** (`build_info.inc` also bakes a per-minute
   `BUILD_TIME`), so a pre-commit md5 is dead the moment you commit. Take the md5
   from the post-commit build, and stage exactly that artifact — never rebuild
   again "just to be sure" after md5-verifying, or you'll stage a binary nobody
   reviewed. Same class as KTPAMXX's "don't rebuild the reviewed dodx" rule.
3. **Compile**: `wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler' && bash compile.sh"`
   (outputs `compiled/`, auto-stages to the KTP DoD Server test tree).
4. **Test-mode build** for the Tier-2 integration runner:
   `KTP_TEST_MODE=1 bash compile.sh` → `compiled/test/` (adds `amx_ktp_test_*`
   rcons; production binary is byte-identical without the flag). The Tier-2 runner
   does **not** pick up fleet bumps automatically — restage the test build and pin
   `EXPECTED_KTPMATCHHANDLER_VERSION` when the version changes.
5. **Review**: `ktp-code-review` agent before any fleet stage.
6. **Fleet stage**: deploy as `.new` via paramiko (see root CLAUDE.md § SSH);
   verify staged md5 on all 24 active instances. Confirm no OTHER `.new` exists
   fleet-wide first — one wave per nightly keeps a bad activation attributable.
7. **Post-activation verify** (after the nightly): 24/24 on the new md5, no
   leftover `.new`, and check `/tmp` for cores — `find /tmp -maxdepth 1 -name
   'core.*' -mtime -1` on every host. A game-tree core search proves nothing
   (matches only core.so/core.ini/core.wav).

## Known dead ends (don't retry)
- Client scoreboard team names ("Allies"/"Axis") are hardcoded client-side;
  `dodx_set_scoreboard_team_name()` cannot change them.
- AMX message natives for score broadcast crash — use `dodx_broadcast_team_score()`.
- `.pause`/`.tac` are disabled by policy; only `.tech` (team-budgeted) exists.
