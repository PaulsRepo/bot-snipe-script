; ============================================================
; DuckHunt Auto-Shooter Script v5.0
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
  ; if ($1 == #computertech)  { return $true }
  ;  if ($1 == #сomputertech)  { return $true }
  ; if ($1 == #example) { return $true }
  return $false
}

alias duck_isbot {
  if ($1 == DuckHunt) { return $true }
  if ($1 == Quackbot) { return $true }
  return $false
}

; Your IRC nick — change this if your nick changes
alias duck_mynick {
  return url
}

alias duck_setactive {
  set %duck.active. [ $+ $1 ] $2
}

alias duck_active {
  var %v = %duck.active. [ $+ $1 ]
  return %v
}

; Cancel all pending shoot/reload timers for a channel
alias duck_cleartimers {
  .timer [ duck_shoot_ $+ $1 ] off
  .timer [ duck_reload_ $+ $1 ] off
}

; Deactivate and cancel all timers — call on any escape/death/confiscate
alias duck_stop {
  duck_setactive $1 0
  duck_cleartimers $1
}

; Queue a single !bang — cancels any existing queued shot first to prevent stacking
alias duck_queueshot {
  ; $1 = chan, $2 = delay
  duck_cleartimers $1
  .timer [ duck_shoot_ $+ $1 ] 1 $2 msg $1 !bang
}

; Queue a reload then shot — cancels any existing timers first
alias duck_queuereload {
  ; $1 = chan
  duck_cleartimers $1
  .timer [ duck_reload_ $+ $1 ] 1 2 msg $1 !reload
  .timer [ duck_shoot_ $+ $1 ] 1 4 msg $1 !bang
}

; ============================================================
; Standard duck detection — fast initial shot
; ============================================================
on *:TEXT:*QUACK!*:#:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }

  duck_stop $chan
  duck_setactive $chan 1
  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Duck spotted! First shot in %delay $+ s
}

; ============================================================
; Boss duck detection
; ============================================================
on *:TEXT:*BOSS DUCK*has appeared*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  duck_stop $chan
  duck_setactive $chan 1
  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : BOSS DUCK appeared! First shot in %delay $+ s
}

; ============================================================
; Boss duck defeated — stop shooting
; ============================================================
on *:TEXT:*Boss duck defeated*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Boss duck defeated — ceasing fire.
}

; ============================================================
; Flock detection
; ============================================================
on *:TEXT:*flock*has landed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

  duck_stop $chan
  duck_setactive $chan 1
  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Flock spotted! First shot in %delay $+ s
}

; ============================================================
; Flock still has ducks remaining — keep shooting
; ============================================================
on *:TEXT:*duck(s) still in the flock*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }

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
  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : $+ %remaining duck(s) left in flock — shooting in %delay $+ s
}

; ============================================================
; Hit response — parse HP by finding "has" token then next token
; ============================================================
on *:TEXT:*It has*HP left*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %msg = $1-
  var %hstok = $findtok(%msg,has,1,32)
  var %hp = $remove($gettok(%msg,$calc(%hstok + 1),32),.,!,?)

  if (%hp > 0) {
    var %delay = $rand(2,5)
    duck_queueshot $chan %delay
    echo -a [DuckHunt] $chan $+ : $+ %hp HP remaining — follow-up in %delay $+ s
  }
  else {
    duck_stop $chan
    echo -a [DuckHunt] $chan $+ : Duck killed!
  }
}

; ============================================================
; Miss response
; ============================================================
on *:TEXT:*You missed the duck*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Missed! Retrying in %delay $+ s
}

; ============================================================
; Friendly fire — keep shooting
; ============================================================
on *:TEXT:*You missed and hit*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Friendly fire! Retrying in %delay $+ s
}

; ============================================================
; Gun jammed — wait then retry
; ============================================================
on *:TEXT:*gun jammed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(2,5)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Gun jammed! Waiting to retry in %delay $+ s
}

; ============================================================
; Shooting too fast — back off
; ============================================================
on *:TEXT:*trying to shoot too fast*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(3,5)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Too fast — backing off, retrying in %delay $+ s
}

