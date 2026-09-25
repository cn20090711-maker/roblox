// Safe Pure ESP (絕對安全 ESP) – 修復版
-- 這個腳本不會對角色造成任何物理干擾，僅使用純 GUI 繪製 2D 方框、骨架、血條與最近敵人體感線。
-- 修正要點：
--   1. 使用安全的 GUI 父容器 (CoreGui/PlayerGui)；若 gethui 不存在則自動回退。
--   2. 針對部分 API 可能返回 nil 的情況加上防護，避免執行時拋出錯誤。
--   3. 確保最近敵人的血條與方框在畫面邊界外時仍能正常隱藏。
--   4. 清晰的註解與可配置參數。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ================= 設定區 =================
local MAX_DISTANCE = 500 -- 超出此距離的玩家不會被顯示
local PURPLE_COLOR = Color3.fromRGB(180, 50, 255)
local LINE_THICKNESS = 1.5

-- ================= 建立 GUI (絕對安全寫法) =================
-- 盡可能使用 CoreGui，若無法取得則回退到 PlayerGui。
local function getGuiParent()
    if gethui then
        return gethui()
    else
        return localPlayer:WaitForChild("PlayerGui")
    end
end

local guiParent = getGuiParent()
local guiName = "Safe_Pure_ESP"

if guiParent:FindFirstChild(guiName) then
    guiParent[guiName]:Destroy()
end

local espGui = Instance.new("ScreenGui")
espGui.Name = guiName
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.Parent = guiParent

local nearestTracer = Instance.new("Frame")
nearestTracer.BackgroundColor3 = PURPLE_COLOR
nearestTracer.AnchorPoint = Vector2.new(0.5, 0.5)
nearestTracer.BorderSizePixel = 0
nearestTracer.Visible = false
nearestTracer.Parent = espGui

local playerVisuals = {}

local function drawLine(frame, p1, p2, color, thickness)
    local distance = (p1 - p2).Magnitude
    local center = (p1 + p2) / 2
    frame.Position = UDim2.new(0, center.X, 0, center.Y)
    frame.Size = UDim2.new(0, distance, 0, thickness or LINE_THICKNESS)
    frame.Rotation = math.deg(math.atan2(p2.Y - p1.Y, p2.X - p1.X))
    if color then frame.BackgroundColor3 = color end
end

local skeletonLinks = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}

local function createVisual(player)
    if playerVisuals[player] then return end
    local container = Instance.new("Folder")
    container.Name = player.Name
    container.Parent = espGui

    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    local stroke = Instance.new("UIStroke")
    stroke.Color = PURPLE_COLOR
    stroke.Thickness = LINE_THICKNESS
    stroke.Parent = box
    box.Parent = container

    local healthBarBg = Instance.new("Frame")
    healthBarBg.BackgroundColor3 = Color3.new(0, 0, 0)
    healthBarBg.BorderSizePixel = 0
    healthBarBg.AnchorPoint = Vector2.new(1, 0) -- 右上角對齊
    healthBarBg.Parent = container

    local healthBar = Instance.new("Frame")
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthBar.BorderSizePixel = 0
    healthBar.AnchorPoint = Vector2.new(0, 1) -- 左下角對齊
    healthBar.Position = UDim2.new(0, 0, 1, 0)
    healthBar.Parent = healthBarBg

    local skeletonLines = {}
    for _ = 1, #skeletonLinks do
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.BackgroundColor3 = PURPLE_COLOR
        line.Visible = false
        line.Parent = container
        table.insert(skeletonLines, line)
    end

    playerVisuals[player] = {
        container = container,
        box = box,
        healthBarBg = healthBarBg,
        healthBar = healthBar,
        skeletonLines = skeletonLines,
    }
end

local function removeVisual(player)
    if playerVisuals[player] then
        playerVisuals[player].container:Destroy()
        playerVisuals[player] = nil
    end
end

-- 初始化現有玩家（不含自己）
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= localPlayer then
        createVisual(player)
    end
end
Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        createVisual(player)
    end
end)
Players.PlayerRemoving:Connect(removeVisual)

local function getHealthColor(percentage)
    if percentage > 0.5 then
        return Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 255, 0), (1 - percentage) * 2)
    else
        return Color3.fromRGB(255, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), (0.5 - percentage) * 2)
    end
