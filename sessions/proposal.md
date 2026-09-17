# ISLAND SIEGE (working title) — Build Specification

A 1v1 Roblox strategy game in the shape of *Metal Marines*. Two players hold facing islands across a channel. Each round, both players build, reshape their terrain, and aim their weapons under the same clock — then both volleys fire at once and both players watch what happens. Islands start small, flat, and simple, and grow in size, elevation, and complexity as the match progresses.

This document is written for autonomous execution by a coding agent. **Read the whole spec, then build the milestones in order without stopping to ask questions.** When a decision is ambiguous, make a reasonable call, record it in `DECISIONS.md`, and continue.

---

## 1. Design Pillars

If you deviate from one, record it in `DECISIONS.md`.

1. **The volley is the loop.** Plan, commit, watch everything fire at once, learn from what you saw, spend, go again. Every system serves that rhythm.
2. **Terrain is public. Structures are secret.** Both players always see the full shape and elevation of both islands. What is *built* on the enemy island is hidden until revealed. Reasoning about a visible ridgeline is the good kind of hidden information; a gray rectangle is not.
3. **Elevation is the tactical system.** Fixed integer levels on a fixed grid, like XCOM or a tactics game. Height buys range and sight; low ground buys cover. Terrain is not decoration.
4. **The island grows.** Small, flat, and legible at the start; larger, taller, and more complex by the end. Complexity is unlocked over the course of a match, not dumped on the player at round 1.
5. **Small roster, working loop.** v1 ships one generator and two weapons. Prove the volley feels good before adding anything.
6. **No avatars.** Players never control a humanoid character. This is a board viewed from above.

---

## 2. Tech Stack & Constraints

- **Roblox / Luau, file-based via Rojo.** Authored as files on disk, synced with `rojo serve`. Nothing may live only inside a `.rbxl`.
- **The rules core is engine-agnostic.** Everything in `src/shared/` is pure Luau with **zero Roblox API calls** — no `Instance`, no `workspace`, no `task.wait`. It takes a state table and commands and returns a new state. The Roblox layer is a thin adapter.
  - This exists so the rules run headlessly under **Lune** (`lune run test`). It is the only part an agent can verify without a human opening Studio, so it must carry as much logic as possible — including all elevation, line-of-flight, and fog math.
- **One serializable `MatchState`.** `rules.resolveRound(state, commandsA, commandsB) -> state, events`. Pure; no mutation of the input.
- **All tuning numbers live in `src/shared/config.luau`.** Nothing numeric hardcoded elsewhere.
- **Server authoritative over everything.** See §12.
- **No dependencies** beyond Rojo and Lune.

### Repo layout

```
/src
  shared/
    config.luau        -- ALL tuning constants
    state.luau         -- MatchState types + initializers
    rules.luau         -- pure round resolution
    board.luau         -- grid, territory, elevation, expansion
    flight.luau        -- line-of-flight, beam interpolation, arcs
    economy.luau
    structures.luau    -- roster data
    fog.luau           -- reveal + stale belief map
  server/
    MatchService.luau  -- lifecycle: lobby -> setup -> rounds -> result
    Replication.luau   -- fog-gated per-player state push
    CommandHandler.luau-- validates every client request
    Bot.luau
  client/
    Board.luau         -- terrain mesh, elevation rendering
    Render.luau        -- structures, projectiles, fog
    Camera.luau
    Input.luau
    UI/                -- build palette, terrain tools, targeting, round clock
/sim
  harness.luau
  archetypes/
  sweep.luau
  out/                 -- gitignored
/tests
default.project.json
DECISIONS.md
SPEC.md
```

---

## 3. Board, Grid & Elevation

### Layout

The board is a single fixed grid, `BOARD_WIDTH` × `BOARD_HEIGHT` (default **40 × 24**) cells. A channel of open water `CHANNEL_WIDTH` cells across (default **6**) runs the full height of the board, splitting it into two mirrored territories.

- Player A owns every cell left of the channel; player B owns every cell right of it.
- **The channel is permanent and unbuildable.** Neither player may ever place land, structures, or terrain in it.
- Each player begins with a **12 × 12 island**, flush against their side of the channel and centered vertically. Everything else in their territory is water they may later reclaim (§9).
- `STUDS_PER_CELL` default **4**. Starting island ≈ 48 studs across; full board ≈ 160 studs.

