-- Thin client view onto a real two-player match (§12): every action the
-- player takes is sent to the server as a `Command` request and never
-- mutates anything locally -- `self.state` only ever changes when the server
-- pushes a fresh `StateUpdate`. This replaces Session 005-007's local
-- PlanController, which called straight into src/shared/state.luau; that
-- flow lives on unchanged as PracticeController.luau for offline practice.
--
-- `self.state` is a src/shared/view.luau `View`: `{ round, board, owner,
-- opponent, self }`, where `self` is this player's own resources/structures/
-- belief/score -- never the opponent's. The rest of the plan-phase UI
-- (StructureView, Cursor, Render, RoundClock, BuildPalette) reads that same
-- shape regardless of which controller is driving it.
--
-- Phases: "setup" (place 3 bases, untimed) -> "plan" (build/target under the
-- clock) -> "resolve" (volley animates) -> back to "plan", or "result" once
-- the server's Rules.checkVictory fires. The round clock shown here is
-- cosmetic only -- the server's own clock (server/MatchService.luau) is what
-- actually ends a round; this one just counts down in step with it so the
-- countdown doesn't freeze between state pushes.

local RunService = game:GetService("RunService")

local Board = require(game:GetService("ReplicatedStorage").Shared.board)
local Flight = require(game:GetService("ReplicatedStorage").Shared.flight)

local PlanController = {}
PlanController.__index = PlanController

local function cellKey(x, y)
	return x .. "," .. y
end

local function otherOwner(owner)
	return owner == "A" and "B" or "A"
end

function PlanController.new(config, owner, remotes)
	local self = setmetatable({}, PlanController)
	self.config = config
	self.owner = owner
	self.enemy = otherOwner(owner)
	self.remotes = remotes

	self.phase = "setup"
	self.state = nil
	self.targets = {}
	self.tool = "none"
	self.armedWeaponKey = nil
	self.armedWeapon = nil
	self.secondsRemaining = config.PLAN_SECONDS
	self.listeners = {}
	self.tickListeners = {}
	self.resolveListeners = {}
	self.matchEndListeners = {}
	self._heartbeatConnection = nil

	-- Request-then-wait, not fire-and-forget: the server only ever pushes
	-- StateUpdate in response to a command, so without this handshake there
	-- would be nothing to populate `self.state` with before PlanUI.mount
	-- reads it to draw the first frame. No other event can arrive between
	-- Wait() returning and the Connect below -- Luau doesn't yield there.
	remotes.Command:FireServer({ type = "requestState" })
	local initialPayload = remotes.StateUpdate.OnClientEvent:Wait()
	self:_applyStateUpdate(initialPayload)

	self._stateConn = remotes.StateUpdate.OnClientEvent:Connect(function(payload)
		self:_onStateUpdate(payload)
	end)
	self._resolveConn = remotes.ResolveEvent.OnClientEvent:Connect(function(payload)
		self:_onResolveEvent(payload)
	end)

	return self
end

function PlanController:onChange(callback)
	table.insert(self.listeners, callback)
end

-- Fires when the server has pushed this round's resolution but before it's
-- animated. `callback(preState, shots, destroyed, newBelief)`: `preState` only
-- ever carries `.board` (the pre-combat, post-terrain-edit board -- terrain is
-- public, per §11); `shots` is every shot from both sides this round (each
-- `{ def, shot, owner, origin, hit }`, `shot` per flight.luau's resolveShot
-- contract); `destroyed` is every structure lost on either side; `newBelief`
-- is this player's own belief map after this round's reveals.
function PlanController:onResolve(callback)
	table.insert(self.resolveListeners, callback)
end

-- Fires once, when the server ends the match: `callback(victory, summary)`,
-- `summary` a `{ own, opponent }` pair of Rules.summary(...) tables -- counts
-- and point totals only, never raw structures/belief (§12 holds even at
-- match end).
function PlanController:onMatchEnd(callback)
	table.insert(self.matchEndListeners, callback)
end

function PlanController:_notify(message, ok)
	for _, callback in ipairs(self.listeners) do
		callback(message, ok)
	end
end

-- Fires every Heartbeat while the (cosmetic) clock runs.
function PlanController:onTick(callback)
	table.insert(self.tickListeners, callback)
end

function PlanController:setTool(tool)
	self.tool = tool
	self.armedWeaponKey = nil
	self.armedWeapon = nil
end

function PlanController:armTarget(weapon)
	self.tool = "target"
	self.armedWeaponKey = weapon.key
	self.armedWeapon = weapon
