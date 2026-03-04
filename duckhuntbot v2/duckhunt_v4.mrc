; mIRC DuckHunt Auto-Reply Script
; LIMITED TO CHANNEL: #url
; Auto buy-back gun feature included
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
    set %duckhunt.has.buyback 0
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: #url only)
    ; Request stats to check inventory
    .timer.duckhunt.checkstats 1 2 msg #url !duckstats
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
    echo -a Buy Gun Back in inventory: $iif(%duckhunt.has.buyback > 0, YES ( $+ %duckhunt.has.buyback $+ ), NO)
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
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) {
    echo -a *** [#url] DUCK ESCAPED
    set %duckhunt.duck.active 0
    set %duckhunt.duck.hp 0
    .timer.duckhunt.shoot* off
  }
  
  ; Parse duckstats to check inventory
  if (*duckstats* iswm $1-) || (*XP* iswm $1-) && (*Items:* iswm $1-) {
    if ($me isin $1-) {
      ; Check for Buy Gun Back in inventory
      var %items = $gettok($1-, $findtok($1-, Items:, 1, 32), 32-)
      
      if (*Buy Gun Back* iswm %items) {
        ; Extract quantity if shown (e.g., "Buy Gun Back x2")
        var %buyback = $regsubex(%items, /.*Buy Gun Back x(\d+).*/i, \1)
        if (%buyback isnum) {
          set %duckhunt.has.buyback %buyback
          echo -a *** [#url] Inventory check: Buy Gun Back x $+ %buyback
        }
        else {
          set %duckhunt.has.buyback 1
          echo -a *** [#url] Inventory check: Buy Gun Back x1
        }
      }
      else {
        set %duckhunt.has.buyback 0
        echo -a *** [#url] Inventory check: NO Buy Gun Back
      }
    }
  }
  
  ; Detect successful purchase of Buy Gun Back
  if (*Successfully purchased Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      inc %duckhunt.has.buyback
      echo -a *** [#url] PURCHASED Buy Gun Back (now have: %duckhunt.has.buyback $+ )
      ; Use it immediately
      .timer.duckhunt.usebuyback 1 1 msg #url !use 7
    }
  }
  
  ; Detect gun returned after using Buy Gun Back
  if (*Your gun has been returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] GUN RECOVERED!
      dec %duckhunt.has.buyback
      ; Reload if we have low ammo
      .timer.duckhunt.reloadafter 1 1 msg #url !reload
    }
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
    
    ; Missed the duck - DON'T retry (to avoid hitting other players)
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) {
      echo -a *** [#url] MISSED THE DUCK
      ; Don't retry - too risky of hitting someone
      ; Just let other scheduled shots continue if it's a golden duck
    }
    
    ; Missed and hit someone - GUN WILL BE CONFISCATED
    elseif (*missed and hit* iswm $1-) {
      echo -a *** [#url] MISSED AND HIT SOMEONE - PREPARING FOR CONFISCATION
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      ; Gun will be confiscated, prepare to buy back
    }
    
    ; Out of ammo
    elseif (*out of ammo* iswm $1-) || (*click* iswm $1-) && (*reload* iswm $1-) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    
    ; Gun confiscated - AUTO BUY BACK
    elseif (*confiscated* iswm $1-) || (*gun has been confiscated* iswm $1-) {
      echo -a *** [#url] GUN CONFISCATED!
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      
      ; Check if we have Buy Gun Back in inventory
      if (%duckhunt.has.buyback > 0) {
        echo -a *** [#url] Using Buy Gun Back from inventory
        .timer.duckhunt.usebuyback 1 1 msg #url !use 7
      }
      else {
        echo -a *** [#url] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
      }
    }
    
    ; Gun jammed - DON'T retry (to avoid hitting someone on miss)
    elseif (*jammed* iswm $1-) {
      echo -a *** [#url] GUN JAMMED
      ; Don't retry - just continue with scheduled shots if any
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

; Check stats periodically to update inventory
alias duckhunt.updateinventory {
  if (%duckhunt.enabled == 1) {
    msg #url !duckstats
  }
}

echo -a *** DuckHunt Auto-Reply Script Loaded (v2.0)
echo -a *** Limited to channel: #url only
echo -a *** Features: Auto buy-back gun, smart miss handling
echo -a *** Type: /duckhunt on    to enable
echo -a *** Type: /duckhunt off   to disable
echo -a *** Type: /duckhunt        to check status
