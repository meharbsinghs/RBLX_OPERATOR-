--!strict
-- ============================================================================
--  Dev log — a single structured channel for every meaningful engine event.
--
--  Server calls devlog.info/warn/err(tag, message). Each line is:
--    - printed to the Studio Output window (server console), and
--    - broadcast to all clients on the DevLog remote, where the Operator
--      Craft plugin (and any debugging client) renders it live.
--
--  Why it exists: "get it perfect for playtesting" starts with *seeing* what
--  the systems are doing. Rounds, spawning, economy, shops and the test
--  runner all speak here, so a playtest session is fully observable.
-- ============================================================================

local RunService = game:GetService("RunService")
local constants = require(script.Parent.constants)
local networking = require(script.Parent.networking)

local devlog = {}

local LEVELS = { info = 1, warn = 2, err = 3 }

local function emit(level: string, tag: string, message: string)
    local line = string.format("[%s] %s: %s", level:upper(), tag, message)
    print(line)
    if RunService:IsServer() then
        task.spawn(function()
            pcall(function()
                networking.fireAllClients(constants.REMOTES.DevLog, {
                    level = level,
                    tag = tag,
                    message = message,
                })
            end)
        end)
    end
end

function devlog.info(tag: string, message: string)
    emit("info", tag, message)
end

function devlog.warn(tag: string, message: string)
    emit("warn", tag, message)
end

function devlog.err(tag: string, message: string)
    emit("err", tag, message)
end

-- Test hook: level name -> severity (used by tooling that wants to filter).
function devlog.levelOf(name: string): number
    return LEVELS[name] or 0
end

return devlog
