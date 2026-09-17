local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Structures = require("../src/shared/structures")

local function freshBoard()
	return Board.new(config)
end

t.test("canPlace rejects an unknown type, a locked type, and illegal cells", function()
	local board = freshBoard()
	local list = Structures.new()

	local ok1, err1 = Structures.canPlace(config, board, list, "A", "nope", 6, 7, 1)
	t.expectFalse(ok1)
	t.expectEqual(err1, "unknown structure type")

	local ok2, err2 = Structures.canPlace(config, board, list, "A", "mortar", 6, 7, 1)
	t.expectFalse(ok2)
	t.expectEqual(err2, "not unlocked yet")

	local ok3, err3 = Structures.canPlace(config, board, list, "A", "generator", 1, 1, 1) -- water
	t.expectFalse(ok3)
	t.expectEqual(err3, "cell is not land")

	local ok4, err4 = Structures.canPlace(config, board, list, "A", "generator", 24, 7, 1) -- B's island
	t.expectFalse(ok4)
	t.expectEqual(err4, "not in your territory")
end)

t.test("placing a structure sets half HP and marks it under construction", function()
	local board = freshBoard()
	local list = Structures.new()

	local newList, ok = Structures.place(config, board, list, "A", "generator", 6, 7, 1)
	t.expectTrue(ok)
	t.expectEqual(#newList, 1)
	t.expectTrue(newList[1].underConstruction)
	t.expectEqual(newList[1].hp, math.floor(config.STRUCTURES.generator.hp / 2))
end)

t.test("a structure's full footprint blocks overlapping placement, including partial overlap", function()
	local board = freshBoard()
	local list = Structures.new()

	local afterBase, ok = Structures.place(config, board, list, "A", "base", 6, 7, 1) -- occupies (6,7)-(7,8)
	t.expectTrue(ok)

	local _, ok2, err2 = Structures.place(config, board, afterBase, "A", "generator", 7, 8, 1)
	t.expectFalse(ok2)
	t.expectEqual(err2, "cell is occupied")

	local _, ok3 = Structures.place(config, board, afterBase, "A", "generator", 9, 7, 1)
	t.expectTrue(ok3)
end)

t.test("bulldoze frees every cell of a structure's footprint", function()
	local board = freshBoard()
	local list = Structures.new()
	local afterBase = Structures.place(config, board, list, "A", "base", 6, 7, 1)

	local afterBulldoze, ok = Structures.bulldoze(config, afterBase, 7, 8) -- any covered cell
	t.expectTrue(ok)
	t.expectEqual(#afterBulldoze, 0)

	local _, ok2, err2 = Structures.bulldoze(config, afterBulldoze, 7, 8)
	t.expectFalse(ok2)
	t.expectEqual(err2, "no structure there")
end)

t.test("completeConstruction restores full HP and live status", function()
	local board = freshBoard()
	local list = Structures.new()
	local afterPlace = Structures.place(config, board, list, "A", "generator", 6, 7, 1)

	t.expectEqual(Structures.countLive(afterPlace, "generator"), 0)

	local afterComplete = Structures.completeConstruction(config, afterPlace)
	t.expectFalse(afterComplete[1].underConstruction)
	t.expectEqual(afterComplete[1].hp, config.STRUCTURES.generator.hp)
	t.expectEqual(Structures.countLive(afterComplete, "generator"), 1)
end)
