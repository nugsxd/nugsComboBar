--------------------------------------------------------------------------------
-- nugsComboBar
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsComboBar  -  Resources.lua
-- What resource this character has, how many pips it needs, and how full it is.
-- Everything class- and spec-specific lives here; Display.lua only ever asks for
-- "how many pips" and "what value do I feed them".
--
-- The 12.0 shape of this problem is not the one it looks like. A class resource
-- used to be a power type and nothing else, and half of them no longer are:
-- Maelstrom Weapon, Icicles and Tip of the Spear are buff stacks, and Vengeance's
-- Soul Fragments are a cast count. Each of those needs its own reader and its own
-- event, so a resource here is a small table with a Value function rather than a
-- power-type constant.
--------------------------------------------------------------------------------
local ADDON_NAME, NCB = ...

local Plain = NCB.Plain

local UnitPower       = UnitPower
local UnitPowerMax    = UnitPowerMax
local UnitStagger     = UnitStagger
local UnitHealthMax   = UnitHealthMax
local GetRuneCooldown = GetRuneCooldown

-- 12.0 moved both of these behind namespaces, but the old globals are still around
-- on some builds; take whichever exists so the addon does not care which patch it
-- is loaded on.
local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
                          or _G.GetSpecialization
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local GetSpellCastCount      = C_Spell and C_Spell.GetSpellCastCount
local GetSpellMaxCumulativeAuraApplications =
      C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
local GetCollapsingStarCost  = _G.GetCollapsingStarCost
local GetUnitChargedPowerPoints = _G.GetUnitChargedPowerPoints
local GetShapeshiftFormID    = _G.GetShapeshiftFormID

local PT = Enum and Enum.PowerType or {}

--------------------------------------------------------------------------------
-- Spec indices
-- GetSpecialization returns the tab number, not the spec ID, and those numbers are
-- stable. Named here so the class table below reads as English.
--------------------------------------------------------------------------------
local SPEC = {
    MAGE_ARCANE      = 1,
    MAGE_FROST       = 3,
    MONK_BREWMASTER  = 1,
    MONK_WINDWALKER  = 3,
    SHAMAN_ENHANCE   = 2,
    HUNTER_SURVIVAL  = 3,
    DH_VENGEANCE     = 2,
    DH_DEVOURER      = 3,
    WARLOCK_DESTRO   = 3,
    PRIEST_SHADOW    = 3,
    EVOKER_AUGMENT   = 3,
}

local DRUID_CAT_FORM = 1

-- Buff/spell IDs used as resource proxies. Confirmed against oUF's classpower
-- element on retail 12.0.7.
local SPELL_MAELSTROM   = 344179
local SPELL_ICICLES     = 205473
local SPELL_SPEAR_TIP   = 260286
local SPELL_SOUL_CLEAVE = 228477

-- Devourer. Its souls are Dark Heart stacks, except while Void Metamorphosis is up,
-- when the stacks live on Silence the Whispers instead - so the aura being counted
-- changes mid-fight, and so does the cap.
local SPELL_DARK_HEART        = 1225789
local SPELL_SILENCE_WHISPERS  = 1227702
local SPELL_VOID_METAMORPHOSIS = 1217607

--------------------------------------------------------------------------------
-- Readers
--
-- Every reader may hand back a SECRET number, and that is fine: the value's only
-- destination is StatusBar:SetValue, which is a display sink. Nothing in this file
-- compares, adds to, or formats a resource value - see the pip layout in Display.lua
-- for why it never needs to.
--------------------------------------------------------------------------------
local function PowerValue(res)
    return UnitPower("player", res.powerType)
end

-- Destruction reads its shards in tenths so the partly-built shard shows as a
-- part-filled pip. `unmodified = true` is what returns the fine-grained number.
local function FragmentValue(res)
    return UnitPower("player", res.powerType, true)
end

