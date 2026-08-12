--!strict
-- ============================================================================
--  Client bootstrap. Starts the UI framework, HUD, menus and the first-person
--  combat controller. All of them render server state — nothing is simulated
--  client-side.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local config = require(ReplicatedStorage:WaitForChild("config"))

local uikit = require(script.Parent.ui.uikit)
local hud = require(script.Parent.ui.hud)
local menus = require(script.Parent.ui.menus)
local combatclient = require(script.Parent.combatclient)
local entities = require(script.Parent.entities)

menus.init()
hud.init()
combatclient.init()
entities.init()

print(`[RBLXOperator] Client online — ${config.name}`)
