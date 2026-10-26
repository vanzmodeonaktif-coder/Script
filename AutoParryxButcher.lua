if getgenv().vanzAutoParry and getgenv().vanzAutoParry.running then
    pcall(function() getgenv().vanzAutoParry.shutdown() end)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local lp = Players.LocalPlayer

local LUNGE_IDS = {
    ["127417297154354"] = true,
    ["129626174716003"] = true,
    ["135002183282873"] = true,
    ["105374834496520"] = true,
    ["117042998468241"] = true,
    ["93902163029544"]  = true,
    ["104540716539347"] = true,
    ["113255068724446"] = true,
    ["98163597193511"]  = true,
    ["125430111937587"] = true,
    ["100014992013740"] = true,
    ["84926129581106"]  = true,
}

local S = getgenv().vanzAutoParry or {}
getgenv().vanzAutoParry = S

S.enabled        = S.enabled ~= nil and S.enabled or false
S.radius         = S.radius or 18
S.facingThresh   = S.facingThresh or 0.5
S.debounceMs     = S.debounceMs or 50
S.lockUI         = S.lockUI or false
S.winPos         = S.winPos or UDim2.new(0.5, -180, 0.5, -130)
S.miniPos        = S.miniPos or UDim2.new(0, 20, 0, 20)
S.minimized      = false
S.running        = true
S.tracking       = {}
S.lastParry      = {}
S.parryBtn       = nil

local function getChar()
    return lp.Character
end
local function getHRP()
    local c = getChar()
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
end

local function classify(model)
    if not model or not model:IsA("Model") then return nil end
    local c = getChar()
    if model == c then return "SELF" end
    if not model:FindFirstChildOfClass("Humanoid") then return nil end
    if not (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")) then return nil end
    if model:FindFirstChild("Lookscriptkiller", true) then return "ENEMY" end
    if model:FindFirstChild("HRP_Clone", true) or model:FindFirstChild("Parrying Dagger", true) then return "SURVIVOR" end
    return "UNKNOWN"
end

local function getPlayingIds(char)
    local h = char:FindFirstChildOfClass("Humanoid")
    if not h then return {} end
    local animator = h:FindFirstChildOfClass("Animator")
    if not animator then return {} end
    local out = {}
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return out end
    for _, t in ipairs(tracks) do
        local a = t.Animation
        if a and a.AnimationId then
            local id = a.AnimationId:gsub("rbxassetid://", "")
            out[id] = t
        end
    end
    return out
end

local function isFacing(killerHRP, playerHRP)
    local dirToPlayer = (playerHRP.Position - killerHRP.Position)
    if dirToPlayer.Magnitude < 0.01 then return true end
    local dot = killerHRP.CFrame.LookVector:Dot(dirToPlayer.Unit)
    return dot > S.facingThresh
end

local function hasLOS(killerChar, playerChar, killerHRP, playerHRP)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local camBlock = Workspace:FindFirstChild("CameraBlock")
    local exclude = {killerChar, playerChar}
    if camBlock then table.insert(exclude, camBlock) end
    params.FilterDescendantsInstances = exclude
    local dir = (playerHRP.Position - killerHRP.Position)
    local result = Workspace:Raycast(killerHRP.Position, dir, params)
    if not result then return true end
    local hit = result.Instance
    if hit and hit:IsDescendantOf(playerChar) then return true end
    return false
end

local function resolveParryButton()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local mob = pg:FindFirstChild("Survivor-mob")
    if not mob then return nil end
    local ctrl = mob:FindFirstChild("Controls")
    if not ctrl then return nil end
    return ctrl:FindFirstChild("Gui-mob")
end

local function fireParry()
    local btn = S.parryBtn
    if not btn or not btn.Parent then
        btn = resolveParryButton()
        S.parryBtn = btn
    end
    if not btn then return false end

    local ap = btn.AbsolutePosition
    local as = btn.AbsoluteSize
    if as.X <= 0 or as.Y <= 0 then return false end
    local pos = Vector3.new(ap.X + as.X / 2, ap.Y + as.Y / 2, 0)

    local ok = pcall(function()
        firesignal(btn.MouseButton1Down, pos, pos)
    end)
    if not ok then
        S.parryBtn = nil
        return false
    end
    task.defer(function()
        pcall(function()
            firesignal(btn.MouseButton1Up, pos, pos)
        end)
    end)
    return true
end

local function nowMs()
    return tick() * 1000
end

local SEGMENTS = 32
local ringFolder = nil
local ringParts = {}

local function initRing()
    if ringFolder and ringFolder.Parent then return end
    ringFolder = Instance.new("Folder")
    ringFolder.Name = "VanzParryRing"
    for i = 1, SEGMENTS do
        local p = Instance.new("Part")
        p.Name = "Seg_" .. i
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(255, 255, 255)
        p.Transparency = 0.2
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.Size = Vector3.new(1, 0.2, 0.5)
        p.Parent = ringFolder
        ringParts[i] = p
    end
    ringFolder.Parent = Workspace
end

local function updateRing()
    if not S.enabled then
        if ringFolder and ringFolder.Parent then ringFolder.Parent = nil end
        return
    end
    local hrp = getHRP()
    if not hrp then
        if ringFolder and ringFolder.Parent then ringFolder.Parent = nil end
        return
    end
    initRing()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getChar() }
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -50, 0), params)
    local groundY = hrp.Position.Y - (hrp.Size.Y / 2) - 2.5
    if result then groundY = result.Position.Y + 0.5 end
    local centerPos = Vector3.new(hrp.Position.X, groundY, hrp.Position.Z)
    local circumference = 2 * math.pi * S.radius
    local segLength = (circumference / SEGMENTS) + 0.1
    for i = 1, SEGMENTS do
        local angle = (i - 1) * (2 * math.pi / SEGMENTS)
        local offsetX = math.cos(angle) * S.radius
        local offsetZ = math.sin(angle) * S.radius
        local pos = centerPos + Vector3.new(offsetX, 0, offsetZ)
        local p = ringParts[i]
        p.Size = Vector3.new(segLength, 0.1, 0.3)
        p.CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, 0)
    end
