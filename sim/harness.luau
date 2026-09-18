-- Runs scripted matches through the shared rules core (§15). Every archetype
-- decision is made against a View (see view.luau), never raw MatchState, so
-- an archetype can only ever act on its own belief map and public terrain.

local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")
local View = require("../src/shared/view")

local Harness = {}

local function key(x, y)
	return x .. "," .. y
end

-- Maps every cell a weapon could be firing from this round to its typeId:
-- structures that already existed, plus anything placed this same round
-- (which completes and can fire in this same resolve -- see Session 002's
-- notes on §4's literal step order).
local function typeAtLookup(structures, commands)
	local map = {}
	for _, structure in ipairs(structures) do
		map[key(structure.x, structure.y)] = structure.typeId
	end
	for _, cmd in ipairs(commands) do
		if cmd.type == "place" then
			map[key(cmd.x, cmd.y)] = cmd.typeId
		end
	end
	return map
end

local function recordShots(shots, round, events, typeAtA, typeAtB)
	for _, event in ipairs(events) do
		if event.type == "shot" then
			local typeAt = (event.owner == "A") and typeAtA or typeAtB
			table.insert(shots, {
				owner = event.owner,
				typeId = typeAt[key(event.weapon.x, event.weapon.y)],
				round = round,
				blocked = event.blocked,
			})
		end
	end
end

local function checkFirstBase(firstBaseFoundRound, owner, belief, round)
	if firstBaseFoundRound[owner] then
		return
	end
	for _, entry in pairs(belief) do
		if entry.typeId == "base" then
			firstBaseFoundRound[owner] = round
			return
		end
	end
end

-- Runs one match to completion (§4/§5 guarantee a victory by config.MAX_ROUNDS
-- at the latest) and returns a plain-table log: final scores and score per
-- round, every "place" command either side issued, every shot fired with its
-- weapon type and whether it was blocked, and the round each side first found
-- a real enemy base.
function Harness.runMatch(config, seed, archetypeA, archetypeB)
	math.randomseed(seed)

	local state = State.new(config)
	local placements = {}
	local shots = {}
	local scoreByRound = {}
	local firstBaseFoundRound = { A = nil, B = nil }
	local victory = nil

	for round = 1, config.MAX_ROUNDS do
		local commandsA = archetypeA.decide(config, View.new(state, "A"))
		local commandsB = archetypeB.decide(config, View.new(state, "B"))

		local typeAtA = typeAtLookup(state.players.A.structures, commandsA)
		local typeAtB = typeAtLookup(state.players.B.structures, commandsB)

		for _, cmd in ipairs(commandsA) do
			if cmd.type == "place" then
				table.insert(placements, { owner = "A", typeId = cmd.typeId, round = round, x = cmd.x, y = cmd.y })
			end
		end
		for _, cmd in ipairs(commandsB) do
			if cmd.type == "place" then
				table.insert(placements, { owner = "B", typeId = cmd.typeId, round = round, x = cmd.x, y = cmd.y })
			end
		end

		local newState, events, v = Rules.resolveRound(config, state, commandsA, commandsB)
		recordShots(shots, round, events, typeAtA, typeAtB)

		checkFirstBase(firstBaseFoundRound, "A", newState.players.A.belief, round)
		checkFirstBase(firstBaseFoundRound, "B", newState.players.B.belief, round)

		table.insert(scoreByRound, {
			A = Rules.finalScore(config, newState.players.A),
			B = Rules.finalScore(config, newState.players.B),
		})

		state = newState
		victory = v
		if victory then
			break
		end
	end

	return {
		seed = seed,
		rounds = #scoreByRound,
		winner = victory.winner,
		condition = victory.condition,
		finalScoreA = Rules.finalScore(config, state.players.A),
		finalScoreB = Rules.finalScore(config, state.players.B),
		finalDestructionPointsA = state.players.A.destructionPoints,
		finalDestructionPointsB = state.players.B.destructionPoints,
		placements = placements,
		shots = shots,
		scoreByRound = scoreByRound,
		firstBaseFoundRound = firstBaseFoundRound,
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
