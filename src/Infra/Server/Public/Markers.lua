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

local EngagementMarkers = shared.GBMod("EngagementMarkers") ---@module EngagementMarkers

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Markers:SendMarker(markerType : string, value : number | {[string] : any}, position : Vector3?)
    EngagementMarkers:FireMarker(markerType, value, {position = position})
end

function Markers:SendPlayerMarker(player : Player, markerType : string, value : number | {[string] : any}, position : Vector3?)
    EngagementMarkers:FireMarker(markerType, value, {player = player, position = position})
end

--= Return Module =--
return Markers