### Elevation

Fixed integer levels, cubic, no slopes or partial heights. A cell's height is `0`, `1`, or `2` (`MAX_ELEVATION`, default 2).

- Every cell of every island starts at level **0**. Round 1 is played entirely flat (§4).
- Cells render as stacked cubes. One cell, one height value, no interpolation. This is deliberate: fixed values make placement, cover, and line of flight predictable to the player and cheap to compute.
- **Smoothness constraint:** after any edit, no cell may differ from an orthogonally adjacent land cell by more than 1 level. This forbids 1×1 towers and keeps the board readable. Reject any edit that would violate it.
- Structures sit **1 unit above** their cell's terrain height. A structure on a level-2 cell has its muzzle at height 3. This matters for §10.
- Water cells are height 0 and block nothing.

---

## 4. Round Structure — the core loop

The match is a sequence of rounds. Both players act simultaneously against the same clock; neither ever waits on the other.

**PLAN phase** (`PLAN_SECONDS`, default **45s** — see §18, this number is deliberately unresolved):

Both players, at the same time, may do any mix of:
- Place or bulldoze structures on their own island.
- **Edit terrain** — raise or lower cells (§9). *Locked in round 1; unlocked from round 2.*
- Reclaim water into land, once unlocked (§9).
- Assign a target cell to each ready weapon.
- Buy tech unlocks.

Nothing takes visible effect yet. A player who finishes early may ready up; the phase ends when both are ready or the clock expires. Unspent resources carry over. Unassigned weapons simply don't fire.

**RESOLVE phase** (`RESOLVE_SECONDS`, default **10s**, no input):

In fixed order, animated so both players watch the same thing:
1. Terrain edits and land reclamation apply.
2. New structures complete and become live.
3. **Both volleys fire simultaneously.** All projectiles from both players launch together, arc or track to their targets, and resolve.
4. Damage applies; destroyed structures become rubble.
5. Reveals are computed and written to each player's belief map (§11).
6. Income accrues (§7).
7. Win check.

Then the next PLAN phase begins. Round counter increments.

**Why this shape:** it is the satisfying part of Metal Marines — commit a plan under time pressure, watch it all go off, profit from what you learned. It also means neither player ever stares at a dead screen, which is what kills turn-based games on this platform.

### Progression gates

| Round | Unlocked |
|---|---|
| 1 | Flat island. Generator + Cannon only. No terrain editing. |
| 2 | Terrain editing. |
| 3 | Mortar. |
| 4 | Land reclamation. |

Gates are round-based in v1 for predictability. Config: `UNLOCK_ROUND[<id>]`. Later versions may move to resource-purchased tech.

---

## 5. Victory Conditions & Scoring

A match ends the moment any condition below is met. All are evaluated at the end of RESOLVE, in this order.

### 5.1 Base elimination

All three of a player's bases destroyed → that player loses immediately.

Volleys are simultaneous, so **both players can lose their last base in the same resolve.** This is not an edge case to hand-wave; it will happen. When it does, the winner is decided on points (§5.4). Handle it explicitly in `rules.luau` and cover it with a test.

### 5.2 Incapacitation

Two of the stated conditions — out of energy with no way to make more, and out of weapons with no way to buy more — are the same underlying state: the player can no longer affect the match. Implement them as one check, not two.

At the end of RESOLVE, a player is **incapable** this round if:

- they own no live weapon, **or** their Energy is below the cheapest energy cost among their live weapons;

and **unrecoverable** if all of:

- no Generator standing or under construction, **and**
- Energy income for next round is 0, **and**
- Supply is below `generator.supply_cost` **and** below the cheapest weapon's `supply_cost`.

A player who is both incapable and unrecoverable for `INCAPACITATION_GRACE_ROUNDS` consecutive rounds (default **2**) loses immediately. The grace window exists so that being one round away from rebuilding is not a loss — only a genuine dead end is.

Incapacitation is an elimination, not a points result. An incapacitated player loses even if they are ahead on points.

**This condition is dead unless `ENERGY_BASE` is 0.** If every player receives free Energy each round regardless of buildings, they can always eventually fire and this can never fire. So: **`ENERGY_BASE` default is 0** and all Energy income comes from Generators (§7), with `STARTING_ENERGY` (default 4) to cover the opening rounds. This also makes Generators the high-value target they should be — knocking out every generator genuinely silences someone.

