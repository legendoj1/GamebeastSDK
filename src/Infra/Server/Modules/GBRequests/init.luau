--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	GBRequests.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local GBRequests = { }

--= Roblox Services =--

local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

--= Dependencies =--

local RequestFunctions = require(script.RequestFunctions)
local Utilities = shared.GBMod("Utilities")
local Queue = shared.GBMod("Queue")
local DataCache = shared.GBMod("DataCache")
local Signal = shared.GBMod("Signal") ---@module Signal

--= Types =--

--= Constants =--

-- How often we check for new requests from GB dashboard
local UPDATE_PERIOD = 1
local EXECUTION_PERIOD = 0.5
-- How long we hold on to the result of a request
local CACHE_EXPIRY_TIME = 30
-- 1024 byte limit in docs but less in practice because of metadata. Not exactly calculated but this will never exceed the limit.
local MESSAGE_SIZE_LIMIT = 800
-- Subscription topic name for direct requests from GB
local GB_MESSAGING_TOPIC = "GB_REQ_MESSAGE"
local ENDPOINTS = {
	{
		URL = "https://api.gamebeast.gg", -- http://localhost:3001 -- https://api.gamebeast.gg -- https://api.stage.gamebeast.gg
		Requests = {
			["sdk/markers"] = "POST",
			["users/create"] = "POST",
			["health_check"] = "GET",
			["jobs/create"] = "POST",
			["sdk/requests"] = "GET",
			["sdk/requests/completed"] = "POST",
			["sdk/requests/started"] = "PUT",
			["application/boot_info"] = "GET",
			["sdk/configurations"] = "GET",
			["sdk/heatmap"] = "POST",
			["sdk/heatmap/waypoint"] = "POST",
		}
	}
}

--= Object References =--

local FinalRequestSignal = Signal.new()
local RequestProcessingCount = 0

-- For processing requests in the order received
local RequestQueue = Queue.new()

--= Variables =--

local KeyYeildWarning = false

-- One time warning if requests are failing because of invalid/unset key
local keyWarningGiven = false

local RequestBodyChunkPool = {}
-- Data structures for request and result processing
-- For tracking if a request has already been added to the request queue for processing
RequestQueueIdMap = {}
-- Short term cache for request results to avoid reprocessing repeatedly sent requests
ResultCacheMap = {}
-- For tracking if a request is already being processed and we started
RequestProcessIdMap = {}
-- Used for batching and sending request results to backend
AsyncResultQueue = {}
-- For testing in studio, make sure pending jobs are ran before closing
PendingJobsRan = false

--= Public Variables =--

-- Subscription topic name for request results from servers
--TODO: Remove this out of public variables.
GBRequests.GB_RESULT_TOPIC = "GB_RES_MESSAGE"

--= Internal Functions =--

local function GetEndpointForRequest(requestType) : (string?, string?)
	for _, endpoint in ENDPOINTS do
		if endpoint.Requests[requestType] then
			return endpoint.URL, endpoint.Requests[requestType]
		end
	end
end

local function YeildForKey() : string | Secret
	local start = tick()
	while not DataCache:Get("Key") do
		task.wait()
		if tick() - start > 5 and not KeyYeildWarning then
			Utilities.GBWarn("Gamebeast key not found! Did you call Gamebeast:Setup()?")
			KeyYeildWarning = true
			break
		end
	end

	return DataCache:Get("Key")
end

-- Clear old cached results from result cache
local function ClearOldCachedResults()
	local curTime = os.time()

	for id, result in ResultCacheMap do
		if curTime - result.timeSubmitted >= CACHE_EXPIRY_TIME then
			ResultCacheMap[id] = nil

			if RequestBodyChunkPool[id] then
				RequestBodyChunkPool[id] = nil
			end
		end
	end
end

--= API Functions =--

-- Callback that is fired when the game is shutting down for final request processing.
function GBRequests:OnFinalRequestCall(callback : () -> ())
	return FinalRequestSignal:Connect(function()
		local currentThread = coroutine.running()
		callback()
		if currentThread ~= coroutine.running() then
			error("Final request should not yeild!")
		end
	end)
end

-- Main method for dispatching requests from SDK to backend
-- Returns parsed body and original response if body can be resolve and response only otherwise
function GBRequests:GBRequest(requestType : string, args : {[string] : any}) : nil
	local _, requestsMethod = GetEndpointForRequest(requestType)
	if requestsMethod ~= "POST" then
		Utilities.GBWarn("GBRequest should only be used for POST requests. Use GBRequestAsync for other request types.")
	end

	task.spawn(function()
		self:GBRequestAsync(requestType, args)
	end)
end

