local t = require("./testkit")
local config = require("../src/shared/config")
local Board = require("../src/shared/board")
local State = require("../src/shared/state")
local Rules = require("../src/shared/rules")

local function withBase(x, y)
	return { typeId = "base", x = x, y = y, hp = config.STRUCTURES.base.hp, underConstruction = false }
end

-- Shrinks build time and cannon/missile/scout cooldown to one tick each so
-- combat tests don't need dozens of Rules.tick calls to get a weapon built and
-- firing repeatedly.
local function fastConfig()
	local c = table.clone(config)
	c.STRUCTURES = table.clone(config.STRUCTURES)
	c.STRUCTURES.cannon = table.clone(config.STRUCTURES.cannon)
	c.STRUCTURES.cannon.cooldown_seconds = c.TICK_SECONDS
	c.STRUCTURES.missile = table.clone(config.STRUCTURES.missile)
	c.STRUCTURES.missile.cooldown_seconds = c.TICK_SECONDS
	c.STRUCTURES.scout = table.clone(config.STRUCTURES.scout)
	c.STRUCTURES.scout.cooldown_seconds = c.TICK_SECONDS
	c.BUILD_SECONDS = c.TICK_SECONDS
	return c
end

local function advanceTicks(cfg, state, n)
	local victory
	for _ = 1, n do
		state, _, victory = Rules.tick(cfg, state)
		if victory then
			break
		end
	end
	return state, victory
end

t.test("commands apply immediately and permanently, so a terrain edit and a placement in sequence both take effect (no batching)", function()
	local state = State.new(config)
	state.elapsed = config.UNLOCK_TIME.terrain_edit
	state = State.withPlayer(state, "A", { resources = { supply = 100, energy = 10 } })

	local afterRaise = Rules.applyCommand(config, state, "A", { type = "raise", x = 10, y = 10 })
	local afterPlace = Rules.applyCommand(config, afterRaise, "A", { type = "place", typeId = "generator", x = 10, y = 10 })

	t.expectEqual(Board.elevationAt(afterPlace.board, 10, 10), 1)
	t.expectEqual(#afterPlace.players.A.structures, 1)
end)

t.test("base elimination: a player with zero bases loses immediately", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = {} })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
end)

t.test("simultaneous mutual base elimination is decided on points, not treated as a draw by default", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = {}, destructionPoints = 100 })
	state = State.withPlayer(state, "B", { structures = {}, destructionPoints = 50 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
end)

t.test("a fully tied mutual elimination is a draw", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = {}, destructionPoints = 50, structuresLost = 2 })
	state = State.withPlayer(state, "B", { structures = {}, destructionPoints = 50, structuresLost = 2 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, nil)
end)

t.test("time limit: the higher score wins if the match clock runs out with no elimination", function()
	local state = State.new(config)
	state.elapsed = config.MATCH_SECONDS
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) }, destructionPoints = 100 })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, destructionPoints = 50 })

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "time_limit")
	t.expectEqual(victory.winner, "A")
end)

t.test("incapacitation: the grace window must fully expire before it can end the match", function()
	-- Zeroing Supply income and starting Supply isolates the "unrecoverable" check
	-- from ordinary accrual, which would otherwise refill B past every threshold
	-- this test cares about. A short grace window keeps the tick loop small while
	-- still exercising the real elapsed-time mechanism, not just its formula.
	local incapConfig = table.clone(config)
	incapConfig.SUPPLY_PER_SECOND = 0
	incapConfig.STARTING_SUPPLY = 0
	incapConfig.INCAPACITATION_GRACE_SECONDS = 2 * config.TICK_SECONDS

	local state = State.new(incapConfig)
	state = State.withPlayer(state, "A", {
		structures = { withBase(6, 7), { typeId = "cannon", x = 6, y = 9, hp = config.STRUCTURES.cannon.hp, underConstruction = false } },
	})
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local afterTick1, victory1 = advanceTicks(incapConfig, state, 1)
	t.expectEqual(victory1, nil)
	t.expectTrue(afterTick1.players.B.incapableSince ~= nil)

	local afterTick2, victory2 = advanceTicks(incapConfig, afterTick1, 1)
	t.expectEqual(victory2, nil)

	local _, victory3 = advanceTicks(incapConfig, afterTick2, 1)
	t.expectTrue(victory3 ~= nil)
	t.expectEqual(victory3.condition, "incapacitation")
	t.expectEqual(victory3.winner, "A")
end)

