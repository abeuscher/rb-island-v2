-- Pure aggregation over Harness match results into the balance metrics §15
-- asks for.

local Metrics = {}

function Metrics.matchLengthDistribution(results)
	local histogram = {}
	for _, r in ipairs(results) do
		histogram[r.rounds] = (histogram[r.rounds] or 0) + 1
	end
	return histogram
end

function Metrics.victoryConditionDistribution(results)
	local counts = {}
	for _, r in ipairs(results) do
		counts[r.condition] = (counts[r.condition] or 0) + 1
	end
	local fractions = {}
	for condition, count in pairs(counts) do
		fractions[condition] = count / #results
	end
	return fractions, counts
end

-- Win rate of the row archetype against the column archetype, combining
-- matches played in both seats. Draws count toward the total but neither win.
function Metrics.winRateMatrix(results)
	local wins, totals = {}, {}
	for _, r in ipairs(results) do
		local x, y = r.archetypeA, r.archetypeB
		totals[x] = totals[x] or {}
		totals[y] = totals[y] or {}
		wins[x] = wins[x] or {}
		wins[y] = wins[y] or {}
		totals[x][y] = (totals[x][y] or 0) + 1
		totals[y][x] = (totals[y][x] or 0) + 1
		if r.winner == "A" then
			wins[x][y] = (wins[x][y] or 0) + 1
		elseif r.winner == "B" then
			wins[y][x] = (wins[y][x] or 0) + 1
		end
	end

	local matrix = {}
	for x, row in pairs(totals) do
		matrix[x] = {}
		for y, total in pairs(row) do
			matrix[x][y] = (wins[x][y] or 0) / total
		end
	end
	return matrix
end

-- Each archetype's win rate against the rest of the field, excluding
-- self-play. "No archetype should exceed 60% against the field" (§15).
function Metrics.fieldWinRates(results)
	local wins, totals = {}, {}
	for _, r in ipairs(results) do
		if r.archetypeA ~= r.archetypeB then
			totals[r.archetypeA] = (totals[r.archetypeA] or 0) + 1
			totals[r.archetypeB] = (totals[r.archetypeB] or 0) + 1
			if r.winner == "A" then
				wins[r.archetypeA] = (wins[r.archetypeA] or 0) + 1
			elseif r.winner == "B" then
				wins[r.archetypeB] = (wins[r.archetypeB] or 0) + 1
			end
		end
	end
	local rates = {}
	for name, total in pairs(totals) do
		rates[name] = (wins[name] or 0) / total
	end
	return rates
end

-- Histogram of the round each side first found a real enemy base. Returns the
-- histogram plus how many side/match observations never found one.
function Metrics.roundsToFirstBaseDistribution(results)
	local histogram = {}
	local neverFound = 0
	for _, r in ipairs(results) do
		for _, owner in ipairs({ "A", "B" }) do
			local round = r.firstBaseFoundRound[owner]
			if round then
				histogram[round] = (histogram[round] or 0) + 1
			else
				neverFound += 1
			end
		end
	end
	return histogram, neverFound
end

-- Average of (round a base was first found / match length), across every
-- side/match that found one -- the number §15 wants in the 25-45% band.
function Metrics.averageFirstBaseFraction(results)
	local totalFraction, count = 0, 0
	for _, r in ipairs(results) do
		for _, owner in ipairs({ "A", "B" }) do
			local round = r.firstBaseFoundRound[owner]
			if round then
				totalFraction += round / r.rounds
				count += 1
			end
		end
	end
	if count == 0 then
		return nil
	end
	return totalFraction / count
end

-- Fraction of matches where the side behind at the midpoint round went on to
-- win -- reads on snowball risk. Excludes draws and matches too short to have
-- a meaningful midpoint.
function Metrics.comebackRate(results)
	local comebacks, decisive = 0, 0
	for _, r in ipairs(results) do
		if r.winner and r.rounds >= 2 then
			local mid = r.scoreByRound[math.floor(r.rounds / 2)]
			if mid.A ~= mid.B then
				local behind = (mid.A < mid.B) and "A" or "B"
				decisive += 1
				if behind == r.winner then
					comebacks += 1
				end
			end
		end
	end
	if decisive == 0 then
		return nil
	end
	return comebacks / decisive
end

-- Fraction of direct-fire (cannon) shots stopped by terrain -- the health
-- check on the whole elevation system (§15).
function Metrics.cannonBlockRate(results)
	local blocked, total = 0, 0
	for _, r in ipairs(results) do
		for _, shot in ipairs(r.shots) do
			if shot.typeId == "cannon" then
				total += 1
				if shot.blocked then
					blocked += 1
				end
			end
		end
	end
	if total == 0 then
		return nil
	end
	return blocked / total
end

-- Share of all "place" commands issued, by structure type -- zero share
-- across a large sweep means miscosted, not merely unpopular.
function Metrics.purchaseShare(results)
	local counts, total = {}, 0
	for _, r in ipairs(results) do
		for _, p in ipairs(r.placements) do
			counts[p.typeId] = (counts[p.typeId] or 0) + 1
			total += 1
		end
	end
	local shares = {}
	for typeId, count in pairs(counts) do
		shares[typeId] = count / total
	end
	return shares, counts
end

-- Destruction points earned per Supply spent on placements, aggregated across
-- both sides of every match. A rough overall proxy, not broken down per
-- structure type -- the event stream doesn't carry enough detail to attribute
-- a kill to the weapon that landed it without extending rules.luau's events,
-- which is out of scope for this session.
function Metrics.supplyEfficiency(config, results)
	local totalPoints, totalSupply = 0, 0
	for _, r in ipairs(results) do
		for _, p in ipairs(r.placements) do
			totalSupply += config.STRUCTURES[p.typeId].supply_cost
		end
		totalPoints += r.finalDestructionPointsA + r.finalDestructionPointsB
	end
	if totalSupply == 0 then
		return nil
	end
	return totalPoints / totalSupply
end

return Metrics
