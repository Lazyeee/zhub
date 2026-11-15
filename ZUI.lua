--[[
	ZUI - lightweight, mobile-friendly Roblox UI library
	-----------------------------------------------------
	* Draggable window, resizable corner, minimize (—) and close (X = hide)
	* Draggable floating button to reopen/close (works on touch)
	* Components: Section (with separator line), Divider, Label, Button, Toggle, Slider,
	  NumberBox, TextBox, Dropdown, ColorPicker, Keybind (typed key, works with virtual keyboards)
	* Config: autosave, named configs, export / import (JSON), saves UI size+position
	* Optimised: no per-frame loops, drag listeners only exist while dragging,
	  debounced saves, hidden tabs are not rendered

	USAGE (from any script):
		local ZUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOU/REPO/main/ZUI.lua"))()
		local Win = ZUI.new({ Title = "My Hub", Folder = "MyHub" })
		local Tab = Win:AddTab("Main")
		Tab:AddToggle({ Name = "Cool feature", Default = false, Callback = function(v) print(v) end })
		Win:AddSettingsTab()   -- config save/load/export/import (always shown last)

	Every component with a Name is stored in Win.Flags[Name] (or opts.Flag).
	Components return an object with :Set(value, silent) and .Value
]]

local cloneref = cloneref or function(o) return o end
local function svc(name) return cloneref(game:GetService(name)) end

local UIS          = svc("UserInputService")
local TweenService = svc("TweenService")
local HttpService  = svc("HttpService")
local Players      = svc("Players")
local okCG, CoreGui = pcall(svc, "CoreGui")

local HAS_FS = (writefile and readfile and isfile and isfolder and makefolder) and true or false

local TOPBAR_H = 38
local SIDEBAR_W = 92

local Theme = {
	Background = Color3.fromRGB(22, 22, 28),
	Topbar     = Color3.fromRGB(28, 28, 36),
	Element    = Color3.fromRGB(36, 36, 46),
	Stroke     = Color3.fromRGB(58, 58, 72),
	Text       = Color3.fromRGB(236, 236, 242),
	SubText    = Color3.fromRGB(150, 150, 168),
	Accent     = Color3.fromRGB(88, 130, 255),
}

local Library = { Theme = Theme, Version = "1.0.0" }
local Window = {}; Window.__index = Window
local Tab = {};    Tab.__index = Tab

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function create(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function corner(parent, r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent })
end

local function stroke(parent, color, t)
	return create("UIStroke", {
		Color = color or Theme.Stroke, Thickness = t or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function pad(parent, l, t, r, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0),
		Parent = parent,
	})
end

local function label(props)
	local p = {
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	}
	for k, v in pairs(props) do p[k] = v end
	return create("TextLabel", p)
end

local function isPointer(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

-- Listens for movement ONLY while a pointer is held down, then disconnects.
local function trackInput(input, onMove, onEnd)
	local move, ended
	move = UIS.InputChanged:Connect(function(i)
		if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
			onMove(i.Position)
		end
	end)
	ended = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			move:Disconnect()
			ended:Disconnect()
			if onEnd then onEnd() end
		end
	end)
end

local function makeDraggable(handle, target, onEnd)
	handle.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		local start, origin, moved = input.Position, target.Position, false
		trackInput(input, function(p)
			local d = p - start
			if not moved and d.Magnitude < 5 then return end
			moved = true
			target.Position = UDim2.fromOffset(origin.X.Offset + d.X, origin.Y.Offset + d.Y)
		end, function()
			if onEnd then onEnd(moved) end
		end)
	end)
end

local function protectGui(gui)
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
	local ok = false
	if gethui then ok = pcall(function() gui.Parent = gethui() end) end
	if not ok or not gui.Parent then
		ok = okCG and pcall(function() gui.Parent = CoreGui end)
	end
	if not ok or not gui.Parent then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end
Library.ProtectGui = protectGui

local function viewport(root)
	local s = root.AbsoluteSize
	if s.X < 10 then
		local cam = workspace.CurrentCamera
		s = cam and cam.ViewportSize or Vector2.new(800, 400)
	end
	return s
end

local function clampPos(x, y, w, vs, margin, bottom)
	x = math.clamp(x, -(w - margin), math.max(0, vs.X - margin))
	y = math.clamp(y, 0, math.max(0, vs.Y - bottom))
	return x, y
end

local function encode(v)
	if typeof(v) == "Color3" then
		return { __c = { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) } }
	end
	return v
