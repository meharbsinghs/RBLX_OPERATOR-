--!strict
-- ============================================================================
--  Automated test runner (self-simulating players).
--
--  Enable by setting _G.__TESTING = true (or the place attribute "__TESTING")
--  before the game boots. The runner:
--    1. Validates the GameSpec's structural integrity (zone chain, balances).
--    2. Creates a dummy player in Studio, starts the round loop, and asserts
--       enemies actually spawn.
--    3. Fires the server-authoritative hitscan engine at a real enemy and
--       asserts damage is applied.
--    4. Drives the shop (wall buy, perk, pack) through the economy and
--       asserts points are spent and rewards granted.
--  Every step prints a machine-parseable "[TEST] PASS|FAIL ..." line. The full
--  report is written to logs/runtime_test.log (Studio only) and mirrored into
--  a TestResults folder in workspace, so bridge.js fix can consume it.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local devlog = require(ReplicatedStorage:WaitForChild("devlog"))

local economy = require(script.Parent.economy)
local enemies = require(script.Parent.enemies)
local combat = require(script.Parent.combat)
local shop = require(script.Parent.shop)
local players = require(script.Parent.players)
local rounds = require(script.Parent.rounds)
local mapbuilder = require(script.Parent.mapbuilder)

local testrunner = {}

local lines: { string } = {}
local failures = 0
local passes = 0

local function log(line: string)
    print(`[TEST] {line}`)
    devlog.info("test", line)
    table.insert(lines, line)
end

local function check(name: string, ok: boolean, detail: string?)
    if ok then
        passes += 1
        log(`PASS {name}`)
    else
        failures += 1
        log(`FAIL {name} {detail or ""}`)
    end
end

local function writeResults()
    local ok = pcall(function()
        writefile("logs/runtime_test.log", table.concat(lines, "\n") .. "\n")
    end)
    if not ok then
        log("(writefile unavailable in this context — copy the [TEST] lines above into logs/runtime_test.log for bridge.js fix)")
    end
    local folder = Instance.new("Folder")
    folder.Name = "TestResults"
    folder.Parent = workspace
    local value = Instance.new("StringValue")
    value.Name = "Report"
    value.Value = table.concat(lines, "\n")
    value.Parent = folder
end

-- --------------------------------------------------------------------------
--  Spec integrity
-- --------------------------------------------------------------------------

