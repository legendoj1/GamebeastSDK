--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	Markers.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local Markers = { }

--= Roblox Services =--
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")
local PolicyService = game:GetService("PolicyService")

--= Dependencies =--

local GetRemote = shared.GBMod("GetRemote")
local Utilities = shared.GBMod("Utilities")
local PlayerStats = shared.GBMod("PlayerStats")
local Configs = shared.GBMod("Configs") ---@module Configs

--= Types =--

--= Object References =--

local FireMarkerEvent = GetRemote("Event", "FireMarker")

--= Constants =--

local MAX_EVENT_QUEUE_SIZE = 1000
local QUEUE_CHECK_TIME = 5
local MAX_EVENT_REPORT_TIME = 10
local SYSTEM_MARKERS = {
	["Died"] = true,
	["Logout"] = true,
	["Login"] = true,
	["Purchase"] = true,
	["Chat"] = true,
	--["GBClientPerformance"] = true,
	--["GBServerPerformance"] = true,
}

--= Variables =--

local MarkerQueue = {}
-- Map of unique session IDs for users for player-associated markers
local SessionIds = {}
-- Connections for supporting player positions for markers
local CharConnections = {}
local LastCharPositions = {}
local LastEventReportTime = 0


--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

-- Send batch to GB
function Markers:SendMarkers()
	if #MarkerQueue > 0 then
		LastEventReportTime = tick()
		
		local entries = MarkerQueue
		MarkerQueue = {}
		
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
		
		shared.GBMod("GBRequests").GBRequest("sdk/markers", data, 1)
	end
end

