-- highground: raises terrain aggressively, places cannons on the resulting
-- peaks, and probes with the long sight lines that height buys (§11).

local Board = require("../../src/shared/board")
local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")

local Highground = {}

local GENERATOR_TARGET = 2
local CANNON_TARGET = 3

function Highground.decide(config, view)
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

	if view.elapsed == 0 then
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
	elseif Kit.countType(view, "cannon") < CANNON_TARGET then
		-- Always work the frontmost open cell: raise it to the ceiling, then
		-- arm it, then move on to the next one.
		local peak = Kit.frontlineCells(config, view, "cannon", reserved)[1]
		if peak then
			if view.elapsed >= config.UNLOCK_TIME.terrain_edit and Kit.wouldSucceed(Board.raise, view.board, peak.x, peak.y) then
				if trySpend({ supply = config.RAISE_COST }) then
					table.insert(commands, { type = "raise", x = peak.x, y = peak.y })
				end
			elseif trySpend({ supply = config.STRUCTURES.cannon.supply_cost }) then
				table.insert(commands, { type = "place", typeId = "cannon", x = peak.x, y = peak.y })
				Kit.reserve(reserved, config, "cannon", peak.x, peak.y)
			end
		end
	end

	for _, command in ipairs(Kit.chooseTargets(config, view, Kit.pendingWeaponsFrom(config, commands))) do
		table.insert(commands, command)
	end

	return commands
end

return Highground
