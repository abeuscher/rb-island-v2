-- Bot difficulty presets (§14): a Supply multiplier, how many seconds a
-- plotted structure goes unconfirmed before the bot treats it as stale and
-- probes it again instead of firing blind, and whether it shapes terrain
-- deliberately. Shared so the client's difficulty picker and the server's
-- Bot (src/server/Bot.luau) read the same three presets in the same order.
-- restProbeSeconds replaces the old round-keyed restProbeRounds (Session
-- 015) -- same 4:2:1 ratio, scaled by the ~10s a testing-config round used
-- to take (Session 006).

return {
	{ id = "shoal", label = "Shoal", supplyMultiplier = 0.8, restProbeSeconds = 40, usesElevation = false },
	{ id = "skirmish", label = "Skirmish", supplyMultiplier = 1.0, restProbeSeconds = 20, usesElevation = true },
	{ id = "siege", label = "Siege", supplyMultiplier = 1.25, restProbeSeconds = 10, usesElevation = true },
}
