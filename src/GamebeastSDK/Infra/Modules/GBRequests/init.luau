-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local playerService = game:GetService("Players")
local messagingService = game:GetService("MessagingService")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local sdk = script.Parent.Parent.Parent
local utilities = shared.GBMod("Utilities")
local queue = require(script.Parent.Utilities.Queue)
local requestFunctions = require(script.RequestFunctions)
local requestsMod = {}

-- For testing in studio, make sure pending jobs are ran before closing
requestsMod.pendingJobsRan = false

-- How often we check for new requests from GB dashboard
local UPDATE_PERIOD = 1
local EXECUTION_PERIOD = 0.5

-- Subscription topic name for direct requests from GB
requestsMod.GB_MESSAGING_TOPIC = "GB_REQ_MESSAGE"

-- Subscription topic name for request results from servers
requestsMod.GB_RESULT_TOPIC = "GB_RES_MESSAGE"

-- How long we hold on to the result of a request
local CACHE_EXPIRY_TIME = 30

-- 1024 byte limit in docs but less in practice because of metadata. Not exactly calculated but this will never exceed the limit.
local MESSAGE_SIZE_LIMIT = 800
local requestBodyChunkPool = {}

-- Data structures for request and result processing
-- For tracking if a request has already been added to the request queue for processing
requestsMod.requestQueueIdMap = {}

-- Used for batching and sending request results to backend
requestsMod.asyncResultQueue = {}

-- For tracking if a request is already being processed and we started
requestsMod.requestProcessIdMap = {}

-- For processing requests in the order received
requestsMod.requestQueue = queue.new()

-- Short term cache for request results to avoid reprocessing repeatedly sent requests
requestsMod.resultCacheMap = {}

-- Request dispatcher

-- Primary API
local GBDomain = "https://api.dev.gamebeast.gg"

-- Endpoint to method map
local requestMethodMap = {
	["users/create"] = "POST",
	["health_check"] = "GET",
	["jobs/create"] = "POST",
	["requests"] = "GET",
	["requests/completed"] = "POST",
	["requests/started"] = "PUT",
	["application/boot_info"] = "GET",
	["sdk/roblox/configurations"] = "GET",
	["sdk/roblox/markers"] = "POST",
	["sdk/roblox/heatmap"] = "POST",
	["sdk/roblox/heatmap/waypoint"] = "POST",
}

-- If no keys module, abort - we can't communicate with backend without keys
if not sdk:FindFirstChild("Keys") then
	utilities.GBWarn("Keys module not found. Please click the Gamebeast plugin to fix your SDK.")
end

-- Capture key and delete module, keeping it only in stack
local keys = require(sdk.Keys)
local projectKey = keys.projectKey
sdk.Keys:Destroy()

-- One time warning if requests are failing because of invalid/unset key
local keyWarningGiven = false

