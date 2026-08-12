-- ============================================================================
--  RBLX OPERATOR CRAFT — Studio plugin
--
--  The playtest + craft surface of the RBLX Operator engine, inside Roblox
--  Studio. Four tabs:
--
--    CONSOLE   live DevLog streamed by the running engine (rounds, spawns,
--              economy, shop, tests). Connect, press Play, watch the game think.
--    PLAYTEST  one-click local test run (game:GetService("TestService"):Run()).
--    CRAFT     lighting mood presets + "Apply GameSpec mood" (paint the derived
--              game's lighting into Studio before Play) + Meshy/Open Cloud
--              asset injector (drop an rbxassetid:// model at your mouse).
--    SPEC      the derived game's identity at a glance (name, type, rosters,
--              win condition) straight from the engine's config.
--
--  Build + install:
--      rojo build plugin/plugin.project.json -o "%LOCALAPPDATA%\Roblox\Plugins\RBLXOperatorCraft.rbxmx"
--  or run scripts\plugin.ps1 (installs Rojo via Rokit first, then installs).
-- ============================================================================

-- ------------------------------------------------------------------ palette
local C = {
	bg      = Color3.fromRGB(10, 12, 16),
	panel   = Color3.fromRGB(15, 19, 26),
	panel2  = Color3.fromRGB(22, 28, 38),
	line    = Color3.fromRGB(35, 43, 58),
	text    = Color3.fromRGB(230, 234, 242),
	muted   = Color3.fromRGB(139, 148, 167),
	accent  = Color3.fromRGB(138, 99, 255),
	cyan    = Color3.fromRGB(55, 211, 255),
	ok      = Color3.fromRGB(61, 220, 132),
	warn    = Color3.fromRGB(255, 200, 87),
	err     = Color3.fromRGB(255, 93, 108),
}

local FONT = Enum.Font.Code
local UI = Enum.Font.SourceSans

-- ------------------------------------------------------------------ helpers
local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

local function button(parent, text, color)
	local b = mk("TextButton", {
		Text = text, Font = FONT, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = color, BorderSizePx = 0, Size = UDim2.new(1, 0, 0, 30),
		AutoButtonColor = true, LayoutOrder = 1,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 7) }, b)
	return b
end

local function section(parent, title, order)
	mk("TextLabel", {
		Name = "CraftSection",
		Text = "— " .. title .. " —", Font = FONT, TextSize = 11,
		TextColor3 = C.cyan, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order or 1,
	}, parent)
end

local function label(parent, text, color, size)
	return mk("TextLabel", {
		Text = text, Font = UI, TextSize = size or 13, TextColor3 = color or C.text,
		BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapping = Enum.TextWrapping.Wrap, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
	}, parent)
end

local function logLine(txt, color)
	return mk("TextLabel", {
		Text = txt, Font = FONT, TextSize = 11, TextColor3 = color or C.muted,
		BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapping = Enum.TextWrapping.Wrap, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
	})
end

-- ------------------------------------------------------------------ engine
-- The engine's remotes live under ReplicatedStorage.constants.Remotes, named
-- in src/shared/constants.luau. We resolve them lazily so the plugin works
-- before a place is built too — it simply shows "waiting for engine".
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TestService = game:GetService("TestService")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local engineLog = nil

local function engineConstants()
	return RS:FindFirstChild("constants")
end

local function findRemote(name)
	-- The engine creates its remotes folder directly under ReplicatedStorage
	-- (networking.luau: ReplicatedStorage[constants.FOLDERS.Remotes]).
	local folder = RS:FindFirstChild("Remotes")
	if folder then
		local remote = folder:FindFirstChild(name)
		if remote then return remote end
	end
	-- Fallback: some builds nest the folder inside the constants module.
	local constants = engineConstants()
	if constants then
		local nested = constants:FindFirstChild("Remotes")
		if nested then return nested:FindFirstChild(name) end
	end
	return nil
end

-- ------------------------------------------------------------------ gui
local toolbar = plugin:CreateToolbar("RBLX Operator")
local toggleBtn = toolbar:CreateButton("Craft", "RBLX Operator Craft — playtest & craft console", "rbxassetid://9104819124")

