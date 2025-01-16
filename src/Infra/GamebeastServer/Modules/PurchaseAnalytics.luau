--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	PurchaseAnalytics.luau
	
	Description:
		No description provided.
	
--]]

--= Root =--
local PurchaseAnalytics = { }

--= Roblox Services =--

local MarketplaceService = game:GetService("MarketplaceService")

--= Dependencies =--

local Utilities = shared.GBMod("Utilities")
local Markers = shared.GBMod("Markers") ---@module Markers

--= Types =--

--= Object References =--

--= Constants =--

local ENUM_TO_TYPE = {
	[Enum.InfoType.GamePass] = "gamepass",
	[Enum.InfoType.Product] = "devproduct",
	[Enum.InfoType.Asset] = "asset",
	[Enum.InfoType.Subscription] = "subscription",
}

--= Variables =--

-- Cache product information when we see it to save resources
-- New servers will send most up-to-date information, effectively don't have to ever clear cache/get most up-to-date info on a server basis
local ProductInfoCacheMap = {}

--= Public Variables =--

--= Internal Functions =--

-- Accepts player as player instance or UserId
local function UpdatePlayerSpend(player, itemId, itemType)
	local userId = tonumber(player) and player or player.UserId

	-- Check if we've already retrieved product info
	if not ProductInfoCacheMap[itemType] then
		ProductInfoCacheMap[itemType] = {}
	end

	local itemInfo = ProductInfoCacheMap[itemType][itemId]
	local wasCached = itemInfo ~= nil

	if not itemInfo then
		itemInfo = Utilities.getProductInfo(itemId, itemType)

		-- In case of service failure even with retries
		if not itemInfo then return end

		ProductInfoCacheMap[itemType][itemId] = itemInfo
	end

	-- Don't send redundant information over the wire
	local args = {
		["item_type"] = ENUM_TO_TYPE[itemType] or "unknown",
		["id"] = itemId,
		["price"] = itemInfo.PriceInRobux,
		["name"] = not wasCached and itemInfo.Name or nil,
		["description"] = not wasCached and itemInfo.Description or nil,
		["image_id"] = not wasCached and "https://assetdelivery.roblox.com/v1/asset?id=".. itemId or nil,
	}

	-- Collect where player made purchase
	local char = player.Character
	local pos
	
	if char and char.PrimaryPart then
		pos = char.PrimaryPart.Position
	end
	
	Markers:SDKMarker("Purchase", args, {player = player, position = pos})
end

--= API Functions =--

--= Initializers =--
function PurchaseAnalytics:Init()
	-- Purchase records handler for gamepasses
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			UpdatePlayerSpend(player, gamePassId, Enum.InfoType.GamePass)
		end
	end)

	-- Purchase records handler for products
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerId, productId, wasPurchased)
		if wasPurchased then
			UpdatePlayerSpend(playerId, productId, Enum.InfoType.Product)
		end	
	end)

	-- Purchase records handler for assets / other
	MarketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, wasPurchased)
		if wasPurchased then
			UpdatePlayerSpend(player, assetId, Enum.InfoType.Asset)
		end
	end)

	MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(player, subscriptionId, didTryPurchasing)
		if didTryPurchasing then
			local success, subscriptionStatus = pcall(function()
				return MarketplaceService:GetUserSubscriptionStatusAsync(player, subscriptionId)
			end)

			if success and subscriptionStatus.IsSubscribed then
				UpdatePlayerSpend(player, subscriptionId, Enum.InfoType.Subscription)
			end
		end
		
	end)

end

--= Return Module =--
return PurchaseAnalytics