-- Grid, territory, elevation, terrain editing, and land reclamation.
-- Pure: every mutating function returns a new board and leaves its input untouched.

local Board = {}

local NEIGHBOR_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Board.new(config)
	local width = config.BOARD_WIDTH
	local height = config.BOARD_HEIGHT
	local channelWidth = config.CHANNEL_WIDTH
	local islandSize = config.ISLAND_SIZE

	local sideWidth = (width - channelWidth) / 2
	assert(sideWidth == math.floor(sideWidth), "BOARD_WIDTH and CHANNEL_WIDTH must split evenly into two territories")

	local channelStart = sideWidth + 1
	local channelEnd = sideWidth + channelWidth
	local islandRowStart = math.floor((height - islandSize) / 2) + 1
	local islandRowEnd = islandRowStart + islandSize - 1

	local cells = {}
	for x = 1, width do
		cells[x] = {}
		for y = 1, height do
			local owner = nil
			if x < channelStart then
				owner = "A"
			elseif x > channelEnd then
				owner = "B"
			end

			local land = false
			local inIslandRow = y >= islandRowStart and y <= islandRowEnd
			if owner == "A" and x >= channelStart - islandSize and inIslandRow then
				land = true
			elseif owner == "B" and x <= channelEnd + islandSize and inIslandRow then
				land = true
			end

			cells[x][y] = { elevation = 0, land = land, owner = owner }
		end
	end

	return {
		width = width,
		height = height,
		channelWidth = channelWidth,
		channelStart = channelStart,
		channelEnd = channelEnd,
		maxElevation = config.MAX_ELEVATION,
		cells = cells,
	}
end

-- Each player's starting-island rectangle, derived from config alone (no board
-- instance needed) -- lets a caller place things relative to an island's edges
-- without walking every owned cell. Mirrors Board.new's own territory math.
function Board.islandBounds(config, owner)
	local width = config.BOARD_WIDTH
	local height = config.BOARD_HEIGHT
	local channelWidth = config.CHANNEL_WIDTH
	local islandSize = config.ISLAND_SIZE
	local sideWidth = (width - channelWidth) / 2
	local channelStart = sideWidth + 1
	local channelEnd = sideWidth + channelWidth
	local rowStart = math.floor((height - islandSize) / 2) + 1
	local rowEnd = rowStart + islandSize - 1

	if owner == "A" then
		return channelStart - islandSize, channelStart - 1, rowStart, rowEnd
	end
	return channelEnd + 1, channelEnd + islandSize, rowStart, rowEnd
end

function Board.inBounds(board, x, y)
	return x >= 1 and x <= board.width and y >= 1 and y <= board.height
end

function Board.getCell(board, x, y)
	if not Board.inBounds(board, x, y) then
		return nil
	end
	return board.cells[x][y]
end

function Board.ownerOf(board, x, y)
	local cell = Board.getCell(board, x, y)
	return cell and cell.owner or nil
end

function Board.isChannel(board, x, y)
	local cell = Board.getCell(board, x, y)
	return cell ~= nil and cell.owner == nil
end

function Board.isLand(board, x, y)
	local cell = Board.getCell(board, x, y)
	return cell ~= nil and cell.land
end

function Board.elevationAt(board, x, y)
	local cell = Board.getCell(board, x, y)
	return cell and cell.elevation or 0
end

local function isSmooth(board, x, y, elevation)
	for _, offset in ipairs(NEIGHBOR_OFFSETS) do
		local neighbor = Board.getCell(board, x + offset[1], y + offset[2])
		if neighbor and neighbor.land and math.abs(neighbor.elevation - elevation) > 1 then
			return false
		end
	end
	return true
end

-- Structural sharing: only the touched column is rebuilt, every other column is reused.
local function withCell(board, x, y, elevation, land)
	local cells = {}
	for cx = 1, board.width do
		if cx == x then
			cells[cx] = {}
			for cy = 1, board.height do
				if cy == y then
					local cell = board.cells[cx][cy]
					cells[cx][cy] = { elevation = elevation, land = land, owner = cell.owner }
				else
					cells[cx][cy] = board.cells[cx][cy]
				end
			end
		else
			cells[cx] = board.cells[cx]
		end
	end

	local newBoard = table.clone(board)
	newBoard.cells = cells
	return newBoard
end

function Board.raise(board, x, y)
	local cell = Board.getCell(board, x, y)
	if not cell then
		return board, false, "out of bounds"
	end
	if not cell.land then
		return board, false, "cell is not land"
	end

	local newElevation = cell.elevation + 1
	if newElevation > board.maxElevation then
		return board, false, "already at max elevation"
	end
	if not isSmooth(board, x, y, newElevation) then
		return board, false, "would violate the smoothness constraint"
	end

	return withCell(board, x, y, newElevation, true), true, nil
end

function Board.lower(board, x, y)
	local cell = Board.getCell(board, x, y)
	if not cell then
		return board, false, "out of bounds"
	end
	if not cell.land then
		return board, false, "cell is not land"
	end

	local newElevation = cell.elevation - 1
	if newElevation < 0 then
		return board, false, "already at minimum elevation"
	end
	if not isSmooth(board, x, y, newElevation) then
		return board, false, "would violate the smoothness constraint"
	end

	return withCell(board, x, y, newElevation, true), true, nil
end

function Board.reclaim(board, owner, x, y)
	local cell = Board.getCell(board, x, y)
	if not cell then
		return board, false, "out of bounds"
	end
	if cell.owner ~= owner then
		return board, false, "not in your territory"
	end
	if cell.land then
		return board, false, "cell is already land"
	end

	local adjacentToOwnLand = false
	for _, offset in ipairs(NEIGHBOR_OFFSETS) do
		local neighbor = Board.getCell(board, x + offset[1], y + offset[2])
		if neighbor and neighbor.land and neighbor.owner == owner then
			adjacentToOwnLand = true
			break
		end
	end
	if not adjacentToOwnLand then
		return board, false, "must be adjacent to your own land"
	end

	if not isSmooth(board, x, y, 0) then
		return board, false, "would violate the smoothness constraint"
	end

	return withCell(board, x, y, 0, true), true, nil
end

return Board