local dock = plugin:CreateDockWidgetPluginGui(
	"RBLXOperatorCraft",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 560)
)
dock.Title = "RBLX Operator Craft"
dock.Name = "RBLXOperatorCraft"

local root = mk("Frame", {
	BackgroundColor3 = C.bg, BorderSizePx = 0, Size = UDim2.fromScale(1, 1),
}, dock)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, root)

local pad = mk("Frame", {
	BackgroundTransparency = 1, BorderSizePx = 0,
	Size = UDim2.fromScale(1, 1),
}, root)
mk("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pad)

-- tabs row
local tabs = mk("Frame", {
	BackgroundTransparency = 1, BorderSizePx = 0,
	Size = UDim2.new(1, 0, 0, 30),
}, pad)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)

local tabButtons = {}
local panels = {}
local TAB_DEFS = {
	{ id = "console", label = "CONSOLE" },
	{ id = "playtest", label = "PLAYTEST" },
	{ id = "craft", label = "CRAFT" },
	{ id = "spec", label = "SPEC" },
}

for i, def in ipairs(TAB_DEFS) do
	local tb = mk("TextButton", {
		Text = def.label, Font = FONT, TextSize = 12,
		TextColor3 = C.muted, BackgroundColor3 = C.panel2, BorderSizePx = 0,
		Size = UDim2.new(0, 78, 0, 26), LayoutOrder = i, AutoButtonColor = false,
	}, tabs)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, tb)
	tb.Activated:Connect(function()
		for _, b in pairs(tabButtons) do
			b.TextColor3 = C.muted
			b.BackgroundColor3 = C.panel2
		end
		tb.TextColor3 = Color3.new(1, 1, 1)
		tb.BackgroundColor3 = C.accent
		for id, panel in pairs(panels) do
			panel.Visible = (id == def.id)
		end
	end)
	tabButtons[def.id] = tb
	local isConsole = (def.id == "console")
	panels[def.id] = mk(isConsole and "Frame" or "ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePx = 0, Visible = (i == 1),
		ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = isConsole and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 1, -40),
	}, pad)
	local list = mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, panels[def.id])
	mk("UIPadding", { PaddingTop = UDim.new(0, 8) }, panels[def.id])
end

-- ================================================================== CONSOLE
local consolePanel = panels.console
section(consolePanel, "engine devlog")
local status = label(consolePanel, "waiting for engine (build the place & press Play)…", C.muted, 12)

local consoleScroll = mk("ScrollingFrame", {
	BackgroundColor3 = C.panel, BorderSizePx = 0,
	ScrollBarThickness = 4, Size = UDim2.new(1, 0, 1, 0), LayoutOrder = 1,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, consolePanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, consoleScroll)
local consoleList = mk("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3),
}, consoleScroll)
mk("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, consoleScroll)

local LINE_COLORS = {
	info = C.muted,
	warn = C.warn,
	err = C.err,
	test = C.cyan,
}

local function pushLog(line)
	local color = LINE_COLORS[line.level] or C.text
	local entry = logLine(("[" .. string.upper(line.level or "info") .. "] " .. (line.tag or "?") .. ": " .. (line.message or "")), color)
	entry.Parent = consoleList
	-- keep the window bounded (count only log lines, never the layout)
	local labels = {}
	for _, child in ipairs(consoleList:GetChildren()) do
		if child:IsA("TextLabel") then table.insert(labels, child) end
	end
	while #labels > 500 do
		local first = table.remove(labels, 1)
		if first then first:Destroy() end
	end
	RunService:Stepped:Wait()
	consoleScroll.CanvasPosition = Vector2.new(0, consoleScroll.AbsoluteCanvasSize.Y)
end

local function connectDevlog()
	local remote = findRemote("DevLog")
	if remote then
		if not engineLog then
			engineLog = remote.OnClientEvent:Connect(function(payload)
				if type(payload) == "table" then
					status.Text = "live — engine events below"
					pushLog(payload)
				end
			end)
			status.TextColor3 = C.ok
			status.Text = "engine connected — DevLog live"
		end
	else
		status.Text = "waiting for engine (build the place & press Play)…"
		status.TextColor3 = C.muted
	end
end

task.spawn(function()
	while true do
		task.wait(2)
		connectDevlog()
	end
end)

-- ================================================================ PLAYTEST
local playPanel = panels.playtest
section(playPanel, "test run")
label(playPanel, "Starts a local playtest of the current place. The engine boots the\nreference game (or your last derived spec), and every system event\nstreams into the CONSOLE tab.", C.muted)

local playBtn = button(playPanel, "▶  START PLAYTEST", C.ok)
playBtn.Activated:Connect(function()
	local ok, err = pcall(function()
		TestService:Run()
	end)
	if not ok then
		status.Text = "playtest failed: " .. tostring(err)
		status.TextColor3 = C.err
	end
end)

section(playPanel, "tips")
label(playPanel, "• Stop with the red STOP button in Studio's toolbar.\n• Set _G.__TESTING = true before Play to run the engine's\n  self-simulating test suite instead (prints [TEST] PASS|FAIL).\n• Rojo users: rojo serve default.project.json then Plugins → Rojo →\n  Connect for live-sync while iterating.", C.muted)

-- =================================================================== CRAFT
local craftPanel = panels.craft
section(craftPanel, "lighting mood")
local moodRow = mk("Frame", { BackgroundTransparency = 1, BorderSizePx = 0, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 }, craftPanel)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, moodRow)