-- Buff stacks. `applications` is one of the fields 12.0 made secret, so it is read
-- and passed straight through without ever being looked at.
local function AuraValue(res)
    if not GetPlayerAuraBySpellID then return 0 end
    local ok, aura = pcall(GetPlayerAuraBySpellID, res.spellID)
    if not ok or not aura then return 0 end
    return aura.applications or 0
end

-- Devourer souls. Which aura carries the stacks depends on whether Void
-- Metamorphosis is up, so the aura is chosen first and read second.
local function DevourerAura()
    if not GetPlayerAuraBySpellID then return SPELL_DARK_HEART, false end
    local ok, meta = pcall(GetPlayerAuraBySpellID, SPELL_VOID_METAMORPHOSIS)
    -- A secret aura table is still safe to truth-test; only its fields are barred.
    if ok and meta then return SPELL_SILENCE_WHISPERS, true end
    return SPELL_DARK_HEART, false
end

local function DevourerValue()
    if not GetPlayerAuraBySpellID then return 0 end
    local spellID = DevourerAura()
    local ok, aura = pcall(GetPlayerAuraBySpellID, spellID)
    if not ok or not aura then return 0 end
    return aura.applications or 0
end

-- The cap is not a constant. Normally it is Dark Heart's own maximum stack count;
-- during Void Metamorphosis it is whatever Collapsing Star currently costs. Either
-- can come back secret or missing, so the last good answer is kept.
local lastDevourerCap
local function DevourerCap()
    local _, inMeta = DevourerAura()
    local value
    if inMeta and GetCollapsingStarCost then
        local ok, v = pcall(GetCollapsingStarCost)
        if ok then value = Plain(v) end
    elseif GetSpellMaxCumulativeAuraApplications then
        local ok, v = pcall(GetSpellMaxCumulativeAuraApplications, SPELL_DARK_HEART)
        if ok then value = Plain(v) end
    end
    if value and value > 0 then
        lastDevourerCap = math.floor(value)
        return lastDevourerCap
    end
    return lastDevourerCap or 5
end
NCB.DevourerCap = DevourerCap

-- Where a threshold line belongs on the bar, as a fraction of it.
--
-- Prefers a SPELL's actual cost over a number somebody typed, because the cost is not
-- a constant: Shadow Word: Madness costs 50 Insanity, or 45 with the talent that
-- reduces it, and a mark drawn at a remembered 50 would be wrong for anybody who took
-- it. Asking the client means the line moves when the talent does.
--
-- Falls back to the manual percentage, which is also the answer on a client whose
-- spell names are not English - the lookup below is by name, and the registry can
-- only carry one.
local function MarkFraction(res, cfg)
    if not (res and cfg) then return nil end

    local spell = res.markSpell
    if spell and C_Spell and C_Spell.GetSpellPowerCost and res.powerType then
        local id = spell
        if type(id) == "string" and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spell)
            id = (ok and info and info.spellID) or nil
        end

        if id then
            local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
            if ok and type(costs) == "table" then
                for _, entry in ipairs(costs) do
                    local cost = Plain(entry and entry.cost)
                    if cost and cost > 0 and entry.type == res.powerType then
                        local max = Plain(UnitPowerMax("player", res.powerType))
                        if max and max > 0 then return cost / max end
                    end
                end
            end
        end
    end

    local at = tonumber(cfg.markAt) or 0
    if at > 0 and at < 100 then return at / 100 end

    -- A resource that has an obvious threshold gets a line without anybody setting
    -- one. The slider defaults to zero and a zero means "off", so a resource whose
    -- whole point is a threshold would otherwise ship with no line and no clue that
    -- there was one to turn on.
    if res.markDefault then return res.markDefault / 100 end
    return nil
end

local function CastCountValue(res)
    if not GetSpellCastCount then return 0 end
    local ok, count = pcall(GetSpellCastCount, res.spellID)
    if not ok then return 0 end
    return count or 0
end

