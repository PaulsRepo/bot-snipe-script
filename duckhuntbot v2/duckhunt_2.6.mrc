; mIRC DuckHunt Auto-Reply Script v2.6
; LIMITED TO CHANNEL: #url
; CHANGELOG:
; - v2.4: Fix buy-back not triggering - confiscation is in the missed-and-hit message
; - v2.5: New duck types (Ninja, Boss, Decoy, Flock), befriend toggle, soaked handler
; - v2.6: Fixes from log analysis 2026-02-22 to 2026-02-25:
;   BUG1: !reload infinite loop - "You're out of ammo!" matched *out of ammo* and
;         re-triggered !reload. Added guard: only reload if duck.active or not mid-recovery.
;         Also changed out-of-ammo detection to only react during active combat.
;         Root fix: "You're out of ammo!" (no duck) vs "You're out of ammo! Use !reload"
;         are different messages - guard on duck.active before sending !reload.
;   BUG2: False-positive BEFRIEND SUCCESSFUL - duckstats contains "0 befriended",
;         matching *befriended*. Fixed by requiring $nick == DuckHunt AND $me isin $1-
;         AND checking that it's NOT a stats/duckstats line (no "shot |" pattern).
;   BUG3: INSURANCE PROTECTED triggered confiscation handler - "missed and hit...
;         [INSURANCE PROTECTED]" matched *missed and hit*. Fixed: only treat as
;         confiscation if [GUN CONFISCATED] is also in the message.
;   BUG4: Boss duck spawn not detected - message has no QUACK/flap. Added dedicated
;         boss spawn pattern: *BOSS DUCK*appeared* / *A BOSS DUCK*
;   BUG5: Flock spawn not detected - "A flock of N ducks has landed!" has no QUACK.
;         Added dedicated flock spawn pattern.
;   BUG6: Ninja escape not detected - "drops a smoke bomb and vanishes! *poof*"
;         Added to escape patterns.
;   BUG7: Swift duck escape not detected - "The swift duck darts away". Added pattern.
;   BUG8: New hit message format - "You hit the DUCK for 1 damage! It has N HP left."
;         Old code only matched "HP remaining" and "shot the duck". Added handler for
;         new "HP left" format, including 0 HP = kill detection.
;   BUG9: Shop buy syntax - bot uses !shop <id>, not !shop buy <id>. Reverted all
;         internal shop calls to !shop <id>.
;   BUG10: Purchase handler used inc blindly - now parses confirmed count from bot msg.
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

  ; BUG4/BUG5 FIX: Boss and Flock have unique spawn messages with no QUACK.
  ; Handle them BEFORE the QUACK block so they don't fall through.

  ; --- BOSS DUCK SPAWN ---
  if (*BOSS DUCK*appeared* iswm $1-) || (*A BOSS DUCK* iswm $1-) || (*boss duck*HP* iswm $1-) {
    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off

    set %duckhunt.duck.type boss
    var %bosshp = $regsubex($1-, /.*with (\d+) HP.*/i, \1)
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

  ; --- FLOCK SPAWN ---
  elseif (*flock of*ducks*landed* iswm $1-) || (*A flock of* iswm $1-) {
    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off

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

    ; Fire count+2 shots to cover all ducks plus safety margin
    var %shots = $calc(%duckhunt.duck.flock.count + 2)
    var %i = 1
    while (%i <= %shots) {
      .timer.duckhunt.shoot $+ %i 1 %i msg #url !bang
      inc %i
    }
  }

  ; --- QUACK/FLAP SPAWNS (Normal, Golden, Fast, Ninja, Decoy) ---
  elseif (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*waddles in* iswm $1-) || (*sneaks in* iswm $1-) {

    ; Clear all state from previous duck
    set %duckhunt.pending.retry 0
    set %duckhunt.duck.flock 0
    set %duckhunt.duck.flock.count 0
    .timer.duckhunt.shoot* off
    .timer.duckhunt.continue off
    .timer.duckhunt.retry off
    .timer.duckhunt.resume off
    .timer.duckhunt.bef off

    ; DECOY first - shooting it = instant confiscation
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

    ; Golden
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

    ; Ninja - 1 HP but dodge; always retry on miss
    elseif (*ninja* iswm $1-) {
      set %duckhunt.duck.type ninja
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] NINJA DUCK SPAWNED - will always retry on dodge
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }

    ; Fast
    elseif (*fast* iswm $1-) || (*speedy* iswm $1-) {
      set %duckhunt.duck.type fast
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] FAST DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }

    ; Normal (fallback)
    else {
      set %duckhunt.duck.type normal
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [#url] DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg #url !bang
    }
  }

  ; ----------------------------------------------------------
  ; DUCK ESCAPE / DISAPPEARED
  ; BUG6/BUG7 FIX: Added ninja smoke bomb and swift duck patterns
  ; ----------------------------------------------------------
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) || (*swims away* iswm $1-) || (*retreats* iswm $1-) || (*smoke bomb and vanishes* iswm $1-) || (*darts away* iswm $1-) || (*takes flight* iswm $1-) || (*disappears into the clouds* iswm $1-) || (*waddles away* iswm $1-) || (*flap*The duck has escaped* iswm $1-) || (*duck flies away* iswm $1-) || (*living another day* iswm $1-) || (*disappears into the distance* iswm $1-) {
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
  ; Format: "🎒 Inventory: Magazine x10 (#2) | Buy Gun Back x2 (#7)"
  ; ----------------------------------------------------------
  if (*Inventory:* iswm $1-) && (*Buy Gun Back* iswm $1-) {
    var %bgbcount = $regsubex($1-, /.*Buy Gun Back x(\d+).*/i, \1)
    if (%bgbcount isnum) {
      set %duckhunt.has.buyback %bgbcount
      echo -a *** [#url] Inventory: Buy Gun Back x $+ %bgbcount
    }
  }

  ; Inventory with no Buy Gun Back - clear counter
  if (*Inventory:* iswm $1-) && (*Buy Gun Back* !iswm $1-) {
    set %duckhunt.has.buyback 0
    echo -a *** [#url] Inventory: No Buy Gun Back
  }

  ; duckstats inventory parse (user may still run !duckstats manually)
  ; Format: "... | Items: Magazine x9, Buy Gun Back x2 | Effects:..."
  if ($me isin $1-) && (*Items:* iswm $1-) && (*shot* iswm $1-) {
    var %itemstr = $regsubex($1-, /.*Items: ([^\|]+).*/i, \1)
    if (Buy Gun Back isin %itemstr) {
      var %bgbfromstats = $regsubex(%itemstr, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbfromstats isnum) {
        set %duckhunt.has.buyback %bgbfromstats
        echo -a *** [#url] duckstats inventory: Buy Gun Back x $+ %bgbfromstats
      }
      else {
        set %duckhunt.has.buyback 1
        echo -a *** [#url] duckstats inventory: Buy Gun Back x1
      }
    }
    else {
      set %duckhunt.has.buyback 0
      echo -a *** [#url] duckstats inventory: No Buy Gun Back
    }
  }

  ; ----------------------------------------------------------
  ; PURCHASE CONFIRMATIONS
  ; BUG10 FIX: Parse confirmed count from bot message instead of blind inc
  ; Bot says: "Stored in inventory (x3)" - use that number
  ; ----------------------------------------------------------
  if (*purchased Buy Gun Back* iswm $1-) || (*purchased*Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      var %newcount = $regsubex($1-, /.*\(x(\d+)\).*/i, \1)
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
      ; BUG1 PARTIAL: Set recovering flag so !reload response doesn't loop
      .timer.duckhunt.reloadafter 1 1 msg #url !reload
      ; Resume if duck still active - wait for reload to complete first (handled in reload handler)
    }
  }

  ; ----------------------------------------------------------
  ; BEFRIEND RESULTS
  ; BUG2 FIX: Require that the message doesn't contain stats markers like "shot |"
  ;           to avoid false-positives from "0 befriended" in duckstats
  ; ----------------------------------------------------------
  if ($me isin $1-) {
    if (*befriended* iswm $1-) && (*shot |* !iswm $1-) && (*0 befriended* !iswm $1-) {
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
  ; SHOT RESULTS (messages mentioning our nick)
  ; ----------------------------------------------------------
  if ($me isin $1-) {

    ; -------------------------------------------------------
    ; Duck killed (explicit kill text)
    ; -------------------------------------------------------
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

    ; -------------------------------------------------------
    ; BUG8 FIX: New hit format "hit the DUCK for 1 damage! It has N HP left."
    ; Covers both 0 HP (kill) and N HP (continue shooting)
    ; -------------------------------------------------------
    elseif (*hit*for*damage* iswm $1-) && (*HP left* iswm $1-) {
      var %hpleft = $regsubex($1-, /.*It has (\d+) HP left.*/i, \1)
      if (%hpleft isnum) {
        if (%hpleft == 0) {
          ; 0 HP = killed
          echo -a *** [#url] DUCK KILLED (0 HP left)
          set %duckhunt.duck.active 0
          set %duckhunt.duck.hp 0
          set %duckhunt.duck.flock 0
          set %duckhunt.pending.retry 0
          .timer.duckhunt.shoot* off
          .timer.duckhunt.continue off
          .timer.duckhunt.retry off
          .timer.duckhunt.resume off
        }
        else {
          ; HP > 0 = hit, keep shooting
          set %duckhunt.duck.hp %hpleft
          set %duckhunt.pending.retry 0
          echo -a *** [#url] HIT! Duck HP: %hpleft (new format)
          if (%duckhunt.duck.active == 1) {
            .timer.duckhunt.continue 1 1 msg #url !bang
          }
        }
      }
    }

    ; -------------------------------------------------------
    ; HP remaining (old format) - continue shooting
    ; -------------------------------------------------------
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

    ; -------------------------------------------------------
    ; One-shot kill (old format - "shot the duck")
    ; -------------------------------------------------------
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

    ; -------------------------------------------------------
    ; Flock: partial kill, others remain
    ; -------------------------------------------------------
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

    ; -------------------------------------------------------
    ; Dodge (ninja)
    ; -------------------------------------------------------
    elseif (*dodged* iswm $1-) || (*evaded* iswm $1-) {
      echo -a *** [#url] DODGE! Retrying...
      if (%duckhunt.duck.active == 1) {
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg #url !bang
      }
    }

    ; -------------------------------------------------------
    ; Normal miss (NOT friendly fire)
    ; -------------------------------------------------------
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) && (*missed and hit* !iswm $1-) {
      echo -a *** [#url] MISSED THE DUCK

      ; Ninja: always retry
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

    ; -------------------------------------------------------
    ; BUG3 FIX: Missed and hit someone
    ; ONLY treat as confiscation if [GUN CONFISCATED] is in the same message.
    ; [INSURANCE PROTECTED] = no confiscation, keep shooting.
    ; -------------------------------------------------------
    elseif *missed and hit* iswm $1- {
      if (*GUN CONFISCATED* iswm $1-) {
        ; Gun actually confiscated
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
        ; Insurance protected - no confiscation, duck is still alive, keep shooting
        echo -a *** [#url] FRIENDLY FIRE but INSURANCE PROTECTED - continuing
        if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
          .timer.duckhunt.continue 1 1 msg #url !bang
        }
      }
      else {
        ; Unknown missed-and-hit variant - assume confiscation to be safe
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

    ; -------------------------------------------------------
    ; BUG1 FIX: Out of ammo
    ; Only auto-reload if we are actively hunting a duck.
    ; "You're out of ammo!" (no duck) must NOT trigger reload loop.
    ; The bot sends "Use !reload" only during active shooting.
    ; Guard: duck.active == 1 OR the message explicitly says "Use !reload".
    ; Also gate on recovering==0 so gun-recovery !reload doesn't re-trigger itself.
    ; -------------------------------------------------------
    elseif (*out of ammo* iswm $1-) && (*Use !reload* iswm $1-) && (%duckhunt.recovering == 0) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.duck.active == 1) && (%duckhunt.recovering == 0) {
      echo -a *** [#url] OUT OF AMMO - RELOADING
      msg #url !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.recovering == 1) {
      ; We're recovering from confiscation and have no magazines - stop the loop
      echo -a *** [#url] Out of ammo during recovery (no spare mags) - stopping
      set %duckhunt.recovering 0
    }

    ; -------------------------------------------------------
    ; Gun confiscated via standalone message (fallback for edge cases)
    ; -------------------------------------------------------
    elseif (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-) && (*INSURANCE* !iswm $1-)) {
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
        .timer.duckhunt.shopbuyback 1 1 msg #url !shop 7
      }
    }

    ; Gun not confiscated - suppress
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

    ; Shooting too fast - cooldown before retry
    elseif *trying to shoot too fast* iswm $1- {
      echo -a *** [#url] RATE LIMITED - waiting 2s before retry
      if (%duckhunt.duck.active == 1) {
        .timer.duckhunt.cooldown 1 2 msg #url !bang
      }
    }

    ; Soaked / wet clothes - buy Dry Clothes (ID 9)
    elseif (*soaked* iswm $1-) || (*wet clothes* iswm $1-) || (*cannot shoot* iswm $1-) || (*wringing wet* iswm $1-) {
      echo -a *** [#url] SOAKED - buying Dry Clothes to resume
      .timer.duckhunt.shoot* off
      .timer.duckhunt.dryclothes 1 2 msg #url !shop 9
    }

    ; No duck in area - stop everything
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
; BUG1 FIX: Clear recovering flag here so gun-recovery !reload
;           doesn't re-trigger the out-of-ammo loop.
; ============================================================
on *:TEXT:*New magazine loaded*:#url:{
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    echo -a *** [#url] MAGAZINE RELOADED
    set %duckhunt.ammo 6
    set %duckhunt.recovering 0

    ; Pending retry from a miss that ran out of ammo - fire immediately
    if (%duckhunt.pending.retry == 1) && (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Pending retry after reload - FIRING
      set %duckhunt.pending.retry 0
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
    ; Resume if duck still alive
    elseif (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [#url] Duck still active (HP: %duckhunt.duck.hp $+ ) - RESUMING
      .timer.duckhunt.afterreload 1 1 msg #url !bang
    }
    ; Gun was just recovered and duck is still active - resume shooting
    elseif (%duckhunt.gun.confiscated == 0) && (%duckhunt.duck.active == 1) {
      echo -a *** [#url] Gun recovered and duck active - resuming
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
echo -a *** DuckHunt Auto-Reply Script Loaded (v2.6)
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
