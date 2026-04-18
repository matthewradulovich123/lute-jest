--!strict
-- examples/flamework.spec.luau — proves @flamework/networking auto-mocks don't crash
local fw = require("@flamework/networking")

describe("flamework networking polyfill", function()
	it("createEvent doesn't crash", function()
		local ev = fw.Networking.createEvent()
		expect(ev).toBeDefined()
		expect(ev.server).toBeDefined()
		expect(ev.client).toBeDefined()
	end)
	it("server event proxy supports indexing arbitrary names", function()
		local ev = fw.Networking.createEvent()
		local some_event = ev.server.some_event
		expect(some_event).toBeDefined()
		some_event:fire(1, 2, 3)  -- should not crash
	end)
end)
