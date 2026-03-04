; ============================================================
; DuckHunt Auto-Shooter Script v3.0
; ============================================================
; CONFIGURATION - Add or remove channels below:
;
; To add a channel:    Add it to the $duck_chans alias, e.g:
;                      if ($1 == #newchannel) { return $true }
;
; To remove a channel: Comment out or delete its line below
;
; Bot names recognized: DuckHunt, Quackbot
; ============================================================

alias duck_chans {
  ; --- Active channels (add/remove here) ---
  if ($1 == #url)    { return $true }
  if ($1 == #3nd3r)  { return $true }
  ; if ($1 == #chat)   { return $true }
  ; if ($1 == #example) { return $true }   ; <-- example: uncomment to add
  return $false
}

alias duck_isbot {
  if ($1 == DuckHunt)  { return $true }
  if ($1 == Quackbot)  { return $true }
  return $false
}

; ============================================================
; Core duck detection — triggers on QUACK line
; ============================================================
on *:TEXT:*\_O<  QUACK!*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  ; Small random delay (1-3s) to feel more human, avoid race conditions
  var %delay = $rand(10,30)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] Duck spotted in $chan $+ ! Shooting in $calc(%delay / 10) $+ s
}

; ============================================================
; Decoy detection — say !befriend instead of !bang
; ============================================================
on *:TEXT:*DECOY*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  var %delay = $rand(10,25)
  .timer 1 %delay msg $chan !befriend
  echo -a [DuckHunt] Decoy spotted in $chan $+ ! Befriending in $calc(%delay / 10) $+ s
}

; ============================================================
; Duck escaped — log it
; ============================================================
on *:TEXT:*duck*away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  echo -a [DuckHunt] Duck escaped in $chan $+ ! Better luck next time.
}

on *:TEXT:*flies away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  echo -a [DuckHunt] Duck got away in $chan $+ .
}

; ============================================================
; Gun confiscated recovery — auto buy back
; ============================================================
on *:TEXT:*GUN CONFISCATED*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  echo -a [DuckHunt] *** Gun confiscated in $chan $+ ! Attempting buy-back...
  .timer 1 3 msg $chan !shop 7
  .timer 1 5 msg $chan !use 7
}

; ============================================================
; Notice-based responses (some bots use NOTICE not TEXT)
; ============================================================
on *:NOTICE:*\_O<  QUACK!*:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  var %delay = $rand(10,30)
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] Duck spotted via NOTICE in $chan $+ !
}
