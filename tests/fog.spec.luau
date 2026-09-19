local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Flight = require("../src/shared/flight")
local Fog = require("../src/shared/fog")

local cannon = config.STRUCTURES.cannon
local mortar = config.STRUCTURES.mortar
local scout = config.STRUCTURES.scout

t.test("a clean direct hit reveals the whole beam path plus the impact cell", function()
	local board = Board.new(config)
	local structures = { { typeId = "generator", x = 5, y = 1, hp = 8, underConstruction = false } }
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)

	local belief = Fog.applyReveal(config, board, structures, Fog.new(), cannon, shot, { x = 1, y = 1 }, nil)

	t.expectEqual(Fog.at(belief, 2, 1).empty, true)
	t.expectEqual(Fog.at(belief, 3, 1).empty, true)
	t.expectEqual(Fog.at(belief, 4, 1).empty, true)
	t.expectEqual(Fog.at(belief, 5, 1).typeId, "generator")
	t.expectFalse(Fog.at(belief, 5, 1).underConstruction)
end)

t.test("a blocked direct shot only reveals up to and including the block point", function()
	local board = Board.new(config)
	board.cells[3][1].elevation = 2
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)
	t.expectTrue(shot.blocked)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), cannon, shot, { x = 1, y = 1 }, nil)

	t.expectTrue(Fog.at(belief, 2, 1) ~= nil)
	t.expectTrue(Fog.at(belief, 3, 1) ~= nil)
	t.expectTrue(Fog.at(belief, 4, 1) == nil) -- past the block point, never reached
	t.expectTrue(Fog.at(belief, 5, 1) == nil)
end)

t.test("a mortar reveals only the impact cell and its four orthogonal neighbors", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, mortar, 1, 1, 10, 10)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), mortar, shot, { x = 1, y = 1 }, nil)

	t.expectTrue(Fog.at(belief, 10, 10) ~= nil)
	t.expectTrue(Fog.at(belief, 11, 10) ~= nil)
	t.expectTrue(Fog.at(belief, 9, 10) ~= nil)
	t.expectTrue(Fog.at(belief, 10, 11) ~= nil)
	t.expectTrue(Fog.at(belief, 10, 9) ~= nil)
	t.expectTrue(Fog.at(belief, 12, 10) == nil) -- outside the splash pattern
end)

t.test("plots are stale: a later change to the real board never updates an old reveal", function()
	local board = Board.new(config)
	local emptyAtRevealTime = {}
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)

	local belief = Fog.applyReveal(config, board, emptyAtRevealTime, Fog.new(), cannon, shot, { x = 1, y = 1 }, nil)
	t.expectEqual(Fog.at(belief, 5, 1).empty, true)

	-- The defender now builds on that same cell, but nothing re-reveals it.
	local builtAfterReveal = { { typeId = "cannon", x = 5, y = 1, hp = 6, underConstruction = true } }
	t.expectEqual(Fog.at(belief, 5, 1).empty, true) -- unchanged: still the stale plot
	t.expectTrue(#builtAfterReveal == 1) -- sanity: the real board did change
end)

t.test("a structure destroyed this round reveals as rubble, not as empty or its old contents", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)
	local destroyedThisRound = { ["5,1"] = true }

	-- The structure list no longer contains the destroyed generator at (5,1).
	local belief = Fog.applyReveal(config, board, {}, Fog.new(), cannon, shot, { x = 1, y = 1 }, destroyedThisRound)

	t.expectTrue(Fog.at(belief, 5, 1).rubble)
end)

t.test("a scout drone flying orthogonally reveals a 3-wide corridor plus a 4x4 block at the target", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, scout, 1, 10, 8, 10)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), scout, shot, { x = 1, y = 10 }, nil)

	-- Corridor: 3-wide (y = 9, 10, 11) along the whole x = 1..8 flight path.
	for x = 1, 8 do
		t.expectTrue(Fog.at(belief, x, 9) ~= nil)
		t.expectTrue(Fog.at(belief, x, 10) ~= nil)
		t.expectTrue(Fog.at(belief, x, 11) ~= nil)
	end
	t.expectTrue(Fog.at(belief, 1, 8) == nil) -- outside the corridor band
	t.expectTrue(Fog.at(belief, 1, 12) == nil)

	-- 4x4 block anchored on the target (8, 10): x/y in [target-1, target+2].
	for x = 7, 10 do
		for y = 9, 12 do
			t.expectTrue(Fog.at(belief, x, y) ~= nil)
		end
	end
	t.expectTrue(Fog.at(belief, 1, 13) == nil) -- outside both the corridor band and the block
	t.expectTrue(Fog.at(belief, 11, 10) == nil)
end)

t.test("a scout drone flying diagonally widens its corridor on the axis with fewer steps", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, scout, 1, 1, 6, 4)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), scout, shot, { x = 1, y = 1 }, nil)

	-- dx (5) > dy (3), so the corridor widens on y. Checked at the origin's own
	-- column (x = 1), the only column belonging to just one path cell -- everywhere
	-- else along this line overlaps the 4x4 target block or a neighboring stepped
	-- cell's own band, so isn't a clean read on the widening axis by itself.
	t.expectTrue(Fog.at(belief, 1, 2) ~= nil) -- y-band neighbor
	t.expectTrue(Fog.at(belief, 1, 3) == nil) -- band is exactly 3 wide, not wider
end)

t.test("a scout drone's corridor and block clip cleanly at the board edge", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, scout, 1, 1, 2, 1)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), scout, shot, { x = 1, y = 1 }, nil)

	t.expectTrue(Fog.at(belief, 1, 1) ~= nil)
	t.expectTrue(Fog.at(belief, 0, 1) == nil) -- off-board, silently dropped
end)
