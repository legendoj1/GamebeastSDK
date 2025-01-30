--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	HostServer.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local HostServer = { }

--= Roblox Services =--

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

--= Dependencies =--


local Utilities = shared.GBMod("Utilities")

--= Types =--

--= Object References =--

local RandomObject = Random.new()

--= Constants =--

-- Messaging service topics for cross server communication
local LEADER_PING_TOPIC = "HOST_SERVER_PRESENT"
local OTHER_PING_TOPIC = "HOST_SYNC"

-- How often we check if more than one host exists and resolve
local DUPLICATE_CHECK_TIME = 15

-- How often we check if no host exists and resolve
local NO_HOST_CHECK_TIME = 5

--= Variables =--

local HostServerStatus = RunService:IsStudio()
local HostServerActive = false
local LastHostTick = 0

--= Public Variables =--

--= Internal Functions =--

-- Establish connections and update fields to assume server role
local function assumeHostServerRole()
	Utilities.GBWarn("No Gamebeast host server detected - assuming role.")
	
	-- Tell other servers you're the captain now
	Utilities.publishMessage(LEADER_PING_TOPIC, game.JobId)
	HostServerActive = false
	HostServerStatus = true
	
	-- While the host server, periodically make sure other host servers do not somehow exist, otherwise relinquish role
	task.spawn(function()
		while task.wait(DUPLICATE_CHECK_TIME) and HostServerStatus do
			Utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)
			task.wait(3)
			
			-- If some other server responded saying they're the host, relinquish, otherwise do nothing
			if tick() - LastHostTick < 5 then
				HostServer:RelinquishHostServerRole()
				break
			end
		end	
	end)
end

--= API Functions =--


-- Returns whether we are currently the host server
function HostServer:IsHostServer()
	return HostServerStatus
end

-- Update fields so we are no longer the host server and don't execute host only requests
function HostServer:RelinquishHostServerRole()
	HostServerActive = true
	HostServerStatus = false
end




-- Sends out signal to see if the host server responds. If no response, attempts to assume host server role
function HostServer:CheckHostServerActive(assumeIfInactive : boolean?)
	if HostServerStatus then
		return true
	end

	Utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)

	task.wait(3)
	
	if tick() - LastHostTick > 5 then	
		if assumeIfInactive then
			assumeHostServerRole()
		else
			return false
		end
	end
end

--= Initializers =--
function HostServer:Init()
	
	-- If ping is received on this channel and it is not from ourself, then another host server exists and we relinquish role
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(LEADER_PING_TOPIC, function(message)
			if message.Data ~= game.JobId then
				LastHostTick = tick()
				--print("New host server found: ".. message.Data)

				self:RelinquishHostServerRole()
			end
		end)
	end)

	-- If ping is received on this channel and we are the host server, we signal we are still active
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(OTHER_PING_TOPIC, function(message)
			if message.Data ~= game.JobId and (not HostServerActive or HostServerStatus) then
				Utilities.publishMessage(LEADER_PING_TOPIC, game.JobId)
			end
		end)
	end)

	Utilities.publishMessage(OTHER_PING_TOPIC, game.JobId)
	-- Attempt to claim host server role at start up
	-- Random staggering to minimize collisions
	-- Will probably make deterministic host election implementation in the future like with A/B testing server partitions but this systems is 3+ years tried and true
	task.spawn(function()
		task.wait(RandomObject:NextNumber(1, 8))

		if not RunService:IsStudio() then
			if not HostServerActive then
				assumeHostServerRole()
			end
			
			while task.wait(NO_HOST_CHECK_TIME) do
				self:CheckHostServerActive(true)
			end
		end
	end)
end

--= Return Module =--
return HostServer