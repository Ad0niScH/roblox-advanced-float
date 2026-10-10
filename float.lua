-- Advanced Float v1.0
-- Client-side flight / hover controller for Roblox.
-- Use as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- Does not bypass game permissions, anti-cheat, or server-authoritative movement.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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
local panelHeight = 446
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
label("V1.0  /  FLIGHT CONTROLLER", 10, theme.muted, {
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

local contents = create("Frame", {
    Name = "Contents",
    Position = UDim2.fromOffset(0, 63),
    Size = UDim2.new(1, 0, 1, -63),
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
    local goal = horizontal * actualSpeed + Vector3.new(0, yVelocity, 0)
    local blend = 1 - math.exp(-CONFIG.acceleration * math.min(dt, 0.1))
    linearVelocity.VectorVelocity = linearVelocity.VectorVelocity:Lerp(goal, blend)
    alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, forward)

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
print("[Advanced Float] Ready. F = fly, C = cruise, X = stop, RightShift = UI.")
