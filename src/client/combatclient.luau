--!strict
-- ============================================================================
--  First-person combat client. Owns the camera, input, tracers and firing
--  feel (recoil, spread, FOV punch). The weapon viewmodel itself lives in the
--  spring-driven viewmodel.luau module. The server remains authoritative for
--  damage — this is pure presentation + request.
-- ============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local types = require(ReplicatedStorage:WaitForChild("types"))
local mathutils = require(ReplicatedStorage:WaitForChild("mathutils"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local hud = require(script.Parent.ui.hud)
local viewmodel = require(script.Parent.viewmodel)

local combatclient = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")
local BASE_FOV = 70
local SENSITIVITY = 1.6

local equippedSpec: types.WeaponSpec? = nil
local loadout = { equipped = "m1911", weapons = {}, ammo = {} }
local aiming = false
local firing = false
local lastFireTime = 0
local yaw = 0
local pitch = 0
local recoilPitch = 0
local recoilYaw = 0
local fovPunch = 0
local spread = 0
local lastMouseDelta = Vector2.new(0, 0)
local isDowned = false
local vm: viewmodel.Viewmodel? = nil

-- --------------------------------------------------------------------------
--  Weapons
-- --------------------------------------------------------------------------

local function currentSpec(): types.WeaponSpec?
    if not equippedSpec then
        for _, spec in config.weapons do
            if spec.id == loadout.equipped then
                equippedSpec = spec
            end
        end
    end
    return equippedSpec
end

local function adsFov(): number
    local spec = currentSpec()
    if spec and spec.id == "sniper" then
        return 20
    end
    return 45
end

-- --------------------------------------------------------------------------
--  Viewmodel
-- --------------------------------------------------------------------------

-- The weapon viewmodel (parts, sway, kick, ADS, reload, bob) now lives in
-- its own spring-driven module — see viewmodel.luau.

-- --------------------------------------------------------------------------
--  Camera
-- --------------------------------------------------------------------------

local function updateCamera(dt: number)
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    local basePos = head and head.Position or Vector3.new(0, 3, 0)

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local bob = Vector3.zero
    if humanoid and humanoid.MoveDirection.Magnitude > 0.5 then
        bob = Vector3.new(math.sin(os.clock() * 9) * 0.05, math.abs(math.cos(os.clock() * 9)) * 0.05, 0)
    end

    local targetFov = BASE_FOV
    if aiming then
        targetFov = adsFov()
    end
    targetFov += fovPunch
    camera.FieldOfView = mathutils.damp(camera.FieldOfView, targetFov, 12, dt)

    local roll = 0
    if isDowned then
        roll = 0.35
    end
    camera.CFrame = CFrame.new(basePos + Vector3.new(0, 1.5, 0) + bob)
        * CFrame.Angles(pitch + recoilPitch, yaw + recoilYaw, roll)
end

-- --------------------------------------------------------------------------
--  Firing
-- --------------------------------------------------------------------------

local function requestReload()
    local spec = currentSpec()
    if not spec or spec.kind ~= "gun" then
        return
    end
    networking.fireServer(constants.REMOTES.ReloadRequest)
    if vm then
        vm:reload()
    end
end

local function requestRevive()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    for _, other in Players:GetPlayers() do
        if other ~= player and other:GetAttribute(constants.ATTRIBUTES.Downed) == true then
            local otherChar = other.Character
            local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position - root.Position).Magnitude < config.player.reviveRange then
                networking.fireServer(constants.REMOTES.ReviveRequest, { target = other.Name })
                return
            end
        end
    end
end

local function canFire(): boolean
    local spec = currentSpec()
    if not spec or isDowned then
        return false
    end
    local rps = spec.roundsPerSecond
    if spec.kind == "gun" then
        local ammo = loadout.ammo[spec.id]
        if not ammo or ammo.mag <= 0 then
            requestReload()
            return false
        end
    end
    return tick() - lastFireTime >= 1 / rps
end

local function muzzleFlash()
    local flash = Instance.new("Part")
    flash.Size = Vector3.new(0.35, 0.35, 0.35)
    flash.Shape = Enum.PartType.Ball
    flash.Anchored = true
    flash.CanCollide = false
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.fromRGB(255, 200, 90)
    flash.CFrame = CFrame.new(vm and vm:getMuzzlePosition() or camera.CFrame.Position + camera.CFrame.LookVector * 2)
    flash.Parent = workspace
    Debris:AddItem(flash, 0.08)
    local light = Instance.new("PointLight")
    light.Parent = flash
    light.Color = Color3.fromRGB(255, 200, 90)
    light.Range = 14
    light.Brightness = 3
end

local function spawnTracer(origin: Vector3, endPos: Vector3, color: Color3)
    local delta = endPos - origin
    local length = delta.Magnitude
    if length < 0.5 then
        return
    end
    local tracer = Instance.new("Part")
    tracer.Size = Vector3.new(0.06, 0.06, length)
    tracer.CFrame = CFrame.new(origin, endPos) * CFrame.new(0, 0, -length / 2)
    tracer.Anchored = true
    tracer.CanCollide = false
    tracer.CastShadow = false
    tracer.Material = Enum.Material.Neon
    tracer.Color = color
    tracer.Transparency = 0.25
    tracer.Parent = workspace
    Debris:AddItem(tracer, 0.09)
end

local function clientRaycast(origin: Vector3, dir: Vector3, range: number): Vector3?
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local character = player.Character
    params.FilterDescendantsInstances = character and { character } or {}
    local result = workspace:Raycast(origin, dir * range, params)
    if result then
        local spark = Instance.new("Part")
        spark.Size = Vector3.new(0.2, 0.2, 0.2)
        spark.Anchored = true
        spark.CanCollide = false
        spark.Material = Enum.Material.Neon
        spark.Color = Color3.fromRGB(255, 240, 160)
        spark.CFrame = CFrame.new(result.Position)
        spark.Parent = workspace
        Debris:AddItem(spark, 0.06)
        return result.Position
    end
    return origin + dir * range
end

local function fire()
    local spec = currentSpec()
    if not spec or spec.kind ~= "gun" then
        return
    end
    if not canFire() then
        return
    end
    lastFireTime = tick()

    local origin = camera.CFrame.Position
    local dir = mathutils.coneDirection(camera.CFrame.LookVector, spec.spread + spread)
    local endPos = clientRaycast(origin, dir, spec.range)
    local tracerColor = if spec.id == "raygun" then Color3.fromRGB(140, 230, 255) else Color3.fromRGB(255, 220, 120)

    muzzleFlash()
    spawnTracer(origin, endPos, tracerColor)

    recoilPitch += math.rad(spec.recoil) * 0.5
    recoilYaw += (math.random() - 0.5) * math.rad(spec.recoil) * 0.6
    fovPunch += 1.2
    spread = math.min(spread + 0.02, 0.1)
    if vm then
        vm:kick(spec.recoil)
    end

    local ammo = loadout.ammo[spec.id]
    if ammo then
        ammo.mag -= 1
        hud.setAmmo(ammo.mag, ammo.reserve, false, 0)
    end

    networking.fireServer(constants.REMOTES.GunFired, {
        weaponId = spec.id,
        origin = origin,
        dir = dir,
        pellets = spec.pellets,
    })

    if not spec.auto then
        firing = false
    end
end

local function melee()
    local spec = currentSpec()
    if not spec or spec.kind ~= "melee" then
        return
    end
    if vm then
        vm:kick(1.5)
    end
    networking.fireServer(constants.REMOTES.MeleeRequest, {
        dir = camera.CFrame.LookVector,
        origin = camera.CFrame.Position,
    })
end

local function switchTo(weaponId: string)
    if loadout.weapons[weaponId] == nil then
        return
    end
    networking.fireServer(constants.REMOTES.SwitchWeapon, { weaponId = weaponId })
end

local function cycleWeapons(direction: number)
    local order: { string } = {}
    for id in loadout.weapons do
        table.insert(order, id)
    end
    table.sort(order)
    if #order == 0 then
        return
    end
    local index = 1
    for i, id in ipairs(order) do
        if id == loadout.equipped then
            index = i
        end
    end
    index = index + direction
    if index < 1 then
        index = #order
    elseif index > #order then
        index = 1
    end
    switchTo(order[index])
end

-- --------------------------------------------------------------------------
--  Input
-- --------------------------------------------------------------------------

local function setupInput()
    UserInputService.InputChanged:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Delta
            lastMouseDelta = delta
            yaw -= delta.X * 0.0022 * SENSITIVITY
            pitch -= delta.Y * 0.0022 * SENSITIVITY
            pitch = math.clamp(pitch, -1.4, 1.4)
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            cycleWeapons(if input.Position.Z > 0 then -1 else 1)
        end
    end)

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then
            return
        end
        local spec = currentSpec()
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            firing = true
            if spec and spec.kind == "melee" then
                melee()
            else
                fire()
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            aiming = true
            if vm then
                vm:setAiming(true)
            end
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            local code = input.KeyCode
            if code == Enum.KeyCode.R then
                requestReload()
            elseif code == Enum.KeyCode.F then
                melee()
            elseif code == Enum.KeyCode.E then
                requestRevive()
            elseif code >= Enum.KeyCode.One and code <= Enum.KeyCode.Nine then
                local order: { string } = {}
                for id in loadout.weapons do
                    table.insert(order, id)
                end
                table.sort(order)
                local idx = code.Value - Enum.KeyCode.One.Value + 1
                local weaponId = order[idx]
                if weaponId then
                    switchTo(weaponId)
                end
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            firing = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            aiming = false
            if vm then
                vm:setAiming(false)
            end
        end
    end)
