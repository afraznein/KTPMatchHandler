# HLStatsX:CE Integration Plan for KTP Match Stats

> **Created:** 2025-12-16
> **Purpose:** Foolproof separation of match stats vs non-match stats
> **Components:** DODX, stats_logging, KTPMatchHandler, HLStatsX:CE

---

## Executive Summary

To cleanly differentiate KTP match stats from warmup/practice stats, we need to:

1. **Flush warmup stats** before match starts (so they're logged separately)
2. **Reset stat counters** for fresh match tracking
3. **Log match markers** that HLStatsX can parse
4. **Add match_id** to HLStatsX event tables
5. **Modify HLStatsX Perl daemon** to track match context

This requires changes to **4 systems**: DODX module, stats_logging.sma, KTPMatchHandler.sma, and HLStatsX:CE.

---

## HLStatsX:CE Architecture (Research Findings)

### How It Works

```
Game Server → UDP Log Packets → HLStatsX Perl Daemon → MySQL Database → PHP Frontend
```

- **Log Source:** Game server sends logs via `logaddress_add` (UDP packets)
- **Parser:** `hlstats.pl` Perl daemon parses log lines in real-time
- **Storage:** Data stored in MySQL tables (`hlstats_Players`, `hlstats_Events_Frags`, etc.)
- **Display:** PHP pages query MySQL and generate stats pages

### Key Tables

| Table | Purpose |
|-------|---------|
| `hlstats_Players` | Permanent player stats (kills, deaths, skill, headshots) |
| `hlstats_Players_History` | Daily stat snapshots |
| `hlstats_Events_Frags` | Individual kill events (killerId, victimId, weapon, headshot) |
| `hlstats_Weapons` | Weapon statistics |
| `hlstats_Servers` | Server information |

### Current Limitation

**No match/session boundary tracking exists.** Stats accumulate continuously at the player level without match context. The `session_*` counters in the Perl daemon reset on map change, not on match boundaries.

### HL Log Standard Format

Events use the "triggered" format with extensible properties:
```
"PlayerName<uid><STEAM_ID><TEAM>" triggered "eventname" (key "value") (key2 "value2")
```

Custom properties can be added as `(key "value")` pairs.

---

## Integration Strategy

### Approach: Full Stack Modification

Since the user requires a **foolproof** solution, we'll modify all components:

1. **DODX Module** - Add natives for flush/reset
2. **stats_logging.sma** - Support flush/reset calls
3. **KTPMatchHandler.sma** - Call natives + log markers
4. **HLStatsX:CE Perl** - Parse markers, track match context
5. **HLStatsX:CE MySQL** - Add match_id columns

---

## Implementation Details

### Phase 1: DODX Module Changes (C++)

**Files:** `modules/dod/dodx/NRank.cpp`, `moduleconfig.cpp`

#### New Natives

```cpp
// Force flush all pending player stats to log
// Iterates all connected players and logs their current weaponstats
native dodx_flush_all_stats();

// Reset all player stat counters
// Clears accumulated stats for fresh match tracking
native dodx_reset_all_stats();

// Set match context for future stat logging
// matchId = "" clears the context
native dodx_set_match_id(const matchId[]);
```

#### Implementation Notes

- `dodx_flush_all_stats()` should trigger the same log output as `client_disconnected()` in stats_logging
- `dodx_reset_all_stats()` should zero out `g_izStats[id]`, `g_izBodyHits[id]`, etc.
- Match ID stored in a global variable for stats_logging to access

### Phase 2: stats_logging.sma Changes (Pawn)

**File:** `plugins/dod/stats_logging.sma`

#### New Public Functions

```pawn
// Called by DODX native to flush all stats
public stats_flush_all() {
    for (new id = 1; id <= MAX_PLAYERS; id++) {
        if (is_user_connected(id)) {
            log_player_stats(id);  // Log weaponstats/weaponstats2
        }
    }
}

// Called by DODX native to reset all stats
public stats_reset_all() {
    for (new id = 1; id <= MAX_PLAYERS; id++) {
        reset_player_stats(id);  // Clear stat arrays
    }
}

// Store match ID for inclusion in logs
new g_matchId[64];

public stats_set_match_id(const matchId[]) {
    copy(g_matchId, charsmax(g_matchId), matchId);
}
```

#### Modified Log Output

When match_id is set, include it in weaponstats:
```
"PlayerName<uid><STEAM_ID><TEAM>" triggered "weaponstats" (weapon "garand") (shots "50") ... (matchid "KTP-1734355200-dod_charlie")
```

### Phase 3: KTPMatchHandler.sma Changes (Pawn)

**File:** `KTPMatchHandler.sma`

#### Match Start Flow

```pawn
// When match goes LIVE:
public on_match_live() {
    // 1. Flush warmup stats (logged as non-match)
    dodx_flush_all_stats();

    // 2. Reset for fresh match tracking
    dodx_reset_all_stats();

    // 3. Set match context
    dodx_set_match_id(g_matchId);

    // 4. Log match start marker for HLStatsX
    log_amx("KTP_MATCH_START (matchid \"%s\") (map \"%s\") (half \"%d\")",
            g_matchId, g_currentMap, g_currentHalf);

    // Continue with match start...
}
```

#### Match/Half End Flow

```pawn
// When match/half ends:
public on_match_end() {
    // 1. Flush match stats (logged WITH matchid)
    dodx_flush_all_stats();

    // 2. Log match end marker
    log_amx("KTP_MATCH_END (matchid \"%s\") (map \"%s\")", g_matchId, g_currentMap);

    // 3. Clear match context
    dodx_set_match_id("");

    // Continue with match end...
}
```

### Phase 4: HLStatsX:CE Perl Daemon Changes

**Files:** `scripts/hlstats.pl`, `scripts/HLstats_EventHandlers.plib`

#### New Match Context Tracking

```perl
# Global match context per server
my %g_matchContext;  # $g_matchContext{$server_addr} = { matchid => "", map => "" }

# Handler for KTP_MATCH_START
sub doEvent_KTPMatchStart {
    my ($s_addr, $properties) = @_;

    $g_matchContext{$s_addr} = {
        matchid => $properties->{matchid},
        map => $properties->{map},
        half => $properties->{half},
        start_time => time()
    };

    # Insert into ktp_matches table
    &doQuery("INSERT INTO ktp_matches (match_id, server_id, map_name, half, start_time)
              VALUES ('$properties->{matchid}', $serverId, '$properties->{map}', $properties->{half}, NOW())");
}

# Handler for KTP_MATCH_END
sub doEvent_KTPMatchEnd {
    my ($s_addr, $properties) = @_;

    # Update match end time
    &doQuery("UPDATE ktp_matches SET end_time = NOW() WHERE match_id = '$properties->{matchid}'");

    # Clear context
    delete $g_matchContext{$s_addr};
}
```

#### Modified Event Recording

```perl
# In recordEvent() or doEvent_Frag():
sub recordEvent {
    my ($eventType, @fields) = @_;

    # Get current match context
    my $matchId = "";
    if (exists $g_matchContext{$s_addr}) {
        $matchId = $g_matchContext{$s_addr}->{matchid};
    }

    # Include match_id in INSERT
    &doQuery("INSERT INTO hlstats_Events_$eventType (..., match_id)
              VALUES (..., '$matchId')");
}
```

### Phase 5: HLStatsX:CE MySQL Schema Changes

#### Add match_id to Event Tables

```sql
-- Add match_id column to event tables
ALTER TABLE hlstats_Events_Frags
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL,
ADD INDEX idx_match_id (match_id);

ALTER TABLE hlstats_Events_Teamkills
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL;

-- etc. for other event tables
```

#### New KTP Match Tables

```sql
-- Match metadata
CREATE TABLE ktp_matches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id VARCHAR(64) UNIQUE NOT NULL,
    server_id INT NOT NULL,
    map_name VARCHAR(32) NOT NULL,
    half TINYINT DEFAULT 1,
    start_time DATETIME NOT NULL,
    end_time DATETIME DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_server (server_id),
    INDEX idx_start_time (start_time),
    FOREIGN KEY (server_id) REFERENCES hlstats_Servers(serverId)
);

-- Players in each match
CREATE TABLE ktp_match_players (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    steam_id VARCHAR(32) NOT NULL,
    player_name VARCHAR(32) NOT NULL,
    team TINYINT NOT NULL,
    joined_at DATETIME NOT NULL,
    INDEX idx_match (match_id),
    INDEX idx_player (player_id),
    FOREIGN KEY (match_id) REFERENCES ktp_matches(match_id),
    FOREIGN KEY (player_id) REFERENCES hlstats_Players(playerId)
);

-- Match-specific player stats (aggregated from events)
CREATE TABLE ktp_match_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    kills INT DEFAULT 0,
    deaths INT DEFAULT 0,
    headshots INT DEFAULT 0,
    team_kills INT DEFAULT 0,
    INDEX idx_match (match_id),
    INDEX idx_player (player_id),
    FOREIGN KEY (match_id) REFERENCES ktp_matches(match_id),
    FOREIGN KEY (player_id) REFERENCES hlstats_Players(playerId)
);
```

---

## Data Flow Summary

### Before Match (Warmup)

```
1. Players join, practice
2. Stats accumulate in DODX (g_izStats[])
3. [Nothing logged yet - stats pending in memory]
```

### Match Start

```
1. All players /ready → Match goes LIVE
2. dodx_flush_all_stats()
   → stats_logging logs warmup stats (NO matchid)
   → HLStatsX parses, stores in Events tables (match_id = NULL)
3. dodx_reset_all_stats()
   → Clears all stat counters
4. dodx_set_match_id(g_matchId)
   → Sets context for future logs
5. log_amx("KTP_MATCH_START ...")
   → HLStatsX parses, creates ktp_matches row
   → Sets g_matchContext for this server
```

### During Match

```
1. Players get kills, die
2. HLStatsX parses frag events
3. Events stored WITH match_id from g_matchContext
4. All kills/deaths associated with match
```

### Match End

```
1. Round ends or /end command
2. dodx_flush_all_stats()
   → stats_logging logs final match stats (WITH matchid)
3. log_amx("KTP_MATCH_END ...")
   → HLStatsX parses, updates ktp_matches.end_time
   → Clears g_matchContext
4. Future stats have match_id = NULL again
```

---

## Query Examples

### Get Match Stats

```sql
-- All kills in a specific match
SELECT ef.*, p1.lastName as killer, p2.lastName as victim
FROM hlstats_Events_Frags ef
JOIN hlstats_Players p1 ON ef.killerId = p1.playerId
JOIN hlstats_Players p2 ON ef.victimId = p2.playerId
WHERE ef.match_id = 'KTP-1734355200-dod_charlie';

-- Match leaderboard
SELECT p.lastName,
       COUNT(CASE WHEN ef.killerId = p.playerId THEN 1 END) as kills,
       COUNT(CASE WHEN ef.victimId = p.playerId THEN 1 END) as deaths
FROM hlstats_Players p
JOIN hlstats_Events_Frags ef ON ef.match_id = 'KTP-1734355200-dod_charlie'
    AND (ef.killerId = p.playerId OR ef.victimId = p.playerId)
GROUP BY p.playerId
ORDER BY kills DESC;
```

### Get Non-Match Stats (Warmup/Practice)

```sql
-- All kills NOT in any match
SELECT * FROM hlstats_Events_Frags
WHERE match_id IS NULL;
```

---

## Testing Checklist

- [ ] DODX `dodx_flush_all_stats()` logs all pending stats
- [ ] DODX `dodx_reset_all_stats()` clears all stat arrays
- [ ] DODX `dodx_set_match_id()` stores match context
- [ ] stats_logging includes matchid in weaponstats when set
- [ ] KTPMatchHandler calls flush/reset/set at correct times
- [ ] HLStatsX parses KTP_MATCH_START correctly
- [ ] HLStatsX parses KTP_MATCH_END correctly
- [ ] Events during match have match_id populated
- [ ] Events outside match have match_id = NULL
- [ ] ktp_matches table populated correctly
- [ ] Queries can separate match vs non-match stats

---

## Files to Modify

| Project | File | Changes |
|---------|------|---------|
| KTPAMXX | `modules/dod/dodx/NRank.cpp` | Add native implementations |
| KTPAMXX | `modules/dod/dodx/moduleconfig.cpp` | Register natives |
| KTPAMXX | `plugins/dod/stats_logging.sma` | Add flush/reset functions |
| KTPMatchHandler | `KTPMatchHandler.sma` | Call natives, log markers |
| HLStatsX | `scripts/hlstats.pl` | Add match context tracking |
| HLStatsX | `scripts/HLstats_EventHandlers.plib` | Add KTP event handlers |
| HLStatsX | `sql/install.sql` | Add match_id columns, new tables |

---

## References

- [HLStatsX:CE GitHub](https://github.com/NomisCZ/hlstatsx-community-edition)
- [HL Log Standard](https://hlstats.org/logs)
- [AlliedModders HLStatsX Forum](https://forums.alliedmods.net/forumdisplay.php?f=156)

---

*This document should be updated as implementation progresses.*
