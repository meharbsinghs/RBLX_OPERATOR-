--!strict
-- ============================================================================
--  HUD. Entirely driven by server broadcasts — the client never simulates
--  game state, it renders it. This is the "human-quality UI" layer.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local mathutils = require(ReplicatedStorage:WaitForChild("mathutils"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local uikit = require(script.Parent.uikit)
local entities = require(script.Parent.Parent.entities)

local hud = {}

local player = Players.LocalPlayer
local theme = uikit.theme
local root: ScreenGui
local hpBar: { frame: Frame, set: (number) -> () }
local ammoLabel: TextLabel
local weaponLabel: TextLabel
local pointsLabel: TextLabel
local roundLabel: TextLabel
local enemiesLabel: TextLabel
local crosshair: Frame
local crosshairBars: { { frame: Frame, dir: Vector2 } } = {}
local crosshairSpread = 0
local downedOverlay: CanvasGroup
local reviveLabel: TextLabel
local perkRow: Frame
local banner: CanvasGroup
local bannerTitle: TextLabel
local bannerSub: TextLabel
local toastHolder: Frame
local killFeed: Frame
local boxOverlay: Frame?
local boxTitle: TextLabel?
local previewViewport: ViewportFrame?

-- --------------------------------------------------------------------------
--  Construction
-- --------------------------------------------------------------------------

local function build()
    root = Instance.new("ScreenGui")
    root.Name = "OperatorHUD"
    root.IgnoreGuiInset = true
    root.ResetOnSpawn = false
    root.Parent = player:WaitForChild("PlayerGui")

    -- Top-left: round + enemies
    roundLabel = uikit.label(root, UDim2.fromOffset(240, 28), UDim2.fromOffset(16, 12), "ROUND 1", Color3.fromRGB(255, 255, 255), 22)
    roundLabel.TextXAlignment = Enum.TextXAlignment.Left
    enemiesLabel = uikit.label(root, UDim2.fromOffset(240, 20), UDim2.fromOffset(16, 40), "Enemies: 0", theme.textDim, 14)
    enemiesLabel.TextXAlignment = Enum.TextXAlignment.Left

    -- Top-right: points
    pointsLabel = uikit.label(root, UDim2.fromOffset(260, 34), UDim2.new(1, -276, 0, 12), "0", theme.accent, 28)
    pointsLabel.TextXAlignment = Enum.TextXAlignment.Right
    local pointsCaption = uikit.label(root, UDim2.fromOffset(120, 16), UDim2.new(1, -140, 0, 40), "POINTS", theme.textDim, 12)
    pointsCaption.TextXAlignment = Enum.TextXAlignment.Right

    -- Perk row (top-left under round info)
    perkRow = uikit.frame(root, UDim2.fromOffset(180, 22), UDim2.fromOffset(16, 66), Color3.fromRGB(255, 255, 255), 1)

    -- Kill feed (right side, under points)
    killFeed = uikit.frame(root, UDim2.fromOffset(280, 200), UDim2.new(1, -296, 0, 84), Color3.fromRGB(255, 255, 255), 1)

    -- Bottom-left: health
    local hpCaption = uikit.label(root, UDim2.fromOffset(100, 16), UDim2.fromOffset(16, -56), "HEALTH", theme.textDim, 12)
    hpCaption.TextXAlignment = Enum.TextXAlignment.Left
    hpBar = uikit.bar(root, UDim2.fromOffset(260, 18), UDim2.fromOffset(16, -36), theme.success)

    -- Bottom-left: rotating 3D weapon preview card (ViewportFrame)
    local previewCaption = uikit.label(root, UDim2.fromOffset(100, 14), UDim2.fromOffset(16, -230), "ARSENAL", theme.textDim, 12)
    previewCaption.TextXAlignment = Enum.TextXAlignment.Left
    previewViewport = uikit.viewport(root, UDim2.fromOffset(200, 120), UDim2.fromOffset(16, -214))

    -- Bottom-right: weapon + ammo
    weaponLabel = uikit.label(root, UDim2.fromOffset(360, 22), UDim2.new(1, -376, 1, -64), "M1911", Color3.fromRGB(255, 255, 255), 16)
    weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
    ammoLabel = uikit.label(root, UDim2.fromOffset(360, 34), UDim2.new(1, -376, 1, -42), "12 / 96", Color3.fromRGB(255, 255, 255), 26)
    ammoLabel.TextXAlignment = Enum.TextXAlignment.Right

    -- Center: crosshair
    crosshair = uikit.frame(root, UDim2.fromOffset(2, 2), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 255, 255))
    crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
    for _, dir in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
        local vertical = dir.X == 0
        local bar = uikit.frame(
            crosshair,
            if vertical then UDim2.fromOffset(2, 10) else UDim2.fromOffset(10, 2),
            UDim2.fromScale(0.5, 0.5),
            Color3.fromRGB(255, 255, 255)
        )
        bar.AnchorPoint = Vector2.new(0.5, 0.5)
        table.insert(crosshairBars, { frame = bar, dir = dir })
    end

    -- Center: round banner (hidden) — a CanvasGroup so the whole banner and
    -- its children fade together with a single GroupTransparency tween
    banner = uikit.canvasGroup(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.32), Color3.fromRGB(255, 255, 255), 1)
    banner.AnchorPoint = Vector2.new(0.5, 0.5)
    banner.GroupTransparency = 1
    banner.Visible = false
    uikit.gradient(banner, theme.panel, theme.panelLight, 90)
    bannerTitle = uikit.label(banner, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.05), "ROUND 5", Color3.fromRGB(255, 255, 255), 64)
    bannerSub = uikit.label(banner, UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.55), "", theme.accent, 24)

    -- Center: toasts
    toastHolder = uikit.frame(root, UDim2.fromOffset(420, 200), UDim2.fromScale(0.5, 0.62), Color3.fromRGB(255, 255, 255), 1)
    toastHolder.AnchorPoint = Vector2.new(0.5, 0)

    -- Downed overlay (hidden) — CanvasGroup so the blood-red screen fades as one
    downedOverlay = uikit.canvasGroup(root, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), theme.danger, 0.65)
    downedOverlay.Visible = false
    uikit.gradient(downedOverlay, theme.danger, Color3.fromRGB(60, 8, 8), 90)
    uikit.label(downedOverlay, UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.42), "YOU ARE DOWNED", Color3.fromRGB(255, 255, 255), 48)
    reviveLabel = uikit.label(downedOverlay, UDim2.fromScale(1, 0.15), UDim2.fromScale(0, 0.52), "A teammate can revive you — hold E near you", theme.textDim, 18)
    local bleed = uikit.bar(downedOverlay, UDim2.fromOffset(300, 10), UDim2.fromScale(0.5, 0.5), theme.danger)
    bleed.frame.AnchorPoint = Vector2.new(0.5, 0.5)
    bleed.frame.Position = UDim2.fromScale(0.5, 0.5)
    bleed.frame.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