### 5.3 Round limit

If `MAX_ROUNDS` (default **5**) completes with no elimination, the higher score wins. This number is a placeholder and expected to move — see §18.

### 5.4 Scoring

Score is the sum of destruction points earned and standing points held. Standing points are counted only at match end.

| Event | Points | Constant |
|---|---|---|
| Destroy an enemy `base` | 100 | `POINTS.destroy.base` |
| Destroy an enemy `mortar` | 35 | `POINTS.destroy.mortar` |
| Destroy an enemy `generator` | 25 | `POINTS.destroy.generator` |
| Destroy an enemy `cannon` | 20 | `POINTS.destroy.cannon` |
| Own `base` standing at match end | 50 | `POINTS.standing.base` |
| Own `mortar` standing at match end | 15 | `POINTS.standing.mortar` |
| Own `generator` standing at match end | 10 | `POINTS.standing.generator` |
| Own `cannon` standing at match end | 10 | `POINTS.standing.cannon` |

Every value lives in `config.luau` and every value is a guess. They exist to be swept (§15), not to be trusted.

Structures under construction score nothing, standing or destroyed. Rubble scores nothing. A structure the player bulldozes themselves scores nothing for either side.

Ties on points: fewest structures lost, then fewest rounds elapsed, then draw. A draw is a legal outcome and the end screen must render it.

---

## 6. Screens & Match Wrapper

Three screens outside the board itself. Build them as real state — `MatchService` owns a session state machine (`INTRO → SETUP → ROUNDS → RESULT → INTRO`), not as UI that happens to appear.

### 6.1 Intro

- **Start Game** — enabled. Begins a new match.
- **Save Game and Continue** — **rendered but disabled**, with a visible "coming soon" treatment. Wire nothing behind it. It exists now so the layout and the eventual session-restore path have a place to live.
- **Settings** — opens the settings panel.

### 6.2 Settings

An empty panel with a title and a close button. No options yet.

Scaffold it so adding one later is a single entry: a `Settings.luau` module exporting an ordered registry of `{ id, label, kind, default, apply }` and a panel that renders whatever the registry contains. An empty registry renders an empty panel. Do not hardcode a list of controls.

### 6.3 Result

Shown on any match end. Declares the winner and **which condition ended the match**, in plain language — "All bases destroyed", "Opponent incapacitated", "Round limit reached", "Draw".

Then a side-by-side breakdown for both players:

- Final score, itemized into destruction points and standing points by structure type.
- Rounds played.
- Structures built, lost, and still standing.
- Shots fired, shots that hit, shots blocked by terrain.
- Cells revealed.

One **Restart** button, returning to a fresh match against the same opponent configuration. (Returning to Intro instead is fine if simpler; the requirement is that a restart never needs a rejoin.)

---

## 7. Resources

Two resources. Both accrue at the end of each RESOLVE phase.

| Resource | Earned per round | Spent on |
|---|---|---|
| **Supply** | Flat `SUPPLY_PER_ROUND` (default 10). | Structures, terrain edits, land reclamation, tech unlocks. |
| **Energy** | `ENERGY_BASE` (default **0**) + `ENERGY_PER_GENERATOR` (default 2) per surviving, non-under-construction Generator. Capped at `ENERGY_CAP` (default 12). Players open with `STARTING_ENERGY` (default 4). | Firing. Every shot costs Energy. |

**Firing must cost Energy, and Energy must come from bombable buildings.** This is the load-bearing economic loop: more generators means more shots per round, generators are visible targets once revealed, and knocking them out throttles the enemy's rate of fire. It is also why cannon fire has a purpose before you have found a base, and it is what makes the incapacitation condition in §5.2 reachable — with `ENERGY_BASE` at 0, destroying every generator genuinely silences a player.

Bases generate nothing. They are purely the win condition, so losing one costs you the match but never your ability to play it.

Never display the opponent's resources.

---

## 8. Structures (v1 roster)

Deliberately minimal. Do not add types until the volley loop is proven.

