-- CLEANUP
for _, v in pairs(game:GetService("Workspace"):GetDescendants()) do
    if v:IsA("Highlight") or v:IsA("BillboardGui") then 
        pcall(function() v:Destroy() end) 
    end
end
if getgenv().vanzCheat and getgenv().vanzCheat.running then pcall(function() getgenv().vanzCheat.shutdown() end) end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local PG = lp:WaitForChild("PlayerGui")

local S = getgenv().vanzCheat or {}
getgenv().vanzCheat = S
S.running = true
S.enabledESP = true
S.winPos = S.winPos or UDim2.new(0.5, 0, 0.5, 0)
S.miniPos = S.miniPos or UDim2.new(0.5, -25, 0.5, -25)
S.lockUI = false

S.toggles = {
    Killer = true, Survivor = true, Generator = true,
    Pallet = true, Hook = true, Vault = true, Trap = true, Gate = true,
    Zombie = true, Pumpkin = true,
}
S.autoSkillEnabled = false

-- FULLBRIGHT CONFIG & BACKUP
S.fullbrightEnabled = false
S.lightingBackup = S.lightingBackup or nil

-- AUTO SKILLCHECK VARS
S.skillLastTrigger = 0
S.skillBusy = false
S.scourgeActive = false
local KingScourgeStart, KingScourgeEnd

-- KING SCOURGE REMOTES
pcall(function()
    local Remotes = ReplicatedStorage:WaitForChild("Remotes")
    local KillerPerks = Remotes:WaitForChild("KillerPerks")
    local KingScourge = KillerPerks:WaitForChild("kingscourge")
    KingScourgeStart = KingScourge:WaitForChild("KingScourgeStart")
    KingScourgeEnd = KingScourge:WaitForChild("KingScourgeEnd")
end)

local espCache = {}
local localGenProgress = {}

local function getUIParent()
    if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
    return PG
end

local function getEquippedItem(char)
    local twist = char:FindFirstChild("Twist of Fate"); if twist then return twist.Name end
    local weapon = char:FindFirstChild("Weapon"); if weapon then return weapon.Name end
    local ignored = {["Torso"]=true,["Head"]=true,["Humanoid"]=true,["Left Arm"]=true,["Right Arm"]=true,["Left Leg"]=true,["Right Leg"]=true,["HumanoidRootPart"]=true,["Hat"]=true,["cassette"]=true,["Animations-new"]=true,["HRP_Clone"]=true,["CheckInterractable"]=true,["Animate"]=true,["Health"]=true,["Sound"]=true,["Killerost"]=true,["Lookscriptkiller"]=true,["Lookscript"]=true,["Camera resetter"]=true,["carriedtransparency"]=true,["cutscene"]=true,["VMscript"]=true,["R6RagdollClient"]=true,["Firstperson"]=true,["PursuitPalletPredict"]=true,["Instinct"]=true,["pamela"]=true,["CamShake"]=true,["Animations"]=true,["Powers"]=true,["Highlight-new"]=true,["BasicAttack"]=true,["MaterialSounds"]=true,["ProgressBar"]=true,["Highlight-forsurvivor"]=true}
    for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") then return c.Name end; if c:IsA("Model") and not ignored[c.Name] then return c.Name end end
    return nil
end

-- ESP MODULE
local ESP_COLORS = { Killer=Color3.fromRGB(255,0,0), Survivor=Color3.fromRGB(0,0,255), Generator=Color3.fromRGB(255,165,0), GeneratorDone=Color3.fromRGB(255,255,255), Pallet=Color3.fromRGB(139,69,19), Hook=Color3.fromRGB(128,0,128), Vault=Color3.fromRGB(135,206,235), Trap=Color3.fromRGB(255,192,203), Gate=Color3.fromRGB(255,255,255), ZombieAlive=Color3.fromRGB(160,32,240), ZombieDead=Color3.fromRGB(255,255,255), Pumpkin=Color3.fromRGB(255,165,0), Item=Color3.fromRGB(255,255,255) }

