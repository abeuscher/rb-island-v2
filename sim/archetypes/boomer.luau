-- boomer: banks generators before ever building a weapon, then pours every
-- remaining round's Supply into mass fire once Energy income is compounding.
-- Ignores terrain entirely.

local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")

local Boomer = {}

local GENERATOR_TARGET = 4

function Boomer.decide(config, view)
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
		-- Prefers mortars, since it has been saving up while it built out its
		-- economy, but keeps spending on cannons too once mortars stop fitting
		-- the remaining budget.
		for _, typeId in ipairs({ "mortar", "cannon" }) do
			local def = config.STRUCTURES[typeId]
			if view.round >= def.unlock_round then
				local spots = Kit.candidateCells(config, view, typeId, reserved)
				while #spots > 0 and Economy.canAfford(resources, { supply = def.supply_cost }) do
					local spot = spots[math.random(#spots)]
					table.insert(commands, { type = "place", typeId = typeId, x = spot.x, y = spot.y })
					resources = Economy.spend(resources, { supply = def.supply_cost })
					Kit.reserve(reserved, config, typeId, spot.x, spot.y)
					spots = Kit.candidateCells(config, view, typeId, reserved)
				end
			end
		end
	end

	for _, command in ipairs(Kit.chooseTargets(config, view, Kit.pendingWeaponsFrom(config, commands))) do
		table.insert(commands, command)
	end

	return commands
end

return Boomer
