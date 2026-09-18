-- Bot difficulty presets (§14): a Supply multiplier, how many rounds a
-- plotted structure goes unconfirmed before the bot treats it as stale and
-- probes it again instead of firing blind, and whether it shapes terrain
-- deliberately. Shared so the client's difficulty picker and the server's
-- Bot (src/server/Bot.luau) read the same three presets in the same order.

return {
	{ id = "shoal", label = "Shoal", supplyMultiplier = 0.8, restProbeRounds = 4, usesElevation = false },
	{ id = "skirmish", label = "Skirmish", supplyMultiplier = 1.0, restProbeRounds = 2, usesElevation = true },
	{ id = "siege", label = "Siege", supplyMultiplier = 1.25, restProbeRounds = 1, usesElevation = true },
}
