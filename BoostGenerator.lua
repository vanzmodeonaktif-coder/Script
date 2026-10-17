local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local function getParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    return PG
end

local REPAIR = RS:WaitForChild("Remotes"):WaitForChild("Generator"):WaitForChild("RepairEvent")
local PROGRESS = RS:WaitForChild("Remotes"):WaitForChild("Progress"):WaitForChild("ProgressUpdateEvent")

local ROOT_NAMES = { "newGenerators", "Generators", "Generator" }
local HOLD_TIME = 0.8
local DECOY_GAP = 0.25
local INTER_GAP = 0.7
local SCAN_RETRY = 10
local SCAN_RETRY_DELAY = 0.2
local AUTO_DONE_TARGET = 5
local KILLER_RADIUS = 35
local TELEPORT_OFFSET = 5

local SKILL = {
    Mode = "INSTANT",
    SuccessMin = 102,
    SuccessMax = 116,
    NeutralMin = 116,
    NeutralMax = 159,
    InstantAngle = 109,
    TriggerDelay = 0.035,
    LastTrigger = 0,
    Busy = false,
    PreviousVisible = false,
    ScourgeActive = false,
    Check = nil,
    Line = nil,
    Goal = nil,
    Action = nil,
    Hits = 0,
}

local S = {
    Active = false,
    AutoActive = false,
    AntiKillerActive = false,
    Locked = false,
    GenIndex = nil,
    GenModel = nil,
    Points = {},
    AllTouchedPoints = {},
    CycleThread = nil,
    WatchThread = nil,
    AutoThread = nil,
    AntiThread = nil,
    CurrentPoint = nil,
    CurrentPointIdx = 0,
    CurrentPhase = "-",
    Progress = 0,
    ForceSkip = false,
    GenProgress = {},
    GenDone = {},
    SortedGens = {},
    EspLabels = {},
    EspBoxes = {},
}

local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

local function classifyPlayer(plr)
    if not plr or plr == LP then return "self" end
    local myTeam = LP.Team
    local theirTeam = plr.Team
    if myTeam and theirTeam then
        if myTeam == theirTeam then return "team" end
        return "enemy"
    end
    local myRole = LP:GetAttribute("Role")
    local theirRole = plr:GetAttribute("Role")
    if myRole and theirRole then
        if myRole == theirRole then return "team" end
        return "enemy"
    end
    return "unknown"
end

local function refreshSkillRefs()
    pcall(function()
        local SkillGui = PG:FindFirstChild("SkillCheckPromptGui")
        if SkillGui then
            SKILL.Check = SkillGui:FindFirstChild("Check")
            if SKILL.Check then
                SKILL.Line = SKILL.Check:FindFirstChild("Line")
                SKILL.Goal = SKILL.Check:FindFirstChild("Goal")
            end
        end
        local Survivor = PG:FindFirstChild("Survivor-mob")
        if Survivor then
            local Controls = Survivor:FindFirstChild("Controls")
            if Controls then
                SKILL.Action = Controls:FindFirstChild("action")
            end
        end
    end)
end

refreshSkillRefs()
task.spawn(function()
    while true do
        refreshSkillRefs()
        task.wait(0.5)
    end
end)

local function triggerAction()
    if not SKILL.Action then refreshSkillRefs() end
    if not SKILL.Action then return false end
    local now = os.clock()
    if now - SKILL.LastTrigger < SKILL.TriggerDelay then return false end
    SKILL.LastTrigger = now
    pcall(function()
        if SKILL.Action:IsA("GuiButton") then SKILL.Action:Activate() end
    end)
    if typeof(firesignal) == "function" then
        pcall(function() firesignal(SKILL.Action.MouseButton1Down) end)
    end
    SKILL.Hits = SKILL.Hits + 1
    return true
end

local function getAngle()
    if not SKILL.Line or not SKILL.Goal then return nil end
    return tonumber(SKILL.Line.Rotation) or 0, tonumber(SKILL.Goal.Rotation) or 0
end

local function isSuccess()
    local lr, gr = getAngle()
    if not lr then return false end
    return lr >= (gr + SKILL.SuccessMin) and lr <= (gr + SKILL.SuccessMax)
end

local function isNeutral()
    local lr, gr = getAngle()
    if not lr then return false end
    return lr > (gr + SKILL.NeutralMin) and lr <= (gr + SKILL.NeutralMax)
