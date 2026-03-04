; mIRC DuckHunt Auto-Reply Script v2.9
; ============================================================
; CHANGELOG:
; v2.4  Confiscation fix - [GUN CONFISCATED] is in the missed-and-hit message itself
; v2.5  New duck types (Ninja, Boss, Decoy, Flock), befriend toggle, soaked handler
; v2.6  Reload loop, false befriend, insurance confiscation, boss/flock spawn detection,
;       ninja/swift escape patterns, new hit format, shop syntax, purchase counter sync
; v2.7  Flock continuation (outside $me block), flock 0HP stop bug, duckstats regex,
;       rate-limit cooldown 2s->3s, decoy *CLANG* confiscation message
; v2.8  Multi-channel support via %duckhunt.chan, watchdog for silent-disabled state
; v2.9  Fix case-sensitivity regression introduced in v2.8: switching the on:TEXT
;       event from "#url" to "*" with an in-script $chan check meant the comparison
;       was case-sensitive. IRC channel names are case-insensitive so #URL and #url
;       are the same channel, but mIRC's != string operator is not. Ducks were
;       silently missed whenever the server sent the channel name in a different case.
;       Fix: keep on:TEXT:*:*: (fires everywhere) but compare with $lower() on both
;       sides so "#URL" == "#url" correctly. Watchdog also updated to use same check.
; ============================================================

; ============================================================
; CHANNEL CONFIGURATION
; ============================================================
; To change which channel the script operates in, edit the ONE
; line below - everything else uses %duckhunt.chan automatically.
; Do NOT include quotes. Example values: #url  #hunting  #ducks
;
alias duckhunt.setchan {
  set %duckhunt.chan $1
  echo -a *** DuckHunt channel set to: %duckhunt.chan
  echo -a *** Reload the script or run /duckhunt on to apply.
}
; ============================================================
; The channel is set when you run /duckhunt on (see alias below).
; Change #url on the next line to your desired channel:
; ============================================================

; ============================================================
; MAIN CONTROL ALIAS
; ============================================================
alias duckhunt {
  if ($1 == on) {
    ; --------------------------------------------------------
    ; CHANNEL CONFIG - change #url here to use a different channel
    ; --------------------------------------------------------
    set %duckhunt.chan #url, #3nd3r
    ; --------------------------------------------------------
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
    echo -a *** DuckHunt Auto-Reply: ENABLED (Channel: %duckhunt.chan only)
    echo -a *** Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a *** Befriend decoys: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
    .timer.duckhunt.checkinv 1 2 msg %duckhunt.chan !inv
    .timer.duckhunt.daily 1 4 msg %duckhunt.chan !daily
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
    echo -a Channel: $iif(%duckhunt.chan != $null, %duckhunt.chan, not set - run /duckhunt on)
    echo -a Buy Gun Back in inventory: $iif(%duckhunt.has.buyback > 0, YES ( $+ %duckhunt.has.buyback $+ ), NO)
    echo -a Retry on miss: $iif(%duckhunt.retry.on.miss == 1, ENABLED, DISABLED)
    echo -a Befriend decoys: $iif(%duckhunt.befriend.enabled == 1, ENABLED, DISABLED)
    echo -a Gun status: $iif(%duckhunt.gun.confiscated == 1, CONFISCATED, OK)
    echo -a Active duck: $iif(%duckhunt.duck.active == 1, YES (Type: %duckhunt.duck.type - HP: %duckhunt.duck.hp $+ ), NO)
  }
}

