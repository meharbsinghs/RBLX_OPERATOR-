--!strict
-- ============================================================================
--  Economy: points ledger, player loadouts (weapons + tiers + ammo), perks,
--  leaderstats and DataStore persistence. The source of truth for balance.
-- ============================================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local types = require(ReplicatedStorage:WaitForChild("types"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))

local economy = {}

local points: { [Player]: number } = {}
local loadouts: { [Player]: types.PlayerLoadout } = {}
local sessionStats = { kills = 0, round = 0 }
local dataStore: DataStore? = nil
local leaderboard: OrderedDataStore? = nil
local starters: { string } = {}

-- --------------------------------------------------------------------------
--  Init
-- --------------------------------------------------------------------------

function economy.init()
    local ok, store = pcall(function()
        return DataStoreService:GetDataStore("RobloxOperator_Profile_v1")
    end)
    if ok then
        dataStore = store
        local ok2, board = pcall(function()
            return DataStoreService:GetOrderedDataStore("RobloxOperator_Leaderboard")
        end)
        if ok2 then
            leaderboard = board
        end
    end

    for _, player in Players:GetPlayers() do
        loadPlayer(player)
    end
    Players.PlayerAdded:Connect(function(player: Player)
        loadPlayer(player)
    end)

    networking.onServer(constants.REMOTES.SwitchWeapon, function(player: Player, payload: any)
        local weaponId = payload and payload.weaponId
        if type(weaponId) == "string" then
            economy.setEquipped(player, weaponId)
        end
    end)
end

local function computeStarters()
    if #starters > 0 then
        return
    end
    -- Starter kit is derived from the GameSpec: first melee + first free gun.
    for _, spec in config.weapons do
        if spec.kind == "melee" then
            table.insert(starters, spec.id)
            break
        end
    end
    for _, spec in config.weapons do
        if spec.kind == "gun" and spec.wallBuyCost == 0 then
            table.insert(starters, spec.id)
            break
        end
    end
    if #starters == 0 and #config.weapons > 0 then
        table.insert(starters, config.weapons[1].id)
    end
end

local function defaultLoadout(): types.PlayerLoadout
    computeStarters()
    local weapons: { [string]: number } = {}
    for _, id in starters do
        weapons[id] = 0
    end
    local ammo: { [string]: { mag: number, reserve: number } } = {}
    for _, spec in config.weapons do
        if spec.kind == "gun" then
            ammo[spec.id] = { mag = spec.magSize, reserve = spec.reserve }
        end
    end
    -- Prefer equipping the free gun over the melee weapon.
    local equipped = starters[1] or ""
    for _, id in starters do
        local spec = economy.weaponSpec(id)
        if spec and spec.kind == "gun" then
            equipped = id
        end
    end
    return { equipped = equipped, weapons = weapons, ammo = ammo }
end

function economy.getStarterWeaponIds(): { string }
    computeStarters()
    return starters
end

