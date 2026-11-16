--[[
	games/example-game/init.lua
	Builds this game's tab(s). Runs ONLY when the player is in this game.
	Receives (Hub, entry) from loader.lua.

	Features live in games/example-game/features/<Name>.lua and are downloaded
	the first time their toggle is switched on (Hub:SetFeature handles that).
]]

return function(Hub, entry)
	local tab = Hub:AddTab(entry.name)

	tab:AddSection("Features")
	tab:AddToggle({ Name = "Example feature", Callback = function(on)
		Hub:SetFeature("Example", on)   -- loads features/Example.lua on first enable
	end })

	-- one line per feature: Hub:SetFeature("FileName", on)
end
