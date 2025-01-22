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

function Markers:SendMarker(markerType : string, value : number | {[string] : any}, position : Vector3?)
    FireMarkerEvent:FireServer(markerType, value, {position = position})
end

function Markers:SendPlayerMarker(...)
    error("SendPlayerMarker can only be used on the Server")
end

--= Return Module =--
return Markers