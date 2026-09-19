local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local Loadout = require("../sim/loadout")

local function makeView(owner, structures, belief)
	return {
		elapsed = 10,
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

local function structure(typeId, x, y)
	return { typeId = typeId, x = x, y = y, hp = config.STRUCTURES[typeId].hp, underConstruction = false }
end

local plottedBase = { ["24,7"] = { typeId = "base", underConstruction = false } }

t.test("holdFireSet holds a cannon once a mortar exists and a base is plotted", function()
	local view = makeView("A", { structure("cannon", 17, 10), structure("mortar", 18, 10) }, plottedBase)
	local holdFire = Loadout.holdFireSet(config, view)
	t.expectTrue(holdFire.cannon)
end)

t.test("holdFireSet leaves a cannon free to scout when no base or generator is plotted yet", function()
	local view = makeView("A", { structure("cannon", 17, 10), structure("mortar", 18, 10) }, {})
	local holdFire = Loadout.holdFireSet(config, view)
	t.expectTrue(not holdFire.cannon)
end)

t.test("holdFireSet leaves a cannon free when no arc-finisher weapon exists", function()
	local view = makeView("A", { structure("cannon", 17, 10) }, plottedBase)
	local holdFire = Loadout.holdFireSet(config, view)
	t.expectTrue(not holdFire.cannon)
end)

t.test("holdFireSet never holds an arc-finisher back", function()
	local view = makeView("A", { structure("cannon", 17, 10), structure("mortar", 18, 10) }, plottedBase)
	local holdFire = Loadout.holdFireSet(config, view)
	t.expectTrue(not holdFire.mortar)
end)

t.test("holdFireSet counts this round's pendingWeapons toward category presence too", function()
	local view = makeView("A", { structure("cannon", 17, 10) }, plottedBase)
	local pending = { { typeId = "mortar", x = 18, y = 10 } }
	local holdFire = Loadout.holdFireSet(config, view, pending)
	t.expectTrue(holdFire.cannon)
end)