t.test("incapacitation is decided on points, not an automatic win for the other side", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	-- B is the incapacitated side here, but still holds a big enough points lead
	-- (from earlier destruction/reveal/hit) that it should still win the match --
	-- running out of Energy isn't itself a loss condition once points disagree.
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, destructionPoints = 200, incapableSince = 0 })
	state.elapsed = config.INCAPACITATION_GRACE_SECONDS

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "incapacitation")
	t.expectEqual(victory.winner, "B")
end)

t.test("Rules.tick fires an off-cooldown weapon automatically once its target and construction are set, and tracks fired/hit/blocked shots", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", {
		structures = { withBase(24, 10), { typeId = "cannon", x = 20, y = 10, hp = cfg.STRUCTURES.cannon.hp, underConstruction = false } },
	})

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	-- Tick 1: construction not ready yet (readyAt is one tick out). Tick 2: it
	-- completes and, being off cooldown and targeted, fires this same tick (§8:
	-- build completes, then the weapon can act, same tick).
	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local newState, _, _, resolution = Rules.tick(cfg, warmedUp)

	t.expectEqual(newState.players.A.shotsFired, 1)
	t.expectEqual(newState.players.A.shotsHit, 1)
	t.expectEqual(newState.players.A.shotsBlocked, 0)
	t.expectEqual(newState.players.A.destructionPoints, 0) -- didn't destroy the base outright
	t.expectEqual(newState.players.B.shotsFired, 0) -- B's cannon was never given a target

	t.expectEqual(resolution.preState.players.A.structures[2].typeId, "cannon")
	t.expectEqual(resolution.preState.players.A.structures[2].underConstruction, false)
	t.expectEqual(#resolution.shotsA, 1)
	t.expectEqual(resolution.shotsA[1].hit, true)
	t.expectEqual(#resolution.shotsB, 0)
end)

t.test("Rules.tick awards destruction points to the attacker, not to the side that lost the structure", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", {
		structures = { withBase(26, 12), { typeId = "cannon", x = 24, y = 10, hp = cfg.STRUCTURES.cannon.hp, underConstruction = false } },
	})

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	-- A one-hit kill (cannon damage 10 vs. cannon hp 6): B's cannon is destroyed
	-- this tick, so A should be the one credited for it.
	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local newState = Rules.tick(cfg, warmedUp)

	t.expectEqual(newState.players.A.destructionPoints, config.POINTS.destroy.cannon)
	t.expectEqual(newState.players.B.destructionPoints, 0)
end)

t.test("Rules.tick awards hit points separately from destroy points", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local newState = Rules.tick(cfg, warmedUp)

	t.expectEqual(newState.players.A.destructionPoints, 0) -- the base survives this hit
	t.expectEqual(newState.players.A.hitPoints, config.POINTS.hit.base)
end)

t.test("Rules.tick awards reveal points once per newly-sighted live structure, not on re-sighting by the same weapon firing again", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", {
		-- Both on B's own land (24-35): the generator at x=24 sits on the direct
		-- beam from A's cannon at x=17 to the base at x=25, right at the cannon's
		-- 8-cell range (§18).
		structures = {
			withBase(25, 10),
			{ typeId = "generator", x = 24, y = 10, hp = config.STRUCTURES.generator.hp, underConstruction = false },
		},
	})

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 25, targetY = 10 })

	-- The beam crosses the generator on the way to the base -- both get revealed
	-- by this first shot, even though only the base takes damage.
	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local afterFirstShot = Rules.tick(cfg, warmedUp)
	t.expectEqual(afterFirstShot.players.A.revealPoints, config.POINTS.reveal.base + config.POINTS.reveal.generator)

	-- Single shot clears the target on firing (§18), so a second shot needs a
	-- fresh target command -- re-sighting the same live structures still must
	-- not double-count.
	local retargeted = Rules.applyCommand(cfg, afterFirstShot, "A", { type = "target", x = 17, y = 10, targetX = 25, targetY = 10 })
	local afterSecondShot = Rules.tick(cfg, retargeted)
	t.expectEqual(afterSecondShot.players.A.shotsFired, 2)
	t.expectEqual(afterSecondShot.players.A.revealPoints, afterFirstShot.players.A.revealPoints)
