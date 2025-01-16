-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.

-- This module contains settings related to use of the Gamebeast SDK within Roblox
local settingsMod = {}

-- GENERAL SETTINGS
-- Enables SDK warnings for API misuse, internal errors, etc.
settingsMod.sdkWarningsEnabled = true;
-- Enables stack trace inclusion with warning messages.
settingsMod.includeWarningStackTrace = false;

-- HEATMAP SETTINGS
-- Number of points used for sampling Gamebeast heatmap. More points will give more resolution but may take longer to run.
settingsMod.heatmapSamplePoints = 500000
-- Whether to include terrain in your heatmap
settingsMod.includeTerrain = true
-- Whether to include water in your heatmap. Not included if includeTerrain is false.
settingsMod.ignoreWater = false

return settingsMod