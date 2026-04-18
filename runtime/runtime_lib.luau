--!strict
-- runtime_lib.luau — provides a roblox-ts-compatible `TS` table for compiled output.
-- Returned by RuntimeLib in the require redirector.
--
-- Usage from runner:
--   local rl = require("./runtime_lib")
--   rl.configure({ projectRoot = "/path/to/project", outDir = "out", jestModule = jest })
--   rl.makeTS() -> returns the TS table that compiled code requires

local fs = require("@std/fs")
local luau = require("@lute/luau")

local M = {}

local config = {
	projectRoot = ".",
	outDir = "out",
	jestModule = nil,
	polyfillRegistry = {},  -- e.g. { ["jest-globals"] = jest, ["services"] = services }
	loadModule = nil,       -- function(absPath) -> module table  (set by runner)
	extraGlobals = {},
}

function M.configure(c)
	for k, v in pairs(c) do config[k] = v end
end

local function fileExists(p)
	local ok, exists = pcall(fs.exists, p)
	return ok and exists
end

local function resolvePath(parts: { string }): (string?, any?)
	-- parts is the list after (script, root). e.g. {"TS", "math"} or
	-- {"rbxts_include", "node_modules", "@rbxts", "jest-globals", "index"}
	if #parts == 0 then return nil, nil end

	-- @rbxts polyfills
	if parts[1] == "rbxts_include" and parts[2] == "node_modules" and parts[3] == "@rbxts" then
		local pkgName = parts[4]
		-- direct hit in registry?
		local reg = config.polyfillRegistry["@rbxts/" .. pkgName]
		if reg ~= nil then return nil, reg end
		-- alt name
		reg = config.polyfillRegistry[pkgName]
		if reg ~= nil then return nil, reg end
		-- inert mock so unknown packages don't crash
		return nil, setmetatable({}, { __index = function() return function() end end })
	end

	-- @flamework / @rbxts other paths
	if parts[1] == "rbxts_include" and parts[3] == "@flamework" then
		local pkgName = parts[4]
		return nil, config.polyfillRegistry["@flamework/" .. pkgName] or {}
	end

	-- Compiled TS code: ("TS", ...rest) -> outDir/rest.luau
	if parts[1] == "TS" then
		local rest = {}
		for i = 2, #parts do rest[#rest + 1] = parts[i] end
		local rel = table.concat(rest, "/")
		local abs = config.projectRoot .. "/" .. config.outDir .. "/" .. rel .. ".luau"
		if fileExists(abs) then return abs, nil end
		-- maybe it's a directory module
		abs = config.projectRoot .. "/" .. config.outDir .. "/" .. rel .. "/init.luau"
		if fileExists(abs) then return abs, nil end
		error("TS.import: cannot find " .. rel .. " under " .. config.outDir)
	end

	-- Unknown: return inert mock
	return nil, setmetatable({}, { __index = function() return function() end end })
end

function M.makeTS()
	local TS = {}

	function TS.import(_script, _root, ...)
		local parts = { ... }
		local path, mod = resolvePath(parts)
		if mod ~= nil then return mod end
		if path then
			return config.loadModule(path)
		end
		return nil
	end

	-- Some roblox-ts helpers
	function TS.async(fn) return fn end
	function TS.await(promise) return promise end
	TS.Promise = nil  -- fill if needed

	return TS
end

return M
