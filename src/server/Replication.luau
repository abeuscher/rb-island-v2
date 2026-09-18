-- Shapes and sends every payload MatchService pushes to a client. The shaping
-- itself is pure (View/TickView/Rules.summary, all in src/shared/) -- this
-- module's only job is picking the right remote and firing it at the right
-- single player. Never :FireAllClients -- a payload meant for A must never
-- reach B and vice versa (§12).

local View = require(game:GetService("ReplicatedStorage").Shared.view)
local Rules = require(game:GetService("ReplicatedStorage").Shared.rules)

local function opponentOf(owner)
	if owner == "A" then
		return "B"
	end
	return "A"
end

local Replication = {}

function Replication.pushMatchFound(remotes, player, owner)
	remotes.MatchFound:FireClient(player, { owner = owner })
end

-- One continuous push, fired both after a command (with `message`/`ok`, no
-- `tickView`) and once per tick (no `message`, `tickView` carrying whatever
-- landed this tick to animate) -- never both at once, since a command ack and
-- a tick's resolution are always separate calls.
function Replication.pushState(remotes, player, state, owner, phase, message, ok, tickView)
	remotes.StateUpdate:FireClient(player, {
		phase = phase,
		view = View.new(state, owner),
		message = message,
		ok = ok,
		shots = tickView and tickView.shots or nil,
		destroyed = tickView and tickView.destroyed or nil,
		newBelief = tickView and tickView.newBelief or nil,
	})
end

function Replication.pushResult(remotes, player, config, state, owner, victory)
	remotes.StateUpdate:FireClient(player, {
		phase = "result",
		victory = victory,
		summary = {
			own = Rules.summary(config, state.players[owner]),
			opponent = Rules.summary(config, state.players[opponentOf(owner)]),
		},
	})
end

return Replication
