# KTPMatchHandler TODO

> **Created:** 2025-12-16
> **Last Updated:** 2025-12-20
> **Current Version:** 0.9.1 (Discord Embed Roster + Score Persistence Fix)

This document tracks planned features and improvements for KTPMatchHandler.
Use this to maintain context across conversation resets.

---

## v0.6.0 Release Summary

**Released:** 2025-12-16
**Status:** Compiled and staged to server

### Features Delivered

| Feature | Status | Notes |
|---------|--------|-------|
| Match ID System | ✅ Done | Format: `KTP-{timestamp}-{mapname}` |
| Match ID in Discord | ✅ Done | Displayed in code block |
| Match ID in Logs | ✅ Done | MATCH_START, HALF_START, HALF_END |
| `/whoneedsready` command | ✅ Done | Shows unready players with Steam IDs |
| Steam IDs in announcements | ✅ Done | READY/NOTREADY messages |
| Periodic unready reminder | ✅ Done | Every 30 sec, team-specific |
| Streamlined match flow | ✅ Done | No pause during ready phase |
| Player roster to Discord | ✅ Existing | Already implemented |

### Match Flow (v0.6.0)

```
/start → Pre-start phase
   ↓
/confirm (both teams) → Pending phase begins
   ↓
Players /ready (reminders every 30 sec)
   ↓
All players ready → MATCH IS LIVE! (immediate, no pause)
```

---

## v0.7.0: HLStatsX:CE Stats Integration

**Goal:** Foolproof separation of match stats vs non-match (warmup/practice) stats.

### Problem Statement

- HLStatsX:CE tracks stats continuously with no match boundaries
- Players accumulate warmup stats before KTP match starts
- No way to differentiate match kills from warmup kills
- Need clean separation for competitive stat tracking

### Solution Overview

Modify **5 systems** to create end-to-end match context tracking:

```
Game Server                    Data Server
┌─────────────────┐            ┌─────────────────┐
│ DODX Module     │            │ HLStatsX:CE     │
│ stats_logging   │ ──UDP──→   │ Perl Daemon     │
│ KTPMatchHandler │            │ MySQL Database  │
└─────────────────┘            └─────────────────┘
```

### Data Flow

```
WARMUP PHASE:
  Players join, practice
  Stats accumulate in DODX memory (g_izStats[])
  [Nothing logged yet]

MATCH START (all players /ready):
  1. dodx_flush_all_stats()     → Log warmup stats (NO matchid)
  2. dodx_reset_all_stats()     → Clear all counters
  3. dodx_set_match_id(id)      → Set match context
  4. log "KTP_MATCH_START"      → HLStatsX creates ktp_matches row

DURING MATCH:
  Kills/deaths logged WITH match_id
  HLStatsX stores events with match_id column populated

MATCH END:
  1. dodx_flush_all_stats()     → Log match stats (WITH matchid)
  2. log "KTP_MATCH_END"        → HLStatsX updates end_time
  3. dodx_set_match_id("")      → Clear context

POST-MATCH:
  Future stats have match_id = NULL again
```

---

### Phase 1: DODX Module Changes (C++)

**Project:** KTPAMXX
**Files:** `modules/dod/dodx/NRank.cpp`, `moduleconfig.cpp`

#### New Natives

```cpp
// Native: dodx_flush_all_stats()
// Purpose: Force write all pending player stats to log
// Implementation: Iterate all connected players, call stats_logging's log function
// Returns: Number of players flushed
native dodx_flush_all_stats();

// Native: dodx_reset_all_stats()
// Purpose: Clear accumulated stats for fresh match tracking
// Implementation: Zero out g_izStats[], g_izBodyHits[], g_izUserRoundStats[]
// Returns: Number of players reset
native dodx_reset_all_stats();

// Native: dodx_set_match_id(const matchId[])
// Purpose: Set match context for future stat log lines
// Implementation: Store in global g_matchId variable
// Pass empty string to clear context
native dodx_set_match_id(const matchId[]);
```

#### Implementation Details

