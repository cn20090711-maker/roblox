--[[==========================================================
  Zaka | Roblox 手机版 ESP + 自瞄  (v2.0)
  用法: 全选复制 -> 丢执行器 -> Execute
  卸载: 面板上的 UNLOAD 按钮, 或执行  _G.ZakaMUnload()
  说明: 纯 Roblox 原生 GUI, 不依赖 Drawing, 手机/电脑都能跑
        面板标签用英文, 避免执行器字体缺中文变成 ????
==========================================================]]--

if _G.ZakaMUnload then pcall(_G.ZakaMUnload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local CAM = Workspace.CurrentCamera

-- ======================= 配置区(面板里也能改) =======================
local CFG = {
	ESP = {
		Enabled   = true,
		Box       = true,
		Name      = true,
		Dist      = true,
		Health    = true,
		Tracer    = false,
		TeamCheck = true,          -- 开 = 队友不画
		MaxDist   = 1200,
		TextSize  = 13,
		BoxColor    = Color3.fromRGB(255, 62, 62),
		LockColor   = Color3.fromRGB(255, 210, 40),
		HealthColor = Color3.fromRGB(70, 255, 100),
		TracerColor = Color3.fromRGB(255, 62, 62),
	},
	AIM = {
		Enabled     = false,
		Part        = "Head",      -- Head / UpperTorso / HumanoidRootPart
		Smooth      = 0.16,
		Radius      = 260,         -- 屏幕像素, 只锁屏幕中间这个范围里的
		MaxDist     = 900,
		TeamCheck   = true,
		Visible     = true,        -- 只锁能看见的(隔墙不锁)
		Predict     = true,
		PredictAmt  = 0.14,
		LockMarker  = true,        -- 锁定目标头顶打十字
		PauseOnTouch = true,       -- 手指拖屏幕看风景时暂停自动锁(手机必需)
	},
	MISC = {
		PanelOpen  = true,
		UpdateRate = 1 / 45,       -- 每帧刷 45 次, 手机省电
	},
}
-- ====================================================================

local espGui = Instance.new("ScreenGui")
espGui.Name = "ZakaMobileESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.DisplayOrder = 9999
do
	local ok = pcall(function()
		espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not ok then
		pcall(function() espGui.Parent = LP:WaitForChild("PlayerGui", 5) end)
	end
end

-- ============================ 小工具 ============================
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

local trace = function() end
if shared and type(shared) == "table" then
	shared.zakaLog = shared.zakaLog or function() end
	trace = shared.zakaLog
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

-- ============================ ESP 缓存 ============================
local espCache = {}

local function destroyEntry(e)
	if not e then return end
	if e.root then e.root:Destroy() end
	if e.tracer then e.tracer:Destroy() end
end

local function setColor(e, col)
	for _, f in ipairs(e.edges) do f.BackgroundColor3 = col end
	e.name.TextColor3 = col
	e.dist.TextColor3 = Color3.new(1, 1, 1)
	e.hpFill.BackgroundColor3 = col == CFG.ESP.LockColor and CFG.ESP.LockColor or CFG.ESP.HealthColor
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
	}, espGui)

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
		ZIndex = 2,
	}, espGui)

	return {
		root = root, edges = edges, hpBg = hpBg, hpFill = hpFill,
		name = name, dist = dist, tracer = tracer, char = nil,
	}
end

-- ============================ 射线 ============================
local rayParams = RaycastParams.new()
do
	local ok = pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Exclude end)
	if not ok then pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Blacklist end) end
	rayParams.IgnoreWater = true
end

local function isVisible(part)
	if not CFG.AIM.Visible then return true end
	local cam = Workspace.CurrentCamera
	if not cam then return false end
	local filter = { cam }
	if LP.Character then table.insert(filter, LP.Character) end
	if part.Parent then table.insert(filter, part.Parent) end
	rayParams.FilterDescendantsInstances = filter
	local origin = cam.CFrame.Position
	local ok, res = pcall(function()
		return Workspace:Raycast(origin, part.Position - origin, rayParams)
	end)
	if not ok then return true end
	return res == nil
end

-- ============================ 自瞄选目标 ============================
local aimTarget = nil

