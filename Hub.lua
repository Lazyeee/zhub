--[[
	Hub.lua - main script. This is the file you loadstring.

	loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/Hub.lua"))()

	Other scripts can plug into the same window (see GUIDE.md):
		local Hub = getgenv().ZHub
		local misc = Hub.Tabs.Misc                 -- add to the Misc tab, or
		local tab = Hub:AddTab("My Script")        -- make a new tab (sits above Misc)
		tab:AddToggle({ Name = "Thing", Callback = function(v) end })
]]

local LIB_URL = "https://raw.githubusercontent.com/Lazyeee/zhub/main/ZUI.lua"

local genv = getgenv and getgenv() or _G
if genv.ZHub then pcall(function() genv.ZHub:Destroy() end) end -- re-execute = clean reload

local Library = loadstring(game:HttpGet(LIB_URL))()
local Hub = Library.new({ Title = "Z Hub", Folder = "ZHub" })
genv.ZHub, genv.ZUI = Hub, Library

local Lighting  = game:GetService("Lighting")
local Players   = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

----------------------------------------------------------------------
-- Sweeper: applies a change to every matching instance (in small chunks so
-- the game doesn't freeze), watches new ones, and fully reverts on disable.
----------------------------------------------------------------------
local function makeSweeper(root, match, apply, revert)
	local saved = setmetatable({}, { __mode = "k" })
	local conn, token = nil, 0

	local function handle(d)
		if saved[d] == nil and match(d) then
			local ok, orig = pcall(apply, d)
			if ok and orig ~= nil then saved[d] = orig end
		end
	end

	local sweeper = {}
	function sweeper.on()
		token += 1
		local my = token
		if conn then conn:Disconnect() end
		conn = root.DescendantAdded:Connect(handle)
		task.spawn(function()
			local n = 0
			for _, d in ipairs(root:GetDescendants()) do
				if my ~= token then return end
				handle(d)
				n += 1
				if n % 250 == 0 then task.wait() end
			end
		end)
	end
	function sweeper.off()
		token += 1
		if conn then conn:Disconnect(); conn = nil end
		for d, orig in pairs(saved) do
			if d.Parent then pcall(revert, d, orig) end
			saved[d] = nil
		end
	end
	return sweeper
end

local plastic = makeSweeper(Workspace,
	function(d) return d:IsA("BasePart") and not d:IsA("Terrain") end,
	function(d)
		local o = { d.Material, d.Reflectance, d.CastShadow }
		d.Material, d.Reflectance, d.CastShadow = Enum.Material.SmoothPlastic, 0, false
		return o
	end,
	function(d, o) d.Material, d.Reflectance, d.CastShadow = o[1], o[2], o[3] end)

local decals = makeSweeper(Workspace,
	function(d) return d:IsA("Decal") or d:IsA("Texture") end,
	function(d) local o = { d.Transparency }; d.Transparency = 1; return o end,
	function(d, o) d.Transparency = o[1] end)

local effects = makeSweeper(Workspace,
	function(d)
		return d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
	end,
	function(d) local o = { d.Enabled }; d.Enabled = false; return o end,
	function(d, o) d.Enabled = o[1] end)

local post = makeSweeper(Lighting,
	function(d) return d:IsA("PostEffect") end,
	function(d) local o = { d.Enabled }; d.Enabled = false; return o end,
	function(d, o) d.Enabled = o[1] end)

local shadowOrig
local function setShadows(off)
	if off then
		if shadowOrig == nil then shadowOrig = Lighting.GlobalShadows end
		Lighting.GlobalShadows = false
	elseif shadowOrig ~= nil then
		Lighting.GlobalShadows = shadowOrig
		shadowOrig = nil
	end
end

local waterOrig
local function setWater(low)
	local t = Workspace:FindFirstChildOfClass("Terrain")
	if not t then return end
	if low then
		if not waterOrig then waterOrig = { t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance } end
		t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance = 0, 0, 0
	elseif waterOrig then
		t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance = waterOrig[1], waterOrig[2], waterOrig[3]
		waterOrig = nil
	end
end

local fpsGui, fpsConn
local function setFpsCounter(on)
	if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
	if fpsGui then fpsGui:Destroy(); fpsGui = nil end
	if not on then return end
	fpsGui = Instance.new("TextLabel")
	fpsGui.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	fpsGui.BackgroundTransparency = 0.25
	fpsGui.TextColor3 = Color3.new(1, 1, 1)
	fpsGui.Font = Enum.Font.GothamBold
	fpsGui.TextSize = 13
	fpsGui.Size = UDim2.fromOffset(70, 24)
	fpsGui.Position = UDim2.new(1, -80, 0, 8)
	fpsGui.Text = "-- FPS"
	Instance.new("UICorner", fpsGui).CornerRadius = UDim.new(0, 6)
	fpsGui.Parent = Hub.Root
	local acc, frames = 0, 0
	fpsConn = RunService.Heartbeat:Connect(function(dt)
		acc += dt; frames += 1
		if acc >= 0.5 then -- label updates twice a second, not every frame
			fpsGui.Text = string.format("%d FPS", frames / acc + 0.5)
			acc, frames = 0, 0
		end
	end)
end

local afkConn
local function setAntiAfk(on)
	if afkConn then afkConn:Disconnect(); afkConn = nil end
	if not on then return end
	afkConn = Players.LocalPlayer.Idled:Connect(function()
		local vu = game:GetService("VirtualUser")
		vu:CaptureController()
		vu:ClickButton2(Vector2.new())
	end)
end

Hub:OnUnload(function()
	plastic.off(); decals.off(); effects.off(); post.off()
	setShadows(false); setWater(false); setFpsCounter(false); setAntiAfk(false)
end)

----------------------------------------------------------------------
-- Tab: Misc  (every universal feature lives here)
-- Top to bottom = priority. Each group is a section with a separator line.
-- To reorder: move a whole "-- group" block up or down in this file.
-- Game-specific tabs made by other scripts sit ABOVE Misc automatically.
----------------------------------------------------------------------
local misc = Hub:AddTab("Misc", 9000)

-- group 1: FPS boost ---------------------------------------------------
misc:AddSection("FPS boost")
local boosters = {}
boosters[#boosters + 1] = misc:AddToggle({ Name = "Smooth plastic + no part shadows", Callback = function(v)
	if v then plastic.on() else plastic.off() end
end })
boosters[#boosters + 1] = misc:AddToggle({ Name = "Hide decals / textures", Callback = function(v)
	if v then decals.on() else decals.off() end
end })
boosters[#boosters + 1] = misc:AddToggle({ Name = "Disable particles / trails / beams", Callback = function(v)
	if v then effects.on() else effects.off() end
end })
boosters[#boosters + 1] = misc:AddToggle({ Name = "Disable post-processing", Callback = function(v)
	if v then post.on() else post.off() end
end })
boosters[#boosters + 1] = misc:AddToggle({ Name = "Disable global shadows", Callback = setShadows })
boosters[#boosters + 1] = misc:AddToggle({ Name = "Calm water", Callback = setWater })
misc:AddButton({ Name = "Enable ALL boosters", Callback = function()
	for _, t in ipairs(boosters) do t:Set(true) end
	Hub:Notify("All boosters enabled")
end })
misc:AddButton({ Name = "Disable all boosters", Callback = function()
	for _, t in ipairs(boosters) do t:Set(false) end
end })

-- group 2: Renderer ----------------------------------------------------
misc:AddSection("Renderer")
misc:AddSlider({ Name = "Graphics level", Min = 1, Max = 10, Default = 5, Callback = function(n)
	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel["Level" .. string.format("%02d", n)]
	end)
end })
misc:AddNumberBox({ Name = "FPS cap (0 = unlimited)", Min = 0, Max = 1000, Default = 60, Integer = true, Callback = function(n)
	if setfpscap then setfpscap(n) else Hub:Notify("Executor has no setfpscap") end
end })

-- group 3: Display -----------------------------------------------------
misc:AddSection("Display")
misc:AddToggle({ Name = "Show FPS counter", Callback = setFpsCounter })

-- group 4: Utilities ---------------------------------------------------
misc:AddSection("Utilities")
misc:AddToggle({ Name = "Anti-AFK", Callback = setAntiAfk })
misc:AddButton({ Name = "Rejoin server", Callback = function()
	local ts = game:GetService("TeleportService")
	if #Players:GetPlayers() <= 1 then
		Players.LocalPlayer:Kick("\nRejoining...")
		task.wait()
		ts:Teleport(game.PlaceId, Players.LocalPlayer)
	else
		ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, Players.LocalPlayer)
	end
end })

