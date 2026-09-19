local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local State = require("../src/shared/state")

t.test("State.new opens at elapsed 0 with each player's starting resources and an empty roster", function()
	local state = State.new(config)
	t.expectEqual(state.elapsed, 0)
	t.expectEqual(state.players.A.resources.supply, config.STARTING_SUPPLY)
	t.expectEqual(state.players.A.resources.energy, config.STARTING_ENERGY)
	t.expectEqual(#state.players.A.structures, 0)
	t.expectEqual(#state.players.B.structures, 0)
end)

t.test("placeStructure spends Supply and leaves the other player untouched", function()
	local state = State.new(config)
	local newState, ok = State.placeStructure(config, state, "A", "generator", 6, 7)
	t.expectTrue(ok)
	t.expectEqual(newState.players.A.resources.supply, config.STARTING_SUPPLY - config.STRUCTURES.generator.supply_cost)
	t.expectEqual(#newState.players.A.structures, 1)
	t.expectEqual(#newState.players.B.structures, 0)
	t.expectEqual(newState.players.B.resources.supply, config.STARTING_SUPPLY)
end)

t.test("placeStructure counts toward structuresBuilt even after the structure is later lost", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "generator", 6, 7)
	t.expectEqual(afterPlace.players.A.structuresBuilt, 1)

	local afterBulldoze = State.bulldozeStructure(config, afterPlace, "A", 6, 7)
	t.expectEqual(afterBulldoze.players.A.structuresBuilt, 1)
end)

t.test("placeStructure rejects a type not yet unlocked, without spending anything", function()
	local state = State.new(config)
	local unchanged, ok, err = State.placeStructure(config, state, "A", "mortar", 6, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "not unlocked yet")
	t.expectEqual(unchanged.players.A.resources.supply, config.STARTING_SUPPLY)
end)

t.test("placeStructure rejects a purchase the player can't afford", function()
	local state = State.new(config)
	-- STARTING_SUPPLY (10) to start; a cannon (10) then a generator (8) can't both fit.
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

local function atElapsed(config_, elapsed)
	local state = State.new(config_)
	state.elapsed = elapsed
	return state
end

t.test("raiseTerrain rejects the opponent's territory and occupied cells, once unlocked", function()
	local state = atElapsed(config, config.UNLOCK_TIME.terrain_edit)

	local _, ok, err = State.raiseTerrain(config, state, "A", 24, 7) -- B's island
	t.expectFalse(ok)
	t.expectEqual(err, "not in your territory")

	local withGenerator = State.placeStructure(config, state, "A", "generator", 6, 7)
	local _, ok2, err2 = State.raiseTerrain(config, withGenerator, "A", 6, 7)
	t.expectFalse(ok2)
	t.expectEqual(err2, "bulldoze the structure on this cell first")
end)

t.test("raiseTerrain and lowerTerrain spend Supply and change elevation once unlocked", function()
	local state = atElapsed(config, config.UNLOCK_TIME.terrain_edit)

	local raised, ok = State.raiseTerrain(config, state, "A", 6, 7)
	t.expectTrue(ok)
	t.expectEqual(Board.elevationAt(raised.board, 6, 7), 1)
	t.expectEqual(raised.players.A.resources.supply, config.STARTING_SUPPLY - config.RAISE_COST)

	local lowered, ok2 = State.lowerTerrain(config, raised, "A", 6, 7)
	t.expectTrue(ok2)
	t.expectEqual(Board.elevationAt(lowered.board, 6, 7), 0)
	t.expectEqual(lowered.players.A.resources.supply, raised.players.A.resources.supply - config.LOWER_COST)
end)

t.test("reclaimLand is locked until its unlock time, then spends Supply to reclaim adjacent water", function()
	local tooEarly = atElapsed(config, config.UNLOCK_TIME.reclamation - 1)
	local _, ok, err = State.reclaimLand(config, tooEarly, "A", 5, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "reclamation is not unlocked yet")

	local state = atElapsed(config, config.UNLOCK_TIME.reclamation)
	state.players.A.resources.supply = config.RECLAIM_COST
	local reclaimed, ok2 = State.reclaimLand(config, state, "A", 5, 7)
	t.expectTrue(ok2)
	t.expectTrue(Board.isLand(reclaimed.board, 5, 7))
	t.expectEqual(reclaimed.players.A.resources.supply, 0)
end)

t.test("setTarget assigns a persistent target to a weapon and rejects a cell with no weapon", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "cannon", 6, 7)

	local targeted, ok = State.setTarget(config, afterPlace, "A", 6, 7, 24, 7)
	t.expectTrue(ok)
	t.expectEqual(targeted.players.A.structures[1].target.x, 24)
	t.expectEqual(targeted.players.A.structures[1].target.y, 7)

	local _, ok2, err2 = State.setTarget(config, afterPlace, "A", 1, 1, 24, 7)
	t.expectFalse(ok2)
	t.expectEqual(err2, "no weapon there")
end)

t.test("setAutoFire flips a weapon's autoFire flag and rejects a cell with no weapon", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "cannon", 6, 7)
	t.expectFalse(afterPlace.players.A.structures[1].autoFire)

	local enabled, ok = State.setAutoFire(config, afterPlace, "A", 6, 7, true)
	t.expectTrue(ok)
	t.expectTrue(enabled.players.A.structures[1].autoFire)

	local disabled, ok2 = State.setAutoFire(config, enabled, "A", 6, 7, false)
	t.expectTrue(ok2)
	t.expectFalse(disabled.players.A.structures[1].autoFire)

	local _, ok3, err3 = State.setAutoFire(config, afterPlace, "A", 1, 1, true)
	t.expectFalse(ok3)
	t.expectEqual(err3, "no weapon there")
end)

t.test("completeConstruction only completes a structure once its readyAt has passed", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "generator", 6, 7)

	local tooEarly = State.completeConstruction(config, afterPlace)
	t.expectTrue(tooEarly.players.A.structures[1].underConstruction)

	local ready = table.clone(afterPlace)
	ready.elapsed = afterPlace.players.A.structures[1].readyAt
	local afterComplete = State.completeConstruction(config, ready)
	t.expectFalse(afterComplete.players.A.structures[1].underConstruction)
	t.expectEqual(afterComplete.players.A.structures[1].hp, config.STRUCTURES.generator.hp)
end)

t.test("completeAllConstruction completes every structure regardless of readyAt -- for setup, which never puts bases on a build timer", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "base", 6, 7)
	t.expectTrue(afterPlace.players.A.structures[1].underConstruction)

	local afterComplete = State.completeAllConstruction(config, afterPlace)
	t.expectFalse(afterComplete.players.A.structures[1].underConstruction)
	t.expectEqual(afterComplete.players.A.structures[1].hp, config.STRUCTURES.base.hp)
end)

t.test("tickAccrue pays out Supply and generator Energy income scaled by TICK_SECONDS", function()
	local state = State.new(config)
	local afterPlace = State.placeStructure(config, state, "A", "generator", 6, 7)
	local ready = table.clone(afterPlace)
	ready.elapsed = afterPlace.players.A.structures[1].readyAt
	local afterComplete = State.completeConstruction(config, ready)

	local afterIncome = State.tickAccrue(config, afterComplete)
	local expectedSupply = afterComplete.players.A.resources.supply + config.SUPPLY_PER_SECOND * config.TICK_SECONDS
	local expectedEnergy = math.min(
		config.ENERGY_CAP,
		afterComplete.players.A.resources.energy + config.ENERGY_PER_GENERATOR_PER_SECOND * config.TICK_SECONDS
	)
	t.expectEqual(afterIncome.players.A.resources.supply, expectedSupply)
	t.expectEqual(afterIncome.players.A.resources.energy, expectedEnergy)
end)