local function pickTarget()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local vp = cam.ViewportSize
	local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
	local best, bestScore = nil, nil

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and not (CFG.AIM.TeamCheck and isTeammate(plr)) then
			local char = plr.Character
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local part = char:FindFirstChild(CFG.AIM.Part)
					or char:FindFirstChild("UpperTorso")
					or char:FindFirstChild("HumanoidRootPart")
				if part then
					local pos = part.Position
					if CFG.AIM.Predict and part.AssemblyLinearVelocity then
						pos = pos + part.AssemblyLinearVelocity * CFG.AIM.PredictAmt
					end
					local dist = (cam.CFrame.Position - pos).Magnitude
					if dist <= CFG.AIM.MaxDist then
						local sp, onScreen = cam:WorldToViewportPoint(pos)
						if onScreen and sp.Z > 0 then
							local score = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							if score <= CFG.AIM.Radius and (bestScore == nil or score < bestScore) then
								if isVisible(part) then
									bestScore = score
									best = { plr = plr, pos = pos, part = part, screen = sp }
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- ============================ 锁定十字 ============================
local marker = new("Frame", {
	Name = "LockMarker",
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 22, 0, 22),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Visible = false,
	ZIndex = 6,
}, espGui)
local mParts = {}
mParts[1] = new("Frame", { Size = UDim2.new(0, 1, 0, 7), Position = UDim2.new(0.5, 0, 0, 0),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
mParts[2] = new("Frame", { Size = UDim2.new(0, 1, 0, 7), Position = UDim2.new(0.5, 0, 1, 0),
	AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
mParts[3] = new("Frame", { Size = UDim2.new(0, 7, 0, 1), Position = UDim2.new(0, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)
mParts[4] = new("Frame", { Size = UDim2.new(0, 7, 0, 1), Position = UDim2.new(1, 0, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(255, 210, 40), BorderSizePixel = 0, ZIndex = 7 }, marker)

-- ============================ 主循环 ============================
local RUNNING = true

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

		local char = plr.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		local hide = (not CFG.ESP.Enabled) or plr == LP or not char or not hum
			or hum.Health <= 0 or (CFG.ESP.TeamCheck and isTeammate(plr))

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
					local up    = Vector3.new(0, 1, 0)

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

						local locked = (aimTarget and aimTarget.plr == plr)
						setColor(e, locked and CFG.ESP.LockColor or CFG.ESP.BoxColor)

						-- 方框
						for _, f in ipairs(e.edges) do
							f.Visible = CFG.ESP.Box
							f.BackgroundTransparency = 0
						end
						e.hpBg.Visible = CFG.ESP.Health
						e.name.Visible = CFG.ESP.Name
						e.dist.Visible = CFG.ESP.Dist

						-- 血条(竖条, 从下往上涨)
						local ratio = 0
						if hum.MaxHealth > 0 then
							ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
						end
						e.hpFill.Size = UDim2.new(1, 0, ratio, 0)

						-- 距离
						e.dist.Text = string.format("%dm", math.floor(dist))

						-- 射线
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

local function doAim(dt)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	if not (CFG.AIM.Enabled and RUNNING) then
		aimTarget = nil
		marker.Visible = false
		return
	end

	-- 手指正在拖屏幕 -> 暂停, 让玩家自己看风景
	if CFG.AIM.PauseOnTouch and UserInputService.TouchEnabled then
		local touches = UserInputService:GetTouches()
		if touches and #touches > 0 then
			marker.Visible = false
			return
		end
	end

	aimTarget = pickTarget()

	if aimTarget then
		local cur = cam.CFrame
		local want = CFrame.new(cur.Position, aimTarget.pos)
		local s = math.clamp(CFG.AIM.Smooth, 0.01, 1)
		local alpha = 1 - (1 - s) ^ (dt * 60)
		cam.CFrame = cur:Lerp(want, alpha)

		if CFG.AIM.LockMarker then
			marker.Visible = true
			marker.Position = UDim2.fromOffset(aimTarget.screen.X, aimTarget.screen.Y)
		else
			marker.Visible = false
		end
	else
		marker.Visible = false
	end
end

-- ============================ 面板 ============================
local panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.new(0, 210, 0, 0),
	Position = UDim2.new(0, 10, 0.24, 0),
	BackgroundColor3 = Color3.fromRGB(18, 18, 22),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Active = true,
	AutomaticSize = Enum.AutomaticSize.Y,
	ZIndex = 20,
}, espGui)
corner(panel, 10)
stroke(panel, Color3.fromRGB(255, 62, 62), 1.2)

new("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, panel)

new("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
}, panel)

local header = new("TextButton", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(255, 62, 62),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "ZAKA MOBILE  [拖我]",
	AutoButtonColor = false,
	LayoutOrder = 0,
	ZIndex = 21,
}, panel)
corner(header, 7)

local function section(text, order)
	local f = new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 21,
	}, panel)
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
	return f
end

local ORDER = 0
local function nextOrder()
	ORDER = ORDER + 1
	return ORDER
end

local function addToggle(labelText, getter, setter)
	ORDER = ORDER + 1
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, panel)
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
		AutoButtonColor = true,
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

local function addCycle(labelText, getter, setter, options)
	ORDER = ORDER + 1
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = ORDER,
		ZIndex = 21,
	}, panel)
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
		AutoButtonColor = true,
		ZIndex = 22,
	}, row)
	corner(btn, 6)

	local function refresh()
		btn.Text = tostring(getter())
	end
	btn.MouseButton1Click:Connect(function()
		local cur = getter()
		local idx = 1
		for i, v in ipairs(options) do
			if tostring(v) == tostring(cur) then idx = i break end -- luacheck: ok
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
	}, panel)
	corner(btn, 7)
	btn.MouseButton1Click:Connect(fn)
	return btn