; ============================================================
; Doing that too quickly — same as too fast
; ============================================================
on *:TEXT:*doing that too quickly*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  var %delay = $rand(3,5)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Too fast — backing off, retrying in %delay $+ s
}

; ============================================================
; Out of ammo — reload then continue
; ============================================================
on *:TEXT:*out of ammo*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  if (!$duck_active($chan)) { halt }

  duck_queuereload $chan
  echo -a [DuckHunt] $chan $+ : Out of ammo — reloading...
}

; ============================================================
; Duck escaped — stop everything
; ============================================================
on *:TEXT:*flies away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck escaped.
}

on *:TEXT:*escapes into the sky*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck escaped into sky.
}

on *:TEXT:*vanishes*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck vanished.
}

on *:TEXT:*disappears*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck disappeared.
}

on *:TEXT:*takes flight*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck took flight.
}

on *:TEXT:*smoke bomb*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Ninja duck escaped.
}

on *:TEXT:*soars away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck soared away.
}

on *:TEXT:*zips away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck zipped away.
}

on *:TEXT:*lightning speed*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck gone at lightning speed.
}

on *:TEXT:*darts away*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck darted away.
}

on *:TEXT:*before you can blink*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck too fast!
}

on *:TEXT:*living another day*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck got away.
}

on *:TEXT:*into the distance*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Duck disappeared into distance.
}

; ============================================================
; Decoy detection — exact bot phrase only
; ============================================================
on *:TEXT:*DECOY DUCK*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  duck_stop $chan
  var %delay = $rand(2,5)
  .timer [ duck_shoot_ $+ $chan ] 1 %delay msg $chan !befriend
  echo -a [DuckHunt] $chan $+ : Decoy! Befriending in %delay $+ s
}

; ============================================================
; Gun confiscated — auto buy-back from inventory
; ============================================================
on *:TEXT:*GUN CONFISCATED*:#:{
  if (!$duck_chans($chan))  { halt }
  if (!$duck_isbot($nick))  { halt }
  if ($gettok($1-,1,32) != $duck_mynick) { halt }
  if ($gettok($1-,2,32) != >) { halt }
  duck_stop $chan
  echo -a [DuckHunt] $chan $+ : Gun confiscated! Attempting buy-back...
  .timer [ duck_gunback_ $+ $chan ] 1 3 msg $chan !use 7
}

; ============================================================
; NOTICE fallback — some bot configs use NOTICE for spawns
; ============================================================
on *:NOTICE:*QUACK!*:{
  if (!$duck_chans($chan))   { halt }
  if (!$duck_isbot($nick))   { halt }
  if ($instr($1-,\_O<) == 0) { halt }
  duck_stop $chan
  duck_setactive $chan 1
  var %delay = $rand(2,4)
  duck_queueshot $chan %delay
  echo -a [DuckHunt] $chan $+ : Duck via NOTICE! Shooting in %delay $+ s
}

; ============================================================
; Daily tasks — !daily and Hunter's Insurance
; Runs once on connect, then re-checked every 6 hours
; Uses %duck.daily.date to track last run date
; ============================================================

; Channel to send daily commands to
alias duck_daily_chan {
  return #3nd3r
}

alias duck_do_daily {
  var %today = $date(yyyy-mm-dd)
  if (%duck.daily.date == %today) {
    echo -a [DuckHunt] Daily tasks already done today ( $+ %today $+ ), skipping.
    halt
  }
  set %duck.daily.date %today
  var %chan = $duck_daily_chan

  .timer duck_daily_cmd1 1 5  msg %chan !daily
  .timer duck_daily_cmd2 1 12 msg %chan !shop 6
  .timer duck_daily_cmd3 1 18 msg %chan !use 6
  echo -a [DuckHunt] Daily tasks queued for %chan
}

on *:CONNECT:{
  .timer duck_daily 1 3 duck_do_daily
  .timer duck_daily_repeat 0 21600 duck_do_daily
}
