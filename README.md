# Z Hub

A vibe coded, open source utility hub for Roblox scripts (Luau), built for mobile and PC.
One loader detects the game you are in and only loads that game's scripts.

## Run it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/loader.lua"))()
```

## Features

- Floating button to open and close the menu (works on touch)
- Movable window, resizable corner, minimize and close buttons
- Config system: autosave, named configs, export and import (saved per game)
- Misc tab in every game: FPS boosters, renderer settings, FPS counter, utilities
- Game-specific tabs that only load in their own game

## Repo layout

```
loader.lua                  entry point (the only file you run)
Hub.lua                     optional shim that calls loader.lua
ZUI.lua                     UI library
games.lua                   game ID -> folder registry
universal/
  Misc.lua                  universal features (every game)
games/
  <game-name>/
    init.lua                builds that game's tab
    features/
      <Feature>.lua         one file per feature, loaded on first use
GUIDE.md                    guide for AI assistants
```

## Add a game

1. Create `games/<game-name>/init.lua` (copy `games/example-game`).
2. Add one line to `games.lua`: `[GameId] = { name = "Game", folder = "games/<game-name>" }`.
3. Put each feature in `games/<game-name>/features/Name.lua` and switch it on with `Hub:SetFeature("Name", on)`.

Find the IDs in-game with `print(game.GameId, game.PlaceId)`.

See `GUIDE.md` for every component and the rules.

## Notes

- Needs an executor that supports `loadstring` and `HttpGet`
- Config saving needs file access (`writefile` / `readfile`)
- Use at your own risk
