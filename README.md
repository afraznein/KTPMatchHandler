# KTP Match Handler

**Version 0.4.0** - Comprehensive competitive match management system for Day of Defeat servers

A feature-rich AMX ModX plugin providing structured match workflows, advanced pause controls with real-time HUD updates, and extensive logging capabilities.

---

## 🎮 Key Features

- **Structured Match System**: Pre-start → Pending → Ready-up → LIVE workflow
- **Advanced Pause Controls**: Real-time HUD with countdown timers
- **Pause Extensions**: Players can extend pauses (2 min × 2 max = 9 min total)
- **Disconnect Protection**: Auto-pause with 10-second cancellable countdown
- **Two-Team Unpause**: Prevents one team from forcing resume
- **Budget Tracking**: Technical pause time limits per team (5 min default)
- **Tactical Limits**: 1 tactical pause per team per half
- **Real-Time HUD**: MM:SS timer updates during pause via ReAPI integration
- **Comprehensive Logging**: AMX log, KTP match log, and Discord webhooks
- **Map Configurations**: Auto-execute map-specific server settings

---

## 🚀 Quick Start

### Requirements

**Required:**
- AMX Mod X 1.9+
- [ReAPI Module](https://github.com/s1lentq/reapi)
- [KTP-ReHLDS](https://github.com/afraznein/KTP-ReHLDS) (custom build for chat during pause)

**Optional:**
- cURL extension (for Discord notifications)

### Installation

1. **Download** the latest release
2. **Compile** `KTPMatchHandler.sma` using AMX Mod X compiler
3. **Install** `KTPMatchHandler.amxx` to `addons/amxmodx/plugins/`
4. **Add to** `addons/amxmodx/configs/plugins.ini`:
   ```
   KTPMatchHandler.amxx
   ```
5. **Configure** maps in `addons/amxmodx/configs/ktp_maps.ini`
6. **(Optional)** Set up Discord webhook in `addons/amxmodx/configs/discord.ini`
7. **Deploy** KTP-ReHLDS server binaries
8. **Restart** server

### Basic Configuration

Add to your `amxx.cfg` or `server.cfg`:

```
// Pause System
ktp_pause_duration "300"              // 5-minute base pause
ktp_pause_extension "120"             // 2-minute extensions
ktp_pause_max_extensions "2"          // Max 2 extensions
ktp_prepause_seconds "3"              // 3-second warning before pause

// Match System
ktp_ready_required "6"                // Players needed to ready up
ktp_tech_budget_seconds "300"         // 5-minute tech pause budget per team

// File Paths
ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"
ktp_match_logfile "ktp_match.log"
```

---

## 📖 Usage

### Starting a Match

1. Admin or captain types `/start`
2. Each team types `/confirm` (one player per team)
3. Players type `/ready` (or `/ktp`) until required count is reached
4. Match automatically goes LIVE with 3-second countdown

### Pause Controls

```
/pause          Initiate tactical pause (3-sec countdown)
/tech           Initiate technical pause
/resume         Request unpause (owner team only)
/confirmunpause Confirm unpause (other team)
/extend         Extend pause by 2 minutes (max 2 times)
/cancelpause    Cancel disconnect auto-pause
```

### Match Commands

```
/ready          Mark yourself ready
/notready       Remove ready status
/status         View detailed match/ready status
/cancel         Cancel match/pre-start
/reloadmaps     Reload map configurations
```

---

## ⏸️ Pause System (v0.4.0 Major Overhaul)

### How Pauses Work

```
Player initiates pause
         ↓
  3-second countdown
         ↓
  Game PAUSES
         ↓
  Real-time HUD updates every frame
  ├─ Elapsed: 2:34
  ├─ Remaining: 2:26
  ├─ Extensions: 1/2
  └─ Commands shown
         ↓
  Warnings at 30s and 10s
         ↓
  Auto-unpause OR manual unpause
         ↓
  3-second countdown → LIVE!
```

### Pause Types

**Tactical Pause**
- Limit: 1 per team per half
- Duration: 5 minutes (default)
- Extensions: Up to 2 × 2 minutes
- Command: `/pause` or console `pause`

**Technical Pause**
- Budget: 5 minutes per team (cumulative)
- No extension limit
- Command: `/tech`

**Disconnect Auto-Pause**
- Triggers: When player disconnects during match
- Countdown: 10 seconds (cancellable)
- Type: Technical (uses team budget)
- Cancel: `/cancelpause` (affected team only)

### Real-Time HUD Display

During pause, players see:
```
  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  /resume  |  /confirmunpause  |  /extend
```

---

## 🔧 Advanced Configuration

### Map Configuration (`ktp_maps.ini`)

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

### Discord Webhook (`discord.ini`)

```ini
[discord]
webhook_url = https://discord.com/api/webhooks/YOUR_WEBHOOK_HERE
```

Notifications sent for:
- ⏸️ Pause events (initiated, extended, timeout)
- ✅ Match events (start, LIVE, ended)
- 🎮 Player ready status
- ⚠️ Warnings and alerts

### All CVARs

```
// Pause Timing
ktp_pause_countdown "5"              // Unpause countdown (seconds)
ktp_pause_duration "300"             // Base pause duration (5 min)
ktp_pause_extension "120"            // Extension time (2 min)
ktp_pause_max_extensions "2"         // Max extensions
ktp_prepause_seconds "3"             // Pre-pause countdown
ktp_pause_hud "1"                    // Enable pause HUD

// Match System
ktp_ready_required "6"               // Players needed ready
ktp_unpause_autorequest_secs "300"   // Auto-request timeout
ktp_tech_budget_seconds "300"        // Tech pause budget per team

// File Paths
ktp_match_logfile "ktp_match.log"
ktp_cfg_basepath "dod/"
ktp_maps_file "addons/amxmodx/configs/ktp_maps.ini"
ktp_discord_ini "addons/amxmodx/configs/discord.ini"

// Server Control
ktp_force_pausable "1"               // Force pausable enabled
```

---

## 📊 Logging

### AMX Log
Standard AMX ModX log entries:
- Location: `amxmodx/logs/L[date].log`
- All major events with timestamps

### KTP Match Log
Detailed structured log:
- Location: Configurable (default: `ktp_match.log`)
- Event-based with key=value pairs
- Pause durations, extensions, budgets
- Player actions with SteamID and IP

Example:
```
event=PAUSE_EXECUTED initiator='PlayerName' reason='tactical_pause' duration=300
event=PAUSE_EXTENDED player='PlayerName' extension=1/2 seconds=120
event=MATCH_START map=dod_avalanche allies_ready=6 axis_ready=6
```

### Discord Webhooks (Optional)
Rich notifications with emojis:
- Pause events (⏸️ initiated, ⏸️➕ extended, ⏱️ timeout)
- Match events (✅ LIVE, 🏁 ended)
- Status updates (⚠️ warnings)

---

## 🏗️ Technical Details

### Architecture

**Real-Time Timing System:**
- Uses `get_systime()` (Unix timestamp) instead of frozen game time
- Enables accurate timer during pause
- Auto-warnings at 30s and 10s
- Auto-unpause when duration expires

**ReAPI Integration:**
- `RH_SV_UpdatePausedHUD` hook (custom KTP-ReHLDS hook)
- Called every frame during pause
- Provides real-time HUD updates
- Falls back to task-based system if not available

**KTP-ReHLDS Modifications:**
- Forces message sending during pause (`SV_SendClientMessages`)
- Allows command processing during pause (`SV_ParseStringCommand`)
- Frametime manipulation for game DLL commands
- Build identification banner on startup

### Performance

**Optimizations (v0.4.0):**
- CVAR caching in frequently-called functions
- Static variables prevent duplicate warnings
- Reduced from ~180 CVAR lookups/sec to ~0 during pause
- Safe task removal prevents errors

---

## 📋 Command Reference

### Match Control
| Command | Description |
|---------|-------------|
| `/start`, `/startmatch` | Initiate pre-start sequence |
| `/confirm` | Confirm team ready for start |
| `/notconfirm` | Remove team confirmation |
| `/ready`, `/ktp` | Mark yourself ready |
| `/notready` | Mark yourself not ready |
| `/status` | View detailed match status |
| `/prestatus` | View pre-start confirmation status |
| `/cancel` | Cancel match/pre-start |

### Pause Control
| Command | Description |
|---------|-------------|
| `/pause` | Initiate tactical pause |
| `pause` (console) | Same as /pause (intercepted) |
| `/tech` | Initiate technical pause |
| `/resume` | Request unpause (owner team) |
| `/confirmunpause` | Confirm unpause (other team) |
| `/cresume`, `/cunpause` | Aliases for confirmunpause |
| `/extend` | Extend pause by 2 minutes |
| `/cancelpause` | Cancel disconnect auto-pause |

### Admin/Config
| Command | Description |
|---------|-------------|
| `/reloadmaps` | Reload map configuration |
| `/ktpconfig` | View current CVARs |
| `/ktpdebug` | Toggle debug mode |

---

## 📝 Changelog

### v0.4.0 (2025-01-15) - Major Pause System Overhaul
**Added:**
- ✅ ReAPI integration for real-time HUD updates during pause
- ✅ Timed pauses with 5-minute default and MM:SS countdown
- ✅ Pre-pause countdown (3-second warning)
- ✅ Pause extensions via `/extend` (2 min × 2 max)
- ✅ Auto-unpause when timer expires
- ✅ Disconnect auto-pause with 10-second cancellable countdown
- ✅ Comprehensive logging to AMX log, match log, and Discord
- ✅ Unified pause system (all commands go through same flow)

**Fixed:**
- 🐛 HUD updates during pause using real-world time
- 🐛 Chat works during pause (with KTP-ReHLDS)
- 🐛 /ready system undefined variable bug
- 🐛 Multiple unsafe remove_task() calls

**Enhanced:**
- 📈 /status command shows player names and detailed info
- 📈 Performance: CVAR caching reduces lookups by ~180/sec
- 📈 Better Discord notifications with rich formatting

**Removed:**
- ❌ Game-time based pause_timer_tick (obsolete)

### v0.3.3 - Previous Stable Release
- Two-team unpause confirmation
- Per-team tactical pause limits
- Technical pause budget system
- Disconnect detection
- Pre-start confirmation
- Discord webhook integration

[Full changelog](CHANGELOG.md)

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

**Areas for contribution:**
- Additional pause features
- Enhanced statistics tracking
- Improved Discord embed formatting
- Bug fixes and optimizations
- Documentation improvements

---

## 📄 License

[Add your license here]

---

## 🔗 Links

- **GitHub Issues**: [Report bugs](https://github.com/afraznein/KTPMatchHandler/issues)
- **KTP-ReHLDS**: [Custom ReHLDS fork](https://github.com/afraznein/KTP-ReHLDS)
- **ReAPI**: [ReGameDLL API](https://github.com/s1lentq/reapi)
- **ReHLDS**: [Original ReHLDS](https://github.com/dreamstalker/rehlds)
- **AMX Mod X**: [Official website](https://www.amxmodx.org/)

---

## 👤 Author

**Nein_**

For support and questions, please open an issue on GitHub.

---

## 🙏 Acknowledgments

- ReAPI developers for the hook chain system
- s1lentq for ReHLDS
- AMX Mod X team for the scripting platform
- KTP community for testing and feedback

---

**KTP Match Handler v0.4.0** - Making competitive Day of Defeat matches better, one pause at a time. ⏸️
