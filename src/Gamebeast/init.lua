-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local runService = game:GetService("RunService")
local gamebeast = {}

local remotesFolder = runService:IsClient() and script:WaitForChild("Remotes") or Instance.new("Folder", script)
remotesFolder.Name = "Remotes"

local function checkGBReady()
	-- Wait for initialization if not initialized otherwise return immediately
	while not script:GetAttribute("ConfigsReady") do task.wait() end
	return true
end

local function getRemote(remoteType : "Function" | "Event", name : string)
	local remote = remotesFolder:FindFirstChild(remoteType..name)
	if not remote then
		remote = Instance.new("Remote"..remoteType, remotesFolder)
		remote.Name = remoteType..name
	end

	return remote
end

-- Everything implemented as functions, most devs use method syntax, so expose accordingly

-- Server sided functions
if runService:IsServer() then	
	-- Configs
	gamebeast.Get = function(_, ...)
		checkGBReady()
		return shared.GBMod("Configs").get(...)
	end
		
	gamebeast.OnChanged = function(_, ...)
		return shared.GBMod("Configs").onChanged(...)
	end
	
	gamebeast.ModuleUpdated = function(_, ...)
		return shared.GBMod("Configs").moduleUpdated(...)
	end
	
	gamebeast.CopyConfigs = function(_, ...)
		return shared.GBMod("Configs").copyConfigs(...)
	end
	
	gamebeast.GetEventData = function(_, ...)
		checkGBReady()
		return shared.GBMod("Configs").getEventData(...)
	end
	
	-- Engagement markers
	gamebeast.FireMarker = function(_, ...)
		shared.GBMod("EngagementMarkers").fireMarker(...)
	end
else
	-- Client sided functions
	
	gamebeast.GetRemote = function(_, ...)
		return getRemote(...)
	end

	-- Configs
	gamebeast.Get = function(_, ...)
		checkGBReady()
		return getRemote("Function", "Get"):InvokeServer(...)
	end
	
	-- Changed criteria checked in "set"
	gamebeast.OnChanged = function(_, config, callback)
		local connection = getRemote("Event", "ConfigChanged").OnClientEvent:Connect(function(changedConfig, newValue, oldValue)
			local isMatchingTable

			if typeof(config) == "table" and typeof(changedConfig) == "table" then
				isMatchingTable = table.concat(config) == table.concat(changedConfig)
			end

			if isMatchingTable or config == changedConfig then
				callback(newValue, oldValue)
			end
		end)

		return connection
	end
	
	gamebeast.ModuleUpdated = function(_, callback)
		return getRemote("Event", "ModuleUpdated").OnClientEvent:Connect(callback)
	end
	
	gamebeast.GetEventData = function(_, ...)
		checkGBReady()
		return getRemote("Function", "GetEventData"):InvokeServer(...)
	end
	
	-- Engagement markers
	gamebeast.FireMarker = function(_, ...)
		getRemote("Event", "FireMarker"):FireServer(...)
	end
end

return gamebeast