-- One real two-player match's authoritative state and round loop (§12). Owns
-- the single MatchState both clients are scored against; every command a
-- client sends is a request, validated here through the same pure
-- src/shared/ functions the old single-player PlanController called
-- directly -- the client itself never calls them anymore.
--
-- PLAN-phase commands are applied immediately to `self.state` (so a push back
-- to that same player reflects it right away) and, in parallel, queued into
-- `self.pendingCommands[owner]` for the round's real `Rules.resolveRound`
-- replay at resolve -- the same two-track model Session 007's local
-- PlanController used, just relocated here now that there are two real
-- owners instead of one player and a scripted dummy.
--
-- A round ends when both players ready up or the clock runs out, whichever
-- comes first (§4 gives a round clock but doesn't say early-ready is allowed
-- for two real players -- Session 008's own call, since a single local player
-- never had anyone else to wait for).
--
-- A bot match (Session 009) gives owner "B" no real Player Instance at all --
-- self.players.B and self.owners simply never get an entry for it. Setup and
-- PLAN-phase commands for a bot seat run through the exact same
-- _handleSetupCommand/_handlePlanCommand/_handleTarget paths a real player's
-- commands do (see _runBotTurn), so a bot is held to identical validation,
-- costs, and unlock gates -- every push-to-client call just no-ops for it
-- (see _pushState).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local State = require(ReplicatedStorage.Shared.state)
local Rules = require(ReplicatedStorage.Shared.rules)
local Structures = require(ReplicatedStorage.Shared.structures)
local Flight = require(ReplicatedStorage.Shared.flight)
local View = require(ReplicatedStorage.Shared.view)
local ResolveView = require(ReplicatedStorage.Shared.resolveView)
local Replication = require(script.Parent.Replication)
local Bot = require(script.Parent.Bot)

local MatchService = {}
MatchService.__index = MatchService

local OWNERS = { "A", "B" }

local function otherOwner(owner)
	return owner == "A" and "B" or "A"
end

local function cellKey(x, y)
	return x .. "," .. y
end

local function footprintCellKeys(config, typeId, x, y)
	local size = config.STRUCTURES[typeId] and config.STRUCTURES[typeId].footprint or 1
	local keys = {}
	for dx = 0, size - 1 do
		for dy = 0, size - 1 do
			table.insert(keys, cellKey(x + dx, y + dy))
		end
	end
	return keys
end

function MatchService.new(config, remotes, playerA, playerB, onEnded, botDifficulty)
	local self = setmetatable({}, MatchService)
	self.config = config
	self.remotes = remotes
	self.players = { A = playerA, B = playerB }
	self.owners = {}
	self.owners[playerA] = "A"
	if playerB then
		self.owners[playerB] = "B"
	end
	self.onEnded = onEnded
	self.bot = botDifficulty and Bot.new(botDifficulty) or nil

	self.state = State.new(config)
	self.roundStartState = nil
	self.pendingCommands = { A = {}, B = {} }
	self.targets = { A = {}, B = {} }
	self.readyForRounds = { A = false, B = false }
	self.readyForResolve = { A = false, B = false }
	self.secondsRemaining = config.PLAN_SECONDS
	self.phase = "setup"
	self.dead = false
	self._roundToken = 0
	self._misfireMessages = nil
	self._lastVictory = nil

	Replication.pushMatchFound(remotes, playerA, "A")
	if playerB then
		Replication.pushMatchFound(remotes, playerB, "B")
	end

	if self.bot then
		for _, spot in ipairs(Bot.chooseBaseSpots(config, View.new(self.state, "B"))) do
			self.state = State.placeStructure(config, self.state, "B", "base", spot.x, spot.y)
		end
		self:_handleReady("B")
	end

	return self
end

function MatchService:_pushState(owner, message, ok)
	local player = self.players[owner]
	if not player then
		return
	end
	Replication.pushState(self.remotes, player, self.config, self.state, owner, self.phase, self.secondsRemaining, message, ok)
end

function MatchService:_pushCurrent(owner)
	if self.phase == "result" then
		Replication.pushResult(self.remotes, self.players[owner], self.config, self.state, owner, self._lastVictory)
		return
	end
	self:_pushState(owner, nil, nil)
end

function MatchService:_countBases(owner)
	local count = 0
	for _, structure in ipairs(self.state.players[owner].structures) do
		if structure.typeId == "base" then
			count += 1
		end
	end
	return count
end

-- Mirrors rules.luau's applyPlayerCommands, which drops a same-round
-- placement on any cell this owner's own commands have already terrain-
-- edited this round (§8). The immediate-apply preview below has to enforce
-- this too, or it would show a placement that resolveRound will silently
-- drop later.
function MatchService:_terrainEditedThisRound(owner)
	local edited = {}
	for _, cmd in ipairs(self.pendingCommands[owner]) do
		if cmd.type == "raise" or cmd.type == "lower" or cmd.type == "reclaim" then
			edited[cellKey(cmd.x, cmd.y)] = true
		end
	end
	return edited
