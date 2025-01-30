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
local BatchConfigUpdatedSignal = Signal.new()

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
	if type(targetConfig) == "string" then
		targetConfig = {targetConfig}
	end

	-- Establish bindable connection
	return BatchConfigUpdatedSignal:Connect(function(changes : {{path : {string}, newValue : any, oldValue : any}}, oldConfigs : any)
		for _, change in changes do
			local match = true
			for index, path in targetConfig do
				if path ~= change.path[index] then
					match = false
					break
				end
			end

			if match then
				callback(self:Get(targetConfig), self:Get(targetConfig, oldConfigs))
				break
			end
		end
	end)
end

function InternalConfigs:_checkConfigChanged(oldConfig, newConfig) : { {path : {string}, newValue : any, oldValue : any} }
	local changedBatch = {} :: {{path : {string}, newValue : any, oldValue : any}}

	local function addToBatch(path, newValue, _)
		table.insert(changedBatch, {path = path, newValue = newValue})
	end

	local function recursiveChangedFinder(old, new, _path)
		_path = _path or {}

		for oldKey, oldValue in old do
			local currentPath = table.clone(_path)
			table.insert(currentPath, oldKey)

			local newValue = new[oldKey]
			if newValue == nil then -- Removed
				addToBatch(currentPath, nil, oldValue)
			elseif type(newValue) ~= type(oldValue) then -- Changed type
				addToBatch(currentPath, newValue, oldValue)
			elseif type(newValue) == "table" then -- Recurse
				recursiveChangedFinder(oldValue, newValue, currentPath)
			elseif newValue ~= oldValue then -- Changed
				addToBatch(currentPath, newValue, oldValue)
			end

			--NOTE: could optimize by using the same table
			--table.remove(path, #path)
		end

		-- check if added
		for newKey, newValue in new do
			local currentPath = table.clone(_path)
			table.insert(currentPath, newKey)

			if old[newKey] == nil then -- Added
				addToBatch(currentPath, newValue, nil)
			end
		end
	end

	recursiveChangedFinder(oldConfig, newConfig)

	return changedBatch
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
	local oldConfigs = Utilities.recursiveCopy(ActiveConfigs.DevConfigs)
	
	CurrentClientPrivacy =  privacyConfig--{{"a", "c"}, {"a", "d", "e"}} --  
	-- We can't recurse over a "config metadata object" unless we make a reserved key for the metadata and preserve the structure of the config object
	-- Create a config-wide metadata key to avoid collisions with config object structure.
	-- Can store metadata + key in configs mod in the future if there's other relevant metadata we want to access at any time.
	--local metadataKey = httpService:GenerateGUID(false)
	--local configMetadata = {}

	
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

	if init ~= true then
		local changedBatch = InternalConfigs:_checkConfigChanged(oldConfigs, newConfigs)

		if #changedBatch > 0 then
			BatchConfigUpdatedSignal:Fire(changedBatch, oldConfigs)

			local filteredChanges = {}
			for _, change in changedBatch do
				if not IsPathPrivate(change.path) then
					change.newValue = FilterConfigForClient(change.path, change.newValue)
					table.insert(filteredChanges, change)
				end
			end

			ConfigChangedRemote:FireAllClients(filteredChanges)
		end
	end

	
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
function InternalConfigs:Get(path : string | { string }, configsOverride : any?) : any
	if typeof(path) ~= "table" and typeof(path) ~= "string" then
		Utilities.GBWarn("Config path must be a string or list of strings.")
		return nil
	end

	path = typeof(path) == "string" and {path} or path
	
	if not configsOverride then
		self:WaitForConfigsReady()
	end

	local value = configsOverride or ActiveConfigs.DevConfigs
	for _, key in ipairs(path) do
		value = value[key]

		if value == nil then
			return nil
		end
	end

	return value
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