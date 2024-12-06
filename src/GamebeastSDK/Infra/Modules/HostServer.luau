-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local messagingService = game:GetService("MessagingService")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")
local random = Random.new()

local hostServerMod = {}

-- Messaging service topics for cross server communication
local LEADER_PING_TOPIC = "HOST_SERVER_PRESENT"
local OTHER_PING_TOPIC = "HOST_SYNC"

-- How often we check if more than one host exists and resolve
local DUPLICATE_CHECK_TIME = 15

-- How often we check if no host exists and resolve
local NO_HOST_CHECK_TIME = 5

local hostServer = runService:IsStudio()
local hostServerActive = false
local lastHostTick = 0

-- Returns whether we are currently the host server
hostServerMod.isHostServer = function()
	return hostServer
end

-- Update fields so we are no longer the host server and don't execute host only requests
hostServerMod.relinquishHostServerRole = function()
	hostServerActive = true
	hostServer = false
end

-- If ping is received on this channel and it is not from ourself, then another host server exists and we relinquish role
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(LEADER_PING_TOPIC, function(message)
		if message.Data ~= game.JobId then
			lastHostTick = tick()
			--print("New host server found: ".. message.Data)

			hostServerMod.relinquishHostServerRole()
		end
	end)
end)

-- If ping is received on this channel and we are the host server, we signal we are still active
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(OTHER_PING_TOPIC, function(message)
		if message.Data ~= game.JobId and (not hostServerActive or hostServer) then
			utilities.publishMessage(LEADER_PING_TOPIC, game.JobId)
		end
	end)
end)

utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)

-- Establish connections and update fields to assume server role
local function assumeHostServerRole()
	utilities.GBWarn("No Gamebeast host server detected - assuming role.")
	
	-- Tell other servers you're the captain now
	utilities.publishMessage(LEADER_PING_TOPIC, game.JobId)
	hostServerActive = false
	hostServer = true
	
	-- While the host server, periodically make sure other host servers do not somehow exist, otherwise relinquish role
	task.spawn(function()
		while task.wait(DUPLICATE_CHECK_TIME) and hostServer do
			utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)
			task.wait(3)
			
			-- If some other server responded saying they're the host, relinquish, otherwise do nothing
			if tick() - lastHostTick < 5 then
				hostServerMod.relinquishHostServerRole()
				break
			end
		end	
	end)
end

-- Sends out signal to see if the host server responds. If no response, attempts to assume host server role
hostServerMod.checkHostServerActive = function(assumeIfInactive)
	if hostServer then
		return true
	end

	utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)

	task.wait(3)
	
	if tick() - lastHostTick > 5 then	
		if assumeIfInactive then
			assumeHostServerRole()
		else
			return false
		end
	end
end

-- Attempt to claim host server role at start up
-- Random staggering to minimize collisions
-- Will probably make deterministic host election implementation in the future like with A/B testing server partitions but this systems is 3+ years tried and true
task.spawn(function()
	task.wait(random:NextNumber(1, 8))

	if not runService:IsStudio() then
		if not hostServerActive then
			assumeHostServerRole()
		end
		
		while task.wait(NO_HOST_CHECK_TIME) do
			hostServerMod.checkHostServerActive(true)
		end
	end
end)

return hostServerMod