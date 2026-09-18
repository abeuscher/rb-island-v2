-- Resolve-phase volley animation (projectiles, impacts, rubble) and enemy-board
-- reveal rendering. Terrain is already fully rendered for both territories by
-- Board.luau (§11: terrain is always public) -- this only draws what the belief
-- map says is built on the enemy island, plus a subtle marker over cells that
-- haven't been revealed yet, per §11's "landscape, not a wall."

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.board)
local Fog = require(ReplicatedStorage.Shared.fog)

local Render = {}

local TRAVEL_TIME = 0.9
local IMPACT_HOLD = 0.6
local ARC_HEIGHT_STUDS = 12

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
local UNKNOWN_COLOR = Color3.fromRGB(90, 90, 90)
local RUBBLE_COLOR = Color3.fromRGB(60, 55, 50)
local PROJECTILE_COLORS = {
	direct = Color3.fromRGB(250, 220, 120),
	arc = Color3.fromRGB(250, 160, 90),
	scout = Color3.fromRGB(150, 220, 230),
}

local function cellKey(x, y)
	return x .. "," .. y
end

local function cellCenter(config, x, y)
	local s = config.STUDS_PER_CELL
	return (x - 0.5) * s, (y - 0.5) * s
end

local function cellTop(config, board, x, y)
	return (Board.elevationAt(board, x, y) + 1) * config.STUDS_PER_CELL
end

local function makePart(name, size, position, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
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

local function spawnRubble(config, board, parent, x, y)
	local cx, cz = cellCenter(config, x, y)
	local top = cellTop(config, board, x, y)
	makePart(
		string.format("Rubble_%d_%d", x, y),
		Vector3.new(config.STUDS_PER_CELL * 0.8, config.STUDS_PER_CELL * 0.4, config.STUDS_PER_CELL * 0.8),
		Vector3.new(cx, top + config.STUDS_PER_CELL * 0.2, cz),
		RUBBLE_COLOR,
		Enum.Material.Slate,
		parent
	)
end

local function spawnImpact(config, board, parent, cell, blocked)
	local x, z = cellCenter(config, cell.x, cell.y)
	local y = cellTop(config, board, cell.x, cell.y)
	local impact = makePart(
		"Impact",
		Vector3.new(1, 1, 1),
		Vector3.new(x, y + config.STUDS_PER_CELL / 2, z),
		blocked and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(255, 140, 60),
		Enum.Material.Neon,
		parent
	)
	local goalSize = blocked and Vector3.new(3, 3, 3) or Vector3.new(5, 5, 5)
	TweenService:Create(impact, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = goalSize,
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		impact:Destroy()
	end)
end

-- Draws (or clears) one enemy cell's belief-map state: an "unknown" marker if
-- never revealed, rubble, a structure, or nothing extra for confirmed-empty land.
-- Always replaces whatever was there before, so this is safe to call repeatedly
-- as a cell's belief changes -- both the full-board render and the progressive
-- reveal during a shot's flight (below) go through this same function.
local function renderEnemyCell(config, board, belief, parent, x, y)
	local existing = parent:FindFirstChild(string.format("Cell_%d_%d", x, y))
	if existing then
		existing:Destroy()
	end

	local cell = belief[cellKey(x, y)]
	if not cell then
		local cx, cz = cellCenter(config, x, y)
		local top = cellTop(config, board, x, y)
		makePart(
			string.format("Cell_%d_%d", x, y),
			Vector3.new(config.STUDS_PER_CELL * 0.9, 0.15, config.STUDS_PER_CELL * 0.9),
			Vector3.new(cx, top + 0.08, cz),
			UNKNOWN_COLOR,
			Enum.Material.SmoothPlastic,
			parent
		)
	elseif cell.rubble then
		local cx, cz = cellCenter(config, x, y)
		local top = cellTop(config, board, x, y)
		makePart(
			string.format("Cell_%d_%d", x, y),
			Vector3.new(config.STUDS_PER_CELL * 0.8, config.STUDS_PER_CELL * 0.4, config.STUDS_PER_CELL * 0.8),
			Vector3.new(cx, top + config.STUDS_PER_CELL * 0.2, cz),
			RUBBLE_COLOR,
			Enum.Material.Slate,
			parent
		)
	elseif cell.typeId then
		local def = config.STRUCTURES[cell.typeId]
		local cx, cz = cellCenter(config, x, y)
		local top = cellTop(config, board, x, y)
		local part = makePart(
			string.format("Cell_%d_%d", x, y),
			Vector3.new(
				def.footprint * config.STUDS_PER_CELL * 0.7,
				config.STUDS_PER_CELL,
				def.footprint * config.STUDS_PER_CELL * 0.7
			),
			Vector3.new(cx, top + config.STUDS_PER_CELL / 2, cz),
			STRUCTURE_COLORS[cell.typeId] or Color3.fromRGB(200, 200, 200),
			Enum.Material.SmoothPlastic,
			parent
		)
		part.Transparency = cell.underConstruction and 0.5 or 0
		addGlyph(part, GLYPHS[cell.typeId] or "?")
	end
	-- cell.empty: confirmed nothing there -- leave it as plain terrain.
end

-- Animates one shot's projectile from its firing structure to where it actually
-- landed (`shot.shot.impactCell` -- already the blocking cell for a blocked direct
-- shot per flight.luau, so this needs no separate beam-path handling to visibly
-- stop short at a ridge). Calls `onProgress(t)` every frame (0 to 1 across the
-- flight) and `onImpact` when the projectile arrives.
local function animateShot(config, board, parent, shot, onProgress, onImpact)
	local def = shot.def
	local impactCell = shot.shot.impactCell
	local sx, sz = cellCenter(config, shot.origin.x, shot.origin.y)
	local sy = cellTop(config, board, shot.origin.x, shot.origin.y) + config.STUDS_PER_CELL / 2
	local ex, ez = cellCenter(config, impactCell.x, impactCell.y)
	local ey = cellTop(config, board, impactCell.x, impactCell.y) + config.STUDS_PER_CELL / 4

	local projectile = makePart(
		"Projectile",
		Vector3.new(1, 1, 1),
		Vector3.new(sx, sy, sz),
		PROJECTILE_COLORS[def.fire_mode] or Color3.fromRGB(240, 240, 240),
		Enum.Material.Neon,
		parent
	)

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / TRAVEL_TIME, 0, 1)
		local x = sx + (ex - sx) * t
		local z = sz + (ez - sz) * t
		local y = sy + (ey - sy) * t
		if def.fire_mode == "arc" then
			y += math.sin(t * math.pi) * ARC_HEIGHT_STUDS
		end
		projectile.Position = Vector3.new(x, y, z)
		if onProgress then
			onProgress(t)
		end
		if t >= 1 then
			connection:Disconnect()
			projectile:Destroy()
			onImpact()
		end
	end)
