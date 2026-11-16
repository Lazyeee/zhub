--[[
	loader.lua - the ONLY file you ever loadstring

	loadstring(game:HttpGet("https://raw.githubusercontent.com/Lazyeee/zhub/main/loader.lua"))()

	What it does
	  1. Downloads ZUI.lua (the UI library) and creates the window
	  2. Downloads games.lua (registry) and looks up the current game:
	       game.PlaceId  (one specific place)   -> checked first
	       game.GameId   (the whole experience) -> checked second
	  3. Runs ONLY that game's folder: games/<folder>/init.lua
	  4. Runs universal/Misc.lua (FPS boost, utilities), unless the game turns it off
	  5. Adds the Settings tab

	Game features (games/<folder>/features/*.lua) are NOT downloaded at startup.
	Each one is fetched the first time its toggle is switched on, and never for other games.
]]

local USER, REPO, BRANCH = "Lazyeee", "zhub", "main"
local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)

local genv = getgenv and getgenv() or _G
if genv.ZHub then pcall(function() genv.ZHub:Destroy() end) end -- re-execute = clean reload

----------------------------------------------------------------------
-- download + compile helpers
----------------------------------------------------------------------
local function fetch(path)
	local ok, body = pcall(function() return game:HttpGet(BASE .. path) end)
	if not ok then return nil, "request failed (" .. path .. "): " .. tostring(body) end
	if type(body) ~= "string" or body:match("^404: Not Found") then return nil, "not found: " .. path end
	return body
end

local function compile(path)
	local src, err = fetch(path)
	if not src then return nil, err end
	local fn, cerr = loadstring(src, "=" .. path)
	if not fn then return nil, "syntax error in " .. path .. ": " .. tostring(cerr) end
	return fn
end

----------------------------------------------------------------------
-- 1. library
----------------------------------------------------------------------
local libChunk, libErr = compile("ZUI.lua")
if not libChunk then return warn("[ZHub] could not load ZUI.lua: " .. tostring(libErr)) end
local Library = libChunk()

----------------------------------------------------------------------
-- 2. which game are we in?
----------------------------------------------------------------------
local registry = { games = {}, places = {} }
do
	local chunk, err = compile("games.lua")
	if chunk then
		local ok, res = pcall(chunk)
		if ok and type(res) == "table" then
			registry.games = res.games or {}
			registry.places = res.places or {}
		end
	else
		warn("[ZHub] " .. tostring(err))
	end
end

local entry = registry.places[game.PlaceId] or registry.games[game.GameId]

----------------------------------------------------------------------
-- 3. window (settings/configs are stored per game: ZHub_<Game name>)
----------------------------------------------------------------------
local tag = (entry and entry.name or "Universal"):gsub("[^%w]", "_")
local Hub = Library.new({
	Title = entry and ("Z Hub - " .. entry.name) or "Z Hub",
	Folder = "ZHub_" .. tag,
})
genv.ZHub, genv.ZUI = Hub, Library

Hub.Base = BASE
Hub.Entry = entry
Hub.GameFolder = entry and ((entry.folder:gsub("/*$", "")) .. "/") or nil
Hub._features = {}

-- Run any repo file. If it returns a function, that function is called with (Hub, entry).
function Hub:Run(path)
	local chunk, err = compile(path)
	if not chunk then
		warn("[ZHub] " .. tostring(err))
		self:Notify("Failed to load " .. path, 4)
		return false
	end
	local ok, res = pcall(chunk)
	if ok and type(res) == "function" then ok, res = pcall(res, self, self.Entry) end
	if not ok then
		warn("[ZHub] error in " .. path .. ": " .. tostring(res))
		self:Notify("Error in " .. path, 4)
		return false
	end
	return true
end

-- Download games/<folder>/features/<name>.lua once and cache it.
-- A feature file returns a table: { Enable = function(Hub) end, Disable = function(Hub) end }
function Hub:LoadFeature(name)
	if self._features[name] then return self._features[name] end
	if not self.GameFolder then return nil end
	local path = self.GameFolder .. "features/" .. name .. ".lua"
	local chunk, err = compile(path)
	if not chunk then
		warn("[ZHub] " .. tostring(err))
		self:Notify("Feature not found: " .. name, 4)
		return nil
	end
	local ok, mod = pcall(chunk)
	if not ok or type(mod) ~= "table" then
		warn("[ZHub] feature " .. name .. " must return a table: " .. tostring(mod))
		return nil
	end
	self._features[name] = mod
	return mod
end

-- Use this from a toggle callback. Nothing is downloaded until the feature is switched ON,
-- and switching OFF a feature that was never loaded does nothing (safe on config restore).
function Hub:SetFeature(name, on)
	local mod = self._features[name]
	if not mod then
		if not on then return end
		self:Notify("Loading " .. name .. "...", 1.5)
		mod = self:LoadFeature(name)
		if not mod then return end
	end
	local fn = on and mod.Enable or mod.Disable
	if fn then
		local ok, err = pcall(fn, self)
		if not ok then warn("[ZHub] feature " .. name .. ": " .. tostring(err)) end
	end
end

Hub:OnUnload(function()
	for _, mod in pairs(Hub._features) do
		if mod.Disable then pcall(mod.Disable, Hub) end
	end
end)

----------------------------------------------------------------------
-- 4. run the right stuff
----------------------------------------------------------------------
if entry then
	Hub:Run(Hub.GameFolder .. "init.lua")
end
if not entry or entry.universal ~= false then
	Hub:Run("universal/Misc.lua")
end

Hub:AddSettingsTab()
Hub:Notify(entry and ("Loaded: " .. entry.name) or "No game profile - universal tools only", 3)
return Hub
