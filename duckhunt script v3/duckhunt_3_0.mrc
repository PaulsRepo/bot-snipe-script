; mIRC DuckHunt Auto-Reply Script v3.0
; ============================================================
; CHANGELOG:
; v2.4  Confiscation fix - [GUN CONFISCATED] is in the missed-and-hit message itself
; v2.5  New duck types (Ninja, Boss, Decoy, Flock), befriend toggle, soaked handler
; v2.6  Reload loop, false befriend, insurance confiscation, boss/flock spawn detection,
;       ninja/swift escape patterns, new hit format, shop syntax, purchase counter sync
; v2.7  Flock continuation (outside $me block), flock 0HP stop bug, duckstats regex,
;       rate-limit cooldown 2s->3s, decoy *CLANG* confiscation message
; v2.8  Multi-channel support via %duckhunt.chan, watchdog for silent-disabled state
; v2.9  Fix case-sensitivity regression: $lower() on both sides of channel comparisons
;       so #URL and #url are treated identically throughout.
; v3.0  MULTICHANNEL REWRITE (Option B - per-channel state):
;       - %duckhunt.chan (single value) replaced by %duckhunt.channels ($addtok list).
;       - All $lower($chan) != $lower(%duckhunt.chan) checks replaced with $istok().
;       - State variables keyed per channel slug, e.g.:
;           %duckhunt.url.duck.active   %duckhunt.hunting.duck.active
;           %duckhunt.url.duck.hp       %duckhunt.hunting.duck.hp
;         A duck in #hunting never stomps state for a duck in #url.
;       - /duckhunt on #chan1 #chan2 ... accepts one or more channels at startup.
;         Running /duckhunt on again with a new list replaces the old one.
;         Running /duckhunt on with no args re-enables using the existing list.
;       - /duckhunt addchan / removechan for live list management without full restart.
;       - /duckhunt off cleans up all per-channel state and timers.
;       - Per-channel timer names include the slug, e.g. timer.duckhunt.url.shoot1,
;         so rapid fire in #url never cancels shots queued for #hunting.
;       - retry / befriend toggles accept optional [#chan] argument:
;           /duckhunt retry on          -> all channels
;           /duckhunt retry #url on     -> #url only
;       - /duckhunt prints a full per-channel status breakdown.
;       - Manual aliases (duckhunt.check, duckhunt.daily, duckhunt.effects) accept
;         optional #chan; default to first channel in list if omitted.
; ============================================================

; ============================================================
; INTERNAL: channel slug  (#url -> url, #my-chan -> my-chan)
; Used to build variable and timer names.
; ============================================================
alias duckhunt.slug {
  return $lower($mid($1, 2))
}

; ============================================================
; INTERNAL: is this channel actively tracked?
; ============================================================
alias duckhunt.active {
  if (%duckhunt.enabled != 1) return 0
  return $istok(%duckhunt.channels, $lower($1), 32)
}

; ============================================================
; INTERNAL: initialise per-channel state variables
; ============================================================
alias duckhunt.initchan {
  var %c = $lower($1)
  var %s = $duckhunt.slug(%c)
  set %duckhunt. $+ %s $+ .duck.active      0
  set %duckhunt. $+ %s $+ .duck.hp          0
  set %duckhunt. $+ %s $+ .duck.type        normal
  set %duckhunt. $+ %s $+ .duck.flock       0
  set %duckhunt. $+ %s $+ .duck.flock.count 0
  set %duckhunt. $+ %s $+ .ammo             6
  set %duckhunt. $+ %s $+ .has.buyback      0
  set %duckhunt. $+ %s $+ .gun.confiscated  0
  set %duckhunt. $+ %s $+ .retry.on.miss    0
  set %duckhunt. $+ %s $+ .pending.retry    0
  set %duckhunt. $+ %s $+ .befriend.enabled 1
  set %duckhunt. $+ %s $+ .recovering       0
}

; ============================================================
; INTERNAL: cancel all shoot/continue timers for a channel
; ============================================================
alias duckhunt.stopshoottimers {
  var %s = $duckhunt.slug($lower($1))
  .timer.duckhunt. $+ %s $+ .shoot* off
  .timer.duckhunt. $+ %s $+ .continue off
  .timer.duckhunt. $+ %s $+ .retry off
  .timer.duckhunt. $+ %s $+ .resume off
  .timer.duckhunt. $+ %s $+ .bef off
  .timer.duckhunt. $+ %s $+ .flockcontinue off
}

; ============================================================
; INTERNAL: cancel ALL timers for a channel
; ============================================================
alias duckhunt.stoptimers {
  var %s = $duckhunt.slug($lower($1))
  .timer.duckhunt. $+ %s $+ .* off
}

; ============================================================
; INTERNAL: reset duck state for a channel (kill/escape/no duck)
; ============================================================
alias duckhunt.clearduck {
  var %c = $lower($1)
  var %s = $duckhunt.slug(%c)
  set %duckhunt. $+ %s $+ .duck.active   0
  set %duckhunt. $+ %s $+ .duck.hp       0
  set %duckhunt. $+ %s $+ .duck.flock    0
  set %duckhunt. $+ %s $+ .pending.retry 0
  duckhunt.stopshoottimers %c
}

; ============================================================
; INTERNAL: handle gun confiscation for a channel
; ============================================================
alias duckhunt.confiscated {
  var %c = $lower($1)
  var %s = $duckhunt.slug(%c)
  echo -a *** [ $+ %c $+ ] GUN CONFISCATED!
  set %duckhunt. $+ %s $+ .gun.confiscated 1
  duckhunt.clearduck %c
  var %bb = $eval(%duckhunt. $+ %s $+ .has.buyback, 2)
  if (%bb > 0) {
    echo -a *** [ $+ %c $+ ] Using Buy Gun Back from inventory ( $+ %bb available)
    .timer.duckhunt. $+ %s $+ .usebuyback 1 1 msg %c !use 7
  }
  else {
    echo -a *** [ $+ %c $+ ] No Buy Gun Back - purchasing one
    .timer.duckhunt. $+ %s $+ .shopbuyback 1 1 msg %c !shop 7
  }
}

; ============================================================
; MAIN CONTROL ALIAS
; ============================================================
alias duckhunt {

  ; ---- ON ----
  if ($1 == on) {
    ; No channel args - re-enable using existing list
    if ($2 == $null) {
      set %duckhunt.enabled 1
      if (%duckhunt.channels != $null) {
        echo -a *** DuckHunt Auto-Reply v3.0: ENABLED
        echo -a *** Resuming with existing channel list: %duckhunt.channels
      }
      else {
        echo -a *** DuckHunt Auto-Reply v3.0: ENABLED (no channels tracked yet)
        echo -a *** Add channels with: /duckhunt on #chan1 [#chan2 ...]  or  /duckhunt addchan #chan
      }
      return
    }
    ; Channels supplied - replace existing list
    if (%duckhunt.channels != $null) {
      var %oi = 1
      var %ototal = $numtok(%duckhunt.channels, 32)
      while (%oi <= %ototal) {
        duckhunt.stoptimers $gettok(%duckhunt.channels, %oi, 32)
        inc %oi
      }
      unset %duckhunt.channels
    }
    set %duckhunt.enabled 1
    var %i = 2
    while (%i <= $0) {
      var %c = $lower($$(%i))
      %duckhunt.channels = $addtok(%duckhunt.channels, %c, 32)
      duckhunt.initchan %c
      echo -a *** DuckHunt: Tracking %c
      .timer.duckhunt. $+ $duckhunt.slug(%c) $+ .checkinv 1 2 msg %c !inv
      .timer.duckhunt. $+ $duckhunt.slug(%c) $+ .daily    1 4 msg %c !daily
      inc %i
    }
    echo -a *** DuckHunt Auto-Reply v3.0: ENABLED
    echo -a *** Channels: %duckhunt.channels
  }

  ; ---- OFF ----
  elseif ($1 == off) {
    var %i = 1
    var %total = $numtok(%duckhunt.channels, 32)
    while (%i <= %total) {
      var %c = $gettok(%duckhunt.channels, %i, 32)
      duckhunt.stoptimers %c
      unset %duckhunt. $+ $duckhunt.slug(%c) $+ .*
      inc %i
    }
    unset %duckhunt.enabled
    unset %duckhunt.channels
    echo -a *** DuckHunt Auto-Reply: DISABLED
  }

  ; ---- ADDCHAN ----
  elseif ($1 == addchan) {
    if ($2 == $null) { echo -a Usage: /duckhunt addchan #channelname | return }
    var %c = $lower($2)
    if ($istok(%duckhunt.channels, %c, 32)) {
      echo -a *** DuckHunt: %c is already tracked
      return
    }
    if (%duckhunt.enabled != 1) { set %duckhunt.enabled 1 }
    %duckhunt.channels = $addtok(%duckhunt.channels, %c, 32)
    duckhunt.initchan %c
    echo -a *** DuckHunt: Added %c  (tracking: %duckhunt.channels $+ )
    .timer.duckhunt. $+ $duckhunt.slug(%c) $+ .checkinv 1 2 msg %c !inv
    .timer.duckhunt. $+ $duckhunt.slug(%c) $+ .daily    1 4 msg %c !daily
  }

  ; ---- REMOVECHAN ----
  elseif ($1 == removechan) {
    if ($2 == $null) { echo -a Usage: /duckhunt removechan #channelname | return }
    var %c = $lower($2)
    if (!$istok(%duckhunt.channels, %c, 32)) {
      echo -a *** DuckHunt: %c is not in the tracked list
      return
    }
    duckhunt.stoptimers %c
    unset %duckhunt. $+ $duckhunt.slug(%c) $+ .*
    %duckhunt.channels = $remtok(%duckhunt.channels, %c, 1, 32)
    echo -a *** DuckHunt: Removed %c  (tracking: $iif(%duckhunt.channels != $null, %duckhunt.channels, (none)) $+ )
  }

  ; ---- RETRY ----
  elseif ($1 == retry) {
    ; /duckhunt retry on|off  -> all channels
    ; /duckhunt retry #chan on|off  -> one channel
    if ($left($2, 1) == #) {
      var %c = $lower($2)
      var %val = $3
      set %duckhunt. $+ $duckhunt.slug(%c) $+ .retry.on.miss $iif(%val == on, 1, 0)
      echo -a *** [ $+ %c $+ ] Retry on miss: $upper(%val)
    }
    else {
      var %val = $2
      var %i = 1
      var %total = $numtok(%duckhunt.channels, 32)
      while (%i <= %total) {
        var %c = $gettok(%duckhunt.channels, %i, 32)
        set %duckhunt. $+ $duckhunt.slug(%c) $+ .retry.on.miss $iif(%val == on, 1, 0)
        inc %i
      }
      echo -a *** Retry on miss: $upper(%val) (all channels)
    }
  }

  ; ---- BEFRIEND ----
  elseif ($1 == befriend) {
    if ($left($2, 1) == #) {
      var %c = $lower($2)
      var %val = $3
      set %duckhunt. $+ $duckhunt.slug(%c) $+ .befriend.enabled $iif(%val == on, 1, 0)
      echo -a *** [ $+ %c $+ ] Befriend mode: $upper(%val)
    }
    else {
      var %val = $2
      var %i = 1
      var %total = $numtok(%duckhunt.channels, 32)
      while (%i <= %total) {
        var %c = $gettok(%duckhunt.channels, %i, 32)
        set %duckhunt. $+ $duckhunt.slug(%c) $+ .befriend.enabled $iif(%val == on, 1, 0)
        inc %i
      }
      echo -a *** Befriend mode: $upper(%val) (all channels)
    }
  }

  ; ---- STATUS (default) ----
  else {
    echo -a *** DuckHunt Auto-Reply v3.0 status
    echo -a     Engine:   $iif(%duckhunt.enabled == 1, ENABLED, DISABLED)
    echo -a     Channels: $iif(%duckhunt.channels != $null, %duckhunt.channels, (none))
    var %i = 1
    var %total = $numtok(%duckhunt.channels, 32)
    while (%i <= %total) {
      var %c = $gettok(%duckhunt.channels, %i, 32)
      var %s = $duckhunt.slug(%c)
      echo -a     ---- %c
      echo -a       Duck:     $iif($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1, YES (Type: $eval(%duckhunt. $+ %s $+ .duck.type,2) HP: $eval(%duckhunt. $+ %s $+ .duck.hp,2) $+ ), NO)
      echo -a       Gun:      $iif($eval(%duckhunt. $+ %s $+ .gun.confiscated,2) == 1, CONFISCATED, OK)
      echo -a       Buyback:  $iif($eval(%duckhunt. $+ %s $+ .has.buyback,2) > 0, YES (x $+ $eval(%duckhunt. $+ %s $+ .has.buyback,2) $+ ), NO)
      echo -a       Retry:    $iif($eval(%duckhunt. $+ %s $+ .retry.on.miss,2) == 1, ENABLED, DISABLED)
      echo -a       Befriend: $iif($eval(%duckhunt. $+ %s $+ .befriend.enabled,2) == 1, ENABLED, DISABLED)
      inc %i
    }
  }
}

; ============================================================
; MAIN MESSAGE HANDLER
; Fires on all channels; $istok() replaces the old single-value
; $lower($chan) != $lower(%duckhunt.chan) filter.
; ============================================================
on *:TEXT:*:*:{

  ; ---- CHANNEL FILTER ----
  if (!$duckhunt.active($chan)) {
    ; Watchdog: warn about ducks on untracked channels
    if (%duckhunt.enabled != 1) return
    if ($nick != DuckHunt) && ($nick != Quackbot) return
    if (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*flock of*ducks* iswm $1-) || (*BOSS DUCK* iswm $1-) {
      echo -a *** [ $+ $lower($chan) $+ ] WARNING: DUCK SPAWNED BUT CHANNEL IS NOT TRACKED - run /duckhunt addchan $chan
    }
    return
  }

  ; ---- BOT FILTER ----
  if ($nick != DuckHunt) && ($nick != Quackbot) return

  var %c = $lower($chan)
  var %s = $duckhunt.slug(%c)

  ; ----------------------------------------------------------
  ; FLOCK REMAINING COUNT (must be outside $me isin block)
  ; ----------------------------------------------------------
  if (*duck(s) still in the flock* iswm $1-) || (*still in the flock* iswm $1-) {
    if ($eval(%duckhunt. $+ %s $+ .duck.type,2) == flock) && ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
      var %remaining = $regsubex($1-, /(\d+) duck.s. still/i, \1)
      if (%remaining isnum) && (%remaining > 0) {
        set %duckhunt. $+ %s $+ .duck.hp %remaining
        echo -a *** [ $+ %c $+ ] FLOCK: %remaining duck(s) remaining - continuing fire
        .timer.duckhunt. $+ %s $+ .flockcontinue 1 1 msg %c !bang
      }
      else {
        echo -a *** [ $+ %c $+ ] FLOCK: ducks remaining (count unknown) - continuing
        .timer.duckhunt. $+ %s $+ .flockcontinue 1 1 msg %c !bang
      }
    }
    return
  }

  ; ----------------------------------------------------------
  ; DUCK SPAWN DETECTION
  ; ----------------------------------------------------------

  ; --- BOSS DUCK ---
  if (*BOSS DUCK*appeared* iswm $1-) || (*A BOSS DUCK* iswm $1-) || (*boss duck*HP* iswm $1-) {
    set %duckhunt. $+ %s $+ .pending.retry 0
    set %duckhunt. $+ %s $+ .duck.flock 0
    duckhunt.stopshoottimers %c

    set %duckhunt. $+ %s $+ .duck.type boss
    var %bosshp = $regsubex($1-, /.*with (\d+) HP.*/i, \1)
    if (%bosshp isnum) { set %duckhunt. $+ %s $+ .duck.hp %bosshp }
    else               { set %duckhunt. $+ %s $+ .duck.hp 10 }
    set %duckhunt. $+ %s $+ .duck.active 1
    echo -a *** [ $+ %c $+ ] BOSS DUCK SPAWNED (HP: $eval(%duckhunt. $+ %s $+ .duck.hp,2) $+ ) - SUSTAINED FIRE
    .timer.duckhunt. $+ %s $+ .shoot1 1 1 msg %c !bang
    .timer.duckhunt. $+ %s $+ .shoot2 1 2 msg %c !bang
    .timer.duckhunt. $+ %s $+ .shoot3 1 3 msg %c !bang
    .timer.duckhunt. $+ %s $+ .shoot4 1 4 msg %c !bang
  }

  ; --- FLOCK ---
  elseif (*flock of*ducks*landed* iswm $1-) || (*A flock of* iswm $1-) {
    set %duckhunt. $+ %s $+ .pending.retry 0
    duckhunt.stopshoottimers %c

    set %duckhunt. $+ %s $+ .duck.type flock
    set %duckhunt. $+ %s $+ .duck.flock 1
    set %duckhunt. $+ %s $+ .duck.active 1

    var %flockcount = $regsubex($1-, /.*flock of (\d+).*/i, \1)
    if (%flockcount isnum) {
      set %duckhunt. $+ %s $+ .duck.flock.count %flockcount
      set %duckhunt. $+ %s $+ .duck.hp %flockcount
      echo -a *** [ $+ %c $+ ] FLOCK OF %flockcount DUCKS - RAPID FIRE
    }
    else {
      set %duckhunt. $+ %s $+ .duck.flock.count 2
      set %duckhunt. $+ %s $+ .duck.hp 2
      echo -a *** [ $+ %c $+ ] FLOCK SPAWNED (count unknown, assuming 2) - RAPID FIRE
    }

    var %shots = $calc($eval(%duckhunt. $+ %s $+ .duck.flock.count,2) + 2)
    var %i = 1
    while (%i <= %shots) {
      .timer.duckhunt. $+ %s $+ .shoot $+ %i 1 %i msg %c !bang
      inc %i
    }
  }

  ; --- QUACK / FLAP SPAWNS ---
  elseif (*QUACK* iswm $1-) || (*quack* iswm $1-) || (*\_O<* iswm $1-) || (*\_o<* iswm $1-) || (*flap flap* iswm $1-) || (*waddles in* iswm $1-) || (*sneaks in* iswm $1-) {

    set %duckhunt. $+ %s $+ .pending.retry 0
    set %duckhunt. $+ %s $+ .duck.flock 0
    set %duckhunt. $+ %s $+ .duck.flock.count 0
    duckhunt.stopshoottimers %c

    if (*decoy* iswm $1-) {
      set %duckhunt. $+ %s $+ .duck.type decoy
      set %duckhunt. $+ %s $+ .duck.hp 1
      set %duckhunt. $+ %s $+ .duck.active 1
      echo -a *** [ $+ %c $+ ] DECOY DUCK SPAWNED - DO NOT SHOOT!
      if ($eval(%duckhunt. $+ %s $+ .befriend.enabled,2) == 1) {
        echo -a *** [ $+ %c $+ ] Befriending decoy duck...
        .timer.duckhunt. $+ %s $+ .bef 1 1 msg %c !bef
      }
      else {
        echo -a *** [ $+ %c $+ ] Befriend disabled - ignoring decoy duck
        set %duckhunt. $+ %s $+ .duck.active 0
      }
    }
    elseif (*golden* iswm $1-) || (*glimmer* iswm $1-) {
      set %duckhunt. $+ %s $+ .duck.type golden
      set %duckhunt. $+ %s $+ .duck.hp 4
      set %duckhunt. $+ %s $+ .duck.active 1
      echo -a *** [ $+ %c $+ ] GOLDEN DUCK SPAWNED - RAPID FIRE (4 HP)
      .timer.duckhunt. $+ %s $+ .shoot1 1 1 msg %c !bang
      .timer.duckhunt. $+ %s $+ .shoot2 1 2 msg %c !bang
      .timer.duckhunt. $+ %s $+ .shoot3 1 3 msg %c !bang
      .timer.duckhunt. $+ %s $+ .shoot4 1 4 msg %c !bang
    }
    elseif (*ninja* iswm $1-) {
      set %duckhunt. $+ %s $+ .duck.type ninja
      set %duckhunt. $+ %s $+ .duck.hp 1
      set %duckhunt. $+ %s $+ .duck.active 1
      echo -a *** [ $+ %c $+ ] NINJA DUCK SPAWNED - always retrying on dodge
      .timer.duckhunt. $+ %s $+ .shoot1 1 1 msg %c !bang
    }
    elseif (*fast* iswm $1-) || (*speedy* iswm $1-) {
      set %duckhunt. $+ %s $+ .duck.type fast
      set %duckhunt. $+ %s $+ .duck.hp 1
      set %duckhunt. $+ %s $+ .duck.active 1
      echo -a *** [ $+ %c $+ ] FAST DUCK SPAWNED
      .timer.duckhunt. $+ %s $+ .shoot1 1 1 msg %c !bang
    }
    else {
      set %duckhunt. $+ %s $+ .duck.type normal
      set %duckhunt. $+ %s $+ .duck.hp 1
      set %duckhunt. $+ %s $+ .duck.active 1
      echo -a *** [ $+ %c $+ ] DUCK SPAWNED
      .timer.duckhunt. $+ %s $+ .shoot1 1 1 msg %c !bang
    }
  }

  ; ----------------------------------------------------------
  ; DUCK ESCAPED / DISAPPEARED
  ; ----------------------------------------------------------
  if (*escapes* iswm $1-) || (*vanishes* iswm $1-) || (*disappears* iswm $1-) || (*glides away* iswm $1-) || (*treasure in the wind* iswm $1-) || (*flies away* iswm $1-) || (*swims away* iswm $1-) || (*retreats* iswm $1-) || (*smoke bomb and vanishes* iswm $1-) || (*darts away* iswm $1-) || (*takes flight* iswm $1-) || (*disappears into the clouds* iswm $1-) || (*waddles away* iswm $1-) || (*flap*The duck has escaped* iswm $1-) || (*duck flies away* iswm $1-) || (*living another day* iswm $1-) || (*disappears into the distance* iswm $1-) || (*flaps away* iswm $1-) {
    echo -a *** [ $+ %c $+ ] DUCK ESCAPED
    duckhunt.clearduck %c
  }

  ; ----------------------------------------------------------
  ; INVENTORY PARSE - !inv response
  ; ----------------------------------------------------------
  if (*Inventory:* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      var %bgbcount = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbcount isnum) {
        set %duckhunt. $+ %s $+ .has.buyback %bgbcount
        echo -a *** [ $+ %c $+ ] Inventory: Buy Gun Back x $+ %bgbcount
      }
    }
    else {
      set %duckhunt. $+ %s $+ .has.buyback 0
      echo -a *** [ $+ %c $+ ] Inventory: No Buy Gun Back
    }
  }

  ; duckstats inventory parse
  if ($me isin $1-) && (*Items:* iswm $1-) && (*shot* iswm $1-) {
    if (*Buy Gun Back* iswm $1-) {
      var %bgbfromstats = $regsubex($1-, /Buy Gun Back x(\d+)/i, \1)
      if (%bgbfromstats isnum) {
        set %duckhunt. $+ %s $+ .has.buyback %bgbfromstats
        echo -a *** [ $+ %c $+ ] duckstats inventory: Buy Gun Back x $+ %bgbfromstats
      }
    }
    else {
      set %duckhunt. $+ %s $+ .has.buyback 0
      echo -a *** [ $+ %c $+ ] duckstats inventory: No Buy Gun Back
    }
  }

  ; ----------------------------------------------------------
  ; PURCHASE CONFIRMATIONS
  ; ----------------------------------------------------------
  if (*purchased Buy Gun Back* iswm $1-) || (*purchased*Buy Gun Back* iswm $1-) {
    if ($me isin $1-) {
      var %newcount = $regsubex($1-, /\(x(\d+)\)/i, \1)
      if (%newcount isnum) {
        set %duckhunt. $+ %s $+ .has.buyback %newcount
        echo -a *** [ $+ %c $+ ] PURCHASED Buy Gun Back (confirmed x $+ %newcount $+ ) - stored
      }
      else {
        var %oldbb = $eval(%duckhunt. $+ %s $+ .has.buyback,2)
        set %duckhunt. $+ %s $+ .has.buyback $calc(%oldbb + 1)
        echo -a *** [ $+ %c $+ ] PURCHASED Buy Gun Back (now have: $eval(%duckhunt. $+ %s $+ .has.buyback,2) $+ ) - stored
      }
    }
  }

  if (*purchased*Hunter* iswm $1-) && (*Insurance* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [ $+ %c $+ ] Hunter's Insurance active - friendly fire protected for 24h
    }
  }

  ; ----------------------------------------------------------
  ; GUN RETURNED after Buy Gun Back
  ; ----------------------------------------------------------
  if (*gun has been returned* iswm $1-) || (*Your gun has been returned* iswm $1-) {
    if ($me isin $1-) {
      echo -a *** [ $+ %c $+ ] GUN RECOVERED!
      set %duckhunt. $+ %s $+ .gun.confiscated 0
      set %duckhunt. $+ %s $+ .recovering 1
      var %curbb = $eval(%duckhunt. $+ %s $+ .has.buyback,2)
      if (%curbb > 0) { set %duckhunt. $+ %s $+ .has.buyback $calc(%curbb - 1) }
      .timer.duckhunt. $+ %s $+ .reloadafter 1 1 msg %c !reload
    }
  }

  ; ----------------------------------------------------------
  ; BEFRIEND RESULTS
  ; ----------------------------------------------------------
  if ($me isin $1-) {
    if (*befriended* iswm $1-) && (*0 befriended* !iswm $1-) && (*shot* !iswm $1-) && (*Items:* !iswm $1-) {
      echo -a *** [ $+ %c $+ ] BEFRIEND SUCCESSFUL
      set %duckhunt. $+ %s $+ .duck.active 0
      set %duckhunt. $+ %s $+ .duck.hp 0
      .timer.duckhunt. $+ %s $+ .bef off
      .timer.duckhunt. $+ %s $+ .shoot* off
    }
    elseif (*made friends* iswm $1-) || (*waddled over* iswm $1-) || (*accept your friendship* iswm $1-) {
      echo -a *** [ $+ %c $+ ] BEFRIEND SUCCESSFUL
      set %duckhunt. $+ %s $+ .duck.active 0
      set %duckhunt. $+ %s $+ .duck.hp 0
      .timer.duckhunt. $+ %s $+ .bef off
      .timer.duckhunt. $+ %s $+ .shoot* off
    }
    elseif (*failed to befriend* iswm $1-) || (*ran away* iswm $1-) {
      echo -a *** [ $+ %c $+ ] BEFRIEND FAILED
      if ($eval(%duckhunt. $+ %s $+ .duck.type,2) == decoy) {
        echo -a *** [ $+ %c $+ ] Decoy - not retrying to avoid confiscation risk
        set %duckhunt. $+ %s $+ .duck.active 0
      }
    }
  }

  ; ----------------------------------------------------------
  ; SHOT RESULTS ($me in message)
  ; ----------------------------------------------------------
  if ($me isin $1-) {

    ; Duck killed (explicit text)
    if ((*killed* iswm $1-) && (*duck* iswm $1-)) || (*DUCK DEFEATED* iswm $1-) {
      echo -a *** [ $+ %c $+ ] DUCK KILLED - STOPPING
      duckhunt.clearduck %c
    }

    ; New hit format: "hit the DUCK for N damage! It has N HP left."
    elseif (*hit*for*damage* iswm $1-) && (*HP left* iswm $1-) {
      var %hpleft = $regsubex($1-, /It has (\d+) HP left/i, \1)
      if (%hpleft isnum) {
        if (%hpleft == 0) {
          if ($eval(%duckhunt. $+ %s $+ .duck.type,2) == flock) {
            echo -a *** [ $+ %c $+ ] FLOCK DUCK DOWN (0 HP) - waiting for remaining count
          }
          else {
            echo -a *** [ $+ %c $+ ] DUCK KILLED (0 HP left)
            set %duckhunt. $+ %s $+ .duck.active 0
            set %duckhunt. $+ %s $+ .duck.hp 0
            set %duckhunt. $+ %s $+ .pending.retry 0
            .timer.duckhunt. $+ %s $+ .shoot* off
            .timer.duckhunt. $+ %s $+ .continue off
            .timer.duckhunt. $+ %s $+ .retry off
            .timer.duckhunt. $+ %s $+ .resume off
          }
        }
        else {
          set %duckhunt. $+ %s $+ .duck.hp %hpleft
          set %duckhunt. $+ %s $+ .pending.retry 0
          echo -a *** [ $+ %c $+ ] HIT! Duck HP: %hpleft
          if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
            .timer.duckhunt. $+ %s $+ .continue 1 1 msg %c !bang
          }
        }
      }
    }

    ; HP remaining (old format)
    elseif *HP remaining* iswm $1- {
      var %hp = $regsubex($1-, /\[(\d+) HP remaining\]/i, \1)
      set %duckhunt. $+ %s $+ .duck.hp %hp
      set %duckhunt. $+ %s $+ .pending.retry 0
      echo -a *** [ $+ %c $+ ] HIT! Duck HP: %hp
      if (%hp > 0) && ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
        .timer.duckhunt. $+ %s $+ .continue 1 1 msg %c !bang
      }
      else {
        .timer.duckhunt. $+ %s $+ .shoot* off
      }
    }

    ; One-shot kill (old "shot the duck" format)
    elseif (*shot*duck* iswm $1-) || (*shot*FAST* iswm $1-) || (*shot*GOLDEN* iswm $1-) || (*shot*NINJA* iswm $1-) || (*shot*BOSS* iswm $1-) || (*shot*FLOCK* iswm $1-) {
      echo -a *** [ $+ %c $+ ] DUCK KILLED (one-shot)
      duckhunt.clearduck %c
    }

    ; Dodge (ninja)
    elseif (*dodged* iswm $1-) || (*evaded* iswm $1-) {
      echo -a *** [ $+ %c $+ ] DODGE! Retrying...
      if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
        set %duckhunt. $+ %s $+ .pending.retry 1
        .timer.duckhunt. $+ %s $+ .retry 1 1 msg %c !bang
      }
    }

    ; Normal miss
    elseif (*missed* iswm $1-) && (*duck* iswm $1-) && (*missed and hit* !iswm $1-) {
      echo -a *** [ $+ %c $+ ] MISSED THE DUCK
      if ($eval(%duckhunt. $+ %s $+ .duck.type,2) == ninja) && ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
        echo -a *** [ $+ %c $+ ] NINJA DUCK - always retrying
        set %duckhunt. $+ %s $+ .pending.retry 1
        .timer.duckhunt. $+ %s $+ .retry 1 1 msg %c !bang
      }
      elseif ($eval(%duckhunt. $+ %s $+ .retry.on.miss,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
        echo -a *** [ $+ %c $+ ] RETRYING (retry enabled)
        set %duckhunt. $+ %s $+ .pending.retry 1
        .timer.duckhunt. $+ %s $+ .retry 1 1 msg %c !bang
      }
      else {
        echo -a *** [ $+ %c $+ ] Not retrying (safer mode)
      }
    }

    ; Missed and hit someone
    elseif *missed and hit* iswm $1- {
      if (*GUN CONFISCATED* iswm $1-) {
        echo -a *** [ $+ %c $+ ] MISSED AND HIT SOMEONE - GUN CONFISCATED
        duckhunt.confiscated %c
      }
      elseif (*INSURANCE PROTECTED* iswm $1-) || (*No penalties* iswm $1-) {
        echo -a *** [ $+ %c $+ ] FRIENDLY FIRE - INSURANCE PROTECTED, continuing
        if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.hp,2) > 0) {
          .timer.duckhunt. $+ %s $+ .continue 1 1 msg %c !bang
        }
      }
      else {
        echo -a *** [ $+ %c $+ ] MISSED AND HIT - unknown result, treating as confiscated
        duckhunt.confiscated %c
      }
    }

    ; Out of ammo
    elseif (*out of ammo* iswm $1-) && (*Use !reload* iswm $1-) {
      if ($eval(%duckhunt. $+ %s $+ .recovering,2) != 1) {
        echo -a *** [ $+ %c $+ ] OUT OF AMMO - RELOADING
        msg %c !reload
      }
    }
    elseif *out of ammo* iswm $1- {
      if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .recovering,2) != 1) {
        echo -a *** [ $+ %c $+ ] OUT OF AMMO - RELOADING
        msg %c !reload
      }
      elseif ($eval(%duckhunt. $+ %s $+ .recovering,2) == 1) {
        echo -a *** [ $+ %c $+ ] Out of ammo during recovery (no spare mags) - stopping reload loop
        set %duckhunt. $+ %s $+ .recovering 0
      }
    }

    ; Decoy/wooden decoy or standalone confiscation fallback
    elseif (*CLANG* iswm $1-) || (*wooden decoy* iswm $1-) || (*gun has been confiscated* iswm $1-) || ((*confiscated* iswm $1-) && (*not confiscated* !iswm $1-) && (*INSURANCE* !iswm $1-)) {
      duckhunt.confiscated %c
    }

    ; Gun is fine
    elseif *gun is not confiscated* iswm $1- {
      echo -a *** [ $+ %c $+ ] Gun is OK
    }

    ; Gun jammed
    elseif *jammed* iswm $1- {
      echo -a *** [ $+ %c $+ ] GUN JAMMED - RETRYING
      if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.hp,2) > 0) {
        .timer.duckhunt. $+ %s $+ .jamretry 1 1 msg %c !bang
      }
    }

    ; Rate limited
    elseif (*trying to shoot too fast* iswm $1-) || (*doing that too quickly* iswm $1-) {
      echo -a *** [ $+ %c $+ ] RATE LIMITED - waiting 3s before retry
      if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) {
        .timer.duckhunt. $+ %s $+ .cooldown 1 3 msg %c !bang
      }
    }

    ; Soaked
    elseif (*soaked* iswm $1-) || (*wet clothes* iswm $1-) || (*cannot shoot* iswm $1-) || (*wringing wet* iswm $1-) {
      echo -a *** [ $+ %c $+ ] SOAKED - buying Dry Clothes to resume
      .timer.duckhunt. $+ %s $+ .shoot* off
      .timer.duckhunt. $+ %s $+ .dryclothes 1 2 msg %c !shop 9
    }

    ; No duck in area
    elseif *no duck in the area* iswm $1- {
      echo -a *** [ $+ %c $+ ] NO DUCK - STOPPING
      duckhunt.clearduck %c
    }

    ; Daily bonus
    elseif (*already claimed* iswm $1-) && (*daily* iswm $1-) {
      echo -a *** [ $+ %c $+ ] Daily XP already claimed today
    }
    elseif (*daily* iswm $1-) && ((*bonus* iswm $1-) || (*XP* iswm $1-)) && (*claimed* iswm $1-) {
      echo -a *** [ $+ %c $+ ] Daily XP bonus claimed!
    }
  }
}

