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

- **Status:** open
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

### MatchService real-time loop

- **Status:** open
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

### Bot re-adaptation

- **Status:** open
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

### Client real-time UI

- **Status:** open
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

### Sim harness rewrite

- **Status:** open
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

### Ship polish and balance pass

- **Status:** open, scope pending re-derivation
- **Prerequisites:** Bot opponent, Sim harness rewrite, Client real-time UI, Bot re-adaptation
- **Success criterion:** Resolve-phase feedback (projectile arcs, impacts, crumbling rubble, terrain rise/fall) is polished, the README documents run/sync/asset-name/config-tuning instructions, a balance pass is applied from a fresh sweep shortlist (produced by the rewritten, time-keyed harness above — the Session 003 shortlist no longer applies), and every self-playtest check from the proposal (win, loss, blocked shot, cleared shot, stale plot, exploit check, each victory condition, restart) passes.
- **Artifact:** polished client feedback, README, final tuned `config.luau`.
- **Note:** Kept as one entry rather than split (Session 010 call) — the sim-harness port and
  the balance sweep it enables are sequential steps of the same "get a trustworthy shortlist
  again" effort, not independently useful halves.

---

## Notes

Free-form project notes.
