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

	NUM_BASES = 3,
	SIM_MATCHES_PER_PAIR = 200,

	-- Seconds of elapsed match time, replacing the old round-keyed UNLOCK_ROUND.
	-- Evenly spaced placeholders standing in for the old round cadence, pending §18.
	UNLOCK_TIME = {
		terrain_edit = 20,
		reclamation = 60,
	},

	POINTS = {
		destroy = { base = 100, mortar = 35, generator = 25, cannon = 20 },
		standing = { base = 50, mortar = 15, generator = 10, cannon = 10 },
		-- Scouting and landing damage are worth something on their own, not just
		-- the kill -- otherwise the only winning move is turtling structures to
		-- the final whistle. Roughly 20%/10% of a kill's value; a guess like every
		-- other POINTS entry, pending a real balance pass (§15/§18).
		reveal = { base = 20, mortar = 7, generator = 5, cannon = 4 },
		hit = { base = 10, mortar = 4, generator = 3, cannon = 2 },
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
	},
}
