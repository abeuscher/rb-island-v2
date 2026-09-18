-- Client-side match controller. Holds a local MatchState (no server yet -- see
-- Session 005's brief) and exposes the commands the setup/plan-phase UI drives:
-- base placement during setup, build/bulldoze, terrain edit/reclaim, target
-- assignment, and the round clock. Also owns resolving each round's volley
-- (advanceRound/commitResolve below) against a scripted dummy opponent seeded
-- onto the enemy island.
--
-- Phases: "setup" (place 3 bases, untimed) -> "plan" (build/target under the
-- clock) -> "resolve" (volley animates) -> back to "plan", or "result" once
-- Rules.checkVictory fires.
--
-- PLAN-phase commands are applied immediately to `self.state` for instant UI
-- feedback (same precedent as Sessions 005-006), and in parallel logged to
-- `self.pendingCommands`. At round's end those commands are replayed from
-- `self.roundStartState` through `Rules.resolveRound` alongside the dummy's own
-- command batch, so both sides resolve simultaneously against the same
-- pre-round snapshot -- the real batching `resolveRound` was built for, closing
-- the gap Session 006 deliberately left open.
--
-- Target assignment still has no equivalent in the shared rules core -- rules.luau
-- expects targets in this same shape (a map keyed by the firing structure's
-- origin cell), but nothing there tracks assignment itself -- so it stays local
-- UI state here, mirrored into pendingCommands as "target" commands.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local State = require(ReplicatedStorage.Shared.state)
local Rules = require(ReplicatedStorage.Shared.rules)
local Economy = require(ReplicatedStorage.Shared.economy)
local Flight = require(ReplicatedStorage.Shared.flight)

local PlanController = {}
PlanController.__index = PlanController

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
-- there is no bot yet (that arrives with a later plan entry). Its 3 bases exist
-- from the start (setup, for the dummy, is instantaneous), plus a generator and
-- a frontline cannon that fires back across the channel every round -- enough to
-- demonstrate a raised ridge blocking a shot once terrain editing is in play.
-- Placed directly via Board.islandBounds rather than through State.placeStructure
-- so the dummy doesn't need to spend its own Supply or wait out a build time.
local function seedDummyOpponent(config, state, enemy)
	local colStart, _, rowStart, _ = Board.islandBounds(config, enemy)
	-- "Frontline" (closest to the channel) is colStart for B, colEnd for A -- only
	-- B is ever seeded as the dummy in practice (PlanUI always mounts as "A").
	local frontlineCol = colStart

	local function structure(typeId, x, y)
		return { typeId = typeId, x = x, y = y, hp = config.STRUCTURES[typeId].hp, underConstruction = false }
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

function PlanController.new(config, owner)
	local self = setmetatable({}, PlanController)
	self.config = config
	self.owner = owner
	self.enemy = otherOwner(owner)

	local state = State.new(config)
	state, self.dummyCannonCell = seedDummyOpponent(config, state, self.enemy)
	self.state = state
	self.roundStartState = nil
	self.pendingState = nil
	self.pendingCommands = {}
	self.pendingVictory = nil
	self.phase = "setup"

	self.targets = {}
	self.tool = "none"
	self.armedWeaponKey = nil
	self.secondsRemaining = config.PLAN_SECONDS
	self.listeners = {}
	self.tickListeners = {}
	self.resolveListeners = {}
	self.matchEndListeners = {}
	self.misfireMessages = {}
	self._heartbeatConnection = nil
	return self
end

function PlanController:onChange(callback)
	table.insert(self.listeners, callback)
end

-- Fires when a Ready/clock-expiry has computed the round's resolution but before
-- it's applied, so the render layer can animate the volley against the state as
-- it stood going in. `callback(preState, shots, destroyed, newBelief)`: `shots` is
-- every shot that was in range this round (each `{ def, shot, owner, origin, hit }`,
-- `shot` per flight.luau's resolveShot contract); `destroyed` is every structure
-- lost; `newBelief` is the owner's belief map after this round's reveals, for
-- revealing cells as a shot's animation actually crosses them rather than only
-- once the round is fully committed.
function PlanController:onResolve(callback)
	table.insert(self.resolveListeners, callback)
end

-- Fires once, when a round's resolve commits into a victory: `callback(victory,
-- finalState)`. The board/UI stop taking input after this -- the Result screen
-- owns the match from here.
function PlanController:onMatchEnd(callback)
	table.insert(self.matchEndListeners, callback)
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

-- Every cell (x,y)'s footprint covers, keyed the same way rules.luau's own
-- footprintKeys does.
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

-- Cells this round's queued raise/lower/reclaim commands have touched so far --
-- mirrors rules.luau's applyPlayerCommands, which drops a same-round placement
-- on any such cell (§8). The immediate-apply preview has to enforce this too, or
-- it can show a structure placed that resolveRound will silently drop later.
function PlanController:_terrainEditedThisRound()
	local edited = {}
	for _, cmd in ipairs(self.pendingCommands) do
		if cmd.type == "raise" or cmd.type == "lower" or cmd.type == "reclaim" then
			edited[cellKey(cmd.x, cmd.y)] = true
		end
	end
	return edited
end

-- How many bases the player currently has placed -- setup's Ready gate (must be
-- exactly config.NUM_BASES) and its "N/3 placed" display both read this.
function PlanController:countOwnBases()
	local count = 0
	for _, structure in ipairs(self.state.players[self.owner].structures) do
		if structure.typeId == "base" then
			count += 1
		end
	end
	return count
end

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
		table.insert(self.pendingCommands, { type = "target", x = weapon.x, y = weapon.y, targetX = x, targetY = y })
		self:_notify(string.format("target set to (%d, %d)", x, y), true)
		return
	end

	if tool == "bulldoze" then
		local newState, ok, err = State.bulldozeStructure(self.config, self.state, self.owner, x, y)
		if ok then
			self.targets[cellKey(x, y)] = nil
		end
		self:_apply(newState, ok, err, "bulldozed", { type = "bulldoze", x = x, y = y })
		return
	end

	if self.phase == "setup" then
		-- Setup only ever offers base placement + bulldoze (see BuildPalette); a
		-- terrain/reclaim/other-structure tool can't be armed here.
		if string.sub(tool, 1, 6) == "place:" then
			local typeId = string.sub(tool, 7)
			local newState, ok, err = State.placeStructure(self.config, self.state, self.owner, typeId, x, y)
			if ok then
				self.state = newState
				self:_notify("placed " .. typeId, true)
			else
				self:_notify(err, false)
			end
		end
		return
	end

	if tool == "raise" then
		local newState, ok, err = State.raiseTerrain(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "raised terrain", { type = "raise", x = x, y = y })
		return
	end

	if tool == "lower" then
		local newState, ok, err = State.lowerTerrain(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "lowered terrain", { type = "lower", x = x, y = y })
		return
	end

	if tool == "reclaim" then
		local newState, ok, err = State.reclaimLand(self.config, self.state, self.owner, x, y)
		self:_apply(newState, ok, err, "reclaimed land", { type = "reclaim", x = x, y = y })
		return
	end

	if string.sub(tool, 1, 6) == "place:" then
		local typeId = string.sub(tool, 7)
		local editedThisRound = self:_terrainEditedThisRound()
		for _, footKey in ipairs(footprintCellKeys(self.config, typeId, x, y)) do
			if editedThisRound[footKey] then
				self:_notify("cell was terrain-edited this round -- place next round", false)
				return
			end
		end
		local newState, ok, err = State.placeStructure(self.config, self.state, self.owner, typeId, x, y)
		self:_apply(newState, ok, err, "placed " .. typeId, { type = "place", typeId = typeId, x = x, y = y })
		return
	end
end

-- Shared success plumbing for the State.* calls above, which all return
-- (newState, ok, err). `label` is used for the success message only. On success,
-- `command` (rules.luau's command shape) is queued for this round's resolveRound
-- batch -- only ever called while phase == "plan", so setup's own direct calls
-- (handled above) never queue anything.
function PlanController:_apply(newState, ok, err, label, command)
	if ok then
		self.state = newState
		table.insert(self.pendingCommands, command)
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

-- Ends the untimed setup phase once the player has placed exactly NUM_BASES
-- bases (§8), completing them immediately (setup isn't a resolve step -- both
-- sides' bases are meant to already be standing when round 1's PLAN begins) and
-- starting round 1's clock.
function PlanController:startRounds()
	if self.phase ~= "setup" then
		return
	end
	if self:countOwnBases() ~= self.config.NUM_BASES then
		self:_notify(string.format("place exactly %d bases before starting", self.config.NUM_BASES), false)
		return
	end

	local newState = State.completeConstruction(self.config, self.state)
	self.state = newState
	self.roundStartState = newState
	self.pendingCommands = {}
	self.phase = "plan"
	self:_notify(string.format("round %d begins", self.state.round), true)
	self:startClock()
end

-- Dispatches the Ready button per phase: finishes setup, or ends the current
-- PLAN phase early. A no-op during "resolve" and "result".
function PlanController:ready()
	if self.phase == "setup" then
		self:startRounds()
	elseif self.phase == "plan" then
		self:advanceRound()
	end
end

-- The dummy's recurring command batch for one round: its frontline cannon fires
-- straight back across the channel, every round, forever. Non-adaptive by
-- design -- there's no bot AI yet (that's its own later plan entry).
function PlanController:_dummyCommandsForRound()
	local cannon = self.dummyCannonCell
	if not cannon then
		return {}
	end
	local targetX, targetY = mirrorCell(self.roundStartState.board, cannon.x, cannon.y)
	return { { type = "target", x = cannon.x, y = cannon.y, targetX = targetX, targetY = targetY } }
end

-- Ends the current PLAN phase (via Ready or clock expiry) and resolves the round
-- through Rules.resolveRound: both sides' full command batches (this player's
-- pendingCommands, the dummy's scripted one) are applied to the same pre-round
-- snapshot, matching real batch semantics -- true simultaneity, matching
-- rules.luau's own contract. The result is held in `pendingState`/`pendingVictory`
-- rather than applied immediately -- `onResolve` listeners animate the volley
-- first and call `commitResolve` when that animation finishes.
function PlanController:advanceRound()
	if self.phase ~= "plan" then
		return
	end
	self:stopClock()
	self.phase = "resolve"

	local config = self.config
	local owner, enemy = self.owner, self.enemy

	local ownCommands = self.pendingCommands
	local enemyCommands = self:_dummyCommandsForRound()
	local commandsA = (owner == "A") and ownCommands or enemyCommands
	local commandsB = (owner == "A") and enemyCommands or ownCommands

	local newState, _, victory, resolution = Rules.resolveRound(config, self.roundStartState, commandsA, commandsB)

	local ownShots = (owner == "A") and resolution.shotsA or resolution.shotsB
	local enemyShots = (owner == "A") and resolution.shotsB or resolution.shotsA
	local destroyedEnemy = (owner == "A") and resolution.destroyedB or resolution.destroyedA
	local destroyedOwn = (owner == "A") and resolution.destroyedA or resolution.destroyedB

	local preState = resolution.preState
	local ownStructures = preState.players[owner].structures

	-- A targeted weapon that's out of range or can't afford its Energy cost simply
	-- doesn't appear in `ownShots`, with no other signal -- surface why, since that's
	-- otherwise indistinguishable from "nothing happened." Held on self rather than
	-- notified immediately: commitResolve's "round begins" message would otherwise
	-- overwrite this before it's had a chance to be read.
	local firedFrom = {}
	for _, s in ipairs(ownShots) do
		firedFrom[cellKey(s.origin.x, s.origin.y)] = true
	end
	self.misfireMessages = {}
	for _, weapon in ipairs(ownStructures) do
		local def = config.STRUCTURES[weapon.typeId]
		local weaponKey = cellKey(weapon.x, weapon.y)
		local target = self.targets[weaponKey]
		if def.fire_mode and not weapon.underConstruction and target and not firedFrom[weaponKey] then
			local reason = Economy.canAfford(preState.players[owner].resources, { energy = def.energy_cost })
					and "target out of range"
				or "not enough Energy to fire"
			table.insert(self.misfireMessages, string.format("%s at (%d,%d) didn't fire -- %s", weapon.typeId, weapon.x, weapon.y, reason))
		end
	end

	self.pendingState = newState
	self.pendingVictory = victory

	local shots = {}
	for _, s in ipairs(ownShots) do
		table.insert(shots, s)
	end
	for _, s in ipairs(enemyShots) do
		table.insert(shots, s)
	end

	local destroyed = {}
	for _, structure in ipairs(destroyedEnemy) do
		table.insert(destroyed, structure)
	end
	for _, structure in ipairs(destroyedOwn) do
		table.insert(destroyed, structure)
	end

	local newBelief = newState.players[owner].belief

	for _, callback in ipairs(self.resolveListeners) do
		callback(preState, shots, destroyed, newBelief)
	end
end

-- Called by the render layer once the resolve animation finishes: applies the
-- round computed by advanceRound. If it ended the match, hands off to the Result
-- screen via onMatchEnd instead of starting the next PLAN phase.
function PlanController:commitResolve()
	self.state = self.pendingState
	self.pendingState = nil
	self.roundStartState = self.state
	self.pendingCommands = {}

	local victory = self.pendingVictory
	self.pendingVictory = nil

	if victory then
		self.phase = "result"
		for _, callback in ipairs(self.matchEndListeners) do
			callback(victory, self.state)
		end
		return
	end

	self.phase = "plan"
	local message = string.format("round %d begins", self.state.round)
	local ok = true
	if #self.misfireMessages > 0 then
		message = table.concat(self.misfireMessages, "; ")
		ok = false
	end
	self:_notify(message, ok)
	self:startClock()
end

return PlanController
