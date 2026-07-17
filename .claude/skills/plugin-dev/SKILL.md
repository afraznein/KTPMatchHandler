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
- Match state survives map changes via localinfo keys (`_ktp_mid`, `_ktp_map`,
  `_ktp_mode`, `_ktp_state`, `_ktp_h1`, `_ktp_t1n`/`_ktp_t2n`, `_ktp_reg`,
  `_ktp_ots`, `_ktp_otst`). Any new persistent state needs a localinfo key AND a
  clear on every teardown exit (see below).
- Score writes during map change crash: never call `dodx_set_team_score()` directly
  in a changelevel window — set `g_pendingScoreAllies/Axis` and use
  `schedule_score_restoration()` (applies on next flag touch).

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
- Comments: short, explain *why*, no ticket/finding IDs, never delete a tripwire
  fact while editing near it.

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
