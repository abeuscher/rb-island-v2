-- Placeholder rendering for the player's own placed structures and assigned
-- targets, per §13's placeholder-first contract (colored part + glyph). Full
-- reveal-aware rendering of both sides belongs to the Resolve-phase session's
-- Render.luau -- this only ever draws the owner's own board, which is always
-- fully visible to them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Board = require(ReplicatedStorage.Shared.board)

local StructureView = {}

local STRUCTURE_COLORS = {
	base = Color3.fromRGB(70, 130, 200),
	generator = Color3.fromRGB(224, 200, 40),
	cannon = Color3.fromRGB(180, 60, 50),
	mortar = Color3.fromRGB(120, 70, 170),
	missile = Color3.fromRGB(210, 90, 40),
	scout = Color3.fromRGB(90, 200, 210),
}
local GLYPHS = {
	base = "\u{2302}",
	generator = "\u{26A1}",
	cannon = "\u{25B2}",
	mortar = "\u{25D3}",
	missile = "\u{2191}",
	scout = "\u{25C9}",
}
local TARGET_COLOR = Color3.fromRGB(220, 40, 40)
local AUTO_FIRE_COLOR = Color3.fromRGB(255, 210, 60)

local function structureCenter(config, x, y, size)
	local s = config.STUDS_PER_CELL
	return (x + size / 2 - 1) * s, (y + size / 2 - 1) * s
end

local function makePart(size, position, color, transparency, name, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.Transparency = transparency
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function addGlyph(parent, text)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 32, 0, 32)
	billboard.StudsOffset = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Parent = billboard
end

-- A small gold dot offset from the type glyph, live weapons only (§21) --
-- autoFire = true is the state worth calling out at a glance, since autoFire =
-- false (manual re-arm after every shot) is already every weapon's default
-- look. Under construction stays distinguished purely by the existing
-- transparency, not this marker, regardless of the flag's value underneath.
local function addAutoFireMarker(parent)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 14, 0, 14)
	billboard.StudsOffset = Vector3.new(0.9, 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(1, 0, 1, 0)
	dot.BackgroundColor3 = AUTO_FIRE_COLOR
	dot.BorderSizePixel = 0
	dot.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
end

function StructureView.render(parent, controller)
	parent:ClearAllChildren()

	local config = controller.config
	local board = controller.state.board
	local studsPerCell = config.STUDS_PER_CELL

	for _, structure in ipairs(controller.state.self.structures) do
		local def = config.STRUCTURES[structure.typeId]
		local elevation = Board.elevationAt(board, structure.x, structure.y)
		local centerX, centerZ = structureCenter(config, structure.x, structure.y, def.footprint)
		local top = (elevation + 1) * studsPerCell
		local part = makePart(
			Vector3.new(def.footprint * studsPerCell * 0.7, studsPerCell, def.footprint * studsPerCell * 0.7),
			Vector3.new(centerX, top + studsPerCell / 2, centerZ),
			STRUCTURE_COLORS[structure.typeId] or Color3.fromRGB(200, 200, 200),
			structure.underConstruction and 0.5 or 0,
			string.format("%s_%d_%d", structure.typeId, structure.x, structure.y),
			parent
		)
		addGlyph(part, GLYPHS[structure.typeId] or "?")
		if structure.autoFire and not structure.underConstruction then
			addAutoFireMarker(part)
		end
	end

	-- Read straight off each weapon's own `.target` (own structures are always
	-- fully visible) rather than a separate client-side cache, so the marker
	-- can never show a target the weapon isn't actually the one firing at.
	for _, structure in ipairs(controller.state.self.structures) do
		local target = structure.target
		if target then
			local elevation = Board.elevationAt(board, target.x, target.y)
			local top = (elevation + 1) * studsPerCell
			makePart(
				Vector3.new(studsPerCell * 0.3, 0.2, studsPerCell * 0.3),
				Vector3.new((target.x - 0.5) * studsPerCell, top + 0.1, (target.y - 0.5) * studsPerCell),
				TARGET_COLOR,
				0,
				string.format("Target_%d_%d", target.x, target.y),
				parent
			)
		end
	end
end

return StructureView
