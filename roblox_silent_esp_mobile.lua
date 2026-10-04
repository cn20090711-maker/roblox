if _G.ZakaSAUnload then pcall(_G.ZakaSAUnload) end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local CFG = { Enabled=true, FOV=250, TargetPart="Head", TeamCheck=true, MaxDist=1200, Predict=0.0, WallCheck=false, CacheTime=0.02, HookNamecall=true, HookCachedFn=true, HookMouse=true, DrawFOV=true, FOVColor=Color3.fromRGB(150,255,150), ESP_Enabled=true, ESP_Boxes=true, ESP_Info=true, ESP_Color=Color3.fromRGB(255,50,50), ESP_Team=false }

local DRAWING = Drawing or (getgenv and getgenv().Drawing)
local HAS_DRAWING = type(DRAWING) == "table" and type(DRAWING.new) == "function"
local RUNNING, ON, BUSY, fovCircle, espObjects = true, CFG.Enabled, false, nil, {}

local sg = Instance.new("ScreenGui")
sg.Name, sg.ResetOnSpawn = "MobileSA_UI", false
pcall(function() sg.Parent = CoreGui end)
if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame", sg)
frame.Size, frame.Position, frame.BackgroundColor3 = UDim2.new(0,150,0,90), UDim2.new(0,50,0,50), Color3.fromRGB(30,30,30)
frame.Active, frame.Draggable = true, true

local title = Instance.new("TextLabel", frame)
title.Size, title.BackgroundTransparency, title.TextColor3, title.Text, title.TextSize, title.Font = UDim2.new(1,0,0,25), 1, Color3.new(1,1,1), "Silent Aim (拖曳)", 14, Enum.Font.Code

local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size, toggleBtn.Position, toggleBtn.TextColor3, toggleBtn.TextSize, toggleBtn.Font = UDim2.new(0.9,0,0,25), UDim2.new(0.05,0,0,30), Color3.new(1,1,1), 14, Enum.Font.Code
toggleBtn.BackgroundColor3 = ON and Color3.fromRGB(50,150,50) or Color3.fromRGB(150,50,50)
toggleBtn.Text = ON and "狀態: 開啟" or "狀態: 關閉"

local unloadBtn = Instance.new("TextButton", frame)
unloadBtn.Size, unloadBtn.Position, unloadBtn.BackgroundColor3, unloadBtn.TextColor3, unloadBtn.Text, unloadBtn.TextSize, unloadBtn.Font = UDim2.new(0.9,0,0,25), UDim2.new(0.05,0,0,60), Color3.fromRGB(80,80,80), Color3.new(1,1,1), "卸載腳本", 14, Enum.Font.Code

toggleBtn.MouseButton1Click:Connect(function()
    ON = not ON
    toggleBtn.BackgroundColor3 = ON and Color3.fromRGB(50,150,50) or Color3.fromRGB(150,50,50)
    toggleBtn.Text = ON and "狀態: 開啟" or "狀態: 關閉"
end)

unloadBtn.MouseButton1Click:Connect(function() if _G.ZakaSAUnload then _G.ZakaSAUnload() end end)

local function getChar(plr)
    local c = plr.Character
    if not c then return nil end
    local h, r = c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return c, h, r end
    return nil
end

local function sameTeam(plr)
    if not CFG.TeamCheck then return false end
    return plr.Team and LP.Team and plr.Team == LP.Team
end

local function createEsp(plr)
    if not HAS_DRAWING or espObjects[plr] then return end
    local box, info = DRAWING.new("Square"), DRAWING.new("Text")
    box.Visible, box.Color, box.Thickness, box.Transparency, box.Filled = false, CFG.ESP_Color, 1, 1, false
    info.Visible, info.Color, info.Size, info.Center, info.Outline = false, CFG.ESP_Color, 14, true, true
    espObjects[plr] = { Box = box, Info = info }
end

local function removeEsp(plr)
    if espObjects[plr] then espObjects[plr].Box:Remove(); espObjects[plr].Info:Remove(); espObjects[plr] = nil end
end

Players.PlayerAdded:Connect(createEsp)
Players.PlayerRemoving:Connect(removeEsp)
for _, v in ipairs(Players:GetPlayers()) do if v ~= LP then createEsp(v) end end

local function pickAimPoint(origin)
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local camPos = cam.CFrame.Position
    local best, bestScore = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and not sameTeam(plr) then
            local char, hum, hrp = getChar(plr)
            if char then
                local part = char:FindFirstChild(CFG.TargetPart) or hrp
                local pos = part.Position + (CFG.Predict > 0 and part.AssemblyLinearVelocity * CFG.Predict or Vector3.zero)
                if (camPos - hrp.Position).Magnitude <= CFG.MaxDist then
                    local sp, onScreen = cam:WorldToViewportPoint(pos)
                    if onScreen and sp.Z > 0 then
                        local score = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if score <= CFG.FOV and score < bestScore then bestScore, best = score, pos end
                    end
                end
            end
        end
    end
    return best
