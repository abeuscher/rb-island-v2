-- The Command remote's single entry point: matchmaking queue plus per-player
-- rate limiting, then handing off to whichever MatchService a player is
-- actually in (§12: "rate-limit all remotes").

local MatchService = require(script.Parent.MatchService)
local Difficulties = require(game:GetService("ReplicatedStorage").Shared.botDifficulty)

local function isKnownDifficulty(id)
	for _, preset in ipairs(Difficulties) do
		if preset.id == id then
			return true
		end
	end
	return false
end

local RATE_LIMIT_PER_SECOND = 20
local RATE_WINDOW_SECONDS = 1

local CommandHandler = {}
CommandHandler.__index = CommandHandler

function CommandHandler.new(config, remotes)
	local self = setmetatable({}, CommandHandler)
	self.config = config
	self.remotes = remotes
	self.queue = {}
	self.matchByPlayer = {}
	self.rate = {}
	return self
end

function CommandHandler:_allowed(player)
	local now = os.clock()
	local bucket = self.rate[player]
	if not bucket or now - bucket.windowStart >= RATE_WINDOW_SECONDS then
		bucket = { windowStart = now, count = 0 }
		self.rate[player] = bucket
	end
	bucket.count += 1
	return bucket.count <= RATE_LIMIT_PER_SECOND
end

function CommandHandler:_tryMatchmake()
	while #self.queue >= 2 do
		local playerA = table.remove(self.queue, 1)
		local playerB = table.remove(self.queue, 1)
		if playerA.Parent and playerB.Parent then
			local match
			match = MatchService.new(self.config, self.remotes, playerA, playerB, function()
				self.matchByPlayer[playerA] = nil
				self.matchByPlayer[playerB] = nil
			end)
			self.matchByPlayer[playerA] = match
			self.matchByPlayer[playerB] = match
		elseif playerA.Parent then
			table.insert(self.queue, 1, playerA)
		elseif playerB.Parent then
			table.insert(self.queue, 1, playerB)
		end
	end
end

function CommandHandler:handle(player, command)
	if type(command) ~= "table" or type(command.type) ~= "string" then
		return
	end
	if not self:_allowed(player) then
		return
	end

	if command.type == "queueForMatch" then
		if self.matchByPlayer[player] then
			return
		end
		table.insert(self.queue, player)
		self:_tryMatchmake()
		return
	end

	-- Starts immediately -- no matchmaking wait, since there's no second real
	-- player to pair with (§14).
	if command.type == "startBotMatch" then
		if self.matchByPlayer[player] then
			return
		end
		local difficulty = isKnownDifficulty(command.difficulty) and command.difficulty or "skirmish"
		local match
		match = MatchService.new(self.config, self.remotes, player, nil, function()
			self.matchByPlayer[player] = nil
		end, difficulty)
		self.matchByPlayer[player] = match
		return
	end

	local match = self.matchByPlayer[player]
	if match then
		match:handleCommand(player, command)
	end
end

function CommandHandler:playerRemoving(player)
	for i, queued in ipairs(self.queue) do
		if queued == player then
			table.remove(self.queue, i)
			break
		end
	end

	local match = self.matchByPlayer[player]
	if match then
		match:playerLeft(player)
	end

	self.rate[player] = nil
end

return CommandHandler
