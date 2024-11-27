-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local messagingService = game:GetService("MessagingService")
local runService = game:GetService("RunService")

local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")
local random = Random.new()

local testingMod = {}

-- Messaging channels for pinging/self-reporting a server exists for self-determining server partition.
local PARTITION_REQ_TOPIC = "CUR_PARTITION_REQ"
local PARTITION_RES_TOPIC = "CUR_PARTITION_RES"

-- Messaging channels on server start up and close for server partition rebalancing.
-- Currently removed, see later comments
--local SERVER_START_TOPIC = "SERVER_START"
--local SERVER_SHUTDOWN_TOPIC = "SERVER_CLOSE"

-- Current partition being used by the server. "" means no partition/canonical configs.
testingMod.CUR_PARTITION = ""

-- How often we check to rebalance
local REBALANCE_CHECK_TIME = NumberRange.new(30, 60)

-- List of JobIds of other servers for determining server partition
local otherServerPartitions = {}

-- State for internal processes
local inShutdown = false

-- Subscribe to receive responses of what partition other servers are on
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(PARTITION_RES_TOPIC, function(message)
		-- Only accept messages from servers specifically responding to us
		if message.Data.requestee ~= game.JobId then
			return
		end
		
		local respondingServerId = message.Data.jobId
		local partition = message.Data.partition
		
		-- Don't count replies from ourself
		if respondingServerId ~= game.JobId then
			otherServerPartitions[respondingServerId] = partition
		end
	end)
end)

-- Subscribe to receive requests from other servers to get what partition we're on
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(PARTITION_REQ_TOPIC, function(message)
		-- Don't reply to our own message or if the server is shutting down
		if message.Data ~= game.JobId and not inShutdown then
			local mesage = {
				jobId = game.JobId,
				partition = testingMod.CUR_PARTITION,
				requestee = message.Data,
			}
			
			utilities.publishMessage(PARTITION_RES_TOPIC, mesage)
		end
	end)
end)

-- Call update configs with cur configs to check/update partition without changing values
local function checkPartitionDisribution()
	if shared.GBMod("Configs").checkGBReady() then
		local curConfigs = utilities.recursiveCopy(shared.GBMod("Configs").configs)
		curConfigs.GBConfigs = shared.GBMod("Configs").GBConfigs
		
		-- See what set of configs we *should* be using, taking A/B testing campaigns into consideration
		local _, partitionName = testingMod.getConfigProfileForServer(curConfigs)
		
		-- If our current profile doesn't match what we should be using, update
		if partitionName ~= testingMod.CUR_PARTITION then
			-- Note we call with cur configs because updateConfigs will handle selecting and updating to a new partiton via the same method we did above
			-- Don't assume too much control, we only find something needs to change and let the function handle it
			shared.GBMod("Updater").updateConfigs(curConfigs)
		end
	end
end

-- Rebalancing ourselves whenever a new server starts or closes (all the time for large games), probably isn't great
-- Commenting out to save MessagingService resources and we'll just rely on the auto-rebalance timer, which is still
-- meaningfully real-time (staggered 30-60 seconds a time of writing)
---- Subscribe to receive message when server starts
--utilities.promiseReturn(nil, function()
--	messagingService:SubscribeAsync(SERVER_START_TOPIC, function(message)
--		if message.Data ~= game.JobId then
--			checkPartitionDisribution()
--		end
--	end)
--end)

---- Subscribe to receive message when server closes
--utilities.promiseReturn(nil, function()
--	messagingService:SubscribeAsync(SERVER_SHUTDOWN_TOPIC, function(message)
--		if message.Data ~= game.JobId then
--			checkPartitionDisribution()
--		end
--	end)
--end)

-- See how many server partitions exist for current set of configurations
testingMod.getNumPartitions = function(configs)
	return #configs.GBConfigs.ABTestingCampaigns.partitions
end

-- Get list of JobIDs from other server and map to what server partition they're in
local function getServerPartitions(configs)
	utilities.publishMessage(PARTITION_REQ_TOPIC, game.JobId)
	-- MessagingService guarantees <= 1 sec response time from all servers, so wait within bounds for all to respond.
	task.wait(1.1)
end

-- Select appropriate config partition, canonical or A/B testing server campaign partition
testingMod.getConfigProfileForServer = function(newConfigs)
	local numPartitions = testingMod.getNumPartitions(newConfigs)

	-- No campaign, use canonical
	if numPartitions == 0 then
		return newConfigs["configs"], ""
	end
	
	-- Put into partition deterministically based on job IDs
	getServerPartitions()
	local selectedPartition
	local serverIdList = {game.JobId}
	
	-- Sort list of JobIds
	for id, _ in otherServerPartitions do
		table.insert(serverIdList, id)
	end
	
	table.sort(serverIdList)
	
	-- Keep running total of partition percentages and see which bucket/partition we fall into based on JobId position in list
	local runningTotal = 0
	local index = table.find(serverIdList, game.JobId)
	local percent = (index - 1) / #serverIdList	
	
	table.sort(newConfigs.GBConfigs.ABTestingCampaigns.partitions, function(a, b)		
		return a.id > b.id
	end)

	for partitionIndex, partitionInfo in newConfigs.GBConfigs.ABTestingCampaigns.partitions do
		if percent >= runningTotal and percent < runningTotal + partitionInfo.load then
			selectedPartition = partitionIndex
		end

		runningTotal += partitionInfo.load
	end

	-- Clean up so dead servers aren't leaking memory by filling the table over time
	otherServerPartitions = {}
	
	local partition_info = newConfigs.GBConfigs.ABTestingCampaigns.partitions[selectedPartition]
	
	return partition_info.configs, partition_info.id
end

-- Tell other servers we exist and start partition self-rebalance loop
task.spawn(function()
	repeat task.wait() until shared.GBMod("Configs").configsReady
	--utilities.publishMessage(SERVER_START_TOPIC, game.JobId)
	
	while task.wait(random:NextNumber(REBALANCE_CHECK_TIME.Min, REBALANCE_CHECK_TIME.Max)) do
		checkPartitionDisribution()
	end
end)

-- Tell other servers we're shutting down and not to count us as a partition member
if not runService:IsStudio() then
	game:BindToClose(function()
		inShutdown = true
		--utilities.publishMessage(SERVER_SHUTDOWN_TOPIC, game.JobId)
	end)
end


return testingMod