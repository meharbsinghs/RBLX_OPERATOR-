--!strict
-- ============================================================================
--  Procedural map builder + navigation graph.
--
--  Reads the MapSpec from config.luau and builds a fully playable map from
--  primitive parts: floors, perimeter walls with enemy windows, barricades,
--  purchasable doors, wall-buy frames, mystery boxes, perk machines and the
--  pack-a-punch station. It also builds a waypoint graph (zone centers + door
--  nodes) used for enemy pathing — no NavMesh required, so maps generated at
--  runtime always work.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local proceduralassets = require(script.Parent.proceduralassets)

local mapbuilder = {}

-- --------------------------------------------------------------------------
--  Internal types
-- --------------------------------------------------------------------------

type Rect = { min: Vector3, max: Vector3 }

type Zone = {
    id: string,
    rect: Rect,
    reachable: boolean,
    windows: { Window },
}

type Window = {
    id: string,
    zone: string,
    position: Vector3,
    facing: Vector3,
    inner: Vector3,
    outer: Vector3,
    active: boolean,
    hp: number,
    maxHp: number,
    planks: { Part },
    sealed: Part?,
}

type Door = {
    id: string,
    name: string,
    cost: number,
    zoneA: string,
    zoneB: string,
    edgeA: string,
    edgeB: string,
    position: Vector3,
    facing: Vector3,
    open: boolean,
    prompt: ProximityPrompt,
    leaves: { Part },
}

type Prop = {
    id: string,
    weaponId: string,
    position: Vector3,
    prompt: ProximityPrompt,
}

-- --------------------------------------------------------------------------
--  Constants
-- --------------------------------------------------------------------------

local WALL_HEIGHT = 14
local THICK = 1
local DOOR_W = 12
local WINDOW_W = 8
local EDGE_ORDER: { string } = { "north", "east", "south", "west" }
local EDGE_NORMALS: { [string]: Vector3 } = {
    north = Vector3.new(0, 0, 1),
    east = Vector3.new(1, 0, 0),
    south = Vector3.new(0, 0, -1),
    west = Vector3.new(-1, 0, 0),
}

local theme = config.map.theme
local wallColor = theme.wall
local floorColor = theme.floor
local accentColor = theme.accent

-- --------------------------------------------------------------------------
--  State
-- --------------------------------------------------------------------------

local zones: { [string]: Zone } = {}
local doors: { [string]: Door } = {}
local rootZoneId = "a"
local windows: { Window } = {}
local wallBuys: { Prop } = {}
local boxSpots: { { id: string, position: Vector3, prompt: ProximityPrompt, light: PointLight } } = {}
local perkStations: { { id: string, perkId: string, position: Vector3, prompt: ProximityPrompt, light: PointLight } } = {}
local packSpot: { position: Vector3, prompt: ProximityPrompt, light: PointLight }? = nil
local repairZones: { { id: string, position: Vector3, cost: number, prompt: ProximityPrompt } } = {}
local mapFolder: Folder? = nil
local enemyFolder: Instance? = nil

-- --------------------------------------------------------------------------
--  Part helpers
-- --------------------------------------------------------------------------

-- Style-guide material mapping. Every part the map builder emits is run
-- through this, so flipping config.styleGuide.material re-themes the whole
-- world (grunge concrete <-> sci-fi metal <-> neon glass) with one field.
local function materialFor(name: string, material: Enum.Material?): Enum.Material
    if material then
        return material
    end
    local style = (config.styleGuide and config.styleGuide.material) or "grunge"
    if name:find("Glow") or name:find("Ring") or name:find("Sign") or name:find("BoxGlow") then
        return Enum.Material.Neon
    end
    if name:find("Plank") or name:find("Leaf") or name:find("Door") then
        return Enum.Material.Wood
    end
    if name == "Floor" or name:find("Ledge") then
        if style == "sci-fi" then
            return Enum.Material.Metal
        elseif style == "neon" then
            return Enum.Material.Glass
        elseif style == "cartoon" then
            return Enum.Material.SmoothPlastic
        end
        return Enum.Material.Slate
    end
    if style == "sci-fi" then
        return Enum.Material.Metal
    elseif style == "cartoon" then
        return Enum.Material.SmoothPlastic
    end
    return Enum.Material.Concrete
