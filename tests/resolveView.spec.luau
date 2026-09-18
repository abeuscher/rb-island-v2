local t = require("./testkit")
local config = require("../src/shared/config")
local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")
local ResolveView = require("../src/shared/resolveView")

local function withBase(x, y)
	return { typeId = "base", x = x, y = y, hp = config.STRUCTURES.base.hp, underConstruction = false }
end

local function withCannon(x, y)
	return { typeId = "cannon", x = x, y = y, hp = config.STRUCTURES.cannon.hp, underConstruction = false }
end

t.test("both sides' shots land in a single owner's view, each carrying the firing weapon's real cell", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7), withCannon(6, 8) }, resources = { supply = 100, energy = 10 } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, resources = { supply = 100, energy = 10 } })

	local commandsA = { { type = "target", x = 6, y = 8, targetX = 24, targetY = 7 } }
	local _, _, _, resolution = Rules.resolveRound(config, state, commandsA, {})

	local view = ResolveView.new(config, "A", resolution, {}, {})
	t.expectEqual(#view.shots, 1)
	t.expectEqual(view.shots[1].owner, "A")
	t.expectEqual(view.shots[1].origin.x, 6)
	t.expectEqual(view.shots[1].origin.y, 8)

	local enemyView = ResolveView.new(config, "B", resolution, {}, {})
	t.expectEqual(#enemyView.shots, 1)
	t.expectEqual(enemyView.shots[1].owner, "A")
end)

t.test("a targeted weapon that produced no shot explains itself in misfireMessages", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withCannon(6, 8) }, resources = { supply = 100, energy = 0 } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local commandsA = { { type = "target", x = 6, y = 8, targetX = 24, targetY = 7 } }
	local _, _, _, resolution = Rules.resolveRound(config, state, commandsA, {})

	local targets = { ["6,8"] = { x = 24, y = 7 } }
	local view = ResolveView.new(config, "A", resolution, targets, {})
	t.expectEqual(#view.shots, 0)
	t.expectEqual(#view.misfireMessages, 1)
	t.expectTrue(view.misfireMessages[1]:find("not enough Energy") ~= nil)
end)

t.test("destroyed carries both sides' losses and board is the pre-combat (post-terrain-edit) board", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local _, _, _, resolution = Rules.resolveRound(config, state, {}, {})
	local view = ResolveView.new(config, "A", resolution, {}, {})

	t.expectEqual(#view.destroyed, 0)
	t.expectTrue(view.board == resolution.preState.board)
end)

t.test("newBelief passes through unchanged -- it's the caller's own post-reveal belief map", function()
	local state = State.new(config)
	local _, _, _, resolution = Rules.resolveRound(config, state, {}, {})
	local belief = { ["24,7"] = { typeId = "base" } }
	local view = ResolveView.new(config, "A", resolution, {}, belief)
	t.expectTrue(view.newBelief == belief)
end)