-- group 5: Component examples (copy what you need, delete this group when done)
misc:AddSection("Component examples")
misc:AddButton({ Name = "Button", Callback = function() Hub:Notify("Button pressed") end })
misc:AddToggle({ Name = "Toggle", Default = false, Callback = function(v) print("toggle", v) end })
misc:AddSlider({ Name = "Slider", Min = 0, Max = 100, Default = 25, Increment = 1, Suffix = "%", Callback = function(v) print("slider", v) end })
misc:AddNumberBox({ Name = "Number box", Min = 0, Max = 500, Default = 16, Callback = function(v) print("number", v) end })
misc:AddTextBox({ Name = "Text box", Placeholder = "type...", Callback = function(v) print("text", v) end })
misc:AddDropdown({ Name = "Dropdown", Values = { "One", "Two", "Three" }, Default = "One", Callback = function(v) print("dropdown", v) end })
misc:AddKeybind({ Name = "Keybind", Default = "F", Callback = function() Hub:Notify("Key pressed") end })
misc:AddColorPicker({ Name = "Color picker", Default = Color3.fromRGB(88, 130, 255), Callback = function(c) print("color", c) end })
misc:AddLabel("Values are available any time as Hub.Flags[\"Slider\"] etc.")

----------------------------------------------------------------------
-- Optional feature modules: repo files that return function(Hub) ... end
-- Add file names here, e.g. { "modules/Visual.lua", "modules/Fun.lua" }
----------------------------------------------------------------------
local BASE = (LIB_URL:gsub("ZUI%.lua$", ""))
local MODULES = {}
for _, file in ipairs(MODULES) do
	local ok, err = pcall(function() loadstring(game:HttpGet(BASE .. file))()(Hub) end)
	if not ok then warn("[ZHub] module failed: " .. file .. " - " .. tostring(err)) end
end

----------------------------------------------------------------------
Hub:AddSettingsTab()
Hub:Notify("Z Hub loaded")
return Hub