end

-- ================= 純 ESP 更新迴圈 (絕不亂飛) =================
RunService.RenderStepped:Connect(function()
    local myChar = localPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end

    local viewportSize = camera.ViewportSize
    local tracerOrigin = Vector2.new(viewportSize.X / 2, viewportSize.Y) -- 画面底部中间

    local nearestPlayer = nil
    local nearestLegScreenPos = nil

    for player, data in pairs(playerVisuals) do
        local isVisible = false
        if player.Character then
            local character = player.Character
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")
            local isEnemy = (localPlayer.Team == nil) or (player.Team ~= localPlayer.Team)

            if humanoid and humanoid.Health > 0 and hrp and head and isEnemy then
                local myPos = myHrp.Position
                local enemyPos = hrp.Position
                local dist = (enemyPos - myPos).Magnitude

                if dist <= MAX_DISTANCE then
                    local headPos = head.Position + Vector3.new(0, 0.5, 0)
                    local legPos = enemyPos - Vector3.new(0, 3, 0) -- 大約腳的高度

                    local headVec, headOnScreen = camera:WorldToViewportPoint(headPos)
                    local legVec, _ = camera:WorldToViewportPoint(legPos)
                    local hrpVec, hrpOnScreen = camera:WorldToViewportPoint(enemyPos)

                    if headOnScreen or hrpOnScreen then
                        isVisible = true
                        local screenHead = Vector2.new(headVec.X, headVec.Y)
                        local screenLeg = Vector2.new(legVec.X, legVec.Y)

                        if not nearestPlayer or dist < (nearestPlayer.Character.HumanoidRootPart.Position - myPos).Magnitude then
                            nearestPlayer = player
                            nearestLegScreenPos = screenLeg
                        end

                        local boxHeight = math.abs(screenHead.Y - screenLeg.Y)
                        local boxWidth = boxHeight * 0.55
                        local boxCenter = (screenHead + screenLeg) / 2
                        data.box.Position = UDim2.new(0, boxCenter.X, 0, boxCenter.Y)
                        data.box.Size = UDim2.new(0, boxWidth, 0, boxHeight)

                        local hpPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                        local barWidth = math.max(2, boxWidth * 0.08)
                        local barPadding = math.max(2, boxWidth * 0.05)
                        data.healthBarBg.Size = UDim2.new(0, barWidth, 0, boxHeight)
                        data.healthBarBg.Position = UDim2.new(0, boxCenter.X - (boxWidth / 2) - barPadding, 0, screenHead.Y - boxHeight / 2)
                        data.healthBar.Size = UDim2.new(1, 0, hpPercent, 0)
                        data.healthBar.BackgroundColor3 = getHealthColor(hpPercent)

                        -- R15 骨架繪製
                        local isR15 = character:FindFirstChild("UpperTorso") ~= nil
                        for i, line in ipairs(data.skeletonLines) do
                            local link = skeletonLinks[i]
                            if link and isR15 then
                                local part1 = character:FindFirstChild(link[1])
                                local part2 = character:FindFirstChild(link[2])
                                if part1 and part2 then
                                    local p1Vec, p1OnScreen = camera:WorldToViewportPoint(part1.Position)
                                    local p2Vec, p2OnScreen = camera:WorldToViewportPoint(part2.Position)
                                    if p1OnScreen or p2OnScreen then
                                        line.Visible = true
                                        drawLine(line, Vector2.new(p1Vec.X, p1Vec.Y), Vector2.new(p2Vec.X, p2Vec.Y), PURPLE_COLOR, 1)
                                    else
                                        line.Visible = false
                                    end
                                else
                                    line.Visible = false
                                end
                            else
                                line.Visible = false
                            end
                        end
                    end
                end
            end
        end
        data.box.Visible = isVisible
        data.healthBarBg.Visible = isVisible
        if not isVisible then
            for _, line in ipairs(data.skeletonLines) do
                line.Visible = false
            end
        end
    end

    if nearestPlayer and nearestLegScreenPos then
        nearestTracer.Visible = true
        drawLine(nearestTracer, tracerOrigin, nearestLegScreenPos, PURPLE_COLOR, LINE_THICKNESS)
    else
        nearestTracer.Visible = false
    end
end)