end

-- --------------------------------------------------------------------------
--  Public API (called by the combat client and remotes)
-- --------------------------------------------------------------------------

function hud.setSpread(value: number)
    crosshairSpread = value
    local gap = 6 + crosshairSpread * 120
    for _, entry in crosshairBars do
        entry.frame.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(entry.dir.X * gap, entry.dir.Y * gap)
    end
end

function hud.hitmarker(headshot: boolean)
    local mark = uikit.frame(root, UDim2.fromOffset(18, 18), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 255, 255), 1)
    mark.AnchorPoint = Vector2.new(0.5, 0.5)
    uikit.label(mark, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), "✕", if headshot then Color3.fromRGB(255, 80, 60) else Color3.fromRGB(255, 255, 255), 18)
    TweenService:Create(mark, TweenInfo.new(0.25), { Size = UDim2.fromOffset(30, 30) }):Play()
    task.delay(0.22, function()
        mark:Destroy()
    end)
end

function hud.damageFlash(amount: number)
    local flash = uikit.frame(root, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), theme.danger, 0.6)
    flash.ZIndex = 5
    uikit.tween(flash, 0.4, { BackgroundTransparency = 1 })
    task.delay(0.4, function()
        flash:Destroy()
    end)
end

function hud.setHealth(frac: number)
    hpBar.set(frac)
    local color = theme.success
    if frac <= 0.5 then
        color = theme.accent
    end
    if frac <= 0.25 then
        color = theme.danger
    end
    hpBar.frame.BackgroundColor3 = color
