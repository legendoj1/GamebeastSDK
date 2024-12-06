-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local replicatedStorage = game:GetService("ReplicatedStorage")
local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")
local updater = shared.GBMod("Updater")
local gamebeastMod = require(replicatedStorage:WaitForChild("Gamebeast"))

local configsMod = {}

-- Full dev defined configuration profile
configsMod.configs = {}
-- Metadata sent along with dev defined configs
configsMod.GBConfigs = {}
-- Set of client accessible configs
configsMod.clientConfigs = {}

-- Return whether initial configs have been loaded
configsMod.checkGBReady = function()
	while not configsMod.configsReady do task.wait() end
	return true
end

-- Get the value of a specific config
-- Usage: configs.get("SunPosition"), configs.get({"NPCs", "Spider", "Health"})
configsMod.get = function(path, configs)
	if typeof(path) ~= "table" and typeof(path) ~= "string" then
		utilities.GBWarn("Config path must be a string or list of strings.")
		return nil
	end
	
	local location, lastKey = configsMod.getEndpointFromPath(path, configs)

	if not location or not lastKey then
		return nil
	end
	
	return location[lastKey]
end

-- Get the configuration list for a live event
-- Usage: configs.getEventData("NewYearsEve")
configsMod.getEventData = function(eventName)
	local info = configsMod.GBConfigs.GBEventData[eventName]
	
	if not info then
		utilities.GBWarn("No Gamebeast event named ".. eventName)
	end
	
	return info
end

-- Add a copy function for convenience as the configs table is read only
configsMod.copyConfigs = function()
	return utilities.recursiveCopy(configsMod.configs)
end

-- Allows users to create events tied to changes of a specific config
-- Usage: local connection = configs.onChanged({"NPCs", "Spider", "Health"}, function(newVal, oldVal) end)
-- NOTE: need to add client arg and make sure path exists in client config set
configsMod.onChanged = function(path, callback)
	-- Establish bindable connection
	local connection = updater.ConfigChanged:Connect(function(changedPath, newValue, oldValue)
		local isMatchingTable

		if typeof(path) == "table" and typeof(changedPath) == "table" then
			isMatchingTable = utilities.tableEqualityCheck(path, changedPath)
		end

		if isMatchingTable or path == changedPath then
			-- Has changed condition checked by "set" before firing bindable
			callback(newValue, oldValue)
		end
	end)

	return connection
end

-- Fires event when a newer configuration module is received from the Roblox website.
-- Usage: local connection = configs.moduleUpdated(function() end)
configsMod.moduleUpdated = function(callback)
	return updater.ModuleUpdated:Connect(callback)
end

-- Follow provided path to get value, directly or nested
-- Config is specified path, configs is set of configurations to iterate over. Can be different from current server configurations.
configsMod.getEndpointFromPath = function(path, configs)
	if not (typeof(path) == "table") then
		return configs or configsMod.configs, path
	elseif #path == 1 then
		return configs or configsMod.configs, path[1]
	end

	local endpoint = configsMod.get(path[1], configs)

	for i = 2, #path - 1 do
		if not endpoint then
			return nil, nil
		end

		endpoint = endpoint[path[i]]
	end

	return endpoint, path[#path]
end

-- For receiving and handling client requests
local getRemoteFunc = gamebeastMod:GetRemote("Function", "Get")
local getEventDataRemoteFunc = gamebeastMod:GetRemote("Function", "GetEventData")

-- Call Get for clients and return value.
getRemoteFunc.OnServerInvoke = function(player, path)
	return configsMod.get(path)
	-- NOTE: We'll want to modify to reflect privacy. To be most efficient, we can create a get function that references a
	-- "client" config set that essentially recursively copies the set of configs only assigning a value if it has client accessibility.
	-- This means we only every make one copy of a table rather than on every client request.
	--return configsMod.get(path, configsMod.clientConfigs)
end

-- Call GetEventData for clients and return value
getEventDataRemoteFunc.OnServerInvoke = function(player, eventName)
	return configsMod.getEventData(eventName)
end

return configsMod