end

local function decode(v)
	if type(v) == "table" and type(v.__c) == "table" then
		return Color3.fromRGB(v.__c[1] or 255, v.__c[2] or 255, v.__c[3] or 255)
	end
	return v
end

local DIGITS = { [0] = "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }

-- "e" / "E" -> E, "5" -> Five, "leftshift" / "Space" -> full KeyCode names. Returns Enum.KeyCode or nil.
local function parseKey(s)
	s = tostring(s or ""):gsub("%s", "")
	if s == "" then return nil end
	local name
	if #s == 1 then
		name = s:match("%d") and DIGITS[tonumber(s)] or s:upper()
	else
		local low = s:lower()
		for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
			if item.Name:lower() == low then name = item.Name break end
		end
	end
	if not name then return nil end
	local ok, kc = pcall(function() return Enum.KeyCode[name] end)
	return ok and kc or nil
end

local function cleanName(n)
	return (tostring(n or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
function Library.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Window)

	self.Title = opts.Title or "ZUI"
	self.Folder = opts.Folder or "ZUI"
	self.ToggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
	self.Flags, self._saved, self._objects = {}, {}, {}
	self._conns, self._cleanup, self._binds = {}, {}, {}
	self.Tabs = {} -- Hub.Tabs["Misc"] etc., so other scripts can add to an existing tab
	self._tabCount, self._toastToken = 0, 0
	self._minSize = opts.MinSize or Vector2.new(320, 210)
	self._defaultSize = opts.Size or Vector2.new(480, 310)
	self._pending = self:_read(self.Folder .. "/autosave.json") or {}

	local root = create("ScreenGui", {
		Name = HttpService:GenerateGUID(false):sub(1, 8),
		ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	})
	protectGui(root)
	self.Root = root

	-- main window ------------------------------------------------------
	local main = create("Frame", {
		Name = "Main", BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
		Active = true, ClipsDescendants = true, Size = UDim2.fromOffset(400, 260), Parent = root,
	})
	corner(main, 10); stroke(main)
	self._main = main

	local top = create("Frame", {
		Name = "Topbar", Size = UDim2.new(1, 0, 0, TOPBAR_H),
		BackgroundColor3 = Theme.Topbar, BorderSizePixel = 0, Parent = main,
	})
	label({
		Text = self.Title, Font = Enum.Font.GothamBold, TextSize = 14,
		Size = UDim2.new(1, -90, 1, 0), Position = UDim2.fromOffset(12, 0), Parent = top,
	})

	local function topBtn(text, xOff)
		local b = create("TextButton", {
			Size = UDim2.fromOffset(28, 26), Position = UDim2.new(1, xOff, 0.5, -13),
			BackgroundColor3 = Theme.Element, Text = text, Font = Enum.Font.GothamBold,
			TextSize = 13, TextColor3 = Theme.Text, AutoButtonColor = true, Parent = top,
		})
		corner(b, 6)
		return b
	end
	local btnClose = topBtn("X", -36)
	local btnMin = topBtn("—", -68)

	local body = create("Frame", {
		Name = "Body", Position = UDim2.fromOffset(0, TOPBAR_H),
		Size = UDim2.new(1, 0, 1, -TOPBAR_H), BackgroundTransparency = 1, Parent = main,
	})
	self._body = body

	local sidebar = create("ScrollingFrame", {
		Size = UDim2.new(0, SIDEBAR_W, 1, 0), BackgroundColor3 = Theme.Topbar,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = body,
	})
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
	pad(sidebar, 6, 8, 6, 8)
	self._sidebar = sidebar

	self._content = create("Frame", {
		Position = UDim2.fromOffset(SIDEBAR_W, 0), Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BackgroundTransparency = 1, Parent = body,
	})

	-- resize grip (bottom-right corner) ---------------------------------
	local grip = create("Frame", {
		Name = "Grip", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1, Active = true, ZIndex = 20, Parent = main,
	})
	for _, p in ipairs({ { 15, 15 }, { 9, 15 }, { 15, 9 } }) do
		local dot = create("Frame", {
			Size = UDim2.fromOffset(3, 3), Position = UDim2.fromOffset(p[1], p[2]),
			BackgroundColor3 = Theme.SubText, BorderSizePixel = 0, ZIndex = 21, Parent = grip,
		})
		corner(dot, 2)
	end
	self._grip = grip

	grip.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		local start, orig = input.Position, self._size
		local vs, pos, min = viewport(root), main.Position, self._minSize
		local maxW = math.max(min.X, vs.X - pos.X.Offset)
		local maxH = math.max(min.Y, vs.Y - pos.Y.Offset)
		trackInput(input, function(p)
			local d = p - start
			self:_setSize(math.clamp(orig.X + d.X, min.X, maxW), math.clamp(orig.Y + d.Y, min.Y, maxH))
		end, function() self:_queueSave() end)
	end)

	-- floating button ---------------------------------------------------
	local btn = create("TextButton", {
		Name = "Float", Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Theme.Accent,
		Text = "", AutoButtonColor = true, ZIndex = 30, Parent = root,
	})
	corner(btn, 23); stroke(btn, Color3.new(1, 1, 1), 1)
	for i = 0, 2 do
		local bar = create("Frame", {
			Size = UDim2.fromOffset(20, 3), Position = UDim2.new(0.5, -10, 0.5, -8 + i * 7),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 31, Parent = btn,
		})
		corner(bar, 2)
	end
	self._btn = btn

	-- toast -------------------------------------------------------------
	local toast = create("TextLabel", {
		Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Topbar, TextColor3 = Theme.Text, Font = Enum.Font.GothamMedium,
		TextSize = 13, Text = "", ZIndex = 50, Parent = root,
	})
	corner(toast, 8); stroke(toast, Theme.Accent); pad(toast, 14, 0, 14, 0)
	self._toast = toast

	-- behaviour ---------------------------------------------------------
	self.Visible = true
	self._minimized = false

	local function afterMove(frame, w, margin, bottom)
		local vs = viewport(root)
		local x, y = clampPos(frame.Position.X.Offset, frame.Position.Y.Offset, w, vs, margin, bottom)
		frame.Position = UDim2.fromOffset(x, y)
		self:_queueSave()
	end

	makeDraggable(top, main, function() afterMove(main, main.AbsoluteSize.X, 80, TOPBAR_H) end)
	makeDraggable(btn, btn, function(moved)
		if moved then afterMove(btn, 46, 24, 24) else self:Toggle() end
	end)

	btnClose.MouseButton1Click:Connect(function() self:SetVisible(false) end)
	btnMin.MouseButton1Click:Connect(function() self:SetMinimized(not self._minimized) end)

	table.insert(self._conns, UIS.InputBegan:Connect(function(i, gp)
		if not gp and i.KeyCode == self.ToggleKey then self:Toggle() end
	end))

	self:_applyUI(self._pending.ui)
	return self
end

function Window:_applyUI(ui)
	ui = ui or {}
	local vs = viewport(self.Root)
	local min = self._minSize
	local w = math.clamp(ui.w or self._defaultSize.X, min.X, math.max(min.X, vs.X - 16))
	local h = math.clamp(ui.h or self._defaultSize.Y, min.Y, math.max(min.Y, vs.Y - 16))
	self._size = Vector2.new(w, h)
	local x, y = clampPos(ui.x or (vs.X - w) / 2, ui.y or (vs.Y - h) / 2, w, vs, 80, TOPBAR_H)
	self._main.Position = UDim2.fromOffset(x, y)
	self._main.Size = UDim2.fromOffset(w, self._minimized and TOPBAR_H or h)
	local bx, by = clampPos(ui.bx or 12, ui.by or vs.Y * 0.4, 46, vs, 24, 24)
	self._btn.Position = UDim2.fromOffset(bx, by)
end

function Window:_setSize(w, h)
	self._size = Vector2.new(w, h)
	if not self._minimized then self._main.Size = UDim2.fromOffset(w, h) end
end

function Window:SetVisible(v)
	self.Visible = v and true or false
	self._main.Visible = self.Visible
end

function Window:Toggle() self:SetVisible(not self.Visible) end

function Window:SetMinimized(v)
	self._minimized = v and true or false
	self._body.Visible = not self._minimized
	self._grip.Visible = not self._minimized
	self._main.Size = UDim2.fromOffset(self._size.X, self._minimized and TOPBAR_H or self._size.Y)
end

function Window:Notify(text, duration)
	self._toastToken += 1
	local token = self._toastToken
	self._toast.Text = tostring(text)
	self._toast.Visible = true
	task.delay(duration or 2.5, function()
		if self._toastToken == token then self._toast.Visible = false end
	end)
end

function Window:OnUnload(fn) table.insert(self._cleanup, fn) end

function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, fn in ipairs(self._cleanup) do pcall(fn) end
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	self.Root:Destroy()
end

----------------------------------------------------------------------
-- config / files
----------------------------------------------------------------------
function Window:_read(path)
	if not HAS_FS or not isfile(path) then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	return ok and type(data) == "table" and data or nil
end

function Window:_ensure()
	if not HAS_FS then return end
	if not isfolder(self.Folder) then pcall(makefolder, self.Folder) end
	if not isfolder(self.Folder .. "/configs") then pcall(makefolder, self.Folder .. "/configs") end
end

function Window:_write(path, tbl)
	if not HAS_FS then return false end
	self:_ensure()
	return (pcall(function() writefile(path, HttpService:JSONEncode(tbl)) end))
end

function Window:_snapshot()
	local flags = {}
	for flag in pairs(self._saved) do flags[flag] = encode(self.Flags[flag]) end
	local m, b = self._main.Position, self._btn.Position
	return {
		flags = flags,
		ui = { w = self._size.X, h = self._size.Y, x = m.X.Offset, y = m.Y.Offset, bx = b.X.Offset, by = b.Y.Offset },
	}
end

-- debounced: many changes in a row = one disk write
function Window:_queueSave()
	if self._saveQueued or self._destroyed then return end
	self._saveQueued = true
	task.delay(1.5, function()
		self._saveQueued = false
		if not self._destroyed then self:_write(self.Folder .. "/autosave.json", self:_snapshot()) end
	end)
end

function Window:ApplyConfig(data)
	if type(data) ~= "table" then return false end
	for flag, val in pairs(data.flags or {}) do
		local o = self._objects[flag]
		if o and self._saved[flag] then pcall(o.Set, o, decode(val)) end
	end
	if type(data.ui) == "table" then self:_applyUI(data.ui) end
	self:_queueSave()
	return true
end

function Window:ExportConfig() return HttpService:JSONEncode(self:_snapshot()) end

function Window:ImportConfig(str)
	local ok, data = pcall(function() return HttpService:JSONDecode(str) end)
	if not ok or type(data) ~= "table" or type(data.flags) ~= "table" then return false end
	return self:ApplyConfig(data)
end

function Window:ListConfigs()
	local out = {}
	if HAS_FS and listfiles then
		self:_ensure()
		local ok, files = pcall(listfiles, self.Folder .. "/configs")
		if ok then
			for _, f in ipairs(files) do
				local n = f:match("([^/\\]+)%.json$")
				if n then table.insert(out, n) end
			end
		end
	end
	table.sort(out)
	return out
end

function Window:SaveConfig(name)
	name = cleanName(name)
	if name == "" then return false, "Enter a config name" end
	if not HAS_FS then return false, "Executor has no file access" end
	return self:_write(self.Folder .. "/configs/" .. name .. ".json", self:_snapshot())
end

function Window:LoadConfig(name)
	name = cleanName(name)
	local data = self:_read(self.Folder .. "/configs/" .. name .. ".json")
	if not data then return false, "Config not found" end
	return self:ApplyConfig(data)
end

function Window:DeleteConfig(name)
	name = cleanName(name)
	local path = self.Folder .. "/configs/" .. name .. ".json"
	if HAS_FS and delfile and isfile(path) then return (pcall(delfile, path)) end
	return false
end

-- Called by every component: restores the saved value (if any) and applies defaults.
function Window:_register(flag, obj, opts)
	if self._objects[flag] then warn("[ZUI] duplicate flag: " .. flag) end
	self._objects[flag] = obj
	if opts.Save ~= false then self._saved[flag] = true end

	local loaded
	if opts.Save ~= false and type(self._pending.flags) == "table" then
		loaded = decode(self._pending.flags[flag])
	end
	local init = loaded
	if init == nil then init = opts.Default end
	obj:Set(init, true)

	-- callbacks run on creation only when restoring a saved value (or a Default=true toggle)
	if (loaded ~= nil or opts.Default == true) and opts.Callback then
		task.spawn(opts.Callback, obj.Value)
	end
	return obj
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
function Window:_select(tab)
	local cur = self._current
	if cur == tab then return end
	if cur then
		cur.Page.Visible = false -- hidden pages are not rendered
		cur.Button.BackgroundTransparency = 1
		cur.Button.TextColor3 = Theme.SubText
	end
	self._current = tab
	tab.Page.Visible = true
	tab.Button.BackgroundTransparency = 0
	tab.Button.TextColor3 = Theme.Text
end

-- order (optional): lower = higher in the sidebar. Default = creation order.
function Window:AddTab(name, order)
	self._tabCount += 1
	local tab = setmetatable({ Window = self, Name = name, Order = order or self._tabCount, _n = 0 }, Tab)

	tab.Button = create("TextButton", {
		Name = name, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 1, Text = name, Font = Enum.Font.GothamMedium, TextSize = 13,
		TextColor3 = Theme.SubText, AutoButtonColor = false, LayoutOrder = tab.Order,
		Parent = self._sidebar,
	})
	corner(tab.Button, 6)

	tab.Page = create("ScrollingFrame", {
		Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = self._content,
	})
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tab.Page })
	pad(tab.Page, 8, 8, 10, 28)

	tab.Button.MouseButton1Click:Connect(function() self:_select(tab) end)
	self.Tabs[name] = tab
	if not self._current or tab.Order < self._current.Order then self:_select(tab) end
	return tab
