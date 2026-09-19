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

Two entry points under `sim/`, both driven by the six scripted archetypes in `sim/archetypes/`:

```
lune run sim
```

A single round robin (every archetype vs. every archetype, including self-play) at the shipped
`src/shared/config.luau`. Writes a per-match log (`sim/output/matches.jsonl`) and an aggregate
CSV (`sim/output/aggregate.csv`), and prints the full balance report: win-rate matrix, field win
rates, match-length and time-to-first-base distributions, cannon block rate, victory-condition
split.

```
lune run sweep
```

A staged three-pass parameter sweep over the knobs `sim/sweep.luau` names (weapon ranges,
terrain costs, income rates, match length, points presets), each pass building on the previous
pass's best pick. Prints every point tried and writes the surviving configs (if any) to
`sim/output/shortlist.md`, ranked by fit. **The sweep narrows a shortlist for human playtesting —
it doesn't decide a config on its own.**

Both commands run a lot of matches (`lune run sim` is ~3,600 matches; `lune run sweep` is closer
to 17,000 across all its config combinations), so expect `sweep` in particular to take several
minutes. `config.SIM_MATCHES_PER_PAIR` and `.lune/sweep.luau`'s `MATCHES_PER_PAIR` trade sample
size for runtime if you need a faster/noisier pass while iterating.

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
