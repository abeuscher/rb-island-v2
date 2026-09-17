-- Scriptable angled top-down camera, panned and zoomed within one player's own
-- territory. Tab swings the framing to the other player's territory.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local Camera = {}

local PITCH = math.rad(55)
local HALF_FOV = math.rad(35)
local MARGIN_STUDS = 12
local MIN_ZOOM = 0.6
local MAX_ZOOM = 1.6
local ZOOM_STEP = 0.1
local PAN_SPEED = 40
local SWING_TIME = 0.6

local function territoryBounds(owner)
	local studsPerCell = Config.STUDS_PER_CELL
	local sideWidth = (Config.BOARD_WIDTH - Config.CHANNEL_WIDTH) / 2
	local minX, maxX
	if owner == "A" then
		minX, maxX = 0, sideWidth * studsPerCell
	else
		minX, maxX = (sideWidth + Config.CHANNEL_WIDTH) * studsPerCell, Config.BOARD_WIDTH * studsPerCell
	end
	local minZ, maxZ = 0, Config.BOARD_HEIGHT * studsPerCell
	local centerX, centerZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	return minX, maxX, minZ, maxZ, centerX, centerZ
end

-- Starts framing `owner`'s ("A" or "B") territory and returns a handle with `stop()`.
function Camera.start(owner)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local side = owner or "A"
	local minX, maxX, minZ, maxZ, centerX, centerZ = territoryBounds(side)
	local focus = Vector2.new(centerX, centerZ)
	local zoom = 1

	local function apply()
		local span = math.max(maxX - minX, maxZ - minZ) + MARGIN_STUDS * 2
		local distance = (span / 2) / math.tan(HALF_FOV) * zoom
		local focusPosition = Vector3.new(focus.X, 0, focus.Y)
		local cameraPosition = focusPosition + Vector3.new(0, distance * math.sin(PITCH), distance * math.cos(PITCH))
		camera.CFrame = CFrame.lookAt(cameraPosition, focusPosition)
	end

	apply()

	local connections = {}
	local swingConnection = nil

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.Tab then
				return
			end

			side = side == "A" and "B" or "A"
			minX, maxX, minZ, maxZ, centerX, centerZ = territoryBounds(side)

			if swingConnection then
				swingConnection:Disconnect()
			end

			local startFocus = focus
			local targetFocus = Vector2.new(centerX, centerZ)
			local elapsed = 0
			swingConnection = RunService.RenderStepped:Connect(function(dt)
				elapsed += dt
				local t = math.clamp(elapsed / SWING_TIME, 0, 1)
				focus = startFocus:Lerp(targetFocus, t)
				apply()
				if t >= 1 then
					swingConnection:Disconnect()
					swingConnection = nil
				end
			end)
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			zoom = math.clamp(zoom - input.Position.Z * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			apply()
		end)
	)

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			if swingConnection then
				return
			end

			local dx, dz = 0, 0
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				dx -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				dx += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
				dz -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
				dz += 1
			end
			if dx == 0 and dz == 0 then
				return
			end

			local moved = Vector2.new(dx, dz).Unit * PAN_SPEED * dt
			local newFocus = focus + moved
			focus = Vector2.new(math.clamp(newFocus.X, minX, maxX), math.clamp(newFocus.Y, minZ, maxZ))
			apply()
		end)
	)

	return {
		stop = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end,
	}
end

return Camera
