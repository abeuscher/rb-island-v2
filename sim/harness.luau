-- Runs scripted matches through the shared rules core, time-stepped to mirror
-- Rules.tick's fixed heartbeat (§4, restated in time terms by Session 011).
-- Every archetype decision is made against a View (see view.luau), never raw
-- MatchState, so an archetype can only ever act on its own belief map and
-- public terrain.

local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")
local View = require("../src/shared/view")

local Harness = {}

local function checkFirstBase(firstBaseFoundAt, owner, belief, elapsed)
	if firstBaseFoundAt[owner] then
		return
	end
	for _, entry in pairs(belief) do
		if entry.typeId == "base" then
			firstBaseFoundAt[owner] = elapsed
			return
		end
	end
end

-- `resolutionShots` (Rules.tick's resolution.shotsA/shotsB) already carries the
-- firing weapon's own def and the resolved shot, so unlike the old per-round
-- event log this needs no separate cell->typeId lookup.
local function recordShots(shots, elapsed, owner, resolutionShots)
	for _, s in ipairs(resolutionShots) do
		table.insert(shots, { owner = owner, typeId = s.def.id, elapsed = elapsed, blocked = s.shot.blocked })
	end
end

-- Runs one match to completion (Rules.tick's own time_limit condition
-- guarantees a victory by config.MATCH_SECONDS at the latest) and returns a
-- plain-table log: final scores and a score sample every tick, every "place"
-- command either side issued, every shot fired with its weapon type and
-- whether it was blocked, and the elapsed time each side first found a real
-- enemy base.
function Harness.runMatch(config, seed, archetypeA, archetypeB)
	math.randomseed(seed)

	local state = State.new(config)
	local placements = {}
	local shots = {}
	local scoreOverTime = {}
	local firstBaseFoundAt = { A = nil, B = nil }
	local victory = nil

	-- Archetypes decide on a periodic cadence rather than once per round --
	-- config.BOT_DECIDE_INTERVAL_SECONDS, the same cadence server/Bot.luau
	-- re-runs its own decide() on during live play (Session 015). The first
	-- call happens at elapsed 0, alongside every archetype's own opening
	-- placement check (`view.elapsed == 0`, renamed from `view.round == 1`).
	local function decideAndApply(owner, archetype)
		for _, cmd in ipairs(archetype.decide(config, View.new(state, owner))) do
			if cmd.type == "place" then
				table.insert(placements, { owner = owner, typeId = cmd.typeId, elapsed = state.elapsed, x = cmd.x, y = cmd.y })
			end
			local newState, ok = Rules.applyCommand(config, state, owner, cmd)
			if ok then
				state = newState
			end
		end
	end

	decideAndApply("A", archetypeA)
	decideAndApply("B", archetypeB)
	-- Mirrors MatchService's setup -> live transition: the sim has no separate
	-- untimed setup phase, so this opening decide-and-apply call stands in for
	-- it -- without this, bases (and whatever else an archetype opens with)
	-- would sit underConstruction and read as zero live bases on the very
	-- first tick.
	state = State.completeAllConstruction(config, state)
	local nextDecideAt = config.BOT_DECIDE_INTERVAL_SECONDS

	while true do
		local newState, _, v, resolution = Rules.tick(config, state)
		state = newState

		recordShots(shots, state.elapsed, "A", resolution.shotsA)
		recordShots(shots, state.elapsed, "B", resolution.shotsB)

		checkFirstBase(firstBaseFoundAt, "A", state.players.A.belief, state.elapsed)
		checkFirstBase(firstBaseFoundAt, "B", state.players.B.belief, state.elapsed)

		table.insert(scoreOverTime, {
			A = Rules.finalScore(config, state.players.A),
			B = Rules.finalScore(config, state.players.B),
		})

		victory = v
		if victory then
			break
		end

		if state.elapsed >= nextDecideAt then
			decideAndApply("A", archetypeA)
			decideAndApply("B", archetypeB)
			nextDecideAt = state.elapsed + config.BOT_DECIDE_INTERVAL_SECONDS
		end
	end

	return {
		seed = seed,
		duration = state.elapsed,
		winner = victory.winner,
		condition = victory.condition,
		finalScoreA = Rules.finalScore(config, state.players.A),
		finalScoreB = Rules.finalScore(config, state.players.B),
		finalDestructionPointsA = state.players.A.destructionPoints,
		finalDestructionPointsB = state.players.B.destructionPoints,
		placements = placements,
		shots = shots,
		scoreOverTime = scoreOverTime,
		firstBaseFoundAt = firstBaseFoundAt,
	}
end

-- All ordered pairs (including self-play) x matchesPerPair, with the same set
-- of seeds reused across every pairing (§15) so pairings are compared against
-- identical random rolls rather than being confounded by seed luck.
function Harness.runRoundRobin(config, archetypes, matchesPerPair, baseSeed)
	local results = {}
	for _, entryA in ipairs(archetypes) do
		for _, entryB in ipairs(archetypes) do
			for i = 1, matchesPerPair do
				local result = Harness.runMatch(config, baseSeed + i, entryA, entryB)
				result.archetypeA = entryA.name
				result.archetypeB = entryB.name
				table.insert(results, result)
			end
		end
	end
	return results
end

return Harness
