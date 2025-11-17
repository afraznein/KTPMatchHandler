# 🎮 KTP Match Handler v0.4.0
**Comprehensive competitive match management for Day of Defeat**

---

## 🌟 Platform Support

The plugin gracefully degrades across different platforms:

### ✅ **Base AMX ModX (HLDS)**
**Minimum requirement** - Core features work
- ✅ All pause commands with countdown
- ✅ Match workflow (pre-start, ready, live)
- ✅ Pause extensions via `/extend`
- ✅ Real-time pause tracking
- ✅ File logging (AMX + KTP logs)
- ✅ Discord webhooks (if cURL installed)
- ⚠️ Timer checks require player commands
- ⚠️ Announcements via `rcon_say` (orange text)
- ❌ HUD frozen during pause
- ❌ Chat frozen during pause

### ⬆️ **Standard ReHLDS**
**Recommended baseline** - Same as Base AMX
- Everything from Base AMX
- No additional features vs base AMX for this plugin
- Better compatibility and performance

### 🚀 **KTP-ReHLDS + ReAPI**
**Optimal experience** - Full feature set
- Everything from Base AMX/ReHLDS
- ✅ **Automatic timer checks** (no player interaction needed)
- ✅ **Real-time HUD updates** during pause
- ✅ **Chat works during pause**
- ✅ **Automatic warnings** at 30s/10s
- ✅ **Better announcements** (client_print works)

---

## ⏸️ Pause System (v0.4.0 Major Overhaul)

### **Unified Countdown System**
ALL pause entry points now use countdown:
- Chat: `/pause`
- Console: `pause`
- Server: `pause`
- RCON: `pause`

**Pre-pause countdown** (configurable):
```
"PlayerName initiated pause. Pausing in 5..."
"Pausing in 4..."
"Pausing in 3..."
"Pausing in 2..."
"Pausing in 1..."
"=== PAUSING NOW ===="
```

### **Pause Types**

**🎯 Tactical Pause**
- Limit: 1 per team per half
- Duration: 5 minutes (default)
- Extensions: Up to 2× 2-minute extensions
- Total max: 9 minutes

**🔧 Technical Pause**
- Budget: 5 minutes per team (cumulative)
- No extension limit
- Command: `/tech`
- Tracks usage across entire match

**📴 Disconnect Auto-Pause**
- Triggers: When player disconnects during live match
- Countdown: 10 seconds (can be cancelled)
- Type: Technical (uses team budget)
- Cancel: `/cancelpause` (team only)

### **During Pause** (on KTP-ReHLDS)

Real-time HUD display:
```
  == GAME PAUSED ==

  Type: TACTICAL
  By: PlayerName

  Elapsed: 2:34  |  Remaining: 2:26
  Extensions: 1/2

  Pauses Left: A:1 X:0

  /resume  |  /confirmunpause  |  /extend
```

**Timer Warnings:**
- ⚠️ 30 seconds remaining
- ⚠️ 10 seconds remaining
- 🔴 Auto-unpause when expired

### **Pause Commands**

| Command | Description | Access |
|---------|-------------|--------|
| `/pause` | Tactical pause (countdown) | Anyone |
| `/tech` | Technical pause | Anyone |
| `/resume` | Request unpause | Owner team |
| `/confirmunpause` | Confirm unpause | Other team |
| `/extend` | +2 minutes (max 2×) | Anyone |
| `/cancelpause` | Cancel disconnect pause | Affected team |

---

## 🎯 Match Workflow

### **1️⃣ Pre-Start**
```
/start → Both teams /confirm → Pending
```
- Captains initiate with `/start`
- Each team confirms with `/confirm`
- Can `/cancel` or `/notconfirm` to abort

### **2️⃣ Pending (Ready-Up)**
```
Pending → Players /ready → Live countdown → LIVE!
```
- Players mark ready: `/ready` or `/ktp`
- View status: `/status`
- Unready: `/notready`
- Requires N players per team (default: 6)

### **3️⃣ Live Match**
```
Match active → Pauses available → Full logging
```
- Tactical pauses limited (1 per team)
- Technical pauses tracked
- Disconnect protection active
- All events logged

---

## 📊 Logging & Notifications

### **AMX Log**
Standard Half-Life logs:
```
L 01/15/2025 - 22:30:45: KTP: Game PAUSED by PlayerName
L 01/15/2025 - 22:35:15: KTP: Pause warning - 30 seconds remaining
```

### **KTP Match Log**
Structured event logging:
```
event=PAUSE_EXECUTED initiator='PlayerName' duration=300
event=PAUSE_EXTENDED player='PlayerName' extension=1/2
event=MATCH_START allies_ready=6 axis_ready=6
```

