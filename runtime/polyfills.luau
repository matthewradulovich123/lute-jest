--!strict
-- polyfills.luau — ALL roblox-ts polyfills in ONE file, no inter-polyfill requires.
-- Returns: { Services, Instance, Signal, Vector3, Vector2, UDim, UDim2, Color3, CFrame, Enum,
--            game, workspace, task, flameworkNetworking, ... }

local M = {}

------------------------------------------------------------
-- Signal (RBXScriptSignal)
------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _h = {} }, Signal)
end
function Signal:Connect(fn)
	local conn
	conn = { Connected = true, Disconnect = function(c)
		c.Connected = false
		for i, h in ipairs(self._h) do if h == fn then table.remove(self._h, i); break end end
	end }
	table.insert(self._h, fn); return conn
end
function Signal:Once(fn)
	local conn; conn = self:Connect(function(...) conn:Disconnect(); fn(...) end); return conn
end
function Signal:Fire(...)
	for _, h in ipairs(self._h) do pcall(h, ...) end
end
function Signal:Wait() error("Signal:Wait() not supported in lute-jest", 2) end
M.Signal = Signal

------------------------------------------------------------
-- Instance
------------------------------------------------------------
local Instance = {}
function Instance.new(className, parent)
	local self
	self = {
		ClassName = className,
		Name = className,
		Parent = nil,
		_children = {},
		_attributes = {},
		Archivable = true,
		ChildAdded = Signal.new(),
		ChildRemoved = Signal.new(),
		AncestryChanged = Signal.new(),
		Destroying = Signal.new(),
	}
	function self:GetChildren()
		local out = {}; for i, c in ipairs(self._children) do out[i] = c end; return out
	end
	function self:GetDescendants()
		local out = {}
		local function walk(n) for _, c in ipairs(n._children) do table.insert(out, c); walk(c) end end
		walk(self); return out
	end
	function self:FindFirstChild(name)
		for _, c in ipairs(self._children) do if c.Name == name then return c end end
		return nil
	end
	function self:FindFirstChildOfClass(cn)
		for _, c in ipairs(self._children) do if c.ClassName == cn then return c end end
		return nil
	end
	function self:WaitForChild(name, _t) return self:FindFirstChild(name) end
	function self:IsA(cn) return self.ClassName == cn end
	function self:Destroy()
		self.Destroying:Fire()
		if self.Parent then
			for i, c in ipairs(self.Parent._children) do if c == self then table.remove(self.Parent._children, i); break end end
		end
		self.Parent = nil
	end
	function self:Clone()
		local c = Instance.new(self.ClassName); c.Name = self.Name; return c
	end
	function self:GetAttribute(k) return self._attributes[k] end
	function self:SetAttribute(k, v) self._attributes[k] = v end
	function self:GetAttributes() return self._attributes end
	if parent then
		self.Parent = parent
		if type(parent) == "table" and parent._children then
			table.insert(parent._children, self)
		end
	end
	return self
end
M.Instance = Instance

------------------------------------------------------------
-- Vector3
------------------------------------------------------------
local Vector3mt = {}
Vector3mt.__index = Vector3mt
Vector3mt.__add = function(a, b) return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3mt.__sub = function(a, b) return M.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3mt.__mul = function(a, b)
	if type(b) == "number" then return M.Vector3.new(a.X*b, a.Y*b, a.Z*b) end
	if type(a) == "number" then return M.Vector3.new(b.X*a, b.Y*a, b.Z*a) end
	return M.Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
Vector3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3mt.__tostring = function(v) return string.format("Vector3(%g, %g, %g)", v.X, v.Y, v.Z) end
function Vector3mt:Dot(o) return self.X*o.X + self.Y*o.Y + self.Z*o.Z end
function Vector3mt:Cross(o)
	return M.Vector3.new(self.Y*o.Z - self.Z*o.Y, self.Z*o.X - self.X*o.Z, self.X*o.Y - self.Y*o.X)
end
function Vector3mt:Lerp(o, a)
	return M.Vector3.new(self.X + (o.X-self.X)*a, self.Y + (o.Y-self.Y)*a, self.Z + (o.Z-self.Z)*a)
end
local function newVec3(x, y, z, withUnit)
	local v = setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3mt)
	v.Magnitude = math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z)
	if withUnit ~= false and v.Magnitude > 0 then
		v.Unit = newVec3(v.X/v.Magnitude, v.Y/v.Magnitude, v.Z/v.Magnitude, false)
	else
		v.Unit = v
	end
	return v
end
M.Vector3 = { new = function(x, y, z) return newVec3(x, y, z, true) end }
M.Vector3.zero = M.Vector3.new(0,0,0)
M.Vector3.one = M.Vector3.new(1,1,1)
M.Vector3.xAxis = M.Vector3.new(1,0,0)
M.Vector3.yAxis = M.Vector3.new(0,1,0)
M.Vector3.zAxis = M.Vector3.new(0,0,1)

------------------------------------------------------------
-- Vector2
------------------------------------------------------------
local Vector2mt = {}; Vector2mt.__index = Vector2mt
Vector2mt.__add = function(a, b) return M.Vector2.new(a.X + b.X, a.Y + b.Y) end
Vector2mt.__sub = function(a, b) return M.Vector2.new(a.X - b.X, a.Y - b.Y) end
Vector2mt.__eq  = function(a, b) return a.X == b.X and a.Y == b.Y end
M.Vector2 = { new = function(x, y)
	local v = setmetatable({ X = x or 0, Y = y or 0 }, Vector2mt)
	v.Magnitude = math.sqrt(v.X*v.X + v.Y*v.Y); return v
end }

