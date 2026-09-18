-- One real match's authoritative state and live tick loop (§12). Owns the
-- single MatchState both clients are scored against; every command a client
-- sends is a request, validated here through the same pure src/shared/
-- functions the old single-player PlanController called directly -- the
-- client itself never calls them anymore.
--
-- Phases: "setup" (place 3 bases, untimed) -> "live" (Rules.tick runs on a
-- recurring config.TICK_SECONDS heartbeat; every command applies immediately
-- and permanently via Rules.applyCommand, since there's no round boundary
-- left to hold anything until) -> "result". This replaces the old
-- setup/plan/resolve/result machine and its immediate-apply/replay two-track
-- command model (that model existed only to make simultaneous-reveal
-- batching possible; once resolution runs continuously rather than once per
-- round, there's nothing left to batch).
--
-- A bot match (Session 009) gives owner "B" no real Player Instance at all --
-- self.players.B and self.owners simply never get an entry for it. Setup
-- commands for a bot seat run through the exact same _handleSetupCommand
-- path a real player's commands do, so a bot is held to identical
-- validation, costs, and unlock gates -- every push-to-client call just
-- no-ops for it (see _pushState). Bot re-decisions during "live" run on a
-- periodic config.BOT_DECIDE_INTERVAL_SECONDS cadence off the same tick loop
-- (Session 015), in place of the old single opening decide() call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local State = require(ReplicatedStorage.Shared.state)
local Rules = require(ReplicatedStorage.Shared.rules)
local Structures = require(ReplicatedStorage.Shared.structures)
local Flight = require(ReplicatedStorage.Shared.flight)
local View = require(ReplicatedStorage.Shared.view)
local TickView = require(ReplicatedStorage.Shared.tickView)
local Replication = require(script.Parent.Replication)
local Bot = require(script.Parent.Bot)

local MatchService = {}
MatchService.__index = MatchService

local OWNERS = { "A", "B" }

local function otherOwner(owner)
	return owner == "A" and "B" or "A"
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
	self.readyForSetup = { A = false, B = false }
	self.phase = "setup"
	self.dead = false
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

function MatchService:_pushState(owner, message, ok, tickView)
	local player = self.players[owner]
	if not player then
		return
	end
	Replication.pushState(self.remotes, player, self.state, owner, self.phase, message, ok, tickView)
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

-- Shared success plumbing for every command that just needs Rules.applyCommand
-- run and the result pushed back.
function MatchService:_applyAndPush(owner, command, label)
	local newState, ok, err = Rules.applyCommand(self.config, self.state, owner, command)
	if ok then
		self.state = newState
		self:_pushState(owner, label, true)
	else
		self:_pushState(owner, err, false)
	end
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

	if self.phase ~= "live" then
		return
	end

	self:_handleLiveCommand(owner, command)
end

function MatchService:_handleReady(owner)
	if self.phase ~= "setup" then
		return
	end
	if self:_countBases(owner) ~= self.config.NUM_BASES then
		self:_pushState(owner, string.format("place exactly %d bases before starting", self.config.NUM_BASES), false)
		return
	end
	self.readyForSetup[owner] = true
	self:_pushState(owner, "waiting for opponent", true)
	if self.readyForSetup.A and self.readyForSetup.B then
		self.state = State.completeAllConstruction(self.config, self.state)
		self:_startLive()
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
		self:_applyAndPush(owner, command, "placed base")
		return
	end

	if command.type == "bulldoze" then
		self:_applyAndPush(owner, command, "bulldozed")
	end
end

function MatchService:_handleLiveCommand(owner, command)
	if command.type == "target" then
		self:_handleTarget(owner, command)
	elseif command.type == "bulldoze" then
		self:_applyAndPush(owner, command, "bulldozed")
	elseif command.type == "raise" then
		self:_applyAndPush(owner, command, "raised terrain")
	elseif command.type == "lower" then
		self:_applyAndPush(owner, command, "lowered terrain")
	elseif command.type == "reclaim" then
		self:_applyAndPush(owner, command, "reclaimed land")
	elseif command.type == "place" then
		self:_applyAndPush(owner, command, "placed " .. tostring(command.typeId))
	end
end

-- Range/ownership are checked here too, ahead of Rules.applyCommand, purely for
-- an instant, specific error message -- Rules.tick's own fire-time check
-- (planShots) would otherwise just leave an illegal target silently never
-- firing, with nothing to tell the player why.
function MatchService:_handleTarget(owner, command)
	local weapon = Structures.at(self.config.STRUCTURES, self.state.players[owner].structures, command.x, command.y)
	if not weapon then
		self:_pushState(owner, "no weapon there", false)
		return
	end

	local def = self.config.STRUCTURES[weapon.typeId]
	if not def.fire_mode then
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

	self:_applyAndPush(owner, command, string.format("target set to (%d, %d)", command.targetX, command.targetY))
end

function MatchService:_startLive()
	self.phase = "live"

	for _, owner in ipairs(OWNERS) do
		self:_pushState(owner, "match begins", true)
	end

	-- The tick loop starts before the bot's own decide() call, so a bot-seat
	-- error can't also take the live loop down with it.
	self:_runTickLoop()

	if self.bot then
		self.state = self:_applyBotSupplyMultiplier(self.state)
		self:_runBotTurn()
		self._botNextDecideAt = self.config.BOT_DECIDE_INTERVAL_SECONDS
	end
end

-- §14's difficulty knob, applied directly to the bot's own resources rather
-- than in the shared economy/rules core every real player and every sim
-- archetype also goes through unmodified -- it's a bot-only handicap, not a
-- rules change. Scales off STARTING_SUPPLY rather than the old per-round
-- SUPPLY_PER_ROUND (gone since Session 011's rate-based economy rework) --
-- same "extra = base * (multiplier - 1)" shape, against the nearest constant
-- that still means the same thing: a one-time starting-Supply handicap.
function MatchService:_applyBotSupplyMultiplier(state)
	local extra = math.floor(self.config.STARTING_SUPPLY * (self.bot.preset.supplyMultiplier - 1) + 0.5)
	if extra == 0 then
		return state
	end
	local botResources = state.players.B.resources
	return State.withPlayer(state, "B", {
		resources = { supply = math.max(0, botResources.supply + extra), energy = botResources.energy },
	})
end

-- Runs one decide() pass: at match start (_startLive) and then periodically
-- from _tick every config.BOT_DECIDE_INTERVAL_SECONDS. Safe to call repeatedly
-- -- decide() only ever adds commands for what the bot doesn't already have,
-- against the current live state each time, so a re-decide call is never a
-- replay of an earlier one.
function MatchService:_runBotTurn()
	local commands = self.bot:decide(self.config, View.new(self.state, "B"))
	for _, command in ipairs(commands) do
		if command.type == "target" then
			self:_handleTarget("B", command)
		else
			self:_applyAndPush("B", command, command.type)
		end
	end
end

function MatchService:_runTickLoop()
	task.spawn(function()
		while self.phase == "live" and not self.dead do
			task.wait(self.config.TICK_SECONDS)
			if self.phase ~= "live" or self.dead then
				return
			end
			self:_tick()
		end
	end)
end

function MatchService:_tick()
	local newState, _, victory, resolution = Rules.tick(self.config, self.state)
	self.state = newState

	for _, owner in ipairs(OWNERS) do
		if self.players[owner] then
			local newBelief = newState.players[owner].belief
			self:_pushState(owner, nil, nil, TickView.new(owner, resolution, newBelief))
		end
	end

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

	if self.bot and self.state.elapsed >= self._botNextDecideAt then
		self:_runBotTurn()
		self._botNextDecideAt = self.state.elapsed + self.config.BOT_DECIDE_INTERVAL_SECONDS
	end
end

-- Best-effort: stop the live loop and let the remaining player know, rather
-- than leaving them in a match nobody will ever tick again. No reconnection
-- support -- out of scope for this session (§16 only asks for two clients
-- able to play a match, not survive a drop).
function MatchService:playerLeft(player)
	if self.dead then
		return
	end
	self.dead = true

	local owner = self.owners[player]
	local remaining = otherOwner(owner)
	local remainingPlayer = self.players[remaining]
	if remainingPlayer and remainingPlayer.Parent then
		self:_pushState(remaining, "opponent disconnected", false)
	end

	self.onEnded()
end

return MatchService
