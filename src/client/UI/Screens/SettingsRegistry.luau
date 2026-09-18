-- Ordered registry of settings entries, each shaped
-- { id, label, kind, default, apply }. Settings.luau renders whatever this
-- contains and nothing else -- adding a setting later means appending one
-- entry here, never touching the panel itself.
--
-- Bot Difficulty (Session 009, §14) is the first real entry: a "cycle" row
-- over src/shared/botDifficulty.luau's three presets. There's nowhere to
-- persist a chosen value yet (Save Game is still "coming soon"), so `apply`
-- just updates the module-local var getBotDifficulty() reads back when
-- MatchController starts a bot match.

local BotDifficulty = require(game:GetService("ReplicatedStorage").Shared.botDifficulty)

local DEFAULT_BOT_DIFFICULTY = "skirmish"
local selectedBotDifficulty = DEFAULT_BOT_DIFFICULTY

local registry = {
	{
		id = "botDifficulty",
		label = "Bot Difficulty",
		kind = "cycle",
		options = BotDifficulty,
		default = DEFAULT_BOT_DIFFICULTY,
		apply = function(value)
			selectedBotDifficulty = value
		end,
	},
}

function registry.getBotDifficulty()
	return selectedBotDifficulty
end

return registry