local function loadPlayer(player: Player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local starting = (config.points and config.points.starting) or 0
    local cash = Instance.new("IntValue")
    cash.Name = "Cash"
    cash.Value = starting
    cash.Parent = leaderstats

    local kills = Instance.new("IntValue")
    kills.Name = "Kills"
    kills.Value = 0
    kills.Parent = leaderstats

    local round = Instance.new("IntValue")
    round.Name = "Round"
    round.Value = 0
    round.Parent = leaderstats

    points[player] = starting
    loadouts[player] = defaultLoadout()
    broadcastLoadout(player)
    syncPoints(player)

    if dataStore then
        task.spawn(function()
            local ok, data = pcall(function()
                return dataStore:GetAsync("u" .. player.UserId)
            end)
            if ok and type(data) == "table" then
                player:SetAttribute("BestRound", data.bestRound or 0)
                player:SetAttribute("TotalKills", data.totalKills or 0)
            end
        end)
    end
end

-- --------------------------------------------------------------------------
--  Points
-- --------------------------------------------------------------------------

local function syncPoints(player: Player)
    local value = points[player] or 0
    networking.fireClient(player, constants.REMOTES.PointsChanged, { points = value })
    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        local cash = leaderstats:FindFirstChild("Cash")
        if cash then
            cash.Value = value
        end
    end
end

function economy.getPoints(player: Player): number
    return points[player] or 0
end

function economy.addPoints(player: Player, amount: number)
    points[player] = (points[player] or 0) + amount
    syncPoints(player)
end

function economy.spendPoints(player: Player, amount: number): boolean
    if (points[player] or 0) < amount then
        networking.fireClient(player, constants.REMOTES.PurchaseRejected, { reason = "Not enough points" })
        return false
    end
    points[player] = (points[player] or 0) - amount
    syncPoints(player)
    return true
end

function economy.addPointsAll(amount: number)
    for _, player in Players:GetPlayers() do
        economy.addPoints(player, amount)
    end
end

-- --------------------------------------------------------------------------
--  Perks
-- --------------------------------------------------------------------------

function economy.hasPerk(player: Player, perkId: string): boolean
    local raw = player:GetAttribute(constants.ATTRIBUTES.Perks)
    local list = tostring(raw or "")
    for _, entry in string.split(list, ",") do
        if entry == perkId then
            return true
        end
    end
    return false
end

function economy.grantPerk(player: Player, perkId: string)
    if economy.hasPerk(player, perkId) then
        return
    end
    local existing = tostring(player:GetAttribute(constants.ATTRIBUTES.Perks) or "")
    local updated = existing == "" and perkId or existing .. "," .. perkId
    player:SetAttribute(constants.ATTRIBUTES.Perks, updated)
    local perkName = perkId
    for _, spec in config.perks do
        if spec.id == perkId then
            perkName = spec.name
        end
    end
    networking.fireClient(player, constants.REMOTES.PerkGranted, { perkId = perkId, name = perkName })
end

-- --------------------------------------------------------------------------
--  Loadouts & ammo
-- --------------------------------------------------------------------------

function economy.getLoadout(player: Player): types.PlayerLoadout
    local loadout = loadouts[player]
    if not loadout then
        loadout = defaultLoadout()
        loadouts[player] = loadout
    end
    return loadout
end

function economy.weaponSpec(weaponId: string): types.WeaponSpec?
    for _, spec in config.weapons do
        if spec.id == weaponId then
            return spec
        end
    end
    return nil
end

local function broadcastLoadout(player: Player)
    local loadout = economy.getLoadout(player)
    networking.fireClient(player, constants.REMOTES.LoadoutChanged, {
        equipped = loadout.equipped,
        weapons = loadout.weapons,
        ammo = loadout.ammo,
    })
end

local function syncAmmo(player: Player, weaponId: string)
    local loadout = economy.getLoadout(player)
    local ammo = loadout.ammo[weaponId]
    if ammo then
        networking.fireClient(player, constants.REMOTES.AmmoChanged, {
            weaponId = weaponId,
            mag = ammo.mag,
            reserve = ammo.reserve,
            reloading = false,
            duration = 0,
        })
    end
end

function economy.getMagSize(player: Player, weaponId: string): number
    local spec = economy.weaponSpec(weaponId)
    if not spec then
        return 0
    end
    local tier = economy.getLoadout(player).weapons[weaponId] or 0
    local tierData = spec.packTiers and spec.packTiers[tier]
    if tierData then
        return math.max(1, math.round(spec.magSize * tierData.magMultiplier))
    end
    return spec.magSize
end

function economy.getAmmoState(player: Player, weaponId: string): { mag: number, reserve: number }
    local loadout = economy.getLoadout(player)
    local ammo = loadout.ammo[weaponId]
    if not ammo then
        ammo = { mag = 0, reserve = 0 }
        loadout.ammo[weaponId] = ammo
    end
    return ammo
end

function economy.consumeAmmo(player: Player, weaponId: string, count: number): boolean
    local ammo = economy.getAmmoState(player, weaponId)
    if ammo.mag < count then
        return false
    end
    ammo.mag -= count
    syncAmmo(player, weaponId)
    return true
end

function economy.finishReload(player: Player, weaponId: string)
    local spec = economy.weaponSpec(weaponId)
    if not spec then
        return
    end
    local ammo = economy.getAmmoState(player, weaponId)
    local magSize = economy.getMagSize(player, weaponId)
    local needed = magSize - ammo.mag
    local taken = math.min(needed, ammo.reserve)
    ammo.mag += taken
    ammo.reserve -= taken
    syncAmmo(player, weaponId)
end

function economy.buyAmmo(player: Player, weaponId: string)
    local spec = economy.weaponSpec(weaponId)
    if not spec then
        return
    end
    local ammo = economy.getAmmoState(player, weaponId)
    ammo.reserve = spec.reserve
    syncAmmo(player, weaponId)
end

function economy.setEquipped(player: Player, weaponId: string)
    local loadout = economy.getLoadout(player)
    if loadout.weapons[weaponId] == nil then
        return
    end
    loadout.equipped = weaponId
    broadcastLoadout(player)
end

function economy.grantWeapon(player: Player, weaponId: string)
    local spec = economy.weaponSpec(weaponId)
    if not spec then
        return
    end
    local loadout = economy.getLoadout(player)
    if loadout.weapons[weaponId] ~= nil then
        -- Already owned: refill ammo
        loadout.ammo[weaponId] = { mag = economy.getMagSize(player, weaponId), reserve = spec.reserve }
    else
        loadout.weapons[weaponId] = 0
        loadout.ammo[weaponId] = { mag = spec.magSize, reserve = spec.reserve }
    end
    broadcastLoadout(player)
    syncAmmo(player, weaponId)
end

function economy.upgradeEquipped(player: Player): number?
    local loadout = economy.getLoadout(player)
    local weaponId = loadout.equipped
    local spec = economy.weaponSpec(weaponId)
    if not spec or spec.kind ~= "gun" then
        return nil
    end
    local tier = loadout.weapons[weaponId] or 0
    if not spec.packTiers or tier >= #spec.packTiers then
        return nil
    end
    loadout.weapons[weaponId] = tier + 1
    local ammo = loadout.ammo[weaponId]
    if ammo then
        ammo.mag = economy.getMagSize(player, weaponId)
    end
    broadcastLoadout(player)
    syncAmmo(player, weaponId)
    return tier + 1
end

-- --------------------------------------------------------------------------
--  Stats & persistence
-- --------------------------------------------------------------------------

function economy.addKill(player: Player)
    sessionStats.kills += 1
    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        local kills = leaderstats:FindFirstChild("Kills")
        if kills then
            kills.Value = kills.Value + 1
        end
    end
end

function economy.bumpRound(round: number)
    sessionStats.round = math.max(sessionStats.round, round)
    for _, player in Players:GetPlayers() do
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local value = leaderstats:FindFirstChild("Round")
            if value then
                value.Value = round
            end
        end
    end
end

function economy.getSessionStats(): { kills: number, round: number }
    return sessionStats
end

function economy.savePlayer(player: Player)
    local bestRound = tonumber(player:GetAttribute("BestRound")) or 0
    local totalKills = tonumber(player:GetAttribute("TotalKills")) or 0
    bestRound = math.max(bestRound, sessionStats.round)
    if not dataStore then
        return
    end
    local userId = player.UserId
    task.spawn(function()
        local ok = pcall(function()
            dataStore:SetAsync("u" .. userId, { bestRound = bestRound, totalKills = totalKills })
        end)
        if ok and leaderboard and bestRound > 0 then
            pcall(function()
                leaderboard:SetAsync("u" .. userId, bestRound)
            end)
        end
    end)
end

return economy