--------------------------------------------------------------------------------
-- The registry
--
-- `max` is the pip count to fall back on when UnitPowerMax cannot be read. `scale`
-- is how many raw units make one pip, which is 1 for everything except Destruction
-- shards - a pip there spans ten fragments.
--------------------------------------------------------------------------------
NCB.RESOURCES = {
    {
        key = "combo", label = "Combo Points", short = "CP",
        powerType = PT.ComboPoints or 4, Value = PowerValue,
        max = 5, hardMax = 10,
        color = { 0.90, 0.24, 0.24 },
        charged = true,          -- Supercharged points get their own colour
        blizz = { "RogueComboPointBarFrame", "DruidComboPointBarFrame" },
        events = { "UNIT_POWER_POINT_CHARGE" },
    },
    {
        key = "holyPower", label = "Holy Power", short = "HP",
        powerType = PT.HolyPower or 9, Value = PowerValue,
        max = 5, hardMax = 5,
        color = { 0.96, 0.88, 0.50 },
        blizz = { "PaladinPowerBarFrame" },
    },
    {
        key = "chi", label = "Chi", short = "Chi",
        powerType = PT.Chi or 12, Value = PowerValue,
        max = 5, hardMax = 6,
        color = { 0.35, 0.92, 0.72 },
        blizz = { "MonkHarmonyBarFrame" },
    },
    {
        key = "soulShards", label = "Soul Shards", short = "Shards",
        powerType = PT.SoulShards or 7, Value = PowerValue,
        max = 5, hardMax = 5,
        color = { 0.62, 0.38, 0.94 },
        blizz = { "WarlockPowerFrame" },
    },
    {
        -- Destruction only. Same power type as above, read at ten times the
        -- resolution, so the shard being built shows as a partly filled pip.
        key = "soulFragments", label = "Soul Shards (Destruction)", short = "Shards",
        powerType = PT.SoulShards or 7, Value = FragmentValue,
        -- The pips are fed fragments so the shard in progress part-fills, but the
        -- number next to them should read in whole shards.
        CountValue = PowerValue,
        max = 5, hardMax = 5, scale = 10,
        color = { 0.62, 0.38, 0.94 },
        blizz = { "WarlockPowerFrame" },
    },
    {
        -- Shadow. A pip is one Devouring Plague, not one point.
        --
        -- Insanity runs 0-100 and a hundred pips is not a readout, it is wallpaper.
        -- Fifty is what a cast costs, so two pips answer the question a Shadow priest
        -- actually asks - have I got one banked, and how close is the next - with the
        -- pip in progress part-filling exactly as a Destruction shard does. The number
        -- beside them still reads in raw Insanity, because that is what the rest of
        -- the game shows you.
        key = "insanity", label = "Insanity", short = "Insanity",
        powerType = PT.Insanity or 13, Value = PowerValue,
        CountValue = PowerValue,
        max = 2, hardMax = 2,
        -- The spender the bar is really about, so a threshold line can follow its
        -- real cost rather than a number that goes stale with a talent.
        markSpell = "Shadow Word: Madness",
        -- What it costs untalented, used when the cost cannot be read - on a client
        -- whose spell names are not English, or before the spellbook is loaded.
        markDefault = 50,
        -- Half the bar per pip, measured rather than assumed. See PipShape.
        Scale = function()
            local max = Plain(UnitPowerMax("player", PT.Insanity or 13))
            if max and max > 0 then return max / 2 end
            return 50
        end,
        color = { 0.52, 0.32, 0.88 },
    },
    {
        key = "arcaneCharges", label = "Arcane Charges", short = "Charges",
        powerType = PT.ArcaneCharges or 16, Value = PowerValue,
        max = 4, hardMax = 4,
        color = { 0.42, 0.62, 1.00 },
        blizz = { "MageArcaneChargesFrame" },
    },
    {
        key = "runes", label = "Runes", short = "Runes",
        powerType = PT.Runes or 5, Value = PowerValue,
        max = 6, hardMax = 6,
        color = { 0.35, 0.78, 0.96 },
        recharging = true,       -- spent runes sweep as they come back
        blizz = { "RuneFrame" },
        events = { "RUNE_POWER_UPDATE" },
    },
    {
        key = "essence", label = "Essence", short = "Essence",
        powerType = PT.Essence or 19, Value = PowerValue,
        max = 6, hardMax = 6,
        color = { 0.34, 0.82, 0.86 },
        recharging = true,
        blizz = { "EssencePlayerFrame" },
    },

    ----------------------------------------------------------------------------
    -- Resources that are not power types in 12.0. Same pips, different reader.
    ----------------------------------------------------------------------------
    {
        key = "maelstrom", label = "Maelstrom Weapon", short = "MSW",
        spellID = SPELL_MAELSTROM, Value = AuraValue, aura = true,
        max = 10, hardMax = 10, extra = true,
        color = { 0.20, 0.62, 0.98 },
    },
    {
        key = "icicles", label = "Icicles", short = "Icicles",
        spellID = SPELL_ICICLES, Value = AuraValue, aura = true,
        max = 5, hardMax = 5, extra = true,
        color = { 0.72, 0.92, 1.00 },
    },
    {
        key = "spearTip", label = "Tip of the Spear", short = "Tip",
        spellID = SPELL_SPEAR_TIP, Value = AuraValue, aura = true,
        max = 3, hardMax = 3, extra = true,
        color = { 0.62, 0.86, 0.36 },
    },
    {
        key = "soulCleave", label = "Soul Fragments", short = "Fragments",
        spellID = SPELL_SOUL_CLEAVE, Value = CastCountValue, castCount = true,
        max = 5, hardMax = 6, extra = true,
        color = { 0.72, 0.34, 0.86 },
        events = { "SPELL_UPDATE_CHARGES" },
    },
    {
        -- Devourer. `dynamic` means the pip count and the scale are recomputed on
        -- every value change rather than only on a spec change, because entering
        -- Void Metamorphosis moves the stacks to a different aura AND changes the cap.
        key = "devourerSouls", label = "Souls (Devourer)", short = "Souls",
        Value = DevourerValue, aura = true, dynamic = true,
        Cap = DevourerCap,
        max = 5, hardMax = 5, extra = true,
        color = { 0.55, 0.28, 0.72 },
    },
}

