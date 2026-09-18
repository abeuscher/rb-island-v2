-- §14's FSM: evaluated once per PLAN phase, playing by identical rules,
-- costs, and unlock gates through its own fog. Built on
-- src/shared/archetypeKit.luau's View-based candidate-cell/target-selection
-- logic -- the same "read only your own belief map, never true enemy
-- structure state" contract the sim's five scripted archetypes already use
-- (Session 003), now driving a real seat in MatchService's round loop
-- (Session 009) instead of a harness-only strategy.
--
-- Setup's 3 bases are placed once by MatchService itself via
-- Bot.chooseBaseSpots, the same way a real player's setup phase precedes
-- round 1 -- decide() below only ever runs during PLAN phases from round 1
-- onward, so it never needs its own round-1 base-placement branch the sim
-- archetypes do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Economy = require(ReplicatedStorage.Shared.economy)
local Kit = require(ReplicatedStorage.Shared.archetypeKit)
local Difficulties = require(ReplicatedStorage.Shared.botDifficulty)

local Bot = {}
Bot.__index = Bot

-- Always restored before advancing to terrain shaping or new weapons (§14
-- "Rebuild: always interleaved -- restore generator count before
-- advancing"), same shape as the sim archetypes' own GENERATOR_TARGET gates,
-- just not itself a difficulty knob (§14 only names three: Supply
-- multiplier, re-probe patience, and whether elevation is used).
local GENERATOR_TARGET = 3

local function difficultyPreset(id)
	for _, preset in ipairs(Difficulties) do
		if preset.id == id then
			return preset
		end
	end
	return Difficulties[2] -- Skirmish: safe default for a missing/unrecognized id
end

function Bot.new(difficultyId)
	local self = setmetatable({}, Bot)
	self.preset = difficultyPreset(difficultyId)
	self.lastBelief = {}
	self.beliefSeenRound = {}
	return self
end

-- MatchService calls this once, at match setup, to place the bot's 3 bases
-- through the same setup-phase path a real player's placements go through --
-- see the module comment above for why this isn't inside decide().
function Bot.chooseBaseSpots(config, view)
	return Kit.spreadPick(Kit.candidateCells(config, view, "base"), config.NUM_BASES)
end

-- A cell's last-seen content, cheap enough to compare directly.
local function beliefCellChanged(a, b)
	if (a == nil) ~= (b == nil) then
		return true
	end
	if a == nil then
		return false
	end
	return a.typeId ~= b.typeId or a.underConstruction ~= b.underConstruction or a.rubble ~= b.rubble
end

-- Records which round each belief cell last actually changed, so a plot that
-- hasn't been reconfirmed in a while can be told apart from one just seen.
function Bot:_markSeenPlots(view)
	for cellKey, entry in pairs(view.self.belief) do
		if beliefCellChanged(entry, self.lastBelief[cellKey]) then
			self.beliefSeenRound[cellKey] = view.round
		end
	end
	self.lastBelief = view.self.belief
end

-- A view with every plotted base/generator older than this difficulty's
-- patience window stripped back to "unexplored" -- so Kit.chooseTargets sends
-- a probing shot there again instead of committing a kill/suppress volley to
-- intel that might be wrong by now (§14: "how many rounds it waits before
-- re-probing stale plots"). Building decisions still read the real view;
-- only targeting goes through this one.
function Bot:_freshView(view)
	local restProbeRounds = self.preset.restProbeRounds
	local freshBelief = table.clone(view.self.belief)
	for cellKey, entry in pairs(view.self.belief) do
		if entry.typeId and (view.round - (self.beliefSeenRound[cellKey] or 0)) >= restProbeRounds then
			freshBelief[cellKey] = nil
		end
	end

	local freshSelf = table.clone(view.self)
	freshSelf.belief = freshBelief
	local freshView = table.clone(view)
	freshView.self = freshSelf
	return freshView
end

-- The frontmost open cell for `typeId`: raised to the ceiling first if
-- terrain editing is unlocked (§14 "raise ground for its cannons"), then
-- armed once it's already at max elevation -- ported from
-- sim/archetypes/highground.luau's identical peak-then-arm loop.
local function raiseThenPlace(config, view, typeId, reserved, trySpend)
	local peak = Kit.frontlineCells(config, view, typeId, reserved)[1]
	if not peak then
		return nil
	end

	if view.round >= config.UNLOCK_ROUND.terrain_edit and Kit.wouldSucceed(Board.raise, view.board, peak.x, peak.y) then
		if trySpend({ supply = config.RAISE_COST }) then
			return { type = "raise", x = peak.x, y = peak.y }
		end
		return nil
	end

	if trySpend({ supply = config.STRUCTURES[typeId].supply_cost }) then
		Kit.reserve(reserved, config, typeId, peak.x, peak.y)
		return { type = "place", typeId = typeId, x = peak.x, y = peak.y }
	end
	return nil
end

-- The cell just beyond a base's channel-facing edge -- ported from
-- sim/archetypes/defilade.luau's shieldCells, the one place a ridge does the
-- most good against direct fire regardless of the shooter's own elevation.
local function shieldCells(config, view, base)
	local footprint = config.STRUCTURES.base.footprint
	local shieldX = (view.owner == "A") and (base.x + footprint) or (base.x - 1)
	local cells = {}
	for dy = 0, footprint - 1 do
		table.insert(cells, { x = shieldX, y = base.y + dy })
	end
	return cells
end

-- §14 "lower ground around its bases" -- the first base with an unshielded
-- edge gets it lowered; nil once every base is already shielded (or none can
-- be), which naturally falls through to building more weapons instead.
local function lowerAroundBases(config, view, trySpend)
	for _, base in ipairs(Kit.liveStructures(view, "base")) do
		for _, cell in ipairs(shieldCells(config, view, base)) do
			if
				Board.inBounds(view.board, cell.x, cell.y)
				and Board.ownerOf(view.board, cell.x, cell.y) == view.owner
				and Kit.wouldSucceed(Board.lower, view.board, cell.x, cell.y)
			then
				if trySpend({ supply = config.LOWER_COST }) then
					return { type = "lower", x = cell.x, y = cell.y }
				end
				return nil
			end
		end
	end
	return nil
end

-- config.STRUCTURES.mortar.unlock_round-gated, mortar preferred over cannon
-- (§14 Kill: "use mortars if a ridge blocks direct lines" -- Kit.chooseTargets
-- already lets a mortar reach a plotted base a cannon's blocked line can't,
-- so simply having both weapon types on the board is what makes that happen)
-- -- ported from sim/archetypes/boomer.luau's spend-to-empty loop, since a
-- real opponent should keep massing weapons all game rather than stop at the
-- small fixed counts the sim's balance-isolating archetypes use.
local function buildWeapons(config, view, reserved, resources, commands)
	for _, typeId in ipairs({ "mortar", "cannon" }) do
		local def = config.STRUCTURES[typeId]
		if view.round >= def.unlock_round then
			local spots = Kit.candidateCells(config, view, typeId, reserved)
			while #spots > 0 and Economy.canAfford(resources, { supply = def.supply_cost }) do
				local spot = spots[math.random(#spots)]
				table.insert(commands, { type = "place", typeId = typeId, x = spot.x, y = spot.y })
				resources = Economy.spend(resources, { supply = def.supply_cost })
				Kit.reserve(reserved, config, typeId, spot.x, spot.y)
				spots = Kit.candidateCells(config, view, typeId, reserved)
			end
		end
	end
	return resources
end

function Bot:decide(config, view)
	self:_markSeenPlots(view)

	local commands = {}
	local resources = view.self.resources
	local reserved = {}

	local function trySpend(cost)
		if Economy.canAfford(resources, cost) then
			resources = Economy.spend(resources, cost)
			return true
		end
		return false
	end

	if Kit.countType(view, "generator") < GENERATOR_TARGET then
		if trySpend({ supply = config.STRUCTURES.generator.supply_cost }) then
			local spots = Kit.candidateCells(config, view, "generator", reserved)
			if #spots > 0 then
				local spot = spots[math.random(#spots)]
				table.insert(commands, { type = "place", typeId = "generator", x = spot.x, y = spot.y })
				Kit.reserve(reserved, config, "generator", spot.x, spot.y)
			end
		end
	else
		local shaped = nil
		if self.preset.usesElevation and view.round >= config.UNLOCK_ROUND.terrain_edit then
			shaped = lowerAroundBases(config, view, trySpend) or raiseThenPlace(config, view, "cannon", reserved, trySpend)
		end

		if shaped then
			table.insert(commands, shaped)
		else
			resources = buildWeapons(config, view, reserved, resources, commands)
		end
	end

	local freshView = self:_freshView(view)
	for _, command in ipairs(Kit.chooseTargets(config, freshView, Kit.pendingWeaponsFrom(config, commands))) do
		table.insert(commands, command)
	end

	return commands
end

return Bot
