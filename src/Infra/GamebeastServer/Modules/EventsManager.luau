--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	EventsManager.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local EventsManager = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local Configs = shared.GBMod("Configs") ---@module Configs
local Utilities = shared.GBMod("Utilities")

--= Types =--

--= Object References =--

local SDK = script.Parent.Parent.Parent.Parent

--= Constants =--

-- How often we check if it's time to execute an event
local EVENT_CHECK_PERIOD = 0.5

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

--= Initializers =--
function EventsManager:Init()
	local eventMods = {}

	Configs:OnConfigsReady(function()
		-- Warning if event module but no corresponding data
	for _, module in SDK.EventCode:GetChildren() do
		if module:IsA("ModuleScript") then
			eventMods[module.Name] = require(module)
			
			if module.Name ~= "ExampleEvent" then
				if not Configs:GetActiveConfig("GBConfigs")["EventData"][module.Name] then
					Utilities.GBWarn("No event data for Gamebeast EventCode module \"".. module.Name.."\"! Is your module named correctly?")
				end
			end
		end
	end

	-- Warning if event data but no corresponding module
	Configs:OnConfigsUpdated(nil, function()
		for eventName, _ in Configs:GetActiveConfig("GBConfigs")["EventData"] do
			if not SDK.EventCode:FindFirstChild(eventName) then
				Utilities.GBWarn("No Gamebeast EventCode module found for event \"".. eventName.."\".")
			end
		end
	end)

	-- Loop to check if an event should be executed
	task.spawn(function()
		while task.wait(EVENT_CHECK_PERIOD) do
			for eventName, eventData in Configs:GetActiveConfig("GBConfigs")["EventData"] do
				local curTime = os.time()
				
				if eventData.endTime and curTime >= eventData.startTime and curTime < eventData.endTime and not eventMods[eventName].executed then
					print("Starting/continuing the '".. eventName.. "' event!")
					eventMods[eventName].executed = true
					
					task.spawn(function()
						eventMods[eventName].eventStart(eventData.info)
					end)
				elseif curTime == eventData.endTime and eventMods[eventName].eventEnd and not eventMods[eventName].endExecuted then
					print("Ending the '".. eventName.. "' event!")
					eventMods[eventName].endExecuted = true
					
					task.spawn(function()
						eventMods[eventName].eventEnd(eventData.info)
					end)
				elseif curTime == eventData.startTime and not eventMods[eventName].executed then
					print("Starting the '".. eventName.. "' event!")
					eventMods[eventName].executed = true

					task.spawn(function()
						eventMods[eventName].eventStart(eventData.info)
					end)
				end
			end
		end
	end)
	end)
	
end

--= Return Module =--
return EventsManager