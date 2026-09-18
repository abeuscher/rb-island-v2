local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")

local function withBase(x, y)
	return { typeId = "base", x = x, y = y, hp = config.STRUCTURES.base.hp, underConstruction = false }
end

t.test("a structure cannot be placed on a cell being terrain-edited the same round (§8)", function()
	local state = State.new(config)
	state.round = 2 -- terrain editing unlocked
	state = State.withPlayer(state, "A", { resources = { supply = 100, energy = 10 } })

	local commandsA = {
		{ type = "raise", x = 10, y = 10 },
		{ type = "place", typeId = "generator", x = 10, y = 10 }, -- rejected: same-round terrain edit
		{ type = "place", typeId = "generator", x = 11, y = 10 }, -- unaffected, different cell
	}
	local newState = Rules.resolveRound(config, state, commandsA, {})

	t.expectEqual(Board.elevationAt(newState.board, 10, 10), 1)
	t.expectTrue(#newState.players.A.structures == 1)
	t.expectEqual(newState.players.A.structures[1].x, 11)
end)

t.test("base elimination: a player with zero bases loses immediately", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = {} })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
end)

t.test("simultaneous mutual base elimination is decided on points, not treated as a draw by default", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = {}, destructionPoints = 100 })
	state = State.withPlayer(state, "B", { structures = {}, destructionPoints = 50 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
end)

t.test("a fully tied mutual elimination is a draw", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = {}, destructionPoints = 50, structuresLost = 2 })
	state = State.withPlayer(state, "B", { structures = {}, destructionPoints = 50, structuresLost = 2 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, nil)
end)

t.test("round limit: the higher score wins if it completes with no elimination", function()
	local state = State.new(config)
	state.round = config.MAX_ROUNDS
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) }, destructionPoints = 100 })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, destructionPoints = 50 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "round_limit")
	t.expectEqual(victory.winner, "A")
end)

t.test("incapacitation: a player with no weapon and no way to rebuild loses after the grace window, not before", function()
	-- Zero SUPPLY_PER_ROUND isolates the "unrecoverable" check from the ordinary
	-- per-round Supply accrual, which would otherwise refill past every threshold
	-- this test cares about before the check even runs.
	local incapConfig = table.clone(config)
	incapConfig.SUPPLY_PER_ROUND = 0

	local state = State.new(incapConfig)
	state = State.withPlayer(state, "A", {
		structures = { withBase(6, 7), { typeId = "cannon", x = 6, y = 9, hp = config.STRUCTURES.cannon.hp, underConstruction = false } },
	})
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local afterRound1, _, victory1 = Rules.resolveRound(incapConfig, state, {}, {})
	t.expectEqual(victory1, nil)
	t.expectEqual(afterRound1.players.B.incapableStreak, 1)

	local afterRound2, _, victory2 = Rules.resolveRound(incapConfig, afterRound1, {}, {})
	t.expectTrue(victory2 ~= nil)
	t.expectEqual(victory2.condition, "incapacitation")
	t.expectEqual(victory2.winner, "A")
end)

t.test("resolveRound tracks fired/hit/blocked shots and returns raw resolution data for animation", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", {
		structures = { withBase(24, 10), { typeId = "cannon", x = 20, y = 10, hp = config.STRUCTURES.cannon.hp, underConstruction = false } },
	})

	local placeAndTarget = {
		{ type = "place", typeId = "cannon", x = 17, y = 10 },
		{ type = "target", x = 17, y = 10, targetX = 24, targetY = 10 },
	}
	local newState, _, _, resolution = Rules.resolveRound(config, state, placeAndTarget, {})

	-- A's cannon completes and fires this same resolve (§8: build completes next
	-- RESOLVE, before volleys), landing a hit on B's base.
	t.expectEqual(newState.players.A.shotsFired, 1)
	t.expectEqual(newState.players.A.shotsHit, 1)
	t.expectEqual(newState.players.A.shotsBlocked, 0)
	t.expectEqual(newState.players.A.destructionPoints, 0) -- didn't destroy the base outright
	t.expectEqual(newState.players.B.shotsFired, 0) -- B's cannon was never given a target

	t.expectEqual(resolution.preState.players.A.structures[2].typeId, "cannon")
	t.expectEqual(resolution.preState.players.A.structures[2].underConstruction, false)
	t.expectEqual(#resolution.shotsA, 1)
	t.expectEqual(resolution.shotsA[1].hit, true)
	t.expectEqual(#resolution.shotsB, 0)
end)

t.test("resolveRound awards hit points separately from destroy points", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local placeAndTarget = {
		{ type = "place", typeId = "cannon", x = 17, y = 10 },
		{ type = "target", x = 17, y = 10, targetX = 24, targetY = 10 },
	}
	local newState = Rules.resolveRound(config, state, placeAndTarget, {})

	t.expectEqual(newState.players.A.destructionPoints, 0) -- the base survives this hit
	t.expectEqual(newState.players.A.hitPoints, config.POINTS.hit.base)
end)

t.test("resolveRound awards reveal points once per newly-sighted live structure, not on re-sighting", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", {
		-- Both on B's own land (24-35): the generator at x=26 sits on the direct
		-- beam from A's cannon at x=17 to the base at x=30, well short of it.
		structures = {
			withBase(30, 10),
			{ typeId = "generator", x = 26, y = 10, hp = config.STRUCTURES.generator.hp, underConstruction = false },
		},
	})

	local placeAndTarget = {
		{ type = "place", typeId = "cannon", x = 17, y = 10 },
		{ type = "target", x = 17, y = 10, targetX = 30, targetY = 10 },
	}
	-- The beam crosses the generator on the way to the base -- both get
	-- revealed by this one shot, even though only the base takes damage.
	local afterRound1 = Rules.resolveRound(config, state, placeAndTarget, {})
	t.expectEqual(afterRound1.players.A.revealPoints, config.POINTS.reveal.base + config.POINTS.reveal.generator)

	local retarget = { { type = "target", x = 17, y = 10, targetX = 30, targetY = 10 } }
	local afterRound2 = Rules.resolveRound(config, afterRound1, retarget, {})
	t.expectEqual(afterRound2.players.A.revealPoints, afterRound1.players.A.revealPoints)
end)

t.test("a full scripted match: place a cannon, fire it round after round, end on base elimination", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local placeAndTarget = {
		{ type = "place", typeId = "cannon", x = 17, y = 10 },
		{ type = "target", x = 17, y = 10, targetX = 24, targetY = 10 },
	}
	local afterRound1, _, victory1 = Rules.resolveRound(config, state, placeAndTarget, {})
	t.expectEqual(victory1, nil)
	t.expectFalse(afterRound1.players.A.structures[1].underConstruction) -- completed this same resolve
	t.expectEqual(afterRound1.players.B.structures[1].hp, config.STRUCTURES.base.hp - config.STRUCTURES.cannon.damage)

	local retarget = { { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 } }
	local current = afterRound1
	local victory = nil
	for _ = 1, 3 do
		local nextState, _, v = Rules.resolveRound(config, current, retarget, {})
		current = nextState
		victory = v
	end

	t.expectTrue(victory ~= nil)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
	t.expectEqual(#current.players.B.structures, 0)
	t.expectEqual(#current.players.A.structures, 2) -- base + cannon, both untouched
end)
