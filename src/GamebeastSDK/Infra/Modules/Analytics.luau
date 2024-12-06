-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

local playerService = game:GetService("Players")
local runService = game:GetService("RunService")
local marketplaceService = game:GetService("MarketplaceService")
local statsService = game:GetService("Stats")

local sdk = script.Parent.Parent.Parent

local utilities = shared.GBMod("Utilities")

local analyticsMod = {}

-- Get default values for each stat type
local statDefaultVals = {
	session_length = function()
		return tick()
	end,
}

-- Map of stat to list of userIds holding state for each stat we want to record
analyticsMod.sessionData = {}
for statName, _ in statDefaultVals do
	analyticsMod.sessionData[statName] = {}
end

-- Set up state for player session
playerService.PlayerAdded:Connect(function(player)
	for stat, func in statDefaultVals do
		analyticsMod.sessionData[stat][player.UserId] = func()
	end
end)

-- Remove state for player session
analyticsMod.clearPlayerSessionData = function(player)
	for stat, _ in statDefaultVals do
		analyticsMod.sessionData[stat][player.UserId] = nil
	end
end

-- Other SDK modules may rely on state stored in this module for various purposes.
-- Because various modules might rely on this state, it's not safe for them to call clearPlayerSessionData themselves.
-- Run with delay to allow time to process and then clear to avoid memory leaks. Not likely worth doing some fancy dependency/roll call system.
playerService.PlayerRemoving:Connect(function(player)
	task.wait(3)
	analyticsMod.clearPlayerSessionData(player)
end)

-- Monetization

-- Cache product information when we see it to save resources
-- New servers will send most up-to-date information, effectively don't have to ever clear cache/get most up-to-date info on a server basis
local productInfoCacheMap = {}
for _, infoType in Enum.InfoType:GetEnumItems() do
	productInfoCacheMap[infoType] = {}
end

-- Accepts player as player instance or UserId
local function updatePlayerSpend(player, itemId, itemType)
	local userId = tonumber(player) and player or player.UserId

	-- Check if we've already retrieved product info
	local itemInfo = productInfoCacheMap[itemType][itemId]
	local wasCached = itemInfo ~= nil

	if not itemInfo then
		itemInfo = utilities.getProductInfo(itemId, itemType)

		-- In case of service failure even with retries
		if not itemInfo then return end

		productInfoCacheMap[itemType][itemId] = itemInfo
	end

	-- Don't send redundant information over the wire
	local args = {
		["price"] = itemInfo.PriceInRobux,
		["item"] = {
			["id"] = itemId,
			["name"] = not wasCached and itemInfo.Name or nil,
			["desc"] = not wasCached and itemInfo.Description or nil,
			["icon"] = not wasCached and "https://assetdelivery.roblox.com/v1/asset?id=".. itemId or nil,
			["type"] = tostring(itemType),
		}
	}

	-- Collect where player made purchase
	local char = player.Character
	local pos
	
	if char and char.PrimaryPart then
		pos = char.PrimaryPart.Position
	end
	
	shared.GBmod("EngagementMarkers").createMarker("Purchase", player, pos, 1, args)
end

-- Purchase records handler for gamepasses
marketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if wasPurchased then
		updatePlayerSpend(player, gamePassId, Enum.InfoType.GamePass)
	end
end)

-- Purchase records handler for products
marketplaceService.PromptProductPurchaseFinished:Connect(function(playerId, productId, wasPurchased)
	if wasPurchased then
		updatePlayerSpend(playerId, productId, Enum.InfoType.Product)
	end	
end)

-- Purchase records handler for assets / other
marketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, wasPurchased)
	if wasPurchased then
		updatePlayerSpend(player, assetId, Enum.InfoType.Asset)
	end
end)


-- Performance analytics


return analyticsMod