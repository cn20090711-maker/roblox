--[[==========================================================
  Zaka | Roblox ESP + Aimbot  (v1.1)
  ----------------------------------------------------------
  用法：全选复制 -> 丢进执行器 -> Execute
        支持 Synapse / Krnl / Fluxus / Wave / Delta /
        Solara / Codex / Xeno / AWP 等（带 Drawing 的都行）
  卸载：End 键，或执行  _G.ZakaUnload()
  ----------------------------------------------------------
  热键：
    RightShift  = ESP 开 / 关
    End         = 全部卸载
    鼠标右键     = 按住自瞄（可改 ToggleMode = true 变切换）
==========================================================]]--

if _G.ZakaUnload then pcall(_G.ZakaUnload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ==================================================================
--  配置区（改这里就行，不用碰下面的代码）
-- ==================================================================
local CFG = {
	ESP = {
		Enabled      = true,

		Box          = true,
		Name         = true,
		Distance     = true,
		Health       = true,
		Tracer       = true,
		Skeleton     = false,          -- 骨骼线，每人多 19 条线，掉帧就关

		MaxDist      = 1500,           -- 超过这个距离不画
		TeamCheck    = true,           -- 过滤队友
		TextSize     = 14,

		BoxColor     = Color3.fromRGB(255, 45, 45),
		NameColor    = Color3.fromRGB(255, 255, 255),
		DistColor    = Color3.fromRGB(180, 180, 180),
		HealthColor  = Color3.fromRGB(70, 255, 90),
		TracerColor  = Color3.fromRGB(255, 45, 45),
		SkelColor    = Color3.fromRGB(255, 255, 255),

		BoxThickness = 1,              -- 方框线宽
		TracerFrom   = "Bottom",       -- "Bottom" | "Center" | "Mouse"
	},

	AIM = {
		Enabled      = true,
		Key          = Enum.UserInputType.MouseButton2,  -- 触发键
		ToggleMode   = false,          -- true = 按一下开/关，false = 按住

		FOV          = 130,            -- 屏幕中心多少像素内的才锁
		DrawFOV      = true,
		FOVColor     = Color3.fromRGB(160, 160, 160),

		Smoothness   = 0.22,           -- 0.05 = 很黏很慢，1 = 瞬间甩过去
		TargetPart   = "Head",         -- "Head" / "HumanoidRootPart" / "UpperTorso"
		Prediction   = 0.165,          -- 弹道预判，跑动目标调 0.15~0.2

		TeamCheck    = true,
		VisibleCheck = true,           -- 隔墙不锁
		MaxDist      = 1000,
		UseMouseFOV  = true,           -- true = 以准心为准，false = 以屏幕中心
	},

	MISC = {
		FOVCamera    = nil,            -- 想改视野填 70~120，不改就留 nil
	},
}
-- ==================================================================


-- ============================ 内部工具 ============================
local DRAWING = Drawing
if not DRAWING and getgenv then DRAWING = getgenv().Drawing end
local HAS_DRAWING = type(DRAWING) == "table" and type(DRAWING.new) == "function"

local mousemoverel = mousemoverel or (getgenv and getgenv().mousemoverel)
local RUNNING = true
local AIM_HOLD = false
local AIM_TOGGLE = false

local function log(...)
	if printconsole then printconsole(...) else print(...) end
end

local function mkDraw(class, props)
	if not HAS_DRAWING then return nil end
	local ok, obj = pcall(function() return DRAWING.new(class) end)
	if not ok or not obj then return nil end
	if props then
		for k, v in pairs(props) do
			pcall(function() obj[k] = v end)
		end
	end
	return obj
end

local function setProps(obj, props)
	if not obj then return end
	for k, v in pairs(props) do
		pcall(function() obj[k] = v end)
	end
end

local function destroyDraw(obj)
	if obj and obj.Remove then pcall(function() obj:Remove() end) end
end

-- 取角色关键部件
local function getChar(plr)
	local char = plr.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
		or char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
	if not hrp then return nil end
	return char, hum, hrp
end

-- ============================ 射线遮挡 ============================
local RAY = RaycastParams.new()
pcall(function() RAY.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() RAY.FilterType = Enum.RaycastFilterType.Blacklist end)
RAY.IgnoreWater = true

local function isVisible(targetPart)
	local cam = Workspace.CurrentCamera
	if not cam then return false end
	local from = cam.CFrame.Position
	local filter = {}
	if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
	if targetPart.Parent then table.insert(filter, targetPart.Parent) end
	RAY.FilterDescendantsInstances = filter
	local res = Workspace:Raycast(from, targetPart.Position - from, RAY)
	return res == nil
end

-- ============================ ESP 缓存 ============================
local espCache = {}
local skeletonBones = {
	-- R15
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
	-- R6（名字带空格，找不到就自动跳过）
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local function newEntry()
	return {
		box    = mkDraw("Square", { Thickness = CFG.ESP.BoxThickness, Filled = false }),
		name   = mkDraw("Text", { Center = true, Outline = true, Size = CFG.ESP.TextSize, Font = 2 }),
		dist   = mkDraw("Text", { Center = true, Outline = true, Size = CFG.ESP.TextSize - 1, Font = 2 }),
		health = mkDraw("Text", { Center = true, Outline = true, Size = CFG.ESP.TextSize - 1, Font = 2 }),
		tracer = mkDraw("Line", { Thickness = 1 }),
		bones  = {},
	}
end

local function clearEntry(e)
	if not e then return end
	destroyDraw(e.box)
	destroyDraw(e.name)
	destroyDraw(e.dist)
	destroyDraw(e.health)
	destroyDraw(e.tracer)
	for _, l in ipairs(e.bones) do destroyDraw(l) end
	e.bones = {}
end

local function hideEntry(e)
	if not e then return end
	for _, k in ipairs({ "box", "name", "dist", "health", "tracer" }) do
		if e[k] then pcall(function() e[k].Visible = false end) end
	end
	for _, l in ipairs(e.bones) do pcall(function() l.Visible = false end) end
end

-- ====================== 实例兜底 ESP（无 Drawing 时）======================
local fallbackCache = {}

local function fallbackUpdate(plr, char, hum, hrp)
	local f = fallbackCache[plr]
	if not f then
		local hl = Instance.new("Highlight")
		hl.Name = "ZakaESP"
		hl.FillTransparency = 0.7
		hl.OutlineTransparency = 0
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
		f = { hl = hl }
		fallbackCache[plr] = f
	end
	f.hl.FillColor = CFG.ESP.BoxColor
	f.hl.OutlineColor = CFG.ESP.BoxColor
	f.hl.Adornee = char
	f.hl.Parent = char

	if CFG.ESP.Name or CFG.ESP.Distance then
		if not f.gui or not f.gui.Parent then
			local head = char:FindFirstChild("Head") or hrp
			local bb = Instance.new("BillboardGui")
			bb.Name = "ZakaESPTag"
			bb.Size = UDim2.new(0, 200, 0, 24)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.AlwaysOnTop = true

			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.Font = Enum.Font.GothamBold
			lbl.TextSize = CFG.ESP.TextSize
			lbl.TextColor3 = CFG.ESP.NameColor
			lbl.TextStrokeTransparency = 0
			lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
			lbl.Parent = bb

			bb.Adornee = head
			bb.Parent = head
			f.gui = bb
			f.lbl = lbl
		end
		local cam = Workspace.CurrentCamera
		local d = cam and (cam.CFrame.Position - hrp.Position).Magnitude or 0
		local txt = ""
		if CFG.ESP.Name then txt = plr.Name end
		if CFG.ESP.Distance then
			txt = txt .. (txt ~= "" and " " or "") .. "[" .. math.floor(d) .. "m]"
		end
		f.lbl.Text = txt
	end
end

local function fallbackRemove(plr)
	local f = fallbackCache[plr]
	if f then
		if f.hl then pcall(function() f.hl:Destroy() end) end
		if f.gui then pcall(function() f.gui:Destroy() end) end
		fallbackCache[plr] = nil
	end
end

-- ============================ FOV 圈 ============================
local fovCircle = mkDraw("Circle", {
	Thickness = 1,
	NumSides = 64,
	Filled = false,
	Color = CFG.AIM.FOVColor,
})

-- ============================ ESP 主循环 ============================
local function renderESP()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize

	-- 鼠标位置（扣掉顶部工具条内缩）
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local mousePos = Vector2.new(mouse.X, mouse.Y - inset.Y)

	for _, plr in ipairs(Players:GetPlayers()) do
		local e = espCache[plr]

		if plr ~= LocalPlayer and CFG.ESP.Enabled then
			local char, hum, hrp = getChar(plr)

			local show = char ~= nil and hum.Health > 0
			if show and CFG.ESP.TeamCheck
				and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
				show = false
			end

			local dist = 0
			if show then
				dist = (cam.CFrame.Position - hrp.Position).Magnitude
				if dist > CFG.ESP.MaxDist then show = false end
			end

			if show and not HAS_DRAWING then
				fallbackUpdate(plr, char, hum, hrp)
			elseif show then
				if not e then
					e = newEntry()
					espCache[plr] = e
				end

				local head = char:FindFirstChild("Head") or hrp
				local topPos = head.Position + Vector3.new(0, head.Size.Y * 0.5, 0)
				local botPos = hrp.Position - Vector3.new(0, hrp.Size.Y * 0.5, 0)

				local top, onTop = cam:WorldToViewportPoint(topPos)
				local bot = cam:WorldToViewportPoint(botPos)

				if onTop and top.Z > 0.1 then
					local h = math.abs(bot.Y - top.Y)
					local w = h * 0.56
					if w < 6 then w = 6 end
					local x = top.X - w * 0.5

					setProps(e.box, {
						Visible = CFG.ESP.Box,
						Color = CFG.ESP.BoxColor,
						Thickness = CFG.ESP.BoxThickness,
						Position = Vector2.new(x, top.Y),
						Size = Vector2.new(w, h),
					})

					setProps(e.name, {
						Visible = CFG.ESP.Name,
						Color = CFG.ESP.NameColor,
						Size = CFG.ESP.TextSize,
						Position = Vector2.new(top.X, top.Y - 16),
						Text = plr.Name,
					})

					setProps(e.dist, {
						Visible = CFG.ESP.Distance,
						Color = CFG.ESP.DistColor,
						Size = CFG.ESP.TextSize - 1,
						Position = Vector2.new(top.X, top.Y + h + 12),
						Text = "[" .. math.floor(dist) .. "m]",
					})

					setProps(e.health, {
						Visible = CFG.ESP.Health,
						Color = CFG.ESP.HealthColor,
						Size = CFG.ESP.TextSize - 1,
						Position = Vector2.new(x - 22, top.Y + h * 0.5),
						Text = tostring(math.floor(hum.Health)) .. "%",
					})

					if e.tracer then
						local origin
						if CFG.ESP.TracerFrom == "Center" then
							origin = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
						elseif CFG.ESP.TracerFrom == "Mouse" then
							origin = mousePos
						else
							origin = Vector2.new(vp.X * 0.5, vp.Y)
						end
						setProps(e.tracer, {
							Visible = CFG.ESP.Tracer,
							Color = CFG.ESP.TracerColor,
							Thickness = 1,
							From = origin,
							To = Vector2.new(top.X, top.Y + h),
						})
					end

					-- 骨骼线：只有开了才创建，省性能
					if CFG.ESP.Skeleton then
						for i, bone in ipairs(skeletonBones) do
							if not e.bones[i] then
								e.bones[i] = mkDraw("Line", { Thickness = 1 })
							end
							local a = char:FindFirstChild(bone[1])
							local b = char:FindFirstChild(bone[2])
							local ln = e.bones[i]
							if ln then
								if a and b then
									local pa = cam:WorldToViewportPoint(a.Position)
									local pb = cam:WorldToViewportPoint(b.Position)
									setProps(ln, {
										Visible = (pa.Z > 0.1) and (pb.Z > 0.1),
										Color = CFG.ESP.SkelColor,
										From = Vector2.new(pa.X, pa.Y),
										To = Vector2.new(pb.X, pb.Y),
									})
								else
									pcall(function() ln.Visible = false end)
								end
							end
						end
					elseif e.bones[1] then
						for _, l in ipairs(e.bones) do
							pcall(function() l.Visible = false end)
						end
					end
				else
					hideEntry(e)
				end
			else
				if HAS_DRAWING then
					hideEntry(e)
				else
					fallbackRemove(plr)
				end
			end
		else
			-- 自己 / ESP 总开关关闭
			if HAS_DRAWING then
				hideEntry(e)
			else
				fallbackRemove(plr)
			end
		end
	end
end

-- ============================ 自瞄 ============================
local function pickTarget()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local vp = cam.ViewportSize

	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local mousePos = Vector2.new(mouse.X, mouse.Y - inset.Y)
	local center = CFG.AIM.UseMouseFOV and mousePos or Vector2.new(vp.X * 0.5, vp.Y * 0.5)

	local best, bestScore = nil, math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local ok = true
			if CFG.AIM.TeamCheck
				and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
				ok = false
			end

			if ok then
				local char, hum, hrp = getChar(plr)
				if char and hum.Health > 0 then
					local dist = (cam.CFrame.Position - hrp.Position).Magnitude
					if dist <= CFG.AIM.MaxDist then
						local part = char:FindFirstChild(CFG.AIM.TargetPart) or hrp
						local pos = part.Position
							+ part.AssemblyLinearVelocity * CFG.AIM.Prediction

						if not CFG.AIM.VisibleCheck or isVisible(part) then
							local sp, onScreen = cam:WorldToViewportPoint(pos)
							if onScreen and sp.Z > 0.1 then
								local p = Vector2.new(sp.X, sp.Y)
								local score = (p - center).Magnitude
								if score <= CFG.AIM.FOV and score < bestScore then
									bestScore = score
									best = { plr = plr, pos = pos, screen = p, part = part }
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

local function moveToScreenPoint(screenPos)
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local cur = Vector2.new(mouse.X, mouse.Y - inset.Y)

	local delta = screenPos - cur
	local step = CFG.AIM.Smoothness

	if mousemoverel then
		mousemoverel(delta.X * step, delta.Y * step)
	else
		-- 没有 mousemoverel 的执行器：退回相机转向模式
		local cam = Workspace.CurrentCamera
		if cam then
			local aimAt = cam.CFrame.Position
				+ cam.CFrame:VectorToWorldSpace(Vector3.new(delta.X, -delta.Y, -1000))
			cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, aimAt), step)
		end
	end
