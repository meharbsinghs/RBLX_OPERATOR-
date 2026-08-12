--!strict
-- ============================================================================
--  UI framework — the layer that makes generated games look hand-built.
--
--  Every color is a THEME TOKEN read from the GameSpec (config.theme), so
--  changing the game type flips the entire HUD without touching UI code.
--  Widgets get rounded corners, subtle strokes, gradients, and tweened
--  hover/press micro-interactions out of the box. Also ships a ViewportFrame
--  helper that renders rotating 3D weapon previews inside the screen space.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local config = require(ReplicatedStorage:WaitForChild("config"))

local uikit = {}

-- Theme tokens: every widget reads these. Generated specs supply the full set;
-- missing tokens fall back to a dark neutral so old specs still work.
local specTheme = config.theme or {}
local function token(name: string, fallback: Color3): Color3
    local value = specTheme[name]
    if typeof(value) == "Color3" then
        return value
    end
    return fallback
end

local theme = {
    accent = token("accent", Color3.fromRGB(255, 180, 40)),
    danger = token("danger", Color3.fromRGB(255, 60, 50)),
    success = token("success", Color3.fromRGB(90, 220, 120)),
    bg = token("bg", Color3.fromRGB(12, 14, 18)),
    panel = token("panel", Color3.fromRGB(18, 20, 26)),
    panelLight = token("panelLight", Color3.fromRGB(30, 34, 42)),
    text = token("text", Color3.fromRGB(235, 238, 245)),
    textDim = token("textDim", Color3.fromRGB(150, 156, 168)),
    overlay = token("overlay", Color3.fromRGB(8, 8, 10)),
}

uikit.theme = theme

function uikit.tween(instance: Instance, seconds: number, goal: { [string]: any }, easeStyle: Enum.EasingStyle?)
    TweenService:Create(instance, TweenInfo.new(seconds, easeStyle or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

function uikit.corner(instance: Instance, radius: number): UICorner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

function uikit.stroke(instance: Instance, color: Color3?, thickness: number?): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Color3.fromRGB(255, 255, 255)
    stroke.Thickness = thickness or 1
    stroke.Transparency = 0.85
    stroke.Parent = instance
    return stroke
end

function uikit.gradient(instance: Instance, color1: Color3, color2: Color3, angle: number?): UIGradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(color1, color2)
    gradient.Rotation = angle or 90
    gradient.Parent = instance
    return gradient
end

function uikit.frame(parent: Instance, size: UDim2, position: UDim2, color: Color3?, transparency: number?): Frame
    local frame = Instance.new("Frame")
    frame.Size = size
    frame.Position = position
    frame.BackgroundColor3 = color or theme.panel
    frame.BackgroundTransparency = transparency or 0
    frame.BorderSizePixel = 0
    frame.Parent = parent
    return frame
end

-- CanvasGroup: fade an entire panel (and children) with one variable.
function uikit.canvasGroup(parent: Instance, size: UDim2, position: UDim2, color: Color3?, transparency: number?): CanvasGroup
    local group = Instance.new("CanvasGroup")
    group.Size = size
    group.Position = position
    group.BackgroundColor3 = color or theme.panel
    group.BackgroundTransparency = transparency or 0
    group.BorderSizePixel = 0
    group.Parent = parent
    return group
end

function uikit.label(parent: Instance, size: UDim2, position: UDim2, text: string, color: Color3?, textSize: number?): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = size
    label.Position = position
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or theme.text
    label.TextSize = textSize or 18
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function luminance(c: Color3): number
    return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

function uikit.button(parent: Instance, size: UDim2, position: UDim2, text: string, onClick: () -> (), color: Color3?): TextButton
    local buttonColor = color or theme.accent
    local button = Instance.new("TextButton")
    button.Size = size
    button.Position = position
    button.BackgroundColor3 = buttonColor
    button.Text = text
    -- Dark buttons get light text, accent buttons get dark text
    button.TextColor3 = if luminance(buttonColor) > 0.5 then Color3.fromRGB(18, 18, 22) else Color3.fromRGB(235, 238, 245)
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = parent

    uikit.corner(button, 10)
    uikit.stroke(button, Color3.fromRGB(255, 255, 255), 1.5)

    local baseSize = size
    button.MouseEnter:Connect(function()
        uikit.tween(button, 0.12, { Size = baseSize * 1.05 }, Enum.EasingStyle.Back)
    end)
    button.MouseLeave:Connect(function()
        uikit.tween(button, 0.15, { Size = baseSize })
    end)
    button.MouseButton1Down:Connect(function()
        uikit.tween(button, 0.08, { Size = baseSize * 0.95 })
    end)
    button.MouseButton1Up:Connect(function()
        uikit.tween(button, 0.1, { Size = baseSize })
    end)
    button.Activated:Connect(function()
        onClick()
    end)
    return button
end

function uikit.bar(parent: Instance, size: UDim2, position: UDim2, color: Color3?, bgColor: Color3?): { frame: Frame, set: (number) -> () }
    local background = uikit.frame(parent, size, position, bgColor or theme.panelLight)
    uikit.corner(background, 6)
    local fill = uikit.frame(background, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), color or theme.success)
    uikit.corner(fill, 6)
    return {
        frame = background,
        set = function(frac: number)
            uikit.tween(fill, 0.15, { Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) })
        end,
    }