```cpp
// In NRank.cpp

// Global match context
char g_szMatchId[64] = "";

// Native implementations
static cell AMX_NATIVE_CALL dodx_flush_all_stats(AMX *amx, cell *params) {
    int count = 0;
    for (int i = 1; i <= gpGlobals->maxClients; i++) {
        CPlayer* pPlayer = GET_PLAYER_POINTER_I(i);
        if (pPlayer && pPlayer->ingame) {
            // Call stats_logging public function
            // MF_ExecuteForward() to "stats_flush_player"
            count++;
        }
    }
    return count;
}

static cell AMX_NATIVE_CALL dodx_reset_all_stats(AMX *amx, cell *params) {
    int count = 0;
    for (int i = 1; i <= gpGlobals->maxClients; i++) {
        CPlayer* pPlayer = GET_PLAYER_POINTER_I(i);
        if (pPlayer) {
            // Zero out stats arrays
            memset(pPlayer->weapons, 0, sizeof(pPlayer->weapons));
            // ... reset other stat arrays
            count++;
        }
    }
    return count;
}

static cell AMX_NATIVE_CALL dodx_set_match_id(AMX *amx, cell *params) {
    int len;
    char* matchId = MF_GetAmxString(amx, params[1], 0, &len);
    strncpy(g_szMatchId, matchId, sizeof(g_szMatchId) - 1);
    return 1;
}

// Getter for stats_logging to use
const char* DODX_GetMatchId() {
    return g_szMatchId;
}
```

#### Tasks - Phase 1 ✅ COMPLETE
- [x] Add `g_szMatchId` global variable to DODX
- [x] Implement `dodx_flush_all_stats()` native
- [x] Implement `dodx_reset_all_stats()` native
- [x] Implement `dodx_set_match_id()` native
- [x] Implement `dodx_get_match_id()` native (added)
- [x] Register natives in `moduleconfig.cpp`
- [x] Register `dod_stats_flush` forward in `moduleconfig.cpp`
- [x] Add `DODX_GetMatchId()` export for stats_logging
- [x] Test natives compile and link (verified 2025-12-17)

---

### Phase 2: stats_logging.sma Changes (Pawn)

**Project:** KTPAMXX
**File:** `plugins/dod/stats_logging.sma`

#### New Public Functions

```pawn
// Global match ID storage (set by DODX native)
new g_matchId[64];

// Called by DODX native to flush a single player's stats
public stats_flush_player(id) {
    if (!is_user_connected(id)) return;

    // Log weaponstats for this player (same as client_disconnected)
    log_player_weaponstats(id);
    log_player_weaponstats2(id);
}

// Called by DODX native to flush ALL players
public stats_flush_all() {
    for (new id = 1; id <= MAX_PLAYERS; id++) {
        if (is_user_connected(id)) {
            stats_flush_player(id);
        }
    }
}

// Called by DODX native to reset a single player's stats
public stats_reset_player(id) {
    if (!is_user_connected(id)) return;

    // Zero out stat arrays for this player
    // (Implementation depends on how stats are stored)
}

// Called by DODX native to reset ALL players
public stats_reset_all() {
    for (new id = 1; id <= MAX_PLAYERS; id++) {
        stats_reset_player(id);
    }
}

// Called by DODX native to set match context
public stats_set_match_id(const matchId[]) {
    copy(g_matchId, charsmax(g_matchId), matchId);
}
```

#### Modified weaponstats Log Format

```pawn
// Current format:
// "Player<uid><STEAM_ID><TEAM>" triggered "weaponstats" (weapon "x") (shots "x") ...

// New format when match_id is set:
// "Player<uid><STEAM_ID><TEAM>" triggered "weaponstats" (weapon "x") (shots "x") ... (matchid "KTP-xxx")

stock log_player_weaponstats(id) {
    // ... existing code to build stats string ...

    // Append matchid if set
    if (g_matchId[0]) {
        format(logString, charsmax(logString), "%s (matchid ^"%s^")", logString, g_matchId);
    }

    log_message(logString);
}
```

#### Tasks - Phase 2 ✅ COMPLETE
- [x] Add `g_matchId` global variable
- [x] Implement `dod_stats_flush()` forward handler (handles per-player flush)
- [x] Implement `log_player_stats()` shared function (reused in client_disconnected)
- [x] Modify log output to include matchid when set
- [x] Add native declarations to `dodx.inc`
- [x] Test logging with and without match context (compiled 2025-12-17, needs live test)

