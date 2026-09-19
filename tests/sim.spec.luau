-- First test coverage for sim/ (criterion e, "Sim weapon roles and loadout
-- matrix" plan entry): sim/harness.luau is pure Luau, so it requires
-- straight into `lune run test` the same way tests/metrics.spec.luau already
-- does for sim/metrics.luau -- no new runner needed. A short-match smoke
-- spec per registered archetype, at the shipped default config: this is the
-- assertion that would have caught defilade's unreachable-cannon bug
-- (Session 019, CANNON_RANGE 8) in one `lune run test` instead of it hiding
-- behind multi-minute aggregate runs for a whole session.

local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local archetypes = require("../sim/archetypes")
local Harness = require("../sim/harness")

local board = Board.new(config)

-- The horizontal gap between a weapon at `wx` and the nearest cell in the
-- opponent's own territory -- the minimal range a weapon needs to reach
-- anything at all. Ignores elevation's range bonus on purpose: a
-- conservative floor, since a weapon that reaches at elevation 0 can always
-- reach, but this smoke spec doesn't need to model live terrain.
local function gapToEnemyTerritory(owner, wx)
	if owner == "A" then
		return math.abs(board.channelEnd + 1 - wx)
	end
	return math.abs(board.channelStart - 1 - wx)
end

for _, entry in ipairs(archetypes) do
	t.test(string.format("%s: places its bases, fires at least one shot, and has a weapon in range of enemy territory", entry.name), function()
		local result = Harness.runMatch(config, 42, entry, entry)

		local placedBase = false
		local inRange = false
		for _, p in ipairs(result.placements) do
			if p.owner == "A" then
				if p.typeId == "base" then
					placedBase = true
				end
				local def = config.STRUCTURES[p.typeId]
				if def.fire_mode and gapToEnemyTerritory("A", p.x) <= def.range then
					inRange = true
				end
			end
		end

		t.expectTrue(placedBase, entry.name .. " never placed a base")
		t.expectTrue(#result.shots > 0, entry.name .. " never fired a shot")
		t.expectTrue(inRange, entry.name .. " has no weapon placement in range of enemy territory")
	end)
end
