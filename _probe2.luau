local t = setmetatable({}, {
	__index = function(_, k)
		print("idx called with", k)
		return setmetatable({ x = 1 }, { __index = function(_, kk) print("inner", kk); return nil end })
	end,
})
local v = t.foo
print("v", v, "v.bar", v.bar)
