-- Entry point for `lune run test`. Discovers and runs every tests/*.spec.luau file.

local fs = require("@lune/fs")
local testkit = require("../tests/testkit")

for _, fileName in fs.readDir("tests") do
	if fileName:match("%.spec%.luau$") then
		local modulePath = "../tests/" .. fileName:gsub("%.luau$", "")
		require(modulePath)
	end
end

testkit.summary()
