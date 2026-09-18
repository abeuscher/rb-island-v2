-- The read-only slice of MatchState a caller outside the rules core is allowed
-- to see: its own full player state (resources, structures, belief, and every
-- score/stat field), plus the board (terrain is public per §11). Never the
-- opponent's raw structures. Originally sim-only (an archetype strategy must
-- read only its own belief map, §15); promoted to shared in Session 008 as the
-- same contract a real client is allowed to see over the network (§12) -- one
-- guarantee, two callers, instead of two copies of it.

local View = {}

local function opponentOf(owner)
	if owner == "A" then
		return "B"
	end
	return "A"
end

function View.new(state, owner)
	return {
		elapsed = state.elapsed,
		board = state.board,
		owner = owner,
		opponent = opponentOf(owner),
		self = state.players[owner],
	}
end

return View
