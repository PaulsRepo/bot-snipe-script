# DuckHunt IRC Bot

An intelligent IRC bot for playing DuckHunt automatically on IRC networks (tested on Rizon).

## Features

✅ **Smart Duck Detection** - Recognizes normal, golden, and fast ducks  
✅ **HP Tracking** - Tracks duck health to avoid wasted shots  
✅ **Prevents Over-shooting** - Stops shooting when duck is killed  
✅ **Golden Duck Priority** - Rapid-fire mode for golden ducks  
✅ **Auto-Reload** - Automatically reloads when out of ammo  
✅ **Rate Limiting** - Prevents getting throttled by the server  
✅ **Auto-Reconnect** - Reconnects automatically if disconnected  
✅ **Detailed Logging** - Logs all actions and results  
✅ **Configuration File** - Easy customization via config file  

## Files

- `duckhunt_bot_v2.py` - Main bot (recommended, has all features)
- `duckhunt_bot.py` - Basic version (simpler, fewer features)
- `bot_config.ini` - Configuration file
- `README.md` - This file

## Quick Start

### 1. Edit Configuration

Edit `bot_config.ini` and update your settings:

```ini
[IRC]
server = irc.rizon.net
port = 6667
channel = #url
nickname = YOUR_NICKNAME_HERE
# password = YOUR_PASSWORD_HERE  # Uncomment if you have NickServ password
```

### 2. Run the Bot

**Option A: Full-featured version (recommended)**
```bash
python3 duckhunt_bot_v2.py
```

**Option B: Basic version**
```bash
python3 duckhunt_bot.py
```

### 3. Stop the Bot

Press `Ctrl+C` to stop the bot gracefully.

## Configuration Options

### Bot Behavior

```ini
[Bot_Behavior]
# Minimum delay between shots (seconds)
min_bang_delay = 0.8

# Delay after duck spawn before first shot (seconds)
spawn_reaction_delay = 0.3

# Delay between consecutive shots on golden ducks (seconds)
golden_duck_shot_delay = 0.85

# Enable automatic reloading when out of ammo
auto_reload = true
```

### Advanced Settings

```ini
[Advanced]
# Enable verbose logging
verbose = true

# Reconnect on disconnect
auto_reconnect = true

# Reconnect delay (seconds)
reconnect_delay = 5
```

## How It Works

### Duck Detection
The bot monitors IRC messages from DuckHunt/Quackbot and detects:
- Duck spawns (various ASCII art patterns)
- Duck types (normal, golden, fast)
- Duck escapes

### Smart Shooting
1. **Normal Ducks**: Single shot
2. **Golden Ducks**: Rapid-fire until killed (tracks HP)
3. **Fast Ducks**: Quick single shot

### HP Tracking
The bot parses messages like:
- `[3 HP remaining]` - Continues shooting
- `You killed the GOLDEN DUCK!` - Stops shooting
- Duck escapes - Stops shooting

### Problem Prevention

**Problem 1: Shooting after duck is dead**  
✅ **Solution**: Bot stops shooting immediately when "killed" message is received

**Problem 2: Golden ducks escaping**  
✅ **Solution**: Rapid-fire mode engages instantly on golden duck spawn

**Problem 3: Manual !rearm needed**  
✅ **Solution**: Bot tracks ammo and reloads automatically

**Problem 4: Gun confiscation from over-shooting**  
✅ **Solution**: HP tracking prevents shooting at non-existent ducks

## Logs

The bot creates `duckhunt_bot.log` with detailed information:

```
[2026-02-15 12:00:00] [INFO] Connected and joined #url
[2026-02-15 12:01:00] [DUCK] 🦆 DUCK SPAWNED: GOLDEN (HP: 3)
[2026-02-15 12:01:01] [SHOOT] 🎯 HIT! Duck HP: 2, Ammo: 5
[2026-02-15 12:01:02] [SHOOT] 🎯 HIT! Duck HP: 1, Ammo: 4
[2026-02-15 12:01:03] [SUCCESS] ✅ DUCK KILLED!
```

## Troubleshooting

### Bot won't connect
- Check server/port in config
- Verify your internet connection
- Make sure the channel exists

### Bot doesn't shoot
- Check if you have ammo (`!duckstats` in IRC)
- Verify gun isn't confiscated
- Check the logs for errors

### Bot shoots too slowly
- Decrease `min_bang_delay` in config (minimum 0.5)
- Decrease `spawn_reaction_delay` (minimum 0.2)

### Golden ducks still escape
- Decrease `golden_duck_shot_delay` to 0.7-0.8
- Check if you have enough ammo

## Advanced Usage

### Running in Background (Linux)

```bash
# Using screen
screen -dmS duckhunt python3 duckhunt_bot_v2.py
screen -r duckhunt  # To view

# Using nohup
nohup python3 duckhunt_bot_v2.py > output.log 2>&1 &
```

### Running on Windows

```cmd
start python duckhunt_bot_v2.py
```

## Performance Tips

1. **Lower ping to server** = faster reactions
2. **Stable connection** = fewer disconnects
3. **Adjust delays** based on your connection speed
4. **Monitor logs** to fine-tune timing

## Safety Features

- Rate limiting prevents server throttling
- Thread locks prevent race conditions
- Auto-reconnect handles network issues
- Graceful shutdown on Ctrl+C

## Requirements

- Python 3.6+
- No external dependencies (uses standard library)

## Version History

### v2.0 (Current)
- Added configuration file support
- HP tracking for golden ducks
- Auto-reconnect functionality
- Detailed logging with emojis
- Session statistics
- Thread-safe shooting

### v1.0
- Basic duck detection
- Simple shooting mechanism

## Support

If you encounter issues:

1. Check the `duckhunt_bot.log` file
2. Verify your configuration in `bot_config.ini`
3. Make sure you're authorized to use bots on the IRC network
4. Test with verbose logging enabled

## License

Free to use and modify. Have fun duck hunting! 🦆

## Tips for Success

1. Start with default settings
2. Monitor the first few ducks to see bot performance
3. Adjust delays based on observed reaction times
4. Keep an eye on your XP and accuracy stats
5. The bot works best with a stable internet connection

## Ethical Usage

- Only use on channels where bots are allowed
- Don't run multiple instances
- Respect channel rules and moderators
- This is for educational/personal use

---

Made with 🦆 for DuckHunt enthusiasts