local function cleanESP(obj)
    if espCache[obj] then pcall(function() espCache[obj].h:Destroy() end); pcall(function() if espCache[obj].bg then espCache[obj].bg:Destroy() end end); espCache[obj] = nil end
end

local function updateESP(obj, color, text, sub)
    if not espCache[obj] then
        local h = Instance.new("Highlight"); h.FillColor=color; h.OutlineColor=color; h.FillTransparency=0.4; h.OutlineTransparency=0; h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=obj
        local bg, l1, l2
        if text and text~="" then
            bg=Instance.new("BillboardGui"); bg.Size=UDim2.new(0,150,0,30); bg.StudsOffset=Vector3.new(0,1.5,0); bg.AlwaysOnTop=true; bg.Parent=obj
            l1=Instance.new("TextLabel"); l1.Size=UDim2.new(1,0,0.5,0); l1.BackgroundTransparency=1; l1.Text=text; l1.TextColor3=color; l1.TextStrokeTransparency=0; l1.Font=Enum.Font.GothamBold; l1.TextSize=10; l1.Parent=bg
            l2=Instance.new("TextLabel"); l2.Size=UDim2.new(1,0,0.5,0); l2.Position=UDim2.new(0,0,0.5,0); l2.BackgroundTransparency=1; l2.Text=sub or ""; l2.TextColor3=ESP_COLORS.Item; l2.TextStrokeTransparency=0; l2.Font=Enum.Font.Gotham; l2.TextSize=9; l2.Parent=bg
        end
        espCache[obj] = {h=h, bg=bg, l1=l1, l2=l2}
    else
        local e = espCache[obj]
        if e.h.FillColor~=color then e.h.FillColor=color; e.h.OutlineColor=color end
        if e.l1 and text and text~="" then if e.l1.Text~=text then e.l1.Text=text; e.l1.TextColor3=color end; if e.l2.Text~=(sub or "") then e.l2.Text=sub or "" end end
    end
end

