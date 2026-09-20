# Plan

The vetted set of sessions between now and done. Each session reads the relevant entry at
open and marks it done at close. This doc is the single source of truth for scope, success
criteria, and sequencing — a session's brief is a delta against its entry, not a replacement
for it.

## How this doc is used

- **Entries are the unit of work.** Each entry names its scope, success criterion, and any
  prerequisite entries.
- **Plan-backed sessions** point at an entry here. **Stub-driven sessions** don't have one yet
  — they're driven by what's in the brief itself, and get promoted to an entry here if they
  turn out to need one (see the housekeeping inbox's "Promote" disposition).
- **Checkmarks land on close**, not mid-session. Otherwise this doc is append-only while a
  session is open — edit it only to record a finding or a newly surfaced prerequisite.
- **A session that outgrows its context splits** into more sessions rather than compressing
  to fit a target count. Update the entry list to match; this doc tracks the work, not the
  session count.

## Entries

### Rules core: board, terrain, and economy

- **Status:** done (Session 001)
- **Prerequisites:** none
- **Success criterion:** The board/territory model, elevation with the smoothness constraint, terrain raise/lower and land reclamation, the resource economy (Supply/Energy), and structure placement/build-time rules are implemented in the pure `src/shared/` layer with zero Roblox API calls, each covered by Lune tests, and `lune run test` passes.
- **Artifact:** `src/shared/board.luau`, `state.luau`, `economy.luau`, `structures.luau`, `config.luau`, with test coverage.

### Rules core: combat, fog, and victory

- **Status:** done (Session 002)
- **Prerequisites:** Rules core: board, terrain, and economy
- **Success criterion:** Line-of-flight math (direct and arcing fire), simultaneous volley resolution, fog reveals with stale belief maps, round-based unlock gates, and all four victory conditions — including simultaneous mutual base elimination — are implemented and tested: line-of-flight exhaustively against hand-worked cases, one test per victory condition. A full scripted match runs end to end in the terminal with a green test suite.
- **Artifact:** `src/shared/flight.luau`, `rules.luau`, `fog.luau`, tests, and any `DECISIONS.md` entries for ambiguity resolved along the way.

### Simulation harness and first balance sweep

- **Status:** done (Session 003)
- **Prerequisites:** Rules core: combat, fog, and victory
- **Success criterion:** A harness runs large batches of scripted matches between five archetype strategies (each reading only its own belief map), producing per-match logs, an aggregate CSV, and the core balance metrics — rounds-to-first-base, match-length distribution, comeback rate, purchase share, cannon block rate, victory-condition distribution, win-rate matrix. A first parameter sweep narrows to a shortlist of candidate configs for later human playtesting.
- **Artifact:** `sim/harness.luau`, `sim/archetypes/`, `sim/sweep.luau`, sweep output, and a shortlist note.
- **Outcome:** `lune run sim` (5,000-match round robin) and `lune run sweep` (staged 3-pass
  sweep) both run from the terminal and produce every metric asked for. The sweep itself
  found zero surviving configs — a real finding, not a gap: standing points reward
  structures over terrain investment (one archetype dominates the field regardless of
  match length), and cannon block rate stays near 0% because a fully-informed scripted
  agent routes around any ridge it can see. Written up in `sim/output/shortlist.md`; feeds
  the **Ship polish and balance pass** entry below rather than being resolved here.

### Board in Studio

- **Status:** done (Session 004)
- **Prerequisites:** Rules core: combat, fog, and victory
- **Success criterion:** The Rojo project syncs a full-size board with the channel and both starting islands into Studio, elevation renders as clearly distinguishable stacked-cube levels, and a scriptable camera frames each player's own territory. No avatars are spawned.
- **Artifact:** `src/client/Board.luau`, `Camera.luau`, `default.project.json` wiring.
- **Outcome:** `rojo build` produces a clean place file; `Board.luau` renders one cube per
  land cell (height and one of 3 shades by elevation) plus a water plate, `Camera.luau`
  gives an angled top-down scriptable camera bound to a territory with pan/zoom and a Tab
  toggle between sides, wired through `src/client/init.client.luau` and
  `src/server/init.server.luau` (`Players.CharacterAutoLoads = false`). User-confirmed
  visually in Studio. Round 1's real starting state is flat (§3), so `init.client.luau`
  currently seeds a temporary demo elevation bump for that visual check — the **Planning
  phase** entry below should remove it once real terrain-editing exists to demonstrate
  elevation instead.

### Planning phase

- **Status:** done (Session 005)
- **Prerequisites:** Board in Studio
- **Success criterion:** A player can place and bulldoze structures, edit and reclaim terrain with cost and smoothness validation and clear rejection feedback, assign weapon targets, and ready up against a round clock, all inside the plan-phase UI.
- **Artifact:** `src/client/UI/` build palette, terrain tools, targeting UI, round clock.
- **Outcome:** A local-only `PlanController` (`src/client/UI/PlanController.luau`) drives a
  client-held `MatchState` and calls straight into the existing `state.luau` commands, so
  cost/territory/smoothness validation and rejection messages come from the rules core
  unchanged. `BuildPalette.luau`, `RoundClock.luau`, and `StructureView.luau` cover
  build/bulldoze, terrain edit/reclaim, targeting (validated against enemy territory only —
  range/line-of-flight needs `flight.luau` and is the next entry's job), and the round
  clock/ready-up. `Cursor.luau` adds a green/red footprint preview while placing and a
  crosshair while targeting. `base` is deliberately absent from the palette — it's placed
  during a setup phase that doesn't exist until **Full match loop and wrapper screens**.
  `rojo build` clean; `lune run test` green (71/71); user-confirmed in Studio (cursor/
  crosshair addition pending a follow-up visual check).

### Resolve phase vs. a dummy opponent

- **Status:** done (Session 006)
- **Prerequisites:** Planning phase
- **Success criterion:** Aiming and firing a volley against a static dummy layout animates both sides' volleys firing simultaneously, shows direct fire visibly stopping at ridges, applies damage and rubble, and updates the belief map to show exactly what was revealed.
- **Artifact:** `src/client/Render.luau` projectile/impact/rubble rendering and reveal rendering.
- **Outcome:** `PlanController:advanceRound()` calls `rules.luau`'s newly-exported
  `resolvePlayerVolley`/`destroyedCellSet` directly (not the full `resolveRound` batch —
  see the log's Open Gate decision) against a static dummy layout seeded onto the enemy
  island. `Render.luau` animates both sides' shots concurrently to wherever they actually
  land, so a blocked cannon shot visibly stops at a ridge with no special-casing needed;
  destroyed structures get transient rubble, and the enemy island renders from the local
  belief map with revealed structures/rubble and a subtle unrevealed-cell marker. Fog
  clears progressively as a shell crosses each beam cell rather than all at once at
  commit (added from live user testing, no fog/rules rework needed). Live Studio testing
  also drove a range-validation gate on targeting and misfire feedback for out-of-range/
  unaffordable shots — both were silent failures before. `rojo build` clean; `lune run
  test` green (71/71, after updating `flight.spec.luau` to read range expectations from
  config rather than hardcoded numbers). `PLAN_SECONDS` (10) and both weapons' ranges
  (cannon 20, mortar 32) are testing-only values pending a real balance pass (§18).

### Full match loop and wrapper screens

- **Status:** done (Session 007)
- **Prerequisites:** Resolve phase vs. a dummy opponent
- **Success criterion:** Multi-round progression with unlock gates and a running economy works end to end through the session state machine (intro → setup → rounds → result): intro with Start Game and a disabled Save/Continue, an empty settings panel backed by an extensible registry, and a result screen with the itemized score/stat breakdown and a Restart that never requires rejoining.
- **Artifact:** `server/MatchService.luau` state machine and the three screens.
- **Outcome:** Kept everything local-only per the Open Gate decision (mirroring Sessions
  004-006's precedent) — `MatchController.luau` (`src/client/UI/`) owns intro → setup →
  rounds → result and mounts/tears down a fresh `PlanUI` per match rather than a real
  `server/MatchService.luau`; that becomes real in **Real two-player networking** below.
  `PlanController` adopted `rules.luau`'s `resolveRound` command-batch model this session
  (closing the gap Session 006 left open), with PLAN-phase commands applied immediately
  for live feedback and replayed through `resolveRound` at round's end for the real
  simultaneous-resolution semantics. The three screens live in `src/client/UI/Screens/`.
  Score/stat bookkeeping (`structuresBuilt`, shots fired/hit/blocked, points broken out by
  structure type, plus reveal/hit point categories added from live playtesting feedback)
  was added to `src/shared/state.luau`/`rules.luau` to back the Result screen's breakdown.
  `rojo build` clean; `lune run test` green (76/76). User-confirmed in Studio, including
  two live fixes: a Ready-button highlight once setup's bases are placed, and the new
  reveal/hit scoring categories (surfaced by a match the user felt they should have won on
  scouting alone).

### Real two-player networking

- **Status:** done (Session 008)
- **Prerequisites:** Full match loop and wrapper screens
- **Success criterion:** Two Studio clients can matchmake, complete setup, and play a full match against each other with the server holding all authoritative state — enemy structures never exist client-side before being revealed — and an exploit check confirms no unrevealed enemy structure appears in either client's Instance tree or remote payloads.
- **Artifact:** `server/Replication.luau`, `CommandHandler.luau`, rate-limited remotes.
- **Outcome:** `server/MatchService.luau` holds the one authoritative `MatchState` per
  match and runs the round loop (setup → plan → resolve → result) through the same pure
  `State.*`/`Rules.resolveRound` functions the old client called directly.
  `server/CommandHandler.luau` matchmakes a two-player queue and rate-limits the
  `Command` remote; `server/Replication.luau` shapes and sends every push. A client only
  ever receives `src/shared/view.luau`'s `View` (promoted from the sim harness, which
  already had the same "own state only" guarantee) plus a per-round animation payload
  (`src/shared/resolveView.luau`) scoped to weapons that actually fired. `PlanController`
  is now a thin server-driven view; the old local-only flow survives unchanged as
  `PracticeController` (an explicit "Practice vs. Dummy" option on the Intro screen,
  alongside "Start Game"). `rojo build` clean; `lune run test` green (80/80). User-
  confirmed live with two real Studio clients: matchmaking, setup, and a full match all
  worked end to end.

### Bot opponent

- **Status:** done (Session 009)
- **Prerequisites:** Real two-player networking
- **Success criterion:** The bot FSM builds its opening layout, shapes terrain, probes with cannons, suppresses generators, concentrates fire on plotted bases, and rebuilds — using only its own fog/belief map — across all three difficulty presets, and a player can lose to it.
- **Artifact:** `server/Bot.luau`.
- **Outcome:** Built on `src/shared/archetypeKit.luau` (promoted from `sim/` this session,
  same move Session 008 made for `view.luau`) — the bot is a second seat in
  `server/MatchService.luau`'s round loop (a virtual owner with no real `Player` Instance),
  not a replacement for `PracticeController.luau`'s offline dummy. Three difficulty presets
  live in `src/shared/botDifficulty.luau`, chosen via the first real entry in the
  previously-empty Settings registry. "Play vs. Bot" is a third Intro option, starting
  instantly through the same server-authoritative path as a real match. Live playtesting
  also caught and fixed a round-clock display bug (`PlanController.luau` never transitioned
  client-side into "resolve," so the clock never restarted past round 1 — logged in
  DECISIONS.md alongside this session's other calls). `rojo build` clean; `lune run test`
  green (80/80); user-confirmed live in Studio against the bot, difficulty presets untuned
  pending §18.

### Real-time rules core

- **Status:** done (Session 011)
- **Prerequisites:** Bot opponent
- **Success criterion:** `resolveRound`'s batch model (validate a whole PLAN-phase command
  set, then run the fixed RESOLVE step order) is replaced by a tick function evaluated on a
  **fixed server heartbeat** (config-driven tick length, default 0.5s — decided over
  independent per-weapon timers in Session 010 for determinism and to give the sim-harness
  rewrite below a concrete discrete step to mirror). Each tick: weapons fire automatically
  against their assigned target whenever off-cooldown, in range, and unblocked; Supply/Energy
  accrue at a per-tick rate instead of a round-end lump sum; building/terrain-edit commands
  apply immediately and permanently on receipt, no batching; construction completes at a
  `readyAt` timestamp instead of "both sides ready up"; victory conditions (base elimination,
  incapacitation) are checked every tick; a single match clock (elapsed time vs. a fixed
  `MATCH_SECONDS`, default ~180s) replaces `MAX_ROUNDS` and the `round_limit` condition.
  Existing scoring (destruction/standing/reveal/hit points) and the incapacitation grace
  window carry over restated in time terms rather than round terms — this is a re-plumbing of
  `resolveRound`'s internals, not a redesign of what it scores. Pure `src/shared/`, zero
  Roblox API calls, fully covered by a rewritten Lune test suite, `lune run test` passes.
  Everything else below depends on this.
- **Artifact:** `src/shared/rules.luau` (batch `resolveRound` → tick function), `state.luau`
  (round counter → elapsed time / `readyAt` timestamps), `economy.luau` (lump accrual →
  rate-based), `config.luau` (tick length, per-tick rates, `MATCH_SECONDS`), rewritten
  `rules.spec.luau` / `state.spec.luau` / `economy.spec.luau`.
- **Outcome:** `Rules.resolveRound` split into `Rules.applyCommand` (immediate, permanent,
  one command at a time — the old same-round terrain-edit/placement batch-conflict rule was
  dropped entirely, since sequential immediate application resolves it structurally) and
  `Rules.tick` (construction, automatic cooldown-gated weapon fire against a shared pre-tick
  snapshot, income, incapacitation, victory). Weapon targets persist on the structure
  (`Structures.setTarget`) instead of being resent every round. `round_limit` renamed
  `time_limit`. Two adjacent shared-layer files broke and got trivial fixes to keep
  `lune run test` green: `view.luau`'s `round` field → `elapsed`, and `archetypeKit.luau`'s
  one reference to it — neither a redesign of `server/`/`sim/` logic, still out of scope.
  `resolveView.luau` (a per-round batch animation shim) and its spec were deleted as obsolete
  under continuous ticks rather than patched — the entry below owns its replacement.
  `server/MatchService.luau`, `server/Bot.luau`, `sim/harness.luau`, `sim/archetypes/*`, and
  round-based client UI are now broken against this, as expected. `lune run test`: 78/78.

### MatchService real-time loop

- **Status:** done (Session 012)
- **Prerequisites:** Real-time rules core
- **Success criterion:** `server/MatchService.luau`'s phase state machine collapses from
  `setup → plan → resolve → result` to `setup → one live phase (running entry 1's tick) →
  result`. The immediate-apply/replay two-track command model (built for simultaneous-reveal
  batching) is dropped entirely — a client's command applies immediately and permanently,
  since nothing is secret enough to need holding it until a boundary once there's no
  boundary. Match clock and victory checks run continuously off the live tick. Two Studio
  clients can matchmake, complete setup, and play a full real-time match against each other
  with the server remaining sole source of truth (unrevealed enemy structures still never
  exist client-side before being revealed — §12's guarantee is unaffected by this rework).
- **Artifact:** `server/MatchService.luau`, `server/Replication.luau` (push shape for a
  continuous tick instead of a per-round batch), `server/CommandHandler.luau` as needed.
- **Outcome:** Phase machine is `setup → live → result`. `live` runs `Rules.tick` on a
  recurring `task.spawn`/`task.wait(TICK_SECONDS)` loop; every command applies immediately
  via a new `Rules.applyCommand` dispatch, replacing MatchService's own per-type State.*
  calls and the whole pendingCommands/roundStartState/replay/same-round-conflict machinery.
  Added `src/shared/tickView.luau` (+ spec) as the per-tick successor to the deleted
  `resolveView.luau`, and `State.completeAllConstruction` (unconditional, for the setup →
  live transition only — setup bases were never meant to sit on the same build timer
  live-placed structures now get). `CommandHandler.luau` needed no changes.
  `src/client/UI/PlanController.luau` (not in the original artifact list, but load-bearing
  for the success criterion) was rewritten to match; `RoundClock.luau`/`Cursor.luau` got
  minimal fixes, one of them (`Cursor.luau`'s stale `.round` reference) a real
  would-have-crashed-on-hover bug caught on read. A first live test failed immediately
  (setup bases silently never went live, read as mutual base elimination) — fixed and
  confirmed working in a second live pass with two Studio clients. `server/Bot.luau` is
  still broken (Session 011's config renames) and out of scope; the live loop now starts
  before the bot's one-shot decide() call so that stays contained. The board still fully
  rebuilds every tick rather than updating incrementally — cosmetic, "Client real-time UI"'s
  job. `lune run test`: 82/82.

### Practice mode real-time adaptation

- **Status:** done (Session 013)
- **Prerequisites:** MatchService real-time loop
- **Success criterion:** `src/client/UI/PracticeController.luau` (the offline "Practice vs.
  Dummy" flow) is reworked to drive `Rules.applyCommand`/`Rules.tick` the same way the
  networked path does, instead of its own inline copy of the old round-batch
  `resolveRound`/resolve-event redaction logic. Surfaced in Session 012: it's a ~500-line
  local-only controller that never touches `MatchService`/`Replication`/`CommandHandler`, so
  it wasn't swept up by that entry's rework and isn't named in "Client real-time UI"'s
  artifacts either — a real gap between entries, not an oversight to silently absorb into
  either one. Left broken (matching `server/Bot.luau`/`sim/`'s status) until this entry lands.
- **Artifact:** `src/client/UI/PracticeController.luau`, reusing `src/shared/tickView.luau`
  (the per-tick redaction module "MatchService real-time loop" introduced to replace the
  deleted `resolveView.luau`) rather than re-deriving its own copy.
- **Outcome:** Phases collapsed to `setup → live → result`, mirroring `MatchService` minus the
  network layer: `Rules.applyCommand` per action, a local `RunService.Heartbeat` loop
  accumulating to `config.TICK_SECONDS` in place of a server heartbeat, and the dummy's
  frontline cannon targeted once (persists on the structure) instead of reissued every round.
  Live testing this session also surfaced and fixed two real bugs outside this entry's own
  artifact list: `Rules.tick` (`src/shared/rules.luau`) was crediting each player's
  `destructionPoints` for structures *they* lost rather than what they destroyed — invisible on
  a straight base-elimination finish, but flips the outcome whenever a match falls back to
  score-based deciding (fixed, regression test added); and the Result screen
  (`src/client/UI/Screens/Result.luau`) unconditionally read "Opponent incapacitated" regardless
  of which side actually was, plus a stale `round_limit` lookup key from session 11's
  `time_limit` rename (both fixed). A third finding, the enemy-board full-rebuild-every-tick
  causing instant rather than progressive fog reveal, and a fourth, the Cannon/Generator
  opening-cost squeeze, were diagnosed but deliberately left for "Client real-time UI" and "Ship
  polish and balance pass" respectively (see those entries below) rather than patched here.
  `lune run test`: 83/83. `rojo build` clean. User-confirmed live in Studio across several
  matches, including a raised ridge still blocking a shot as before.

### Bot re-adaptation

- **Status:** done (Session 015)
- **Prerequisites:** MatchService real-time loop
- **Success criterion:** `server/Bot.luau` moves from one `decide()` call per PLAN phase to a
  periodic re-decide cadence inside the live tick loop (config-driven interval). `Bot:decide`'s
  existing idempotency (it only ever adds what it doesn't already have) is verified to hold
  under repeated calls rather than the single call it was written against. Re-probe patience
  and other difficulty knobs move from round-keyed to time-keyed staleness tracking. The bot
  remains playable across all three difficulty presets under the same real-time cooldown/
  economy rules a real player is held to.
- **Artifact:** `server/Bot.luau`, `src/shared/botDifficulty.luau` (round-keyed → time-keyed
  patience).
- **Outcome:** `Bot.luau`'s `view.round`/`config.UNLOCK_ROUND`/`def.unlock_round` references —
  dead since Session 011's round→time rename, never touched since — are now `view.elapsed`/
  `config.UNLOCK_TIME`/`def.unlock_time`; belief-staleness tracking (`beliefSeenRound` →
  `beliefSeenAt`) and `botDifficulty.luau`'s patience knob (`restProbeRounds` →
  `restProbeSeconds`, keeping the old 4:2:1 ratio scaled by the ~10s a testing round used to
  take) moved the same way. A second, unrelated crash surfaced on read:
  `MatchService.luau`'s difficulty-based starting-Supply bonus referenced `SUPPLY_PER_ROUND`,
  also deleted in the same rework — swapped for `STARTING_SUPPLY`, same "extra = base ×
  (multiplier − 1)" shape. Added `config.BOT_DECIDE_INTERVAL_SECONDS` (3s) and wired
  `MatchService:_tick` to re-run `Bot:decide()` on that cadence instead of once at match
  start; `decide()` needed no changes for repeated-call safety (build/terrain commands
  already only add what's missing), and its per-call full re-target pass incidentally became
  its own re-arm mechanism once this session's single-shot change (below) landed. `lune run
  test`: 84/84 unaffected (server/-only changes, outside the pure layer). `rojo build` clean.
  Also this session, at the user's request: single shot is now the rules core's default (a
  fired weapon clears its own target instead of firing again on its own; `structure.autoFire`,
  default `false`, is the flag a future control will flip — see "Weapon inspection and control
  panel"'s finding below), and the build palette's weapon buttons show their Supply cost and
  dim when unaffordable. `lune run test`: 85/85 after those changes. Live Studio confirmation
  across all three difficulty presets wasn't explicitly reported back in this session — the
  user acknowledged the summary and moved on to the two requests above without flagging a
  problem, but this is worth an explicit playtest pass before calling the bot fully proven.

### Client real-time UI

- **Status:** done (Session 014)
- **Prerequisites:** Real-time rules core, MatchService real-time loop
- **Success criterion:** The round-based clock display is replaced by a single match clock
  (elapsed/remaining time against `MATCH_SECONDS`) — **no round counter anywhere in the UI**;
  rounds stop existing as a concept once this lands. Per-weapon cooldown indicators show live
  off-cooldown state. Supply/Energy display updates continuously instead of jumping once per
  round. Shot animation is event-driven — fires and animates as each weapon comes off
  cooldown and resolves — instead of batched per-round. During setup, the base build tool is
  **pre-selected by default** (base placement, and bulldoze-then-replace, are the only
  actions available in setup, so requiring a manual tool selection first is a needless step).
- **Artifact:** `src/client/UI/RoundClock.luau` (reworked into a match clock), `BuildPalette.
  luau` (setup default tool), `StructureView.luau`, `Render.luau` event-driven hookup.
- **Note:** A live-updating running score display (score currently only appears on the
  Result screen) is a natural fit once scoring is event-driven rather than round-batched —
  raised in Session 010 — but is **deferred**, not required for this entry's success
  criterion. Revisit as a follow-up polish item once the above lands.
- **Finding (Session 013):** confirmed live, in both Practice and (by shared code) the real
  networked/bot match: `Render.luau`'s `onChange` handler calls `renderEnemyBoard()` on every
  tick, which fully redraws the enemy fog/structure display from the current, already-updated
  belief map. Since this runs every `TICK_SECONDS` (0.5s) — shorter than a shot's ~0.9s flight
  animation — it overwrites the beam's progressive per-cell `reveal()` calls almost immediately,
  so fog reveal now looks instant rather than tracing in as the shot travels. This is the same
  "full rebuild every tick" issue Session 012 flagged as cosmetic; it's the dominant cause of
  that symptom, not a minor one. `effectsFolder`'s own every-tick clear (a separate, smaller bug
  that was also killing the projectile itself) was already fixed in Session 013; this one needs
  the real event-driven rendering this entry owns.
- **Outcome:** The Session 013 finding was the fix: `Render.luau`'s `onChange` handler no
  longer calls `renderEnemyBoard()` every tick — belief only ever changes via a reveal
  (confirmed against `fog.luau`), and `onResolve`'s existing progressive per-cell reveal was
  already the only place that needed to touch the enemy board, so removing the redundant
  full-board redraw was the whole fix. `BuildPalette.luau` pre-selects "Place Base" for setup;
  weapon rows show live "ready"/"cooling Ns"/"building" state (`nextFireAt`/`underConstruction`
  threaded through both controllers' `getWeapons()`); `RoundClock.luau` gained a Supply/Energy
  readout (net-new — no such display existed anywhere in the client before this session, not a
  rework of an existing one). Match clock / no-round-counter was already satisfied by Sessions
  011-013's real-time rework, confirmed rather than changed. Live user testing surfaced two
  further bugs fixed in the same session (not in the original artifact list): weapons couldn't
  be targeted until construction finished (`getWeapons()` was filtering them out entirely —
  removed, since the rules layer never required completion either), and retargeting a live
  weapon didn't take because the display read from an optimistic client-only `self.targets`
  cache instead of the structure's own `.target` (removed the cache in favor of reading
  `structure.target` directly, and fixed a matching stale gate in `server/MatchService.luau`).
  Also, at the user's explicit request, `Rules.checkVictory`'s incapacitation ending is now
  decided by score (`decideByPoints`, same as time-limit and mutual base elimination) rather
  than an automatic win for the other side — surfaced by the Session 013 Supply-squeeze finding
  leaving no path to a win during testing. `lune run test`: 84/84. `rojo build` clean.
  User-confirmed live in Studio across each fix.

### Weapon inspection and control panel

- **Status:** done (Session 021)
- **Prerequisites:** Client real-time UI
- **Success criterion:** Selecting a placed weapon on the battlefield surfaces an info card
  (bottom-right of the screen) showing its live stats — range, damage, cooldown, current
  target — and a control to enable/disable its automatic firing without bulldozing and
  replacing it. The card's layout leaves room for upgrade controls to be added later without
  a rework of the panel itself.
- **Artifact:** a weapon-select interaction on the battlefield (client), the info card
  component, and a `structure.enabled`-style flag threaded through `Structures`/`Rules.tick`'s
  fire gate (shared) for the enable/disable control.
- **Note (raised Session 014):** deliberately left unscoped for now — needs its own design
  pass before implementation (how a weapon gets "selected" on the board vs. from the
  BuildPalette list it has today, how a disabled weapon reads visually on the battlefield).
  Upgrades themselves are explicitly out of scope here and not yet their own entry — this
  card is meant to be the future home for upgrade controls once that feature is actually
  designed, not a prerequisite that must land alongside it.
- **Finding (Session 015):** at the user's request, single shot is now the rules core's
  default (a fired weapon clears its own target and needs a fresh target command to fire
  again) and the underlying flag this entry's artifact list anticipated already exists as
  `structure.autoFire` (default `false`; `true` keeps a weapon firing on its own target every
  cooldown, the practice-mode dummy's own setting since nothing else re-arms it). This entry's
  remaining scope is purely the UI — the info card and a control wired to the existing flag —
  not the flag itself.
- **Outcome:** Design settled at the Open Gate: selection has no persistent mode, and the
  disabled-weapon visual question resolved to marking the opt-in state (`autoFire = true`)
  rather than the default. `Structures.setAutoFire`/`State.setAutoFire`/a new `autoFire`
  `Rules.applyCommand` case mirror `target`'s existing shape end to end (both controllers,
  `MatchService`). A new `WeaponInfoCard.luau` (bottom-right, plain `UIListLayout` column so
  upgrade controls can be appended later) shows range/damage/cooldown/target plus the toggle;
  `StructureView.luau` adds a small gold marker on any own weapon with `autoFire = true`.
  Live user testing drove two real revisions beyond the original design: the info card was
  unreachable at first — selection only fired on a plain left-click while no tool was armed,
  but a tool stays armed after use (so repeat placement doesn't need re-arming), so it was
  essentially never "none" once a match was underway. Moved to right-click instead (entirely
  unused elsewhere — camera is WASD/wheel/Tab only), independent of whatever tool is armed on
  left-click; arming a weapon's target from BuildPalette's list now also selects it for the
  card, at the user's request, notifying through the existing `onChange` chain rather than
  threading a direct `WeaponInfoCard` reference into `BuildPalette`. A weapon's status
  (BuildPalette's list and the card) now also distinguishes "not powered" (off cooldown but
  can't currently afford its Energy cost) from a plain "ready," added after the finding below
  made an idle-looking weapon confusing. `lune run test`: 107/107 (106 + 1 new spec covering
  `setAutoFire`). `rojo build` clean. User-confirmed live in Studio across each iteration
  (right-click selection, BuildPalette arm-also-selects); the newest "not powered" status
  display itself hasn't had an explicit live confirmation pass yet.
- **Finding (Session 021):** live testing surfaced a real, pre-existing rules-core issue,
  distinct from anything this entry built: `planShots` (`rules.luau`) pays out the shared
  Energy pool to whichever weapon it checks first each tick — always whichever was built
  first, usually the cheap cannon — so a costlier weapon (mortar) can sit off-cooldown,
  targeted, and starved indefinitely once a cheaper weapon is also drawing continuously.
  Measured directly: a mortar alone on one generator gets 4 shots in 60s; add a cannon on
  auto-fire too (same generator) and the mortar drops to 1 while the cannon gets 9. This is
  the same effect Session 019/020 documented and worked around for the sim's bot strategies
  (`sim/loadout.luau`'s hold-fire logic, `Kit.chooseTargets`'s `holdFire` parameter in
  `src/shared/archetypeKit.luau`) but never applied to real players' or the real bot's weapons
  firing through `planShots` directly. Not fixed here — it's a rules-core Energy-allocation
  change affecting every weapon, not an info-card scope item; the user asked for it to be
  logged for a follow-up rather than fixed inline. See the "Notes" section below.

### New weapon types: missiles and scout drones

- **Status:** done (Session 016)
- **Prerequisites:** none — the weapon roster (`config.STRUCTURES`) and fire pipeline
  (`Rules.tick`/`Flight.luau`) are already generic across weapon types, so this can start
  whenever it's scoped.
- **Success criterion:** both new types are real, playable `config.STRUCTURES` entries with
  build-menu entries reusing the existing cost/afford display; `lune run test` passes;
  user-confirmed live in Studio.
- **Artifact:** `config.luau` (`missile`/`scout` entries, `POINTS` table additions),
  `BuildPalette.luau` menu entries, `Bot.luau` (missile only), `Render.luau`/
  `StructureView.luau`/`Result.luau` display metadata.
- **Outcome:** Missile is arc fire (unblockable by terrain like the mortar), the longest
  range and biggest single hit in the roster, no splash, slower cooldown, higher cost, later
  unlock — a precision long-range role distinct from the mortar's area denial. Scout drone is
  a non-damaging weapon: reuses the existing target/cooldown/`planShots` pipeline unchanged,
  just with `damage = 0`, so firing it only ever reveals fog via the pipeline's existing
  `Fog.applyReveal` call — no new data shape, no `Rules.tick`/`Flight.luau`/`Fog.luau` changes
  needed. Bot's `buildWeapons` roster picked up the missile (tried first once unlocked); the
  scout drone stays player-only — it needs a placement-strategy design the bot doesn't have,
  deliberately deferred rather than bolted on. `sim/` untouched, still owned by "Sim harness
  rewrite" below. Found and fixed a real bug on read: `applyWeaponDamage` gated splash on
  `def.fire_mode == "arc"` rather than `def.splash` being set, which only ever worked because
  the mortar was the only arc weapon so far — the missile (arc, no splash) would have crashed
  on first fire under the old check. `lune run test`: 87/87 (85 + 2 new, covering the
  splash-coupling fix and the scout's zero-damage/reveal behavior). `rojo build` clean.
  User-confirmed live in Studio, alongside the still-outstanding Session 015 confirmation
  (bot re-adaptation, single-shot combat, build-menu pricing) this session's playtest also
  covered.

### Sim harness rewrite

- **Status:** done (Session 017)
- **Prerequisites:** Real-time rules core
- **Success criterion:** `sim/harness.luau` moves from discrete per-round match stepping to
  discrete time-step stepping mirroring entry 1's fixed tick. Every existing round-keyed
  metric — rounds-to-first-base, match-length distribution, comeback rate, cannon block rate,
  victory-condition distribution, win-rate matrix — is re-derived in time-keyed terms (e.g.
  time-to-first-base instead of rounds-to-first-base). `lune run sim` (round robin) and
  `lune run sweep` both still run a full batch from the terminal and produce every metric.
- **Artifact:** `sim/harness.luau`, `sim/archetypes/*`, `sim/sweep.luau`, `sim/metrics.luau`.
- **Note:** Can run in either order relative to "Client real-time UI" — both only need "Real-
  time rules core" done first.
- **Outcome:** Archetypes now `decide()` on a periodic cadence (`config.BOT_DECIDE_INTERVAL_
  SECONDS`, same as `server/Bot.luau`) instead of once per round, applying commands immediately
  via `Rules.applyCommand` and stepping the match with `Rules.tick`. The five archetypes' dead
  `view.round`/`UNLOCK_ROUND`/`unlock_round` references (dead since Session 011) are now
  `view.elapsed`/`UNLOCK_TIME`/`unlock_time`. Found and fixed two real bugs on the first real
  runs: freshly-placed structures start `underConstruction`, so every match instantly hit
  `base_elimination` until the harness called `State.completeAllConstruction` right after the
  opening `decide()` call (mirroring `MatchService`'s setup → live transition); and the sweep's
  `generatorHeavy` POINTS preset replaced `config.POINTS` wholesale with a Session-003-era
  literal missing the `reveal`/`hit`/`missile`/`scout` entries added since, crashing the moment
  anything got revealed — fixed by mutating the real table in place instead of replacing it.
  Time-keyed durations land on scattered elapsed values rather than a handful of round numbers,
  so `matchLengthDistribution`/`timeToFirstBaseDistribution` bin to 10-second buckets to stay as
  compact as the old round-based histograms. `lune run test`: 87/87. `lune run sim` (5,000
  matches) and `lune run sweep` (all 24 config points, three passes) both complete and print
  every metric. The sweep still finds zero survivors — the same structural finding Session 003
  made (cannon block rate near 0%, standing points reward structures over terrain), restated in
  time terms rather than re-litigated; `sim/output/shortlist.md` has the fresh numbers.
  Missile/scout stayed out of the sim archetypes (cannon/mortar only), per the Open Gate's
  scoping call — user-confirmed, matching the real bot's own scout-drone deferral.

### Ship polish and balance pass

- **Status:** done (Session 019)
- **Prerequisites:** Bot opponent, Sim harness rewrite, Client real-time UI, Bot re-adaptation
- **Success criterion:** Resolve-phase feedback (projectile arcs, impacts, crumbling rubble, terrain rise/fall) is polished, the README documents run/sync/asset-name/config-tuning instructions, a balance pass is applied from a fresh sweep shortlist (produced by the rewritten, time-keyed harness above — the Session 003 shortlist no longer applies), and every self-playtest check from the proposal (win, loss, blocked shot, cleared shot, stale plot, exploit check, each victory condition, restart) passes.
- **Artifact:** polished client feedback, README, final tuned `config.luau`.
- **Note:** Kept as one entry rather than split (Session 010 call) — the sim-harness port and
  the balance sweep it enables are sequential steps of the same "get a trustworthy shortlist
  again" effort, not independently useful halves.
- **Finding (Session 013):** `STARTING_SUPPLY` (10) covers exactly one of Cannon (`supply_cost`
  10) or Generator (`supply_cost` 8), never both, at the very start of live play. In practice
  this meant every practice match tested this session opened with a cannon and no generator, the
  generator never got circled back to, and the match ended in an incapacitation loss once
  starting Energy drained with no income to replace it — regardless of score. Confirmed as a
  configured number working as configured, not a logic bug; revisit alongside the other
  placeholder economy values this entry already owns.
- **Finding (Session 017):** all four prerequisites are now done — this entry is fully
  unblocked. Its own fresh sweep shortlist (the thing its success criterion says it needs)
  found zero survivors, same structural cause Session 003 found: standing points reward
  structures over terrain, and cannon block rate stays near 0% since a fully-informed scripted
  agent never targets a ridge it can see visibly. Neither is fixable by the config knobs this
  sweep tunes. See `sim/output/shortlist.md` for the current numbers — re-deriving this entry's
  scope means deciding whether/how to address those two structural issues before a balance pass
  can mean anything, not just re-running the sweep with different knobs.
- **Outcome:** Re-derivation concluded the structural finding was really about archetype
  passivity, not missing terrain scoring — added `sim/archetypes/rush.luau` (fast opening,
  focus-fire) and `Kit.chooseTargets` gained an optional `focusBases` parameter so weapons can
  commit to one target instead of randomizing; time-limit share dropped from ~100% to ~60-70%
  and terrain investment (`highground`) stopped being uniformly punished, no `POINTS` change
  needed. Re-ran the sweep with `rush` included; still zero literal survivors of its 60%-bar
  (best 66%), accepted per the user's call — that's a defense-side balance question for a
  future session. Applying the sweep's own picks live surfaced two as broken rather than
  suboptimal: `CANNON_RANGE` 8 left `defilade`'s deliberately-set-back cannons unable to reach
  anything all match (never fired), and `ENERGY_PER_GENERATOR_PER_SECOND` 0.05 starved mortars
  almost entirely since cheaper cannons always claim the shared Energy pool first each tick —
  both found by building a second archetype (`sim/archetypes/recon.luau`) and instrumenting
  shot counts, not by the sweep itself. Overrode to 14 and 0.15 (the sweep's own other tested
  candidate); `base_elimination` rose from ~0.1% to ~5% field-wide once `recon` also stood its
  cannons down once a mortar existed to finish the job. Final tuned `config.luau`: `RAISE_COST`
  6, `RECLAIM_COST` 8, `SUPPLY_PER_SECOND` 0.7, `ENERGY_PER_GENERATOR_PER_SECOND` 0.15,
  `MATCH_SECONDS` 200, cannon range 14, mortar range 20. Resolve-phase polish: fixed the
  player's own board doing a full destroy-and-rebuild every tick (same anti-pattern Session 014
  fixed for the enemy board, never applied here) so raise/lower/reclaim now tween instead of
  snapping, and destroyed structures now crumble into rubble instead of popping. Wrote
  `README.md` (didn't exist before). `lune run test`: 89/89. The self-playtest checklist itself
  was **not run** — needs a live Studio pass, carried to the next session's starting state,
  same as Session 018's still-unconfirmed Restart/base-cap-UI items. A follow-up design
  conversation (sim weapon strategy is duplicated per-archetype by literal type name, which is
  why `missile`/`scout` are unused by any sim archetype despite being stat-complete since
  Session 016) produced a new plan entry, "Sim weapon roles and loadout matrix", rather than
  being built ad hoc here.

### Scout drone reveal shape

- **Status:** done (Session 018)
- **Prerequisites:** none — "New weapon types: missiles and scout drones" (done, Session 016) is
  the only thing this builds on.
- **Success criterion:** A fired scout drone reveals a 3-cell-wide corridor along its flight
  path from the firing structure's cell to its target, plus a 4x4 block around the target cell.
  The cannon's beam reveal and the mortar/missile impact reveal (impact cell + its four
  orthogonal neighbours) are unchanged. `Fog.revealedCells` branches on `def.reveal_mode` —
  today a per-weapon field in `config.luau` (`"beam"` for cannon, `"impact"` for everything
  else) that nothing reads, so the shape is keyed off `fire_mode` and every arc weapon shares
  the mortar's 5-cell reveal — with a new `"scout"` value for the drone. `Fog.applyReveal` takes
  the firing weapon's origin cell so there's a start point to walk the corridor from; the caller
  in `rules.luau` already holds it. Covered by fog specs (corridor width, target block, cells
  clipped at the board edge, unchanged cannon/mortar shapes); `lune run test` passes;
  user-confirmed live in Studio.
- **Artifact:** `src/shared/fog.luau`, `src/shared/rules.luau` (thread origin through to
  `applyReveal`), `src/shared/config.luau` (`reveal_mode = "scout"`), plus `fog.spec.luau` /
  `rules.spec.luau`.
- **Note (raised Session 017):** the point of the change is that the cannon currently reveals
  more ground than the weapon whose whole job is recon, which is backwards. The 3-wide corridor
  and 4x4 block are sized against today's island; revisit both numbers if the board is ever
  enlarged, so the drone's footprint stays proportionate.
- **Outcome:** Shipped as scoped — `Fog.revealedCells` branches on `def.reveal_mode`
  (`"beam"`/`"scout"`/default-impact), `Flight.beamCells` exported for the corridor walk,
  `Fog.applyReveal`/`rules.luau`/`Render.luau` thread the firing origin through. 4x4 block
  anchored `[target-1, target+2]` on both axes; diagonal corridor widens on whichever axis has
  fewer steps. `lune run test`: 90/90 at the time (87 + 3 new fog specs), later 89/89 after an
  unrelated same-session test removal (see below). User-confirmed live in Studio.
  User feedback in the same session drove five more changes, all shipped: scout
  `supply_cost` 12 → 4 (was priced like a Cannon for a zero-damage weapon); a real bug fix in
  `PlanController:stopClock()` (was a no-op, leaking the `StateUpdate` connection across
  restarts and breaking Restart for bot/online matches — Practice was unaffected); setup's
  "Place Base" tool now grays out/deselects once `NUM_BASES` is placed, matching a new general
  rule that any round tool (weapon or terrain edit) auto-deselects once unaffordable; Raise/
  Lower/Reclaim now show their Supply cost like weapons do (`BuildPalette.luau` gained a
  `costKey` alongside `typeId` for tools with no `config.STRUCTURES` entry); and
  `UNLOCK_TIME.terrain_edit` 20 → 0 (terrain shaping is available from the start of live play,
  not gated behind an elapsed-time window that happened to coincide with early weapon unlocks).
  `state.spec.luau`'s "terrain editing is locked before its unlock time" test was removed as
  obsolete under the 0-second unlock (`reclaimLand`'s own lock test already covers the same
  `requireUnlocked` mechanism). Restart and the base-cap UI fix weren't individually
  re-confirmed live after landing — see the session log's "Notes for next session."

### Sim weapon roles and loadout matrix

- **Status:** done (Session 020)
- **Prerequisites:** none hard. Everything it builds on is already done — "New weapon types:
  missiles and scout drones" (Session 016), "Sim harness rewrite" (Session 017), "Scout drone
  reveal shape" (Session 018). Nothing about the shipped game is blocked on this; what's blocked
  is the sim's own coverage, which is the thing "Ship polish and balance pass" has to be able to
  trust. Worth landing before that entry's shortlist is treated as the balance answer — a sweep
  run against a field where no archetype ever builds a missile or a scout drone is tuning half
  the weapon roster blind.
- **Success criterion:** (a) `missile` and `scout` are built and fired by at least some sim
  archetypes — a full `lune run sim` round robin reports non-zero `Metrics.purchaseShare` and
  non-zero shots fired for both — and they get there by being *declared*, not by hand-writing a
  bespoke eighth and ninth archetype file. (b) The cannon stand-down currently hand-written
  inline in `sim/archetypes/recon.luau` (the `standDown` local in `chooseReconTargets`) is
  deleted and replaced by a declared per-weapon hold-fire condition every archetype gets for
  free, so no cheap weapon spends the match draining the shared Energy pool a costlier one is
  saving for. (c) Energy sizing is derived from a loadout's actual aggregate draw (each active
  weapon's `energy_cost / cooldown_seconds` against `ENERGY_PER_GENERATOR_PER_SECOND`) instead
  of each archetype's hand-picked `GENERATOR_TARGET` literal. (d) A curated adversarial
  base-placement suite runs *alongside* (not instead of) `Kit.spreadPick`'s randomized spread —
  at minimum all-three-clustered-in-one-corner, all-three-in-a-back-row, and decoy-forward /
  real-bases-deep — as its own fast, cheap pass, reporting per-layout victory-condition and
  time-to-first-base breakdowns; any archetype that fails to ever locate a base under a layout is
  named as a blind spot and gets a real fix, not a note. (e) `sim/` gains its first test coverage
  under `tests/` (`tests/metrics.spec.luau` already specs `sim/metrics.luau` from there — same
  pattern, no new runner): at minimum a short-match smoke spec asserting that every registered
  archetype places its bases, ends the match having fired at least one shot, and has at least one
  weapon whose range actually reaches enemy territory under the shipped config — literally the
  assertion that would have caught `defilade` below in one `lune run test` instead of hiding for a
  session behind multi-minute aggregate runs. (f) The intake checklist for adding a new weapon or
  structure to the sim is written down where the next person will hit it (README plus the module
  header comments `sim/` already uses to carry this kind of rule), and is demonstrated end to end
  on one weapon rather than just asserted. `lune run test` passes; `lune run sim` and `lune run
  sweep` still produce every metric "Sim harness rewrite" listed.
- **Artifact:** `sim/archetypes.luau` (flat 7-entry registry → loadout generator),
  `sim/archetypes/*.luau`, `src/shared/archetypeKit.luau` (`Kit.chooseTargets` gains the declared
  priority/hold-fire hooks; `Kit.spreadPick` gains a curated-layout sibling), `sim/harness.luau`
  (the placement-suite pass), `sim/metrics.luau` / `sim/report.luau` (per-loadout and per-layout
  breakdowns), new `tests/*.spec.luau`, README. **The shape below is a starting proposal to
  validate, not a mandate** — it came out of Session 019's conversation and reconsidering it is
  this entry's first job, the same way "Weapon inspection and control panel" holds its own design
  open: a `sim/weaponRoles/<typeId>.luau` module per weapon type, sitting alongside (not inside)
  its `config.STRUCTURES` stats entry, declaring a category tag (recon / direct-damage /
  arc-finisher / support-economy), a build trigger, a target priority, and a stand-down
  condition; archetypes then become declarative loadouts — an ordered list of category slots
  (e.g. one recon slot + one finisher slot) — that the harness fills combinatorially from each
  category, so weapon pairings get covered without hand-authoring an archetype file per
  combination. Whether those roles stay in `sim/` or get promoted to `src/shared/` the way
  `view.luau` (Session 008) and `archetypeKit.luau` (Session 009) were is an open question this
  entry should answer rather than assume — `server/Bot.luau` has the same per-weapon-by-name
  hardcoding and the same missing scout-drone placement strategy that Session 016 deliberately
  deferred.
- **Finding (Session 019):** two sweep-chosen config values turned out to be empirically
  catastrophic and had to be overridden by hand, diagnosed with an ad hoc instrumented script
  rather than by the sweep itself. `CANNON_RANGE` 8 meant `defilade` — which deliberately sets its
  cannons back from the frontline — never fired a single shot in an entire match; now 14.
  `ENERGY_PER_GENERATOR_PER_SECOND` 0.05 meant mortars (3 Energy) almost never fired even with
  nothing else competing for the pool, because `planShots` (`rules.luau`) pays out to whichever
  weapon it checks first each tick — always the cheaper cannons (1 Energy), built first — so the
  shared pool never accumulated a mortar's worth; now 0.15, which was the sweep's other tested
  candidate rather than a fresh guess. Both point at the same gap this entry owns: the sweep
  optimizes its own fairness formula and has no notion of a weapon being structurally unable to
  fire, and `sim/` has no test coverage at all (`lune run test` only reaches the pure
  `src/shared/` layer), so the only validation is eyeballing aggregates off thousands-of-match,
  multi-minute runs.
- **Finding (Session 019):** even after both overrides, `base_elimination` only rose to ~5% of
  matches sim-wide — `time_limit` and `incapacitation` still decide nearly everything — and `rush`
  (added this session) takes ~87% of its matches. The `recon` stand-down raised mortar
  participation, but only for `recon`: it is one hand-written `if` inside one archetype file.
  `missile` and `scout` have been complete, stat-balanced `config.STRUCTURES` entries since
  Session 016, used by the real game and (missile) by `server/Bot.luau`, yet zero sim archetypes
  reference either — every archetype hardcodes build order and targeting per weapon by literal
  string (`Kit.countType(view, "cannon") < CANNON_TARGET`), copy-pasted and hand-tweaked across
  seven files. There is no structural reason for the omission; nobody has hand-written the inline
  logic. Base placement likewise has exactly one mode — `Kit.spreadPick`'s greedy farthest-point
  sampling from a random start — so no archetype's exploration behaviour has ever been tested
  against a deliberately awkward layout.
- **Note (raised Session 019):** the user's framing, in their terms: each weapon type should be
  worked into the sim's strategies *as it is added to the game*, shaped by its particular
  strengths rather than bolted on generically or left out; not every archetype needs every weapon
  — grouping weapons into categories and running combinations drawn from likely groupings is the
  preferred shape; Energy production should be sized to what a loadout actually needs to sustain
  fire, or weapons should stand down when they aren't needed for the win; and base placement
  should keep its randomization but add a small curated set of "gotcha" layouts specifically to
  expose exploration blind spots. Above all they asked for "some sort of matrix or intake/creation
  process for new weapons and structures as we add them" — a repeatable checklist so a new weapon
  lands in the sim by process rather than by someone remembering to write bespoke archetype logic.
  Proposed intake steps, to be confirmed or replaced by this entry's design pass: (1) the
  `config.STRUCTURES` stats entry — the existing, working process, unchanged; (2) a weapon-role
  entry; (3) an Energy-sustain figure, preferably derived from `energy_cost`/`cooldown_seconds`
  rather than hand-maintained; (4) a category tag so the loadout generator picks the weapon up
  with no archetype edits at all.
- **Outcome:** Reconsidered the plan's own starting shape at the Open Gate and simplified it:
  roles live in a single flat `sim/loadout.luau` table (not one file per weapon type) and stay
  in `sim/`, not promoted to `src/shared/` — `server/Bot.luau` isn't a real second consumer yet,
  so promoting was premature; deferred the same way Session 016 deferred scout-on-bot. The 7
  existing archetypes kept their own terrain/tempo doctrine (that's real strategic personality,
  not weapon-role logic) rather than being flattened into pure category-slot loadouts; only
  their weapon build/target block changed. `Kit.chooseTargets` gained a plain `holdFire`
  typeId-set parameter (no category concept in the shared layer), fed by
  `Loadout.holdFireSet` — a cheap weapon (cannon) now holds fire once a costlier one
  (mortar/missile) exists *and* something's actually plotted to shoot at, generalizing
  `recon.luau`'s deleted inline check to all 7 archetypes (b). `Kit.energySustainTarget`
  replaced every archetype's hand-picked `GENERATOR_TARGET` with a number derived from
  `energy_cost`/`cooldown_seconds` (c). Missile and scout went into `boomer` and `recon`
  respectively — the two archetypes whose existing doctrine already fit each weapon's category
  — not new files (a); `lune run sim` confirms non-zero purchases and shots fired for both.
  `sim/placementSuite.luau` added the three curated layouts as a fast pass inside `lune run
  sim` (d); the first version pinned bases to the absolute edge of territory and found 5 of 7
  archetypes never finding a base at all, which turned out to be two real bugs rather than
  balance noise — `defilade` placing its own cannons beyond their own range (the same class of
  bug §18 already fixed once for a different cause, now fixed by deriving the cannon's depth
  from `CANNON_RANGE` instead of hardcoding "the backmost cell"), and the curated layouts
  themselves testing raw range instead of exploration behavior (softened to 60% depth). A third
  bug, found via `lune run sim`'s purchase-share report rather than the suite: `boomer` never
  once bought a missile, because its spend loop let mortar (always affordable first) drain
  Supply to near-zero every cycle before missile's pricier threshold could ever accumulate —
  fixed by having it bank Supply toward an already-unlocked pricier weapon instead. After both
  fixes, no archetype shows a 0%-ever-found rate under any curated layout;
  `tests/sim.spec.luau`'s smoke spec (e) is what would have caught the defilade regression in
  seconds instead of a multi-minute aggregate run. README's new "Adding a new weapon or
  structure to the sim" section (f) is the checklist, demonstrated on missile/scout. `lune run
  test`: 106/106 (89/89 at session start). `lune run sweep` wasn't re-run in full (each pass is
  ~15,000+ matches and a fresh balance pass wasn't this entry's job) — confirmed instead that
  its call surface into `sim/archetypes.luau`/`Harness` is unchanged. `server/Bot.luau` untouched,
  per the Open Gate scoping call.

### Fair Energy allocation across weapons

- **Status:** done (Session 022)
- **Prerequisites:** Weapon inspection and control panel (Session 021 — the finding this
  entry fixes)
- **Success criterion:** `planShots` (`rules.luau`) no longer systematically favors whichever
  weapon type happens to be cheapest and built first when multiple weapons share one Energy
  pool; the starvation scenario Session 021 measured ad hoc (mortar alone: 4 shots/60s; mortar
  alongside an auto-firing cannon: 1) has permanent Lune coverage instead of a throwaway
  script.
- **Artifact:** `src/shared/rules.luau` (`planShots`), `tests/rules.spec.luau`.
- **Outcome:** A plain reorder (check the costlier weapon first each tick) was proposed and
  then invalidated by direct measurement before shipping: against the real config numbers it
  changed nothing (cannon 9 / mortar 1, identical to the original bug), since cannon's 1-Energy
  threshold is so far below mortar's 3 that same-tick reordering never lets the pool sit still
  long enough to reach 3. The fix that actually works is a full stand-down: a cheaper weapon
  doesn't spend at all while a costlier one is also eligible to fire this tick, generalizing
  `sim/loadout.luau`'s hold-fire pattern (a declared category table) into a direct Energy-cost
  comparison over `planShots`' real per-tick candidate set. Measured, this flips the scenario
  to mortar 4 / cannon 1 — the mortar gets its full solo output, but the cannon is now the
  suppressed side. That tradeoff (a hard swing toward whichever costs more, not an even split)
  was surfaced to the user before shipping and confirmed as intended over building a
  proportional-split allocator, which would need real new design and its own tuning pass.
  `server/Bot.luau` needed no changes — it has no firing/Energy logic of its own, so it
  inherits the fix automatically through the same `planShots`. Live-testing this fix surfaced
  two separate, pre-existing bugs (not caused by this change) that made an unrelated match
  outcome look wrong: the Result screen inferred which side was incapacitated from the
  points-decided `winner` (backwards whenever the incapacitated side wins on points, per
  Session 014's own decision) — fixed by having `Rules.checkVictory` return
  `incapacitatedSide` directly; and the real cause underneath, `State.withPlayer`'s
  `pairs()`-based merge can never actually clear a field to `nil` (a Lua table literal with a
  `nil` value simply omits the key), so a player who recovered from a brief early Energy/Supply
  squeeze stayed flagged incapacitated forever and could still end the match on a stale
  timestamp long after their economy was healthy — fixed with a new
  `State.setIncapableSince` (direct field assignment) in place of the generic merge for that
  one field. `lune run test`: 110/110 (107 at session start). `rojo build` clean. User-
  confirmed live for the original energy-allocation fix (that's how the confusing incapacitation
  outcome was found); the two incapacitation fixes have automated coverage but no dedicated
  live re-confirmation pass yet.

---

## Notes

Free-form project notes.

- **Fixed inventory / build-count caps (raised Session 018):** a general lever the user
  wants available for the buy menu — capping how many of a given structure type a player
  can have built at once (the way setup's 3 bases already work, just generalized and
  exposed as a real per-type config knob rather than base's one-off hardcoded
  `NUM_BASES`/ready-gate special case). Not needed by anything built so far; no plan entry
  yet. Revisit if/when a specific weapon or structure actually needs a cap.
