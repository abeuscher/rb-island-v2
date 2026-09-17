-- Client-side plan-phase controller. Holds a local MatchState (no server yet --
-- see Session 005's brief) and exposes the commands the plan-phase UI drives:
-- build/bulldoze, terrain edit/reclaim, target assignment, and the round clock.
--
-- Target assignment has no equivalent in the shared rules core yet (rules.luau,
-- which will consume it, doesn't exist until the Resolve phase session), so it's
-- tracked here as local UI state, keyed by the firing structure's origin cell.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local State = require(ReplicatedStorage.Shared.state)

local PlanController = {}
PlanController.__index = PlanController

local function cellKey(x, y)
	return x .. "," .. y
end

local function otherOwner(owner)
	return owner == "A" and "B" or "A"
end

function PlanController.new(config, owner)
	local self = setmetatable({}, PlanController)
	self.config = config
	self.owner = owner
	self.state = State.new(config)
	self.targets = {}
	self.tool = "none"
	self.armedWeaponKey = nil
	self.secondsRemaining = config.PLAN_SECONDS
	self.listeners = {}
	self.tickListeners = {}
	self._heartbeatConnection = nil
	return self
end

function PlanController:onChange(callback)
	table.insert(self.listeners, callback)
end

function PlanController:_notify(message, ok)
	for _, callback in ipairs(self.listeners) do
		callback(message, ok)
	end
end

-- Fires every Heartbeat while the clock runs, for cheap per-frame countdown
-- display -- kept separate from onChange so a plain tick doesn't force a full
-- board/structure re-render 60 times a second.
function PlanController:onTick(callback)
	table.insert(self.tickListeners, callback)
end

function PlanController:setTool(tool)
	self.tool = tool
	self.armedWeaponKey = nil
end

function PlanController:armTarget(weaponKey)
	self.tool = "target"
	self.armedWeaponKey = weaponKey
end

-- The player's own live, completed weapons -- only these can be given a target.
function PlanController:getWeapons()
	local weapons = {}
	for _, structure in ipairs(self.state.players[self.owner].structures) do
		local def = self.config.STRUCTURES[structure.typeId]
		if def.fire_mode and not structure.underConstruction then
			local key = cellKey(structure.x, structure.y)
			table.insert(weapons, {
				key = key,
				x = structure.x,
				y = structure.y,
				typeId = structure.typeId,
				target = self.targets[key],
			})
		end
	end
	return weapons
end

function PlanController:handleBoardClick(x, y)
	local tool = self.tool

	if tool == "target" then
		if not self.armedWeaponKey then
			return
		end
		local enemy = otherOwner(self.owner)
		if Board.ownerOf(self.state.board, x, y) ~= enemy then
			self:_notify("target must be on the enemy island", false)
			return
		end
		self.targets[self.armedWeaponKey] = { x = x, y = y }
		self:_notify(string.format("target set to (%d, %d)", x, y), true)
		return
	end

	if tool == "bulldoze" then
		local newState, ok, err = State.bulldozeStructure(self.config, self.state, self.owner, x, y)
		if ok then
			self.targets[cellKey(x, y)] = nil
		end
		self:_apply(newState, ok, err, "bulldozed")
		return
	end

	if tool == "raise" then
		local newState, ok, err = State.raiseTerrain(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "raised terrain")
		return
	end

	if tool == "lower" then
		local newState, ok, err = State.lowerTerrain(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "lowered terrain")
		return
	end

	if tool == "reclaim" then
		local newState, ok, err = State.reclaimLand(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "reclaimed land")
		return
	end

	if string.sub(tool, 1, 6) == "place:" then
		local typeId = string.sub(tool, 7)
		local newState, ok, err = State.placeStructure(self.config, self.state, self.owner, typeId, x, y)
		self:_apply(newState, ok, err, "placed " .. typeId)
		return
	end
end

-- Shared success plumbing for the State.* calls above, which all return
-- (newState, ok, err). `label` is used for the success message only.
function PlanController:_apply(newState, ok, err, label)
	if ok then
		self.state = newState
		self:_notify(label, true)
	else
		self:_notify(err, false)
	end
end

function PlanController:getSecondsRemaining()
	return self.secondsRemaining
end

function PlanController:startClock()
	self.secondsRemaining = self.config.PLAN_SECONDS
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		self.secondsRemaining -= dt
		if self.secondsRemaining <= 0 then
			self:advanceRound()
		else
			for _, callback in ipairs(self.tickListeners) do
				callback()
			end
		end
	end)
end

function PlanController:stopClock()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
end

-- Ends the current PLAN phase (via Ready or clock expiry) and starts the next
-- one. There's no rules.luau round-resolution yet and no opponent to wait on
-- in this local-only session, so this just runs the RESOLVE-phase steps the
-- rules core already exposes (construction completing, income accruing) and
-- increments the round counter.
function PlanController:advanceRound()
	local newState = State.completeConstruction(self.config, self.state)
	newState = State.accrueIncome(self.config, newState)
	newState = table.clone(newState)
	newState.round = newState.round + 1
	self.state = newState
	self.secondsRemaining = self.config.PLAN_SECONDS
	self:_notify(string.format("round %d begins", newState.round), true)
end

return PlanController
