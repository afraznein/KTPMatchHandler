#!/bin/bash
# Disassemble the key CBasePlayer functions and dump their full bodies so we
# can read the `this+OFFSET` store/load instructions and derive the real
# score/deaths byte offsets.
set -u
LSO="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/research/dod_i386.so.atl-24.04"
OUT="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/research/disas.txt"

cd "$(dirname "$LSO")"

echo "Disassembly of dod_i386.so (md5 $(md5sum "$LSO" | cut -d' ' -f1))" > "$OUT"
echo "Generated $(date -u +%FT%TZ)" >> "$OUT"
echo "" >> "$OUT"

for fn in \
    "AddFrags__11CBasePlayerii" \
    "AddObjScore__11CBasePlayerii" \
    "AddPoints__11CBasePlayerii" \
    "AddPointsToTeam__11CBasePlayerii" \
    "Killed__11CBasePlayerP9entvars_si"; do
    echo "============================================================" >> "$OUT"
    echo "== $fn" >> "$OUT"
    echo "============================================================" >> "$OUT"
    # Use --demangle and --disassemble=SYMBOL_NAME for clean targeted output
    objdump --demangle=auto --disassemble="$fn" -M intel "$LSO" >> "$OUT" 2>&1
    echo "" >> "$OUT"
done

# Also dump the data section symbols for gmsgScoreInfo* — these are global
# vars holding the message IDs; their use sites (MessageBegin calls) show
# where the ScoreInfo packet is built.
echo "============================================================" >> "$OUT"
echo "== Data symbols for ScoreInfo / Frags / Deaths" >> "$OUT"
echo "============================================================" >> "$OUT"
nm --demangle=auto "$LSO" 2>/dev/null | grep -iE "ScoreInfo|gmsgScore|gmsgDeaths|gmsgFrags" >> "$OUT"

wc -l "$OUT"
