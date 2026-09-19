-- Reveal computation and stale belief maps (§11). A belief map records what a
-- player last saw on enemy cells; it only changes on an actual reveal, never live.

local Board = require("./board")
local Structures = require("./structures")
local Flight = require("./flight")

local Fog = {}

local NEIGHBOR_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function key(x, y)
	return x .. "," .. y
end

-- Every cell the scout drone's corridor sweeps: origin, target, and every
-- Flight.beamCells stepping point between them, each widened into a 3-wide band
-- perpendicular to the dominant travel axis (grid-aligned, rather than a true
-- geometric perpendicular that wouldn't stay on-grid for a diagonal path).
local function corridorCells(originX, originY, targetX, targetY)
	local dx = targetX - originX
	local dy = targetY - originY
	local perpX, perpY = 1, 0
	if math.abs(dx) >= math.abs(dy) then
		perpX, perpY = 0, 1
	end

	local pathCells = { { x = originX, y = originY } }
	for _, cell in ipairs(Flight.beamCells(originX, originY, targetX, targetY)) do
		table.insert(pathCells, { x = cell.x, y = cell.y })
	end
	table.insert(pathCells, { x = targetX, y = targetY })

	local cells = {}
	for _, cell in ipairs(pathCells) do
		table.insert(cells, { x = cell.x - perpX, y = cell.y - perpY })
		table.insert(cells, { x = cell.x, y = cell.y })
		table.insert(cells, { x = cell.x + perpX, y = cell.y + perpY })
	end
	return cells
end

function Fog.new()
	return {}
end

function Fog.at(belief, x, y)
	return belief[key(x, y)]
end

-- What a reveal at (x, y) records right now: a live/under-construction structure,
-- rubble if `destroyedThisRound` names a structure destroyed at this cell this
-- round, or empty land.
function Fog.snapshotCell(config, structures, x, y, destroyedThisRound)
	if destroyedThisRound and destroyedThisRound[key(x, y)] then
		return { rubble = true }
	end

	local structure = Structures.at(config.STRUCTURES, structures, x, y)
	if structure then
		return { typeId = structure.typeId, underConstruction = structure.underConstruction }
	end

	return { empty = true }
end

-- Every cell a shot's reveal touches, keyed off def.reveal_mode: the full beam path
-- plus impact point for the cannon's "beam"; a 3-wide corridor from the firing cell
-- to the target plus a 4x4 block at the target for the scout drone's "scout"; the
-- impact cell and its four orthogonal neighbors for everything else ("impact").
function Fog.revealedCells(def, shot, origin)
	local cells = {}
	local seen = {}
	local function add(x, y)
		local k = key(x, y)
		if not seen[k] then
			seen[k] = true
			table.insert(cells, { x = x, y = y })
		end
	end

	if def.reveal_mode == "beam" then
		for _, cell in ipairs(shot.beamPath) do
			add(cell.x, cell.y)
		end
		add(shot.impactCell.x, shot.impactCell.y)
	elseif def.reveal_mode == "scout" then
		for _, cell in ipairs(corridorCells(origin.x, origin.y, shot.impactCell.x, shot.impactCell.y)) do
			add(cell.x, cell.y)
		end
		-- 4x4 block anchored on the target: a 4x4 has no true center on a grid, so
		-- the target sits one cell in from the near edge, two from the far edge, on
		-- both axes.
		for ox = -1, 2 do
			for oy = -1, 2 do
				add(shot.impactCell.x + ox, shot.impactCell.y + oy)
			end
		end
	else
		add(shot.impactCell.x, shot.impactCell.y)
		for _, offset in ipairs(NEIGHBOR_OFFSETS) do
			add(shot.impactCell.x + offset[1], shot.impactCell.y + offset[2])
		end
	end

	return cells
end

function Fog.applyReveal(config, board, structures, belief, def, shot, origin, destroyedThisRound)
	local newBelief = table.clone(belief)
	for _, cell in ipairs(Fog.revealedCells(def, shot, origin)) do
		if Board.inBounds(board, cell.x, cell.y) and not Board.isChannel(board, cell.x, cell.y) then
			newBelief[key(cell.x, cell.y)] = Fog.snapshotCell(config, structures, cell.x, cell.y, destroyedThisRound)
		end
	end
	return newBelief
end

return Fog
