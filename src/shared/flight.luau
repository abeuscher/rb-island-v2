-- Line-of-flight: direct-fire beam blocking and range, and arc-fire range.
-- Pure and deterministic; zero Roblox API calls, per §10.

local Board = require("./board")

local Flight = {}

local function round(n)
	if n >= 0 then
		return math.floor(n + 0.5)
	end
	return math.ceil(n - 0.5)
end

function Flight.chebyshevDistance(sx, sy, tx, ty)
	return math.max(math.abs(tx - sx), math.abs(ty - sy))
end

function Flight.range(def, firingElevation)
	return def.range + def.elevation_range_bonus * firingElevation
end

-- Cells strictly between S and T, walked in evenly-spaced steps (an even DDA step
-- matches "Bresenham line" closely enough for a square grid and gives each cell a
-- clean t = step / totalSteps fraction to interpolate beam height against -- the
-- spec names the algorithm but not this fraction's distance metric).
local function beamCells(sx, sy, tx, ty)
	local dx = tx - sx
	local dy = ty - sy
	local steps = math.max(math.abs(dx), math.abs(dy))
	local cells = {}
	for i = 1, steps - 1 do
		local t = i / steps
		table.insert(cells, { x = sx + round(dx * t), y = sy + round(dy * t), t = t })
	end
	return cells
end

-- def.fire_mode == "direct" | "arc". Result:
--   inRange (bool)
--   blocked (bool, direct fire only)
--   impactCell { x, y } -- where the shot actually lands
--   beamPath { {x,y}, ... } -- intervening cells travelled through (direct fire only)
function Flight.resolveShot(board, def, sx, sy, tx, ty)
	local hs = Board.elevationAt(board, sx, sy)
	local dist = Flight.chebyshevDistance(sx, sy, tx, ty)
	if dist > Flight.range(def, hs) then
		return { inRange = false }
	end

	if def.fire_mode ~= "direct" then
		return { inRange = true, blocked = false, impactCell = { x = tx, y = ty }, beamPath = {} }
	end

	local ht = Board.elevationAt(board, tx, ty)
	local muzzle = hs + 1
	local beamPath = {}
	for _, cell in ipairs(beamCells(sx, sy, tx, ty)) do
		table.insert(beamPath, { x = cell.x, y = cell.y })
		local beamHeight = muzzle + (ht - muzzle) * cell.t
		if Board.elevationAt(board, cell.x, cell.y) > beamHeight then
			return { inRange = true, blocked = true, impactCell = { x = cell.x, y = cell.y }, beamPath = beamPath }
		end
	end

	return { inRange = true, blocked = false, impactCell = { x = tx, y = ty }, beamPath = beamPath }
end

return Flight
