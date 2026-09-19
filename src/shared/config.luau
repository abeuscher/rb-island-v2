-- All tuning numbers for the rules core. Nothing numeric is hardcoded elsewhere.

return {
	BOARD_WIDTH = 40,
	BOARD_HEIGHT = 24,
	CHANNEL_WIDTH = 6,
	STUDS_PER_CELL = 4,
	ISLAND_SIZE = 12,
	MAX_ELEVATION = 2,

	RAISE_COST = 4,
	LOWER_COST = 2,
	RECLAIM_COST = 12,

	-- Per-second rates; each tick accrues rate * TICK_SECONDS. Magnitudes carried
	-- over from the old per-round lump amounts divided by the ~20s a testing-config
	-- round used to take, not a fresh balance pass.
	SUPPLY_PER_SECOND = 0.5,
	STARTING_SUPPLY = 10,
	ENERGY_BASE = 0,
	ENERGY_PER_GENERATOR_PER_SECOND = 0.1,
	ENERGY_CAP = 12,
	STARTING_ENERGY = 4,

	TICK_SECONDS = 0.5,
	MATCH_SECONDS = 180,
	BUILD_SECONDS = 5,
	INCAPACITATION_GRACE_SECONDS = 40,

	-- How often server/Bot.luau re-runs decide() during "live" -- a guess at what
	-- reads as responsive without thrashing weapon targets between cooldowns,
	-- pending live testing (§18).
	BOT_DECIDE_INTERVAL_SECONDS = 3,

	NUM_BASES = 3,
	SIM_MATCHES_PER_PAIR = 200,

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
			range = 20, -- doubled for testing so weapons aren't pinned to the frontline (§18)
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
			range = 32, -- doubled for testing, matching the cannon (§18)
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
