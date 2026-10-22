-- m2_aim_fixed_cam.lua
-- scope 19: snap 1.5s, fix camera stuck on mobile

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer

local CFG = {
    TriggerAnimId = "98163597193511", 
    MaxRange      = math.huge,
    AimOffset     = Vector3.new(0, 0, 0), 
    TrackDuration = 1.5, 
}

local cam = workspace.CurrentCamera
local defaultSubject = nil

local S = {
    enabled    = false,
    tracking   = false,
    target     = nil,
    root       = nil,
    trackConn  = nil,
    animConn   = nil,
    animator   = nil,
    startedAt  = 0,
    gui        = nil,
}

local function isEnemy(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if not plr then return false end
    if LocalPlayer.Team and plr.Team and (LocalPlayer.Team == plr.Team) then
        return false
    end
    return true
end

local function isValidTarget(model)
    if not model or model == LocalPlayer.Character then return false end
    if not model:IsA("Model") or not model.Parent then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root then return false end
    if not isEnemy(model) then return false end
    return true
end

local function myRoot()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function findNearest()
    local root = myRoot()
    if not root then return nil end
    local origin = root.Position
    local best, bestDist = nil, CFG.MaxRange

    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and isValidTarget(char) then
            local tr = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
            if tr then
                local d = (tr.Position - origin).Magnitude
                if d < bestDist then
                    best = char
                    bestDist = d
                end
            end
        end
    end
    return best, bestDist
end

local function setStatus(text)
    if S.statusLbl then S.statusLbl.Text = text end
end

local function restoreCamera()
    if cam.CameraType == Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Custom
    end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        cam.CameraSubject = hum
    end
end

local function stopTracking()
    if S.trackConn then S.trackConn:Disconnect(); S.trackConn = nil end
    S.tracking = false
    S.target = nil
    S.root = nil
    restoreCamera() -- Paksa kamera balik ke karakter
end

local function startTracking(target)
    stopTracking()
    local tr = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if not tr then return end
    
    S.tracking = true
    S.target = target
    S.root = tr
    S.startedAt = os.clock()
    
    -- JANGAN pakai Scriptable, biar gak macet pas dash
    -- Cukup ubah CFrame-nya secara paksa per frame
    local trackConn = RunService.RenderStepped:Connect(function()
        if not S.enabled or not S.tracking then return end
        
        local t = S.target
        if not t or not t.Parent or not isValidTarget(t) then
            setStatus("idle (target lost)")
            stopTracking()
            return
        end
        
        -- Timer 1.5 Detik
        if os.clock() - S.startedAt > CFG.TrackDuration then
            setStatus("idle (timer end)")
            stopTracking()
            return
        end
        
        local root = myRoot()
        if not root then return end
        
        local aimPos = S.root.Position + CFG.AimOffset
        local eye = cam.CFrame.Position
        local dir = aimPos - eye
        if dir.Magnitude > 1e-3 then
            -- Paksa kamera ngikutin musuh
            cam.CFrame = CFrame.lookAt(eye, aimPos)
        end
    end)
    S.trackConn = trackConn
    setStatus("LOCKED: " .. target.Name)
end

local function onAnimPlayed(track)
    if not S.enabled then return end
    local anim = track.Animation
    if not anim then return end
    
    local id = tostring(anim.AnimationId):gsub("rbxassetid://", "")
    if id == CFG.TriggerAnimId then
        local t, d = findNearest()
        if not t then
            setStatus("idle (no target)")
            return
        end
        startTracking(t)
    end
end

local function attach()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    
    if not animator then return false end
    if S.animator == animator and S.animConn then return true end
    
    if S.animConn then S.animConn:Disconnect() end
    S.animator = animator
    S.animConn = animator.AnimationPlayed:Connect(onAnimPlayed)
    return true
end

local function detach()
    if S.animConn then S.animConn:Disconnect(); S.animConn = nil end
    S.animator = nil
    stopTracking()
end

local function buildGUI()
    if S.gui then S.gui:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "M2AimGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    
    local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
    local ok = pcall(function() gui.Parent = parentGui end)
    if not ok then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 200, 0, 110)
    main.Position = UDim2.new(0, 20, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    
    local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = main
    local ms = Instance.new("UIStroke"); ms.Color = Color3.fromRGB(90, 90, 110); ms.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "M2 Lock 1.5s (Fix)"
    title.TextColor3 = Color3.fromRGB(235, 235, 235)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.Parent = main

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(1, -20, 0, 40)
    toggle.Position = UDim2.new(0, 10, 0, 35)
    toggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    toggle.BorderSizePixel = 0
    toggle.Text = "OFF"
    toggle.TextColor3 = Color3.fromRGB(250, 250, 250)
    toggle.TextSize = 16
    toggle.Font = Enum.Font.GothamBold
    toggle.Active = true
    toggle.AutoButtonColor = true
    toggle.Parent = main
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = toggle

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 20)
    status.Position = UDim2.new(0, 10, 0, 80)
    status.BackgroundTransparency = 1
    status.Text = "idle"
    status.TextColor3 = Color3.fromRGB(160, 160, 170)
    status.TextSize = 12
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = main

    S.gui = gui
    S.toggleBtn = toggle
    S.statusLbl = status

    local function doToggle()
        if S.enabled then
            S.enabled = false
            detach()
            toggle.Text = "OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
            setStatus("disabled")
        else
            S.enabled = true
            attach()
            toggle.Text = "ON"
            toggle.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
            setStatus("armed")
        end
    end

    toggle.MouseButton1Click:Connect(doToggle)
    toggle.TouchTap:Connect(doToggle)
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    if S.enabled then attach() end
end)

buildGUI()