end

function MatchService:handleCommand(player, command)
	if self.dead or type(command) ~= "table" or type(command.type) ~= "string" then
		return
	end
	local owner = self.owners[player]
	if not owner then
		return
	end

	if command.type == "requestState" then
		self:_pushCurrent(owner)
		return
	end

	if command.type == "ready" then
		self:_handleReady(owner)
		return
	end

	if self.phase == "setup" then
		self:_handleSetupCommand(owner, command)
		return
	end

	if self.phase ~= "plan" then
		return
	end

	if command.type == "target" then
		self:_handleTarget(owner, command)
		return
	end

	self:_handlePlanCommand(owner, command)
end

function MatchService:_handleReady(owner)
	if self.phase == "setup" then
		if self:_countBases(owner) ~= self.config.NUM_BASES then
			self:_pushState(owner, string.format("place exactly %d bases before starting", self.config.NUM_BASES), false)
			return
		end
		self.readyForRounds[owner] = true
		self:_pushState(owner, "waiting for opponent", true)
		if self.readyForRounds.A and self.readyForRounds.B then
			self.state = State.completeConstruction(self.config, self.state)
			self:_startPlanPhase()
		end
	elseif self.phase == "plan" then
		self.readyForResolve[owner] = true
		if self.readyForResolve.A and self.readyForResolve.B then
			self:_advanceRound()
		else
			self:_pushState(owner, "waiting for opponent", true)
		end
	end
end

-- Setup only ever offers base placement (§8: setup's 3 bases, not bought
-- during PLAN) and bulldoze -- the client's BuildPalette already restricts
-- its tool set to match, but that's UI only; a same-round terrain edit or any
-- other structure type has to be rejected here too, or a client could just
-- send one directly.
function MatchService:_handleSetupCommand(owner, command)
	if command.type == "place" then
		if command.typeId ~= "base" then
			self:_pushState(owner, "only bases can be placed during setup", false)
			return
		end
		local newState, ok, err = State.placeStructure(self.config, self.state, owner, "base", command.x, command.y)
		if ok then
			self.state = newState
			self:_pushState(owner, "placed base", true)
		else
			self:_pushState(owner, err, false)
		end
		return
	end

	if command.type == "bulldoze" then
		local newState, ok, err = State.bulldozeStructure(self.config, self.state, owner, command.x, command.y)
		if ok then
			self.state = newState
			self:_pushState(owner, "bulldozed", true)
		else
			self:_pushState(owner, err, false)
		end
	end
end

function MatchService:_handleTarget(owner, command)
	local weapon = Structures.at(self.config.STRUCTURES, self.state.players[owner].structures, command.x, command.y)
	if not weapon then
		self:_pushState(owner, "no weapon there", false)
		return
	end

	local def = self.config.STRUCTURES[weapon.typeId]
	if not def.fire_mode or weapon.underConstruction then
		self:_pushState(owner, "not a usable weapon", false)
		return
	end

	if Board.ownerOf(self.state.board, command.targetX, command.targetY) ~= otherOwner(owner) then
		self:_pushState(owner, "target must be on the enemy island", false)
		return
	end

	local elevation = Board.elevationAt(self.state.board, weapon.x, weapon.y)
	local distance = Flight.chebyshevDistance(weapon.x, weapon.y, command.targetX, command.targetY)
	if distance > Flight.range(def, elevation) then
		self:_pushState(owner, "target out of range", false)
		return
	end

	self.targets[owner][cellKey(weapon.x, weapon.y)] = { x = command.targetX, y = command.targetY }
	table.insert(self.pendingCommands[owner], {
		type = "target",
		x = weapon.x,
		y = weapon.y,
		targetX = command.targetX,
		targetY = command.targetY,
	})
	self:_pushState(owner, string.format("target set to (%d, %d)", command.targetX, command.targetY), true)
end

function MatchService:_handlePlanCommand(owner, command)
	local newState, ok, err, label

	if command.type == "bulldoze" then
		newState, ok, err = State.bulldozeStructure(self.config, self.state, owner, command.x, command.y)
		label = "bulldozed"
	elseif command.type == "raise" then
		newState, ok, err = State.raiseTerrain(self.config, self.state, owner, command.x, command.y)
		label = "raised terrain"
	elseif command.type == "lower" then
		newState, ok, err = State.lowerTerrain(self.config, self.state, owner, command.x, command.y)
		label = "lowered terrain"
	elseif command.type == "reclaim" then
		newState, ok, err = State.reclaimLand(self.config, self.state, owner, command.x, command.y)
		label = "reclaimed land"
	elseif command.type == "place" then
		local editedThisRound = self:_terrainEditedThisRound(owner)
		for _, footKey in ipairs(footprintCellKeys(self.config, command.typeId, command.x, command.y)) do
			if editedThisRound[footKey] then
				self:_pushState(owner, "cell was terrain-edited this round -- place next round", false)
				return
			end
		end
		newState, ok, err = State.placeStructure(self.config, self.state, owner, command.typeId, command.x, command.y)
		label = "placed " .. tostring(command.typeId)
	else
		return
	end

	if ok then
		self.state = newState
		table.insert(self.pendingCommands[owner], command)
		self:_pushState(owner, label, true)
	else
		self:_pushState(owner, err, false)
	end
