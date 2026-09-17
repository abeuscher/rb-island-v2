-- Builds the placeholder terrain from the shared board model: one cube per land
-- cell (height and color carry the elevation level), one water plate underneath.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Config = require(ReplicatedStorage.Shared.config)

local ClientBoard = {}

local LEVEL_COLORS = {
	[0] = Color3.fromRGB(91, 154, 76),
	[1] = Color3.fromRGB(168, 142, 78),
	[2] = Color3.fromRGB(150, 150, 150),
}
local WATER_COLOR = Color3.fromRGB(46, 111, 173)
local WATER_THICKNESS = 1

local function makePart(size, position, color, name, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Builds `board` (or a fresh starting board, if none given) into `parent` and
-- returns the board model it rendered.
function ClientBoard.build(parent, board)
	board = board or Board.new(Config)
	local studsPerCell = Config.STUDS_PER_CELL
	local boardWidth = board.width * studsPerCell
	local boardDepth = board.height * studsPerCell

	makePart(
		Vector3.new(boardWidth, WATER_THICKNESS, boardDepth),
		Vector3.new(boardWidth / 2, -WATER_THICKNESS / 2, boardDepth / 2),
		WATER_COLOR,
		"Water",
		parent
	)

	for x = 1, board.width do
		for y = 1, board.height do
			local cell = Board.getCell(board, x, y)
			if cell.land then
				local cellHeight = (cell.elevation + 1) * studsPerCell
				local position = Vector3.new((x - 0.5) * studsPerCell, cellHeight / 2, (y - 0.5) * studsPerCell)
				makePart(
					Vector3.new(studsPerCell, cellHeight, studsPerCell),
					position,
					LEVEL_COLORS[cell.elevation],
					string.format("Cell_%d_%d", x, y),
					parent
				)
			end
		end
	end

	return board
end

return ClientBoard
