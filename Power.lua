--------------------------------------------------------------------------------
-- nugsComboBar
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsComboBar  -  Power.lua
-- Resource BARS: Energy, Fury, Rage, Focus, Runic Power, Insanity, Mana.
--
-- Separate displays rather than more entries in the resource registry, because the
-- two answer different questions and a rogue needs both at once. Combo points are a
-- countable thing spent in whole units, which is what the pip row is for; energy is
-- a pool that refills on its own, which is a bar. Havoc has only the second kind and
-- until now got nothing at all.
--
-- TWO of them, because one is not enough for a real class. Shadow spends Insanity
-- and still has Mana; a resto druid in cat form has Energy and Mana. The primary
-- follows whatever the character is currently spending; the second is chosen, and
-- defaults to Mana because that is the pairing that keeps coming up.
--
-- Each has its own anchor and its own position, so they sit where they are useful
-- rather than where the points happen to be. Stagger stays welded to the pip row
-- because it belongs to that display; these do not.
--
-- NO CLASS TABLE.
--
-- UnitPowerType("player") already answers "what does this character spend", and it
-- answers it for specs and forms this addon has never heard of: Havoc gets Fury,
-- Shadow gets Insanity, a druid gets Energy in cat and Rage in bear, and a spec
-- added in a later patch gets whatever it was given. Every other resource in this
-- addon needed a table because the client would not answer; this one would only be
-- made wrong by writing one.
--------------------------------------------------------------------------------
local ADDON_NAME, NCB = ...

local Plain = NCB.Plain

local UnitPower     = UnitPower
local UnitPowerMax  = UnitPowerMax
local UnitPowerType = UnitPowerType

local PT = Enum and Enum.PowerType or {}

NCB.Power = {}

-- What the second bar may be set to. Deliberately short: these are the ones a class
-- actually carries alongside a different primary. Anything else would be a list of
-- resources nobody has two of.
NCB.POWER_CHOICES = {
    { key = "mana",       label = "Mana",        type = PT.Mana or 0 },
    { key = "energy",     label = "Energy",      type = PT.Energy or 3 },
    { key = "rage",       label = "Rage",        type = PT.Rage or 1 },
    { key = "focus",      label = "Focus",       type = PT.Focus or 2 },
    { key = "runicPower", label = "Runic Power", type = PT.RunicPower or 6 },
    { key = "fury",       label = "Fury",        type = PT.Fury or 17 },
    { key = "insanity",   label = "Insanity",    type = PT.Insanity or 13 },
    { key = "maelstrom",  label = "Maelstrom",   type = PT.Maelstrom or 11 },
    { key = "astral",     label = "Astral Power", type = PT.LunarPower or 8 },
}

local function TypeForChoice(key)
    for _, entry in ipairs(NCB.POWER_CHOICES) do
        if entry.key == key then return entry.type end
    end
    return PT.Mana or 0
end

-- The colour the game itself uses, so a bar reads as the thing it is without anybody
-- choosing a colour. PowerBarColor is keyed by the token the client hands back.
local function TokenColor(token)
    local c = token and _G.PowerBarColor and _G.PowerBarColor[token]
    if c and c.r then return c.r, c.g, c.b end
    return 0.35, 0.72, 1.00
end

--------------------------------------------------------------------------------
-- One bar
--------------------------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

-- id is the settings key: "power" for the primary, "power2" for the second.
function NCB.Power.New(id, labelText)
    return setmetatable({ id = id, labelText = labelText }, Bar)
end

function Bar:cfg() return NCB.db and NCB.db[self.id] end

