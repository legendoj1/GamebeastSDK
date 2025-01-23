-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

-- So the current problem with Updater is that it is updating the modules instead of having the modules update themselves based on signals from Updater.
-- This is a problem because it is not following the Observer pattern. 
-- The Observer pattern is a behavioral design pattern that defines a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.


--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	Updater.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local Updater = { }

--= Roblox Services =--
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local GBRequests = shared.GBMod("GBRequests")
local ABTesting = shared.GBMod("ABTesting")
local Utilities = shared.GBMod("Utilities")
local InternalConfigs = shared.GBMod("InternalConfigs") ---@module InternalConfigs
local GetRemote = shared.GBMod("GetRemote")
local Signal = shared.GBMod("Signal")

--= Types =--

--= Constants =--

local BACKUP_STORE_KEY = "GBConfigBackup"

--= Object References =--

local BackupConfigStore = DataStoreService:GetDataStore(BACKUP_STORE_KEY)

--= Variables =--

--= Public Variables =--

--= Internal Functions =--



--= API Functions =--

Updater.ModuleUpdated = Signal.new()
Updater.ConfigChanged = Signal.new()

-- Update modules based on config data in new module version
function Updater:UpdateConfigs(newConfigs, init)
	local GBConfigs = InternalConfigs:GetActiveConfig("GBConfigs")
	local lastVersion = not init and GBConfigs["GBPublishTime"] or nil
	
	-- If we got an old configuration version over the wire for some reason, don't apply it
	if lastVersion and newConfigs["GBConfigs"]["GBPublishTime"] <= lastVersion then
		return
	end

	--print("Loading new configs from Gamebeast")
	-- Save newly received configs to datastore for backup purposes. Only the host server needs to do this for resource considerations.
	-- Make sure we're not initializing and saving an already backed up config.
	if shared.GBMod("HostServer"):IsHostServer() and not init then
		task.spawn(function()
			self:SaveConfigsToBackup(newConfigs)
		end)
	end

	InternalConfigs:ApplyInternalConfigs(newConfigs["GBConfigs"])

	-- Update game configs
	init = init or not InternalConfigs:IsReady()

	-- Determine whether we're using canonical config profile or A/B testing partition

	-- ABTesting is integral to the configs, but it cant be a leaf.
	-- Maybe we have it listen and then fire 

	local configsToIntegrate, configName = ABTesting:GetConfigProfileForServer(newConfigs)
	
	-- This block is irrelevant now with sending analytics data through as markers with the partition ID contained
	---- If we were on a server A/B testing campaign
	--if curPartition ~= "" then
	--	if shared.GBMod("ABTesting").getNumPartitions(newConfigs) == 0 then
	--		-- We were on a server campaign but now we're not
	--	elseif not newConfigs.GBConfigs.ABTestingCampaigns.partitions[curPartition] then
	--		-- A new server campaign was deployed, last terminated
	--	end
	--end
 
	ABTesting:SetCurrentPartition(configName)

	-- Integrate new configs

	InternalConfigs:ApplyConfigs(configsToIntegrate, init)



	--[[ Signal mod update
	if not init then
		self.ModuleUpdated:Fire()
		ModuleUpdatedRemote:FireAllClients()
	end
	]]
end


-- In the unlikely case GB is down, fall back on Roblox datastores
function Updater:GetBackupConfigs()
	local configs, success = Utilities.promiseReturn(2, function()
		return BackupConfigStore:GetAsync(BACKUP_STORE_KEY)
	end)
	
	if not success then
		Utilities.GBWarn("Couldn't get configs from backup. Attempting to re-establish connection with Gamebeast...")
	end

	return configs
end

-- Save new configs to Roblox datastores for backup
-- NOTE: if a server is starting up and there are a bunch of update config jobs pending, this can throttle, should probably add a flag
function Updater:SaveConfigsToBackup(newConfigs)
	Utilities.promiseReturn(1, function()
		BackupConfigStore:SetAsync(BACKUP_STORE_KEY, newConfigs)
	end)
end


--= Initializers =--
function Updater:Init()
	-- Start up, ask for most recent configuations
	local newConfigsResp, req = GBRequests.GBRequestAsync("sdk/configurations", nil, 1)
	local newConfigs

	-- If no response or failed status, attempt to recover
	if not req or req.StatusCode ~= 200 then
		Utilities.GBWarn("Couldn't get configurations from Gamebeast. Attempting to load from backup...")
		-- Try to get datastore backed up configs
		newConfigs = self:GetBackupConfigs()

		-- If they've never published configs / no backup for this project, then we have to wait for a connection or we would error every other part of the system. Extremely unlikely.
		if not newConfigs then
			repeat
				task.wait(10)
				Utilities.GBWarn("Attempting to establish connection...")
				newConfigs = GBRequests.GBRequestAsync("sdk/configurations", nil, 0)
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
	self:UpdateConfigs(newConfigs, true)

	ABTesting.NewConfigSignal:Connect(function(...)
		self:UpdateConfigs(...)
	end)
end

--= Return Module =--
return Updater