end

local function startWatchThread()
    if S.WatchThread then pcall(task.cancel, S.WatchThread) end
    SKILL.Busy = false
    SKILL.PreviousVisible = false
    SKILL.Hits = 0
    S.WatchThread = task.spawn(function()
        while (S.Active or S.AutoActive) do
            if not SKILL.Check then refreshSkillRefs() end
            if SKILL.Check and SKILL.Check.Parent then
                local Visible = SKILL.Check.Visible
                if Visible and not SKILL.PreviousVisible then
                    SKILL.Busy = false
                    if SKILL.Mode == "INSTANT" and SKILL.Line and SKILL.Goal then
                        local gr = tonumber(SKILL.Goal.Rotation) or 0
                        pcall(function() SKILL.Line.Rotation = gr + SKILL.InstantAngle end)
                        triggerAction()
                    end
                end
                SKILL.PreviousVisible = Visible
                if Visible and not SKILL.Busy then
                    local should = false
                    if SKILL.Mode == "SUCCESS" then should = isSuccess()
                    elseif SKILL.Mode == "NEUTRAL" then should = isNeutral() end
                    if should then
                        SKILL.Busy = true
                        triggerAction()
                        task.delay(0.07, function() SKILL.Busy = false end)
                    end
                end
            else
                SKILL.PreviousVisible = false
            end
            task.wait(0.005)
        end
    end)
end

local function stopWatchThread()
    if S.WatchThread then pcall(task.cancel, S.WatchThread); S.WatchThread = nil end
    SKILL.Busy = false
    SKILL.PreviousVisible = false
end

local function stopCycleThread()
    if S.CycleThread then pcall(task.cancel, S.CycleThread); S.CycleThread = nil end
end

local function markTouched(point)
    if point then S.AllTouchedPoints[point] = true end
end

local function startCycleThread()
    stopCycleThread()
    S.CycleThread = task.spawn(function()
        local activeFlag = function() return S.Active or S.AutoActive end
        for i = 1, #S.Points do
            if not activeFlag() then return end
            local point = S.Points[i]

            S.CurrentPoint = point
            S.CurrentPointIdx = i
            S.CurrentPhase = "HOLD"

            markTouched(point)
            pcall(function() REPAIR:FireServer(point, true) end)
            task.wait(HOLD_TIME)

            if not activeFlag() then
                pcall(function() REPAIR:FireServer(point, false) end)
                return
            end

            S.CurrentPhase = "RELEASE"
            pcall(function() REPAIR:FireServer(point, false) end)
            task.wait(DECOY_GAP)

            if not activeFlag() then return end

            S.CurrentPhase = "STAY"
            pcall(function() REPAIR:FireServer(point, true) end)

            if i < #S.Points then
                S.CurrentPhase = "GAP"
                task.wait(INTER_GAP)
            end
        end
        if activeFlag() then S.CurrentPhase = "DONE" end
    end)
end

local function findGeneratorsRoot()
    local ws = workspace
    local map = ws:FindFirstChild("Map")
    if map then
        for _, name in ipairs(ROOT_NAMES) do
            local g = map:FindFirstChild(name)
            if g then return g end
        end
    end
    for _, name in ipairs(ROOT_NAMES) do
        local g = ws:FindFirstChild(name)
        if g then return g end
    end
    return nil
end

local function modelHasPoints(m)
    for _, c in ipairs(m:GetChildren()) do
        if c:IsA("BasePart") and c.Name:match("^GeneratorPoint%d+$") then
            return true
        end
    end
    return false
end

local function collectGenModels()
    local models = {}
    local seen = {}
    local root = findGeneratorsRoot()
    if root then
        for _, child in ipairs(root:GetChildren()) do
            if (child:IsA("Model") or child:IsA("Folder")) and modelHasPoints(child) and not seen[child] then
                table.insert(models, child)
                seen[child] = true
            end
        end
        if #models == 0 then
            for _, desc in ipairs(root:GetDescendants()) do
                if (desc:IsA("Model") or desc:IsA("Folder")) and modelHasPoints(desc) and not seen[desc] then
                    table.insert(models, desc)
                    seen[desc] = true
                end
            end
        end
    end
    if #models == 0 then
        for _, d in ipairs(workspace:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("Folder")) and modelHasPoints(d) and not seen[d] then
                table.insert(models, d)
                seen[d] = true
            end
        end
    end
    return models
