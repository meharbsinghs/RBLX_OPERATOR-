--!strict
-- ============================================================================
--  Menus: animated main menu, how-to-play, and the game-over screen.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local config = require(ReplicatedStorage:WaitForChild("config"))
local constants = require(ReplicatedStorage:WaitForChild("constants"))
local networking = require(ReplicatedStorage:WaitForChild("networking"))
local uikit = require(script.Parent.uikit)

local menus = {}

local player = Players.LocalPlayer
local theme = uikit.theme
local root: ScreenGui

local function build()
    root = Instance.new("ScreenGui")
    root.Name = "OperatorMenus"
    root.IgnoreGuiInset = true
    root.ResetOnSpawn = false
    root.Parent = player:WaitForChild("PlayerGui")

    -- Backdrop
    local backdrop = uikit.frame(root, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.fromRGB(10, 12, 16), 0.35)
    backdrop.ZIndex = 10

    -- Title
    local title = uikit.label(root, UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0.22), config.name:upper(), theme.accent, 64)
    title.ZIndex = 11
    title.TextTransparency = 0
    TweenService:Create(title, TweenInfo.new(1.2, Enum.EasingStyle.Back), { TextTransparency = 0, TextSize = 72 }):Play()

    local tagline = uikit.label(root, UDim2.fromScale(1, 0.05), UDim2.fromScale(0, 0.34), config.tagline, Color3.fromRGB(200, 206, 220), 22)
    tagline.ZIndex = 11

    -- Play
    local play = uikit.button(root, UDim2.fromOffset(280, 64), UDim2.fromScale(0.5, 0.44), "PLAY", function()
        networking.fireServer(constants.REMOTES.PlayerReady)
        root:Destroy()
    end, theme.accent)
    play.AnchorPoint = Vector2.new(0.5, 0)
    play.ZIndex = 11

    -- How to play
    local howto = uikit.button(root, UDim2.fromOffset(280, 48), UDim2.fromScale(0.5, 0.44), "HOW TO PLAY", function()
        showHowTo()
    end, Color3.fromRGB(46, 52, 64))
    howto.AnchorPoint = Vector2.new(0.5, 0)
    howto.Position = UDim2.fromScale(0.5, 0.44)
    howto.ZIndex = 11
    howto.TextColor3 = Color3.fromRGB(235, 238, 245)

    local footer = uikit.label(root, UDim2.fromScale(1, 0.04), UDim2.fromScale(0, 0.94), "Built by the RBLX Operator engine — regenerate me with: node pipeline/bridge.js newgame", Color3.fromRGB(120, 126, 140), 14)
    footer.ZIndex = 11
end

local function showHowTo()
    local panel = uikit.frame(root, UDim2.fromOffset(520, 380), UDim2.fromScale(0.5, 0.5), theme.panel)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.ZIndex = 20
    uikit.corner(panel, 14)
    uikit.gradient(panel, theme.panel, theme.panelLight, 90)
    uikit.stroke(panel, theme.accent, 2)

    uikit.label(panel, UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.04), "HOW TO PLAY", theme.accent, 28)
    local lines = {
        "• Left-click: fire your weapon  • Right-click: aim down sights",
        "• R: reload  • F: melee  • 1-9: switch weapons  • Scroll: cycle",
        "• Walk near an interactable (E) to buy doors, weapons & perks",
        "• Kill enemies for points. Points buy doors to new zones.",
        "• Mystery Box: random weapon. Pack-a-Punch: upgrade damage.",
        "• Downed? A teammate can revive you. All down = game over.",
        "• Survive as many rounds as you can.",
    }
    for i, line in ipairs(lines) do
        uikit.label(panel, UDim2.fromScale(0.94, 0.1), UDim2.new(0.03, 0, 0, 40 + (i - 1) * 38), line, Color3.fromRGB(200, 206, 220), 17)
    end

    local close = uikit.button(panel, UDim2.fromOffset(200, 44), UDim2.fromScale(0.5, 0.86), "CLOSE", function()
        panel:Destroy()
    end, Color3.fromRGB(46, 52, 64))
    close.AnchorPoint = Vector2.new(0.5, 0.5)
    close.TextColor3 = Color3.fromRGB(235, 238, 245)
end

local function showGameOver(round: number, kills: number, win: boolean)
    local overlay = uikit.canvasGroup(root, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), theme.overlay, 0.45)
    overlay.ZIndex = 30

    local panel = uikit.frame(overlay, UDim2.fromOffset(520, 360), UDim2.fromScale(0.5, 0.5), theme.panel)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    uikit.corner(panel, 14)
    uikit.gradient(panel, theme.panel, theme.panelLight, 90)
    uikit.stroke(panel, if win then theme.success else theme.danger, 2)

    uikit.label(panel, UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.06), if win then "EXTRACTION COMPLETE" else "GAME OVER", if win then theme.success else theme.danger, if win then 32 else 40)
    uikit.label(panel, UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.24), `You survived {round} rounds`, Color3.fromRGB(235, 238, 245), 24)
    uikit.label(panel, UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.34), `Total kills: {kills}`, Color3.fromRGB(200, 206, 220), 20)

    local again = uikit.button(panel, UDim2.fromOffset(240, 52), UDim2.fromScale(0.5, 0.52), "PLAY AGAIN", function()
        TeleportService:Teleport(game.PlaceId)
    end, theme.accent)
    again.AnchorPoint = Vector2.new(0.5, 0)
end

function menus.init()
    build()
    networking.onClient(constants.REMOTES.GameOver, function(payload: any)
        local p = payload :: { round: number, kills: number, win: boolean }
        showGameOver(p.round or 0, p.kills or 0, p.win or false)
    end)
end

return menus
