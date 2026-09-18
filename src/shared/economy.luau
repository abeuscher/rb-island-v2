-- Supply and Energy: per-round accrual and spending.

local Economy = {}

function Economy.new(config)
	return {
		supply = config.STARTING_SUPPLY,
		energy = config.STARTING_ENERGY,
	}
end

-- Per-second rate, not a per-tick amount -- callers scale by TICK_SECONDS themselves
-- (Economy.tickAccrue does, isUnrecoverable in rules.luau checks the rate directly).
function Economy.energyIncome(config, generatorCount)
	return config.ENERGY_BASE + config.ENERGY_PER_GENERATOR_PER_SECOND * generatorCount
end

function Economy.tickAccrue(config, resources, generatorCount)
	local dt = config.TICK_SECONDS
	return {
		supply = resources.supply + config.SUPPLY_PER_SECOND * dt,
		energy = math.min(config.ENERGY_CAP, resources.energy + Economy.energyIncome(config, generatorCount) * dt),
	}
end

function Economy.canAfford(resources, cost)
	return resources.supply >= (cost.supply or 0) and resources.energy >= (cost.energy or 0)
end

function Economy.spend(resources, cost)
	if not Economy.canAfford(resources, cost) then
		return resources, false, "cannot afford"
	end
	return {
		supply = resources.supply - (cost.supply or 0),
		energy = resources.energy - (cost.energy or 0),
	}, true, nil
end

return Economy