end

function Tab:_row(height)
	self._n += 1
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0, LayoutOrder = self._n, Parent = self.Page,
	})
	corner(row, 6)
	return row
end

----------------------------------------------------------------------
-- Components
----------------------------------------------------------------------
-- Section header with a separator line under it. Use one per group of features.
function Tab:AddSection(text)
	self._n += 1
	local f = create("Frame", {
		Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = self._n, Parent = self.Page,
	})
	label({
		Text = string.upper(text), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Theme.Accent,
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(2, 8), Parent = f,
	})
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = f,
	})
	return f
end

-- Plain separator line (no title)
function Tab:AddDivider()
	self._n += 1
	return create("Frame", {
		Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0,
		LayoutOrder = self._n, Parent = self.Page,
	})
end

function Tab:AddLabel(text)
	self._n += 1
	local l = label({
		Text = text, TextColor3 = Theme.SubText, TextWrapped = true, TextSize = 12,
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._n, Parent = self.Page,
	})
	return { Instance = l, SetText = function(_, t) l.Text = tostring(t) end }
end

function Tab:AddButton(opts)
	self._n += 1
	local b = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Theme.Element, Text = opts.Name,
		Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.Text,
		AutoButtonColor = true, LayoutOrder = self._n, Parent = self.Page,
	})
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		if opts.Callback then task.spawn(opts.Callback) end
	end)
	return { Instance = b, SetText = function(_, t) b.Text = tostring(t) end }
