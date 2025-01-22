--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    ClientConfigs.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local ClientConfigs = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local GetRemote = shared.GBMod("GetRemote")
local Signal = shared.GBMod("Signal")

--= Types =--

--= Object References =--

local GetConfigRemoteFunc = GetRemote("Function", "Get")
--local GetEventDataRemoteFunc = GetRemote("Function", "GetEventData")
local ConfigChangedRemote = GetRemote("Event", "ConfigChanged")
local ConfigUpdatedSignal = Signal.new()

--= Constants =--

--= Variables =--

local CachedConfigs = {}
local ConfigsReady = false

--= Public Variables =--

--= Internal Functions =--

local function AreTablesEqual(table1, table2)
    if typeof(table1) ~= "table" or typeof(table2) ~= "table" then
        return false
    end

    for key, value in pairs(table1) do
        if table2[key] ~= value then
            return false
        end
    end

    for key, value in pairs(table2) do
        if table1[key] ~= value then
            return false
        end
    end

    return true
end

--= API Functions =--

function ClientConfigs:Get(path : string | { string })
    if typeof(path) ~= "table" and typeof(path) ~= "string" then
		error("Config path must be a string or list of strings.")
		return nil
	end

    if typeof(path) == "string" then
        path = {path}
    end
	
    local target = CachedConfigs
	for _, key in path do
        if not target[key] then
            return nil
        end
        target = target[key]
    end

	return target
end

function ClientConfigs:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection
    return ConfigUpdatedSignal:Connect(function(changedPath, newValue, oldValue)
		local isMatchingTable

		if typeof(targetConfig) == "table" and typeof(changedPath) == "table" then
			isMatchingTable = AreTablesEqual(targetConfig, changedPath)
		end

		if isMatchingTable or targetConfig == changedPath then
			-- Has changed condition checked by "set" before firing bindable
			callback(newValue, oldValue)
		end
	end)
end

function ClientConfigs:IsReady() : boolean
    return ConfigsReady
end

--= Initializers =--
function ClientConfigs:Init()

    ConfigChangedRemote.OnClientEvent:Connect(function(path, newValue, oldValue)
        if not ConfigsReady then return end

        local target = CachedConfigs
        for index, pathSegment in path do
            if index == #path then
                target[pathSegment] = newValue
            else
                target = target[pathSegment]
            end
        end

        ConfigUpdatedSignal:Fire(path, newValue, oldValue)
    end)

    task.spawn(function()
        CachedConfigs = GetConfigRemoteFunc:InvokeServer()
        --TODO: Make sure we actually got something
        ConfigsReady = true
    end)
    
end

--= Return Module =--
return ClientConfigs