| id | Name | Supply | HP | Footprint | Behavior |
|---|---|---|---|---|---|
| `base` | Base | free | 40 | 2×2 | 3 placed during setup. Lose all 3 → defeat. Generates nothing. |
| `generator` | Generator | 8 | 8 | 1×1 | +2 Energy per round. |
| `cannon` | Cannon | 10 | 6 | 1×1 | **Direct fire.** Energy 1. Base range `CANNON_RANGE` (default 10) **+2 per level of the firing cell's elevation.** Blocked by terrain (§10). Damage 10 to target cell. Reveals every cell along its beam path (§11). |
| `mortar` | Mortar | 18 | 5 | 1×1 | **Arcing fire.** Energy 3. Range `MORTAR_RANGE` (default 16), unaffected by elevation. Ignores terrain entirely. Damage 14 to target + 6 to the 4 orthogonal neighbors. Reveals only the impact area. Unlocked round 3. |

**Rules:**
- One structure per cell. Structures cannot be placed on a cell being terrain-edited in the same round.
- Build time: structures complete during the next RESOLVE phase. Under construction = inert, half HP.
- Bulldoze: free, instant, no refund. Required before terrain-editing an occupied cell.
- No repair in v1.
- Each weapon fires at most once per round.

The cannon/mortar split exists to make elevation matter in both directions: the cannon is cheap, gains range from height, and does your scouting — but a ridge stops it. The mortar ignores terrain completely but is expensive and slow to accumulate. Height is for shooting and seeing; low ground behind a ridge is for surviving.

### Structure schema

Structures are data. Adding a type should mean a config entry and at most one resolution branch.

```
id, display_name, supply_cost, energy_cost, hp, footprint,
fire_mode ("direct" | "arc" | nil), range, elevation_range_bonus,
damage, splash, reveal_mode, unlock_round, upgrades[]
```

---

## 9. Terrain Editing & Expansion

Both happen inside the PLAN phase, alongside placement and targeting. They are ordinary build actions, not a separate mode.

### Terrain editing (unlocked round 2)

- **Raise** a land cell by 1 level: `RAISE_COST` (default 4 Supply).
- **Lower** a land cell by 1 level: `LOWER_COST` (default 2 Supply).
- Bounded by 0 and `MAX_ELEVATION`.
- The cell must be empty. Bulldoze first.
- The smoothness constraint (§3) is validated at commit time; illegal edits are rejected in the PLAN phase with clear UI feedback, never silently at resolve.
- Multiple edits to the same cell in one round are allowed if each is paid for and the result is legal.
- **Terrain changes are public.** Both players see the new shape at resolve. You cannot secretly build a ridge. This is intended — watching the enemy raise ground and inferring what they are protecting is part of the game.

### Land reclamation (unlocked round 4)

- **Reclaim** a water cell into level-0 land: `RECLAIM_COST` (default 12 Supply).
- Must be orthogonally adjacent to one of your existing land cells.
- Must be inside your own territory. **Never in the channel.**
- Becomes buildable at the next RESOLVE.

Growth away from the channel produces safe rear area for mortars; growth along the channel widens your frontage. Both are legitimate and the choice should stay open.

---

## 10. Line of Flight

Deterministic, integer, and computed entirely in `src/shared/flight.luau`. This is the most important thing to unit-test.

### Direct fire (cannon)

Given firing cell `S` with terrain height `hs` and target cell `T` with terrain height `ht`:

1. Muzzle height is `hs + 1`. Impact height is `ht`.
2. Walk the cells between `S` and `T` using a Bresenham line, exclusive of both endpoints.
3. For each intervening cell `C`, let `t = dist(S,C) / dist(S,T)` and `beam = lerp(hs + 1, ht, t)`.
4. If `terrainHeight(C) > beam`, the shot is **blocked** at `C`. Strictly greater — grazing a ridge at exactly beam height passes.
5. A blocked shot still travels to `C`, impacts there for no damage, and reveals everything up to and including `C`.

Range is measured in cells as Chebyshev distance and is `CANNON_RANGE + 2 * hs`.

### Arcing fire (mortar)

Ignores terrain completely. No blocking check, no elevation bonus. Always reaches its target if in range.

### Elevation summary

| | Direct fire | Arcing fire |
|---|---|---|
| Blocked by terrain | Yes | No |
| Range bonus from height | +2 per level | None |
| Reveals | Full beam path | Impact area only |
| Cost | Cheap | Expensive |

