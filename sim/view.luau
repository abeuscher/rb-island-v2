-- The read-only slice of MatchState an archetype strategy is allowed to see:
-- its own resources/structures, its own belief map of the opponent, and the
-- board (terrain is public per §11). Archetypes never receive raw MatchState,
-- so there is no way for one to read true opponent structure state.

local View = {}

local function opponentOf(owner)
	if owner == "A" then
		return "B"
	end
	return "A"
end

function View.new(state, owner)
	local player = state.players[owner]
	return {
		round = state.round,
		board = state.board,
		owner = owner,
		opponent = opponentOf(owner),
		self = {
			resources = player.resources,
			structures = player.structures,
			belief = player.belief,
		},
	}
end

return View
