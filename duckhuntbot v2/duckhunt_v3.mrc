; mIRC DuckHunt Auto-Reply Script
; LIMITED TO CHANNEL: #url
; Save this as duckhunt.mrc and load it in mIRC: /load -rs duckhunt.mrc
; To enable: /duckhunt on
; To disable: /duckhunt off

alias duckhunt {
  if ($1 == on) {
    set %duckhunt.enabled 1
    set %duckhunt.duck.active 0
    set %duckhunt.duck.hp 0
    set %duckhunt.duck.type normal
    set %duckhunt.ammo 6
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: #url only)
  }
  elseif ($1 == off) {
    unset %duckhunt.*
    .timer.duckhunt.* off
    echo -a *** DuckHunt Auto-Reply: DISABLED
  }
  else {
    echo -a Usage: /duckhunt on|off
    echo -a Status: $iif(%duckhunt.enabled == 1, ENABLED, DISABLED)
    echo -a Channel: #url only
  }
}

; Detect duck spawns - ONLY in #url
on *:TEXT:*:#url:{
  if (%duckhunt.enabled != 1) return
  
  ; Only listen to DuckHunt bot
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  
  ; Duck spawn detection
  if (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) {
    
    ; Determine duck type
    if (*golden* iswm $1-) || (*glimmer* iswm $1-) || (*\o<* iswm $1-) {
      set %duckhunt.duck.type golden
      set %duckhunt.duck.hp 3
      echo -a *** [#url] GOLDEN DUCK SPAWNED - RAPID FIRE MODE
      
      ; Rapid fire for golden ducks - 4 shots with 0.85 second delays
      .timer.duckhunt.shoot1 1 1 msg #url !bang
      .timer.duckhunt.shoot2 1 2 msg #url !bang
      .timer.duckhunt.shoot3 1 3 msg #url !bang
      .timer.duckhunt.shoot4 1 4 msg #url !bang
    }
    elseif (*fast* iswm $1-) || (*respawn* iswm $1-) {
      set %duckhunt.duck.type fast
      set %duckhunt.duck.hp 1
      echo -a *** [#url] FAST DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
    else {
      set %duckhunt.duck.type normal
      set %duckhunt.duck.hp 1
      echo -a *** [#url] DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
    
    set %duckhunt.duck.active 1
  }
  
  ; Duck escape detection
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) {
    echo -a *** [#url] DUCK ESCAPED
    set %duckhunt.duck.active 0
    set %duckhunt.duck.hp 0
    .timer.duckhunt.shoot* off
  }
  
  ; Shot result detection (your nickname mentioned)
  if ($me isin $1-) {
    
    ; Duck killed - STOP SHOOTING IMMEDIATELY
    if (*killed* iswm $1-) && (*duck* iswm $1-) {
      echo -a *** [#url] DUCK KILLED - STOPPING
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
    }
    
    ; HP remaining - continue shooting
    elseif (*HP remaining* iswm $1-) {
      var %hp = $regsubex($1-, /.*\[(\d+) HP remaining\].*/i, \1)
      set %duckhunt.duck.hp %hp
      echo -a *** [#url] HIT! Duck HP: %hp
      
      ; Continue shooting if HP > 0
      if (%hp > 0) && (%duckhunt.duck.active == 1) {
        .timer.duckhunt.continue 1 1 msg #url !bang
      }
      else {
        .timer.duckhunt.shoot* off
      }
    }
    
    ; Shot the duck (1 HP kill)
    elseif (*shot*duck* iswm $1-) || (*shot*FAST DUCK* iswm $1-) || (*shot*GOLDEN DUCK* iswm $1-) {
      echo -a *** [#url] DUCK KILLED
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
    }
    
    ; Missed - try again if duck is still active
    elseif (*missed* iswm $1-) {
      echo -a *** [#url] MISSED
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        echo -a *** [#url] TRYING AGAIN
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
    }
    
    ; Out of ammo
    elseif (*out of ammo* iswm $1-) || (*click* iswm $1-) && (*reload* iswm $1-) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    
    ; Gun confiscated - STOP EVERYTHING
    elseif (*confiscated* iswm $1-) {
      echo -a *** [#url] GUN CONFISCATED - STOPPING
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
    }
    
    ; Gun jammed - try again
    elseif (*jammed* iswm $1-) {
      echo -a *** [#url] GUN JAMMED
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        echo -a *** [#url] RETRYING
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
    }
    
    ; No duck in area - means we shot after it was killed, STOP
    elseif (*no duck in the area* iswm $1-) {
      echo -a *** [#url] NO DUCK - STOPPING ALL TIMERS
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
    }
  }
}

; Auto-reload confirmation - ONLY in #url
on *:TEXT:*New magazine loaded*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    echo -a *** [#url] MAGAZINE RELOADED
    set %duckhunt.ammo 6
  }
}

; Clean up on disconnect
on *:DISCONNECT:{
  .timer.duckhunt.* off
  echo -a *** DuckHunt: Timers cleared on disconnect
}

; Clean up on part #url
on *:PART:#url:{
  if ($nick == $me) {
    .timer.duckhunt.* off
    echo -a *** DuckHunt: Timers cleared on leaving #url
  }
}

echo -a *** DuckHunt Auto-Reply Script Loaded
echo -a *** Limited to channel: #url only
echo -a *** Type: /duckhunt on    to enable
echo -a *** Type: /duckhunt off   to disable
