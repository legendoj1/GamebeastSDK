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

--= Dependencies =--

local ClientConfigs = shared.GBMod("ClientConfigs")

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Config:Get(path : string | { string })
    return ClientConfigs:Get(path)
end

function Config:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection
    return ClientConfigs:OnChanged(targetConfig, callback)
end

function Config:IsReady() : boolean
    return ClientConfigs:IsReady()
end

--= Return Module =--
return Config