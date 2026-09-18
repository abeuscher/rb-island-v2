-- Intro screen (§6.1): Start Game (enabled), Save Game and Continue (rendered
-- but disabled -- wired to nothing, a placeholder for the eventual session-
-- restore path), and Settings.

local Intro = {}

local function makeButton(text, order, parent, enabled)
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.new(0, 280, 0, 44)
	button.LayoutOrder = order
	button.Text = text
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 20
	button.TextWrapped = true
	button.BackgroundColor3 = enabled and Color3.fromRGB(60, 100, 60) or Color3.fromRGB(40, 40, 40)
	button.TextColor3 = enabled and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(140, 140, 140)
	button.AutoButtonColor = enabled
	button.Parent = parent
	return button
end

-- `handlers.onStart()` and `handlers.onSettings()`. Returns a handle with
-- `show()`/`hide()`.
function Intro.mount(parent, handlers)
	local overlay = Instance.new("Frame")
	overlay.Name = "IntroOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	overlay.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Position = UDim2.new(0, 0, 0.2, 0)
	title.Text = "ISLAND SIEGE"
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 48
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.Parent = overlay

	local buttonColumn = Instance.new("Frame")
	buttonColumn.AnchorPoint = Vector2.new(0.5, 0)
	buttonColumn.Position = UDim2.new(0.5, 0, 0.42, 0)
	buttonColumn.Size = UDim2.new(0, 280, 0, 180)
	buttonColumn.BackgroundTransparency = 1
	buttonColumn.Parent = overlay

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttonColumn

	local startButton = makeButton("Start Game", 1, buttonColumn, true)
	startButton.MouseButton1Click:Connect(function()
		handlers.onStart()
	end)

	local saveButton = makeButton("Save Game and Continue (coming soon)", 2, buttonColumn, false)
	saveButton.TextSize = 15
	saveButton.Size = UDim2.new(0, 280, 0, 52)
	saveButton.Active = false

	local settingsButton = makeButton("Settings", 3, buttonColumn, true)
	settingsButton.MouseButton1Click:Connect(function()
		handlers.onSettings()
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

return Intro