local MOODS = {
	{ name = "Dusk", brightness = 1.15, clock = 19.5, ambient = Color3.fromRGB(30, 34, 42), density = 0.3, fogStart = 40, fogEnd = 220 },
	{ name = "Night", brightness = 0.85, clock = 0.5, ambient = Color3.fromRGB(20, 20, 28), density = 0.45, fogStart = 30, fogEnd = 170 },
	{ name = "Neon", brightness = 1.5, clock = 0.4, ambient = Color3.fromRGB(24, 14, 48), density = 0.5, fogStart = 30, fogEnd = 180 },
	{ name = "Day", brightness = 1.6, clock = 12, ambient = Color3.fromRGB(150, 150, 180), density = 0.2, fogStart = 60, fogEnd = 320 },
}

local function applyLightingProfile(profile)
	Lighting.Ambient = profile.ambient
	Lighting.OutdoorAmbient = profile.outdoor or profile.ambient
	Lighting.Brightness = profile.brightness
	Lighting.ClockTime = profile.clock
	Lighting.ExposureCompensation = profile.exposure or 0
	Lighting.FogColor = profile.fogColor or profile.ambient
	Lighting.FogStart = profile.fogStart
	Lighting.FogEnd = profile.fogEnd
	Lighting.GlobalShadows = true
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = profile.density
	atm.Offset = profile.offset or 0.1
	atm.Glare = profile.glare or 0.25
	atm.Haze = profile.haze or 1.2
end

for _, mood in ipairs(MOODS) do
	local b = button(moodRow, mood.name, C.panel2)
	b.Size = UDim2.new(0, 74, 0, 28)
	b.LayoutOrder = 1
	b.Activated:Connect(function()
		applyLightingProfile(mood)
	end)
end

section(craftPanel, "gamespec mood")
label(craftPanel, "Paints the derived game's lighting profile (map.theme.lighting from\nsrc/shared/config.luau) into Studio, so you see the designed mood\nbefore you press Play.", C.muted)
local applySpecBtn = button(craftPanel, "APPLY GAMESPEC MOOD", C.accent)
applySpecBtn.Activated:Connect(function()
	local ok, result = pcall(function()
		local config = RS:FindFirstChild("config")
		if not config then error("config not found — build the place first") end
		local light = config.map.theme.lighting
		local profile = {
			ambient = light.ambient,
			outdoor = light.outdoor,
			brightness = light.brightness,
			clock = light.clockTime,
			exposure = light.exposure,
			fogColor = config.map.theme.fog,
			fogStart = light.fogStart,
			fogEnd = light.fogEnd,
			density = light.atmosphereDensity,
			offset = light.atmosphereOffset,
			glare = light.atmosphereGlare,
			haze = light.atmosphereHaze,
		}
		applyLightingProfile(profile)
		return true
	end)
	if not ok then
		status.Text = "mood apply failed: " .. tostring(result)
		status.TextColor3 = C.err
	end
end)