end

section("ESP", nextOrder())
addToggle("ESP 开关", function() return CFG.ESP.Enabled end, function(v) CFG.ESP.Enabled = v end)
addToggle("方框 BOX", function() return CFG.ESP.Box end, function(v) CFG.ESP.Box = v end)
addToggle("名字 NAME", function() return CFG.ESP.Name end, function(v) CFG.ESP.Name = v end)
addToggle("距离 DIST", function() return CFG.ESP.Dist end, function(v) CFG.ESP.Dist = v end)
addToggle("血条 HP", function() return CFG.ESP.Health end, function(v) CFG.ESP.Health = v end)
addToggle("连线 LINE", function() return CFG.ESP.Tracer end, function(v) CFG.ESP.Tracer = v end)
addToggle("队友检测 TEAM", function() return CFG.ESP.TeamCheck end, function(v) CFG.ESP.TeamCheck = v end)
addCycle("显示范围", function() return CFG.ESP.MaxDist end, function(v) CFG.ESP.MaxDist = v end,
	{ 400, 700, 1000, 1200, 2000, 5000 })

section("AIM  自瞄", nextOrder())
addToggle("自瞄开关", function() return CFG.AIM.Enabled end, function(v) CFG.AIM.Enabled = v end)
addCycle("瞄准部位", function() return CFG.AIM.Part end, function(v) CFG.AIM.Part = v end,
	{ "Head", "UpperTorso", "HumanoidRootPart" })
addCycle("平滑度", function() return CFG.AIM.Smooth end, function(v) CFG.AIM.Smooth = v end,
	{ 0.06, 0.10, 0.16, 0.24, 0.35, 0.5 })
addCycle("锁头范围", function() return CFG.AIM.Radius end, function(v) CFG.AIM.Radius = v end,
	{ 80, 140, 200, 260, 360, 500 })
addCycle("最远距离", function() return CFG.AIM.MaxDist end, function(v) CFG.AIM.MaxDist = v end,
	{ 200, 400, 700, 900, 1500 })
addToggle("隔墙不锁", function() return CFG.AIM.Visible end, function(v) CFG.AIM.Visible = v end)
addToggle("移动预判", function() return CFG.AIM.Predict end, function(v) CFG.AIM.Predict = v end)
addToggle("锁定标记", function() return CFG.AIM.LockMarker end, function(v) CFG.AIM.LockMarker = v end)
addToggle("手拖暂停", function() return CFG.AIM.PauseOnTouch end, function(v) CFG.AIM.PauseOnTouch = v end)
addToggle("队友不锁", function() return CFG.AIM.TeamCheck end, function(v) CFG.AIM.TeamCheck = v end)

ORDER = ORDER + 1
local unloadBtn = addButton("UNLOAD  卸载", Color3.fromRGB(170, 40, 40), function()
	if _G.ZakaMUnload then _G.ZakaMUnload() end
end)

-- 收起按钮
local miniBtn = new("TextButton", {
	Size = UDim2.new(0, 42, 0, 42),
	Position = UDim2.new(0, 10, 0.24, 0),
	BackgroundColor3 = Color3.fromRGB(255, 62, 62),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Z",
	Visible = false,
	ZIndex = 30,
}, espGui)
corner(miniBtn, 21)
stroke(miniBtn, Color3.new(1, 1, 1), 1.5)

local function applyPanelState()
	panel.Visible = CFG.MISC.PanelOpen
	miniBtn.Visible = not CFG.MISC.PanelOpen
	if CFG.MISC.PanelOpen then
		miniBtn.Position = panel.Position
	end
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

-- 拖动面板
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

-- ============================ 循环 ============================
local conns = {}
local accum = 0
table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	if not RUNNING then return end
	accum = accum + dt
	if accum < CFG.MISC.UpdateRate then return end
	local step = accum
	accum = 0
	local ok, err = pcall(function()
		updateESP()
		doAim(step)
	end)
	if not ok and not _G.__zakaMErr then
		_G.__zakaMErr = true
		pcall(function() trace("[Zaka] err:", tostring(err)) end)
	end
end))

table.insert(conns, Players.PlayerRemoving:Connect(function(plr)
	destroyEntry(espCache[plr])
	espCache[plr] = nil
end))

-- ============================ 卸载 ============================
_G.ZakaMUnload = function()
	RUNNING = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	for _, e in pairs(espCache) do destroyEntry(e) end
	espCache = {}
	pcall(function() espGui:Destroy() end)
	_G.ZakaMUnload = nil
	_G.__zakaMErr = nil
end

pcall(function()
	trace("[Zaka] Mobile ESP + Aim v2.0 loaded")
end)