---

### Phase 3: KTPMatchHandler.sma Changes (Pawn)

**Project:** KTPMatchHandler
**File:** `KTPMatchHandler.sma`

#### Include DODX Natives

```pawn
// At top of file, declare natives
native dodx_flush_all_stats();
native dodx_reset_all_stats();
native dodx_set_match_id(const matchId[]);
```

#### Match Start Integration

```pawn
// In cmd_ready() when match goes LIVE:

// After: announce_all("=== MATCH IS LIVE! ===");
// Add:

// Flush warmup stats (logged WITHOUT matchid)
new flushed = dodx_flush_all_stats();
log_ktp("event=STATS_FLUSH type=warmup players=%d", flushed);

// Reset stats for fresh match tracking
new reset = dodx_reset_all_stats();
log_ktp("event=STATS_RESET players=%d", reset);

// Set match context for future stats
dodx_set_match_id(g_matchId);

// Log match start marker for HLStatsX
log_amx("KTP_MATCH_START (matchid ^"%s^") (map ^"%s^") (half ^"%d^")",
        g_matchId, g_currentMap, g_currentHalf);
```

#### Match/Half End Integration

```pawn
// In handle_map_change() or match end handler:

// Flush match stats (logged WITH matchid)
new flushed = dodx_flush_all_stats();
log_ktp("event=STATS_FLUSH type=match players=%d match_id=%s", flushed, g_matchId);

// Log match end marker for HLStatsX
log_amx("KTP_MATCH_END (matchid ^"%s^") (map ^"%s^")", g_matchId, g_currentMap);

// Clear match context
dodx_set_match_id("");
```

#### Tasks - Phase 3 ✅ COMPLETE
- [x] Add `#tryinclude <dodx>` with HAS_DODX define
- [x] Add flush/reset/set_match_id calls at match start (when all players ready)
- [x] Add flush at 1st half end (stats continue for 2nd half)
- [x] Add flush and KTP_MATCH_END at 2nd half end (match complete)
- [x] Add KTP_MATCH_START log line for HLStatsX parsing
- [x] Add KTP_MATCH_END log line for HLStatsX parsing
- [x] Update version to 0.7.0
- [x] Test full match flow with logging (compiled 2025-12-17, needs live test)

---

### Phase 4: HLStatsX:CE Perl Daemon Changes

**Project:** HLStatsX:CE (fork or modify)
**Files:** `scripts/hlstats.pl`, `scripts/HLstats_EventHandlers.plib`

#### Match Context Tracking

```perl
# In hlstats.pl or HLstats_EventHandlers.plib

# Global hash to track match context per server
my %g_matchContext;
# Structure: $g_matchContext{$server_addr} = {
#     matchid => "KTP-xxx",
#     map => "dod_charlie",
#     half => 1,
#     start_time => 1734355200
# }

# Event handler for KTP_MATCH_START
sub doEvent_KTPMatchStart {
    my ($s_addr, $properties) = @_;

    my $matchId = $properties->{matchid} || "";
    my $map = $properties->{map} || "";
    my $half = $properties->{half} || 1;

    # Store context for this server
    $g_matchContext{$s_addr} = {
        matchid => $matchId,
        map => $map,
        half => $half,
        start_time => time()
    };

    # Get server ID
    my $serverId = $g_servers{$s_addr}->{id};

    # Insert into ktp_matches table
    my $query = "INSERT INTO ktp_matches
                 (match_id, server_id, map_name, half, start_time)
                 VALUES (?, ?, ?, ?, NOW())
                 ON DUPLICATE KEY UPDATE half = ?, start_time = NOW()";
    &doQuery($query, $matchId, $serverId, $map, $half, $half);

    &printEvent("MATCH", "KTP Match started: $matchId on $map (half $half)");
}

# Event handler for KTP_MATCH_END
sub doEvent_KTPMatchEnd {
    my ($s_addr, $properties) = @_;

    my $matchId = $properties->{matchid} || "";

    # Update match end time
    my $query = "UPDATE ktp_matches SET end_time = NOW() WHERE match_id = ?";
    &doQuery($query, $matchId);

    # Clear context for this server
    delete $g_matchContext{$s_addr};

    &printEvent("MATCH", "KTP Match ended: $matchId");
}
```

