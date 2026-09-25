-- ============================================================
--  Rivals 零卡頓版  (Fixed)
-- ============================================================
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local Workspace      = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local camera      = Workspace.CurrentCamera

local Config = {
    Box      = true,  Name    = true,  Dist   = true,  Health = true,
    Skeleton = true,  Tracer  = true,  Aimbot = true,  Fly    = false,
    AimFOV   = 180,   MaxDist = 300,
    AimSmooth = 0.88,   -- 自瞄強度 (0–1, 越高越快鎖定)
}

-- ── 效能優化 ───────────────────────────────────────────────
task.spawn(function()
    pcall(function()
        local l = game:GetService("Lighting")
        l.GlobalShadows = false
        l.FogEnd        = 9e9
        for _, v in ipairs(l:GetChildren()) do
            if v:IsA("PostEffect") then v.Enabled = false end
        end
    end)
end)

-- ── 清理舊 GUI，防止重複執行時堆疊 ───────────────────────
for _, name in ipairs({"Rivals_PersistentGUI", "Rivals_PersistentESP"}) do
    local old = localPlayer.PlayerGui:FindFirstChild(name)
    if old then old:Destroy() end
end

-- ══════════════════════════════════════════════════════════
--  控制面板 GUI
-- ══════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name            = "Rivals_PersistentGUI"
gui.ResetOnSpawn    = false
gui.IgnoreGuiInset  = true
gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
gui.Parent          = localPlayer:WaitForChild("PlayerGui")

-- 主框架
local frame = Instance.new("Frame", gui)
frame.Size            = UDim2.new(0, 260, 0, 360)
frame.Position        = UDim2.new(0, 50, 0, 40)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

-- 標題列
local bar = Instance.new("Frame", frame)
bar.Size            = UDim2.new(1, 0, 0, 32)
bar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
bar.BorderSizePixel = 0
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

local tLbl = Instance.new("TextLabel", bar)
tLbl.Size               = UDim2.new(1, -70, 1, 0)
tLbl.Position           = UDim2.new(0, 10, 0, 0)
tLbl.BackgroundTransparency = 1
tLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
tLbl.Font               = Enum.Font.GothamBold
tLbl.TextSize           = 12
tLbl.Text               = "Rivals 零卡頓版"
tLbl.TextXAlignment     = Enum.TextXAlignment.Left

-- ── 面板拖曳 ─────────────────────────────────────────────
local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

bar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ── 捲動區 ───────────────────────────────────────────────
local ctn = Instance.new("ScrollingFrame", frame)
ctn.Size                = UDim2.new(1, 0, 1, -32)
ctn.Position            = UDim2.new(0, 0, 0, 32)
ctn.BackgroundTransparency = 1
ctn.CanvasSize          = UDim2.new(0, 0, 0, 395)
ctn.ScrollBarThickness  = 4
ctn.BorderSizePixel     = 0

-- 最小化 / 關閉按鈕
local minB = Instance.new("TextButton", bar)
minB.Size            = UDim2.new(0, 26, 0, 24)
minB.Position        = UDim2.new(1, -60, 0, 4)
minB.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
minB.TextColor3      = Color3.fromRGB(255, 255, 255)
minB.Text            = "-"
minB.BorderSizePixel = 0
Instance.new("UICorner", minB).CornerRadius = UDim.new(0, 4)

local clsB = Instance.new("TextButton", bar)
clsB.Size            = UDim2.new(0, 26, 0, 24)
clsB.Position        = UDim2.new(1, -30, 0, 4)
clsB.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
clsB.TextColor3      = Color3.fromRGB(255, 255, 255)
clsB.Text            = "X"
clsB.BorderSizePixel = 0
Instance.new("UICorner", clsB).CornerRadius = UDim.new(0, 4)

local minimized = false
minB.MouseButton1Click:Connect(function()
    minimized     = not minimized
    ctn.Visible   = not minimized
    frame.Size    = minimized and UDim2.new(0, 260, 0, 32) or UDim2.new(0, 260, 0, 360)
    minB.Text     = minimized and "+" or "-"
end)

-- 重開按鈕（右側懸浮圓形）
local opB = Instance.new("TextButton", gui)
opB.Size            = UDim2.new(0, 42, 0, 42)
opB.Position        = UDim2.new(0, 10, 0, 180)
opB.BackgroundColor3 = Color3.fromRGB(180, 50, 255)
opB.TextColor3      = Color3.fromRGB(255, 255, 255)
opB.Text            = "UI"
opB.Visible         = false
opB.BorderSizePixel = 0
Instance.new("UICorner", opB).CornerRadius = UDim.new(1, 0)

