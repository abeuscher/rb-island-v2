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
