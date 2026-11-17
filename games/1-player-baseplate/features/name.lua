--[[
	games/1-player-baseplate/features/name.lua
	A feature file MUST return a table with Enable and Disable (a plain "test" line is not valid).
]]

local Feature = {}

function Feature.Enable(Hub)
	Hub:Notify("name feature: ON", 2)
end

function Feature.Disable(Hub)
	Hub:Notify("name feature: OFF", 2)
end

return Feature
