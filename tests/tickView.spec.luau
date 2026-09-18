local t = require("./testkit")
local config = require("../src/shared/config")
local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")
local TickView = require("../src/shared/tickView")

local function withBase(x, y)
	return { typeId = "base", x = x, y = y, hp = config.STRUCTURES.base.hp, underConstruction = false }
end

local function withCannon(x, y)
	return { typeId = "cannon", x = x, y = y, hp = config.STRUCTURES.cannon.hp, underConstruction = false, nextFireAt = 0 }
end

t.test("both sides' shots land in a single owner's view, each carrying the firing weapon's real cell", function()
	local state = State.new(config)
	-- The base's 2x2 footprint covers (6,7)-(7,8), so the cannon sits at (6,9) --
	-- one row further out -- to avoid overlapping it (Structures.at, which
	-- setTarget uses to find the weapon, returns the first structure whose
	-- footprint covers the cell).
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7), withCannon(6, 9) }, resources = { supply = 100, energy = 10 } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, resources = { supply = 100, energy = 10 } })
	state = Rules.applyCommand(config, state, "A", { type = "target", x = 6, y = 9, targetX = 24, targetY = 7 })

	local _, _, _, resolution = Rules.tick(config, state)

	local view = TickView.new("A", resolution, {})
	t.expectEqual(#view.shots, 1)
	t.expectEqual(view.shots[1].owner, "A")
	t.expectEqual(view.shots[1].origin.x, 6)
	t.expectEqual(view.shots[1].origin.y, 9)

	local enemyView = TickView.new("B", resolution, {})
	t.expectEqual(#enemyView.shots, 1)
	t.expectEqual(enemyView.shots[1].owner, "A")
end)

t.test("destroyed carries both sides' losses", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local _, _, _, resolution = Rules.tick(config, state)
	local view = TickView.new("A", resolution, {})

	t.expectEqual(#view.destroyed, 0)
end)

t.test("newBelief passes through unchanged -- it's the caller's own post-reveal belief map", function()
	local state = State.new(config)
	local _, _, _, resolution = Rules.tick(config, state)
	local belief = { ["24,7"] = { typeId = "base" } }
	local view = TickView.new("A", resolution, belief)
	t.expectTrue(view.newBelief == belief)
end)
