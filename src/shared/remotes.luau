-- The RemoteEvent set client and server both need a handle to. The server
-- creates them (first call, at boot); the client waits for them to exist.
-- Rate limiting lives in server/CommandHandler.luau, not here -- this module
-- only ever hands back Instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local NAMES = { "Command", "StateUpdate", "MatchFound" }

function Remotes.get()
	local events = {}

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		for _, name in ipairs(NAMES) do
			local event = folder:FindFirstChild(name)
			if not event then
				event = Instance.new("RemoteEvent")
				event.Name = name
				event.Parent = folder
			end
			events[name] = event
		end
		return events
	end

	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in ipairs(NAMES) do
		events[name] = folder:WaitForChild(name)
	end
	return events
end

return Remotes