-- The power type this bar is showing, and its token.
--
-- The primary asks the client. The second is told, and refuses to draw when it would
-- duplicate the primary - two identical bars stacked on each other is not a feature.
function Bar:Resolve()
    local c = self:cfg()
    if not c then return nil end

    local ok, primary, token = pcall(UnitPowerType, "player")
    if not ok then return nil end

    if self.id == "power" then return primary, token end

    local wanted = TypeForChoice(c.powerType)
    if wanted == primary then return nil end

    -- Only if the character actually has it. A warrior has no mana, and a bar that
    -- never moves is worse than no bar.
    local max = Plain(UnitPowerMax("player", wanted))
    if not (max and max > 0) then return nil end
    return wanted, nil
end

function Bar:SavePosition()
    local a = self:cfg() and self:cfg().anchor
    if not (a and self.frame) then return end
    -- The relative point goes with the point: StopMovingOrSizing is free to
    -- re-anchor to a different corner, and saving only one of the two makes the bar
    -- walk further across the screen on every reload.
    local point, _, relPoint, x, y = self.frame:GetPoint()
    a.point, a.relPoint, a.x, a.y = point, relPoint, x, y
end

function Bar:Restyle()
    local c, f = self:cfg(), self.frame
    if not (c and f) then return end

    local a = c.anchor or {}
    f:ClearAllPoints()
    f:SetPoint(a.point or "CENTER", UIParent, a.relPoint or a.point or "CENTER",
               a.x or 0, a.y or -180)
    f:SetScale(a.scale or 1)
    f:SetSize(c.width or 200, c.height or 14)

    f.tex:SetTexture(NCB.TexturePath(c.texture))
    f.bg:SetColorTexture(0, 0, 0, c.backdropAlpha or 0.6)

    local _, token = self:Resolve()
    if c.useClassColor then
        f.tex:SetVertexColor(TokenColor(token))
    else
        local col = c.color or { 0.35, 0.72, 1.00 }
        f.tex:SetVertexColor(col[1], col[2], col[3])
    end

    -- The pip row's font by default, so the display matches without setting the same
    -- thing twice. "Own font" breaks that per bar: a 14px bar and a row of 18px pips
    -- do not always want the same size, and a bar placed away from the pips has no
    -- row to match. The number colour stays shared either way.
    local L = NCB.db.look
    local src = c.ownFont and c or L
    pcall(f.text.SetFont, f.text, NCB.FontPath(src.font), src.fontSize or L.fontSize,
          src.fontOutline ~= "NONE" and src.fontOutline or "")
    f.text:SetTextColor(unpack(L.colorText))
    f.text:SetShown(c.textMode ~= "none")
    f.border:SetShown(c.showBorder and true or false)
end

function Bar:Update()
    local c, f = self:cfg(), self.frame
    if not (c and f) then return end

    if not (NCB.db.enabled and c.enabled) then
        f:Hide()
        return
    end

    local powerType = self:Resolve()
    if not powerType then
        f:Hide()
        return
    end

    -- The max may come back secret, in which case the last one the client did state
    -- stands in. A range that collapses to 0..1 for a moment reads as a full bar,
    -- which is worse than a range one second out of date.
    local max = Plain(UnitPowerMax("player", powerType))
    if max and max > 0 then self.lastMax = max end
    local range = self.lastMax or 100
    f:SetMinMaxValues(0, range)

    -- The value goes in raw, secret or not: SetValue is a display sink. Nothing in
    -- this file does arithmetic on it without laundering it through Plain first.
    local value = UnitPower("player", powerType)
    f:SetValue(value)

    local plain = Plain(value)
    if c.textMode ~= "none" then
        if c.textMode == "percent" and plain and range > 0 then
            f.text:SetText(("%d%%"):format(plain / range * 100))
        elseif c.textMode == "both" and plain and range > 0 then
            f.text:SetText(("%d / %d"):format(plain, range))
        else
            -- Also the fallback when the value is secret: it can be displayed, it
            -- just cannot be divided.
            f.text:SetText(value)
        end
    end

    -- "Hide when full" is a comparison, so it only applies when the value is
    -- readable. A secret value keeps the bar up, which is the safer way to be wrong,
    -- and placing it always keeps it up or there would be nothing to drag.
    if c.hideWhenFull and plain and self.lastMax and plain >= self.lastMax
       and not self.placing then
        f:Hide()
        return
    end

    f:Show()
