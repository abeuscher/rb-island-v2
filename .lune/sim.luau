-- Entry point for `lune run sim`: the baseline round robin from §15/§16's
-- M1.5 acceptance bar -- all 5 archetypes x 5 archetypes (including
-- self-play) x config.SIM_MATCHES_PER_PAIR matches, at the shipped default
-- config. Writes a per-match JSONL log and an aggregate CSV under
-- sim/output/, and prints the full §15 metrics report.

local config = require("../src/shared/config")
local archetypes = require("../sim/archetypes")
local Harness = require("../sim/harness")
local Report = require("../sim/report")
local PlacementSuite = require("../sim/placementSuite")

local BASE_SEED = 1000
-- A fast, cheap pass (criterion d) -- a handful of matches per curated
-- layout, not the full round robin's match count.
local PLACEMENT_MATCHES_PER_PAIR = 5

local results = Harness.runRoundRobin(config, archetypes, config.SIM_MATCHES_PER_PAIR, BASE_SEED)

Report.ensureDir("sim/output")
Report.writeMatchLogJsonl("sim/output/matches.jsonl", results)
Report.writeAggregateCsv("sim/output/aggregate.csv", results)

print(Report.summaryText(config, results))
print("")
print("Per-match log: sim/output/matches.jsonl")
print("Aggregate CSV: sim/output/aggregate.csv")

print("")
print("Curated base-placement suite:")
local placementReport = PlacementSuite.run(config, archetypes, PLACEMENT_MATCHES_PER_PAIR, BASE_SEED + 500)
print(Report.placementSuiteText(placementReport))
