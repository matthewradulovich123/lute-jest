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
	["react-globals"]            = "ReactGlobals",
	["roblox-lua-promise"]       = "Promise",
	["roblox-shared"]            = "RobloxShared",
	["safe-flags"]               = "SafeFlags",
	["shared"]                   = "Shared",
	["symbol-luau"]              = "Symbol",
	["test-utils"]               = "TestUtils",
	["throat"]                   = "Throat",
	-- jest-roblox-shared exists too
	["jest-roblox-shared"]       = "JestRobloxShared",
}

-- Reverse map (PascalCase → kebab-case dirname)
local reverseMap: { [string]: string } = {}
for k, v in pairs(nameMap) do reverseMap[v] = k end

local fileExists  -- forward decl
local existsSet: { [string]: boolean } = {}

fileExists = function(p)
	return existsSet[p] == true
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
	local script
	-- script.X resolves to a sibling file in the package's src/ dir.
	-- e.g. boolean/src/init.lua: require(script.toJSBoolean) → src/toJSBoolean.lua
	script = setmetatable({ Name = "init", ClassName = "ModuleScript" }, {
		__index = function(_, k)
			if k == "Parent" then return rawget(script, "_Parent") end
			if type(k) ~= "string" then return nil end
			local base = packagesRoot .. "/" .. pkgKebab .. "/src/" .. k
			return setmetatable({ __isRelModule = true, _path = base, _pkgKebab = pkgKebab, _pkgPascal = pkgPascal, Name = k }, {})
		end,
	})

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

	-- src folder: contains `init` (this) and other module files.
	-- If `src/<k>` doesn't exist locally, fall back to the global package map.
	-- This emulates Wally/Rojo's flat Packages/ folder where all sibling packages
	-- get materialized into one directory at build time.
	local srcFolder = setmetatable({ Name = "src", Parent = nil, ClassName = "Folder" }, {
		__index = function(_, k)
			if k == "Parent" then return nil end
			if type(k) ~= "string" then return nil end
			-- Try local file first
			local base = packagesRoot .. "/" .. pkgKebab .. "/src/" .. k
			local hasLocal = fileExists(base .. ".lua") or fileExists(base .. ".luau")
				or fileExists(base .. "/init.lua") or fileExists(base .. "/init.luau")
			if hasLocal then
				return setmetatable({ __isRelModule = true, _path = base, _pkgKebab = pkgKebab, _pkgPascal = pkgPascal, Name = k }, {})
			end
			-- Fall back to global package map (PascalCase → kebab)
			local kebab = reverseMap[k]
			if kebab and fileExists(packagesRoot .. "/" .. kebab .. "/src/init.lua") then
				return setmetatable({ __isJestLuaPkg = true, _kebab = kebab, Name = k }, {
					__index = function(_, child)
						local mod = loadPackage(kebab)
						return mod[child]
					end,
				})
			end
			return nil
		end,
		__call = function(_, ...) return nil end,
	})

	local pkgDir = setmetatable({ Name = pkgPascal, ClassName = "Folder", src = srcFolder }, {
		__index = function(_, k)
			if k == "Parent" then return Packages end
			return nil
		end,
	})
	rawset(srcFolder, "Parent", pkgDir)

	rawset(script, "_Parent", srcFolder)
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
					-- Build a script for this sub-module.
					local pkgKebab = spec._pkgKebab
					local pkgPascal = spec._pkgPascal
					-- The script's "directory" is where its siblings live:
					-- If t ends in /init.lua, dir = parent (Array/init.lua → dir = Array)
					-- Otherwise dir = file's parent
					local scriptDir
					if t:sub(-9) == "/init.lua" or t:sub(-10) == "/init.luau" then
						scriptDir = spec._path  -- e.g. .../Array (the directory containing init.lua)
					else
						-- file like .../toJSBoolean.lua — dir is parent dir
						scriptDir = spec._path:match("(.+)/[^/]+$") or spec._path
					end
					local subScript
					subScript = setmetatable({ Name = spec.Name, ClassName = "ModuleScript" }, {
						__index = function(_, k)
							if k == "Parent" then
								-- Parent is the directory above scriptDir, which is *another* virtual
								-- folder. For sub-sub-modules, we keep walking up via Parent.Parent etc.
								return M._makeFolder(packagesRoot, pkgKebab, pkgPascal, scriptDir:match("(.+)/[^/]+$") or scriptDir)
							end
							if type(k) ~= "string" then return nil end
							-- siblings of this script (children if init.lua)
							local base = scriptDir .. "/" .. k
							return setmetatable({ __isRelModule = true, _path = base, _pkgKebab = pkgKebab, _pkgPascal = pkgPascal, Name = k }, {})
						end,
					})
					local env = { script = subScript, require = M._require }
					if extraGlobals then for k, v in pairs(extraGlobals) do env[k] = v end end
					setmetatable(env, { __index = _G })
					local fn = luau.load(bc, t, env)
					local ok, result = pcall(fn)
					if not ok then
						print("[jest_lua_loader] sub-module load failed: " .. t .. ": " .. tostring(result))
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

