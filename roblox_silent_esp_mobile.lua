--[[==========================================================
  Zaka | Silent Aim + ESP  (Mobile / PC)   v3.0
  ----------------------------------------------------------
  Silent Aim : 不动视角, 只改写射线/远程事件的朝向, 命中目标
  ESP        : 纯 Roblox 原生 GUI, 不用 Drawing, 不掉帧, 无 FOV 圈
  用法       : 全选复制 -> 丢执行器 -> Execute
  卸载       : 面板上 UNLOAD 按钮, 或执行  _G.ZakaSXUnload()
  PC 热键    : RightAlt = Silent 开关 | RightShift = ESP 开关 | End 卸载
  面板标签用英文, 避免执行器缺中文字体显示成 ????
==========================================================]]--

if _G.ZakaSXUnload then pcall(_G.ZakaSXUnload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- ======================= 执行器能力探测 =======================
local RAWMT      = getrawmetatable
local SETRO      = setreadonly
local NCC        = newcclosure
local GNCM       = getnamecallmethod
local CHKCALLER  = checkcaller
local GETGENV    = getgenv

local function wrap(f)
	if type(NCC) == "function" then
		local ok, r = pcall(NCC, f)
		if ok and type(r) == "function" then return r end
	end
	return f
end

local function log(...)
	local ok = pcall(function()
		if type(printconsole) == "function" then printconsole(...) else print(...) end
	end)
	if not ok then pcall(print, ...) end
end

local trace = function() end
pcall(function()
	local env = type(GETGENV) == "function" and GETGENV() or nil
	if env then
		env.zakaLog = env.zakaLog or function() end
		trace = env.zakaLog
	end
end)

-- ============================ 配置区 ============================
local CFG = {
	ESP = {
		Enabled   = true,
		Box       = true,
		Name      = true,
		Dist      = true,
		Health    = true,
		Tracer    = false,
		TeamCheck = true,
		MaxDist   = 1200,
		TextSize  = 13,
		BoxColor    = Color3.fromRGB(255, 62, 62),
		LockColor   = Color3.fromRGB(255, 210, 40),
		HealthColor = Color3.fromRGB(70, 255, 100),
		TracerColor = Color3.fromRGB(255, 62, 62),
	},

	-- 相机转向式自瞄 (会动视角), 默认关; silent 才是主力
	AIM = {
		Enabled     = false,
		Part        = "Head",
		Smooth      = 0.16,
		Radius      = 260,
		MaxDist     = 900,
		TeamCheck   = true,
		Visible     = true,
		Predict     = true,
		PredictAmt  = 0.14,
		LockMarker  = true,
		PauseOnTouch = true,
	},

	-- 静默自瞄: 不动视角, 改射线/远程朝向
	SILENT = {
		Enabled    = true,
		Part       = "Head",
		FOV        = 400,          -- 屏幕像素半径选目标, 9999 = 全屏
		CenterMode = "Auto",       -- Auto / Screen / Mouse
		MaxDist    = 1600,
		TeamCheck  = true,
		Visible    = false,        -- 隔墙不锁 (自己发的射线, 关着更快)
		Predict    = false,
		PredictAmt = 0.14,
		Sticky     = 0.25,         -- 目标粘性(秒), 防止锁一下跳一下
		Marker     = true,         -- 锁定时在目标头顶打十字
		MinOriginDist = 100,       -- origin 离相机超过这个距离就不认(防误判坐标参数)
	},

	HOOK = {
		Namecall   = true,         -- 主入口: workspace:Raycast / FindPartOnRay*
		Cached     = true,         -- 游戏把 workspace.Raycast 存成局部变量
		Camera     = true,         -- Camera:ViewportPointToRay / ScreenPointToRay
		Mouse      = false,        -- Mouse.UnitRay / Hit (手机不用)
		Remote     = true,         -- 远程事件朝向改写(很多游戏靠这个才算命中)
		RemoteAll  = false,        -- 关 = 只改名字像射击的 remote
		RemoteCFrame = false,      -- 有些游戏传 CFrame 朝向, 开了才改(默认关, 免得误伤)
		RemoteNames = {
			"aim", "fire", "shoot", "shot", "hit", "ray", "attack", "mouse",
			"dir", "bullet", "gun", "weapon", "trace", "damage", "cast",
			"projectile", "laser", "target", "click",
		},
		UseCheckCaller = false,    -- 有些执行器里开了会失效, 默认关
	},

	MISC = {
		PanelOpen  = true,
		UpdateRate = 1 / 60,
		ShowStats  = true,
	},
}
-- ==============================================================

-- ============================ 运行状态 ============================
local RUNNING = true
local SILENT_ON = CFG.SILENT.Enabled
local ESP_INPUT_ON = CFG.ESP.Enabled
local HOLD = false

local STATS = { ray = 0, rem = 0, rayTotal = 0, remTotal = 0, tgt = "-", mode = "-" }

local BUSY = false                 -- 我们自己发的射线, 不要被自己改
local curTarget = nil              -- { plr=, pos=, part= }
local curTargetAt = 0

local function now()
	return os.clock()
end

local function silentActive()
	if not RUNNING or not CFG.SILENT.Enabled then return false end
	return SILENT_ON or HOLD
end

-- ============================ GUI 骨架 ============================
local gui = Instance.new("ScreenGui")
gui.Name = "ZakaSilentESP"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9998
do
	local ok = pcall(function()
		gui.Parent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
	end)
	if not ok then pcall(function() gui.Parent = LP:WaitForChild("PlayerGui", 5) end) end
end

local espLayer = Instance.new("Frame")
espLayer.Name = "ESPLayer"
espLayer.BackgroundTransparency = 1
espLayer.Size = UDim2.new(1, 0, 1, 0)
espLayer.ZIndex = 1
espLayer.Parent = gui

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(inst, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 4) }, inst)
	return inst