end

local function getModelPosition(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart.Position end
    local sum, count = Vector3.zero, 0
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name:match("^GeneratorPoint%d+$") then
            sum = sum + p.Position
            count = count + 1
        end
    end
    if count > 0 then return sum / count end
    return nil
end

local function sortGensByX(models)
    table.sort(models, function(a, b)
        local pa = getModelPosition(a)
        local pb = getModelPosition(b)
        if not pa or not pb then return false end
        return pa.X < pb.X
    end)
end

local function refreshSortedGens()
    S.SortedGens = collectGenModels()
    sortGensByX(S.SortedGens)
end

local function collectPoints(gen)
    local list = {}
    for _, p in ipairs(gen:GetChildren()) do
        if p:IsA("BasePart") and p.Name:match("^GeneratorPoint%d+$") then
            local n = tonumber(p.Name:match("^GeneratorPoint(%d+)$")) or 0
            table.insert(list, {p = p, n = n})
        end
    end
    table.sort(list, function(a, b) return a.n < b.n end)
    local out = {}
    for _, v in ipairs(list) do table.insert(out, v.p) end
    return out
end

local function detectNearestGenerator()
    local models = collectGenModels()
    if #models == 0 then return nil, nil end
    local char = LP.Character
    if not char then return nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local myPos = hrp.Position
    local bestIdx, bestModel, bestDist = nil, nil, math.huge
    for i, model in ipairs(models) do
        local pos = getModelPosition(model)
        if pos then
            local d = (pos - myPos).Magnitude
            if d < bestDist then
                bestDist, bestIdx, bestModel = d, i, model
            end
        end
    end
    return bestIdx, bestModel
end

local function getGenProgress(model)
    if not model then return 0 end
    if S.GenDone[model] then return 100 end

    for _, n in ipairs({"Progress", "RepairProgress", "ProgressValue", "RepairAmount"}) do
        local v = model:GetAttribute(n)
        if typeof(v) == "number" then return v end
    end
    for _, n in ipairs({"Repaired", "IsRepaired", "Done", "IsDone", "Completed"}) do
        local v = model:GetAttribute(n)
        if v == true then return 100 end
    end
    for _, c in ipairs(model:GetDescendants()) do
        if c:IsA("NumberValue") or c:IsA("IntValue") then
            local low = string.lower(c.Name)
            if low:find("progress") or low:find("repair") then
                return c.Value
            end
        end
    end

    return S.GenProgress[model] or 0
end

local function isGenDone(model)
    if not model then return false end
    if S.GenDone[model] then return true end
    if getGenProgress(model) >= 100 then
        S.GenDone[model] = true
        return true
    end
    return false
end

local function genScore(gen)
    if not gen then return -1 end
    if isGenDone(gen) then return -1 end
    return S.GenProgress[gen] or 0
end

local function countDone()
    local n = 0
    for _, g in ipairs(S.SortedGens) do
        if isGenDone(g) then n = n + 1 end
    end
    return n
end

local function findBestTargetGen(skipGen)
    refreshSortedGens()
    local candidates = {}

    for _, g in ipairs(S.SortedGens) do
        if not isGenDone(g) and g ~= skipGen then
            local pos = getModelPosition(g)
            if pos then
                local nearestKiller = math.huge
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p.Character and classifyPlayer(p) == "enemy" then
                        local ph = p.Character:FindFirstChild("HumanoidRootPart")
                        local hum = p.Character:FindFirstChildOfClass("Humanoid")
                        if ph and hum and hum.Health > 0 then
                            local d = (ph.Position - pos).Magnitude
                            if d < nearestKiller then nearestKiller = d end
                        end
                    end
                end

                table.insert(candidates, {
                    gen = g,
                    score = genScore(g),
                    killerDist = nearestKiller,
                    safe = nearestKiller > KILLER_RADIUS,
                })
            end
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        if a.safe ~= b.safe then return a.safe end
        if a.safe then
            return a.score > b.score
        end
        return a.killerDist > b.killerDist
    end)

    return candidates[1].gen
end

