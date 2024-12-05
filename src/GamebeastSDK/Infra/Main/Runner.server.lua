--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.

	Runner.server.lua
	
	Description:
		No description provided.
	
--]]

--= Roblox Services =--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players") 
local StarterPlayer = game:GetService("StarterPlayer")

--= Types =--

type ModuleData = {
	Name : string,
	Instance : ModuleScript,
	Loaded : boolean,
	Module : { [string] : any } | nil
}

--= Object References =--

local SDK = script.Parent.Parent.Parent

--= Variables =--

local Modules = {} :: { ModuleData }
local Initialized = false

--= Internal Functions =--

local function GetModule(name : string) : ModuleData?
	--Note: Array instead of dictionary for future proofing 
	for _, module in pairs(Modules) do
		if module.Name == name then
			return module
		end
	end

	return nil
end

local function InitializeModule(moduleData : ModuleData)
	if moduleData.Loaded then
		return moduleData.Module
	end

	local module = require(moduleData.Instance)
	moduleData.Module = module
	moduleData.Loaded = true
	moduleData.Instance:SetAttribute("Loaded", true) -- TODO: Validate if this is necessary

	return module
end

local function AddModule(module : ModuleScript)
	local newData = {
		Name = module.Name,
		Instance = module,
		Loaded = false,
		Module = nil
	}

	table.insert(Modules, newData)

	if Initialized then
		InitializeModule(newData)
	end
end

--= Initializers =--
do 
	SDK.Infra.Main.GamebeastClient.Parent = StarterPlayer:WaitForChild("StarterPlayerScripts")

	-- Load modules asynchronously, task.spawn presented strange behaviors in some instances so opt for coroutines
	for _, module in SDK.Infra.Modules:GetDescendants() do
		-- Check if already loaded by another referencing module already and return. Reference will already be stored so we're fine
		--if module:GetAttribute("Loaded") then continue end
		
		if not module:IsA("ModuleScript") then
			return 
		end

		local loadMod = coroutine.create(function()
			AddModule(module)
		end)

		coroutine.resume(loadMod)
	end

	shared.GBMod = function(name)
		local moduleData = GetModule(name)
		if moduleData then
			return InitializeModule(moduleData)
		else
			--Utilities.GBWarn("Gamebeast module \"".. name.. "\" not found!")
		end
	end

	for _, module in pairs(Modules) do
		task.spawn(InitializeModule, module)
	end
	Initialized = true

	local Utilities = shared.GBMod("Utilities")

	-- Warn if junk in EventCode folder
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

	-- Function to enable easy communication between GB modules
	
end