-- Build a folder Instance-like object for a directory under a package's src/.
-- Used when a sub-module asks for script.Parent.
function M._makeFolder(pkgsRoot: string, pkgKebab: string, pkgPascal: string, dirPath: string)
	local folder
	local srcDir = pkgsRoot .. "/" .. pkgKebab .. "/src"
	folder = setmetatable({ Name = dirPath:match("([^/]+)$") or "src", ClassName = "Folder" }, {
		__index = function(_, k)
			if k == "Parent" then
				-- Once at or above src, all .Parent walks land in the virtual Packages folder.
				if #dirPath <= #srcDir then
					return M._makePackagesFolder()
				end
				local up = dirPath:match("(.+)/[^/]+$") or dirPath
				return M._makeFolder(pkgsRoot, pkgKebab, pkgPascal, up)
			end
			if type(k) ~= "string" then return nil end
			-- Lookup as a child file/dir of dirPath
			local base = dirPath .. "/" .. k
			local hasLocal = fileExists(base .. ".lua") or fileExists(base .. ".luau")
				or fileExists(base .. "/init.lua") or fileExists(base .. "/init.luau")
			if hasLocal then
				return setmetatable({ __isRelModule = true, _path = base, _pkgKebab = pkgKebab, _pkgPascal = pkgPascal, Name = k }, {})
			end
			-- Cross-package fallback
			local kebab = reverseMap[k]
			if kebab and fileExists(packagesRoot .. "/" .. kebab .. "/src/init.lua") then
				return setmetatable({ __isJestLuaPkg = true, _kebab = kebab, Name = k }, {
					__index = function(_, child)
						local mod = loadPackage(kebab)
						return mod[child]
					end,
				})
			end
			return nil
		end,
	})
	return folder
end

function M._makePackagesFolder()
	local pf
	pf = setmetatable({ Name = "Packages", ClassName = "Folder" }, { __index = function(_, k)
		if k == "Parent" then return pf end  -- Packages.Parent → self (avoid nil chain breaks)
		if type(k) ~= "string" then return nil end
		local kebab = reverseMap[k] or k
		return setmetatable({ __isJestLuaPkg = true, _kebab = kebab, Name = k }, {
			__index = function(_, child)
				local mod = loadPackage(kebab)
				return mod[child]
			end,
		})
	end })
	return pf
end

function M.configure(opts)
	packagesRoot = opts.packagesRoot
	extraGlobals = opts.extraGlobals
	-- Pre-enumerate filesystem so __index metamethods (which can't yield) can
	-- check existence with O(1) table lookups instead of fs.exists() calls.
	existsSet = {}
	local stack = { packagesRoot }
	while #stack > 0 do
		local dir = table.remove(stack)
		local okList, entries = pcall(fs.listDirectory, dir)
		if okList and entries then
			for _, entry in ipairs(entries) do
				local p = dir .. "/" .. entry.name
				existsSet[p] = true
				if entry.type == "dir" then
					table.insert(stack, p)
				end
			end
		end
	end
end

function M.load()
	-- Return the JestGlobals module
	return loadPackage("jest-globals")
end

return M
