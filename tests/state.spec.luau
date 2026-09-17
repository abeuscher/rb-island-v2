local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local State = require("../src/shared/state")

t.test("State.new opens round 1 with each player's starting resources and an empty roster", function()
	local state = State.new(config)
	t.expectEqual(state.round, 1)
	t.expectEqual(state.players.A.resources.supply, config.SUPPLY_PER_ROUND)
	t.expectEqual(state.players.A.resources.energy, config.STARTING_ENERGY)
	t.expectEqual(#state.players.A.structures, 0)
	t.expectEqual(#state.players.B.structures, 0)
end)

t.test("placeStructure spends Supply and leaves the other player untouched", function()
	local state = State.new(config)
	local newState, ok = State.placeStructure(config, state, "A", "generator", 6, 7)
	t.expectTrue(ok)
	t.expectEqual(newState.players.A.resources.supply, config.SUPPLY_PER_ROUND - config.STRUCTURES.generator.supply_cost)
	t.expectEqual(#newState.players.A.structures, 1)
	t.expectEqual(#newState.players.B.structures, 0)
	t.expectEqual(newState.players.B.resources.supply, config.SUPPLY_PER_ROUND)
end)

t.test("placeStructure rejects a type not yet unlocked, without spending anything", function()
	local state = State.new(config)
	local unchanged, ok, err = State.placeStructure(config, state, "A", "mortar", 6, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "not unlocked yet")
	t.expectEqual(unchanged.players.A.resources.supply, config.SUPPLY_PER_ROUND)
end)

t.test("placeStructure rejects a purchase the player can't afford", function()
	local state = State.new(config)
	-- 10 Supply to start; a cannon (10) then a generator (8) can't both fit.
	local afterCannon = State.placeStructure(config, state, "A", "cannon", 6, 7)
	local unchanged, ok, err = State.placeStructure(config, afterCannon, "A", "generator", 8, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "cannot afford")
	t.expectEqual(#unchanged.players.A.structures, 1)
end)

t.test("bulldozeStructure removes the structure without a refund", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "generator", 6, 7)
	local afterBulldoze, ok = State.bulldozeStructure(config, afterPlace, "A", 6, 7)
	t.expectTrue(ok)
	t.expectEqual(#afterBulldoze.players.A.structures, 0)
	t.expectEqual(afterBulldoze.players.A.resources.supply, afterPlace.players.A.resources.supply)
end)

t.test("terrain editing is locked in round 1", function()
	local state = State.new(config)
	local unchanged, ok, err = State.raiseTerrain(config, state, "A", 6, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "terrain_edit is not unlocked yet")
end)

local function atRound(config_, round)
	local state = State.new(config_)
	state.round = round
	return state
end

t.test("raiseTerrain rejects the opponent's territory and occupied cells, once unlocked", function()
	local state = atRound(config, 2)

	local _, ok, err = State.raiseTerrain(config, state, "A", 24, 7) -- B's island
	t.expectFalse(ok)
	t.expectEqual(err, "not in your territory")

	local withGenerator = State.placeStructure(config, state, "A", "generator", 6, 7)
	local _, ok2, err2 = State.raiseTerrain(config, withGenerator, "A", 6, 7)
	t.expectFalse(ok2)
	t.expectEqual(err2, "bulldoze the structure on this cell first")
end)

t.test("raiseTerrain and lowerTerrain spend Supply and change elevation once unlocked", function()
	local state = atRound(config, 2)

	local raised, ok = State.raiseTerrain(config, state, "A", 6, 7)
	t.expectTrue(ok)
	t.expectEqual(Board.elevationAt(raised.board, 6, 7), 1)
	t.expectEqual(raised.players.A.resources.supply, config.SUPPLY_PER_ROUND - config.RAISE_COST)

	local lowered, ok2 = State.lowerTerrain(config, raised, "A", 6, 7)
	t.expectTrue(ok2)
	t.expectEqual(Board.elevationAt(lowered.board, 6, 7), 0)
	t.expectEqual(lowered.players.A.resources.supply, raised.players.A.resources.supply - config.LOWER_COST)
end)

t.test("reclaimLand is locked until round 4, then spends Supply to reclaim adjacent water", function()
	local tooEarly = atRound(config, 3)
	local _, ok, err = State.reclaimLand(config, tooEarly, "A", 5, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "reclamation is not unlocked yet")

	local state = atRound(config, 4)
	state.players.A.resources.supply = config.RECLAIM_COST
	local reclaimed, ok2 = State.reclaimLand(config, state, "A", 5, 7)
	t.expectTrue(ok2)
	t.expectTrue(Board.isLand(reclaimed.board, 5, 7))
	t.expectEqual(reclaimed.players.A.resources.supply, 0)
end)

t.test("completeConstruction and accrueIncome bring a generator online and pay out next round", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "generator", 6, 7)
	local afterComplete = State.completeConstruction(config, afterPlace)
	t.expectFalse(afterComplete.players.A.structures[1].underConstruction)

	local afterIncome = State.accrueIncome(config, afterComplete)
	local expectedSupply = afterComplete.players.A.resources.supply + config.SUPPLY_PER_ROUND
	local expectedEnergy = math.min(config.ENERGY_CAP, afterComplete.players.A.resources.energy + config.ENERGY_PER_GENERATOR)
	t.expectEqual(afterIncome.players.A.resources.supply, expectedSupply)
	t.expectEqual(afterIncome.players.A.resources.energy, expectedEnergy)
end)
