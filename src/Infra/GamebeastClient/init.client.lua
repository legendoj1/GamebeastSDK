--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
	
	init.lua
	
	Description:
		No description provided.
	
--]]

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

local GBModule = require(ReplicatedStorage:WaitForChild("Gamebeast"))

do 
	GBModule:Start(script:GetChildren())
end
