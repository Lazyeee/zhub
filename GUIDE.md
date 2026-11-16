# Z Hub: guide for AI assistants

I build Roblox executor scripts (Luau) on top of my own UI library, **ZUI**, and my hub, **Z Hub**.
Read this whole guide before writing code. Do NOT create your own UI, windows, ScreenGuis or buttons.
Use ZUI for every menu element.

Repo: `https://raw.githubusercontent.com/Lazyeee/zhub/main/`
Run command: `loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/loader.lua"))()`

---

## 1. Repo structure

```
loader.lua                      only entry point; never edit unless asked
Hub.lua                         1-line shim that calls loader.lua
ZUI.lua                         UI library; never rewrite
games.lua                       registry: game ID -> folder
universal/
  Misc.lua                      universal features (shown in EVERY game)
games/
  <game-name>/
    init.lua                    builds this game's tab(s); runs only in that game
    features/
      <Feature>.lua             one file per feature; downloaded on first enable
```

How it runs: `loader.lua` loads ZUI, reads `games.lua`, matches `game.PlaceId` first and then `game.GameId`,
runs ONLY that game's `init.lua`, then runs `universal/Misc.lua`, then adds the Settings tab.
Features never leak between games because each game folder is only fetched in that game.

### Window layout
- Left sidebar of tabs. Game tab(s) first, **Misc** near the bottom, **Settings** last (added by the loader; never call `AddSettingsTab`).
- Misc holds the universal features as sections with separator lines. Order = priority, top = most important.
- Floating open/close button for mobile; the X only hides the window.

### Globals and Hub fields
- `getgenv().ZHub` is the window (called `Hub` inside files), `getgenv().ZUI` is the library
- `Hub.Tabs["Name"]` returns an existing tab
- `Hub.Flags["Component name"]` is the current value of any component
- `Hub.Entry` is this game's registry entry, `Hub.GameFolder` is e.g. `"games/example-game/"`

### Already in universal/Misc.lua (do not duplicate)
FPS boost (smooth plastic and no part shadows, hide decals/textures, disable particles/trails/beams,
disable post-processing, disable global shadows, calm water, enable/disable all), Renderer (graphics level,
FPS cap), Display (FPS counter), Utilities (Anti-AFK, Rejoin), and one example of every component.

---

## 2. Component API

Get a tab with `local tab = Hub:AddTab("Name")` or `local tab = Hub.Tabs["Misc"]`.

```lua
tab:AddSection("Title")      -- header with a separator line; start every group of features with one
tab:AddDivider()             -- plain separator line
tab:AddLabel("text")         -- obj:SetText("new text")
tab:AddButton{ Name="", Callback=function() end }

tab:AddToggle{ Name="", Default=false, Callback=function(on) end }
tab:AddSlider{ Name="", Min=0, Max=100, Default=50, Increment=1, Suffix="", Callback=function(n) end }
tab:AddNumberBox{ Name="", Min=0, Max=500, Default=16, Integer=false, Callback=function(n) end }
tab:AddTextBox{ Name="", Default="", Placeholder="", Callback=function(str) end }
tab:AddDropdown{ Name="", Values={"A","B"}, Default="A", Callback=function(choice) end }   -- obj:Refresh(newValues)
tab:AddColorPicker{ Name="", Default=Color3.fromRGB(255,255,255), Callback=function(color) end }
tab:AddKeybind{ Name="", Default="F", Callback=function() end }
```

Options for every value component: `Flag = "id"` (save key, defaults to Name) and `Save = false` (keep out of configs).
Every value component returns `obj` with `obj.Value` and `obj:Set(value, silent)` (`silent` = no callback).

Keybind: the user TYPES the key ("F", "5", "LeftShift") so it works with on-screen keyboards. `Callback()` runs on press;
with `Hold = true` it runs `Callback(true)` on down and `Callback(false)` on up. `OnChanged(keyName)` runs when the key changes.
Ignored while any TextBox is focused. Keybind callbacks never run on load.

