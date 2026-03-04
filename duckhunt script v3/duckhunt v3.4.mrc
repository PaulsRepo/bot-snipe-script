; ============================================================
; DuckHunt Auto-Shooter Script v3.4
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

alias duck_canceltimer {
  var %tname = duck_ $+ $1
  .timer %tname off
}

alias duck_shoot {
  ; $1 = chan, $2 = delay
  var %tname = duck_ $+ $1
  .timer %tname 1 $2 msg $1 !bang
}

; ============================================================
; Duck detection — fast initial shot
; ============================================================
on *:TEXT:*QUACK!*:#:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan

  var %delay = $rand(8,12)
  set %duck.active. [ $+ $chan ] 1
  duck_shoot $chan %delay
  echo -a [DuckHunt] $chan $+ : Duck spotted! First shot in $calc(%delay / 10) $+ s
}

; ============================================================
; Hit response — continue shooting if HP remains
; Quackbot format: "It has X HP left"
; ============================================================
on *:TEXT:*It has*HP left*:#:{
  if (!$duck_chans($chan))             { halt }
  if (!$duck_isbot($nick))             { halt }
  if (!%duck.active. [ $+ $chan ])     { halt }

  var %msg = $1-
  var %hppos = $instr(%msg,HP left)
  var %sub = $left(%msg,$calc(%hppos - 2))
  var %hp = $gettok(%sub,-1,32)

  if (%hp > 0) {
    var %delay = $rand(18,28)
    duck_shoot $chan %delay
    echo -a [DuckHunt] $chan $+ : $+ %hp HP remaining — follow-up in $calc(%delay / 10) $+ s
  }
  else {
    set %duck.active. [ $+ $chan ] 0
    echo -a [DuckHunt] $chan $+ : Duck killed!
  }
}

; ============================================================
; Miss response — faster retry to catch fast ducks
; ============================================================
on *:TEXT:*You missed the duck*:#:{
  if (!$duck_chans($chan))           { halt }
  if (!$duck_isbot($nick))           { halt }
  if (!%duck.active. [ $+ $chan ])   { halt }

  var %delay = $rand(12,18)
  duck_shoot $chan %delay
  echo -a [DuckHunt] $chan $+ : Missed! Retrying in $calc(%delay / 10) $+ s
}

; ============================================================
; Out of ammo — auto reload then continue
; ============================================================
on *:TEXT:*out of ammo*:#:{
  if (!$duck_chans($chan))           { halt }
  if (!$duck_isbot($nick))           { halt }
  if (!%duck.active. [ $+ $chan ])   { halt }

  echo -a [DuckHunt] $chan $+ : Out of ammo — reloading...
  var %tnameR = duckR_ $+ $chan
  var %tnameB = duck_ $+ $chan
  .timer %tnameR 1 2 msg $chan !reload
  .timer %tnameB 1 4 msg $chan !bang
}

; ============================================================
; Duck escaped — cancel timer and clean up
; ============================================================
on *:TEXT:*flies away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Duck escaped — timer cancelled.
}

on *:TEXT:*vanishes*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Duck vanished — timer cancelled.
}

on *:TEXT:*disappears*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Duck disappeared — timer cancelled.
}

on *:TEXT:*smoke bomb*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Ninja duck escaped — timer cancelled.
}

on *:TEXT:*soars away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Duck soared away — timer cancelled.
}

; ============================================================
; Decoy detection — bot announcement only, not inventory
; ============================================================
on *:TEXT:*DECOY DUCK*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  var %delay = $rand(15,25)
  var %tname = duckD_ $+ $chan
  .timer %tname 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Decoy! Befriending in $calc(%delay / 10) $+ s
}

on *:TEXT:*decoy*:#:{
  if (!$duck_chans($chan))              { halt }
  if (!$duck_isbot($nick))              { halt }
  if ($instr($1-,nventory) > 0)        { halt }
  if ($instr($1-,hop) > 0)             { halt }
  if ($instr($1-,dropped) > 0)         { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  var %delay = $rand(15,25)
  var %tname = duckD_ $+ $chan
  .timer %tname 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Possible decoy! Befriending in $calc(%delay / 10) $+ s
}

; ============================================================
; Gun confiscated — auto buy-back from inventory
; ============================================================
on *:TEXT:*GUN CONFISCATED*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  set %duck.active. [ $+ $chan ] 0
  duck_canceltimer $chan
  echo -a [DuckHunt] $chan $+ : Gun confiscated! Attempting buy-back...
  var %tname = duckG_ $+ $chan
  .timer %tname 1 3 msg $chan !use 7
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
  duck_shoot $chan %delay
  echo -a [DuckHunt] $chan $+ : Duck via NOTICE! Shooting in $calc(%delay / 10) $+ s
}
