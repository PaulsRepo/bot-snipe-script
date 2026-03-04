#!/usr/bin/env python3
"""
Enhanced DuckHunt IRC Bot with Config Support
Features:
- Prevents shooting after duck is killed
- Fast reaction to golden ducks (rapid-fire mode)
- Automatic reloading and magazine management
- Smart HP tracking to avoid wasted shots
- Configuration file support
- Auto-reconnect on disconnect
- Detailed logging
"""

import socket
import re
import time
import threading
import configparser
import sys
from collections import deque
from datetime import datetime
from pathlib import Path

class DuckHuntBot:
    def __init__(self, config_file="bot_config.ini"):
        # Load configuration
        self.config = configparser.ConfigParser()
        if Path(config_file).exists():
            self.config.read(config_file)
        else:
            self._create_default_config(config_file)
            self.config.read(config_file)
            
        # IRC settings
        self.server = self.config.get('IRC', 'server', fallback='irc.rizon.net')
        self.port = self.config.getint('IRC', 'port', fallback=6667)
        self.channel = self.config.get('IRC', 'channel', fallback='#url')
        self.nickname = self.config.get('IRC', 'nickname', fallback='url')
        self.password = self.config.get('IRC', 'password', fallback=None)
        
        # Bot behavior settings
        self.min_bang_delay = self.config.getfloat('Bot_Behavior', 'min_bang_delay', fallback=0.8)
        self.spawn_reaction_delay = self.config.getfloat('Bot_Behavior', 'spawn_reaction_delay', fallback=0.3)
        self.golden_shot_delay = self.config.getfloat('Bot_Behavior', 'golden_duck_shot_delay', fallback=0.85)
        self.auto_reload = self.config.getboolean('Bot_Behavior', 'auto_reload', fallback=True)
        
        # Advanced settings
        self.verbose = self.config.getboolean('Advanced', 'verbose', fallback=True)
        self.auto_reconnect = self.config.getboolean('Advanced', 'auto_reconnect', fallback=True)
        self.reconnect_delay = self.config.getint('Advanced', 'reconnect_delay', fallback=5)
        
        # Connection
        self.irc = None
        self.connected = False
        self.running = True
        
        # Duck tracking
        self.active_duck = None
        self.duck_hp = 0
        self.duck_type = None
        self.duck_spawn_time = None
        
        # Ammo tracking
        self.current_ammo = 6
        self.magazines = 3
        self.gun_confiscated = False
        
        # Stats tracking
        self.shots_fired = 0
        self.ducks_killed = 0
        self.ducks_missed = 0
        
        # Rate limiting
        self.last_bang_time = 0
        
        # Message buffer
        self.recent_messages = deque(maxlen=20)
        
        # Shooting lock
        self.shooting_lock = threading.Lock()
        
    def _create_default_config(self, config_file):
        """Create default configuration file"""
        config = configparser.ConfigParser()
        
        config['IRC'] = {
            'server': 'irc.rizon.net',
            'port': '6667',
            'channel': '#url',
            'nickname': 'url',
            '# password': 'your_password_here'
        }
        
        config['Bot_Behavior'] = {
            'min_bang_delay': '0.8',
            'spawn_reaction_delay': '0.3',
            'golden_duck_shot_delay': '0.85',
            'auto_reload': 'true'
        }
        
        config['Advanced'] = {
            'verbose': 'true',
            'auto_reconnect': 'true',
            'reconnect_delay': '5'
        }
        
        with open(config_file, 'w') as f:
            config.write(f)
            
        print(f"Created default config file: {config_file}")
        
    def log(self, message, level="INFO"):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] [{level}] {message}"
        print(log_msg)
        
        # Optionally write to log file
        with open("duckhunt_bot.log", "a") as f:
            f.write(log_msg + "\n")
            
    def connect(self):
        """Connect to IRC server"""
        try:
            self.log(f"Connecting to {self.server}:{self.port}")
            self.irc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.irc.settimeout(300)  # 5 minute timeout
            self.irc.connect((self.server, self.port))
            
            if self.password:
                self._send_raw(f"PASS {self.password}")
            
            self._send_raw(f"NICK {self.nickname}")
            self._send_raw(f"USER {self.nickname} 0 * :{self.nickname}")
            
            time.sleep(2)
            self._send_raw(f"JOIN {self.channel}")
            self.connected = True
            self.log(f"Connected and joined {self.channel}")
            return True
            
        except Exception as e:
            self.log(f"Connection failed: {e}", "ERROR")
            return False
            
    def _send_raw(self, message):
        """Send raw IRC message"""
        try:
            self.irc.send(f"{message}\r\n".encode('utf-8'))
        except Exception as e:
            self.log(f"Failed to send: {e}", "ERROR")
            self.connected = False
            
    def _send_message(self, message):
        """Send message to channel"""
        self._send_raw(f"PRIVMSG {self.channel} :{message}")
        if self.verbose:
            self.log(f"SENT: {message}", "CMD")
            
    def _parse_message(self, line):
        """Parse IRC message"""
        match = re.match(r':([^!]+)![^\s]+ PRIVMSG ([^\s]+) :(.*)', line)
        if match:
            return match.group(1), match.group(3)
        return None, None
        
    def _detect_duck_spawn(self, sender, message):
        """Detect duck spawn"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return False
            
        # Duck spawn indicators
        spawn_indicators = [
            (r'\_[Oo]<', 'normal'),
            (r'QUACK', 'normal'),
            (r'\*flap flap\*', 'normal'),
            (r'quack', 'normal'),
        ]
        
        for pattern, default_type in spawn_indicators:
            if re.search(pattern, message):
                # Determine duck type from context
                msg_lower = message.lower()
                
                if 'golden' in msg_lower or 'glimmer' in msg_lower or '\\o<' in message:
                    self.duck_type = 'golden'
                    self.duck_hp = 3
                elif 'fast' in msg_lower or 'respawn' in msg_lower:
                    self.duck_type = 'fast'
                    self.duck_hp = 1
                else:
                    self.duck_type = default_type
                    self.duck_hp = 1
                    
                self.active_duck = True
                self.duck_spawn_time = time.time()
                self.log(f"🦆 DUCK SPAWNED: {self.duck_type.upper()} (HP: {self.duck_hp})", "DUCK")
                return True
                
        return False
        
    def _detect_duck_escape(self, sender, message):
        """Detect duck escape"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return False
            
        escape_words = ['escapes', 'vanishes', 'disappears', 'glides away', 'treasure in the wind']
        
        if any(word in message.lower() for word in escape_words):
            self.log(f"🦆 DUCK ESCAPED", "DUCK")
            self.active_duck = None
            self.duck_hp = 0
            return True
            
        return False
        
    def _parse_shot_result(self, sender, message):
        """Parse shot result"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return
            
        # Only process messages mentioning our nickname
        if self.nickname.lower() not in message.lower():
            return
            
        # Duck killed
        if 'killed' in message.lower() and 'duck' in message.lower():
            self.log(f"✅ DUCK KILLED!", "SUCCESS")
            self.active_duck = None
            self.duck_hp = 0
            self.current_ammo -= 1
            self.ducks_killed += 1
            return
            
        # Duck shot (HP remaining)
        hp_match = re.search(r'\[(\d+) HP remaining\]', message)
        if hp_match:
            self.duck_hp = int(hp_match.group(1))
            self.current_ammo -= 1
            self.log(f"🎯 HIT! Duck HP: {self.duck_hp}, Ammo: {self.current_ammo}", "SHOOT")
            
            # Continue shooting if duck is still alive
            if self.duck_hp > 0 and self.active_duck:
                time.sleep(self.golden_shot_delay)
                self._shoot_duck()
            return
            
        # Direct kill (no HP shown)
        if re.search(r'shot (the|a) (duck|FAST DUCK|GOLDEN DUCK)', message, re.IGNORECASE):
            self.log(f"✅ DUCK KILLED!", "SUCCESS")
            self.active_duck = None
            self.duck_hp = 0
            self.current_ammo -= 1
            self.ducks_killed += 1
            return
            
        # Missed
        if 'missed' in message.lower():
            self.log(f"❌ MISSED", "SHOOT")
            self.current_ammo -= 1
            self.ducks_missed += 1
            
            # Try again if duck is still alive
            if self.active_duck and self.duck_hp > 0:
                time.sleep(self.min_bang_delay + 0.1)
                self._shoot_duck()
            return
            
        # Out of ammo
        if 'out of ammo' in message.lower() or ('*click*' in message.lower() and 'reload' in message.lower()):
            self.log(f"🔫 OUT OF AMMO", "WARN")
            self.current_ammo = 0
            if self.auto_reload:
                self._reload()
            return
            
        # Gun confiscated
        if 'confiscated' in message.lower():
            self.log(f"⚠️ GUN CONFISCATED!", "WARN")
            self.gun_confiscated = True
            self.current_ammo = 0
            self.active_duck = None
            return
            
        # Gun jammed
        if 'jammed' in message.lower():
            self.log(f"🔧 GUN JAMMED", "WARN")
            self.current_ammo -= 1
            # Try shooting again
            if self.active_duck and self.duck_hp > 0:
                time.sleep(self.min_bang_delay)
                self._shoot_duck()
            return
            
    def _shoot_duck(self):
        """Shoot at duck with proper timing and checks"""
        with self.shooting_lock:
            # Safety checks
            if not self.active_duck:
                return False
                
            if self.gun_confiscated:
                self.log("Cannot shoot - gun confiscated", "WARN")
                return False
                
            if self.current_ammo <= 0:
                if self.auto_reload:
                    self._reload()
                return False
                
            # Rate limiting
            current_time = time.time()
            time_since_last = current_time - self.last_bang_time
            
            if time_since_last < self.min_bang_delay:
                sleep_time = self.min_bang_delay - time_since_last
                time.sleep(sleep_time)
                
            # Fire!
            self._send_message("!bang")
            self.last_bang_time = time.time()
            self.shots_fired += 1
            return True
            
    def _reload(self):
        """Reload gun"""
        if self.magazines > 0:
            self.log("🔄 RELOADING...", "ACTION")
            self._send_message("!reload")
            time.sleep(1.5)
            
    def _engage_golden_duck(self):
        """Rapid-fire mode for golden ducks"""
        self.log(f"⚡ ENGAGING GOLDEN DUCK - RAPID FIRE MODE", "ACTION")
        
        max_shots = 6  # Maximum shots to attempt
        shots_taken = 0
        
        while self.active_duck and self.duck_hp > 0 and shots_taken < max_shots:
            if self._shoot_duck():
                shots_taken += 1
                time.sleep(self.golden_shot_delay)
            else:
                break
                
    def run(self):
        """Main bot loop"""
        buffer = ""
        
        while self.running and self.connected:
            try:
                data = self.irc.recv(4096).decode('utf-8', errors='ignore')
                if not data:
                    self.log("Connection lost", "ERROR")
                    break
                    
                buffer += data
                
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    
                    if not line:
                        continue
                        
                    # Handle PING
                    if line.startswith('PING'):
                        pong = line.replace('PING', 'PONG')
                        self._send_raw(pong)
                        continue
                        
                    # Parse message
                    sender, message = self._parse_message(line)
                    if not sender or not message:
                        continue
                        
                    self.recent_messages.append((sender, message))
                    
                    # Check for duck spawn
                    if self._detect_duck_spawn(sender, message):
                        time.sleep(self.spawn_reaction_delay)
                        
                        if self.duck_type == 'golden':
                            # Use thread for golden duck to allow rapid fire
                            threading.Thread(target=self._engage_golden_duck, daemon=True).start()
                        else:
                            self._shoot_duck()
                            
                    # Check for escape
                    self._detect_duck_escape(sender, message)
                    
                    # Parse shot results
                    self._parse_shot_result(sender, message)
                    
            except socket.timeout:
                self.log("Socket timeout, sending ping", "WARN")
                self._send_raw("PING :keepalive")
                
            except Exception as e:
                self.log(f"Error in main loop: {e}", "ERROR")
                if not self.connected:
                    break
                time.sleep(1)
                
    def start(self):
        """Start the bot with auto-reconnect"""
        while self.running:
            if self.connect():
                try:
                    self.run()
                except KeyboardInterrupt:
                    self.log("Shutting down...", "INFO")
                    self.running = False
                    break
                except Exception as e:
                    self.log(f"Fatal error: {e}", "ERROR")
                    
            # Disconnect
            self.disconnect()
            
            # Auto-reconnect
            if self.running and self.auto_reconnect:
                self.log(f"Reconnecting in {self.reconnect_delay} seconds...", "INFO")
                time.sleep(self.reconnect_delay)
            else:
                break
                
    def disconnect(self):
        """Disconnect from IRC"""
        if self.connected:
            try:
                self._send_raw("QUIT :Bot shutting down")
                self.irc.close()
            except:
                pass
            self.connected = False
            self.log("Disconnected")
            
        # Print stats
        self.log(f"Session Stats - Shots: {self.shots_fired}, Kills: {self.ducks_killed}, Missed: {self.ducks_missed}", "STATS")


def main():
    print("="*60)
    print("DuckHunt IRC Bot v2.0")
    print("="*60)
    
    bot = DuckHuntBot("bot_config.ini")
    
    try:
        bot.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
        bot.running = False
        bot.disconnect()
        

if __name__ == "__main__":
    main()