end

local function newPart(
    parent: Instance,
    name: string,
    size: Vector3,
    position: Vector3,
    color: Color3,
    material: Enum.Material?
): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Position = position
    part.Anchored = true
    part.Locked = true
    part.Material = materialFor(name, material)
    part.Color = color
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function makePrompt(part: Instance, text: string): ProximityPrompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.Parent = part
    prompt.ActionText = text
    prompt.ObjectText = ""
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.Style = Enum.ProximityPromptStyle.Custom
    return prompt
end

local function makeBillboard(parent: Instance, text: string, color: Color3): BillboardGui
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.fromOffset(220, 60)
    billboard.StudsOffset = Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0.4
    label.Parent = billboard
    return billboard
end

local function makeZoneRect(spec: any): Rect
    local half = spec.size / 2
    return {
        min = Vector3.new(spec.center.X - half.X, 0, spec.center.Z - half.Z),
        max = Vector3.new(spec.center.X + half.X, 0, spec.center.Z + half.Z),
    }
end

local function edgeLine(rect: Rect, kind: string): (Vector3, Vector3)
    if kind == "north" then
        return Vector3.new(rect.min.X, 0, rect.max.Z), Vector3.new(rect.max.X, 0, rect.max.Z)
    elseif kind == "east" then
        return Vector3.new(rect.max.X, 0, rect.max.Z), Vector3.new(rect.max.X, 0, rect.min.Z)
    elseif kind == "south" then
        return Vector3.new(rect.min.X, 0, rect.min.Z), Vector3.new(rect.max.X, 0, rect.min.Z)
    end
    return Vector3.new(rect.min.X, 0, rect.min.Z), Vector3.new(rect.min.X, 0, rect.max.Z)
end

-- --------------------------------------------------------------------------
--  Barricades
-- --------------------------------------------------------------------------

local function buildBarricade(window: Window)
    local parent = mapFolder :: Folder
    local planks: { Part } = {}
    for i = 1, 2 do
        local plank = newPart(
            parent,
            "BarricadePlank",
            Vector3.new(WINDOW_W, 0.5, 0.35),
            window.position + Vector3.new(0, 0.8 + i * 1.1, 0),
            Color3.fromRGB(96, 66, 38),
            Enum.Material.Wood
        )
        plank.CFrame = CFrame.lookAt(plank.Position, plank.Position + window.facing)
        CollectionService:AddTag(plank, constants.TAGS.Barricade)
        plank:SetAttribute(constants.ATTRIBUTES.WindowId, window.id)
        table.insert(planks, plank)
    end
    window.planks = planks
    window.hp = window.maxHp
end

local function syncPlankVisuals(window: Window)
    local ratio = window.maxHp > 0 and window.hp / window.maxHp or 0
    local desired = ratio > 0.66 and 2 or (ratio > 0.33 and 1 or 0)
    for i = #window.planks, 1, -1 do
        if i > desired then
            local plank = window.planks[i]
            plank:Destroy()
            table.remove(window.planks, i)
        end
    end
end

local function damageBarricade(windowId: string, amount: number)
    for _, window in windows do
        if window.id == windowId then
            if not window.active or window.hp <= 0 then
                return
            end
            window.hp = math.max(0, window.hp - amount)
            syncPlankVisuals(window)
            networking.fireAllClients(constants.REMOTES.BarricadeChanged, {
                windowId = windowId,
                hp = window.hp,
                maxHp = window.maxHp,
            })
            return
        end
    end
end

local function activateZone(zoneId: string)
    local zone = zones[zoneId]
    if not zone or zone.reachable then
        return
    end
    zone.reachable = true
    for _, window in zone.windows do
        if window.sealed then
            window.sealed:Destroy()
            window.sealed = nil
        end
        window.active = true
        buildBarricade(window)
    end