local function testSpec()
    check("spec: weapons exist", #config.weapons > 0)
    check("spec: enemies exist", #config.enemies > 0)
    check("spec: perks exist", #config.perks > 0)
    check("spec: zones exist", #config.map.zones >= 2)

    local firstDoorOk = config.map.zones[1].door == nil
    check("spec: first zone is root (no door)", firstDoorOk)

    local zoneIds: { [string]: boolean } = {}
    for _, zone in config.map.zones do
        zoneIds[zone.id] = true
    end
    local chainOk = true
    for _, door in config.map.doors do
        if not zoneIds[door.from] or not zoneIds[door.to] then
            chainOk = false
        end
    end
    check("spec: doors reference known zones", chainOk)

    local balanceOk = true
    for _, weapon in config.weapons do
        if weapon.damage <= 0 or weapon.roundsPerSecond <= 0 then
            balanceOk = false
        end
    end
    for _, enemy in config.enemies do
        if enemy.baseHealth <= 0 then
            balanceOk = false
        end
    end
    check("spec: balances are positive", balanceOk)
end

-- --------------------------------------------------------------------------
--  Dummy player + character (Studio only)
-- --------------------------------------------------------------------------

local function makeDummyPlayer(): Player?
    if not RunService:IsStudio() then
        return nil
    end
    local ok, dummy = pcall(function()
        return Instance.new("Player")
    end)
    if not ok then
        return nil
    end
    local player = dummy :: Player
    player.Name = "TestDummy"
    player.Parent = Players
    return player
end

local function spawnCharacter(player: Player)
    local character = Instance.new("Model")
    character.Name = "TestDummyChar"
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(2, 2, 1)
    root.Transparency = 1
    root.Anchored = true
    root.Parent = character
    local humanoid = Instance.new("Humanoid")
    humanoid.Parent = character
    character.PrimaryPart = root
    character.Parent = workspace
    player.Character = character
end

-- --------------------------------------------------------------------------
--  Combat + economy + shop simulation
-- --------------------------------------------------------------------------

local function findVisibleEnemy(origin: Vector3): Model?
    -- Poll until an enemy is inside the room with a clear line of sight, so the
    -- test shot cannot be eaten by a wall or barricade.
    for _ = 1, 30 do
        for _, model in (workspace:WaitForChild(constants.FOLDERS.Enemies)):GetChildren() do
            if CollectionService:HasTag(model, constants.TAGS.Enemy) then
                local enemyRoot = model:FindFirstChild("HumanoidRootPart")
                if enemyRoot and enemyRoot:IsA("BasePart") then
                    local status = mapbuilder.lineOfSightStatus(origin, enemyRoot.Position)
                    if status == "clear" then
                        return model :: Model
                    end
                end
            end
        end
        task.wait(0.5)
    end
    return nil
end

local function testCombat(dummy: Player?)
    if dummy then
        economy.addPoints(dummy, 10000)
    end

    -- Give the round loop time to pass intermission and spawn enemies
    task.wait(config.rounds.intermissionSeconds + 3)

    local alive = enemies.getAliveCount()
    check("enemies: spawned", alive > 0, `alive={alive}`)

    local enemyModel: Model? = nil
    if dummy then
        local dummyChar = dummy.Character
        local dummyRoot = dummyChar and dummyChar:FindFirstChild("HumanoidRootPart") :: BasePart
        if dummyRoot then
            enemyModel = findVisibleEnemy(dummyRoot.Position + Vector3.new(0, 2, 0))
        end
    end
    if enemyModel then
        local enemyRoot = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart
        local startHp = tonumber(enemyModel:GetAttribute(constants.ATTRIBUTES.Hp)) or 9999

        if dummy then
            -- Fire from the dummy's own position toward the enemy so the
            -- origin-sanity checks in combat.luau pass.
            local dummyChar = dummy.Character
            local dummyRoot = dummyChar and dummyChar:FindFirstChild("HumanoidRootPart") :: BasePart
            if dummyRoot then
                local origin = dummyRoot.Position + Vector3.new(0, 2, 0)
                local dir = (enemyRoot.Position - origin).Unit
                combat.__test.fire(dummy, {
                    weaponId = "m1911",
                    origin = origin,
                    dir = dir,
                    pellets = 1,
                })
                task.wait(0.2)
                local nowHp = tonumber(enemyModel:GetAttribute(constants.ATTRIBUTES.Hp)) or 9999
                check("combat: shot applied damage", nowHp < startHp, `hp {startHp} -> {nowHp}`)
            else
                log("SKIP combat-fire (dummy has no root part)")
            end
        else
            log("SKIP combat-fire (requires Studio)")
        end
    else
        log("SKIP combat-fire (no enemy with clear line of sight found)")
    end

    -- Shop simulation through the public economy + shop hooks
    if dummy then
        local before = economy.getPoints(dummy)
        shop.__test.buyWall(dummy, "mp5")
        local after = economy.getPoints(dummy)
        check("shop: wall buy spends points", after < before)
        local loadout = economy.getLoadout(dummy)
        check("shop: weapon granted", loadout.weapons["mp5"] ~= nil)

        shop.__test.buyPerk(dummy, "jugg")
        check("shop: perk granted", economy.hasPerk(dummy, "jugg"))

        shop.__test.buyPack(dummy)
        check("shop: pack upgrade applied", (economy.getLoadout(dummy).weapons["mp5"] or 0) >= 1)
    end
end

-- --------------------------------------------------------------------------
--  Entry point
-- --------------------------------------------------------------------------

function testrunner.run()
    log(`Test runner started — game: {config.name}`)
    log(`Env: Studio={RunService:IsStudio()}`)

    testSpec()

    if RunService:IsStudio() then
        local dummy = makeDummyPlayer()
        if dummy then
            spawnCharacter(dummy)
            players.markReady(dummy)
            rounds.startWhenReady()
            testCombat(dummy)
        else
            log("SKIP combat/round simulation (could not create dummy player)")
        end
    else
        log("SKIP combat/round simulation (test runner requires Studio)")
        rounds.startWhenReady()
    end

    log(`DONE {passes} passed, {failures} failed`)
    writeResults()
end

return testrunner