end

function Tab:AddToggle(opts)
	local win = self.Window
	local flag = opts.Flag or opts.Name
	local row = self:_row(34)
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = row })
	label({ Text = opts.Name, Size = UDim2.new(1, -62, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = row })
	local sw = create("Frame", {
		Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -48, 0.5, -10),
		BackgroundColor3 = Theme.Stroke, Parent = row,
	})
	corner(sw, 10)
	local knob = create("Frame", {
		Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), Parent = sw,
	})
	corner(knob, 7)

	local obj = { Value = false }
	local info = TweenInfo.new(0.1)
	function obj:Set(v, silent)
		v = v and true or false
		self.Value = v
		win.Flags[flag] = v
		TweenService:Create(knob, info, { Position = v and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) }):Play()
		TweenService:Create(sw, info, { BackgroundColor3 = v and Theme.Accent or Theme.Stroke }):Play()
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, v) end
		end
	end
	hit.MouseButton1Click:Connect(function() obj:Set(not obj.Value) end)
	return win:_register(flag, obj, opts)
end

function Tab:AddSlider(opts)
	local win, page = self.Window, self.Page
	local flag = opts.Flag or opts.Name
	local min, max, inc = opts.Min or 0, opts.Max or 100, opts.Increment or 1
	local decimals = #(tostring(inc):match("%.(%d+)") or "")
	local suffix = opts.Suffix or ""

	local row = self:_row(48)
	label({ Text = opts.Name, Size = UDim2.new(1, -96, 0, 22), Position = UDim2.fromOffset(10, 4), Parent = row })
	local valLbl = label({
		Size = UDim2.fromOffset(80, 22), Position = UDim2.new(1, -90, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.SubText, Parent = row,
	})
	local hit = create("TextButton", {
		Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
		Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 25), Parent = row,
	})
	local track = create("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3),
		BackgroundColor3 = Theme.Stroke, Parent = hit,
	})
	corner(track, 3)
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, Parent = track })
	corner(fill, 3)
	local knob = create("Frame", {
		Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track,
	})
	corner(knob, 7)

	local obj = { Value = nil }
	function obj:Set(v, silent)
		v = tonumber(v) or opts.Default or min
		v = math.clamp(min + math.floor((v - min) / inc + 0.5) * inc, min, max)
		v = tonumber(string.format("%." .. decimals .. "f", v))
		if v == self.Value and not silent then return end
		self.Value = v
		win.Flags[flag] = v
		local a = (max > min) and (v - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valLbl.Text = tostring(v) .. suffix
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, v) end
		end
	end

	local function fromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		obj:Set(min + (max - min) * rel)
	end
	hit.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		page.ScrollingEnabled = false -- stop the page scrolling while dragging
		fromX(input.Position.X)
		trackInput(input, function(p) fromX(p.X) end, function() page.ScrollingEnabled = true end)
	end)
	return win:_register(flag, obj, opts)
