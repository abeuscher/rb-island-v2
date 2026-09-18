-- Round/phase label, countdown, and the Ready button.

local RoundClock = {}

function RoundClock.mount(parent, controller)
	local frame = Instance.new("Frame")
	frame.Name = "RoundClock"
	frame.Size = UDim2.new(0, 180, 0, 80)
	frame.Position = UDim2.new(1, -180, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	frame.BackgroundTransparency = 0.2
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "RoundLabel"
	roundLabel.Size = UDim2.new(1, 0, 0, 24)
	roundLabel.LayoutOrder = 1
	roundLabel.Font = Enum.Font.SourceSansBold
	roundLabel.TextSize = 18
	roundLabel.BackgroundTransparency = 1
	roundLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	roundLabel.Parent = frame

	local clockLabel = Instance.new("TextLabel")
	clockLabel.Name = "ClockLabel"
	clockLabel.Size = UDim2.new(1, 0, 0, 24)
	clockLabel.LayoutOrder = 2
	clockLabel.Font = Enum.Font.SourceSans
	clockLabel.TextSize = 16
	clockLabel.BackgroundTransparency = 1
	clockLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	clockLabel.Parent = frame

	local readyButton = Instance.new("TextButton")
	readyButton.Name = "ReadyButton"
	readyButton.Size = UDim2.new(1, 0, 0, 28)
	readyButton.LayoutOrder = 3
	readyButton.Text = "Ready"
	readyButton.Font = Enum.Font.SourceSansBold
	readyButton.TextSize = 16
	readyButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
	readyButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	readyButton.Parent = frame

	readyButton.MouseButton1Click:Connect(function()
		controller:ready()
	end)

	-- Calls attention to Ready once setup's base count is satisfied, so the
	-- player isn't left hunting for what to do next.
	local readyHighlight = Instance.new("UIStroke")
	readyHighlight.Name = "ReadyHighlight"
	readyHighlight.Thickness = 3
	readyHighlight.Color = Color3.fromRGB(255, 255, 255)
	-- Contextual (the default) strokes the button's TEXT for a text-bearing
	-- object; Border strokes the button's own rectangle, which is the outline
	-- that's actually wanted here.
	readyHighlight.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	readyHighlight.Enabled = false
	readyHighlight.Parent = readyButton

	local function refresh()
		readyHighlight.Enabled = controller.phase == "setup" and controller:countOwnBases() == controller.config.NUM_BASES
		readyButton.Visible = controller.phase == "setup"

		if controller.phase == "setup" then
			roundLabel.Text = "Setup"
			clockLabel.Text = string.format("%d/%d bases placed", controller:countOwnBases(), controller.config.NUM_BASES)
		elseif controller.phase == "result" then
			roundLabel.Text = "Match over"
			clockLabel.Text = ""
		else
			roundLabel.Text = "Live"
			clockLabel.Text = string.format("%ds remaining", math.max(0, math.ceil(controller:getSecondsRemaining())))
		end
	end

	refresh()
	controller:onResolve(refresh)

	return { refresh = refresh }
end

return RoundClock