-- Above this, a row of pips stops being readable and the resource is drawn as one
-- pip that fills like a bar instead. Only Devourer can reach it.
NCB.PIP_LIMIT = 10

function NCB.ResourceByKey(key)
    for _, res in ipairs(NCB.RESOURCES) do
        if res.key == key then return res end
    end
end

--------------------------------------------------------------------------------
-- Class -> resource
-- Returns the key of the resource this character is currently showing, or nil.
-- Called on every event that could change the answer, so it must be cheap and must
-- never assume the spec has finished loading.
--------------------------------------------------------------------------------
local function ResolveKey(class, spec)
    if class == "ROGUE" then
        return "combo"

    elseif class == "DRUID" then
        -- Feral's points only exist in cat form, and Blizzard hides its own bar
        -- outside it. Matching that is less surprising than a row of dead pips.
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        return (form == DRUID_CAT_FORM) and "combo" or nil

    elseif class == "PALADIN" then
        return "holyPower"

    elseif class == "MONK" then
        return (spec == SPEC.MONK_WINDWALKER) and "chi" or nil

    elseif class == "WARLOCK" then
        return (spec == SPEC.WARLOCK_DESTRO) and "soulFragments" or "soulShards"

    elseif class == "MAGE" then
        if spec == SPEC.MAGE_ARCANE then return "arcaneCharges" end
        if spec == SPEC.MAGE_FROST  then return "icicles" end
        return nil

    elseif class == "DEATHKNIGHT" then
        return "runes"

    elseif class == "EVOKER" then
        return "essence"

    elseif class == "SHAMAN" then
        return (spec == SPEC.SHAMAN_ENHANCE) and "maelstrom" or nil

    elseif class == "HUNTER" then
        return (spec == SPEC.HUNTER_SURVIVAL) and "spearTip" or nil

    elseif class == "PRIEST" then
        -- Discipline and Holy have no Insanity at all, so they get nothing rather
        -- than a row of pips that can never fill.
        return (spec == SPEC.PRIEST_SHADOW) and "insanity" or nil

    elseif class == "DEMONHUNTER" then
        if spec == SPEC.DH_VENGEANCE then return "soulCleave" end
        if spec == SPEC.DH_DEVOURER  then return "devourerSouls" end
        return nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- Engine
