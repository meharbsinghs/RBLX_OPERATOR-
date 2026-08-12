--!strict
-- ============================================================================
--  Procedural asset factory.
--
--  Builds high-quality low-poly models (enemy rigs, impact effects) from
--  primitive parts so games run with ZERO external assets. When the pipeline
--  generates Meshy models (assets/registry.json), attach those meshes to the
--  same slots — the engine degrades gracefully.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))

local proceduralassets = {}

local style = (config.styleGuide and config.styleGuide.material) or "grunge"
local eye = config.styleGuide and config.styleGuide.eyeColor
local eyeColor = Color3.fromRGB(
    (eye and eye[1]) or 255,
    (eye and eye[2]) or 40,
    (eye and eye[3]) or 30
)

-- Material for enemy "flesh" per style guide: grunge = fabric, sci-fi = metal,
-- cartoon/neon = smooth plastic. Keeps generated rigs on-theme without assets.
function proceduralassets.styleMaterial(role: string): Enum.Material
    if style == "sci-fi" then
        return Enum.Material.Metal
    elseif style == "cartoon" or style == "neon" then
        return Enum.Material.SmoothPlastic
    end
    return role == "flesh" and Enum.Material.Fabric or Enum.Material.SmoothPlastic
end

local function buildBodyPart(parent: Instance, name: string, size: Vector3, color: Color3, cframe: CFrame): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Material = proceduralassets.styleMaterial((name == "Torso" or name == "Head") and "flesh" or "limb")
    part.Color = color
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function weld(a: Instance, b: Instance)
    local constraint = Instance.new("WeldConstraint")
    constraint.Part0 = a
    constraint.Part1 = b
    constraint.Parent = a
end

-- Builds an R6-style enemy rig from an EnemySpec. Returns the model parts.
function proceduralassets.spawnEnemyModel(
    spec: { id: string, color: Color3, scale: number, isBoss: boolean },
    spawnPos: Vector3,
    parent: Instance
): { model: Model, humanoid: Humanoid, root: BasePart }
    local s = spec.scale
    local model = Instance.new("Model")
    model.Name = "Enemy"
    model.Parent = parent

    local baseCF = CFrame.new(spawnPos)

    local root = buildBodyPart(model, "HumanoidRootPart", Vector3.new(2 * s, 2 * s, 1 * s), Color3.fromRGB(255, 255, 255), baseCF)
    root.Transparency = 1
    root.CanCollide = true

    local torso = buildBodyPart(model, "Torso", Vector3.new(2 * s, 2 * s, 1 * s), spec.color, baseCF * CFrame.new(0, 1.5 * s, 0))
    local head = buildBodyPart(model, "Head", Vector3.new(1.2 * s, 1.2 * s, 1.2 * s), spec.color:Lerp(Color3.fromRGB(0, 0, 0), 0.25), baseCF * CFrame.new(0, 3.2 * s, 0))

    local armColor = spec.color:Lerp(Color3.fromRGB(0, 0, 0), 0.15)
    local legColor = spec.color:Lerp(Color3.fromRGB(0, 0, 0), 0.35)
    local leftArm = buildBodyPart(model, "Left Arm", Vector3.new(0.8 * s, 1.8 * s, 0.8 * s), armColor, baseCF * CFrame.new(-1.4 * s, 2.1 * s, 0))
    local rightArm = buildBodyPart(model, "Right Arm", Vector3.new(0.8 * s, 1.8 * s, 0.8 * s), armColor, baseCF * CFrame.new(1.4 * s, 2.1 * s, 0))
    local leftLeg = buildBodyPart(model, "Left Leg", Vector3.new(0.9 * s, 1.8 * s, 0.9 * s), legColor, baseCF * CFrame.new(-0.6 * s, -0.4 * s, 0))
    local rightLeg = buildBodyPart(model, "Right Leg", Vector3.new(0.9 * s, 1.8 * s, 0.9 * s), legColor, baseCF * CFrame.new(0.6 * s, -0.4 * s, 0))

    -- Glowing eyes (color from the style guide)
    for _, side in { -0.22, 0.22 } do
        local eye = buildBodyPart(model, "Eye", Vector3.new(0.22 * s, 0.22 * s, 0.1 * s), eyeColor, head.CFrame * CFrame.new(side * s, 0.05 * s, -0.6 * s))
        eye.Material = Enum.Material.Neon
        weld(head, eye)
    end

    -- Boss flair: red glow + smoke
    if spec.isBoss then
        local light = Instance.new("PointLight")
        light.Parent = head
        light.Color = eyeColor
        light.Range = 24 * s
        light.Brightness = 2
        local smoke = Instance.new("ParticleEmitter")
        smoke.Parent = head
        smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
        smoke.Rate = 12
        smoke.Speed = NumberRange.new(1, 2)
        smoke.Lifetime = NumberRange.new(1.5, 2.5)
        smoke.Size = NumberSequence.new(1 * s)
        smoke.Transparency = NumberSequence.new(0.4)
        smoke.Color = ColorSequence.new(Color3.fromRGB(120, 40, 40))
    end

    weld(root, torso)
    weld(torso, head)
    weld(torso, leftArm)
    weld(torso, rightArm)
    weld(torso, leftLeg)
    weld(torso, rightLeg)

    local humanoid = Instance.new("Humanoid")
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.WalkSpeed = 12
    humanoid.Parent = model

    model.PrimaryPart = root
    return { model = model, humanoid = humanoid, root = root }
end

-- Blood / impact burst at a position.
function proceduralassets.spawnBlood(position: Vector3, parent: Instance)
    local part = Instance.new("Part")
    part.Name = "Blood"
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Transparency = 1
    part.Anchored = true
    part.CanCollide = false
    part.Parent = parent

    local emitter = Instance.new("ParticleEmitter")
    emitter.Parent = part
    emitter.Texture = "rbxasset://textures/particles/explosion_fire_main.dds"
    emitter.Rate = 40
    emitter.Lifetime = NumberRange.new(0.2, 0.5)
    emitter.Speed = NumberRange.new(4, 10)
    emitter.Size = NumberSequence.new(0.6)
    emitter.Color = ColorSequence.new(Color3.fromRGB(150, 10, 10))
    emitter.Transparency = NumberSequence.new(0.2)
    emitter.LightEmission = 0.4
    emitter.Enabled = true
    emitter:Emit(8)

    game:GetService("Debris"):AddItem(part, 0.6)
end

return proceduralassets
