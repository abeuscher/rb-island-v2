-- Mounts one match's board/HUD: setup, build palette, terrain tools, targeting
-- list, and round clock, wired to either a real server-authoritative
-- PlanController ("online") or a local offline PracticeController
-- ("practice") -- both expose the same controller surface (§12's `View`-
-- shaped `state`, `onChange`/`onResolve`/`onMatchEnd`/`onTick`, etc.), so
-- everything below is blind to which one is driving it. Owned by
-- MatchController, which mounts a fresh one per match (Start Game / Practice
-- / Restart) and tears the old one down via the handle this returns.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local SharedBoard = require(ReplicatedStorage.Shared.board)
local ClientBoard = require(script.Parent.Board)
local ClientCamera = require(script.Parent.Camera)
local Input = require(script.Parent.Input)
local Render = require(script.Parent.Render)
local PlanController = require(script.PlanController)
local PracticeController = require(script.PracticeController)
local BuildPalette = require(script.BuildPalette)
local RoundClock = require(script.RoundClock)
local StructureView = require(script.StructureView)
local Cursor = require(script.Cursor)

local PlanUI = {}

-- `mode` is "online" (real match, needs `remotes`) or "practice" (local
-- dummy match, `remotes` unused).
function PlanUI.mount(owner, mode, remotes)
	local player = Players.LocalPlayer
	local controller = (mode == "online") and PlanController.new(Config, owner, remotes) or PracticeController.new(Config, owner)
	local cameraHandle = ClientCamera.start(owner)

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "Match"
	worldFolder.Parent = Workspace

	local boardFolder = Instance.new("Folder")
	boardFolder.Name = "Board"
	boardFolder.Parent = worldFolder

	local structureFolder = Instance.new("Folder")
	structureFolder.Name = "Structures"
	structureFolder.Parent = worldFolder

	local cursorFolder = Instance.new("Folder")
	cursorFolder.Name = "Cursor"
	cursorFolder.Parent = worldFolder

	local enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "EnemyStructures"
	enemyFolder.Parent = worldFolder

	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ResolveEffects"
	effectsFolder.Parent = worldFolder

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

	local lastBoard = nil

	-- Full rebuild on the first frame; after that, only the cells whose
	-- elevation/land actually changed get touched (via ClientBoard.updateCell,
	-- tweened) instead of clearing and rebuilding the whole board on every
	-- tick's onChange -- the same "don't redraw what didn't change" fix
	-- Session 014 made for the enemy board, applied here to the player's own.
	local function renderBoard()
		local board = controller.state.board
		if not lastBoard then
			boardFolder:ClearAllChildren()
			ClientBoard.build(boardFolder, board)
		else
			for x = 1, board.width do
				for y = 1, board.height do
					local old = SharedBoard.getCell(lastBoard, x, y)
					local new = SharedBoard.getCell(board, x, y)
					if old.land ~= new.land or old.elevation ~= new.elevation then
						ClientBoard.updateCell(boardFolder, board, x, y)
					end
				end
			end
		end
		lastBoard = board
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

	local inputConnection = Input.onBoardClick(boardFolder, function(x, y)
		controller:handleBoardClick(x, y)
	end)

	local cursorHandle = Cursor.mount(cursorFolder, boardFolder, controller, Input)
	Render.mount(effectsFolder, enemyFolder, controller)

	local function teardown()
		controller:stopClock()
		inputConnection:Disconnect()
		cursorHandle.stop()
		cameraHandle.stop()
		screenGui:Destroy()
		worldFolder:Destroy()
	end

	return { controller = controller, teardown = teardown }
end

return PlanUI
