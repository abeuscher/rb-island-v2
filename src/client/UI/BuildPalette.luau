-- Build palette + terrain tools + targeting list. One panel: a column of tool
-- buttons and, below it, a list of the player's own weapons with their current
-- target (if any) and a button to (re)arm targeting for each.
--
-- Buttons are always shown regardless of round -- the shared rules core is the
-- single source of truth for what's unlocked, and its rejection message (e.g.
-- "not unlocked yet") is what the status label surfaces. Duplicating unlock
-- gating here would be a second copy of a rule that already lives in state.luau.

local BuildPalette = {}

-- Setup only ever offers base placement (§8: "3 placed during setup", not bought
-- with Supply during PLAN) -- once rounds start, base is never offered again.
local TOOLS_SETUP = {
	{ id = "place:base", label = "Place Base" },
	{ id = "bulldoze", label = "Bulldoze" },
}
local TOOLS_ROUNDS = {
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

	local toolFrame = Instance.new("Frame")
	toolFrame.Name = "Tools"
	toolFrame.Size = UDim2.new(1, 0, 0, 0)
	toolFrame.AutomaticSize = Enum.AutomaticSize.Y
	toolFrame.LayoutOrder = 1
	toolFrame.BackgroundTransparency = 1
	toolFrame.Parent = frame

	local toolLayout = Instance.new("UIListLayout")
	toolLayout.Padding = UDim.new(0, 4)
	toolLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toolLayout.Parent = toolFrame

	-- The tool set only ever changes once, from setup's restricted set to the
	-- full round set, so this only rebuilds the buttons on that one transition.
	local builtForPhase = nil
	local function rebuildTools()
		local phase = controller.phase
		if builtForPhase == phase then
			return
		end
		builtForPhase = phase

		for _, child in ipairs(toolFrame:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		toolButtons = {}

		local tools = (phase == "setup") and TOOLS_SETUP or TOOLS_ROUNDS
		for order, tool in ipairs(tools) do
			local button = makeButton(tool.label, order, toolFrame)
			toolButtons[tool.id] = button
			button.MouseButton1Click:Connect(function()
				controller:setTool(tool.id)
				setActive(tool.id)
			end)
		end

		-- Setup only ever offers base placement + bulldoze, and placing bases is
		-- the only thing to do first -- pre-select it so the player isn't forced
		-- to click a tool before their first placement. Rounds has no single
		-- obvious default, so it starts with nothing armed as before.
		if phase == "setup" then
			controller:setTool("place:base")
			setActive("place:base")
		else
			controller:setTool("none")
			setActive(nil)
		end
	end

	local weaponHeader = Instance.new("TextLabel")
	weaponHeader.Name = "WeaponHeader"
	weaponHeader.Size = UDim2.new(1, 0, 0, 24)
	weaponHeader.LayoutOrder = 2
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
	weaponList.LayoutOrder = 3
	weaponList.BackgroundTransparency = 1
	weaponList.Parent = frame

	local weaponListLayout = Instance.new("UIListLayout")
	weaponListLayout.Padding = UDim.new(0, 2)
	weaponListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	weaponListLayout.Parent = weaponList

	local function refresh()
		rebuildTools()

		local showWeapons = controller.phase ~= "setup"
		weaponHeader.Visible = showWeapons
		weaponList.Visible = showWeapons

		for _, child in ipairs(weaponList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for order, weapon in ipairs(controller:getWeapons()) do
			local targetText = weapon.target and string.format("-> (%d, %d)", weapon.target.x, weapon.target.y)
				or "-> unassigned"
			local cooldownText
			if weapon.underConstruction then
				cooldownText = "building"
			else
				local secondsLeft = math.max(0, (weapon.nextFireAt or 0) - controller.state.elapsed)
				cooldownText = secondsLeft > 0 and string.format("cooling %ds", math.ceil(secondsLeft)) or "ready"
			end
			local button = makeButton(
				string.format("%s (%d,%d) %s [%s]", weapon.typeId, weapon.x, weapon.y, targetText, cooldownText),
				order,
				weaponList
			)
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.MouseButton1Click:Connect(function()
				controller:armTarget(weapon)
				setActive(nil)
			end)
		end
	end

	refresh()

	return { refresh = refresh }
end

return BuildPalette
