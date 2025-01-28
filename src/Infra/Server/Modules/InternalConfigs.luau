--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	InternalConfigs.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local InternalConfigs = { }

--= Roblox Services =--

--= Dependencies =--

local Utilities = shared.GBMod("Utilities")
local GetRemote = shared.GBMod("GetRemote")
local Signal = shared.GBMod("Signal")

--= Types =--

--= Object References =--

local GetConfigRemoteFunc = GetRemote("Function", "Get")
local GetEventDataRemoteFunc = GetRemote("Function", "GetEventData")
local EventDataUpdatedRemote = GetRemote("Event", "EventDataUpdated")
local ConfigChangedRemote = GetRemote("Event", "ConfigChanged")
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
local CurrentClientPrivacy = {}
--[[ Full dev defined configuration profile
ActiveConfigs.DevConfigs = {}
-- Metadata sent along with dev defined configs
configsMod.GBConfigs = {}
-- Set of client accessible configs
configsMod.clientConfigs = {}]]

--= Public Variables =--

--= Internal Functions =--

local function IsPathPrivate(path : {string}) : boolean
	for _, privacyPath in CurrentClientPrivacy do -- a, d, e
		if #privacyPath > #path then
			continue
		end

		local match = true
		for index, pathSegment in ipairs(path) do -- a, d
			if pathSegment ~= privacyPath[index] then
				match = false
				break
			end
		end

		if match then
			return true
		end
	end

	return false
end

local function FilterConfigForClient(path : {string}, config : {[string] : any}) : {[string] : any}
	if type(config) ~= "table" then
		return config
	end

	local configCopy = Utilities.recursiveCopy(config)
	local privacyConfig = CurrentClientPrivacy

	-- Determine if the path is a match for any privacy paths
	local targetPaths = {}
	for _, privacyPath in privacyConfig do -- a, d, e
		local match = true
		for index, pathSegment in ipairs(path) do -- a, d
			if pathSegment ~= privacyPath[index] then
				match = false
				break
			end
		end

		if match then
			local relativePath = table.clone(privacyPath)
			for _=1, #path do
				table.remove(relativePath, 1)
			end

			table.insert(targetPaths, relativePath)
		end
	end

	-- Remove any paths that are marked as private
	for _, targetPath in targetPaths do
		local target = configCopy
		for index, pathSegment in targetPath do
			if index == #targetPath then
				target[pathSegment] = nil
				break
			else
				target = target[pathSegment]

				if target == nil then
					Utilities.GBWarn("Privacy path ".. table.concat(targetPath, ".").. " does not exist in config.")
					break
				end
			end
		end
	end

	return configCopy
end

local function SendConfigUpdateSignal(path, newValue, oldValue)
	ConfigUpdatedSignal:Fire(path, newValue, oldValue)

	if not IsPathPrivate(path) then
		ConfigChangedRemote:FireAllClients(path, FilterConfigForClient(path, newValue))
	end
end

--= API Functions =--

function InternalConfigs:IsReady() : boolean
	return ConfigsReady
end

function InternalConfigs:OnReady(callback : (newConfigs : any) -> ())
	if not ConfigsReady then
		ConfigReadySignal:Once(callback)
	else
		task.spawn(callback)
	end
end

function InternalConfigs:WaitForConfigsReady() : true
	if not ConfigsReady then
		ConfigReadySignal:Wait()
	end
	return true
end

function InternalConfigs:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection

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