end

-- --------------------------------------------------------------------------
--  Reachability + pathing
-- --------------------------------------------------------------------------

local function computeReachable()
    local reached: { [string]: boolean } = { [rootZoneId] = true }
    local changed = true
    while changed do
        changed = false
        for _, door in doors do
            if door.open then
                local aOk = reached[door.zoneA]
                local bOk = reached[door.zoneB]
                if aOk and not bOk then
                    reached[door.zoneB] = true
                    changed = true
                elseif bOk and not aOk then
                    reached[door.zoneA] = true
                    changed = true
                end
            end
        end
    end
    for zoneId, zone in zones do
        zone.reachable = reached[zoneId] == true
    end
end

local function bfsDoorChain(startZone: string, goalZone: string): { string }?
    if startZone == goalZone then
        return {}
    end
    local queue: { { zone: string, doors: { string } } } = { { zone = startZone, doors = {} } }
    local visited: { [string]: boolean } = { [startZone] = true }
    while #queue > 0 do
        local node = table.remove(queue, 1)
        for _, door in doors do
            if door.open then
                local nextZone: string? = nil
                if door.zoneA == node.zone then
                    nextZone = door.zoneB
                elseif door.zoneB == node.zone then
                    nextZone = door.zoneA
                end
                if nextZone and not visited[nextZone] then
                    visited[nextZone] = true
                    local newDoors = table.clone(node.doors)
                    table.insert(newDoors, door.id)
                    if nextZone == goalZone then
                        return newDoors
                    end
                    table.insert(queue, { zone = nextZone, doors = newDoors })
                end
            end
        end
    end
    return nil
end

function mapbuilder.getNearestZone(position: Vector3): string
    local best = rootZoneId
    local bestDist = math.huge
    for zoneId, zone in zones do
        local dist = (Vector3.new(position.X, 0, position.Z) - Vector3.new(zone.rect.min.X + (zone.rect.max.X - zone.rect.min.X) / 2, 0, zone.rect.min.Z + (zone.rect.max.Z - zone.rect.min.Z) / 2)).Magnitude
        if dist < bestDist then
            bestDist = dist
            best = zoneId
        end
    end
    return best
end

function mapbuilder.isZoneReachable(zoneId: string): boolean
    local zone = zones[zoneId]
    return zone ~= nil and zone.reachable
end

function mapbuilder.getPath(startPos: Vector3, goalPos: Vector3): { Vector3 }?
    local startZone = mapbuilder.getNearestZone(startPos)
    local goalZone = mapbuilder.getNearestZone(goalPos)
    local chain = bfsDoorChain(startZone, goalZone)
    if chain == nil then
        return nil
    end
    local waypoints: { Vector3 } = { startPos }
    for _, doorId in chain do
        local door = doors[doorId]
        if door then
            table.insert(waypoints, door.position + door.facing * 2)
        end
    end
    table.insert(waypoints, goalPos)
    return waypoints
end

-- Returns "clear", "blocked" or "barricade" (+ the window id when barricade).
function mapbuilder.lineOfSightStatus(origin: Vector3, target: Vector3): (string, string?)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter: { Instance } = {}
    if enemyFolder then
        table.insert(filter, enemyFolder)
    end
    for _, player in Players:GetPlayers() do
        local character = player.Character
        if character then
            table.insert(filter, character)
        end
    end
    params.FilterDescendantsInstances = filter

    local delta = target - origin
    local result = workspace:Raycast(origin, delta, params)
    if not result then
        return "clear"
    end
    local windowId = result.Instance:GetAttribute(constants.ATTRIBUTES.WindowId)
    if windowId then
        return "barricade", windowId
    end
    return "blocked"
end

-- --------------------------------------------------------------------------
--  Doors
-- --------------------------------------------------------------------------

