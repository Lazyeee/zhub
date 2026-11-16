--[[
	games/example-game/features/Example.lua
	A feature is a table with Enable and Disable. Nothing runs until the toggle is on.
	Disable must undo everything Enable did (it is also called when the UI is unloaded).
]]

local Players = game:GetService("Players")

local conn
local Feature = {}

function Feature.Enable(Hub)
	if conn then return end
	conn = Players.PlayerAdded:Connect(function(p)
		Hub:Notify(p.Name .. " joined", 2)
	end)
end

function Feature.Disable(Hub)
	if conn then conn:Disconnect(); conn = nil end
end

return Feature
