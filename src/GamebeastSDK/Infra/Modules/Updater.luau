-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local replicatedStorage = game:GetService("ReplicatedStorage")
local messagingService = game:GetService("MessagingService")
local dataStoreService = game:GetService("DataStoreService")
local httpService = game:GetService("HttpService")

local sdk = script.Parent.Parent.Parent
local utilities = shared.GBMod("Utilities")
local signal = shared.GBMod("Signal")
local gamebeastModInstance = replicatedStorage:WaitForChild("Gamebeast")
local gamebeastModule = require(gamebeastModInstance)

local updaterMod = {}

local configChangedRemote = gamebeastModule:GetRemote("Event", "ConfigChanged")
local moduleUpdatedRemote = gamebeastModule:GetRemote("Event", "ModuleUpdated")

-- Datastore to get last configs if we can't communicate with GB servers
local BACKUP_STORE_KEY = "GBConfigBackup"
updaterMod.backupConfigStore = dataStoreService:GetDataStore(BACKUP_STORE_KEY)

updaterMod.ModuleUpdated = signal.new()
updaterMod.ConfigChanged = signal.new()

-- Update modules based on config data in new module version
updaterMod.updateConfigs = function(newConfigs, init)	
	local configsMod = shared.GBMod("Configs")
	local lastVersion = not init and configsMod["GBConfigs"]["GBPublishTime"] or nil
	
	-- If we got an old configuration version over the wire for some reason, don't apply it
	if lastVersion and newConfigs["GBConfigs"]["GBPublishTime"] <= lastVersion then
		return
	end

	--print("Loading new configs from Gamebeast")
	-- Save newly received configs to datastore for backup purposes. Only the host server needs to do this for resource considerations.
	-- Make sure we're not initializing and saving an already backed up config.
	if shared.GBMod("HostServer").isHostServer() and not init then
		task.spawn(function()
			updaterMod.saveConfigsToBackup(newConfigs)
		end)
	end

	-- Split internally used metadata from dev facing configs
	for index, value in newConfigs["GBConfigs"] do
		configsMod["GBConfigs"][index] = value
	end

	-- Update game configs
	init = init or not shared.GBMod("Configs").configsReady

	-- Determine whether we're using canonical config profile or A/B testing partition
	local configsToIntegrate, configName = shared.GBMod("ABTesting").getConfigProfileForServer(newConfigs)
	local curPartition = shared.GBMod("ABTesting").CUR_PARTITION
	
	-- This block is irrelevant now with sending analytics data through as markers with the partition ID contained
	---- If we were on a server A/B testing campaign
	--if curPartition ~= "" then
	--	if shared.GBMod("ABTesting").getNumPartitions(newConfigs) == 0 then
	--		-- We were on a server campaign but now we're not
	--	elseif not newConfigs.GBConfigs.ABTestingCampaigns.partitions[curPartition] then
	--		-- A new server campaign was deployed, last terminated
	--	end
	--end

	shared.GBMod("ABTesting").CUR_PARTITION = configName

	-- Integrate new configs
	updaterMod.integrateConfigs(configsToIntegrate, init)

	-- Start up flag
	shared.GBMod("Configs").configsReady = true
	gamebeastModInstance:SetAttribute("ConfigsReady", true)

	-- Signal mod update
	if not init then
		updaterMod.ModuleUpdated:Fire()
		moduleUpdatedRemote:FireAllClients()
	end
end

-- Send update signal to specific config branch
local function sendConfigUpdateSignal(path, newValue, oldValue, notifyClient)
	updaterMod.ConfigChanged:Fire(path, newValue, oldValue)
	configChangedRemote:FireAllClients(path, newValue, oldValue)
end

---- Checks whether given path value (evaluated, not by reference) has changed between two sets of configs. Returns whether config changed.
--updaterMod.sendConfigUpdateSignal = function(oldConfigs, oldClientConfigs, newConfigs, newClientConfigs, path, init, forceNotify)
--	if init and not forceNotify then
--		return false
--	end
	
