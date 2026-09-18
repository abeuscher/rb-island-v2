-- Client-side plan-phase controller. Holds a local MatchState (no server yet --
-- see Session 005's brief) and exposes the commands the plan-phase UI drives:
-- build/bulldoze, terrain edit/reclaim, target assignment, and the round clock.
-- Also owns resolving each round's volley (advanceRound/commitResolve below)
-- against a static dummy opponent seeded onto the enemy island.
--
-- Target assignment still has no equivalent in the shared rules core -- rules.luau
-- expects targets in this same shape (a map keyed by the firing structure's
-- origin cell), but nothing there tracks assignment itself -- so it stays local
-- UI state here.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local State = require(ReplicatedStorage.Shared.state)
local Rules = require(ReplicatedStorage.Shared.rules)
local Fog = require(ReplicatedStorage.Shared.fog)
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

local function ownedLandCells(board, owner)
	local cells = {}
	for x = 1, board.width do
		for y = 1, board.height do
			if Board.ownerOf(board, x, y) == owner and Board.isLand(board, x, y) then
				table.insert(cells, { x = x, y = y })
			end
		end
	end
	table.sort(cells, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.y < b.y
	end)
	return cells
end

-- The board is mirror-symmetric across the channel (see board.luau's construction),
-- so reflecting a cell's x through the board's width lines it up with the cell
-- directly opposite it on the other island.
local function mirrorCell(board, x, y)
	return board.width + 1 - x, y
end

-- Seeds a static, already-built enemy layout to have something to shoot at -- there
-- is no bot yet (that arrives with a later plan entry), so this dummy exists only
-- to give the resolve-phase volley/damage/reveal loop two live sides to animate.
-- Its cannon fires straight back across the channel every round, which is enough
-- to demonstrate a raised ridge blocking a shot once terrain editing is in play.
local function seedDummyOpponent(config, state, enemy)
	local cells = ownedLandCells(state.board, enemy)
	local cannonCell = cells[1]
	local generatorCell = cells[math.floor(#cells / 2)]

	local newState = State.withPlayer(state, enemy, {
		structures = {
			{ typeId = "cannon", x = cannonCell.x, y = cannonCell.y, hp = config.STRUCTURES.cannon.hp, underConstruction = false },
			{ typeId = "generator", x = generatorCell.x, y = generatorCell.y, hp = config.STRUCTURES.generator.hp, underConstruction = false },
		},
	})

	local targetX, targetY = mirrorCell(state.board, cannonCell.x, cannonCell.y)
	local targets = { [cellKey(cannonCell.x, cannonCell.y)] = { x = targetX, y = targetY } }

	return newState, targets
end

function PlanController.new(config, owner)
	local self = setmetatable({}, PlanController)
	self.config = config
	self.owner = owner
	self.enemy = otherOwner(owner)

	local state = State.new(config)
	state, self.dummyTargets = seedDummyOpponent(config, state, self.enemy)
	self.state = state
	self.pendingState = nil
	self.phase = "plan"

	self.targets = {}
	self.tool = "none"
	self.armedWeaponKey = nil
	self.secondsRemaining = config.PLAN_SECONDS
	self.listeners = {}
	self.tickListeners = {}
	self.resolveListeners = {}
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
-- every shot that was in range this round (each `{ def, shot, owner, origin }`,
-- `shot` per flight.luau's resolveShot contract); `destroyed` is every structure
-- lost; `newBelief` is the owner's belief map after this round's reveals, for
-- revealing cells as a shot's animation actually crosses them rather than only
-- once the round is fully committed.
function PlanController:onResolve(callback)
	table.insert(self.resolveListeners, callback)
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

function PlanController:handleBoardClick(x, y)
	if self.phase == "resolve" then
		return
	end

	local tool = self.tool

	if tool == "target" then
		if not self.armedWeaponKey then
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

-- Ends the current PLAN phase (via Ready or clock expiry) and resolves the round:
-- construction completes, both sides' volleys fire against the pre-resolve
-- snapshot (true simultaneity, matching rules.luau's own resolveRound), damage and
-- reveals apply, and income accrues. The result is held in `pendingState` rather
-- than applied immediately -- `onResolve` listeners animate the volley first and
-- call `commitResolve` when that animation finishes. There's still no full
-- rules.resolveRound batch here: PlanController applies commands immediately
-- rather than batching them for resolve, so only the flight/damage/reveal pieces
-- are wired in, not the whole orchestration (see the Open Gate decision).
function PlanController:advanceRound()
	if self.phase == "resolve" then
		return
	end
	self:stopClock()
	self.phase = "resolve"

	local config = self.config
	local owner, enemy = self.owner, self.enemy
	local preState = State.completeConstruction(config, self.state)

	local ownStructures = preState.players[owner].structures
	local enemyStructures = preState.players[enemy].structures

	local newEnemyStructures, newOwnResources, ownShots, destroyedEnemy = Rules.resolvePlayerVolley(
		config,
		preState.board,
		owner,
		ownStructures,
		self.targets,
		preState.players[owner].resources,
		enemyStructures
	)
	local newOwnStructures, newEnemyResources, enemyShots, destroyedOwn = Rules.resolvePlayerVolley(
		config,
		preState.board,
		enemy,
		enemyStructures,
		self.dummyTargets,
		preState.players[enemy].resources,
		ownStructures
	)

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

	local destroyedEnemyCells = Rules.destroyedCellSet(config, destroyedEnemy)
	local newBelief = preState.players[owner].belief
	for _, s in ipairs(ownShots) do
		newBelief = Fog.applyReveal(config, preState.board, newEnemyStructures, newBelief, s.def, s.shot, destroyedEnemyCells)
	end

	local newState = State.withPlayer(preState, owner, {
		structures = newOwnStructures,
		resources = newOwnResources,
		belief = newBelief,
	})
	newState = State.withPlayer(newState, enemy, {
		structures = newEnemyStructures,
		resources = newEnemyResources,
	})
	newState = State.accrueIncome(config, newState)
	newState = table.clone(newState)
	newState.round = newState.round + 1
	self.pendingState = newState

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

	for _, callback in ipairs(self.resolveListeners) do
		callback(preState, shots, destroyed, newBelief)
	end
end

-- Called by the render layer once the resolve animation finishes: applies the
-- round computed by advanceRound and starts the next PLAN phase.
function PlanController:commitResolve()
	self.state = self.pendingState
	self.pendingState = nil
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
