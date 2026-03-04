; ============================================================
; DuckHunt Auto-Shooter Script v3.2
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
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  ; Clear any lingering follow-up state from previous duck
  set %duck.active. [ $+ $chan ] 0
  unset %duck.chan

  ; Fast first shot — 0.8 to 1.2 seconds
  var %delay = $rand(8,12)
  set %duck.active. [ $+ $chan ] 1
  set %duck.chan $chan
  .timer 1 %delay msg $chan !bang
  echo -a [DuckHunt] $chan $+ : Duck spotted! First shot in $calc(%delay / 10) $+ s
}

; ============================================================
; Hit response parser — continue shooting if HP remains
; Quackbot format: "It has X HP left"
; ============================================================
on *:TEXT:*It has*HP left*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if (!%duck.active. [ $+ $chan ]) { halt }

  ; Extract remaining HP using token parsing
  var %msg = $1-
  var %hp = $gettok($remove(%msg,HP,left,It,has),$findtok($remove(%msg,HP,left,It,has),1,32),32)

  ; Cleaner HP extraction — find the number before "HP left"
  var %hppos = $instr(%msg,HP left)
  var %sub = $left(%msg,$calc(%hppos - 2))
  var %hp = $gettok(%sub,-1,32)

  if (%hp > 0) {
    ; Multi-HP duck confirmed — pace follow-up shots
    var %delay = $rand(18,28)
    .timer 1 %delay msg $chan !bang
    echo -a [DuckHunt] $chan $+ : $+ %hp HP remaining — follow-up shot in $calc(%delay / 10) $+ s
  }
  else {
    ; Duck dead — clean up
    set %duck.active. [ $+ $chan ] 0
    echo -a [DuckHunt] $chan $+ : Du
