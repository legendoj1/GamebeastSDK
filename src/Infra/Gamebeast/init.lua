
-- Client sided functions

	--[[ Configs
	gamebeast.Get = function(_, ...)
		checkGBReady()
		return getRemote("Function", "Get"):InvokeServer(...)
	end
	
	-- Changed criteria checked in "set"
	gamebeast.OnChanged = function(_, config, callback)
		local connection = getRemote("Event", "ConfigChanged").OnClientEvent:Connect(function(changedConfig, newValue, oldValue)
			local isMatchingTable

			if typeof(config) == "table" and typeof(changedConfig) == "table" then
				isMatchingTable = table.concat(config) == table.concat(changedConfig)
			end

			if isMatchingTable or config == changedConfig then
				callback(newValue, oldValue)
			end
		end)

		return connection
	end
	
	gamebeast.ModuleUpdated = function(_, callback)
		return getRemote("Event", "ModuleUpdated").OnClientEvent:Connect(callback)
	end
	
	gamebeast.GetEventData = function(_, ...)
		checkGBReady()
		return getRemote("Function", "GetEventData"):InvokeServer(...)
	end
	
	-- Engagement markers
	gamebeast.FireMarker = function(_, ...)
		getRemote("Event", "FireMarker"):FireServer(...)
	end
]]


--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	init.lua
	
	Description:
		No description provided.
	
--]]

--= Root =--
local Gamebeast = { }

--= Roblox Services =--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--= Dependencies =--

--= Types =-- 

type ModuleData = {
	Name : string,
	Instance : ModuleScript,
	Loaded : boolean,
	Module : { [string] : any } | nil
}

--= Object References =--

--= Variables =--

local Modules = {} :: { ModuleData }
local Initialized = false

--= Internal Functions =--

local function AddModules(modules : {ModuleScript | Instance}, _isPublic : boolean?)
	local function addModule(module : ModuleScript)
		local moduleData = {
			Name = module.Name,
			Instance = module,
			Loaded = false,
			Module = nil,
			Public = _isPublic
		}

		table.insert(Modules, moduleData)
	end

	for _, module in ipairs(modules) do
		if module:IsA("Folder") and module.Name == "Public" then
			_isPublic = true
		end

		if module:IsA("ModuleScript") then
			addModule(module)
		end
		AddModules(module:GetChildren(), _isPublic )
	end
end

local function GetModule(name : string) : ModuleData?
	while (#Modules == 0) do task.wait() end
	--Note: Array instead of dictionary for future proofing 
	for _, module in pairs(Modules) do
		if module.Name == name then
			return module
		end
	end

	return nil
end

local function RequireModule(moduleData : ModuleData)
	if moduleData.Loaded then
		return moduleData.Module
	end

	local module = require(moduleData.Instance)
	moduleData.Module = module
	moduleData.Loaded = true
	moduleData.Instance:SetAttribute("Loaded", true) -- TODO: Validate if this is necessary

	return module
end


--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= API Functions =-- 

function Gamebeast:GetModule(name : string)
	local moduleData = GetModule(name)
	if moduleData and not moduleData.Public then
		return RequireModule(moduleData)
	else
		--Utilities.GBWarn("Gamebeast module \"".. name.. "\" not found!")
	end
end

function Gamebeast:Start(modules : {ModuleScript | Instance})
	if Initialized then
		return
	end

	AddModules(modules)
	AddModules(script:GetChildren())

	-- Require all modules
	for _, moduleData in ipairs(Modules) do
		RequireModule(moduleData)
	end

	-- Initialize all modules
	--TODO: Priority system
	for _, moduleData in ipairs(Modules) do
		if type(moduleData.Module) ~= "table" then
			continue
		end

		local InitMethod = rawget(moduleData.Module, "Init")
		if InitMethod then
			task.spawn(InitMethod, moduleData.Module)
		end
	end
end


--= Initializers =--
do 
	shared.GBMod = function(...)
		return Gamebeast:GetModule(...)
	end

	--[[ Warn if junk in EventCode folder
	for _, module in SDK.EventCode:GetChildren() do
		if not module:IsA("ModuleScript") then
			Utilities.GBWarn("EventCode folder should only contain ModuleScripts with names corresponding to your events.")
			break
		end
	end

	-- Warn if SDK out of date
	if script:GetAttribute("OutOfDate") then
		Utilities.GBWarn("Gamebeast SDK out of date. Please update via the Gamebeast plugin.")
	end

	-- Add client script to new players

	-- Function to enable easy communication between GB modules]]
end

--= Return Module =--
return Gamebeast