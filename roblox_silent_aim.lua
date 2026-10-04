--[[==========================================================
  Zaka | Roblox Silent Aim  (v1.1)
  命中改写型：不动视角，只把射线的落点换成目标身上。
  用法：全选复制 -> 丢进执行器 -> Execute
  卸载：End 键，或执行 _G.ZakaSAUnload()
  热键：RightAlt = 开关（切换式）
==========================================================]]--

if _G.ZakaSAUnload then pcall(_G.ZakaSAUnload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local Workspace        = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- ==================== 配置区（改这里）====================
local CFG = {
	Enabled    = true,
	Key        = Enum.KeyCode.RightAlt,
	ToggleMode = true,          -- true = 按一下开/关 | false = 按住生效

	FOV        = 250,           -- 屏幕像素半径，准星范围外不锁
	TargetPart = "Head",        -- "Head" / "UpperTorso" / "HumanoidRootPart"
	TeamCheck  = true,
	MaxDist    = 1200,
	Predict    = 0.0,           -- 移动靶提前量，0.12 ~ 0.2 试
	WallCheck  = false,         -- 开墙检要递归 raycast，掉帧自己扛
	CacheTime  = 0.02,          -- 目标结果缓存(秒)，防止一帧多发时重复遍历

	HookNamecall = true,        -- 主入口：拦 workspace:Raycast / FindPartOnRay 系列
	HookCachedFn = false,       -- 副入口：游戏把 workspace.Raycast 存成局部变量时用
	HookMouse    = false,       -- 副入口：有些游戏用 mouse.Hit / UnitRay 判定

	DrawFOV    = true,
	FOVColor   = Color3.fromRGB(150, 150, 150),
	Debug      = false,
}
-- =======================================================

local DRAWING     = Drawing or (getgenv and getgenv().Drawing)
local HAS_DRAWING = type(DRAWING) == "table" and type(DRAWING.new) == "function"

local RUNNING   = true
local ON        = CFG.ToggleMode and CFG.Enabled or false
local HOLD      = false
local BUSY      = false          -- 我们自己发起的射线，别被自己的 hook 改
local fovCircle = nil

local function log(...)
	if printconsole then printconsole(...) else print(...) end
end
local function dbg(...)
	if CFG.Debug then log("[SA]", ...) end
end
local function isActive()
	if not CFG.Enabled then return false end
	return CFG.ToggleMode and ON or HOLD
end

-- ==================== 目标相关 ====================
local function getChar(plr)
	local c = plr.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if h and r and h.Health > 0 then return c, h, r end
	return nil
end

local function sameTeam(plr)
	if not CFG.TeamCheck then return false end
	if not plr.Team or not LP.Team then return false end
	return plr.Team == LP.Team
end

-- 墙检（可选，默认关）
local function visibleFrom(origin, char, pos)
	if not CFG.WallCheck then return true end
	BUSY = true
	local ok, clear = pcall(function()
		local rp = RaycastParams.new()
		local okE = pcall(function() rp.FilterType = Enum.RaycastFilterType.Exclude end)
		if not okE then pcall(function() rp.FilterType = Enum.RaycastFilterType.Blacklist end) end
		rp.FilterDescendantsInstances = { LP.Character }
		local hit = Workspace:Raycast(origin, pos - origin, rp)
		if hit == nil then return true end
		local inst = hit.Instance
		return inst ~= nil and inst:IsDescendantOf(char)
	end)
	BUSY = false
	if not ok then return true end
	return clear
end

-- 选目标：离准星（鼠标）屏幕距离最近的那个
local function pickAimPoint(origin)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local center = Vector2.new(mouse.X, mouse.Y - inset.Y)

	local camPos = cam.CFrame.Position
	local best, bestScore = nil, math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and not sameTeam(plr) then
			local char, hum, hrp = getChar(plr)
			if char then
				local part = char:FindFirstChild(CFG.TargetPart) or hrp
				local pos = part.Position
				if CFG.Predict > 0 then
					pos = pos + part.AssemblyLinearVelocity * CFG.Predict
				end

				if (camPos - hrp.Position).Magnitude <= CFG.MaxDist then
					local sp, onScreen = cam:WorldToViewportPoint(pos)
					if onScreen and sp.Z > 0 then
						local score = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if score <= CFG.FOV and score < bestScore then
							if visibleFrom(origin, char, pos) then
								bestScore = score
								best = pos
							end
						end
					end
				end
			end
		end
	end

	return best
end

-- 结果缓存：一帧内可能十几次射线，别每次都重扫玩家列表
local _cacheAt, _cachePos = 0, nil
local function aimPointCached(origin)
	local now = os.clock()
	if CFG.CacheTime > 0 and (now - _cacheAt) < CFG.CacheTime then
		return _cachePos
	end
	_cacheAt  = now
	_cachePos = pickAimPoint(origin)
	return _cachePos
end

-- 把射线的落点改到目标身上（方向换，射程不变）
local function redirect(origin, dir)
	if BUSY or not RUNNING or not isActive() then return nil end
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return nil end
	if dir.Magnitude < 1e-3 then return nil end

	local tpos = aimPointCached(origin)
	if not tpos then return nil end

	local dist = math.max(dir.Magnitude, 1)
	return (tpos - origin).Unit * dist
end

-- 统一改写参数表；改了返 true
local function rewriteArgs(method, args)
	local origin, dir, isRay = nil, nil, false

	if method == "Raycast" then
		origin, dir = args[1], args[2]
	else
		local ray = args[1]
		if typeof(ray) == "Ray" then
			origin, dir, isRay = ray.Origin, ray.Direction, true
		end
	end

	if not origin or not dir then return false end

	local newDir = redirect(origin, dir)
	if not newDir then return false end

	if isRay then
		args[1] = Ray.new(origin, newDir)
	else
		args[2] = newDir
	end
	return true
end

-- ==================== 核心：hook ====================
local RAY_METHODS = {
	Raycast                     = true,
	FindPartOnRay               = true,
	FindPartOnRayWithIgnoreList = true,
	FindPartOnRayWithWhitelist  = true,
}

local mt = getrawmetatable(game)
local oldNamecall = mt and mt.__namecall
local oldIndex    = mt and mt.__index

if mt then
	local ok = pcall(setreadonly, mt, false)
	if not ok then pcall(function() setreadonly(mt, false) end) end
end

-- ① 主入口：__namecall —— workspace:Raycast(...) / FindPartOnRay(...)
if mt and oldNamecall and CFG.HookNamecall then
	mt.__namecall = newcclosure(function(self, ...)
		local method = getnamecallmethod()

		if RAY_METHODS[method] then
			local args = table.pack(...)
			if rewriteArgs(method, args) then
				dbg("namecall hooked:", method)
				return oldNamecall(self, table.unpack(args, 1, args.n))
			end
		end

		return oldNamecall(self, ...)
	end)
end

-- ② 副入口（可选）：游戏把 workspace.Raycast 存成局部变量，绕过 namecall
--    ③ 副入口（可选）：mouse.Hit / mouse.UnitRay
if mt and oldIndex and (CFG.HookCachedFn or CFG.HookMouse) then
	mt.__index = newcclosure(function(self, key)
		-- ② 缓存函数
		if CFG.HookCachedFn and RAY_METHODS[key] then
			local ok, isWs = pcall(function() return self == Workspace end)
			if ok and isWs then
				local orig = oldIndex(self, key)
				if typeof(orig) == "function" then
					return newcclosure(function(s, ...)
						local args = table.pack(...)
						if rewriteArgs(key, args) then
							dbg("cached fn hooked:", key)
							return orig(s, table.unpack(args, 1, args.n))
						end
						return orig(s, ...)
					end)
				end
				return orig
			end
		end

		-- ③ 鼠标
		if CFG.HookMouse and (key == "UnitRay" or key == "Hit") then
			local ok, cls = pcall(function() return self.ClassName end)
			if ok and cls == "Mouse" then
				local cam = Workspace.CurrentCamera
				if cam then
					local tpos = aimPointCached(cam.CFrame.Position)
					if tpos then
						if key == "UnitRay" then
							return Ray.new(cam.CFrame.Position,
								(tpos - cam.CFrame.Position).Unit * 1000)
						end
						return tpos
					end
				end
			end
		end

		return oldIndex(self, key)
	end)
end

-- ==================== FOV 圈 ====================
local function ensureFovCircle()
	if not HAS_DRAWING then return nil end
	if not fovCircle then
		local ok, obj = pcall(function() return DRAWING.new("Circle") end)
		if ok and obj then fovCircle = obj end
	end
	return fovCircle
end

RunService.RenderStepped:Connect(function()
	if not RUNNING then return end
	local c = ensureFovCircle()
	if not c then return end

	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()

	local ok = pcall(function()
		c.Visible      = CFG.DrawFOV and isActive()
		c.Position     = Vector2.new(mouse.X, mouse.Y - inset.Y)
		c.Radius       = CFG.FOV
		c.Color        = CFG.FOVColor
		c.Thickness    = 1
		c.Transparency = 1
		c.NumSides     = 60
		c.Filled       = false
	end)

	if not ok then
		pcall(function() c:Remove() end)
		fovCircle = nil
	end
end)

-- ==================== 输入 ====================
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == CFG.Key then
		if CFG.ToggleMode then
			ON = not ON
		else
			HOLD = true
		end
		log("[ZakaSA]", isActive() and "ON" or "OFF")
	elseif input.KeyCode == Enum.KeyCode.End then
		if _G.ZakaSAUnload then _G.ZakaSAUnload() end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not CFG.ToggleMode
		and input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == CFG.Key then
		HOLD = false
	end
end)

-- ==================== 卸载 ====================
_G.ZakaSAUnload = function()
	RUNNING = false

	if mt then
		pcall(function()
			if oldNamecall then mt.__namecall = oldNamecall end
			if oldIndex then mt.__index = oldIndex end
			setreadonly(mt, true)
		end)
	end

	if fovCircle then pcall(function() fovCircle:Remove() end) end
	fovCircle = nil
	_cachePos = nil

	log("[ZakaSA] 已卸载，元表已还原")
	_G.ZakaSAUnload = nil
end

log("[ZakaSA] Silent Aim 已加载")
log("  " .. CFG.Key.Name .. " = " .. (CFG.ToggleMode and "开关" or "按住") .. " | End = 卸载")
if not HAS_DRAWING then log("  无 Drawing，FOV 圈不画（不影响命中改写）") end
if not CFG.HookCachedFn then log("  若某游戏锁不中，把 CFG.HookCachedFn 改成 true 再试") end