task.spawn(function()
    while S.running do
        if S.enabledESP then
            local char = lp.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if char and hrp then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChildOfClass("Humanoid").Health>0 then
                        local isK = p.Character:FindFirstChild("Lookscriptkiller", true) ~= nil
                        local typeStr = isK and "Killer" or "Survivor"
                        local dist = (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude
                        if S.toggles[typeStr] then updateESP(p.Character, ESP_COLORS[typeStr], string.format("%s | %dm", typeStr, math.floor(dist)), getEquippedItem(p.Character)) else cleanESP(p.Character) end
                    end
                end
                if S.toggles.Zombie then for _, m in ipairs(Workspace:GetChildren()) do if m:IsA("Model") and m.Name:lower():find("zombie") then local h=m:FindFirstChildOfClass("Humanoid"); if h and h.Health>0 then updateESP(m, ESP_COLORS.ZombieAlive, "Zombie", "") else cleanESP(m) end end end end
                if S.toggles.Generator then
                    local gens = CollectionService:GetTagged("Generator")
                    if #gens==0 then local map=Workspace:FindFirstChild("Map"); if map then for _,g in ipairs(map:GetDescendants()) do if g.Name=="Generator" and g:IsA("Model") then table.insert(gens,g) end end end end
                    for _,g in ipairs(gens) do local p=g:GetAttribute("RepairProgress") or 0; if localGenProgress[g] and localGenProgress[g]>p then p=localGenProgress[g] end; if p>=99.5 then p=100 end; updateESP(g, (p>=100) and ESP_COLORS.GeneratorDone or ESP_COLORS.Generator, string.format("Gen: %d%%", math.floor(p)), "") end
                end
            end
        else for obj,_ in pairs(espCache) do cleanESP(obj) end end
        task.wait(0.016)
    end
end)

task.spawn(function()
    while S.running do
        if S.enabledESP then
            for obj,_ in pairs(espCache) do if not obj or not obj.Parent then cleanESP(obj) end end
            local map = Workspace:FindFirstChild("Map")
            if map then
                for _,obj in ipairs(map:GetDescendants()) do
                    if S.toggles.Pumpkin and obj.Name:lower():find("pumpkin") and obj:IsA("Model") then updateESP(obj, ESP_COLORS.Pumpkin, "", "") end
                    if S.toggles.Zombie and obj.Name:lower():find("zombie") and obj:IsA("Model") then local h=obj:FindFirstChildOfClass("Humanoid"); if h and h.Health<=0 then updateESP(obj, ESP_COLORS.ZombieDead, "Dead", "") end end
                    if S.toggles.Pallet and obj.Name=="Newpallet" then updateESP(obj, ESP_COLORS.Pallet, "Pallet", "") end
                    if S.toggles.Hook and obj.Name=="Hook" and obj:FindFirstChild("HookPoint") then updateESP(obj, ESP_COLORS.Hook, "Hook", "") end
                    if S.toggles.Gate and obj.Name=="Gate" and obj:FindFirstChild("LeftGate") then updateESP(obj, ESP_COLORS.Gate, "Gate", "") end
                    if S.toggles.Gate and obj.Name=="ExitLever" then updateESP(obj, ESP_COLORS.Gate, "Lever", "") end
                    if S.toggles.Vault and obj.Name=="VaultTrigger" then updateESP(obj, ESP_COLORS.Vault, "Vault", "") end
                    if S.toggles.Trap and obj.Name=="BearTrap" and (obj:GetAttribute("Armed") or obj:GetAttribute("ButcherTrapOwnerUserId")) then updateESP(obj, ESP_COLORS.Trap, "Trap", "") end
                end
            end
        end
        task.wait(5)
    end
end)

-- ==========================================
-- AUTO SKILLCHECK MODULE (LOGIKA BARU)
-- ==========================================
local check, line, goal, action

local function refreshSkillRefs()
    pcall(function()
        local sGui = PG:FindFirstChild("SkillCheckPromptGui") or PG:FindFirstChild("SkillCheckPromptGui-con")
        if sGui then
            check = sGui:FindFirstChild("Check")
            if check then
                line = check:FindFirstChild("Line")
                goal = check:FindFirstChild("Goal")
            end
        end
        local mob = PG:FindFirstChild("Survivor-mob")
        if mob then
            local ctrl = mob:FindFirstChild("Controls")
            if ctrl then
                action = ctrl:FindFirstChild("action")
            end
        end
    end)
end
refreshSkillRefs()

task.spawn(function()
    while S.running do
        refreshSkillRefs()
        task.wait(0.5)
    end
end)

local function triggerAction()
    if not action then refreshSkillRefs() end
    if not action then return false end
    
    -- Activate (bawaan Roblox)
    pcall(function()
        if action:IsA("GuiButton") then
            action:Activate()
        end
    end)
    
    -- Firesignal (sesuai ParryClient)
    if typeof(firesignal) == "function" then
        pcall(function()
            firesignal(action.MouseButton1Down)
            task.wait(0.05)
            firesignal(action.MouseButton1Up)
        end)
    end
    return true
end

local function isSuccess()
    if not line or not goal then return false end
    local lr = tonumber(line.Rotation) or 0
    local gr = tonumber(goal.Rotation) or 0
    return lr >= (gr + 102) and lr <= (gr + 116)
end

local function doSkillParry()
    local now = tick()
    if now - S.skillLastTrigger < 0.05 then return end
    S.skillLastTrigger = now
    triggerAction()
end

-- King Scourge Start & End listener
if KingScourgeStart then
    KingScourgeStart.OnClientEvent:Connect(function()
        S.scourgeActive = true
    end)
end
if KingScourgeEnd then
    KingScourgeEnd.OnClientEvent:Connect(function()
        S.scourgeActive = false
    end)
end

RunService.RenderStepped:Connect(function()
    if not S.running or not S.autoSkillEnabled then return end
    if not check then refreshSkillRefs() end
    if not check or not check.Visible then return end
    
    if isSuccess() then
        doSkillParry()
    end
end)

-- ==========================================
-- FULLBRIGHT MODULE
-- ==========================================
local function setFullbright(state)
    if state then
        if not S.lightingBackup then
            S.lightingBackup = {
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                Brightness = Lighting.Brightness,
                GlobalShadows = Lighting.GlobalShadows,
                EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
                EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd
            }
        end
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 2
        Lighting.GlobalShadows = false
        Lighting.EnvironmentDiffuseScale = 1
        Lighting.EnvironmentSpecularScale = 1
        Lighting.ClockTime = 12
        Lighting.FogEnd = 100000
    else
        if S.lightingBackup then
            Lighting.Ambient = S.lightingBackup.Ambient
            Lighting.OutdoorAmbient = S.lightingBackup.OutdoorAmbient
            Lighting.Brightness = S.lightingBackup.Brightness
            Lighting.GlobalShadows = S.lightingBackup.GlobalShadows
            Lighting.EnvironmentDiffuseScale = S.lightingBackup.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = S.lightingBackup.EnvironmentSpecularScale
            Lighting.ClockTime = S.lightingBackup.ClockTime
            Lighting.FogEnd = S.lightingBackup.FogEnd
        end
    end
end

-- ==========================================
-- UI SETUP
-- ==========================================
local gui = Instance.new("ScreenGui"); gui.Name="VanzCheat"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
gui.DisplayOrder=2147483647; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=getUIParent()

local function mk(cls, props, parent) local i=Instance.new(cls); for k,v in pairs(props) do i[k]=v end; if parent then i.Parent=parent end; return i end

local mainFrame = mk("Frame", {Size=UDim2.new(0,280,0.85,0), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(26,26,26), BorderSizePixel=0}, gui)
mk("UICorner",{CornerRadius=UDim.new(0,8)},mainFrame); mk("UIStroke",{Color=Color3.fromRGB(50,50,50),Thickness=1},mainFrame)

local tb = mk("Frame", {Size=UDim2.new(1,0,0,44), BackgroundColor3=Color3.fromRGB(20,20,20), BorderSizePixel=0}, mainFrame)
mk("UICorner",{CornerRadius=UDim.new(0,8)},tb)
mk("TextLabel", {Size=UDim2.new(1,-160,1,0), Position=UDim2.new(0,12,0,0), BackgroundTransparency=1, Text="VANZ CHEAT", TextColor3=Color3.fromRGB(255,255,255), Font=Enum.Font.GothamBold, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left}, tb)

local function mkBtn(text,xOff,parent) local b=mk("TextButton",{Size=UDim2.new(0,36,0,36),Position=UDim2.new(1,xOff,0.5,-18),BackgroundColor3=Color3.fromRGB(45,45,45),Text=text,TextColor3=Color3.fromRGB(220,220,220),Font=Enum.Font.GothamBold,TextSize=14,BorderSizePixel=0},parent); mk("UICorner",{CornerRadius=UDim.new(0,6)},b); return b end

local lockBtn=mkBtn("🔓",-120,tb); local minBtn=mkBtn("─",-80,tb); local closeBtn=mkBtn("✕",-40,tb)
local tf=mk("Frame",{Size=UDim2.new(1,0,0,40),Position=UDim2.new(0,0,0,44),BackgroundTransparency=1},mainFrame)
local function ct(text,x,w) return mk("TextButton",{Size=UDim2.new(w,-4,1,-4),Position=UDim2.new(x,2,0,2),BackgroundColor3=Color3.fromRGB(40,40,40),Text=text,TextColor3=Color3.fromRGB(200,200,200),Font=Enum.Font.GothamBold,TextSize=12,BorderSizePixel=0},tf) end

local tabESP=ct("ESP",0,0.5); mk("UICorner",{CornerRadius=UDim.new(0,6)},tabESP)
local tabSurv=ct("SURVIVOR",0.5,0.5); mk("UICorner",{CornerRadius=UDim.new(0,6)},tabSurv)

local cf=mk("Frame",{Size=UDim2.new(1,0,1,-84),Position=UDim2.new(0,0,0,84),BackgroundTransparency=1},mainFrame)

-- ESP TAB
local ep=mk("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y},cf)
local mr=mk("Frame",{Size=UDim2.new(1,-16,0,44),Position=UDim2.new(0,8,0,8),BackgroundTransparency=1},ep)
mk("TextLabel",{Size=UDim2.new(1,-70,1,0),BackgroundTransparency=1,Text="Master ESP",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left},mr)
local mt=mk("TextButton",{Size=UDim2.new(0,60,0,30),Position=UDim2.new(1,-60,0.5,-15),BackgroundColor3=S.enabledESP and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60),Text=S.enabledESP and "ON" or "OFF",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0},mr)
mk("UICorner",{CornerRadius=UDim.new(0,5)},mt)
mt.MouseButton1Click:Connect(function() S.enabledESP=not S.enabledESP; mt.Text=S.enabledESP and "ON" or "OFF"; mt.BackgroundColor3=S.enabledESP and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60) end)

