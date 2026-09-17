-- Supply and Energy: per-round accrual and spending.

local Economy = {}

function Economy.new(config)
	return {
		supply = config.SUPPLY_PER_ROUND,
		energy = config.STARTING_ENERGY,
	}
end

function Economy.energyIncome(config, generatorCount)
	return config.ENERGY_BASE + config.ENERGY_PER_GENERATOR * generatorCount
end

function Economy.accrue(config, resources, generatorCount)
	return {
		supply = resources.supply + config.SUPPLY_PER_ROUND,
		energy = math.min(config.ENERGY_CAP, resources.energy + Economy.energyIncome(config, generatorCount)),
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
