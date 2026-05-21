# DODX pdata offset research — Ubuntu 24.04 baremetal

Generated 2026-05-21 by disassembling production `dod_i386.so` from ATL:27019 (Ubuntu 24.04.4 LTS, GLIBC 2.39).

- **Binary:** `dod_i386.so` md5 `4f4727b2390d3a0ed6f5ad862dd6d4be`, 2,145,843 bytes, ELF32-i386, **not stripped** (symbols preserved).
- **Source:** `/home/dodserver/dod-27019/serverfiles/dod/dlls/dod_i386.so` (same binary used on all 5 active baremetals — Atlanta, Dallas, Denver, New York, Chicago).
- **Artifacts:**
  - `dod_i386.so.atl-24.04` — pulled binary
  - `recon_output.txt` — symbol-table dump
  - `disas.txt` — `AddFrags` / `AddObjScore` / `AddPoints` / `AddPointsToTeam` / `CBasePlayer::Killed`
  - `disas_death.txt` — `ClientKill` / `CDoDTeamPlay::PlayerKilled` / `CDoDTeamPlay::DeathNotice` / `CSPDoDRules::*`

## Confirmed offsets

`pvPrivateData` is the `this` pointer of the `CBasePlayer` instance (HLDS engine convention). Offsets below are in bytes from that base.

| Field | Byte offset | Int-offset (÷4) | Type | Evidence |
|---|---|---|---|---|
| `m_iObjScore` | `0x780` | **480** | `int` | `CBasePlayer::AddObjScore` at `0xf396c`: `add DWORD PTR [edi+0x780], eax` where edi = this. The same `[edi+0x780]` is reloaded at `0xf3a13` for the subsequent ScoreInfo send. |
| `m_iDeaths` | `0x784` | **481** | `int` | `CDoDTeamPlay::PlayerKilled` at `0xb272e`: `inc DWORD PTR [eax+0x784]` where eax = pVictim (loaded from `[ebp+0xc]` at `0xb272b`). Death counter increment happens immediately before the scoreboard refresh sequence at `0xb2734-0xb277c`. |
| `pev->frags` (NOT in pvPrivateData) | n/a | n/a | `float` in `entvars_t` | `CBasePlayer::AddFrags` at `0xf38c5`: `fadd DWORD PTR [eax+0x164]` where `eax = this->pev` (loaded via `mov eax,[edi]` since pev is offset 0 of CBaseEntity). Frags is a float on entvars_t at offset `0x164`, NOT an int on pvPrivateData. |

The scoreboard's "Score" and "Deaths" columns are populated from the `ScoreInfoLong` user message which the engine builds from these fields (verified in the strings table: `gmsgScoreInfoLong` symbol `0x001891b4`, ASCII string at file offset `0x16f4ee`).

## What went wrong in spike v1.2 (5/21 client test)

Spike v1.2 (`851295e4` on branch `feature/dodx-score-persistence-spike-v1.2`):

```c
// dodx.h
#define STEAM_PDOFFSET_SCORE    (476 + g_iLinuxPdataOffsetAdjust)
#define STEAM_PDOFFSET_DEATHS   (477 + g_iLinuxPdataOffsetAdjust)

// NBase.cpp (read path)
return *((int*)pEdict->pvPrivateData + STEAM_PDOFFSET_SCORE);
```

Note `*((int*)pvPrivateData + N)` is **int-offset arithmetic**, so `N = 481` reads the int at byte 1924 = `0x784`, and `N = 480` reads the int at byte 1920 = `0x780`.

**Spike design intent:** default `g_iLinuxPdataOffsetAdjust = 4`. With `+4`:
- SCORE = `476 + 4` = **480** ✓ (= `m_iObjScore`)
- DEATHS = `477 + 4` = **481** ✓ (= `m_iDeaths`)

**What actually happened at runtime:** The `g_iLinuxPdataOffsetAdjust` value is shared with the grenade-ammo offsets. The boot-time auto-detect in `moduleconfig.cpp` (around `1990-2020`) is triggered by the **first grenade op** and uses a heuristic on the grenade-ammo offsets to promote `g_iLinuxPdataOffsetAdjust` from 4 to 5 on older glibc. On the 24.04 fleet that heuristic **falsely promotes to 5** (boot-time log on ATL:27019 5/21: `[DODX] Auto-detected pdata offset +5 (score +5=2 vs +4=0 out of 6)`). After the promotion:
- SCORE = `476 + 5` = **481** → reads `m_iDeaths` (= 2 because deaths==2 at test end)
- DEATHS = `477 + 5` = **482** → reads whatever int sits past `m_iDeaths` (= 0)

This perfectly explains the 5/21 test result (scoreboard 3/2, captured 2/0):
- "score=2" was actually reading m_iDeaths
- "deaths=0" was reading the field past m_iDeaths

The heuristic's "score +5=2 vs +4=0" framing is also revealing: at boot time (before any players had scored), `m_iObjScore` was 0 for all 6 players checked, and `m_iDeaths` was 0 too — but the int just past `m_iDeaths` had some non-zero stale value, which the heuristic interpreted as evidence that "+5 is the correct slot." **Non-zero-int-at-N is not evidence that N is the right field.**