------------------------------------------------------------
-- UDim / UDim2 / Color3 / CFrame / Enum
------------------------------------------------------------
M.UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
M.UDim2 = {
	new = function(xs, xo, ys, yo)
		return { X = M.UDim.new(xs, xo), Y = M.UDim.new(ys, yo),
		         Width = M.UDim.new(xs, xo), Height = M.UDim.new(ys, yo) }
	end,
	fromScale  = function(xs, ys) return M.UDim2.new(xs, 0, ys, 0) end,
	fromOffset = function(xo, yo) return M.UDim2.new(0, xo, 0, yo) end,
}
M.Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromRGB = function(r, g, b) return { R = (r or 0)/255, G = (g or 0)/255, B = (b or 0)/255 } end,
	fromHSV = function(h, s, v) return { R = v, G = v, B = v } end,
}
local CFmt = {}; CFmt.__index = CFmt
CFmt.__mul = function(a, b)
	if type(b) == "table" and b.X ~= nil and b.Magnitude then
		return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	return M.CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
M.CFrame = {
	new = function(x, y, z)
		if type(x) == "table" and x.X ~= nil then
			local s = setmetatable({ X = x.X, Y = x.Y, Z = x.Z, Position = x }, CFmt); return s
		end
		local s = setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, CFmt)
		s.Position = M.Vector3.new(s.X, s.Y, s.Z); return s
	end,
	lookAt = function(from, _to) return M.CFrame.new(from.X, from.Y, from.Z) end,
}
M.CFrame.identity = M.CFrame.new(0,0,0)
M.Enum = setmetatable({}, { __index = function(_, k)
	return setmetatable({}, { __index = function(_, kk) return { Name = kk, Value = 0, EnumType = k } end })
end })

------------------------------------------------------------
-- Services + game
------------------------------------------------------------
local services = {}
local function makeService(name)
	if services[name] then return services[name] end
	local s = Instance.new(name); s.Name = name; services[name] = s; return s
end
local KNOWN = { "Workspace","Players","Lighting","ReplicatedStorage","ReplicatedFirst",
	"ServerStorage","ServerScriptService","StarterPlayer","StarterGui","StarterPack","Teams",
	"SoundService","TweenService","RunService","UserInputService","ContextActionService",
	"HttpService","DataStoreService","MemoryStoreService","MessagingService","TextService",
	"MarketplaceService","BadgeService","GroupService","PolicyService","Chat","TextChatService",
	"PathfindingService","PhysicsService","CollectionService","Debris","GamePassService",
	"GuiService","TeleportService","Stats" }
for _, n in ipairs(KNOWN) do makeService(n) end

M.Services = setmetatable({}, { __index = function(_, k) return makeService(k) end })
for _, n in ipairs(KNOWN) do rawset(M.Services, n, services[n]) end

M.game = setmetatable({
	GetService = function(_, name) return makeService(name) end,
	Workspace = services.Workspace,
	Players = services.Players,
}, { __index = function(_, k) return makeService(k) end })

------------------------------------------------------------
-- task
------------------------------------------------------------
M.task = {
	spawn = function(fn, ...) local a = {...}; coroutine.wrap(function() fn(table.unpack(a)) end)() end,
	defer = function(fn, ...) local a = {...}; coroutine.wrap(function() fn(table.unpack(a)) end)() end,
	delay = function(_, fn, ...) local a = {...}; fn(table.unpack(a)) end,
	wait  = function(_) return 0 end,
}

------------------------------------------------------------
-- Flamework networking (mock that swallows everything)
------------------------------------------------------------
local function makeEvent()
	local handlers = {}
	return setmetatable({}, { __index = {
		connect = function(_, fn) table.insert(handlers, fn); return { Disconnect = function() end } end,
		fire = function(_, ...) for _, h in ipairs(handlers) do pcall(h, ...) end end,
		broadcast = function(_, ...) for _, h in ipairs(handlers) do pcall(h, ...) end end,
		predict = function() end,
	} })
end
local function makeFunction()
	local cb = function() end
	return setmetatable({}, { __index = {
		setCallback = function(_, fn) cb = fn end,
		invoke = function(_, ...) return cb(...) end,
	} })
end
local serverProxy = setmetatable({}, { __index = function() return makeEvent() end })
local clientProxy = setmetatable({}, { __index = function() return makeEvent() end })
M.flamework_networking = {
	Networking = {
		createEvent = function() return { server = serverProxy, client = clientProxy } end,
		createFunction = function() return { server = serverProxy, client = clientProxy } end,
	},
	GlobalEvents = { server = serverProxy, client = clientProxy },
	GlobalFunctions = {
		server = setmetatable({}, { __index = function() return makeFunction() end }),
		client = setmetatable({}, { __index = function() return makeFunction() end }),
	},
}
M.flamework_core = {
	Flamework = { addPaths = function() end, ignite = function() end, id = function() return "" end },
}

------------------------------------------------------------
-- Misc roblox-ts utility libs
------------------------------------------------------------
M.t = setmetatable({}, { __index = function() return function() return true end end })
M.sift = {
	Array = { copy = function(t) local o={}; for i,v in ipairs(t) do o[i]=v end; return o end },
	Dictionary = { copy = function(t) local o={}; for k,v in pairs(t) do o[k]=v end; return o end },
}
M.charm = {
	atom = function(initial)
		local v = initial
		return setmetatable({}, { __call = function(_, new) if new ~= nil then v = new end; return v end })
	end,
}
M.charm_sync = {
	server = setmetatable({}, { __index = function() return function() end end }),
	client = setmetatable({}, { __index = function() return function() end end }),
}

return M
