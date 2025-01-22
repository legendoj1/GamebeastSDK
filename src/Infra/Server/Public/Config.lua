--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    Config.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local Config = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local InternalConfigs = shared.GBMod("Configs")

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Config:Get(path : string | { string })
    return InternalConfigs:Get(path)
end

function Config:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection
    return InternalConfigs:OnChanged(targetConfig, callback)
end

function Config:IsReady() : boolean
    return InternalConfigs:IsReady()
end

--= Return Module =--
return Config