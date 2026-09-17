local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Kit = require("../sim/archetypeKit")

local function makeView(round, owner, structures, belief)
	return {
		round = round,
		board = Board.new(config),
		owner = owner,
		opponent = (owner == "A") and "B" or "A",
		self = {
			resources = { supply = 1000, energy = 1000 },
			structures = structures or {},
			belief = belief or {},
		},
	}
end

t.test("candidateCells only returns cells inside the owner's own territory", function()
	local view = makeView(1, "A", {})
	local candidates = Kit.candidateCells(config, view, "base")
	t.expectTrue(#candidates > 0)
	for _, cell in ipairs(candidates) do
		t.expectEqual(Board.ownerOf(view.board, cell.x, cell.y), "A")
	end
end)

t.test("candidateCells excludes cells reserved earlier in the same round", function()
	local view = makeView(1, "A", {})
	local reserved = {}
	Kit.reserve(reserved, config, "base", 6, 7) -- base footprint is 2x2: (6,7),(7,7),(6,8),(7,8)
	local candidates = Kit.candidateCells(config, view, "base", reserved)
	for _, cell in ipairs(candidates) do
		t.expectFalse(cell.x == 6 and cell.y == 7)
		t.expectFalse(cell.x == 7 and cell.y == 7)
	end
end)

t.test("frontlineCells orders candidates by distance to the channel, closest first", function()
	local view = makeView(1, "A", {})
	local cells = Kit.frontlineCells(config, view, "cannon")
	for i = 2, #cells do
		local da = math.abs(cells[i - 1].x - view.board.channelStart)
		local db = math.abs(cells[i].x - view.board.channelStart)
		t.expectTrue(da <= db)
	end
end)

t.test("spreadPick returns the requested count of distinct cells", function()
	math.randomseed(1)
	local candidates = {}
	for x = 1, 10 do
		table.insert(candidates, { x = x, y = 1 })
	end
	local chosen = Kit.spreadPick(candidates, 3)
	t.expectEqual(#chosen, 3)

	local seen = {}
	for _, cell in ipairs(chosen) do
		local key = cell.x .. "," .. cell.y
		t.expectTrue(not seen[key])
		seen[key] = true
	end
end)

t.test("plottedEnemyStructures reads typed entries off the belief map, ignoring empty/rubble", function()
	local view = makeView(3, "A", {}, {
		["24,7"] = { typeId = "base", underConstruction = false },
		["10,10"] = { empty = true },
		["11,10"] = { rubble = true },
	})
	local plotted = Kit.plottedEnemyStructures(view)
	t.expectEqual(#plotted, 1)
	t.expectEqual(plotted[1].typeId, "base")
	t.expectEqual(plotted[1].x, 24)
	t.expectEqual(plotted[1].y, 7)
end)

t.test("chooseTargets never assigns a target beyond the weapon's range", function()
	local view = makeView(1, "A", {
		{ typeId = "cannon", x = 17, y = 10, hp = config.STRUCTURES.cannon.hp, underConstruction = false },
	}, {})
	local commands = Kit.chooseTargets(config, view)
	t.expectTrue(#commands > 0)
	for _, cmd in ipairs(commands) do
		local dist = math.max(math.abs(cmd.targetX - cmd.x), math.abs(cmd.targetY - cmd.y))
		t.expectTrue(dist <= config.STRUCTURES.cannon.range)
	end
end)

t.test("chooseTargets also targets weapons placed this same round via pendingWeapons", function()
	local view = makeView(1, "A", {}, {})
	local pending = Kit.pendingWeaponsFrom(config, { { type = "place", typeId = "cannon", x = 17, y = 10 } })
	local commands = Kit.chooseTargets(config, view, pending)
	t.expectEqual(#commands, 1)
	t.expectEqual(commands[1].x, 17)
	t.expectEqual(commands[1].y, 10)
end)

t.test("pendingWeaponsFrom only pulls weapon-type structures out of this round's place commands", function()
	local commands = {
		{ type = "place", typeId = "base", x = 6, y = 7 },
		{ type = "place", typeId = "cannon", x = 17, y = 10 },
		{ type = "target", x = 1, y = 1, targetX = 2, targetY = 2 },
	}
	local weapons = Kit.pendingWeaponsFrom(config, commands)
	t.expectEqual(#weapons, 1)
	t.expectEqual(weapons[1].typeId, "cannon")
end)
