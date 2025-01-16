--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    Markers.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local Markers = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local GetRemote = shared.GBMod("GetRemote")

--= Types =--

--= Object References =--

local FireMarkerEvent = GetRemote("Event", "FireMarker")

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Markers:FireMarker(markerType : string, value : number | {[string] : any}, metaData : {[string] : any})
    FireMarkerEvent:FireServer(markerType, value, metaData)
end

--= Initializers =--
function Markers:Init()
    
end

--= Return Module =--
return Markers