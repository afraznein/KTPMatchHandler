# Day of Defeat Wall Penetration Issue - Analysis Summary

## The Problem

Wall penetration breaks when using **ReHLDS + Metamod** together. Any version of Metamod.

| Configuration | Wall Penetration |
|--------------|------------------|
| ReHLDS + DoD (no Metamod) | **WORKS** |
| Vanilla HLDS + Metamod + DoD | **WORKS** |
| ReHLDS + Metamod + DoD | **BROKEN** |

Symptoms: Bullets stop at first surface. No exit holes, no penetration effects.

---

## The Key Discovery

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

**The trace results are identical through bullet 3.** Same fractions, same positions, same flags. But DoD makes a different internal decision - with Metamod present, it stops after finding the exit point instead of continuing to traces 4 and 5 (actual penetration).

---

## What We Ruled Out

We systematically bypassed every layer:

| Test | Result |
|------|--------|
| Bypass individual trace wrappers | Still broken |
| Bypass ALL trace wrappers | Still broken |
| Pass original enginefuncs_t directly to DoD | Still broken |
| Pass original DLL_FUNCTIONS to engine | Still broken |
| Pass original NEW_DLL_FUNCTIONS to engine | Still broken |
| All three tables bypassed simultaneously | **Still broken** |

Even with complete API bypass - DoD receiving original ReHLDS functions, engine receiving original DoD functions, no Metamod wrappers in the call chain - wall penetration still fails.

---

## Root Cause

**The mere presence of Metamod in the DLL loading chain changes DoD's internal state.**

The issue is not in the API tables. It's in the loading process itself:

1. ReHLDS calls `GiveFnptrsToDll` to Metamod (thinking it's the game DLL)
2. Metamod calls `GiveFnptrsToDll` to the real DoD
3. DoD receives the enginefuncs table from Metamod's address space

DoD appears to be making decisions based on something other than the function pointers themselves - possibly the address of the table, module addresses, initialization timing, or memory layout assumptions.

Vanilla HLDS + Metamod works because they were developed together and whatever assumptions DoD makes are satisfied. ReHLDS, as a reimplementation, has subtle differences that break this.

---

## The Solution

Bypass Metamod entirely.

```
Previous (BROKEN):
ReHLDS → Metamod → AMXX → DoD

Solution (WORKING):
ReHLDS → DoD
   ↓
AMXX Lite (loaded via extensions.ini)
```

KTP-ReHLDS includes an extension loader that loads DLLs directly without inserting them into the game DLL chain. KTPAMXX is a modified AMX Mod X that runs through this extension system instead of through Metamod.

---

## Configuration

**Before (broken):**
```
liblist.gam:
  gamedll_linux "addons/metamod/metamod_i386.so"
```

**After (working):**
```
liblist.gam:
  gamedll_linux "dlls/dod.so"

addons/extensions.ini:
  addons/amxxlite/amxxlite_i386.so
```

---

*Last Updated: 2025-12-04*
