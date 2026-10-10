-- Advanced Float v2.0 / Float Tech + Prank Moveset
-- Client-side flight / hover controller for Roblox.
-- Use as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- Does not bypass game permissions, anti-cheat, or server-authoritative movement.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
if not player then
    warn("[Advanced Float] This script must run on the client.")
    return
end

-- Running the script again cleanly replaces the previous instance.
local environment = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        environment = result
    end
end
if type(environment.__ADVANCED_FLOAT_UNLOAD) == "function" then
    pcall(environment.__ADVANCED_FLOAT_UNLOAD)
end

local CONFIG = {
    minSpeed = 10,
    maxSpeed = 300,
    speedStep = 10,
    boostMultiplier = 2.25,
    slowMultiplier = 0.4,
    verticalMultiplier = 0.8,
    acceleration = 11,
    techAcceleration = 21,
    dashSpeed = 200,
    dashDuration = 0.36,
    dashCooldown = 2.8,
    riseCooldown = 3.5,
    spinCooldown = 2.0,
}

local theme = {
    background = Color3.fromRGB(12, 17, 29),
    surface = Color3.fromRGB(21, 29, 45),
    surfaceHover = Color3.fromRGB(29, 41, 60),
    border = Color3.fromRGB(48, 64, 84),
    white = Color3.fromRGB(237, 246, 255),
    muted = Color3.fromRGB(141, 160, 184),
    cyan = Color3.fromRGB(67, 222, 230),
    darkCyan = Color3.fromRGB(18, 84, 95),
    green = Color3.fromRGB(77, 233, 172),
    red = Color3.fromRGB(245, 119, 128),
    purple = Color3.fromRGB(169, 132, 255),
    gold = Color3.fromRGB(255, 196, 97),
}

local speed = 60
local flying = false
local unloaded = false
local minimized = false
local visible = true
local cruise = false
local heightLock = true
local noclip = false
local autoResume = true
local mobileUp = false
local mobileDown = false
local mobileBoost = false
local targetAltitude = nil
local lastUiRefresh = 0
local floatTech = false
local dashUntil = 0
local dashDirection = Vector3.zero
local spinUntil = 0
local spinAngle = 0
local riseUntil = 0
local nextActionAt = {}
local selectedTargetId = nil
local prankRemote = nil
local allowPranks = false
local techFeedback = "Local preview / Server not connected"

local character
local humanoid
local root
local attachment
local linearVelocity
local alignOrientation
local savedAutoRotate
local savedPlatformStand
local collisions = {}
local connections = {}
local controls
local currentGeneration = 0
local screenGui

local function track(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties) do
        object[property] = value
    end
    if parent then
        object.Parent = parent
    end
    return object
end

local function rounded(object, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, object)
end

local function border(object, color, thickness)
    create("UIStroke", {
        Color = color or theme.border,
        Thickness = thickness or 1,
        Transparency = 0.28,
    }, object)
end

local function label(text, size, color, properties, parent)
    local settings = {
        Text = text,
        BackgroundTransparency = 1,
        TextColor3 = color or theme.white,
        TextSize = size or 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
    }
    for property, value in pairs(properties or {}) do
        settings[property] = value
    end
    return create("TextLabel", settings, parent)
end

local function button(text, properties, parent)
    local settings = {
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = theme.white,
        BackgroundColor3 = theme.surface,
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }
    for property, value in pairs(properties or {}) do
        settings[property] = value
    end
    local item = create("TextButton", settings, parent)
    rounded(item, 10)
    return item
end

local function restoreCollisions()
    for part, original in pairs(collisions) do
        if part and part.Parent then
            part.CanCollide = original
        end
    end
    table.clear(collisions)
end

