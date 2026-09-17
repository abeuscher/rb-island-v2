# Decisions

Ambiguities in `sessions/proposal.md` resolved with a reasonable call rather than blocking,
per the proposal's own instruction (§0). Newest last.

## Starting Supply (Session 001)

The proposal gives `STARTING_ENERGY` (4) as an explicit opening stipend but names no
equivalent `STARTING_SUPPLY`. Read literally, Supply would start at 0 and only arrive after
round 1's RESOLVE — but round 1's unlock table allows building a Generator or Cannon
immediately, which needs Supply on hand during round 1's PLAN phase.

**Call:** players open round 1 with one round's worth of Supply already banked
(`supply = SUPPLY_PER_ROUND`), mirroring how `STARTING_ENERGY` covers the opening rounds.
Implemented in `Economy.new`.

## Smoothness constraint applied to reclamation (Session 001)

§3's smoothness constraint says "after any edit, no cell may differ from an orthogonally
adjacent land cell by more than 1 level," but §9's reclamation rules don't restate it. Land
reclamation creates a new level-0 land cell, which could sit beside a level-2 ridge.

**Call:** enforce the same smoothness check on reclamation as on raise/lower — a reasonable
land cell shouldn't drop the rule just because it arrived via reclamation instead of terrain
editing. Implemented in `Board.reclaim`.

## Same-round terrain/placement interaction deferred (Session 001)

§8 says "structures cannot be placed on a cell being terrain-edited in the same round." This
needs awareness of everything else queued in the same PLAN phase, which is a whole-round
command-batch concern — this session's `board.luau` / `structures.luau` / `state.luau`
validate one command at a time against already-committed state, with no notion of "other
commands pending this round."

**Call:** left unimplemented here; belongs to the next session's round-resolution layer
(`rules.luau`), which validates a full set of simultaneous commands together.

## Line-of-flight beam fraction (Session 002)

§10 says to walk the beam as "a Bresenham line" and interpolate beam height with
`t = dist(S,C) / dist(S,T)`, but never names the distance metric for `t`.

**Call:** walk the line in evenly-spaced integer steps (`steps = max(|dx|, |dy|)`, the same
Chebyshev count §10 already uses for range) and set `t = step / steps`. This is exact for
horizontal, vertical, and 45° shots and a close approximation everywhere else, and it keeps
the whole beam calculation in the same distance metric as range. Implemented in
`flight.luau`.

## Points table added to config (Session 002)

§5.4 specifies the full destroy/standing point table but §16's repo layout never added it to
`config.luau`, and no prior session needed it.

**Call:** added `config.POINTS.destroy` and `config.POINTS.standing`, keyed by structure
type, exactly matching §5.4's table.

## Rubble as a stale belief-map entry (Session 002)

§18 lists "whether rubble persists on the belief map permanently or decays" as an open
question.

**Call:** rubble isn't tracked as persistent world state at all -- a reveal simply records
"rubble" instead of the destroyed structure if the target cell was destroyed this same round,
the same way a reveal records anything else it currently sees. Once recorded, it decays
exactly like any other stale plot: only a fresh reveal of that cell changes what's shown. No
separate rubble-decay rule was needed.

## Mutual simultaneous incapacitation (Session 002)

§5.2 explicitly covers simultaneous mutual base elimination (decided on points) but says
nothing about both players crossing the incapacitation grace window in the same round.

**Call:** extended the same points-tiebreak resolution to this case, for consistency with the
base-elimination precedent -- an elimination condition met by both players at once is decided
on points regardless of which condition it is.

## Structure placement no longer spends Energy (Session 002 fix)

Session 001's `State.placeStructure` spent both `def.supply_cost` and `def.energy_cost` when
building a structure. §8's table lists Supply as the build cost; "Energy N" appears only in
each weapon's *behavior* text as its per-shot firing cost. This meant building a cannon or
mortar silently docked Energy it was never supposed to cost, discovered when this session's
scripted-match test showed a cannon's owner short on Energy for firing it had clearly paid
for.

**Call:** `State.placeStructure` now spends Supply only. Firing is the only place
`energy_cost` is charged, in `rules.luau`.

## Number of bases per player (Session 003)

§5.1 says "all three of a player's bases," and §14's bot behavior says "place 3 bases
spread apart," but nothing in `rules.luau`/`state.luau` hardcodes a base count -- a base
costs 0 Supply and can be placed as many times as there's room for, and Session 002's own
tests use a single base per player.

**Call:** added `config.NUM_BASES = 3` and had every sim archetype build that many, spread
across its territory, matching §5.1's literal wording and the future bot's behavior. A
single-base match (as Session 002's tests use) still works identically -- `checkVictory`
only ever checks whether the live count is zero, regardless of how many were built.

## Sweep dimension names mapped to actual config paths (Session 003)

§15 names `CANNON_RANGE` and `MORTAR_RANGE` as sweep dimensions, but no such flat keys
exist in `config.luau` -- only `config.STRUCTURES.cannon.range` and `.mortar.range`.

**Call:** `sim/sweep.luau` accepts `CANNON_RANGE`/`MORTAR_RANGE` as override names and maps
them to the nested paths. The third pass's "MAX_ROUNDS x the POINTS table" is implemented
as `MAX_ROUNDS` x a `POINTS_PRESET` choice (`"default"` or `"generatorHeavy"`, which raises
the generator's destroy/standing points) rather than a full per-value grid over all eight
`POINTS` entries, which would have been a combinatorial explosion for a first sweep.

## Sim archetypes get a restricted View, not raw MatchState (Session 003)

§15's hard requirement is that an archetype reads only its own belief map and public
terrain. Passing raw `MatchState` and trusting each archetype not to read
`state.players[opponent].structures` would make that requirement a convention, not a
guarantee.

**Call:** `sim/view.luau` builds a `View` carrying only `round`, `board`, `owner`,
`opponent`, and the owning player's own `resources`/`structures`/`belief`. Every archetype
and `sim/archetypeKit.luau` helper takes a `View`, never `MatchState` -- there is no field
on it that reaches the opponent's real structures. `tests/view.spec.luau` pins the View's
exact key set so this stays true if it's ever extended.

## `rules.resolveRound`'s signature takes `config` explicitly (Session 002)

§2 writes the signature as `rules.resolveRound(state, commandsA, commandsB)`, but every
existing `src/shared/` module (`board`, `economy`, `structures`, `state`) takes `config` as an
explicit first argument rather than importing a config singleton.

**Call:** matched the existing convention: `rules.resolveRound(config, state, commandsA,
commandsB)`.
