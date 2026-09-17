local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Config = require(ReplicatedStorage.Shared.config)
local ClientBoard = require(script.Board)
local Camera = require(script.Camera)

-- TEMPORARY: round 1 starts fully flat (§3), so there's nothing at levels 1/2
-- to look at yet. Bump a small pyramid on each island purely so elevation
-- rendering can be checked visually in Studio; remove once terrain-editing
-- commands can produce real elevation instead.
local function seedDemoElevation(board)
	local function raise(x, y)
		board = (Board.raise(board, x, y))
	end
	for _, x in ipairs({ 11, 12, 13 }) do
		for _, y in ipairs({ 11, 12, 13 }) do
			raise(x, y)
		end
	end
	raise(12, 12)
	for _, x in ipairs({ 28, 29, 30 }) do
		for _, y in ipairs({ 11, 12, 13 }) do
			raise(x, y)
		end
	end
	raise(29, 12)
	return board
end

local board = seedDemoElevation(Board.new(Config))

local boardFolder = Instance.new("Folder")
boardFolder.Name = "Board"
boardFolder.Parent = Workspace

ClientBoard.build(boardFolder, board)
Camera.start("A")