-- Main method for dispatching requests from SDK to backend
-- Returns parsed body and original response if body can be resolve and response only otherwise
requestsMod.GBRequest = function(requestType : string, args : {[string] : any}, maxRetries : number?)
	local requestMethod = requestMethodMap[requestType]
	local response, body
	args = args or {}
	
	local partition = shared.GBMod("ABTesting").CUR_PARTITION
	
	-- Define relevant headers. Backend enforces header presence unless specified.
	local headers = {
		["authorization"] = projectKey,
		["isstudio"] = tostring(runService:IsStudio()),
		["sdkversion"] = sdk:GetAttribute("Version") or "NA",
		["universeid"] = tostring(game.GameId),
		-- optional, to be removed with A/B testing overhaul
		["partitionid"] = partition ~= "" and partition or nil,
	}
	
	-- JobId is undefined in studio so send a hard coded default for this environment
	if headers["isstudio"] then
		headers["serverid"] = "00000000-0000-0000-0000-000000000000"
	else
		headers["serverid"] = game.JobId
	end
	
	local url = GBDomain.. "/".. requestType

	if requestMethod == "POST" or requestMethod == "PUT" then
		body = httpService:JSONEncode(args)
		headers["Content-Type"] = "application/json"
	elseif requestMethod == "GET" then
		-- Encode args to query string
		local paramString = "?"
		for key, val in args do
			paramString ..= key.. "=".. httpService:UrlEncode(val).. "&"
		end
		
		paramString = string.sub(paramString, 1, #paramString - 1)
		url ..= paramString
	end
		
	-- Send request
	response = utilities.promiseReturn(maxRetries or 1, function()
		return httpService:RequestAsync({
			Url = url,
			Method = requestMethod,
			Headers = headers,
			Body = body
		})
	end)

	if response and #response.Body > 0 then
		if response.StatusCode == 401 or response.StatusCode == 403 and not keyWarningGiven then
			utilities.GBWarn("Gamebeast project key invalid or not set! Set your project key in the Keys module.")
			keyWarningGiven = true
		end
		
		-- Decode returned body
		--print(results)
		local bodyParsed, success = utilities.promiseReturn(0, function()
			return httpService:JSONDecode(response.Body)
		end)
		
		return bodyParsed, response
	end
	
	return response
end

-- Handles adding of new requests into request pipeline
requestsMod.addRequestsToQueue = function(newRequests)
	for _, request in newRequests do
		if request.details.host_only and not request.details.host_authority and not shared.GBMod("HostServer").isHostServer() then
			continue
		end
		
		local cachedResult
		
		-- Check if we already have a result for this request and it's been erroneously resent
		if requestsMod.resultCacheMap[request.request_id] then
			cachedResult = requestsMod.resultCacheMap[request.request_id].result
		end
		
		-- Resend result across the network in case of previously failed delivery from SDK or if delayed/duplicated request
		if cachedResult then
			requestsMod.addResultToAsyncQueue(cachedResult)
			continue
		end

		-- If this event isn't already being processed, then add to queue and add tracking state info
		if not requestsMod.requestQueueIdMap[request.request_id] then
			requestsMod.requestQueue:push(request)
			requestsMod.requestQueueIdMap[request.request_id] = os.time()
		end
	end
end

-- Add a single request to the async result queue to be sent to GB
requestsMod.addResultToAsyncQueue = function(result)
	table.insert(requestsMod.asyncResultQueue, result)
end

-- Cleans up requests after processing. Can be request or result, just needs request_id field.
requestsMod.sendRequestResults = function(results)
	-- Sent once per batch
	requestsMod.GBRequest("requests/completed", results)

	for _, result in results do
		local id = result.request_id
		
		-- Cache result to avoid reprocessing in the event of a delayed/duplicated request across the network
		requestsMod.resultCacheMap[id] = {
			result = result;
			timeSubmitted = os.time();
		}
		
		-- Remove state about this request currently being processed
		requestsMod.requestQueueIdMap[id] = nil
		requestsMod.requestProcessIdMap[id] = nil
		
		-- Remove stored chunks if request was chunked via messaging service to this server from host
		if requestBodyChunkPool[id] then
			requestBodyChunkPool[id] = nil
		end
	end
end

-- Clear old cached results from result cache
local function clearOldCachedResults()
	local curTime = os.time()
	
	for id, result in requestsMod.resultCacheMap do
		if curTime - result.timeSubmitted >= CACHE_EXPIRY_TIME then
			requestsMod.resultCacheMap[id] = nil
			
			if requestBodyChunkPool[id] then
				requestBodyChunkPool[id] = nil
			end
		end
	end
end

-- Receive requests from host server and other sources
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(requestsMod.GB_MESSAGING_TOPIC, function(message)
		local decodedRequests = httpService:JSONDecode(message.Data)
		local newRequests = {}

		for _, request in decodedRequests do
			-- This is a request sent from the host with total message size >1KiB, meaning it was chunked for MessagingService
			if request.chunked then
				if not requestBodyChunkPool[request.request_id] then
					requestBodyChunkPool[request.request_id] = {}
				end

				-- Add chunk to pool	
				requestBodyChunkPool[request.request_id][request.chunk_id] = request.args

				local haveAllChunks = true

				for i = 1, request.chunks do
					if not requestBodyChunkPool[request.request_id][i] then
						haveAllChunks = false
						break
					end
				end

				-- If all chunks accounted for, reconstruct via concatenation and load body, continue with normal pipeline
				if haveAllChunks then
					local argString = ""
					
					for i = 1, request.chunks do
						argString ..= requestBodyChunkPool[request.request_id][i]
					end

					request.args = httpService:JSONDecode(argString)
					table.insert(newRequests, request)
				else
					continue
				end
			else
				-- Not chunked, just add request
				table.insert(newRequests, request)
			end
		end
		
		requestsMod.addRequestsToQueue(newRequests)
	end)
end)

-- Return results from non-host servers to host.
utilities.promiseReturn(nil, function()
	messagingService:SubscribeAsync(requestsMod.GB_RESULT_TOPIC, function(message)
		local result = httpService:JSONDecode(message.Data)
		
		if shared.GBMod("HostServer").isHostServer()  then
			requestsMod.addResultToAsyncQueue(result)
		end
	end)
end)

-- Send a failure message for a given request with arbitrary args
requestsMod.sendFailure = function(request, result)
	result = result or {}
	requestsMod.addResultToAsyncQueue({request_id=request.request_id, status="failure", result=result})
end

-- Send a success message for a given request with arbitrary args
requestsMod.sendSuccess = function(request, result)
	result = result or {}
	requestsMod.addResultToAsyncQueue({request_id=request.request_id, status="success", result=result})
end

