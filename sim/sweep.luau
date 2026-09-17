-- First parameter sweep (§15): three staged passes, each layering its own
-- knobs on top of the previous pass's best pick rather than one full joint
-- grid, which is how §15 phrases it ("...then a second pass on...").
--
-- §15 names two sweep dimensions, CANNON_RANGE and MORTAR_RANGE, that don't
-- exist as flat config keys -- they're config.STRUCTURES.cannon.range and
-- .mortar.range. Mapped here; see DECISIONS.md.

local Harness = require("./harness")
local Metrics = require("./metrics")
local archetypes = require("./archetypes")

local Sweep = {}

local function deepClone(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepClone(v)
	end
	return copy
end
Sweep.deepClone = deepClone

-- All combinations of a { name = { values... } } dimension table, as a list
-- of { name = value, ... } override tables.
function Sweep.cartesian(dimensions)
	local names = {}
	for name in pairs(dimensions) do
		table.insert(names, name)
	end
	table.sort(names)

	local combos = { {} }
	for _, name in ipairs(names) do
		local expanded = {}
		for _, combo in ipairs(combos) do
			for _, value in ipairs(dimensions[name]) do
				local copy = table.clone(combo)
				copy[name] = value
				table.insert(expanded, copy)
			end
		end
		combos = expanded
	end
	return combos
end

local GENERATOR_HEAVY_POINTS = {
	destroy = { base = 100, mortar = 35, generator = 50, cannon = 20 },
	standing = { base = 50, mortar = 15, generator = 20, cannon = 10 },
}

local function applyOverride(config, name, value)
	if name == "CANNON_RANGE" then
		config.STRUCTURES.cannon.range = value
	elseif name == "MORTAR_RANGE" then
		config.STRUCTURES.mortar.range = value
	elseif name == "POINTS_PRESET" then
		if value == "generatorHeavy" then
			config.POINTS = deepClone(GENERATOR_HEAVY_POINTS)
		end
	else
		config[name] = value
	end
end

-- `base` deep-cloned and every key in `overrides` applied on top.
function Sweep.buildConfig(base, overrides)
	local config = deepClone(base)
	for name, value in pairs(overrides) do
		applyOverride(config, name, value)
	end
	return config
end

-- Runs one round robin at `config` and reduces it to the handful of numbers
-- the shortlist filter and ranking care about.
function Sweep.evaluate(config, matchesPerPair, baseSeed)
	local results = Harness.runRoundRobin(config, archetypes, matchesPerPair, baseSeed)

	local maxFieldWinRate = 0
	for _, rate in pairs(Metrics.fieldWinRates(results)) do
		maxFieldWinRate = math.max(maxFieldWinRate, rate)
	end
	local conditions = Metrics.victoryConditionDistribution(results)

	return {
		maxFieldWinRate = maxFieldWinRate,
		cannonBlockRate = Metrics.cannonBlockRate(results) or 0,
		roundLimitShare = conditions.round_limit or 0,
		averageFirstBaseFraction = Metrics.averageFirstBaseFraction(results) or 0,
	}
end

-- A config survives if no archetype dominates the field, cannons are neither
-- cosmetic nor dead weight, and the match isn't decided by the round limit
-- almost every time (§15).
function Sweep.survives(measurement)
	return measurement.maxFieldWinRate <= 0.60
		and measurement.cannonBlockRate >= 0.15
		and measurement.cannonBlockRate <= 0.85
		and measurement.roundLimitShare <= 0.90
end

-- Lower is better: distance of the field win rate from a fair 50/50, distance
-- of the cannon block rate from a healthy midpoint, and a penalty for leaning
-- on the round limit to decide most matches.
function Sweep.badness(measurement)
	return math.abs(measurement.maxFieldWinRate - 0.5) * 2
		+ math.abs(measurement.cannonBlockRate - 0.5)
		+ math.max(0, measurement.roundLimitShare - 0.5)
end

-- Evaluates every combo in `dimensions` layered on top of `baseOverrides`,
-- returning every { overrides, measurement } point plus the best one found.
function Sweep.runPass(baseConfig, baseOverrides, dimensions, matchesPerPair, baseSeed)
	local points = {}
	local best, bestBadness = nil, math.huge
	for _, combo in ipairs(Sweep.cartesian(dimensions)) do
		local overrides = table.clone(baseOverrides)
		for name, value in pairs(combo) do
			overrides[name] = value
		end

		local config = Sweep.buildConfig(baseConfig, overrides)
		local measurement = Sweep.evaluate(config, matchesPerPair, baseSeed)
		local point = { overrides = overrides, measurement = measurement }
		table.insert(points, point)

		local score = Sweep.badness(measurement)
		if score < bestBadness then
			best, bestBadness = point, score
		end
	end
	return points, best
end

return Sweep
