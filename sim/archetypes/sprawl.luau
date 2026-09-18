-- sprawl: reclaims new land as soon as it's unlocked and keeps growing its
-- footprint, so the opponent has to search more cells to find anything real.

local Board = require("../../src/shared/board")
local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")

local Sprawl = {}

local GENERATOR_TARGET = 2
local CANNON_TARGET = 2
local RECLAIM_TARGET = 6

local function reclaimCandidates(view)
	local minX, maxX = Kit.territoryXRange(view, view.owner)
	local candidates = {}
	for x = minX, maxX do
		for y = 1, view.board.height do
			if Kit.wouldSucceed(Board.reclaim, view.board, view.owner, x, y) then
				table.insert(candidates, { x = x, y = y })
			end
		end
	end
	return candidates
end

local function ownLandCount(view)
	local minX, maxX = Kit.territoryXRange(view, view.owner)
	local count = 0
	for x = minX, maxX do
		for y = 1, view.board.height do
			if Board.isLand(view.board, x, y) then
				count += 1
			end
		end
	end
	return count
end

function Sprawl.decide(config, view)
	local commands = {}
	local resources = view.self.resources
	local reserved = {}

	local function trySpend(cost)
		if Economy.canAfford(resources, cost) then
			resources = Economy.spend(resources, cost)
			return true
		end
		return false
	end

	if view.round == 1 then
		local baseSpots = Kit.spreadPick(Kit.candidateCells(config, view, "base", reserved), config.NUM_BASES)
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
	else
		if view.round >= config.UNLOCK_ROUND.reclamation then
			local reclaimedSoFar = ownLandCount(view) - (config.ISLAND_SIZE * config.ISLAND_SIZE)
			if reclaimedSoFar < RECLAIM_TARGET then
				local spots = reclaimCandidates(view)
				if #spots > 0 and trySpend({ supply = config.RECLAIM_COST }) then
					local spot = spots[math.random(#spots)]
					table.insert(commands, { type = "reclaim", x = spot.x, y = spot.y })
				end
			end
		end

		if Kit.countType(view, "cannon") < CANNON_TARGET then
			-- Spread apart, same doctrine as its base placement: cover ground.
			local spots = Kit.spreadPick(Kit.candidateCells(config, view, "cannon", reserved), 1)
			if #spots > 0 and trySpend({ supply = config.STRUCTURES.cannon.supply_cost }) then
				local spot = spots[1]
				table.insert(commands, { type = "place", typeId = "cannon", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "cannon", spot.x, spot.y)
			end
		end
	end

	for _, command in ipairs(Kit.chooseTargets(config, view, Kit.pendingWeaponsFrom(config, commands))) do
		table.insert(commands, command)
	end

	return commands
end

return Sprawl
