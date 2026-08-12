--!strict
-- ============================================================================
--  Hitscan combat engine (server-authoritative).
--
--  Client sends { weaponId, origin, dir } -> server validates (weapon owned,
--  fire rate, ammo, origin sanity, direction sanity) -> server raycasts ->
--  applies damage with headshot multipliers and pack tiers -> awards points ->
--  broadcasts tracers and hit confirmations. No client can cheat damage.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local types = require(ReplicatedStorage:WaitForChild("types"))
local mathutils = require(ReplicatedStorage:WaitForChild("mathutils"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))

local enemies = require(script.Parent.enemies)
local players = require(script.Parent.players)
local economy = require(script.Parent.economy)
local anticheat = require(script.Parent.anticheat)
local audio = require(script.Parent.audio)

local combat = {}

local specsById: { [string]: types.WeaponSpec } = {}
local lastShot: { [Player]: number } = {}
local lastMelee: { [Player]: number } = {}
local reloadUntil: { [Player]: number } = {}

function combat.weaponSpec(weaponId: string): types.WeaponSpec?
    return specsById[weaponId]
end

-- --------------------------------------------------------------------------
--  Init
-- --------------------------------------------------------------------------

function combat.init()
    for _, spec in config.weapons do
        specsById[spec.id] = spec
    end

    networking.onServer(constants.REMOTES.GunFired, function(player: Player, payload: any)
        handleFire(player, payload)
    end)
    networking.onServer(constants.REMOTES.ReloadRequest, function(player: Player)
        handleReload(player)
    end)
    networking.onServer(constants.REMOTES.MeleeRequest, function(player: Player, payload: any)
        handleMelee(player, payload)
    end)
end

-- --------------------------------------------------------------------------
--  Helpers
-- --------------------------------------------------------------------------

local function effectiveRPS(player: Player, spec: types.WeaponSpec): number
    local rps = spec.roundsPerSecond
    if economy.hasPerk(player, "doubletap") then
        rps *= 1.33
    end
    return rps
end

local function reloadMultiplier(player: Player): number
    if economy.hasPerk(player, "speed") then
        return 0.7
    end
    return 1
end