#### Modified Event Recording

```perl
# In recordEvent() function - add match_id parameter

sub recordEvent {
    my ($eventType, $playerId, @otherFields) = @_;

    # Get current match context for this server
    my $matchId = "";
    if (exists $g_matchContext{$s_addr} && $g_matchContext{$s_addr}->{matchid}) {
        $matchId = $g_matchContext{$s_addr}->{matchid};
    }

    # Build INSERT with match_id
    my $query = "INSERT INTO hlstats_Events_$eventType
                 (eventTime, serverId, map, match_id, ...)
                 VALUES (?, ?, ?, ?, ...)";

    # ... execute query with $matchId ...
}
```

#### Parse Custom Log Lines

```perl
# In the main log parsing section, add handlers for KTP events

# Pattern to match KTP_MATCH_START
if ($message =~ /^KTP_MATCH_START\s+(.*)$/) {
    my $propsStr = $1;
    my %props = &parseProperties($propsStr);
    &doEvent_KTPMatchStart($s_addr, \%props);
    return;
}

# Pattern to match KTP_MATCH_END
if ($message =~ /^KTP_MATCH_END\s+(.*)$/) {
    my $propsStr = $1;
    my %props = &parseProperties($propsStr);
    &doEvent_KTPMatchEnd($s_addr, \%props);
    return;
}

# Helper to parse (key "value") properties
sub parseProperties {
    my ($str) = @_;
    my %props;
    while ($str =~ /\((\w+)\s+"([^"]*)"\)/g) {
        $props{$1} = $2;
    }
    return %props;
}
```

#### Tasks - Phase 4 ✅ COMPLETE
- [x] Create KTPHLStatsX project (fork files from HLStatsX:CE)
- [x] Add `%g_ktpMatchContext` global hash in hlstats.pl
- [x] Implement `doEvent_KTPMatchStart()` handler
- [x] Implement `doEvent_KTPMatchEnd()` handler
- [x] Add log line pattern matching for KTP_MATCH_START/END
- [x] Modify `buildEventInsertData()` to include match_id column
- [x] Modify `recordEvent()` to include match_id value
- [x] Test parsing of KTP log lines (code validated 2025-12-17, needs live test)

---

### Phase 5: HLStatsX:CE MySQL Schema Changes

**Project:** HLStatsX:CE
**File:** `sql/install.sql` or migration script

#### Add match_id to Event Tables

```sql
-- Add match_id column to hlstats_Events_Frags
ALTER TABLE hlstats_Events_Frags
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL AFTER map,
ADD INDEX idx_match_id (match_id);

-- Add match_id column to hlstats_Events_Teamkills
ALTER TABLE hlstats_Events_Teamkills
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL AFTER map,
ADD INDEX idx_match_id (match_id);

-- Add match_id column to hlstats_Events_Suicides
ALTER TABLE hlstats_Events_Suicides
ADD COLUMN match_id VARCHAR(64) DEFAULT NULL AFTER map,
ADD INDEX idx_match_id (match_id);

-- Add to other event tables as needed...
```

#### Create KTP Match Tables