; ============================================================
; RELOAD CONFIRMATION
; ============================================================
on *:TEXT:*New magazine loaded*:*:{
  if (!$duckhunt.active($chan)) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  var %c = $lower($chan)
  var %s = $duckhunt.slug(%c)
  if ($me isin $1-) {
    echo -a *** [ $+ %c $+ ] MAGAZINE RELOADED
    set %duckhunt. $+ %s $+ .ammo 6
    set %duckhunt. $+ %s $+ .recovering 0
    if ($eval(%duckhunt. $+ %s $+ .pending.retry,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.hp,2) > 0) {
      echo -a *** [ $+ %c $+ ] Pending retry after reload - FIRING
      set %duckhunt. $+ %s $+ .pending.retry 0
      .timer.duckhunt. $+ %s $+ .afterreload 1 1 msg %c !bang
    }
    elseif ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.hp,2) > 0) {
      echo -a *** [ $+ %c $+ ] Duck still active (HP: $eval(%duckhunt. $+ %s $+ .duck.hp,2) $+ ) - RESUMING
      .timer.duckhunt. $+ %s $+ .afterreload 1 1 msg %c !bang
    }
  }
}

; ============================================================
; DRY CLOTHES CONFIRMATION
; ============================================================
on *:TEXT:*dried*:*:{
  if (!$duckhunt.active($chan)) return
  if ($nick != DuckHunt) && ($nick != Quackbot) return
  var %c = $lower($chan)
  var %s = $duckhunt.slug(%c)
  if ($me isin $1-) {
    if (*dry* iswm $1-) || (*dried off* iswm $1-) {
      echo -a *** [ $+ %c $+ ] DRY CLOTHES USED - can shoot again
      if ($eval(%duckhunt. $+ %s $+ .duck.active,2) == 1) && ($eval(%duckhunt. $+ %s $+ .duck.hp,2) > 0) {
        .timer.duckhunt. $+ %s $+ .afterdry 1 1 msg %c !bang
      }
    }
  }
}