-- FULLBRIGHT TOGGLE
local fbr=mk("Frame",{Size=UDim2.new(1,-16,0,44),Position=UDim2.new(0,8,0,56),BackgroundTransparency=1},ep)
mk("TextLabel",{Size=UDim2.new(1,-70,1,0),BackgroundTransparency=1,Text="Fullbright (No Shadow)",TextColor3=Color3.fromRGB(200,200,200),Font=Enum.Font.Gotham,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left},fbr)
local fbt=mk("TextButton",{Size=UDim2.new(0,60,0,30),Position=UDim2.new(1,-60,0.5,-15),BackgroundColor3=S.fullbrightEnabled and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60),Text=S.fullbrightEnabled and "ON" or "OFF",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0},fbr)
mk("UICorner",{CornerRadius=UDim.new(0,5)},fbt)
fbt.MouseButton1Click:Connect(function() 
    S.fullbrightEnabled = not S.fullbrightEnabled
    fbt.Text = S.fullbrightEnabled and "ON" or "OFF"
    fbt.BackgroundColor3 = S.fullbrightEnabled and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60)
    setFullbright(S.fullbrightEnabled)
end)

-- List ESP
local el={"Killer","Survivor","Generator","Pallet","Hook","Vault","Trap","Gate","Zombie","Pumpkin"}; local ey=104
for _,n in ipairs(el) do
    local r=mk("Frame",{Size=UDim2.new(1,-16,0,44),Position=UDim2.new(0,8,0,ey),BackgroundTransparency=1},ep)
    mk("TextLabel",{Size=UDim2.new(1,-70,1,0),BackgroundTransparency=1,Text=n.." ESP",TextColor3=Color3.fromRGB(200,200,200),Font=Enum.Font.Gotham,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left},r)
    local t=mk("TextButton",{Size=UDim2.new(0,60,0,30),Position=UDim2.new(1,-60,0.5,-15),BackgroundColor3=S.toggles[n] and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60),Text=S.toggles[n] and "ON" or "OFF",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0},r)
    mk("UICorner",{CornerRadius=UDim.new(0,5)},t)
    t.MouseButton1Click:Connect(function() S.toggles[n]=not S.toggles[n]; t.Text=S.toggles[n] and "ON" or "OFF"; t.BackgroundColor3=S.toggles[n] and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60) end)
    ey=ey+44
