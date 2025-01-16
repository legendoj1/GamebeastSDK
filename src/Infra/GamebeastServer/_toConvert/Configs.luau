--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	Configs.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local Configs = { }

--= Roblox Services =--

--= Dependencies =--

local GBRequests = shared.GBMod("GBRequests")
local Utilities = shared.GBMod("Utilities")
local GetRemote = shared.GBMod("GetRemote")
local Signal = shared.GBMod("Signal")

--= Types =--

--= Object References =--

local GetConfigRemoteFunc = GetRemote("Function", "Get")
local GetEventDataRemoteFunc = GetRemote("Function", "GetEventData")
local ConfigChangedRemote = GetRemote("Event", "ConfigChanged")
local ModuleUpdatedRemote = GetRemote("Event", "ModuleUpdated")
local ConfigReadySignal = Signal.new()
local ConfigUpdatedSignal = Signal.new()

--= Constants =--

--= Variables =--

local ConfigsReady = false
local ActiveConfigs = {
	--Full dev defined configuration profile
	DevConfigs = {},
	--Metadata sent along with dev defined configs
	GBConfigs = {},
	--Set of client accessible configs
	ClientConfigs = {}
}
--[[ Full dev defined configuration profile
ActiveConfigs.DevConfigs = {}
-- Metadata sent along with dev defined configs
configsMod.GBConfigs = {}
-- Set of client accessible configs
configsMod.clientConfigs = {}]]

--= Public Variables =--

--= Internal Functions =--

local function SendConfigUpdateSignal(path, newValue, oldValue)
	ConfigUpdatedSignal:Fire(path, newValue, oldValue)
	ConfigChangedRemote:FireAllClients(path, newValue, oldValue)
end

--= API Functions =--

function Configs:AreConfigsReady() : boolean
	return ConfigsReady
end

function Configs:OnConfigsReady(callback : () -> ())
	if not ConfigsReady then
		ConfigReadySignal:Once(callback)
	else
		task.spawn(callback)
	end
end

---@deprecated Use Configs:OnConfigsReady instead.
function Configs:WaitForConfigsReady() : true
	if not ConfigsReady then
		ConfigReadySignal:Wait()
	end
	return true
end

