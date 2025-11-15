# KTP Match Handler v0.4.0 - Complete Feature Summary

## Overview

The KTP Match Handler is a comprehensive competitive match management system for Day of Defeat servers. It provides structured match workflows, advanced pause controls with real-time HUD updates, and extensive logging capabilities.

---

## Core Systems

### 1. Match Lifecycle Management

#### **Pre-Start Phase**
- **Initiation**: `/start` or `/startmatch` - Begins the pre-start sequence
- **Team Confirmation**: Requires one `/confirm` from each team (Allies & Axis)
- **Status Checking**: `/prestatus` - View which teams have confirmed
- **Cancellation**: `/cancel` - Abort pre-start and return to normal play
- **Not Confirm**: `/notconfirm` - Remove your team's confirmation

**Flow:**
```
Normal Play → /start → Pre-Start Pending → Both teams /confirm → Pending Match
```

#### **Pending Match Phase (Ready-Up)**
- **Ready System**: `/ready` or `/ktp` - Mark yourself as ready
- **Unready**: `/notready` - Mark yourself as not ready
- **Status**: `/status` - Detailed view of ready status
  - Shows ready count per team
  - Lists ready players by name
  - Lists not-ready players by name
- **Requirement**: Configurable number of players must be ready (`ktp_ready_required`, default: 6)
- **Auto-Start**: Match goes LIVE when both teams meet ready requirements

**Flow:**
```
Pending → Players /ready → Requirements met → 3-second countdown → LIVE!
```

#### **Live Match Phase**
- Game is active with full competitive rules
- Pause systems become available
- Tactical pause limits enforced (1 per team per half)
- Technical pause budget tracked
- Match statistics logged

---

### 2. Comprehensive Pause System (v0.4.0 Major Overhaul)

#### **Pause Types**

**A. Tactical Pause**
- Initiated via: `/pause`, `pause` (console), or RCON `pause`
- Limit: 1 per team per half
- Duration: 5 minutes (default, configurable)
- Extensions: Up to 2 extensions of 2 minutes each (9 minutes total max)
- Owner: Team that initiated the pause

**B. Technical Pause**
- Initiated via: `/tech`
- Budget: 5 minutes per team (default, configurable via `ktp_tech_budget_seconds`)
- No extension limit
- Owner: Team that initiated the pause
- Tracks cumulative usage across match

**C. Disconnect Auto-Pause**
- Automatic: Triggers when player disconnects during live match
- Countdown: 10 seconds before pause activates
- Type: Technical pause (deducts from team budget)
- Cancellable: Affected team can use `/cancelpause` to abort
- Shows team name and cancel instructions during countdown

#### **Pause Flow (Unified System)**

```
ANY pause initiated (console/RCON/chat)
         ↓
  Pre-pause countdown (3 seconds)
         ├─→ "Pausing in 3..."
         ├─→ "Pausing in 2..."
         └─→ "Pausing in 1..."
         ↓
  Game PAUSES (server executes pause command)
         ↓
  HUD updates in real-time (every frame via ReAPI hook)
         ├─→ Elapsed time (MM:SS)
         ├─→ Remaining time (MM:SS)
         ├─→ Extensions used (X/2)
         ├─→ Pause type (TACTICAL/TECHNICAL)
         └─→ Available commands
         ↓
  Timer warnings
         ├─→ 30 seconds remaining warning
         └─→ 10 seconds remaining warning
         ↓
  Auto-unpause OR manual unpause
         ↓
  Unpause countdown (3 seconds)
         ├─→ "Unpausing in 3..."
         ├─→ "Unpausing in 2..."
         └─→ "Unpausing in 1... LIVE!"
         ↓
  Game resumes
```

#### **Pause Commands**

| Command | Description | Who Can Use |
|---------|-------------|-------------|
| `/pause` | Initiate tactical pause (3-sec countdown) | Any player during live match |
| `pause` (console) | Same as /pause (intercepted) | Any player |
| RCON `pause` | Server-initiated pause | Server admins |
| `/tech` | Initiate technical pause | Any player during live match |
| `/resume` | Request unpause | Pause owner team |
| `/confirmunpause` | Confirm unpause request | Non-owner team |
| `/extend` | Extend pause by 2 minutes | Any player (max 2 uses) |
| `/cancelpause` | Cancel disconnect auto-pause | Affected team only |

**Aliases:**
- `/cresume`, `/cunpause` → `/confirmunpause`

#### **Pause HUD Display**

During pause, players see real-time HUD:
```
  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  /resume  |  /confirmunpause  |  /extend
```

**HUD Updates:**
- **With KTP-ReHLDS + ReAPI**: Real-time updates every frame during pause
- **With KTP-ReHLDS only**: Updates every 0.5 seconds using fallback task system
- **Without KTP-ReHLDS**: No updates during pause (standard behavior)

---

### 3. Unpause System (Two-Team Confirmation)

#### **Unpause Requirements**
1. Pause owner team requests unpause via `/resume`
2. Other team confirms via `/confirmunpause`
3. 3-second countdown begins
4. Game goes LIVE