-- Core function, should be used internally by SDK rather than fireMarker
-- function Markers:CreateMarker(source, markerType, player, position, value)
function Markers:CreateMarker(source : "server" | "client" | "sdk", markerType : string, value : any | {[string] : any}, metaData : {[string] : any})
	metaData = metaData or {}
	-- Validate all arguments.
	local usageStr
	
	if source == "server" then 
		usageStr = "Usage: FireMarker(MarkerType, Value (optional), Parameters (optional))"
	elseif source == "client" then
		usageStr = "Usage: FireMarker(MarkerType, Value (optional), Parameters (optional))"
	end
	
	if typeof(markerType) ~= "string" then
		Utilities.GBWarn("MarkerType argument should be a string.")
		return
	end

	local player = metaData.player
	local position = metaData.position
	
	if player ~= nil and not (player:IsA("Player") or typeof(player) == "number") then
		Utilities.GBWarn("Player argument for ".. source .." marker \"".. markerType.."\" should be a player instance, string/numeric identifier, or nil.\n".. usageStr)
		return
	end
	
	if position ~= nil and typeof(position) ~= "Vector3" then
		Utilities.GBWarn("Position arugment for ".. source .." marker \"".. markerType.."\" should be Vector3 or nil.\n".. usageStr)
		return
	end
	
	local valueType = typeof(value)

	if value ~= nil and valueType ~= "table" and valueType ~= "number" or (valueType == "table" and #value > 0) then
		Utilities.GBWarn("Value for ".. source .." marker \"".. markerType.."\" should be a key-value dictionary, number, or nil.\n".. usageStr)
		return
	end
	
	-- Interface allows for player instance or userId. We already validated args types, so just handle accordingly.
	local userId = tonumber(player)
	
	if not userId and player then
		userId = player.UserId
	end
	
	
	-- Marker fields
	local entry = {
		["type"] = markerType,
		["user_id"] = userId,
		["utc"] = DateTime.now().UnixTimestampMillis,
		["args"] = if typeof(value) == "table" then value else nil,
		["origin"] = source,
		["value"] = if typeof(value) == "number" then value else nil,
		-- server A/B testing partition ID if applicable
		--["partition_id"] = partition ~= "" and partition or nil,
	}
	
	-- If player associated marker, include unique session ID
	if userId then
		entry["session_id"] = SessionIds[userId]
		-- client A/B testing partition ID if applicable
		--["partition_id"] = activeCampaign and id or nil
	end
	
	-- Yield only if first configs/initialization not done
	if Configs:WaitForConfigsReady() then
		-- To be overhauled likely with new heatmap API. Can likely scrap localization of marker position and send world positions
		local heatmapMetadata = Configs:GetActiveConfig("GBConfigs").HeatmapMetadata

		if position then
			-- Warn if trying to send associated position and no heatmaps are defined
			-- Round positions to avoid sending 14 decimals of accuracy across wire
			
			if not heatmapMetadata.center and not SYSTEM_MARKERS[markerType] then
				--utilities.GBWarn("A heatmap must be defined for position information to be included with markers.")
			elseif heatmapMetadata.center then
				-- Localize position
				local center, size = heatmapMetadata.center, heatmapMetadata.size
				center = CFrame.new(center[1], center[2], center[3])
				size = Vector3.new(size[1], size[2], size[3])
				position = center:Inverse() * CFrame.new(position)
				local x = Utilities.roundNum(-position.X / size.X, 0.0001)
				local y = Utilities.roundNum(position.Y / size.Y, 0.0001)
				local z = Utilities.roundNum(-position.Z / size.Z, 0.0001)
				
				entry.position = {x, y, z}
			end
		end
	end
	
	table.insert(MarkerQueue, entry)
	
	-- If marker queue size limit reached then send batch
	if #MarkerQueue >= MAX_EVENT_QUEUE_SIZE then
		Markers:SendMarkers()
	end
end

-- Fire an engagement marker. Used by devs via API module, wraps createMarker to declare source.
-- Usage: Markers:FireMarker("LevelUp", {playerLevel = player:GetAttribute("Level")}, {player = player, position = player.Character.PrimaryPart.Position})
function Markers:FireMarker(...)
	self:CreateMarker("server", ...)
end

-- Used internally by SDK to create markers
function Markers:SDKMarker(...)
	self:CreateMarker("sdk", ...)
end

--= Initializers =--
function Markers:Init()
	-- Handle client requests through API module
	FireMarkerEvent.OnServerEvent:Connect(function(player, markerType, value, metaData)
		if metaData then
			metaData.player = player
		end

		Markers:CreateMarker("client", markerType, value, metaData)
	end)

	local function playerAdded(player : Player)
		local userId = player.UserId
		
		-- Get unique session ID for user
		SessionIds[userId] = HttpService:GenerateGUID(false)
		
		-- Track deaths by default
		player.CharacterAdded:Connect(function(char)
			local connection
			local hum = char:FindFirstChildOfClass("Humanoid")
			
			if hum then
				CharConnections[player] = hum.Died:Connect(function()
					local primaryPart = char.PrimaryPart
					
					-- Still helpful to tell where players are falling out of the map. Solutions?
					if primaryPart then
						self:SDKMarker("Died", nil, {player = player, position = primaryPart.Position})
						CharConnections[player]:Disconnect()
						CharConnections[player] = nil
					end
				end)
			end
		end)
		
		-- Collect last position with this event given PlayerRemoving was inconsistent on character still existing for providing position for Logout markers
		player.CharacterRemoving:Connect(function(char)
			local position = char.PrimaryPart and char.PrimaryPart.Position or nil
			LastCharPositions[player] = position
		end)
		
		-- Get player Login position
		local char = player.Character or player.CharacterAdded:Wait()
		local position
		
		if char and char.PrimaryPart then
			position = char.PrimaryPart.Position
		end
		
		-- Send Login marker with relevant session information
		local loginArgs = {
			region_id = Utilities.promiseReturn(1, function()
				return LocalizationService:GetCountryRegionForPlayerAsync(player)
			end) or "unknown",
			locale_id = Utilities.promiseReturn(1, function()
				return LocalizationService:GetTranslatorForPlayer(player).LocaleId
			end) or "unknown",
			allowed_ads = Utilities.promiseReturn(1, function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player).AreAdsAllowed
			end),
			device = Utilities.getPlayerDeviceType(player),
		}
		
		self:SDKMarker("Login", loginArgs, {player = player, position = position})
	end

	Players.PlayerAdded:Connect(playerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		
		-- Clear session state
		SessionIds[userId] = nil
		
		-- Collect last position for Logout marker
		local position = LastCharPositions[player]
		LastCharPositions[player] = nil
		
		-- Compute session length in addition to backend for reasons(?)
		local args = {
			["session_length"] = Utilities.roundNum(tick() - PlayerStats:GetStat(player, "session_length"), 0.1)
		}
		
		-- Send Logout marker with relevant info
		self:SDKMarker("Logout", args, {player = player, position = position})
		
		if CharConnections[player] then
			CharConnections[player]:Disconnect()
			CharConnections[player] = nil
		end
	end)

	-- Check if time limit has elapsed and send current data, if any
	task.spawn(function()
		while task.wait(QUEUE_CHECK_TIME) do
			-- Check if we need to send queued events to GB
			local lastReportElapsed = tick() - LastEventReportTime

			if lastReportElapsed >= MAX_EVENT_REPORT_TIME then
				Markers:SendMarkers()
			end
			
			if Configs:WaitForConfigsReady() then
				MAX_EVENT_REPORT_TIME = Configs:GetActiveConfig("GBConfigs")["GBRates"]["EngagementMarkers"]
			end
		end
	end)

	-- Can be annoying to wait for markers to send when you're stopping a test in studio. Maybe make a setting?
	if not RunService:IsStudio() then
		game:BindToClose(function()
			-- Wait for markers from various systems to come in
			task.wait(0.5)
			-- Send remaining items in queue on shutdown
			Markers:SendMarkers()
		end)
	end
end

--= Return Module =--
return Markers