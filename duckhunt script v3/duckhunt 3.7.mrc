; ============================================================
; DuckHunt Auto-Shooter Script v3.7
; Bots: DuckHunt, Quackbot
; ============================================================
; CHANNEL CONFIGURATION:
; To add a channel:    if ($1 == #newchan) { return $true }
; To remove a channel: comment out or delete its line
; ============================================================

alias duck_chans {
  if ($1 == #url)   { return $true }
  if ($1 == #3nd3r) { return $true }
  ; if ($1 == #chat)  { return $true }
  ; if ($1 == #example) { return $true }
  return $false
}

alias duck_isbot {
  if ($1 == DuckHunt) { return $true }
  if ($1 == Quackbot) { return $true }
  return $false
}

; ============================================================
; Duck detection — fast initial shot
; ============================================================
on *:TEXT:*QUACK!*:#:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  set %duck.active. [ $+ $chan ] 1
  var %delay = $rand(8,12)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck spotted! First shot in $calc(%delay / 10) $+ s
}

; ============================================================
; Hit response — continue shooting if HP remains
; ============================================================
on *:TEXT:*It has*HP left*:#:{
  if (!$duck_chans($chan))           { halt }
  if (!$duck_isbot($nick))           { halt }
  if (!%duck.active. [ $+ $chan ])   { halt }

  var %msg = $1-
  var %hppos = $instr(%msg,HP left)
  var %sub = $left(%msg,$calc(%hppos - 2))
  var %hp = $gettok(%sub,-1,32)

  if (%hp > 0) {
    var %delay = $rand(18,28)
    .timer 1 %delay msg $chan !bang
    echo -a [DuckHunt] $chan $+ : $+ %hp HP remaining — follow-up in $calc(%delay / 10) $+ s
  }
  else {
    set %duck.active. [ $+ $chan ] 0
    echo -a [DuckHunt] $chan $+ : Duck killed!
  }
}

; ============================================================
; Miss response — faster retry
; ============================================================
on *:TEXT:*You missed the duck*:#:{
  if (!$duck_chans($chan))           { halt }
  if (!$duck_isbot($nick))           { halt }
  if (!%duck.active. [ $+ $chan ])   { halt }

  var %delay = $rand(12,18)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Missed! Retrying in $calc(%delay / 10) $+ s
}

; ============================================================
; Out of ammo — reload then continue
; ============================================================
on *:TEXT:*out of ammo*:#:{
  if (!$duck_chans($chan))           { halt }
  if (!$duck_isbot($nick))           { halt }
  if (!%duck.active. [ $+ $chan ])   { halt }

  echo -a [DuckHunt] $chan $+ : Out of ammo — reloading...
  .timer 1 2 msg $chan !reload
  .timer 1 4 msg $chan !bang
}

; ============================================================
; Duck escaped — clear active flag, timers will fire harmlessly
; into empty air but %duck.active prevents any chained response
; ============================================================
on *:TEXT:*flies away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck escaped.
}

on *:TEXT:*vanishes*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck vanished.
}

on *:TEXT:*disappears*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck disappeared.
}

on *:TEXT:*smoke bomb*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Ninja duck escaped.
}

on *:TEXT:*soars away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck soared away.
}

on *:TEXT:*zips away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck zipped away.
}

on *:TEXT:*lightning speed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Duck gone at lightning speed.
}

; ============================================================
; Decoy detection — bot only, filter out inventory messages
; ============================================================
on *:TEXT:*DECOY DUCK*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  var %delay = $rand(15,25)
  .timer 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Decoy! Befriending in $calc(%delay / 10) $+ s
}

on *:TEXT:*decoy*:#:{
  if (!$duck_chans($chan))        { halt }
  if (!$duck_isbot($nick))        { halt }
  if ($instr($1-,nventory) > 0)  { halt }
  if ($instr($1-,hop) > 0)       { halt }
  if ($instr($1-,dropped) > 0)   { halt }
  set %duck.active. [ $+ $chan ] 0
  var %delay = $rand(15,25)
  .timer 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Possible decoy! Befriending in $calc(%delay / 10) $+ s
}

; ============================================================
; Gun confiscated — auto buy-back from inventory
; ============================================================
on *:TEXT:*GUN CONFISCATED*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  echo -a [DuckHunt] $chan $+ : Gun confiscated! Attempting buy-back...
  .timer 1 3 msg $chan !use 7
}

; ============================================================
; NOTICE fallback — some bot configs use NOTICE for spawns
; ============================================================
on *:NOTICE:*QUACK!*:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }
  set %duck.active. [ $+ $chan ] 1
  var %delay = $rand(8,12)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck via NOTICE! Shooting in $calc(%delay / 10) $+ s
}
