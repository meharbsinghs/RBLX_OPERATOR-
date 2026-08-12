--!strict
-- ============================================================================
--  Central registry of every remote, tag, folder and attribute the engine
--  uses. One source of truth — never hardcode a name in a module.
-- ============================================================================

local REMOTES = {
    -- client -> server
    GunFired = "GunFired",
    ReloadRequest = "ReloadRequest",
    MeleeRequest = "MeleeRequest",
    BuyRequest = "BuyRequest",
    ReviveRequest = "ReviveRequest",
    PlayerReady = "PlayerReady",
    SwitchWeapon = "SwitchWeapon",
    -- server -> client
    Tracer = "Tracer",
    HitConfirmed = "HitConfirmed",
    KillConfirmed = "KillConfirmed",
    PlayerDamaged = "PlayerDamaged",
    Downed = "Downed",
    Revived = "Revived",
    RoundState = "RoundState",
    EnemyCount = "EnemyCount",
    PointsChanged = "PointsChanged",
    AmmoChanged = "AmmoChanged",
    LoadoutChanged = "LoadoutChanged",
    PurchaseRejected = "PurchaseRejected",
    PurchaseToast = "PurchaseToast",
    BoxRoll = "BoxRoll",
    PerkGranted = "PerkGranted",
    GameOver = "GameOver",
    BarricadeChanged = "BarricadeChanged",
    RevivePrompt = "RevivePrompt",
    Stats = "Stats",
    EnemyStateBatch = "EnemyStateBatch",
    DevLog = "DevLog",
    DevCommand = "DevCommand",
}

local TAGS = {
    Enemy = "Enemy",
    Barricade = "Barricade",
}

local FOLDERS = {
    Map = "Map",
    Enemies = "Enemies",
    FX = "FX",
    Remotes = "Remotes",
    Audio = "Audio",
}

local ATTRIBUTES = {
    EnemyId = "EnemyId",
    EnemyType = "EnemyType",
    MaxHp = "MaxHp",
    Hp = "Hp",
    WindowId = "WindowId",
    PerkId = "PerkId",
    Downed = "Downed",
    Perks = "Perks",
    Ready = "Ready",
    Strikes = "Strikes",
}

return {
    REMOTES = REMOTES,
    TAGS = TAGS,
    FOLDERS = FOLDERS,
    ATTRIBUTES = ATTRIBUTES,
}