--YEILDS 
function GBRequests:GBRequestAsync(requestType : string, args : {[string] : any}, maxRetries : number?) : any
	RequestProcessingCount += 1
	local GBDomain, requestMethod = GetEndpointForRequest(requestType)
	local response, body
	args = args or {}

	local partition = shared.GBMod("ABTesting").CUR_PARTITION

	local authKey = YeildForKey()

	-- Define relevant headers. Backend enforces header presence unless specified.
	local headers = {
		["authorization"] = authKey,
		["isstudio"] = tostring(RunService:IsStudio()),
		["sdkversion"] = "NA", --TODO: Get SDK version from attribute on SDK.
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
		body = HttpService:JSONEncode(args)
		headers["Content-Type"] = "application/json"
	elseif requestMethod == "GET" then
		-- Encode args to query string
		local paramString = "?"
		for key, val in args do
			paramString ..= key.. "=".. HttpService:UrlEncode(val).. "&"
		end

		paramString = string.sub(paramString, 1, #paramString - 1)
		url ..= paramString
	end

	-- Send request
	response = Utilities.promiseReturn(maxRetries or 1, function()
		return HttpService:RequestAsync({
			Url = url,
			Method = requestMethod,
			Headers = headers,
			Body = body
		})
	end)


	RequestProcessingCount -= 1

	if response and #response.Body > 0 then
		if response.StatusCode == 401 or response.StatusCode == 403 and not keyWarningGiven then
			Utilities.GBWarn("Gamebeast project key invalid or not set! Set your project key in the :Setup method.")
			keyWarningGiven = true
		end

		-- Decode returned body
		--print(results)
		local bodyParsed, success = Utilities.promiseReturn(0, function()
			return HttpService:JSONDecode(response.Body)
		end)

		return bodyParsed, response
	end

	return response
end

-- Handles adding of new requests into request pipeline
function GBRequests:AddRequestsToQueue(newRequests)
	for _, request in newRequests do
		if request.details.hostOnly and not request.details.host_authority and not shared.GBMod("HostServer"):IsHostServer() then
			continue
		end

		local cachedResult

		-- Check if we already have a result for this request and it's been erroneously resent
		if ResultCacheMap[request.requestId] then
			cachedResult = ResultCacheMap[request.requestId].result
		end

		-- Resend result across the network in case of previously failed delivery from SDK or if delayed/duplicated request
		if cachedResult then
			self:AddResultToAsyncQueue(cachedResult)
			continue
		end

		-- If this event isn't already being processed, then add to queue and add tracking state info
		if not RequestQueueIdMap[request.requestId] then
			RequestQueue:push(request)
			RequestQueueIdMap[request.requestId] = os.time()
		end
	end
end

-- Add a single request to the async result queue to be sent to GB
function GBRequests:AddResultToAsyncQueue(result)
	table.insert(AsyncResultQueue, result)
end

-- Cleans up requests after processing. Can be request or result, just needs requestId field.
function GBRequests:SendRequestResults(results)
	-- Sent once per batch
	self:GBRequestAsync("sdk/requests/completed", results)

	for _, result in results do
		local id = result.requestId

		-- Cache result to avoid reprocessing in the event of a delayed/duplicated request across the network
		ResultCacheMap[id] = {
			result = result;
			timeSubmitted = os.time();
		}

		-- Remove state about this request currently being processed
		RequestQueueIdMap[id] = nil
		RequestProcessIdMap[id] = nil

		-- Remove stored chunks if request was chunked via messaging service to this server from host
		if RequestBodyChunkPool[id] then
			RequestBodyChunkPool[id] = nil
		end
	end
end

-- Send a failure message for a given request with arbitrary args
function GBRequests:SendFailure(request, result)
	result = result or {}
	self:AddResultToAsyncQueue({requestId=request.requestId, status="failure", result=result})
end

-- Send a success message for a given request with arbitrary args
function GBRequests:SendSuccess(request, result)
	result = result or {}
	self:AddResultToAsyncQueue({requestId=request.requestId, status="success", result=result})
end


--= Initializers =--
function GBRequests:Init()
	-- Receive requests from host server and other sources
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(GB_MESSAGING_TOPIC, function(message)
			local decodedRequests = HttpService:JSONDecode(message.Data)
			local newRequests = {}

			for _, request in decodedRequests do
				-- This is a request sent from the host with total message size >1KiB, meaning it was chunked for MessagingService
				if request.chunked then
					if not RequestBodyChunkPool[request.requestId] then
						RequestBodyChunkPool[request.requestId] = {}
					end

					-- Add chunk to pool	
					RequestBodyChunkPool[request.requestId][request.chunk_id] = request.args

					local haveAllChunks = true

					for i = 1, request.chunks do
						if not RequestBodyChunkPool[request.requestId][i] then
							haveAllChunks = false
							break
						end
					end

					-- If all chunks accounted for, reconstruct via concatenation and load body, continue with normal pipeline
					if haveAllChunks then
						local argString = ""

						for i = 1, request.chunks do
							argString ..= RequestBodyChunkPool[request.requestId][i]
						end

						request.args = HttpService:JSONDecode(argString)
						table.insert(newRequests, request)
					else
						continue
					end
				else
					-- Not chunked, just add request
					table.insert(newRequests, request)
				end
			end

			self:AddRequestsToQueue(newRequests)
		end)
	end)

	-- Return results from non-host servers to host.
	Utilities.promiseReturn(nil, function()
		MessagingService:SubscribeAsync(self.GB_RESULT_TOPIC, function(message)
			local result = HttpService:JSONDecode(message.Data)

			if shared.GBMod("HostServer"):IsHostServer()  then
				self:AddResultToAsyncQueue(result)
			end
		end)
	end)


	-- Check for new requsts and add to queue loop
	local lastReqWarning = 0
	task.spawn(function()
		local function checkForRequests()
			-- Check if old cached results need to be cleared
			ClearOldCachedResults()

			-- Only host should be asking for requests
			if not shared.GBMod("HostServer"):IsHostServer() then return end

			-- Get requests from Gamebeast. Soon-to-be legacy?
			local newRequests, resp = self:GBRequestAsync("sdk/requests")

			if not newRequests or (resp["error"] or resp["StatusCode"] ~= 200) then
				if tick() - lastReqWarning >= 10 and resp["StatusCode"] ~= 403 then
					Utilities.GBWarn("Issue getting new requests from Gamebeast dashboard. Check status.gamebeast.gg and status.roblox.com.")
					lastReqWarning = tick()
				end
				return
			end

			self:AddRequestsToQueue(newRequests)
		end

		local InternalConfigs = shared.GBMod("InternalConfigs") -- RECURSIVE!
		InternalConfigs:OnReady(function()
			checkForRequests()

			PendingJobsRan = true

			while task.wait(UPDATE_PERIOD) do
				checkForRequests()
				UPDATE_PERIOD = InternalConfigs:GetActiveConfig("GBConfigs")["GBRates"]["CheckRequests"]
			end
		end)
	end)

	-- Request execution loop
	task.spawn(function()
		while task.wait(EXECUTION_PERIOD) do		

			local synchronousResults = {}
			local isHost = shared.GBMod("HostServer"):IsHostServer()
			local queueLen = RequestQueue.len

			-- Iterate over queue of requests at process start time, i.e. ignore new requests getting added to queue one loop begins
			for i = 1, queueLen do
				local request = RequestQueue:pop()
				if RequestProcessIdMap[request.requestId] then
					continue
				end

				RequestProcessIdMap[request.requestId] = os.time()

				-- Send job started message
				if isHost then
					self:GBRequestAsync("sdk/requests/started", {request.requestId})
				end

				if (isHost or request.details.host_authority) and not request.details.hostOnly then
					local requestString = HttpService:JSONEncode(request)
					local argsString = HttpService:JSONEncode(request.args)

					-- We need to chunk into messages that will fit into MessagingService limit to propagate requests to servers
					if #requestString > MESSAGE_SIZE_LIMIT then
						local request = Utilities.recursiveCopy(request)
						request.chunked = true

						-- Make chunks as large as possible to send fewest messages, accounting for chunk metadata we're adding too
						local argsChunkSize = MESSAGE_SIZE_LIMIT - ((#requestString + 150) - #argsString)

						-- We can only chunk args, so if the request itself is larger than the limit, abort
						if argsChunkSize <= 0 then
							Utilities.GBWarn("Request too large to chunk, aborting.")
							self:SendFailure(request, {details="request too large to chunk"})
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
								Utilities.publishMessage(GB_MESSAGING_TOPIC, HttpService:JSONEncode({request}))
							end)
						end
					else
						-- No chunking needed, send full message to other servers
						task.spawn(function()
							Utilities.publishMessage(GB_MESSAGING_TOPIC, HttpService:JSONEncode({request}))
						end)
					end
				end

				-- Process request
				if not request.details.hostOnly or isHost or request.details.host_authority then
					local requestFunc = RequestFunctions.funcs[request.requestType]

					-- Either run relevant function in its own thread or (potentially) yield and run sequentially as determined by request details
					if request.details.async then
						task.spawn(function()
							requestFunc(request)
						end)
					else
						local result = requestFunc(request)
						table.insert(synchronousResults, {requestId = request.requestId, result = result})
					end
				end
			end

			-- Send results to GB, results are only ever in our queue if we're host
			-- Send synchronous results to GB
			-- NOTE: Kind of pointless since we send any async results right after, resulting in 2 requests.
			-- We should just put sync results in async queue unless we move async to a separate reporting schedule
			if #synchronousResults > 0 then
				self:SendRequestResults(synchronousResults)
			end

			-- Send any queued async results to GB
			if #AsyncResultQueue > 0 then
				local queuedResults = AsyncResultQueue
				AsyncResultQueue = {}
				self:SendRequestResults(queuedResults)
			end
		end
	end)

	game:BindToClose(function()
		FinalRequestSignal:Fire()

		repeat
			task.wait()
		until RequestProcessingCount == 0
	end)
end

--= Return Module =--
return GBRequests