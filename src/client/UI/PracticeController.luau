-- Local, offline practice mode against a scripted dummy opponent -- kept on
-- deliberately as a documented fallback alongside the real server-
-- authoritative match (see PlanController.luau). No server, no remotes: this
-- controller owns a local MatchState directly and drives it the same way
-- MatchService.luau drives a real match, minus the network layer -- a local
-- `Rules.applyCommand` call per player action, a local recurring tick loop
-- (RunService.Heartbeat accumulating to config.TICK_SECONDS, since there's
-- no server heartbeat to piggyback on here), and TickView.new for the
-- resolve-animation payload.
--
-- The rest of the plan-phase UI (StructureView, Cursor, Render, RoundClock,
-- BuildPalette) reads a redacted `View` (src/shared/view.luau) off
-- `controller.state` rather than raw MatchState, so both this controller and
-- the real PlanController can drive the exact same UI code unmodified.
-- `self._full` is this controller's private full dual-player MatchState
-- (needed for Rules.tick, dummy seeding, and the enemy's true structures);
-- `self.state` is always that state's `View` for the local player,
-- republished via `_publish()` after every mutation.
--
-- Phases: "setup" (place 3 bases, untimed) -> "live" (build/target/fire runs
-- continuously against the tick loop) -> "result" once Rules.checkVictory
-- fires. There's no separate resolve phase or clock to restart between
-- rounds -- every tick can carry something to animate.
--
-- Commands apply immediately and permanently on receipt, like the real
-- match -- no pendingCommands/roundStartState/replay, since there's no round
-- boundary left to batch against.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Structures = require(ReplicatedStorage.Shared.structures)
local State = require(ReplicatedStorage.Shared.state)
local Rules = require(ReplicatedStorage.Shared.rules)
local Flight = require(ReplicatedStorage.Shared.flight)
local View = require(ReplicatedStorage.Shared.view)
local TickView = require(ReplicatedStorage.Shared.tickView)

local PracticeController = {}
PracticeController.__index = PracticeController

local function cellKey(x, y)
	return x .. "," .. y
end

local function otherOwner(owner)
	return owner == "A" and "B" or "A"
end

-- The board is mirror-symmetric across the channel (see board.luau's construction),
-- so reflecting a cell's x through the board's width lines it up with the cell
-- directly opposite it on the other island.
local function mirrorCell(board, x, y)
	return board.width + 1 - x, y
end

-- Seeds a scripted, already-built enemy layout to have something to shoot at --
-- practice mode's whole point, since it has no real second player. Its 3 bases
-- exist from the start (setup, for the dummy, is instantaneous), plus a
-- generator and a frontline cannon that targets once, live, and fires on its
-- own cooldown from there -- enough to demonstrate a raised ridge blocking a
-- shot once terrain editing is in play. Placed directly via Board.islandBounds
-- rather than through State.placeStructure so the dummy doesn't need to spend
-- its own Supply or wait out a build time.
local function seedDummyOpponent(config, state, enemy)
	local colStart, _, rowStart, _ = Board.islandBounds(config, enemy)
	-- "Frontline" (closest to the channel) is colStart for B, colEnd for A -- only
	-- B is ever seeded as the dummy in practice (PlanUI always mounts as "A").
	local frontlineCol = colStart

	-- autoFire = true: the dummy has no one to keep re-arming its target every
	-- cooldown the way single-shot now expects a real player to (§18), and
	-- it's still meant to keep pressuring the player across a whole match.
	local function structure(typeId, x, y)
		return { typeId = typeId, x = x, y = y, hp = config.STRUCTURES[typeId].hp, underConstruction = false, autoFire = true }
	end

	local cannonCell = { x = frontlineCol, y = rowStart }
	local structures = {
		structure("cannon", cannonCell.x, cannonCell.y),
		structure("generator", frontlineCol, rowStart + 1),
		structure("base", colStart + 1, rowStart + 1),
		structure("base", colStart + 1, rowStart + 5),
		structure("base", colStart + 1, rowStart + 9),
	}

	local newState = State.withPlayer(state, enemy, { structures = structures })
	return newState, cannonCell
end

function PracticeController.new(config, owner)
	local self = setmetatable({}, PracticeController)
	self.config = config
	self.owner = owner
	self.enemy = otherOwner(owner)

	local full = State.new(config)
	full, self.dummyCannonCell = seedDummyOpponent(config, full, self.enemy)
	self._full = full
	self.phase = "setup"

	self.tool = "none"
	self.armedWeaponKey = nil
	self.armedWeapon = nil
	self.selectedWeaponKey = nil
	self.listeners = {}
	self.tickListeners = {}
	self.resolveListeners = {}
	self.matchEndListeners = {}
	self._heartbeatConnection = nil

	self:_publish()
	return self
end

function PracticeController:_publish()
	self.state = View.new(self._full, self.owner)
end

function PracticeController:onChange(callback)
	table.insert(self.listeners, callback)
end

-- Fires whenever a tick produced something worth animating. `callback(preState,
-- shots, destroyed, newBelief)`: `preState` only ever carries `.board` (terrain
-- is public and never changes mid-tick); `shots` is every shot from both sides
-- this tick (each `{ def, shot, owner, origin, hit }`, `shot` per flight.luau's
-- resolveShot contract); `destroyed` is every structure lost on either side
-- this tick; `newBelief` is the owner's belief map after this tick's reveals.
function PracticeController:onResolve(callback)
	table.insert(self.resolveListeners, callback)
end

-- Fires once, when a tick's resolution ends the match: `callback(victory,
-- summary)`, `summary` a `{ own, opponent }` pair of Rules.summary(...) tables --
-- the Result screen's contract regardless of controller (see PlanController.luau).
function PracticeController:onMatchEnd(callback)
	table.insert(self.matchEndListeners, callback)
end

function PracticeController:_notify(message, ok)
	for _, callback in ipairs(self.listeners) do
		callback(message, ok)
	end
end

-- Fires every Heartbeat while the clock runs, for cheap per-frame countdown
-- display -- kept separate from onChange so a plain frame doesn't force a full
-- board/structure re-render 60 times a second.
function PracticeController:onTick(callback)
	table.insert(self.tickListeners, callback)
end

function PracticeController:setTool(tool)
	self.tool = tool
	self.armedWeaponKey = nil
	self.armedWeapon = nil
	self.selectedWeaponKey = nil
end

-- See PlanController.luau's own armTarget -- arming from BuildPalette's list
-- also selects the weapon for the info card, notifying through the same
-- onChange chain PracticeController's other actions already use.
function PracticeController:armTarget(weapon)
	self.tool = "target"
	self.armedWeaponKey = weapon.key
	self.armedWeapon = weapon
	self.selectedWeaponKey = weapon.key
	self:_notify(nil, nil)
end

-- See PlanController.luau's own selectWeaponAt/getSelectedWeapon -- same
-- right-click interaction, same live-read-off-state contract, mirrored here
-- since both controllers drive the same UI code unmodified.
function PracticeController:selectWeaponAt(x, y)
	local structure = Structures.at(self.config.STRUCTURES, self.state.self.structures, x, y)
	if structure and self.config.STRUCTURES[structure.typeId].fire_mode then
		self.selectedWeaponKey = cellKey(structure.x, structure.y)
	else
		self.selectedWeaponKey = nil
	end
end

function PracticeController:getSelectedWeapon()
	if not self.selectedWeaponKey then
		return nil
	end
	for _, weapon in ipairs(self:getWeapons()) do
		if weapon.key == self.selectedWeaponKey then
			return weapon
		end
	end
	self.selectedWeaponKey = nil
	return nil
end

-- The player's own weapons, still under construction or not -- a target can be
-- armed on one right after placing it (Rules.applyCommand's "target" command
-- doesn't require it to be complete either), so it starts firing the moment
-- construction finishes instead of sitting idle until the player comes back.
-- `target` reads straight off the structure (own structures are always fully
-- visible, never redacted) rather than a separate client-side cache -- so the
-- displayed target can never drift from what the weapon is actually firing at.
function PracticeController:getWeapons()
	local weapons = {}
	local resources = self.state.self.resources
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
				autoFire = structure.autoFire,
				-- See PlanController.luau's own getWeapons() -- same "off cooldown
				-- but can't currently afford it" surfacing.
				powered = resources.energy >= def.energy_cost,
			})
		end
	end
	return weapons
end

-- How many bases the player currently has placed -- setup's Ready gate (must be
-- exactly config.NUM_BASES) and its "N/3 placed" display both read this.
function PracticeController:countOwnBases()
	local count = 0
	for _, structure in ipairs(self.state.self.structures) do
		if structure.typeId == "base" then
			count += 1
		end
	end
	return count
end

-- Shared success plumbing for every command that just needs Rules.applyCommand
-- run and the result published.
function PracticeController:_dispatch(command, label)
	local newState, ok, err = Rules.applyCommand(self.config, self._full, self.owner, command)
	if ok then
		self._full = newState
		self:_publish()
		self:_notify(label, true)
	else
		self:_notify(err, false)
	end
end

function PracticeController:handleBoardClick(x, y)
	if self.phase ~= "setup" and self.phase ~= "live" then
		return
	end

	local tool = self.tool

	if tool == "target" then
		if self.phase ~= "live" or not self.armedWeaponKey then
			return
		end
		if Board.ownerOf(self._full.board, x, y) ~= self.enemy then
			self:_notify("target must be on the enemy island", false)
			return
		end

		local weapon = self.armedWeapon
		local def = self.config.STRUCTURES[weapon.typeId]
		local elevation = Board.elevationAt(self._full.board, weapon.x, weapon.y)
		local distance = Flight.chebyshevDistance(weapon.x, weapon.y, x, y)
		if distance > Flight.range(def, elevation) then
			self:_notify("target out of range", false)
			return
		end

		self:_dispatch(
			{ type = "target", x = weapon.x, y = weapon.y, targetX = x, targetY = y },
			string.format("target set to (%d, %d)", x, y)
		)
		return
	end

	if tool == "bulldoze" then
		local newState, ok, err = Rules.applyCommand(self.config, self._full, self.owner, { type = "bulldoze", x = x, y = y })
		if ok then
			self._full = newState
			self:_publish()
			self:_notify("bulldozed", true)
		else
			self:_notify(err, false)
		end
		return
	end

	if self.phase == "setup" then
		-- Setup only ever offers base placement + bulldoze (see BuildPalette); a
		-- terrain/reclaim/other-structure tool can't be armed here.
		if string.sub(tool, 1, 6) == "place:" then
			local typeId = string.sub(tool, 7)
			self:_dispatch({ type = "place", typeId = typeId, x = x, y = y }, "placed " .. typeId)
		end
		return
	end

	if tool == "raise" then
		self:_dispatch({ type = "raise", x = x, y = y }, "raised terrain")
		return
	end

	if tool == "lower" then
		self:_dispatch({ type = "lower", x = x, y = y }, "lowered terrain")
		return
	end

	if tool == "reclaim" then
		self:_dispatch({ type = "reclaim", x = x, y = y }, "reclaimed land")
		return
	end

	if string.sub(tool, 1, 6) == "place:" then
		local typeId = string.sub(tool, 7)
		self:_dispatch({ type = "place", typeId = typeId, x = x, y = y }, "placed " .. typeId)
		return
	end
end

-- Same command shape as PlanController's setAutoFire, dispatched locally
-- instead of over the network like every other command here.
function PracticeController:setAutoFire(weapon, enabled)
	self:_dispatch(
		{ type = "autoFire", x = weapon.x, y = weapon.y, enabled = enabled },
		enabled and "auto-fire enabled" or "auto-fire disabled"
	)
end

function PracticeController:getSecondsRemaining()
	local elapsed = self.state and self.state.elapsed or 0
	return math.max(0, self.config.MATCH_SECONDS - elapsed)
end

-- Runs Rules.tick once, publishes the result, and fires onResolve when this
-- tick actually produced something worth animating -- mirrors MatchService's
-- _tick, minus pushing anything over the network.
function PracticeController:_tick()
	local newState, _, victory, resolution = Rules.tick(self.config, self._full)
	self._full = newState
	self:_publish()
	self:_notify(nil, nil)

	local tickView = TickView.new(self.owner, resolution, newState.players[self.owner].belief)
	if #tickView.shots > 0 or #tickView.destroyed > 0 then
		local preState = { board = newState.board }
		for _, callback in ipairs(self.resolveListeners) do
			callback(preState, tickView.shots, tickView.destroyed, tickView.newBelief)
		end
	end

	if victory then
		self:stopClock()
		self.phase = "result"
		local summary = {
			own = Rules.summary(self.config, self._full.players[self.owner]),
			opponent = Rules.summary(self.config, self._full.players[self.enemy]),
		}
		for _, callback in ipairs(self.matchEndListeners) do
			callback(victory, summary)
		end
	end
end

-- Drives the tick loop off RunService.Heartbeat, accumulating to
-- config.TICK_SECONDS -- the local stand-in for the real match's server
-- heartbeat. Catches up (runs more than one tick in a frame) after a stall
-- rather than dropping ticks, and stops calling in once phase leaves "live"
-- (victory, from inside _tick above).
function PracticeController:startClock()
	local accumulated = 0
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		while accumulated >= self.config.TICK_SECONDS and self.phase == "live" do
			accumulated -= self.config.TICK_SECONDS
			self:_tick()
		end
		for _, callback in ipairs(self.tickListeners) do
			callback()
		end
	end)
end

function PracticeController:stopClock()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
end

-- Ends the untimed setup phase once the player has placed exactly NUM_BASES
-- bases (§8), completing every structure immediately regardless of readyAt --
-- setup's bases were never meant to sit on the same build timer live-placed
-- structures get (session 012's fix, restated here) -- arms the dummy's
-- frontline cannon with a persistent target, and starts the live tick loop.
function PracticeController:_startLive()
	self._full = State.completeAllConstruction(self.config, self._full)

	if self.dummyCannonCell then
		local targetX, targetY = mirrorCell(self._full.board, self.dummyCannonCell.x, self.dummyCannonCell.y)
		local newFull, ok = Rules.applyCommand(self.config, self._full, self.enemy, {
			type = "target",
			x = self.dummyCannonCell.x,
			y = self.dummyCannonCell.y,
			targetX = targetX,
			targetY = targetY,
		})
		if ok then
			self._full = newFull
		end
	end

	self.phase = "live"
	self:_publish()
	self:_notify("match begins", true)
	self:startClock()
end

-- Dispatches the Ready button: finishes setup once exactly NUM_BASES bases are
-- placed. A no-op once "live" -- ending the match early isn't a concept, same
-- as the server no-opping a "live" Ready.
function PracticeController:ready()
	if self.phase ~= "setup" then
		return
	end
	if self:countOwnBases() ~= self.config.NUM_BASES then
		self:_notify(string.format("place exactly %d bases before starting", self.config.NUM_BASES), false)
		return
	end
	self:_startLive()
end

-- No-op: nothing here to commit -- the tick that produced a resolution already
-- applied it before onResolve fired. Kept only so Render.luau's existing
-- post-animation call stays harmless.
function PracticeController:commitResolve() end

return PracticeController
