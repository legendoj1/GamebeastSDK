--[[
	The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
	All rights reserved.
	
	Gamebeast.lua
	
	Description:
		Primary SDK entry point and module loader.
	
--]]

--= Root =--
local Gamebeast = { }

--= Roblox Services =--

local RunService = game:GetService("RunService")

--= Dependencies =--

local Types = require(script.Types)

--= Types =--

export type ServerSetupConfig = Types.ServerSetupConfig
export type JSON = Types.JSON

-- Services
export type ConfigsService = Types.ConfigsService
export type MarkersService = Types.MarkersService
export type EventsService = Types.EventsService

type ModuleData = {
	Name : string,
	Instance : ModuleScript,
	Loaded : boolean,
	Module : { [string] : any } | nil
}

type PublicModuleData = {
	Name : string,
	Instance : ModuleScript,
}

--= Constants =--

local DEFAULT_SETTINGS = {
	sdkWarningsEnabled = true,
	includeWarningStackTrace = false,
}

--= Object References =--

--= Variables =--

local Modules = {} :: { [string] : ModuleData }
local PublicModules = {} :: { [string] : ModuleData }
local Initialized = false
local DidRequire = false
local IsServer = RunService:IsServer()

--= Internal Functions =--

local function RequireModule(moduleData : ModuleData)
	if moduleData.Loaded then
		return moduleData.Module
	end

	local module = require(moduleData.Instance)
	moduleData.Module = module
	moduleData.Loaded = true

	return module
end

local function AddModules(modulesFolder : Instance)

	local function addModule(module : ModuleScript, isPublic : boolean?)
		if isPublic then
			PublicModules[module.Name] = {
				Name = module.Name,
				Instance = module,
			}
		else
			local moduleData = {
				Name = module.Name,
				Instance = module,
				Loaded = false,
				Module = nil,
			}

			Modules[module.Name] = moduleData
		end
	end

	local function search(folder : Folder, isPublic : boolean?)
		for _, module in ipairs(folder:GetChildren()) do
			if module:IsA("ModuleScript") then
				addModule(module, isPublic)
			end
			search(module, isPublic)
		end
	end

	search(modulesFolder:WaitForChild("Modules"))
	search(modulesFolder:WaitForChild("Public"), true)

	local function moduleAddedLate(module : ModuleScript, public : boolean?)
		if module:IsA("ModuleScript") then
			addModule(module, public)
			if DidRequire and not public then
				RequireModule(Modules[module.Name])
			end
		end
	end

	modulesFolder.Modules.DescendantAdded:Connect(moduleAddedLate)
	modulesFolder.Public.DescendantAdded:Connect(moduleAddedLate, true)
end

local function FindModule(moduleCache : {[string] : ModuleData | PublicModuleData}, name : string, timeout : number?)
	local startTime = tick()
	while (tick() - startTime < (timeout or 5)) do
		if moduleCache[name] then
			return moduleCache[name]
		end
		task.wait()
	end

	error("Gamebeast service \"".. name.. "\" not found!")
end

local function GetModule(name : string) : ModuleData?
	return FindModule(Modules, name)
end

local function GetPublicModule(name : string) : PublicModuleData?
	return FindModule(PublicModules, name)
end

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= API Functions =--

function Gamebeast:GetService(name : string) : Types.Service
	if not Initialized then
		local startTime = tick()
		local didWarn = false
		while not Initialized do
			task.wait()
			if tick() - startTime > 5 and not didWarn then
				warn("Gamebeast SDK has not initialized, did you forget to call Gamebeast:Setup()?")
				didWarn = true
			end
		end
	end
	
	assert(Initialized, "Gamebeast SDK not initialized! Call Gamebeast:Setup() first.")

	local module = GetPublicModule(name)
	if module then
		return require(module.Instance)
	else
		error("Gamebeast service \"".. name.. "\" not found!")
	end
end

function Gamebeast:Setup(setupConfig : ServerSetupConfig?)
	assert(not Initialized, "Gamebeast SDK already initialized!")
	if IsServer == true then
		assert(setupConfig, "Gamebeast SDK requires a setup config on the server.")
		assert(setupConfig.key, "Gamebeast SDK requires a key to be set in the setup config.")
	end
	if IsServer == false then
		setupConfig = setupConfig or {}
		assert(setupConfig.key == nil, "Gamebeast SDK key should not be set on the client.")
	end

	local targetModules = IsServer and script.Infra.Server or script.Infra.Client

	AddModules(targetModules)
	AddModules(script.Infra.Shared)

	-- Set settings

	local sdkSettings = setupConfig.sdkSettings or {}

	for key, value in DEFAULT_SETTINGS do
		if sdkSettings[key] == nil then
			sdkSettings[key] = value
		end
	end

	local dataCacheModule = RequireModule(GetModule("DataCache"))
	dataCacheModule:Set("Key", setupConfig.key)
	dataCacheModule:Set("Settings", sdkSettings)

	-- Require all modules
	for _, moduleData in (Modules) do
		RequireModule(moduleData)
	end
	DidRequire = true

	-- Initialize all modules
	--TODO: Priority system
	for _, moduleData in (Modules) do
		if type(moduleData.Module) ~= "table" then
			continue
		end

		local InitMethod = rawget(moduleData.Module, "Init")
		if InitMethod then
			task.spawn(InitMethod, moduleData.Module)
		end
	end

	Initialized = true
end


--= Initializers =--
do
	shared.GBMod = function(name : string)
		local moduleData = GetModule(name)
		if moduleData then
			return RequireModule(moduleData)
		else
			--Utilities.GBWarn("Gamebeast module \"".. name.. "\" not found!")
		end
	end
end

--= Return Module =--

return Gamebeast