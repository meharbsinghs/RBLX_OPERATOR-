--!strict
-- ============================================================================
--  Client-side entity registry + interpolation layer.
--
--  Consumes the compressed EnemyStateBatch channel (integer-keyed payloads —
--  see shared/pack.luau) and keeps a smoothed local view of the horde: counts
--  ease toward the server value, per-enemy health lerps so UI never pops.
--
--  The batch also carries authoritative death events. Each kill spawns a
--  contextual blood burst and a local, non-replicated ragdoll assembly, so
--  horde clearing has visceral feedback with ZERO extra network chatter — the
--  server only ever broadcasts one batched channel.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local config = require(ReplicatedStorage:WaitForChild("config"))

local entities = {}

type Entry = {
    x: number,
    y: number,
    z: number,
    hp: number,
    mx: number,
    displayHp: number,
}

local observed: { [number]: Entry } = {}
local smoothedCount = 0
local targetCount = 0

-- --------------------------------------------------------------------------
--  Death VFX
-- --------------------------------------------------------------------------

local MAX_RAGDOLLS = 30
local activeRagdolls = 0

local function enemyColor(typeId: string): Color3
    for _, spec in config.enemies do
        if spec.id == typeId then
            return spec.color
        end
    end
    return Color3.fromRGB(110, 150, 110)
end

-- Cheap blood burst: one transparent part + a manual particle emit, gone in
-- ~1s. Runs entirely client-side; nothing here replicates to the server.
local function spawnBlood(position: Vector3)
    local holder = Instance.new("Part")
    holder.Name = "BloodBurst"
    holder.Size = Vector3.new(0.4, 0.4, 0.4)
    holder.Transparency = 1
    holder.Anchored = true
    holder.CanCollide = false
    holder.CanQuery = false
    holder.CanTouch = false
    holder.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Parent = holder
    emitter.Color = ColorSequence.new(Color3.fromRGB(150, 16, 20))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.55),
        NumberSequenceKeypoint.new(0.6, 0.25),
        NumberSequenceKeypoint.new(1, 0.04),
    })
    emitter.Lifetime = NumberRange.new(0.25, 0.6)
    emitter.Speed = NumberRange.new(5, 14)
    emitter.SpreadAngle = Vector2.new(360, 360)
    emitter.LightEmission = 0.12
    emitter.LightInfluence = 0
    emitter:Emit(28)

    Debris:AddItem(holder, 1.2)
end

-- Ragdoll: a local, unanchored body assembly (torso + head + limbs joined by
-- BallSocketConstraints) that bursts apart and tumbles under physics. Because
-- it is client-created, it never replicates to the server or other clients —
-- satisfying death physics at zero server cost.
local RAGDOLL_BODY = {
    { name = "Head", size = Vector3.new(0.9, 0.9, 0.9), offset = Vector3.new(0, 1.9, 0) },
    { name = "Torso", size = Vector3.new(1.6, 1.6, 0.9), offset = Vector3.new(0, 0.8, 0) },
    { name = "Left Arm", size = Vector3.new(0.45, 1.3, 0.45), offset = Vector3.new(-1.15, 1.15, 0) },
    { name = "Right Arm", size = Vector3.new(0.45, 1.3, 0.45), offset = Vector3.new(1.15, 1.15, 0) },
    { name = "Left Leg", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(-0.5, -0.6, 0) },
    { name = "Right Leg", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(0.5, -0.6, 0) },
}

-- Torso-anchored joint offsets + matching limb-anchored offsets.
local RAGDOLL_JOINTS = {
    { limb = "Head", torsoOffset = Vector3.new(0, 0.75, 0), limbOffset = Vector3.new(0, -0.45, 0) },
    { limb = "Left Arm", torsoOffset = Vector3.new(-0.75, 0.5, 0), limbOffset = Vector3.new(0, 0.65, 0) },
    { limb = "Right Arm", torsoOffset = Vector3.new(0.75, 0.5, 0), limbOffset = Vector3.new(0, 0.65, 0) },
    { limb = "Left Leg", torsoOffset = Vector3.new(-0.4, -0.6, 0), limbOffset = Vector3.new(0, 0.75, 0) },
    { limb = "Right Leg", torsoOffset = Vector3.new(0.4, -0.6, 0), limbOffset = Vector3.new(0, 0.75, 0) },
}

