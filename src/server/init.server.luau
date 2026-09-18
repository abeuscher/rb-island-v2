local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No avatars per §13: players never walk, they only ever look at the board.
Players.CharacterAutoLoads = false

local Config = require(ReplicatedStorage.Shared.config)
local Remotes = require(ReplicatedStorage.Shared.remotes)
local CommandHandler = require(script.CommandHandler)

local remotes = Remotes.get()
local commandHandler = CommandHandler.new(Config, remotes)

remotes.Command.OnServerEvent:Connect(function(player, command)
	commandHandler:handle(player, command)
end)

Players.PlayerRemoving:Connect(function(player)
	commandHandler:playerRemoving(player)
end)