end

function Bar:SetLocked(locked)
    self.placing = not locked
    local f = self.frame
    if not f then return end
    f.grip:SetShown(not locked)
    f.label:SetShown(not locked)
    f:EnableMouse(not locked)
    if not locked and self:cfg() and self:cfg().enabled then f:Show() end
end

function Bar:Init()
    if self.frame then return end

    local f = CreateFrame("StatusBar", "nugsComboBar" .. self.id, UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    -- Dragging, from the shared nugsMove.lua. Read the note at the top of that file:
    -- it asserts that a frame nobody is holding is not moving, rather than closing one
    -- more route by which a move could be left running.
    NCB.InstallMove(f, {
        label = "the power bar",
        -- The mouse belongs to the lock state, not to this call.
        mouse = false,
        -- Runs however the move ended, including when the invariant ended it because
        -- the mouse-up never arrived.
        onEnd = function() self:SavePosition() end,
    })

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f:SetStatusBarTexture(f.tex)

    -- One texture behind the bar, inset on every side: a border without four
    -- textures to keep in step.
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.9)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("CENTER")

    -- Something to grab while unlocked, for the same reason the pip row has one: a
    -- full energy bar on a class standing still is a rectangle you cannot find.
    f.grip = f:CreateTexture(nil, "BACKGROUND")
    f.grip:SetPoint("TOPLEFT", -4, 4)
    f.grip:SetPoint("BOTTOMRIGHT", 4, -4)
    f.grip:SetColorTexture(0.35, 0.72, 1.00, 0.22)
    f.grip:Hide()

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.label:SetText(self.labelText)
    f.label:Hide()

    self:Restyle()
    self:SetLocked(NCB.db.locked)
    self:Update()
end

--------------------------------------------------------------------------------
-- The pair
--------------------------------------------------------------------------------

local bars = {
    NCB.Power.New("power",  "nugsComboBar power - drag me"),
    NCB.Power.New("power2", "nugsComboBar second bar - drag me"),
}
NCB.Power.bars = bars

local events

function NCB.Power:Init()
    for _, b in ipairs(bars) do b:Init() end
    if events then return end

    events = CreateFrame("Frame")
    -- Filtered to the player. An unfiltered UNIT_POWER_FREQUENT in a raid is one of
    -- the most expensive things an addon can ask for.
    events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    events:RegisterUnitEvent("UNIT_POWER_UPDATE",   "player")
    events:RegisterUnitEvent("UNIT_MAXPOWER",       "player")
    -- Which power is primary changes with form and with spec, and this is the event
    -- that says so - it is what makes a druid's bar follow cat and bear with no
    -- table saying which is which.
    events:RegisterUnitEvent("UNIT_DISPLAYPOWER",   "player")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED",
                             "UPDATE_SHAPESHIFT_FORM" }) do
        pcall(events.RegisterEvent, events, event)
    end

    events:SetScript("OnEvent", function(_, event)
        -- A changed power type is a different colour and a different range, so it is
        -- a restyle and not just a new value.
        local reshape = event == "UNIT_DISPLAYPOWER"
                        or event == "PLAYER_SPECIALIZATION_CHANGED"
                        or event == "UPDATE_SHAPESHIFT_FORM"
                        or event == "PLAYER_ENTERING_WORLD"
        for _, b in ipairs(bars) do
            if reshape then
                b.lastMax = nil
                b:Restyle()
            end
            b:Update()
        end
    end)
end

function NCB.Power:Rebuild()
    for _, b in ipairs(bars) do
        b:Init()
        b:Restyle()
        b:Update()
    end
end

function NCB.Power:SetLocked(locked)
    for _, b in ipairs(bars) do b:SetLocked(locked) end
end