end

local markers = {}
local function updateMarkers(enemies)
    for _, m in pairs(markers) do
        pcall(function() m.Visible = false end)
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    for _, e in ipairs(enemies) do
        local model = e.model
        if model and model.Parent then
            local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
            if hrp then
                local head = model:FindFirstChild("Head") or hrp
                local pos = head.Position + Vector3.new(0, 2.5, 0)
                local sp, onScreen = cam:WorldToViewportPoint(pos)
                local key = model
                if not markers[key] then
                    pcall(function()
                        local d = Drawing.new("Text")
                        d.Center = true
                        d.Outline = true
                        d.Size = 14
                        d.Font = 2
                        markers[key] = d
                    end)
                end
                local d = markers[key]
                if d then
                    d.Position = Vector2.new(sp.X, sp.Y)
                    d.Text = e.cls
                    if e.cls == "ENEMY" then
                        if e.inRadius then
                            d.Color = Color3.fromRGB(255, 80, 80)
                            d.Transparency = 1
                        else
                            d.Color = Color3.fromRGB(255, 80, 80)
                            d.Transparency = 0.55
                        end
                    elseif e.cls == "SURVIVOR" then
                        d.Color = Color3.fromRGB(80, 255, 120)
                        d.Transparency = 0.55
                    else
                        d.Color = Color3.fromRGB(255, 220, 80)
                        d.Transparency = 0.55
                    end
                    d.Visible = onScreen
                end
            end
        end
    end
end

local function fullScan()
    local result = {}
    local c = getChar()
    if not c then return result end
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") and m ~= c then
            local cls = classify(m)
            if cls then
                table.insert(result, {model = m, cls = cls})
            end
        end
    end
    return result
end

local function tryParry(killerModel, playerChar, playerHRP)
    local kh = killerModel:FindFirstChildOfClass("Humanoid")
    if not kh or kh.Health <= 0 then return false end
    local khrp = killerModel:FindFirstChild("HumanoidRootPart") or killerModel:FindFirstChild("Torso")
    if not khrp then return false end
    local ids = getPlayingIds(killerModel)
    local matched = nil
    for id in pairs(ids) do
        if LUNGE_IDS[id] then matched = id; break end
    end
    if not matched then return false end
    if not isFacing(khrp, playerHRP) then return false end
    if not hasLOS(killerModel, playerChar, khrp, playerHRP) then return false end
    local key = tostring(killerModel) .. ":" .. matched
    local t = nowMs()
    if S.lastParry[key] and (t - S.lastParry[key]) < S.debounceMs then return false end
    S.lastParry[key] = t
    return fireParry()
end

local mainConn
local function startLoop()
    if mainConn then mainConn:Disconnect() end
    mainConn = RunService.Heartbeat:Connect(function()
        if not S.running then return end
        updateRing()
        if not S.enabled then return end
        local c = getChar()
        local hrp = getHRP()
        if not c or not hrp then return end
        local list = fullScan()
        for _, item in ipairs(list) do
            if item.cls == "ENEMY" then
                local khrp = item.model:FindFirstChild("HumanoidRootPart") or item.model:FindFirstChild("Torso")
                if khrp then
                    local dx = khrp.Position.X - hrp.Position.X
                    local dz = khrp.Position.Z - hrp.Position.Z
                    local dist = math.sqrt(dx*dx + dz*dz)
                    local inR = dist <= S.radius
                    item.inRadius = inR
                    item.dist = dist
                    if inR then
                        tryParry(item.model, c, hrp)
                    end
                end
            end
        end
        S.tracking = list
        updateMarkers(list)
    end)
