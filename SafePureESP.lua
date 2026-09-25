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