end

-- SURVIVOR TAB
local sp=mk("Frame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Visible=false},cf)
local ss=mk("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y},sp)
local function createSurvToggle(yPos,text,key,callback)
    local r=mk("Frame",{Size=UDim2.new(1,-16,0,44),Position=UDim2.new(0,8,0,yPos),BackgroundTransparency=1},ss)
    mk("TextLabel",{Size=UDim2.new(1,-70,1,0),BackgroundTransparency=1,Text=text,TextColor3=Color3.fromRGB(200,200,200),Font=Enum.Font.Gotham,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left},r)
    local t=mk("TextButton",{Size=UDim2.new(0,60,0,30),Position=UDim2.new(1,-60,0.5,-15),BackgroundColor3=S[key] and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60),Text=S[key] and "ON" or "OFF",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0},r)
    mk("UICorner",{CornerRadius=UDim.new(0,5)},t)
    t.MouseButton1Click:Connect(function() S[key]=not S[key]; t.Text=S[key] and "ON" or "OFF"; t.BackgroundColor3=S[key] and Color3.fromRGB(40,140,70) or Color3.fromRGB(60,60,60); if callback then callback(S[key]) end end)
end
createSurvToggle(8,"Auto Skillcheck","autoSkillEnabled")

-- FLOATING MAIN BTN
local mb=mk("TextButton",{Size=UDim2.new(0,50,0,50),Position=S.miniPos,BackgroundColor3=Color3.fromRGB(26,26,26),Text="VC",TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamBold,TextSize=16,BorderSizePixel=0,Visible=false},gui)
mk("UICorner",{CornerRadius=UDim.new(0,10)},mb); mk("UIStroke",{Color=Color3.fromRGB(60,60,60),Thickness=1},mb)
local md,mds,msp=false,nil,nil
mb.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then md,mds,msp=true,input.Position,mb.Position; input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then md=false end end) end end)
UserInputService.InputChanged:Connect(function(input) if md and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then local d=input.Position-mds; mb.Position=UDim2.new(msp.X.Scale,msp.X.Offset+d.X,msp.Y.Scale,msp.Y.Offset+d.Y); S.miniPos=mb.Position end end)
local mm=false
mb.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then mm=false; local s=mb.Position; task.delay(0.15,function() if mb.Position~=s then mm=true end end) end end)
mb.MouseButton1Click:Connect(function() if not mm then mb.Visible=false; mainFrame.Visible=true end end)
minBtn.MouseButton1Click:Connect(function() S.miniPos=UDim2.new(mainFrame.Position.X.Scale,mainFrame.Position.X.Offset+(mainFrame.Size.X.Offset/2)-25,mainFrame.Position.Y.Scale,mainFrame.Position.Y.Offset+5); mb.Position=S.miniPos; mainFrame.Visible=false; mb.Visible=true end)

