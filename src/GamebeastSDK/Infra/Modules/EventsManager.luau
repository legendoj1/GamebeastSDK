-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")

local eventsMod = {}

-- How often we check if it's time to execute an event
local EVENT_CHECK_PERIOD = 0.5

-- Wait until configs are loaded
repeat task.wait() until shared.GBMod("Configs").configsReady

local eventMods = {}

-- Warning if event module but no corresponding data
for _, module in sdk.EventCode:GetChildren() do
	if module:IsA("ModuleScript") then
		eventMods[module.Name] = require(module)
		
		if module.Name ~= "ExampleEvent" then
			if not shared.GBMod("Configs")["GBConfigs"]["EventData"][module.Name] then
				utilities.GBWarn("No event data for Gamebeast EventCode module \"".. module.Name.."\"! Is your module named correctly?")
			end
		end
	end
end

-- Warning if event data but no corresponding module
shared.GBMod("Configs").moduleUpdated(function()
	for eventName, _ in shared.GBMod("Configs")["GBConfigs"]["EventData"] do
		if not sdk.EventCode:FindFirstChild(eventName) then
			utilities.GBWarn("No Gamebeast EventCode module found for event \"".. eventName.."\".")
		end
	end
end)

-- Loop to check if an event should be executed
task.spawn(function()
	while task.wait(EVENT_CHECK_PERIOD) do
		for eventName, eventData in shared.GBMod("Configs")["GBConfigs"]["EventData"] do
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

return eventsMod