## Architectural mistake

A single global `g_iLinuxPdataOffsetAdjust` is shared across two field families with **different correct adjust values on the same OS build**:

| Field family | Base offsets | Correct adjust on Ubuntu 24.04 (fleet-confirmed) |
|---|---|---|
| Grenade-ammo (`PDOFFSET_BASE_HANDGRENADE_*` = 59-64, `PDOFFSET_BASE_STICKGRENADE_*` = 61-66) | adjust = **5** (production fleet grenade refills work; this was the empirically-validated value before the spike) |
| Score / Deaths (`STEAM_PDOFFSET_SCORE` = 476, `STEAM_PDOFFSET_DEATHS` = 477) | adjust = **4** (this research) |

Two field families that happen to live in different struct regions can shift by different amounts between compiler / glibc / kernel ABI versions. Forcing them into the same adjust global is the architectural bug.

## Recommended fix paths (operator decision)

### Option A — Hardcode literals for current fleet (~5 min, 1-line change)
```c
#define STEAM_PDOFFSET_SCORE    480
#define STEAM_PDOFFSET_DEATHS   481
```
Pros: minimum diff, immediately ships the spike. Cons: breaks portability to non-24.04 hosts (the deprecated Atlanta/Dallas/Old-Dallas VPS hosts would have wrong offsets if any were reactivated).

### Option B — Separate adjust per field family (~30 min)
Introduce `g_iScoreDeathsOffsetAdjust` separate from `g_iLinuxPdataOffsetAdjust`. Default both to 4. Keep the grenade auto-detect promoting only the grenade adjust to 5; leave score/deaths at 4. Score/deaths get **no auto-detect** (the heuristic was the bug — eliminate it for fields without one).
```c
#define STEAM_PDOFFSET_SCORE    (476 + g_iScoreDeathsOffsetAdjust)
#define STEAM_PDOFFSET_DEATHS   (477 + g_iScoreDeathsOffsetAdjust)
```
Pros: portable, avoids the heuristic foot-gun. Cons: still relies on baked-in defaults that may shift on a future OS bump.

### Option C — Validate against AMXX builtin at first SAVE (~2h)
Before exposing the `dodx_get/set_user_score/deaths` natives, validate the read path against AMXX's existing builtin `get_user_deaths(id)` for a connected player. If mismatch, fall back: SAVE uses the AMXX builtins (read-only stable), RESTORE is disabled. Adds a real ground-truth comparison gate (the same pattern the memory `dodx_pdata_offsets_ubuntu_shift.md` calls for).
Pros: robust against future offset shifts. Cons: requires a connected player at validation time (offset isn't validated until first SAVE call, so server boot can't pre-validate).

### Option D — Combine B + C (~2.5h, recommended)
Use Option B's separated adjusts as defensible defaults; layer Option C's runtime validation on top. If first-SAVE validation against AMXX builtin disagrees with the spike's read, log loudly and switch the spike natives into a "validation-failed, AMXX-fallback" mode that doesn't read or write pdata directly.

## Open questions for redesign

1. **Is `get_user_deaths()` (AMXX core builtin) currently working on the fleet?** If yes, Option C/D is trivially feasible. If no (e.g., it goes through the same broken offset somewhere), need to find a different ground truth. Verify by sending `amx_ktp_test_setup_match` → drive to LIVE → `dodx_get_user_deaths` vs the AMXX builtin at SAVE time with a real client.
2. **Does the validation gate need to handle the empty-pdata case** (first connect, no kills yet) gracefully? At boot time both fields are 0; the gate must wait until at least one engine-update has touched the field before comparing.
3. **Mac/Windows portability** — the existing `#ifdef __linux__` branch has Windows literal offsets (476/477 with no adjust). Those are the Windows DoD server values; the spike inherits them as the `#else` branch. Mac builds of DoD aren't part of the current scope but if added would need separate offsets.
4. **Does the grenade adjust=5 promotion still happen on a freshly-restarted fleet host?** If yes, the heuristic is reproducible and worth instrumenting before the fix; if it varies (some boots stay at 4, some go to 5), the heuristic is sampling stack-garbage and any future change to map-load timing could flip behavior. Worth a one-off "boot 25 instances, count how many promote" before designing.

## Pickup state

- Task #6 (re-research offsets): research phase **COMPLETE**.
- KTPAMXX spike branch `feature/dodx-score-persistence-spike-v1.2` (commit `851295e4`) **preserved unchanged** — fix design must land on top of it.
- KTPMatchHandler `main` working tree: 181 uncommitted v1.2 spike lines — preserved unchanged.
- ATL:27019 production state: rolled back to 0.10.121 + pre-spike dodx (md5 `cb670f75…`).
- Next step: operator picks fix path (A/B/C/D), implements + retests via the same deploy/test/rollback workflow (scripts in `KTPMatchHandler/scripts/`).