clsB.MouseButton1Click:Connect(function() frame.Visible = false; opB.Visible = true  end)
opB.MouseButton1Click:Connect(function()  frame.Visible = true;  opB.Visible = false end)

-- ── 功能開關按鈕工廠 ─────────────────────────────────────
local function mkBtn(label, yOff, key)
    local b = Instance.new("TextButton", ctn)
    b.Size            = UDim2.new(0, 220, 0, 32)
    b.Position        = UDim2.new(0, 20, 0, yOff)
    b.BackgroundColor3 = Config[key] and Color3.fromRGB(60, 180, 100) or Color3.fromRGB(180, 60, 60)
    b.TextColor3      = Color3.fromRGB(255, 255, 255)
    b.Font            = Enum.Font.GothamBold
    b.TextSize        = 12
    b.Text            = label .. ": " .. (Config[key] and "開啟" or "關閉")
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        b.BackgroundColor3 = Config[key] and Color3.fromRGB(60, 180, 100) or Color3.fromRGB(180, 60, 60)
        b.Text = label .. ": " .. (Config[key] and "開啟" or "關閉")
    end)
    return b
end

mkBtn("ESP 方框", 10,  "Box")
mkBtn("玩家名字", 50,  "Name")
mkBtn("距離顯示", 90,  "Dist")
mkBtn("血條顯示", 130, "Health")
mkBtn("骨架透視", 170, "Skeleton")
mkBtn("底部射線", 210, "Tracer")
mkBtn("極致自瞄", 250, "Aimbot")
mkBtn("飛行模式", 290, "Fly")

-- ── FOV 滑桿 ─────────────────────────────────────────────
local fLbl = Instance.new("TextLabel", ctn)
fLbl.Size               = UDim2.new(0, 220, 0, 18)
fLbl.Position           = UDim2.new(0, 20, 0, 335)
fLbl.BackgroundTransparency = 1
fLbl.TextColor3         = Color3.fromRGB(220, 220, 220)
fLbl.Font               = Enum.Font.GothamBold
fLbl.TextSize           = 11
fLbl.Text               = "FOV 範圍: " .. Config.AimFOV

local sBar = Instance.new("Frame", ctn)
sBar.Size            = UDim2.new(0, 220, 0, 8)
sBar.Position        = UDim2.new(0, 20, 0, 360)
sBar.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
sBar.BorderSizePixel = 0
Instance.new("UICorner", sBar).CornerRadius = UDim.new(1, 0)

-- FIX: 初始滑桿位置按照 Config.AimFOV 計算 (FOV 範圍 60–360)
local initScale = math.clamp((Config.AimFOV - 60) / 300, 0, 1)

local sBtn = Instance.new("TextButton", sBar)
sBtn.Size            = UDim2.new(0, 18, 0, 22)
sBtn.AnchorPoint     = Vector2.new(0.5, 0.5)
sBtn.Position        = UDim2.new(initScale, 0, 0.5, 0)
sBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 255)
sBtn.Text            = ""
sBtn.BorderSizePixel = 0
Instance.new("UICorner", sBtn).CornerRadius = UDim.new(1, 0)

local draggingSlider = false
sBtn.MouseButton1Down:Connect(function() draggingSlider = true end)

UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = false
    end
end)

UserInputService.InputChanged:Connect(function(i)
    if draggingSlider and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local barPos  = sBar.AbsolutePosition.X
        local barSize = sBar.AbsoluteSize.X
        local scale   = math.clamp((i.Position.X - barPos) / barSize, 0, 1)
        sBtn.Position   = UDim2.new(scale, 0, 0.5, 0)
        Config.AimFOV   = math.floor(60 + scale * 300)
        fLbl.Text       = "FOV 範圍: " .. Config.AimFOV
    end
end)

-- ══════════════════════════════════════════════════════════
--  ESP ScreenGui
-- ══════════════════════════════════════════════════════════
local rGui = Instance.new("ScreenGui")
rGui.Name           = "Rivals_PersistentESP"
rGui.ResetOnSpawn   = false
rGui.IgnoreGuiInset = true
rGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
rGui.Parent         = localPlayer:WaitForChild("PlayerGui")

-- FOV 圓圈
local fovC = Instance.new("Frame", rGui)
fovC.AnchorPoint        = Vector2.new(0.5, 0.5)
fovC.BackgroundTransparency = 1
fovC.BorderSizePixel    = 0
Instance.new("UICorner", fovC).CornerRadius = UDim.new(1, 0)
local fStr = Instance.new("UIStroke", fovC)
fStr.Color       = Color3.fromRGB(180, 50, 255)
fStr.Transparency = 0.5
fStr.Thickness   = 1.5

