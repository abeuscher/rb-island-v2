local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Flight = require("../src/shared/flight")

local cannon = config.STRUCTURES.cannon
local mortar = config.STRUCTURES.mortar

local function boardWithElevation(edits)
	local board = Board.new(config)
	for _, edit in ipairs(edits) do
		board.cells[edit.x][edit.y].elevation = edit.h
	end
	return board
end

t.test("chebyshevDistance is the max of the axis deltas", function()
	t.expectEqual(Flight.chebyshevDistance(1, 1, 4, 2), 3)
	t.expectEqual(Flight.chebyshevDistance(1, 1, 2, 5), 4)
	t.expectEqual(Flight.chebyshevDistance(3, 3, 3, 3), 0)
end)

t.test("direct-fire range gains +2 per level of the firing cell's elevation", function()
	t.expectEqual(Flight.range(cannon, 0), 10)
	t.expectEqual(Flight.range(cannon, 1), 12)
	t.expectEqual(Flight.range(cannon, 2), 14)
end)

t.test("arc-fire range is unaffected by elevation", function()
	t.expectEqual(Flight.range(mortar, 0), 16)
	t.expectEqual(Flight.range(mortar, 2), 16)
end)

t.test("a clear direct shot over flat ground is not blocked and lands on the target", function()
	local board = boardWithElevation({})
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)
	t.expectTrue(shot.inRange)
	t.expectFalse(shot.blocked)
	t.expectEqual(shot.impactCell.x, 5)
	t.expectEqual(shot.impactCell.y, 1)
	t.expectEqual(#shot.beamPath, 3) -- cells (2,1) (3,1) (4,1)
end)

t.test("a direct shot is blocked strictly above the beam, hand-worked", function()
	-- S=(1,1) h0, T=(5,1) h0, muzzle=1. At (3,1) t=0.5, beam = 1 + (0-1)*0.5 = 0.5.
	-- A level-2 ridge at (3,1) is strictly above that beam, so the shot stops there.
	local board = boardWithElevation({ { x = 3, y = 1, h = 2 } })
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)
	t.expectTrue(shot.inRange)
	t.expectTrue(shot.blocked)
	t.expectEqual(shot.impactCell.x, 3)
	t.expectEqual(shot.impactCell.y, 1)
	t.expectEqual(#shot.beamPath, 2) -- (2,1) then (3,1), where it stops
end)

t.test("grazing a ridge at exactly beam height passes (strictly greater required)", function()
	-- S=(1,1) h2 (muzzle 3), T=(3,1) h1. At (2,1) t=0.5, beam = 3 + (1-3)*0.5 = 2.
	-- A level-2 cell there equals the beam exactly, so it does not block.
	local board = boardWithElevation({ { x = 1, y = 1, h = 2 }, { x = 2, y = 1, h = 2 }, { x = 3, y = 1, h = 1 } })
	local shot = Flight.resolveShot(board, cannon, 1, 1, 3, 1)
	t.expectTrue(shot.inRange)
	t.expectFalse(shot.blocked)
	t.expectEqual(shot.impactCell.x, 3)
	t.expectEqual(shot.impactCell.y, 1)
end)

t.test("arc fire ignores terrain entirely, even over a ridge that would block direct fire", function()
	local board = boardWithElevation({ { x = 3, y = 1, h = 2 } })
	local shot = Flight.resolveShot(board, mortar, 1, 1, 5, 1)
	t.expectTrue(shot.inRange)
	t.expectFalse(shot.blocked)
	t.expectEqual(shot.impactCell.x, 5)
	t.expectEqual(shot.impactCell.y, 1)
	t.expectEqual(#shot.beamPath, 0)
end)

t.test("a shot beyond range never resolves a beam", function()
	local board = boardWithElevation({})
	local shot = Flight.resolveShot(board, cannon, 1, 1, 12, 1) -- distance 11 > range 10
	t.expectFalse(shot.inRange)
	t.expectEqual(shot.blocked, nil)
end)

t.test("beam path walks a 45-degree line through its exact intermediate cells", function()
	local board = boardWithElevation({})
	local shot = Flight.resolveShot(board, cannon, 1, 1, 4, 4)
	t.expectEqual(#shot.beamPath, 2)
	t.expectEqual(shot.beamPath[1].x, 2)
	t.expectEqual(shot.beamPath[1].y, 2)
	t.expectEqual(shot.beamPath[2].x, 3)
	t.expectEqual(shot.beamPath[2].y, 3)
end)
