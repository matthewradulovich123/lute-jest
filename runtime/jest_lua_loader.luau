--!strict
-- jest_lua_loader.luau — load jest-lua (jsdotlua/jest-lua) under Lute by emulating
-- Roblox `script.Parent.X` package navigation against node_modules/@rbxts-js/.
--
-- Contract: M.load(packagesRoot) returns a `Packages` Instance-like table.
-- Then `Packages.JestGlobals` returns the loaded init.lua of jest-globals.

local fs = require("@std/fs")
local luau = require("@lute/luau")

local M = {}

local cache: { [string]: any } = {}
local extraGlobals: any = nil  -- set by configure
local packagesRoot: string = ""

-- kebab-case dirname → PascalCase Roblox name
local nameMap: { [string]: string } = {
	["luau-polyfill"]            = "LuauPolyfill",
	["promise"]                  = "Promise",
	["chalk-lua"]                = "Chalk",
	["collections"]              = "Collections",
	["console"]                  = "Console",
	["diff-sequences"]           = "DiffSequences",
	["emittery"]                 = "Emittery",
	["es7-types"]                = "ES7Types",
	["expect"]                   = "Expect",
	["instance-of"]              = "InstanceOf",
	["jest"]                     = "Jest",
	["jest-circus"]              = "JestCircus",
	["jest-config"]              = "JestConfig",
	["jest-console"]             = "JestConsole",
	["jest-core"]                = "JestCore",
	["jest-diff"]                = "JestDiff",
	["jest-each"]                = "JestEach",
	["jest-environment"]         = "JestEnvironment",
	["jest-environment-luau"]    = "JestEnvironmentLuau",
	["jest-fake-timers"]         = "JestFakeTimers",
	["jest-get-type"]            = "JestGetType",
	["jest-globals"]             = "JestGlobals",
	["jest-matcher-utils"]       = "JestMatcherUtils",
	["jest-message-util"]        = "JestMessageUtil",
	["jest-mock"]                = "JestMock",
	["jest-mock-genv"]           = "JestMockGenv",
	["jest-mock-rbx"]            = "JestMockRbx",
	["jest-reporters"]           = "JestReporters",
	["jest-runner"]              = "JestRunner",
	["jest-runtime"]             = "JestRuntime",
	["jest-snapshot"]            = "JestSnapshot",
	["jest-test-result"]         = "JestTestResult",
	["jest-types"]               = "JestTypes",
	["jest-util"]                = "JestUtil",
	["jest-validate"]            = "JestValidate",
	["luau-regexp"]              = "LuauRegexp",
	["math"]                     = "Math",
	["number"]                   = "Number",
	["path"]                     = "Path",
	["picomatch-lua"]            = "PicomatchLua",
	["pretty-format"]            = "PrettyFormat",
	["react-is"]                 = "ReactIs",
	["regexp"]                   = "RegExp",
	["string"]                   = "String",
	["timers"]                   = "Timers",
	["yargs"]                    = "Yargs",
	["boolean"]                  = "Boolean",
}

-- Reverse map (PascalCase → kebab-case dirname)
local reverseMap: { [string]: string } = {}
for k, v in pairs(nameMap) do reverseMap[v] = k end

local function fileExists(p)
	local ok, e = pcall(fs.exists, p)
	return ok and e
end