-- 底部射線 (Tracer)
local tracer = Instance.new("Frame", rGui)
tracer.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
tracer.AnchorPoint      = Vector2.new(0.5, 0.5)
tracer.BorderSizePixel  = 0
tracer.Visible          = false

-- ── ESP 視覺資料存放 ─────────────────────────────────────
local visuals = {}

local function isEnemy(p)
    if p == localPlayer then return false end
    if localPlayer.Team and p.Team and localPlayer.Team == p.Team then return false end
    return true
end

local function getVisual(p)
    if visuals[p] then return visuals[p] end

    local f    = Instance.new("Folder", rGui); f.Name = p.Name

    -- 方框
    local box  = Instance.new("Frame", f)
    box.BackgroundTransparency = 1
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.BorderSizePixel = 0
    local bStr = Instance.new("UIStroke", box)
    bStr.Color     = Color3.fromRGB(255, 50, 50)
    bStr.Thickness = 1.8

    -- 名字
    local name = Instance.new("TextLabel", f)
    name.BackgroundTransparency = 1
    name.Font                   = Enum.Font.GothamBold
    name.TextSize               = 11
    name.TextColor3             = Color3.fromRGB(255, 255, 255)
    name.TextStrokeTransparency = 0
    name.Size                   = UDim2.new(0, 150, 0, 15)
    name.AnchorPoint            = Vector2.new(0.5, 1)

    -- 距離
    local dist = Instance.new("TextLabel", f)
    dist.BackgroundTransparency = 1
    dist.Font                   = Enum.Font.Gotham
    dist.TextSize               = 10
    dist.TextColor3             = Color3.fromRGB(255, 80, 80)
    dist.TextStrokeTransparency = 0
    dist.Size                   = UDim2.new(0, 150, 0, 15)
    dist.AnchorPoint            = Vector2.new(0.5, 0)

    -- 血條背景
    local hBg = Instance.new("Frame", f)
    hBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    hBg.BorderSizePixel  = 0
    hBg.AnchorPoint      = Vector2.new(1, 0)

    local hBar = Instance.new("Frame", hBg)
    hBar.BackgroundColor3 = Color3.fromRGB(0, 220, 80)
    hBar.BorderSizePixel  = 0
    hBar.AnchorPoint      = Vector2.new(0, 1)
    hBar.Position         = UDim2.new(0, 0, 1, 0)

    -- 骨架線段（10 條）
    local skel = {}
    for i = 1, 10 do
        local l = Instance.new("Frame", f)
        l.AnchorPoint      = Vector2.new(0.5, 0.5)
        l.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        l.BorderSizePixel  = 0
        l.Visible          = false
        skel[i] = l
    end

    visuals[p] = {folder=f, box=box, name=name, dist=dist, hBg=hBg, hBar=hBar, skel=skel}
    return visuals[p]
end

-- 骨架關節連接定義
local links = {
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},
    {"UpperTorso","RightUpperArm"},
    {"RightUpperArm","RightLowerArm"},
    {"LowerTorso","LeftUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},
    {"LowerTorso","RightUpperLeg"},
    {"RightUpperLeg","RightLowerLeg"},
}

-- 飛行用物件
local bv, bg = nil, nil
local lockedTarget = nil

