-- Real-time tick resolution. Commands (place/bulldoze/raise/lower/reclaim/target)
-- apply immediately and permanently through Rules.applyCommand; Rules.tick advances
-- the match by one fixed heartbeat (config.TICK_SECONDS): construction completion,
-- automatic weapon fire, income, incapacitation, and victory, all evaluated every
-- tick in place of the old once-per-round RESOLVE step order (§4).

local Board = require("./board")
local Economy = require("./economy")
local Structures = require("./structures")
local State = require("./state")
local Flight = require("./flight")
local Fog = require("./fog")

local Rules = {}

local ORTHOGONAL_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function key(x, y)
	return x .. "," .. y
end

local function opponentOf(owner)
	if owner == "A" then
		return "B"
	end
	return "A"
end

-- ## Command application ##
-- Each command applies immediately and permanently on receipt -- no batching, no
-- same-tick conflict rules to enforce, since commands are simply sequential.

function Rules.applyCommand(config, state, owner, cmd)
	if cmd.type == "place" then
		return State.placeStructure(config, state, owner, cmd.typeId, cmd.x, cmd.y)
	elseif cmd.type == "bulldoze" then
		return State.bulldozeStructure(config, state, owner, cmd.x, cmd.y)
	elseif cmd.type == "raise" then
		return State.raiseTerrain(config, state, owner, cmd.x, cmd.y)
	elseif cmd.type == "lower" then
		return State.lowerTerrain(config, state, owner, cmd.x, cmd.y)
	elseif cmd.type == "reclaim" then
		return State.reclaimLand(config, state, owner, cmd.x, cmd.y)
	elseif cmd.type == "target" then
		return State.setTarget(config, state, owner, cmd.x, cmd.y, cmd.targetX, cmd.targetY)
	elseif cmd.type == "autoFire" then
		return State.setAutoFire(config, state, owner, cmd.x, cmd.y, cmd.enabled)
	end
	return state, false, "unknown command type"
end

-- ## Automatic weapon fire ##

local function applyWeaponDamage(config, def, opponentStructures, impactCell)
	local destroyedStructures = {}
	local events = {}
	local hitPoints = 0

	local function damageCell(x, y, amount)
		-- Looked up before damaging so a hit that also destroys the structure
		-- still knows what type it was hitting (Structures.damage's own return
		-- only carries a typeId on the destroyed branch).
		local target = Structures.at(config.STRUCTURES, opponentStructures, x, y)
		local newList, hit, destroyed, destroyedStructure = Structures.damage(config, opponentStructures, x, y, amount)
		opponentStructures = newList
		if hit and target and not target.underConstruction then
			hitPoints += config.POINTS.hit[target.typeId]
		end
		if destroyed then
			table.insert(destroyedStructures, destroyedStructure)
		end
		table.insert(events, { type = "damage", x = x, y = y, amount = amount, hit = hit, destroyed = destroyed })
	end

	damageCell(impactCell.x, impactCell.y, def.damage)
	if def.splash then
		for _, offset in ipairs(ORTHOGONAL_OFFSETS) do
			damageCell(impactCell.x + offset[1], impactCell.y + offset[2], def.splash.amount)
		end
	end

	return opponentStructures, destroyedStructures, events, hitPoints
end

-- Decides which of `weapons` (one player's own, as they stood at the start of this
-- tick) fire this tick: off cooldown, targeted into the opponent's territory, in
-- range, and affordable. Resolved purely from the owner's own state and the board
-- -- shot geometry never depends on the opponent's structures, only the damage step
-- does -- so this can run for both players against the same pre-tick snapshot
-- without either side's fire affected by the other's, including a weapon that is
-- itself destroyed this tick still getting its shot off.
local function planShots(config, board, owner, weapons, resources, now)
	local firings = {}
	for _, weapon in ipairs(weapons) do
		local def = config.STRUCTURES[weapon.typeId]
		if def.fire_mode and not weapon.underConstruction and weapon.target and now >= (weapon.nextFireAt or 0) then
			local target = weapon.target
			if Board.ownerOf(board, target.x, target.y) == opponentOf(owner) then
				local cost = { energy = def.energy_cost }
				if Economy.canAfford(resources, cost) then
					local shot = Flight.resolveShot(board, def, weapon.x, weapon.y, target.x, target.y)
					if shot.inRange then
						resources = Economy.spend(resources, cost)
						table.insert(firings, { def = def, shot = shot, owner = owner, origin = { x = weapon.x, y = weapon.y }, target = target })
					end
				end
			end
		end
	end
	return firings, resources
end

