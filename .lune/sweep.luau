-- Entry point for `lune run sweep`: the first parameter sweep (§15), three
-- staged passes each layering its own knobs on top of the previous pass's
-- best pick. Prints every point tried and writes a shortlist of surviving
-- configs to sim/output/shortlist.md for human playtesting -- the sweep
-- narrows, it does not decide (§15).

local fs = require("@lune/fs")
local config = require("../src/shared/config")
local Sweep = require("../sim/sweep")
local Report = require("../sim/report")

-- Smaller than the baseline round robin's 200: the sweep trades per-point
-- fidelity for breadth across many configs, then hands its shortlist to a
-- full-fidelity human playtest rather than deciding anything itself.
local MATCHES_PER_PAIR = 40
local BASE_SEED = 2000

local function formatOverrides(overrides)
	local parts = {}
	for _, name in ipairs({ "RAISE_COST", "CANNON_RANGE", "MORTAR_RANGE", "ENERGY_PER_GENERATOR", "SUPPLY_PER_ROUND", "RECLAIM_COST", "MAX_ROUNDS", "POINTS_PRESET" }) do
		if overrides[name] ~= nil then
			table.insert(parts, name .. "=" .. tostring(overrides[name]))
		end
	end
	return table.concat(parts, " ")
end

local function formatMeasurement(m)
	return string.format(
		"maxFieldWinRate=%.0f%% cannonBlockRate=%.0f%% roundLimitShare=%.0f%% firstBaseFraction=%.0f%%",
		m.maxFieldWinRate * 100,
		m.cannonBlockRate * 100,
		m.roundLimitShare * 100,
		m.averageFirstBaseFraction * 100
	)
end

print("Pass 1: RAISE_COST x CANNON_RANGE x MORTAR_RANGE x ENERGY_PER_GENERATOR")
local pass1Points, pass1Best = Sweep.runPass(config, {}, {
	RAISE_COST = { 2, 6 },
	CANNON_RANGE = { 8, 12 },
	MORTAR_RANGE = { 12, 20 },
	ENERGY_PER_GENERATOR = { 1, 3 },
}, MATCHES_PER_PAIR, BASE_SEED)
print(string.format("  best: %s -- %s", formatOverrides(pass1Best.overrides), formatMeasurement(pass1Best.measurement)))

print("Pass 2: SUPPLY_PER_ROUND x RECLAIM_COST (on top of pass 1's best)")
local pass2Points, pass2Best = Sweep.runPass(config, pass1Best.overrides, {
	SUPPLY_PER_ROUND = { 8, 14 },
	RECLAIM_COST = { 8, 16 },
}, MATCHES_PER_PAIR, BASE_SEED)
print(string.format("  best: %s -- %s", formatOverrides(pass2Best.overrides), formatMeasurement(pass2Best.measurement)))

print("Pass 3: MAX_ROUNDS x POINTS table (on top of pass 2's best)")
local pass3Points, pass3Best = Sweep.runPass(config, pass2Best.overrides, {
	MAX_ROUNDS = { 5, 10 },
	POINTS_PRESET = { "default", "generatorHeavy" },
}, MATCHES_PER_PAIR, BASE_SEED)
print(string.format("  best: %s -- %s", formatOverrides(pass3Best.overrides), formatMeasurement(pass3Best.measurement)))

local allPoints = {}
for _, p in ipairs(pass1Points) do
	table.insert(allPoints, p)
end
for _, p in ipairs(pass2Points) do
	table.insert(allPoints, p)
end
for _, p in ipairs(pass3Points) do
	table.insert(allPoints, p)
end

local survivors = {}
for _, p in ipairs(allPoints) do
	if Sweep.survives(p.measurement) then
		table.insert(survivors, p)
	end
end
table.sort(survivors, function(a, b)
	return Sweep.badness(a.measurement) < Sweep.badness(b.measurement)
end)

