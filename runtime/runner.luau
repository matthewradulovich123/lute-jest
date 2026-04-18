--!strict
-- runner.luau — Test runner. Compiles + runs a user spec under Lute,
-- with a custom `require` that maps roblox-ts module specifiers to polyfills,
-- jest-globals, and resolves relative paths.
--
-- Usage: lute runner.luau <abs_spec_path>

local fs = require("@std/fs")
local proc = require("@std/process")
local luau = require("@lute/luau")

local jest = require("./jest")
local polyfills = require("./polyfills")

------------------------------------------------------------
-- Build the polyfill registry (module specifier -> table)
------------------------------------------------------------
local registry: { [string]: any } = {
	["@rbxts/services"]              = polyfills.Services,
	["@rbxts/Services"]              = polyfills.Services,
	["@rbxts/datatypes"]             = polyfills,
	["@flamework/networking"]        = polyfills.flamework_networking,
	["@flamework/core"]              = polyfills.flamework_core,
	["@rbxts/flamework"]             = polyfills.flamework_core,
	["@rbxts/t"]                     = polyfills.t,
	["@rbxts/sift"]                  = polyfills.sift,
	["@rbxts/charm"]                 = polyfills.charm,
	["@rbxts/charm-sync"]            = polyfills.charm_sync,
	["@rbxts/jest-globals"]          = jest,
	["@rbxts/jest"]                  = jest,
	["JestGlobals"]                  = jest,
}

------------------------------------------------------------
-- Globals to inject into every loaded chunk
------------------------------------------------------------
local extraGlobals = {
	Vector3 = polyfills.Vector3,
	Vector2 = polyfills.Vector2,
	UDim    = polyfills.UDim,
	UDim2   = polyfills.UDim2,
	Color3  = polyfills.Color3,
	CFrame  = polyfills.CFrame,
	Enum    = polyfills.Enum,
	Instance = polyfills.Instance,
	game    = polyfills.game,
	workspace = polyfills.game.Workspace,
	task    = polyfills.task,
}

------------------------------------------------------------
-- Path helpers
------------------------------------------------------------
local function dirname(path: string): string
	local d = string.match(path, "(.+)/[^/]+$")
	return d or "."
end

local function normalize(path: string): string
	-- Resolve "/./" and "/../" segments
	local parts = {}
	for seg in string.gmatch(path, "[^/]+") do
		if seg == "." then
			-- skip
		elseif seg == ".." then
			if #parts > 0 and parts[#parts] ~= ".." then
				table.remove(parts)
			else
				table.insert(parts, seg)
			end
		else
			table.insert(parts, seg)
		end
	end
	local prefix = string.sub(path, 1, 1) == "/" and "/" or ""
	return prefix .. table.concat(parts, "/")
end

local function fileExists(p: string): boolean
	local ok, exists = pcall(fs.exists, p)
	return ok and exists
end

------------------------------------------------------------
-- Module cache + per-module require factory
------------------------------------------------------------
local moduleCache: { [string]: any } = {}

local makeRequire
makeRequire = function(baseDir: string)
	local function req(spec: string): any
		-- Registry hit
		local hit = registry[spec]
		if hit ~= nil then return hit end

		-- Relative path
		if string.sub(spec, 1, 2) == "./" or string.sub(spec, 1, 3) == "../" then
			local raw = baseDir .. "/" .. spec
			local base = normalize(raw)
			local tries = { base .. ".luau", base .. ".lua", base .. "/init.luau", base .. "/init.lua", base }
			for _, t in ipairs(tries) do
				if moduleCache[t] then return moduleCache[t] end
				if fileExists(t) then
					local src = fs.readFileToString(t)
					local bc = luau.compile(src)
					local innerEnv = { require = makeRequire(dirname(t)) }
					for k, v in pairs(extraGlobals) do innerEnv[k] = v end
					local env = setmetatable(innerEnv, { __index = _G })
					local loaded = luau.load(bc, t, env)
					local result = loaded()
					moduleCache[t] = result
					return result
				end
			end
			error("require: could not resolve " .. spec .. " (from " .. baseDir .. ")")
		end

		-- @lute/* / @std/* — passthrough to native require
		if string.sub(spec, 1, 1) == "@" then
			local ok, mod = pcall(require, spec)
			if ok then return mod end
		end

		-- Unknown bare module: return inert mock so test bootstrap doesn't crash
		local mock = setmetatable({}, { __index = function() return function() end end })
		return mock
	end
	return req
end

------------------------------------------------------------
-- Main: compile + execute the spec
------------------------------------------------------------
local args = proc.args
if #args < 2 then
	print("usage: lute runner.luau <spec.luau>")
	proc.exit(1)
end

local specPath = args[2]
if string.sub(specPath, 1, 1) ~= "/" then
	specPath = tostring(proc.cwd()) .. "/" .. specPath
end
specPath = normalize(specPath)

local source = fs.readFileToString(specPath)
local bc = luau.compile(source)

local envBase = {
	require    = makeRequire(dirname(specPath)),
	describe   = jest.describe,
	it         = jest.it,
	test       = jest.test,
	expect     = jest.expect,
	beforeEach = jest.beforeEach,
	afterEach  = jest.afterEach,
	beforeAll  = jest.beforeAll,
	afterAll   = jest.afterAll,
	jest       = jest.jest,
}
for k, v in pairs(extraGlobals) do envBase[k] = v end
local env = setmetatable(envBase, { __index = _G })

local loaded = luau.load(bc, specPath, env)
loaded()

local ok = jest._run()
proc.exit(ok and 0 or 1)