local function spawnRagdoll(position: Vector3, color: Color3)
    if activeRagdolls >= MAX_RAGDOLLS then
        return
    end
    activeRagdolls += 1
    task.delay(5, function()
        activeRagdolls = math.max(0, activeRagdolls - 1)
    end)

    local model = Instance.new("Model")
    model.Name = "DeathRagdoll"
    model.Parent = workspace

    local torso: Part? = nil
    local limbs: { [string]: Part } = {}
    local dark = color:Lerp(Color3.new(0.3, 0.28, 0.3), 0.3)

    for _, body in RAGDOLL_BODY do
        local part = Instance.new("Part")
        part.Name = body.name
        part.Size = body.size
        part.Color = if body.name == "Head" then color else dark
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = false
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CFrame = CFrame.new(position + body.offset)
        part.Parent = model
        limbs[body.name] = part
        if body.name == "Torso" then
            torso = part
        end
    end

    if torso then
        for _, joint in RAGDOLL_JOINTS do
            local limb = limbs[joint.limb]
            if limb then
                local torsoAtt = Instance.new("Attachment")
                torsoAtt.Position = joint.torsoOffset
                torsoAtt.Parent = torso
                local limbAtt = Instance.new("Attachment")
                limbAtt.Position = joint.limbOffset
                limbAtt.Parent = limb
                local socket = Instance.new("BallSocketConstraint")
                socket.Attachment0 = torsoAtt
                socket.Attachment1 = limbAtt
                socket.LimitsEnabled = true
                socket.UpperAngle = 60
                socket.Parent = torso
            end
        end
    end

    -- Burst impulse on the torso; the constraints drag the limbs along.
    if torso then
        local dir = Vector3.new(math.random() - 0.5, math.random() * 0.7 + 0.3, math.random() - 0.5)
        if dir.Magnitude < 0.01 then
            dir = Vector3.new(0, 1, 0)
        end
        torso.AssemblyLinearVelocity = dir.Unit * math.random(8, 20)
        torso.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
    end

    Debris:AddItem(model, 4)
end

local function spawnDeathVFX(death: any)
    local d = death :: { x: number, y: number, z: number, typeId: string }
    local position = Vector3.new(d.x, d.y, d.z)
    local color = enemyColor(d.typeId)
    spawnBlood(position)
    spawnRagdoll(position, color)
end

-- --------------------------------------------------------------------------
--  Public API
-- --------------------------------------------------------------------------

function entities.getCount(): number
    return math.round(smoothedCount)
end

-- Smoothed health readout for an entity (displayHp, maxHp) or nil.
function entities.getHealth(id: number): (number, number)?
    local entry = observed[id]
    if entry then
        return entry.displayHp, entry.mx
    end
    return nil
end

-- Latest server-reported position for an entity, if observed.
function entities.getPosition(id: number): Vector3?
    local entry = observed[id]
    if entry then
        return Vector3.new(entry.x, entry.y, entry.z)
    end
    return nil
end

function entities.init()
    networking.onClient(constants.REMOTES.EnemyStateBatch, function(payload: any)
        local p = payload :: { count: number, ents: { [number]: any }, deaths: { any }? }
        targetCount = tonumber(p.count) or 0
        local seen: { [number]: boolean } = {}
        for id, raw in p.ents do
            seen[id] = true
            local entry = observed[id]
            if not entry then
                observed[id] = {
                    x = raw.x,
                    y = raw.y,
                    z = raw.z,
                    hp = raw.hp,
                    mx = raw.mx,
                    displayHp = raw.hp,
                }
            else
                entry.x = raw.x
                entry.y = raw.y
                entry.z = raw.z
                entry.hp = raw.hp
                entry.mx = raw.mx
            end
        end
        local removed: { number } = {}
        for id in observed do
            if not seen[id] then
                table.insert(removed, id)
            end
        end
        for _, id in removed do
            observed[id] = nil
        end

        -- Authoritative kills since the last batch -> contextual local VFX.
        if p.deaths then
            for _, death in p.deaths do
                spawnDeathVFX(death)
            end
        end
    end)

    RunService.RenderStepped:Connect(function(dt: number)
        smoothedCount = smoothedCount + (targetCount - smoothedCount) * math.min(1, dt * 6)
        for _, entry in observed do
            local diff = entry.hp - entry.displayHp
            if math.abs(diff) > 0.5 then
                entry.displayHp += diff * math.min(1, dt * 10)
            else
                entry.displayHp = entry.hp
            end
        end
    end)
end

return entities
