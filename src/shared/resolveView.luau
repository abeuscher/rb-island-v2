-- One owner's animatable slice of a round's resolution (rules.luau's
-- resolveRound fourth return value): every shot from both sides landing on
-- the shared board, every structure destroyed on either side this round, and
-- why any of the owner's own targeted weapons silently failed to fire.
--
-- A firing weapon's own cell is part of its shot -- an incoming shot is only
-- ever sent to the player it's fired at, and only for the weapons that
-- actually fired this round, the same muzzle-flash-is-visible precedent the
-- single-player dummy already set (Sessions 006-007). Nothing here ever
-- carries a structure that didn't fire and wasn't hit.
--
-- `targets` is the owner's own persisted weapon-target assignments (session
-- state, not MatchState -- rules.luau only ever sees a target if it's resent
-- as a command the same round, per §8's command-batch contract), used only to
-- explain a weapon that had a target but produced no shot.

local Economy = require("./economy")

local ResolveView = {}

local function cellKey(x, y)
	return x .. "," .. y
end

function ResolveView.new(config, owner, resolution, targets, newBelief)
	local ownShots = (owner == "A") and resolution.shotsA or resolution.shotsB
	local enemyShots = (owner == "A") and resolution.shotsB or resolution.shotsA
	local destroyedEnemy = (owner == "A") and resolution.destroyedB or resolution.destroyedA
	local destroyedOwn = (owner == "A") and resolution.destroyedA or resolution.destroyedB

	local preState = resolution.preState
	local ownStructures = preState.players[owner].structures

	local firedFrom = {}
	for _, s in ipairs(ownShots) do
		firedFrom[cellKey(s.origin.x, s.origin.y)] = true
	end

	local misfireMessages = {}
	for _, weapon in ipairs(ownStructures) do
		local def = config.STRUCTURES[weapon.typeId]
		local weaponKey = cellKey(weapon.x, weapon.y)
		local target = targets[weaponKey]
		if def.fire_mode and not weapon.underConstruction and target and not firedFrom[weaponKey] then
			local reason = Economy.canAfford(preState.players[owner].resources, { energy = def.energy_cost })
					and "target out of range"
				or "not enough Energy to fire"
			table.insert(misfireMessages, string.format("%s at (%d,%d) didn't fire -- %s", weapon.typeId, weapon.x, weapon.y, reason))
		end
	end

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

	return {
		board = preState.board,
		shots = shots,
		destroyed = destroyed,
		misfireMessages = misfireMessages,
		newBelief = newBelief,
	}
end

return ResolveView