end

local function getUIParent()
    if typeof(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    return lp:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "VanzAutoParry"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2147483647
gui.Parent = getUIParent()

local function mk(cls, props, parent)
    local i = Instance.new(cls)
    for k, v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local mainFrame = mk("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 360, 0, 260),
    Position = S.winPos,
    BackgroundColor3 = Color3.fromRGB(26, 26, 26),
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 8)}, mainFrame)
mk("UIStroke", {Color = Color3.fromRGB(50, 50, 50), Thickness = 1}, mainFrame)

local titleBar = mk("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
    BorderSizePixel = 0,
}, mainFrame)
mk("UICorner", {CornerRadius = UDim.new(0, 8)}, titleBar)

mk("TextLabel", {
    Size = UDim2.new(1, -110, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "VANZ AUTO-PARRY",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local function mkBtn(text, xOff, parent)
    local b = mk("TextButton", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, xOff, 0.5, -12),
        BackgroundColor3 = Color3.fromRGB(35, 35, 35),
        Text = text,
        TextColor3 = Color3.fromRGB(220, 220, 220),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        BorderSizePixel = 0,
        AutoButtonColor = true,
    }, parent)
    mk("UICorner", {CornerRadius = UDim.new(0, 5)}, b)
    return b
end

local lockBtn = mkBtn("🔓", -84, titleBar)
local minBtn  = mkBtn("─", -56, titleBar)
local closeBtn = mkBtn("✕", -28, titleBar)

local content = mk("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -32),
    Position = UDim2.new(0, 0, 0, 32),
    BackgroundTransparency = 1,
}, mainFrame)

