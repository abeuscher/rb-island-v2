-- Declared weapon roles ("Sim weapon roles and loadout matrix" plan entry):
-- a category tag per weapon type, plus which other categories it holds fire
-- for. Stays sim-only rather than promoted to src/shared/archetypeKit.luau --
-- server/Bot.luau doesn't need this yet (deliberately deferred, same call
-- Session 016 made for scout-drone placement on the bot), and
-- Kit.chooseTargets's own new `holdFire` parameter is a plain typeId set with
-- no category concept baked in, so promoting later needs no rework there.
--
-- Today's one real use (criterion b): a cheap weapon category
-- (direct-damage) stands down once a costlier one (arc-finisher) exists and
-- there's an actual plotted base or generator worth its Energy -- so Energy
-- banks toward the weapon that needs more of it per shot instead of the two
-- competing for the same shared pool, but a cheap weapon still scouts freely
-- until there's something worth saving Energy for. Generalized from
-- sim/archetypes/recon.luau's old inline `hasMortar`/`focus` check into
-- something every archetype gets by calling Loadout.holdFireSet instead of
-- hand-writing its own version.

local Kit = require("../src/shared/archetypeKit")

local Roles = {
	generator = { category = "support-economy", standDownIfPresent = {} },
	cannon = { category = "direct-damage", standDownIfPresent = { "arc-finisher" } },
	mortar = { category = "arc-finisher", standDownIfPresent = {} },
	missile = { category = "arc-finisher", standDownIfPresent = {} },
	scout = { category = "recon", standDownIfPresent = {} },
}

local Loadout = { Roles = Roles }

-- typeId -> true for every live/pending weapon that should hold fire this
-- decide() cycle: its role declares a category it defers to, that category
-- is present among `weapons`, and a base or generator is already plotted --
-- no point banking Energy for a costlier weapon that has nothing to shoot at
-- yet either.
function Loadout.holdFireSet(config, view, pendingWeapons)
	local weapons = Kit.liveStructures(view)
	if pendingWeapons then
		for _, weapon in ipairs(pendingWeapons) do
			table.insert(weapons, weapon)
		end
	end

	local present = {}
	for _, weapon in ipairs(weapons) do
		local role = Roles[weapon.typeId]
		if role then
			present[role.category] = true
		end
	end

	local hasPlottedTarget = false
	for _, s in ipairs(Kit.plottedEnemyStructures(view)) do
		if s.typeId == "base" or s.typeId == "generator" then
			hasPlottedTarget = true
			break
		end
	end

	local holdFire = {}
	if hasPlottedTarget then
		for _, weapon in ipairs(weapons) do
			local role = Roles[weapon.typeId]
			if role then
				for _, category in ipairs(role.standDownIfPresent) do
					if present[category] then
						holdFire[weapon.typeId] = true
					end
				end
			end
		end
	end
	return holdFire
end

return Loadout