-- Applies one side's planned firings to the opponent's structures (as they stood at
-- the start of this tick).
local function applyFirings(config, firings, opponentStructures)
	local shots = {}
	local destroyedStructures = {}
	local events = {}
	local hitPoints = 0

	for _, firing in ipairs(firings) do
		local shot = { def = firing.def, shot = firing.shot, owner = firing.owner, origin = firing.origin, hit = false }
		table.insert(shots, shot)
		table.insert(events, {
			type = "shot",
			owner = firing.owner,
			weapon = firing.origin,
			target = firing.target,
			blocked = firing.shot.blocked,
		})

		-- A blocked direct shot impacts terrain for no damage (§10).
		if not (firing.def.fire_mode == "direct" and firing.shot.blocked) then
			local newOpponentStructures, destroyed, damageEvents, damageHitPoints = applyWeaponDamage(config, firing.def, opponentStructures, firing.shot.impactCell)
			opponentStructures = newOpponentStructures
			hitPoints += damageHitPoints
			-- damageEvents[1] is always the primary impact-cell hit (splash
			-- neighbors, if any, follow it) -- that's what "a shot that hit"
			-- means for the Result screen's shot breakdown.
			shot.hit = damageEvents[1] ~= nil and damageEvents[1].hit or false
			for _, destroyedStructure in ipairs(destroyed) do
				table.insert(destroyedStructures, destroyedStructure)
			end
			for _, damageEvent in ipairs(damageEvents) do
				table.insert(events, damageEvent)
			end
		end
	end

	return opponentStructures, destroyedStructures, events, hitPoints, shots
end

-- Puts fired weapons on cooldown, applied after the opponent's simultaneous damage
-- so a weapon destroyed this same tick is simply gone rather than resurrected with
-- a cooldown. Looked up by cell rather than by index since the damage pass may have
-- removed or reordered entries. Also clears the target unless autoFire is set --
-- single shot by default (§18): a fired weapon goes idle until re-targeted, rather
-- than firing again on its own next cooldown.
local function applyCooldowns(config, list, firings, now)
	for _, firing in ipairs(firings) do
		local x, y = firing.origin.x, firing.origin.y
		local target = Structures.at(config.STRUCTURES, list, x, y)
		if target then
			local newList = {}
			for _, structure in ipairs(list) do
				if structure == target then
					local updated = table.clone(structure)
					updated.nextFireAt = now + firing.def.cooldown_seconds
					if not updated.autoFire then
						updated.target = nil
					end
					table.insert(newList, updated)
				else
					table.insert(newList, structure)
				end
			end
			list = newList
		end
	end
	return list
end

local function destroyedCellSet(config, destroyedStructures)
	local set = {}
	for _, structure in ipairs(destroyedStructures) do
		for _, cell in ipairs(Structures.occupiedCells(config.STRUCTURES, structure)) do
			set[key(cell.x, cell.y)] = true
		end
	end
	return set
end

-- ## Scoring (§5.4) ##

local function standingPoints(config, playerState)
	local total = 0
	for _, structure in ipairs(playerState.structures) do
		if not structure.underConstruction then
			total += config.POINTS.standing[structure.typeId]
		end
	end
	return total
end

function Rules.finalScore(config, playerState)
	return playerState.destructionPoints + standingPoints(config, playerState) + playerState.revealPoints + playerState.hitPoints
end

-- The Result screen's aggregate breakdown (§6.3), for either player -- counts
-- and point totals only, never the raw `structures`/`belief` a playerState
-- otherwise carries. Session 007's local Result screen read those directly
-- off `finalState.players[enemy]` because everything was still one client's
-- local state; Session 008's server-authoritative version can't do that for
-- the opponent's column without handing the client the opponent's real
-- structure positions in the same remote payload that ends the match (§12).
function Rules.summary(config, playerState)
	local standingPointsByType = {}
	local structuresStanding = 0
	for typeId in pairs(config.STRUCTURES) do
		standingPointsByType[typeId] = 0
	end
	for _, structure in ipairs(playerState.structures) do
		if not structure.underConstruction then
			standingPointsByType[structure.typeId] += config.POINTS.standing[structure.typeId]
			structuresStanding += 1
		end
	end

	local cellsRevealed = 0
	for _ in pairs(playerState.belief) do
		cellsRevealed += 1
	end

	return {
		finalScore = Rules.finalScore(config, playerState),
		destructionPointsByType = playerState.destructionPointsByType,
		standingPointsByType = standingPointsByType,
		revealPoints = playerState.revealPoints,
		hitPoints = playerState.hitPoints,
		structuresBuilt = playerState.structuresBuilt,
		structuresLost = playerState.structuresLost,
		structuresStanding = structuresStanding,
		shotsFired = playerState.shotsFired,
		shotsHit = playerState.shotsHit,
		shotsBlocked = playerState.shotsBlocked,
		cellsRevealed = cellsRevealed,
	}
end