local function openDoor(doorId: string)
    local door = doors[doorId]
    if not door or door.open then
        return
    end
    door.open = true
    for _, leaf in door.leaves do
        if leaf.Parent then
            leaf.CanCollide = false
            TweenService:Create(leaf, TweenInfo.new(0.6), { Transparency = 1 }):Play()
            task.delay(0.7, function()
                leaf:Destroy()
            end)
        end
    end
    computeReachable()
    -- Activate the zone on the far side of this door
    local zoneA = zones[door.zoneA]
    local zoneB = zones[door.zoneB]
    if zoneA and zoneA.reachable then
        activateZone(door.zoneB)
    elseif zoneB and zoneB.reachable then
        activateZone(door.zoneA)
    end
end

-- --------------------------------------------------------------------------
--  Building
-- --------------------------------------------------------------------------

local function buildWallSegments(rect: Rect, kind: string, openings: { { t: number, width: number } })
    local a, b = edgeLine(rect, kind)
    local length = (b - a).Magnitude
    local dir = (b - a).Unit
    local normal = EDGE_NORMALS[kind]
    local horizontal = kind == "north" or kind == "south"

    table.sort(openings, function(x, y)
        return x.t < y.t
    end)

    local segments: { { s: number, e: number } } = {}
    local cursor = 0
    for _, opening in openings do
        local s = math.max(opening.t - opening.width / 2, 0)
        local e = math.min(opening.t + opening.width / 2, length)
        if s > cursor then
            table.insert(segments, { s = cursor, e = s })
        end
        cursor = math.max(cursor, e)
    end
    if cursor < length then
        table.insert(segments, { s = cursor, e = length })
    end

    local parent = mapFolder :: Folder
    for _, segment in segments do
        local segLen = segment.e - segment.s
        local mid = a + dir * ((segment.s + segment.e) / 2)
        local size = horizontal
                and Vector3.new(segLen + THICK * 2, WALL_HEIGHT, THICK)
            or Vector3.new(THICK, WALL_HEIGHT, segLen + THICK * 2)
        newPart(parent, "Wall", size, mid + normal * (THICK / 2) + Vector3.new(0, WALL_HEIGHT / 2, 0), wallColor)
    end
end

local function buildLintel(rect: Rect, kind: string, position: Vector3, width: number, bottom: number)
    local normal = EDGE_NORMALS[kind]
    local height = WALL_HEIGHT - bottom
    local horizontal = kind == "north" or kind == "south"
    local size = horizontal
            and Vector3.new(width, height, THICK)
        or Vector3.new(THICK, height, width)
    newPart(
        (mapFolder :: Folder),
        "Lintel",
        size,
        position + normal * (THICK / 2) + Vector3.new(0, bottom + height / 2, 0),
        wallColor
    )
end

