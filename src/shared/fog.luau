-- Reveal computation and stale belief maps (§11). A belief map records what a
-- player last saw on enemy cells; it only changes on an actual reveal, never live.

local Board = require("./board")
local Structures = require("./structures")

local Fog = {}

local NEIGHBOR_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function key(x, y)
	return x .. "," .. y
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

-- Every cell a shot's reveal touches: the full beam path plus impact point for
-- direct fire; the impact cell and its four orthogonal neighbors for arc fire.
function Fog.revealedCells(def, shot)
	local cells = {}
	local seen = {}
	local function add(x, y)
		local k = key(x, y)
		if not seen[k] then
			seen[k] = true
			table.insert(cells, { x = x, y = y })
		end
	end

	if def.fire_mode == "direct" then
		for _, cell in ipairs(shot.beamPath) do
			add(cell.x, cell.y)
		end
		add(shot.impactCell.x, shot.impactCell.y)
	else
		add(shot.impactCell.x, shot.impactCell.y)
		for _, offset in ipairs(NEIGHBOR_OFFSETS) do
			add(shot.impactCell.x + offset[1], shot.impactCell.y + offset[2])
		end
	end

	return cells
end

function Fog.applyReveal(config, board, structures, belief, def, shot, destroyedThisRound)
	local newBelief = table.clone(belief)
	for _, cell in ipairs(Fog.revealedCells(def, shot)) do
		if Board.inBounds(board, cell.x, cell.y) and not Board.isChannel(board, cell.x, cell.y) then
			newBelief[key(cell.x, cell.y)] = Fog.snapshotCell(config, structures, cell.x, cell.y, destroyedThisRound)
		end
	end
	return newBelief
end

return Fog
