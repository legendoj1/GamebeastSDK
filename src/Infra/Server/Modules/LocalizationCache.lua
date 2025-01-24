--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    LocalizationCache.lua
    
    Description:
        No description provided.
    
--]]

--= Root =--
local LocalizationCache = { }

--= Roblox Services =--
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local Utilities = shared.GBMod("Utilities") ---@module Utilities

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

local Cache = {}

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function LocalizationCache:GetRegionId(player : Player | number)
    player = Utilities.resolvePlayerObject(player)

    if not Cache[player] then
        Cache[player] = {}
    end

    if Cache[player].regionId then
        return Cache[player].regionId
    end

    local regionId = Utilities.promiseReturn(1, function()
        return LocalizationService:GetCountryRegionForPlayerAsync(player)
    end)

    Cache[player].regionId = regionId

    return regionId or "unknown"
end

function LocalizationCache:GetLocaleId(player : Player | number)
    player = Utilities.resolvePlayerObject(player)

    if not Cache[player] then
        Cache[player] = {}
    end

    if Cache[player].localeId then
        return Cache[player].localeId
    end

    local localeId = Utilities.promiseReturn(1, function()
        return LocalizationService:GetTranslatorForPlayer(player).LocaleId
    end)

    Cache[player].localeId = localeId

    return localeId or "unknown"
end

--= Initializers =--
function LocalizationCache:Init()
    Players.PlayerRemoving:Connect(function(player : Player)
        Cache[player] = nil
    end)
end

--= Return Module =--
return LocalizationCache