#### **Auto-Request Feature**
- If pause duration expires, unpause is auto-requested
- Other team still must confirm
- Default timeout: 300 seconds (5 minutes)
- Configurable via `ktp_unpause_autorequest_secs`

#### **Unpause Flow**
```
Owner team: /resume
    ↓
"Team X requested unpause. Team Y must /confirmunpause"
    ↓
Other team: /confirmunpause
    ↓
3-second countdown
    ↓
"Unpausing in 3... 2... 1... LIVE!"
    ↓
Match resumes
```

---

### 4. Real-Time Timing System (v0.4.0)

#### **Technical Implementation**
- Uses `get_systime()` (Unix timestamp) instead of game time
- Game time (`g_psv.time`) is frozen during pause
- Real-world time continues, enabling:
  - Accurate elapsed/remaining time display
  - Timer warnings during pause
  - Auto-unpause when duration expires

#### **Pause Duration System**
- **Base Duration**: 5 minutes (300 seconds, configurable)
- **Extensions**: 2 minutes each (120 seconds, configurable)
- **Maximum Extensions**: 2 (configurable)
- **Total Possible**: 9 minutes (5 + 2 + 2)

#### **Warnings**
- 30 seconds remaining: Chat warning + Discord notification
- 10 seconds remaining: Chat warning
- 0 seconds remaining: Auto-unpause countdown begins

---

### 5. Disconnect Detection & Auto-Pause

#### **Trigger Conditions**
- Player disconnects during live match
- Player is on a playing team (not spectator)
- Match is active (not pending or pre-start)

#### **Countdown Sequence (10 seconds)**
```
Player disconnects
    ↓
"[KTP] PlayerName (ALLIES) disconnected."
"[KTP] Auto tech-pause in 10 seconds..."
"[KTP] ALLIES can type /cancelpause to cancel"
    ↓
Every second: countdown message
    ↓
If not cancelled → Technical pause activates
If cancelled → Normal play continues
```

#### **Cancellation**
- Only the affected team can cancel
- Use `/cancelpause` during the 10-second countdown
- Prevents unnecessary pauses for intentional subs

---

### 6. Logging & Notifications

#### **A. AMX Log (via `log_amx()`)**
Standard AMX ModX log entries for all major events:
- Pre-pause countdown started
- Game paused (with initiator and reason)
- Pause warnings (30s, 10s)
- Pause timeout
- Pause extended
- Unpause countdown started
- Game LIVE
- Match start/end
- Player ready/not ready status

**Location**: `amxmodx/logs/L[date].log`

#### **B. KTP Match Log (via `log_ktp()`)**
Detailed match-specific log with structured data:
- Event-based logging with key=value pairs
- Tracks pause durations, extensions, budgets
- Player actions with SteamID and IP
- Team statistics and scores
- Map information

**Location**: Configurable via `ktp_match_logfile` (default: `ktp_match.log`)

**Example Entries:**
```
event=PREPAUSE_START initiator='PlayerName' reason='client command' countdown=3
event=PAUSE_EXECUTED initiator='PlayerName' reason='tactical_pause' duration=300
event=PAUSE_EXTENDED player='PlayerName' extension=1/2 seconds=120
event=PAUSE_TIMEOUT elapsed=305 duration=300
event=MATCH_START map=dod_avalanche allies_ready=6 axis_ready=6
```

#### **C. Discord Webhook Integration (Optional, requires cURL)**

Rich notifications sent to Discord webhook:

**Pause Events:**
- ⏸️ Pause initiated with countdown
- ⏸️ Game PAUSED with duration and extension info
- ⚠️ Pause ending in 30 seconds
- ⏱️ Pause timeout - Auto-unpausing
- ⏸️➕ Pause extended by player
- ▶️ Unpause countdown
- ✅ Match LIVE (with total pause duration)
- ❌ Auto-pause cancelled

**Match Events:**
- 🎮 Match starting (with ready counts)
- ✅ Match LIVE
- 🏁 Match ended (with final scores)
- 📋 Pre-start initiated
- ⚡ Player ready status changes

**Configuration:**
- Webhook URL stored in `addons/amxmodx/configs/discord.ini`
- Format: `webhook_url = https://discord.com/api/webhooks/...`
- Gracefully degrades if cURL not available

---

### 7. Map Configuration System

#### **Map INI File**
- Location: `addons/amxmodx/configs/ktp_maps.ini` (configurable)
- Format: Standard INI file with map-specific settings

**Example:**
```ini
[dod_avalanche]
config = dod_avalanche.cfg
name = Avalanche
type = competitive

[dod_flash]
config = dod_flash.cfg
name = Flash
type = competitive
```

#### **Commands**
- `/reloadmaps` - Reload map configuration from disk
- Useful for updating configs without server restart

#### **Auto-Execution**
- Executes map-specific config when map loads
- Config path: `ktp_cfg_basepath` + map config filename
- Example: `dod/dod_avalanche.cfg`

---

### 8. Admin & Debug Commands

