; mIRC DuckHunt Auto-Reply Script v2.5
; LIMITED TO CHANNEL: #url
; CHANGELOG:
; - v2.2: Don't auto-use Buy Gun Back unless confiscated; better confiscation detection
; - v2.2: Re-enabled shooting after miss (configurable); resume after gun recovery
; - v2.3: Persist retry intent through reload cycle
; - v2.4: Fix buy-back not triggering - [GUN CONFISCATED] is in the missed-and-hit
;         message itself, not a follow-up; merged into one handler
; - v2.5: Full new duck type support:
;         - Ninja duck: 1 HP but high dodge - always retry on miss/dodge
;         - Boss duck: high HP cooperative kill - sustained rapid fire
;         - Decoy duck: DO NOT SHOOT - use !bef instead (shooting = confiscation)
;         - Flock duck: 2-4 ducks at once - rapid fire, track remaining count
;         - Fast/Normal: confirmed working, no changes
;         - Shop buy syntax updated: !shop buy <id>
;         - Inventory check updated: !inv instead of !duckstats
;         - Auto-claim !daily on enable
;         - New toggle: /duckhunt befriend on|off (controls decoy duck behaviour)
;         - New handler: soaked/wet clothes - auto-buys Dry Clothes (ID 9)
;         - New manual aliases: /duckhunt.daily, /duckhunt.effects
; Save as duckhunt.mrc and load: /load -rs duckhunt.mrc
; To enable:  /duckhunt on
; To disable: /duckhunt off