; ============================================================
; MAIN MESSAGE HANDLER
; Listens on ALL channels (*) then checks against %duckhunt.chan
; This is required because mIRC on:TEXT channel filters don't
; accept variables - the check is done manually inside instead.
; ============================================================
on *:TEXT:*:*:{
  ; --------------------------------------------------------
  ; CHANNEL FILTER - case-insensitive match
  ; We use $lower() on both sides because IRC channel names are
  ; case-insensitive (#URL and #url are the same channel) but
  ; mIRC's != string operator is case-sensitive. Without $lower()
  ; the check silently fails whenever the server sends the channel
  ; name in a different case, and every duck gets missed.
  ; To change channel: edit the 'set %duckhunt.chan' line above.
  ; --------------------------------------------------------
  if ($lower($chan) != $lower(%duckhunt.chan)) return

  ; Only listen to the DuckHunt bot
  if ($nick != DuckHunt) && ($nick != Quackbot) return

  ; ----------------------------------------------------------
  ; WATCHDOG: If DuckHunt is talking but we're disabled, warn visibly.
  ; This catches the "silent disabled" state seen in the logs where
  ; ducks were missed with no echo and no obvious cause.
  ; ----------------------------------------------------------
  if (%duckhunt.enabled != 1) {
    if (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*flock of*ducks* iswm $1-) || (*BOSS DUCK* iswm $1-) {
      echo -a *** [%duckhunt.chan] WARNING: DUCK SPAWNED BUT SCRIPT IS DISABLED - run /duckhunt on
    }
    return
  }

  ; ----------------------------------------------------------
  ; BUG-A FIX: FLOCK REMAINING COUNT
  ; "🦆 N duck(s) still in the flock!" has no nick prefix so it
  ; must be handled OUTSIDE the $me isin $1- block below.
  ; ----------------------------------------------------------
  if (*duck(s) still in the flock* iswm $1-) || (*still in the flock* iswm $1-) {
    if (%duckhunt.duck.type == flock) && (%duckhunt.duck.active == 1) {
      var %remaining = $regsubex($1-, /(\d+) duck.s. still/i, \1)
      if (%remaining isnum) && (%remaining > 0) {
        set %duckhunt.duck.hp %remaining
        echo -a *** [%duckhunt.chan] FLOCK: %remaining duck(s) remaining - continuing fire
        .timer.duckhunt.flockcontinue 1 1 msg %duckhunt.chan !bang
      }
      else {
        echo -a *** [%duckhunt.chan] FLOCK: ducks remaining (count unknown) - continuing
        .timer.duckhunt.flockcontinue 1 1 msg %duckhunt.chan !bang
      }
    }
    return
  }

  ; ----------------------------------------------------------
  ; DUCK SPAWN DETECTION
  ; ----------------------------------------------------------

  ; --- BOSS DUCK SPAWN (no QUACK in message) ---
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
    echo -a *** [%duckhunt.chan] BOSS DUCK SPAWNED (HP: %duckhunt.duck.hp $+ ) - SUSTAINED FIRE
    .timer.duckhunt.shoot1 1 1 msg %duckhunt.chan !bang
    .timer.duckhunt.shoot2 1 2 msg %duckhunt.chan !bang
    .timer.duckhunt.shoot3 1 3 msg %duckhunt.chan !bang
    .timer.duckhunt.shoot4 1 4 msg %duckhunt.chan !bang
  }

  ; --- FLOCK SPAWN (no QUACK in message) ---
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
      echo -a *** [%duckhunt.chan] FLOCK OF %flockcount DUCKS - RAPID FIRE
    }
    else {
      set %duckhunt.duck.flock.count 2
      set %duckhunt.duck.hp 2
      echo -a *** [%duckhunt.chan] FLOCK SPAWNED (count unknown, assuming 2) - RAPID FIRE
    }

    var %shots = $calc(%duckhunt.duck.flock.count + 2)
    var %i = 1
    while (%i <= %shots) {
      .timer.duckhunt.shoot $+ %i 1 %i msg %duckhunt.chan !bang
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

    if (*decoy* iswm $1-) {
      set %duckhunt.duck.type decoy
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [%duckhunt.chan] DECOY DUCK SPAWNED - DO NOT SHOOT!
      if (%duckhunt.befriend.enabled == 1) {
        echo -a *** [%duckhunt.chan] Befriending decoy duck...
        .timer.duckhunt.bef 1 1 msg %duckhunt.chan !bef
      }
      else {
        echo -a *** [%duckhunt.chan] Befriend disabled - ignoring decoy duck
        set %duckhunt.duck.active 0
      }
    }
    elseif (*golden* iswm $1-) || (*glimmer* iswm $1-) {
      set %duckhunt.duck.type golden
      set %duckhunt.duck.hp 4
      set %duckhunt.duck.active 1
      echo -a *** [%duckhunt.chan] GOLDEN DUCK SPAWNED - RAPID FIRE (4 HP)
      .timer.duckhunt.shoot1 1 1 msg %duckhunt.chan !bang
      .timer.duckhunt.shoot2 1 2 msg %duckhunt.chan !bang
      .timer.duckhunt.shoot3 1 3 msg %duckhunt.chan !bang
      .timer.duckhunt.shoot4 1 4 msg %duckhunt.chan !bang
    }
    elseif (*ninja* iswm $1-) {
      set %duckhunt.duck.type ninja
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [%duckhunt.chan] NINJA DUCK SPAWNED - always retrying on dodge
      .timer.duckhunt.shoot1 1 1 msg %duckhunt.chan !bang
    }
    elseif (*fast* iswm $1-) || (*speedy* iswm $1-) {
      set %duckhunt.duck.type fast
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [%duckhunt.chan] FAST DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg %duckhunt.chan !bang
    }
    else {
      set %duckhunt.duck.type normal
      set %duckhunt.duck.hp 1
      set %duckhunt.duck.active 1
      echo -a *** [%duckhunt.chan] DUCK SPAWNED
      .timer.duckhunt.shoot1 1 1 msg %duckhunt.chan !bang
    }
  }

  ; ----------------------------------------------------------
  ; DUCK ESCAPED / DISAPPEARED
  ; ----------------------------------------------------------
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) || (*swims away* iswm $1-) || (*retreats* iswm $1-) || (*smoke bomb and vanishes* iswm $1-) || (*darts away* iswm $1-) || (*takes flight* iswm $1-) || (*disappears into the clouds* iswm $1-) || (*waddles away* iswm $1-) || (*flap*The duck has escaped* iswm $1-) || (*duck flies away* iswm $1-) || (*living another day* iswm $1-) || (*disappears into the distance* iswm $1-) || (*flaps away* iswm $1-) {
    echo -a *** [%duckhunt.chan] DUCK ESCAPED
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
  ; ----------------------------------------------------------
  if (*Inventory:* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      var %bgbcount = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbcount isnum) {
        set %duckhunt.has.buyback %bgbcount
        echo -a *** [%duckhunt.chan] Inventory: Buy Gun Back x $+ %bgbcount
      }
    }
    else {
      set %duckhunt.has.buyback 0
      echo -a *** [%duckhunt.chan] Inventory: No Buy Gun Back
    }
  }

  ; duckstats inventory parse - direct scan on full line
  if ($me isin $1-) && (*Items:* iswm $1-) && (*shot* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      var %bgbfromstats = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbfromstats isnum) {
        set %duckhunt.has.buyback %bgbfromstats
        echo -a *** [%duckhunt.chan] duckstats inventory: Buy Gun Back x $+ %bgbfromstats
      }
    }
    else {
      set %duckhunt.has.buyback 0
      echo -a *** [%duckhunt.chan] duckstats inventory: No Buy Gun Back
    }
  }

  ; ----------------------------------------------------------
  ; PURCHASE CONFIRMATIONS
  ; ----------------------------------------------------------
  if (*purchased Buy Gun Back* iswm $1-) || (*purchased*Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      var %newcount = $regsubex($1-, /\(x(\d+)\)/i, \1)
      if (%newcount isnum) {
        set %duckhunt.has.buyback %newcount
        echo -a *** [%duckhunt.chan] PURCHASED Buy Gun Back (confirmed x $+ %newcount $+ ) - stored
      }
      else {
        inc %duckhunt.has.buyback
        echo -a *** [%duckhunt.chan] PURCHASED Buy Gun Back (now have: %duckhunt.has.buyback $+ ) - stored
      }
    }
  }

  if (*purchased*Hunter* iswm $1-) && (*Insurance* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [%duckhunt.chan] Hunter's Insurance active - friendly fire protected for 24h
    }
  }

  ; ----------------------------------------------------------
  ; GUN RETURNED after Buy Gun Back
  ; ----------------------------------------------------------
  if (*gun has been returned* iswm $1-) || (*Your gun has been returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [%duckhunt.chan] GUN RECOVERED!
      set %duckhunt.gun.confiscated 0
      set %duckhunt.recovering 1
      if (%duckhunt.has.buyback > 0) dec %duckhunt.has.buyback
      .timer.duckhunt.reloadafter 1 1 msg %duckhunt.chan !reload
    }
  }

  ; ----------------------------------------------------------
  ; BEFRIEND RESULTS
  ; Exclude duckstats lines that contain "0 befriended"
  ; ----------------------------------------------------------
  if ($me isin $1-) {
    if (*befriended* iswm $1-) && (*0 befriended* !iswm $1-) && (*shot* !iswm $1-) && (*Items:* !iswm $1-) {
      echo -a *** [%duckhunt.chan] BEFRIEND SUCCESSFUL
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.bef off
      .timer.duckhunt.shoot* off
    }
    elseif (*made friends* iswm $1-) || (*waddled over* iswm $1-) || (*accept your friendship* iswm $1-) {
      echo -a *** [%duckhunt.chan] BEFRIEND SUCCESSFUL
      set %duckhunt.duck.active 0
      set %duckhunt.duck.hp 0
      .timer.duckhunt.bef off
      .timer.duckhunt.shoot* off
    }
    elseif (*failed to befriend* iswm $1-) || (*ran away* iswm $1-) {
      echo -a *** [%duckhunt.chan] BEFRIEND FAILED
      if (%duckhunt.duck.type == decoy) {
        echo -a *** [%duckhunt.chan] Decoy - not retrying to avoid confiscation risk
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
      echo -a *** [%duckhunt.chan] DUCK KILLED - STOPPING
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

    ; New hit format: "hit the DUCK for N damage! It has N HP left."
    ; For flock: 0 HP = one duck down, DON'T stop - flock remaining handler drives continuation
    ; For all others: 0 HP = duck dead, stop
    elseif (*hit*for*damage* iswm $1-) && (*HP left* iswm $1-) {
      var %hpleft = $regsubex($1-, /It has (\d+) HP left/i, \1)
      if (%hpleft isnum) {
        if (%hpleft == 0) {
          if (%duckhunt.duck.type == flock) {
            echo -a *** [%duckhunt.chan] FLOCK DUCK DOWN (0 HP) - waiting for remaining count
          }
          else {
            echo -a *** [%duckhunt.chan] DUCK KILLED (0 HP left)
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
          set %duckhunt.duck.hp %hpleft
          set %duckhunt.pending.retry 0
          echo -a *** [%duckhunt.chan] HIT! Duck HP: %hpleft
          if (%duckhunt.duck.active == 1) {
            .timer.duckhunt.continue 1 1 msg %duckhunt.chan !bang
          }
        }
      }
    }

    ; HP remaining (old format)
    elseif *HP remaining* iswm $1- {
      var %hp = $regsubex($1-, /\[(\d+) HP remaining\]/i, \1)
      set %duckhunt.duck.hp %hp
      set %duckhunt.pending.retry 0
      echo -a *** [%duckhunt.chan] HIT! Duck HP: %hp
      if (%hp > 0) && (%duckhunt.duck.active == 1) {
        .timer.duckhunt.continue 1 1 msg %duckhunt.chan !bang
      }
      else {
        .timer.duckhunt.shoot* off
      }
    }

    ; One-shot kill (old "shot the duck" format)
    elseif (*shot*duck* iswm $1-) || (*shot*FAST* iswm $1-) || (*shot*GOLDEN* iswm $1-) || (*shot*NINJA* iswm $1-) || (*shot*BOSS* iswm $1-) || (*shot*FLOCK* iswm $1-) {
      echo -a *** [%duckhunt.chan] DUCK KILLED (one-shot)
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
      echo -a *** [%duckhunt.chan] DODGE! Retrying...
      if (%duckhunt.duck.active == 1) {
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg %duckhunt.chan !bang
      }
    }

    ; Normal miss (not friendly fire)
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) && (*missed and hit* !iswm $1-) {
      echo -a *** [%duckhunt.chan] MISSED THE DUCK
      if (%duckhunt.duck.type == ninja) && (%duckhunt.duck.active == 1) {
        echo -a *** [%duckhunt.chan] NINJA DUCK - always retrying
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg %duckhunt.chan !bang
      }
      elseif (%duckhunt.retry.on.miss == 1) && (%duckhunt.duck.active == 1) {
        echo -a *** [%duckhunt.chan] RETRYING (retry enabled)
        set %duckhunt.pending.retry 1
        .timer.duckhunt.retry 1 1 msg %duckhunt.chan !bang
      }
      else {
        echo -a *** [%duckhunt.chan] Not retrying (safer mode)
      }
    }

    ; Missed and hit someone - check for actual confiscation vs insurance protection
    elseif *missed and hit* iswm $1- {
      if (*GUN CONFISCATED* iswm $1-) {
        echo -a *** [%duckhunt.chan] MISSED AND HIT SOMEONE - GUN CONFISCATED
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
          echo -a *** [%duckhunt.chan] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
          .timer.duckhunt.usebuyback 1 1 msg %duckhunt.chan !use 7
        }
        else {
          echo -a *** [%duckhunt.chan] No Buy Gun Back - purchasing one
          .timer.duckhunt.shopbuyback 1 1 msg %duckhunt.chan !shop 7
        }
      }
      elseif (*INSURANCE PROTECTED* iswm $1-) || (*No penalties* iswm $1-) {
        echo -a *** [%duckhunt.chan] FRIENDLY FIRE - INSURANCE PROTECTED, continuing
        if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
          .timer.duckhunt.continue 1 1 msg %duckhunt.chan !bang
        }
      }
      else {
        echo -a *** [%duckhunt.chan] MISSED AND HIT - unknown result, treating as confiscated
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
          echo -a *** [%duckhunt.chan] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
          .timer.duckhunt.usebuyback 1 1 msg %duckhunt.chan !use 7
        }
        else {
          echo -a *** [%duckhunt.chan] No Buy Gun Back - purchasing one
          .timer.duckhunt.shopbuyback 1 1 msg %duckhunt.chan !shop 7
        }
      }
    }

    ; Out of ammo - only reload if actively hunting or message says to
    elseif (*out of ammo* iswm $1-) && (*Use !reload* iswm $1-) && (%duckhunt.recovering == 0) {
      echo -a *** [%duckhunt.chan] OUT OF AMMO - RELOADING
      msg %duckhunt.chan !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.duck.active == 1) && (%duckhunt.recovering == 0) {
      echo -a *** [%duckhunt.chan] OUT OF AMMO - RELOADING
      msg %duckhunt.chan !reload
    }
    elseif (*out of ammo* iswm $1-) && (%duckhunt.recovering == 1) {
      echo -a *** [%duckhunt.chan] Out of ammo during recovery (no spare mags) - stopping reload loop
      set %duckhunt.recovering 0
    }

    ; Decoy/wooden decoy confiscation + standalone confiscation fallback
    elseif (*CLANG* iswm $1-) || (*wooden decoy* iswm $1-) || (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-) && (*INSURANCE* !iswm $1-)) {
      echo -a *** [%duckhunt.chan] GUN CONFISCATED!
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
        echo -a *** [%duckhunt.chan] Using Buy Gun Back from inventory ( $+ %duckhunt.has.buyback available)
        .timer.duckhunt.usebuyback 1 1 msg %duckhunt.chan !use 7
      }
      else {
        echo -a *** [%duckhunt.chan] No Buy Gun Back - purchasing one
        .timer.duckhunt.shopbuyback 1 1 msg %duckhunt.chan !shop 7
      }
    }

    ; Gun is fine
    elseif *gun is not confiscated* iswm $1- {
      echo -a *** [%duckhunt.chan] Gun is OK
    }

    ; Gun jammed
    elseif *jammed* iswm $1- {
      echo -a *** [%duckhunt.chan] GUN JAMMED - RETRYING
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.jamretry 1 1 msg %duckhunt.chan !bang
      }
    }

    ; Rate limited - 3s cooldown
    elseif (*trying to shoot too fast* iswm $1-) || (*doing that too quickly* iswm $1-) {
      echo -a *** [%duckhunt.chan] RATE LIMITED - waiting 3s before retry
      if (%duckhunt.duck.active == 1) {
        .timer.duckhunt.cooldown 1 3 msg %duckhunt.chan !bang
      }
    }

    ; Soaked / wet clothes
    elseif (*soaked* iswm $1-) || (*wet clothes* iswm $1-) || (*cannot shoot* iswm $1-) || (*wringing wet* iswm $1-) {
      echo -a *** [%duckhunt.chan] SOAKED - buying Dry Clothes to resume
      .timer.duckhunt.shoot* off
      .timer.duckhunt.dryclothes 1 2 msg %duckhunt.chan !shop 9
    }

    ; No duck in area
    elseif *no duck in the area* iswm $1- {
      echo -a *** [%duckhunt.chan] NO DUCK - STOPPING
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

    ; Daily bonus responses
    elseif (*already claimed* iswm $1-) && (*daily* iswm $1-) {
      echo -a *** [%duckhunt.chan] Daily XP already claimed today
    }
    elseif (*daily* iswm $1-) && ((*bonus* iswm $1-) || (*XP* iswm $1-)) && (*claimed* iswm $1-) {
      echo -a *** [%duckhunt.chan] Daily XP bonus claimed!
    }
  }
}