local function safeTeleportToGen(gen)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not gen then return false end
    local genPos = getModelPosition(gen)
    if not genPos then return false end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}

    local dirs = {
        Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
        Vector3.new(0.707, 0, 0.707), Vector3.new(-0.707, 0, 0.707),
        Vector3.new(0.707, 0, -0.707), Vector3.new(-0.707, 0, -0.707),
    }

    local ordered = {}
    for _, d in ipairs(dirs) do
        local p = genPos + d * TELEPORT_OFFSET
        table.insert(ordered, {dir = d, dist = (p - hrp.Position).Magnitude})
    end
    table.sort(ordered, function(a, b) return a.dist < b.dist end)

    for _, entry in ipairs(ordered) do
        local testOrigin = genPos + Vector3.new(0, 3, 0)
        local result = workspace:Raycast(testOrigin, entry.dir * TELEPORT_OFFSET, params)
        if not result then
            local targetPos = genPos + entry.dir * TELEPORT_OFFSET + Vector3.new(0, 3, 0)
            pcall(function() hrp.CFrame = CFrame.new(targetPos) end)
            return true
        end
    end

    pcall(function() hrp.CFrame = CFrame.new(genPos + Vector3.new(0, 5, 0)) end)
    return true
end

-- =========================================================
-- RELEASE ALL — fire false ke semua point yang pernah di-true
-- =========================================================
local function releaseAll()
    local targets = {}
    local seen = {}

    for _, p in ipairs(S.Points) do
        if p and not seen[p] then
            seen[p] = true
            table.insert(targets, p)
        end
    end
    for p, _ in pairs(S.AllTouchedPoints) do
        if p and not seen[p] then
            seen[p] = true
            table.insert(targets, p)
        end
    end

    for _, p in ipairs(targets) do
        pcall(function() REPAIR:FireServer(p, false) end)
    end

    task.delay(0.1, function()
        for _, p in ipairs(targets) do
            pcall(function() REPAIR:FireServer(p, false) end)
        end
    end)

    task.delay(0.25, function()
        for _, p in ipairs(targets) do
            pcall(function() REPAIR:FireServer(p, false) end)
        end
    end)
end

local function hardStop()
    S.Active = false
    S.AutoActive = false
    S.ForceSkip = false
    stopCycleThread()
    stopWatchThread()
    if S.AutoThread then pcall(task.cancel, S.AutoThread); S.AutoThread = nil end
    releaseAll()
    S.Points = {}
    S.AllTouchedPoints = {}
    S.GenIndex = nil
    S.GenModel = nil
    S.CurrentPoint = nil
    S.CurrentPointIdx = 0
    S.CurrentPhase = "-"
    S.Progress = 0
end

local function startAutoGen()
    if S.AutoActive then return end
    S.AutoActive = true
    S.ForceSkip = false

    refreshSortedGens()
    if #S.SortedGens == 0 then
        S.AutoActive = false
        return
    end

    S.AutoThread = task.spawn(function()
        while S.AutoActive do
            if countDone() >= AUTO_DONE_TARGET then
                break
            end

            local needNew = false
            if not S.GenModel then
                needNew = true
            elseif isGenDone(S.GenModel) then
                needNew = true
            elseif S.ForceSkip then
                needNew = true
            end

            if needNew then
                releaseAll()
                stopCycleThread()
                stopWatchThread()

                local skipGen = nil
                if S.GenModel and S.ForceSkip then
                    skipGen = S.GenModel
                end

                local nextGen = findBestTargetGen(skipGen)

                if nextGen then
                    safeTeleportToGen(nextGen)
                    task.wait(0.4)
                    S.GenModel = nextGen
                    S.Points = collectPoints(nextGen)
                    S.Progress = S.GenProgress[nextGen] or 0
                    S.ForceSkip = false
                    startCycleThread()
                    startWatchThread()
                else
                    S.ForceSkip = false
                    S.GenModel = nil
                    S.Points = {}
                end
            end

            task.wait(0.3)
        end

        S.AutoActive = false
        releaseAll()
        stopCycleThread()
        stopWatchThread()
        S.GenModel = nil
        S.Points = {}
    end)
end

local function stopAutoGen()
    S.AutoActive = false
    S.ForceSkip = false
    if S.AutoThread then pcall(task.cancel, S.AutoThread); S.AutoThread = nil end
    stopCycleThread()
    stopWatchThread()
    releaseAll()
    S.GenModel = nil
    S.Points = {}
    S.AllTouchedPoints = {}
end