--------------------------------------------------------------------------------
local Resources = {}
NCB.Resources = Resources

Resources.active   = nil     -- registry entry currently on screen
Resources.maxPips  = 0
Resources.class    = nil
Resources.spec     = nil
Resources.staggerShown = false

-- Last known good pip count. UnitPowerMax can come back secret, and a resource that
-- silently collapses to zero pips mid-pull is worse than one that keeps drawing the
-- count it had a moment ago.
local lastGoodMax = {}

-- Pip count and scale together, because for a dynamic resource they trade off:
-- a cap small enough to read gets one pip each, and a larger one collapses to a
-- single pip that fills like a bar (scale = the whole cap).
-- Whether this resource is set to draw as one bar rather than a row of pips.
--
-- Pips answer "how many have I got" and are the right shape for five combo points.
-- A bar answers "how full am I", which is the right shape for something like
-- Insanity that moves continuously and has no meaningful individual point. Both are
-- legitimate readings of a class resource, so it is a per-resource choice rather
-- than a judgement made here.
local function BarMode(res)
    local cfg = res and NCB.ResourceConfig and NCB.ResourceConfig(res.key)
    return (cfg and cfg.barMode) and true or false
end

-- The shape this resource has on its own, before any bar-mode preference.
local function NaturalShape(res)
    if not res then return 0, 1 end
    if res.Cap then
        local cap = res.Cap()
        if cap <= NCB.PIP_LIMIT then return cap, 1 end
        return 1, cap
    end
    -- A scale the client answers rather than a number written down here. Used where
    -- the raw units behind a resource are not knowable from a wiki: Insanity is shown
    -- as 0-100 but has been stored at ten times that, and a hard-coded 50 would be
    -- silently wrong on whichever of the two this build uses.
    if res.Scale then
        local scale = res.Scale()
        if scale and scale > 0 then return nil, scale end
    end
    return nil, res.scale or 1
end

local function NaturalCount(res)
    if not res then return 0 end

    local dynamic = NaturalShape(res)
    if dynamic then return dynamic end

    -- Talents raise the combo point cap, and the choice is whether that adds pips
    -- or squeezes the ones already there. Adding them is the default; capping at
    -- five is for people who have muscle memory for a five-wide row.
    local cap = res.hardMax
    if res.key == "combo" and NCB.db and not NCB.db.extras.comboAnticipation then
        cap = res.max
    end

    if res.powerType then
        local raw = Plain(UnitPowerMax("player", res.powerType))
        if raw and raw > 0 then
            local n = math.min(raw, cap or raw)
            lastGoodMax[res.key] = n
            return n
        end
    end
    return math.min(lastGoodMax[res.key] or res.max or 0, cap or math.huge)
end

-- Bar mode is the natural shape collapsed into a single pip that spans the lot.
--
-- Deliberately built ON TOP of the pip layout rather than beside it. The display
-- already draws one pip filling like a bar - that is what a resource too large to
-- read as pips falls back to - so a bar is not a second way of drawing, it is the
-- same way with a count of one. Nothing in Display.lua had to learn about it.
local function PipShape(res)
    if not res then return 0, 1 end

    local pips, scale = NaturalShape(res)
    if not BarMode(res) then return pips, scale end

    local count = pips or NaturalCount(res)
    return 1, math.max(1, count * (scale or 1))
end

local function PipCount(res)
    if not res then return 0 end
    if BarMode(res) then return 1 end
    return NaturalCount(res)
end

