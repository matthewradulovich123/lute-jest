--!strict
-- examples/sum.spec.luau — pure logic test
describe("sum", function()
	it("adds positive numbers", function()
		expect(1 + 1).toBe(2)
	end)
	it("adds negatives", function()
		expect(-2 + -3).toBe(-5)
	end)
end)