No damage or accuracy modifiers from elevation. The geometry does all the work — do not add multipliers on top of it.

---

## 11. Fog of War & Intel

- **Terrain is always fully visible to both players** — shape, elevation, coastline, reclamation, every edit. No fog over terrain, ever. This is the single most important rule in this document.
- **Structures on the enemy island are hidden** until revealed.
- **Cannon reveal:** every cell along the beam path, up to the impact or block point, is revealed. Height therefore buys information — a cannon on level 2 draws a long sight line across the enemy island. This is why there is no dedicated scout structure.
- **Mortar reveal:** the impact cell and its 4 orthogonal neighbors only.
- **Plots are stale, not live.** A revealed cell records what was there *at reveal time* and stays plotted. If the defender later builds or bulldozes there, the plot is wrong until re-revealed. Do not live-update the belief map. This is the Metal Marines behavior and it is what makes re-probing meaningful.
- Structures destroyed during a volley the attacker witnessed update the plot to rubble.
- Your own island is always fully visible to you.

Unrevealed enemy cells render as ordinary terrain with an empty surface and a subtle "unknown" surface treatment — not as an opaque fog layer. The player should be looking at a landscape, not a wall.

---

## 12. Server Authority

The section most likely to be quietly skipped and the most expensive to retrofit.

- The server holds the full `MatchState`. Clients hold their own island plus their belief map plus public terrain.
- **Never create enemy structure Instances on the client until the server reveals them.** Hiding them with `Transparency`, a `CollisionGroup`, or a fog overlay is not fog of war — positions can be read out of the client's Instance tree in seconds and the whole game is defeated. Revealed structures are spawned client-side on reveal.
- Terrain is public and may be freely replicated. Structures may not.
- All player actions are RemoteEvent *requests* submitted during PLAN and validated server-side: ownership, territory, affordability, unlock round, cell legality, smoothness constraint, build state, range, one-shot-per-weapon. The client never computes damage, reveal, or resource change.
- Resolution runs once, on the server, at the end of PLAN. Clients receive an event stream to animate. They never simulate the volley themselves.
- Rate-limit all remotes.

---

## 13. Camera, Rendering & the Asset Contract

**No avatars.** Do not spawn a character. Players never walk. `Players.CharacterAutoLoads = false`.

**Camera:** scriptable, fixed at an angled top-down framing over the player's own island, with pan and zoom bounded to their territory. A toggle (and entering targeting mode) swings the camera to frame the enemy island. Both islands need not be on screen at once.

**Placeholder-first rendering.** Terrain cells are `Part` cubes colored by elevation level (3 distinct shades, clearly distinguishable). Structures are colored parts with a `BillboardGui` glyph and an HP pip bar. Suggested glyphs: `base` 🏠, `generator` ⚡, `cannon` ▲, `mortar` ◓, rubble ▪.

**Swap contract (do not skip):** at boot, look for a Model at `ReplicatedStorage/Assets/Structures/<id>` for every structure id, plus `projectile_direct`, `projectile_arc`, `impact`, `rubble`, and `tile_L0` / `tile_L1` / `tile_L2`. If present, clone and scale to cell size; if absent, fall back to the placeholder silently. Document the full name list in `README.md`.

**Resolve-phase feedback is the game's best moment — spend effort here.** Projectiles from both players in the air at once, arcs with ground shadows, a visible stop-and-puff when a cannon shot clips a ridge, impact particles, floating damage numbers, structures crumbling to rubble, terrain visibly rising and falling at the top of resolve.

---

## 14. Bot Opponent

An FSM evaluated once per PLAN phase. Plays by identical rules, identical costs, identical unlock gates, and **its own fog** — its knowledge of the player's structures comes only from its own reveals. It must never read true enemy structure state. It may read terrain, because terrain is public.

**Behavior:**
1. **Open (rounds 1–2):** place 3 bases spread apart, a generator, a cannon. From round 2, raise ground for its cannons and lower ground around its bases.
2. **Probe:** fire cannons along long unexplored lines, preferring shots from its highest cells for reach and sight.
3. **Suppress:** when plots show generators, prioritize them to throttle enemy fire rate.
4. **Kill:** when a plotted base exists, concentrate fire; use mortars if a ridge blocks direct lines.
5. **Rebuild:** always interleaved — restore generator count before advancing.

