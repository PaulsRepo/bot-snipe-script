; ============================================================
; DuckHunt Auto-Shooter Script v4.1
; Bots: DuckHunt, Quackbot
; ============================================================
; CHANNEL CONFIGURATION:
; To add a channel:    if ($1 == #newchan) { return $true }
; To remove a channel: comment out or delete its line
; ============================================================

alias duck_chans {
  if ($1 == #url)   { return $true }
  if ($1 == #3nd3r) { return $true }
  if ($1 == #chat)  { return $true }
  ; if ($1 == #example) { return $true }
  return $false
}

alias duck_isbot {
  if ($1 == DuckHunt) { return $true }
  if ($1 == Quackbot) { return $true }
  return $false
}

alias duck_setactive {
  set %duck.active. [ $+ $1 ] $2
}

alias duck_active {
  var %v = %duck.active. [ $+ $1 ]
  return %v
}

; ============================================================
; Duck detection — fast initial shot
; ============================================================
on *:TEXT:*QUACK!*:#:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  duck_setactive $chan 1
  var %delay = $rand(8,12)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck spotted! First shot in $calc(%delay / 10) $+ s
}

; ============================================================
; Flock detection — treat like a regular duck spawn
; ============================================================
on *:TEXT:*flock*has landed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  duck_setactive $chan 1
  var %delay = $rand(8,12)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Flock spotted! First shot in $calc(%delay / 10) $+ s
}

; ============================================================
; Flock still has ducks remaining — keep shooting
; "🦆 X duck(s) still in the flock!"
; ============================================================
on *:TEXT:*duck(s) still in the flock*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  ; Extract remaining count — first token that is a number
  var %msg = $1-
  var %i = 1
  var %remaining = 0
  :findnum
  var %tok = $gettok(%msg,%i,32)
  if (%tok == $null) { goto doshot }
  if ($regex(%tok,^[0-9]+$)) { var %remaining = %tok | goto doshot }
  inc %i
  goto findnum
  :doshot
  duck_setactive $chan 1
  var %delay = $rand(12,18)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : $+ %remaining duck(s) left in flock — shooting in $calc(%delay / 10) $+ s
}

; ============================================================
; Hit response — parse HP by finding "has" token then next token
; Handles both solo duck and flock hit messages
; ============================================================
on *:TEXT:*It has*HP left*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if (!$duck_active($chan)) { halt }

  var %msg = $1-
  var %hstok = $findtok(%msg,has,1,32)
  var %hp = $remove($gettok(%msg,$calc(%hstok + 1),32),.,!,?)

  if (%hp > 0) {
    var %delay = $rand(18,28)
    .timer 1 %delay msg $chan !bang
    echo -a [DuckHunt] $chan $+ : $+ %hp HP remaining — follow-up in $calc(%delay / 10) $+ s
  }
  else {
    ; Don't deactivate on flock kill — flock remaining handler keeps it alive
    ; Only deactivate if this is a solo duck (no flock remaining line will follow)
    duck_setactive $chan 0
    echo -a [DuckHunt] $chan $+ : Duck killed!
  }
}

; ============================================================
; Miss response — faster retry
; ============================================================
on *:TEXT:*You missed the duck*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(12,18)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Missed! Retrying in $calc(%delay / 10) $+ s
}

; ============================================================
; Out of ammo — reload then continue
; ============================================================
on *:TEXT:*out of ammo*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if (!$duck_active($chan)) { halt }

  echo -a [DuckHunt] $chan $+ : Out of ammo — reloading...
  .timer 1 2 msg $chan !reload
  .timer 1 4 msg $chan !bang
}

; ============================================================
; Duck escaped — clear active flag
; ============================================================
on *:TEXT:*flies away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck escaped.
}

on *:TEXT:*vanishes*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck vanished.
}

on *:TEXT:*disappears*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck disappeared.
}

on *:TEXT:*smoke bomb*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Ninja duck escaped.
}

on *:TEXT:*soars away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck soared away.
}

on *:TEXT:*zips away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck zipped away.
}

on *:TEXT:*lightning speed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck gone at lightning speed.
}

on *:TEXT:*darts away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck darted away.
}

on *:TEXT:*before you can blink*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  echo -a [DuckHunt] $chan $+ : Duck too fast!
}

; ============================================================
; Decoy detection — exact bot phrase only
; ============================================================
on *:TEXT:*DECOY DUCK*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
  var %delay = $rand(15,25)
  .timer 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Decoy! Befriending in $calc(%delay / 10) $+ s
}

; ============================================================
; Gun confiscated — auto buy-back from inventory
; ============================================================
on *:TEXT:*GUN CONFISCATED*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_setactive $chan 0
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
  duck_setactive $chan 1
  var %delay = $rand(8,12)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck via NOTICE! Shooting in $calc(%delay / 10) $+ s
}