-- DRAG UI
local dg,ds,dp=false,nil,nil
tb.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then if S.lockUI then return end; dg,ds,dp=true,input.Position,mainFrame.Position; input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dg=false end end) end end)
UserInputService.InputChanged:Connect(function(input) if dg and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then local d=input.Position-ds; mainFrame.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y); S.winPos=mainFrame.Position end end)
lockBtn.MouseButton1Click:Connect(function() S.lockUI=not S.lockUI; lockBtn.Text=S.lockUI and "🔒" or "🔓" end)
closeBtn.MouseButton1Click:Connect(function() S.shutdown() end)

local function stTab(t) 
    ep.Visible=t=="E"; sp.Visible=t=="S"
    tabESP.BackgroundColor3=t=="E" and Color3.fromRGB(60,60,60) or Color3.fromRGB(30,30,30)
    tabSurv.BackgroundColor3=t=="S" and Color3.fromRGB(60,60,60) or Color3.fromRGB(30,30,30)
end
tabESP.MouseButton1Click:Connect(function() stTab("E") end)
tabSurv.MouseButton1Click:Connect(function() stTab("S") end)
stTab("E")

function S.shutdown()
    S.running = false
    if S.fullbrightEnabled then setFullbright(false) end
    for o, _ in pairs(espCache) do cleanESP(o) end
    pcall(function() if gui then gui:Destroy() end end)
    getgenv().vanzCheat = nil
end

print("[VANZ] ESP + Fullbright + Auto Skillcheck (Activate + King Scourge) Loaded.")