**Difficulty:** Supply multiplier (0.8 / 1.0 / 1.25), how many rounds it waits before re-probing stale plots, and whether it uses elevation deliberately. Presets: **Shoal / Skirmish / Siege**.

The bot is shipping scope, not a stretch goal — a 1v1 game with no player base cannot be played at launch.

---

## 15. Simulation Harness & Balance Sweep

Because the rules core is pure and headless, balance can be measured before any UI exists. Build it immediately after M1, while changing a number is still free.

`sim/harness.luau` runs N matches given a config, a seed range, and two strategy modules, and writes one JSONL match log per game plus an aggregate CSV. The round structure makes this cleaner than it would have been under real time: a match is a discrete sequence of command sets, so there is no action-rate problem to correct for.

**Hard requirement:** agents read only their own belief map, through the same interface the bot uses in §14. An agent that can see true enemy structure state invalidates the run.

**Archetypes** — scripted, not learned. Scripted is interpretable: when one dominates you know which constant to move.

| Archetype | Behavior |
|---|---|
| `highground` | Raises terrain aggressively, cannons on peaks, long sight lines. |
| `defilade` | Lowers ground around bases, ridges in front, wins by absorbing direct fire. |
| `boomer` | Generators first, no offense until Energy is compounding, then mass fire. |
| `mortarline` | Skips elevation entirely, saves for mortars, ignores terrain. |
| `sprawl` | Reclaims land early, spreads wide, forces the opponent to search more cells. |

Round robin including self-play, `SIM_MATCHES_PER_PAIR` (default 200), seeds shared across pairings.

**Metrics:**
- **Rounds to first real base found** — the primary number. Target 25–45% of expected match length.
- Match length distribution, not the mean. Bimodal results conceal a dominant line.
- Comeback rate from behind at the midpoint — reads on snowball risk.
- Per-structure purchase share and Supply efficiency. Never bought = miscosted.
- Cannon block rate — what fraction of direct shots are stopped by terrain. If near 0, elevation is cosmetic; if near 1, cannons are dead weight. **This is the health check on the whole elevation system.**
- **Victory condition distribution** — what fraction of matches end by base elimination, incapacitation, and round limit. If nearly everything ends on the round limit, the match is too short or weapons are too weak. If incapacitation never fires, it is a dead rule. If it fires often, the economy is too punishing.
- Win rate matrix. **No archetype should exceed 60% against the field.**

**Sweep:** `sim/sweep.luau` over `RAISE_COST` × `CANNON_RANGE` × `MORTAR_RANGE` × `ENERGY_PER_GENERATOR`, then a second pass on `SUPPLY_PER_ROUND` × `RECLAIM_COST`, then `MAX_ROUNDS` × the `POINTS` table.

**Rubric pass:** feed logs to a model for *pathology detection*, not enjoyment scoring — rounds where nothing consequential happened, losing players whose last actions had no bearing on the outcome, structures that never affected an outcome. Treat balance and fairness findings as reliable; treat any direct "is this fun" score as near-noise.

**The sweep narrows; it does not decide.** Expect roughly five surviving configs, which then go to human playtesting. Do not ship a config chosen by simulation alone.

**Known limitation:** this is a hidden-information search game and results transfer only as far as agent search resembles human search. A scripted agent never forgets a cleared sight line; humans do. The harness is authoritative on dominance and pacing, suggestive on everything else.

---

## 16. Milestones & Acceptance Criteria

Build in order. After each: the rules core passes `lune run test` with zero failures, and the Rojo project syncs into Studio without errors. Log notable choices in `DECISIONS.md`.