```sql
-- Match metadata table
CREATE TABLE IF NOT EXISTS ktp_matches (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    server_id INT NOT NULL,
    map_name VARCHAR(32) NOT NULL,
    half TINYINT DEFAULT 1,
    start_time DATETIME NOT NULL,
    end_time DATETIME DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uk_match_id (match_id),
    KEY idx_server (server_id),
    KEY idx_start_time (start_time),
    KEY idx_map (map_name),

    FOREIGN KEY (server_id) REFERENCES hlstats_Servers(serverId)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Players participating in each match
CREATE TABLE IF NOT EXISTS ktp_match_players (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    steam_id VARCHAR(32) NOT NULL,
    player_name VARCHAR(64) NOT NULL,
    team TINYINT NOT NULL COMMENT '1=Allies, 2=Axis',
    joined_at DATETIME NOT NULL,

    PRIMARY KEY (id),
    KEY idx_match (match_id),
    KEY idx_player (player_id),
    KEY idx_steam (steam_id),

    FOREIGN KEY (match_id) REFERENCES ktp_matches(match_id)
        ON DELETE CASCADE,
    FOREIGN KEY (player_id) REFERENCES hlstats_Players(playerId)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Aggregated match statistics per player (computed from events)
CREATE TABLE IF NOT EXISTS ktp_match_stats (
    id INT AUTO_INCREMENT,
    match_id VARCHAR(64) NOT NULL,
    player_id INT NOT NULL,
    kills INT DEFAULT 0,
    deaths INT DEFAULT 0,
    headshots INT DEFAULT 0,
    team_kills INT DEFAULT 0,
    suicides INT DEFAULT 0,

    PRIMARY KEY (id),
    UNIQUE KEY uk_match_player (match_id, player_id),
    KEY idx_match (match_id),
    KEY idx_player (player_id),

    FOREIGN KEY (match_id) REFERENCES ktp_matches(match_id)
        ON DELETE CASCADE,
    FOREIGN KEY (player_id) REFERENCES hlstats_Players(playerId)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Useful Views

```sql
-- View: Match leaderboard
CREATE VIEW ktp_match_leaderboard AS
SELECT
    m.match_id,
    m.map_name,
    m.start_time,
    p.lastName AS player_name,
    mp.steam_id,
    mp.team,
    COALESCE(ms.kills, 0) AS kills,
    COALESCE(ms.deaths, 0) AS deaths,
    COALESCE(ms.headshots, 0) AS headshots,
    CASE WHEN ms.deaths > 0
         THEN ROUND(ms.kills / ms.deaths, 2)
         ELSE ms.kills END AS kd_ratio
FROM ktp_matches m
JOIN ktp_match_players mp ON m.match_id = mp.match_id
JOIN hlstats_Players p ON mp.player_id = p.playerId
LEFT JOIN ktp_match_stats ms ON m.match_id = ms.match_id AND mp.player_id = ms.player_id
ORDER BY m.start_time DESC, ms.kills DESC;
```

#### Tasks - Phase 5 ✅ COMPLETE
- [x] Create migration script (sql/ktp_schema.sql)
- [x] Add match_id column to hlstats_Events_Frags
- [x] Add match_id column to other event tables
- [x] Create ktp_matches table
- [x] Create ktp_match_players table
- [x] Create ktp_match_stats table
- [x] Create useful views (ktp_match_leaderboard, ktp_recent_matches)
- [x] Test schema with sample data (SQL validated 2025-12-17, run on VPS)

---

### Phase 6: Testing & Validation

#### Test Scenarios

1. **Warmup Stats Separation**
   - Join server, get kills during warmup
   - Start KTP match
   - Verify warmup kills have `match_id = NULL`
   - Verify warmup kills logged BEFORE match start

2. **Match Stats Tracking**
   - Complete a full KTP match
   - Verify all match kills have correct `match_id`
   - Verify ktp_matches row created with correct times

3. **Half Tracking**
   - Complete first half, map change
   - Start second half
   - Verify same `match_id` for both halves
   - Verify half number tracked correctly

4. **Match End**
   - End match or map changes
   - Verify stats flushed with matchid
   - Verify ktp_matches.end_time populated
   - Verify post-match kills have `match_id = NULL`

#### Query Validation

```sql
-- Count match vs non-match kills
SELECT
    CASE WHEN match_id IS NULL THEN 'Non-Match' ELSE 'Match' END AS type,
    COUNT(*) AS kill_count
FROM hlstats_Events_Frags
WHERE eventTime > DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY (match_id IS NULL);

-- Get specific match stats
SELECT
    killerId,
    COUNT(*) AS kills,
    SUM(headshot) AS headshots