local function buildZone(zoneSpec: any)
    local rect = makeZoneRect(zoneSpec)
    local zone: Zone = { id = zoneSpec.id, rect = rect, reachable = zoneSpec.id == rootZoneId, windows = {} }
    zones[zoneSpec.id] = zone

    -- Floor
    local half = zoneSpec.size / 2
    newPart(
        (mapFolder :: Folder),
        "Floor",
        Vector3.new(zoneSpec.size.X + THICK * 2, 1, zoneSpec.size.Z + THICK * 2),
        Vector3.new(zoneSpec.center.X, -0.5, zoneSpec.center.Z),
        floorColor
    )

    for _, kind in EDGE_ORDER do
        local a, b = edgeLine(rect, kind)
        local length = (b - a).Magnitude
        local dir = (b - a).Unit
        local doorOnEdge: Door? = nil
        for _, door in doors do
            if (door.zoneA == zoneSpec.id and door.edgeA == kind)
                or (door.zoneB == zoneSpec.id and door.edgeB == kind) then
                doorOnEdge = door
                break
            end
        end

        if doorOnEdge then
            -- Door edge: wall segments around the opening, lintel above,
            -- and the two door leaves (built once, from the `from` zone).
            local door = doorOnEdge
            local t = (door.position - a):Dot(dir)
            buildWallSegments(rect, kind, { { t = t, width = DOOR_W } })
            if door.zoneA == zoneSpec.id then
                buildLintel(rect, kind, door.position, DOOR_W, 8)
                for _, side in { -1, 1 } do
                    local leafPos = door.position + dir * (side * 3)
                    local leaf = newPart(
                        (mapFolder :: Folder),
                        "DoorLeaf",
                        Vector3.new(6, 8, 0.45),
                        leafPos + Vector3.new(0, 4, 0),
                        Color3.fromRGB(70, 52, 34),
                        Enum.Material.Wood
                    )
                    if not (kind == "north" or kind == "south") then
                        leaf.CFrame = CFrame.new(leaf.Position) * CFrame.Angles(0, math.pi / 2, 0)
                    end
                    table.insert(door.leaves, leaf)
                end
            end
        else
            -- Outer edge: windows + solid walls
            local hasWindows = false
            for _, windowKind in zoneSpec.windows do
                if windowKind == kind then
                    hasWindows = true
                end
            end

            local openings: { { t: number, width: number } } = {}
            if hasWindows then
                local count = length >= 40 and 2 or 1
                for i = 1, count do
                    local t = (length * (i / (count + 1)))
                    local pos = a + dir * t
                    local facing = EDGE_NORMALS[kind]
                    local window: Window = {
                        id = zoneSpec.id .. "-" .. kind .. "-" .. i,
                        zone = zoneSpec.id,
                        position = pos,
                        facing = facing,
                        inner = pos - facing * 3,
                        outer = pos + facing * 2.5,
                        active = false,
                        hp = 0,
                        maxHp = config.rounds.barricadeHp,
                        planks = {},
                        sealed = nil,
                    }
                    table.insert(windows, window)
                    table.insert(zone.windows, window)
                    table.insert(openings, { t = t, width = WINDOW_W })
                    buildLintel(rect, kind, pos, WINDOW_W, 6)

                    -- Ledge so enemies have ground to stand on outside the wall
                    local horizontal2 = kind == "north" or kind == "south"
                    local ledgeSize = horizontal2
                            and Vector3.new(WINDOW_W, 1, 4)
                        or Vector3.new(4, 1, WINDOW_W)
                    newPart(
                        (mapFolder :: Folder),
                        "WindowLedge",
                        ledgeSize,
                        pos + facing * 2.5 + Vector3.new(0, -0.5, 0),
                        floorColor
                    )

                    if zoneSpec.id == rootZoneId then
                        window.active = true
                        buildBarricade(window)
                    else
                        local seal = newPart(
                            (mapFolder :: Folder),
                            "Seal",
                            Vector3.new(WINDOW_W, 6, THICK),
                            pos + Vector3.new(0, 3, 0),
                            wallColor
                        )
                        window.sealed = seal
                    end
                end
            end
            buildWallSegments(rect, kind, openings)
        end
    end
end

