-- Mounts the plan-phase UI: build palette, terrain tools, targeting list, and
-- round clock, wired to a local PlanController. See Session 005's brief for why
-- this is local-only rather than server-authoritative.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local ClientBoard = require(script.Parent.Board)
local Input = require(script.Parent.Input)
local PlanController = require(script.PlanController)
local BuildPalette = require(script.BuildPalette)
local RoundClock = require(script.RoundClock)
local StructureView = require(script.StructureView)
local Cursor = require(script.Cursor)

local PlanUI = {}

function PlanUI.mount(owner)
	local player = Players.LocalPlayer
	local controller = PlanController.new(Config, owner)

	local boardFolder = Instance.new("Folder")
	boardFolder.Name = "Board"
	boardFolder.Parent = Workspace

	local structureFolder = Instance.new("Folder")
	structureFolder.Name = "Structures"
	structureFolder.Parent = Workspace

	local cursorFolder = Instance.new("Folder")
	cursorFolder.Name = "Cursor"
	cursorFolder.Parent = Workspace

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -400, 0, 30)
	statusLabel.Position = UDim2.new(0, 200, 1, -30)
	statusLabel.BackgroundTransparency = 0.3
	statusLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.TextSize = 16
	statusLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	statusLabel.Text = ""
	statusLabel.Parent = screenGui

	local palette = BuildPalette.mount(screenGui, controller)
	local clock = RoundClock.mount(screenGui, controller)

	local function renderBoard()
		boardFolder:ClearAllChildren()
		ClientBoard.build(boardFolder, controller.state.board)
		StructureView.render(structureFolder, controller)
	end

	renderBoard()

	controller:onChange(function(message, ok)
		if message then
			statusLabel.Text = message
			statusLabel.TextColor3 = ok and Color3.fromRGB(180, 240, 180) or Color3.fromRGB(240, 160, 160)
		end
		renderBoard()
		palette.refresh()
		clock.refresh()
	end)

	controller:onTick(function()
		clock.refresh()
	end)

	Input.onBoardClick(boardFolder, function(x, y)
		controller:handleBoardClick(x, y)
	end)

	Cursor.mount(cursorFolder, boardFolder, controller, Input)

	controller:startClock()

	return controller
end

return PlanUI
