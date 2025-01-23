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

--= Dependencies =--

local ClientConfigs = shared.GBMod("ClientConfigs")

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Configs:Get(path : string | { string })
    return ClientConfigs:Get(path)
end

function Configs:OnChanged(targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) : RBXScriptConnection
    return ClientConfigs:OnChanged(targetConfig, callback)
end

function Configs:IsReady() : boolean
    return ClientConfigs:IsReady()
end

--= Return Module =--
return Configs