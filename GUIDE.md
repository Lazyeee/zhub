# Z Hub: guide for AI assistants

I build Roblox executor scripts (Luau) on top of my own UI library, **ZUI**, and my hub, **Z Hub**.
Read this whole guide before writing code. Do NOT create your own UI, windows, ScreenGuis or buttons.
Use ZUI for every menu element.

Repo: `https://raw.githubusercontent.com/Lazyeee/zhub/main/`

| File | What it is |
|------|------------|
| `ZUI.lua` | The UI library (window, tabs, components, config system). Never rewrite it. |
| `Hub.lua` | The main script that I loadstring. It creates the window and the built-in features. |
| `modules/*.lua` | Optional feature modules (one file per group of features). |

Run command: `loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/Hub.lua"))()`

---

## 1. How the hub is organised

- One window with a left sidebar of **tabs**. It has a floating open/close button for mobile, a movable
  window, a resizable corner, and a minimize and an X button (X only hides it).
- **Misc tab**: all universal features live here (FPS boost, renderer, display, utilities, component
  examples). Each group is a section with a separator line. Order = priority, so the most important group is at the top.
- **Game-specific features** get their own tab. Tabs sort by creation order, except Misc (always near the
  bottom) and Settings (always last).
- **Settings tab**: config save/load/delete, export/import (JSON), reset window, unload, menu key.
  It is added once by `Hub.lua`. Feature scripts must never call `AddSettingsTab`.
- Globals available after `Hub.lua` has run:
  - `getgenv().ZHub` is the window (also `Hub` inside `Hub.lua`)
  - `getgenv().ZUI` is the library
  - `Hub.Tabs["Misc"]` (or any tab name) returns an existing tab
  - `Hub.Flags["Component name"]` gives the current value of any component

### Features that already exist in Misc (do not duplicate)
FPS boost: smooth plastic and no part shadows, hide decals/textures, disable particles/trails/beams, disable
post-processing, disable global shadows, calm water, enable/disable all boosters.
Renderer: graphics level slider, FPS cap box.
Display: FPS counter.
Utilities: Anti-AFK, Rejoin server.
Component examples: one of every component.

---

## 2. Component API

Get a tab with `local tab = Hub:AddTab("Name")` (new tab) or `local tab = Hub.Tabs["Misc"]` (existing tab).
Components are added top to bottom in the order you call them.

```lua
tab:AddSection("Title")      -- header with a separator line; start every group of features with one
tab:AddDivider()             -- plain separator line, no title
tab:AddLabel("text")         -- returns obj; obj:SetText("new text")
tab:AddButton{ Name="", Callback=function() end }

tab:AddToggle{ Name="", Default=false, Callback=function(on) end }
tab:AddSlider{ Name="", Min=0, Max=100, Default=50, Increment=1, Suffix="", Callback=function(n) end }
tab:AddNumberBox{ Name="", Min=0, Max=500, Default=16, Integer=false, Callback=function(n) end }
tab:AddTextBox{ Name="", Default="", Placeholder="", Callback=function(str) end }
tab:AddDropdown{ Name="", Values={"A","B"}, Default="A", Callback=function(choice) end }   -- obj:Refresh(newValues)
tab:AddColorPicker{ Name="", Default=Color3.fromRGB(255,255,255), Callback=function(color) end }
tab:AddKeybind{ Name="", Default="F", Callback=function() end }
```

Options shared by every component that has a value:
- `Flag = "id"`: key used for saving and `Hub.Flags` (defaults to `Name`).
- `Save = false`: do not store this value in configs (use for lists, temporary text, etc.).

Every value component returns an object: `obj.Value` (current), `obj:Set(value, silent)`
(`silent = true` updates the UI without running the callback).

### Keybind details
- The user TYPES the key ("F", "5", "LeftShift", "Space") instead of pressing it, so it works with on-screen keyboards.
- `Callback()` runs when the key is pressed. With `Hold = true` it runs `Callback(true)` on key down
  and `Callback(false)` on key up.
- `OnChanged(keyName)` runs when the user changes the key.
- Keybinds are ignored while any TextBox is focused.
- To bind a key to a toggle: `Callback = function() myToggle:Set(not myToggle.Value) end`.

### Callback timing (important)
- Callbacks run on every change, and on drag for sliders and color pickers. Keep them cheap.
- A callback also runs ONCE when the hub loads if a saved value exists (or if a toggle has `Default = true`).
  So the "off" path must be safe to run when the feature was never on.
- Keybind callbacks never run on load.

---

## 3. Rules for every feature you write

1. **Unique names.** Every `Name` (or `Flag`) must be unique across the whole hub, not just the tab.
2. **Cleanup.** Whatever a feature changes must be fully reverted when its toggle turns off. Also register
   `Hub:OnUnload(function() ... end)` so unloading the UI reverts everything.
3. **Performance first.** No `while true` or `RenderStepped` loops running by default. Connect events only
   when a toggle is ON, store the connection, and `:Disconnect()` it when OFF. Prefer events
   (`.Changed`, `.ChildAdded`) over polling. If a loop is unavoidable, use `task.wait(0.25)` or slower and stop it when OFF.
   Big sweeps over `GetDescendants()` must yield (`task.wait()`) every few hundred items.
4. **Executor safety.** Check that executor functions exist before using them
   (`if setfpscap then`, `if getgenv then`) and wrap risky calls in `pcall`.
5. **Mobile first.** No features that need a physical keyboard or mouse to use. Prefer toggles, sliders and buttons.
6. **No new GUIs.** Need an on-screen element (like an FPS label)? Parent it to `Hub.Root` (a ScreenGui),
   never create a new ScreenGui.
7. **Notifications.** Use `Hub:Notify("text", seconds)` for feedback.
8. **Services.** Use `game:GetService(...)` at the top of the file, not `game.Players`.
9. **Do not modify** the library functions or touch `Settings`. If you need a component that ZUI doesn't have,
   say so and describe it instead of faking it.

---

## 4. Where to put new code

**A. A feature for the Misc tab (universal feature):** give me a new group to paste into `Hub.lua`
inside the Misc section, starting with `misc:AddSection("Group name")`. Say which existing group it should sit
below so the priority order stays right.

**B. A feature module (game-specific or large):** write it as its own file `modules/Name.lua`:

```lua
return function(Hub)
	local Players = game:GetService("Players")
	local tab = Hub:AddTab("Tab name")           -- or: local tab = Hub.Tabs["Misc"]

	tab:AddSection("Group name")
	local conn
	tab:AddToggle({ Name = "Example feature", Callback = function(on)
		if conn then conn:Disconnect() conn = nil end
		if on then
			conn = Players.LocalPlayer.CharacterAdded:Connect(function(char)
				-- do something
			end)
		else
			-- revert anything the feature changed
		end
	end })

	Hub:OnUnload(function() if conn then conn:Disconnect() end end)
end
```

Modules are loaded by `Hub.lua`: I add the file path (for example `"modules/Name.lua"`) to its `MODULES` list.
Modules run before the Settings tab is added, so their tabs appear above Settings.

---

## 5. Output format I want back

- One code block per file, with the filename above it (for example `modules/Visual.lua`).
- If a change is needed in `Hub.lua`, show only the lines to add and say exactly where they go.
- After the code, give a short list: what each feature does, and any executor function it depends on.
- Ask me before guessing if the request is unclear (game, exact behaviour, mobile or PC).

---

## 6. My request

<describe the features here, and say which tab or group they belong in>
