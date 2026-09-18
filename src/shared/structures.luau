-- Structure placement, bulldozing, and build-time. Roster data lives in config.STRUCTURES;
-- this module only adds behavior on top of it.

local Board = require("./board")

local Structures = {}

local function footprintCells(roster, typeId, x, y)
	local size = roster[typeId].footprint
	local cells = {}
	for dx = 0, size - 1 do
		for dy = 0, size - 1 do
			table.insert(cells, { x = x + dx, y = y + dy })
		end
	end
	return cells
end

function Structures.new()
	return {}
end

function Structures.occupiedCells(roster, structure)
	return footprintCells(roster, structure.typeId, structure.x, structure.y)
end

function Structures.at(roster, list, x, y)
	for _, structure in ipairs(list) do
		for _, cell in ipairs(Structures.occupiedCells(roster, structure)) do
			if cell.x == x and cell.y == y then
				return structure
			end
		end
	end
	return nil
end

function Structures.canPlace(config, board, list, owner, typeId, x, y, elapsed)
	local def = config.STRUCTURES[typeId]
	if not def then
		return false, "unknown structure type"
	end
	if elapsed < def.unlock_time then
		return false, "not unlocked yet"
	end

	for _, cell in ipairs(footprintCells(config.STRUCTURES, typeId, x, y)) do
		if not Board.inBounds(board, cell.x, cell.y) then
			return false, "out of bounds"
		end
		if Board.ownerOf(board, cell.x, cell.y) ~= owner then
			return false, "not in your territory"
		end
		if not Board.isLand(board, cell.x, cell.y) then
			return false, "cell is not land"
		end
		if Structures.at(config.STRUCTURES, list, cell.x, cell.y) then
			return false, "cell is occupied"
		end
	end

	return true, nil
end

function Structures.place(config, board, list, owner, typeId, x, y, elapsed)
	local ok, err = Structures.canPlace(config, board, list, owner, typeId, x, y, elapsed)
	if not ok then
		return list, false, err
	end

	local def = config.STRUCTURES[typeId]
	local newList = table.clone(list)
	table.insert(newList, {
		typeId = typeId,
		x = x,
		y = y,
		hp = math.floor(def.hp / 2),
		underConstruction = true,
		readyAt = elapsed + config.BUILD_SECONDS,
		target = nil,
		nextFireAt = 0,
		-- Single shot by default: firing clears the target (rules.luau's
		-- applyCooldowns), so it takes a fresh target command to fire again.
		-- autoFire = true keeps firing on its own target every cooldown instead --
		-- the "Weapon inspection and control panel" plan entry's own toggle,
		-- not yet exposed to a real player (Session 015).
		autoFire = false,
	})
	return newList, true, nil
end

function Structures.bulldoze(config, list, x, y)
	local target = Structures.at(config.STRUCTURES, list, x, y)
	if not target then
		return list, false, "no structure there"
	end

	local newList = {}
	for _, structure in ipairs(list) do
		if structure ~= target then
			table.insert(newList, structure)
		end
	end
	return newList, true, nil
end

-- Ticks construction forward: a structure whose readyAt has passed goes live at
-- full HP. Structures not yet ready pass through unchanged.
function Structures.completeConstruction(config, list, elapsed)
	local newList = {}
	for _, structure in ipairs(list) do
		if structure.underConstruction and elapsed >= structure.readyAt then
			local def = config.STRUCTURES[structure.typeId]
			local updated = table.clone(structure)
			updated.underConstruction = false
			updated.hp = def.hp
			table.insert(newList, updated)
		else
			table.insert(newList, structure)
		end
	end
	return newList
end

-- Sets (or clears, with targetX/targetY nil) the persistent target a weapon fires
-- at whenever it's off-cooldown, in range, and unblocked -- assigned once, not
-- resupplied every round.
function Structures.setTarget(config, list, x, y, targetX, targetY)
	local target = Structures.at(config.STRUCTURES, list, x, y)
	if not target or not config.STRUCTURES[target.typeId].fire_mode then
		return list, false, "no weapon there"
	end

	local newList = {}
	for _, structure in ipairs(list) do
		if structure == target then
			local updated = table.clone(structure)
			updated.target = targetX and { x = targetX, y = targetY } or nil
			table.insert(newList, updated)
		else
			table.insert(newList, structure)
		end
	end
	return newList, true, nil
end

-- Applies damage to whatever structure occupies (x, y), regardless of footprint size
-- or construction state -- half-built structures are still standing targets.
-- Returns (list, hit, destroyed, destroyedStructure); destroyedStructure is the
-- pre-damage structure so callers can still read its typeId and footprint.
function Structures.damage(config, list, x, y, amount)
	local target = Structures.at(config.STRUCTURES, list, x, y)
	if not target then
		return list, false, false, nil
	end

	local newHp = target.hp - amount
	local newList = {}
	if newHp > 0 then
		for _, structure in ipairs(list) do
			if structure == target then
				local updated = table.clone(structure)
				updated.hp = newHp
				table.insert(newList, updated)
			else
				table.insert(newList, structure)
			end
		end
		return newList, true, false, nil
	end

	for _, structure in ipairs(list) do
		if structure ~= target then
			table.insert(newList, structure)
		end
	end
	return newList, true, true, target
end

function Structures.countLive(list, typeId)
	local count = 0
	for _, structure in ipairs(list) do
		if structure.typeId == typeId and not structure.underConstruction then
			count += 1
		end
	end
	return count
end

return Structures