end

local function doAim()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize

	if fovCircle then
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local pos = CFG.AIM.UseMouseFOV
			and Vector2.new(mouse.X, mouse.Y - inset.Y)
			or Vector2.new(vp.X * 0.5, vp.Y * 0.5)
		setProps(fovCircle, {
			Visible = CFG.AIM.Enabled and CFG.AIM.DrawFOV,
			Color = CFG.AIM.FOVColor,
			Thickness = 1,
			Position = pos,
			Radius = CFG.AIM.FOV,
		})
	end

	local active = AIM_HOLD or AIM_TOGGLE
	if not (CFG.AIM.Enabled and active) then return end

	local t = pickTarget()
	if t then moveToScreenPoint(t.screen) end
end

-- ============================ 事件 ============================
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType == CFG.AIM.Key then
		if CFG.AIM.ToggleMode then
			AIM_TOGGLE = not AIM_TOGGLE
		else
			AIM_HOLD = true
		end
	elseif input.KeyCode == Enum.KeyCode.RightShift then
		CFG.ESP.Enabled = not CFG.ESP.Enabled
		log("[Zaka] ESP ->", CFG.ESP.Enabled and "ON" or "OFF")
	elseif input.KeyCode == Enum.KeyCode.End then
		if _G.ZakaUnload then _G.ZakaUnload() end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == CFG.AIM.Key and not CFG.AIM.ToggleMode then
		AIM_HOLD = false
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	clearEntry(espCache[plr])
	espCache[plr] = nil
	fallbackRemove(plr)