### **Discord Webhooks** (Optional, requires cURL)
Rich notifications with emojis:
- ⏸️ Pause events
- ▶️ Unpause countdown
- ⚔️ Match start
- ✅ Match live
- ⚠️ Timer warnings
- 📴 Disconnect events

---

## ⚙️ Key CVARs

### **Pause System**
```
ktp_pause_duration "300"           // 5 minutes base
ktp_pause_extension "120"          // 2 minutes per extend
ktp_pause_max_extensions "2"       // Max 2 extensions
ktp_prepause_seconds "5"           // Live match countdown
ktp_prematch_pause_seconds "5"     // Pre-match countdown
```

### **Match System**
```
ktp_ready_required "6"             // Players per team
ktp_tech_budget_seconds "300"      // 5 min tech budget
ktp_unpause_autorequest_secs "300" // Auto-request timeout
```

---

## 🎮 Command Quick Reference

### **Match Control**
- `/start` - Begin pre-start
- `/confirm` - Confirm team ready
- `/ready` or `/ktp` - Mark ready
- `/notready` - Unmark ready
- `/status` - View match status
- `/cancel` - Cancel match

### **Pause Control**
- `/pause` - Tactical pause
- `/tech` - Technical pause
- `/resume` - Request unpause
- `/confirmunpause` - Confirm unpause (aliases: `/cresume`, `/cunpause`)
- `/extend` - Extend pause +2min
- `/cancelpause` - Cancel disconnect pause

### **Admin/Debug**
- `/reloadmaps` - Reload map configs
- `/ktpconfig` - View current config
- `/ktpdebug` - Debug info

---

## 🗺️ Map Configuration

**INI Format** (`ktp_maps.ini`):
```ini
[dod_avalanche]
config = ktp_avalanche.cfg
name = Avalanche
type = competitive

[dod_flash]
config = ktp_flash.cfg
name = Flash
type = competitive
```

- Auto-executes map config on load
- Reload without restart: `/reloadmaps`

---

## 📦 Installation

### **Minimum (Base AMX)**
1. Install AMX ModX 1.9+
2. Copy `KTPMatchHandler.amxx` to `plugins/`
3. Add to `plugins.ini`
4. Configure CVARs

### **Optimal (KTP-ReHLDS)**
1. Install AMX ModX 1.9+
2. Install ReAPI module
3. Copy `KTPMatchHandler.amxx` to `plugins/`
4. Deploy KTP-ReHLDS binaries
5. Configure CVARs
6. Setup `ktp_maps.ini`
7. (Optional) Configure Discord webhook

---

## 🎯 Key Features

✅ **Unified Pause System** - ALL entry points use countdown
✅ **Platform Degradation** - Works on base AMX → KTP-ReHLDS
✅ **Real-Time Tracking** - `get_systime()` based timers
✅ **Pause Extensions** - Players request more time
✅ **Two-Team Unpause** - Both teams must agree
✅ **Disconnect Protection** - 10-sec cancellable auto-pause
✅ **Budget Tracking** - Tech pause limits enforced
✅ **Comprehensive Logging** - 3 logging systems
✅ **Discord Integration** - Rich webhook notifications
✅ **ReAPI Integration** - Real-time HUD updates (KTP-ReHLDS)

---

## 📋 What's New in v0.4.0

### **Major Changes**
- 🔄 **Unified pause countdown** - ALL pause commands use countdown
- 🎚️ **Platform degradation** - Works on base AMX, better on KTP-ReHLDS
- 🗺️ **New map INI format** - Section-based configuration
- ⚡ **Simplified ready logic** - More efficient checks
- 📢 **Smart announcements** - `rcon_say` fallback on base platforms

### **New Features**
- `ktp_prematch_pause_seconds` CVAR for pre-match countdowns
- Server/RCON pause command interception
- Manual timer checks for base AMX (on player commands)
- Platform-aware announcement system

### **Bug Fixes**
- Fixed announcements during pause on base platforms
- Fixed all pause entry points (console, server, RCON)
- Fixed ready system redundant checks
- Real-time tracking on all platforms

---

## 👨‍💻 Credits

**Author:** Nein_
**Version:** 0.4.0
**License:** Open Source

**Built with:**
- [AMX Mod X](https://www.amxmodx.org/)
- [ReAPI](https://github.com/s1lentq/reapi)
- [ReHLDS](https://github.com/dreamstalker/rehlds)

---

**📥 Download:** [GitHub Repository](https://github.com/afraznein/KTPMatchHandler)
**🐛 Report Issues:** [GitHub Issues](https://github.com/afraznein/KTPMatchHandler/issues)
**📖 Full Documentation:** See `FEATURE_SUMMARY.md`