-- ══════════════════════════════════════════════════════════
--  主渲染迴圈
-- ══════════════════════════════════════════════════════════
RunService:BindToRenderStep("TruePerfectFlyAndESP", Enum.RenderPriority.Camera.Value + 1, function()
    local myChar = localPlayer.Character
    local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local vp    = camera.ViewportSize

    -- ── 飛行 ─────────────────────────────────────────────
    if Config.Fly and myHrp and humanoid then
        if not bv or bv.Parent ~= myHrp then
            if bv then pcall(function() bv:Destroy() end) end
            if bg then pcall(function() bg:Destroy() end) end
            bv = Instance.new("BodyVelocity", myHrp)
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Velocity = Vector3.new(0, 0, 0)
            bg = Instance.new("BodyGyro", myHrp)
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.P = 9e4
        end
        humanoid.PlatformStand = true
        local camCF      = camera.CFrame
        local camRight   = camCF.RightVector
        local flatFwd    = Vector3.new(0, 1, 0):Cross(camRight).Unit
        local moveDir    = humanoid.MoveDirection
        local fwdInput   = moveDir:Dot(flatFwd)
        local rightInput = moveDir:Dot(camRight)
        bv.Velocity = (camCF.LookVector * fwdInput + camRight * rightInput) * 50
        bg.CFrame   = camCF
    else
        if bv then pcall(function() bv:Destroy() end); bv = nil end
        if bg then pcall(function() bg:Destroy() end); bg = nil end
        if humanoid and humanoid.PlatformStand then
            humanoid.PlatformStand = false
        end
    end

    -- FOV 圓圈位置
    fovC.Size     = UDim2.new(0, Config.AimFOV * 2, 0, Config.AimFOV * 2)
    fovC.Position = UDim2.new(0, math.floor(vp.X / 2), 0, math.floor(vp.Y / 2))

    if not myHrp then
        tracer.Visible = false
        return
    end
    local myPos = myHrp.Position

    -- ── Aimbot ───────────────────────────────────────────
    if Config.Aimbot then
        local bestHead = nil
        local mDst     = Config.AimFOV

        -- 持續鎖定檢查
        if lockedTarget and lockedTarget.Parent
        and lockedTarget:FindFirstChild("Humanoid")
        and lockedTarget.Humanoid.Health > 0 then
            local head = lockedTarget:FindFirstChild("Head")
            local hrp  = lockedTarget:FindFirstChild("HumanoidRootPart")
            if head and hrp and (hrp.Position - myPos).Magnitude <= Config.MaxDist then
                local pos, vis = camera:WorldToViewportPoint(head.Position)
                if vis and pos.Z > 0 then
                    local dC = (Vector2.new(pos.X, pos.Y) - Vector2.new(vp.X/2, vp.Y/2)).Magnitude
                    if dC <= Config.AimFOV then
                        bestHead = head
                    end
                end
            end
        end

        -- 尋找新目標
        if not bestHead then
            lockedTarget = nil
            for _, p in ipairs(Players:GetPlayers()) do
                if isEnemy(p) and p.Character then
                    local c    = p.Character
                    local hum  = c:FindFirstChildOfClass("Humanoid")
                    local hrp  = c:FindFirstChild("HumanoidRootPart")
                    local head = c:FindFirstChild("Head")
                    if hum and hum.Health > 0 and hrp and head then
                        if (hrp.Position - myPos).Magnitude <= Config.MaxDist then
                            local pos, isVis = camera:WorldToViewportPoint(head.Position)
                            if isVis and pos.Z > 0 then
                                local dC = (Vector2.new(pos.X, pos.Y) - Vector2.new(vp.X/2, vp.Y/2)).Magnitude
                                if dC < mDst then
                                    mDst         = dC
                                    bestHead     = head
                                    lockedTarget = c
                                end
                            end
                        end
                    end
                end
            end
        end

        if bestHead then
            camera.CFrame = camera.CFrame:Lerp(
                CFrame.lookAt(camera.CFrame.Position, bestHead.Position),
                Config.AimSmooth
            )
        else
            lockedTarget = nil
        end
    else
        lockedTarget = nil
    end

    -- ── ESP ──────────────────────────────────────────────
    local nearestPlayer = nil
    local nearestDist   = math.huge
    local nearestBotPos = nil

    local currentValidPlayers = {}

    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) and p.Character then
            local c    = p.Character
            local hum  = c:FindFirstChildOfClass("Humanoid")
            local hrp  = c:FindFirstChild("HumanoidRootPart")
            local head = c:FindFirstChild("Head")

            if hum and hum.Health > 0 and hrp and head then
                local dist3D = (hrp.Position - myPos).Magnitude
                if dist3D <= Config.MaxDist then
                    -- FIX: 正確解構 WorldToViewportPoint 回傳值
                    local rootPos, rootVis = camera:WorldToViewportPoint(hrp.Position)
                    if rootVis and rootPos.Z > 0 then
                        currentValidPlayers[p] = true
                        local dat = getVisual(p)

                        -- FIX: 同樣正確解構 head/leg 位置
                        local headPos3, _ = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local legPos3,  _ = camera:WorldToViewportPoint(hrp.Position  - Vector3.new(0, 3,   0))

                        local h  = math.max(1, math.floor(math.abs(headPos3.Y - legPos3.Y)))
                        local w  = math.max(1, math.floor(h * 0.55))
                        local cx = math.floor(rootPos.X)
                        local cy = math.floor((headPos3.Y + legPos3.Y) / 2)
                        local topY = math.floor(cy - h / 2)
                        local botY = math.floor(cy + h / 2)

                        -- 記錄最近玩家（用於 Tracer）
                        if dist3D < nearestDist then
                            nearestDist   = dist3D
                            nearestPlayer = p
                            nearestBotPos = Vector2.new(cx, botY)
                        end

                        -- 方框
                        dat.box.Visible = Config.Box
                        if Config.Box then
                            dat.box.Position = UDim2.new(0, cx, 0, cy)
                            dat.box.Size     = UDim2.new(0, w,  0, h)
                        end

                        -- 名字
                        dat.name.Visible = Config.Name
                        if Config.Name then
                            dat.name.Text     = p.DisplayName
                            dat.name.Position = UDim2.new(0, cx, 0, topY - 5)
                        end

                        -- 距離
                        dat.dist.Visible = Config.Dist
                        if Config.Dist then
                            dat.dist.Text     = string.format("[%dm]", math.floor(dist3D))
                            dat.dist.Position = UDim2.new(0, cx, 0, botY + 2)
                        end

                        -- 血條
                        dat.hBg.Visible = Config.Health
                        if Config.Health then
                            local pct      = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                            local barW     = math.clamp(math.floor(w * 0.08), 2, 4)
                            dat.hBg.Size   = UDim2.new(0, barW, 0, h)
                            dat.hBg.Position = UDim2.new(0, cx - math.floor(w / 2) - barW - 2, 0, topY)
                            dat.hBar.Size  = UDim2.new(1, 0, pct, 0)
                            -- 血量顏色漸變：綠→黃→紅
                            dat.hBar.BackgroundColor3 = Color3.fromRGB(
                                math.floor((1 - pct) * 255),
                                math.floor(pct * 220),
                                0
                            )
                        end

                        -- 骨架
                        if Config.Skeleton then
                            for i, ln in ipairs(links) do
                                local l    = dat.skel[i]
                                local pt1  = c:FindFirstChild(ln[1])
                                local pt2  = c:FindFirstChild(ln[2])
                                if pt1 and pt2 then
                                    local v1, v1s = camera:WorldToViewportPoint(pt1.Position)
                                    local v2, v2s = camera:WorldToViewportPoint(pt2.Position)
                                    if (v1s or v2s) and v1.Z > 0 and v2.Z > 0 then
                                        local dx  = v2.X - v1.X
                                        local dy  = v2.Y - v1.Y
                                        local len = math.max(1, math.floor(math.sqrt(dx*dx + dy*dy)))
                                        l.Visible  = true
                                        l.Size     = UDim2.new(0, len, 0, 1)
                                        l.Position = UDim2.new(0, math.floor((v1.X + v2.X) / 2), 0, math.floor((v1.Y + v2.Y) / 2))
                                        l.Rotation = math.deg(math.atan2(dy, dx))
                                    else
                                        l.Visible = false
                                    end
                                else
                                    l.Visible = false
                                end
                            end
                        else
                            for _, l in ipairs(dat.skel) do l.Visible = false end
                        end
                    end
                end
            end
        end
    end

    -- ── 清理不在視野或已死亡的 ESP ──────────────────────
    -- FIX: 安全遍歷，避免在迭代中修改 table 導致問題
    local toRemove = {}
    for p, dat in pairs(visuals) do
        if not currentValidPlayers[p] then
            dat.box.Visible  = false
            dat.name.Visible = false
            dat.dist.Visible = false
            dat.hBg.Visible  = false
            for _, l in ipairs(dat.skel) do l.Visible = false end
            if not p.Parent then
                toRemove[p] = dat
            end
        end
    end
    for p, dat in pairs(toRemove) do
        pcall(function() dat.folder:Destroy() end)
        visuals[p] = nil
    end

    -- ── 底部射線 ─────────────────────────────────────────
    if Config.Tracer and nearestBotPos then
        local sx   = math.floor(vp.X / 2)
        local sy   = math.floor(vp.Y)
        local dx   = nearestBotPos.X - sx
        local dy   = nearestBotPos.Y - sy
        -- FIX: math.max(1, ...) 防止長度為 0
        local len  = math.max(1, math.floor(math.sqrt(dx*dx + dy*dy)))
        tracer.Visible  = true
        tracer.Size     = UDim2.new(0, len, 0, 2)
        tracer.Position = UDim2.new(0, math.floor((sx + nearestBotPos.X) / 2), 0, math.floor((sy + nearestBotPos.Y) / 2))
        tracer.Rotation = math.deg(math.atan2(dy, dx))
    else
        tracer.Visible = false
    end
end)