end

local function updateWeaponPreview(weaponId: string)
    if not previewViewport then
        return
    end
    local spec = nil
    for _, candidate in config.weapons do
        if candidate.id == weaponId then
            spec = candidate
        end
    end
    uikit.viewportWeapon(previewViewport, spec and { color = spec.color, kind = spec.kind })
end

function hud.setWeapon(name: string)
    weaponLabel.Text = name
end

function hud.setAmmo(mag: number, reserve: number, reloading: boolean, duration: number)
    if reloading then
        ammoLabel.Text = `RELOADING... {math.ceil(duration)}`
    else
        ammoLabel.Text = `${mag} / ${reserve}`
    end
end

function hud.setPoints(points: number)
    pointsLabel.Text = mathutils.formatNumber(points)
end

function hud.setRound(round: number)
    roundLabel.Text = `ROUND ${round}`
end

function hud.setEnemies(alive: number)
    enemiesLabel.Text = `Enemies: ${alive}`
end

function hud.roundBanner(newState: string, data: any)
    if newState == "intermission" then
        banner.Visible = true
        bannerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        bannerTitle.Text = `ROUND ${data and data.round or 0}`
        bannerSub.Text = "Enemies incoming — gear up."
        uikit.tween(banner, 0.3, { GroupTransparency = 0.15 })
        task.delay(4, function()
            uikit.tween(banner, 0.4, { GroupTransparency = 1 })
        end)
    elseif newState == "roundEnd" then
        banner.Visible = true
        bannerTitle.Text = "ROUND CLEAR"
        bannerTitle.TextColor3 = theme.success
        bannerSub.Text = `+${config.points.perRound} points`
        uikit.tween(banner, 0.3, { GroupTransparency = 0.15 })
        task.delay(3, function()
            uikit.tween(banner, 0.4, { GroupTransparency = 1 })
        end)
    elseif newState == "gameOver" then
        banner.Visible = true
        banner.GroupTransparency = 0.15
        bannerTitle.Text = "GAME OVER"
        bannerTitle.TextColor3 = theme.danger
        bannerSub.Text = ""
    end
end

function hud.toast(text: string, tone: string)
    local color = theme.accent
    if tone == "danger" then
        color = theme.danger
    elseif tone == "success" then
        color = theme.success
    end
    local label = uikit.label(toastHolder, UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), text, color, 18)
    label.BackgroundColor3 = theme.panel
    label.BackgroundTransparency = 0.25
    uikit.corner(label, 8)
    uikit.gradient(label, theme.panel, theme.panelLight, 90)
    local y = (#toastHolder:GetChildren() - 1) * 0.17
    label.Position = UDim2.fromScale(0, y)
    uikit.tween(label, 0.3, { BackgroundTransparency = 1 })
    task.delay(2.5, function()
        label:Destroy()
    end)
end

function hud.downed(active: boolean, healer: string?)
    downedOverlay.Visible = active
    if active then
        reviveLabel.Text = healer and `Being revived by ${healer}...` or "A teammate can revive you — hold E near you"
    end
end

function hud.reviveProgress(progress: number)
    if downedOverlay.Visible then
        reviveLabel.Text = `Reviving... {math.floor(progress * 100)}%`
    end
end

function hud.addPerk(perkId: string, name: string)
    for _, existing in perkRow:GetChildren() do
        if existing:IsA("Frame") and existing.Name == perkId then
            return
        end
    end
    local chip = uikit.frame(perkRow, UDim2.fromOffset(0, 22), UDim2.fromOffset(0, 0), Color3.fromRGB(255, 255, 255), 0.9)
    chip.Name = perkId
    chip.Size = UDim2.fromOffset(22, 22)
    local count = #perkRow:GetChildren()
    chip.Position = UDim2.fromOffset((count - 1) * 26, 0)
    uikit.corner(chip, 6)
    uikit.label(chip, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), name:sub(1, 1), Color3.fromRGB(255, 255, 255), 14)
