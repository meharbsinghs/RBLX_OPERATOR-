--!strict
-- ============================================================================
--  Shop: doors, wall buys (weapon or ammo), perk machines, pack-a-punch and
--  the mystery box. Every price and reward comes from the GameSpec.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))

local mapbuilder = require(script.Parent.mapbuilder)
local economy = require(script.Parent.economy)
local players = require(script.Parent.players)
local audio = require(script.Parent.audio)
local devlog = require(ReplicatedStorage:WaitForChild("devlog"))

local shop = {}

local function toast(player: Player, text: string, tone: string)
    networking.fireClient(player, constants.REMOTES.PurchaseToast, { text = text, tone = tone })
end

-- --------------------------------------------------------------------------
--  Purchases
-- --------------------------------------------------------------------------

local function buyDoor(player: Player, doorId: string)
    local door = mapbuilder.getProps().doors[doorId]
    if not door or door.open then
        return
    end
    if economy.spendPoints(player, door.cost) then
        mapbuilder.openDoor(doorId)
        audio.play("door")
        devlog.info("shop", `${player.Name} opened ${door.name}.`)
        toast(player, `Opened ${door.name}`, "accent")
    end
end

local function buyWall(player: Player, weaponId: string)
    local spec = economy.weaponSpec(weaponId)
    if not spec then
        return
    end
    local loadout = economy.getLoadout(player)
    if loadout.weapons[weaponId] ~= nil then
        if economy.spendPoints(player, spec.ammoCost) then
            economy.buyAmmo(player, weaponId)
            toast(player, `${spec.name} ammo refilled`, "success")
        end
    else
        if economy.spendPoints(player, spec.wallBuyCost) then
            economy.grantWeapon(player, weaponId)
            economy.setEquipped(player, weaponId)
            toast(player, `Bought ${spec.name}`, "success")
        end
    end
end

local function buyPerk(player: Player, perkId: string)
    if economy.hasPerk(player, perkId) then
        toast(player, "Perk already owned", "danger")
        return
    end
    local perk = nil
    for _, candidate in config.perks do
        if candidate.id == perkId then
            perk = candidate
        end
    end
    if not perk then
        return
    end
    if economy.spendPoints(player, perk.cost) then
        economy.grantPerk(player, perkId)
        audio.play("perk")
        devlog.info("shop", `${player.Name} bought ${perk.name}.`)
        if perkId == "jugg" then
            players.increaseMaxHealth(player, 100)
        elseif perkId == "stamina" then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = 20
            end
        end
        toast(player, `Perk acquired: ${perk.name}`, "success")
    end
end

local function buyPack(player: Player)
    if economy.spendPoints(player, config.packCost) then
        audio.play("pack")
        local loadout = economy.getLoadout(player)
        local weaponId = loadout.equipped
        local tier = economy.upgradeEquipped(player)
        if tier then
            local spec = economy.weaponSpec(weaponId)
            toast(player, `${spec and spec.name or weaponId} upgraded → tier ${tier}`, "accent")
        else
            toast(player, "Weapon is fully upgraded", "danger")
        end
    end
end

local function buyRepair(player: Player, zoneId: string)
    local zone = nil
    for _, rz in mapbuilder.getProps().repairZones do
        if rz.id == zoneId then
            zone = rz
        end
    end
    if not zone then
        return
    end
    -- Don't charge players when every barricade is already at full health.
    local needsRepair = false
    for _, window in mapbuilder.getActiveWindows() do
        if window.hp < window.maxHp then
            needsRepair = true
        end
    end
    if not needsRepair then
        toast(player, "Barricades are already repaired", "accent")
        return
    end
    if economy.spendPoints(player, zone.cost) then
        mapbuilder.repairBarricades()
        toast(player, "Barricades repaired", "success")
    end
end

local function spinBox(player: Player)
    if economy.spendPoints(player, config.mysteryBoxCost) then
        devlog.info("shop", `${player.Name} spun the mystery box.`)
        local starters: { [string]: boolean } = {}
        for _, id in economy.getStarterWeaponIds() do
            starters[id] = true
        end
        local pool: { string } = {}
        for _, spec in config.weapons do
            if spec.kind == "gun" and not starters[spec.id] then
                table.insert(pool, spec.id)
            end
        end
        if #pool == 0 then
            toast(player, "No box weapons in this game", "danger")
            return
        end

        local finalWeapon = pool[math.random(#pool)]
        local sequence: { string } = {}
        for _ = 1, 5 do
            table.insert(sequence, pool[math.random(#pool)])
        end

        networking.fireClient(player, constants.REMOTES.BoxRoll, {
            sequence = sequence,
            final = finalWeapon,
        })
        audio.play("box")
        task.delay(3.2, function()
            economy.grantWeapon(player, finalWeapon)
            local spec = economy.weaponSpec(finalWeapon)
            toast(player, `Mystery Box gave you: ${spec and spec.name or finalWeapon}`, "accent")
        end)
    end
end

-- --------------------------------------------------------------------------
--  Init — attach all prompts
-- --------------------------------------------------------------------------

function shop.init()
    local props = mapbuilder.getProps()

    for _, door in props.doors do
        door.prompt.Triggered:Connect(function(player: Player)
            buyDoor(player, door.id)
        end)
    end

    for _, wb in props.wallBuys do
        wb.prompt.Triggered:Connect(function(player: Player)
            buyWall(player, wb.weaponId)
        end)
    end

    for _, station in props.perkStations do
        station.prompt.Triggered:Connect(function(player: Player)
            buyPerk(player, station.perkId)
        end)
    end

    if props.pack then
        props.pack.prompt.Triggered:Connect(function(player: Player)
            buyPack(player)
        end)
    end

    for _, spot in props.boxSpots do
        spot.prompt.Triggered:Connect(function(player: Player)
            spinBox(player)
        end)
    end

    for _, rz in props.repairZones do
        rz.prompt.Triggered:Connect(function(player: Player)
            buyRepair(player, rz.id)
        end)
    end
end

-- Test hooks (used by testrunner.luau when _G.__TESTING is enabled)
shop.__test = {
    buyWall = buyWall,
    buyPerk = buyPerk,
    buyDoor = buyDoor,
    buyPack = buyPack,
    spinBox = spinBox,
    buyRepair = buyRepair,
}

return shop
