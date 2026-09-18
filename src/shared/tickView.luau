-- One player's animatable slice of a tick's resolution (rules.luau's Rules.tick
-- fourth return value): every shot from both sides landing on the shared board
-- this tick, and every structure destroyed on either side this tick. Replaces
-- Session 008's resolveView.luau now that resolution happens every tick instead
-- of once per round -- same redaction shape (see DECISIONS.md's "an incoming
-- shot reveals its own firing weapon's cell" call, which still holds), just
-- without the misfire-explanation concept a per-round PLAN commitment needed:
-- a weapon that can't fire this tick simply tries again next tick, with no
-- round boundary to explain itself at.

local TickView = {}

function TickView.new(owner, resolution, newBelief)
	local ownShots = (owner == "A") and resolution.shotsA or resolution.shotsB
	local enemyShots = (owner == "A") and resolution.shotsB or resolution.shotsA
	local destroyedEnemy = (owner == "A") and resolution.destroyedB or resolution.destroyedA
	local destroyedOwn = (owner == "A") and resolution.destroyedA or resolution.destroyedB

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
		shots = shots,
		destroyed = destroyed,
		newBelief = newBelief,
	}
end

return TickView