local function playerRoot(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function rayParamsFor(player: Player): RaycastParams
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local character = player.Character
    params.FilterDescendantsInstances = character and { character } or {}
    return params
end

local function killRewardFor(typeId: string): number
    for _, spec in config.enemies do
        if spec.id == typeId then
            return spec.points
        end
    end
    return config.points.perKill
end

local function awardKill(player: Player, typeId: string, headshot: boolean, weaponId: string)
    local reward = killRewardFor(typeId)
    if headshot then
        reward += config.points.perHeadshotBonus
    end
    economy.addPoints(player, reward)
    economy.addKill(player)
    networking.fireAllClients(constants.REMOTES.KillConfirmed, {
        typeId = typeId,
        killer = player.Name,
        headshot = headshot,
        weaponId = weaponId,
    })
end

local function validPayload(payload: any): { origin: Vector3, dir: Vector3, weaponId: string, pellets: number }?
    if type(payload) ~= "table" then
        return nil
    end
    local origin = payload.origin
    local dir = payload.dir
    local weaponId = payload.weaponId
    local pellets = payload.pellets or 1
    if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or type(weaponId) ~= "string" then
        return nil
    end
    if math.abs(dir.Magnitude - 1) > 0.1 then
        return nil
    end
    if pellets < 1 or pellets > 8 then
        return nil
    end
    return { origin = origin, dir = dir, weaponId = weaponId, pellets = pellets }
end

-- --------------------------------------------------------------------------
--  Fire
-- --------------------------------------------------------------------------

local function handleFire(player: Player, payload: any)
    if players.isDowned(player) then
        return
    end
    local valid = validPayload(payload)
    if not valid then
        return
    end
    if anticheat.isFlagged(player) then
        return
    end

    local loadout = economy.getLoadout(player)
    if loadout.equipped ~= valid.weaponId then
        return
    end
    local spec = specsById[valid.weaponId]
    if not spec or spec.kind == "melee" then
        return
    end

    -- Fire-rate validation
    local now = tick()
    if now - (lastShot[player] or 0) < 1 / effectiveRPS(player, spec) then
        return
    end
    if (reloadUntil[player] or 0) > now then
        return
    end
    lastShot[player] = now

    -- Ammo (server-authoritative)
    if not economy.consumeAmmo(player, valid.weaponId, 1) then
        return
    end

    -- Origin sanity: shots must originate near the player's own head, and the
    -- straight line from the head to the claimed origin must not cross a wall.
    local root = playerRoot(player)
    if not root then
        return
    end
    if (valid.origin - root.Position).Magnitude > 12 then
        anticheat.strike(player, "origin")
        return
    end
    if anticheat.lineBlocked(root.Position + Vector3.new(0, 2, 0), valid.origin) then
        anticheat.strike(player, "wallclip")
        return
    end

    -- Pack-a-punch tier multipliers
    local tier = loadout.weapons[valid.weaponId] or 0
    local damageMultiplier = 1
    local tierData = spec.packTiers and spec.packTiers[tier]
    if tierData then
        damageMultiplier = tierData.damageMultiplier
    end
    local baseDamage = spec.damage * damageMultiplier

    local rayParams = rayParamsFor(player)
    local hitEnemyId: string? = nil
    local hitPartName = ""
    local hitPos: Vector3? = nil
    local anyKilled = false
    local killTypeId = ""
    local killHeadshot = false
    local lastDamageDealt = 0

    for _ = 1, valid.pellets do
        local dir = mathutils.coneDirection(valid.dir, spec.spread)
        local result = workspace:Raycast(valid.origin, dir * spec.range, rayParams)
        if result then
            local model = result.Instance:FindFirstAncestorOfClass("Model")
            if model and CollectionService:HasTag(model, constants.TAGS.Enemy) then
                local enemyId = model:GetAttribute(constants.ATTRIBUTES.EnemyId)
                if type(enemyId) == "string" then
                    local damage = baseDamage
                    local isHead = result.Instance.Name == "Head"
                    if isHead then
                        damage *= spec.headshotMultiplier
                    end
                    local outcome = enemies.damageEnemy(enemyId, damage, result.Instance.Name, player)
                    if outcome.killed then
                        anyKilled = true
                        killTypeId = outcome.typeId
                        killHeadshot = outcome.headshot
                    end
                    hitEnemyId = enemyId
                    hitPartName = result.Instance.Name
                    lastDamageDealt = damage
                end
            end
            hitPos = result.Position
        else
            hitPos = valid.origin + valid.dir * spec.range
        end
    end

    -- Rewards + feedback
    audio.play("shot")
    if hitEnemyId then
        economy.addPoints(player, config.points.perHit)
        networking.fireClient(player, constants.REMOTES.HitConfirmed, {
            enemyId = hitEnemyId,
            hitPos = hitPos,
            headshot = hitPartName == "Head",
            damage = lastDamageDealt,
        })
    end
    if anyKilled then
        audio.play(killHeadshot and "headshot" or "kill")
        awardKill(player, killTypeId, killHeadshot, valid.weaponId)
    end

    networking.fireAllClients(constants.REMOTES.Tracer, {
        player = player.Name,
        origin = valid.origin,
        endPos = hitPos,
        weaponId = valid.weaponId,
    })
end

-- --------------------------------------------------------------------------
--  Reload
-- --------------------------------------------------------------------------

local function handleReload(player: Player)
    if players.isDowned(player) then
        return
    end
    local loadout = economy.getLoadout(player)
    local spec = specsById[loadout.equipped]
    if not spec or spec.kind ~= "gun" then
        return
    end
    local now = tick()
    if (reloadUntil[player] or 0) > now then
        return
    end
    local ammoState = economy.getAmmoState(player, spec.id)
    if ammoState.mag >= economy.getMagSize(player, spec.id) or ammoState.reserve <= 0 then
        return
    end
    local duration = spec.reloadTime * reloadMultiplier(player)
    reloadUntil[player] = now + duration
    networking.fireClient(player, constants.REMOTES.AmmoChanged, {
        weaponId = spec.id,
        mag = ammoState.mag,
        reserve = ammoState.reserve,
        reloading = true,
        duration = duration,
    })
    task.delay(duration, function()
        economy.finishReload(player, spec.id)
    end)
end

-- --------------------------------------------------------------------------
--  Melee
-- --------------------------------------------------------------------------

local function handleMelee(player: Player, payload: any)
    if players.isDowned(player) then
        return
    end
    local loadout = economy.getLoadout(player)
    local spec = specsById[loadout.equipped]
    if not spec or spec.kind ~= "melee" then
        return
    end
    local now = tick()
    if now - (lastMelee[player] or 0) < 1 / spec.roundsPerSecond then
        return
    end
    lastMelee[player] = now

    local root = playerRoot(player)
    if not root then
        return
    end
    local dir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
    if dir.Magnitude < 0.01 then
        dir = Vector3.new(0, 0, -1)
    end
    dir = dir.Unit
    local origin = root.Position + Vector3.new(0, 2, 0)

    local rayParams = rayParamsFor(player)
    local result = workspace:Raycast(origin, dir * spec.range, rayParams)
    local endPos = origin + dir * spec.range

    if result then
        endPos = result.Position
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        if model and CollectionService:HasTag(model, constants.TAGS.Enemy) then
            local enemyId = model:GetAttribute(constants.ATTRIBUTES.EnemyId)
            if type(enemyId) == "string" then
                local outcome = enemies.damageEnemy(enemyId, spec.damage, result.Instance.Name, player)
                if outcome.killed then
                    awardKill(player, outcome.typeId, outcome.headshot, spec.id)
                else
                    economy.addPoints(player, config.points.perHit)
                end
                networking.fireClient(player, constants.REMOTES.HitConfirmed, {
                    enemyId = enemyId,
                    hitPos = result.Position,
                    headshot = outcome.headshot,
                    damage = spec.damage,
                })
            end
        end
    end

    networking.fireAllClients(constants.REMOTES.Tracer, {
        player = player.Name,
        origin = origin,
        endPos = endPos,
        weaponId = spec.id,
    })
end

-- Test hooks (used by testrunner.luau when _G.__TESTING is enabled)
combat.__test = {
    fire = handleFire,
    reload = handleReload,
    melee = handleMelee,
}

return combat
