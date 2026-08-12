--!strict
-- ============================================================================
--  First-person viewmodel controller.
--
--  Builds a procedural weapon model parented to the camera and drives it with
--  a spring-physics feel layer: mouse sway, positional kickback, rotational
--  kick, ADS blend, reload dip, walk bob and a downed drop. Every motion runs
--  through a damped spring (semi-implicit Euler), so the weapon always feels
--  weighty and snaps back to rest with zero wobble — the difference between
--  "a rectangle in the corner" and a gun you can feel.
--
--  Presentation only. Damage and validation stay server-authoritative.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local types = require(ReplicatedStorage:WaitForChild("types"))

local viewmodel = {}

-- --------------------------------------------------------------------------
--  Spring math — the entire feel layer runs on these.
-- --------------------------------------------------------------------------

type Spring = {
    pos: number,
    vel: number,
}

local function newSpring(pos: number): Spring
    return { pos = pos, vel = 0 }
end

-- Semi-implicit Euler with velocity damping. stiffness controls how hard the
-- spring pulls toward its target; damping controls how quickly it stops.
-- Lower damping = snappier, punchier returns; higher = smooth ADS blends.
local function tickSpring(s: Spring, target: number, dt: number, stiffness: number, damping: number): number
    s.vel += (target - s.pos) * stiffness * dt
    s.vel *= 1 / (1 + damping * dt)
    s.pos += s.vel * dt
    return s.pos
end

-- Velocity impulse: kick the spring and let it decay back to rest.
local function springImpulse(s: Spring, force: number)
    s.vel += force
end

export type Viewmodel = {
    setWeapon: (spec: types.WeaponSpec) -> (),
    update: (dt: number) -> (),
    kick: (power: number) -> (),
    reload: () -> (),
    setAiming: (aiming: boolean) -> (),
    setDowned: (downed: boolean) -> (),
    addSway: (delta: Vector2) -> (),
    getMuzzlePosition: () -> Vector3,
    destroy: () -> (),
}

function viewmodel.new(camera: Camera, player: Player): Viewmodel
    local parts: { { part: Part, rel: CFrame } } = {}
    local muzzleRel: CFrame? = nil
    local muzzleWorld = Vector3.new(0, 0, -3)

    -- Motion springs
    local swayX = newSpring(0)     -- horizontal mouse sway
    local swayY = newSpring(0)     -- vertical mouse sway + idle breath
    local kickZ = newSpring(0)     -- positional kickback (weapon pushes back)
    local kickRot = newSpring(0)   -- rotational kick (muzzle rise)
    local ads = newSpring(0)       -- aim-down-sight blend 0..1
    local reloadDip = newSpring(0) -- reload animation

    local lastDelta = Vector2.new(0, 0)
    local aiming = false
    local downed = false

    local function clearParts()
        for _, entry in parts do
            if entry.part.Parent then
                entry.part:Destroy()
            end
        end
        parts = {}
        muzzleRel = nil
    end

    local function addPart(size: Vector3, color: Color3, rel: CFrame, material: Enum.Material?)
        local part = Instance.new("Part")
        part.Size = size
        part.Anchored = true
        part.CanCollide = false
        part.CastShadow = false
        part.Material = material or Enum.Material.Metal
        part.Color = color
        part.Parent = camera
        table.insert(parts, { part = part, rel = rel })
        return part
    end

    local function buildParts(spec: types.WeaponSpec)
        clearParts()
        local dark = Color3.fromRGB(24, 26, 30)

        if spec.kind == "melee" then
            addPart(Vector3.new(0.06, 0.06, 0.9), Color3.fromRGB(190, 194, 205), CFrame.new(0.28, -0.18, -0.6))
            addPart(Vector3.new(0.16, 0.12, 0.22), dark, CFrame.new(0.28, -0.18, 0.2))
            muzzleRel = CFrame.new(0.28, -0.18, -1.1)
            return
        end

        local bodyColor = spec.color:Lerp(dark, 0.4)
        addPart(Vector3.new(0.09, 0.09, 1.1), spec.color, CFrame.new(0.3, -0.16, -0.7)) -- barrel
        addPart(Vector3.new(0.16, 0.2, 0.55), bodyColor, CFrame.new(0.3, -0.16, -0.1))  -- receiver
        addPart(Vector3.new(0.1, 0.12, 0.28), dark, CFrame.new(0.3, -0.22, 0.28))       -- stock
        addPart(Vector3.new(0.11, 0.26, 0.16), dark, CFrame.new(0.3, -0.05, 0.08))      -- grip + mag
        addPart(Vector3.new(0.08, 0.1, 0.18), dark, CFrame.new(0.3, -0.05, -0.45))      -- front sight
        muzzleRel = CFrame.new(0.3, -0.16, -1.3)
    end

    local function update(dt: number)
        if downed or #parts == 0 then
            return
        end
        local time = os.clock()

        -- Mouse sway: the springs chase the delta, then relax to rest.
        tickSpring(swayX, math.clamp(-lastDelta.X * 1.7, -0.1, 0.1), dt, 90, 13)
        tickSpring(swayY, math.clamp(lastDelta.Y * 1.7, -0.1, 0.1) + math.sin(time * 1.4) * 0.006, dt, 90, 13)
        lastDelta = Vector2.new(0, 0)

        -- Kick / dip / ADS springs always relax toward their targets.
        tickSpring(kickZ, 0, dt, 110, 11)
        tickSpring(kickRot, 0, dt, 90, 13)
        tickSpring(ads, aiming and 1 or 0, dt, 70, 11)
        tickSpring(reloadDip, 0, dt, 60, 9)

        -- Walk bob
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.5
        local bobX = 0
        local bobY = 0
        local bobRoll = 0
        if moving then
            bobX = math.sin(time * 9) * 0.02
            bobY = math.abs(math.cos(time * 9)) * 0.02
            bobRoll = math.sin(time * 9) * 0.01
        end

        -- Blend between hip-fire and ADS positions, then apply sway + kick.
        local rest = CFrame.new(0.3, -0.16, -0.5)
        local adsPos = CFrame.new(0, -0.15, -0.52)
        local base = camera.CFrame
            * rest:Lerp(adsPos, ads.pos)
            * CFrame.new(swayX.pos, swayY.pos + bobY, -kickZ.pos * 3)
            * CFrame.Angles(
                kickRot.pos * 1.15 + reloadDip.pos * -2.6 + bobX,
                kickRot.pos * 0.35,
                kickRot.pos * 0.4 + bobRoll
            )

        for _, entry in parts do
            entry.part.CFrame = base * entry.rel
        end
        if muzzleRel then
            muzzleWorld = (base * muzzleRel).Position
        end
    end

    local function setWeapon(spec: types.WeaponSpec)
        buildParts(spec)
        -- A fresh weapon starts its kick springs at rest.
        kickZ.pos = 0
        kickRot.pos = 0
        kickZ.vel = 0
        kickRot.vel = 0
    end

    return {
        setWeapon = setWeapon,
        update = update,
        kick = function(power: number)
            springImpulse(kickZ, 0.3 + power * 0.06)
            springImpulse(kickRot, power)
        end,
        reload = function()
            springImpulse(reloadDip, 1.4)
        end,
        setAiming = function(value: boolean)
            aiming = value
        end,
        setDowned = function(value: boolean)
            downed = value
            for _, entry in parts do
                entry.part.Visible = not value
            end
        end,
        addSway = function(delta: Vector2)
            lastDelta = delta
        end,
        getMuzzlePosition = function(): Vector3
            return muzzleWorld
        end,
        destroy = function()
            clearParts()
        end,
    }
end

return viewmodel