| Command | Description | Access Level |
|---------|-------------|--------------|
| `/ktpconfig` | View current KTP configuration and CVARs | All players |
| `/ktpdebug` | Toggle debug mode and view internal state | All players |
| `/reloadmaps` | Reload map configuration file | All players |
| `/status` | View detailed match/ready status | All players |
| `/prestatus` | View pre-start confirmation status | All players |

---

### 9. CVARs (Configuration Variables)

#### **Pause System**
```
ktp_pause_countdown "5"              // Unpause countdown duration (seconds)
ktp_pause_duration "300"             // Base pause duration (5 minutes)
ktp_pause_extension "120"            // Extension time per /extend (2 minutes)
ktp_pause_max_extensions "2"         // Maximum number of extensions allowed
ktp_prepause_seconds "3"             // Pre-pause countdown duration
ktp_pause_hud "1"                    // Enable/disable pause HUD display
```

#### **Match System**
```
ktp_ready_required "6"               // Number of ready players needed per team
ktp_unpause_autorequest_secs "300"   // Auto-request unpause timeout
ktp_tech_budget_seconds "300"        // Technical pause budget per team (5 min)
```

#### **File Paths**
```
ktp_match_logfile "ktp_match.log"    // Match log file path
ktp_cfg_basepath "dod/"              // Config file base directory
ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"  // Map config file
ktp_discord_ini "addons/amxmodx/configs/discord.ini" // Discord webhook config
```

#### **Server Control**
```
ktp_force_pausable "1"               // Force 'pausable' cvar to 1 when needed
```

---

## Technical Requirements

### **Required**
- **AMX Mod X**: Version 1.9 or higher
- **ReAPI Module**: For real-time pause HUD updates
- **KTP-ReHLDS**: Custom ReHLDS build with selective pause modifications
  - Enables chat during pause
  - Enables HUD message sending during pause
  - Provides `RH_SV_UpdatePausedHUD` hook

### **Optional**
- **cURL Extension**: For Discord webhook notifications
- Falls back gracefully if not available

### **Server Setup**
1. Install AMX Mod X 1.9+
2. Install ReAPI module
3. Compile and install KTPMatchHandler.amxx
4. Deploy KTP-ReHLDS binaries
5. Configure CVARs in `amxx.cfg` or server.cfg
6. Set up `ktp_maps.ini` with your map rotation
7. (Optional) Configure Discord webhook in `discord.ini`

---

## Command Reference (Quick List)

### **Match Control**
- `/start`, `/startmatch` - Initiate pre-start
- `/confirm` - Confirm team ready for start
- `/notconfirm` - Remove team confirmation
- `/ready`, `/ktp` - Mark yourself ready
- `/notready` - Mark yourself not ready
- `/cancel` - Cancel match/pre-start
- `/status` - View match status
- `/prestatus` - View pre-start status

### **Pause Control**
- `/pause`, `pause` - Initiate pause (3-sec countdown)
- `/tech` - Technical pause
- `/resume` - Request unpause (owner team)
- `/confirmunpause`, `/cresume`, `/cunpause` - Confirm unpause
- `/extend` - Extend pause by 2 minutes
- `/cancelpause` - Cancel disconnect auto-pause

### **Configuration**
- `/reloadmaps` - Reload map configs
- `/ktpconfig` - View current config
- `/ktpdebug` - Debug mode toggle

---

## Key Features Summary

✅ **Structured Match Workflow** - Pre-start → Pending → Ready → LIVE
✅ **Real-Time Pause System** - MM:SS timer, auto-warnings, auto-unpause
✅ **Pause Extensions** - Players can request more time (2 min × 2 max)
✅ **Two-Team Unpause** - Prevents one team from forcing resume
✅ **Disconnect Protection** - Auto-pause with 10-sec cancellable countdown
✅ **Budget Tracking** - Technical pause time limits per team
✅ **Tactical Limits** - 1 tactical pause per team per half
✅ **Comprehensive Logging** - AMX log, KTP log, Discord webhooks
✅ **Map Configs** - Auto-execute map-specific settings
✅ **Ready System** - Flexible ready-up with detailed status
✅ **ReAPI Integration** - Real-time HUD updates during pause
✅ **KTP-ReHLDS Support** - Chat and HUD work during pause

---

## Version History

**v0.4.0 (2025-01-15)** - Major Pause System Overhaul
- ReAPI integration for real-time HUD updates
- Timed pauses with visible countdown
- Pause extension system
- Pre-pause countdown
- Disconnect auto-pause with cancellation
- Comprehensive logging enhancements
- Bug fixes and optimizations

**v0.3.3** - Previous Stable Release
- Two-team unpause confirmation
- Per-team tactical pause limits
- Technical pause budget system
- Disconnect detection
- Discord integration
- Map configuration system

---

## Credits

**Author**: Nein_
**Engine**: AMX ModX 1.9+ with ReAPI
**Server**: KTP-ReHLDS (Modified ReHLDS for selective pause)

**Dependencies:**
- [ReAPI](https://github.com/s1lentq/reapi)
- [ReHLDS](https://github.com/dreamstalker/rehlds)
- [AMX Mod X](https://www.amxmodx.org/)

---

**End of Feature Summary**
**KTP Match Handler v0.4.0**
