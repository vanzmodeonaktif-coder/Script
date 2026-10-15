local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ATTACK_IDS = {
    "139369275981139","121216847022485","78935059863801",
    "74968262036854","82666958311998","78432063483146",
    "132817836308238","111920872708571","138720291317243",
    "130593238885843","106871536134254","109402730355822",
}

local PARRY_ANIM_ID = "109133187196613"
local MAX_DISPLAY = 2147483647
local DEBOUNCE = 0.005

local ATTACK_SET = {}
for _, id in ipairs(ATTACK_IDS) do
    ATTACK_SET[id] = true
    ATTACK_SET["rbxassetid://" .. id] = true
    ATTACK_SET["http://www.roblox.com/asset/?id=" .. id] = true
end

local firesignalFn = type(firesignal) == "function" and firesignal or nil

local state = {
    enabled = false,
    fakeEnabled = false,
    radius = 10,
    ringParts = {},
    preConn = nil,
    simConn = nil,
    conns = {},
    lastWS = {},
    ui = nil,
    fakeBtn = nil,
    lastFire = 0,
    ringFolder = nil,
    btnCache = nil,
    parryRemote = nil,
    myHRP = nil,
    myPos = nil,
}

local function cacheParryRemote()
    if state.parryRemote and state.parryRemote.Parent then return state.parryRemote end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local items = remotes and remotes:FindFirstChild("Items")
    local dagger = items and items:FindFirstChild("Parrying Dagger")
    local rem = dagger and dagger:FindFirstChild("parry")
    if rem and rem:IsA("RemoteEvent") then
        state.parryRemote = rem
        return rem
    end
    return nil
end

local function getButton()
    if state.btnCache and state.btnCache.Parent then
        return state.btnCache
    end
    local gui = PlayerGui:FindFirstChild("Survivor-mob")
    if not gui then return nil end
    local ctrl = gui:FindFirstChild("Controls")
    if not ctrl then return nil end
    local b = ctrl:FindFirstChild("Gui-mob")
    if b then state.btnCache = b end
    return b
end

local fireFn
fireFn = function()
    local now = os.clock()
    if now - state.lastFire < DEBOUNCE then return end
    state.lastFire = now

    local btn = getButton()
    if btn and firesignalFn then
        pcall(firesignalFn, btn.MouseButton1Down)
        pcall(firesignalFn, btn.MouseButton1Up)
    else
        local rem = cacheParryRemote()
        if rem then
            pcall(function() rem:FireServer() end)
        end
    end
end

local function playFakeParry()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. PARRY_ANIM_ID
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if ok and track then
        track.Priority = Enum.AnimationPriority.Action4
        pcall(function() track:Play(0.05, 1, 1) end)
    end
    anim:Destroy()
end

local function isEnemy(player)
    if player == LocalPlayer then return false end
    local myTeam = LocalPlayer.Team
    local theirTeam = player.Team
    if myTeam and theirTeam then
        return myTeam ~= theirTeam
    end
    local myRole = LocalPlayer:GetAttribute("Role")
    local theirRole = player:GetAttribute("Role")
    if myRole and theirRole then
        return myRole ~= theirRole
    end
    return false
end

local function hasAttackAnim(animator)
    if not animator then return nil end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return nil end
    for _, t in ipairs(tracks) do
        local aid = t.Animation and t.Animation.AnimationId or ""
        if ATTACK_SET[aid] then return aid end
    end
    return nil
end

local function destroyRing()
    for _, p in ipairs(state.ringParts) do
        if p then p:Destroy() end
    end
    state.ringParts = {}
end

local function buildRing(radius)
    destroyRing()
    if radius <= 0 then return end
    local segments = 48
    local arcLen = (2 * math.pi * radius) / segments
    local segLen = arcLen * 1.35
    for i = 1, segments do
        local p = Instance.new("Part")
        p.Name = "VanzRingSeg"
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(255, 255, 255)
        p.Size = Vector3.new(segLen, 0.06, 0.18)
        p.Transparency = 0.12
        p.Parent = state.ringFolder
        table.insert(state.ringParts, p)
    end
end

local function updateRing()
    local n = #state.ringParts
    if n == 0 then return end
    local myHRP = state.myHRP
    if not myHRP then return end
    local center = myHRP.Position - Vector3.new(0, myHRP.Size.Y * 0.5 + 0.05, 0)
    local r = state.radius
    for i, p in ipairs(state.ringParts) do
        local angle = (i / n) * math.pi * 2
        local offset = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
        local pos = center + offset
        p.CFrame = CFrame.lookAt(pos, center)
    end
end

local function makeCorner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = parent
end