-- Points for newly sighting a live enemy structure -- a cell that wasn't known
-- to hold one (never revealed, revealed as empty/rubble, or last seen mid-
-- construction) and now is. Compares the whole belief map before/after this
-- tick's reveals rather than per-shot, so a cell touched by more than one shot
-- this tick (or already known) is never double-counted.
local function revealPointsEarned(config, oldBelief, newBelief)
	local points = 0
	for cellKey, cell in pairs(newBelief) do
		if cell.typeId and not cell.underConstruction then
			local old = oldBelief[cellKey]
			local wasKnownLive = old and old.typeId and not old.underConstruction
			if not wasKnownLive then
				points += config.POINTS.reveal[cell.typeId]
			end
		end
	end
	return points
end

local function decideByPoints(config, state)
	local scoreA = Rules.finalScore(config, state.players.A)
	local scoreB = Rules.finalScore(config, state.players.B)
	if scoreA ~= scoreB then
		return (scoreA > scoreB) and "A" or "B"
	end

	local lostA = state.players.A.structuresLost
	local lostB = state.players.B.structuresLost
	if lostA ~= lostB then
		return (lostA < lostB) and "A" or "B"
	end

	-- Elapsed match time is identical for both players in a single 1v1 match; kept
	-- for fidelity to §5.4's tiebreak chain even though it can never decide anything
	-- here.
	return nil
end

-- ## Incapacitation (§5.2) ##

local function liveWeaponDefs(config, structures)
	local defs = {}
	for _, structure in ipairs(structures) do
		local def = config.STRUCTURES[structure.typeId]
		if def.fire_mode and not structure.underConstruction then
			table.insert(defs, def)
		end
	end
	return defs
end

local function isIncapableNow(config, structures, resources)
	local weapons = liveWeaponDefs(config, structures)
	if #weapons == 0 then
		return true
	end

	local cheapest = math.huge
	for _, def in ipairs(weapons) do
		cheapest = math.min(cheapest, def.energy_cost)
	end
	return resources.energy < cheapest
end

local function isUnrecoverable(config, structures, resources)
	for _, structure in ipairs(structures) do
		if structure.typeId == "generator" then
			return false
		end
	end

	if Economy.energyIncome(config, 0) > 0 then
		return false
	end
	if resources.supply >= config.STRUCTURES.generator.supply_cost then
		return false
	end

	local cheapestWeaponCost = math.huge
	for _, def in pairs(config.STRUCTURES) do
		if def.fire_mode then
			cheapestWeaponCost = math.min(cheapestWeaponCost, def.supply_cost)
		end
	end
	if resources.supply >= cheapestWeaponCost then
		return false
	end

	return true
end

-- ## Victory (§5) ##

function Rules.checkVictory(config, state)
	local basesA = Structures.countLive(state.players.A.structures, "base")
	local basesB = Structures.countLive(state.players.B.structures, "base")
	if basesA == 0 or basesB == 0 then
		if basesA == 0 and basesB == 0 then
			return { condition = "base_elimination", winner = decideByPoints(config, state) }
		end
		return { condition = "base_elimination", winner = (basesA == 0) and "B" or "A" }
	end

	-- Restates the old round-streak in time terms: a player is only eliminated once
	-- they've been continuously incapable and unrecoverable for the whole grace
	-- window, not just at the instant they first become so.
	local function graceExpired(playerState)
		return playerState.incapableSince ~= nil and (state.elapsed - playerState.incapableSince) >= config.INCAPACITATION_GRACE_SECONDS
	end
	local incapA = graceExpired(state.players.A)
	local incapB = graceExpired(state.players.B)
	if incapA or incapB then
		-- Decided on points like every other non-elimination ending, not an
		-- automatic win for the other side -- a player can still be ahead on
		-- score (destruction/standing/reveal/hit) despite being the one who ran
		-- out of Energy, and that should still win them the match.
		return { condition = "incapacitation", winner = decideByPoints(config, state) }
	end

	if state.elapsed >= config.MATCH_SECONDS then
		return { condition = "time_limit", winner = decideByPoints(config, state) }
	end

	return nil
end

-- ## Tick resolution ##

