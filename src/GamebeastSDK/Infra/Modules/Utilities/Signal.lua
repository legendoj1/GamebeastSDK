-- The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
-- All rights reserved.
--[[
    Signal.lua
    
    Description:
        Bindable event class for easy event handling.

        May switch this to a solution that elimates deferred signals.
    
--]]

--= Root =--

local Signal = {}
Signal.__index = Signal

--= Constructor =--

function Signal.new()
    local self = setmetatable({}, Signal)

    self._bindable = Instance.new("BindableEvent")

    return self
end

--= Methods =--

function Signal:Connect(callback : (any) -> ())
    return self._bindable.Event:Connect(callback)
end

function Signal:Fire(...)
    self._bindable:Fire(...)
end

function Signal:Destroy()
    self._bindable:Destroy()
end

return Signal