local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")

t.test("territory splits the board around the channel", function()
	local board = Board.new(config)
	t.expectEqual(Board.ownerOf(board, 1, 1), "A")
	t.expectEqual(Board.ownerOf(board, 17, 24), "A")
	t.expectEqual(Board.ownerOf(board, 24, 1), "B")
	t.expectEqual(Board.ownerOf(board, 40, 24), "B")
end)

t.test("the channel is unbuildable and belongs to neither player", function()
	local board = Board.new(config)
	t.expectTrue(Board.isChannel(board, 18, 12))
	t.expectTrue(Board.isChannel(board, 23, 12))
	t.expectFalse(Board.isChannel(board, 17, 12))
	t.expectFalse(Board.isChannel(board, 24, 12))
	t.expectFalse(Board.isLand(board, 18, 12))
end)

t.test("each player starts with a 12x12 island flush against the channel, centered vertically", function()
	local board = Board.new(config)
	-- A's island: columns 6-17, rows 7-18
	t.expectTrue(Board.isLand(board, 6, 7))
	t.expectTrue(Board.isLand(board, 17, 18))
	t.expectFalse(Board.isLand(board, 5, 7))
	t.expectFalse(Board.isLand(board, 6, 6))
	-- B's island: columns 24-35, rows 7-18
	t.expectTrue(Board.isLand(board, 24, 7))
	t.expectTrue(Board.isLand(board, 35, 18))
	t.expectFalse(Board.isLand(board, 36, 7))
end)

t.test("islandBounds matches each player's starting island exactly", function()
	local aColStart, aColEnd, aRowStart, aRowEnd = Board.islandBounds(config, "A")
	t.expectEqual(aColStart, 6)
	t.expectEqual(aColEnd, 17)
	t.expectEqual(aRowStart, 7)
	t.expectEqual(aRowEnd, 18)

	local bColStart, bColEnd, bRowStart, bRowEnd = Board.islandBounds(config, "B")
	t.expectEqual(bColStart, 24)
	t.expectEqual(bColEnd, 35)
	t.expectEqual(bRowStart, 7)
	t.expectEqual(bRowEnd, 18)
end)

t.test("every starting cell is flat", function()
	local board = Board.new(config)
	t.expectEqual(Board.elevationAt(board, 6, 7), 0)
	t.expectEqual(Board.elevationAt(board, 35, 18), 0)
end)

t.test("raise fails on water, out of bounds, or above max elevation", function()
	local board = Board.new(config)

	local _, ok, err = Board.raise(board, 1, 1) -- A's water
	t.expectFalse(ok)
	t.expectEqual(err, "cell is not land")

	local _, ok2 = Board.raise(board, 41, 1) -- out of bounds
	t.expectFalse(ok2)
end)

t.test("raising a cell twice without raising its neighbors violates smoothness", function()
	local board = Board.new(config)

	local raisedOnce, ok = Board.raise(board, 6, 7)
	t.expectTrue(ok)
	t.expectEqual(Board.elevationAt(raisedOnce, 6, 7), 1)

	local _, ok2, err2 = Board.raise(raisedOnce, 6, 7)
	t.expectFalse(ok2)
	t.expectEqual(err2, "would violate the smoothness constraint")
end)

t.test("raising a neighborhood evenly reaches max elevation legally", function()
	local board = Board.new(config)

	local ok
	board, ok = Board.raise(board, 6, 7)
	t.expectTrue(ok)
	board, ok = Board.raise(board, 7, 7)
	t.expectTrue(ok)
	board, ok = Board.raise(board, 6, 8)
	t.expectTrue(ok)

	board, ok = Board.raise(board, 6, 7)
	t.expectTrue(ok)
	t.expectEqual(Board.elevationAt(board, 6, 7), config.MAX_ELEVATION)

	local _, ok2, err2 = Board.raise(board, 6, 7)
	t.expectFalse(ok2)
	t.expectEqual(err2, "already at max elevation")
end)

t.test("lower fails at minimum elevation, succeeds after a raise", function()
	local board = Board.new(config)

	local _, ok, err = Board.lower(board, 6, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "already at minimum elevation")

	local raised = Board.raise(board, 6, 7)
	local lowered, ok2 = Board.lower(raised, 6, 7)
	t.expectTrue(ok2)
	t.expectEqual(Board.elevationAt(lowered, 6, 7), 0)
end)

t.test("reclaim requires your own territory, adjacency to your land, and still-water", function()
	local board = Board.new(config)

	local _, ok, err = Board.reclaim(board, "A", 20, 1) -- channel
	t.expectFalse(ok)
	t.expectEqual(err, "not in your territory")

	local _, ok2, err2 = Board.reclaim(board, "B", 5, 7) -- A's water, wrong owner
	t.expectFalse(ok2)
	t.expectEqual(err2, "not in your territory")

	local _, ok3, err3 = Board.reclaim(board, "A", 1, 1) -- A's water, not adjacent to land
	t.expectFalse(ok3)
	t.expectEqual(err3, "must be adjacent to your own land")

	local _, ok4, err4 = Board.reclaim(board, "A", 6, 7) -- already land
	t.expectFalse(ok4)
	t.expectEqual(err4, "cell is already land")

	local reclaimed, ok5 = Board.reclaim(board, "A", 5, 7)
	t.expectTrue(ok5)
	t.expectTrue(Board.isLand(reclaimed, 5, 7))
	t.expectEqual(Board.elevationAt(reclaimed, 5, 7), 0)
end)

t.test("reclaiming next to a raised ridge violates smoothness", function()
	local board = Board.new(config)
	board = Board.raise(board, 6, 7)
	board = Board.raise(board, 7, 7)
	board = Board.raise(board, 6, 8)
	board = Board.raise(board, 6, 7) -- (6,7) now at elevation 2

	local _, ok, err = Board.reclaim(board, "A", 5, 7)
	t.expectFalse(ok)
	t.expectEqual(err, "would violate the smoothness constraint")
end)
