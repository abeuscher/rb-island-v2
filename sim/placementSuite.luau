-- Curated adversarial base-placement layouts (criterion d, "Sim weapon roles
-- and loadout matrix" plan entry): a small, fast, deterministic pass
-- alongside the harness's normal Kit.spreadPick-randomized spread. A
-- genuinely bad exploration blind spot can hide behind favorable random
-- rolls for a long time -- the way defilade's unreachable-cannon bug sat
-- undetected for a whole session (Session 019) -- so this runs a handful of
-- matches per layout and reports, per archetype, whether it ever found a
-- base placed somewhere deliberately awkward.
--
-- Every layout is read through Kit.chooseBaseSpots's config.curatedBaseLayout
-- hook, so no archetype file needs to know this suite exists.

local Kit = require("../src/shared/archetypeKit")
local Harness = require("./harness")
local Metrics = require("./metrics")

local Suite = {}

-- How deep into the owner's own territory a "back" placement sits, as a
-- fraction of the way from the frontmost legal cell to the backmost one.
-- Not the true 100% extreme: that pushes a base far enough that no weapon
-- in the current roster can reach it even at max elevation, which tests
-- CANNON_RANGE arithmetic instead of an archetype's exploration behavior --
-- exactly the trap defilade's own placement fell into (Session 020). 60%
-- keeps every layout meaningfully deeper/tighter than Kit.spreadPick's
-- random spread while staying inside a frontline cannon's own unraised
-- range, so a failure to find one is a real behavioral blind spot.
local DEPTH_FRACTION = 0.6

-- The column `DEPTH_FRACTION` of the way back through already-legal
-- candidates, sorted front-to-back the same way Kit.frontlineCells does --
-- derived from real legal placements (in-bounds/in-territory/on-land/
-- unoccupied), not recomputed from board geometry.
local function deepX(view, sortedCandidates)
	local index = math.max(1, math.floor(#sortedCandidates * DEPTH_FRACTION))
	return sortedCandidates[index].x
end

local function minY(candidates)
	local best = candidates[1].y
	for _, c in ipairs(candidates) do
		best = math.min(best, c.y)
	end
	return best
end

local function centerY(candidates)
	local lo, hi = candidates[1].y, candidates[1].y
	for _, c in ipairs(candidates) do
		lo = math.min(lo, c.y)
		hi = math.max(hi, c.y)
	end
	return math.floor((lo + hi) / 2)
end

-- Packs config.NUM_BASES bases as close as possible to the target depth
-- column and `getTargetY`'s row, in that priority order.
local function packedLayout(getTargetY)
	return function(config, view, reserved)
		local sorted = Kit.frontlineCells(config, view, "base", reserved)
		if #sorted == 0 then
			return {}
		end
		local backX = deepX(view, sorted)
		local targetY = getTargetY(sorted)
		local candidates = table.clone(sorted)
		table.sort(candidates, function(a, b)
			local da = math.abs(a.x - backX) * 1000 + math.abs(a.y - targetY)
			local db = math.abs(b.x - backX) * 1000 + math.abs(b.y - targetY)
			return da < db
		end)
		return Kit.pickNonOverlapping(config, "base", candidates, config.NUM_BASES)
	end
end

-- All three bases spread across the full width of a single deep column --
-- unlike the packed layouts, exploring one corner doesn't find them all; a
-- searcher has to cover the whole row.
local function backRow(config, view, reserved)
	local sorted = Kit.frontlineCells(config, view, "base", reserved)
	if #sorted == 0 then
		return {}
	end
	local backX = deepX(view, sorted)
	local onBackX = {}
	for _, c in ipairs(sorted) do
		if c.x == backX then
			table.insert(onBackX, c)
		end
	end
	if #onBackX < config.NUM_BASES then
		onBackX = sorted
	end
	return Kit.spreadPick(onBackX, config.NUM_BASES)
end

Suite.layouts = {
	-- All three clustered together in one corner of the island.
	cornerCluster = packedLayout(minY),
	-- All three spread along the single back row.
	backRow = backRow,
	-- All three clustered together, deep and centered rather than in a
	-- corner -- sitting behind wherever an archetype's own frontline build
	-- naturally goes, no separate decoy structure needed.
	deepCenter = packedLayout(centerY),
}

-- typeId (archetype name) -> { total, neverFound } across every side-
-- observation in `results`.
local function blindSpotCounts(results)
	local counts = {}
	for _, r in ipairs(results) do
		for _, owner in ipairs({ "A", "B" }) do
			local name = (owner == "A") and r.archetypeA or r.archetypeB
			counts[name] = counts[name] or { total = 0, neverFound = 0 }
			counts[name].total += 1
			if not r.firstBaseFoundAt[owner] then
				counts[name].neverFound += 1
			end
		end
	end
	return counts
end

-- Runs every curated layout as its own round robin (both sides placed under
-- the same layout, so every archetype is tested finding every other
-- archetype's bases under it) and returns { [layoutName] = { conditions,
-- averageFirstBaseFraction, blindSpots } }.
function Suite.run(config, archetypes, matchesPerPair, baseSeed)
	local report = {}
	for layoutName, layoutFn in pairs(Suite.layouts) do
		local layoutConfig = table.clone(config)
		layoutConfig.curatedBaseLayout = layoutFn
		local results = Harness.runRoundRobin(layoutConfig, archetypes, matchesPerPair, baseSeed)
		report[layoutName] = {
			conditions = Metrics.victoryConditionDistribution(results),
			averageFirstBaseFraction = Metrics.averageFirstBaseFraction(results),
			blindSpots = blindSpotCounts(results),
		}
	end
	return report
end

return Suite
