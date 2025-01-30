--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	ABTesting.luau
	
	Description:
		Handles the A/B testing partitioning of servers.
	
--]]

--= Root =--
local ABTesting = { }

--= Roblox Services =--

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

--= Dependencies =--

local Utilities = shared.GBMod("Utilities")
local InternalConfigs = shared.GBMod("InternalConfigs") ---@module InternalConfigs
local Signal = shared.GBMod("Signal")

--= Types =--

--= Object References =--

local RandomObject = Random.new()

--= Constants =--

-- Messaging channels for pinging/self-reporting a server exists for self-determining server partition.
local PARTITION_REQ_TOPIC = "CUR_PARTITION_REQ"
local PARTITION_RES_TOPIC = "CUR_PARTITION_RES"

-- How often we check to rebalance
local REBALANCE_CHECK_TIME = NumberRange.new(30, 60)

-- List of JobIds of other servers for determining server partition
local otherServerPartitions = {}

--= Variables =--

local InShutdown = false

--= Public Variables =--

ABTesting.NewConfigSignal = Signal.new()

--= Internal Functions =--

-- Get list of JobIDs from other server and map to what server partition they're in
local function getServerPartitions(configs)
	Utilities.publishMessage(PARTITION_REQ_TOPIC, game.JobId)
	-- MessagingService guarantees <= 1 sec response time from all servers, so wait within bounds for all to respond.
	task.wait(1.1)
end

-- Call update configs with cur configs to check/update partition without changing values
local function checkPartitionDisribution()
	local curConfigs = InternalConfigs:CopyConfigs()
	curConfigs.GBConfigs = InternalConfigs:GetActiveConfig("GBConfigs") --NOTE: Are we just tacking GBConfigs onto the end of the configs table?

	-- See what set of configs we *should* be using, taking A/B testing campaigns into consideration
	local _, partitionName = ABTesting:GetConfigProfileForServer(curConfigs)

	-- If our current profile doesn't match what we should be using, update
	if partitionName ~= ABTesting.CUR_PARTITION then
		-- Note we call with cur configs because updateConfigs will handle selecting and updating to a new partiton via the same method we did above
		-- Don't assume too much control, we only find something needs to change and let the function handle it
		ABTesting.NewConfigSignal:Fire(curConfigs)
	end
end

--= API Functions =--

ABTesting.CUR_PARTITION = ""

function ABTesting:SetCurrentPartition(partitionName)
	ABTesting.CUR_PARTITION = partitionName
end

-- See how many server partitions exist for current set of configurations
function ABTesting:GetPartitionCount(configs) : number
	return #configs.GBConfigs.ABTestingCampaigns.partitions
end


-- Select appropriate config partition, canonical or A/B testing server campaign partition

function ABTesting:GetConfigProfileForServer(newConfigs)
	local numPartitions = self:GetPartitionCount(newConfigs)

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

--= Initializers =--
function ABTesting:Init()

	-- Subscribe to receive responses of what partition other servers are on
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(PARTITION_RES_TOPIC, function(message)
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
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(PARTITION_REQ_TOPIC, function(message)
			-- Don't reply to our own message or if the server is shutting down
			if message.Data ~= game.JobId and not InShutdown then
				local mesage = {
					jobId = game.JobId,
					partition = ABTesting.CUR_PARTITION,
					requestee = message.Data,
				}

				Utilities.publishMessage(PARTITION_RES_TOPIC, mesage)
			end
		end)
	end)

	-- Tell other servers we're shutting down and not to count us as a partition member
	if not RunService:IsStudio() then
		game:BindToClose(function()
			InShutdown = true
			--utilities.publishMessage(SERVER_SHUTDOWN_TOPIC, game.JobId)
		end)
	end

	-- Tell other servers we exist and start partition self-rebalance loop
	InternalConfigs:OnReady(function()
		while task.wait(RandomObject:NextNumber(REBALANCE_CHECK_TIME.Min, REBALANCE_CHECK_TIME.Max)) do
			checkPartitionDisribution()
		end
	end)

end

--= Return Module =--
return ABTesting