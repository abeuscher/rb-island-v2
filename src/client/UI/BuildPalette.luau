-- Build palette + terrain tools + targeting list. One panel: a column of tool
-- buttons and, below it, a list of the player's own weapons with their current
-- target (if any) and a button to (re)arm targeting for each.
--
-- Buttons are always shown regardless of round -- the shared rules core is the
-- single source of truth for what's unlocked, and its rejection message (e.g.
-- "not unlocked yet") is what the status label surfaces. Duplicating unlock
-- gating here would be a second copy of a rule that already lives in state.luau.

local BuildPalette = {}

local TOOLS = {
	{ id = "place:generator", label = "Build Generator" },
	{ id = "place:cannon", label = "Build Cannon" },
	{ id = "place:mortar", label = "Build Mortar" },
	{ id = "bulldoze", label = "Bulldoze" },
	{ id = "raise", label = "Raise Terrain" },
	{ id = "lower", label = "Lower Terrain" },
	{ id = "reclaim", label = "Reclaim Land" },
}

local function makeButton(text, layoutOrder, parent)
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.new(1, 0, 0, 32)
	button.LayoutOrder = layoutOrder
	button.Text = text
	button.Font = Enum.Font.SourceSans
	button.TextSize = 16
	button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.Parent = parent
	return button
end

-- Builds the panel into `parent` and wires its buttons to `controller`.
-- Returns a handle with `refresh()`, called whenever the controller's state
-- changes so the weapon/target list stays current.
function BuildPalette.mount(parent, controller)
	local frame = Instance.new("Frame")
	frame.Name = "BuildPalette"
	frame.Size = UDim2.new(0, 200, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	frame.BackgroundTransparency = 0.2
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local activeTool = nil
	local toolButtons = {}

	local function setActive(id)
		activeTool = id
		for buttonId, button in pairs(toolButtons) do
			button.BackgroundColor3 = buttonId == id and Color3.fromRGB(80, 110, 80) or Color3.fromRGB(45, 45, 45)
		end
	end

	for order, tool in ipairs(TOOLS) do
		local button = makeButton(tool.label, order, frame)
		toolButtons[tool.id] = button
		button.MouseButton1Click:Connect(function()
			controller:setTool(tool.id)
			setActive(tool.id)
		end)
	end

	local weaponHeader = Instance.new("TextLabel")
	weaponHeader.Name = "WeaponHeader"
	weaponHeader.Size = UDim2.new(1, 0, 0, 24)
	weaponHeader.LayoutOrder = #TOOLS + 1
	weaponHeader.Text = "Weapons"
	weaponHeader.Font = Enum.Font.SourceSansBold
	weaponHeader.TextSize = 16
	weaponHeader.BackgroundTransparency = 1
	weaponHeader.TextColor3 = Color3.fromRGB(240, 240, 240)
	weaponHeader.Parent = frame

	local weaponList = Instance.new("Frame")
	weaponList.Name = "WeaponList"
	weaponList.Size = UDim2.new(1, 0, 0, 0)
	weaponList.AutomaticSize = Enum.AutomaticSize.Y
	weaponList.LayoutOrder = #TOOLS + 2
	weaponList.BackgroundTransparency = 1
	weaponList.Parent = frame

	local weaponListLayout = Instance.new("UIListLayout")
	weaponListLayout.Padding = UDim.new(0, 2)
	weaponListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	weaponListLayout.Parent = weaponList

	local function refresh()
		for _, child in ipairs(weaponList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for order, weapon in ipairs(controller:getWeapons()) do
			local targetText = weapon.target and string.format("-> (%d, %d)", weapon.target.x, weapon.target.y)
				or "-> unassigned"
			local button = makeButton(
				string.format("%s (%d,%d) %s", weapon.typeId, weapon.x, weapon.y, targetText),
				order,
				weaponList
			)
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.MouseButton1Click:Connect(function()
				controller:armTarget(weapon.key)
				setActive(nil)
			end)
		end
	end

	refresh()

	return { refresh = refresh }
end

return BuildPalette
