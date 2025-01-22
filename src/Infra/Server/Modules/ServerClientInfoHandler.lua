--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    ServerClientInfoHandler.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local ServerClientInfoHandler = { }

--= Roblox Services =--

local Players = game:GetService("Players")

--= Dependencies =--

local GetRemote = shared.GBMod("GetRemote")

--= Types =--

--= Object References =--

local ClientInfoRemote = GetRemote("Event", "ClientInfoChanged")

--= Constants =--

--= Variables =--

local ClientInfoCache = {}

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function ServerClientInfoHandler:GetClientInfo(player : Player, key : string) : any?
    if ClientInfoCache[player] then
        return ClientInfoCache[player][key]
    end

    return nil
end

--= Initializers =--
function ServerClientInfoHandler:Init()
    Players.PlayerRemoving:Connect(function(player : Player)
        ClientInfoCache[player] = nil
    end)

    ClientInfoRemote.OnServerEvent:Connect(function(player : Player, key : string | nil, value : any)
        if not ClientInfoCache[player] then
            ClientInfoCache[player] = {}
        end

        if key then
            ClientInfoCache[player][key] = value
        else
            ClientInfoCache[player] = value
        end
    end)
end

--= Return Module =--
return ServerClientInfoHandler