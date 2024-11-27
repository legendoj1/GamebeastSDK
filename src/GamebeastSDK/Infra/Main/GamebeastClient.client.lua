local replicatedStorage = game:GetService("ReplicatedStorage")
local inputService = game:GetService("UserInputService")
local statsService = game:GetService("Stats")

local gamebeastModInstance = replicatedStorage:WaitForChild("Gamebeast")

local gamebeastModule = require(gamebeastModInstance)

-- Get device type via horrible existing Roblox API
local function getPlayerDeviceType()
		if inputService.TouchEnabled and not inputService.KeyboardEnabled then
		return "mobile"
	elseif inputService.GamepadEnabled and not inputService.KeyboardEnabled then
		return "console"
	elseif inputService.KeyboardEnabled then
		return "pc"
	else
		return "unknown"
	end
end

-- Function to get client info for session data and other telemetry
-- Consider renaming for clarity

gamebeastModule:GetRemote("Function", "GetClientInfo").GetClientInfo.OnClientInvoke = function()
	return {
		deviceType = getPlayerDeviceType()
	}
end

-- Performance analytics