function Rules.tick(config, state)
	local events = {}
	local now = state.elapsed

	local newState = State.completeConstruction(config, state)
	local preCombatState = newState

	local structsA0 = newState.players.A.structures
	local structsB0 = newState.players.B.structures

	local firingsA, newResourcesA = planShots(config, newState.board, "A", structsA0, newState.players.A.resources, now)
	local firingsB, newResourcesB = planShots(config, newState.board, "B", structsB0, newState.players.B.resources, now)

	local newStructsB, destroyedB, eventsA, hitPointsA, shotsA = applyFirings(config, firingsA, structsB0)
	local newStructsA, destroyedA, eventsB, hitPointsB, shotsB = applyFirings(config, firingsB, structsA0)

	newStructsA = applyCooldowns(config, newStructsA, firingsA, now)
	newStructsB = applyCooldowns(config, newStructsB, firingsB, now)

	for _, e in ipairs(eventsA) do
		table.insert(events, e)
	end
	for _, e in ipairs(eventsB) do
		table.insert(events, e)
	end

	local destroyedSetA = destroyedCellSet(config, destroyedA)
	local destroyedSetB = destroyedCellSet(config, destroyedB)

	local newBeliefA = newState.players.A.belief
	for _, s in ipairs(shotsA) do
		newBeliefA = Fog.applyReveal(config, newState.board, newStructsB, newBeliefA, s.def, s.shot, s.origin, destroyedSetB)
	end

	local newBeliefB = newState.players.B.belief
	for _, s in ipairs(shotsB) do
		newBeliefB = Fog.applyReveal(config, newState.board, newStructsA, newBeliefB, s.def, s.shot, s.origin, destroyedSetA)
	end

	local revealPointsA = revealPointsEarned(config, newState.players.A.belief, newBeliefA)
	local revealPointsB = revealPointsEarned(config, newState.players.B.belief, newBeliefB)

	local function destroyPoints(destroyed, byType)
		local total = 0
		for _, structure in ipairs(destroyed) do
			if not structure.underConstruction then
				local points = config.POINTS.destroy[structure.typeId]
				total += points
				byType[structure.typeId] += points
			end
		end
		return total
	end

	-- Fired/hit/blocked feed the Result screen's per-player shot breakdown (§6.3).
	-- "Hit" means the shot's primary impact cell actually damaged something; a
	-- blocked direct shot is never a hit (it never reaches its target).
	local function shotStats(shots)
		local fired, hit, blocked = 0, 0, 0
		for _, s in ipairs(shots) do
			fired += 1
			if s.hit then
				hit += 1
			end
			if s.shot.blocked then
				blocked += 1
			end
		end
		return fired, hit, blocked
	end

	local firedA, hitA, blockedA = shotStats(shotsA)
	local firedB, hitB, blockedB = shotStats(shotsB)

	local destructionByTypeA = table.clone(newState.players.A.destructionPointsByType)
	local destructionByTypeB = table.clone(newState.players.B.destructionPointsByType)

	newState = State.withPlayer(newState, "A", {
		structures = newStructsA,
		resources = newResourcesA,
		belief = newBeliefA,
		destructionPoints = newState.players.A.destructionPoints + destroyPoints(destroyedB, destructionByTypeA),
		destructionPointsByType = destructionByTypeA,
		revealPoints = newState.players.A.revealPoints + revealPointsA,
		hitPoints = newState.players.A.hitPoints + hitPointsA,
		structuresLost = newState.players.A.structuresLost + #destroyedA,
		shotsFired = newState.players.A.shotsFired + firedA,
		shotsHit = newState.players.A.shotsHit + hitA,
		shotsBlocked = newState.players.A.shotsBlocked + blockedA,
	})
	newState = State.withPlayer(newState, "B", {
		structures = newStructsB,
		resources = newResourcesB,
		belief = newBeliefB,
		destructionPoints = newState.players.B.destructionPoints + destroyPoints(destroyedA, destructionByTypeB),
		destructionPointsByType = destructionByTypeB,
		revealPoints = newState.players.B.revealPoints + revealPointsB,
		hitPoints = newState.players.B.hitPoints + hitPointsB,
		structuresLost = newState.players.B.structuresLost + #destroyedB,
		shotsFired = newState.players.B.shotsFired + firedB,
		shotsHit = newState.players.B.shotsHit + hitB,
		shotsBlocked = newState.players.B.shotsBlocked + blockedB,
	})

	newState = State.tickAccrue(config, newState)

	for _, owner in ipairs({ "A", "B" }) do
		local player = newState.players[owner]
		local incap = isIncapableNow(config, player.structures, player.resources) and isUnrecoverable(config, player.structures, player.resources)
		local since = incap and (player.incapableSince or now) or nil
		newState = State.withPlayer(newState, owner, { incapableSince = since })
	end

	local victory = Rules.checkVictory(config, newState)
	if victory then
		table.insert(events, { type = "victory", result = victory })
	else
		newState.elapsed = newState.elapsed + config.TICK_SECONDS
	end

	-- Raw per-side shot/destruction data, for a client that wants to animate the
	-- volley precisely (impact cells, beam paths, blocked shots) rather than just
	-- react to the flattened event log.
	local resolution = {
		preState = preCombatState,
		shotsA = shotsA,
		shotsB = shotsB,
		destroyedA = destroyedA,
		destroyedB = destroyedB,
	}

	return newState, events, victory, resolution
end

return Rules