local function startAntiKiller()
    if S.AntiThread then return end
    S.AntiKillerActive = true
    S.AntiThread = task.spawn(function()
        while S.AntiKillerActive do
            if S.AutoActive then
                local char = LP.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LP and p.Character and classifyPlayer(p) == "enemy" then
                            local ph = p.Character:FindFirstChild("HumanoidRootPart")
                            local hum = p.Character:FindFirstChildOfClass("Humanoid")
                            if ph and hum and hum.Health > 0 then
                                if (ph.Position - hrp.Position).Magnitude <= KILLER_RADIUS then
                                    S.ForceSkip = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
            task.wait(0.15)
        end
    end)
end

local function stopAntiKiller()
    S.AntiKillerActive = false
    S.ForceSkip = false
    if S.AntiThread then pcall(task.cancel, S.AntiThread); S.AntiThread = nil end
end

local function getTopPart(model)
    if model.PrimaryPart then return model.PrimaryPart end
    local best, bestY = nil, -math.huge
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p.Position.Y > bestY then
            best, bestY = p, p.Position.Y
        end
    end
    return best
end

local function createEspFor(model)
    if S.EspBoxes[model] then return end
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end
    if #parts == 0 then return end

    local lines = {}
    if hasDrawing then
        for i = 1, 4 do
            local l = Drawing.new("Line")
            l.Visible = false
            l.Color = Color3.fromRGB(255, 165, 0)
            l.Thickness = 1.5
            l.Transparency = 1
            lines[i] = l
        end
    end

    local bb = Instance.new("BillboardGui")
    bb.Name = "VanzGenEsp"
    bb.Size = UDim2.new(0, 100, 0, 18)
    bb.AlwaysOnTop = true
    bb.MaxDistance = math.huge
    bb.LightInfluence = 0

    local topPart = getTopPart(model)
    if topPart then
        bb.Adornee = topPart
        bb.StudsOffsetWorldSpace = Vector3.new(0, topPart.Size.Y / 2 + 2, 0)
    end

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "0%"
    lbl.TextColor3 = Color3.fromRGB(255, 165, 0)
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0.3
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.Parent = bb
    bb.Parent = PG

    S.EspBoxes[model] = {lines = lines, parts = parts, bb = bb, lbl = lbl}
    S.EspLabels[model] = lbl
end

local function removeEspFor(model)
    local box = S.EspBoxes[model]
    if box then
        for _, l in ipairs(box.lines) do
            pcall(function() l:Remove() end)
        end
        if box.bb then pcall(function() box.bb:Destroy() end) end
        S.EspBoxes[model] = nil
        S.EspLabels[model] = nil
    end
end

local function clearAllEsp()
    for model, _ in pairs(S.EspBoxes) do
        removeEspFor(model)
    end
    S.EspBoxes = {}
    S.EspLabels = {}
end

local function updateEsp()
    local cam = workspace.CurrentCamera
    if not cam then return end
    refreshSortedGens()

    local valid = {}
    for _, gen in ipairs(S.SortedGens) do valid[gen] = true end

    for model, _ in pairs(S.EspBoxes) do
        if not valid[model] or not model.Parent then
            removeEspFor(model)
        end
    end

    for _, gen in ipairs(S.SortedGens) do
        if isGenDone(gen) then
            if S.EspBoxes[gen] then removeEspFor(gen) end
        else
            createEspFor(gen)
            local box = S.EspBoxes[gen]
            if box then
                local ok = true
                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge

                for _, part in ipairs(box.parts) do
                    if not part.Parent then ok = false break end
                    local size = part.Size
                    local cf = part.CFrame
                    for ix = -1, 1, 2 do
                        for iy = -1, 1, 2 do
                            for iz = -1, 1, 2 do
                                local corner = cf * Vector3.new(
                                    size.X / 2 * ix,
                                    size.Y / 2 * iy,
                                    size.Z / 2 * iz)
                                local sp, on = cam:WorldToViewportPoint(corner)
                                if sp.Z > 0 and on then
                                    if sp.X < minX then minX = sp.X end
                                    if sp.Y < minY then minY = sp.Y end
                                    if sp.X > maxX then maxX = sp.X end
                                    if sp.Y > maxY then maxY = sp.Y end
                                end
                            end
                        end
                    end
                end

                if ok and minX < maxX and minY < maxY and minX > -5000 then
                    local l = box.lines
                    if #l == 4 then
                        l[1].From = Vector2.new(minX, minY)
                        l[1].To = Vector2.new(maxX, minY)
                        l[2].From = Vector2.new(maxX, minY)
                        l[2].To = Vector2.new(maxX, maxY)
                        l[3].From = Vector2.new(maxX, maxY)
                        l[3].To = Vector2.new(minX, maxY)
                        l[4].From = Vector2.new(minX, maxY)
                        l[4].To = Vector2.new(minX, minY)
                        for i = 1, 4 do l[i].Visible = true end
                    end
                else
                    for i = 1, #box.lines do box.lines[i].Visible = false end
                end

                local prog = getGenProgress(gen)
                if box.lbl then
                    box.lbl.Text = string.format("%.1f%%", prog)
                end
            end
        end
    end