; ============================================================
; RELOAD CONFIRMATION
; ============================================================
on *:TEXT:*New magazine loaded*:*:{
  if ($lower($chan) != $lower(%duckhunt.chan)) return
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    echo -a *** [%duckhunt.chan] MAGAZINE RELOADED
    set %duckhunt.ammo 6
    set %duckhunt.recovering 0

    if (%duckhunt.pending.retry == 1) && (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [%duckhunt.chan] Pending retry after reload - FIRING
      set %duckhunt.pending.retry 0
      .timer.duckhunt.afterreload 1 1 msg %duckhunt.chan !bang
    }
    elseif (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
      echo -a *** [%duckhunt.chan] Duck still active (HP: %duckhunt.duck.hp $+ ) - RESUMING
      .timer.duckhunt.afterreload 1 1 msg %duckhunt.chan !bang
    }
  }
}

; ============================================================
; DRY CLOTHES CONFIRMATION
; ============================================================
on *:TEXT:*dried*:*:{
  if ($lower($chan) != $lower(%duckhunt.chan)) return
  if (%duckhunt.enabled != 1) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  if ($me isin $1-) {
    if (*dry* iswm $1-) || (*dried off* iswm $1-) {
      echo -a *** [%duckhunt.chan] DRY CLOTHES USED - can shoot again
      if (%duckhunt.duck.active == 1) && (%duckhunt.duck.hp > 0) {
        .timer.duckhunt.afterdry 1 1 msg %duckhunt.chan !bang
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

on *:PART:*:{
  if ($nick == $me) && ($lower($chan) == $lower(%duckhunt.chan)) {
    .timer.duckhunt.* off
    echo -a *** DuckHunt: Timers cleared on leaving %duckhunt.chan
  }
}

; ============================================================
; MANUAL ALIASES
; ============================================================
alias duckhunt.check {
  msg %duckhunt.chan !inv
}
alias duckhunt.daily {
  msg %duckhunt.chan !daily
}
alias duckhunt.effects {
  msg %duckhunt.chan !effects
}

; ============================================================
; LOAD MESSAGE
; ============================================================
echo -a *** DuckHunt Auto-Reply Script Loaded (v2.9)
echo -a *** To change channel: edit the 'set %duckhunt.chan' line in the duckhunt alias
echo -a *** Duck types: Normal, Golden, Fast, Ninja, Boss, Decoy, Flock
echo -a *** Type: /duckhunt on              to enable
echo -a *** Type: /duckhunt off             to disable
echo -a *** Type: /duckhunt retry on|off    to toggle retry on miss (risky)
echo -a *** Type: /duckhunt befriend on|off to toggle befriend for decoy ducks
echo -a *** Type: /duckhunt                 to check full status
echo -a *** Type: /duckhunt.check           to check inventory (!inv)
echo -a *** Type: /duckhunt.daily           to manually claim daily XP
echo -a *** Type: /duckhunt.effects         to check active buffs/debuffs