section(craftPanel, "asset injector")
label(craftPanel, "Paste a Meshy / Open Cloud rbxassetid:// and click to insert the model\nat your mouse position (or the Viewport center).", C.muted)
local assetBox = mk("TextBox", {
	Text = "rbxassetid://0", Font = FONT, TextSize = 12,
	TextColor3 = C.text, PlaceholderText = "rbxassetid://…",
	BackgroundColor3 = C.panel, BorderSizePx = 0,
	Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1,
	ClearTextOnFocus = false,
}, craftPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, assetBox)

local injectBtn = button(craftPanel, "INSERT ASSET", C.accent)
injectBtn.Activated:Connect(function()
	local id = assetBox.Text:match("(%d+)")
	if not id then
		status.Text = "no asset id found in: " .. assetBox.Text
		status.TextColor3 = C.err
		return
	end
	local ok, model = pcall(function()
		return InsertService:LoadAsset(tonumber(id))
	end)
	if not ok then
		status.Text = "load failed: " .. tostring(model)
		status.TextColor3 = C.err
		return
	end
	local parts = model:GetChildren()
	if #parts == 0 then
		status.Text = "asset loaded but empty"
		status.TextColor3 = C.warn
		return
	end
	local target = parts[1]
	local pos = workspace.CurrentCamera and workspace.CurrentCamera:GetPivot().Position or Vector3.zero
	if plugin:GetMouse() and plugin:GetMouse().Hit then
		pos = plugin:GetMouse().Hit.Position
	end
	target:PivotTo(CFrame.new(pos + Vector3.new(0, 2, 0)))
	target.Parent = workspace
	status.Text = "inserted " .. target.Name
	status.TextColor3 = C.ok
end)

-- ==================================================================== SPEC
local specPanel = panels.spec
section(specPanel, "current gamespec")

local function refreshSpec()
	-- remove old rows (named specRow), keep section titles + the refresh button
	for _, child in ipairs(specPanel:GetChildren()) do
		if child.Name == "specRow" then
			child:Destroy()
		end
	end
	local ok, result = pcall(function()
		local config = RS:FindFirstChild("config")
		if not config then error("config not found — build the place first") end
		return config
	end)
	if not ok then
		status.Text = "spec unavailable: " .. tostring(result)
		status.TextColor3 = C.muted
		return
	end
	local config = result
	local lines = {
		("name:      %s"):format(tostring(config.name)),
		("type:      %s"):format(tostring(config.gameType or "wave")),
		("win round: %s"):format(tostring(config.rounds and config.rounds.winRound or 0)),
		("weapons:   %d"):format(#(config.weapons or {})),
		("enemies:   %d"):format(#(config.enemies or {})),
		("perks:     %d"):format(#(config.perks or {})),
		("zones:     %d"):format(#(config.map and config.map.zones or {})),
		("doors:     %d"):format(#(config.map and config.map.doors or {})),
		("audio:     %s"):format(tostring(config.audio and config.audio.enabled and "on" or "off")),
	}
	local rowOrder = 2
	for _, line in ipairs(lines) do
		local row = label(specPanel, line, C.cyan, 12)
		row.Name = "specRow"
		row.LayoutOrder = rowOrder
		rowOrder += 1
	end
	local theme = config.theme or {}
	local spacer = label(specPanel, "", C.muted, 8)
	spacer.Name = "specRow"
	spacer.LayoutOrder = rowOrder
	rowOrder += 1
	local accent = label(specPanel, ("theme accent rgb(%d,%d,%d)"):format(theme.accent.R * 255, theme.accent.G * 255, theme.accent.B * 255), C.muted, 12)
	accent.Name = "specRow"
	accent.LayoutOrder = rowOrder
end

section(specPanel, "refresh", 90)
local specBtn = button(specPanel, "REFRESH SPEC", C.panel2)
specBtn.LayoutOrder = 91
specBtn.Activated:Connect(refreshSpec)
task.spawn(function()
	task.wait(1)
	refreshSpec()
end)

-- ------------------------------------------------------------------ toggle
local shown = false
local function show(state)
	shown = state
	dock.Visible = shown
	toggleBtn:SetActive(shown)
end

toggleBtn.Click:Connect(function()
	show(not shown)
end)

show(true)
task.spawn(connectDevlog)
print("[RBLX Operator Craft] loaded — CONSOLE / PLAYTEST / CRAFT / SPEC")
