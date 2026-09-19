-- defilade: builds a ridge on the channel-facing edge of each base instead of
-- chasing offensive elevation, and keeps its own cannons on the low ground
-- behind that ridge -- it wins by absorbing direct fire, not out-ranging it.

local Board = require("../../src/shared/board")
local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")
local Loadout = require("../loadout")

local Defilade = {}

local CANNON_TARGET = 2

-- The cell(s) just beyond a base's channel-facing edge -- a ridge here sits
-- close to the target in flight.luau's beam interpolation, which is what
-- makes it an effective block regardless of the shooter's own elevation.
local function shieldCells(config, view, base)
	local footprint = config.STRUCTURES.base.footprint
	local shieldX = (view.owner == "A") and (base.x + footprint) or (base.x - 1)
	local cells = {}
	for dy = 0, footprint - 1 do
		table.insert(cells, { x = shieldX, y = base.y + dy })
	end
	return cells
end

-- A few cells behind the front, not the absolute back of the island: picking
-- the single backmost candidate (the old behaviour) could put a cannon
-- farther from the channel than config.STRUCTURES.cannon.range reaches at
-- all, once the island is deep enough -- the exact bug this doctrine has
-- always had, only caught once sim/ gained real test coverage (Session 020).
-- Depth is derived from the cannon's own range so a future range or
-- board-size change can't silently reintroduce it.
local function shieldedCannonSpot(config, view, reserved)
	local lowGround = Kit.frontlineCells(config, view, "cannon", reserved)
	local maxSafeDepth = config.STRUCTURES.cannon.range - config.CHANNEL_WIDTH - 1
	local index = math.max(1, math.min(#lowGround, math.floor(maxSafeDepth / 2) + 1))
	return lowGround[index]
end

function Defilade.decide(config, view)
	local commands = {}
	local resources = view.self.resources
	local reserved = {}
	local GENERATOR_TARGET = Kit.energySustainTarget(config, { cannon = CANNON_TARGET })

	local function trySpend(cost)
		if Economy.canAfford(resources, cost) then
			resources = Economy.spend(resources, cost)
			return true
		end
		return false
	end

	if view.elapsed == 0 then
		local baseSpots = Kit.chooseBaseSpots(config, view, reserved)
		for _, spot in ipairs(baseSpots) do
			table.insert(commands, { type = "place", typeId = "base", x = spot.x, y = spot.y })
			Kit.reserve(reserved, config, "base", spot.x, spot.y)
		end
	end

	if Kit.countType(view, "generator") < GENERATOR_TARGET then
		if trySpend({ supply = config.STRUCTURES.generator.supply_cost }) then
			local spots = Kit.candidateCells(config, view, "generator", reserved)
			if #spots > 0 then
				local spot = spots[math.random(#spots)]
				table.insert(commands, { type = "place", typeId = "generator", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "generator", spot.x, spot.y)
			end
		end
	elseif view.elapsed >= config.UNLOCK_TIME.terrain_edit then
		local raised = false
		for _, base in ipairs(Kit.liveStructures(view, "base")) do
			for _, cell in ipairs(shieldCells(config, view, base)) do
				if
					Board.inBounds(view.board, cell.x, cell.y)
					and Board.ownerOf(view.board, cell.x, cell.y) == view.owner
					and Kit.wouldSucceed(Board.raise, view.board, cell.x, cell.y)
				then
					if trySpend({ supply = config.RAISE_COST }) then
						table.insert(commands, { type = "raise", x = cell.x, y = cell.y })
						raised = true
					end
					break
				end
			end
			if raised then
				break
			end
		end

		if not raised and Kit.countType(view, "cannon") < CANNON_TARGET then
			local spot = shieldedCannonSpot(config, view, reserved)
			if spot and trySpend({ supply = config.STRUCTURES.cannon.supply_cost }) then
				table.insert(commands, { type = "place", typeId = "cannon", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "cannon", spot.x, spot.y)
			end
		end
	end

	local pendingWeapons = Kit.pendingWeaponsFrom(config, commands)
	local holdFire = Loadout.holdFireSet(config, view, pendingWeapons)
	for _, command in ipairs(Kit.chooseTargets(config, view, pendingWeapons, nil, holdFire)) do
		table.insert(commands, command)
	end

	return commands
end

return Defilade