end

function hud.boxRoll(sequence: any, finalWeapon: string)
    if not boxOverlay then
        boxOverlay = uikit.frame(root, UDim2.fromOffset(420, 140), UDim2.fromScale(0.5, 0.45), Color3.fromRGB(16, 14, 22))
        boxOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
        uikit.corner(boxOverlay, 12)
        uikit.stroke(boxOverlay, Color3.fromRGB(255, 60, 200), 2)
        uikit.label(boxOverlay, UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.05), "MYSTERY BOX", Color3.fromRGB(255, 120, 220), 22)
        boxTitle = uikit.label(boxOverlay, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.4), "", Color3.fromRGB(255, 255, 255), 30)
    end
    boxOverlay.Visible = true
    boxTitle.Text = ""
    local seq = sequence and sequence or {}
    local index = 0
    local function step()
        index += 1
        if index > #seq then
            boxTitle.Text = finalWeapon
            boxTitle.TextColor3 = theme.accent
            task.delay(1, function()
                if boxOverlay then
                    boxOverlay.Visible = false
                end
            end)
            return
        end
        boxTitle.Text = seq[index]
        task.delay(0.45, step)
    end
    step()
end

function hud.killFeed(typeId: string, killer: string?, headshot: boolean)
    local suffix = headshot and " (headshot)" or ""
    local label = uikit.label(killFeed, UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0), `${killer or "You"} eliminated ${typeId}${suffix}`, Color3.fromRGB(255, 255, 255), 14)
    label.TextXAlignment = Enum.TextXAlignment.Right
    label.BackgroundTransparency = 1
    local count = #killFeed:GetChildren()
    label.Position = UDim2.fromScale(0, (count - 1) * 0.15)
    uikit.tween(label, 0.4, { TextTransparency = 1 })
    task.delay(4, function()
        label:Destroy()
    end)
end

function hud.damageNumber(hitPos: Vector3, damage: number, headshot: boolean)
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Transparency = 1
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(120, 40)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = uikit.label(billboard, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), tostring(math.floor(damage)), if headshot then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 255, 255), 22)
    uikit.tween(label, 0.5, { TextTransparency = 1 })
    Debris:AddItem(part, 0.6)
end

-- --------------------------------------------------------------------------
--  Networking
-- --------------------------------------------------------------------------