end

function MatchService:_startPlanPhase()
	self._roundToken += 1
	local token = self._roundToken
	self.phase = "plan"

	-- Applied before roundStartState is captured below -- _advanceRound's
	-- Rules.resolveRound replays pendingCommands.B against roundStartState,
	-- not self.state, so the bot's Supply multiplier has to already be
	-- baked into that snapshot or a purchase the bot could only afford with
	-- the bonus would preview successfully here and then silently get
	-- dropped as unaffordable during the real resolve.
	if self.bot then
		self.state = self:_applyBotSupplyMultiplier(self.state)
	end

	self.roundStartState = self.state
	self.pendingCommands = { A = {}, B = {} }
	self.readyForResolve = { A = false, B = false }
	self.secondsRemaining = self.config.PLAN_SECONDS

	for _, owner in ipairs(OWNERS) do
		local misfire = self._misfireMessages and self._misfireMessages[owner] or {}
		local message, ok
		if #misfire > 0 then
			message = table.concat(misfire, "; ")
			ok = false
		else
			message = string.format("round %d begins", self.state.round)
			ok = true
		end
		self:_pushState(owner, message, ok)
	end
	self._misfireMessages = nil

	self:_runBotTurn()

	task.delay(self.config.PLAN_SECONDS, function()
		if self._roundToken == token then
			self:_advanceRound()
		end
	end)
end

-- §14's difficulty knob, applied directly to the bot's own resources rather
-- than in the shared economy/rules core every real player and every sim
-- archetype also goes through unmodified -- it's a bot-only handicap, not a
-- rules change.
function MatchService:_applyBotSupplyMultiplier(state)
	local extra = math.floor(self.config.SUPPLY_PER_ROUND * (self.bot.preset.supplyMultiplier - 1) + 0.5)
	if extra == 0 then
		return state
	end
	local botResources = state.players.B.resources
	return State.withPlayer(state, "B", {
		resources = { supply = math.max(0, botResources.supply + extra), energy = botResources.energy },
	})
end

-- Evaluated once per PLAN phase (§14), right as it opens -- a bot never needs
-- the clock, so its move is locked in immediately rather than waiting out
-- config.PLAN_SECONDS alongside the real player.
function MatchService:_runBotTurn()
	if not self.bot then
		return
	end

	local commands = self.bot:decide(self.config, View.new(self.state, "B"))
	for _, command in ipairs(commands) do
		if command.type == "target" then
			self:_handleTarget("B", command)
		else
			self:_handlePlanCommand("B", command)
		end
	end
	self:_handleReady("B")
end

function MatchService:_advanceRound()
	if self.phase ~= "plan" then
		return
	end
	self._roundToken += 1
	self.phase = "resolve"

	local newState, _, victory, resolution = Rules.resolveRound(self.config, self.roundStartState, self.pendingCommands.A, self.pendingCommands.B)

	self._pendingState = newState
	self._pendingVictory = victory
	self._misfireMessages = {}

	for _, owner in ipairs(OWNERS) do
		local newBelief = newState.players[owner].belief
		local view = ResolveView.new(self.config, owner, resolution, self.targets[owner], newBelief)
		self._misfireMessages[owner] = view.misfireMessages
		if self.players[owner] then
			Replication.pushResolveView(self.remotes, self.players[owner], view)
		end
	end

	task.delay(self.config.RESOLVE_SECONDS, function()
		self:_commitResolve()
	end)
end

function MatchService:_commitResolve()
	if self.phase ~= "resolve" then
		return
	end
	self.state = self._pendingState
	local victory = self._pendingVictory
	self._pendingState = nil
	self._pendingVictory = nil

	if victory then
		self.phase = "result"
		self._lastVictory = victory
		for _, owner in ipairs(OWNERS) do
			if self.players[owner] then
				Replication.pushResult(self.remotes, self.players[owner], self.config, self.state, owner, victory)
			end
		end
		self.onEnded()
		return
	end

	self:_startPlanPhase()
end

-- Best-effort: stop the round loop and let the remaining player know, rather
-- than leaving them ticking down a clock nobody will ever resolve. No
-- reconnection support -- out of scope for this session (§16 only asks for
-- two clients able to play a match, not survive a drop).
function MatchService:playerLeft(player)
	if self.dead then
		return
	end
	self.dead = true
	self._roundToken += 1

	local owner = self.owners[player]
	local remaining = otherOwner(owner)
	local remainingPlayer = self.players[remaining]
	if remainingPlayer and remainingPlayer.Parent then
		self:_pushState(remaining, "opponent disconnected", false)
	end

	self.onEnded()
end

return MatchService