function Resources:Detect()
    local _, class = UnitClass("player")
    local spec = GetSpecialization and GetSpecialization() or nil
    self.class, self.spec = class, spec

    local key = ResolveKey(class, spec)
    local res = key and NCB.ResourceByKey(key) or nil

    -- A resource the user has switched off in the options is treated exactly as if
    -- the class did not have one.
    local cfg = res and NCB.ResourceConfig(res.key)
    if cfg and not cfg.enabled then res = nil end

    self.active  = res
    self.maxPips = PipCount(res)
    -- How many raw units one pip spans. Static for everything except Devourer.
    local _, scale = PipShape(res)
    self.scale = scale or 1

    -- How many pips' worth of WIDTH the row occupies.
    --
    -- Normally one per pip. In bar mode there is a single pip, and without this it
    -- would be drawn one pip wide - a stub, not a bar. Spanning what the pips would
    -- have spanned means switching between the two modes changes the shape of the
    -- display without moving it or changing how much room it takes, which is the
    -- behaviour somebody toggling back and forth to compare them expects.
    self.barSpan = (res and BarMode(res)) and math.max(1, NaturalCount(res)) or 1

    -- Part of the resolved shape, so a cost that moves because a talent changed
    -- redraws the line instead of leaving it where it was.
    self.markFrac = MarkFraction(res, res and NCB.ResourceConfig(res.key))

    -- Brewmaster's Stagger rides alongside whatever else is on screen, so it is
    -- resolved separately rather than competing for the one resource slot.
    self.staggerShown = (class == "MONK" and spec == SPEC.MONK_BREWMASTER
                         and NCB.db and NCB.db.extras.stagger and UnitStagger ~= nil) or false

    return res
end

-- How many raw units one pip spans. Everything that draws must go through this
-- rather than reading res.scale, because for Devourer it changes mid-fight.
function Resources:Scale()
    return self.scale or (self.active and self.active.scale) or 1
end

-- The number the pips are fed. May be secret; that is the whole point of the pip
-- layout, and nothing here inspects it.
function Resources:Value()
    local res = self.active
    if not res then return 0 end
    local ok, value = pcall(res.Value, res)
    if not ok then return 0 end
    return value or 0
end

-- Which points are Supercharged, as a lookup. Purely cosmetic, and skipped entirely
-- if the API hands back something we cannot walk.
function Resources:ChargedPoints()
    local res = self.active
    if not (res and res.charged and GetUnitChargedPowerPoints) then return nil end
    local ok, list = pcall(GetUnitChargedPowerPoints, "player")
    if not ok or type(list) ~= "table" then return nil end
    local lookup = {}
    for _, index in ipairs(list) do
        local i = Plain(index)
        if i then lookup[i] = true end
    end
    return lookup
end

-- Rune recharge, for the sweep on a spent pip. Runes are the only resource that
-- refills one unit at a time on its own clock.
function Resources:RuneCooldown(index)
    if not GetRuneCooldown then return nil end
    local ok, start, duration, ready = pcall(GetRuneCooldown, index)
    if not ok then return nil end
    return Plain(start), Plain(duration), ready
end

function Resources:Stagger()
    if not (UnitStagger and UnitHealthMax) then return nil, nil end
    -- Blizzard's own code nil-checks this return, and it can also come back secret,
    -- so it goes straight to the bar without being looked at.
    local ok, cur = pcall(UnitStagger, "player")
    if not ok then return nil, nil end
    return cur, UnitHealthMax("player")
end

--------------------------------------------------------------------------------
-- Blizzard's own resource frames
-- These are protected, so touching them in combat taints; every call is gated on
-- InCombatLockdown and the work is re-run when combat drops.
--------------------------------------------------------------------------------
local blizzardPending = false

