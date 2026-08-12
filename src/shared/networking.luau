--!strict
-- ============================================================================
--  Typed RemoteEvent wrapper. The server creates every remote once; clients
--  wait for them. All event names come from constants.REMOTES.
-- ============================================================================

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local constants = require(script.Parent.constants)

local IS_SERVER = RunService:IsServer()

if IS_SERVER then
    local folder = ReplicatedStorage:FindFirstChild(constants.FOLDERS.Remotes)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = constants.FOLDERS.Remotes
        folder.Parent = ReplicatedStorage
    end
    for _, name in constants.REMOTES do
        if not folder:FindFirstChild(name) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = name
            remote.Parent = folder
        end
    end
end

local function getRemote(name: string): RemoteEvent
    local folder = ReplicatedStorage:WaitForChild(constants.FOLDERS.Remotes, 15)
    assert(folder, "networking: remotes folder missing")
    local remote = folder:WaitForChild(name, 15)
    assert(remote, "networking: missing remote " .. name)
    return remote :: RemoteEvent
end

local networking = {}

function networking.fireServer(name: string, ...: any)
    getRemote(name):FireServer(...)
end

function networking.fireAllClients(name: string, ...: any)
    getRemote(name):FireAllClients(...)
end

function networking.fireClient(player: Player, name: string, ...: any)
    getRemote(name):FireClient(player, ...)
end

function networking.onServer(name: string, fn: (Player, ...any) -> ())
    getRemote(name).OnServerEvent:Connect(function(player: Player, ...: any)
        task.spawn(fn, player, ...)
    end)
end

function networking.onClient(name: string, fn: (...any) -> ())
    getRemote(name).OnClientEvent:Connect(function(...: any)
        task.spawn(fn, ...)
    end)
end

return networking