end

function Tab:AddNumberBox(opts)
	local win = self.Window
	local flag = opts.Flag or opts.Name
	local min, max = opts.Min or -math.huge, opts.Max or math.huge
	local row = self:_row(34)
	label({ Text = opts.Name, Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = row })
	local box = create("TextBox", {
		Size = UDim2.fromOffset(90, 24), Position = UDim2.new(1, -100, 0.5, -12),
		BackgroundColor3 = Theme.Background, TextColor3 = Theme.Text, Font = Enum.Font.Gotham,
		TextSize = 12, Text = "", ClearTextOnFocus = false, Parent = row,
	})
	corner(box, 5); stroke(box)

	local obj = { Value = nil }
	function obj:Set(v, silent)
		v = tonumber(v)
		if not v then v = self.Value or opts.Default or 0 end
		v = math.clamp(v, min, max)
		if opts.Integer then v = math.floor(v + 0.5) end
		self.Value = v
		win.Flags[flag] = v
		box.Text = tostring(v)
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, v) end
		end
	end
	box.FocusLost:Connect(function() obj:Set(box.Text) end)
	return win:_register(flag, obj, opts)
end

function Tab:AddTextBox(opts)
	local win = self.Window
	local flag = opts.Flag or opts.Name
	local row = self:_row(34)
	label({ Text = opts.Name, Size = UDim2.new(0.45, -10, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = row })
	local box = create("TextBox", {
		Size = UDim2.new(0.55, -16, 0, 24), Position = UDim2.new(0.45, 6, 0.5, -12),
		BackgroundColor3 = Theme.Background, TextColor3 = Theme.Text, Font = Enum.Font.Gotham,
		TextSize = 12, Text = "", PlaceholderText = opts.Placeholder or "", PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	corner(box, 5); stroke(box)

	local obj = { Value = "" }
	function obj:Set(v, silent)
		v = tostring(v == nil and (opts.Default or "") or v)
		self.Value = v
		win.Flags[flag] = v
		box.Text = v
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, v) end
		end
	end
	box.FocusLost:Connect(function() obj:Set(box.Text) end)
	return win:_register(flag, obj, opts)
end

function Tab:AddDropdown(opts)
	local win = self.Window
	local flag = opts.Flag or opts.Name
	local values = opts.Values or {}
	local row = self:_row(34)
	row.ClipsDescendants = true

	local head = create("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", Parent = row })
	label({ Text = opts.Name, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = head })
	local valLbl = label({
		Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.fromScale(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Accent,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = head,
	})
	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 0, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = row,
	})
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local obj = { Value = nil, Open = false }
	local function resize()
		local h = math.min(#values * 29, 145)
		list.Size = UDim2.new(1, -12, 0, h)
		row.Size = UDim2.new(1, 0, 0, obj.Open and (34 + h + 10) or 34)
	end
	local function build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for i, v in ipairs(values) do
			local b = create("TextButton", {
				Size = UDim2.new(1, -4, 0, 26), BackgroundColor3 = Theme.Background, Text = tostring(v),
				Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Text, LayoutOrder = i, Parent = list,
			})
			corner(b, 5)
			b.MouseButton1Click:Connect(function()
				obj.Open = false
				resize()
				obj:Set(v)
			end)
		end
		resize()
	end

	function obj:Set(v, silent)
		if v == nil then v = opts.Default or values[1] end
		self.Value = v
		win.Flags[flag] = v
		valLbl.Text = tostring(v == nil and "" or v)
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, v) end
		end
	end
	function obj:Refresh(newValues)
		values = newValues or {}
		build()
	end
	head.MouseButton1Click:Connect(function()
		obj.Open = not obj.Open
		resize()
	end)

	build()
	return win:_register(flag, obj, opts)
