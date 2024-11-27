-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.
local playerService = game:GetService("Players")

local sdk = script.Parent.Parent.Parent
local utilities = require(sdk.Infra.Modules.Utilities)

local modules = {}

-- Add client script to new players
sdk.Infra.Main.GamebeastClient.Parent = game:GetService("StarterPlayer").StarterPlayerScripts

-- Add modules to system
local function addModule(module)
	-- Warn if module with same name already loaded, will overwrite reference if we've gotten to this point
	if modules[module.Name] then
		utilities.GBWarn("Module with name '".. module.Name.."' already exists in Gamebeast SDK. Overwriting.")
	end
	
	-- Use module name as index, loaded module as value
	modules[module.Name] = require(module)
	module:SetAttribute("Loaded", true)
	return modules[module.Name]
end

-- Function to enable easy communication between GB modules
shared.GBMod = function(name)
	-- Check if module already loaded and stored and return reference otherwise return newly loaded module
	if not modules[name] then
		local modInstance = sdk.Infra.Modules:FindFirstChild(name)
		
		-- Warn if module with given name doesn't exist
		if not modInstance then
			utilities.GBWarn("Gamebeast module \"".. name.. "\" not found!")
			return nil
		else
			return addModule(modInstance)
		end
	end

	return modules[name]
end

-- Load modules asynchronously, task.spawn presented strange behaviors in some instances so opt for coroutines
for _, module in sdk.Infra.Modules:GetChildren() do
	-- Check if already loaded by another referencing module already and return. Reference will already be stored so we're fine
	if module:GetAttribute("Loaded") then continue end
	
	local loadMod = coroutine.create(function()
		addModule(module)
	end)

	coroutine.resume(loadMod)
end

-- Warn if junk in EventCode folder
for _, module in sdk.EventCode:GetChildren() do
	if not module:IsA("ModuleScript") then
		utilities.GBWarn("EventCode folder should only contain ModuleScripts with names corresponding to your events.")
		break
	end
end

-- Warn if SDK out of date
if script:GetAttribute("OutOfDate") then
	utilities.GBWarn("Gamebeast SDK out of date. Please update via the Gamebeast plugin.")
end