end)

t.test("a weapon defaults to single shot: firing clears its target instead of firing again on its own", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local afterFirstShot = Rules.tick(cfg, warmedUp)
	t.expectEqual(afterFirstShot.players.A.shotsFired, 1)
	t.expectEqual(afterFirstShot.players.A.structures[2].target, nil)

	-- Off cooldown again but never re-targeted -- must not fire a second time.
	local afterSecondTick = Rules.tick(cfg, afterFirstShot)
	t.expectEqual(afterSecondTick.players.A.shotsFired, 1)
end)

t.test("a full scripted match with autoFire on: target once, let it fire on its own tick after tick until base elimination", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) } })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	-- autoFire isn't exposed to a real player yet (§ Weapon inspection and control
	-- panel), so it's set directly here to exercise the "keeps firing on its own"
	-- path this test is actually about.
	local cannon = table.clone(afterTarget.players.A.structures[2])
	cannon.autoFire = true
	local structures = table.clone(afterTarget.players.A.structures)
	structures[2] = cannon
	local withAutoFire = State.withPlayer(afterTarget, "A", { structures = structures })

	-- base hp 40 / cannon damage 10 = 4 hits: 1 tick to complete construction, then
	-- 4 more ticks firing once per (one-tick) cooldown.
	local current, victory = advanceTicks(cfg, withAutoFire, 5)

	t.expectTrue(victory ~= nil)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
	t.expectEqual(#current.players.B.structures, 0)
	t.expectEqual(#current.players.A.structures, 2) -- base + cannon, both untouched
end)

t.test("the missile is arc fire (unblockable by terrain) with no splash: only its impact cell takes damage", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state.elapsed = cfg.STRUCTURES.missile.unlock_time
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) }, resources = { supply = 100, energy = 10 } })
	state = State.withPlayer(state, "B", {
		structures = {
			withBase(30, 10),
			{ typeId = "generator", x = 24, y = 10, hp = cfg.STRUCTURES.generator.hp, underConstruction = false },
		},
	})

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "missile", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local newState = Rules.tick(cfg, warmedUp)

	t.expectEqual(newState.players.A.shotsFired, 1)
	t.expectEqual(newState.players.A.destructionPoints, config.POINTS.destroy.generator) -- one-hit kill on the impact cell
	t.expectEqual(#newState.players.B.structures, 1) -- generator destroyed, base untouched by splash
end)

t.test("the scout drone deals no damage but still reveals what it targets, like any other shot", function()
	local cfg = fastConfig()
	local state = State.new(cfg)
	state.elapsed = cfg.STRUCTURES.scout.unlock_time
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) }, resources = { supply = 100, energy = 10 } })
	state = State.withPlayer(state, "B", {
		-- Generator sits well clear of the base's own footprint, and far enough from
		-- the base that the drone's corridor+block reveal (session 018) never reaches
		-- the base's cells, so revealPoints below only ever credits the generator.
		structures = {
			withBase(30, 10),
			{ typeId = "generator", x = 24, y = 10, hp = cfg.STRUCTURES.generator.hp, underConstruction = false },
		},
	})

	local afterPlace = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "scout", x = 17, y = 10 })
	local afterTarget = Rules.applyCommand(cfg, afterPlace, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })

	local warmedUp = advanceTicks(cfg, afterTarget, 1)
	local newState = Rules.tick(cfg, warmedUp)

	t.expectEqual(newState.players.A.shotsFired, 1)
	t.expectEqual(newState.players.B.structures[2].hp, cfg.STRUCTURES.generator.hp) -- undamaged
	t.expectEqual(#newState.players.B.structures, 2) -- nothing destroyed
	t.expectEqual(newState.players.A.revealPoints, config.POINTS.reveal.generator)
end)