end

function Tab:AddColorPicker(opts)
	local win, page = self.Window, self.Page
	local flag = opts.Flag or opts.Name
	local row = self:_row(34)
	row.ClipsDescendants = true

	local head = create("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", Parent = row })
	label({ Text = opts.Name, Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = head })
	local swatch = create("Frame", {
		Size = UDim2.fromOffset(32, 18), Position = UDim2.new(1, -42, 0, 8),
		BackgroundColor3 = Color3.new(1, 1, 1), Parent = head,
	})
	corner(swatch, 4); stroke(swatch)

	local body = create("Frame", {
		Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 110), BackgroundTransparency = 1, Parent = row,
	})

	-- saturation / value square
	local sv = create("Frame", {
		Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -52, 0, 98),
		BackgroundColor3 = Color3.fromHSV(0, 1, 1), BorderSizePixel = 0, Parent = body,
	})
	corner(sv, 4)
	local white = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sv })
	corner(white, 4)
	create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv })
	corner(black, 4)
	create("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = black })
	local svCursor = create("Frame", {
		Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 5, Parent = sv,
	})
	corner(svCursor, 5); stroke(svCursor, Color3.new(1, 1, 1), 2)

	-- hue bar
	local hue = create("Frame", {
		Position = UDim2.new(1, -34, 0, 6), Size = UDim2.fromOffset(22, 98),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = body,
	})
	corner(hue, 4)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hue,
	})
	local hueCursor = create("Frame", {
		Size = UDim2.new(1, 4, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5, Parent = hue,
	})
	corner(hueCursor, 2); stroke(hueCursor, Color3.new(0, 0, 0), 1)

	local h, s, v = 0, 0, 1
	local obj = { Value = Color3.new(1, 1, 1), Open = false }

	local function refresh()
		local c = Color3.fromHSV(h, s, v)
		obj.Value = c
		win.Flags[flag] = c
		swatch.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
	end
	local function commit(silent)
		refresh()
		if not silent then
			win:_queueSave()
			if opts.Callback then task.spawn(opts.Callback, obj.Value) end
		end
	end

	function obj:Set(c, silent)
		if typeof(c) ~= "Color3" then c = opts.Default or Color3.new(1, 1, 1) end
		h, s, v = c:ToHSV()
		commit(silent)
	end

	-- dragging is delta-based, so it is immune to GUI inset differences between devices
	sv.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		page.ScrollingEnabled = false
		local start, s0, v0 = input.Position, s, v
		local W, H = math.max(1, sv.AbsoluteSize.X), math.max(1, sv.AbsoluteSize.Y)
		trackInput(input, function(p)
			local d = p - start
			s = math.clamp(s0 + d.X / W, 0, 1)
			v = math.clamp(v0 - d.Y / H, 0, 1)
			commit(false)
		end, function() page.ScrollingEnabled = true end)
	end)
	hue.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		page.ScrollingEnabled = false
		local start, h0 = input.Position, h
		local H = math.max(1, hue.AbsoluteSize.Y)
		trackInput(input, function(p)
			h = math.clamp(h0 + (p - start).Y / H, 0, 1)
			commit(false)
		end, function() page.ScrollingEnabled = true end)
	end)
	head.MouseButton1Click:Connect(function()
		obj.Open = not obj.Open
		row.Size = UDim2.new(1, 0, 0, obj.Open and 148 or 34)
	end)

	return win:_register(flag, obj, opts)
