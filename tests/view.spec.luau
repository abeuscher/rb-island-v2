local t = require("./testkit")
local config = require("../src/shared/config")
local State = require("../src/shared/state")
local View = require("../src/shared/view")

-- §15's hard requirement: an archetype reads only its own belief map, plus
-- public terrain, never the opponent's true structure state. §12 reuses the
-- same guarantee for a real client over the network (Session 008). This is
-- enforced structurally by never putting the opponent's player state anywhere
-- on the view -- these tests exist so that requirement stays enforced if the
-- view ever grows.

t.test("a view only ever carries round, board, owner, opponent, and self", function()
	local state = State.new(config)
	local view = View.new(state, "A")

	local keys = {}
	for key in pairs(view) do
		table.insert(keys, key)
	end
	table.sort(keys)
	t.expectEqual(table.concat(keys, ","), "board,opponent,owner,round,self")
end)

t.test("a view exposes the owner's own resources, structures, and belief -- never the opponent's", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { structures = { { typeId = "base", x = 6, y = 7, hp = 40, underConstruction = false } } })
	state = State.withPlayer(state, "B", { structures = { { typeId = "base", x = 24, y = 7, hp = 40, underConstruction = false } } })

	local view = View.new(state, "A")

	t.expectEqual(view.owner, "A")
	t.expectEqual(view.opponent, "B")
	t.expectEqual(#view.self.structures, 1)
	t.expectEqual(view.self.structures[1].x, 6)
end)

t.test("belief on the view is the owner's own belief map about the opponent", function()
	local state = State.new(config)
	state = State.withPlayer(state, "A", { belief = { ["24,7"] = { typeId = "base", underConstruction = false } } })

	local view = View.new(state, "A")
	t.expectEqual(view.self.belief["24,7"].typeId, "base")
end)

t.test("board on the view is the same public terrain object -- terrain is fully visible (§11)", function()
	local state = State.new(config)
	local view = View.new(state, "A")
	t.expectTrue(view.board == state.board)
end)
