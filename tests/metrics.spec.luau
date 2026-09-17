local t = require("./testkit")
local Metrics = require("../sim/metrics")

local function match(archetypeA, archetypeB, winner, condition, rounds, overrides)
	local base = {
		archetypeA = archetypeA,
		archetypeB = archetypeB,
		winner = winner,
		condition = condition,
		rounds = rounds,
		finalScoreA = 0,
		finalScoreB = 0,
		finalDestructionPointsA = 0,
		finalDestructionPointsB = 0,
		placements = {},
		shots = {},
		scoreByRound = {},
		firstBaseFoundRound = { A = nil, B = nil },
	}
	for k, v in pairs(overrides or {}) do
		base[k] = v
	end
	return base
end

t.test("winRateMatrix combines both seatings of a matchup into one rate", function()
	local results = {
		match("x", "y", "A", "round_limit", 5),
		match("x", "y", "A", "round_limit", 5),
		match("y", "x", "B", "round_limit", 5), -- x also wins here, playing as B
	}
	local matrix = Metrics.winRateMatrix(results)
	t.expectEqual(matrix.x.y, 1)
	t.expectEqual(matrix.y.x, 0)
end)

t.test("fieldWinRates excludes self-play", function()
	local results = {
		match("x", "x", "A", "round_limit", 5),
		match("x", "y", "A", "round_limit", 5),
	}
	local rates = Metrics.fieldWinRates(results)
	t.expectEqual(rates.x, 1)
end)

t.test("roundsToFirstBaseDistribution and averageFirstBaseFraction read firstBaseFoundRound", function()
	local results = {
		match("x", "y", "A", "round_limit", 4, { firstBaseFoundRound = { A = 2, B = nil } }),
	}
	local histogram, neverFound = Metrics.roundsToFirstBaseDistribution(results)
	t.expectEqual(histogram[2], 1)
	t.expectEqual(neverFound, 1)
	t.expectEqual(Metrics.averageFirstBaseFraction(results), 0.5)
end)

t.test("comebackRate counts a match where the side behind at the midpoint went on to win", function()
	local results = {
		match("x", "y", "A", "base_elimination", 4, {
			scoreByRound = { { A = 0, B = 10 }, { A = 5, B = 10 }, { A = 20, B = 10 }, { A = 30, B = 10 } },
		}),
	}
	-- midpoint = floor(4/2) = round 2 -> A trails (5 < 10), and A is the winner.
	t.expectEqual(Metrics.comebackRate(results), 1)
end)

t.test("comebackRate excludes a match tied at the midpoint", function()
	local results = {
		match("x", "y", "A", "base_elimination", 4, {
			scoreByRound = { { A = 0, B = 0 }, { A = 10, B = 10 }, { A = 20, B = 10 }, { A = 30, B = 10 } },
		}),
	}
	t.expectEqual(Metrics.comebackRate(results), nil)
end)

t.test("cannonBlockRate only counts cannon-typed shots", function()
	local results = {
		match("x", "y", "A", "round_limit", 5, {
			shots = {
				{ owner = "A", typeId = "cannon", blocked = true },
				{ owner = "A", typeId = "cannon", blocked = false },
				{ owner = "B", typeId = "mortar", blocked = false },
			},
		}),
	}
	t.expectEqual(Metrics.cannonBlockRate(results), 0.5)
end)

t.test("purchaseShare divides per-type counts by the total number of placements", function()
	local results = {
		match("x", "y", "A", "round_limit", 5, {
			placements = { { typeId = "base" }, { typeId = "base" }, { typeId = "generator" } },
		}),
	}
	local shares, counts = Metrics.purchaseShare(results)
	t.expectEqual(counts.base, 2)
	t.expectTrue(math.abs(shares.generator - (1 / 3)) < 1e-9)
end)

t.test("victoryConditionDistribution divides counts by the total match count", function()
	local results = {
		match("x", "y", "A", "base_elimination", 3),
		match("x", "y", "B", "round_limit", 5),
	}
	local fractions = Metrics.victoryConditionDistribution(results)
	t.expectEqual(fractions.base_elimination, 0.5)
	t.expectEqual(fractions.round_limit, 0.5)
end)
