-- Whole-round resolution. Validates each side's PLAN-phase command batch together
-- (this is where §8's same-round terrain-edit/placement interaction is enforced),
-- then runs the fixed RESOLVE order from §4: terrain, construction, simultaneous
-- volleys, damage, reveals, income, victory check.

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

-- ## PLAN-phase command application ##

local function footprintKeys(config, typeId, x, y)
	local size = config.STRUCTURES[typeId] and config.STRUCTURES[typeId].footprint or 1
	local keys = {}
	for dx = 0, size - 1 do
		for dy = 0, size - 1 do
			table.insert(keys, key(x + dx, y + dy))
		end
	end
	return keys
end

-- Applies one player's whole command batch for the round. Invalid commands are
-- simply dropped (an unaffordable purchase or an out-of-territory edit never took
-- effect) -- surfacing rejection reasons to a player is the future CommandHandler's
-- job (§12), not this pure layer's.
local function applyPlayerCommands(config, state, owner, commands)
	local terrainEditedCells = {}
	for _, cmd in ipairs(commands) do
		if cmd.type == "raise" or cmd.type == "lower" or cmd.type == "reclaim" then
			terrainEditedCells[key(cmd.x, cmd.y)] = true
		end
	end

	local newState = state
	for _, cmd in ipairs(commands) do
		if cmd.type == "place" then
			local blockedByTerrainEdit = false
			for _, footKey in ipairs(footprintKeys(config, cmd.typeId, cmd.x, cmd.y)) do
				if terrainEditedCells[footKey] then
					blockedByTerrainEdit = true
					break
				end
			end
			if not blockedByTerrainEdit then
				newState = State.placeStructure(config, newState, owner, cmd.typeId, cmd.x, cmd.y)
			end
		elseif cmd.type == "bulldoze" then
			newState = State.bulldozeStructure(config, newState, owner, cmd.x, cmd.y)
		elseif cmd.type == "raise" then
			newState = State.raiseTerrain(config, newState, owner, cmd.x, cmd.y)
		elseif cmd.type == "lower" then
			newState = State.lowerTerrain(config, newState, owner, cmd.x, cmd.y)
		elseif cmd.type == "reclaim" then
			newState = State.reclaimLand(config, newState, owner, cmd.x, cmd.y)
		end
	end
	return newState
end

local function extractTargets(commands)
	local targets = {}
	for _, cmd in ipairs(commands) do
		if cmd.type == "target" then
			targets[key(cmd.x, cmd.y)] = { x = cmd.targetX, y = cmd.targetY }
		end
	end
	return targets
end

-- ## Simultaneous volley resolution ##

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
	if def.fire_mode == "arc" then
		for _, offset in ipairs(ORTHOGONAL_OFFSETS) do
			damageCell(impactCell.x + offset[1], impactCell.y + offset[2], def.splash.amount)
		end
	end

	return opponentStructures, destroyedStructures, events, hitPoints
end

-- Resolves everything one player's weapons do this round against the OTHER
-- player's structures as they stood at the START of this resolve step. Both
-- players' calls read that same pre-volley snapshot (see resolveVolleys below), so
-- neither side's fire can be affected by damage the other side lands this round --
-- true simultaneity, including a weapon that is itself destroyed this round still
-- getting its shot off.
local function resolvePlayerVolley(config, board, owner, weapons, targets, resources, opponentStructures)
	local shots = {}
	local destroyedStructures = {}
	local events = {}
	local hitPoints = 0

	for _, weapon in ipairs(weapons) do
		local def = config.STRUCTURES[weapon.typeId]
		if def.fire_mode and not weapon.underConstruction then
			local target = targets[key(weapon.x, weapon.y)]
			if target and Board.ownerOf(board, target.x, target.y) == opponentOf(owner) then
				local cost = { energy = def.energy_cost }
				if Economy.canAfford(resources, cost) then
					local shot = Flight.resolveShot(board, def, weapon.x, weapon.y, target.x, target.y)
					if shot.inRange then
						resources = Economy.spend(resources, cost)
						table.insert(shots, { def = def, shot = shot, owner = owner, origin = { x = weapon.x, y = weapon.y }, hit = false })
						table.insert(events, {
							type = "shot",
							owner = owner,
							weapon = { x = weapon.x, y = weapon.y },
							target = { x = target.x, y = target.y },
							blocked = shot.blocked,
						})

						-- A blocked direct shot impacts terrain for no damage (§10).
						if not (def.fire_mode == "direct" and shot.blocked) then
							local newOpponentStructures, destroyed, damageEvents, damageHitPoints = applyWeaponDamage(config, def, opponentStructures, shot.impactCell)
							opponentStructures = newOpponentStructures
							hitPoints += damageHitPoints
							-- damageEvents[1] is always the primary impact-cell hit (splash
							-- neighbors, if any, follow it) -- that's what "a shot that hit"
							-- means for the Result screen's shot breakdown.
							shots[#shots].hit = damageEvents[1] ~= nil and damageEvents[1].hit or false
							for _, destroyedStructure in ipairs(destroyed) do
								table.insert(destroyedStructures, destroyedStructure)
							end
							for _, damageEvent in ipairs(damageEvents) do
								table.insert(events, damageEvent)
							end
						end
					end
				end
			end
		end
	end

	return opponentStructures, resources, shots, destroyedStructures, events, hitPoints
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

-- Points for newly sighting a live enemy structure -- a cell that wasn't known
-- to hold one (never revealed, revealed as empty/rubble, or last seen mid-
-- construction) and now is. Compares the whole belief map before/after this
-- round's reveals rather than per-shot, so a cell touched by more than one shot
-- this round (or already known) is never double-counted.
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

	-- Rounds elapsed is identical for both players in a single 1v1 match; kept for
	-- fidelity to §5.4's tiebreak chain even though it can never decide anything here.
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

	local graceLimit = config.INCAPACITATION_GRACE_ROUNDS
	local incapA = state.players.A.incapableStreak >= graceLimit
	local incapB = state.players.B.incapableStreak >= graceLimit
	if incapA or incapB then
		if incapA and incapB then
			return { condition = "incapacitation", winner = decideByPoints(config, state) }
		end
		return { condition = "incapacitation", winner = incapA and "B" or "A" }
	end

	if state.round >= config.MAX_ROUNDS then
		return { condition = "round_limit", winner = decideByPoints(config, state) }
	end

	return nil
end

-- ## Round resolution ##

function Rules.resolveRound(config, state, commandsA, commandsB)
	local events = {}

	local newState = applyPlayerCommands(config, state, "A", commandsA)
	newState = applyPlayerCommands(config, newState, "B", commandsB)

	newState = State.completeConstruction(config, newState)
	local preCombatState = newState

	local targetsA = extractTargets(commandsA)
	local targetsB = extractTargets(commandsB)

	local newStructsB, newResourcesA, shotsA, destroyedB, eventsA, hitPointsA = resolvePlayerVolley(
		config,
		newState.board,
		"A",
		newState.players.A.structures,
		targetsA,
		newState.players.A.resources,
		newState.players.B.structures
	)
	local newStructsA, newResourcesB, shotsB, destroyedA, eventsB, hitPointsB = resolvePlayerVolley(
		config,
		newState.board,
		"B",
		newState.players.B.structures,
		targetsB,
		newState.players.B.resources,
		newState.players.A.structures
	)

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
		newBeliefA = Fog.applyReveal(config, newState.board, newStructsB, newBeliefA, s.def, s.shot, destroyedSetB)
	end

	local newBeliefB = newState.players.B.belief
	for _, s in ipairs(shotsB) do
		newBeliefB = Fog.applyReveal(config, newState.board, newStructsA, newBeliefB, s.def, s.shot, destroyedSetA)
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
		destructionPoints = newState.players.A.destructionPoints + destroyPoints(destroyedA, destructionByTypeA),
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
		destructionPoints = newState.players.B.destructionPoints + destroyPoints(destroyedB, destructionByTypeB),
		destructionPointsByType = destructionByTypeB,
		revealPoints = newState.players.B.revealPoints + revealPointsB,
		hitPoints = newState.players.B.hitPoints + hitPointsB,
		structuresLost = newState.players.B.structuresLost + #destroyedB,
		shotsFired = newState.players.B.shotsFired + firedB,
		shotsHit = newState.players.B.shotsHit + hitB,
		shotsBlocked = newState.players.B.shotsBlocked + blockedB,
	})

	newState = State.accrueIncome(config, newState)

	for _, owner in ipairs({ "A", "B" }) do
		local player = newState.players[owner]
		local incap = isIncapableNow(config, player.structures, player.resources) and isUnrecoverable(config, player.structures, player.resources)
		local streak = incap and (player.incapableStreak + 1) or 0
		newState = State.withPlayer(newState, owner, { incapableStreak = streak })
	end

	local victory = Rules.checkVictory(config, newState)
	if victory then
		table.insert(events, { type = "victory", result = victory })
	else
		newState.round = newState.round + 1
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