function Resources:ApplyBlizzardVisibility()
    if InCombatLockdown() then
        blizzardPending = true
        return
    end
    blizzardPending = false
    if not NCB.db then return end

    for _, res in ipairs(NCB.RESOURCES) do
        if res.blizz then
            local cfg = NCB.ResourceConfig(res.key)
            local hide = cfg and cfg.enabled and cfg.hideBlizzard
            for _, name in ipairs(res.blizz) do
                local frame = _G[name]
                if frame then
                    if hide then
                        frame:Hide()
                    else
                        frame:Show()
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Events
-- Value changes come from UNIT_POWER_FREQUENT for real power types and UNIT_AURA
-- for the stack-based ones; everything else on this list can change *which*
-- resource is on screen or *how many* pips it needs.
--------------------------------------------------------------------------------
local frame = CreateFrame("Frame")

local VALUE_EVENTS = {
    UNIT_POWER_FREQUENT      = true,
    UNIT_POWER_UPDATE        = true,
    UNIT_AURA                = true,
    RUNE_POWER_UPDATE        = true,
    UNIT_POWER_POINT_CHARGE  = true,
    SPELL_UPDATE_CHARGES     = true,
}

local SHAPE_EVENTS = {
    PLAYER_SPECIALIZATION_CHANGED = true,
    PLAYER_TALENT_UPDATE          = true,
    UPDATE_SHAPESHIFT_FORM        = true,
    UNIT_MAXPOWER                 = true,
    UNIT_DISPLAYPOWER             = true,
    SPELLS_CHANGED                = true,
    PLAYER_ENTERING_WORLD         = true,
}

function Resources:Init()
    -- Unit events are filtered to the player, so nothing in a raid's worth of power
    -- updates ever reaches this addon.
    frame:RegisterUnitEvent("UNIT_POWER_FREQUENT",     "player")
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE",       "player")
    frame:RegisterUnitEvent("UNIT_MAXPOWER",           "player")
    frame:RegisterUnitEvent("UNIT_DISPLAYPOWER",       "player")
    frame:RegisterUnitEvent("UNIT_AURA",               "player")
    frame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    -- Yours only: plainly registered, this fires for every party member, arena
    -- opponent and nameplate too.
    pcall(frame.RegisterUnitEvent, frame, "PLAYER_SPECIALIZATION_CHANGED", "player")

    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TALENT_UPDATE", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED",
        "RUNE_POWER_UPDATE", "SPELL_UPDATE_CHARGES",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE",
        "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and blizzardPending then
            Resources:ApplyBlizzardVisibility()
        end

        if SHAPE_EVENTS[event] or event == "PLAYER_REGEN_ENABLED" then
            Resources:Refresh()
        elseif VALUE_EVENTS[event] then
            -- A dynamic resource can change how many pips it needs on the same event
            -- that changes its value, so it re-resolves rather than just redrawing.
            -- Refresh only rebuilds when something actually moved.
            if Resources.active and Resources.active.dynamic then
                Resources:Refresh()
            else
                NCB.Display:Update()
            end
        else
            -- vehicle and pet battle transitions: visibility only
            NCB.Display:UpdateVisibility()
        end
    end)
end

-- Re-resolve which resource is active and rebuild the pips if the answer changed.
function Resources:Refresh()
    local before, beforeMax, beforeScale = self.active, self.maxPips, self.scale
    local beforeMark = self.markFrac
    self:Detect()
    self:ApplyBlizzardVisibility()

    -- Scale is in the comparison for Devourer: entering Void Metamorphosis changes
    -- the cap without changing the resource, and the pips have to be re-ranged.
    if self.active ~= before or self.maxPips ~= beforeMax or self.scale ~= beforeScale
       or self.markFrac ~= beforeMark then
        NCB.Display:Rebuild()
    else
        NCB.Display:Update()
    end
end

