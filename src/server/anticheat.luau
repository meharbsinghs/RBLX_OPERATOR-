--!strict
-- ============================================================================
--  Server-side anti-cheat.
--
--  Physics-independent movement validation: a server heartbeat samples every
--  player's root position, flags teleports and speed hacks, and after enough
--  strikes snaps the offender back (or kicks, if the GameSpec says so). Also
--  exposes line-of-sight + origin checks so the combat engine can reject shots
--  that would have to pass through generated walls or start from impossible
--  positions. Tuning lives in config.anticheat.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))

local anticheat = {}

type Tracked = {
    lastPos: Vector3?,
    lastTime: number,
    strikes: number,
    violations: { string },
}

local tracked: { [Player]: Tracked } = {}

local enabled = (config.anticheat and config.anticheat.enabled) ~= false
local maxSpeed = (config.anticheat and config.anticheat.maxSpeed) or 55
local teleportThreshold = (config.anticheat and config.anticheat.teleportThreshold) or 30
local strikesBeforeAction = (config.anticheat and config.anticheat.strikesBeforeAction) or 3
local action = (config.anticheat and config.anticheat.action) or "teleport"

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

local function reset(player: Player)
    local state = tracked[player]
    if state then
        state.lastPos = nil
        state.lastTime = 0
        state.strikes = 0
        state.violations = {}
        player:SetAttribute(constants.ATTRIBUTES.Strikes, 0)
    end
end

local function snapBack(player: Player, position: Vector3)
    local character = player.Character
    if character then
        pcall(function()
            character:PivotTo(CFrame.new(position + Vector3.new(0, 4, 0)))
        end)
    end
end

-- Record a single violation with the configured action (teleport-back / kick).
-- `snapTo` is the position to restore when the action is "teleport" (the last
-- legit sample). When it is given, the restored position becomes the new
-- baseline so the snap-back itself is never counted as a second violation.
function anticheat.strike(player: Player, reason: string, snapTo: Vector3?)
    if not enabled then
        return
    end
    local state = tracked[player]
    if not state then
        return
    end
    state.strikes += 1
    player:SetAttribute(constants.ATTRIBUTES.Strikes, state.strikes)
    table.insert(state.violations, reason)
    if state.strikes >= strikesBeforeAction then
        state.strikes = 0
        player:SetAttribute(constants.ATTRIBUTES.Strikes, 0)
        if action == "kick" then
            player:Kick(`[RBLXOperator] Anti-cheat: repeated {reason} violations.`)
        elseif snapTo then
            snapBack(player, snapTo)
            state.lastPos = snapTo
        end
    end
end

-- Sample a movement heartbeat. Returns the violation name, if any.
function anticheat.reportMove(player: Player, position: Vector3): string?
    if not enabled then
        return nil
    end
    local state = tracked[player]
    if not state then
        return nil
    end
    local now = os.clock()
    local last = state.lastPos
    state.lastPos = position
    if not last then
        state.lastTime = now
        return nil
    end
    local dt = now - state.lastTime
    state.lastTime = now
    if dt <= 0 then
        return nil
    end
    local dist = (position - last).Magnitude
    local violation: string? = nil
    if dist > teleportThreshold and dt < 2 then
        violation = "teleport"
    elseif dist / dt > maxSpeed * 1.6 then
        violation = "speedhack"
    end
    if violation then
        anticheat.strike(player, violation, last)
        return violation
    end
    return nil
end

-- Wall-clip probe: is the straight line from A to B blocked by solid geometry?
-- The combat engine uses this to reject shots that pass through map walls.
function anticheat.lineBlocked(from: Vector3, to: Vector3): boolean
    local delta = to - from
    if delta.Magnitude < 0.5 then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter: { Instance } = {}
    for _, player in Players:GetPlayers() do
        local character = player.Character
        if character then
            table.insert(filter, character)
        end
    end
    params.FilterDescendantsInstances = filter
    local result = workspace:Raycast(from, delta, params)
    return result ~= nil and result.Instance.CanCollide == true
end

function anticheat.isFlagged(player: Player): boolean
    local state = tracked[player]
    return state ~= nil and state.strikes > 0
end

function anticheat.getViolations(player: Player): { string }
    local state = tracked[player]
    return (state and state.violations) or {}
end

function anticheat.init()
    for _, player in Players:GetPlayers() do
        tracked[player] = { lastPos = nil, lastTime = 0, strikes = 0, violations = {} }
    end
    Players.PlayerAdded:Connect(function(player: Player)
        tracked[player] = { lastPos = nil, lastTime = 0, strikes = 0, violations = {} }
        player.CharacterAdded:Connect(function()
            reset(player)
        end)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        tracked[player] = nil
    end)

    if not enabled then
        return
    end

    task.spawn(function()
        while true do
            task.wait(0.5)
            for _, player in Players:GetPlayers() do
                local root = playerRoot(player)
                if root then
                    anticheat.reportMove(player, root.Position)
                end
            end
        end
    end)
end

return anticheat
