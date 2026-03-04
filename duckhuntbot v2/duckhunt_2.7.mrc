; mIRC DuckHunt Auto-Reply Script v2.7
; LIMITED TO CHANNEL: #url
; CHANGELOG:
; - v2.4: Confiscation fix - [GUN CONFISCATED] is in the missed-and-hit message itself
; - v2.5: New duck types (Ninja, Boss, Decoy, Flock), befriend toggle, soaked handler
; - v2.6: Reload loop, false befriend, insurance confiscation, boss/flock spawn detection,
;         ninja/swift escape detection, new hit format, shop syntax, purchase counter sync
; - v2.7: Fixes from log analysis 2026-02-25 to 2026-02-26:
;   BUG-A: FLOCK CONTINUATION BROKEN - "🦆 N duck(s) still in the flock!" is sent by
;           DuckHunt without the user's nick, so it was inside the "$me isin $1-" block
;           and NEVER fired. Moved to its own top-level handler OUTSIDE the nick block.
;           This was the primary cause of flocks partially escaping after the first kill.
;   BUG-B: FLOCK 0HP KILLS STOPPED COMBAT - "hit a duck in the flock for 1 damage!
;           It has 0 HP left." matched the HP-left=0 kill handler, setting duck.active=0
;           BEFORE the "🦆 N still in flock" announcement arrived. For flock type, a
;           0 HP hit now checks for remaining flock count rather than ending combat.
;           Combined with BUG-A fix, flock continuation now works correctly.
;   BUG-C: duckstats inventory regex returned wrong count (x2 showing as x1) - the
;           intermediate itemstr extraction had edge cases with the new duckstats pipe
;           format ("Armed | 5/6 ammo | 9 spares | ... | Items: ..."). Replaced with
;           a direct regex scan on the full $1- line for "Buy Gun Back x(\d+)".
;   BUG-D: Rate-limited retry silently dropped - after "too fast" cooldown the next
;           shot sometimes got no response. Increased cooldown delay from 2s to 3s
;           to better respect the server's rate-limit window.
;   BUG-E: Decoy duck confiscation - decoys spawn with a normal QUACK message, not
;           labelled as "decoy". The only way to know is *CLANG* on shoot. This is
;           unfixable without binoculars (ID 11). Added the specific *CLANG* wooden
;           decoy confiscation message to the gun-confiscated handler so recovery
;           still works correctly.
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
    set %duckhunt.recovering 0
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: #url only)
    echo -a *** Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a *** Befriend decoys: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
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
  if ($nick != DuckHunt) && ($nick != Quackbot) return

  ; ----------------------------------------------------------
  ; BUG-A FIX: FLOCK REMAINING COUNT - top-level, outside $me block
  ; "🦆 N duck(s) still in the flock!" - sent by DuckHunt with NO nick prefix
  ; This MUST be checked before the $me block since $me is not in this line
  ; ----------------------------------------------------------
  if (*duck(s) still in the flock* iswm $1-) || (*still in the flock* iswm $1-) {
    if (%duckhunt.duck.type == flock) && (%duckhunt.duck.active == 1) {
      var %remaining = $regsubex($1-, /(\d+) duck.s. still/i, \1)
      if (%remaining isnum) && (%remaining > 0) {
        set %duckhunt.duck.hp %remaining
        echo -a *** [#url] FLOCK: %remaining duck(s) remaining - continuing fire
        .timer.duckhunt.flockcontinue 1 1 msg #url !bang
      }
      else {
        ; Couldn't parse count but flock still active - fire anyway
        echo -a *** [#url] FLOCK: ducks remaining (count unknown) - continuing
        .timer.duckhunt.flockcontinue 1 1 msg #url !bang
      }
    }
    return
  }

  ; ----------------------------------------------------------
  ; DUCK SPAWN DETECTION
  ; ----------------------------------------------------------

  ; --- BOSS DUCK SPAWN (no QUACK) ---
  if (*BOSS DUCK*appeared* iswm $1-) || (*A BOSS DUCK* iswm $1-) || (*boss duck*HP* iswm $1-) {
    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off
    .timer.duckhunt.flockcontinue off

    set %duckhunt.duck.type boss
    var %bosshp = $regsubex($1-, /.*with (\d+) HP.*/i, \1)
    if (%bosshp isnum) { set %duckhunt.duck.hp %bosshp }
    else { set %duckhunt.duck.hp 10 }
    set %duckhunt.duck.active 1
    echo -a *** [#url] BOSS DUCK SPAWNED (HP: %duckhunt.duck.hp $+ ) - SUSTAINED FIRE
    .timer.duckhunt.shoot1 1 1 msg #url !bang
    .timer.duckhunt.shoot2 1 2 msg #url !bang
    .timer.duckhunt.shoot3 1 3 msg #url !bang
    .timer.duckhunt.shoot4 1 4 msg #url !bang
  }

  ; --- FLOCK SPAWN (no QUACK) ---
  elseif (*flock of*ducks*landed* iswm $1-) || (*A flock of* iswm $1-) {
    set %duckhunt.pending.retry 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off
    .timer.duckhunt.flockcontinue off

    set %duckhunt.duck.type flock
    set %duckhunt.duck.flock 1
    set %duckhunt.duck.active 1

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

    ; BUG-B FIX: Fire count+2 shots. The flock remaining handler
    ; drives continuation after each kill, not the HP=0 kill handler.
    var %shots = $calc(%duckhunt.duck.flock.count + 2)
    var %i = 1
    while (%i <= %shots) {
      .timer.duckhunt.shoot $+ %i 1 %i msg #url !bang
      inc %i
    }
  }

  ; --- QUACK/FLAP SPAWNS ---
  elseif (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*waddles in* iswm $1-) || (*sneaks in* iswm $1-) {

    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off
    .timer.duckhunt.flockcontinue off

    ; Decoy check first (only if spawn message itself says decoy)
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
    elseif (*ninja* iswm $1-) {
      set %duckhunt.duck.type ninja
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] NINJA DUCK SPAWNED - always retrying on dodge
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
    elseif (*fast* iswm $1-) || (*speedy* iswm $1-) {
      set %duckhunt.duck.type fast
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] FAST DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
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
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) || (*swims away* iswm $1-) || (*retreats* iswm $1-) || (*smoke bomb and vanishes* iswm $1-) || (*darts away* iswm $1-) || (*takes flight* iswm $1-) || (*disappears into the clouds* iswm $1-) || (*waddles away* iswm $1-) || (*flap*The duck has escaped* iswm $1-) || (*duck flies away* iswm $1-) || (*living another day* iswm $1-) || (*disappears into the distance* iswm $1-) || (*flaps away* iswm $1-) {
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
    .timer.duckhunt.flockcontinue off
  }

  ; ----------------------------------------------------------
  ; INVENTORY PARSE - !inv response
  ; Format: "🎒 Inventory: Magazine x10 (#2) | Buy Gun Back x2 (#7)"
  ; ----------------------------------------------------------
  if (*Inventory:* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      ; BUG-C FIX: Scan full line directly, no intermediate itemstr extraction
      var %bgbcount = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbcount isnum) {
        set %duckhunt.has.buyback %bgbcount
        echo -a *** [#url] Inventory: Buy Gun Back x $+ %bgbcount
      }
    }
    else {
      set %duckhunt.has.buyback 0
      echo -a *** [#url] Inventory: No Buy Gun Back
    }
  }

  ; duckstats inventory parse - also scan full line directly
  ; Detect duckstats by presence of "shot |" or "shot " and "Items:"
  if ($me isin $1-) && (*Items:* iswm $1-) && (*shot* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      ; BUG-C FIX: Direct scan on full line
      var %bgbfromstats = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbfromstats isnum) {
        set %duckhunt.has.buyback %bgbfromstats
        echo -a *** [#url] duckstats inventory: Buy Gun Back x $+ %bgbfromstats
      }
    }
    else {
      set %duckhunt.has.buyback 0
      echo -a *** [#url] duckstats inventory: No Buy Gun Back
    }
  }

  ; ----------------------------------------------------------
  ; PURCHASE CONFIRMATIONS
  ; BUG-C RELATED: Parse confirmed count from "(xN)" in bot message
  ; ----------------------------------------------------------
  if (*purchased Buy Gun Back* iswm $1-) || (*purchased*Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      var %newcount = $regsubex($1-, /\(x(\d+)\)/i, \1)
      if (%newcount isnum) {
        set %duckhunt.has.buyback %newcount
        echo -a *** [#url] PURCHASED Buy Gun Back (confirmed x $+ %newcount $+ ) - stored
      }
      else {
        inc %duckhunt.has.buyback
        echo -a *** [#url] PURCHASED Buy Gun Back (now have: %duckhunt.has.buyback $+ ) - stored
      }
    }
  }

  if (*purchased*Hunter* iswm $1-) && (*Insurance* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] Hunter's Insurance active - friendly fire protected for 24h
    }
  }

  ; ----------------------------------------------------------
  ; GUN RETURNED after Buy Gun Back
  ; ----------------------------------------------------------
  if (*gun has been returned* iswm $1-) || (*Your gun has been returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [#url] GUN RECOVERED!
      set %duckhunt.gun.confiscated 0
      set %duckhunt.recovering 1
      if (%duckhunt.has.buyback > 0) dec %duckhunt.has.buyback
      .timer.duckhunt.reloadafter 1 1 msg #url !reload
    }
  }

  ; ----------------------------------------------------------
  ; BEFRIEND RESULTS
  ; Exclude duckstats lines ("0 befriended") via negative checks
  ; ----------------------------------------------------------
  if ($me isin $1-) {
    if (*befriended* iswm $1-) && (*0 befriended* !iswm $1-) && (*shot* !iswm $1-) && (*Items:* !iswm $1-) {
      echo -a *** [#url] BEFRIEND SUCCESSFUL
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.bef off
      .timer.duckhunt.shoot* off
    }
    elseif (*made friends* iswm $1-) || (*waddled over* iswm $1-) || (*accept your friendship* iswm $1-) {
      echo -a *** [#url] BEFRIEND SUCCESSFUL
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.bef off
      .timer.duckhunt.shoot* off
    }
    elseif (*failed to befriend* iswm $1-) || (*ran away* iswm $1-) {
      echo -a *** [#url] BEFRIEND FAILED
      if (%duckhunt.duck.type == decoy) {
        echo -a *** [#url] Decoy - not retrying to avoid confiscation risk
        set %duckhunt.duck.active 0
      }
    }
  }

  ; ----------------------------------------------------------
  ; SHOT RESULTS ($me in message)
  ; ----------------------------------------------------------
  if ($me isin $1-) {

    ; Duck killed (explicit text)
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
      .timer.duckhunt.flockcontinue off
    }

    ; -------------------------------------------------------
    ; BUG-B FIX: New hit format "hit the DUCK for N damage! It has N HP left."
    ; For FLOCK type: 0 HP = one flock duck dead, DON'T stop combat.
    ;   Continuation is driven by the "still in the flock" handler above.
    ; For all other types: 0 HP = duck is dead, stop combat.
    ; -------------------------------------------------------
    elseif (*hit*for*damage* iswm $1-) && (*HP left* iswm $1-) {
      var %hpleft = $regsubex($1-, /It has (\d+) HP left/i, \1)
      if (%hpleft isnum) {
        if (%hpleft == 0) {
          if (%duckhunt.duck.type == flock) {
            ; One flock duck down - the "still in the flock" handler drives continuation
            echo -a *** [#url] FLOCK DUCK DOWN (0 HP) - waiting for remaining count
            ; Don't touch duck.active - leave flock handler in charge
          }
          else {
            echo -a *** [#url] DUCK KILLED (0 HP left)
            set %duckhunt.duck.active 0
            set %duckhunt.duck.hp 0
            set %duckhunt.pending.retry 0
            .timer.duckhunt.shoot* off
            .timer.duckhunt.continue off
            .timer.duckhunt.retry off
            .timer.duckhunt.resume off
          }
        }
        else {
          ; HP > 0, keep shooting
          set %duckhunt.duck.hp %hpleft
          set %duckhunt.pending.retry 0
          echo -a *** [#url] HIT! Duck HP: %hpleft
          if (%duckhunt.duck.active == 1) {
            .timer.duckhunt.continue 1 1 msg #url !bang
          }
        }
      }
    }

    ; HP remaining (old format)
    elseif *HP remaining* iswm $1- {
      var %hp = $regsubex($1-, /\[(\d+) HP remaining\]/i, \1)
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

    ; One-shot kill (old "shot the duck" format)
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
      .timer.duckhunt.flockcontinue off
    }

    ; Dodge (ninja)
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

    ; Missed and hit someone - check for actual confiscation vs insurance
    elseif *missed and hit* iswm $1- {
      if (*GUN CONFISCATED* iswm $1-) {
        echo -a *** [#url] MISSED AND HIT SOMEONE - GUN CONFISCATED
        set %duckhunt.gun.confiscated 1
        set %duckhunt.duck.active 0
        set %duckhunt.duck.hp 0
        set %duckhunt.duck.flock 0
        set %duckhunt.pending.retry 0
        .timer.duckhunt.shoot* off
        .timer.duckhunt.continue off
        .timer.duckhunt.retry off
        .timer.duckhunt.resume off
        .timer.duckhunt.flockcontinue off
        if (%duckhunt.has.buyback > 0) {
          echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
          .timer.duckhunt.usebuyback 1 1 msg #url !use 7
        }
        else {
          echo -a *** [#url] No Buy Gun Back - purchasing one
          .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
        }
      }
      elseif (*INSURANCE PROTECTED* iswm $1-) || (*No penalties* iswm $1-) {
        echo -a *** [#url] FRIENDLY FIRE - INSURANCE PROTECTED, continuing
        if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
          .timer.duckhunt.continue 1 1 msg #url !bang
        }
      }
      else {
        ; Unknown variant - assume confiscation
        echo -a *** [#url] MISSED AND HIT - unknown result, treating as confiscated
        set %duckhunt.gun.confiscated 1
        set %duckhunt.duck.active 0
        set %duckhunt.duck.hp 0
        set %duckhunt.duck.flock 0
        set %duckhunt.pending.retry 0
        .timer.duckhunt.shoot* off
        .timer.duckhunt.continue off
        .timer.duckhunt.retry off
        .timer.duckhunt.resume off
        .timer.duckhunt.flockcontinue off
        if (%duckhunt.has.buyback > 0) {
          echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
          .timer.duckhunt.usebuyback 1 1 msg #url !use 7
        }
        else {
          echo -a *** [#url] No Buy Gun Back - purchasing one
          .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
        }
      }
    }

    ; Out of ammo - only reload if hunting or message says to
    ; BUG1 guard: recovering flag prevents !reload loop
    elseif (*out of ammo* iswm $1-) && (*Use !reload* iswm $1-) && (%duckhunt.recovering == 0) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.duck.active == 1) && (%duckhunt.recovering == 0) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.recovering == 1) {
      echo -a *** [#url] Out of ammo during recovery (no spare mags) - stopping reload loop
      set %duckhunt.recovering 0
    }

    ; BUG-E: Decoy duck confiscation via wooden decoy message (*CLANG*)
    ; Also catches standalone gun confiscated messages
    elseif (*CLANG* iswm $1-) || (*wooden decoy* iswm $1-) || (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-) && (*INSURANCE* !iswm $1-)) {
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
      .timer.duckhunt.flockcontinue off
      if (%duckhunt.has.buyback > 0) {
        echo -a *** [#url] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
        .timer.duckhunt.usebuyback 1 1 msg #url !use 7
      }
      else {
        echo -a *** [#url] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
      }
    }

    ; Gun not confiscated - suppress false positive
    elseif *gun is not confiscated* iswm $1- {
      echo -a *** [#url] Gun is OK
    }

    ; Gun jammed - always retry if duck active
    elseif *jammed* iswm $1- {
      echo -a *** [#url] GUN JAMMED - RETRYING
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.jamretry 1 1 msg #url !bang
      }
    }

    ; BUG-D FIX: Rate limited - increased from 2s to 3s cooldown
    elseif (*trying to shoot too fast* iswm $1-) || (*doing that too quickly* iswm $1-) {
      echo -a *** [#url] RATE LIMITED - waiting 3s before retry
      if (%duckhunt.duck.active == 1) {
        .timer.duckhunt.cooldown 1 3 msg #url !bang
      }
    }

    ; Soaked - buy Dry Clothes
    elseif (*soaked* iswm $1-) || (*wet clothes* iswm $1-) || (*cannot shoot* iswm $1-) || (*wringing wet* iswm $1-) {
      echo -a *** [#url] SOAKED - buying Dry Clothes to resume
      .timer.duckhunt.shoot* off
      .timer.duckhunt.dryclothes 1 2 msg #url !shop 9
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
      .timer.duckhunt.flockcontinue off
    }

    ; Daily
    elseif (*already claimed* iswm $1-) && (*daily* iswm $1-) {
      echo -a *** [#url] Daily XP already claimed today
    }
    elseif (*daily* iswm $1-) && ((*bonus* iswm $1-) || (*XP* iswm $1-)) && (*claimed* iswm $1-) {
      echo -a *** [#url] Daily XP bonus claimed!
    }
  }
}

; ============================================================
; RELOAD CONFIRMATION
; Clears recovering flag so gun-recovery !reload doesn't loop
; ============================================================
on *:TEXT:*New magazine loaded*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    echo -a *** [#url] MAGAZINE RELOADED
    set %duckhunt.ammo 6
    set %duckhunt.recovering 0

    if (%duckhunt.pending.retry == 1) && (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Pending retry after reload - FIRING
      set %duckhunt.pending.retry 0
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
    elseif (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Duck still active (HP: %duckhunt.duck.hp $+ ) - RESUMING
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
  }
}

; ============================================================
; DRY CLOTHES CONFIRMATION
; ============================================================
on *:TEXT:*dried*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    if (*dry* iswm $1-) || (*dried off* iswm $1-) {
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
echo -a *** DuckHunt Auto-Reply Script Loaded (v2.7)
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
