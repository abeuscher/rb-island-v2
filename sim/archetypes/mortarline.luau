-- mortarline: ignores terrain and cannons entirely, banking Supply until it
-- can afford mortars -- indirect fire that never has to care about line of
-- flight.

local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")
local Loadout = require("../loadout")

local Mortarline = {}

function Mortarline.decide(config, view)
	local commands = {}
	local resources = view.self.resources
	local reserved = {}
	local GENERATOR_TARGET = Kit.energySustainTarget(config, { mortar = 2 })

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
	elseif view.elapsed >= config.STRUCTURES.mortar.unlock_time and trySpend({ supply = config.STRUCTURES.mortar.supply_cost }) then
		local spots = Kit.candidateCells(config, view, "mortar", reserved)
		if #spots > 0 then
			local spot = spots[math.random(#spots)]
			table.insert(commands, { type = "place", typeId = "mortar", x = spot.x, y = spot.y })
			Kit.reserve(reserved, config, "mortar", spot.x, spot.y)
		end
	end

	local pendingWeapons = Kit.pendingWeaponsFrom(config, commands)
	local holdFire = Loadout.holdFireSet(config, view, pendingWeapons)
	for _, command in ipairs(Kit.chooseTargets(config, view, pendingWeapons, nil, holdFire)) do
		table.insert(commands, command)
	end

	return commands
end

return Mortarline
