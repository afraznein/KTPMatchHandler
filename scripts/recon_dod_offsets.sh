#!/bin/bash
# Recon dod_i386.so for canonical score/deaths struct offsets on Ubuntu 24.04.
# Intent: locate the byte offset (from pvPrivateData base) where the engine
# actually stores per-player score + deaths counters that the scoreboard
# reads from, replacing the spike's incorrect 481/482 int-offsets (= 1924/1928 byte).
set -u
LSO="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/research/dod_i386.so.atl-24.04"

if [ ! -f "$LSO" ]; then
    echo "missing $LSO — pull from ATL first"
    exit 1
fi

echo "=== ELF header ==="
readelf -h "$LSO" | head -12
echo

echo "=== Symbol table size summary ==="
nm "$LSO" 2>/dev/null | wc -l
nm --dynamic "$LSO" 2>/dev/null | wc -l
echo

echo "=== Class methods related to scoring/killing (text section symbols) ==="
nm --demangle=auto "$LSO" 2>/dev/null \
    | awk '$2 == "T" || $2 == "t" || $2 == "W" || $2 == "w"' \
    | grep -iE "Killed|ScoreInfo|MsgFunc|AddPoints|AddKill|AddDeath|GetScore|PlayerKilled|UpdateScore|SendInfo" \
    | head -50
echo

echo "=== ALL functions with 'kill' / 'death' / 'score' / 'frag' in name (text only) ==="
nm --demangle=auto "$LSO" 2>/dev/null \
    | awk '$2 == "T" || $2 == "t" || $2 == "W" || $2 == "w" {print $0}' \
    | grep -iE "kill|death|score|frag|points" \
    | head -60
echo

echo "=== References to score/deaths string literals ==="
strings -t x "$LSO" | grep -iE "scoreinfo|^[ ]*[0-9a-f]+[ ]+score|deaths|m_iScore|m_iDeath|m_iFrag" | head -30
echo

echo "=== Largest data symbols (suspect class instance layouts) ==="
nm --demangle=auto --size-sort "$LSO" 2>/dev/null | tail -20
