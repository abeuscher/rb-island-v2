-- Minimal assert-based test runner for `lune run test`. No dependencies.

local process = require("@lune/process")

local testkit = {}

local passed = 0
local failed = 0
local failures = {}

function testkit.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, { name = name, error = err })
	end
end

function testkit.expectEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
	end
end

function testkit.expectTrue(value, message)
	if not value then
		error(message or "expected true, got false", 2)
	end
end

function testkit.expectFalse(value, message)
	if value then
		error(message or "expected false, got true", 2)
	end
end

function testkit.summary()
	print(string.format("\n%d passed, %d failed", passed, failed))
	if failed > 0 then
		for _, failure in ipairs(failures) do
			print(string.format("  FAIL %s: %s", failure.name, failure.error))
		end
		process.exit(1)
	end
end

return testkit
