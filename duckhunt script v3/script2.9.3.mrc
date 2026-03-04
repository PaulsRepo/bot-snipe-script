; ============================================================
; DuckHunt Auto-Shooter Script v3.1
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
  if ($1 == DuckHunt)  { return $true }
  if ($1 == Quackbot)  { return $true }
  return $false
}

; ============================================================
; Duck detection — match the QUACK line specifically
; Uses $instr to avoid backslash wildcard issues
; ============================================================
on *:TEXT:*QUACK!*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  ; Confirm it's actually the duck spawn line, not something else
  if ($instr($1-,\_O<) == 0) { halt }

  var %delay = $rand(15,35)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck spotted! Shooting in $calc(%delay / 10) $+ s
}

; ============================================================
; Decoy detection — must come from the bot AND contain DECOY DUCK
; Tightened pattern so inventory messages don't false-trigger
; ============================================================
on *:TEXT:*DECOY DUCK*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  var %delay = $rand(15,25)
  .timer 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Decoy duck! Befriending in $calc(%delay / 10) $+ s
}

; ============================================================
; Also catch decoy if bot announces it differently
; Only fires if the bot says it (not inventory/shop messages)
; ============================================================
on *:TEXT:*decoy*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  ; Must contain "trap" style announcement, not an inventory line
  if ($instr($1-,inventory) > 0) { halt }
  if ($instr($1-,Inventory) > 0) { halt }
  if ($instr($1-,shop) > 0)      { halt }
  if ($instr($1-,dropped) > 0)   { halt }

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
  echo -a [DuckHunt] $chan $+ : Gun confiscated! Attempting buy-back...
  .timer 1 3 msg $chan !use 7
}

; ============================================================
; NOTICE fallback — some bot configs use NOTICE for spawns
; ============================================================
on *:NOTICE:*QUACK!*:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  var %delay = $rand(15,35)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck via NOTICE! Shooting in $calc(%delay / 10) $+ s
}