end

-- `effectsFolder` holds the transient resolve animation (projectiles, impacts, and
-- rubble for structures destroyed this round, on either side). `enemyFolder` holds
-- the persistent belief-map render of the enemy island. `controller.enemy` names
-- the other side; terrain for both islands is already drawn by Board.luau.
function Render.mount(effectsFolder, enemyFolder, controller)
	local config = controller.config

	local function renderEnemyBoard()
		enemyFolder:ClearAllChildren()
		local board = controller.state.board
		local belief = controller.state.self.belief

		for x = 1, board.width do
			for y = 1, board.height do
				if Board.ownerOf(board, x, y) == controller.enemy and Board.isLand(board, x, y) then
					renderEnemyCell(config, board, belief, enemyFolder, x, y)
				end
			end
		end
	end

	-- Enemy belief only ever changes via a reveal (§11, confirmed in fog.luau --
	-- nothing else touches it), and onResolve below already repaints exactly the
	-- cells a reveal touches, progressively as each shot's beam crosses them. So
	-- this is a one-time initial draw, not a per-tick hook: redrawing the whole
	-- board on every onChange would repaint already-revealed cells from the
	-- current belief before the animation gets to them, making the reveal look
	-- instant instead of tracing in.
	renderEnemyBoard()

	controller:onResolve(function(preState, shots, destroyed, newBelief)
		effectsFolder:ClearAllChildren()

		local function finish()
			for _, structure in ipairs(destroyed) do
				spawnRubble(config, preState.board, effectsFolder, structure.x, structure.y)
			end
			task.delay(IMPACT_HOLD, function()
				controller:commitResolve()
			end)
		end

		local remaining = #shots
		if remaining == 0 then
			finish()
			return
		end

		for _, shot in ipairs(shots) do
			-- Only the player's own shots reveal anything new -- the dummy's shots
			-- target the player's own island, which has no fog to clear. Direct fire
			-- reveals its beam path as the shell physically crosses each cell; every
			-- shot reveals its full footprint (impact, plus splash neighbors for a
			-- mortar) the instant it lands, rather than waiting for the round to
			-- fully commit.
			local isOwnShot = shot.owner == controller.owner
			local revealed = {}
			-- A beam path can cross the channel, and even the near end of it can still
			-- be over the firing player's own territory -- only the far end is ever a
			-- belief-map cell worth (re)drawing.
			local function reveal(cell)
				if Board.ownerOf(preState.board, cell.x, cell.y) ~= controller.enemy or not Board.isLand(preState.board, cell.x, cell.y) then
					return
				end
				local key = cellKey(cell.x, cell.y)
				if not revealed[key] then
					revealed[key] = true
					renderEnemyCell(config, preState.board, newBelief, enemyFolder, cell.x, cell.y)
				end
			end

			local onProgress = nil
			if isOwnShot and shot.def.fire_mode == "direct" then
				local beamPath = shot.shot.beamPath
				local totalSteps = #beamPath + 1
				onProgress = function(t)
					local passed = math.min(math.floor(t * totalSteps), #beamPath)
					for i = 1, passed do
						reveal(beamPath[i])
					end
				end
			end

			animateShot(config, preState.board, effectsFolder, shot, onProgress, function()
				if isOwnShot then
					for _, cell in ipairs(Fog.revealedCells(shot.def, shot.shot)) do
						reveal(cell)
					end
				end
				spawnImpact(config, preState.board, effectsFolder, shot.shot.impactCell, shot.shot.blocked)
				remaining -= 1
				if remaining == 0 then
					finish()
				end
			end)
		end
	end)

	return {}
end

return Render