--	local function configChanged(oldValue, newValue, init)		
--		local hasChanged = false
--		local valueType = typeof(newValue)

--		if valueType == "table" then
--			if valueType ~= typeof(oldValue) then
--				hasChanged = true
--			else
--				hasChanged = not utilities.tableEqualityCheck(newValue, oldValue)
--			end
--		else
--			hasChanged = newValue ~= oldValue
--		end

--		if hasChanged or forceNotify then
--			return true
--		end
		
--		return false
--	end

--	local oldValue = shared.GBMod("Configs").get(path, oldConfigs)
--	local newValue = shared.GBMod("Configs").get(path, newConfigs)
	
--	if configChanged(oldValue, newValue) then
--		-- Bindable to server listeners
--		remotes.ConfigChanged:Fire(path, newValue, oldValue)
		
--		local oldClientValue = shared.GBMod("Configs").get(path, oldClientConfigs)
--		local newClientValue = shared.GBMod("Configs").get(path, newClientConfigs)
		
--		-- Check separately for client, i.e. main config path value could have changed but path is nil in both old and new for client
--		-- Also don't want to breach privacy by sending server old value in event
--		if configChanged(oldClientValue, newClientValue) then
--			gamebeastMod.Remotes.ConfigChanged:FireAllClients(path, newClientValue, oldClientValue)
--		end
		
--		return true
--	end
	
--	return false
--end
updaterMod.checkConfigChanged = function(configs, path, value, init, forceNotify)
	configs = configs or shared.GBMod("Configs").configs

	local oldValue = shared.GBMod("Configs").get(path, configs)
	-- Config table reference is overwritten, don't actually need to set values -- save iteration.
	--local location, lastKey = shared.GBMod("Configs").getEndpointFromPath(config, configs)
	--location[lastKey] = value

	if not init then
		local hasChanged = false
		local valueType = typeof(value)

		if valueType == "table" then
			if valueType ~= typeof(oldValue) then
				hasChanged = true
			else
				hasChanged = not utilities.tableEqualityCheck(value, oldValue)
			end
		else
			hasChanged = value ~= oldValue
		end

		if hasChanged or forceNotify then
			sendConfigUpdateSignal(path, value, oldValue)
		end

		return hasChanged
	end
end

