-- rush: skips the generator-heavy opening every other archetype uses. Gets a
-- cannon down immediately to start reading the board, follows with a second
-- cannon and just enough generator to sustain fire, then pivots to mortars
-- once they unlock and commits every weapon to whichever enemy base was
-- found first until it's confirmed dead, instead of splitting fire across
-- everything currently visible.

local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")
local Loadout = require("../loadout")

local Rush = {}

local CANNON_TARGET = 2
local MORTAR_TARGET = 2

-- The lowest-coordinate live (non-rubble) plotted base, as a single-element
-- list for Kit.chooseTargets's focusBases -- deterministic, so every weapon
-- commits to the same base each decide() call rather than each one
-- independently randomizing among everything plotted.
local function focusBase(view)
	local best = nil
	for _, s in ipairs(Kit.plottedEnemyStructures(view)) do
		if s.typeId == "base" and (not best or s.x < best.x or (s.x == best.x and s.y < best.y)) then
			best = s
		end
	end
	if best then
		return { best }
	end
	return nil
end

function Rush.decide(config, view)
	local commands = {}
	local resources = view.self.resources
	local reserved = {}
	-- Sized off the cannons this doctrine actually opens with, not the
	-- mortars it only pivots to once they unlock -- keeping "just enough
	-- generator to sustain fire" a lean, fast-opening number rather than what
	-- a full cannon+mortar loadout would need.
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

	if Kit.countType(view, "cannon") < CANNON_TARGET then
		if trySpend({ supply = config.STRUCTURES.cannon.supply_cost }) then
			local spot = Kit.frontlineCells(config, view, "cannon", reserved)[1]
			if spot then
				table.insert(commands, { type = "place", typeId = "cannon", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "cannon", spot.x, spot.y)
			end
		end
	elseif Kit.countType(view, "generator") < GENERATOR_TARGET then
		if trySpend({ supply = config.STRUCTURES.generator.supply_cost }) then
			local spots = Kit.candidateCells(config, view, "generator", reserved)
			if #spots > 0 then
				local spot = spots[math.random(#spots)]
				table.insert(commands, { type = "place", typeId = "generator", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "generator", spot.x, spot.y)
			end
		end
	elseif Kit.countType(view, "mortar") < MORTAR_TARGET and view.elapsed >= config.STRUCTURES.mortar.unlock_time then
		if trySpend({ supply = config.STRUCTURES.mortar.supply_cost }) then
			local spot = Kit.frontlineCells(config, view, "mortar", reserved)[1]
			if spot then
				table.insert(commands, { type = "place", typeId = "mortar", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "mortar", spot.x, spot.y)
			end
		end
	end

	local pendingWeapons = Kit.pendingWeaponsFrom(config, commands)
	local holdFire = Loadout.holdFireSet(config, view, pendingWeapons)
	for _, command in ipairs(Kit.chooseTargets(config, view, pendingWeapons, focusBase(view), holdFire)) do
		table.insert(commands, command)
	end

	return commands
end

return Rush
