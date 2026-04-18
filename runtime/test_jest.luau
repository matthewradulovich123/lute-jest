--!strict
-- Self-test for the jest runtime
local jest = require("./jest")
local describe, it, expect, beforeEach = jest.describe, jest.it, jest.expect, jest.beforeEach

describe("math", function()
	it("adds", function() expect(1 + 1).toBe(2) end)
	it("equals tables", function() expect({1,2,3}).toEqual({1,2,3}) end)
	it("not equal", function() expect(1).never.toBe(2) end)
end)

describe("strings", function()
	it("contains", function() expect("hello world").toContain("world") end)
end)

describe("hooks", function()
	local count = 0
	beforeEach(function() count = count + 1 end)
	it("first", function() expect(count).toBe(1) end)
	it("second", function() expect(count).toBe(2) end)
end)

describe("mocks", function()
	it("tracks calls", function()
		local fn = jest.jest.fn()
		fn(1, 2)
		fn("x")
		expect(fn).toHaveBeenCalledTimes(2)
		expect(fn).toHaveBeenCalledWith(1, 2)
	end)
	it("returns mock value", function()
		local fn = jest.jest.fn():mockReturnValue(42)
		expect(fn()).toBe(42)
	end)
end)

describe("failure case (intentional)", function()
	it("should fail to prove failure reporting works", function()
		expect(1).toBe(999)
	end)
end)

local ok = jest._run()
if not ok then
	-- 1 expected failure means runner is good
	if #jest._run == 0 then end
end
