-- Result screen (§6.3): shown on any match end. Declares the winner and which
-- condition ended the match in plain language, then a side-by-side itemized
-- breakdown for both players, then Restart.
--
-- Takes a `summary` pair (`{ own, opponent }`, each a src/shared/rules.luau
-- `Rules.summary(...)` table -- counts and point totals only) rather than raw
-- MatchState. Session 007's local match could just read `finalState.players[
-- enemy]` directly; Session 008's server-authoritative match can't hand the
-- client the opponent's real structures/belief in the same payload that ends
-- the match without breaking §12's exploit check, so the server (or, for
-- local practice matches, the controller itself) computes the breakdown
-- instead of this screen reading it off raw player state.

local Result = {}

local STRUCTURE_TYPES = { "base", "generator", "cannon", "mortar" }
local STRUCTURE_LABELS = { base = "Base", generator = "Generator", cannon = "Cannon", mortar = "Mortar" }

local CONDITION_TEXT = {
	base_elimination = "All bases destroyed",
	incapacitation = "Opponent incapacitated",
	round_limit = "Round limit reached",
}

local function makeLabel(text, order, parent, bold, size)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, size or 18)
	label.LayoutOrder = order
	label.Text = text
	label.Font = bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
	label.TextSize = size or 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 230, 230)
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function buildColumn(parent, order, heading, summary)
	local column = Instance.new("Frame")
	column.Name = heading
	column.Size = UDim2.new(0.48, 0, 1, 0)
	column.LayoutOrder = order
	column.BackgroundTransparency = 1
	column.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

	local rowOrder = 1
	local function line(text, bold, size)
		makeLabel(text, rowOrder, column, bold, size)
		rowOrder += 1
	end

	line(heading, true, 22)
	line(string.format("Final score: %d", summary.finalScore))

	line("Destruction points:", true)
	for _, typeId in ipairs(STRUCTURE_TYPES) do
		line(string.format("  %s: %d", STRUCTURE_LABELS[typeId], summary.destructionPointsByType[typeId]))
	end

	line("Standing points:", true)
	for _, typeId in ipairs(STRUCTURE_TYPES) do
		line(string.format("  %s: %d", STRUCTURE_LABELS[typeId], summary.standingPointsByType[typeId]))
	end

	line(string.format("Reveal points: %d", summary.revealPoints))
	line(string.format("Hit points: %d", summary.hitPoints))
	line(string.format("Structures built: %d", summary.structuresBuilt))
	line(string.format("Structures lost: %d", summary.structuresLost))
	line(string.format("Structures standing: %d", summary.structuresStanding))
	line(string.format("Shots fired: %d", summary.shotsFired))
	line(string.format("Shots that hit: %d", summary.shotsHit))
	line(string.format("Shots blocked by terrain: %d", summary.shotsBlocked))
	line(string.format("Cells revealed: %d", summary.cellsRevealed))
end

-- `handlers.onRestart()`. Returns a handle with `show(victory, summary,
-- owner)` / `hide()`.
function Result.mount(parent, handlers)
	local overlay = Instance.new("Frame")
	overlay.Name = "ResultOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	overlay.Visible = false
	overlay.Parent = parent

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, 0, 0, 44)
	heading.Position = UDim2.new(0, 0, 0.05, 0)
	heading.Font = Enum.Font.SourceSansBold
	heading.TextSize = 36
	heading.BackgroundTransparency = 1
	heading.TextColor3 = Color3.fromRGB(240, 240, 240)
	heading.Parent = overlay

	local subheading = Instance.new("TextLabel")
	subheading.Name = "Subheading"
	subheading.Size = UDim2.new(1, 0, 0, 28)
	subheading.Position = UDim2.new(0, 0, 0.13, 0)
	subheading.Font = Enum.Font.SourceSans
	subheading.TextSize = 20
	subheading.BackgroundTransparency = 1
	subheading.TextColor3 = Color3.fromRGB(210, 210, 210)
	subheading.Parent = overlay

	local breakdown = Instance.new("Frame")
	breakdown.Name = "Breakdown"
	breakdown.AnchorPoint = Vector2.new(0.5, 0)
	breakdown.Position = UDim2.new(0.5, 0, 0.22, 0)
	breakdown.Size = UDim2.new(0.82, 0, 0.65, 0)
	breakdown.BackgroundTransparency = 1
	breakdown.Parent = overlay

	local breakdownLayout = Instance.new("UIListLayout")
	breakdownLayout.FillDirection = Enum.FillDirection.Horizontal
	breakdownLayout.Padding = UDim.new(0, 24)
	breakdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
	breakdownLayout.Parent = breakdown

	local restartButton = Instance.new("TextButton")
	restartButton.Name = "RestartButton"
	restartButton.AnchorPoint = Vector2.new(0.5, 1)
	restartButton.Position = UDim2.new(0.5, 0, 0.96, 0)
	restartButton.Size = UDim2.new(0, 200, 0, 48)
	restartButton.Text = "Restart"
	restartButton.Font = Enum.Font.SourceSansBold
	restartButton.TextSize = 20
	restartButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
	restartButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	restartButton.Parent = overlay

	restartButton.MouseButton1Click:Connect(function()
		handlers.onRestart()
	end)

	local function clearColumns()
		for _, child in ipairs(breakdown:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function show(victory, summary, owner)
		local winnerText
		if victory.winner == nil then
			winnerText = "Draw"
		elseif victory.winner == owner then
			winnerText = "Victory"
		else
			winnerText = "Defeat"
		end
		heading.Text = winnerText
		subheading.Text = CONDITION_TEXT[victory.condition] or victory.condition

		clearColumns()
		buildColumn(breakdown, 1, "You", summary.own)
		buildColumn(breakdown, 2, "Opponent", summary.opponent)

		overlay.Visible = true
	end

	return {
		show = show,
		hide = function()
			overlay.Visible = false
		end,
	}
end

return Result