end

-- The player's own live, completed weapons -- only these can be given a target.
function PlanController:getWeapons()
	local weapons = {}
	for _, structure in ipairs(self.state.self.structures) do
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

-- How many bases the player currently has placed -- setup's Ready gate (must be
-- exactly config.NUM_BASES) and its "N/3 placed" display both read this.
function PlanController:countOwnBases()
	local count = 0
	for _, structure in ipairs(self.state.self.structures) do
		if structure.typeId == "base" then
			count += 1
		end
	end
	return count
end

-- Every click just becomes a Command request -- the server is the only thing
-- that ever mutates MatchState now. The one exception is the target tool's
-- range/ownership preflight, kept here purely so a bad click fails instantly
-- instead of round-tripping to the server first; the server re-validates the
-- same two checks regardless (§12), so this is UX only, not a trust boundary.
function PlanController:handleBoardClick(x, y)
	if self.phase ~= "setup" and self.phase ~= "plan" then
		return
	end

	local tool = self.tool

	if tool == "target" then
		if self.phase ~= "plan" or not self.armedWeaponKey then
			return
		end
		if Board.ownerOf(self.state.board, x, y) ~= self.enemy then
			self:_notify("target must be on the enemy island", false)
			return
		end

		local weapon = self.armedWeapon
		local def = self.config.STRUCTURES[weapon.typeId]
		local elevation = Board.elevationAt(self.state.board, weapon.x, weapon.y)
		local distance = Flight.chebyshevDistance(weapon.x, weapon.y, x, y)
		if distance > Flight.range(def, elevation) then
			self:_notify("target out of range", false)
			return
		end

		self.targets[self.armedWeaponKey] = { x = x, y = y }
		self.remotes.Command:FireServer({ type = "target", x = weapon.x, y = weapon.y, targetX = x, targetY = y })
		return
	end

	if tool == "bulldoze" then
		self.remotes.Command:FireServer({ type = "bulldoze", x = x, y = y })
		return
	end

	if self.phase == "setup" then
		-- Setup only ever offers base placement + bulldoze (see BuildPalette); a
		-- terrain/reclaim/other-structure tool can't be armed here.
		if string.sub(tool, 1, 6) == "place:" then
			self.remotes.Command:FireServer({ type = "place", typeId = string.sub(tool, 7), x = x, y = y })
		end
		return
	end

	if tool == "raise" or tool == "lower" or tool == "reclaim" then
		self.remotes.Command:FireServer({ type = tool, x = x, y = y })
		return
	end

	if string.sub(tool, 1, 6) == "place:" then
		self.remotes.Command:FireServer({ type = "place", typeId = string.sub(tool, 7), x = x, y = y })
		return
	end
end

function PlanController:getSecondsRemaining()
	return self.secondsRemaining
end

function PlanController:startClock()
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		self.secondsRemaining = math.max(0, self.secondsRemaining - dt)
		for _, callback in ipairs(self.tickListeners) do
			callback()
		end
	end)
end

function PlanController:stopClock()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
end

-- Ready works the same button for both setup ("done placing bases") and plan
-- ("end this round early") -- the server knows which from its own phase.
function PlanController:ready()
	self.remotes.Command:FireServer({ type = "ready" })
end

function PlanController:_applyStateUpdate(payload)
	local enteringPlan = payload.phase == "plan" and self.phase ~= "plan"
	local leavingPlan = payload.phase ~= "plan" and self.phase == "plan"

	self.phase = payload.phase
	self.state = payload.view

	if leavingPlan then
		self:stopClock()
	end
	if enteringPlan then
		self.secondsRemaining = payload.secondsRemaining
		self:startClock()
	end
end

function PlanController:_onStateUpdate(payload)
	if payload.phase == "result" then
		self:stopClock()
		self.phase = "result"
		for _, callback in ipairs(self.matchEndListeners) do
			callback(payload.victory, payload.summary)
		end
		return
	end

	self:_applyStateUpdate(payload)
	self:_notify(payload.message, payload.ok)
end

function PlanController:_onResolveEvent(payload)
	local preState = { board = payload.board }
	for _, callback in ipairs(self.resolveListeners) do
		callback(preState, payload.shots, payload.destroyed, payload.newBelief)
	end
end

-- No-op: the server commits the round on its own timer
-- (config.RESOLVE_SECONDS), independent of how long this client's own
-- animation takes. Kept only so Render.luau's existing post-animation call
-- stays harmless.
function PlanController:commitResolve() end

return PlanController
