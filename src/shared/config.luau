-- All tuning numbers for the rules core. Nothing numeric is hardcoded elsewhere.

return {
	BOARD_WIDTH = 40,
	BOARD_HEIGHT = 24,
	CHANNEL_WIDTH = 6,
	STUDS_PER_CELL = 4,
	ISLAND_SIZE = 12,
	MAX_ELEVATION = 2,

	-- Terrain-edit costs and per-second economy rates below are Session 019's
	-- sweep-tuned values (§18), chosen as the lowest-badness point from
	-- sim/output/shortlist.md's 24-point sweep -- no point cleared the sweep's
	-- own "no archetype over 60% of the field" bar (best was 66%), which is
	-- expected until a real defense-side balance pass exists (Session 019 Open
	-- Gate decision); this is the least-bad config on the numbers as they stand.
	RAISE_COST = 6,
	LOWER_COST = 2,
	RECLAIM_COST = 8,

	-- Per-second rates; each tick accrues rate * TICK_SECONDS.
	SUPPLY_PER_SECOND = 0.7,
	STARTING_SUPPLY = 10,
	ENERGY_BASE = 0,
	-- The sweep's own pick here (0.05) starved weapon fire almost entirely --
	-- mortars (3 Energy/shot) barely fired once per match even with nothing
	-- else competing for the pool (Session 019, found on read). 0.15 is the
	-- sweep's other directly-tested value, not a new guess.
	ENERGY_PER_GENERATOR_PER_SECOND = 0.15,
	ENERGY_CAP = 12,
	STARTING_ENERGY = 4,

	TICK_SECONDS = 0.5,
	MATCH_SECONDS = 200,
	BUILD_SECONDS = 5,
	INCAPACITATION_GRACE_SECONDS = 40,

	-- How often server/Bot.luau re-runs decide() during "live" -- a guess at what
	-- reads as responsive without thrashing weapon targets between cooldowns,
	-- pending live testing (§18).
	BOT_DECIDE_INTERVAL_SECONDS = 3,

	NUM_BASES = 3,
	SIM_MATCHES_PER_PAIR = 100,

	-- Seconds of elapsed match time, replacing the old round-keyed UNLOCK_ROUND.
	-- terrain_edit is open from the moment live play starts (raise/lower are how a
	-- player shapes their defense from turn one, not a later-game unlock);
	-- reclamation stays a placeholder pending §18.
	UNLOCK_TIME = {
		terrain_edit = 0,
		reclamation = 60,
	},

	POINTS = {
		destroy = { base = 100, mortar = 35, generator = 25, cannon = 20, missile = 45, scout = 15 },
		standing = { base = 50, mortar = 15, generator = 10, cannon = 10, missile = 20, scout = 8 },
		-- Scouting and landing damage are worth something on their own, not just
		-- the kill -- otherwise the only winning move is turtling structures to
		-- the final whistle. Roughly 20%/10% of a kill's value; a guess like every
		-- other POINTS entry, pending a real balance pass (§15/§18).
		reveal = { base = 20, mortar = 7, generator = 5, cannon = 4, missile = 9, scout = 3 },
		hit = { base = 10, mortar = 4, generator = 3, cannon = 2, missile = 5, scout = 1 },
	},

	STRUCTURES = {
		base = {
			id = "base",
			display_name = "Base",
			supply_cost = 0,
			energy_cost = 0,
			hp = 40,
			footprint = 2,
			fire_mode = nil,
			range = nil,
			elevation_range_bonus = 0,
			damage = 0,
			splash = nil,
			reveal_mode = nil,
			unlock_time = 0,
		},
		generator = {
			id = "generator",
			display_name = "Generator",
			supply_cost = 8,
			energy_cost = 0,
			hp = 8,
			footprint = 1,
			fire_mode = nil,
			range = nil,
			elevation_range_bonus = 0,
			damage = 0,
			splash = nil,
			reveal_mode = nil,
			unlock_time = 0,
		},
		cannon = {
			id = "cannon",
			display_name = "Cannon",
			supply_cost = 10,
			energy_cost = 1,
			hp = 6,
			footprint = 1,
			fire_mode = "direct",
			-- The sweep's own pick here (8) was mechanically "fair" but broke long-
			-- range recon entirely: a frontline cannon couldn't reach more than the
			-- opponent's first couple of columns, so several archetypes (`defilade`
			-- especially) never fired a shot all match (Session 019, found on read
			-- of the full sim run). 14 lets an unelevated frontline cannon reach most
			-- of a 12-deep island, and the full depth once elevated -- keeping
			-- elevation meaningful without making it mandatory just to function.
			range = 14,
			elevation_range_bonus = 2,
			damage = 10,
			cooldown_seconds = 5,
			splash = nil,
			reveal_mode = "beam",
			unlock_time = 0,
		},
		mortar = {
			id = "mortar",
			display_name = "Mortar",
			supply_cost = 18,
			energy_cost = 3,
			hp = 5,
			footprint = 1,
			fire_mode = "arc",
			range = 20, -- sweep-tuned (§18), see the RAISE_COST comment above
			elevation_range_bonus = 0,
			damage = 14,
			cooldown_seconds = 5,
			splash = { amount = 6, pattern = "orthogonal" },
			reveal_mode = "impact",
			unlock_time = 40,
		},
		-- Long-range arc sniper (Session 016): arcs over terrain like the mortar,
		-- but the longest range and biggest single hit in the roster, with no
		-- splash and a slower cooldown -- precision reach, not area denial.
		-- Placeholder numbers pending a real balance pass (§18), same as every
		-- other weapon's.
		missile = {
			id = "missile",
			display_name = "Missile",
			supply_cost = 26,
			energy_cost = 5,
			hp = 5,
			footprint = 1,
			fire_mode = "arc",
			range = 44,
			elevation_range_bonus = 0,
			damage = 24,
			cooldown_seconds = 12,
			splash = nil,
			reveal_mode = "impact",
			unlock_time = 80,
		},
		-- Non-damaging recon weapon (Session 016): fires like any other weapon --
		-- targeted, cooldown-gated, single-shot -- but deals 0 damage, so its only
		-- effect is the reveal Fog.applyReveal already does for every shot.
		scout = {
			id = "scout",
			display_name = "Scout Drone",
			supply_cost = 4,
			energy_cost = 1,
			hp = 3,
			footprint = 1,
			fire_mode = "scout",
			range = 24,
			elevation_range_bonus = 0,
			damage = 0,
			cooldown_seconds = 8,
			splash = nil,
			reveal_mode = "scout",
			unlock_time = 20,
		},
	},
}
