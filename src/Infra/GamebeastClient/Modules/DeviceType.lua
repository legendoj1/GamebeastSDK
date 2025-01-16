--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    DeviceType.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local DeviceType = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--= Dependencies =--

local GetRemote = shared.GBMod("GetRemote")

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function DeviceType:Get() : string
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "mobile"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "console"
	elseif UserInputService.KeyboardEnabled then
		return "pc"
	else
		return "unknown"
	end
end

--= Initializers =--
function DeviceType:Init()
    GetRemote("Function", "GetClientInfo").OnClientInvoke = function()
        return {
            deviceType = self:Get()
        }
    end
end

--= Return Module =--
return DeviceType