local function createFakeButton()
    if state.fakeBtn then
        state.fakeBtn:Destroy()
        state.fakeBtn = nil
    end
    if not state.fakeEnabled or not state.ui then return end

    local btn = Instance.new("TextButton")
    btn.Name = "VanzFakeParry"
    btn.Size = UDim2.new(0, 68, 0, 68)
    btn.Position = UDim2.new(1, -90, 0.5, -34)
    btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    btn.BackgroundTransparency = 0.15
    btn.Text = "PARRY"
    btn.TextColor3 = Color3.fromRGB(20, 20, 30)
    btn.Font = Enum.Font.GothamBlack
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Active = true
    btn.Parent = state.ui.sg
    makeCorner(btn, 34)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 220, 255)
    stroke.Thickness = 2
    stroke.Parent = btn

    btn.MouseButton1Click:Connect(playFakeParry)
    state.fakeBtn = btn
end

local function createUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "VanzAutoParry"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = MAX_DISPLAY
    sg.Parent = PlayerGui

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 220, 0, 168)
    main.Position = UDim2.new(0, 30, 0.4, -84)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = sg
    makeCorner(main, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(90, 90, 120)
    stroke.Thickness = 1
    stroke.Parent = main

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    title.BorderSizePixel = 0
    title.Parent = main
    makeCorner(title, 8)

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, -70, 1, 0)
    tl.Position = UDim2.new(0, 12, 0, 0)
    tl.BackgroundTransparency = 1
    tl.Text = "VANZ AUTO PARRY v4"
    tl.TextColor3 = Color3.fromRGB(230, 230, 240)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 12
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Parent = title

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 22, 0, 22)
    close.Position = UDim2.new(1, -26, 0, 4)
    close.BackgroundColor3 = Color3.fromRGB(180, 45, 45)
    close.Text = "X"
    close.TextColor3 = Color3.fromRGB(255, 255, 255)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.BorderSizePixel = 0
    close.AutoButtonColor = false
    close.Parent = title
    makeCorner(close, 4)

    local min = Instance.new("TextButton")
    min.Size = UDim2.new(0, 22, 0, 22)
    min.Position = UDim2.new(1, -52, 0, 4)
    min.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    min.Text = "-"
    min.TextColor3 = Color3.fromRGB(255, 255, 255)
    min.Font = Enum.Font.GothamBold
    min.TextSize = 14
    min.BorderSizePixel = 0
    min.AutoButtonColor = false
    min.Parent = title
    makeCorner(min, 4)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -20, 1, -40)
    content.Position = UDim2.new(0, 10, 0, 36)
    content.BackgroundTransparency = 1
    content.Parent = main

    local apLbl = Instance.new("TextLabel")
    apLbl.Size = UDim2.new(0.55, 0, 0, 28)
    apLbl.BackgroundTransparency = 1
    apLbl.Text = "Auto Parry"
    apLbl.TextColor3 = Color3.fromRGB(210, 210, 220)
    apLbl.Font = Enum.Font.Gotham
    apLbl.TextSize = 13
    apLbl.TextXAlignment = Enum.TextXAlignment.Left
    apLbl.Parent = content

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 52, 0, 24)
    toggle.Position = UDim2.new(1, -52, 0, 2)
    toggle.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
    toggle.Text = "OFF"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.BorderSizePixel = 0
    toggle.AutoButtonColor = false
    toggle.Parent = content
    makeCorner(toggle, 4)

    local fpLbl = Instance.new("TextLabel")
    fpLbl.Size = UDim2.new(0.55, 0, 0, 28)
    fpLbl.Position = UDim2.new(0, 0, 0, 32)
    fpLbl.BackgroundTransparency = 1
    fpLbl.Text = "Fake Parry"
    fpLbl.TextColor3 = Color3.fromRGB(210, 210, 220)
    fpLbl.Font = Enum.Font.Gotham
    fpLbl.TextSize = 13
    fpLbl.TextXAlignment = Enum.TextXAlignment.Left
    fpLbl.Parent = content

    local fakeToggle = Instance.new("TextButton")
    fakeToggle.Size = UDim2.new(0, 52, 0, 24)
    fakeToggle.Position = UDim2.new(1, -52, 0, 34)
    fakeToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
    fakeToggle.Text = "OFF"
    fakeToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    fakeToggle.Font = Enum.Font.GothamBold
    fakeToggle.TextSize = 12
    fakeToggle.BorderSizePixel = 0
    fakeToggle.AutoButtonColor = false
    fakeToggle.Parent = content
    makeCorner(fakeToggle, 4)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0.55, 0, 0, 28)
    sLbl.Position = UDim2.new(0, 0, 0, 64)
    sLbl.BackgroundTransparency = 1
    sLbl.Text = "Radius (stud)"
    sLbl.TextColor3 = Color3.fromRGB(210, 210, 220)
    sLbl.Font = Enum.Font.Gotham
    sLbl.TextSize = 13
    sLbl.TextXAlignment = Enum.TextXAlignment.Left
    sLbl.Parent = content

    local minus = Instance.new("TextButton")
    minus.Size = UDim2.new(0, 24, 0, 24)
    minus.Position = UDim2.new(1, -122, 0, 66)
    minus.BackgroundColor3 = Color3.fromRGB(60, 60, 82)
    minus.Text = "-"
    minus.TextColor3 = Color3.fromRGB(255, 255, 255)
    minus.Font = Enum.Font.GothamBold
    minus.TextSize = 14
    minus.BorderSizePixel = 0
    minus.AutoButtonColor = false
    minus.Parent = content
    makeCorner(minus, 4)

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0, 46, 0, 24)
    val.Position = UDim2.new(1, -94, 0, 66)
    val.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    val.Text = "10"
    val.TextColor3 = Color3.fromRGB(255, 255, 255)
    val.Font = Enum.Font.GothamBold
    val.TextSize = 12
    val.BorderSizePixel = 0
    val.Parent = content
    makeCorner(val, 4)

    local plus = Instance.new("TextButton")
    plus.Size = UDim2.new(0, 24, 0, 24)
    plus.Position = UDim2.new(1, -44, 0, 66)
    plus.BackgroundColor3 = Color3.fromRGB(60, 60, 82)
    plus.Text = "+"
    plus.TextColor3 = Color3.fromRGB(255, 255, 255)
    plus.Font = Enum.Font.GothamBold
    plus.TextSize = 14
    plus.BorderSizePixel = 0
    plus.AutoButtonColor = false
    plus.Parent = content
    makeCorner(plus, 4)

    return {
        sg=sg, main=main, content=content,
        toggle=toggle, fakeToggle=fakeToggle,
        minus=minus, plus=plus, val=val,
        close=close, min=min, title=title,
    }