-- Check for new requsts and add to queue loop
local lastReqWarning = 0
task.spawn(function()
	local function checkForRequests()
		-- Check if old cached results need to be cleared
		clearOldCachedResults()

		-- Only host should be asking for requests
		if not shared.GBMod("HostServer").isHostServer() then return end

		-- Get requests from Gamebeast. Soon-to-be legacy?
		local newRequests, resp = requestsMod.GBRequest("requests")

if not newRequests or (resp["error"] or resp["StatusCode"] ~= 200) then
			if tick() - lastReqWarning >= 10 and resp["StatusCode"] ~= 403 then
				utilities.GBWarn("Issue getting new requests from Gamebeast dashboard. Check status.gamebeast.gg and status.roblox.com.")
				lastReqWarning = tick()
			end
			return
		end

		requestsMod.addRequestsToQueue(newRequests)
	end
	
	-- Yield only if first configs/initialization not done
	shared.GBMod("Configs").checkGBReady()
	
	checkForRequests()
	
	requestsMod.pendingJobsRan = true
	
	while task.wait(UPDATE_PERIOD) do
		checkForRequests()
		UPDATE_PERIOD = shared.GBMod("Configs")["GBConfigs"]["GBRates"]["CheckRequests"]
	end
end)

-- Request execution loop
task.spawn(function()
	while task.wait(EXECUTION_PERIOD) do		
		local synchronousResults = {}
		local isHost = shared.GBMod("HostServer").isHostServer()
		local queueLen = requestsMod.requestQueue.len
		
		-- Iterate over queue of requests at process start time, i.e. ignore new requests getting added to queue one loop begins
		for i = 1, queueLen do
			local request = requestsMod.requestQueue:pop()
			
			if requestsMod.requestProcessIdMap[request.request_id] then
				continue
			end

			requestsMod.requestProcessIdMap[request.request_id] = os.time()
			
			-- Send job started message
			if isHost then
				requestsMod.GBRequest("requests/started", {request.request_id})
			end
			
			if (isHost or request.details.host_authority) and not request.details.host_only then
				local requestString = httpService:JSONEncode(request)
				local argsString = httpService:JSONEncode(request.args)

				-- We need to chunk into messages that will fit into MessagingService limit to propagate requests to servers
				if #requestString > MESSAGE_SIZE_LIMIT then
					local request = utilities.recursiveCopy(request)
					request.chunked = true
					
					-- Make chunks as large as possible to send fewest messages, accounting for chunk metadata we're adding too
					local argsChunkSize = MESSAGE_SIZE_LIMIT - ((#requestString + 150) - #argsString)
					
					-- We can only chunk args, so if the request itself is larger than the limit, abort
					if argsChunkSize <= 0 then
						utilities.GBWarn("Request too large to chunk, aborting.")
						requestsMod.sendFailure(request, {details="request too large to chunk"})
						continue
					end
					
					local argChunks = {}
					local chunkText
					local curIndex = 1
					
					-- Generate message chunks at determined size
					repeat
						chunkText = string.sub(argsString, curIndex, curIndex + argsChunkSize - 1)
						curIndex += argsChunkSize
						table.insert(argChunks, chunkText)
					until #chunkText < argsChunkSize
					
					-- Let recipient servers how many chunks to expect before reconstruction
					request.chunks = #argChunks
					
					-- Send all chunks to other servers
					for i = 1, #argChunks do
						request.args = argChunks[i]
						request.chunk_id = i
						
						task.spawn(function()
							utilities.publishMessage(requestsMod.GB_MESSAGING_TOPIC, httpService:JSONEncode({request}))
						end)
					end
				else
					-- No chunking needed, send full message to other servers
					task.spawn(function()
						utilities.publishMessage(requestsMod.GB_MESSAGING_TOPIC, httpService:JSONEncode({request}))
					end)
				end
			end

			-- Process request
			if not request.details.host_only or isHost or request.details.host_authority then
				local requestFunc = requestFunctions.funcs[request.request_type]
				
				-- Either run relevant function in its own thread or (potentially) yield and run sequentially as determined by request details
				if request.details.async then
					task.spawn(function()
						requestFunc(request)
					end)
				else
					local result = requestFunc(request)
					table.insert(synchronousResults, {request_id = request.request_id, result = result})
				end
			end
		end
		
		-- Send results to GB, results are only ever in our queue if we're host
		-- Send synchronous results to GB
		-- NOTE: Kind of pointless since we send any async results right after, resulting in 2 requests.
		-- We should just put sync results in async queue unless we move async to a separate reporting schedule
		if #synchronousResults > 0 then
			requestsMod.sendRequestResults(synchronousResults)
		end
		
		-- Send any queued async results to GB
		if #requestsMod.asyncResultQueue > 0 then
			local queuedResults = requestsMod.asyncResultQueue
			requestsMod.asyncResultQueue = {}
			requestsMod.sendRequestResults(queuedResults)
		end
	end
end)

return requestsMod