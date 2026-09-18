-- MatchState shape, initializer, and the command-level operations that compose
-- board, economy, and structures for a single player's action. Pure: every
-- operation returns a new state and leaves its input untouched.

local Board = require("./board")
local Economy = require("./economy")
local Structures = require("./structures")
local Fog = require("./fog")

local State = {}

local function newPlayerState(config)
	return {
		resources = Economy.new(config),
		structures = Structures.new(),
		belief = Fog.new(),
		destructionPoints = 0,
		destructionPointsByType = { base = 0, generator = 0, cannon = 0, mortar = 0 },
		revealPoints = 0,
		hitPoints = 0,
		structuresLost = 0,
		structuresBuilt = 0,
		shotsFired = 0,
		shotsHit = 0,
		shotsBlocked = 0,
		-- Elapsed-match-time timestamp of when this player first became incapable
		-- and unrecoverable, or nil while they aren't. Restates the old round-streak
		-- in time terms (§5.2's grace window is now INCAPACITATION_GRACE_SECONDS).
		incapableSince = nil,
	}
end

function State.new(config)
	return {
		elapsed = 0,
		board = Board.new(config),
		players = {
			A = newPlayerState(config),
			B = newPlayerState(config),
		},
	}
end

-- Merges `fields` onto the existing player state rather than replacing it outright,
-- so a caller that only touches resources/structures doesn't clobber belief,
-- score, or incapacitation tracking it never meant to change.
local function withPlayer(state, owner, fields)
	local players = table.clone(state.players)
	local player = table.clone(players[owner])
	for key, value in pairs(fields) do
		player[key] = value
	end
	players[owner] = player

	local newState = table.clone(state)
	newState.players = players
	return newState
end

State.withPlayer = withPlayer

local function requireUnlocked(config, state, feature)
	if state.elapsed < config.UNLOCK_TIME[feature] then
		return false, feature .. " is not unlocked yet"
	end
	return true, nil
end

function State.placeStructure(config, state, owner, typeId, x, y)
	local player = state.players[owner]
	local def = config.STRUCTURES[typeId]
	if not def then
		return state, false, "unknown structure type"
	end

	local newStructures, ok, err = Structures.place(config, state.board, player.structures, owner, typeId, x, y, state.elapsed)
	if not ok then
		return state, false, err
	end

	-- def.energy_cost is the per-shot firing cost (§8's "Energy N" in each weapon's
	-- behavior text), not a build cost -- structures only ever cost Supply to build.
	local newResources, ok2, err2 = Economy.spend(player.resources, { supply = def.supply_cost })
	if not ok2 then
		return state, false, err2
	end

	return withPlayer(state, owner, {
		resources = newResources,
		structures = newStructures,
		structuresBuilt = player.structuresBuilt + 1,
	}), true, nil
end

function State.bulldozeStructure(config, state, owner, x, y)
	local player = state.players[owner]
	local newStructures, ok, err = Structures.bulldoze(config, player.structures, x, y)
	if not ok then
		return state, false, err
	end

	return withPlayer(state, owner, { resources = player.resources, structures = newStructures }), true, nil
end

function State.raiseTerrain(config, state, owner, x, y)
	local ok, err = requireUnlocked(config, state, "terrain_edit")
	if not ok then
		return state, false, err
	end
	if Board.ownerOf(state.board, x, y) ~= owner then
		return state, false, "not in your territory"
	end

	local player = state.players[owner]
	if Structures.at(config.STRUCTURES, player.structures, x, y) then
		return state, false, "bulldoze the structure on this cell first"
	end

	local newBoard, ok2, err2 = Board.raise(state.board, x, y)
	if not ok2 then
		return state, false, err2
	end

	local newResources, ok3, err3 = Economy.spend(player.resources, { supply = config.RAISE_COST })
	if not ok3 then
		return state, false, err3
	end

	local newState = withPlayer(state, owner, { resources = newResources, structures = player.structures })
	newState.board = newBoard
	return newState, true, nil
end

function State.lowerTerrain(config, state, owner, x, y)
	local ok, err = requireUnlocked(config, state, "terrain_edit")
	if not ok then
		return state, false, err
	end
	if Board.ownerOf(state.board, x, y) ~= owner then
		return state, false, "not in your territory"
	end

	local player = state.players[owner]
	if Structures.at(config.STRUCTURES, player.structures, x, y) then
		return state, false, "bulldoze the structure on this cell first"
	end

	local newBoard, ok2, err2 = Board.lower(state.board, x, y)
	if not ok2 then
		return state, false, err2
	end

	local newResources, ok3, err3 = Economy.spend(player.resources, { supply = config.LOWER_COST })
	if not ok3 then
		return state, false, err3
	end

	local newState = withPlayer(state, owner, { resources = newResources, structures = player.structures })
	newState.board = newBoard
	return newState, true, nil
end

function State.reclaimLand(config, state, owner, x, y)
	local ok, err = requireUnlocked(config, state, "reclamation")
	if not ok then
		return state, false, err
	end

	local player = state.players[owner]
	local newBoard, ok2, err2 = Board.reclaim(state.board, owner, x, y)
	if not ok2 then
		return state, false, err2
	end

	local newResources, ok3, err3 = Economy.spend(player.resources, { supply = config.RECLAIM_COST })
	if not ok3 then
		return state, false, err3
	end

	local newState = withPlayer(state, owner, { resources = newResources, structures = player.structures })
	newState.board = newBoard
	return newState, true, nil
end

-- Sets or clears the target a live weapon at (x, y) fires at automatically whenever
-- it's off-cooldown -- applied immediately and permanently on receipt, like every
-- other command.
function State.setTarget(config, state, owner, x, y, targetX, targetY)
	local player = state.players[owner]
	local newStructures, ok, err = Structures.setTarget(config, player.structures, x, y, targetX, targetY)
	if not ok then
		return state, false, err
	end
	return withPlayer(state, owner, { structures = newStructures }), true, nil
end

-- Per-tick steps shared by both players; tick sequencing (§4, restated in time
-- terms) is rules.luau's concern, but the per-step transforms live here since
-- they're pure state operations.

function State.completeConstruction(config, state)
	local newState = withPlayer(state, "A", {
		resources = state.players.A.resources,
		structures = Structures.completeConstruction(config, state.players.A.structures, state.elapsed),
	})
	return withPlayer(newState, "B", {
		resources = newState.players.B.resources,
		structures = Structures.completeConstruction(config, newState.players.B.structures, state.elapsed),
	})
end

function State.tickAccrue(config, state)
	local function accrued(player)
		local generatorCount = Structures.countLive(player.structures, "generator")
		return {
			resources = Economy.tickAccrue(config, player.resources, generatorCount),
			structures = player.structures,
		}
	end

	local newState = withPlayer(state, "A", accrued(state.players.A))
	return withPlayer(newState, "B", accrued(newState.players.B))
end

return State