end

-- --------------------------------------------------------------------------
--  3D viewport previews (ViewportFrame + rotating procedural model)
-- --------------------------------------------------------------------------

function uikit.viewport(parent: Instance, size: UDim2, position: UDim2): ViewportFrame
    local vp = Instance.new("ViewportFrame")
    vp.Size = size
    vp.Position = position
    vp.BackgroundColor3 = theme.panel
    vp.BorderSizePixel = 0
    vp.Parent = parent
    uikit.corner(vp, 10)
    uikit.stroke(vp, theme.textDim, 1)

    local camera = Instance.new("Camera")
    camera.Parent = vp
    vp.CurrentCamera = camera
    return vp
end

local function addPreviewPart(parent: Instance, size: Vector3, color: Color3, rel: CFrame, material: Enum.Material?): Part
    local part = Instance.new("Part")
    part.Size = size
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = true
    part.Material = material or Enum.Material.Metal
    part.Color = color
    part.Parent = parent
    part:SetAttribute("Rel", rel)
    return part
end

-- Render a rotating preview of a weapon spec inside an existing ViewportFrame.
-- Re-uses the same procedural gun language as the FPS viewmodel so the UI
-- preview matches the gun in your hand. A per-viewport generation counter
-- guarantees only the newest rotation loop runs after a rebuild.
local previewGen = 0

function uikit.viewportWeapon(vp: ViewportFrame, spec: { color: Color3, kind: string }?)
    for _, child in vp:GetChildren() do
        if child:IsA("BasePart") then
            child:Destroy()
        end
    end
    local camera = vp.CurrentCamera
    if not spec or not camera then
        return
    end

    local dark = Color3.fromRGB(24, 26, 30)
    if spec.kind == "melee" then
        addPreviewPart(vp, Vector3.new(0.12, 0.12, 2.2), Color3.fromRGB(190, 194, 205), CFrame.new(0, 0, -0.4))
        addPreviewPart(vp, Vector3.new(0.5, 0.35, 0.6), dark, CFrame.new(0, 0, 1.1))
    else
        local bodyColor = spec.color:Lerp(dark, 0.4)
        addPreviewPart(vp, Vector3.new(0.18, 0.18, 2.6), spec.color, CFrame.new(0, 0, -0.8))
        addPreviewPart(vp, Vector3.new(0.5, 0.4, 1.2), bodyColor, CFrame.new(0, 0, 0.2))
        addPreviewPart(vp, Vector3.new(0.3, 0.35, 0.6), dark, CFrame.new(0, -0.5, 0.9))
        addPreviewPart(vp, Vector3.new(0.24, 0.6, 0.4), dark, CFrame.new(0, 0.15, 0.35))
    end

    camera.CFrame = CFrame.new(0, 0.3, 6)

    previewGen += 1
    local myGen = previewGen
    vp:SetAttribute("PreviewGen", myGen)

    task.spawn(function()
        local t = 0
        while vp.Parent do
            if vp:GetAttribute("PreviewGen") ~= myGen then
                return -- a newer preview replaced this one
            end
            t += 0.025
            local base = CFrame.Angles(0.12, t, 0)
            for _, child in vp:GetChildren() do
                if child:IsA("BasePart") and child.Parent == vp then
                    local rel = child:GetAttribute("Rel") :: CFrame
                    if typeof(rel) == "CFrame" then
                        child.CFrame = base * rel
                    end
                end
            end
            task.wait()
        end
    end)
end

return uikit
