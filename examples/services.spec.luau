--!strict
-- examples/services.spec.luau — proves @rbxts/services is mocked
local services = require("@rbxts/services")

describe("services polyfill", function()
	it("exposes Workspace", function()
		expect(services.Workspace).toBeDefined()
		expect(services.Workspace.ClassName).toBe("Workspace")
	end)
	it("exposes ReplicatedStorage", function()
		expect(services.ReplicatedStorage.Name).toBe("ReplicatedStorage")
	end)
	it("returns mock for any service name", function()
		local custom = services.SomeMadeUpService
		expect(custom).toBeDefined()
		expect(custom.ClassName).toBe("SomeMadeUpService")
	end)
	it("Instance.new produces tables with methods", function()
		local part = Instance.new("Part")
		part.Name = "TestPart"
		expect(part.Name).toBe("TestPart")
		expect(part:IsA("Part")).toBe(true)
		expect(part:GetChildren()).toEqual({})
	end)
end)

describe("game global", function()
	it("GetService works", function()
		local rs = game:GetService("ReplicatedStorage")
		expect(rs.ClassName).toBe("ReplicatedStorage")
	end)
end)
