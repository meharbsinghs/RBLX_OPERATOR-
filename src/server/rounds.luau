--!strict
-- ============================================================================
--  Round state machine. Drives the lobby -> intermission -> spawning ->
--  combat -> roundEnd loop from the GameSpec's rounds config. Also handles
--  barricade repair, revive-on-intermission, and game over.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local types = require(ReplicatedStorage:WaitForChild("types"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))

local mapbuilder = require(script.Parent.mapbuilder)
local players = require(script.Parent.players)
local enemies = require(script.Parent.enemies)
local economy = require(script.Parent.economy)
local audio = require(script.Parent.audio)
local devlog = require(ReplicatedStorage:WaitForChild("devlog"))

local rounds = {}

local state: types.RoundState = "lobby"
local roundNumber = 0
local started = false
local winRound = (config.rounds and config.rounds.winRound) or 0

local function broadcast()
    networking.fireAllClients(constants.REMOTES.RoundState, state, {
        round = roundNumber,
        alive = enemies.getAliveCount(),
    })
end

local function endGame()
    if state == "gameOver" then
        return
    end
    state = "gameOver"
    audio.setIntensity("gameOver")
    devlog.info("rounds", "Game over — run ended.")
    enemies.clearAll()
    networking.fireAllClients(constants.REMOTES.GameOver, {
        round = roundNumber,
        kills = economy.getSessionStats().kills,
    })
end

function rounds.init()
    enemies.setKillCallback(function(_typeId: string)
        -- Combat completion is polled by the loop below.
    end)
    players.setOnAllDowned(function()
        endGame()
    end)
end

function rounds.startWhenReady()
    if started then
        return
    end
    started = true
    task.spawn(runLoop)
end

local function runLoop()
    while state ~= "gameOver" do
        roundNumber += 1

        -- Intermission: repair, revive, let players shop
        state = "intermission"
        audio.setIntensity("intermission")
        devlog.info("rounds", `Intermission — round {roundNumber} starts in {config.rounds.intermissionSeconds}s.`)
        broadcast()
        mapbuilder.repairBarricades()
        players.reviveAllDowned(0.5)
        task.wait(config.rounds.intermissionSeconds)
        if state == "gameOver" then
            break
        end

        -- Spawning + combat
        state = "spawning"
        broadcast()
        local playerCount = #players.getAlivePlayers()
        if playerCount == 0 then
            endGame()
            break
        end
        enemies.startRound(roundNumber, playerCount)
        state = "combat"
        audio.setIntensity("combat", roundNumber % config.rounds.bossEvery == 0)
        devlog.info("rounds", `Combat — round {roundNumber}, {playerCount} player(s), {enemies.getAliveCount()} enemies.`)
        broadcast()

        while enemies.getAliveCount() > 0 do
            task.wait(0.5)
            if state == "gameOver" then
                break
            end
        end
        if state == "gameOver" then
            break
        end

        -- Round complete
        economy.addPointsAll(config.points.perRound)
        economy.bumpRound(roundNumber)

        -- Extraction / objective win: rounds.winRound > 0 ends the run early.
        if winRound > 0 and roundNumber >= winRound then
            state = "gameOver"
            audio.celebrate()
            devlog.info("rounds", `Objective complete — extraction on round {roundNumber}.`)
            enemies.clearAll()
            networking.fireAllClients(constants.REMOTES.GameOver, {
                round = roundNumber,
                kills = economy.getSessionStats().kills,
                win = true,
            })
            break
        end

        state = "roundEnd"
        broadcast()
        task.wait(2)
    end
end

-- Test hook: expose the live state machine to testrunner.luau
function rounds.getStateInfo(): { state: string, round: number }
    return { state = state, round = roundNumber }
end

return rounds
