--[[
	games/1-player-baseplate/init.lua
	Builds this game's tab. Runs ONLY in 1 Player Baseplate.
	Hub:SetFeature("name", on) loads features/name.lua the first time its toggle is switched on.
	The text in quotes must match the file name EXACTLY (capital letters count).
]]

return function(Hub, entry)
	local tab = Hub:AddTab(entry.name)

	tab:AddSection("Features")
	tab:AddToggle({ Name = "Name feature (test)", Callback = function(on)
		Hub:SetFeature("name", on)
	end })
end