function InternalConfigs:_checkConfigChanged(old, new, _path : {string}?)
	_path = _path or {}
	for oldKey, oldValue in old do
		local currentPath = table.clone(_path)
		table.insert(currentPath, oldKey)

		local newValue = new[oldKey]
		if newValue == nil then -- Removed
			SendConfigUpdateSignal(currentPath, nil, oldValue)
		elseif type(newValue) ~= type(oldValue) then -- Changed type
			SendConfigUpdateSignal(currentPath, newValue, oldValue)
		elseif type(newValue) == "table" then -- Recurse
			self:_checkConfigChanged(oldValue, newValue, currentPath)
		elseif newValue ~= oldValue then -- Changed
			SendConfigUpdateSignal(currentPath, newValue, oldValue)
		end

		--NOTE: could optimize by using the same table
		--table.remove(path, #path)
	end

	-- check if added
	for newKey, newValue in new do
		local currentPath = table.clone(_path)
		table.insert(currentPath, newKey)

		if old[newKey] == nil then -- Added
			SendConfigUpdateSignal(currentPath, newValue, nil)
		end
	end
end

function InternalConfigs:ApplyInternalConfigs(newGBConfigs)
	-- Split internally used metadata from dev facing configs
	for index, value in newGBConfigs do
		ActiveConfigs.GBConfigs[index] = value
	end

	-- Note: In the future, check to see if the event data actually changed from the internal config update.
	--EventDataUpdatedRemote:FireAllClients(newConfigs["GBEventData"])
end

function InternalConfigs:ApplyConfigs(newConfigs, privacyConfig : { {string} }, init : boolean?)
	local oldConfigs = ActiveConfigs.DevConfigs
	
	CurrentClientPrivacy = privacyConfig --{{"a", "c"}, {"a", "d", "e"}} --  
	-- We can't recurse over a "config metadata object" unless we make a reserved key for the metadata and preserve the structure of the config object
	-- Create a config-wide metadata key to avoid collisions with config object structure.
	-- Can store metadata + key in configs mod in the future if there's other relevant metadata we want to access at any time.
	--local metadataKey = httpService:GenerateGUID(false)
	--local configMetadata = {}

	
	-- Check if key has been removed from config

	if init ~= true then
		InternalConfigs:_checkConfigChanged(oldConfigs, newConfigs)
	end

	-- Freeze new configs to prevent modification
	local function recursiveFreeze(configs)
		table.freeze(configs)
		for _, value in configs do
			if type(value) == "table" then
				recursiveFreeze(value)
			end
		end
	end

	recursiveFreeze(newConfigs)

	ActiveConfigs.DevConfigs = newConfigs
	-- Freeze highest level table not referenced in traversal
	
	--shared.GBMod("InternalConfigs").clientConfigs = newClientConfigs
	---- Freeze highest level table not referenced in traversal
	--table.freeze(clientConfigs)
	
	--TODO:
	ConfigsReady = true

	ConfigReadySignal:Fire(newConfigs)
	--ConfigUpdatedSignal:Fire(path, newValue, oldValue)
end

-- Returns a copy of the active dev configs
function InternalConfigs:CopyConfigs()
	return Utilities.recursiveCopy(ActiveConfigs.DevConfigs)
end

-- Get the value of a specific config
function InternalConfigs:Get(path : string | { string }, configs : any?) : any
	if typeof(path) ~= "table" and typeof(path) ~= "string" then
		Utilities.GBWarn("Config path must be a string or list of strings.")
		return nil
	end
	
	self:WaitForConfigsReady()

	local location, lastKey = self:GetEndpointFromPath(path, configs or ActiveConfigs.DevConfigs)

	if not location or not lastKey then
		return nil
	end
	
	return location[lastKey]
end

function InternalConfigs:GetActiveConfig(key : string) : any
	return ActiveConfigs[key]
end

-- Get the value of a specific event
function InternalConfigs:GetEventData(eventName : string) : { [string] : any }
	local info = ActiveConfigs.GBConfigs.GBEventData[eventName]
	
	if not info then
		Utilities.GBWarn("No Gamebeast event named ".. eventName)
	end
	
	return info
end

function InternalConfigs:GetEndpointFromPath(path, configs)
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
function InternalConfigs:Init()

	-- Call Get for clients and return value.
	GetConfigRemoteFunc.OnServerInvoke = function(_, path)
		self:WaitForConfigsReady()
		if path == nil then
			return FilterConfigForClient({}, ActiveConfigs.DevConfigs)
		end

		if IsPathPrivate(path) then
			return nil
		end

		return FilterConfigForClient(path, self:Get(path))
		-- NOTE: We'll want to modify to reflect privacy. To be most efficient, we can create a get function that references a
		-- "client" config set that essentially recursively copies the set of configs only assigning a value if it has client accessibility.
		-- This means we only every make one copy of a table rather than on every client request.
		--return configsMod.get(path, configsMod.clientConfigs)
	end

	-- Call GetEventData for clients and return value
	--[[GetEventDataRemoteFunc.OnServerInvoke = function(_)
		return ActiveConfigs.GBConfigs.GBEventData
	end]]
end

--= Return Module =--
return InternalConfigs