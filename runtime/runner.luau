--!strict
-- runner.luau — Test runner. Compiles + runs a user spec under Lute,
-- with a custom `require` that maps roblox-ts module specifiers to polyfills,
-- jest-globals, and resolves relative paths.
--
-- Two modes (auto-detected by file extension/structure):
--   1. Direct .spec.luau   — global describe/it/expect; require maps @rbxts/* → polyfills
--   2. roblox-ts compiled  — code starts with `local TS = require(... "RuntimeLib")`,
--                            uses `TS.import(script, root, "TS", "math")` etc.

local fs = require("@std/fs")
local proc = require("@std/process")
local luau = require("@lute/luau")

local jest = require("./jest")
local polyfills = require("./polyfills")
local runtime_lib = require("./runtime_lib")

------------------------------------------------------------
-- Polyfill registry (specifier → table)
------------------------------------------------------------
local polyfillRegistry: { [string]: any } = {
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
	["jest-globals"]                 = jest,
	["@rbxts/jest"]                  = jest,
	["JestGlobals"]                  = jest,
}

------------------------------------------------------------
-- Globals injected into every loaded chunk
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
	return string.match(path, "(.+)/[^/]+$") or "."
end

local function normalize(path: string): string
	local parts = {}
	for seg in string.gmatch(path, "[^/]+") do
		if seg == "." then
			-- skip
		elseif seg == ".." then
			if #parts > 0 and parts[#parts] ~= ".." then table.remove(parts) else table.insert(parts, seg) end
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

-- Pre-seed the cache with the jest module so any `require("../runtime/jest")`
-- variant returns the singleton whose state the runner reports on.
do
	local scriptDir = debug.info(1, "s"):match("@?(.+)/[^/]+$") or "."
	local jestPath = scriptDir .. "/jest.luau"
	moduleCache[jestPath] = jest
end
local makeRequire

-- Load and cache a Luau file at an absolute path
local function loadModule(absPath: string): any
	if moduleCache[absPath] then return moduleCache[absPath] end
	local src = fs.readFileToString(absPath)
	local bc = luau.compile(src)
	local innerEnv = { require = makeRequire(dirname(absPath)) }
	for k, v in pairs(extraGlobals) do innerEnv[k] = v end
	local env = setmetatable(innerEnv, { __index = _G })
	local loaded = luau.load(bc, absPath, env)
	local result = loaded()
	moduleCache[absPath] = result
	return result
end

-- Sentinel object returned by `WaitForChild("RuntimeLib")` so compiled code can
-- `require()` it and get the TS runtime
local RuntimeLibSentinel = setmetatable({ __isRuntimeLib = true }, { __tostring = function() return "RuntimeLib" end })

makeRequire = function(baseDir: string)
	local function req(spec): any
		-- Handle Instance-like / sentinel requires (compiled TS code)
		if type(spec) == "table" then
			if spec.__isRuntimeLib then
				return runtime_lib.makeTS()
			end
			-- treat unknown table requires as inert
			return setmetatable({}, { __index = function() return function() end end })
		end

		-- String requires
		local hit = polyfillRegistry[spec]
		if hit ~= nil then return hit end

		-- Relative paths
		if string.sub(spec, 1, 2) == "./" or string.sub(spec, 1, 3) == "../" then
			local raw = baseDir .. "/" .. spec
			local base = normalize(raw)
			local tries = { base .. ".luau", base .. ".lua", base .. "/init.luau", base .. "/init.lua", base }
			for _, t in ipairs(tries) do
				if moduleCache[t] then return moduleCache[t] end
				if fileExists(t) then return loadModule(t) end
			end
			error("require: could not resolve " .. spec .. " (from " .. baseDir .. ")")
		end

		-- @lute/* / @std/*
		if string.sub(spec, 1, 1) == "@" then
			local ok, mod = pcall(require, spec)
			if ok then return mod end
		end

		return setmetatable({}, { __index = function() return function() end end })
	end
	return req
end

------------------------------------------------------------
-- Inject RuntimeLib sentinel into the polyfill Instance tree.
-- Compiled TS does game:GetService("RS"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib")
------------------------------------------------------------
local function makeRuntimeLibInstance()
	-- minimal Instance-like that returns the sentinel from any access; our require
	-- detects __isRuntimeLib
	return RuntimeLibSentinel
end
do
	local rs = polyfills.Services.ReplicatedStorage
	-- patch WaitForChild on rs
	local oldWFC = rs.WaitForChild
	rs.WaitForChild = function(self, name)
		if name == "rbxts_include" then
			-- return a proxy whose WaitForChild returns the RuntimeLib sentinel
			return setmetatable({}, { __index = function(_, k)
				if k == "WaitForChild" then
					return function(_, n)
						if n == "RuntimeLib" then return makeRuntimeLibInstance() end
						return setmetatable({}, { __index = function() return function() end end })
					end
				end
				return function() end
			end })
		end
		return oldWFC(self, name)
	end
end

------------------------------------------------------------
-- Main: discover spec path, configure runtime_lib, run
------------------------------------------------------------
local args = proc.args
if #args < 2 then
	print("usage: lute runner.luau <spec.luau> [--project-root <dir>] [--out-dir <dir>]")
	proc.exit(1)
end

local specPath = args[2]
if string.sub(specPath, 1, 1) ~= "/" then
	specPath = tostring(proc.cwd()) .. "/" .. specPath
end
specPath = normalize(specPath)

-- Optional flags
local projectRoot = dirname(specPath)
local outDir = "out"
local i = 3
while i <= #args do
	if args[i] == "--project-root" and args[i+1] then projectRoot = args[i+1]; i = i + 2
	elseif args[i] == "--out-dir" and args[i+1] then outDir = args[i+1]; i = i + 2
	else i = i + 1 end
end

-- Heuristic: if specPath is inside an "out/" directory, infer project root + outDir
do
	local p, d = string.match(specPath, "(.+)/([^/]+)/[^/]+%.luau$")
	if d == "out" then
		projectRoot = p
		outDir = "out"
	end
end

runtime_lib.configure({
	projectRoot = projectRoot,
	outDir = outDir,
	polyfillRegistry = polyfillRegistry,
	loadModule = loadModule,
})

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