; ============================================================
; MAIN CONTROL ALIAS
; ============================================================
alias duckhunt {
  if ($1 == on) {
    set %duckhunt.enabled 1
    set %duckhunt.duck.active 0
    set %duckhunt.duck.hp 0
    set %duckhunt.duck.type normal
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    set %duckhunt.ammo 6
    set %duckhunt.has.buyback 0
    set %duckhunt.gun.confiscated 0
    set %duckhunt.retry.on.miss 0
    set %duckhunt.pending.retry 0
    set %duckhunt.befriend.enabled 1
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: #url only)
    echo -a *** Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a *** Befriend decoys: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
    ; Check inventory and claim daily bonus
    .timer.duckhunt.checkinv 1 2 msg #url !inv
    .timer.duckhunt.daily 1 4 msg #url !daily
  }
  elseif ($1 == off) {
    unset %duckhunt.*
    .timer.duckhunt.* off
    echo -a *** DuckHunt Auto-Reply: DISABLED
  }
  elseif ($1 == retry) {
    if ($2 == on) {
      set %duckhunt.retry.on.miss 1
      echo -a *** Retry on miss: ENABLED (Warning: increases friendly-fire risk!)
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
  elseif ($1 == befriend) {
    if ($2 == on) {
      set %duckhunt.befriend.enabled 1
      echo -a *** Befriend mode: ENABLED (will !bef decoy ducks)
    }
    elseif ($2 == off) {
      set %duckhunt.befriend.enabled 0
      echo -a *** Befriend mode: DISABLED (will skip decoy ducks entirely)
    }
    else {
      echo -a Usage: /duckhunt befriend on|off
      echo -a Current: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
    }
  }
  else {
    echo -a Usage: /duckhunt on|off
    echo -a        /duckhunt retry on|off    - Retry after miss (risky - friendly fire)
    echo -a        /duckhunt befriend on|off - Befriend decoy ducks (recommended: on)
    echo -a Status: $iif(%duckhunt.enabled == 1, ENABLED, DISABLED)
    echo -a Channel: #url only
    echo -a Buy Gun Back in inventory: $iif(%duckhunt.has.buyback > 0, YES ( $+ %duckhunt.has.buyback $+ ), NO)
    echo -a Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a Befriend decoys: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
    echo -a Gun status: $iif(%duckhunt.gun.confiscated == 1, CONFISCATED, OK)
    echo -a Active duck: $iif(%duckhunt.duck.active == 1, YES (Type: %duckhunt.duck.type - HP: %duckhunt.duck.hp $+ ), NO)
  }
}

; ============================================================
; MAIN MESSAGE HANDLER
; ============================================================
on *:TEXT:*:#url:{
  if (%duckhunt.enabled != 1) return

  ; Only respond to the DuckHunt bot
  if ($nick != DuckHunt) && ($nick != Quackbot) return

  ; ----------------------------------------------------------
  ; DUCK SPAWN DETECTION
  ; ----------------------------------------------------------
  if (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*waddles in* iswm $1-) || (*sneaks in* iswm $1-) {

    ; Clear all state and timers from previous duck
    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off

    ; --- DECOY DUCK ---
    ; Check FIRST - shooting a decoy confiscates your gun
    if (*decoy* iswm $1-) {
      set %duckhunt.duck.type decoy
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] DECOY DUCK SPAWNED - DO NOT SHOOT!

      if (%duckhunt.befriend.enabled == 1) {
        echo -a *** [#url] Befriending decoy duck...
        .timer.duckhunt.bef 1 1 msg #url !bef
      }
      else {
        echo -a *** [#url] Befriend disabled - ignoring decoy duck
        set %duckhunt.duck.active 0
      }
    }

    ; --- FLOCK DUCK ---
    elseif (*flock* iswm $1-) {
      set %duckhunt.duck.type flock
      set %duckhunt.duck.flock 1
      set %duckhunt.duck.active 1

      ; Try to extract count from message e.g. "a flock of 3 ducks"
      var %flockcount = $regsubex($1-, /.*flock of (\d+).*/i, \1)
      if (%flockcount isnum) {
        set %duckhunt.duck.flock.count %flockcount
        set %duckhunt.duck.hp %flockcount
        echo -a *** [#url] FLOCK OF %flockcount DUCKS - RAPID FIRE
      }
      else {
        set %duckhunt.duck.flock.count 2
        set %duckhunt.duck.hp 2
        echo -a *** [#url] FLOCK SPAWNED (count unknown, assuming 2) - RAPID FIRE
      }

      ; Fire count+2 shots to handle all ducks safely
      var %shots = $calc(%duckhunt.duck.flock.count + 2)
      var %i = 1
      while (%i <= %shots) {
        .timer.duckhunt.shoot $+ %i 1 %i msg #url !bang
        inc %i
      }
    }

    ; --- GOLDEN DUCK ---
    elseif (*golden* iswm $1-) || (*glimmer* iswm $1-) {
      set %duckhunt.duck.type golden
      set %duckhunt.duck.hp 4
      set %duckhunt.duck.active 1
      echo -a *** [#url] GOLDEN DUCK SPAWNED - RAPID FIRE (4 HP)
      .timer.duckhunt.shoot1 1 1 msg #url !bang
      .timer.duckhunt.shoot2 1 2 msg #url !bang
      .timer.duckhunt.shoot3 1 3 msg #url !bang
      .timer.duckhunt.shoot4 1 4 msg #url !bang
    }

    ; --- BOSS DUCK ---
    ; Cooperative multi-HP duck; sustained fire, let HP remaining messages drive continuation
    elseif (*boss* iswm $1-) {
      set %duckhunt.duck.type boss
      var %bosshp = $regsubex($1-, /.*\[(\d+) HP\].*/i, \1)
      if (%bosshp isnum) {
        set %duckhunt.duck.hp %bosshp
      }
      else {
        set %duckhunt.duck.hp 10
      }
      set %duckhunt.duck.active 1
      echo -a *** [#url] BOSS DUCK SPAWNED (HP: %duckhunt.duck.hp $+ ) - SUSTAINED FIRE
      .timer.duckhunt.shoot1 1 1 msg #url !bang
      .timer.duckhunt.shoot2 1 2 msg #url !bang
      .timer.duckhunt.shoot3 1 3 msg #url !bang
      .timer.duckhunt.shoot4 1 4 msg #url !bang
    }

    ; --- NINJA DUCK ---
    ; 1 HP but dodge chance - shoot once, retry handler covers misses always
    elseif (*ninja* iswm $1-) {
      set %duckhunt.duck.type ninja
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] NINJA DUCK SPAWNED - will always retry on dodge
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }

    ; --- FAST DUCK ---
    elseif (*fast* iswm $1-) || (*speedy* iswm $1-) {
      set %duckhunt.duck.type fast
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] FAST DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }

    ; --- NORMAL DUCK (fallback) ---
    else {
      set %duckhunt.duck.type normal
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
  }

  ; ----------------------------------------------------------
  ; DUCK ESCAPED / DISAPPEARED
  ; ----------------------------------------------------------
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) || (*swims away* iswm $1-) || (*retreats* iswm $1-) {
    echo -a *** [#url] DUCK ESCAPED
    set %duckhunt.duck.active 0
    set %duckhunt.duck.hp 0
    set %duckhunt.duck.flock 0
    set %duckhunt.pending.retry 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off
  }

  ; ----------------------------------------------------------
  ; INVENTORY PARSE - !inv response
  ; ----------------------------------------------------------
  if ($me isin $1-) && (*Buy Gun Back* iswm $1-) {
    var %bgbcount = $regsubex($1-, /.*Buy Gun Back(?:\s*x(\d+))?.*/i, \1)
    if (%bgbcount isnum) {
      set %duckhunt.has.buyback %bgbcount
      echo -a *** [#url] Inventory: Buy Gun Back x $+ %bgbcount
    }
    else {
      set %duckhunt.has.buyback 1
      echo -a *** [#url] Inventory: Buy Gun Back x1
    }
  }

  ; ----------------------------------------------------------
  ; PURCHASE CONFIRMATIONS
  ; ----------------------------------------------------------
  if (*Successfully purchased Buy Gun Back* iswm $1-) || (*purchased*Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      inc %duckhunt.has.buyback
      echo -a *** [#url] PURCHASED Buy Gun Back (now have: %duckhunt.has.buyback $+ ) - stored
    }
  }

  if (*purchased*Hunter* iswm $1-) && (*Insurance* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] Hunter's Insurance active - friendly fire protected for 24h
    }
  }

  ; ----------------------------------------------------------
  ; GUN RETURNED after Buy Gun Back used
  ; ----------------------------------------------------------
  if (*Your gun has been returned* iswm $1-) || (*gun.*returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] GUN RECOVERED!
      set %duckhunt.gun.confiscated 0
      if (%duckhunt.has.buyback > 0) dec %duckhunt.has.buyback
      .timer.duckhunt.reloadafter 1 1 msg #url !reload
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        echo -a *** [#url] Duck still active (HP: %duckhunt.duck.hp $+ ) - resuming after reload
        .timer.duckhunt.resume 1 3 msg #url !bang
      }
    }
  }

  ; ----------------------------------------------------------
  ; BEFRIEND RESULTS
  ; ----------------------------------------------------------
  if ($me isin $1-) {
    if (*befriended* iswm $1-) || (*made friends* iswm $1-) || (*waddled over* iswm $1-) || (*accept your friendship* iswm $1-) {
      echo -a *** [#url] BEFRIEND SUCCESSFUL
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.bef off
      .timer.duckhunt.shoot* off
    }
    elseif (*failed to befriend* iswm $1-) || (*ran away* iswm $1-) {
      echo -a *** [#url] BEFRIEND FAILED
      if (%duckhunt.duck.type == decoy) {
        echo -a *** [#url] Decoy - not retrying to avoid risk
        set %duckhunt.duck.active 0
      }
    }
  }

  ; ----------------------------------------------------------
  ; SHOT RESULTS (messages that contain our nick)
  ; ----------------------------------------------------------
  if ($me isin $1-) {

    ; Duck killed
    if ((*killed* iswm $1-) && (*duck* iswm $1-)) || (*DUCK DEFEATED* iswm $1-) {
      echo -a *** [#url] DUCK KILLED - STOPPING
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      set %duckhunt.duck.flock 0
      set %duckhunt.pending.retry 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
    }

    ; HP remaining - update HP and keep shooting
    elseif *HP remaining* iswm $1- {
      var %hp = $regsubex($1-, /.*\[(\d+) HP remaining\].*/i, \1)
      set %duckhunt.duck.hp %hp
      set %duckhunt.pending.retry 0
      echo -a *** [#url] HIT! Duck HP: %hp
      if (%hp > 0) && (%duckhunt.duck.active == 1) {
        .timer.duckhunt.continue 1 1 msg #url !bang
      }
      else {
        .timer.duckhunt.shoot* off
      }
    }

    ; One-shot kill (no HP remaining message)
    elseif (*shot*duck* iswm $1-) || (*shot*FAST* iswm $1-) || (*shot*GOLDEN* iswm $1-) || (*shot*NINJA* iswm $1-) || (*shot*BOSS* iswm $1-) || (*shot*FLOCK* iswm $1-) {
      echo -a *** [#url] DUCK KILLED (one-shot)
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      set %duckhunt.duck.flock 0
      set %duckhunt.pending.retry 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
    }

    ; Flock: partial kill, ducks remaining
    elseif (*flock* iswm $1-) && ((*remaining* iswm $1-) || (*duck*down* iswm $1-)) {
      var %fleft = $regsubex($1-, /.*(\d+).*remaining.*/i, \1)
      if (%fleft isnum) && (%fleft > 0) {
        set %duckhunt.duck.hp %fleft
        echo -a *** [#url] FLOCK HIT - %fleft duck(s) remaining - continuing
        .timer.duckhunt.continue 1 1 msg #url !bang
      }
      else {
        echo -a *** [#url] FLOCK CLEARED
        set %duckhunt.duck.active 0
        set %duckhunt.duck.hp 0
        set %duckhunt.duck.flock 0
        .timer.duckhunt.shoot* off
        .timer.duckhunt.continue off
      }
    }

    ; Ninja dodge - always retry
    elseif (*dodged* iswm $1-) || (*evaded* iswm $1-) {
      echo -a *** [#url] DODGE! Retrying...
      if (%duckhunt.duck.active == 1) {
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
    }

    ; Normal miss (not friendly fire)
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) && (*missed and hit* !iswm $1-) {
      echo -a *** [#url] MISSED THE DUCK

      ; Ninja: always retry regardless of setting
      if (%duckhunt.duck.type == ninja) && (%duckhunt.duck.active == 1) {
        echo -a *** [#url] NINJA DUCK - always retrying
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
      elseif (%duckhunt.retry.on.miss == 1) && (%duckhunt.duck.active == 1) {
        echo -a *** [#url] RETRYING (retry enabled)
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
      else {
        echo -a *** [#url] Not retrying (safer mode)
      }
    }

    ; Missed and hit someone - confiscation is IN THIS message
    elseif *missed and hit* iswm $1- {
      echo -a *** [#url] MISSED AND HIT SOMEONE - HANDLING CONFISCATION NOW
      set %duckhunt.gun.confiscated 1
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      set %duckhunt.duck.flock 0
      set %duckhunt.pending.retry 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off

      if (%duckhunt.has.buyback > 0) {
        echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
        .timer.duckhunt.usebuyback 1 1 msg #url !use 7
      }
      else {
        echo -a *** [#url] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop buy 7
      }
    }

    ; Out of ammo - reload; pending.retry survives into reload handler
    elseif (*out of ammo* iswm $1-) || ((*click* iswm $1-) && (*reload* iswm $1-)) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }

    ; Gun confiscated via standalone message (fallback)
    elseif (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-)) {
      echo -a *** [#url] GUN CONFISCATED!
      set %duckhunt.gun.confiscated 1
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      set %duckhunt.duck.flock 0
      set %duckhunt.pending.retry 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off

      if (%duckhunt.has.buyback > 0) {
        echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
        .timer.duckhunt.usebuyback 1 1 msg #url !use 7
      }
      else {
        echo -a *** [#url] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop buy 7
      }
    }

    ; Gun is fine - suppress false positive
    elseif *gun is not confiscated* iswm $1- {
      echo -a *** [#url] Gun is OK
    }

    ; Gun jammed - always retry if duck is up
    elseif *jammed* iswm $1- {
      echo -a *** [#url] GUN JAMMED - RETRYING
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.jamretry 1 1 msg #url !bang
      }
    }

    ; Soaked / wet clothes - buy Dry Clothes (ID 9) and wait
    elseif (*soaked* iswm $1-) || (*wet clothes* iswm $1-) || (*cannot shoot* iswm $1-) || (*wringing wet* iswm $1-) {
      echo -a *** [#url] SOAKED - buying Dry Clothes to resume shooting
      .timer.duckhunt.shoot* off
      .timer.duckhunt.dryclothes 1 2 msg #url !shop buy 9
    }

    ; No duck in area
    elseif *no duck in the area* iswm $1- {
      echo -a *** [#url] NO DUCK - STOPPING
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      set %duckhunt.duck.flock 0
      set %duckhunt.pending.retry 0
      .timer.duckhunt.shoot* off
      .timer.duckhunt.continue off
      .timer.duckhunt.retry off
      .timer.duckhunt.resume off
    }

    ; Daily already claimed
    elseif (*already claimed* iswm $1-) && (*daily* iswm $1-) {
      echo -a *** [#url] Daily XP already claimed today
    }

    ; Daily claimed successfully
    elseif (*daily* iswm $1-) && ((*bonus* iswm $1-) || (*XP* iswm $1-)) && (*claimed* iswm $1-) {
      echo -a *** [#url] Daily XP bonus claimed!
    }
  }
}

; ============================================================
; RELOAD CONFIRMATION
; ============================================================
on *:TEXT:*New magazine loaded*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    echo -a *** [#url] MAGAZINE RELOADED
    set %duckhunt.ammo 6

    ; Pending retry from a miss that ran out of ammo - fire immediately
    if (%duckhunt.pending.retry == 1) && (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Pending retry after reload - FIRING
      set %duckhunt.pending.retry 0
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
    ; Otherwise resume normally if duck still alive
    elseif (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Duck still active (HP: %duckhunt.duck.hp $+ ) - RESUMING
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
  }
}

; ============================================================
; DRY CLOTHES CONFIRMATION - resume after soaked
; ============================================================
on *:TEXT:*dried*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    if (*dry* iswm $1-) || (*clothes* iswm $1-) || (*dried off* iswm $1-) {
      echo -a *** [#url] DRY CLOTHES USED - can shoot again
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.afterdry 1 1 msg #url !bang
      }
    }
  }
}

; ============================================================
; CLEANUP
; ============================================================
on *:DISCONNECT:{
  .timer.duckhunt.* off
  echo -a *** DuckHunt: Timers cleared on disconnect
}

on *:PART:#url:{
  if ($nick == $me) {
    .timer.duckhunt.* off
    echo -a *** DuckHunt: Timers cleared on leaving #url
  }
}

; ============================================================
; MANUAL ALIASES
; ============================================================
alias duckhunt.check {
  msg #url !inv
}

alias duckhunt.daily {
  msg #url !daily
}

alias duckhunt.effects {
  msg #url !effects
}

; ============================================================
; LOAD MESSAGE
; ============================================================
echo -a *** DuckHunt Auto-Reply Script Loaded (v2.5)
echo -a *** Limited to channel: #url only
echo -a *** Duck types: Normal, Golden, Fast, Ninja, Boss, Decoy, Flock
echo -a *** Type: /duckhunt on              to enable
echo -a *** Type: /duckhunt off             to disable
echo -a *** Type: /duckhunt retry on|off    to toggle retry on miss (risky)
echo -a *** Type: /duckhunt befriend on|off to toggle befriend for decoy ducks
echo -a *** Type: /duckhunt                 to check full status
echo -a *** Type: /duckhunt.check           to check inventory (!inv)
echo -a *** Type: /duckhunt.daily           to manually claim daily XP
echo -a *** Type: /duckhunt.effects         to check active buffs/debuffs