function hud.init()
    build()

    networking.onClient(constants.REMOTES.PointsChanged, function(payload: any)
        local p = payload :: { points: number }
        hud.setPoints(p.points or 0)
    end)

    networking.onClient(constants.REMOTES.AmmoChanged, function(payload: any)
        local p = payload :: { weaponId: string, mag: number, reserve: number, reloading: boolean, duration: number }
        hud.setAmmo(p.mag or 0, p.reserve or 0, p.reloading or false, p.duration or 0)
    end)

    networking.onClient(constants.REMOTES.LoadoutChanged, function(payload: any)
        local p = payload :: { equipped: string, weapons: any, ammo: any }
        local spec = nil
        for _, weapon in config.weapons do
            if weapon.id == p.equipped then
                spec = weapon
            end
        end
        local name = spec and spec.name or p.equipped
        local tier = p.weapons and p.weapons[p.equipped] or 0
        if tier and tier > 0 then
            local specTier = spec and spec.packTiers[tier]
            if specTier then
                name = name .. specTier.nameSuffix
            end
        end
        hud.setWeapon(name)
        updateWeaponPreview(p.equipped or "")
        local ammo = p.ammo and p.ammo[p.equipped]
        if ammo then
            hud.setAmmo(ammo.mag or 0, ammo.reserve or 0, false, 0)
        end
    end)

    networking.onClient(constants.REMOTES.RoundState, function(newState: any, data: any)
        hud.setRound((data and data.round) or 0)
        hud.setEnemies((data and data.alive) or 0)
        hud.roundBanner(tostring(newState), data)
    end)

    networking.onClient(constants.REMOTES.EnemyCount, function(count: any)
        hud.setEnemies(tonumber(count) or 0)
    end)

    networking.onClient(constants.REMOTES.PlayerDamaged, function()
        hud.damageFlash(0)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            hud.setHealth(humanoid.Health / humanoid.MaxHealth)
        end
    end)

    networking.onClient(constants.REMOTES.Downed, function(payload: any)
        local p = payload :: { player: string }
        if p.player == player.Name then
            hud.downed(true)
        end
    end)

    networking.onClient(constants.REMOTES.Revived, function(payload: any)
        local p = payload :: { player: string }
        if p.player == player.Name then
            hud.downed(false)
        end
    end)

    networking.onClient(constants.REMOTES.RevivePrompt, function(payload: any)
        local p = payload :: { progress: number, healer: string }
        hud.reviveProgress(p.progress or 0)
        hud.downed(true, p.healer)
    end)

    networking.onClient(constants.REMOTES.KillConfirmed, function(payload: any)
        local p = payload :: { typeId: string, killer: string, headshot: boolean }
        local name = p.typeId
        for _, spec in config.enemies do
            if spec.id == p.typeId then
                name = spec.name
            end
        end
        hud.killFeed(name, p.killer, p.headshot or false)
    end)

    networking.onClient(constants.REMOTES.HitConfirmed, function(payload: any)
        local p = payload :: { hitPos: Vector3, damage: number, headshot: boolean }
        hud.hitmarker(p.headshot or false)
        if p.hitPos then
            hud.damageNumber(p.hitPos, p.damage or 0, p.headshot or false)
        end
    end)

    networking.onClient(constants.REMOTES.PurchaseToast, function(payload: any)
        local p = payload :: { text: string, tone: string }
        hud.toast(p.text or "", p.tone or "accent")
    end)

    networking.onClient(constants.REMOTES.PurchaseRejected, function(payload: any)
        local p = payload :: { reason: string }
        hud.toast(p.reason or "Can't afford that", "danger")
    end)

    networking.onClient(constants.REMOTES.BoxRoll, function(payload: any)
        local p = payload :: { sequence: any, final: string }
        hud.boxRoll(p.sequence, p.final or "")
    end)

    networking.onClient(constants.REMOTES.PerkGranted, function(payload: any)
        local p = payload :: { perkId: string, name: string }
        hud.addPerk(p.perkId or "", p.name or "")
    end)

    networking.onClient(constants.REMOTES.GameOver, function(payload: any)
        local p = payload :: { round: number, kills: number }
        hud.roundBanner("gameOver", p)
    end)

    -- Health bar sync loop (server-owned health)
    task.spawn(function()
        while true do
            task.wait(0.2)
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                hud.setHealth(humanoid.Health / humanoid.MaxHealth)
            end
        end
    end)

    -- Enemy count from the compressed batch channel, smoothed client-side by
    -- entities.luau (the single source for horde size — no per-event chatter).
    task.spawn(function()
        while true do
            task.wait(0.2)
            hud.setEnemies(entities.getCount())
        end
    end)
end

return hud
