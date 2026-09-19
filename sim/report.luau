-- Output plumbing shared by the sim and sweep entry points: per-match JSONL
-- logs, an aggregate CSV, and a plain-text metrics summary (§15).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Metrics = require("./metrics")

local Report = {}

function Report.ensureDir(path)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

function Report.writeMatchLogJsonl(path, results)
	local lines = {}
	for _, r in ipairs(results) do
		table.insert(lines, serde.encode("json", r))
	end
	fs.writeFile(path, table.concat(lines, "\n") .. "\n")
end

function Report.writeAggregateCsv(path, results)
	local lines = { "seed,archetypeA,archetypeB,duration,winner,condition,finalScoreA,finalScoreB" }
	for _, r in ipairs(results) do
		table.insert(
			lines,
			table.concat({
				r.seed,
				r.archetypeA,
				r.archetypeB,
				r.duration,
				r.winner or "draw",
				r.condition,
				r.finalScoreA,
				r.finalScoreB,
			}, ",")
		)
	end
	fs.writeFile(path, table.concat(lines, "\n") .. "\n")
end

local function formatPercent(value)
	if value == nil then
		return "n/a"
	end
	return string.format("%.1f%%", value * 100)
end

-- Sorts numerically when every key is a number (round-number histograms),
-- otherwise falls back to string order (archetype/structure names).
local function sortedKeys(t)
	local keys = {}
	local allNumbers = true
	for k in pairs(t) do
		table.insert(keys, k)
		if type(k) ~= "number" then
			allNumbers = false
		end
	end
	if allNumbers then
		table.sort(keys)
	else
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
	end
	return keys
end

-- A plain-text report covering every metric in §15: win-rate matrix,
-- time-to-first-base distribution, match-length distribution, comeback
-- rate, purchase share, cannon block rate, and victory-condition
-- distribution.
function Report.summaryText(config, results)
	local lines = {}
	local function say(line)
		table.insert(lines, line)
	end

	say(string.format("%d matches", #results))
	say("")

	say("Win rate matrix (row beats column):")
	local matrix = Metrics.winRateMatrix(results)
	local names = sortedKeys(matrix)
	say("            " .. table.concat(names, "  "))
	for _, x in ipairs(names) do
		local row = { string.format("%-10s ", x) }
		for _, y in ipairs(names) do
			table.insert(row, string.format("%6s", formatPercent(matrix[x][y])))
		end
		say(table.concat(row))
	end
	say("")

	say("Win rate vs the field (target: none over 60%):")
	local field = Metrics.fieldWinRates(results)
	for _, name in ipairs(sortedKeys(field)) do
		say(string.format("  %-12s %s", name, formatPercent(field[name])))
	end
	say("")

	say("Time to first real base found, binned to 10s (target: 25-45% of match length):")
	local avgFraction = Metrics.averageFirstBaseFraction(results)
	local histogram, neverFound = Metrics.timeToFirstBaseDistribution(results)
	say(string.format("  average: %s of match length, never found: %d", formatPercent(avgFraction), neverFound))
	for _, elapsed in ipairs(sortedKeys(histogram)) do
		say(string.format("  %d-%ds: %d", elapsed, elapsed + 9, histogram[elapsed]))
	end
	say("")

	say("Match length distribution, binned to 10s:")
	local lengths = Metrics.matchLengthDistribution(results)
	for _, duration in ipairs(sortedKeys(lengths)) do
		say(string.format("  %d-%ds: %d matches", duration, duration + 9, lengths[duration]))
	end
	say("")

	say(string.format("Comeback rate (behind at midpoint, won anyway): %s", formatPercent(Metrics.comebackRate(results))))
	say(string.format("Cannon block rate (target: neither ~0%% nor ~100%%): %s", formatPercent(Metrics.cannonBlockRate(results))))
	say(string.format("Supply efficiency (destruction+standing points per Supply spent): %.2f", Metrics.supplyEfficiency(config, results) or 0))
	say("")

	say("Purchase share (never-bought = miscosted):")
	local shares = Metrics.purchaseShare(results)
	for _, typeId in ipairs(sortedKeys(shares)) do
		say(string.format("  %-10s %s", typeId, formatPercent(shares[typeId])))
	end
	for typeId in pairs(config.STRUCTURES) do
		if shares[typeId] == nil then
			say(string.format("  %-10s NEVER BOUGHT", typeId))
		end
	end
	say("")

	say("Victory condition distribution:")
	local conditions = Metrics.victoryConditionDistribution(results)
	for _, condition in ipairs(sortedKeys(conditions)) do
		say(string.format("  %-18s %s", condition, formatPercent(conditions[condition])))
	end

	return table.concat(lines, "\n")
end

-- A plain-text report of sim/placementSuite.luau's per-layout breakdown:
-- victory conditions, average time-to-first-base, and any archetype that
-- never found a base at all under that layout (a real blind spot, named so
-- it gets fixed rather than just noted).
function Report.placementSuiteText(suiteReport)
	local lines = {}
	local function say(line)
		table.insert(lines, line)
	end

	for _, layoutName in ipairs(sortedKeys(suiteReport)) do
		local layout = suiteReport[layoutName]
		say(string.format("%s:", layoutName))
		say(string.format("  average time to first base found: %s", formatPercent(layout.averageFirstBaseFraction)))
		for _, condition in ipairs(sortedKeys(layout.conditions)) do
			say(string.format("  %-18s %s", condition, formatPercent(layout.conditions[condition])))
		end

		local anyBlindSpot = false
		for _, name in ipairs(sortedKeys(layout.blindSpots)) do
			local counts = layout.blindSpots[name]
			if counts.neverFound > 0 then
				anyBlindSpot = true
				say(string.format("  BLIND SPOT: %s never found a base in %d/%d matches", name, counts.neverFound, counts.total))
			end
		end
		if not anyBlindSpot then
			say("  no blind spots -- every archetype found a base at least once")
		end
		say("")
	end

	return table.concat(lines, "\n")
end

return Report
