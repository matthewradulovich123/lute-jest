--!strict
-- jest.luau — minimal jest-style test runtime that runs under Lute (no Roblox deps)
-- Exports: describe, it, test, expect, beforeEach, afterEach, beforeAll, afterAll, jest

local M = {}

------------------------------------------------------------
-- Internal state
------------------------------------------------------------
type Test = { name: string, fn: () -> (), file: string?, line: number? }
type Hook = () -> ()
type Suite = {
	name: string,
	tests: { Test },
	beforeEach: { Hook },
	afterEach: { Hook },
	beforeAll: { Hook },
	afterAll: { Hook },
	parent: Suite?,
	children: { Suite },
}

local rootSuite: Suite = {
	name = "",
	tests = {},
	beforeEach = {},
	afterEach = {},
	beforeAll = {},
	afterAll = {},
	parent = nil,
	children = {},
}

local currentSuite: Suite = rootSuite

------------------------------------------------------------
-- Public API: describe / it / test
------------------------------------------------------------
function M.describe(name: string, fn: () -> ())
	local suite: Suite = {
		name = name,
		tests = {},
		beforeEach = {},
		afterEach = {},
		beforeAll = {},
		afterAll = {},
		parent = currentSuite,
		children = {},
	}
	table.insert(currentSuite.children, suite)
	local prev = currentSuite
	currentSuite = suite
	fn()
	currentSuite = prev
end

function M.it(name: string, fn: () -> ())
	table.insert(currentSuite.tests, { name = name, fn = fn })
end
M.test = M.it

function M.beforeEach(fn: Hook) table.insert(currentSuite.beforeEach, fn) end
function M.afterEach(fn: Hook)  table.insert(currentSuite.afterEach,  fn) end
function M.beforeAll(fn: Hook)  table.insert(currentSuite.beforeAll,  fn) end
function M.afterAll(fn: Hook)   table.insert(currentSuite.afterAll,   fn) end