end

state.ringFolder = Instance.new("Folder")
state.ringFolder.Name = "VanzParryRing"
state.ringFolder.Parent = workspace

local ui = createUI()
state.ui = ui

local function refreshToggle()
    if state.enabled then
        ui.toggle.Text = "ON"
        ui.toggle.BackgroundColor3 = Color3.fromRGB(50, 185, 90)
    else
        ui.toggle.Text = "OFF"
        ui.toggle.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
    end
end

local function refreshFakeToggle()
    if state.fakeEnabled then
        ui.fakeToggle.Text = "ON"
        ui.fakeToggle.BackgroundColor3 = Color3.fromRGB(50, 185, 90)
    else
        ui.fakeToggle.Text = "OFF"
        ui.fakeToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
    end
end

local function refreshVal()
    ui.val.Text = tostring(state.radius)
end

local function setEnabled(on)
    state.enabled = on
    if on then
        buildRing(state.radius)
        updateRing()
    else
        destroyRing()
    end
    refreshToggle()
end

local function setFakeEnabled(on)
    state.fakeEnabled = on
    refreshFakeToggle()
    createFakeButton()
end

ui.toggle.MouseButton1Click:Connect(function() setEnabled(not state.enabled) end)
ui.fakeToggle.MouseButton1Click:Connect(function() setFakeEnabled(not state.fakeEnabled) end)

ui.minus.MouseButton1Click:Connect(function()
    state.radius = math.clamp(state.radius - 1, 0, 30)
    refreshVal()
    if state.enabled then
        buildRing(state.radius)
        updateRing()
    end
end)

ui.plus.MouseButton1Click:Connect(function()
    state.radius = math.clamp(state.radius + 1, 0, 30)
    refreshVal()
    if state.enabled then
        buildRing(state.radius)
        updateRing()
    end
end)

local minimized = false
ui.min.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        ui.main.Size = UDim2.new(0, 220, 0, 30)
        ui.content.Visible = false
        ui.min.Text = "+"
    else
        ui.main.Size = UDim2.new(0, 220, 0, 168)
        ui.content.Visible = true
        ui.min.Text = "-"
    end
end)

local function detachPlayer(player)
    local c = state.conns[player]
    if c then
        for _, conn in pairs(c) do
            pcall(function() conn:Disconnect() end)
        end
        state.conns[player] = nil
    end
    state.lastWS[player] = nil
end

local function cleanup()
    state.enabled = false
    state.fakeEnabled = false
    state.lastFire = 0
    state.btnCache = nil
    state.parryRemote = nil
    state.myHRP = nil
    state.myPos = nil
    destroyRing()
    if state.preConn then state.preConn:Disconnect(); state.preConn = nil end
    if state.simConn then state.simConn:Disconnect(); state.simConn = nil end
    for p, _ in pairs(state.conns) do detachPlayer(p) end
    state.conns = {}
    state.lastWS = {}
    if state.fakeBtn then
        pcall(function() state.fakeBtn:Destroy() end)
        state.fakeBtn = nil
    end
    if state.ringFolder then
        pcall(function() state.ringFolder:Destroy() end)
        state.ringFolder = nil
    end
    if state.ui and state.ui.sg then
        pcall(function() state.ui.sg:Destroy() end)
        state.ui = nil
    end
