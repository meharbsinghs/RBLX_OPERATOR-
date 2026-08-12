--!strict
-- ============================================================================
--  Player service: character setup, health + regen, downed/bleedout state,
--  teammate revives, ready state. All timings come from the GameSpec.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))

local mapbuilder = require(script.Parent.mapbuilder)
local economy = require(script.Parent.economy)

local players = {}

type PlayerState = {
    downed: boolean,
    bleedoutUntil: number,
    lastDamage: number,
    reviveProgress: { [Player]: number },
}

local states: { [Player]: PlayerState } = {}
local onAllDowned: (() -> ())? = nil

-- --------------------------------------------------------------------------
--  Setup
-- --------------------------------------------------------------------------

local function maxHealth(player: Player): number
    local hp = config.player.maxHealth
    if economy.hasPerk(player, "jugg") then
        hp += 100
    end
    return hp
end

local function walkSpeed(player: Player): number
    if economy.hasPerk(player, "stamina") then
        return 20
    end
    return 16
end

local function onCharacterAdded(player: Player, character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.MaxHealth = maxHealth(player)
    humanoid.Health = maxHealth(player)
    humanoid.WalkSpeed = walkSpeed(player)
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.Died:Connect(function()
        downPlayer(player)
    end)
    character:SetPrimaryPartCFrame(CFrame.new(mapbuilder.getSpawnPosition() + Vector3.new(0, 4, 0)))
end

local function setupPlayer(player: Player)
    player:SetAttribute(constants.ATTRIBUTES.Downed, false)
    player:SetAttribute(constants.ATTRIBUTES.Perks, "")
    player:SetAttribute(constants.ATTRIBUTES.Ready, false)
    states[player] = { downed = false, bleedoutUntil = 0, lastDamage = 0, reviveProgress = {} }
    player.CharacterAdded:Connect(function(character: Model)
        onCharacterAdded(player, character)
    end)
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

function players.init()
    for _, player in Players:GetPlayers() do
        setupPlayer(player)
    end
    Players.PlayerAdded:Connect(function(player: Player)
        setupPlayer(player)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        states[player] = nil
    end)

    networking.onServer(constants.REMOTES.ReviveRequest, function(player: Player, payload: any)
        local target = payload and payload.target or ""
        handleReviveTick(player, tostring(target))
    end)

    task.spawn(regenLoop)
end

-- --------------------------------------------------------------------------
--  Damage / downed / revive
-- --------------------------------------------------------------------------

function players.takePlayerDamage(player: Player, amount: number, _attacker: Model?)
    local state = states[player]
    if not state or state.downed then
        return
    end
    local character = player.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    humanoid:TakeDamage(amount)
    state.lastDamage = tick()
    networking.fireClient(player, constants.REMOTES.PlayerDamaged, { amount = amount })
end

local function checkAllDowned()
    if #Players:GetPlayers() == 0 then
        return
    end
    if #players.getAlivePlayers() == 0 and onAllDowned then
        onAllDowned()
    end
end

local function downPlayer(player: Player)
    local state = states[player]
    if not state or state.downed then
        return
    end
    state.downed = true
    state.bleedoutUntil = tick() + config.player.bleedoutSeconds
    player:SetAttribute(constants.ATTRIBUTES.Downed, true)

    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 4
            if humanoid.Health <= 0 then
                -- Revive the body into a downed crawl state
                humanoid.Health = math.max(1, math.floor(humanoid.MaxHealth * 0.3))
            end
        end
    end

    networking.fireAllClients(constants.REMOTES.Downed, { player = player.Name })
    checkAllDowned()
end

local function revivePlayer(player: Player, healthFraction: number)
    local state = states[player]
    if not state or not state.downed then
        return
    end
    state.downed = false
    state.reviveProgress = {}
    player:SetAttribute(constants.ATTRIBUTES.Downed, false)

    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = walkSpeed(player)
            humanoid.Health = math.max(1, math.floor(humanoid.MaxHealth * healthFraction))
        end
    end

    networking.fireAllClients(constants.REMOTES.Revived, { player = player.Name })
end

function players.reviveAllDowned(healthFraction: number)
    for _, player in Players:GetPlayers() do
        if players.isDowned(player) then
            revivePlayer(player, healthFraction)
        end
    end
end

local function handleReviveTick(healer: Player, targetName: string)
    if players.isDowned(healer) then
        return
    end
    local target = Players:FindFirstChild(targetName)
    if not target then
        return
    end
    local targetState = states[target]
    if not targetState or not targetState.downed then
        return
    end

    local healerChar = healer.Character
    local targetChar = target.Character
    local healerRoot = healerChar and healerChar:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not healerRoot or not targetRoot then
        return
    end
    if (healerRoot.Position - targetRoot.Position).Magnitude > config.player.reviveRange then
        return
    end

    local progress = (targetState.reviveProgress[healer] or 0) + 0.5
    targetState.reviveProgress[healer] = progress
    networking.fireClient(target, constants.REMOTES.RevivePrompt, {
        progress = math.clamp(progress / config.player.reviveSeconds, 0, 1),
        healer = healer.Name,
    })
    if progress >= config.player.reviveSeconds then
        targetState.reviveProgress[healer] = 0
        revivePlayer(target, 0.5)
    end
end

-- --------------------------------------------------------------------------
--  Regen
-- --------------------------------------------------------------------------

local function regenLoop()
    while true do
        task.wait(0.25)
        for _, player in Players:GetPlayers() do
            local state = states[player]
            if state and not state.downed then
                local delay = config.player.regenDelay
                local rate = config.player.regenRate
                if economy.hasPerk(player, "revive") then
                    delay *= 0.6
                    rate *= 1.5
                end
                local now = tick()
                if now - state.lastDamage >= delay then
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
                        humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + rate * 0.25)
                    end
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Queries
-- --------------------------------------------------------------------------

function players.isDowned(player: Player): boolean
    local state = states[player]
    return state ~= nil and state.downed
end

function players.getAlivePlayers(): { Player }
    local list: { Player } = {}
    for _, player in Players:GetPlayers() do
        local state = states[player]
        if state and not state.downed then
            table.insert(list, player)
        end
    end
    return list
end

function players.getNearestAlivePlayer(position: Vector3): (Player, number)?
    local best: Player? = nil
    local bestDist = math.huge
    for _, player in players.getAlivePlayers() do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then
            local dist = (root.Position - position).Magnitude
            if dist < bestDist then
                best = player
                bestDist = dist
            end
        end
    end
    if best then
        return best, bestDist
    end
    return nil
end

function players.markReady(player: Player)
    player:SetAttribute(constants.ATTRIBUTES.Ready, true)
end

function players.increaseMaxHealth(player: Player, amount: number)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.MaxHealth = humanoid.MaxHealth + amount
        humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
    end
end

function players.setOnAllDowned(callback: () -> ())
    onAllDowned = callback
end

return players
