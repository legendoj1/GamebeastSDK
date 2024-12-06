-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local playerService = game:GetService("Players")
local runService = game:GetService("RunService")
local httpService = game:GetService("HttpService")
local localizationService = game:GetService("LocalizationService")
local chat = game:GetService("Chat")

local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")

local captureMod = {}

local chatConns = {}

-- Create connections on player joined
playerService.PlayerAdded:Connect(function(player)
	-- Get relevant language settings
	local translator = utilities.promiseReturn(1, function()
		return localizationService:GetTranslatorForPlayer(player)
	end)

	chatConns[player] = player.Chatted:Connect(function(message)
		local position
		
		-- Compliance
		message = utilities.promiseReturn(0, function()
			chat:FilterStringForBroadcast(message, player)
		end) or message

		local heatmapMetadata = shared.GBMod("Configs").GBConfigs.HeatmapMetadata

		-- Likely to scrap position localization with new heatmap API
		if heatmapMetadata.center then
			if player.Character and player.Character.PrimaryPart then
				position = player.Character.PrimaryPart.Position
			end

			local center, size = heatmapMetadata.center, heatmapMetadata.size
			center = CFrame.new(center[1], center[2], center[3])
			size = Vector3.new(size[1], size[2], size[3])

			position = center:Inverse() * CFrame.new(position)
			position = {-position.X / size.X, position.Y / size.Y, -position.Z / size.Z}
		end

		-- Send marker with relevant args
		local args = {
			["message"] = message
		}

		shared.GBMod("EngagementMarkers").sdkMarker("Chat", player, position, 1, args)
	end)
end)

-- Clear session connections on player leave
playerService.PlayerRemoving:Connect(function(player)
	if chatConns[player] then
		chatConns[player]:Disconnect()
		chatConns[player] = nil
	end
end)

return captureMod