end

ui.close.MouseButton1Click:Connect(cleanup)

local function attachToPlayer(player)
    if player == LocalPlayer then return end

    local function onChar(char)
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then
            hum = char:WaitForChild("Humanoid", 3)
            if not hum then return end
        end
        local animator = hum:FindFirstChildOfClass("Animator")
        if not animator then
            animator = hum:WaitForChild("Animator", 3)
            if not animator then return end
        end

        detachPlayer(player)
        state.lastWS[player] = hum.WalkSpeed

        local function tryFireFromAnim(aid)
            if not state.enabled then return end
            if not isEnemy(player) then return end
            if state.radius <= 0 then return end
            local myHRP = state.myHRP
            local pchar = player.Character
            if not myHRP or not pchar then return end
            local hrp = pchar:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local dx = hrp.Position.X - myHRP.Position.X
            local dz = hrp.Position.Z - myHRP.Position.Z
            if (dx * dx + dz * dz) <= (state.radius * state.radius) then
                fireFn()
            end
        end

        state.conns[player] = {
            anim = animator.AnimationPlayed:Connect(function(track)
                if not state.enabled then return end
                local aid = track.Animation and track.Animation.AnimationId or ""
                if not ATTACK_SET[aid] then return end
                tryFireFromAnim(aid)
            end),

            ws = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                if not state.enabled then return end
                if not isEnemy(player) then return end
                local newWS = hum.WalkSpeed
                local oldWS = state.lastWS[player] or newWS
                state.lastWS[player] = newWS
                if oldWS > 1 and newWS <= 0.5 then
                    if state.radius <= 0 then return end
                    local myHRP = state.myHRP
                    local pchar = player.Character
                    if not myHRP or not pchar then return end
                    local hrp = pchar:FindFirstChild("HumanoidRootPart")
                    if not hrp then return end
                    local dx = hrp.Position.X - myHRP.Position.X
                    local dz = hrp.Position.Z - myHRP.Position.Z
                    if (dx * dx + dz * dz) <= (state.radius * state.radius) then
                        if hasAttackAnim(animator) then
                            fireFn()
                        end
                    end
                end
            end),

            attr = hum.AttributeChanged:Connect(function(attrName)
                if not state.enabled then return end
                if not isEnemy(player) then return end
                if state.radius <= 0 then return end
                local myHRP = state.myHRP
                local pchar = player.Character
                if not myHRP or not pchar then return end
                local hrp = pchar:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local dx = hrp.Position.X - myHRP.Position.X
                local dz = hrp.Position.Z - myHRP.Position.Z
                if (dx * dx + dz * dz) > (state.radius * state.radius) then return end
                local n = string.lower(tostring(attrName))
                if n:find("attack") or n:find("action") or n:find("busy")
                   or n:find("state") or n:find("combat") or n:find("skill")
                   or n:find("swing") or n:find("slash") or n:find("cast") then
                    if hasAttackAnim(animator) then
                        fireFn()
                    end
                end
            end),
        }
    end

    if player.Character then
        onChar(player.Character)
    end
    player.CharacterAdded:Connect(onChar)
end

for _, p in ipairs(Players:GetPlayers()) do
    attachToPlayer(p)
end
Players.PlayerAdded:Connect(attachToPlayer)
Players.PlayerRemoving:Connect(function(p)
    detachPlayer(p)
end)

local function tickScan()
    if not state.enabled then return end

    local char = LocalPlayer.Character
    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
    state.myHRP = myHRP
    if not myHRP then
        updateRing()
        return
    end

    updateRing()

    local r = state.radius
    if r <= 0 then return end
    local r2 = r * r
    local mx = myHRP.Position.X
    local mz = myHRP.Position.Z

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isEnemy(player) then
            local pchar = player.Character
            if pchar then
                local hrp = pchar:FindFirstChild("HumanoidRootPart")
                local hum = pchar:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local dx = hrp.Position.X - mx
                    local dz = hrp.Position.Z - mz
                    if (dx * dx + dz * dz) <= r2 then
                        local animator = hum:FindFirstChildOfClass("Animator")
                        if animator then
                            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
                            if ok and tracks then
                                for _, t in ipairs(tracks) do
                                    local aid = t.Animation and t.Animation.AnimationId or ""
                                    if ATTACK_SET[aid] and t.TimePosition < 0.2 then
                                        fireFn()
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

state.preConn = RunService.PreRender:Connect(tickScan)
state.simConn = RunService.PreSimulation:Connect(tickScan)
