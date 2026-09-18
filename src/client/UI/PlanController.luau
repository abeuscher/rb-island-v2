-- Thin client view onto a real match (§12): every action the player takes is
-- sent to the server as a `Command` request and never mutates anything
-- locally -- `self.state` only ever changes when the server pushes a fresh
-- `StateUpdate`. This replaces Session 005-007's local PlanController, which
-- called straight into src/shared/state.luau; that flow lives on unchanged
-- as PracticeController.luau for offline practice.
--
-- `self.state` is a src/shared/view.luau `View`: `{ elapsed, board, owner,
-- opponent, self }`, where `self` is this player's own resources/structures/
-- belief/score -- never the opponent's. The rest of the plan-phase UI
-- (StructureView, Cursor, Render, RoundClock, BuildPalette) reads that same
-- shape regardless of which controller is driving it.
--
-- Phases: "setup" (place 3 bases, untimed) -> "live" (build/target/fire runs
-- continuously; the server pushes a fresh StateUpdate every tick, carrying
-- whatever shots/destroyed landed since the last one) -> "result" once the
-- server's Rules.checkVictory fires. There's no separate resolve phase or
-- clock to restart between rounds anymore -- a single StateUpdate stream
-- covers both "my state changed" and "here's what to animate."

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
	self.tool = "none"
	self.armedWeaponKey = nil
	self.armedWeapon = nil
	self.listeners = {}
	self.tickListeners = {}
	self.resolveListeners = {}
	self.matchEndListeners = {}

	-- Request-then-wait, not fire-and-forget: the server only ever pushes
	-- StateUpdate in response to a command, so without this handshake there
	-- would be nothing to populate `self.state` with before PlanUI.mount
	-- reads it to draw the first frame. No other event can arrive between
	-- Wait() returning and the Connect below -- Luau doesn't yield there.
	remotes.Command:FireServer({ type = "requestState" })
	local initialPayload = remotes.StateUpdate.OnClientEvent:Wait()
	self:_onStateUpdate(initialPayload)

	self._stateConn = remotes.StateUpdate.OnClientEvent:Connect(function(payload)
		self:_onStateUpdate(payload)
	end)

	return self
end

function PlanController:onChange(callback)
	table.insert(self.listeners, callback)
end

-- Fires whenever a tick pushed something worth animating. `callback(preState,
-- shots, destroyed, newBelief)`: `preState` only ever carries `.board` (terrain
-- is public, per §11, and never changes mid-tick); `shots` is every shot from
-- both sides this tick (each `{ def, shot, owner, origin, hit }`, `shot` per
-- flight.luau's resolveShot contract); `destroyed` is every structure lost on
-- either side this tick; `newBelief` is this player's own belief map after
-- this tick's reveals.
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

-- Kept for interface parity with PracticeController/RoundClock -- the server's
-- own tick pushes a fresh StateUpdate roughly every config.TICK_SECONDS
-- already, which onChange already reacts to, so there's no local heartbeat
-- left to drive here.
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

-- The player's own weapons, still under construction or not -- a target can be
-- armed on one right after placing it (Rules.applyCommand's "target" command
-- doesn't require it to be complete either), so it starts firing the moment
-- construction finishes instead of sitting idle until the player comes back.
-- `target` reads straight off the structure (own structures are always fully
-- visible, never redacted) rather than a separate client-side cache -- so the
-- displayed target can never drift from what the weapon is actually firing at.
function PlanController:getWeapons()
	local weapons = {}
	for _, structure in ipairs(self.state.self.structures) do
		local def = self.config.STRUCTURES[structure.typeId]
		if def.fire_mode then
			table.insert(weapons, {
				key = cellKey(structure.x, structure.y),
				x = structure.x,
				y = structure.y,
				typeId = structure.typeId,
				target = structure.target,
				nextFireAt = structure.nextFireAt,
				underConstruction = structure.underConstruction,
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
	if self.phase ~= "setup" and self.phase ~= "live" then
		return
	end

	local tool = self.tool

	if tool == "target" then
		if self.phase ~= "live" or not self.armedWeaponKey then
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

-- The match clock is derived from the server's own continuously-pushed
-- elapsed time, not counted down locally.
function PlanController:getSecondsRemaining()
	local elapsed = self.state and self.state.elapsed or 0
	return math.max(0, self.config.MATCH_SECONDS - elapsed)
end

-- No-ops: kept for interface parity with PracticeController (whose local
-- countdown genuinely needs a heartbeat). Nothing here needs its own clock --
-- the server's tick pushes are the clock.
function PlanController:startClock() end
function PlanController:stopClock() end

-- Ready only ever matters during setup now -- ending a "round" early isn't a
-- concept once there's no round. The server itself no-ops a "live" Ready.
function PlanController:ready()
	self.remotes.Command:FireServer({ type = "ready" })
end

function PlanController:_onStateUpdate(payload)
	if payload.phase == "result" then
		self.phase = "result"
		for _, callback in ipairs(self.matchEndListeners) do
			callback(payload.victory, payload.summary)
		end
		return
	end

	self.phase = payload.phase
	self.state = payload.view
	self:_notify(payload.message, payload.ok)

	if payload.shots and (#payload.shots > 0 or #payload.destroyed > 0) then
		local preState = { board = self.state.board }
		for _, callback in ipairs(self.resolveListeners) do
			callback(preState, payload.shots, payload.destroyed, payload.newBelief)
		end
	end
end

-- No-op: nothing here to commit -- the server's own tick already applied
-- everything before pushing it. Kept only so Render.luau's existing
-- post-animation call stays harmless.
function PlanController:commitResolve() end

return PlanController