end

-- --------------------------------------------------------------------------
--  Networking
-- --------------------------------------------------------------------------

local function onLoadout(payload: any)
    local p = payload :: { equipped: string, weapons: any, ammo: any }
    loadout = { equipped = p.equipped, weapons = p.weapons or {}, ammo = p.ammo or {} }
    equippedSpec = nil
    local spec = currentSpec()
    if spec and vm then
        vm:setWeapon(spec)
    end
end

local function onAmmo(payload: any)
    local p = payload :: { weaponId: string, mag: number, reserve: number }
    local ammo = loadout.ammo[p.weaponId]
    if ammo then
        ammo.mag = p.mag
        ammo.reserve = p.reserve
    end
end

function combatclient.init()
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = BASE_FOV
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

    vm = viewmodel.new(camera, player)

    -- Initial loadout sync
    local spec = currentSpec()
    if spec then
        vm:setWeapon(spec)
    end

    networking.onClient(constants.REMOTES.LoadoutChanged, onLoadout)
    networking.onClient(constants.REMOTES.AmmoChanged, onAmmo)
    networking.onClient(constants.REMOTES.Tracer, function(payload: any)
        local p = payload :: { player: string, origin: Vector3, endPos: Vector3, weaponId: string }
        if p.player == player.Name then
            return
        end
        local color = Color3.fromRGB(255, 220, 120)
        if p.weaponId == "raygun" then
            color = Color3.fromRGB(140, 230, 255)
        end
        spawnTracer(p.origin, p.endPos, color)
    end)

    setupInput()

    RunService.RenderStepped:Connect(function(dt: number)
        isDowned = player:GetAttribute(constants.ATTRIBUTES.Downed) == true

        if firing and not isDowned then
            local spec = currentSpec()
            if spec and spec.kind == "gun" then
                fire()
            end
        end

        if vm then
            vm:setDowned(isDowned)
            vm:addSway(lastMouseDelta)
            vm:update(dt)
        end
        lastMouseDelta = Vector2.new(0, 0)

        spread = mathutils.damp(spread, aiming and 0.004 or 0, 8, dt)
        recoilPitch = mathutils.damp(recoilPitch, 0, 9, dt)
        recoilYaw = mathutils.damp(recoilYaw, 0, 9, dt)
        fovPunch = mathutils.damp(fovPunch, 0, 6, dt)

        updateCamera(dt)
    end)

    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        local spec = currentSpec()
        if spec and vm then
            vm:setWeapon(spec)
        end
    end)
end

return combatclient