end

local _cacheAt, _cachePos = 0, nil
local function aimPointCached(origin)
    local now = os.clock()
    if CFG.CacheTime > 0 and (now - _cacheAt) < CFG.CacheTime then return _cachePos end
    _cacheAt, _cachePos = now, pickAimPoint(origin)
    return _cachePos
end

local function redirect(origin, dir)
    if BUSY or not RUNNING or not ON or typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return nil end
    local tpos = aimPointCached(origin)
    if not tpos then return nil end
    return (tpos - origin).Unit * math.max(dir.Magnitude, 1)
end

local function rewriteArgs(method, args)
    local origin, dir, isRay = nil, nil, false
    if method == "Raycast" then origin, dir = args[1], args[2] else
        local ray = args[1]
        if typeof(ray) == "Ray" then origin, dir, isRay = ray.Origin, ray.Direction, true end
    end
    if not origin or not dir then return false end
    local newDir = redirect(origin, dir)
    if not newDir then return false end
    if isRay then args[1] = Ray.new(origin, newDir) else args[2] = newDir end
    return true
end

local RAY_METHODS = { Raycast = true, FindPartOnRay = true, FindPartOnRayWithIgnoreList = true, FindPartOnRayWithWhitelist = true }
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if not RUNNING then return oldNamecall(self, ...) end
    local method = getnamecallmethod()
    if CFG.HookNamecall and RAY_METHODS[method] then
        local args = table.pack(...)
        if rewriteArgs(method, args) then return oldNamecall(self, table.unpack(args, 1, args.n)) end
    end
    return oldNamecall(self, ...)
end)

local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if not RUNNING then return oldIndex(self, key) end
    if CFG.HookCachedFn and RAY_METHODS[key] then
        local ok, isWs = pcall(function() return self == Workspace end)
        if ok and isWs then
            local orig = oldIndex(self, key)
            if typeof(orig) == "function" then
                return newcclosure(function(s, ...)
                    local args = table.pack(...)
                    if rewriteArgs(key, args) then return orig(s, table.unpack(args, 1, args.n)) end
                    return orig(s, ...)
                end)
            end
        end
    end
    if CFG.HookMouse and (key == "UnitRay" or key == "Hit") then
        local ok, cls = pcall(function() return self.ClassName end)
        if ok and cls == "Mouse" then
            local cam = Workspace.CurrentCamera
            if cam then
                local tpos = aimPointCached(cam.CFrame.Position)
                if tpos then
                    if key == "UnitRay" then return Ray.new(cam.CFrame.Position, (tpos - cam.CFrame.Position).Unit * 1000) end
                    return CFrame.new(tpos)
                end
            end
        end
    end
    return oldIndex(self, key)
end)

RunService.RenderStepped:Connect(function()
    if not RUNNING then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    
    if HAS_DRAWING then
        if not fovCircle then pcall(function() fovCircle = DRAWING.new("Circle") end) end
        if fovCircle then
            pcall(function()
                fovCircle.Visible, fovCircle.Position, fovCircle.Radius, fovCircle.Color, fovCircle.Thickness, fovCircle.Transparency, fovCircle.NumSides, fovCircle.Filled = (CFG.DrawFOV and ON), center, CFG.FOV, CFG.FOVColor, 1, 1, 60, false
            end)
        end
        if CFG.ESP_Enabled then
            for plr, esp in pairs(espObjects) do
                local char, hum, hrp = getChar(plr)
                if char and (CFG.ESP_Team or not sameTeam(plr)) then
                    local head = char:FindFirstChild("Head")
                    if head then
                        local rootPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                        local headPos = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local legPos = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                        if onScreen then
                            local height = math.abs(headPos.Y - legPos.Y)
                            local width = height / 2
                            esp.Box.Size, esp.Box.Position, esp.Box.Visible = Vector2.new(width, height), Vector2.new(rootPos.X - width / 2, headPos.Y), CFG.ESP_Boxes
                            if CFG.ESP_Info then
                                esp.Info.Text = string.format("%s | %d HP | %dm", plr.Name, math.floor(hum.Health), math.floor((cam.CFrame.Position - hrp.Position).Magnitude))
                                esp.Info.Position, esp.Info.Visible = Vector2.new(rootPos.X, headPos.Y - 20), true
                            else esp.Info.Visible = false end
                        else esp.Box.Visible, esp.Info.Visible = false, false end
                    else esp.Box.Visible, esp.Info.Visible = false, false end
                else esp.Box.Visible, esp.Info.Visible = false, false end
            end
        else
            for _, esp in pairs(espObjects) do esp.Box.Visible, esp.Info.Visible = false, false end
        end
    end
end)

_G.ZakaSAUnload = function()
    RUNNING = false
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    fovCircle = nil
    for plr, _ in pairs(espObjects) do removeEsp(plr) end
    if sg then sg:Destroy() end
    _cachePos, _G.ZakaSAUnload = nil, nil
end
