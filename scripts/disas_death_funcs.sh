#!/bin/bash
# Find where m_iDeaths is incremented. Candidates: CDoDTeamPlay::PlayerKilled,
# CDoDTeamPlay::DeathNotice, ClientKill (suicide entry), or any helper called
# from the death path.
set -u
LSO="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/research/dod_i386.so.atl-24.04"
OUT="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/research/disas_death.txt"

echo "Disassembly of death-handling functions (dod_i386.so md5 $(md5sum "$LSO" | cut -d' ' -f1))" > "$OUT"
echo "" >> "$OUT"

for fn in \
    "ClientKill__FP7edict_s" \
    "PlayerKilled__12CDoDTeamPlayP11CBasePlayerP9entvars_sT2i" \
    "DeathNotice__12CDoDTeamPlayP11CBasePlayerP9entvars_sT2i" \
    "PlayerKilled__11CSPDoDRulesP11CBasePlayerP9entvars_sT2i" \
    "DeathNotice__11CSPDoDRulesP11CBasePlayerP9entvars_sT2i"; do
    echo "============================================================" >> "$OUT"
    echo "== $fn" >> "$OUT"
    echo "============================================================" >> "$OUT"
    objdump --demangle=auto --disassemble="$fn" -M intel "$LSO" >> "$OUT" 2>&1
    echo "" >> "$OUT"
done

wc -l "$OUT"
