-- boomer: banks generators before ever building a weapon, then pours every
-- remaining round's Supply into mass fire once Energy income is compounding.
-- Ignores terrain entirely.

local Economy = require("../../src/shared/economy")
local Kit = require("../../src/shared/archetypeKit")
local Loadout = require("../loadout")

local Boomer = {}

function Boomer.decide(config, view)
	local commands = {}
	local resources = view.self.resources
	local reserved = {}
	-- Sized off one mortar sustaining continuous fire, not the full arsenal
	-- it eventually fields -- GENERATOR_TARGET never grows past this once set
	-- (there's no later branch that returns to building more), and 2 full
	-- mortars' worth (8 generators) delayed the weapon phase so long that
	-- boomer was regularly incapacitated before ever spending on a weapon at
	-- all, missile included -- caught by `lune run sim`'s purchaseShare
	-- showing missile never bought across a full round robin (Session 020).
	local GENERATOR_TARGET = Kit.energySustainTarget(config, { mortar = 1 })

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
	else
		-- Prefers missiles, then mortars, since it has been saving up while it
		-- built out its economy, but keeps spending on cannons too once the
		-- pricier weapons stop fitting the remaining budget. Stops trying
		-- cheaper types entirely once a pricier, already-unlocked one is out
		-- of reach this cycle, banking Supply toward it instead -- otherwise
		-- the cheaper type (always affordable first) drains the pool back to
		-- near-zero every single decide() cycle, and the pricier one's cost
		-- never gets a chance to accumulate at all. Missile (26 Supply, the
		-- priciest, latest-unlocking) never once got bought in a full
		-- `lune run sim` round robin before this fix (Session 020).
		local savingForPricier = false
		for _, typeId in ipairs({ "missile", "mortar", "cannon" }) do
			local def = config.STRUCTURES[typeId]
			if not savingForPricier and view.elapsed >= def.unlock_time then
				local spots = Kit.candidateCells(config, view, typeId, reserved)
				while #spots > 0 and Economy.canAfford(resources, { supply = def.supply_cost }) do
					local spot = spots[math.random(#spots)]
					table.insert(commands, { type = "place", typeId = typeId, x = spot.x, y = spot.y })
					resources = Economy.spend(resources, { supply = def.supply_cost })
					Kit.reserve(reserved, config, typeId, spot.x, spot.y)
					spots = Kit.candidateCells(config, view, typeId, reserved)
				end
				if not Economy.canAfford(resources, { supply = def.supply_cost }) then
					savingForPricier = true
				end
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

return Boomer
