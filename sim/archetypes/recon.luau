-- recon: a genuinely different opening from `rush`'s greedy "attack whatever's
-- found" doctrine. Gets two cannons down fast, same as `rush`, but spends its
-- first several shots deliberately firing at the farthest unexplored ground
-- it can reach -- ignoring any base or generator spotted along the way --
-- instead of committing to combat the moment something's found. Once that
-- recon burst is done (or there's nothing left to explore), it switches to
-- the same single-base focus-fire finish `rush` uses, now armed with a much
-- better picture of the board than a shot-by-shot opportunist ever builds.

local Economy = require("../../src/shared/economy")
local Flight = require("../../src/shared/flight")
local Kit = require("../../src/shared/archetypeKit")

local Recon = {}

local CANNON_TARGET = 2
local GENERATOR_TARGET = 2
local MORTAR_TARGET = 2
local RECON_SHOTS = 8

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

local function farthest(board, def, wx, wy, cells)
	local hits = Kit.reachableCells(board, def, wx, wy, cells)
	if #hits == 0 then
		return nil
	end
	table.sort(hits, function(a, b)
		return Flight.chebyshevDistance(wx, wy, a.x, a.y) > Flight.chebyshevDistance(wx, wy, b.x, b.y)
	end)
	return hits[1]
end

-- Per weapon: the farthest reachable unexplored cell while the recon budget
-- is still open, then the same base > generator > unexplored > known priority
-- Kit.chooseTargets uses. Unlike Kit.chooseTargets, a weapon that's out of
-- recon budget but has nothing else reachable falls through the rest of the
-- chain in the same call instead of going untargeted -- a weapon boxed into a
-- corner with nothing left to scout still attacks whatever it already knows
-- about rather than sitting idle for the remainder of the recon window.
local function chooseReconTargets(config, view, pendingWeapons, reconBudget)
	local commands = {}
	local focus = focusBase(view)
	local plottedGenerators = {}
	for _, s in ipairs(Kit.plottedEnemyStructures(view)) do
		if s.typeId == "generator" then
			table.insert(plottedGenerators, s)
		end
	end

	local opponentLand = Kit.opponentLandCells(view)
	local unexplored = {}
	for _, cell in ipairs(opponentLand) do
		if Kit.isUnexplored(view, cell.x, cell.y) then
			table.insert(unexplored, cell)
		end
	end

	local weapons = Kit.liveStructures(view)
	if pendingWeapons then
		for _, weapon in ipairs(pendingWeapons) do
			table.insert(weapons, weapon)
		end
	end

	-- Cannons and mortars draw from the same Energy pool, and planShots
	-- (rules.luau) pays out to whichever weapon it checks first each tick --
	-- always the cannons here, since they're built first. A cheap cannon shot
	-- every cooldown never lets the pool accumulate the mortar's pricier 3
	-- Energy. Once a base is actually found and a mortar exists to finish it,
	-- cannons stand down (no target, no fire) so Energy banks up for the
	-- mortar's harder hit instead of the two competing for the same trickle.
	local hasMortar = Kit.countType(view, "mortar") > 0
	for _, weapon in ipairs(pendingWeapons or {}) do
		if weapon.typeId == "mortar" then
			hasMortar = true
		end
	end

	for _, weapon in ipairs(weapons) do
		local def = config.STRUCTURES[weapon.typeId]
		if def.fire_mode then
			local target = nil
			local standDown = weapon.typeId == "cannon" and reconBudget <= 0 and focus and hasMortar

			if not standDown then
				if reconBudget > 0 then
					target = farthest(view.board, def, weapon.x, weapon.y, unexplored)
				end

				if not target and focus then
					target = farthest(view.board, def, weapon.x, weapon.y, focus)
				end

				if not target and #plottedGenerators > 0 then
					local hits = Kit.reachableCells(view.board, def, weapon.x, weapon.y, plottedGenerators)
					if #hits > 0 then
						target = hits[math.random(#hits)]
					end
				end

				if not target then
					target = farthest(view.board, def, weapon.x, weapon.y, unexplored)
				end

				if not target then
					local hits = Kit.reachableCells(view.board, def, weapon.x, weapon.y, opponentLand)
					if #hits > 0 then
						target = hits[math.random(#hits)]
					end
				end
			end

			if target then
				table.insert(commands, { type = "target", x = weapon.x, y = weapon.y, targetX = target.x, targetY = target.y })
			end
		end
	end

	return commands
end

function Recon.decide(config, view)
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

	-- One cannon first to start scouting immediately, then a generator right
	-- away -- unlike `rush`'s burst-damage doctrine, a sustained scouting
	-- campaign (several shots, not one decisive volley) needs Energy income
	-- online early rather than after both cannons are already competing for
	-- the same starting 4 Energy.
	if Kit.countType(view, "cannon") < 1 then
		if trySpend({ supply = config.STRUCTURES.cannon.supply_cost }) then
			local spot = Kit.frontlineCells(config, view, "cannon", reserved)[1]
			if spot then
				table.insert(commands, { type = "place", typeId = "cannon", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "cannon", spot.x, spot.y)
			end
		end
	elseif Kit.countType(view, "generator") < 1 then
		if trySpend({ supply = config.STRUCTURES.generator.supply_cost }) then
			local spots = Kit.candidateCells(config, view, "generator", reserved)
			if #spots > 0 then
				local spot = spots[math.random(#spots)]
				table.insert(commands, { type = "place", typeId = "generator", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "generator", spot.x, spot.y)
			end
		end
	elseif Kit.countType(view, "cannon") < CANNON_TARGET then
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
	local reconBudget = RECON_SHOTS - view.self.shotsFired
	for _, command in ipairs(chooseReconTargets(config, view, pendingWeapons, reconBudget)) do
		table.insert(commands, command)
	end

	return commands
end

return Recon
