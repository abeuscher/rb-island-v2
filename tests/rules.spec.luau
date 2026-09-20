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
	t.expectEqual(victory3.incapacitatedSide, "B")
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
	-- The real bug this guards against: the Result screen used to infer who was
	-- incapacitated from `winner` alone, which is backwards exactly here -- B
	-- won on points despite being the incapacitated side, so a naive
	-- winner-equals-owner check would tell B's own screen "Opponent
	-- incapacitated" instead of "You were incapacitated."
	t.expectEqual(victory.incapacitatedSide, "B")
end)

t.test("both sides incapacitated at once reports incapacitatedSide as \"both\"", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { withBase(6, 7) }, incapableSince = 0 })
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) }, incapableSince = 0 })
	state.elapsed = config.INCAPACITATION_GRACE_SECONDS

	local victory = Rules.checkVictory(config, state)
	t.expectEqual(victory.condition, "incapacitation")
	t.expectEqual(victory.incapacitatedSide, "both")
end)

t.test("Rules.tick clears incapableSince once a player actually recovers, instead of it sticking forever", function()
	-- A real bug, found live: State.withPlayer merges fields with `pairs`,
	-- which can never see a `nil` value in a plain table literal --
	-- `{ incapableSince = nil }` simply omits the key -- so the old
	-- withPlayer-based clear was a silent no-op. A player who was briefly
	-- incapable early on (no generator, no affordable weapon) but fully
	-- recovered stayed flagged forever and could still lose (or win) on a
	-- stale "incapacitation" long after their economy was healthy again.
	local incapConfig = table.clone(config)
	incapConfig.SUPPLY_PER_SECOND = 0
	incapConfig.STARTING_SUPPLY = 0
	incapConfig.INCAPACITATION_GRACE_SECONDS = 4 * config.TICK_SECONDS

	local state = State.new(incapConfig)
	state = State.withPlayer(state, "A", {
		structures = { withBase(6, 7), { typeId = "cannon", x = 6, y = 9, hp = config.STRUCTURES.cannon.hp, underConstruction = false } },
	})
	state = State.withPlayer(state, "B", { structures = { withBase(24, 7) } })

	local afterTick1 = advanceTicks(incapConfig, state, 1)
	t.expectTrue(afterTick1.players.B.incapableSince ~= nil)

	-- B recovers well before the grace window expires -- Supply arrives (the
	-- mechanism doesn't matter here) and B builds a generator.
	local recovering = State.withPlayer(afterTick1, "B", { resources = { supply = 100, energy = afterTick1.players.B.resources.energy } })
	local afterBuild = Rules.applyCommand(incapConfig, recovering, "B", { type = "place", typeId = "generator", x = 24, y = 10 })
	t.expectEqual(#afterBuild.players.B.structures, 2)

	-- The next tick re-evaluates incapableSince with the generator now live.
	local afterTick2 = advanceTicks(incapConfig, afterBuild, 1)
	t.expectEqual(afterTick2.players.B.incapableSince, nil)

	-- Advance well past the original grace window: with the stale-timestamp
	-- bug, B would still end the match on a false incapacitation here despite
	-- having fully recovered several ticks ago.
	local _, victory = advanceTicks(incapConfig, afterTick2, 10)
	t.expectEqual(victory, nil)
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
	local withAutoFire = Rules.applyCommand(cfg, afterTarget, "A", { type = "autoFire", x = 17, y = 10, enabled = true })
	t.expectTrue(withAutoFire.players.A.structures[2].autoFire)

	-- base hp 40 / cannon damage 10 = 4 hits: 1 tick to complete construction, then
	-- 4 more ticks firing once per (one-tick) cooldown.
	local current, victory = advanceTicks(cfg, withAutoFire, 5)

	t.expectTrue(victory ~= nil)
	t.expectEqual(victory.condition, "base_elimination")
	t.expectEqual(victory.winner, "A")
	t.expectEqual(#current.players.B.structures, 0)
	t.expectEqual(#current.players.A.structures, 2) -- base + cannon, both untouched
end)

t.test("planShots: a costlier weapon no longer starves once a cheaper one is also drawing from the same Energy pool", function()
	-- Session 021's finding, measured directly with the real cannon/mortar costs
	-- and cooldowns (fastConfig's cooldown shortcuts don't apply here -- they'd
	-- change cannon's cooldown relative to mortar's and mask the real dynamic).
	-- Only BUILD_SECONDS is shortened, to skip construction wait, and the base's
	-- hp is raised so 60s of hits never ends the match early -- neither changes
	-- the Energy economy this test is exercising.
	local cfg = table.clone(config)
	cfg.STRUCTURES = table.clone(config.STRUCTURES)
	cfg.STRUCTURES.base = table.clone(config.STRUCTURES.base)
	cfg.STRUCTURES.base.hp = 1000000
	cfg.BUILD_SECONDS = cfg.TICK_SECONDS

	local state = State.new(cfg)
	state.elapsed = cfg.STRUCTURES.mortar.unlock_time
	state = State.withPlayer(state, "A", {
		structures = {
			withBase(6, 7),
			{ typeId = "generator", x = 6, y = 9, hp = cfg.STRUCTURES.generator.hp, underConstruction = false },
		},
		resources = { supply = 100, energy = cfg.STARTING_ENERGY },
	})
	state = State.withPlayer(state, "B", { structures = { withBase(24, 10) } })

	local afterCannon = Rules.applyCommand(cfg, state, "A", { type = "place", typeId = "cannon", x = 17, y = 9 })
	local afterMortar = Rules.applyCommand(cfg, afterCannon, "A", { type = "place", typeId = "mortar", x = 17, y = 10 })
	local built = advanceTicks(cfg, afterMortar, 1)

	local afterCannonTarget = Rules.applyCommand(cfg, built, "A", { type = "target", x = 17, y = 9, targetX = 24, targetY = 10 })
	local afterMortarTarget = Rules.applyCommand(cfg, afterCannonTarget, "A", { type = "target", x = 17, y = 10, targetX = 24, targetY = 10 })
	local afterCannonAuto = Rules.applyCommand(cfg, afterMortarTarget, "A", { type = "autoFire", x = 17, y = 9, enabled = true })
	local current = Rules.applyCommand(cfg, afterCannonAuto, "A", { type = "autoFire", x = 17, y = 10, enabled = true })

	-- 60s of continuous auto-fire from both, same as Session 021's measurement.
	local mortarShots = 0
	for _ = 1, 60 / cfg.TICK_SECONDS do
		local newState, _, _, resolution = Rules.tick(cfg, current)
		current = newState
		for _, shot in ipairs(resolution.shotsA) do
			if shot.def.id == "mortar" then
				mortarShots += 1
			end
		end
	end

	-- Session 021 measured the bug at 1 shot here (vs. 4 with no cannon
	-- competing for the pool at all) -- this only needs to confirm the mortar
	-- is no longer starved down to that, not pin an exact shot count to a
	-- balance number this session isn't meant to retune.
	t.expectTrue(mortarShots > 1)
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
