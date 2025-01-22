-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local playerService = game:GetService("Players")
local messagingService = game:GetService("MessagingService")
local httpService = game:GetService("HttpService")
local chatService = game:GetService("Chat")

local utilities = shared.GBMod("Utilities")

-- Header comments provide info on request details sent from backend.

-- host_only: whether this job is only ever executed by the host server or propagated by the host server for execution on all servers

-- async: whether this request yields other requests in the queue and returns its result immediately or is run on its own thread
-- and the result is added to the async batch queue.

-- Make sure to check HostServer:IsHostServer() before sending request results for host_only: false requests or risk every
-- server pinging our backend.
-- For requests where we actually want to aggregate results from servers, publish to the GBRequests.GB_RESULT_TOPIC channel
-- and the host will batch and report results

-- Functions we define for each request type from the GB dashboard
local requestFunctions = {}

requestFunctions.funcs = {	
	-- host_only: true
	-- async: true
	["Ban"] = function(request)
		local args = request.args
		local userIdentifier = args.user_identifier
		local success
		
		-- We support UserIds + usernames from the dashboard
		if not tonumber(userIdentifier) then
			-- Get UserId from username
			userIdentifier, success = utilities.promiseReturn(1, function()
				return playerService:GetUserIdFromNameAsync(userIdentifier)
			end)
			
			-- If the service failed, we can't proceed
			if not success then
				shared.GBMod("GBRequests").sendFailure(request)
				return
			end
		else
			-- Valid numeric, we proceed
			userIdentifier = tonumber(userIdentifier)
		end
		
		-- If nil, we use -1 (Ban API representation of perm)
		local banTime = args.ban_duration or -1
		
		-- Execute ban action
		local _, success = utilities.promiseReturn(2, function()
			playerService:BanAsync({UserIds = {userIdentifier}, Duration = banTime, DisplayReason = args.reason, PrivateReason = args.private_reason, ExcludeAltAccounts = args.exclude_alts})
		end)
		
		if not success then
			shared.GBMod("GBRequests").sendFailure(request)
		else
			shared.GBMod("GBRequests").sendSuccess(request)
		end
	end;
	
	-- host_only: true
	-- async: true
	["Unban"] = function(request)
		local args = request.args
		local userIdentifier = args.user_identifier
		local success

		-- We support UserIds + usernames from the dashboard
		if not tonumber(userIdentifier) then
			-- Get UserId from username
			userIdentifier, success = utilities.promiseReturn(1, function()
				return playerService:GetUserIdFromNameAsync(userIdentifier)
			end)

			-- If the service failed, we can't proceed
			if not success then
				shared.GBMod("GBRequests").sendFailure(request)
				return
			end
		else
			-- Valid numeric, we proceed
			userIdentifier = tonumber(userIdentifier)
		end
		
		-- Execute unban action
		local _, success = utilities.promiseReturn(2, function()
			playerService:UnbanAsync({UserIds = {userIdentifier}})
		end)

		if not success then
			shared.GBMod("GBRequests").sendFailure(request)
		else
			shared.GBMod("GBRequests").sendSuccess(request)
		end
	end;
	
	-- host_only: false
	-- async: true
	["Kick"] = function(request)
		local args = request.args
		local userIdentifier = args.user_identifier
		-- We support UserIds + usernames from the dashboard
		if tonumber(userIdentifier) then
			--
			for _, player in playerService:GetPlayers() do
				if player.UserId == tonumber(userIdentifier) then
					local filteredReason = utilities.promiseReturn(1, function()
						return chatService:FilterStringForBroadcast(args.reason, player)
					end)

					player:Kick(filteredReason)
				end
			end
		else
			local player = playerService:FindFirstChild(userIdentifier)

			if player then
				local filteredReason = utilities.promiseReturn(1, function()
					return chatService:FilterStringForBroadcast(args.reason, player)
				end)
				
				player:Kick(filteredReason)
			end
		end
		
		if shared.GBMod("HostServer"):IsHostServer() then
			shared.GBMod("GBRequests").sendSuccess(request)
		end
	end;
	
	-- host_only: false
	-- async: false
	["UpdateConfigs"] = function(request)
		shared.GBMod("Updater"):UpdateConfigs(request.args)
		
		if shared.GBMod("HostServer"):IsHostServer() then
			shared.GBMod("GBRequests").sendSuccess(request, {})
		end
	end;
	
	-- Not yet implemented
	--["CustomJob"] = function(request)
	--	local res, success = utilities.promiseReturn(0, function()
	--		shared.GBMod("CustomJobs").executeCustomJob(request.args)
	--	end)
		
	--	if success then
	--		shared.GBMod("GBRequests").sendFailure(request)
	--	else
	--		shared.GBMod("GBRequests").sendSuccess(request, {res})
	--	end
	--end;
}

return requestFunctions