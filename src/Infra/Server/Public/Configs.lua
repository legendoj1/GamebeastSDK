--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    Configs.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local Configs = { }

--= Roblox Services =--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local InternalConfigs = shared.GBMod("InternalConfigs") ---@module InternalConfigs

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Configs:Get(path : string | { string })
    return InternalConfigs:Get(path)
end

function Configs:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection
    return InternalConfigs:OnChanged(targetConfig, callback)
end

function Configs:OnReady(callback : (configs : any) -> ()) : RBXScriptSignal
    return InternalConfigs:OnReady(callback)
end

function Configs:IsReady() : boolean
    return InternalConfigs:IsReady()
end

--= Return Module =--
return Configs