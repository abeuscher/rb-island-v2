-- Bottom-right info card for a weapon selected on the battlefield (§21):
-- live stats (range, damage, cooldown, current target) and the auto-fire
-- enable/disable control. A plain UIListLayout column, so upgrade controls
-- (not built yet -- see the plan entry's own note) can be appended as further
-- rows later without reworking the card itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Board = require(ReplicatedStorage.Shared.board)
local Flight = require(ReplicatedStorage.Shared.flight)

local WeaponInfoCard = {}

local STATUS_COLOR = Color3.fromRGB(220, 220, 220)
local NOT_POWERED_COLOR = Color3.fromRGB(230, 130, 60)

local function makeStatLabel(name, layoutOrder, parent)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 18)
	label.LayoutOrder = layoutOrder
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.Parent = parent
	return label
end

function WeaponInfoCard.mount(parent, controller)
	local frame = Instance.new("Frame")
	frame.Name = "WeaponInfoCard"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -8, 1, -40)
	frame.Size = UDim2.new(0, 220, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	frame.BackgroundTransparency = 0.2
	frame.Visible = false
	frame.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.LayoutOrder = 1
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.Parent = frame

	local rangeLabel = makeStatLabel("Range", 2, frame)
	local damageLabel = makeStatLabel("Damage", 3, frame)
	local cooldownLabel = makeStatLabel("Cooldown", 4, frame)
	local statusLabel = makeStatLabel("Status", 5, frame)
	local targetLabel = makeStatLabel("Target", 6, frame)

	local autoFireButton = Instance.new("TextButton")
	autoFireButton.Name = "AutoFireButton"
	autoFireButton.Size = UDim2.new(1, 0, 0, 28)
	autoFireButton.LayoutOrder = 7
	autoFireButton.Font = Enum.Font.SourceSansBold
	autoFireButton.TextSize = 15
	autoFireButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	autoFireButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	autoFireButton.Parent = frame

	local currentWeapon = nil
	autoFireButton.MouseButton1Click:Connect(function()
		if currentWeapon then
			controller:setAutoFire(currentWeapon, not currentWeapon.autoFire)
		end
	end)

	local function refresh()
		local weapon = controller:getSelectedWeapon()
		currentWeapon = weapon
		frame.Visible = weapon ~= nil
		if not weapon then
			return
		end

		local def = controller.config.STRUCTURES[weapon.typeId]
		local elevation = Board.elevationAt(controller.state.board, weapon.x, weapon.y)

		title.Text = string.format("%s (%d, %d)", def.display_name, weapon.x, weapon.y)
		rangeLabel.Text = string.format("Range: %d", Flight.range(def, elevation))
		damageLabel.Text = string.format("Damage: %d", def.damage)
		cooldownLabel.Text = string.format("Cooldown: %ds", def.cooldown_seconds)

		if weapon.underConstruction then
			statusLabel.Text = "Status: building"
			statusLabel.TextColor3 = STATUS_COLOR
		else
			local secondsLeft = math.max(0, (weapon.nextFireAt or 0) - controller.state.elapsed)
			if secondsLeft > 0 then
				statusLabel.Text = string.format("Status: cooling %ds", math.ceil(secondsLeft))
				statusLabel.TextColor3 = STATUS_COLOR
			elseif not weapon.powered then
				statusLabel.Text = "Status: not powered"
				statusLabel.TextColor3 = NOT_POWERED_COLOR
			else
				statusLabel.Text = "Status: ready"
				statusLabel.TextColor3 = STATUS_COLOR
			end
		end

		targetLabel.Text = weapon.target and string.format("Target: (%d, %d)", weapon.target.x, weapon.target.y)
			or "Target: none"

		autoFireButton.Text = weapon.autoFire and "Auto-Fire: ON" or "Auto-Fire: OFF"
		autoFireButton.BackgroundColor3 = weapon.autoFire and Color3.fromRGB(80, 110, 80) or Color3.fromRGB(60, 60, 60)
	end

	refresh()
	return { refresh = refresh }
end

return WeaponInfoCard
