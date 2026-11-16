--[[
	games.lua - registry: which game uses which folder.
	To add a game: create its folder under games/, then add ONE line below.

	games  = keyed by game.GameId  (the whole experience; covers every place inside it)  <- use this by default
	places = keyed by game.PlaceId (one specific place; wins over `games` if both match)  <- only for special cases

	Fields
	  name      shown in the title bar, also names the per-game config folder
	  folder    folder inside the repo (no leading slash), must contain init.lua
	  universal set to false to hide the universal Misc tab for that game (optional)

	Find the IDs in-game with:  print(game.GameId, game.PlaceId)
]]

return {
	games = { [10725638928] = { name = "1 Player Baseplate", folder = "games/1-player-baseplate" },
		-- [1234567890] = { name = "Example Game", folder = "games/example-game" },
	},
	places = {
		-- [9876543210] = { name = "Example Lobby", folder = "games/example-lobby", universal = false },
	},
}
