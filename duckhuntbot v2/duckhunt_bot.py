#!/usr/bin/env python3
"""
Enhanced DuckHunt IRC Bot
Fixes:
- Prevents shooting after duck is killed
- Fast reaction to golden ducks
- Automatic reloading and magazine management
- Smart HP tracking to avoid wasted shots
"""

import socket
import re
import time
import threading
from collections import deque
from datetime import datetime

class DuckHuntBot:
    def __init__(self, server, port, channel, nickname, password=None):
        self.server = server
        self.port = port
        self.channel = channel
        self.nickname = nickname
        self.password = password
        
        # Connection
        self.irc = None
        self.connected = False
        
        # Duck tracking
        self.active_duck = None
        self.duck_hp = 0
        self.duck_type = None  # 'normal', 'golden', 'fast'
        self.duck_spawn_time = None
        
        # Ammo tracking
        self.current_ammo = 6
        self.magazines = 3
        self.gun_confiscated = False
        
        # Rate limiting
        self.last_bang_time = 0
        self.min_bang_delay = 0.8  # Minimum seconds between shots
        
        # Message buffer for analysis
        self.recent_messages = deque(maxlen=10)
        
        # Shooting lock to prevent race conditions
        self.shooting_lock = threading.Lock()
        
    def connect(self):
        """Connect to IRC server"""
        print(f"[{self._timestamp()}] Connecting to {self.server}:{self.port}")
        self.irc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.irc.connect((self.server, self.port))
        
        if self.password:
            self._send_raw(f"PASS {self.password}")
        
        self._send_raw(f"NICK {self.nickname}")
        self._send_raw(f"USER {self.nickname} 0 * :{self.nickname}")
        
        # Wait for connection to be established
        time.sleep(2)
        self._send_raw(f"JOIN {self.channel}")
        self.connected = True
        print(f"[{self._timestamp()}] Connected and joined {self.channel}")
        
    def _send_raw(self, message):
        """Send raw IRC message"""
        self.irc.send(f"{message}\r\n".encode('utf-8'))
        
    def _send_message(self, message):
        """Send message to channel"""
        self._send_raw(f"PRIVMSG {self.channel} :{message}")
        print(f"[{self._timestamp()}] SENT: {message}")
        
    def _timestamp(self):
        """Get current timestamp"""
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
    def _parse_message(self, line):
        """Parse IRC message and extract relevant info"""
        # Match pattern: :nickname!user@host PRIVMSG #channel :message
        match = re.match(r':([^!]+)![^\s]+ PRIVMSG ([^\s]+) :(.*)', line)
        if match:
            sender = match.group(1)
            message = match.group(3)
            return sender, message
        return None, None
        
    def _detect_duck_spawn(self, sender, message):
        """Detect when a duck spawns"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return False
            
        # Duck spawn patterns
        duck_patterns = [
            r'\_[Oo]<',  # Standard duck
            r'QUACK',
            r'quack',
            r'\*flap flap\*',
        ]
        
        for pattern in duck_patterns:
            if re.search(pattern, message):
                # Determine duck type
                if 'golden' in message.lower() or '*glimmer*' in message.lower():
                    self.duck_type = 'golden'
                    self.duck_hp = 3  # Golden ducks typically have 2-4 HP
                elif 'fast' in message.lower() or 'respawn' in message.lower():
                    self.duck_type = 'fast'
                    self.duck_hp = 1
                else:
                    self.duck_type = 'normal'
                    self.duck_hp = 1
                    
                self.active_duck = True
                self.duck_spawn_time = time.time()
                print(f"[{self._timestamp()}] DUCK SPAWNED: {self.duck_type.upper()} (HP: {self.duck_hp})")
                return True
                
        return False
        
    def _detect_duck_escape(self, sender, message):
        """Detect when a duck escapes"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return False
            
        escape_patterns = [
            r'escapes',
            r'vanishes',
            r'disappears',
            r'glides away',
        ]
        
        for pattern in escape_patterns:
            if re.search(pattern, message, re.IGNORECASE):
                print(f"[{self._timestamp()}] DUCK ESCAPED")
                self.active_duck = None
                self.duck_hp = 0
                return True
                
        return False
        
    def _parse_shot_result(self, sender, message):
        """Parse the result of a shot"""
        if sender not in ['DuckHunt', 'Quackbot']:
            return
            
        # Duck killed
        if 'killed' in message.lower():
            print(f"[{self._timestamp()}] DUCK KILLED!")
            self.active_duck = None
            self.duck_hp = 0
            self.current_ammo -= 1
            return
            
        # Duck hit (HP remaining)
        hp_match = re.search(r'\[(\d+) HP remaining\]', message)
        if hp_match:
            self.duck_hp = int(hp_match.group(1))
            self.current_ammo -= 1
            print(f"[{self._timestamp()}] HIT! Duck HP: {self.duck_hp}, Ammo: {self.current_ammo}")
            return
            
        # Shot the duck (1 HP kill)
        if re.search(r'You shot (the|a) (duck|FAST DUCK)', message):
            print(f"[{self._timestamp()}] DUCK KILLED!")
            self.active_duck = None
            self.duck_hp = 0
            self.current_ammo -= 1
            return
            
        # Missed
        if 'missed' in message.lower():
            print(f"[{self._timestamp()}] MISSED")
            self.current_ammo -= 1
            return
            
        # Out of ammo
        if "out of ammo" in message.lower() or "*click*" in message.lower():
            print(f"[{self._timestamp()}] OUT OF AMMO")
            self.current_ammo = 0
            return
            
        # Gun confiscated
        if "confiscated" in message.lower():
            print(f"[{self._timestamp()}] GUN CONFISCATED!")
            self.gun_confiscated = True
            self.current_ammo = 0
            return
            
        # Gun jammed
        if "jammed" in message.lower():
            print(f"[{self._timestamp()}] GUN JAMMED")
            self.current_ammo -= 1
            return
            
    def _shoot_duck(self):
        """Shoot at the duck with proper timing"""
        with self.shooting_lock:
            if not self.active_duck:
                return False
                
            if self.gun_confiscated:
                print(f"[{self._timestamp()}] Cannot shoot - gun confiscated")
                return False
                
            if self.current_ammo <= 0:
                self._reload()
                return False
                
            # Rate limiting
            current_time = time.time()
            if current_time - self.last_bang_time < self.min_bang_delay:
                time.sleep(self.min_bang_delay - (current_time - self.last_bang_time))
                
            self._send_message("!bang")
            self.last_bang_time = time.time()
            return True
            
    def _reload(self):
        """Reload the gun"""
        if self.magazines > 0:
            print(f"[{self._timestamp()}] RELOADING...")
            self._send_message("!reload")
            time.sleep(1.5)  # Wait for reload to complete
            
    def _handle_golden_duck(self):
        """Special handling for golden ducks - rapid fire"""
        print(f"[{self._timestamp()}] ENGAGING GOLDEN DUCK (HP: {self.duck_hp})")
        
        shots_needed = self.duck_hp
        for i in range(shots_needed + 1):  # +1 for safety
            if not self.active_duck:
                break
                
            self._shoot_duck()
            time.sleep(0.85)  # Slightly longer delay for golden ducks
            
    def _handle_normal_duck(self):
        """Handle normal/fast ducks"""
        print(f"[{self._timestamp()}] ENGAGING {self.duck_type.upper()} DUCK")
        self._shoot_duck()
        
    def _auto_manage_resources(self):
        """Automatically manage ammo and magazines"""
        # If we have magazines in inventory, use them
        if self.current_ammo == 6 and self.magazines < 3:
            self._send_message("!use 2")  # Use magazine item
            time.sleep(0.5)
            
    def run(self):
        """Main bot loop"""
        buffer = ""
        
        while self.connected:
            try:
                data = self.irc.recv(4096).decode('utf-8', errors='ignore')
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
                        
                    # Store in recent messages
                    self.recent_messages.append((sender, message))
                    
                    # Check for duck spawn
                    if self._detect_duck_spawn(sender, message):
                        # Small delay to ensure spawn is fully registered
                        time.sleep(0.3)
                        
                        # Handle based on duck type
                        if self.duck_type == 'golden':
                            threading.Thread(target=self._handle_golden_duck, daemon=True).start()
                        else:
                            self._handle_normal_duck()
                            
                    # Check for duck escape
                    self._detect_duck_escape(sender, message)
                    
                    # Parse shot results
                    if self.nickname.lower() in message.lower():
                        self._parse_shot_result(sender, message)
                        
                        # If duck still alive and we have HP info, continue shooting
                        if self.active_duck and self.duck_hp > 0:
                            time.sleep(0.9)
                            self._shoot_duck()
                            
            except Exception as e:
                print(f"[{self._timestamp()}] ERROR: {e}")
                time.sleep(1)
                
    def disconnect(self):
        """Disconnect from IRC"""
        if self.connected:
            self._send_raw("QUIT :Bot shutting down")
            self.irc.close()
            self.connected = False
            print(f"[{self._timestamp()}] Disconnected")


def main():
    # Configuration - UPDATE THESE VALUES
    SERVER = "irc.rizon.net"
    PORT = 6667
    CHANNEL = "#url"
    NICKNAME = "url"  # Your nickname
    PASSWORD = None  # If you have a NickServ password, add it here
    
    bot = DuckHuntBot(SERVER, PORT, CHANNEL, NICKNAME, PASSWORD)
    
    try:
        bot.connect()
        print(f"[{bot._timestamp()}] Bot started. Press Ctrl+C to stop.")
        bot.run()
    except KeyboardInterrupt:
        print("\n[{bot._timestamp()}] Shutting down...")
        bot.disconnect()
    except Exception as e:
        print(f"[{bot._timestamp()}] Fatal error: {e}")
        bot.disconnect()


if __name__ == "__main__":
    main()
