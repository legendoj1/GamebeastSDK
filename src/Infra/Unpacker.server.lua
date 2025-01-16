--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

--= Dependencies =--

--= Types =--

--= Object References =--

local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

--= Initializers =--

do
    local ClientScript = script.Parent:FindFirstChild("GamebeastClient")
    local SharedScript = script.Parent:FindFirstChild("Gamebeast")

    if ClientScript then
        ClientScript.Parent = StarterPlayerScripts
    end

    if SharedScript then
        SharedScript.Parent = ReplicatedStorage
    end

end