------------------------------------------------------------
-- expect()
------------------------------------------------------------
local function deepEqual(a, b): boolean
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then return false end
	end
	for k, _ in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function fmt(v): string
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do
			table.insert(parts, tostring(k) .. "=" .. tostring(x))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function makeMatchers(actual, negate: boolean)
	local function check(cond: boolean, msg: string)
		if negate then cond = not cond end
		if not cond then error(msg, 3) end
	end

	local m = {}
	function m.toBe(expected)
		check(actual == expected,
			string.format("expected %s%s to be %s", negate and "not " or "", fmt(actual), fmt(expected)))
	end
	function m.toEqual(expected)
		check(deepEqual(actual, expected),
			string.format("expected %s%s to equal %s", negate and "not " or "", fmt(actual), fmt(expected)))
	end
	function m.toBeTruthy()
		check(actual ~= nil and actual ~= false,
			string.format("expected %s%s to be truthy", negate and "not " or "", fmt(actual)))
	end
	function m.toBeFalsy()
		check(actual == nil or actual == false,
			string.format("expected %s%s to be falsy", negate and "not " or "", fmt(actual)))
	end
	function m.toBeNil()
		check(actual == nil,
			string.format("expected %s%s to be nil", negate and "not " or "", fmt(actual)))
	end
	function m.toBeDefined()
		check(actual ~= nil,
			string.format("expected %s%s to be defined", negate and "not " or "", fmt(actual)))
	end
	function m.toBeGreaterThan(n)
		check(actual > n, string.format("expected %s > %s", fmt(actual), fmt(n)))
	end
	function m.toBeLessThan(n)
		check(actual < n, string.format("expected %s < %s", fmt(actual), fmt(n)))
	end
	function m.toContain(item)
		local found = false
		if type(actual) == "table" then
			for _, v in pairs(actual) do
				if deepEqual(v, item) then found = true; break end
			end
		elseif type(actual) == "string" then
			found = string.find(actual, item, 1, true) ~= nil
		end
		check(found, string.format("expected %s to contain %s", fmt(actual), fmt(item)))
	end
	function m.toThrow(matcher)
		assert(type(actual) == "function", "expect(fn).toThrow requires a function")
		local ok, err = pcall(actual)
		if matcher == nil then
			check(not ok, "expected function to throw")
		else
			check(not ok and string.find(tostring(err), matcher, 1, true) ~= nil,
				string.format("expected function to throw matching %s, got %s", fmt(matcher), tostring(err)))
		end
	end
	function m.toHaveBeenCalled()
		assert(type(actual) == "table" and actual._isMockFn, "expect requires a jest.fn()")
		check(#actual.mock.calls > 0, "expected mock to have been called")
	end
	function m.toHaveBeenCalledTimes(n: number)
		assert(type(actual) == "table" and actual._isMockFn, "expect requires a jest.fn()")
		check(#actual.mock.calls == n,
			string.format("expected mock to have been called %d times, was %d", n, #actual.mock.calls))
	end
	function m.toHaveBeenCalledWith(...)
		assert(type(actual) == "table" and actual._isMockFn, "expect requires a jest.fn()")
		local expected = {...}
		local found = false
		for _, call in ipairs(actual.mock.calls) do
			if deepEqual(call, expected) then found = true; break end
		end
		check(found, string.format("expected mock to have been called with %s", fmt(expected)))
	end
	return m
end

function M.expect(actual)
	local matchers = makeMatchers(actual, false)
	matchers.never = makeMatchers(actual, true)
	matchers["not"] = matchers.never  -- jest uses .not

	-- Support colon-call syntax: expect(x):toBe(y) (used by roblox-ts compiled output).
	-- Wrap each matcher so the first arg (self) is dropped when it's the matchers table.
	local function wrap(orig)
		return function(a, ...)
			if a == matchers or a == matchers.never then return orig(...) end
			return orig(a, ...)
		end
	end
	for k, v in pairs(matchers) do
		if type(v) == "function" then matchers[k] = wrap(v) end
	end
	for k, v in pairs(matchers.never) do
		if type(v) == "function" then matchers.never[k] = wrap(v) end
	end
	return matchers
end

------------------------------------------------------------
-- jest.fn() — mock functions
------------------------------------------------------------
M.jest = {}

function M.jest.fn(impl)
	local mockFn
	mockFn = setmetatable({
		_isMockFn = true,
		mock = { calls = {}, results = {} },
		_impl = impl,
	}, {
		__call = function(self, ...)
			local args = {...}
			table.insert(self.mock.calls, args)
			if self._impl then
				local result = self._impl(...)
				table.insert(self.mock.results, { type = "return", value = result })
				return result
			end
			table.insert(self.mock.results, { type = "return", value = nil })
			return nil
		end,
	})
	function mockFn:mockReturnValue(v)
		self._impl = function() return v end
		return self
	end
	function mockFn:mockImplementation(fn)
		self._impl = fn
		return self
	end
	function mockFn:mockClear()
		self.mock.calls = {}
		self.mock.results = {}
		return self
	end
	return mockFn
end

------------------------------------------------------------
-- Runner
------------------------------------------------------------
local results = {
	passed = 0,
	failed = 0,
	failures = {} :: { { suite: string, test: string, error: string } },
}

local function runHooks(suite: Suite, kind: string)
	local list = suite[kind] :: { Hook }
	for _, h in ipairs(list) do h() end
end

-- collect all beforeEach/afterEach up the parent chain
local function collectHooks(suite: Suite, kind: string): { Hook }
	local chain = {}
	local s: Suite? = suite
	while s do
		for _, h in ipairs(s[kind] :: { Hook }) do
			table.insert(chain, h)
		end
		s = s.parent
	end
	-- beforeEach: parent first, then child. But we walked child→parent. Reverse for beforeEach only.
	if kind == "beforeEach" then
		local rev = {}
		for i = #chain, 1, -1 do table.insert(rev, chain[i]) end
		return rev
	end
	return chain
end

local function suitePath(suite: Suite): string
	local parts = {}
	local s: Suite? = suite
	while s and s.name ~= "" do
		table.insert(parts, 1, s.name)
		s = s.parent
	end
	return table.concat(parts, " > ")
end

local function runSuite(suite: Suite)
	runHooks(suite, "beforeAll")
	for _, t in ipairs(suite.tests) do
		local before = collectHooks(suite, "beforeEach")
		local after = collectHooks(suite, "afterEach")
		for _, h in ipairs(before) do h() end
		local ok, err = pcall(t.fn)
		for _, h in ipairs(after) do h() end
		local label = suitePath(suite)
		local prefix = label ~= "" and (label .. " > ") or ""
		if ok then
			results.passed += 1
			print("  \27[32m✓\27[0m " .. prefix .. t.name)
		else
			results.failed += 1
			table.insert(results.failures, { suite = label, test = t.name, error = tostring(err) })
			print("  \27[31m✗\27[0m " .. prefix .. t.name)
			print("    \27[31m" .. tostring(err) .. "\27[0m")
		end
	end
	for _, child in ipairs(suite.children) do
		runSuite(child)
	end
	runHooks(suite, "afterAll")
end

function M._run(): boolean
	print("")
	runSuite(rootSuite)
	print("")
	print(string.format("\27[1mTests: \27[32m%d passed\27[0m, \27[31m%d failed\27[0m, \27[1m%d total",
		results.passed, results.failed, results.passed + results.failed))
	return results.failed == 0
end

function M._reset()
	rootSuite = {
		name = "", tests = {}, beforeEach = {}, afterEach = {},
		beforeAll = {}, afterAll = {}, parent = nil, children = {},
	}
	currentSuite = rootSuite
	results = { passed = 0, failed = 0, failures = {} }
end

return M