function Configs:OnConfigsUpdated(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection

	-- Establish bindable connection
	return ConfigUpdatedSignal:Connect(function(changedPath, newValue, oldValue)
		local isMatchingTable

		if typeof(targetConfig) == "table" and typeof(changedPath) == "table" then
			isMatchingTable = Utilities.tableEqualityCheck(targetConfig, changedPath)
		end

		if isMatchingTable or targetConfig == changedPath then
			-- Has changed condition checked by "set" before firing bindable
			callback(newValue, oldValue)
		end
	end)
end

function Configs:_checkConfigChanged(configs, path, value) : boolean
	configs = configs or ActiveConfigs.DevConfigs

	local oldValue = self:Get(path, configs)
	-- Config table reference is overwritten, don't actually need to set values -- save iteration.
	--local location, lastKey = shared.GBMod("Configs").getEndpointFromPath(config, configs)
	--location[lastKey] = value


	local hasChanged = false
	local valueType = typeof(value)

	if valueType == "table" then
		if valueType ~= typeof(oldValue) then
			hasChanged = true
		else
			hasChanged = not Utilities.tableEqualityCheck(value, oldValue)
		end
	else
		hasChanged = value ~= oldValue
	end

	if hasChanged then
		SendConfigUpdateSignal(path, value, oldValue)
	end

	return hasChanged
end

function Configs:ApplyConfigs(newConfigs, init : boolean?)
	
	warn("Applying configs")
	local updatedBranches = {}
	local oldConfigs = ActiveConfigs.DevConfigs
	
	-- We can't recurse over a "config metadata object" unless we make a reserved key for the metadata and preserve the structure of the config object
	-- Create a config-wide metadata key to avoid collisions with config object structure.
	-- Can store metadata + key in configs mod in the future if there's other relevant metadata we want to access at any time.
	--local metadataKey = httpService:GenerateGUID(false)
	--local configMetadata = {}

	-- Inner recursive function for config traversal and value change detection. Also splits config values from metadata.
	local function innerFunc(configs, depthIndex)
		local hasChanged

		for index, value in configs do
			-- Drop metadata completely and proceed as old implementation
			--value = value[1]
			--configs[index] = value
			table.insert(depthIndex, index)

			local path = #depthIndex > 1 and depthIndex or depthIndex[1]
			
			if typeof(value) == "table" then
				-- Piggy back off traversal and deeply make newConfigs read only
				if not table.isfrozen(value) then
					table.freeze(value)
				end

				local res = innerFunc(value, depthIndex)
				hasChanged = hasChanged or res
			else
				local res = if init then false else self:_checkConfigChanged(oldConfigs, path, value)
				--local res = updaterMod.checkConfigChanged(oldConfigs, oldClientConfigs, newConfigs, newClientConfigs, path, init)
				hasChanged = hasChanged or res
			end

			table.remove(depthIndex, #depthIndex)
		end

		-- Notify up the branch if something in it changed but at most once even if multiple changes
		if #depthIndex > 0 then
			-- Use concat as we actually want the state of depthIndex as the branch key. Can't use table itself or string ref because we're actually only ever using one table.
			local branchIndex = table.concat(depthIndex)
			
			-- Record change occured if one did and we haven't already recorded it
			if hasChanged and not updatedBranches[branchIndex] then
				updatedBranches[branchIndex] = Utilities.recursiveCopy(depthIndex)
			end
		end

		return hasChanged
	end

	-- Begin recursive traversal
	innerFunc(newConfigs, {})

	-- Iterate over updated branches and notify as needed
	for _, depthIndex in updatedBranches do
		local newVal = self:Get(depthIndex, newConfigs)
		local oldVal
		
		if Utilities.tableEqualityCheck(oldConfigs, {}) then
			oldVal = nil
		else
			self:Get(depthIndex, oldConfigs)
		end
		
		SendConfigUpdateSignal(depthIndex, newVal, oldVal)
		-- Can just be replaced with this line with metadata update
		--sendConfigUpdateSignal(oldConfigs, oldClientConfigs, newConfigs, newClientConfigs, depthIndex)
	end

	ActiveConfigs.DevConfigs = newConfigs
	-- Freeze highest level table not referenced in traversal
	table.freeze(newConfigs)
	
	--shared.GBMod("Configs").clientConfigs = newClientConfigs
	---- Freeze highest level table not referenced in traversal
	--table.freeze(clientConfigs)
	
	--TODO:
	ConfigsReady = true

	ConfigReadySignal:Fire()
	--ConfigUpdatedSignal:Fire(path, newValue, oldValue)
end

-- Returns a copy of the active dev configs
function Configs:CopyConfigs()
	return Utilities.recursiveCopy(ActiveConfigs.DevConfigs)
end

-- Get the value of a specific config
function Configs:Get(path : string | { string }, configs : any) : any
	if typeof(path) ~= "table" and typeof(path) ~= "string" then
		Utilities.GBWarn("Config path must be a string or list of strings.")
		return nil
	end
	
	local location, lastKey = self:GetEndpointFromPath(path, ActiveConfigs.DevConfigs)

	if not location or not lastKey then
		return nil
	end
	
	return location[lastKey]
end

function Configs:GetActiveConfig(key : string) : any
	return ActiveConfigs[key]
end

-- Get the value of a specific event
function Configs:GetEventData(eventName : string) : { [string] : any }
	local info = ActiveConfigs.GBConfigs.GBEventData[eventName]
	
	if not info then
		Utilities.GBWarn("No Gamebeast event named ".. eventName)
	end
	
	return info
end

function Configs:GetEndpointFromPath(path, configs)
	if not (typeof(path) == "table") then
		return configs or ActiveConfigs.DevConfigs, path
	elseif #path == 1 then
		return configs or ActiveConfigs.DevConfigs, path[1]
	end

	local endpoint = self:Get(path[1], configs) --NOTE: why is this recursive?

	for i = 2, #path - 1 do
		if not endpoint then
			return nil, nil
		end

		endpoint = endpoint[path[i]]
	end

	return endpoint, path[#path]
end

--= Initializers =--
function Configs:Init()
	-- Call Get for clients and return value.
	GetConfigRemoteFunc.OnServerInvoke = function(player, path)
		return self:Get(path)
		-- NOTE: We'll want to modify to reflect privacy. To be most efficient, we can create a get function that references a
		-- "client" config set that essentially recursively copies the set of configs only assigning a value if it has client accessibility.
		-- This means we only every make one copy of a table rather than on every client request.
		--return configsMod.get(path, configsMod.clientConfigs)
	end

	-- Call GetEventData for clients and return value
	GetEventDataRemoteFunc.OnServerInvoke = function(player, eventName)
		return self:GetEventData(eventName)
	end
end

--= Return Module =--
return Configs