end

local KingScourgeStart, KingScourgeEnd
pcall(function()
    local KS = RS:WaitForChild("Remotes"):WaitForChild("KillerPerks"):WaitForChild("kingscourge")
    KingScourgeStart = KS:WaitForChild("KingScourgeStart")
    KingScourgeEnd = KS:WaitForChild("KingScourgeEnd")
end)

if KingScourgeStart then
    KingScourgeStart.OnClientEvent:Connect(function()
        if not (S.Active or S.AutoActive) then return end
        SKILL.ScourgeActive = true
        SKILL.Busy = false
        task.defer(function()
            if not (S.Active or S.AutoActive) then return end
            if SKILL.Mode == "INSTANT"
            and SKILL.Check and SKILL.Check.Visible
            and SKILL.Line and SKILL.Goal then
                local gr = tonumber(SKILL.Goal.Rotation) or 0
                pcall(function() SKILL.Line.Rotation = gr + SKILL.InstantAngle end)
                triggerAction()
            end
        end)
    end)
end

if KingScourgeEnd then
    KingScourgeEnd.OnClientEvent:Connect(function()
        SKILL.ScourgeActive = false
        SKILL.Busy = false
    end)
end

local sg = Instance.new("ScreenGui")
sg.Name = "VanzBoost_" .. tostring(math.random(100000, 999999))
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 2147483647
sg.Parent = getParent()

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 208)
main.Position = UDim2.new(0, 20, 0, 120)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
main.BorderSizePixel = 0
main.Active = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local mstr = Instance.new("UIStroke", main)
mstr.Color = Color3.fromRGB(80, 80, 100)
mstr.Thickness = 1

local mtitle = Instance.new("TextLabel")
mtitle.Size = UDim2.new(0, 60, 0, 26)
mtitle.Position = UDim2.new(0, 10, 0, 4)
mtitle.BackgroundTransparency = 1
mtitle.Text = "BOOST"
mtitle.TextColor3 = Color3.fromRGB(255, 80, 80)
mtitle.Font = Enum.Font.GothamBold
mtitle.TextSize = 14
mtitle.TextXAlignment = Enum.TextXAlignment.Left
mtitle.Parent = main

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(1, -54, 0, 5)
minBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.BorderSizePixel = 0
minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 220, 220)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.BorderSizePixel = 0
closeBtn.Parent = main
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

local dragArea = Instance.new("TextButton")
dragArea.Size = UDim2.new(1, -130, 0, 26)
dragArea.Position = UDim2.new(0, 70, 0, 4)
dragArea.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
dragArea.Text = ""
dragArea.AutoButtonColor = false
dragArea.BorderSizePixel = 0
dragArea.Parent = main
Instance.new("UICorner", dragArea).CornerRadius = UDim.new(0, 4)

local boostBtn = Instance.new("TextButton")
boostBtn.Size = UDim2.new(1, -20, 0, 34)
boostBtn.Position = UDim2.new(0, 10, 0, 36)
boostBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
boostBtn.Text = "START"
boostBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
boostBtn.Font = Enum.Font.GothamBold
boostBtn.TextSize = 13
boostBtn.BorderSizePixel = 0
boostBtn.AutoButtonColor = false
boostBtn.Parent = main
Instance.new("UICorner", boostBtn).CornerRadius = UDim.new(0, 6)

local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0.5, -15, 0, 26)
modeBtn.Position = UDim2.new(0, 10, 0, 76)
modeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
modeBtn.Text = "MODE : INSTANT"
modeBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 10
modeBtn.BorderSizePixel = 0
modeBtn.AutoButtonColor = false
modeBtn.Parent = main
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

