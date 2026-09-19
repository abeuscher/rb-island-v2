# Island Siege

A 1v1 Metal Marines-style real-time strategy game: two islands separated by a channel, fog of
war, terrain you can raise/lower/reclaim, and simultaneous-fire combat. Design history and
decisions live in `sessions/proposal.md` and `DECISIONS.md`; this file only covers running the
project.

## Requirements

Tool versions are pinned in `rokit.toml`:

- [Rokit](https://github.com/rojo-rbx/rokit) (installs the two tools below at the pinned versions)
- Lune 0.10.5 (runs the pure rules-core tests and the simulator, no Roblox client needed)
- Rojo 7.7.0 (syncs the project into Roblox Studio)

With Rokit installed, run `rokit install` from the repo root to fetch both.

## Running the tests

```
lune run test
```

Discovers and runs every `tests/*.spec.luau` file. These cover `src/shared/` only — the pure,
zero-Roblox-API rules core (board, economy, combat, fog, victory, scoring). `src/client/` and
`src/server/` aren't unit-tested (they need a live Roblox environment); verify those live in
Studio.

## Running the simulator

Two entry points under `sim/`, both driven by the seven scripted archetypes in `sim/archetypes/`:

```
lune run sim
```

A round robin (every archetype vs. every archetype, including self-play) at the shipped
`src/shared/config.luau`. Writes a per-match log (`sim/output/matches.jsonl`) and an aggregate
CSV (`sim/output/aggregate.csv`), and prints the full balance report: win-rate matrix, field win
rates, match-length and time-to-first-base distributions, cannon block rate, victory-condition
split. It then runs `sim/placementSuite.luau`'s curated base-placement pass — the same round
robin again, but with every side's bases placed by one of a few deliberately awkward layouts
(clustered in a corner, spread along the back row, packed deep and centered) instead of the
normal random spread — and prints, per layout, whether any archetype went a whole match without
ever finding a base under it. That's a real exploration blind spot, not a balance nuance, and is
worth a real fix rather than a shrug.

```
lune run sweep
```

A staged three-pass parameter sweep over the knobs `sim/sweep.luau` names (weapon ranges,
terrain costs, income rates, match length, points presets), each pass building on the previous
pass's best pick. Prints every point tried and writes the surviving configs (if any) to
`sim/output/shortlist.md`, ranked by fit. **The sweep narrows a shortlist for human playtesting —
it doesn't decide a config on its own.**

Both commands run a lot of matches, so expect `sweep` in particular to take several minutes.
`config.SIM_MATCHES_PER_PAIR` and `.lune/sweep.luau`'s `MATCHES_PER_PAIR` trade sample size for
runtime if you need a faster/noisier pass while iterating.

## Adding a new weapon or structure to the sim

Stat-complete in `config.STRUCTURES` is not the same as usable by the simulator — a weapon the
real game and `server/Bot.luau` already fire can still sit at 0% `purchaseShare` in every
`lune run sim` run if nothing in `sim/` ever builds it. `missile` and `scout` were exactly this
for several sessions after Session 016 added them; the checklist below (and `sim/loadout.luau`'s
own header comment) is what closes that gap, demonstrated end to end on those two weapons in
Session 020.

1. **`config.STRUCTURES` entry.** The existing, working process — cost, range, damage, cooldown,
   unlock time. Unchanged by anything below.
2. **A role in `sim/loadout.luau`'s `Roles` table**: a category tag (`direct-damage`,
   `arc-finisher`, `recon`, `support-economy`, or a new one if the weapon is a genuinely new
   kind of thing) and, if it should ever hold fire for a costlier weapon sharing the Energy pool,
   a `standDownIfPresent` list of the categories it defers to. This is the whole "declared, not
   hand-written" step — no archetype file needs editing for the stand-down behavior to apply.
3. **A generator target sized off it, not guessed**: any archetype that plans to build the new
   weapon should size its `GENERATOR_TARGET` with `Kit.energySustainTarget(config, counts)`
   (`src/shared/archetypeKit.luau`), passing the weapon counts it actually intends to field, not
   a hand-picked literal.
4. **Slot it into whichever archetype's doctrine actually fits its category** — not a new,
   bespoke archetype file. A recon-flavored archetype is the natural home for a `recon`-category
   weapon; an archetype that already mass-fires its strongest affordable weapon is the natural
   home for a new `arc-finisher`. `sim/archetypes/recon.luau` (scout drone) and
   `sim/archetypes/boomer.luau` (missile) are the two worked examples.
5. **Run `lune run test`** — `tests/sim.spec.luau`'s smoke spec fails loudly if the new weapon
   (or anything it shares an Energy pool with) ends up placed somewhere it can never actually
   fire from, the same class of bug that let `defilade`'s cannons sit out of range for a whole
   session before this spec existed.
6. **Run `lune run sim`** and check `purchaseShare`/shots fired for the new weapon are non-zero
   in the printed report before calling it done.

## Syncing into Studio

1. `rojo serve` from the repo root (uses `default.project.json`).
2. In Studio, install the Rojo plugin (via the Roblox plugin marketplace) and connect to the
   running server.

`default.project.json` maps the source tree straight into the DataModel — there are no binary
asset files in this project (everything renders as procedurally-created `Part`s):

| Source | Studio location |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/server/` | `ServerScriptService.Server` |

`Players.CharacterAutoLoads` is off — this project never spawns avatars, so there's nothing else
to configure in Studio beyond connecting the sync.

## Tuning config

`src/shared/config.luau` is the single source of every tunable number: board/island size,
terrain-edit costs, Supply/Energy rates, tick length and match length, the full weapon roster
(`STRUCTURES`, one entry per structure with its cost/range/damage/cooldown), and the scoring
weights (`POINTS`). Nothing numeric is hardcoded outside this file.

To validate a config change before touching it live in Studio: point `lune run sim` at it (it
always reads the shipped `config.luau` directly) and check the balance report, or add the knob
to `.lune/sweep.luau`'s dimension tables to sweep it against a range of values. A config is
worth taking to human playtesting if it clears `sim/sweep.luau`'s `Sweep.survives` bar: no
archetype wins more than 60% of the field, the cannon block rate lands between 15-85%, and the
time limit doesn't decide more than 90% of matches.
