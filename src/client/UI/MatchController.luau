-- Owns the match wrapper (§6): the Intro/Settings/Result screens, mounted once,
-- and the session state machine around them (intro -> setup -> rounds -> result
-- -> intro). Each Start Game or Restart mounts a fresh PlanUI (board, HUD, and
-- PlanController) and tears the previous one down, so neither ever needs a
-- rejoin -- there's nothing to "rejoin" locally in the first place, but this is
-- also the shape server authority will need to slot into later (§12).

local Players = game:GetService("Players")

local PlanUI = require(script.Parent)
local Intro = require(script.Parent.Screens.Intro)
local Settings = require(script.Parent.Screens.Settings)
local SettingsRegistry = require(script.Parent.Screens.SettingsRegistry)
local Result = require(script.Parent.Screens.Result)

local MatchController = {}

function MatchController.start(owner)
	local player = Players.LocalPlayer
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MatchWrapperUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10 -- always above the in-match board HUD
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local activeMatch = nil
	local startMatch

	local function teardownMatch()
		if activeMatch then
			activeMatch.teardown()
			activeMatch = nil
		end
	end

	local settingsScreen
	local intro = Intro.mount(screenGui, {
		onStart = function()
			startMatch()
		end,
		onSettings = function()
			settingsScreen.show()
		end,
	})
	settingsScreen = Settings.mount(screenGui, SettingsRegistry)
	local result = Result.mount(screenGui, {
		onRestart = function()
			result.hide()
			startMatch()
		end,
	})

	startMatch = function()
		teardownMatch()
		intro.hide()
		result.hide()

		local handle = PlanUI.mount(owner)
		handle.controller:onMatchEnd(function(victory, finalState)
			teardownMatch()
			result.show(victory, finalState, handle.controller.config, owner, handle.controller.enemy)
		end)
		activeMatch = handle
	end
end

return MatchController