FROM hlstats_Events_Frags
WHERE match_id = 'KTP-1734355200-dod_charlie'
GROUP BY killerId
ORDER BY kills DESC;
```

#### Tasks - Phase 6 (Requires Live VPS Testing)
- [x] Test warmup → match transition
- [ ] Test match → post-match transition
- [ ] Test half tracking across map change
- [ ] Verify query separation works
- [ ] Performance test with large dataset
- [ ] Document any edge cases found

**Note:** All code is compiled and staged. Phase 6 requires running on the VPS with:
1. Game server with KTPAMXX loaded
2. HLStatsX daemon running with modified scripts
3. MySQL database with ktp_schema.sql applied

---

## Files to Modify Summary

| Project | File | Phase | Changes | Status |
|---------|------|-------|---------|--------|
| KTPAMXX | `modules/dod/dodx/NRank.cpp` | 1 | Add native implementations | ✅ Done |
| KTPAMXX | `modules/dod/dodx/moduleconfig.cpp` | 1 | Register natives and forward | ✅ Done |
| KTPAMXX | `modules/dod/dodx/dodx.h` | 1 | Add extern declarations | ✅ Done |
| KTPAMXX | `plugins/include/dodx.inc` | 1 | Add native declarations | ✅ Done |
| KTPAMXX | `plugins/dod/stats_logging.sma` | 2 | Add flush forward handler, matchid in logs | ✅ Done |
| KTPMatchHandler | `KTPMatchHandler.sma` | 3 | Call natives, log markers | ✅ Done |
| KTPHLStatsX | `scripts/hlstats.pl` | 4 | Add match context tracking | ✅ Done |
| KTPHLStatsX | `scripts/HLstats_EventHandlers.plib` | 4 | Add KTP event handlers | ✅ Done |
| KTPHLStatsX | `sql/ktp_schema.sql` | 5 | New tables and columns | ✅ Done |

---

## v0.9.1 Release Summary

**Released:** 2025-12-20
**Status:** Compiled and staged to server

### Fixes Delivered

| Feature | Status | Notes |
|---------|--------|-------|
| Discord Embed Roster | ✅ Done | Side-by-side team display with inline fields |
| Score Persistence | ✅ Done | `msg_TeamScore` hook saves to localinfo on every game tick |
| Discord Newlines | ✅ Done | Proper JSON escaping via `escape_for_json()` |
| Periodic Score Save | ✅ Done | Backup task every 30s during 1st half |

### Technical Changes

- **`msg_TeamScore()` hook** now persists scores to localinfo immediately when game updates
- **`escape_for_json()`** helper function for proper JSON string escaping
- **Discord embed format** for roster with match ID in footer
- **Removed code block wrapper** from Discord messages so markdown renders

---

## v0.9.0 Release Summary

**Released:** 2025-12-18
**Status:** Compiled and staged to server

### Features Delivered

| Feature | Status | Notes |
|---------|--------|-------|
| KTP Season Control | ✅ Done | `/ktpseason` toggles competitive availability |
| Match Password Protection | ✅ Done | `/start <pw>` and `/ktp <pw>` require password |
| MATCH_TYPE_DRAFT | ✅ Done | Separate match type, always available |
| 4-Type Match System | ✅ Done | COMPETITIVE, SCRIM, 12MAN, DRAFT |

### Security Model

| Feature | Password | Season Required |
|---------|----------|-----------------|
| `/start`, `/ktp` | ✅ Required | ✅ Yes |
| `/draft` | ❌ None | ❌ No |
| `/12man` | ❌ None | ❌ No |
| `/scrim` | ❌ None | ❌ No |
| `/ktpseason` | ✅ Admin password | N/A |

---

## Priority 2: Potential Enhancements

| Feature | Description | Complexity |
|---------|-------------|------------|
| ~~Configurable reminder interval~~ | ✅ **DONE (v0.8.0)** - CVARs `ktp_unready_reminder_secs`, `ktp_unpause_reminder_secs` | ~~Low~~ |
| ~~Match result tracking~~ | ✅ **DONE (v0.8.0)** - TeamScore hook tracks scores, persisted via localinfo | ~~Low~~ |
| ~~Discord match end notification~~ | ✅ **DONE (v0.8.0)** - Final score sent to Discord with half breakdown | ~~Low~~ |
| ~~Team name support~~ | ✅ **DONE (v0.8.0)** - `/setteamallies`, `/setteamaxis`, `/teamnames` commands | ~~Medium~~ |
| ~~Unpause reminder notifications~~ | ✅ **DONE (v0.8.0)** - Periodic reminders when waiting for other team | ~~Low~~ |
| ~~Pause usage per match (not per half)~~ | ✅ **DONE (v0.7.1)** - Pause counts and tech budget now persist via localinfo | ~~Medium~~ |
| ~~Season control~~ | ✅ **DONE (v0.9.0)** - `/ktpseason` password-protected toggle | ~~Medium~~ |
| ~~Match password protection~~ | ✅ **DONE (v0.9.0)** - `/start <pw>` requires password | ~~Medium~~ |
| Match history command | `/matchhistory` to show recent matches | Medium |
| Admin override commands | Force-ready players, force-start match | Medium |

---

## Technical Reference

### Variables Added in v0.6.0

```pawn
// Match ID system
new g_matchId[64];              // Format: KTP-{timestamp}-{mapname}
new g_matchStartTime = 0;       // Unix timestamp when match started
new g_taskUnreadyReminderId;    // Task for 30-sec unready reminders