-- Recursively explore new configs version, check for differences, and apply updates throughout system
updaterMod.integrateConfigs = function(newConfigs, init)
	local updatedBranches = {}

	local oldConfigs = shared.GBMod("Configs").configs
	local oldClientConfigs = shared.GBMod("Configs").clientConfigs
	
	-- We can't recurse over a "config metadata object" unless we make a reserved key for the metadata and preserve the structure of the config object
	-- Create a config-wide metadata key to avoid collisions with config object structure.
	-- Can store metadata + key in configs mod in the future if there's other relevant metadata we want to access at any time.
	--local metadataKey = httpService:GenerateGUID(false)
	--local configMetadata = {}
	
	-- Recursively copy new configs only keeping branches where privacy field of corresponding metadata object is client-accessible to create client config set.
	-- Assign client accessible configs set to configs.clientConfigs. Use same traversal to build traversable metadata object if we want to store and use it later.
	--local function createClientConfigs(configs, metadata, depthIndex)
	--	local tableCopy = {}

	--	for index, value in configs do
	--		local curMetadata = value[2]
	--		value = value[1]

	--		table.insert(depthIndex, index)
	--		local path = #depthIndex > 1 and depthIndex or depthIndex[1]
			
	--		-- if client accessible privacy level
	--		if curMetadata.prvc == 0 then
	--			if typeof(value) == "table" then
	--				-- Make copy so metadata key doesn't become part of main configs, make everything readonly
	--				metadata[index] = utilities.recursiveCopy(value, true) 
	--				metadata[index][metadataKey] = curMetadata
	--				if not table.isfrozen(metadata[index]) then
	--					table.freeze(metadata[index])
	--				end
					
	--				-- We avoid using Get(path, metadata) to eliminate double iteration for path existence + value retrieval, which is guaranteed
	--				value = utilities.createClientConfigs(value, metadata[index], depthIndex)

	--				-- Piggy back off traversal and deeply make read only
	--				if not table.isfrozen(value) then
	--					table.freeze(value)
	--				end
	--			else
	--				metadata[index] = {metadataKey = curMetadata}
	--			end

	--			tableCopy[index] = value
	--		end

	--		table.remove(depthIndex, #depthIndex)
	--	end
		
	--	return tableCopy
	--end
	
	--local newClientConfigs = createClientConfigs(newConfigs, configMetadata, {})

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
				local res = updaterMod.checkConfigChanged(oldConfigs, path, value, init)
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
				updatedBranches[branchIndex] = utilities.recursiveCopy(depthIndex)
			end
		end

		return hasChanged
	end

	-- Begin recursive traversal
	innerFunc(newConfigs, {})

	-- Iterate over updated branches and notify as needed
	for _, depthIndex in updatedBranches do
		local newVal = shared.GBMod("Configs").get(depthIndex, newConfigs)
		local oldVal
		
		if utilities.tableEqualityCheck(oldConfigs, {}) then
			oldVal = nil
		else
			shared.GBMod("Configs").get(depthIndex, oldConfigs)
		end
		
		sendConfigUpdateSignal(depthIndex, newVal, oldVal)
		-- Can just be replaced with this line with metadata update
		--sendConfigUpdateSignal(oldConfigs, oldClientConfigs, newConfigs, newClientConfigs, depthIndex)
	end

	shared.GBMod("Configs").configs = newConfigs
	-- Freeze highest level table not referenced in traversal
	table.freeze(newConfigs)
	
	--shared.GBMod("Configs").clientConfigs = newClientConfigs
	---- Freeze highest level table not referenced in traversal
	--table.freeze(clientConfigs)
end

-- In the unlikely case GB is down, fall back on Roblox datastores
updaterMod.getBackupConfigs = function()
	local configs, success = utilities.promiseReturn(2, function()
		return updaterMod.backupConfigStore:GetAsync(BACKUP_STORE_KEY)
	end)
	
	if not success then
		utilities.GBWarn("Couldn't get configs from backup. Attempting to re-establish connection with Gamebeast...")
	end

	return configs
end

-- Save new configs to Roblox datastores for backup
-- NOTE: if a server is starting up and there are a bunch of update config jobs pending, this can throttle, should probably add a flag
updaterMod.saveConfigsToBackup = function(newConfigs)
	utilities.promiseReturn(1, function()
		updaterMod.backupConfigStore:SetAsync(BACKUP_STORE_KEY, newConfigs)
	end)
end

-- Start up, ask for most recent configuations
local newConfigsResp, req = shared.GBMod("GBRequests").GBRequest("sdk/roblox/configurations", nil, 1)
local newConfigs

-- If no response or failed status, attempt to recover
if not req or req.StatusCode ~= 200 then
	utilities.GBWarn("Couldn't get configurations from Gamebeast. Attempting to load from backup...")
	-- Try to get datastore backed up configs
	newConfigs = updaterMod.getBackupConfigs()

	-- If they've never published configs / no backup for this project, then we have to wait for a connection or we would error every other part of the system. Extremely unlikely.
	if not newConfigs then
		repeat
			task.wait(10)
			utilities.GBWarn("Attempting to establish connection...")
			newConfigs = shared.GBMod("GBRequests").GBRequest("sdk/roblox/configurations", nil, 0)
		until newConfigs
		print("Connection with Gamebeast re-established! Loading newest configs...")
	else
		print("Backup configs loaded successfully!")
	end
else
	-- Good response, proceed
	newConfigs = newConfigsResp.args
end

-- Update configs for server with initialization flag
updaterMod.updateConfigs(newConfigs, true)

return updaterMod