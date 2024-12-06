-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local replicatedStorage = game:GetService("ReplicatedStorage")
local playerService = game:GetService("Players")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")
local localizationService = game:GetService("LocalizationService")
local policyService = game:GetService("PolicyService")

local sdk = script.Parent.Parent.Parent
local utilities = shared.GBMod("Utilities")
local gamebeastMod = require(replicatedStorage:WaitForChild("Gamebeast"))

local markerMod = {}

local systemMarkers = {
	["Died"] = true,
	["Logout"] = true,
	["Login"] = true,
	["Purchase"] = true,
	["Chat"] = true,
	--["GBClientPerformance"] = true,
	--["GBServerPerformance"] = true,
}

local markerQueue = {}
local lastEventReportTime = tick()
local MAX_EVENT_QUEUE_SIZE = 1000
local QUEUE_CHECK_TIME = 5
local MAX_EVENT_REPORT_TIME = 10

-- Send batch to GB
markerMod.sendMarkers = function()
	if #markerQueue > 0 then
		lastEventReportTime = tick()
		
		local entries = markerQueue
		markerQueue = {}
		
		local data = {
			["GBReserved"] = {
				["Purchase"] = {},
				["Chat"] = {},
				["Login"] = {},
				["Logout"] = {}
			},
			["general"] = {
				["markers"] = {}
			}
		}

		for _, marker in entries do
			local markerType = marker["type"]
			
			if data["GBReserved"][markerType] then
				table.insert(data["GBReserved"][markerType], marker)
			else
				table.insert(data["general"].markers, marker)
			end
		end
		
		shared.GBMod("GBRequests").GBRequest("sdk/roblox/markers", data, 1)
	end
end

-- Connections for supporting player positions for markers
local charConnections = {}
local lastCharPositions = {}

-- Map of unique session IDs for users for player-associated markers
markerMod.sessionIDs = {}

