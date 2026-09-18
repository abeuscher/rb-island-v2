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

- **Status:** open, scope pending design
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

- **Status:** open, scope pending re-derivation
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

### Scout drone reveal shape

- **Status:** open
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

---

## Notes

Free-form project notes.