--------------------------------------------------------------------------------
-- Diagnostics
-- Says what the addon can actually see, which is the first question worth asking
-- when a resource does not show up.
--------------------------------------------------------------------------------
function NCB.Diagnostics()
    NCB.Print("v" .. NCB.version .. " diagnostics")
    print(("  class: |cffffd479%s|r   spec: |cffffd479%s|r")
        :format(tostring(Resources.class), tostring(Resources.spec)))

    local res = Resources.active
    if not res then
        print("  |cffff8080no class resource for this spec|r - nothing to draw.")
    else
        print(("  resource: |cffffd479%s|r (%s), pips: |cffffd479%d|r")
            :format(res.label, res.key, Resources.maxPips))

        -- The bar and its threshold line, because "I cannot see the mark" has three
        -- possible causes - not in bar mode, no fraction resolved, or resolved and
        -- drawn somewhere unexpected - and they are indistinguishable on screen.
        local cfg = NCB.ResourceConfig(res.key)
        print(("  bar mode: |cffffd479%s|r   span: |cffffd479%s|r")
            :format(tostring(cfg and cfg.barMode and true or false),
                    tostring(Resources.barSpan)))
        if Resources.markFrac then
            print(("  mark at: |cffffd479%.1f%%|r of the bar%s")
                :format(Resources.markFrac * 100,
                        res.markSpell and ("  (following " .. tostring(res.markSpell) .. ")")
                                       or ""))
        else
            print("  mark: |cff808080none|r - set 'Mark at' under this resource.")
        end
        local value = Resources:Value()
        if NCB.IsSecret(value) then
            print("  value: |cff8cd2ffsecret|r - fed straight to the pips, which is fine.")
        else
            print(("  value: |cffffd479%s|r"):format(tostring(value)))
        end
        print(("  source: %s"):format(
            res.aura and "buff stacks" or res.castCount and "cast count" or "power type"))
        if res.Cap then
            -- Devourer's cap is not a constant and I could not verify it offline, so
            -- it is reported rather than assumed.
            local cap = res.Cap()
            print(("  cap: |cffffd479%d|r  scale: |cffffd479%d|r per pip  %s")
                :format(cap, Resources:Scale(),
                        cap > NCB.PIP_LIMIT and "|cff8cd2ff(drawn as one filling bar)|r"
                        or "(one pip each)"))
        end
    end

    print(("  stagger bar: %s"):format(Resources.staggerShown and "on" or "off"))
    print(("  secrets in this client: %s"):format(NCB.secretsExist and "yes" or "no"))

    -- What the display actually managed to apply. Everything below here exists
    -- because "the options are all there but nothing happens" is otherwise
    -- indistinguishable from "the setting did nothing", and the difference is
    -- usually one widget call that quietly threw.
    local L = NCB.db and NCB.db.look
    if L then
        print(("  shape: |cffffd479%s|r   border: |cffffd479%s|r   empty: |cffffd479%s|r")
            :format(tostring(L.shape),
                    L.showBorder and (L.borderSize .. "px") or "off",
                    tostring(L.emptyStyle)))
        print(("  at max - glow: |cffffd479%s|r  recolour: |cffffd479%s|r")
            :format(L.fullGlow and "on" or "off", L.fullHighlight and "on" or "off"))
    end

    local p = NCB.Display and NCB.Display:Presence()
    if p then
        print(("  pips built: |cffffd479%d|r  shown: |cffffd479%d|r  on screen: %s  alpha: |cffffd479%.2f|r")
            :format(p.built, p.shown,
                    p.visible and "|cff80ff80yes|r" or "|cffff8080NO|r", p.alpha))
        if p.built == 0 then
            print("  |cffff8080Nothing of ours is drawn.|r Any pips you can see are " ..
                  "Blizzard's, which is why nothing here changes them.")
        end
    end

    local masksOK = NCB.Display and NCB.Display:MasksWorking()
    if masksOK == nil then
        print("  pip masks: |cff999999no pips built yet|r")
    else
        print(("  pip masks: %s"):format(masksOK and "|cff80ff80applied|r"
            or "|cffff8080FAILED - shapes and the outline border are off|r"))
    end

    local any = false
    for label, err in pairs(NCB.errors or {}) do
        any = true
        print(("  |cffff8080error in %s:|r %s"):format(label, err))
    end
    if not any then
        print("  |cff80ff80no errors recorded|r")
    else
        print("  |cffffd479Send the lines above - that is the actual fault.|r")
    end
end