-- Core function, should be used internally by SDK rather than fireMarker
markerMod.createMarker = function(source, markerType, player, position, value, args)
	-- Validate all arguments.
	local usageStr
	
	if source == "server" then
		usageStr = "Usage: FireMarker(MarkerType, Player (optional), Position (optional),  Value (optional), Args (optional))"
	elseif source == "client" then
		usageStr = "Usage: FireMarker(MarkerType, Position (optional), Value (optional), Args (optional))"
	end
	
	if typeof(markerType) ~= "string" then
		utilities.GBWarn("MarkerType argument should be a string.")
		return
	end
	
	if player ~= nil and not (player:IsA("Player") or typeof(player) == "number") then
		utilities.GBWarn("Player argument for ".. source .." marker \"".. markerType.."\" should be a player instance, string/numeric identifier, or nil.\n".. usageStr)
		return
	end
	
	if position ~= nil and typeof(position) ~= "Vector3" then
		utilities.GBWarn("Position arugment for ".. source .." marker \"".. markerType.."\" should be Vector3 or nil.\n".. usageStr)
		return
	end
	
	if value ~= nil and typeof(value) ~= "number" then
		utilities.GBWarn("Value agrument for ".. source .." marker \"".. markerType.."\" must be a number or nil. Use \"args\" for other data types.\n".. usageStr)
		return
	end
	
	if args ~= nil and typeof(args) ~= "table" or (typeof(args) == "table" and #args > 0) then
		utilities.GBWarn("Args for ".. source .." marker \"".. markerType.."\" should be a key-value dictionary or nil.\n".. usageStr)
		return
	end
	
	-- Interface allows for player instance or userId. We already validated args types, so just handle accordingly.
	local userId = tonumber(player)
	
	if not userId and player then
		userId = player.UserId
	end
	
	--local partition = shared.GBMod("A/BTesting").CUR_PARTITION
	
	-- Marker fields
	local entry = {
		["type"] = markerType,
		["user_id"] = userId,
		["utc"] = DateTime.now().UnixTimestampMillis,
		["args"] = args,
		["origin"] = source,
		["value"] = value,
		-- server A/B testing partition ID if applicable
		--["partition_id"] = partition ~= "" and partition or nil,
	}
	
	-- If player associated marker, include unique session ID
	if userId then
		entry["session_id"] = markerMod.sessionIDs[userId]
		-- client A/B testing partition ID if applicable
		--["partition_id"] = activeCampaign and id or nil
	end
	
	-- Yield only if first configs/initialization not done
	if shared.GBMod("Configs").checkGBReady() then
		-- To be overhauled likely with new heatmap API. Can likely scrap localization of marker position and send world positions
		local heatmapMetadata = shared.GBMod("Configs").GBConfigs.HeatmapMetadata

		if position then
			-- Warn if trying to send associated position and no heatmaps are defined
			-- Round positions to avoid sending 14 decimals of accuracy across wire
			
			if not heatmapMetadata.center and not systemMarkers[markerType] then
				--utilities.GBWarn("A heatmap must be defined for position information to be included with markers.")
			elseif heatmapMetadata.center then
				-- Localize position
				local center, size = heatmapMetadata.center, heatmapMetadata.size
				center = CFrame.new(center[1], center[2], center[3])
				size = Vector3.new(size[1], size[2], size[3])
				position = center:Inverse() * CFrame.new(position)
				local x = utilities.roundNum(-position.X / size.X, 0.0001)
				local y = utilities.roundNum(position.Y / size.Y, 0.0001)
				local z = utilities.roundNum(-position.Z / size.Z, 0.0001)
				
				entry.position = {x, y, z}
			end
		end
	end
	
	table.insert(markerQueue, entry)
	
	-- If marker queue size limit reached then send batch
	if #markerQueue >= MAX_EVENT_QUEUE_SIZE then
		markerMod.sendMarkers()
	end
end

-- Used internally by SDK to create markers
markerMod.sdkMarker = function(...)
	-- CHANGE TO "sdk"
	markerMod.createMarker("sdk", ...)
end

-- Fire an engagement marker. Used by devs via API module, wraps createMarker to declare source.
-- Usage: markers.fireMarker("LevelUp", player, player.Character.PrimaryPart.Position, value = 1, {playerLevel = player:GetAttribute("Level")})
markerMod.fireMarker = function(...)
	markerMod.createMarker("server", ...)
end

-- Handle client requests through API module
gamebeastMod:GetRemote("Event", "FireMarker").OnServerEvent:Connect(function(player, markerType, ...)
	markerMod.createMarker("client", markerType, player, ...)
end)

playerService.PlayerAdded:Connect(function(player)
	local userId = player.UserId
	
	-- Get unique session ID for user
	markerMod.sessionIDs[userId] = httpService:GenerateGUID(false)
	
	-- Track deaths by default
	player.CharacterAdded:Connect(function(char)
		local connection
		local hum = char:FindFirstChildOfClass("Humanoid")
		
		if hum then
			charConnections[player] = hum.Died:Connect(function()
				local primaryPart = char.PrimaryPart
				
				-- Still helpful to tell where players are falling out of the map. Solutions?
				if primaryPart then
					markerMod.sdkMarker("Died", player, primaryPart.Position)
					charConnections[player]:Disconnect()
					charConnections[player] = nil
				end
			end)
		end
	end)
	
	-- Collect last position with this event given PlayerRemoving was inconsistent on character still existing for providing position for Logout markers
	player.CharacterRemoving:Connect(function(char)
		local position = char.PrimaryPart and char.PrimaryPart.Position or nil
		lastCharPositions[player] = position
	end)
	
	-- Get player Login position
	local char = player.Character or player.CharacterAdded:Wait()
	local position
	
	if char and char.PrimaryPart then
		position = char.PrimaryPart.Position
	end
	
	-- Send Login marker with relevant session information
	local loginArgs = {
		region_id = utilities.promiseReturn(1, function()
			return localizationService:GetCountryRegionForPlayerAsync(player)
		end) or "unknown",
		locale_id = utilities.promiseReturn(1, function()
			return localizationService:GetTranslatorForPlayer(player).LocaleId
		end) or "unknown",
		allowed_ads = utilities.promiseReturn(1, function()
			return policyService:GetPolicyInfoForPlayerAsync(player).AreAdsAllowed
		end),
		device = utilities.getPlayerDeviceType(player),
	}
	
	markerMod.sdkMarker("Login", player, position, nil, loginArgs)
end)

playerService.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	
	-- Clear session state
	markerMod.sessionIDs[userId] = nil
	
	-- Collect last position for Logout marker
	local position = lastCharPositions[player]
	lastCharPositions[player] = nil
	
	-- Compute session length in addition to backend for reasons(?)
	local args = {
		["session_length"] = utilities.roundNum(tick() - shared.GBMod("Analytics").sessionData.session_length[player.UserId], 0.1)
	}
	
	-- Send Logout marker with relevant info
	markerMod.sdkMarker("Logout", player, position, nil, args)
	
	if charConnections[player] then
		charConnections[player]:Disconnect()
		charConnections[player] = nil
	end
end)

-- Check if time limit has elapsed and send current data, if any
task.spawn(function()
	while task.wait(QUEUE_CHECK_TIME) do
		-- Check if we need to send queued events to GB
		local lastReportElapsed = tick() - lastEventReportTime

		if lastReportElapsed >= MAX_EVENT_REPORT_TIME then
			markerMod.sendMarkers()
		end
		
		if shared.GBMod("Configs").checkGBReady() then
			MAX_EVENT_REPORT_TIME = shared.GBMod("Configs")["GBConfigs"]["GBRates"]["EngagementMarkers"]
		end
	end
end)

-- Can be annoying to wait for markers to send when you're stopping a test in studio. Maybe make a setting?
if not runService:IsStudio() then
	game:BindToClose(function()
		-- Wait for markers from various systems to come in
		task.wait(0.5)
		-- Send remaining items in queue on shutdown
		markerMod.sendMarkers()
	end)
end

return markerMod