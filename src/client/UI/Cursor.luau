-- Cursor feedback for the plan-phase UI: a footprint preview over the hovered
-- cell while placing a structure -- green if the shared validator would
-- accept it there, red if not -- and a crosshair replacing the system cursor
-- while a weapon is armed for targeting.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Structures = require(ReplicatedStorage.Shared.structures)

local Cursor = {}

local VALID_COLOR = Color3.fromRGB(80, 220, 80)
local INVALID_COLOR = Color3.fromRGB(220, 70, 70)
local CROSSHAIR_SIZE = 20
local CROSSHAIR_THICKNESS = 2

local function structureCenter(config, x, y, size)
	local s = config.STUDS_PER_CELL
	return (x + size / 2 - 1) * s, (y + size / 2 - 1) * s
end

local function makeCrosshairBar(sizeX, sizeY, parent)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.5, 0, 0.5, 0)
	bar.Size = UDim2.new(0, sizeX, 0, sizeY)
	bar.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	bar.BorderSizePixel = 0
	bar.Parent = parent
	return bar
end

-- `Input` is passed in rather than required, since it's a sibling of the UI
-- folder rather than a shared module -- mirrors how UI/init.luau wires its
-- other dependencies.
function Cursor.mount(cursorFolder, boardFolder, controller, Input)
	local config = controller.config
	local player = Players.LocalPlayer

	local previewPart = Instance.new("Part")
	previewPart.Name = "PlacementPreview"
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.CanQuery = false
	previewPart.Material = Enum.Material.Neon
	previewPart.Transparency = 1
	previewPart.Parent = cursorFolder

	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "Crosshair"
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.ResetOnSpawn = false
	crosshairGui.Enabled = false
	crosshairGui.Parent = player:WaitForChild("PlayerGui")

	local crosshairContainer = Instance.new("Frame")
	crosshairContainer.Name = "CrosshairContainer"
	crosshairContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshairContainer.Size = UDim2.new(0, CROSSHAIR_SIZE, 0, CROSSHAIR_SIZE)
	crosshairContainer.BackgroundTransparency = 1
	crosshairContainer.Parent = crosshairGui

	makeCrosshairBar(CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, crosshairContainer)
	makeCrosshairBar(CROSSHAIR_THICKNESS, CROSSHAIR_SIZE, crosshairContainer)

	local wasTargeting = false

	local connection = RunService.RenderStepped:Connect(function()
		local tool = controller.tool
		local isTargeting = tool == "target"
		if isTargeting ~= wasTargeting then
			wasTargeting = isTargeting
			crosshairGui.Enabled = isTargeting
			UserInputService.MouseIconEnabled = not isTargeting
		end

		if isTargeting then
			local mouse = UserInputService:GetMouseLocation()
			crosshairContainer.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
		end

		if string.sub(tool, 1, 6) == "place:" then
			local x, y = Input.getBoardCellUnderMouse(boardFolder)
			if x then
				local typeId = string.sub(tool, 7)
				local def = config.STRUCTURES[typeId]
				local centerX, centerZ = structureCenter(config, x, y, def.footprint)
				local top = (Board.elevationAt(controller.state.board, x, y) + 1) * config.STUDS_PER_CELL
				local ok = Structures.canPlace(
					config,
					controller.state.board,
					controller.state.self.structures,
					controller.owner,
					typeId,
					x,
					y,
					controller.state.elapsed
				)
				previewPart.Size =
					Vector3.new(def.footprint * config.STUDS_PER_CELL, 0.3, def.footprint * config.STUDS_PER_CELL)
				previewPart.Position = Vector3.new(centerX, top + 0.15, centerZ)
				previewPart.Color = ok and VALID_COLOR or INVALID_COLOR
				previewPart.Transparency = 0.4
			else
				previewPart.Transparency = 1
			end
		else
			previewPart.Transparency = 1
		end
	end)

	return {
		stop = function()
			connection:Disconnect()
			UserInputService.MouseIconEnabled = true
		end,
	}
end

return Cursor
