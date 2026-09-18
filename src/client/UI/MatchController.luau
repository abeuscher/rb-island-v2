-- Owns the match wrapper (§6): the Intro/Settings/Result screens, mounted
-- once, and the session flow around them. Three ways into a match now
-- (Session 009 adds the third): "Start Game" queues on the server and waits
-- for a second real Studio client to pair with (§12); "Practice vs. Dummy"
-- mounts the old local-only flow instantly, no server round trip needed;
-- "Play vs. Bot" is server-authoritative exactly like Start Game, just
-- against server/Bot.luau's seat instead of a queued second player, so it
-- reuses the same MatchFound -> mountOnline path and starts instantly since
-- there's no one to wait for. Restart re-enters whichever of those the match
-- that just ended came from. Each mount is a fresh PlanUI (board, HUD, and
-- controller) and the previous one is torn down first, so no path ever needs
-- a rejoin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.remotes)
local PlanUI = require(script.Parent)
local Intro = require(script.Parent.Screens.Intro)
local Settings = require(script.Parent.Screens.Settings)
local SettingsRegistry = require(script.Parent.Screens.SettingsRegistry)
local Result = require(script.Parent.Screens.Result)

local MatchController = {}

function MatchController.start()
	local player = Players.LocalPlayer
	local remotes = Remotes.get()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MatchWrapperUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10 -- always above the in-match board HUD
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local activeMatch = nil
	local lastMode = nil
	local mountOnline, mountPractice, queueForMatch, startBotMatch

	local function teardownMatch()
		if activeMatch then
			activeMatch.teardown()
			activeMatch = nil
		end
	end

	local settingsScreen
	local intro = Intro.mount(screenGui, {
		onStart = function()
			queueForMatch()
		end,
		onPractice = function()
			mountPractice()
		end,
		onBot = function()
			startBotMatch()
		end,
		onSettings = function()
			settingsScreen.show()
		end,
	})
	settingsScreen = Settings.mount(screenGui, SettingsRegistry)
	local result = Result.mount(screenGui, {
		onRestart = function()
			result.hide()
			if lastMode == "practice" then
				mountPractice()
			elseif lastMode == "bot" then
				startBotMatch()
			else
				queueForMatch()
			end
		end,
	})

	queueForMatch = function()
		intro.show()
		intro.setWaiting(true)
		lastMode = "online"
		remotes.Command:FireServer({ type = "queueForMatch" })
	end

	-- No queueing wait, unlike queueForMatch -- the bot is always ready, so
	-- MatchFound fires back as soon as the server round-trips (§14).
	startBotMatch = function()
		lastMode = "bot"
		remotes.Command:FireServer({ type = "startBotMatch", difficulty = SettingsRegistry.getBotDifficulty() })
	end

	mountOnline = function(owner)
		teardownMatch()
		intro.hide()
		intro.setWaiting(false)
		result.hide()
		-- Both queueForMatch and startBotMatch route MatchFound here; each
		-- already set lastMode itself before firing the remote.

		local handle = PlanUI.mount(owner, "online", remotes)
		handle.controller:onMatchEnd(function(victory, summary)
			teardownMatch()
			result.show(victory, summary, owner)
		end)
		activeMatch = handle
	end

	mountPractice = function()
		teardownMatch()
		intro.hide()
		result.hide()
		lastMode = "practice"

		local handle = PlanUI.mount("A", "practice", remotes)
		handle.controller:onMatchEnd(function(victory, summary)
			teardownMatch()
			result.show(victory, summary, handle.controller.owner)
		end)
		activeMatch = handle
	end

	remotes.MatchFound.OnClientEvent:Connect(function(payload)
		mountOnline(payload.owner)
	end)
end

return MatchController
