type SDKSettings = {
	-- Enables SDK warnings for API misuse, internal errors, etc.
	sdkWarningsEnabled : boolean,
	-- Enables stack trace inclusion with warning messages.
	includeWarningStackTrace : boolean,
}
export type ServerSetupConfig = {
	key : string | Secret,
	sdkSettings : SDKSettings?
}

export type ClientSetupConfig = {
	sdkSettings : SDKSettings?
}

--NOTE: The actual JSON type doesnt get represented cleanly in Roblox's intellesense. This is a simplified version for now.
export type JSON = any
--[[{
    [string] : (number | string | boolean | JSON)
} | { number | string | boolean | JSON }
 ]]


--// Public API Types

export type ConfigService = {
	Get : (self : ConfigService, path : string | { string }) -> any,
	OnChanged : (self : ConfigService, targetConfig : string | {string}, callback : (newValue : any, oldValue : any) -> ()) -> RBXScriptConnection,
	IsReady : (self : ConfigService) -> boolean,
}

export type MarkersService = {
	SendMarker : (self : MarkersService, marker : string, data : JSON) -> (),
	--Server only
	SendPlayerMarker : (server : MarkersService, player : Player, marker : string, data : JSON) -> (),
}

export type EventsService = {
	-- Server only
	GetEventData : (self : EventsService, event : string) -> JSON,
	OnStart : (self : EventsService, event : string, callback : (data : JSON) -> ()) -> RBXScriptConnection,
	OnEnd : (self : EventsService, event : string, callback : (data : JSON) -> ()) -> RBXScriptConnection,
}


export type Service = ConfigService | MarkersService | EventsService

return true