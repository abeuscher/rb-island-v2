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

- **Status:** open
- **Prerequisites:** Full match loop and wrapper screens
- **Success criterion:** Two Studio clients can matchmake, complete setup, and play a full match against each other with the server holding all authoritative state — enemy structures never exist client-side before being revealed — and an exploit check confirms no unrevealed enemy structure appears in either client's Instance tree or remote payloads.
- **Artifact:** `server/Replication.luau`, `CommandHandler.luau`, rate-limited remotes.

### Bot opponent

- **Status:** open
- **Prerequisites:** Real two-player networking
- **Success criterion:** The bot FSM builds its opening layout, shapes terrain, probes with cannons, suppresses generators, concentrates fire on plotted bases, and rebuilds — using only its own fog/belief map — across all three difficulty presets, and a player can lose to it.
- **Artifact:** `server/Bot.luau`.

### Ship polish and balance pass

- **Status:** open
- **Prerequisites:** Bot opponent, Simulation harness and first balance sweep
- **Success criterion:** Resolve-phase feedback (projectile arcs, impacts, crumbling rubble, terrain rise/fall) is polished, the README documents run/sync/asset-name/config-tuning instructions, a balance pass is applied from the sweep's shortlist, and every self-playtest check from the proposal (win, loss, blocked shot, cleared shot, stale plot, exploit check, each victory condition, restart) passes.
- **Artifact:** polished client feedback, README, final tuned `config.luau`.

---

## Notes

Free-form project notes.