local lockBtn = Instance.new("TextButton")
lockBtn.Size = UDim2.new(0.5, -15, 0, 26)
lockBtn.Position = UDim2.new(0.5, 5, 0, 76)
lockBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
lockBtn.Text = "LOCK : OFF"
lockBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
lockBtn.Font = Enum.Font.GothamBold
lockBtn.TextSize = 10
lockBtn.BorderSizePixel = 0
lockBtn.AutoButtonColor = false
lockBtn.Parent = main
Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(0, 6)

local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(0.5, -15, 0, 26)
autoBtn.Position = UDim2.new(0, 10, 0, 108)
autoBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
autoBtn.Text = "AUTO : OFF"
autoBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 10
autoBtn.BorderSizePixel = 0
autoBtn.AutoButtonColor = false
autoBtn.Parent = main
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 6)

local antiBtn = Instance.new("TextButton")
antiBtn.Size = UDim2.new(0.5, -15, 0, 26)
antiBtn.Position = UDim2.new(0.5, 5, 0, 108)
antiBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
antiBtn.Text = "ANTI K : OFF"
antiBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
antiBtn.Font = Enum.Font.GothamBold
antiBtn.TextSize = 10
antiBtn.BorderSizePixel = 0
antiBtn.AutoButtonColor = false
antiBtn.Parent = main
Instance.new("UICorner", antiBtn).CornerRadius = UDim.new(0, 6)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -20, 0, 20)
statusLbl.Position = UDim2.new(0, 10, 0, 140)
statusLbl.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
statusLbl.Text = "Cycle: - | Phase: - | Hits: 0"
statusLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 10
statusLbl.BorderSizePixel = 0
statusLbl.Parent = main
Instance.new("UICorner", statusLbl).CornerRadius = UDim.new(0, 4)

local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(1, -20, 0, 10)
progressBg.Position = UDim2.new(0, 10, 0, 166)
progressBg.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
progressBg.BorderSizePixel = 0
progressBg.Parent = main
Instance.new("UICorner", progressBg).CornerRadius = UDim.new(0, 4)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBg
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 4)

local progressLbl = Instance.new("TextLabel")
progressLbl.Size = UDim2.new(1, -20, 0, 18)
progressLbl.Position = UDim2.new(0, 10, 0, 178)
progressLbl.BackgroundTransparency = 1
progressLbl.Text = "REPAIR: 0%"
progressLbl.TextColor3 = Color3.fromRGB(255, 165, 0)
progressLbl.Font = Enum.Font.Code
progressLbl.TextSize = 10
progressLbl.TextXAlignment = Enum.TextXAlignment.Center
progressLbl.Parent = main

local logo = Instance.new("TextButton")
logo.Size = UDim2.new(0, 50, 0, 50)
logo.Position = UDim2.new(0, 20, 0, 120)
logo.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
logo.Text = "B"
logo.TextColor3 = Color3.fromRGB(255, 80, 80)
logo.Font = Enum.Font.GothamBold
logo.TextSize = 22
logo.AutoButtonColor = false
logo.Visible = false
logo.Parent = sg
Instance.new("UICorner", logo).CornerRadius = UDim.new(1, 0)
local lstr = Instance.new("UIStroke", logo)
lstr.Color = Color3.fromRGB(255, 80, 80)
lstr.Thickness = 2

local function bindDrag(target, handle)
    local dragging, dragInput, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or input ~= dragInput then return end
        if S.Locked then return end
        local delta = input.Position - dragStart
        target.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end)
end

bindDrag(main, dragArea)
bindDrag(logo, logo)

local ModeList = {"INSTANT", "SUCCESS", "NEUTRAL"}
local ModeIdx = 1

modeBtn.MouseButton1Click:Connect(function()
    ModeIdx = ModeIdx % #ModeList + 1
    SKILL.Mode = ModeList[ModeIdx]
    modeBtn.Text = "MODE : " .. SKILL.Mode
end)

lockBtn.MouseButton1Click:Connect(function()
    S.Locked = not S.Locked
    lockBtn.Text = S.Locked and "LOCK : ON" or "LOCK : OFF"
    lockBtn.BackgroundColor3 = S.Locked
        and Color3.fromRGB(180, 120, 40)
        or Color3.fromRGB(45, 45, 60)
end)