local function applyNoclip()
    if not character then return end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if collisions[descendant] == nil then
                collisions[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

local function detachPhysics()
    restoreCollisions()
    if linearVelocity then linearVelocity:Destroy() end
    if alignOrientation then alignOrientation:Destroy() end
    if attachment then attachment:Destroy() end
    linearVelocity = nil
    alignOrientation = nil
    attachment = nil
    targetAltitude = nil
    dashUntil = 0
    spinUntil = 0

    if humanoid and humanoid.Parent and humanoid.Health > 0 then
        if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
        if savedPlatformStand ~= nil then humanoid.PlatformStand = savedPlatformStand end
        if not humanoid.PlatformStand then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    savedAutoRotate = nil
    savedPlatformStand = nil
end

local function attachPhysics()
    if unloaded or not flying then return false end
    if not character or not root or not humanoid or humanoid.Health <= 0 then
        return false
    end
    if linearVelocity and linearVelocity.Parent == root then
        return true
    end

    detachPhysics()

    attachment = create("Attachment", { Name = "AdvancedFloatAttachment" }, root)
    linearVelocity = create("LinearVelocity", {
        Name = "AdvancedFloatLinearVelocity",
        Attachment0 = attachment,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
        ForceLimitsEnabled = false,
        VectorVelocity = Vector3.zero,
    }, root)
    alignOrientation = create("AlignOrientation", {
        Name = "AdvancedFloatAlignOrientation",
        Attachment0 = attachment,
        Mode = Enum.OrientationAlignmentMode.OneAttachment,
        Responsiveness = 22,
        MaxTorque = 1000000000,
        RigidityEnabled = false,
    }, root)

    savedAutoRotate = humanoid.AutoRotate
    savedPlatformStand = humanoid.PlatformStand
    humanoid.AutoRotate = false
    humanoid.PlatformStand = true
    targetAltitude = root.Position.Y
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

local refreshUI = function() end
local function setFlying(enabled)
    if unloaded then return end
    if enabled then
        if not (root and humanoid and humanoid.Health > 0) then
            flying = false
        else
            flying = true
            if not attachPhysics() then flying = false end
        end
    else
        flying = false
        cruise = false
        dashUntil = 0
        spinUntil = 0
        detachPhysics()
    end
    refreshUI()
end

local function setSpeed(value)
    speed = math.clamp(math.floor(value / CONFIG.speedStep + 0.5) * CONFIG.speedStep,
        CONFIG.minSpeed, CONFIG.maxSpeed)
    refreshUI()
end

local function horizontalAxes(camera)
    local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
    if forward.Magnitude < 0.02 then
        local fallback = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
        forward = Vector3.new(fallback.X, 0, fallback.Z)
    end
    forward = forward.Magnitude > 0 and forward.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(forward.Z * -1, 0, forward.X)
    return forward, right
end

local function getMovement(camera, forward, right)
    if UserInputService:GetFocusedTextBox() then return Vector3.zero end

    if controls then
        local ok, move = pcall(function() return controls:GetMoveVector() end)
        if ok and typeof(move) == "Vector3" and move.Magnitude > 0.05 then
            local direction = right * move.X - forward * move.Z
            return direction.Magnitude > 1 and direction.Unit or direction
        end
    end

    local x, z = 0, 0
    if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x -= 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then z += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then z -= 1 end
    local direction = right * x + forward * z
    if direction.Magnitude > 0 then return direction.Unit end

    if humanoid then
        local move = humanoid.MoveDirection
        return Vector3.new(move.X, 0, move.Z)
    end
    return Vector3.zero
end

-- Float Tech: client-side movement abilities and visual previews.
local updateTechUI = function() end
local function isActionReady(name, cooldown)
    local now = os.clock()
    if now < (nextActionAt[name] or 0) then return false end
    nextActionAt[name] = now + cooldown
    return true
end

local function ensureFlight()
    if not flying then setFlying(true) end
    return flying and root and root.Parent and humanoid and humanoid.Health > 0
end

local function airDash()
    if not isActionReady("dash", CONFIG.dashCooldown) then return end
    if not ensureFlight() then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local forward = horizontalAxes(camera)
    dashDirection = forward
    dashUntil = os.clock() + CONFIG.dashDuration
    if targetAltitude then targetAltitude = root.Position.Y end
end

local function skyBurst()
    if not isActionReady("rise", CONFIG.riseCooldown) then return end
    if not ensureFlight() then return end
    targetAltitude = root.Position.Y + 28
    riseUntil = os.clock() + 0.65
end

local function spinTech()
    if not isActionReady("spin", CONFIG.spinCooldown) then return end
    if not ensureFlight() then return end
    spinUntil = os.clock() + 0.8
    spinAngle = 0
end

local function airBrake()
    cruise = false
    dashUntil = 0
    riseUntil = 0
    if root then targetAltitude = root.Position.Y end
    if linearVelocity then linearVelocity.VectorVelocity = Vector3.zero end
    refreshUI()
end

local function showBurst(position, action)
    if typeof(position) ~= "Vector3" then return end
    local color = (action == "FLING" and theme.red) or
        (action == "SHOCKWAVE" and theme.cyan) or
        (action == "CONFETTI" and theme.gold) or theme.purple
    for index = 1, 3 do
        local sphere = create("Part", {
            Name = "FloatPrankVFX", Shape = Enum.PartType.Ball,
            Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
            Material = Enum.Material.Neon, Color = color,
            Transparency = 0.5 + (index * 0.08),
            Size = Vector3.new(1, 1, 1),
            CFrame = CFrame.new(position),
        }, workspace)
        local size = (action == "SHOCKWAVE" and 18 or 9) * (0.65 + index * 0.30)
        TweenService:Create(sphere, TweenInfo.new(0.42 + index * 0.10, Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out), {
            Size = Vector3.new(size, size, size),
            Transparency = 1,
        }):Play()
        Debris:AddItem(sphere, 0.95)
    end

    if action == "CONFETTI" then
        local colors = {theme.cyan, theme.purple, theme.gold, theme.green, theme.red}
        for index = 1, 24 do
            local cube = create("Part", {
                Name = "FloatConfetti", Shape = Enum.PartType.Block,
                Size = Vector3.new(0.22, 0.36, 0.14), Material = Enum.Material.Neon,
                Color = colors[((index - 1) % #colors) + 1],
                Anchored = false, CanCollide = false, CanTouch = false, CanQuery = false,
                CFrame = CFrame.new(position + Vector3.new(math.random(-3, 3), 2, math.random(-3, 3))),
            }, workspace)
            cube.AssemblyLinearVelocity = Vector3.new(math.random(-22, 22), math.random(18, 38), math.random(-22, 22))
            cube.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 13
            Debris:AddItem(cube, 2.2)
        end
    elseif action == "ORBIT" then
        local orbs = {}
        for index = 1, 4 do
            local orb = create("Part", {
                Name = "FloatOrbit", Shape = Enum.PartType.Ball,
                Size = Vector3.new(0.9, 0.9, 0.9),
                Material = Enum.Material.Neon, Color = index % 2 == 0 and theme.purple or theme.cyan,
                Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
            }, workspace)
            table.insert(orbs, orb)
        end
        local start = os.clock()
        local follow
        local connection
        connection = RunService.Heartbeat:Connect(function()
            if unloaded or os.clock() - start > 2.3 then
                connection:Disconnect()
                for _, orb in ipairs(orbs) do orb:Destroy() end
                return
            end
            local elapsed = os.clock() - start
            local center = position
            if follow and follow.Parent then center = follow.Position end
            for index, orb in ipairs(orbs) do
                local angle = elapsed * 6 + index * math.pi * 0.5
                orb.Position = center + Vector3.new(math.cos(angle) * 4, 2 + math.sin(angle * 2) * 0.8, math.sin(angle) * 4)
            end
        end)
    end
end

local function showBillboard(position, words)
    local anchor = create("Part", {
        Name = "FloatPrankCaption", Anchored = true, CanCollide = false,
        CanQuery = false, CanTouch = false, Transparency = 1,
        Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(position + Vector3.new(0, 3.5, 0)),
    }, workspace)
    local board = create("BillboardGui", {
        Size = UDim2.fromOffset(200, 54), AlwaysOnTop = true,
        StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0),
        Adornee = anchor,
    }, anchor)
    local text = label(words, 25, theme.gold, {
        Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack,
        TextScaled = true, TextStrokeColor3 = theme.background,
        TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
    }, board)
    TweenService:Create(text, TweenInfo.new(0.9), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
    Debris:AddItem(anchor, 1.0)
end

local function findTarget()
    if not selectedTargetId then return nil end
    local target = Players:GetPlayerByUserId(selectedTargetId)
    if target == player then return nil end
    return target
end

local function previewPrank(action, target)
    local targetRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        techFeedback = "Pick a nearby player first"
    else
        showBurst(targetRoot.Position, action)
        local texts = {
            FLING = "YEET!", SHOCKWAVE = "BOOM!", CONFETTI = "SURPRISE!",
            ORBIT = "MAGIC!", JUMPSCARE = "BOO!",
        }
        showBillboard(targetRoot.Position, texts[action] or "LOL!")
        techFeedback = "LOCAL PREVIEW ONLY - others cannot see this"
    end
    updateTechUI()
end

local function triggerPrank(action)
    if not isActionReady(action, 1.0) then return end
    local target = findTarget()
    if not target then
        techFeedback = "Select a player in the TARGET button"
        updateTechUI()
        return
    end
    if prankRemote and prankRemote.Parent then
        prankRemote:FireServer("Move", action, target.UserId)
        techFeedback = "Request sent (server validates consent/range)"
        updateTechUI()
    else
        previewPrank(action, target)
    end
end

-- UI -------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
screenGui = create("ScreenGui", {
    Name = "AdvancedFloatUI",
    ResetOnSpawn = false,
    DisplayOrder = 200,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, playerGui)

local isMobile = UserInputService.TouchEnabled
local panelWidth = isMobile and 304 or 326
local panelHeight = 495
local panel = create("Frame", {
    Name = "MainPanel",
    Size = UDim2.fromOffset(panelWidth, panelHeight),
    Position = isMobile and UDim2.fromOffset(12, 76) or UDim2.fromOffset(32, 140),
    BackgroundColor3 = theme.background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
}, screenGui)
rounded(panel, 16)
border(panel, theme.border, 1.2)

local header = create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 63),
    BackgroundColor3 = theme.surface,
    BorderSizePixel = 0,
    Active = true,
}, panel)
rounded(header, 16)
create("Frame", {
    Position = UDim2.new(0, 0, 1, -9),
    Size = UDim2.new(1, 0, 0, 9),
    BorderSizePixel = 0,
    BackgroundColor3 = theme.surface,
}, header)
local emblem = create("Frame", {
    Size = UDim2.fromOffset(35, 35),
    Position = UDim2.fromOffset(13, 14),
    BackgroundColor3 = theme.darkCyan,
    BorderSizePixel = 0,
}, header)
rounded(emblem, 10)
label("AF", 14, theme.cyan, {
    Size = UDim2.fromScale(1, 1),
    TextXAlignment = Enum.TextXAlignment.Center,
    Font = Enum.Font.GothamBlack,
}, emblem)
label("ADVANCED FLOAT", 15, theme.white, {
    Size = UDim2.new(1, -140, 0, 24),
    Position = UDim2.fromOffset(58, 10),
    Font = Enum.Font.GothamBold,
}, header)
label("V2.0  /  FLIGHT + TECH + PRANK", 10, theme.muted, {
    Size = UDim2.new(1, -145, 0, 18),
    Position = UDim2.fromOffset(58, 33),
}, header)
local minButton = button("-", {
    Size = UDim2.fromOffset(29, 29),
    Position = UDim2.new(1, -74, 0, 17),
    BackgroundColor3 = theme.surfaceHover,
    TextSize = 20,
}, header)
local closeButton = button("X", {
    Size = UDim2.fromOffset(29, 29),
    Position = UDim2.new(1, -39, 0, 17),
    BackgroundColor3 = Color3.fromRGB(68, 35, 49),
    TextColor3 = theme.red,
}, header)

local tabBar = create("Frame", {
    Name = "TabBar", Position = UDim2.fromOffset(0, 63),
    Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = theme.background,
    BorderSizePixel = 0,
}, panel)
local flightTab = button("FLIGHT", {
    Position = UDim2.fromOffset(12, 5), Size = UDim2.new(0.5, -17, 0, 30),
    BackgroundColor3 = theme.darkCyan, TextColor3 = theme.cyan,
}, tabBar)
local techTab = button("TECH + PRANK", {
    Position = UDim2.new(0.5, 5, 0, 5), Size = UDim2.new(0.5, -17, 0, 30),
    BackgroundColor3 = theme.surface, TextColor3 = theme.muted,
}, tabBar)
local contents = create("Frame", {
    Name = "Contents",
    Position = UDim2.fromOffset(0, 103),
    Size = UDim2.new(1, 0, 1, -103),
    BackgroundTransparency = 1,
}, panel)
local innerWidth = panelWidth - 28
local statusCard = create("Frame", {
    Position = UDim2.fromOffset(14, 12),
    Size = UDim2.fromOffset(innerWidth, 72),
    BackgroundColor3 = theme.surface,
    BorderSizePixel = 0,
}, contents)
rounded(statusCard, 12)
border(statusCard)
local statusDot = create("Frame", {
    Position = UDim2.fromOffset(14, 17),
    Size = UDim2.fromOffset(9, 9),
    BackgroundColor3 = theme.muted,
    BorderSizePixel = 0,
}, statusCard)
rounded(statusDot, 10)
local statusText = label("STANDBY", 13, theme.white, {
    Position = UDim2.fromOffset(31, 10),
    Size = UDim2.fromOffset(166, 24),
    Font = Enum.Font.GothamBold,
}, statusCard)
local subtitleText = label("Ready to take off", 11, theme.muted, {
    Position = UDim2.fromOffset(14, 38),
    Size = UDim2.fromOffset(innerWidth - 25, 20),
}, statusCard)
local altitudeText = label("Y: --", 11, theme.cyan, {
    Position = UDim2.new(1, -78, 0, 14),
    Size = UDim2.fromOffset(64, 20),
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Enum.Font.GothamBold,
}, statusCard)

local speedCard = create("Frame", {
    Position = UDim2.fromOffset(14, 96),
    Size = UDim2.fromOffset(innerWidth, 87),
    BackgroundColor3 = theme.surface,
    BorderSizePixel = 0,
}, contents)
rounded(speedCard, 12)
border(speedCard)
label("FLIGHT SPEED", 11, theme.muted, {
    Position = UDim2.fromOffset(14, 7),
    Size = UDim2.fromOffset(139, 21),
    Font = Enum.Font.GothamBold,
}, speedCard)
local speedValue = label("60", 23, theme.white, {
    Position = UDim2.new(1, -113, 0, 0),
    Size = UDim2.fromOffset(48, 35),
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Enum.Font.GothamBold,
}, speedCard)
label("ST/S", 10, theme.muted, {
    Position = UDim2.new(1, -63, 0, 10),
    Size = UDim2.fromOffset(36, 20),
}, speedCard)
local minusButton = button("-", {
    Position = UDim2.fromOffset(13, 36),
    Size = UDim2.fromOffset(33, 35),
    BackgroundColor3 = theme.surfaceHover,
    TextSize = 23,
}, speedCard)
local plusButton = button("+", {
    Position = UDim2.new(1, -46, 0, 36),
    Size = UDim2.fromOffset(33, 35),
    BackgroundColor3 = theme.surfaceHover,
    TextSize = 22,
}, speedCard)
local barWidth = innerWidth - 112
local speedTrack = create("Frame", {
    Position = UDim2.fromOffset(56, 49),
    Size = UDim2.fromOffset(barWidth, 9),
    BackgroundColor3 = Color3.fromRGB(43, 59, 78),
    BorderSizePixel = 0,
}, speedCard)
rounded(speedTrack, 9)
local speedFill = create("Frame", {
    Size = UDim2.fromScale(0.15, 1),
    BackgroundColor3 = theme.cyan,
    BorderSizePixel = 0,
}, speedTrack)
rounded(speedFill, 9)
local sliderHit = create("TextButton", {
    Size = UDim2.new(1, 0, 0, 35),
    Position = UDim2.fromOffset(0, -13),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
}, speedTrack)

local flightButton = button("START FLOAT", {
    Position = UDim2.fromOffset(14, 197),
    Size = UDim2.fromOffset(innerWidth, 48),
    TextSize = 15,
    BackgroundColor3 = theme.cyan,
    TextColor3 = theme.background,
}, contents)
rounded(flightButton, 12)

label("FLIGHT OPTIONS", 10, theme.muted, {
    Position = UDim2.fromOffset(15, 259),
    Size = UDim2.fromOffset(innerWidth, 21),
    Font = Enum.Font.GothamBold,
}, contents)

local optButtons = {}
local optStates = {}
local optW = math.floor((innerWidth - 10) / 2)
local function addOption(title, col, row, name, onClick)
    local option = button("", {
        Size = UDim2.fromOffset(optW, 42),
        Position = UDim2.fromOffset(14 + (col - 1) * (optW + 10), 283 + (row - 1) * 50),
        BackgroundColor3 = theme.surface,
        AutoButtonColor = false,
    }, contents)
    border(option)
    label(title, 11, theme.white, {
        Position = UDim2.fromOffset(11, 0),
        Size = UDim2.new(1, -48, 1, 0),
        Font = Enum.Font.GothamBold,
    }, option)
    local state = label("OFF", 10, theme.muted, {
        Position = UDim2.new(1, -43, 0, 0),
        Size = UDim2.fromOffset(33, 42),
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, option)
    optButtons[name] = option
    optStates[name] = state
    track(option.Activated, function()
        onClick()
        refreshUI()
    end)
end

addOption("CRUISE", 1, 1, "cruise", function() cruise = not cruise end)
addOption("HEIGHT LOCK", 2, 1, "height", function()
    heightLock = not heightLock
    if root then targetAltitude = root.Position.Y end
end)
addOption("NOCLIP", 1, 2, "noclip", function()
    noclip = not noclip
    if not noclip then restoreCollisions() end
end)
addOption("AUTO RESUME", 2, 2, "resume", function() autoResume = not autoResume end)

label("F  TOGGLE     SHIFT  BOOST     C  CRUISE     X  STOP", 9, theme.muted, {
    Position = UDim2.fromOffset(14, 366),
    Size = UDim2.fromOffset(innerWidth, 17),
    TextXAlignment = Enum.TextXAlignment.Center,
}, contents)

local techPage = create("Frame", {
    Name = "TechPage", Visible = false,
    Position = UDim2.fromOffset(0, 103), Size = UDim2.new(1, 0, 1, -103),
    BackgroundTransparency = 1,
}, panel)
local function tbtn(text, x, y, w, h, color)
    local b = button(text, {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = color or theme.surface, TextSize = 12,
    }, techPage)
    border(b)
    return b
end
local half = math.floor((innerWidth - 9) / 2)
label("AIR TECH  /  MOVEMENT", 10, theme.purple, {
    Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(innerWidth, 18),
    Font = Enum.Font.GothamBold,
}, techPage)
local techToggle = tbtn("FLOAT TECH: OFF", 14, 30, innerWidth, 40, theme.surface)
local dashButton = tbtn("AIR DASH  [R]", 14, 79, half, 39)
local riseButton = tbtn("SKY BURST  [T]", 23 + half, 79, half, 39)
local spinButton = tbtn("SPIN TECH  [Y]", 14, 126, half, 39)
local brakeButton = tbtn("AIR BRAKE  [B]", 23 + half, 126, half, 39)
label("PRANK MOVESET  /  TARGETED", 10, theme.gold, {
    Position = UDim2.fromOffset(14, 178), Size = UDim2.fromOffset(innerWidth, 17),
    Font = Enum.Font.GothamBold,
}, techPage)
local targetButton = tbtn("TARGET: NONE    >", 14, 201, innerWidth, 34)
local consentButton = tbtn("ALLOW PRANKS ON ME: OFF", 14, 241, innerWidth, 32)
local flingButton = tbtn("FLING", 14, 280, half, 35, Color3.fromRGB(76, 36, 52))
local waveButton = tbtn("SHOCKWAVE", 23 + half, 280, half, 35)
local triW = math.floor((innerWidth - 16) / 3)
local confettiButton = tbtn("CONFETTI", 14, 321, triW, 35)
local orbitButton = tbtn("ORBIT", 22 + triW, 321, triW, 35)
local scareButton = tbtn("BOO!", 30 + triW * 2, 321, innerWidth - 16 - 2 * triW, 35)
local feedbackText = label("Local preview / Server not connected", 10, theme.muted, {
    Position = UDim2.fromOffset(14, 362), Size = UDim2.fromOffset(innerWidth, 22),
    TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
}, techPage)

local function listTargets()
    local result = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then table.insert(result, other) end
    end
    table.sort(result, function(a, b) return a.Name:lower() < b.Name:lower() end)
    return result
end

local function cycleTarget()
    local targets = listTargets()
    if #targets == 0 then
        selectedTargetId = nil
    else
        local index = 0
        for i, t in ipairs(targets) do
            if t.UserId == selectedTargetId then index = i; break end
        end
        selectedTargetId = targets[(index % #targets) + 1].UserId
    end
    updateTechUI()
end

updateTechUI = function()
    if unloaded then return end
    techToggle.Text = floatTech and "FLOAT TECH: ON  /  AGILE" or "FLOAT TECH: OFF"
    techToggle.BackgroundColor3 = floatTech and theme.darkCyan or theme.surface
    local target = findTarget()
    targetButton.Text = target and ("TARGET: @" .. target.Name .. "    >") or "TARGET: NONE    >"
    consentButton.Text = "ALLOW PRANKS ON ME: " .. (allowPranks and "ON" or "OFF")
    consentButton.BackgroundColor3 = allowPranks and theme.darkCyan or theme.surface
    feedbackText.Text = techFeedback
    feedbackText.TextColor3 = prankRemote and theme.green or theme.muted
end

local function switchPage(toTech)
    contents.Visible = not toTech
    techPage.Visible = toTech
    flightTab.BackgroundColor3 = toTech and theme.surface or theme.darkCyan
    flightTab.TextColor3 = toTech and theme.muted or theme.cyan
    techTab.BackgroundColor3 = toTech and theme.darkCyan or theme.surface
    techTab.TextColor3 = toTech and theme.cyan or theme.muted
    updateTechUI()
end
track(flightTab.Activated, function() switchPage(false) end)
track(techTab.Activated, function() switchPage(true) end)
track(techToggle.Activated, function()
    floatTech = not floatTech
    updateTechUI()
end)
track(dashButton.Activated, airDash)
track(riseButton.Activated, skyBurst)
track(spinButton.Activated, spinTech)
track(brakeButton.Activated, airBrake)
track(targetButton.Activated, cycleTarget)
track(consentButton.Activated, function()
    if not prankRemote then
        techFeedback = "Server companion required for multiplayer"
    else
        allowPranks = not allowPranks
        prankRemote:FireServer("OptIn", allowPranks)
        techFeedback = allowPranks and "You opted in to server pranks" or "You opted out of server pranks"
    end
    updateTechUI()
end)
track(flingButton.Activated, function() triggerPrank("FLING") end)
track(waveButton.Activated, function() triggerPrank("SHOCKWAVE") end)
track(confettiButton.Activated, function() triggerPrank("CONFETTI") end)
track(orbitButton.Activated, function() triggerPrank("ORBIT") end)
track(scareButton.Activated, function() triggerPrank("JUMPSCARE") end)

local function bindPrankRemote(remote)
    if not remote:IsA("RemoteEvent") or remote.Name ~= "AdvancedFloatPrankRemote" then return end
    prankRemote = remote
    techFeedback = "SERVER CONNECTED / target must opt in"
    updateTechUI()
    track(remote.OnClientEvent, function(command, arg1, arg2)
        if unloaded then return end
        if command == "Info" and type(arg1) == "string" then
            techFeedback = arg1:sub(1, 90)
            updateTechUI()
        elseif command == "FX" and typeof(arg1) == "Vector3" and type(arg2) == "string" then
            showBurst(arg1, arg2)
            local names = {FLING = "YEET!", SHOCKWAVE = "BOOM!", CONFETTI = "SURPRISE!", ORBIT = "MAGIC!", JUMPSCARE = "BOO!"}
            showBillboard(arg1, names[arg2] or "LOL!")
        elseif command == "Impulse" and typeof(arg1) == "Vector3" then
            if flying then setFlying(false) end
            if root and root.Parent and root:IsA("BasePart") then
                root:ApplyImpulse(arg1 * root.AssemblyMass)
            end
        elseif command == "Scare" then
            local flash = create("TextLabel", {
                Name = "FloatPrankScare", AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
                Text = "BOO!", Font = Enum.Font.GothamBlack, TextScaled = true,
                BackgroundColor3 = theme.red, BackgroundTransparency = 0.2,
                TextColor3 = theme.background, ZIndex = 80,
            }, screenGui)
            TweenService:Create(flash, TweenInfo.new(0.65), {BackgroundTransparency = 1, TextTransparency = 1}):Play()
            Debris:AddItem(flash, 0.75)
        end
    end)
end
local initialRemote = ReplicatedStorage:FindFirstChild("AdvancedFloatPrankRemote")
if initialRemote then bindPrankRemote(initialRemote) end
track(ReplicatedStorage.ChildAdded, bindPrankRemote)
track(ReplicatedStorage.ChildRemoved, function(child)
    if child == prankRemote then
        prankRemote = nil
        allowPranks = false
        techFeedback = "Server disconnected / local preview only"
        updateTechUI()
    end
end)
track(Players.PlayerRemoving, function(other)
    if selectedTargetId == other.UserId then
        selectedTargetId = nil
        updateTechUI()
    end
end)

local bubble = button("AF", {
    Visible = false,
    Size = UDim2.fromOffset(52, 52),
    Position = isMobile and UDim2.fromOffset(12, 80) or UDim2.fromOffset(32, 140),
    BackgroundColor3 = theme.darkCyan,
    TextColor3 = theme.cyan,
    TextSize = 17,
}, screenGui)
rounded(bubble, 16)
border(bubble, theme.cyan, 1.5)

local touchPanel = create("Frame", {
    Name = "MobileControls",
    Visible = isMobile,
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -14, 1, -90),
    Size = UDim2.fromOffset(144, 190),
    BackgroundTransparency = 1,
}, screenGui)
local touchFly = button("FLY", {
    Position = UDim2.fromOffset(76, 0),
    Size = UDim2.fromOffset(64, 48),
    TextColor3 = theme.background,
    BackgroundColor3 = theme.cyan,
}, touchPanel)
local touchUp = button("UP", {
    Position = UDim2.fromOffset(76, 56),
    Size = UDim2.fromOffset(64, 48),
    BackgroundColor3 = theme.surface,
}, touchPanel)
local touchDown = button("DOWN", {
    Position = UDim2.fromOffset(76, 112),
    Size = UDim2.fromOffset(64, 48),
    BackgroundColor3 = theme.surface,
}, touchPanel)
local touchBoost = button("BOOST", {
    Position = UDim2.fromOffset(0, 112),
    Size = UDim2.fromOffset(68, 48),
    BackgroundColor3 = theme.surface,
    TextColor3 = theme.cyan,
}, touchPanel)

refreshUI = function()
    if unloaded then return end
    speedValue.Text = tostring(speed)
    speedFill.Size = UDim2.fromScale((speed - CONFIG.minSpeed) / (CONFIG.maxSpeed - CONFIG.minSpeed), 1)
    local ready = root and humanoid and humanoid.Health > 0
    statusText.Text = flying and (ready and "FLOAT ACTIVE" or "RECONNECTING") or "STANDBY"
    statusDot.BackgroundColor3 = flying and theme.green or theme.muted
    subtitleText.Text = flying and (ready and "Camera-relative movement enabled" or "Waiting for respawn...") or "Press F or START FLOAT"
    flightButton.Text = flying and "STOP FLOAT" or "START FLOAT"
    flightButton.BackgroundColor3 = flying and Color3.fromRGB(87, 40, 53) or theme.cyan
    flightButton.TextColor3 = flying and theme.red or theme.background
    touchFly.Text = flying and "STOP" or "FLY"
    touchFly.BackgroundColor3 = flying and Color3.fromRGB(87, 40, 53) or theme.cyan
    touchFly.TextColor3 = flying and theme.red or theme.background

    local options = { cruise = cruise, height = heightLock, noclip = noclip, resume = autoResume }
    updateTechUI()
    for key, isOn in pairs(options) do
        optButtons[key].BackgroundColor3 = isOn and Color3.fromRGB(22, 56, 67) or theme.surface
        optStates[key].Text = isOn and "ON" or "OFF"
        optStates[key].TextColor3 = isOn and theme.cyan or theme.muted
    end
end

track(flightButton.Activated, function() setFlying(not flying) end)
track(touchFly.Activated, function() setFlying(not flying) end)
track(minusButton.Activated, function() setSpeed(speed - CONFIG.speedStep) end)
track(plusButton.Activated, function() setSpeed(speed + CONFIG.speedStep) end)

local sliding = false
local function slideTo(screenX)
    local x = (screenX - speedTrack.AbsolutePosition.X) / math.max(speedTrack.AbsoluteSize.X, 1)
    setSpeed(CONFIG.minSpeed + math.clamp(x, 0, 1) * (CONFIG.maxSpeed - CONFIG.minSpeed))
end
track(sliderHit.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliding = input
        slideTo(input.Position.X)
    end
end)
track(UserInputService.InputChanged, function(input)
    if sliding and (input == sliding or (sliding.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        slideTo(input.Position.X)
    end
end)
track(UserInputService.InputEnded, function(input)
    if input == sliding then sliding = false end
end)

local function showPanel(show)
    visible = show
    panel.Visible = show
    bubble.Visible = not show
end
track(bubble.Activated, function() showPanel(true) end)
track(minButton.Activated, function()
    minimized = not minimized
    contents.Visible = not minimized
    minButton.Text = minimized and "+" or "-"
    TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(panelWidth, minimized and 63 or panelHeight),
    }):Play()
end)

local dragging = false
local dragStart
local origin
track(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = input
        dragStart = input.Position
        origin = panel.AbsolutePosition
    end
end)
track(UserInputService.InputChanged, function(input)
    if dragging and (input == dragging or (dragging.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local offset = input.Position - dragStart
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local newX = math.clamp(origin.X + offset.X, 0, math.max(0, viewport.X - panelWidth))
        local newY = math.clamp(origin.Y + offset.Y, 0, math.max(0, viewport.Y - 65))
        panel.Position = UDim2.fromOffset(newX, newY)
    end
end)
track(UserInputService.InputEnded, function(input)
    if input == dragging then dragging = false end
end)

local heldTouch = {}
local function bindTouchHold(uiButton, key)
    track(uiButton.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            heldTouch[key] = input
            if key == "up" then mobileUp = true end
            if key == "down" then mobileDown = true end
            if key == "boost" then mobileBoost = true end
        end
    end)
end
bindTouchHold(touchUp, "up")
bindTouchHold(touchDown, "down")
bindTouchHold(touchBoost, "boost")
track(UserInputService.InputEnded, function(input)
    for key, held in pairs(heldTouch) do
        if held == input then
            heldTouch[key] = nil
            if key == "up" then mobileUp = false end
            if key == "down" then mobileDown = false end
            if key == "boost" then mobileBoost = false end
        end
    end
end)

local function unload()
    if unloaded then return end
    flying = false
    if allowPranks and prankRemote and prankRemote.Parent then
        pcall(function() prankRemote:FireServer("OptIn", false) end)
    end
    detachPhysics()
    unloaded = true
    currentGeneration += 1
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    if screenGui then screenGui:Destroy() end
    if environment.__ADVANCED_FLOAT_UNLOAD == unload then
        environment.__ADVANCED_FLOAT_UNLOAD = nil
    end
end
environment.__ADVANCED_FLOAT_UNLOAD = unload
track(closeButton.Activated, unload)

track(UserInputService.InputBegan, function(input, processed)
    if unloaded or processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F then
        setFlying(not flying)
    elseif input.KeyCode == Enum.KeyCode.C then
        cruise = not cruise
        refreshUI()
    elseif input.KeyCode == Enum.KeyCode.X then
        setFlying(false)
    elseif input.KeyCode == Enum.KeyCode.R then
        airDash()
    elseif input.KeyCode == Enum.KeyCode.T then
        skyBurst()
    elseif input.KeyCode == Enum.KeyCode.Y then
        spinTech()
    elseif input.KeyCode == Enum.KeyCode.B then
        airBrake()
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        showPanel(not visible)
    elseif input.KeyCode == Enum.KeyCode.Equals or input.KeyCode == Enum.KeyCode.KeypadPlus then
        setSpeed(speed + CONFIG.speedStep)
    elseif input.KeyCode == Enum.KeyCode.Minus or input.KeyCode == Enum.KeyCode.KeypadMinus then
        setSpeed(speed - CONFIG.speedStep)
    end
end)

local function bindCharacter(newCharacter)
    currentGeneration += 1
    local generation = currentGeneration
    detachPhysics()
    character = newCharacter
    root = nil
    humanoid = nil
    refreshUI()
    task.spawn(function()
        local foundRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
        local foundHumanoid = newCharacter:WaitForChild("Humanoid", 10)
        if unloaded or currentGeneration ~= generation then return end
        if not foundRoot or not foundHumanoid then return end
        root = foundRoot
        humanoid = foundHumanoid
        if flying and autoResume then
            attachPhysics()
        elseif flying then
            setFlying(false)
        end
        refreshUI()
    end)
end
track(player.CharacterAdded, bindCharacter)
track(player.CharacterRemoving, function()
    currentGeneration += 1
    detachPhysics()
    root = nil
    humanoid = nil
    character = nil
    if not autoResume then flying = false end
    refreshUI()
end)

-- Default Roblox PlayerModule controls support thumbsticks and mobile movement.
task.spawn(function()
    local playerScripts = player:WaitForChild("PlayerScripts", 10)
    if not playerScripts or unloaded then return end
    local module = playerScripts:FindFirstChild("PlayerModule") or playerScripts:WaitForChild("PlayerModule", 5)
    if not module or unloaded then return end
    local ok, result = pcall(function()
        return require(module):GetControls()
    end)
    if ok and result and not unloaded then controls = result end
end)

local noclipClock = 0
track(RunService.Heartbeat, function(dt)
    if unloaded then return end
    if not flying or not root or not humanoid or humanoid.Health <= 0 then return end
    if not linearVelocity or not alignOrientation or not linearVelocity.Parent then
        if not attachPhysics() then return end
    end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local forward, right = horizontalAxes(camera)
    local horizontal = getMovement(camera, forward, right)
    if cruise and horizontal.Magnitude <= 0.05 then horizontal = forward end

    local focused = UserInputService:GetFocusedTextBox() ~= nil
    local up = mobileUp or (not focused and (UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E)))
    local down = mobileDown or (not focused and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q)))
    local vertical = (up and 1 or 0) - (down and 1 or 0)
    local boosting = mobileBoost or (not focused and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift))
    local slowing = not focused and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
    local multiplier = boosting and CONFIG.boostMultiplier or (slowing and CONFIG.slowMultiplier or 1)
    local actualSpeed = speed * multiplier

    if not targetAltitude then targetAltitude = root.Position.Y end
    local verticalSpeed = actualSpeed * CONFIG.verticalMultiplier
    local yVelocity
    if heightLock then
        targetAltitude += vertical * verticalSpeed * math.min(dt, 0.1)
        yVelocity = math.clamp((targetAltitude - root.Position.Y) * 7.5, -verticalSpeed, verticalSpeed)
    else
        targetAltitude = root.Position.Y
        yVelocity = vertical * verticalSpeed
    end
    local now = os.clock()
    local goal = horizontal * actualSpeed + Vector3.new(0, yVelocity, 0)
    local accel = floatTech and CONFIG.techAcceleration or CONFIG.acceleration
    if now < dashUntil then
        goal = dashDirection * CONFIG.dashSpeed + Vector3.new(0, yVelocity * 0.25, 0)
        accel = 45
    end
    if now < riseUntil then
        goal = Vector3.new(goal.X, math.max(goal.Y, 95), goal.Z)
    end
    local blend = 1 - math.exp(-accel * math.min(dt, 0.1))
    linearVelocity.VectorVelocity = linearVelocity.VectorVelocity:Lerp(goal, blend)
    if now < spinUntil then
        spinAngle += dt * math.pi * 8
        alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, forward) * CFrame.Angles(0, spinAngle, 0)
    else
        alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, forward)
    end

    noclipClock += dt
    if noclip and noclipClock >= 0.09 then
        noclipClock = 0
        applyNoclip()
    end
    if os.clock() - lastUiRefresh >= 0.18 then
        lastUiRefresh = os.clock()
        altitudeText.Text = "Y: " .. tostring(math.floor(root.Position.Y + 0.5))
        subtitleText.Text = string.format("Moving %.0f st/s   |   %s", root.AssemblyLinearVelocity.Magnitude,
            boosting and "BOOST" or (cruise and "CRUISE" or "CONTROL"))
    end
end)

if player.Character then bindCharacter(player.Character) end
refreshUI()
print("[Advanced Float V2] F fly | R dash | T burst | Y spin | B brake | RightShift UI.")