end

-- One shared listener for ALL keybinds (created on first use, ignored while typing in any TextBox)
function Window:_bindKey(obj, opts)
	table.insert(self._binds, { obj = obj, opts = opts })
	if self._bindConn then return end
	local function fire(input, down)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if UIS:GetFocusedTextBox() then return end
		for _, b in ipairs(self._binds) do
			local cb = b.opts.Callback
			if cb and b.obj.Key and input.KeyCode == b.obj.Key then
				if b.opts.Hold then task.spawn(cb, down) elseif down then task.spawn(cb) end
			end
		end
	end
	self._bindConn = UIS.InputBegan:Connect(function(i) fire(i, true) end)
	table.insert(self._conns, self._bindConn)
	table.insert(self._conns, UIS.InputEnded:Connect(function(i) fire(i, false) end))
end

-- Keybind: the user TYPES the key ("F", "5", "LeftShift") instead of pressing it,
-- so it works with on-screen / virtual keyboards. Callback fires when that key is pressed.
-- Options: Name, Default="F", Callback(), Hold=false (Callback(true/false) on down/up), OnChanged(keyName)
function Tab:AddKeybind(opts)
	local win = self.Window
	local flag = opts.Flag or opts.Name
	local row = self:_row(34)
	label({ Text = opts.Name, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = row })
	local box = create("TextBox", {
		Size = UDim2.fromOffset(80, 24), Position = UDim2.new(1, -90, 0.5, -12),
		BackgroundColor3 = Theme.Background, TextColor3 = Theme.Accent, Font = Enum.Font.GothamMedium,
		TextSize = 12, Text = "", PlaceholderText = "type key", PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false, Parent = row,
	})
	corner(box, 5); stroke(box)

	local obj = { Value = "", Key = nil }
	function obj:Set(v, silent)
		v = tostring(v == nil and (opts.Default or "") or v)
		local kc = parseKey(v)
		if v ~= "" and not kc then
			box.Text = self.Value -- invalid input: put the old key back
			win:Notify("Unknown key: " .. v)
			return
		end
		self.Key = kc
		self.Value = kc and kc.Name or ""
		win.Flags[flag] = self.Value
		box.Text = self.Value
		if not silent then
			win:_queueSave()
			if opts.OnChanged then task.spawn(opts.OnChanged, self.Value) end
		end
	end
	box.FocusLost:Connect(function() obj:Set(box.Text) end)

	win:_bindKey(obj, opts)
	-- Callback is deliberately NOT passed to _register: restoring a saved key must not trigger the action
	return win:_register(flag, obj, { Default = opts.Default, Save = opts.Save })
