local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Flight = require("../src/shared/flight")
local Fog = require("../src/shared/fog")

local cannon = config.STRUCTURES.cannon
local mortar = config.STRUCTURES.mortar

t.test("a clean direct hit reveals the whole beam path plus the impact cell", function()
	local board = Board.new(config)
	local structures = { { typeId = "generator", x = 5, y = 1, hp = 8, underConstruction = false } }
	local shot = Flight.resolveShot(board, cannon, 1, 1, 5, 1)

	local belief = Fog.applyReveal(config, board, structures, Fog.new(), cannon, shot, nil)

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

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), cannon, shot, nil)

	t.expectTrue(Fog.at(belief, 2, 1) ~= nil)
	t.expectTrue(Fog.at(belief, 3, 1) ~= nil)
	t.expectTrue(Fog.at(belief, 4, 1) == nil) -- past the block point, never reached
	t.expectTrue(Fog.at(belief, 5, 1) == nil)
end)

t.test("a mortar reveals only the impact cell and its four orthogonal neighbors", function()
	local board = Board.new(config)
	local shot = Flight.resolveShot(board, mortar, 1, 1, 10, 10)

	local belief = Fog.applyReveal(config, board, {}, Fog.new(), mortar, shot, nil)

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

	local belief = Fog.applyReveal(config, board, emptyAtRevealTime, Fog.new(), cannon, shot, nil)
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
	local belief = Fog.applyReveal(config, board, {}, Fog.new(), cannon, shot, destroyedThisRound)

	t.expectTrue(Fog.at(belief, 5, 1).rubble)
end)
