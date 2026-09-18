-- Settings panel (§6.2): a title, a close button, and one row per entry in the
-- registry passed in. An empty registry renders an empty panel -- this module
-- never hardcodes a list of controls, so adding a setting is a registry-only
-- change.

local Settings = {}

local function makeToggleRow(entry, parent, order)
	local row = Instance.new("Frame")
	row.Name = entry.id
	row.Size = UDim2.new(1, 0, 0, 32)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = entry.label
	label.Font = Enum.Font.SourceSans
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.35, 0, 1, 0)
	button.Position = UDim2.new(0.65, 0, 0, 0)
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	button.Parent = row

	local value = entry.default
	local function render()
		button.Text = value and "On" or "Off"
	end
	render()

	button.MouseButton1Click:Connect(function()
		value = not value
		render()
		entry.apply(value)
	end)
end

local ROW_BUILDERS = {
	toggle = makeToggleRow,
}

-- Mounts (hidden) into `parent`. Returns a handle with `show()`/`hide()`.
function Settings.mount(parent, registry)
	local overlay = Instance.new("Frame")
	overlay.Name = "SettingsOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = parent

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 360, 0, 280)
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	panel.ZIndex = 11
	panel.Parent = overlay

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Text = "Settings"
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 22
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.ZIndex = 11
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.Position = UDim2.new(1, -34, 0, 6)
	closeButton.Text = "X"
	closeButton.Font = Enum.Font.SourceSansBold
	closeButton.TextSize = 18
	closeButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	closeButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	closeButton.ZIndex = 12
	closeButton.Parent = panel

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -24, 1, -52)
	list.Position = UDim2.new(0, 12, 0, 44)
	list.BackgroundTransparency = 1
	list.ZIndex = 11
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	for order, entry in ipairs(registry) do
		local build = ROW_BUILDERS[entry.kind]
		if build then
			build(entry, list, order)
		end
	end

	closeButton.MouseButton1Click:Connect(function()
		overlay.Visible = false
	end)

	return {
		show = function()
			overlay.Visible = true
		end,
		hide = function()
			overlay.Visible = false
		end,
	}
end

return Settings