- **M1 — Rules core, headless.** `src/shared/` complete and pure: board and territory generation, elevation with the smoothness constraint, terrain edits, reclamation, economy, structure placement, **line-of-flight with the beam rule**, volley resolution, fog reveals and stale plots, unlock gates, **all four victory conditions (§5) and scoring**. Lune specs cover each, with line-of-flight covered exhaustively against hand-worked cases and one test per victory condition including simultaneous mutual base elimination. *Accept: I can run a full scripted match end to end in the terminal with no Roblox involved, and the test suite is green.*
- **M1.5 — Sim harness & first sweep.** §15: harness, five archetypes, round robin, metrics, first parameter sweep. *Accept: I can run a 5,000-match round robin from the terminal and get a win-rate matrix, a rounds-to-first-base distribution, a cannon block rate, and a shortlist of surviving configs.*
- **M2 — Board in Studio.** Rojo project, 40×24 board with channel and two 12×12 flat islands, elevation rendering as stacked cubes, scriptable camera, no avatars. *Accept: I can look at the board and tell the two territories and three elevation levels apart at a glance.*
- **M3 — PLAN phase.** Build palette, placement with cost and territory validation, terrain raise/lower with smoothness feedback, reclamation, ready-up, round clock. *Accept: I can lay out an island and reshape its terrain inside the timer.*
- **M4 — RESOLVE phase, vs. a dummy.** Targeting UI, simultaneous volley animation, direct-fire blocking visibly stopping at ridges, damage, rubble, reveals, belief map rendering with public terrain. Static enemy layout to shoot at. *Accept: I can aim a volley, watch it fire, and see exactly what my shots revealed — and a shot into a hillside visibly stops there.*
- **M5 — Full loop & wrapper.** Multi-round progression, unlock gates, economy across rounds, the session state machine and all three screens (§6): intro with Start Game and a disabled Save Game and Continue, empty settings panel backed by the registry, result screen with the itemized breakdown and Restart. *Accept: I can go intro → match → result → restart without rejoining, and the result screen tells me which condition ended the match.*
- **M6 — Real 1v1.** Two-client matchmaking, setup phase, server-authoritative replication per §12, simultaneous plan/resolve across both clients. *Accept: two Studio clients can play a complete match against each other.*
- **M7 — Bot.** Full §14 FSM, three difficulties. *Accept: the bot builds, shapes terrain, probes, and kills my bases; I can lose to it.*
- **M8 — Ship.** Feedback polish on the resolve phase, README (run, sync, asset names, config tuning guide), balance pass from §15.

### Self-playtest before declaring done

- (a) A full win against the bot.
- (b) A full loss by idling.
- (c) A cannon shot blocked by a raised ridge, visibly stopping short, revealing only up to the block point.
- (d) A mortar clearing that same ridge and hitting the target behind it.
- (e) A stale plot: build something on a revealed cell, confirm the opponent's view still shows the old contents.
- (f) **Exploit check:** with a client attached, confirm no unrevealed enemy structure exists anywhere in the client's Instance tree or in any received remote payload — while confirming terrain *is* fully present.
- (g) Each victory condition fires and is reported correctly on the result screen: all bases destroyed; incapacitation after the grace window; round limit decided on points; a points tie resolved by the tiebreak chain.
- (h) Restart produces a fresh match without rejoining, with scores fully reset.

---

## 17. Out of Scope (v1)

More than 2 players, weapon upgrade tiers, scout/radar structures, decoy structures, anti-air, cross-match persistence, unlocks outside the match, cosmetics, monetization, mobile-specific UI, leaderboards, spectating, sound beyond basic impact cues, balance perfection — expose knobs in `config.luau` instead.

Several of these (upgrades, decoys, a dedicated spotter that requires height to function) are strong candidates for a later release and the schemas should leave room for them. Do not build them now.

---

## 18. Open Decisions

Resolve in `DECISIONS.md` and continue; do not block.

1. **`PLAN_SECONDS` — deliberately unresolved.** 45s is a placeholder. A window that is generous on a 12×12 flat island will be frantic once islands are larger, taller, and carrying a dozen weapons. Whether the clock is fixed, scales with island size, or scales with weapon count is a question to answer *after* the loop is playable and has been felt. Do not spend design effort on it before M5.
2. **`MAX_ROUNDS` and the point table are placeholders.** 5 rounds is almost certainly too few — with generators completing at the end of round 1, the first real volley lands in round 2, leaving three rounds of actual fighting. Sweep both (§15) once the loop is playable rather than guessing now.
3. Whether `INCAPACITATION_GRACE_ROUNDS` should scale with `MAX_ROUNDS` — a 2-round grace in a 5-round match is a large fraction of it.
4. Theming and naming — the roster is unthemed placeholder.
5. Whether rubble persists on the belief map permanently or decays.
6. Whether terrain can be edited under an enemy-revealed cell to deliberately invalidate their plot.
7. Mobile input — grid-and-tap should port well, but terrain editing and targeting need a precision pass.