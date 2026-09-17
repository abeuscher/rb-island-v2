-- Resolves a mouse click against the rendered board to the board cell (x, y)
-- underneath it, using the same cell-to-world math ClientBoard renders with.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local Input = {}

-- Board cell (x, y) under the current mouse position, or nil if the mouse
-- isn't over `boardFolder`.
function Input.getBoardCellUnderMouse(boardFolder)
	local camera = Workspace.CurrentCamera
	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { boardFolder }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not result then
		return nil
	end

	local studsPerCell = Config.STUDS_PER_CELL
	local x = math.floor(result.Position.X / studsPerCell) + 1
	local y = math.floor(result.Position.Z / studsPerCell) + 1
	return x, y
end

-- Fires `callback(x, y)` on every left-click that lands on `boardFolder`.
-- Returns a connection to disconnect.
function Input.onBoardClick(boardFolder, callback)
	return UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local x, y = Input.getBoardCellUnderMouse(boardFolder)
		if x then
			callback(x, y)
		end
	end)
end

return Input