end

local function stroke(inst, col, th)
	new("UIStroke", {
		Color = col or Color3.new(0, 0, 0),
		Thickness = th or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
	return inst
end

-- ============================ 队友判定 ============================
local function isTeammate(plr)
	if plr == LP then return true end
	if plr.Team ~= nil and LP.Team ~= nil then
		return plr.Team == LP.Team
	end
	if plr.Neutral or LP.Neutral then return false end
	return plr.TeamColor == LP.TeamColor
end

-- ============================ 角色取部件 ============================
local function aliveChar(plr)
	local c = plr and plr.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return nil end
	return c, h
end

local function partOf(char, name)
	return char:FindFirstChild(name)
		or char:FindFirstChild("HumanoidRootPart")
		or char:FindFirstChildOfClass("BasePart")
end

-- ============================ 隔墙检查 ============================
local visParams = RaycastParams.new()
do
	local ok = pcall(function() visParams.FilterType = Enum.RaycastFilterType.Exclude end)
	if not ok then pcall(function() visParams.FilterType = Enum.RaycastFilterType.Blacklist end) end
	visParams.IgnoreWater = true
end

local function canSee(origin, char, pos)
	local ok, res = pcall(function()
		local cam = Workspace.CurrentCamera
		local filter = {}
		if cam then table.insert(filter, cam) end
		if LP.Character then table.insert(filter, LP.Character) end
		if char then table.insert(filter, char) end
		visParams.FilterDescendantsInstances = filter
		BUSY = true
		local hit = Workspace:Raycast(origin, pos - origin, visParams)
		BUSY = false
		if hit == nil then return true end
		local inst = hit.Instance
		return inst ~= nil and char ~= nil and inst:IsDescendantOf(char)
	end)
	BUSY = false
	if not ok then return true end
	return res
end

-- ============================ 选目标 ============================
local function fovCenter(cam)
	local vp = cam.ViewportSize
	local mode = CFG.SILENT.CenterMode
	local useMouse = (mode == "Mouse") or (mode == "Auto" and UserInputService.MouseEnabled)
	if useMouse then
		local ok, m = pcall(function() return UserInputService:GetMouseLocation() end)
		if ok and m then return Vector2.new(m.X, m.Y) end
	end
	return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
end

local function evaluate(plr, cam, center, opts)
	if plr == LP then return nil end
	if opts.teamCheck and isTeammate(plr) then return nil end
	local char, hum = aliveChar(plr)
	if not char then return nil end
	local part = partOf(char, opts.part)
	if not part then return nil end

	local camPos = cam.CFrame.Position
	local pos = part.Position
	if opts.predict and part.AssemblyLinearVelocity then
		pos = pos + part.AssemblyLinearVelocity * opts.predictAmt
	end

	local dist = (camPos - pos).Magnitude
	if dist > opts.maxDist then return nil end

	local sp, onScreen = cam:WorldToViewportPoint(pos)
	if not onScreen or sp.Z <= 0 then return nil end

	local score = (Vector2.new(sp.X, sp.Y) - center).Magnitude
	if score > opts.fov then return nil end

	if opts.visible then
		if not canSee(camPos, char, pos) then return nil end
	end

	return { plr = plr, pos = pos, part = part, char = char, hum = hum, screen = sp, score = score, dist = dist }
end

local function pickTarget(opts)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local center = fovCenter(cam)

	-- 粘性: 刚锁过的目标只要还合法就继续锁, 免得一帧换一个
	if opts.sticky and opts.sticky > 0 and curTarget and curTarget.plr and (now() - curTargetAt) < opts.sticky then
		local keep = evaluate(curTarget.plr, cam, center, opts)
		if keep then return keep end
	end

	local best = nil
	for _, plr in ipairs(Players:GetPlayers()) do
		local t = evaluate(plr, cam, center, opts)
		if t and (best == nil or t.score < best.score) then best = t end
	end
	return best
end

local function silentOpts()
	return {
		part      = CFG.SILENT.Part,
		fov       = CFG.SILENT.FOV,
		maxDist   = CFG.SILENT.MaxDist,
		teamCheck = CFG.SILENT.TeamCheck,
		visible   = CFG.SILENT.Visible,
		predict   = CFG.SILENT.Predict,
		predictAmt = CFG.SILENT.PredictAmt,
		sticky    = CFG.SILENT.Sticky,
	}
end

-- 目标缓存: 同一帧里游戏可能连发十几次射线, 别每次都重扫玩家
local _cacheAt, _cachePos, _cachePlr = 0, nil, nil
local function targetCached(origin)
	local t = now()
	if (t - _cacheAt) < 0.02 then return _cachePos, _cachePlr end
	_cacheAt = t

	local opts = silentOpts()
	local best = pickTarget(opts)
	if best then
		_cachePos, _cachePlr = best.pos, best.plr
		curTarget, curTargetAt = best, t
		STATS.tgt = best.plr.Name
		return best.pos, best.plr
	end
	_cachePos, _cachePlr = nil, nil
	STATS.tgt = "-"
	return nil, nil
end

-- ==================== 射线参数识别 + 改写 ====================
local EPS = 1e-4

local function originLooksReal(origin)
	local cam = Workspace.CurrentCamera
	if cam then
		if (origin - cam.CFrame.Position).Magnitude < CFG.SILENT.MinOriginDist then return true end
	end
	if LP.Character then
		local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (origin - hrp.Position).Magnitude < CFG.SILENT.MinOriginDist then return true end
	end
	return false
end

-- 在参数表里找 (origin, dir[, setter])，支持 Ray 对象和 Vector3 对
local function findRayArgs(args)
	for i = 1, args.n do
		local v = args[i]
		if typeof(v) == "Ray" then
			return v.Origin, v.Direction, i, "ray"
		end
	end
	for i = 1, args.n - 1 do
		local a, b = args[i], args[i + 1]
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" and b.Magnitude > EPS then
			return a, b, (i + 1), "vec", i
		end
	end
	return nil
end

local function rewriteRayArgs(args)
	if not silentActive() or BUSY then return false end

	local origin, dir, idx, kind, originIdx = findRayArgs(args)
	if not origin or not dir then return false end
	if dir.Magnitude <= EPS then return false end
	if not originLooksReal(origin) then return false end

	local tpos = targetCached(origin)
	if not tpos then return false end

	local newDir = (tpos - origin)
	local len = dir.Magnitude
	if newDir.Magnitude < EPS then return false end
	newDir = newDir.Unit * len

	if kind == "ray" then
		pcall(function() args[idx] = Ray.new(origin, newDir) end)
	else
		args[idx] = newDir
	end

	STATS.ray = STATS.ray + 1
	STATS.rayTotal = STATS.rayTotal + 1
	return true
end

-- ==================== 远程事件改写 ====================
local function isRemoteObj(obj)
	local ok, cls = pcall(function() return obj.ClassName end)
	if not ok or type(cls) ~= "string" then return false end
	return cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent"
end

local function remoteAllowed(obj)
	if CFG.HOOK.RemoteAll then return true end
	local ok, nm = pcall(function() return obj.Name end)
	if not ok or type(nm) ~= "string" then return false end
	local low = string.lower(nm)
	for _, kw in ipairs(CFG.HOOK.RemoteNames) do
		if string.find(low, kw, 1, true) then return true end
	end
	return false
end

local function rewriteRemote(obj, method, args)
	if not silentActive() or BUSY then return false end
	if method ~= "FireServer" and method ~= "InvokeServer" then return false end
	if not isRemoteObj(obj) or not remoteAllowed(obj) then return false end

	local cam = Workspace.CurrentCamera
	if not cam then return false end
	local camPos = cam.CFrame.Position

	-- 收集向量参数
	local vecIdx = {}
	local rayIdx = nil
	for i = 1, args.n do
		local v = args[i]
		if typeof(v) == "Vector3" then
			table.insert(vecIdx, i)
		elseif typeof(v) == "Ray" and rayIdx == nil then
			rayIdx = i
		end
	end

	local tpos = targetCached(camPos)
	if not tpos then return false end

	-- ① 参数里直接带 Ray
	if rayIdx then
		local r = args[rayIdx]
		local newDir = (tpos - r.Origin)
		if newDir.Magnitude > EPS then
			args[rayIdx] = Ray.new(r.Origin, newDir.Unit * r.Direction.Magnitude)
			STATS.rem = STATS.rem + 1
			STATS.remTotal = STATS.remTotal + 1
			return true
		end
		return false
	end

	-- ② origin + dir 两个向量
	if #vecIdx >= 2 then
		local oi, di = vecIdx[1], vecIdx[2]
		local o, d = args[oi], args[di]
		if originLooksReal(o) and d.Magnitude > EPS then
			local newDir = (tpos - o)
			if newDir.Magnitude > EPS then
				args[di] = newDir.Unit * d.Magnitude
				STATS.rem = STATS.rem + 1
				STATS.remTotal = STATS.remTotal + 1
				return true
			end
		end
		return false
	end

	-- ③ 只有一个向量: 那多半是单位方向, 直接从相机指向目标
	if #vecIdx == 1 then
		local di = vecIdx[1]
		local d = args[di]
		if d.Magnitude > EPS and d.Magnitude < 4 then
			local newDir = (tpos - camPos)
			if newDir.Magnitude > EPS then
				args[di] = newDir.Unit * d.Magnitude
				STATS.rem = STATS.rem + 1
				STATS.remTotal = STATS.remTotal + 1
				return true
			end
		end
	end

	-- ④ CFrame 朝向 (可选, 默认关; 有些游戏直接发一个朝向 CFrame)
	if CFG.HOOK.RemoteCFrame then
		for i = 1, args.n do
			local v = args[i]
			if typeof(v) == "CFrame" then
				local p = v.Position
				if originLooksReal(p) then
					local aim = tpos - p
					if aim.Magnitude > EPS then
						local ok = pcall(function() args[i] = CFrame.lookAt(p, tpos) end)
						if ok then
							STATS.rem = STATS.rem + 1
							STATS.remTotal = STATS.remTotal + 1
							return true
						end
					end
				end
				break
			end
		end
	end

	return false
end

-- ============================ 安装 hook ============================
local RAY_METHODS = {
	Raycast                     = true,
	FindPartOnRay               = true,
	FindPartOnRayWithIgnoreList = true,
	FindPartOnRayWithWhitelist  = true,
	FindPartOnRayWithIgnoreList2 = true,
}

local CAM_METHODS = {
	ViewportPointToRay = true,
	ScreenPointToRay   = true,
}

local mt, oldNamecall, oldIndex = nil, nil, nil
local hookOK = false

if type(RAWMT) == "function" then
	local ok, m = pcall(RAWMT, game)
	if ok and type(m) == "table" then mt = m end
end

if mt then
	pcall(function() SETRO(mt, false) end)
	oldNamecall = mt.__namecall
	oldIndex    = mt.__index
end

local cachedRayFns = {}

-- 有的元表 __index 是表不是函数, 两种都得兜住
local function callOldIndex(self, key)
	if type(oldIndex) == "function" then return oldIndex(self, key) end
	if type(oldIndex) == "table" then return oldIndex[key] end
	return nil
end

local function callerIsOurs()
	if not CFG.HOOK.UseCheckCaller then return false end
	if type(CHKCALLER) ~= "function" then return false end
	local ok, v = pcall(CHKCALLER)
	return ok and v == true
end

-- ① 主入口
if mt and type(oldNamecall) == "function" and CFG.HOOK.Namecall then
	mt.__namecall = wrap(function(self, ...)
		local method = type(GNCM) == "function" and GNCM() or nil
		if type(method) ~= "string" then return oldNamecall(self, ...) end

		local isRay    = RAY_METHODS[method] == true
		local isRemote = CFG.HOOK.Remote and (method == "FireServer" or method == "InvokeServer")
		if not (isRay or isRemote) then return oldNamecall(self, ...) end
		if BUSY or callerIsOurs() then return oldNamecall(self, ...) end
		if not silentActive() then return oldNamecall(self, ...) end

		local args = table.pack(...)
		local changed = false

		if isRay then
			changed = rewriteRayArgs(args)
			if changed then STATS.mode = method end
		end
		if not changed and isRemote then
			changed = rewriteRemote(self, method, args)
			if changed then STATS.mode = "remote:" .. tostring(method) end
		end

		if changed then
			return oldNamecall(self, table.unpack(args, 1, args.n))
		end
		return oldNamecall(self, ...)
	end)
	hookOK = true
end

-- ② 副入口: 缓存函数 + 相机射线 + 鼠标
if mt and (type(oldIndex) == "function" or type(oldIndex) == "table") then
	mt.__index = wrap(function(self, key)
		if type(key) ~= "string" then return callOldIndex(self, key) end

		-- ② 游戏把 workspace.Raycast 存成局部变量时, 从源头包一层
		if CFG.HOOK.Cached and RAY_METHODS[key] and self == Workspace then
			local fn = callOldIndex(self, key)
			if type(fn) == "function" then
				local w = cachedRayFns[key]
				if not w then
					w = wrap(function(s, ...)
						if not silentActive() or BUSY or callerIsOurs() then return fn(s, ...) end
						local args = table.pack(...)
						if rewriteRayArgs(args) then
							STATS.mode = "cached:" .. key
							return fn(s, table.unpack(args, 1, args.n))
						end
						return fn(s, ...)
					end)
					cachedRayFns[key] = w
				end
				return w
			end
			return fn
		end

		-- ③ 相机射线
		if CFG.HOOK.Camera and CAM_METHODS[key] and self == Workspace.CurrentCamera then
			local fn = callOldIndex(self, key)
			if type(fn) == "function" then
				local w = cachedRayFns["cam_" .. key]
				if not w then
					w = wrap(function(s, px, py)
						local r = fn(s, px, py)
						if silentActive() and not BUSY and not callerIsOurs() and typeof(r) == "Ray" then
							local args = table.pack(r)
							if rewriteRayArgs(args) then
								STATS.mode = "cam:" .. key
								return args[1]
							end
						end
						return r
					end)
					cachedRayFns["cam_" .. key] = w
				end
				return w
			end
			return fn
		end

		-- ④ 鼠标
		if CFG.HOOK.Mouse and (key == "UnitRay" or key == "Hit") then
			local ok, cls = pcall(function() return self.ClassName end)
			if ok and cls == "Mouse" and silentActive() and not BUSY then
				local cam = Workspace.CurrentCamera
				if cam then
					local tpos = targetCached(cam.CFrame.Position)
					if tpos then
						STATS.mode = "mouse:" .. key
						if key == "UnitRay" then
							local d = (tpos - cam.CFrame.Position)
							if d.Magnitude > EPS then
								return Ray.new(cam.CFrame.Position, d.Unit * 1000)
							end
						else
							return tpos
						end
					end
				end
			end
		end

		return callOldIndex(self, key)
	end)
	hookOK = true
end

-- ============================ ESP ============================
local espCache = {}

local function destroyEntry(e)
	if not e then return end
	if e.root then e.root:Destroy() end
	if e.tracer then e.tracer:Destroy() end
end

local function setColor(e, col)
	for _, f in ipairs(e.edges) do f.BackgroundColor3 = col end
	e.name.TextColor3 = col
	e.hpFill.BackgroundColor3 = (col == CFG.ESP.LockColor) and CFG.ESP.LockColor or CFG.ESP.HealthColor
end

local function createEntry(plr)
	local root = new("Frame", {
		Name = "P_" .. plr.Name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 0),
		ZIndex = 2,
	}, espLayer)

	local edges = {}
	edges[1] = new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = CFG.ESP.BoxColor, BorderSizePixel = 0, ZIndex = 3 }, root)
	edges[2] = new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = CFG.ESP.BoxColor, BorderSizePixel = 0, ZIndex = 3 }, root)
	edges[3] = new("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = CFG.ESP.BoxColor, BorderSizePixel = 0, ZIndex = 3 }, root)
	edges[4] = new("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = CFG.ESP.BoxColor, BorderSizePixel = 0, ZIndex = 3 }, root)

	local hpBg = new("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.new(0, -7, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	local hpFill = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = CFG.ESP.HealthColor,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, hpBg)

	local name = new("TextLabel", {
		Size = UDim2.new(0, 220, 0, 16),
		Position = UDim2.new(0.5, 0, 0, -19),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = CFG.ESP.TextSize,
		TextColor3 = CFG.ESP.BoxColor,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Text = plr.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	}, root)

	local dist = new("TextLabel", {
		Size = UDim2.new(0, 160, 0, 14),
		Position = UDim2.new(0.5, 0, 1, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = CFG.ESP.TextSize - 2,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Text = "",
		ZIndex = 5,
	}, root)

	local tracer = new("Frame", {
		Name = "Tracer_" .. plr.Name,
		BackgroundColor3 = CFG.ESP.TracerColor,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 1),
		Visible = false,
		ZIndex = 1,
	}, espLayer)

	return {
		root = root, edges = edges, hpBg = hpBg, hpFill = hpFill,
		name = name, dist = dist, tracer = tracer,
	}
end

local function updateESP()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local seen = {}

	for _, plr in ipairs(Players:GetPlayers()) do
		seen[plr] = true
		local e = espCache[plr]
		if not e then
			e = createEntry(plr)
			espCache[plr] = e
		end

		local char, hum = aliveChar(plr)
		local hide = (not CFG.ESP.Enabled) or plr == LP or char == nil
			or (CFG.ESP.TeamCheck and isTeammate(plr))

		if hide then
			e.root.Visible = false
			e.tracer.Visible = false
		else
			local ok, cf, size = pcall(function() return char:GetBoundingBox() end)
			if not ok or not cf or not size then
				e.root.Visible = false
				e.tracer.Visible = false
			else
				if size.Y < 0.1 then size = Vector3.new(2, 5, 1) end
				local center = cf.Position
				local dist = (cam.CFrame.Position - center).Magnitude

				if dist > CFG.ESP.MaxDist then
					e.root.Visible = false
					e.tracer.Visible = false
				else
					local right = cam.CFrame.RightVector
					local up = Vector3.new(0, 1, 0)

					local cs, on1 = cam:WorldToViewportPoint(center)
					local xs, on2 = cam:WorldToViewportPoint(center + right * (size.X * 0.5))
					local ys, on3 = cam:WorldToViewportPoint(center + up * (size.Y * 0.5))

					if (not on1 or cs.Z <= 0) or (not on2) or (not on3) then
						e.root.Visible = false
						e.tracer.Visible = false
					else
						local w = math.abs(xs.X - cs.X) * 2
						local h = math.abs(cs.Y - ys.Y) * 2
						if w < 8 then w = 8 end
						if h < 14 then h = 14 end
						if w > 900 then w = 900 end
						if h > 1400 then h = 1400 end

						e.root.Visible = true
						e.root.Position = UDim2.fromOffset(cs.X, cs.Y)
						e.root.Size = UDim2.fromOffset(w, h)

						local locked = curTarget ~= nil and curTarget.plr == plr
							and (now() - curTargetAt) < 0.6
						setColor(e, locked and CFG.ESP.LockColor or CFG.ESP.BoxColor)

						for _, f in ipairs(e.edges) do
							f.Visible = CFG.ESP.Box
						end
						e.hpBg.Visible = CFG.ESP.Health
						e.name.Visible = CFG.ESP.Name
						e.dist.Visible = CFG.ESP.Dist

						local ratio = 0
						if hum and hum.MaxHealth > 0 then
							ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
						end
						e.hpFill.Size = UDim2.new(1, 0, ratio, 0)
						e.dist.Text = string.format("%dm", math.floor(dist))

						if CFG.ESP.Tracer then
							local from = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y)
							local to = Vector2.new(cs.X, cs.Y + h * 0.5)
							local d = to - from
							local len = d.Magnitude
							if len > 4 then
								e.tracer.Visible = true
								e.tracer.Size = UDim2.fromOffset(len, 1)
								e.tracer.Position = UDim2.fromOffset((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5)
								e.tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
								e.tracer.BackgroundColor3 = CFG.ESP.TracerColor
							else
								e.tracer.Visible = false
							end
						else
							e.tracer.Visible = false
						end
					end
				end
			end
		end
	end

	for plr, e in pairs(espCache) do
		if not seen[plr] then
			destroyEntry(e)
			espCache[plr] = nil
		end
	end
end

-- ============================ 锁定十字 ============================
local marker = new("Frame", {
	Name = "LockMarker",
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 22, 0, 22),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Visible = false,
	ZIndex = 6,
}, espLayer)
new("Frame", { Size = UDim2.new(0, 1, 0, 7), Position = UDim2.new(0.5, 0, 0, 0),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
new("Frame", { Size = UDim2.new(0, 1, 0, 7), Position = UDim2.new(0.5, 0, 1, 0),
	AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
new("Frame", { Size = UDim2.new(0, 7, 0, 1), Position = UDim2.new(0, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
new("Frame", { Size = UDim2.new(0, 7, 0, 1), Position = UDim2.new(1, 0, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)

-- 锁定十字: 相机自瞄开着时它自己管, 否则跟着 silent 的当前目标
local function updateMarker()
	if CFG.AIM.Enabled and RUNNING then return end
	local fresh = curTarget ~= nil and curTarget.plr ~= nil and curTarget.screen ~= nil
		and (now() - curTargetAt) < 0.6
	if fresh and CFG.SILENT.Marker then
		marker.Visible = true
		marker.Position = UDim2.fromOffset(curTarget.screen.X, curTarget.screen.Y)
	else
		marker.Visible = false
	end
end

-- ============================ 相机自瞄(可选) ============================
local function doAimCam(dt)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	if not (CFG.AIM.Enabled and RUNNING) then
		if not (curTarget and curTarget.plr) then marker.Visible = false end
		return
	end

	if CFG.AIM.PauseOnTouch and UserInputService.TouchEnabled then
		local ok, touches = pcall(function() return UserInputService:GetTouches() end)
		if ok and touches and #touches > 0 then return end
	end

	local opts = {
		part = CFG.AIM.Part, fov = CFG.AIM.Radius, maxDist = CFG.AIM.MaxDist,
		teamCheck = CFG.AIM.TeamCheck, visible = CFG.AIM.Visible,
		predict = CFG.AIM.Predict, predictAmt = CFG.AIM.PredictAmt, sticky = 0.1,
	}
	local t = pickTarget(opts)
	if t then
		local cur = cam.CFrame
		local want = CFrame.new(cur.Position, t.pos)
		local s = math.clamp(CFG.AIM.Smooth, 0.01, 1)
		local alpha = 1 - (1 - s) ^ (dt * 60)
		cam.CFrame = cur:Lerp(want, alpha)
		if CFG.AIM.LockMarker then
			marker.Visible = true
			marker.Position = UDim2.fromOffset(t.screen.X, t.screen.Y)
		end
	else
		if not (curTarget and curTarget.plr) then marker.Visible = false end
	end
end

-- ============================ 面板 ============================
local vpY = 640
pcall(function()
	local c = Workspace.CurrentCamera
	if c then vpY = c.ViewportSize.Y end
end)
local panelH = math.min(380, vpY - 90)
if panelH < 220 then panelH = 220 end

local panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.new(0, 224, 0, panelH),
	Position = UDim2.new(0, 10, 0, 44),
	BackgroundColor3 = Color3.fromRGB(18, 18, 22),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 20,
}, gui)
corner(panel, 10)
stroke(panel, Color3.fromRGB(255, 62, 62), 1.2)

-- 内容全塞进滚动区, 手机上一个屏装不下 29 个开关
local scroller = new("ScrollingFrame", {
	Name = "Scroll",
	Size = UDim2.new(1, 0, 1, -36),
	Position = UDim2.new(0, 0, 0, 36),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Color3.fromRGB(255, 90, 90),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 20,
}, scroller)

new("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, scroller)

new("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
}, scroller)

local header = new("TextButton", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(255, 62, 62),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "ZAKA SILENT + ESP  [drag]",
	AutoButtonColor = false,
	LayoutOrder = 0,
	ZIndex = 21,
}, panel)
corner(header, 7)

local ORDER = 0

local function section(text)
	ORDER = ORDER + 1
	local f = new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, scroller)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 120, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		ZIndex = 22,
	}, f)
end

local function addToggle(labelText, getter, setter)
	ORDER = ORDER + 1
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, scroller)
	new("TextLabel", {
		Size = UDim2.new(1, -66, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(235, 235, 235),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		ZIndex = 22,
	}, row)
	local btn = new("TextButton", {
		Size = UDim2.new(0, 60, 0, 24),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "OFF",
		ZIndex = 22,
	}, row)
	corner(btn, 6)

	local function refresh()
		local on = getter() and true or false
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(40, 170, 80) or Color3.fromRGB(70, 70, 78)
	end
	btn.MouseButton1Click:Connect(function()
		setter(not getter())
		refresh()
	end)
	refresh()
	return btn
end

local function addCycle(labelText, getter, setter, options, fmt)
	ORDER = ORDER + 1
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, scroller)
	new("TextLabel", {
		Size = UDim2.new(1, -96, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(235, 235, 235),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		ZIndex = 22,
	}, row)
	local btn = new("TextButton", {
		Size = UDim2.new(0, 90, 0, 24),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.fromRGB(48, 48, 58),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "?",
		ZIndex = 22,
	}, row)
	corner(btn, 6)

	local function refresh()
		local v = getter()
		btn.Text = fmt and fmt(v) or tostring(v)
	end
	btn.MouseButton1Click:Connect(function()
		local cur = getter()
		local idx = 1
		for i, v in ipairs(options) do
			if tostring(v) == tostring(cur) then idx = i break end
		end
		local nxt = options[(idx % #options) + 1]
		setter(nxt)
		refresh()
	end)
	refresh()
	return btn
end

local function addButton(labelText, color, fn)
	ORDER = ORDER + 1
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = labelText,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, scroller)
	corner(btn, 7)
	btn.MouseButton1Click:Connect(fn)
	return btn
end

local statsLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = Color3.fromRGB(10, 10, 12),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(120, 255, 160),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "hook: -\n",
	TextWrapped = true,
	LayoutOrder = 1,
	ZIndex = 21,
}, scroller)
corner(statsLabel, 6)
ORDER = 1   -- 统计行占了 order 1, 后面的从 2 开始, 免得和它抢位

section("SILENT AIM")
addToggle("Silent 开关", function() return CFG.SILENT.Enabled end, function(v) CFG.SILENT.Enabled = v end)
addCycle("锁定部位", function() return CFG.SILENT.Part end, function(v) CFG.SILENT.Part = v end,
	{ "Head", "UpperTorso", "HumanoidRootPart" })
addCycle("锁定范围", function() return CFG.SILENT.FOV end, function(v) CFG.SILENT.FOV = v end,
	{ 120, 250, 400, 700, 9999 }, function(v) return (v >= 9999) and "FULL" or tostring(v) end)
addCycle("最远距离", function() return CFG.SILENT.MaxDist end, function(v) CFG.SILENT.MaxDist = v end,
	{ 300, 600, 1000, 1600, 4000 })
addCycle("目标粘性", function() return CFG.SILENT.Sticky end, function(v) CFG.SILENT.Sticky = v end,
	{ 0, 0.1, 0.25, 0.5, 1 })
addToggle("队友不锁", function() return CFG.SILENT.TeamCheck end, function(v) CFG.SILENT.TeamCheck = v end)
addToggle("隔墙不锁", function() return CFG.SILENT.Visible end, function(v) CFG.SILENT.Visible = v end)
addToggle("移动预判", function() return CFG.SILENT.Predict end, function(v) CFG.SILENT.Predict = v end)
addToggle("锁定标记", function() return CFG.SILENT.Marker end, function(v) CFG.SILENT.Marker = v end)

section("HOOK  命中改写")
addToggle("射线入口", function() return CFG.HOOK.Namecall end, function(v) CFG.HOOK.Namecall = v end)
addToggle("缓存函数", function() return CFG.HOOK.Cached end, function(v) CFG.HOOK.Cached = v end)
addToggle("相机射线", function() return CFG.HOOK.Camera end, function(v) CFG.HOOK.Camera = v end)
addToggle("鼠标射线", function() return CFG.HOOK.Mouse end, function(v) CFG.HOOK.Mouse = v end)
addToggle("远程事件", function() return CFG.HOOK.Remote end, function(v) CFG.HOOK.Remote = v end)
addToggle("远程全部", function() return CFG.HOOK.RemoteAll end, function(v) CFG.HOOK.RemoteAll = v end)
addToggle("远程CFrame", function() return CFG.HOOK.RemoteCFrame end, function(v) CFG.HOOK.RemoteCFrame = v end)

section("ESP")
addToggle("ESP 开关", function() return CFG.ESP.Enabled end, function(v) CFG.ESP.Enabled = v end)
addToggle("方框 BOX", function() return CFG.ESP.Box end, function(v) CFG.ESP.Box = v end)
addToggle("名字 NAME", function() return CFG.ESP.Name end, function(v) CFG.ESP.Name = v end)
addToggle("距离 DIST", function() return CFG.ESP.Dist end, function(v) CFG.ESP.Dist = v end)
addToggle("血条 HP", function() return CFG.ESP.Health end, function(v) CFG.ESP.Health = v end)
addToggle("连线 LINE", function() return CFG.ESP.Tracer end, function(v) CFG.ESP.Tracer = v end)
addToggle("队友检测 TEAM", function() return CFG.ESP.TeamCheck end, function(v) CFG.ESP.TeamCheck = v end)
addCycle("显示范围", function() return CFG.ESP.MaxDist end, function(v) CFG.ESP.MaxDist = v end,
	{ 400, 700, 1000, 1200, 2000, 5000 })

section("CAMERA AIM  (动视角, 可选)")
addToggle("相机自瞄", function() return CFG.AIM.Enabled end, function(v) CFG.AIM.Enabled = v end)
addCycle("瞄准部位", function() return CFG.AIM.Part end, function(v) CFG.AIM.Part = v end,
	{ "Head", "UpperTorso", "HumanoidRootPart" })
addCycle("平滑度", function() return CFG.AIM.Smooth end, function(v) CFG.AIM.Smooth = v end,
	{ 0.06, 0.10, 0.16, 0.24, 0.35, 0.5 })

addButton("UNLOAD  卸载", Color3.fromRGB(170, 40, 40), function()
	if _G.ZakaSXUnload then _G.ZakaSXUnload() end
end)

-- 收起按钮
local miniBtn = new("TextButton", {
	Size = UDim2.new(0, 42, 0, 42),
	Position = UDim2.new(0, 10, 0.2, 0),
	BackgroundColor3 = Color3.fromRGB(255, 62, 62),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Z",
	Visible = false,
	ZIndex = 30,
}, gui)
corner(miniBtn, 21)
stroke(miniBtn, Color3.new(1, 1, 1), 1.5)

local function applyPanelState()
	panel.Visible = CFG.MISC.PanelOpen
	miniBtn.Visible = not CFG.MISC.PanelOpen
	if CFG.MISC.PanelOpen then miniBtn.Position = panel.Position end
end

header.MouseButton1Click:Connect(function()
	CFG.MISC.PanelOpen = false
	applyPanelState()
end)
miniBtn.MouseButton1Click:Connect(function()
	CFG.MISC.PanelOpen = true
	applyPanelState()
end)
applyPanelState()

-- 拖面板
do
	local dragging, dragStart, startPos = false, nil, nil
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement then
			local d = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
			miniBtn.Position = panel.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
end

-- ============================ 热键 (PC) ============================
local function onKey(input)
	if input.KeyCode == Enum.KeyCode.RightAlt then
		SILENT_ON = not SILENT_ON
		log("[Zaka] Silent ->", SILENT_ON and "ON" or "OFF")
	elseif input.KeyCode == Enum.KeyCode.RightShift then
		CFG.ESP.Enabled = not CFG.ESP.Enabled
	elseif input.KeyCode == Enum.KeyCode.End then
		if _G.ZakaSXUnload then _G.ZakaSXUnload() end
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not input then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		onKey(input)
	end
end)

-- ============================ 主循环 ============================
local conns = {}
local accum = 0
local statAt = 0

table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	if not RUNNING then return end
	accum = accum + dt
	if accum < CFG.MISC.UpdateRate then return end
	local step = accum
	accum = 0

	local ok, err = pcall(function()
		if curTarget ~= nil and (now() - curTargetAt) > 0.6 then
			curTarget = nil
			STATS.tgt = "-"
		end
		updateESP()
		doAimCam(step)
		updateMarker()
	end)
	if not ok and not _G.__zakaSXErr then
		_G.__zakaSXErr = true
		pcall(function() trace("[Zaka] err:", tostring(err)) end)
	end

	if CFG.MISC.ShowStats then
		statAt = statAt + step
		if statAt >= 0.4 then
			statAt = 0
			local okS = pcall(function()
				statsLabel.Text = string.format(
					"ray/s:%d  rem/s:%d  tot:%d/%d\nmode:%s\ntgt:%s",
					STATS.ray, STATS.rem, STATS.rayTotal, STATS.remTotal,
					STATS.mode, STATS.tgt
				)
			end)
			if okS then
				STATS.ray = 0
				STATS.rem = 0
			end
		end
	end
end))

table.insert(conns, Players.PlayerRemoving:Connect(function(plr)
	destroyEntry(espCache[plr])
	espCache[plr] = nil
end))

table.insert(conns, LP.CharacterRemoving:Connect(function()
	curTarget = nil
	STATS.tgt = "-"
end))

-- ============================ 卸载 ============================
_G.ZakaSXUnload = function()
	RUNNING = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	for _, e in pairs(espCache) do destroyEntry(e) end
	espCache = {}
	cachedRayFns = {}

	if mt then
		pcall(function() if oldNamecall then mt.__namecall = oldNamecall end end)
		pcall(function() if oldIndex then mt.__index = oldIndex end end)
		pcall(function() SETRO(mt, true) end)
	end

	pcall(function() gui:Destroy() end)
	_G.ZakaSXUnload = nil
	_G.__zakaSXErr = nil
	log("[Zaka] Silent + ESP 已卸载, 元表已还原")
end

-- ============================ 启动提示 ============================
log("[Zaka] Silent Aim + ESP v3.0 已加载")
log("  Silent:", SILENT_ON and "ON" or "OFF", "(PC 按 RightAlt 切)")
log("  ESP:", CFG.ESP.Enabled and "ON" or "OFF", "(PC 按 RightShift 切)")
log("  面板上 hook 那行能看到有没有真的命中改写")
if not mt then
	log("  [警告] 这个执行器没有 getrawmetatable, 改写装不上, 只能用 ESP")
elseif not hookOK then
	log("  [警告] __namecall 没挂上, 试试把 缓存函数/相机射线 打开")
end
if not CFG.HOOK.Remote then
	log("  提示: 有些游戏靠远程事件判定命中, 打不中可以试试开 远程事件")
end