-- Load a package's init.lua and return its module value
local function loadPackage(pkgKebab: string): any
	if cache[pkgKebab] then return cache[pkgKebab] end
	local initPath = packagesRoot .. "/" .. pkgKebab .. "/src/init.lua"
	if not fileExists(initPath) then
		initPath = packagesRoot .. "/" .. pkgKebab .. "/src/init.luau"
	end
	if not fileExists(initPath) then
		-- inert mock
		local mock = setmetatable({}, { __index = function() return function() end end })
		cache[pkgKebab] = mock
		return mock
	end

	local src = fs.readFileToString(initPath)
	local bc = luau.compile(src)

	-- Build env: this script's `script` is a "ModuleScript" whose Parent is the package's `src`,
	-- whose Parent is the package dir, whose Parent is the `Packages` virtual folder.
	local pkgPascal = nameMap[pkgKebab] or pkgKebab
	local scriptObj = M._makeScript(pkgKebab, pkgPascal)

	local env = { script = scriptObj, require = M._require }
	if extraGlobals then for k, v in pairs(extraGlobals) do env[k] = v end end
	local mt = { __index = _G }
	setmetatable(env, mt)

	local fn = luau.load(bc, initPath, env)
	local ok, result = pcall(fn)
	if not ok then
		print("[jest_lua_loader] failed to load " .. pkgKebab .. ": " .. tostring(result))
		local mock = setmetatable({}, { __index = function() return function() end end })
		cache[pkgKebab] = mock
		return mock
	end
	cache[pkgKebab] = result
	return result
end

-- Build a fake `script` for a given package
function M._makeScript(pkgKebab: string, pkgPascal: string)
	local script = {}
	script.Name = "init"
	script.ClassName = "ModuleScript"

	-- Packages folder: indexed by PascalCase, returns a sentinel that, when require()'d, loads that package
	local Packages = setmetatable({}, { __index = function(_, k)
		if type(k) ~= "string" then return nil end
		local kebab = reverseMap[k] or k
		-- Return a sentinel; require(sentinel) loads it
		return setmetatable({ __isJestLuaPkg = true, _kebab = kebab, Name = k }, {
			__index = function(_, child)
				-- Sub-module access (e.g. Packages.JestGlobals.foo) — load + index
				local mod = loadPackage(kebab)
				return mod[child]
			end,
		})
	end })

	-- src folder: contains `init` (this) and other module files
	local srcFolder = setmetatable({ Name = "src", Parent = nil, ClassName = "Folder" }, {
		__index = function(_, k)
			-- script.Parent.Parent — return the package dir
			-- script.Parent.X — return a sub-module sentinel
			if k == "Parent" then return nil end
			-- look for src/<k>.lua or src/<k>.luau or src/<k>/init.lua
			local base = packagesRoot .. "/" .. pkgKebab .. "/src/" .. k
			return setmetatable({ __isRelModule = true, _path = base, Name = k }, {})
		end,
	})

	local pkgDir = setmetatable({ Name = pkgPascal, ClassName = "Folder", src = srcFolder }, {
		__index = function(_, k)
			if k == "Parent" then return Packages end
			return nil
		end,
	})
	rawset(srcFolder, "Parent", pkgDir)

	rawset(script, "Parent", srcFolder)
	-- script.Parent.Parent = pkgDir, script.Parent.Parent.Parent = Packages
	return script
end

-- Custom require for jest-lua modules
function M._require(spec)
	if type(spec) == "table" then
		if spec.__isJestLuaPkg then return loadPackage(spec._kebab) end
		if spec.__isRelModule then
			-- relative file under src/
			local tries = { spec._path .. ".lua", spec._path .. ".luau", spec._path .. "/init.lua", spec._path .. "/init.luau" }
			for _, t in ipairs(tries) do
				if cache[t] then return cache[t] end
				if fileExists(t) then
					local src = fs.readFileToString(t)
					local bc = luau.compile(src)
					-- This sub-module has no special script context; reuse globals only
					local env = { require = M._require }
					if extraGlobals then for k, v in pairs(extraGlobals) do env[k] = v end end
					setmetatable(env, { __index = _G })
					local fn = luau.load(bc, t, env)
					local ok, result = pcall(fn)
					if not ok then
						return setmetatable({}, { __index = function() return function() end end })
					end
					cache[t] = result
					return result
				end
			end
		end
		return setmetatable({}, { __index = function() return function() end end })
	end
	-- fallback to native require for @std/@lute
	return require(spec)
end

function M.configure(opts)
	packagesRoot = opts.packagesRoot
	extraGlobals = opts.extraGlobals
end

function M.load()
	-- Return the JestGlobals module
	return loadPackage("jest-globals")
end

return M