end)

-- ============================ 卸载 ============================
_G.ZakaUnload = function()
	RUNNING = false
	for _, e in pairs(espCache) do clearEntry(e) end
	espCache = {}
	for plr in pairs(fallbackCache) do fallbackRemove(plr) end
	destroyDraw(fovCircle)
	if CFG.MISC.FOVCamera then
		local cam = Workspace.CurrentCamera
		if cam then cam.FieldOfView = 70 end
	end
	log("[Zaka] 已卸载")
	_G.ZakaUnload = nil
end

-- ============================ 起飞 ============================
if CFG.MISC.FOVCamera then
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = CFG.MISC.FOVCamera end
end

RunService.RenderStepped:Connect(function()
	if not RUNNING then return end
	local ok, err = pcall(function()
		renderESP()
		doAim()
	end)
	if not ok and not _G.__zaka_err_logged then
		_G.__zaka_err_logged = true
		log("[Zaka] 运行错误（已忽略，不影响继续跑）:", err)
	end
end)

log("[Zaka] ESP + Aimbot 已加载")
log("  RightShift = ESP 开关 | End = 卸载 | "
	.. (CFG.AIM.ToggleMode and "右键切换自瞄" or "按住右键自瞄"))
if not HAS_DRAWING then
	log("  未检测到 Drawing，已退化为 Highlight 模式（无方框/射线/骨骼）")
end
if not mousemoverel then
	log("  未检测到 mousemoverel，自瞄走相机转向模式")
end
