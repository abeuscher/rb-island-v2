-- Shapes and sends every payload MatchService pushes to a client. The shaping
-- itself is pure (View/ResolveView/Rules.summary, all in src/shared/) --
-- this module's only job is picking the right remote and firing it at the
-- right single player. Never :FireAllClients -- a payload meant for A must
-- never reach B and vice versa (§12).

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

function Replication.pushState(remotes, player, config, state, owner, phase, secondsRemaining, message, ok)
	remotes.StateUpdate:FireClient(player, {
		phase = phase,
		view = View.new(state, owner),
		secondsRemaining = secondsRemaining,
		message = message,
		ok = ok,
	})
end

-- `view` is already-built src/shared/resolveView.luau output -- MatchService
-- builds it itself (it also needs to read `view.misfireMessages` back out to
-- carry into the next plan phase's message), so this only ever fires it.
function Replication.pushResolveView(remotes, player, view)
	remotes.ResolveEvent:FireClient(player, view)
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