local function row(y, labelText)
    local f = mk("Frame", {
        Size = UDim2.new(1, -24, 0, 28),
        Position = UDim2.new(0, 12, 0, y),
        BackgroundTransparency = 1,
    }, content)
    mk("TextLabel", {
        Size = UDim2.new(0, 120, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(200, 200, 200),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    return f
end

local toggleRow = row(8, "Auto-Parry")
local toggleBtn = mk("TextButton", {
    Size = UDim2.new(0, 80, 0, 24),
    Position = UDim2.new(1, -80, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(60, 60, 60),
    Text = "DISABLED",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    BorderSizePixel = 0,
}, toggleRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, toggleBtn)

local radRow = row(44, "Radius")
local minusBtn = mk("TextButton", {
    Size = UDim2.new(0, 24, 0, 24),
    Position = UDim2.new(1, -136, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(45, 45, 45),
    Text = "-",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    BorderSizePixel = 0,
}, radRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, minusBtn)
local radBox = mk("TextBox", {
    Size = UDim2.new(0, 60, 0, 24),
    Position = UDim2.new(1, -108, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    Text = tostring(S.radius),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.Gotham,
    TextSize = 12,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
}, radRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, radBox)
local plusBtn = mk("TextButton", {
    Size = UDim2.new(0, 24, 0, 24),
    Position = UDim2.new(1, -40, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(45, 45, 45),
    Text = "+",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    BorderSizePixel = 0,
}, radRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, plusBtn)

local thRow = row(80, "Facing Threshold")
local thBox = mk("TextBox", {
    Size = UDim2.new(0, 80, 0, 24),
    Position = UDim2.new(1, -80, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    Text = tostring(S.facingThresh),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.Gotham,
    TextSize = 12,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
}, thRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, thBox)

local debRow = row(116, "Debounce (ms)")
local debBox = mk("TextBox", {
    Size = UDim2.new(0, 80, 0, 24),
    Position = UDim2.new(1, -80, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    Text = tostring(S.debounceMs),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.Gotham,
    TextSize = 12,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
}, debRow)
mk("UICorner", {CornerRadius = UDim.new(0, 5)}, debBox)

local statusFrame = mk("Frame", {
    Size = UDim2.new(1, -24, 0, 70),
    Position = UDim2.new(0, 12, 0, 152),
    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
    BorderSizePixel = 0,
}, content)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, statusFrame)
local statusLbl = mk("TextLabel", {
    Size = UDim2.new(1, -12, 1, -8),
    Position = UDim2.new(0, 6, 0, 4),
    BackgroundTransparency = 1,
    Text = "Killers: 0 | In radius: 0",
    TextColor3 = Color3.fromRGB(180, 180, 180),
    Font = Enum.Font.Code,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, statusFrame)

local function updateToggleVisual()
    toggleBtn.Text = S.enabled and "ACTIVE" or "DISABLED"
    toggleBtn.BackgroundColor3 = S.enabled and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(60, 60, 60)
end
updateToggleVisual()

toggleBtn.MouseButton1Click:Connect(function()
    S.enabled = not S.enabled
    updateToggleVisual()
end)

local function setRadius(v)
    v = tonumber(v) or S.radius
    v = math.clamp(math.floor(v + 0.5), 1, 50)
    S.radius = v
    radBox.Text = tostring(v)
end
minusBtn.MouseButton1Click:Connect(function() setRadius(S.radius - 1) end)
plusBtn.MouseButton1Click:Connect(function() setRadius(S.radius + 1) end)
radBox.FocusLost:Connect(function() setRadius(radBox.Text) end)

thBox.FocusLost:Connect(function()
    local v = tonumber(thBox.Text)
    if v then S.facingThresh = math.clamp(v, -1, 1); thBox.Text = tostring(S.facingThresh) end
end)
debBox.FocusLost:Connect(function()
    local v = tonumber(debBox.Text)
    if v then S.debounceMs = math.clamp(v, 0, 1000); debBox.Text = tostring(S.debounceMs) end
end)

local function updateLock()
    lockBtn.Text = S.lockUI and "🔒" or "🔓"
end
updateLock()
lockBtn.MouseButton1Click:Connect(function()
    S.lockUI = not S.lockUI
    updateLock()
end)

local dragging = false
local dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if S.lockUI then return end
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        S.winPos = mainFrame.Position
    end
end)

local miniBtnFrame = mk("TextButton", {
    Name = "MiniBtn",
    Size = UDim2.new(0, 44, 0, 44),
    Position = S.miniPos,
    BackgroundColor3 = Color3.fromRGB(26, 26, 26),
    Text = "VZ",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    BorderSizePixel = 0,
    Visible = false,
    AutoButtonColor = true,
}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 8)}, miniBtnFrame)
mk("UIStroke", {Color = Color3.fromRGB(60, 60, 60), Thickness = 1}, miniBtnFrame)

local miniDragging = false
local miniDragStart, miniStartPos
miniBtnFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        miniDragging = true
        miniDragStart = input.Position
        miniStartPos = miniBtnFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then miniDragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if miniDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - miniDragStart
        local newPos = UDim2.new(miniStartPos.X.Scale, miniStartPos.X.Offset + delta.X, miniStartPos.Y.Scale, miniStartPos.Y.Offset + delta.Y)
        miniBtnFrame.Position = newPos
        S.miniPos = newPos
    end
end)

local miniMoved = false
miniBtnFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        miniMoved = false
        local start = miniBtnFrame.Position
        task.delay(0.15, function()
            if miniBtnFrame and miniBtnFrame.Parent then
                if miniBtnFrame.Position ~= start then miniMoved = true end
            end
        end)
    end
end)
miniBtnFrame.MouseButton1Click:Connect(function()
    if miniMoved then return end
    S.minimized = false
    miniBtnFrame.Visible = false
    mainFrame.Visible = true
end)

minBtn.MouseButton1Click:Connect(function()
    S.minimized = true
    mainFrame.Visible = false
    miniBtnFrame.Visible = true
end)

local function fullShutdown()
    S.running = false
    S.enabled = false
    if mainConn then mainConn:Disconnect(); mainConn = nil end
    if ringFolder then
        pcall(function() ringFolder:Destroy() end)
        ringFolder = nil
        ringParts = {}
    end
    for _, d in pairs(markers) do pcall(function() d:Remove() end) end
    markers = {}
    if gui then pcall(function() gui:Destroy() end) end
    getgenv().vanzAutoParry = nil
end
S.shutdown = fullShutdown

closeBtn.MouseButton1Click:Connect(fullShutdown)

startLoop()

task.spawn(function()
    while S.running do
        task.wait(0.5)
        if not S.running then break end
        local enemies = 0
        local inR = 0
        for _, item in ipairs(S.tracking or {}) do
            if item.cls == "ENEMY" then
                enemies = enemies + 1
                if item.inRadius then inR = inR + 1 end
            end
        end
        local total = #(S.tracking or {})
        pcall(function()
            statusLbl.Text = string.format("Tracking: %d | Killers: %d | In radius: %d\nState: %s",
                total, enemies, inR, S.enabled and "ACTIVE" or "DISABLED")
        end)
    end
end)

print("[VANZ AUTO-PARRY] Loaded v1.5 (firesignal + Vector3 center).")
