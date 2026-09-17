local t = require("./testkit")
local config = require("../src/shared/config")
local Economy = require("../src/shared/economy")

t.test("players open with one round of Supply and their starting Energy", function()
	local resources = Economy.new(config)
	t.expectEqual(resources.supply, config.SUPPLY_PER_ROUND)
	t.expectEqual(resources.energy, config.STARTING_ENERGY)
end)

t.test("Energy income is zero with no generators, since ENERGY_BASE is zero", function()
	t.expectEqual(Economy.energyIncome(config, 0), 0)
	t.expectEqual(Economy.energyIncome(config, 2), 2 * config.ENERGY_PER_GENERATOR)
end)

t.test("accrue adds Supply uncapped and Energy capped at ENERGY_CAP", function()
	local resources = { supply = 5, energy = config.ENERGY_CAP - 1 }
	local accrued = Economy.accrue(config, resources, 3)
	t.expectEqual(accrued.supply, 5 + config.SUPPLY_PER_ROUND)
	t.expectEqual(accrued.energy, config.ENERGY_CAP)
end)

t.test("spend fails without mutating resources when unaffordable", function()
	local resources = { supply = 5, energy = 1 }
	local unchanged, ok, err = Economy.spend(resources, { supply = 10 })
	t.expectFalse(ok)
	t.expectEqual(err, "cannot afford")
	t.expectEqual(unchanged.supply, 5)
end)

t.test("spend deducts both Supply and Energy costs when affordable", function()
	local resources = { supply = 10, energy = 3 }
	local spent, ok = Economy.spend(resources, { supply = 10, energy = 1 })
	t.expectTrue(ok)
	t.expectEqual(spent.supply, 0)
	t.expectEqual(spent.energy, 2)
end)