// Helper functions
stock generate_match_id()       // Generates matchID at 1st half start
stock clear_match_id()          // Clears matchID after 2nd half ends
public unready_reminder_tick()  // Periodic unready player reminder
```

### Commands Added in v0.6.0

| Command | Aliases | Description |
|---------|---------|-------------|
| `/whoneedsready` | `.whoneedsready`, `/unready`, `.unready` | Shows unready players with Steam IDs |

---

## Resolved Questions

| Question | Resolution |
|----------|------------|
| Match ID format? | `KTP-{timestamp}-{mapname}` |
| Same ID for both halves? | Yes, same matchID persists |
| Pause during ready phase? | No - seamless flow |
| Stats association method? | DODX natives + HLStatsX modification |
| Match ID in weaponstats? | Yes, as `(matchid "xxx")` property |
| How to persist match context across halves? | **SOLVED (v0.7.1):** Use `localinfo` keys to store match_id, map, pause counts, and tech budget before map change. Restore in `plugin_cfg()` on 2nd half load. Keys: `_ktp_match_id`, `_ktp_half_pending`, `_ktp_pause_allies/axis`, `_ktp_tech_allies/axis` |

## Open Questions

| Question | Notes |
|----------|-------|
| Reset stats between halves? | Probably not - track full match stats |
| HLStatsX fork or patch? | TBD - depends on upstream activity |

## Known Bugs

| Bug | Description | Reported | Status |
|-----|-------------|----------|--------|
| ~~Pause HUD without pause state~~ | ~~`.tech` shows pause HUD but game doesn't actually enter pause state. Error: `Can't "pause", not connected`. Likely related to ReAPI not available in extension mode.~~ **RESOLVED:** ReAPI now available in extension mode after building with include. | 2025-12-18 | ✅ Fixed |
| ~~KTP_MATCH_END not logged on map change~~ | ~~Map changed but KTP_MATCH_END was not logged.~~ **RESOLVED:** (1) Map comparison uses `equali()` (case-insensitive) at line 3240. (2) Abandoned 1st-half matches now log `KTP_MATCH_END (reason "abandoned")` at lines 3251-3260. | 2025-12-18 | ✅ Fixed |

---

## Known Edge Cases (To Test on VPS)

| Edge Case | Expected Behavior | Status |
|-----------|-------------------|--------|
| Player disconnects mid-match | Stats flush on disconnect with matchid | ✅ Verified |
| Server crash during match | Match context lost, no KTP_MATCH_END logged | Untested |
| Map change without /end | Should flush stats and log KTP_MATCH_END | Untested |
| Multiple matches same map | Each gets unique matchid (timestamp differs) | Untested |
| HLStatsX daemon restart mid-match | Context hash cleared, subsequent events have no matchid | Untested |
| Very long match (>2 hours) | Timestamp-based matchid still unique | Untested |
| MySQL connection failure | Events logged to file but match_id may be lost | Untested |

---

*Last compiled: 2025-12-20 (v0.9.1)*
*Staged to: N:\Nein_\KTP DoD Server\dod\addons\ktpamx\plugins\*