end

----------------------------------------------------------------------
-- Built-in settings tab (config manager). Always sorted last.
----------------------------------------------------------------------
function Window:AddSettingsTab()
	local tab = self:AddTab("Settings", 9999)

	tab:AddSection("Configs")
	local nameBox = tab:AddTextBox({ Name = "Config name", Default = "default", Placeholder = "name", Save = false })
	local list
	list = tab:AddDropdown({
		Name = "Saved configs", Values = self:ListConfigs(), Save = false,
		Callback = function(v) nameBox:Set(v, true) end,
	})
	local function refreshList() list:Refresh(self:ListConfigs()) end

	tab:AddButton({ Name = "Save config", Callback = function()
		local ok, err = self:SaveConfig(nameBox.Value)
		self:Notify(ok and "Config saved" or ("Save failed: " .. tostring(err or "error")))
		refreshList()
	end })
	tab:AddButton({ Name = "Load config", Callback = function()
		local ok, err = self:LoadConfig(nameBox.Value)
		self:Notify(ok and "Config loaded" or ("Load failed: " .. tostring(err or "error")))
	end })
	tab:AddButton({ Name = "Delete config", Callback = function()
		self:Notify(self:DeleteConfig(nameBox.Value) and "Config deleted" or "Delete failed")
		refreshList()
	end })

	tab:AddSection("Share")
	tab:AddButton({ Name = "Export config (copy to clipboard)", Callback = function()
		local str = self:ExportConfig()
		if setclipboard then
			setclipboard(str)
			self:Notify("Config copied to clipboard")
		else
			print(str)
			self:Notify("No clipboard access - printed to console")
		end
	end })
	local importBox = tab:AddTextBox({ Name = "Paste config", Placeholder = "paste JSON here", Save = false })
	tab:AddButton({ Name = "Import pasted config", Callback = function()
		self:Notify(self:ImportConfig(importBox.Value) and "Config imported" or "Invalid config")
	end })
	if getclipboard then
		tab:AddButton({ Name = "Import from clipboard", Callback = function()
			local ok, str = pcall(getclipboard)
			self:Notify(ok and self:ImportConfig(str) and "Config imported" or "Invalid config")
		end })
	end

	tab:AddSection("Interface")
	tab:AddButton({ Name = "Reset window size / position", Callback = function()
		self:_applyUI({})
		self:_queueSave()
	end })
	tab:AddButton({ Name = "Unload UI", Callback = function() self:Destroy() end })
	local function applyMenuKey(name)
		local ok, kc = pcall(function() return Enum.KeyCode[name] end)
		if ok and kc then self.ToggleKey = kc end
	end
	local mk = tab:AddKeybind({ Name = "Menu toggle key", Default = self.ToggleKey.Name, OnChanged = applyMenuKey })
	applyMenuKey(mk.Value)
	tab:AddLabel("Type a key name, e.g. M, F4 or RightShift. The floating button always works.")
	return tab
end

return Library
