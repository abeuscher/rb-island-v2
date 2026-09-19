-- Shared read-only helpers for archetype strategies: candidate-cell search,
-- spread placement, belief-map queries, and legal-target selection. Every
-- function here only ever reads a View (see view.luau) plus the pure
-- src/shared modules, never raw MatchState -- there is nothing here an
-- archetype could use to peek at true opponent structure state. Originally
-- sim-only; promoted here in Session 009 so server/Bot.luau's real match
-- opponent can build on the exact same candidate-cell/target-selection logic
-- the sim's five scripted archetypes already use, instead of a second copy
-- (same reasoning as view.luau's Session 008 promotion).

local Board = require("./board")
local Structures = require("./structures")
local Flight = require("./flight")

local Kit = {}

local function key(x, y)
	return x .. "," .. y
end
Kit.key = key

-- The column range belonging to `owner`'s territory.
local function territoryXRange(view, owner)
	if owner == "A" then
		return 1, view.board.channelStart - 1
	end
	return view.board.channelEnd + 1, view.board.width
end
Kit.territoryXRange = territoryXRange

local function footprintKeys(config, typeId, x, y)
	local size = config.STRUCTURES[typeId].footprint
	local keys = {}
	for dx = 0, size - 1 do
		for dy = 0, size - 1 do
			table.insert(keys, key(x + dx, y + dy))
		end
	end
	return keys
end
Kit.footprintKeys = footprintKeys

function Kit.reserve(reserved, config, typeId, x, y)
	for _, k in ipairs(footprintKeys(config, typeId, x, y)) do
		reserved[k] = true
	end
end

-- Calls a pure Board mutator (raise/lower/reclaim) purely to read its second
-- (ok) return value; the board it returns on failure is the original,
-- untouched, so this is a safe dry run.
function Kit.wouldSucceed(fn, ...)
	local _, ok = fn(...)
	return ok
end

-- Every legal placement spot for `typeId` in the owner's own territory this
-- round, excluding any cell reserved earlier in the same decide() call.
function Kit.candidateCells(config, view, typeId, reserved)
	local candidates = {}
	local minX, maxX = territoryXRange(view, view.owner)
	for x = minX, maxX do
		for y = 1, view.board.height do
			if Structures.canPlace(config, view.board, view.self.structures, view.owner, typeId, x, y, view.elapsed) then
				local blocked = false
				if reserved then
					for _, k in ipairs(footprintKeys(config, typeId, x, y)) do
						if reserved[k] then
							blocked = true
							break
						end
					end
				end
				if not blocked then
					table.insert(candidates, { x = x, y = y })
				end
			end
		end
	end
	return candidates
end

-- `candidates` sorted by distance to the channel -- the frontmost (index 1)
-- is the cell nearest the enemy, the backmost (last index) is the cell
-- furthest from it.
function Kit.frontlineCells(config, view, typeId, reserved)
	local candidates = Kit.candidateCells(config, view, typeId, reserved)
	local channelX = (view.owner == "A") and view.board.channelStart or view.board.channelEnd
	table.sort(candidates, function(a, b)
		local da = math.abs(a.x - channelX)
		local db = math.abs(b.x - channelX)
		if da ~= db then
			return da < db
		end
		return a.y < b.y
	end)
	return candidates
end

-- Greedy farthest-point sampling: each pick after the first maximizes its
-- Manhattan distance to every pick already made, so a handful of picks land
-- spread across the candidates rather than clustered together.
function Kit.spreadPick(candidates, count)
	if #candidates == 0 then
		return {}
	end
	local chosen = { candidates[math.random(#candidates)] }
	local used = { [key(chosen[1].x, chosen[1].y)] = true }
	while #chosen < count and #chosen < #candidates do
		local best, bestDist = nil, -1
		for _, c in ipairs(candidates) do
			if not used[key(c.x, c.y)] then
				local minDist = math.huge
				for _, picked in ipairs(chosen) do
					minDist = math.min(minDist, math.abs(c.x - picked.x) + math.abs(c.y - picked.y))
				end
				if minDist > bestDist then
					best, bestDist = c, minDist
				end
			end
		end
		table.insert(chosen, best)
		used[key(best.x, best.y)] = true
	end
	return chosen
end

-- Every land cell in the opponent's territory -- terrain is public (§11).
function Kit.opponentLandCells(view)
	local cells = {}
	local minX, maxX = territoryXRange(view, view.opponent)
	for x = minX, maxX do
		for y = 1, view.board.height do
			if Board.isLand(view.board, x, y) then
				table.insert(cells, { x = x, y = y })
			end
		end
	end
	return cells
end

function Kit.isUnexplored(view, x, y)
	return view.self.belief[key(x, y)] == nil
end

-- Every enemy structure currently plotted on the belief map (stale or not).
function Kit.plottedEnemyStructures(view)
	local found = {}
	for k, entry in pairs(view.self.belief) do
		if entry.typeId then
			local x, y = k:match("(%-?%d+),(%-?%d+)")
			table.insert(found, { x = tonumber(x), y = tonumber(y), typeId = entry.typeId, underConstruction = entry.underConstruction })
		end
	end
	return found
end

-- Every cell in `cells` a weapon at (wx, wy) could legally hit right now: in
-- range and not blocked by terrain. Shared by Kit.chooseTargets and any
-- archetype that wants its own targeting priority over the same reachability
-- check (see sim/archetypes/recon.luau).
function Kit.reachableCells(board, def, wx, wy, cells)
	local hits = {}
	for _, cell in ipairs(cells) do
		local shot = Flight.resolveShot(board, def, wx, wy, cell.x, cell.y)
		if shot.inRange and not shot.blocked then
			table.insert(hits, cell)
		end
	end
	return hits
end

function Kit.liveStructures(view, typeId)
	local list = {}
	for _, structure in ipairs(view.self.structures) do
		if not structure.underConstruction and (not typeId or structure.typeId == typeId) then
			table.insert(list, structure)
		end
	end
	return list
end

function Kit.countType(view, typeId)
	local count = 0
	for _, structure in ipairs(view.self.structures) do
		if structure.typeId == typeId then
			count += 1
		end
	end
	return count
end

-- The weapon-type structures among the "place" commands already decided this
-- round. A structure placed this round completes and can fire in this same
-- round's resolve (§4's literal step order -- see DECISIONS.md), but it isn't
-- in view.self.structures yet since that reflects state as of the start of
-- the round -- pass this alongside Kit.liveStructures to chooseTargets so
-- those weapons get a target too instead of sitting idle their first round.
function Kit.pendingWeaponsFrom(config, commands)
	local weapons = {}
	for _, cmd in ipairs(commands) do
		if cmd.type == "place" and config.STRUCTURES[cmd.typeId].fire_mode then
			table.insert(weapons, { x = cmd.x, y = cmd.y, typeId = cmd.typeId })
		end
	end
	return weapons
end

-- Assigns every live, non-under-construction weapon (plus any `pendingWeapons`
-- placed this same round, see Kit.pendingWeaponsFrom) a legal, unblocked
-- target: a plotted base first, then a plotted generator, then the farthest
-- reachable unexplored cell (height buys information, §11), then any
-- reachable known cell as a last resort so a weapon still fires rather than
-- sitting idle. A weapon with nothing legal to hit is left untargeted.
-- `focusBases`, if given, replaces the base list every weapon picks from --
-- lets a caller commit every weapon to the same single base instead of each
-- one independently randomizing among everything currently plotted.
function Kit.chooseTargets(config, view, pendingWeapons, focusBases)
	local commands = {}
	local plottedBases, plottedGenerators = {}, {}
	for _, s in ipairs(Kit.plottedEnemyStructures(view)) do
		if s.typeId == "base" then
			table.insert(plottedBases, s)
		elseif s.typeId == "generator" then
			table.insert(plottedGenerators, s)
		end
	end
	if focusBases then
		plottedBases = focusBases
	end

	local opponentLand = Kit.opponentLandCells(view)
	local unexplored = {}
	for _, cell in ipairs(opponentLand) do
		if Kit.isUnexplored(view, cell.x, cell.y) then
			table.insert(unexplored, cell)
		end
	end

	local function reachable(def, wx, wy, cells)
		return Kit.reachableCells(view.board, def, wx, wy, cells)
	end

	local weapons = Kit.liveStructures(view)
	if pendingWeapons then
		for _, weapon in ipairs(pendingWeapons) do
			table.insert(weapons, weapon)
		end
	end

	for _, weapon in ipairs(weapons) do
		local def = config.STRUCTURES[weapon.typeId]
		if def.fire_mode then
			local target = nil

			local hitBases = reachable(def, weapon.x, weapon.y, plottedBases)
			if #hitBases > 0 then
				target = hitBases[math.random(#hitBases)]
			end

			if not target then
				local hitGenerators = reachable(def, weapon.x, weapon.y, plottedGenerators)
				if #hitGenerators > 0 then
					target = hitGenerators[math.random(#hitGenerators)]
				end
			end

			if not target then
				local hitUnexplored = reachable(def, weapon.x, weapon.y, unexplored)
				if #hitUnexplored > 0 then
					table.sort(hitUnexplored, function(a, b)
						return Flight.chebyshevDistance(weapon.x, weapon.y, a.x, a.y)
							> Flight.chebyshevDistance(weapon.x, weapon.y, b.x, b.y)
					end)
					local topCount = math.min(3, #hitUnexplored)
					target = hitUnexplored[math.random(topCount)]
				end
			end

			if not target then
				local hitKnown = reachable(def, weapon.x, weapon.y, opponentLand)
				if #hitKnown > 0 then
					target = hitKnown[math.random(#hitKnown)]
				end
			end

			if target then
				table.insert(commands, { type = "target", x = weapon.x, y = weapon.y, targetX = target.x, targetY = target.y })
			end
		end
	end

	return commands
end

return Kit