local function buildProps()
    -- Wall buys
    for _, spec in config.map.wallBuys do
        local weaponName = spec.weaponId
        local weaponCost = 0
        for _, weapon in config.weapons do
            if weapon.id == spec.weaponId then
                weaponName = weapon.name
                weaponCost = weapon.wallBuyCost
            end
        end
        local parent = mapFolder :: Folder
        newPart(parent, "WallBuyPost", Vector3.new(0.4, 2.4, 0.4), spec.position + Vector3.new(-1.4, 1.2, 0), Color3.fromRGB(40, 40, 46))
        newPart(parent, "WallBuyPost", Vector3.new(0.4, 2.4, 0.4), spec.position + Vector3.new(1.4, 1.2, 0), Color3.fromRGB(40, 40, 46))
        local bar = newPart(parent, "WallBuyBar", Vector3.new(3.6, 0.5, 0.5), spec.position + Vector3.new(0, 2.6, 0), accentColor, Enum.Material.Neon)
        makeBillboard(bar, `${weaponName} — ${weaponCost} pts`, accentColor)
        local prompt = makePrompt(bar, weaponName)
        table.insert(wallBuys, { id = spec.id, weaponId = spec.weaponId, position = spec.position, prompt = prompt })
    end

    -- Mystery boxes
    for _, spec in config.map.boxes do
        local crate = newPart((mapFolder :: Folder), "MysteryBox", Vector3.new(4, 4, 4), spec.position + Vector3.new(0, 2, 0), Color3.fromRGB(52, 42, 66))
        local strip = newPart((mapFolder :: Folder), "BoxGlow", Vector3.new(4.2, 0.3, 4.2), spec.position + Vector3.new(0, 3.6, 0), Color3.fromRGB(255, 60, 200), Enum.Material.Neon)
        strip.Parent = crate.Parent
        local light = Instance.new("PointLight")
        light.Parent = crate
        light.Color = Color3.fromRGB(255, 60, 200)
        light.Range = 20
        light.Brightness = 3
        makeBillboard(crate, `MYSTERY BOX — ${config.mysteryBoxCost} pts`, Color3.fromRGB(255, 120, 220))
        local prompt = makePrompt(crate, "Spin the Mystery Box")
        table.insert(boxSpots, { id = spec.id, position = spec.position, prompt = prompt, light = light })
    end

    -- Perk machines
    for _, spec in config.map.perks do
        local perk = nil
        for _, candidate in config.perks do
            if candidate.id == spec.perkId then
                perk = candidate
            end
        end
        local color = perk and perk.color or accentColor
        local machine = newPart((mapFolder :: Folder), "PerkMachine", Vector3.new(2.4, 5, 1.4), spec.position + Vector3.new(0, 2.5, 0), color)
        local glow = newPart((mapFolder :: Folder), "PerkGlow", Vector3.new(2.6, 0.4, 1.6), spec.position + Vector3.new(0, 4.6, 0), color, Enum.Material.Neon)
        glow.Parent = machine.Parent
        local light = Instance.new("PointLight")
        light.Parent = machine
        light.Color = color
        light.Range = 16
        light.Brightness = 3
        local name = perk and perk.name or spec.perkId
        makeBillboard(machine, `${name} — ${perk and perk.cost or 0} pts`, color)
        local prompt = makePrompt(machine, `Buy ${name}`)
        table.insert(perkStations, { id = spec.id, perkId = spec.perkId, position = spec.position, prompt = prompt, light = light })
    end

    -- Pack-a-punch
    local packPos = config.map.pack
    local machine = newPart((mapFolder :: Folder), "PackMachine", Vector3.new(3, 6, 2), packPos + Vector3.new(0, 3, 0), Color3.fromRGB(48, 40, 56))
    local sign = newPart((mapFolder :: Folder), "PackSign", Vector3.new(4, 1.2, 0.4), packPos + Vector3.new(0, 6.4, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
    sign.Parent = machine.Parent
    local light = Instance.new("PointLight")
    light.Parent = machine
    light.Color = Color3.fromRGB(120, 220, 255)
    light.Range = 24
    light.Brightness = 4
    makeBillboard(machine, `PACK-A-PUNCH — ${config.packCost} pts`, Color3.fromRGB(140, 230, 255))
    local prompt = makePrompt(machine, "Pack-a-Punch your weapon")
    packSpot = { position = packPos, prompt = prompt, light = light }

    -- Barricade repair stations (hand-placed via config.map.repairZones)
    local repairColor = Color3.fromRGB(255, 200, 60)
    for _, spec in (config.map.repairZones or {}) do
        local station = newPart((mapFolder :: Folder), "RepairStation", Vector3.new(2.6, 3.2, 1.6), spec.position + Vector3.new(0, 1.6, 0), Color3.fromRGB(70, 74, 58))
        local glow = newPart((mapFolder :: Folder), "RepairGlow", Vector3.new(2.8, 0.35, 1.8), spec.position + Vector3.new(0, 3.1, 0), repairColor, Enum.Material.Neon)
        glow.Parent = station.Parent
        local light = Instance.new("PointLight")
        light.Parent = station
        light.Color = repairColor
        light.Range = 14
        light.Brightness = 2.5
        makeBillboard(station, `REPAIR BARRICADES — ${spec.cost} pts`, repairColor)
        local repairPrompt = makePrompt(station, "Repair Barricades")
        table.insert(repairZones, { id = spec.id, position = spec.position, cost = spec.cost, prompt = repairPrompt })
    end

    -- Glowing status lights (security beacons) at explicit coordinates
    for _, spec in (config.map.statusLights or {}) do
        local pole = newPart((mapFolder :: Folder), "StatusPole", Vector3.new(0.3, 6, 0.3), spec.position + Vector3.new(0, 3, 0), Color3.fromRGB(40, 42, 48))
        local head = newPart((mapFolder :: Folder), "StatusLight", Vector3.new(0.8, 0.8, 0.8), spec.position + Vector3.new(0, 6.2, 0), spec.color, Enum.Material.Neon)
        head.Parent = pole.Parent
        local light = Instance.new("PointLight")
        light.Parent = head
        light.Color = spec.color
        light.Range = spec.range or 18
        light.Brightness = 2
        if spec.label then
            makeBillboard(head, spec.label, spec.color)
        end
    end
end

local function buildSpawn()
    local position = config.map.spawn
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "SpawnLocation"
    spawn.Size = Vector3.new(4, 1, 4)
    spawn.Position = position + Vector3.new(0, 0.5, 0)
    spawn.Anchored = true
    spawn.Locked = true
    spawn.Neutral = true
    spawn.Material = Enum.Material.SmoothPlastic
    spawn.Color = Color3.fromRGB(40, 44, 52)
    spawn.Parent = mapFolder

    local ring = newPart((mapFolder :: Folder), "SpawnRing", Vector3.new(6, 0.15, 6), position + Vector3.new(0, 0.1, 0), accentColor, Enum.Material.Neon)
    ring.Parent = spawn.Parent
end

-- --------------------------------------------------------------------------
--  Lighting
-- --------------------------------------------------------------------------

-- Applies the GameSpec's dynamic lighting profile (theme.lighting) and builds
-- an Atmosphere so every generated game gets a cinematic, themed environment
-- instead of the default Studio sky. Works for any theme: grunge dusk,
-- sci-fi night, neon overdrive, cartoon daylight — all data-driven.
local function applyLighting()
    local lighting = game:GetService("Lighting")
    local profile = config.map.theme.lighting
    if profile then
        if profile.ambient ~= nil then
            lighting.Ambient = profile.ambient
        end
        if profile.outdoor ~= nil then
            lighting.OutdoorAmbient = profile.outdoor
        end
        if profile.shiftTop ~= nil then
            lighting.ColorShift_Top = profile.shiftTop
        end
        if profile.shiftBottom ~= nil then
            lighting.ColorShift_Bottom = profile.shiftBottom
        end
        if profile.brightness ~= nil then
            lighting.Brightness = profile.brightness
        end
        if profile.clockTime ~= nil then
            lighting.ClockTime = profile.clockTime
        end
        if profile.exposure ~= nil then
            lighting.ExposureCompensation = profile.exposure
        end
        if profile.fogStart ~= nil then
            lighting.FogStart = profile.fogStart
        end
        if profile.fogEnd ~= nil then
            lighting.FogEnd = profile.fogEnd
        end
    end
    lighting.FogColor = theme.fog

    local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = lighting
    end
    if profile then
        if profile.atmosphereDensity ~= nil then
            atmosphere.Density = profile.atmosphereDensity
        end
        if profile.atmosphereOffset ~= nil then
            atmosphere.Offset = profile.atmosphereOffset
        end
        if profile.atmosphereGlare ~= nil then
            atmosphere.Glare = profile.atmosphereGlare
        end
        if profile.atmosphereHaze ~= nil then
            atmosphere.Haze = profile.atmosphereHaze
        end
        if profile.skyColor ~= nil then
            atmosphere.Color = profile.skyColor
        end
    end
end

-- --------------------------------------------------------------------------
--  Public API
-- --------------------------------------------------------------------------

function mapbuilder.build(mapParent: Folder, enemyParent: Instance): typeof(mapbuilder)
    mapFolder = mapParent
    enemyFolder = enemyParent

    -- Doors first so zone building knows which edges are shared
    for _, spec in config.map.doors do
        local fromSpec = nil
        local toSpec = nil
        for _, zone in config.map.zones do
            if zone.id == spec.from then
                fromSpec = zone
            elseif zone.id == spec.to then
                toSpec = zone
            end
        end
        assert(fromSpec and toSpec, `mapbuilder: door ${spec.id} references unknown zones`)

        local fromRect = makeZoneRect(fromSpec)
        local toRect = makeZoneRect(toSpec)
        local delta = toSpec.center - fromSpec.center
        local door: Door
        if math.abs(delta.X) >= math.abs(delta.Z) then
            local east = delta.X > 0
            door = {
                id = spec.id,
                name = spec.name,
                cost = spec.cost,
                zoneA = spec.from,
                zoneB = spec.to,
                edgeA = east and "east" or "west",
                edgeB = east and "west" or "east",
                position = Vector3.new(east and fromRect.max.X or fromRect.min.X, 0, (fromSpec.center.Z + toSpec.center.Z) / 2),
                facing = Vector3.new(east and 1 or -1, 0, 0),
                open = false,
                prompt = Instance.new("ProximityPrompt"),
                leaves = {},
            }
        else
            local north = delta.Z > 0
            door = {
                id = spec.id,
                name = spec.name,
                cost = spec.cost,
                zoneA = spec.from,
                zoneB = spec.to,
                edgeA = north and "north" or "south",
                edgeB = north and "south" or "north",
                position = Vector3.new((fromSpec.center.X + toSpec.center.X) / 2, 0, north and fromRect.max.Z or fromRect.min.Z),
                facing = Vector3.new(0, 0, north and 1 or -1),
                open = false,
                prompt = Instance.new("ProximityPrompt"),
                leaves = {},
            }
        end
        doors[spec.id] = door
        -- The trigger slab only hosts the prompt; the door leaves are the real seal.
        local trigger = newPart((mapFolder :: Folder), "DoorTrigger", Vector3.new(DOOR_W, 8, 0.4), door.position + Vector3.new(0, 4, 0), Color3.fromRGB(60, 60, 66))
        trigger.CanCollide = false
        trigger.Transparency = 1
        door.prompt = makePrompt(trigger, `${spec.name} — ${spec.cost} pts`)
    end

    rootZoneId = config.map.zones[1].id

    for _, zoneSpec in config.map.zones do
        buildZone(zoneSpec)
    end

    buildProps()
    buildSpawn()
    computeReachable()
    applyLighting()
    return mapbuilder
end

function mapbuilder.getProps()
    return {
        zones = zones,
        doors = doors,
        windows = windows,
        wallBuys = wallBuys,
        boxSpots = boxSpots,
        perkStations = perkStations,
        pack = packSpot,
        repairZones = repairZones,
    }
end

function mapbuilder.getActiveWindows(): { Window }
    local active: { Window } = {}
    for _, window in windows do
        if window.active then
            table.insert(active, window)
        end
    end
    return active
end

function mapbuilder.getSpawnPosition(): Vector3
    return config.map.spawn
end

function mapbuilder.openDoor(doorId: string)
    openDoor(doorId)
end

function mapbuilder.damageBarricade(windowId: string, amount: number)
    damageBarricade(windowId, amount)
end

function mapbuilder.repairBarricades()
    for _, window in windows do
        if window.active then
            for _, plank in window.planks do
                if plank.Parent then
                    plank:Destroy()
                end
            end
            window.planks = {}
            buildBarricade(window)
        end
    end
end

return mapbuilder
