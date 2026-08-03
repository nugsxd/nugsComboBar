--------------------------------------------------------------------------------
-- nugsComboBar
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsComboBar  -  Core.lua
-- Shared state: media lists (pip textures, fonts), saved-variable defaults, and the
-- slash command. The resource registry itself lives in Resources.lua.
--
-- Shared namespace: the second vararg is the same table across every Lua file in
-- this addon, so all state and functions hang off of it.
--------------------------------------------------------------------------------
local ADDON_NAME, NCB = ...

NCB.name    = ADDON_NAME
NCB.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
              or "0.1.0"

local PREFIX = "|cff6fc2ffnugsComboBar|r: "
function NCB.Print(msg)
    print(PREFIX .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Secret values (Midnight / 12.0)
-- Combat data can be handed to addons as opaque "secret" values: reading one is
-- fine, doing arithmetic on it is not. Anything that might come back secret goes
-- through Plain(), which returns nil rather than a value we are not allowed to
-- compute with. nil means "cannot know right now".
--
-- The player's own power has always come back plain, and every pip count in this
-- addon is the player's own - but Plain() costs nothing and a class resource is
-- exactly the sort of thing that could be locked down in a later patch, so the
-- engine treats a nil count as "leave the pips as they are" rather than erroring.
--------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
NCB.secretsExist = (issecretvalue ~= nil)

function NCB.IsSecret(v)
    if v == nil or not issecretvalue then return false end
    return issecretvalue(v) and true or false
end

function NCB.Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Media
-- Stock entries always work. If LibSharedMedia happens to be loaded by some other
-- addon we borrow its lists too, but nothing here depends on it.
--------------------------------------------------------------------------------
local STOCK_TEXTURES = {
    { name = "Flat",              path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Blizzard Raid Bar", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Blizzard",          path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Blizzard Character",path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { name = "Cast Bar",          path = "Interface\\CastingBar\\UI-CastingBar-Fill" },
    { name = "Otravi",            path = "Interface\\PVPFrame\\UI-PVP-Progress-Bar" },
}

local STOCK_FONTS = {
    { name = "Friz Quadrata TT", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",     path = "Fonts\\ARIALN.TTF"   },
    { name = "Skurri",           path = "Fonts\\SKURRI.TTF"   },
    { name = "Morpheus",         path = "Fonts\\MORPHEUS.TTF" },
}

-- Shared shape for both media kinds: stock list first, LSM appended, no duplicates.
local function MediaList(stock, lsmKind)
    local list, seen = {}, {}
    for _, entry in ipairs(stock) do
        list[#list + 1] = entry
        seen[entry.name] = true
    end

    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, names = pcall(LSM.List, LSM, lsmKind)
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if not seen[name] then
                    local ok2, path = pcall(LSM.Fetch, LSM, lsmKind, name)
                    if ok2 and type(path) == "string" then
                        list[#list + 1] = { name = name, path = path }
                        seen[name] = true
                    end
                end
            end
        end
    end
    return list
end

function NCB.TextureList() return MediaList(STOCK_TEXTURES, "statusbar") end
function NCB.FontList()    return MediaList(STOCK_FONTS,    "font")      end

function NCB.TexturePath(name)
    for _, entry in ipairs(NCB.TextureList()) do
        if entry.name == name then return entry.path end
    end
    return STOCK_TEXTURES[1].path
end

function NCB.FontPath(name)
    for _, entry in ipairs(NCB.FontList()) do
        if entry.name == name then return entry.path end
    end
    return STOCK_FONTS[1].path
end

--------------------------------------------------------------------------------
-- Choice lists
--------------------------------------------------------------------------------
NCB.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE" }

-- Pip shapes. Each is a mask applied over the pip texture, so any bar texture the
-- user picks still shows through - a circle pip is the chosen texture seen through
-- a round hole, not a separate piece of art.
NCB.SHAPES = {
    { key = "rect",    label = "Rectangle" },
    { key = "rounded", label = "Rounded" },
    { key = "circle",  label = "Circle" },
    { key = "diamond", label = "Diamond" },
    { key = "hex",     label = "Hexagon" },
}

NCB.DIRECTIONS = {
    { key = "right", label = "Left to right" },
    { key = "left",  label = "Right to left" },
    { key = "up",    label = "Bottom to top" },
    { key = "down",  label = "Top to bottom" },
}

-- What sits under a pip that is not filled. None of these can depend on whether the
-- pip IS filled - for a secret resource that is not knowable - so they differ only
-- in what is drawn behind every pip.
NCB.EMPTY_STYLES = {
    { key = "dim",    label = "Filled, dimmed" },
    { key = "hollow", label = "Outline only" },
    { key = "none",   label = "Nothing at all" },
}

NCB.COUNT_MODES = {
    { key = "none",    label = "No number" },
    { key = "center",  label = "Number in the middle" },
    { key = "above",   label = "Number above" },
    { key = "below",   label = "Number below" },
}

NCB.VISIBILITY = {
    { key = "always",   label = "Always" },
    { key = "combat",   label = "In combat only" },
    { key = "spent",    label = "When not empty" },
    { key = "target",   label = "With a hostile target" },
}

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------
-- The look is one shared block rather than a copy per resource: a character has
-- exactly one class resource on screen at a time, so five separate style sets would
-- be five places to change the same setting. What genuinely differs per resource -
-- its colour, and whether it is drawn at all - lives in db.resources instead.
NCB.defaults = {
    enabled       = true,
    locked        = true,
    minimapHidden = false,
    minimapAngle  = 200,

    anchor = {
        point   = "CENTER",
        relPoint= "CENTER",
        x       = 0,
        y       = -140,
        scale   = 1.00,
    },

    look = {
        pipWidth   = 26,
        pipHeight  = 18,
        spacing    = 5,
        shape      = "rounded",
        direction  = "right",
        texture    = "Flat",

        emptyStyle = "dim",
        emptyAlpha = 0.25,
        showBorder = true,
        borderSize = 1,
        staggerHeight = 6,

        -- Charged pips grow slightly and glow; that motion is what makes a resource
        -- readable out of the corner of your eye without looking straight at it.
        animate    = true,
        gainPop    = 1.18,   -- scale a pip briefly reaches when it fills
        glow       = true,
        glowAlpha  = 0.55,

        -- Capping the resource is the single most useful thing this display can tell
        -- you, so it gets two independent tells: a recolour and a glow. Both are
        -- driven by the widget rather than by a comparison, so both survive a secret
        -- resource value.
        fullHighlight    = true,
        fullGlow         = true,
        fullGlowStrength = 0.85,
        fullGlowPulse    = true,

        font        = "Friz Quadrata TT",
        fontSize    = 13,
        fontOutline = "OUTLINE",
        countMode   = "none",

        colorEmpty      = { 0.16, 0.16, 0.18, 1.00 },
        colorBorder     = { 0.00, 0.00, 0.00, 1.00 },
        -- Near-white, NOT gold. These have to read against whatever colour the
        -- resource itself is, and the old gold defaults were within a few hundredths
        -- of Holy Power's own gold - so on a Paladin a working recolour and a working
        -- additive glow were both invisible, which is indistinguishable from broken.
        colorFull       = { 1.00, 0.99, 0.92 },
        colorFullGlow   = { 1.00, 0.97, 0.88 },
        colorText       = { 1.00, 1.00, 1.00 },
    },

    behaviour = {
        -- Every colour and glow control acts on a FILLED pip, and a resource sitting
        -- at zero out of combat has none - so without this the options window is full
        -- of controls that visibly do nothing.
        previewInOptions = true,
        visibility     = "always",
        hideInVehicle  = true,
        hideOnPetBattle= true,
        fadeAlpha      = 0.35,  -- alpha when the visibility rule says "not now"
        fadeTime       = 0.25,
    },

    -- Per resource: whether to draw it, its colour, and whether Blizzard's own
    -- version of it is suppressed. Filled in from Resources.lua's registry.
    resources = {},

    -- Deliberately short. A partial fill for the essence currently regenerating was
    -- the obvious fourth entry here and is not possible: it needs the regen rate,
    -- and GetPowerRegenForPowerType comes back secret. A toggle that cannot do
    -- anything is worse than no toggle.
    extras = {
        stagger        = true,    -- Brewmaster's Stagger, drawn as its own small bar
        runeCooldowns  = true,    -- sweep each spent rune as it recharges
        comboAnticipation = true, -- draw combo points past the normal maximum
    },
}

NCB.charDefaults = {
    -- Which resource the options window last had open, so it reopens where you left
    -- it rather than always on General.
    lastTab = nil,
}

local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
NCB.CopyDefaults = CopyDefaults

local function InitDB()
    nugsComboBarDB     = CopyDefaults(nugsComboBarDB     or {}, NCB.defaults)
    nugsComboBarCharDB = CopyDefaults(nugsComboBarCharDB or {}, NCB.charDefaults)

    -- One settings block per registered resource, seeded from the registry's own
    -- colour so a new resource added in a later patch lands with a sane default
    -- instead of white.
    for _, res in ipairs(NCB.RESOURCES) do
        local cfg = nugsComboBarDB.resources[res.key] or {}
        cfg = CopyDefaults(cfg, {
            enabled      = true,
            hideBlizzard = true,
            color        = { res.color[1], res.color[2], res.color[3] },
            perPointColor= res.perPointColor and true or false,
        })
        nugsComboBarDB.resources[res.key] = cfg
    end

    -- One-time colour repair. The at-max recolour and glow shipped gold, which is
    -- within a few hundredths of Holy Power's own gold - so on a Paladin both worked
    -- perfectly and neither was visible. Anyone still carrying the old shipped values
    -- is moved to the new near-white ones; anyone who picked their own keeps them.
    if not nugsComboBarDB.fullColoursRepaired then
        local L = nugsComboBarDB.look
        local function IsStill(c, r, g, b)
            return c and math.abs(c[1] - r) < 0.005
                     and math.abs(c[2] - g) < 0.005
                     and math.abs(c[3] - b) < 0.005
        end
        if IsStill(L.colorFull,     1.00, 0.85, 0.30) then
            L.colorFull     = { 1.00, 0.99, 0.92 }
        end
        if IsStill(L.colorFullGlow, 1.00, 0.78, 0.25) then
            L.colorFullGlow = { 1.00, 0.97, 0.88 }
        end
        nugsComboBarDB.fullColoursRepaired = true
    end

    NCB.db   = nugsComboBarDB
    NCB.char = nugsComboBarCharDB
    nugsComboBarDB.profiles = nugsComboBarDB.profiles or {}
end

--------------------------------------------------------------------------------
-- Profiles
-- Named snapshots of the settings, kept in the account-wide saved variables -
-- which is the whole trick. Save one on any character and every other character
-- can see and load it, with no strings to copy and nothing to export.
--
-- Loading is always a deliberate act. Nothing is bound to a character and nothing
-- auto-saves: a change you make now simply stays, until you choose to Save it into
-- a profile or Load a different one over it.
--
-- Everything in the saved variables is profiled EXCEPT what is listed here, so a
-- setting added later is carried automatically rather than being quietly left out
-- until somebody notices it did not travel.
--------------------------------------------------------------------------------
local PROFILE_SKIP = {
    profiles      = true,   -- the store itself
    activeProfile = true,   -- a record ABOUT profiles, never part of one
    minimapAngle  = true,   -- where you dragged the button is not a look
    minimapHidden = true,
}

local function ProfileDeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = ProfileDeepCopy(sub) end
    return out
end

-- Written out rather than using `s:trim()`: that is a WoW helper, not Lua, and this
-- file has no business assuming which of them is present.
local function ProfileTrim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
NCB.TrimName = ProfileTrim

function NCB.ProfileNames()
    local names = {}
    for name in pairs(NCB.db.profiles or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function NCB.SaveProfile(name)
    name = ProfileTrim(name)
    if name == "" then return false end
    local snap = {}
    for k, v in pairs(NCB.db) do
        if not PROFILE_SKIP[k] then snap[k] = ProfileDeepCopy(v) end
    end
    NCB.db.profiles[name] = snap
    NCB.db.activeProfile = name
    return true
end

function NCB.LoadProfile(name)
    local snap = NCB.db.profiles and NCB.db.profiles[name]
    if not snap then return false end
    for k, v in pairs(snap) do
        if not PROFILE_SKIP[k] then NCB.db[k] = ProfileDeepCopy(v) end
    end
    NCB.db.activeProfile = name
    if NCB.Display and NCB.Display.Rebuild then NCB.Display:Rebuild() end
    if NCB.RefreshOptions then NCB.RefreshOptions() end
    return true
end


-- Which profile the current settings correspond to.
--
-- Returns the name and whether the live settings still MATCH it. Loading a profile
-- and then nudging one slider leaves you on "Raid, modified" - which is the honest
-- answer, and the one that stops somebody assuming their change was saved.
local function ProfileSnapshot()
    local snap = {}
    for k, v in pairs(NCB.db) do
        if not PROFILE_SKIP[k] then snap[k] = ProfileDeepCopy(v) end
    end
    return snap
end

local function SameSettings(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not SameSettings(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function NCB.ProfileStatus()
    local name = NCB.db.activeProfile
    local stored = name and NCB.db.profiles and NCB.db.profiles[name]
    if not stored then return nil, false end
    return name, SameSettings(ProfileSnapshot(), stored)
end

function NCB.DeleteProfile(name)
    name = ProfileTrim(name)
    if not (NCB.db.profiles and NCB.db.profiles[name]) then return false end
    NCB.db.profiles[name] = nil
    return true
end


function NCB.ResourceConfig(key)
    return NCB.db and NCB.db.resources[key]
end

-- Reset back to the shipped look. Position is included: a "reset" that leaves the
-- display somewhere you cannot find is not a reset.
function NCB.ResetAll()
    if not NCB.db then return end
    for _, section in ipairs({ "anchor", "look", "behaviour", "extras" }) do
        local t = NCB.db[section]
        for k in pairs(t) do t[k] = nil end
        CopyDefaults(t, NCB.defaults[section])
    end
    NCB.db.resources = {}
    for _, res in ipairs(NCB.RESOURCES) do
        NCB.db.resources[res.key] = CopyDefaults({}, {
            enabled      = true,
            hideBlizzard = true,
            color        = { res.color[1], res.color[2], res.color[3] },
            perPointColor= res.perPointColor and true or false,
        })
    end
    NCB.Display:Rebuild()
end

--------------------------------------------------------------------------------
-- nugsSuite
--------------------------------------------------------------------------------
-- One entry in a plain global table, which the nugsSuite launcher reads to list
-- this addon, open its options and carry its settings between characters.
--
-- Written unconditionally and without checking whether nugsSuite exists: the table
-- is inert on its own, so this costs nothing when the suite is not installed, and
-- being a global rather than a call into it means neither addon has to load first.
--
-- The effective defaults are rebuilt rather than handing over NCB.defaults, whose
-- resources block starts empty and is seeded per resource by InitDB. Without that,
-- every resource colour would read as changed from default.
local function EffectiveDefaults()
    local eff = CopyDefaults({}, NCB.defaults)
    eff.resources = {}
    for _, res in ipairs(NCB.RESOURCES) do
        eff.resources[res.key] = CopyDefaults({}, {
            enabled      = true,
            hideBlizzard = true,
            color        = { res.color[1], res.color[2], res.color[3] },
            perPointColor= res.perPointColor and true or false,
        })
    end
    return eff
end

local function RegisterWithSuite()
    _G.nugsSuiteRegistry = _G.nugsSuiteRegistry or {}
    _G.nugsSuiteRegistry[ADDON_NAME] = {
        title      = "nugsComboBar",
        version    = NCB.version,
        icon       = "Interface\\AddOns\\nugsComboBar\\icon",
        slash      = "/ncb",
        Open       = function() NCB.ToggleOptions() end,
        SetMinimap = function(shown)
            NCB.db.minimapHidden = not shown
            NCB.SetMinimapShown(shown)
        end,
        GetDB      = function() return nugsComboBarDB, EffectiveDefaults() end,
        GetCharDB  = function() return nugsComboBarCharDB, NCB.charDefaults end,
        -- Where this button sits is nobody else's business, and fullColoursRepaired
        -- is a one-shot migration flag rather than a setting - carrying it would
        -- have shown up in every export as a changed value.
        exclude    = { minimapAngle = true, fullColoursRepaired = true },
    }
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
        NCB.Display:Init()
        NCB.Resources:Init()
        if NCB.InitOptions then NCB.InitOptions() end
        RegisterWithSuite()

    elseif event == "PLAYER_LOGIN" then
        NCB.InitMinimap()
        NCB.Resources:Refresh()
        NCB.Display:Rebuild()
    end
end)

--------------------------------------------------------------------------------
-- Slash command
-- /ncb belongs to nugsCastBars, so this one answers to /ncb.
--------------------------------------------------------------------------------
local function Usage()
    NCB.Print("v" .. NCB.version .. " commands:")
    print("  |cffffd479/ncb|r - open the options window")
    print("  |cffffd479/ncb unlock|r / |cffffd479/ncb lock|r - drag the display into place")
    print("  |cffffd479/ncb test|r - cycle the pips so you can see the look")
    print("  |cffffd479/ncb on|r / |cffffd479/ncb off|r - master switch")
    print("  |cffffd479/ncb reset|r - back to the shipped look and position")
    print("  |cffffd479/ncb minimap|r - show or hide the minimap button")
    print("  |cffffd479/ncb diag|r - report what the addon sees for your spec")
    print("  |cffffd479/ncb probe|r - report the live state of the pip widgets")
end

SLASH_NUGSCOMBOBAR1 = "/ncb"
SLASH_NUGSCOMBOBAR2 = "/nugscombobar"
SlashCmdList["NUGSCOMBOBAR"] = function(msg)
    local db = NCB.db
    if not db then return end

    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd  = (cmd or ""):lower()
    rest = (rest or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        NCB.ToggleOptions()

    elseif cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        NCB.Display:Rebuild()
        NCB.Print("display " .. (db.enabled and "enabled" or "disabled") .. ".")

    elseif cmd == "unlock" then
        NCB.Display:ToggleLock(false)

    elseif cmd == "lock" then
        NCB.Display:ToggleLock(true)

    elseif cmd == "test" then
        NCB.Display:Test()

    elseif cmd == "diag" then
        NCB.Diagnostics()

    elseif cmd == "probe" then
        NCB.Display:Probe()

    elseif cmd == "minimap" then
        db.minimapHidden = not db.minimapHidden
        NCB.SetMinimapShown(not db.minimapHidden)
        NCB.Print("minimap button " .. (db.minimapHidden and "hidden" or "shown") .. ".")

    elseif cmd == "reset" then
        NCB.ResetAll()
        NCB.Print("reset to defaults.")

    else
        Usage()
    end

    if NCB.RefreshOptions then NCB.RefreshOptions() end
end