### Callback timing (important)
- Callbacks run on every change (and while dragging sliders/color pickers), so keep them cheap.
- A callback also runs ONCE on load if a saved value exists (or a toggle has `Default = true`), including with `false`.
  So the "off" path must be safe when the feature was never on. `Hub:SetFeature(name, false)` already handles this.

---

## 3. Game features: how to write them

A feature file returns a table with `Enable` and `Disable`. It is downloaded the first time its toggle is switched on.

```lua
-- games/<game-name>/features/MyFeature.lua
local Players = game:GetService("Players")
local conn
local Feature = {}

function Feature.Enable(Hub)
	if conn then return end
	conn = Players.PlayerAdded:Connect(function(p) Hub:Notify(p.Name .. " joined", 2) end)
end

function Feature.Disable(Hub)
	if conn then conn:Disconnect(); conn = nil end   -- undo EVERYTHING Enable did
end

return Feature
```

And in the game's `init.lua`, one toggle per feature:

```lua
return function(Hub, entry)
	local tab = Hub:AddTab(entry.name)
	tab:AddSection("Group name")
	tab:AddToggle({ Name = "My feature", Callback = function(on) Hub:SetFeature("MyFeature", on) end })
end
```

Hub helpers added by the loader:
- `Hub:SetFeature(name, on)`: loads `GameFolder .. "features/" .. name .. ".lua"` on first enable, then calls Enable/Disable
- `Hub:LoadFeature(name)`: returns the cached feature table (use for sliders/dropdowns that talk to a feature)
- `Hub:Run(path)`: downloads and runs any repo file (if it returns a function, it is called with `(Hub, entry)`)
- `Hub:Notify(text, seconds)`, `Hub:OnUnload(fn)`, `Hub:SetVisible(bool)`, `Hub:Destroy()`

Features that need settings (a slider, a color) should expose them on the feature table, for example
`Feature.SetSize = function(n) ... end`, and the slider callback calls `Hub:LoadFeature("MyFeature").SetSize(n)`
only when the feature is loaded.

---

## 4. Adding a new game

1. Create `games/<game-name>/init.lua` (copy `games/example-game/init.lua`) and `games/<game-name>/features/`.
2. Add one line to `games.lua` inside `games = { ... }`:
   `[GameId] = { name = "Display Name", folder = "games/<game-name>" },`
   Use `game.GameId` by default. Use the `places` table (keyed by `game.PlaceId`) only for a specific place that needs its own folder.
   Set `universal = false` on the entry to hide the universal Misc tab for that game.
3. Never add game code to `universal/Misc.lua` or `loader.lua`.

For a feature that works in every game, add a new group to `universal/Misc.lua`, starting with
`misc:AddSection("Group name")`, placed in priority order.

---

## 5. Rules for every feature you write

1. **Unique names.** Every component `Name` (or `Flag`) must be unique across the whole hub, across tabs and games.
2. **Cleanup.** `Disable` must fully revert what `Enable` changed. Features are also disabled automatically on unload.
3. **Performance first.** No always-running loops. Connect events only while a feature is ON and disconnect when OFF.
   Prefer events over polling. If a loop is unavoidable, use `task.wait(0.25)` or slower and stop it on Disable.
   Sweeps over `GetDescendants()` must yield (`task.wait()`) every few hundred items.
4. **Executor safety.** Check executor functions exist (`if setfpscap then`) and `pcall` risky calls.
5. **Mobile first.** No features that need a physical keyboard or mouse. Prefer toggles, sliders and buttons.
6. **No new GUIs.** If you need an on-screen element, parent it to `Hub.Root`, never create a ScreenGui.
7. **Services.** `game:GetService(...)` at the top of the file.
8. **Do not modify** `ZUI.lua` or `loader.lua`. If a component is missing, say so and describe it.

---

## 6. Output format I want back

- One code block per file, with the full repo path above it (for example `games/example-game/features/Esp.lua`).
- If a change to an existing file is needed, show only the lines to add and say exactly where they go.
- After the code, list what each feature does and which executor functions it needs.
- Ask me before guessing if the request is unclear (which game, exact behaviour).

---

## 7. My request

<describe the game and features here>
