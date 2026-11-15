# Z Hub

A vibe coded, open source utility hub for Roblox scripts (Luau), built for mobile and PC.

## Run it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/Hub.lua"))()
```

## Features

- Floating button to open and close the menu (works on touch)
- Movable window, resizable corner, minimize and close buttons
- Config system: autosave, named configs, export and import
- Window size and position are saved with your config
- Misc tab with FPS boosters, renderer settings, an FPS counter and utilities

## Files

| File | What it is |
|------|------------|
| `Hub.lua` | Main script. Load this one |
| `ZUI.lua` | The UI library (tabs, toggles, sliders, color picker and more) |
| `GUIDE.md` | Guide for AI assistants on how to add features to the hub |

## Add your own features

Add a tab or add to Misc from any script after the hub has loaded:

```lua
local Hub = getgenv().ZHub
local tab = Hub:AddTab("My Script")
tab:AddToggle({ Name = "My feature", Callback = function(on) print(on) end })
```

See `GUIDE.md` for every component and the rules.

## Notes

- Needs an executor that supports `loadstring` and `HttpGet`
- Config saving needs file access (`writefile` / `readfile`)
- Use at your own risk
