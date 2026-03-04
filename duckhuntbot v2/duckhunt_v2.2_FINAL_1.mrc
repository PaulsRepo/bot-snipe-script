; mIRC DuckHunt Auto-Reply Script v2.2
; LIMITED TO CHANNEL: #url
; FIXES:
; - Don't auto-use Buy Gun Back when purchasing (only when confiscated)
; - Better confiscation detection (not triggered by "is not confiscated")
; - Re-enabled shooting after miss (configurable)
; - Resume shooting after gun recovery
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
    set %duckhunt.gun.confiscated 0
    set %duckhunt.retry.on.miss 0
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: #url only)
    echo -a *** Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    ; Request stats to check inventory
    .timer.duckhunt.checkstats 1 2 msg #url !duckstats
  }
  elseif ($1 == off) {
    unset %duckhunt.*
    .timer.duckhunt.* off
    echo -a *** DuckHunt Auto-Reply: DISABLED
  }
  elseif ($1 == retry) {
    if ($2 == on) {
      set %duckhunt.retry.on.miss 1
      echo -a *** Retry on miss: ENABLED (Warning: Can hit bystanders!)
    }
    elseif ($2 == off) {
      set %duckhunt.retry.on.miss 0
      echo -a *** Retry on miss: DISABLED (Safer)
    }
    else {
      echo -a Usage: /duckhunt retry on|off
      echo -a Current: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    }
  }
  else {
    echo -a Usage: /duckhunt on|off
    echo -a        /duckhunt retry on|off  - Toggle retry after miss
    echo -a Status: $iif(%duckhunt.enabled == 1, ENABLED, DISABLED)
    echo -a Channel: #url only
    echo -a Buy Gun Back in inventory: $iif(%duckhunt.has.buyback > 0, YES ( $+ %duckhunt.has.buyback $+ ), NO)
    echo -a Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a Gun status: $iif(%duckhunt.gun.confiscated == 1, CONFISCATED, OK)
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
      set %duckhunt.duck.hp 4
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
  if ($me isin $1-) && (*Items:* iswm $1-) {
    ; Extract everything after "Items:"
    var %fulltext = $1-
    var %pos = $pos(%fulltext, Items:, 1)
    
    if (%pos > 0) {
      var %items = $mid(%fulltext, $calc(%pos + 6))
      echo -a *** [#url] DEBUG: Items string: %items
      
      ; Look for "Buy Gun Back x#" or just "Buy Gun Back"
      if (Buy Gun Back isin %items) {
        ; Use regex to extract number after "Buy Gun Back x"
        var %result = $regsubex(%items, /.*Buy Gun Back x(\d+).*/i, \1)
        
        ; Check if we got a number back
        if (%result isnum) {
          set %duckhunt.has.buyback %result
          echo -a *** [#url] Inventory check: Buy Gun Back x $+ %result
        }
        else {
          ; No "x#" found, assume quantity is 1
          set %duckhunt.has.buyback 1
          echo -a *** [#url] Inventory check: Buy Gun Back x1
        }
      }
      else {
        set %duckhunt.has.buyback 0
        echo -a *** [#url] Inventory check: NO Buy Gun Back
      }
      
      ; Check gun status from duckstats
      if (*Confiscated* iswm $1-) {
        set %duckhunt.gun.confiscated 1
      }
      else {
        set %duckhunt.gun.confiscated 0
      }
    }
  }
  
  ; Detect successful purchase of Buy Gun Back - DON'T auto-use
  if (*Successfully purchased Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      inc %duckhunt.has.buyback
      echo -a *** [#url] PURCHASED Buy Gun Back (now have: %duckhunt.has.buyback $+ )
      echo -a *** [#url] Buy Gun Back stored in inventory (not using it unless confiscated)
    }
  }
  
  ; Detect gun returned after using Buy Gun Back
  if (*Your gun has been returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] GUN RECOVERED!
      set %duckhunt.gun.confiscated 0
      dec %duckhunt.has.buyback
      
      ; Auto-reload after recovery
      .timer.duckhunt.reloadafter 1 1 msg #url !reload
      
      ; Resume shooting if duck is still active
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        echo -a *** [#url] Resuming shooting at duck (HP: %duckhunt.duck.hp $+ )
        .timer.duckhunt.resume 1 3 msg #url !bang
      }
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
      .timer.duckhunt.resume off
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
      .timer.duckhunt.resume off
    }
    
    ; Missed the duck - retry if enabled
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) && (*missed and hit* !iswm $1-) {
      echo -a *** [#url] MISSED THE DUCK
      
      if (%duckhunt.retry.on.miss == 1) && (%duckhunt.duck.active == 1) {
        echo -a *** [#url] RETRYING (retry enabled)
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
      else {
        echo -a *** [#url] Not retrying (safer mode)
      }
    }
    
    ; Missed and hit someone - GUN WILL BE CONFISCATED
    elseif (*missed and hit* iswm $1-) {
      echo -a *** [#url] MISSED AND HIT SOMEONE - GUN ABOUT TO BE CONFISCATED
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
      ; Gun confiscation message will come next
    }
    
    ; Out of ammo
    elseif (*out of ammo* iswm $1-) || ((*click* iswm $1-) && (*reload* iswm $1-)) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    
    ; Gun confiscated - ONLY if actually confiscated (not "is not confiscated")
    elseif (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-) && (*GUN CONFISCATED* iswm $1-)) {
      echo -a *** [#url] GUN CONFISCATED!
      set %duckhunt.gun.confiscated 1
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
      
      ; Check if we have Buy Gun Back in inventory
      if (%duckhunt.has.buyback > 0) {
        echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
        .timer.duckhunt.usebuyback 1 1 msg #url !use 7
      }
      else {
        echo -a *** [#url] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
      }
    }
    
    ; "Your gun is not confiscated" - ignore this, don't trigger confiscation handler
    elseif (*gun is not confiscated* iswm $1-) {
      echo -a *** [#url] Gun is OK (not confiscated)
    }
    
    ; Gun jammed - RETRY
    elseif (*jammed* iswm $1-) {
      echo -a *** [#url] GUN JAMMED - RETRYING
      
      ; Always retry after jam if duck is still active
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.jamretry 1 1 msg #url !bang
      }
    }
    
    ; No duck in area - STOP
    elseif (*no duck in the area* iswm $1-) {
      echo -a *** [#url] NO DUCK - STOPPING ALL TIMERS
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
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

; Manual inventory check alias
alias duckhunt.check {
  msg #url !duckstats
}

echo -a *** DuckHunt Auto-Reply Script Loaded (v2.2)
echo -a *** Limited to channel: #url only
echo -a *** Features: Auto buy-back gun, optional retry on miss
echo -a *** Type: /duckhunt on           to enable
echo -a *** Type: /duckhunt off          to disable
echo -a *** Type: /duckhunt retry on     to enable retry on miss (risky!)
echo -a *** Type: /duckhunt retry off    to disable retry on miss (safer)
echo -a *** Type: /duckhunt              to check status
echo -a *** Type: /duckhunt.check        to manually check inventory
