--!strict
-- ============================================================================
--  Enemy manager: spawning, round scaling, AI (pathing, barricades, attacks),
--  damage and death. Fully generic — driven by the GameSpec's enemy table.
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local types = require(ReplicatedStorage:WaitForChild("types"))
local mathutils = require(ReplicatedStorage:WaitForChild("mathutils"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local pack = require(ReplicatedStorage:WaitForChild("pack"))

local mapbuilder = require(script.Parent.mapbuilder)
local players = require(script.Parent.players)
local proceduralassets = require(script.Parent.proceduralassets)
local devlog = require(ReplicatedStorage:WaitForChild("devlog"))

local enemies = {}

type EnemyState = {
    id: string,
    typeId: string,
    model: Model,
    humanoid: Humanoid,
    root: BasePart,
    spec: types.EnemySpec,
    hp: number,
    maxHp: number,
    lastAttack: number,
    repathAt: number,
    waypoints: { Vector3 }?,
    waypointIndex: number,
    target: Player?,
    wanderPos: Vector3?,
}

local enemyFolder: Folder? = nil
local alive: { [string]: EnemyState } = {}
local specsById: { [string]: types.EnemySpec } = {}
local windows: { any } = {}
local idCounter = 0
local lastTick = 0
local killCallback: ((typeId: string) -> ())? = nil
-- The enemy id flagged isBoss in the GameSpec. Derived games name their boss
-- anything — never hardcode a type id.
local bossTypeId: string? = nil

-- Compressed enemy-state channel: integer-keyed batch broadcast at a fixed
-- rate (config.net.enemyBatchHz). One remote instead of per-enemy chatter;
-- clients smooth the numbers locally (see client/entities.luau).
type BatchEntry = { x: number, y: number, z: number, hp: number, mx: number }
local encoder = pack.makeEncoder()
local enemyBatch: { [number]: BatchEntry } = {}
-- Enemies killed since the last batch broadcast. Flushed alongside the batch
-- so clients spawn death VFX (blood + ragdolls) with zero extra remotes.
local deathEvents: { { x: number, y: number, z: number, typeId: string } } = {}

local function getSpec(typeId: string): types.EnemySpec?
    return specsById[typeId]
end

-- --------------------------------------------------------------------------
--  Composition
-- --------------------------------------------------------------------------

local function enemyCountForRound(round: number, playerCount: number): number
    local r = config.rounds
    local count = r.baseEnemies + (round - 1) * r.enemiesPerRound
    count = math.min(count, r.maxEnemies)
    local scale = 1 + (playerCount - 1) * 0.5
    scale = math.min(scale, r.playerScaleCap)
    return math.max(1, math.round(count * scale))
end

local function pickType(round: number): string
    local candidates: { string } = {}
    for _, spec in config.enemies do
        if not spec.isBoss and spec.unlockRound <= round then
            for _ = 1, spec.spawnWeight do
                table.insert(candidates, spec.id)
            end
        end
    end
    if #candidates == 0 then
        return config.enemies[1].id
    end
    return candidates[math.random(#candidates)]
end

local function buildQueue(round: number, playerCount: number): { string }
    local queue: { string } = {}
    local count = enemyCountForRound(round, playerCount)
    if round % config.rounds.bossEvery == 0 and bossTypeId then
        local bossCount = math.max(1, math.floor(round / config.rounds.bossEvery))
        devlog.info("enemies", `Boss round {round} — spawning {bossCount} {bossTypeId}.`)
        for _ = 1, bossCount do
            table.insert(queue, bossTypeId)
        end
        count = math.max(4, math.floor(count * 0.6))
    end
    for _ = 1, count do
        table.insert(queue, pickType(round))
    end
    return mathutils.shuffle(queue)
end

-- --------------------------------------------------------------------------
--  Spawning
-- --------------------------------------------------------------------------

local function pickActiveWindow(): { position: Vector3, inner: Vector3 }?
    local active = mapbuilder.getActiveWindows()
    if #active == 0 then
        return nil
    end
    local window = active[math.random(#active)]
    return { position = window.outer, inner = window.inner }
end

local function spawnEnemy(typeId: string, round: number)
    local spec = getSpec(typeId)
    if not spec then
        return
    end
    local window = pickActiveWindow()
    if not window then
        return
    end
    idCounter += 1
    local id = "e" .. idCounter

    local hp = spec.baseHealth + spec.healthPerRound * (round - 1)
    if spec.isBoss then
        hp = spec.baseHealth + spec.healthPerRound * math.max(1, math.floor(round / config.rounds.bossEvery) - 1)
    end

    local built = proceduralassets.spawnEnemyModel(spec, window.position, enemyFolder :: Folder)
    local humanoid = built.humanoid
    humanoid.MaxHealth = hp
    humanoid.Health = hp
    humanoid.WalkSpeed = spec.speed

    local state: EnemyState = {
        id = id,
        typeId = typeId,
        model = built.model,
        humanoid = humanoid,
        root = built.root,
        spec = spec,
        hp = hp,
        maxHp = hp,
        lastAttack = 0,
        repathAt = 0,
        waypoints = nil,
        waypointIndex = 1,
        target = nil,
        wanderPos = window.inner,
    }

    built.model:SetAttribute(constants.ATTRIBUTES.EnemyId, id)
    built.model:SetAttribute(constants.ATTRIBUTES.EnemyType, typeId)
    built.model:SetAttribute(constants.ATTRIBUTES.MaxHp, hp)
    built.model:SetAttribute(constants.ATTRIBUTES.Hp, hp)
    CollectionService:AddTag(built.model, constants.TAGS.Enemy)

    local rootPos = built.root.Position
    enemyBatch[encoder.encode(id)] = { x = rootPos.X, y = rootPos.Y, z = rootPos.Z, hp = hp, mx = hp }
    alive[id] = state
end

function enemies.startRound(round: number, playerCount: number)
    local queue = buildQueue(round, playerCount)
    task.spawn(function()
        while #queue > 0 do
            for _ = 1, 4 do
                if #queue == 0 then
                    break
                end
                spawnEnemy(table.remove(queue, 1), round)
                task.wait(0.12)
            end
            if #queue > 0 then
                task.wait(0.7)
            end
        end
    end)
end

function enemies.getAliveCount(): number
    local count = 0
    for _ in alive do
        count += 1
    end
    return count
end

function enemies.clearAll()
    for id in alive do
        local state = alive[id]
        if state.model.Parent then
            state.model:Destroy()
        end
        alive[id] = nil
    end
    enemyBatch = {}
end

function enemies.setKillCallback(callback: (typeId: string) -> ())
    killCallback = callback
end

-- --------------------------------------------------------------------------
--  Damage
-- --------------------------------------------------------------------------

function enemies.damageEnemy(
    enemyId: string,
    amount: number,
    hitPartName: string,
    shooter: Player
): { killed: boolean, typeId: string, headshot: boolean }
    local state = alive[enemyId]
    if not state then
        return { killed = false, typeId = "", headshot = false }
    end
    local headshot = hitPartName == "Head"
    state.hp = math.max(0, state.hp - amount)
    local batchEntry = enemyBatch[encoder.encode(enemyId)]
    if batchEntry then
        batchEntry.hp = state.hp
    end
    state.model:SetAttribute(constants.ATTRIBUTES.Hp, state.hp)

    -- Hit reaction: white flash + small knock
    if state.hp > 0 then
        local torso = state.model:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then
            local original = torso.Color
            torso.Color = Color3.fromRGB(255, 255, 255)
            task.delay(0.06, function()
                if state.model.Parent then
                    torso.Color = original
                end
            end)
        end
        state.humanoid:MoveTo(state.root.Position - (state.humanoid.MoveDirection * 1))
        return { killed = false, typeId = state.typeId, headshot = headshot }
    end

    -- Kill
    alive[enemyId] = nil
    enemyBatch[encoder.encode(enemyId)] = nil
    local rootPos = state.root.Position
    table.insert(deathEvents, { x = rootPos.X, y = rootPos.Y, z = rootPos.Z, typeId = state.typeId })
    if state.model.Parent then
        state.model:Destroy()
    end
    if killCallback then
        killCallback(state.typeId)
    end
    return { killed = true, typeId = state.typeId, headshot = headshot }
end

-- --------------------------------------------------------------------------
--  AI tick
-- --------------------------------------------------------------------------

local function nearestAlivePlayer(position: Vector3): (Player, number)?
    local best: Player? = nil
    local bestDist = math.huge
    for _, player in Players:GetPlayers() do
        if not players.isDowned(player) then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                local dist = (root.Position - position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = player
                end
            end
        end
    end
    if best then
        return best, bestDist
    end
    return nil
end

local function findBarricadeInRange(position: Vector3, range: number): string?
    for _, window in windows do
        if window.active and window.hp > 0 then
            local dist = (window.position - position).Magnitude
            if dist <= range then
                return window.id
            end
        end
    end
    return nil
end

local function repath(state: EnemyState)
    local target = state.target
    if not target or not target.Character then
        return
    end
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end
    local path = mapbuilder.getPath(state.root.Position, targetRoot.Position)
    if path then
        state.waypoints = path
        state.waypointIndex = 2
    end
end

local function tickEnemy(state: EnemyState, now: number)
    if not state.model.Parent then
        return
    end

    local target, dist = nearestAlivePlayer(state.root.Position)
    state.target = target

    if not target then
        -- No targets: drift back toward the last window
        if state.wanderPos then
            state.humanoid:MoveTo(state.wanderPos)
        end
        return
    end

    -- Attack when in melee range
    local attackRange = 5 * state.spec.scale
    if dist <= attackRange then
        state.humanoid:MoveTo(state.root.Position)
        if now - state.lastAttack >= 1 / state.spec.attackRate then
            state.lastAttack = now
            players.takePlayerDamage(target, state.spec.damage, state.model)
        end
        return
    end

    -- Barricade blocking the way? Attack it.
    local barricadeId = findBarricadeInRange(state.root.Position, 5)
    if barricadeId then
        state.humanoid:MoveTo(state.root.Position)
        if now - state.lastAttack >= 1 / state.spec.attackRate then
            state.lastAttack = now
            mapbuilder.damageBarricade(barricadeId, state.spec.damage)
        end
        return
    end

    -- Movement
    if now >= state.repathAt then
        state.repathAt = now + 2
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local status = mapbuilder.lineOfSightStatus(state.root.Position, targetRoot.Position)
            if status == "clear" then
                state.humanoid:MoveTo(targetRoot.Position)
                state.waypoints = nil
            else
                repath(state)
            end
        end
    end

    local waypoints = state.waypoints
    if waypoints and state.waypointIndex <= #waypoints then
        local waypoint = waypoints[state.waypointIndex]
        state.humanoid:MoveTo(waypoint)
        local reached = state.humanoid.MoveToFinished:Wait(1)
        if reached then
            state.waypointIndex += 1
        end
    end
end

function enemies.init(parent: Folder)
    enemyFolder = parent
    for _, spec in config.enemies do
        specsById[spec.id] = spec
        if spec.isBoss then
            bossTypeId = spec.id
        end
    end
    for _, window in mapbuilder.getProps().windows do
        table.insert(windows, window)
    end

    RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastTick < 0.2 then
            return
        end
        lastTick = now
        local step = 0
        for id, state in alive do
            step += 1
            if step % 4 == 0 then
                task.spawn(tickEnemy, state, now)
            end
        end
    end)

    -- Compressed batched broadcast to every client (one remote, integer keys)
    local hz = (config.net and config.net.enemyBatchHz) or 5
    task.spawn(function()
        while true do
            task.wait(1 / hz)
            for id, state in alive do
                local entry = enemyBatch[encoder.encode(id)]
                if entry and state.root then
                    local pos = state.root.Position
                    entry.x = pos.X
                    entry.y = pos.Y
                    entry.z = pos.Z
                    entry.hp = state.hp
                end
            end
            networking.fireAllClients(constants.REMOTES.EnemyStateBatch, {
                tick = os.clock(),
                count = enemies.getAliveCount(),
                ents = enemyBatch,
                deaths = deathEvents,
            })
            deathEvents = {}
        end
    end)

    humanoidDiedCleanup()
end

-- Cleanup if an enemy dies from physics (fell off, etc.)
local function humanoidDiedCleanup()
    task.spawn(function()
        while true do
            task.wait(2)
            for id, state in alive do
                if not state.model.Parent then
                    if state.root.Parent then
                        local pos = state.root.Position
                        table.insert(deathEvents, { x = pos.X, y = pos.Y, z = pos.Z, typeId = state.typeId })
                    end
                    alive[id] = nil
                end
            end
        end
    end)
end

return enemies