; ============================================================
; CLEANUP
; ============================================================
on *:DISCONNECT:{
  .timer.duckhunt.* off
  echo -a *** DuckHunt: All timers cleared on disconnect
}

on *:PART:*:{
  if ($nick == $me) {
    var %lc = $lower($chan)
    if ($istok(%duckhunt.channels, %lc, 32)) {
      duckhunt.stoptimers %lc
      echo -a *** DuckHunt: Timers cleared on leaving %lc
    }
  }
}

; ============================================================
; MANUAL ALIASES
; Optional #chan arg; defaults to first tracked channel if omitted
; ============================================================
alias duckhunt.check {
  var %t = $iif($1 != $null, $lower($1), $gettok(%duckhunt.channels, 1, 32))
  if (%t == $null) { echo -a Usage: /duckhunt.check [#chan] | return }
  msg %t !inv
}
alias duckhunt.daily {
  var %t = $iif($1 != $null, $lower($1), $gettok(%duckhunt.channels, 1, 32))
  if (%t == $null) { echo -a Usage: /duckhunt.daily [#chan] | return }
  msg %t !daily
}
alias duckhunt.effects {
  var %t = $iif($1 != $null, $lower($1), $gettok(%duckhunt.channels, 1, 32))
  if (%t == $null) { echo -a Usage: /duckhunt.effects [#chan] | return }
  msg %t !effects
}

; ============================================================
; LOAD MESSAGE
; ============================================================
echo -a *** DuckHunt Auto-Reply Script Loaded (v3.0 - Multichannel)
echo -a *** /duckhunt on #chan1 [#chan2 ...]  - Enable and set tracked channels
echo -a *** /duckhunt off                    - Disable and clear all state
echo -a *** /duckhunt addchan #chan           - Add a channel to the active list
echo -a *** /duckhunt removechan #chan        - Remove a channel from the active list
echo -a *** /duckhunt retry [#chan] on|off    - Toggle retry on miss (risky)
echo -a *** /duckhunt befriend [#chan] on|off - Toggle befriend for decoy ducks
echo -a *** /duckhunt                        - Full per-channel status
echo -a *** /duckhunt.check [#chan]           - Check inventory (!inv)
echo -a *** /duckhunt.daily [#chan]           - Manually claim daily XP
echo -a *** /duckhunt.effects [#chan]         - Check active buffs/debuffs
echo -a *** Active channels: $iif(%duckhunt.channels != $null, %duckhunt.channels, (none))