autoBtn.MouseButton1Click:Connect(function()
    if not S.AutoActive then
        if S.Active then
            S.Active = false
            stopCycleThread()
            stopWatchThread()
            releaseAll()
            S.Points = {}
            S.AllTouchedPoints = {}
            boostBtn.Text = "START"
            boostBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
        end
        startAutoGen()
        autoBtn.Text = "AUTO : ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 200)
    else
        stopAutoGen()
        autoBtn.Text = "AUTO : OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    end
end)

antiBtn.MouseButton1Click:Connect(function()
    if not S.AntiKillerActive then
        startAntiKiller()
        antiBtn.Text = "ANTI K : ON"
        antiBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 40)
    else
        stopAntiKiller()
        antiBtn.Text = "ANTI K : OFF"
        antiBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    end
end)

PROGRESS.OnClientEvent:Connect(function(progress, labelText)
    if labelText ~= "REPAIR" then return end
    if typeof(progress) ~= "number" then return end
    if S.GenModel then
        S.GenProgress[S.GenModel] = progress
    end
    if S.Active or S.AutoActive then
        S.Progress = progress
        local frac = math.clamp(progress / 100, 0, 1)
        progressFill.Size = UDim2.new(frac, 0, 1, 0)
        progressLbl.Text = string.format("REPAIR: %.1f%%", progress)
        if progress >= 100 and S.GenModel then
            S.GenDone[S.GenModel] = true
            if S.Active and not S.AutoActive then
                hardStop()
                boostBtn.Text = "START"
                boostBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
            end
        end
    end
end)

boostBtn.MouseButton1Click:Connect(function()
    if S.AutoActive then
        stopAutoGen()
        autoBtn.Text = "AUTO : OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
        boostBtn.Text = "START"
        boostBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
        return
    end

    if not S.Active then
        local idx, model = nil, nil
        for attempt = 1, SCAN_RETRY do
            idx, model = detectNearestGenerator()
            if model then break end
            boostBtn.Text = "SCAN " .. attempt .. "/" .. SCAN_RETRY
            task.wait(SCAN_RETRY_DELAY)
        end
        if not model then
            boostBtn.Text = "NO GEN"
            task.wait(1.5)
            boostBtn.Text = "START"
            return
        end
        S.GenIndex = idx
        S.GenModel = model
        S.Points = collectPoints(model)
        if #S.Points == 0 then
            boostBtn.Text = "NO POINTS"
            task.wait(1.5)
            boostBtn.Text = "START"
            S.Points = {}
            S.GenModel = nil
            return
        end
        S.Progress = S.GenProgress[model] or 0
        S.Active = true
        progressFill.Size = UDim2.new(math.clamp(S.Progress / 100, 0, 1), 0, 1, 0)
        progressLbl.Text = string.format("REPAIR: %.1f%%", S.Progress)
        startCycleThread()
        startWatchThread()
        boostBtn.Text = "STOP"
        boostBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    else
        hardStop()
        boostBtn.Text = "START"
        boostBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
    end
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    main.Visible = not minimized
    logo.Visible = minimized
end)

logo.MouseButton1Click:Connect(function()
    minimized = false
    main.Visible = true
    logo.Visible = false
end)

closeBtn.MouseButton1Click:Connect(function()
    hardStop()
    stopAntiKiller()
    clearAllEsp()
    pcall(function() sg:Destroy() end)
end)

LP.CharacterAdded:Connect(function()
    task.wait(1)
    refreshSkillRefs()
end)

task.spawn(function()
    while sg.Parent do
        pcall(updateEsp)

        if S.Active or S.AutoActive then
            local cycleTxt = "-"
            if #S.Points > 0 and S.CurrentPointIdx > 0 then
                cycleTxt = S.CurrentPointIdx .. "/" .. #S.Points
            end
            local phaseTxt = S.CurrentPhase
            if S.ForceSkip then phaseTxt = "SKIP" end
            statusLbl.Text = string.format("Cycle: %s | Phase: %s | Hits: %d",
                cycleTxt, phaseTxt, SKILL.Hits)
        else
            statusLbl.Text = "Cycle: - | Phase: - | Hits: 0"
        end

        task.wait(0.03)
    end
end)

print("[VANZ] Boost + Auto Gen + Anti Killer + ESP ready.")
