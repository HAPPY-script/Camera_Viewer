if _G.Camera_Viewer then
    warn("Script đã chạy! Không thể chạy lại.")
    return
end
_G.Camera_Viewer = true

game.StarterGui:SetCore("SendNotification", {
    Title = "⚙Camera Viewer👁";
    Text = "🔔Press Shift + P to enable or disable.";
    Duration = 20;
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- CONFIG
local ROTATE_BUTTON = Enum.UserInputType.MouseButton2 -- right mouse button
local DEFAULT_SPEED = 60        -- studs per second
local MIN_SPEED = 5
local MAX_SPEED = 1000
local SPEED_STEP = 10           -- when using wheel
local MOUSE_SENSITIVITY = 0.005 -- rotation sensitivity
local PITCH_LIMIT = math.rad(89) -- limit pitch to avoid gimbal

-- STATE
local enabled = false
local flyPart = nil
local yaw = 0      -- rotation around Y (radians)
local pitch = 0    -- rotation around X (radians)
local speed = DEFAULT_SPEED
local rotating = false
local moveState = {W=false,A=false,S=false,D=false,Q=false,E=false}
local connRender = nil
local prevMousePos = Vector2.new()
local initialMouseCaptured = false

-- Utility: restore camera to default (Custom + subject = humanoid or workspace)
local function restoreCamera()
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        -- Try set camera subject back to humanoid if exists
        local char = player.Character
        if char then
            local hum = char:FindFirstChildWhichIsA("Humanoid")
            if hum then
                camera.CameraSubject = hum
            end
        end
    end
end

-- Create the hidden part at player's head/root position
local function createFlyPart()
    local char = player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
    local pos = root and root.Position or (camera and camera.CFrame.Position or Vector3.new(0,5,0))

    local p = Instance.new("Part")
    p.Name = "FlyCam_Part_"..tostring(player.UserId)
    p.Size = Vector3.new(1,1,1)
    p.Transparency = 1
    p.CanCollide = false
    p.Anchored = true
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Position = pos + Vector3.new(0,2,0)
    p.Parent = workspace
    return p
end

-- Clean up part
local function destroyFlyPart()
    if flyPart and flyPart.Parent then
        flyPart:Destroy()
    end
    flyPart = nil
end

-- Update camera each frame to follow flyPart
local function renderStep(dt)
    if not flyPart then return end

    -- rotation already applied to flyPart in mouse code; maintain camera at flyPart CFrame
    camera.CFrame = flyPart.CFrame
    -- movement: compute from moveState
    local moveVec = Vector3.new(0,0,0)
    if moveState.W then moveVec = moveVec + flyPart.CFrame.LookVector end
    if moveState.S then moveVec = moveVec - flyPart.CFrame.LookVector end
    if moveState.D then moveVec = moveVec + flyPart.CFrame.RightVector end
    if moveState.A then moveVec = moveVec - flyPart.CFrame.RightVector end
    if moveState.E then moveVec = moveVec + flyPart.CFrame.UpVector end
    if moveState.Q then moveVec = moveVec - flyPart.CFrame.UpVector end

    if moveVec.Magnitude > 0 then
        local deltaPos = moveVec.Unit * speed * dt
        local newPos = flyPart.Position + deltaPos
        -- apply rotation: keep orientation (we construct CFrame from position and stored yaw/pitch)
        local orient = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
        flyPart.CFrame = CFrame.new(newPos) * orient
    end
end

-- Mouse movement rotation handler
local function onMouseMove(input)
    if not rotating or not flyPart then return end
    -- input is InputObject with Delta
    local dx = input.Delta.X
    local dy = input.Delta.Y
    yaw = yaw - dx * MOUSE_SENSITIVITY
    pitch = pitch - dy * MOUSE_SENSITIVITY
    -- clamp pitch
    if pitch > PITCH_LIMIT then pitch = PITCH_LIMIT end
    if pitch < -PITCH_LIMIT then pitch = -PITCH_LIMIT end

    -- update flyPart orientation while keeping position
    local pos = flyPart.Position
    local orient = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
    flyPart.CFrame = CFrame.new(pos) * orient
end

-- Wheel to change speed (InputChanged fallback)
local function onInputChanged(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        -- handled by onMouseMove via InputChanged as well
        onMouseMove(input)
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        local delta = input.Position.Z
        if delta > 0 then
            speed = math.clamp(speed + SPEED_STEP, MIN_SPEED, MAX_SPEED)
        elseif delta < 0 then
            speed = math.clamp(speed - SPEED_STEP, MIN_SPEED, MAX_SPEED)
        end
    end
end

-- Also handle Mouse wheel via PlayerMouse (compatibility)
local function setupMouseWheelFallback()
    local success, mouse = pcall(function() return player:GetMouse() end)
    if success and mouse then
        mouse.WheelForward:Connect(function()
            speed = math.clamp(speed + SPEED_STEP, MIN_SPEED, MAX_SPEED)
        end)
        mouse.WheelBackward:Connect(function()
            speed = math.clamp(speed - SPEED_STEP, MIN_SPEED, MAX_SPEED)
        end)
    end
end

-- Input began / ended for movement keys and rotation
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == TOGGLE_KEY then
        -- toggle handled separately (use Action for safety)
        return
    end

    if input.KeyCode == Enum.KeyCode.W then moveState.W = true end
    if input.KeyCode == Enum.KeyCode.S then moveState.S = true end
    if input.KeyCode == Enum.KeyCode.A then moveState.A = true end
    if input.KeyCode == Enum.KeyCode.D then moveState.D = true end
    if input.KeyCode == Enum.KeyCode.Q then moveState.Q = true end
    if input.KeyCode == Enum.KeyCode.E then moveState.E = true end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.W then moveState.W = false end
    if input.KeyCode == Enum.KeyCode.S then moveState.S = false end
    if input.KeyCode == Enum.KeyCode.A then moveState.A = false end
    if input.KeyCode == Enum.KeyCode.D then moveState.D = false end
    if input.KeyCode == Enum.KeyCode.Q then moveState.Q = false end
    if input.KeyCode == Enum.KeyCode.E then moveState.E = false end
end)

-- Also handle InputChanged (mouse movement + wheel)
UserInputService.InputChanged:Connect(onInputChanged)

-- Toggle action: use ContextActionService to avoid conflicts with UI
local function toggleAction(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then

        -- Kiểm tra tổ hợp Shift + P
        local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

        if inputObject.KeyCode ~= Enum.KeyCode.P or not shift then
            return
        end

        if not enabled then
            -- enable
            enabled = true
            -- create part
            flyPart = createFlyPart()

            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.Anchored = true
            end

            -- initialize yaw/pitch to current camera orientation
            local cf = camera.CFrame
            -- compute yaw/pitch from camera look vector
            local look = cf.LookVector
            yaw = math.atan2(-look.X, -look.Z) + math.pi -- adjust to align axes (experimental)
            -- Another safer method: derive yaw/pitch from camera's rotation:
            local _, camY, _ = cf:ToOrientation()
            -- We'll instead set yaw/pitch from camera's CFrame
            local xRot, yRot, zRot = cf:ToEulerAnglesYXZ()
            yaw = yRot
            pitch = xRot

            -- apply orientation
            local orient = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
            flyPart.CFrame = CFrame.new(flyPart.Position) * orient

            -- set camera to scriptable and lock to part
            camera.CameraType = Enum.CameraType.Scriptable

            -- Bật mô phỏng Shift-Lock: khóa chuột giữa và ẩn con trỏ
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            UserInputService.MouseIconEnabled = false

            -- Cho phép quay bằng việc di chuột (không cần giữ chuột phải)
            rotating = true

            -- Start render loop
            connRender = RunService.RenderStepped:Connect(renderStep)

            -- setup wheel fallback
            setupMouseWheelFallback()
        else
            -- disable
            enabled = false

            rotating = false
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true

            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.Anchored = false
            end

            -- disconnect render
            if connRender then
                connRender:Disconnect()
                connRender = nil
            end

            destroyFlyPart()
            restoreCamera()
        end
    end
end

-- Bind toggle
ContextActionService:BindAction("FlyCam_Toggle", toggleAction, false, Enum.KeyCode.P)

-- If player dies or character removed while enabled, disable and cleanup
local function onCharacterRemoving()
    if enabled then
        enabled = false
        if connRender then connRender:Disconnect(); connRender = nil end
        destroyFlyPart()
        restoreCamera()
        rotating = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end
end

player.CharacterRemoving:Connect(onCharacterRemoving)
player.CharacterAdded:Connect(function(char)
    -- small safety: if camera was left scriptable (unlikely), restore it
    if not enabled then
        restoreCamera()
    end
end)

-- safety on script end / reset
script.Destroying:Connect(function()
    if enabled then
        if connRender then connRender:Disconnect() end
        destroyFlyPart()
        restoreCamera()
    end
end)