local shortlist = {}
for i = 1, math.min(5, #survivors) do
	table.insert(shortlist, survivors[i])
end

print("")
print(string.format("%d of %d points survived the filter (max field win rate <= 60%%, cannon block rate 15-85%%, round limit <= 90%% of matches).", #survivors, #allPoints))
print(string.format("Shortlist: %d configs", #shortlist))
for _, p in ipairs(shortlist) do
	print(string.format("  %s -- %s", formatOverrides(p.overrides), formatMeasurement(p.measurement)))
end

Report.ensureDir("sim/output")

local lines = {
	"# Sim sweep shortlist",
	"",
	string.format("%d of %d swept points survived; top %d shown below, ranked by fit.", #survivors, #allPoints, #shortlist),
	"Each config's overrides apply on top of the shipped default `src/shared/config.luau`.",
	"This is a narrowing pass, not a decision -- take these to human playtesting (§15).",
	"",
}
if #shortlist == 0 then
	table.insert(lines, "## No swept point survived")
	table.insert(lines, "")
	table.insert(lines, "Every point tried, up to MAX_ROUNDS=20, ends 84-100% of the time on the round limit,")
	table.insert(lines, "decided by points rather than combat, with one archetype (`boomer`) taking 85-91% of")
	table.insert(lines, "the field regardless of which knob moved. A follow-up probe (not part of the grid above)")
	table.insert(lines, "pushed MAX_ROUNDS to 40: boomer's field win rate plateaus at 91% rather than continuing")
	table.insert(lines, "to climb, so this isn't a match-length problem that a longer clock would fix on its own.")
	table.insert(lines, "")
	table.insert(lines, "Two structural causes, neither of which a config knob in this sweep can reach:")
	table.insert(lines, "")
	table.insert(lines, "1. **Standing points reward structures, not terrain.** Raising, lowering, and reclaiming")
	table.insert(lines, "   score nothing (§5.4). `boomer` spends every Supply point on generators and weapons;")
	table.insert(lines, "   `highground`/`defilade`/`sprawl` spend a share of theirs on terrain instead, and lose the")
	table.insert(lines, "   round-limit points race every time regardless of how the terrain investment plays out")
	table.insert(lines, "   tactically. Since round_limit decides 84-100% of matches at every swept MAX_ROUNDS, this")
	table.insert(lines, "   bias dominates the outcome almost by itself.")
	table.insert(lines, "2. **Cannon block rate stays near 0% because terrain is fully public (§11).** Every")
	table.insert(lines, "   archetype here checks `Flight.resolveShot` before choosing a target and only ever fires")
	table.insert(lines, "   at cells it can already tell are clear -- a rational agent with full terrain information")
	table.insert(lines, "   simply never fires into a ridge it can see. The handful of blocked shots that do happen")
	table.insert(lines, "   come from a same-round terrain edit changing the board after targets were already chosen.")
	table.insert(lines, "   RAISE_COST/CANNON_RANGE/MORTAR_RANGE tuning can't fix this -- it's a targeting-behavior")
	table.insert(lines, "   effect, not a numeric one.")
	table.insert(lines, "")
	table.insert(lines, "Neither is a config-tuning problem, so no amount of further grid search will surface a")
	table.insert(lines, "survivor. Worth a look before the next balance pass: whether standing points should credit")
	table.insert(lines, "terrain investment somehow, and whether elevation's role should shift away from \"blocks a")
	table.insert(lines, "shot outright\" toward something a fully-informed agent can't simply route around.")
	table.insert(lines, "")
	table.insert(lines, "See the full point list below for the least-bad candidates on the raw numbers.")
	table.insert(lines, "")
end
for i, p in ipairs(shortlist) do
	table.insert(lines, string.format("%d. `%s`", i, formatOverrides(p.overrides)))
	table.insert(lines, string.format("   %s", formatMeasurement(p.measurement)))
end
table.insert(lines, "")
table.insert(lines, "## All points tried")
table.insert(lines, "")
for _, p in ipairs(allPoints) do
	table.insert(lines, string.format("- `%s` -- %s%s", formatOverrides(p.overrides), formatMeasurement(p.measurement), Sweep.survives(p.measurement) and " (survives)" or ""))
end

fs.writeFile("sim/output/shortlist.md", table.concat(lines, "\n") .. "\n")
print("")
print("Shortlist written to sim/output/shortlist.md")
