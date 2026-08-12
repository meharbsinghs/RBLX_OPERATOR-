--!strict
-- ============================================================================
--  Server bootstrap. The engine is a set of decoupled modules; this script
--  wires them together. Everything below reads its design from the GameSpec
--  (src/shared/config.luau), so swapping that one file changes the game.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local config = require(ReplicatedStorage:WaitForChild("config"))

local mapbuilder = require(script.Parent.mapbuilder)
local economy = require(script.Parent.economy)
local players = require(script.Parent.players)
local enemies = require(script.Parent.enemies)
local rounds = require(script.Parent.rounds)
local combat = require(script.Parent.combat)
local shop = require(script.Parent.shop)
local anticheat = require(script.Parent.anticheat)
local audio = require(script.Parent.audio)
local testrunner = require(script.Parent.testrunner)

-- Runtime folders
local mapFolder = Instance.new("Folder")
mapFolder.Name = constants.FOLDERS.Map
mapFolder.Parent = workspace

local enemyFolder = Instance.new("Folder")
enemyFolder.Name = constants.FOLDERS.Enemies
enemyFolder.Parent = workspace

local fxFolder = Instance.new("Folder")
fxFolder.Name = constants.FOLDERS.FX
fxFolder.Parent = workspace

-- Build the world from the GameSpec, then start every system.
mapbuilder.build(mapFolder, enemyFolder)

enemies.init(enemyFolder)
economy.init()
players.init()
anticheat.init()
combat.init()
rounds.init()
shop.init()
audio.init()

-- Ready flow: the lobby waits for the first player to press PLAY.
networking.onServer(constants.REMOTES.PlayerReady, function(player: Player)
    players.markReady(player)
    rounds.startWhenReady()
end)

Players.PlayerRemoving:Connect(function(player: Player)
    economy.savePlayer(player)
end)

-- Automated test mode: _G.__TESTING = true (or the place attribute
-- "__TESTING") boots the self-simulating test runner.
local testing = _G.__TESTING == true or game:GetAttribute("__TESTING") == true
if testing then
    task.spawn(function()
        task.wait(1)
        testrunner.run()
    end)
end

print(`[RBLXOperator] {config.name or "Game"} online (type: {config.gameType or "wave"}).`)
