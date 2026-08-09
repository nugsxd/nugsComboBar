--------------------------------------------------------------------------------
-- nugsComboBar
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsComboBar  -  Display.lua
-- The pips themselves: one draggable anchor, a row of pips chained off it, and an
-- optional Stagger bar underneath.
--
-- THE ONE IDEA THIS FILE IS BUILT ON
-- Pip number `i` is a StatusBar whose range is (i-1, i), and every pip is fed the
-- SAME raw resource value. Pip 3 fills exactly when the value passes 3, and no Lua
-- code ever compares, divides or subtracts anything. That matters because in 12.0
-- some resources - buff stacks especially - arrive as secret values that may not be
-- used in arithmetic at all. Handing the raw number to a widget and letting the
-- widget do the division is the whole trick, and it costs nothing for the resources
-- that are still plain numbers.
--
-- It also gets fractional resources right for free: Destruction reads its shards in
-- tenths, so the shard being built shows as a part-filled pip without a special case.
--
-- SHAPES
-- A pip is the user's chosen bar texture seen through a hole. The hole is a
-- MaskTexture anchored to the PIP rather than to the fill, which is what keeps a
-- half-filled circle looking like a half-filled circle instead of a squashed one.
--------------------------------------------------------------------------------
local ADDON_NAME, NCB = ...

local Display = {}
NCB.Display = Display

local anchor, pips, stagger, countText, lockLabel
local testValue, testDirection

-- Forward declaration: the demo cycle is defined at the bottom of the file but the
-- drawing code above has to ask whether it is running.
local Cycling

-- Forward-declared: lastPlain is only read down in Display:Update(), but Display:Rebuild()
-- above it clears the value so a spec change does not pop every pip. Declaring it beside
-- Update() would put the `local` after that assignment, and Rebuild would silently be
-- writing to a global of the same name while the reset did nothing.
local lastPlain

local MASK_PATH    = "Interface\\AddOns\\nugsComboBar\\mask-%s"
local MASKINV_PATH = "Interface\\AddOns\\nugsComboBar\\maskinv-%s"
local GLOW_PATH    = "Interface\\AddOns\\nugsComboBar\\glow-%s"

-- glow-*.blp draws its shape at this fraction of the texture and spends the rest on
-- the halo. Must match SHAPE_SCALE in nugsComboBar-art\glow.js, or the lit core
-- stops lining up with the pip it is meant to be lighting.
local GLOW_TEX_SCALE = 0.62

-- A hair under a whole point. The "row is full" overlay is a StatusBar ranged
-- (max - EPS, max), so it reads as a plain on/off for integer resources while still
-- being driven entirely by the widget - the comparison a secret value would refuse.
local EPS = 0.001

local function look()      return NCB.db.look      end
local function behaviour() return NCB.db.behaviour end

--------------------------------------------------------------------------------
-- Pip construction
--------------------------------------------------------------------------------
local function NewPip(index)
    local pip = CreateFrame("Frame", nil, anchor)
    pip.index = index

    -- Masks shape everything. The outer one traces the border, the inner one
    -- everything inside it, and each is anchored to the PIP rather than to the
    -- texture it masks - that is what makes a partly filled circle clip to a circle
    -- instead of squashing into an ellipse as it fills.
    --
    -- Each is created on the same frame as the texture it masks. A mask can reach
    -- across frames, but the fill lives on a StatusBar child and this is not worth
    -- being clever about: an extra MaskTexture per pip costs nothing, and the pips
    -- top out at ten.
    pip.masks = {}
    local function NewMask(owner)
        local m = owner:CreateMaskTexture()
        pip.masks[#pip.masks + 1] = m
        return m
    end

    pip.maskOuter = NewMask(pip)
    pip.maskOuter:SetAllPoints(pip)
    pip.maskInner = NewMask(pip)

    -- Opaque outside the shape, clear inside. Masks INTERSECT and there is no
    -- subtract, so this is the only way to get a ring: keep what is inside the pip
    -- and outside the inset, at exactly the border thickness. Drawing the border as
    -- a solid shape instead made "dimmed pip" and "outline only" identical - both
    -- were a filled blob, one with a 25% overlay on it.
    pip.maskInnerInv = NewMask(pip)

    pip.border = pip:CreateTexture(nil, "BACKGROUND")
    pip.border:SetAllPoints(pip)
    pip.border:AddMaskTexture(pip.maskOuter)
    pip.border:AddMaskTexture(pip.maskInnerInv)

    pip.empty = pip:CreateTexture(nil, "BORDER")
    pip.empty:AddMaskTexture(pip.maskInner)

    pip.bar = CreateFrame("StatusBar", nil, pip)
    pip.bar:SetFrameLevel(pip:GetFrameLevel() + 1)
    pip.barTex = pip.bar:CreateTexture(nil, "ARTWORK")
    pip.bar:SetStatusBarTexture(pip.barTex)
    pip.maskBar = NewMask(pip.bar)
    pip.barTex:AddMaskTexture(pip.maskBar)

    -- Lights the whole row the moment the resource caps. Ranged rather than
    -- branched, for the reason EPS exists.
    pip.full = CreateFrame("StatusBar", nil, pip)
    pip.full:SetFrameLevel(pip.bar:GetFrameLevel() + 1)
    pip.fullTex = pip.full:CreateTexture(nil, "ARTWORK")
    pip.full:SetStatusBarTexture(pip.fullTex)
    pip.maskFull = NewMask(pip.full)
    pip.fullTex:AddMaskTexture(pip.maskFull)

    pip.glow = pip:CreateTexture(nil, "OVERLAY")
    pip.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    pip.glow:SetBlendMode("ADD")
    pip.glow:AddMaskTexture(pip.maskOuter)
    pip.glow:Hide()

    -- "Resource is full" glow. A StatusBar rather than a texture for the same reason
    -- pip.full is one: whether the row is capped is a comparison, and a secret value
    -- may not be compared. Ranged (max - EPS, max) and fed the raw value, so the
    -- widget decides and every pip lights at the same instant.
    --
    -- It is larger than the pip because glow-*.blp draws its shape at GLOW_TEX_SCALE
    -- of the texture and spends the rest on the halo; sizing the frame by the
    -- reciprocal is what lines the lit core up with the pip underneath.
    pip.fullGlow = CreateFrame("StatusBar", nil, pip)
    pip.fullGlow:SetFrameLevel(pip.full:GetFrameLevel() + 1)
    pip.fullGlowTex = pip.fullGlow:CreateTexture(nil, "OVERLAY")
    pip.fullGlowTex:SetBlendMode("ADD")
    pip.fullGlow:SetStatusBarTexture(pip.fullGlowTex)
    pip.fullGlow:Hide()

    -- Recharge sweep for runes and essence. The template has outlived several
    -- expansions, but it is still a Blizzard template, so a client without it loses
    -- the sweep and nothing else.
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, pip, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(pip)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        cd:SetReverse(true)
        pip.cd = cd
    end

    return pip
end

--------------------------------------------------------------------------------
-- Error trapping
--
-- One bad widget call used to abandon the rest of the styling pass silently: the
-- pips still drew, but everything after the failing line - colours, glow, layout -
-- never ran, which looks exactly like "the options do nothing". Now a failure is
-- caught, counted and reported by /ncb diag instead of vanishing.
--------------------------------------------------------------------------------
NCB.errors = {}

local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not NCB.errors[label] then
        NCB.errors[label] = tostring(err)
        NCB.Print("|cffff8080error in " .. label .. "|r - see |cffffd479/ncb diag|r")
    end
    return ok
end
NCB.Guard = Guard

-- Everything size-, colour- and texture-dependent, applied once per rebuild rather
-- than on every value change.
-- Split into independently guarded phases. The masks are the one part of this that
-- depends on client behaviour I cannot verify from outside the game, so a failure
-- there must not be allowed to take the colours and the glow down with it - which is
-- exactly what a single flat function did.
local function StylePip(pip, res, cfg)
    local L = look()
    local w, h = L.pipWidth, L.pipHeight
    local inset = L.showBorder and L.borderSize or 0
    local shape = L.shape or "rounded"

    ------------------------------------------------------------------ geometry
    Guard("geometry", function()
        pip:SetSize(w, h)
        for _, region in ipairs({ pip.empty, pip.bar, pip.full }) do
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", pip, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -inset, inset)
        end
        pip.glow:ClearAllPoints()
        pip.glow:SetPoint("TOPLEFT", pip, "TOPLEFT", -2, 2)
        pip.glow:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 2, -2)
    end)

    --------------------------------------------------------------------- masks
    -- Every mask must be both textured AND anchored. A MaskTexture with no points
    -- has no size and silently masks nothing, which is what left the border a solid
    -- blob and made "outline only" identical to "dimmed".
    local masksOK = Guard("masks", function()
        for _, m in ipairs(pip.masks) do
            if m ~= pip.maskInnerInv then
                m:SetTexture(MASK_PATH:format(shape),
                             "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
        end
        -- CLAMP, not CLAMPTOBLACKADDITIVE: this mask is anchored to the INSET rect,
        -- so the border band lies outside its bounds, and clamping to black there
        -- would erase the one part of the border meant to survive. Every shape
        -- leaves a margin at the texture edge (PAD in masks.js), so the inverted
        -- mask's edge texels are opaque and clamping to them keeps the band visible.
        pip.maskInnerInv:SetTexture(MASKINV_PATH:format(shape), "CLAMP", "CLAMP")

        for _, m in ipairs({ pip.maskInner, pip.maskInnerInv }) do
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", pip, "TOPLEFT", inset, -inset)
            m:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -inset, inset)
        end
        pip.maskBar:SetAllPoints(pip.bar)
        pip.maskFull:SetAllPoints(pip.full)
    end)
    pip.masksOK = masksOK

    --------------------------------------------------------------------- paint
    Guard("paint", function()
        local texture = NCB.TexturePath(L.texture)
        -- The backing takes the same texture as the fill, tinted, rather than a flat
        -- colour block - otherwise picking a textured bar leaves the empty pips
        -- looking like they belong to a different addon.
        pip.empty:SetTexture(texture)
        pip.barTex:SetTexture(texture)
        pip.fullTex:SetTexture(texture)

        -- A real texture tinted, not SetColorTexture. A solid-colour texture is a
        -- 1x1 source and masking one is far less predictable than masking texels.
        local bc = L.colorBorder
        pip.border:SetTexture("Interface\\Buttons\\WHITE8X8")
        pip.border:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
        -- With no working mask the border would be a solid slab covering the pip, so
        -- it is only drawn when the masks that cut it into a ring actually took.
        pip.border:SetShown(L.showBorder and L.emptyStyle ~= "none" and masksOK)

        local c = cfg.color
        pip.barTex:SetVertexColor(c[1], c[2], c[3], 1)
        pip.fullTex:SetVertexColor(L.colorFull[1], L.colorFull[2], L.colorFull[3], 1)
        -- Whether these are actually shown is Update's call, since only it knows
        -- whether the resource is capped.
        pip.full:Hide()

        local e = L.colorEmpty
        pip.empty:SetVertexColor(e[1], e[2], e[3], e[4] or 1)
        pip.empty:SetAlpha(L.emptyAlpha)
        pip.empty:SetShown(L.emptyStyle == "dim")
    end)

    ---------------------------------------------------------------------- glow
    Guard("glow", function()
        pip.fullGlow:ClearAllPoints()
        pip.fullGlow:SetPoint("CENTER", pip, "CENTER", 0, 0)
        pip.fullGlow:SetSize(w / GLOW_TEX_SCALE, h / GLOW_TEX_SCALE)
        pip.fullGlowTex:SetTexture(GLOW_PATH:format(shape))
        local fg = L.colorFullGlow
        pip.fullGlowTex:SetVertexColor(fg[1], fg[2], fg[3], L.fullGlowStrength)
        pip.fullGlow:Hide()
    end)

    --------------------------------------------------------------------- range
    -- The line that makes the whole design work.
    Guard("range", function()
        local scale = NCB.Resources:Scale()
        pip.scale = scale
        pip.bar:SetMinMaxValues((pip.index - 1) * scale, pip.index * scale)
        if pip.cd then pip.cd:SetShown(false) end
    end)
end

-- nil when nothing has been built yet, otherwise whether the mask pass succeeded.
-- Reported by /ncb diag, because a mask that fails takes the shapes and the
-- outline border with it and there is no other way to see that from in game.
function Display:MasksWorking()
    if not (pips and pips[1]) then return nil end
    return pips[1].masksOK and true or false
end

-- Reports the live state of one pip's widgets. Reasoning about what a StatusBar
-- "should" be doing is how this addon shipped broken three times; this measures it.
local function Field(label, get)
    local ok, a, b, c, d = pcall(get)
    if not ok then return ("    %s: |cffff8080errored|r"):format(label) end
    local parts = {}
    for _, v in ipairs({ a, b, c, d }) do
        if type(v) == "number" then parts[#parts + 1] = ("%.3f"):format(v)
        else parts[#parts + 1] = tostring(v) end
    end
    return ("    %s: |cffffd479%s|r"):format(label, table.concat(parts, ", "))
end

function Display:Probe()
    if not (pips and pips[1]) then
        NCB.Print("nothing built yet - open the options window or /ncb test first.")
        return
    end
    local n = math.max(1, NCB.Resources.maxPips or 1)
    local pip = pips[n]
    if not pip then NCB.Print("no pip " .. n) return end

    NCB.Print(("probe of pip %d (the last one, so it only fills at maximum)"):format(n))
    print(Field("pip shown / size", function()
        return pip:IsShown(), pip:GetWidth(), pip:GetHeight() end))
    print(Field("bar  min,max / value", function()
        local lo, hi = pip.bar:GetMinMaxValues() return lo, hi, pip.bar:GetValue() end))
    print(Field("bar  fill width / colour", function()
        local t = pip.bar:GetStatusBarTexture()
        local r, g, b = pip.barTex:GetVertexColor()
        return t and t:GetWidth() or -1, r, g, b end))
    print(Field("full shown / fill width", function()
        local t = pip.full:GetStatusBarTexture()
        return pip.full:IsShown(), t and t:GetWidth() or -1 end))
    print(Field("full colour", function()
        local r, g, b, a = pip.fullTex:GetVertexColor() return r, g, b, a end))
    print(Field("glow shown / size", function()
        return pip.fullGlow:IsShown(), pip.fullGlow:GetWidth(), pip.fullGlow:GetHeight() end))
    print(Field("glow fill width / alpha", function()
        local t = pip.fullGlow:GetStatusBarTexture()
        local _, _, _, a = pip.fullGlowTex:GetVertexColor()
        return t and t:GetWidth() or -1, a end))
    print(Field("glow texture set", function()
        return pip.fullGlowTex:GetTexture() end))
    print(Field("border shown", function() return pip.border:IsShown() end))
    print(Field("empty shown / alpha", function()
        return pip.empty:IsShown(), pip.empty:GetAlpha() end))

    -- The colours being compared. Two that are nearly identical make a working
    -- recolour look like a broken one.
    local L, res = look(), NCB.Resources.active
    if res then
        local c = NCB.ResourceConfig(res.key).color
        print(("    resource colour: |cffffd479%.2f %.2f %.2f|r")
            :format(c[1], c[2], c[3]))
        print(("    at-max colour:   |cffffd479%.2f %.2f %.2f|r")
            :format(L.colorFull[1], L.colorFull[2], L.colorFull[3]))
        local diff = math.abs(c[1] - L.colorFull[1]) + math.abs(c[2] - L.colorFull[2])
                   + math.abs(c[3] - L.colorFull[3])
        if diff < 0.45 then
            print(("    |cffff8080Those two are nearly the same colour (difference %.2f).|r " ..
                   "A recolour between them is invisible - pick contrasting ones."):format(diff))
        end
    end
end

-- Whether what is on screen is actually ours. If this addon drew nothing and
-- Blizzard's own frame is still up, then recolouring, the glow and the empty-pip
-- styles would ALL appear to do nothing - one cause, not three bugs.
function Display:Presence()
    local built, shown = 0, 0
    for _, pip in ipairs(pips or {}) do
        built = built + 1
        if pip:IsShown() then shown = shown + 1 end
    end
    return {
        built   = built,
        shown   = shown,
        visible = anchor and anchor:IsVisible() and true or false,
        alpha   = anchor and anchor:GetAlpha() or 0,
        scale   = anchor and anchor:GetScale() or 0,
        testing = Display.testing and true or false,
    }
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local function RowSize(count)
    local L = look()
    local horizontal = (L.direction == "right" or L.direction == "left")
    if count <= 0 then return 1, 1 end
    if horizontal then
        return count * L.pipWidth + (count - 1) * L.spacing, L.pipHeight
    end
    return L.pipWidth, count * L.pipHeight + (count - 1) * L.spacing
end

local function LayoutPips(count)
    local L = look()
    local w, h = RowSize(count)
    anchor:SetSize(w, h + (Display.staggerVisible and (L.staggerHeight or 6) + 3 or 0))

    for i = 1, count do
        local pip = pips[i]
        pip:ClearAllPoints()
        local step = i - 1
        if L.direction == "right" then
            pip:SetPoint("TOPLEFT", anchor, "TOPLEFT", step * (L.pipWidth + L.spacing), 0)
        elseif L.direction == "left" then
            pip:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -step * (L.pipWidth + L.spacing), 0)
        elseif L.direction == "up" then
            pip:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, step * (L.pipHeight + L.spacing))
        else
            pip:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -step * (L.pipHeight + L.spacing))
        end
    end
end

--------------------------------------------------------------------------------
-- The anchor
--------------------------------------------------------------------------------
local function SavePosition()
    local a = NCB.db.anchor
    -- StopMovingOrSizing can re-anchor to a different corner, so the relative point
    -- has to be saved alongside the point or the display walks on every reload.
    local point, _, relPoint, x, y = anchor:GetPoint()
    a.point, a.relPoint, a.x, a.y = point, relPoint, x, y
end

local function RestorePosition()
    local a = NCB.db.anchor
    anchor:ClearAllPoints()
    anchor:SetPoint(a.point or "CENTER", UIParent, a.relPoint or a.point or "CENTER",
                    a.x or 0, a.y or 0)
    anchor:SetScale(a.scale or 1)
end

function Display:Init()
    anchor = CreateFrame("Frame", "nugsComboBarAnchor", UIParent)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Only drawn while unlocked, so there is something to grab when the resource
    -- itself is empty or the class has none at all.
    anchor.grip = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.grip:SetPoint("TOPLEFT", -4, 4)
    anchor.grip:SetPoint("BOTTOMRIGHT", 4, -4)
    anchor.grip:SetColorTexture(0.35, 0.72, 1.00, 0.22)
    anchor.grip:Hide()

    lockLabel = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockLabel:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    lockLabel:SetText("nugsComboBar - drag me")
    lockLabel:Hide()

    -- The number lives on its own frame stacked above the pips. On the anchor it was
    -- drawn behind them: pips are child frames, and a parent's font string can never
    -- come out in front of a child.
    anchor.overlay = CreateFrame("Frame", nil, anchor)
    anchor.overlay:SetAllPoints(anchor)
    anchor.overlay:SetFrameLevel(anchor:GetFrameLevel() + 20)
    countText = anchor.overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    stagger = CreateFrame("StatusBar", nil, anchor)
    stagger.bg = stagger:CreateTexture(nil, "BACKGROUND")
    stagger.bg:SetAllPoints()
    stagger.bg:SetColorTexture(0, 0, 0, 0.6)
    stagger.tex = stagger:CreateTexture(nil, "ARTWORK")
    stagger:SetStatusBarTexture(stagger.tex)
    stagger:Hide()

    pips = {}
    RestorePosition()
    Display:SetLocked(NCB.db.locked)
end

function Display:SetLocked(locked)
    NCB.db.locked = locked and true or false
    if not anchor then return end
    anchor:EnableMouse(not NCB.db.locked)
    anchor.grip:SetShown(not NCB.db.locked)
    lockLabel:SetShown(not NCB.db.locked)
    Display:UpdateVisibility()
    if NCB.RefreshOptions then NCB.RefreshOptions() end
end

-- The deliberate act, as opposed to SetLocked which ApplySettings calls on every
-- change to re-assert the current state. Everything chatty, and everything that
-- rearranges windows, belongs here so that neither happens on a slider tick.
function Display:ToggleLock(locked)
    -- Unlocking mid-fight is refused, for the same reason a pull locks the bar:
    -- placing it puts the drag box and a filled sample bar on screen, which cannot be
    -- told apart from your actual resource during a real pull. The button and the
    -- slash command both come through here, so this is the only place it needs saying.
    if not locked and InCombatLockdown() then
        NCB.Print("the bar cannot be placed during combat - try again after the fight.")
        return
    end

    self:SetLocked(locked)
    if locked then
        NCB.Print("locked.")
    else
        NCB.Print("unlocked - drag it where you want it, then |cffffd479/ncb lock|r.")
    end
    -- The options window gets out of the way while you are placing things, and a
    -- small bar takes its place. Options.lua owns that; guarded because that file is
    -- only loaded on demand.
    if NCB.OnLockChanged then NCB.OnLockChanged(NCB.db.locked) end
end

--------------------------------------------------------------------------------
-- Rebuild: called when the resource, the pip count or the look changes
--------------------------------------------------------------------------------
function Display:Rebuild()
    if not anchor then return end

    local res   = NCB.Resources.active
    local count = res and NCB.Resources.maxPips or 0
    local cfg   = res and NCB.ResourceConfig(res.key)
    local L     = look()

    Display.staggerVisible = NCB.Resources.staggerShown

    for i = 1, count do
        pips[i] = pips[i] or NewPip(i)
        pips[i].index = i
        StylePip(pips[i], res, cfg)
        pips[i]:Show()
    end
    for i = count + 1, #pips do
        pips[i]:Hide()
    end

    LayoutPips(count)
    RestorePosition()

    -- Forget the previous count, or switching spec pops every pip on the first update.
    lastPlain = nil

    -- Count readout
    local font, size = NCB.FontPath(L.font), L.fontSize
    pcall(countText.SetFont, countText, font, size, L.fontOutline ~= "NONE" and L.fontOutline or "")
    countText:SetTextColor(unpack(L.colorText))
    countText:ClearAllPoints()
    if L.countMode == "center" then
        countText:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    elseif L.countMode == "above" then
        countText:SetPoint("BOTTOM", anchor, "TOP", 0, 3)
    elseif L.countMode == "below" then
        countText:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
    end
    countText:SetShown(L.countMode ~= "none" and count > 0)

    -- Stagger bar
    if Display.staggerVisible then
        local h = L.staggerHeight or 6
        stagger:ClearAllPoints()
        stagger:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
        stagger:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -3)
        stagger:SetHeight(h)
        stagger.tex:SetTexture(NCB.TexturePath(L.texture))
        stagger:Show()
    else
        stagger:Hide()
    end

    Display:UpdatePulse()
    Display:Update()
    Display:UpdateVisibility()
end

--------------------------------------------------------------------------------
-- Update: called on every value change
--------------------------------------------------------------------------------
function Display:Update()
    if not anchor then return end
    local res   = NCB.Resources.active
    local count = res and NCB.Resources.maxPips or 0
    if count == 0 then
        Display:UpdateStagger()
        Display:UpdateVisibility()
        return
    end

    local value = Cycling() and testValue or NCB.Resources:Value()
    local maxRaw = count * NCB.Resources:Scale()
    local charged = (not Cycling()) and NCB.Resources:ChargedPoints() or nil
    local L = look()

    -- A plain value lets us do the nice things - pop a pip as it fills, dim the row
    -- when it is empty. A secret one still draws perfectly; it just does not animate,
    -- because knowing that a pip changed is exactly the thing we are not allowed to
    -- know. Degrading here rather than erroring is the whole point of the design.
    local plain = NCB.Plain(value)

    -- Guarded per pip: a value setter that rejects something is a client behaviour I
    -- cannot test for from here, and one refusal must not stop the rest of the row -
    -- or the readout, the stagger bar and the visibility rules below it.
    for i = 1, count do
      Guard("update", function()
        local pip = pips[i]
        pip.bar:SetValue(value)

        -- Two ways to light the "at maximum" layers, and the plain one is used
        -- whenever it can be. A resource that is a normal number can simply be
        -- compared, and a bar shown or hidden outright is far more robust than one
        -- asked to fill across a 0.001-wide range. The range trick is kept only for
        -- secret values, where comparing is not allowed at all.
        if plain then
            local isFull = plain >= maxRaw - EPS
            for _, layer in ipairs({ pip.full, pip.fullGlow }) do
                layer:SetMinMaxValues(0, 1)
                layer:SetValue(1)
            end
            pip.full:SetShown(L.fullHighlight and isFull)
            pip.fullGlow:SetShown(L.fullGlow and isFull)
        else
            pip.full:SetShown(L.fullHighlight)
            pip.fullGlow:SetShown(L.fullGlow)
            if L.fullHighlight then
                pip.full:SetMinMaxValues(maxRaw - EPS, maxRaw)
                pip.full:SetValue(value)
            end
            if L.fullGlow then
                pip.fullGlow:SetMinMaxValues(maxRaw - EPS, maxRaw)
                pip.fullGlow:SetValue(value)
            end
        end

        -- Supercharged combo points: plain data, so this one can branch.
        local isCharged = charged and charged[i]
        if isCharged then
            pip.barTex:SetVertexColor(1.00, 0.86, 0.32, 1)
        else
            local c = NCB.ResourceConfig(res.key).color
            pip.barTex:SetVertexColor(c[1], c[2], c[3], 1)
        end

        if L.glow then
            pip.glow:SetShown(isCharged and true or false)
            pip.glow:SetVertexColor(1.00, 0.86, 0.32, L.glowAlpha)
        else
            pip.glow:Hide()
        end

        Display:UpdateRecharge(pip, res, i, plain)

        -- Pop only the pip that just filled. `plain` is in raw units, so it has to
        -- come back through the scale to name a pip - Destruction counts in tenths.
        if L.animate and plain and lastPlain and plain > lastPlain
           and i == math.ceil(plain / NCB.Resources:Scale()) then
            Display:Pop(pip)
        end
      end)
    end

    lastPlain = plain

    if L.countMode ~= "none" then
        -- SetText is a display sink and accepts a secret; string.format does not, so
        -- the number goes in raw and unformatted.
        local shown = value
        if res.CountValue then
            local ok, v = pcall(res.CountValue, res)
            if ok then shown = v end
        end
        countText:SetText(shown)
    end

    Display:UpdateStagger()
    Display:UpdateVisibility()
end

-- Spent runes and essence come back one at a time on their own clock, which is the
-- one thing a StatusBar range cannot express. A radial sweep over the empty pip is
-- what players already read as "recharging".
function Display:UpdateRecharge(pip, res, index, plain)
    if not (pip.cd and res.recharging and NCB.db.extras.runeCooldowns) then
        if pip.cd then pip.cd:Hide() end
        return
    end

    if res.key == "runes" then
        local start, duration, ready = NCB.Resources:RuneCooldown(index)
        if ready or not (start and duration) or duration <= 0 then
            pip.cd:Hide()
        else
            pip.cd:Show()
            pcall(pip.cd.SetCooldown, pip.cd, start, duration)
        end
    else
        pip.cd:Hide()
    end
end

function Display:UpdateStagger()
    if not (stagger and Display.staggerVisible) then return end
    local cur, max = NCB.Resources:Stagger()
    if not (cur and max) then
        stagger:Hide()
        return
    end
    -- Both go straight to the widget. Stagger has been observed coming back secret
    -- even though it was not supposed to, so nothing here reads either number.
    pcall(stagger.SetMinMaxValues, stagger, 0, max)
    pcall(stagger.SetValue, stagger, cur)

    local plain = NCB.Plain(cur)
    local plainMax = NCB.Plain(max)
    local r, g, b = 0.52, 0.79, 0.28
    if plain and plainMax and plainMax > 0 then
        local pct = plain / plainMax
        if pct >= 0.6 then r, g, b = 0.86, 0.28, 0.24
        elseif pct >= 0.3 then r, g, b = 0.94, 0.76, 0.24 end
    end
    stagger.tex:SetVertexColor(r, g, b, 1)
end

-- The full-glow breathes rather than sitting flat. This runs whenever the glow is
-- enabled and never asks whether the resource is actually full - it only changes the
-- texture's alpha, and the StatusBar underneath decides whether any of it is on
-- screen. That is what keeps a pulsing glow legal on a secret value.
local pulseFrame

function Display:UpdatePulse()
    local L = look()
    local on = L.fullGlow and L.fullGlowPulse and (NCB.Resources.active ~= nil or Cycling())

    if not on then
        if pulseFrame then pulseFrame:SetScript("OnUpdate", nil) end
        -- Settle back to the flat strength, or turning the pulse off leaves the glow
        -- stuck at whatever brightness it happened to be mid-breath.
        for _, pip in ipairs(pips or {}) do
            local fg = L.colorFullGlow
            pip.fullGlowTex:SetVertexColor(fg[1], fg[2], fg[3], L.fullGlowStrength)
        end
        return
    end

    pulseFrame = pulseFrame or CreateFrame("Frame")
    pulseFrame:SetScript("OnUpdate", function()
        local LL = look()
        local fg = LL.colorFullGlow
        -- 1.4s cycle, dipping to 55% of the set strength at the bottom.
        local wave = 0.775 + 0.225 * math.sin(GetTime() * (2 * math.pi / 1.4))
        local a = LL.fullGlowStrength * wave
        for i = 1, (NCB.Resources.maxPips or 0) do
            local pip = pips[i]
            if pip then pip.fullGlowTex:SetVertexColor(fg[1], fg[2], fg[3], a) end
        end
    end)
end

-- A short scale-up on the pip that just filled. Cosmetic, and skipped entirely when
-- the value is secret.
function Display:Pop(pip)
    local L = look()
    pip.popUntil = GetTime() + 0.18
    pip.popFrom = L.gainPop or 1.18
    pip:SetScript("OnUpdate", function(self)
        local left = (self.popUntil or 0) - GetTime()
        if left <= 0 then
            self:SetScale(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        local t = left / 0.18
        self:SetScale(1 + (self.popFrom - 1) * t)
    end)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
local fadeTarget, fadeFrame = 1

function Display:UpdateVisibility()
    if not anchor then return end
    local db = NCB.db
    local B  = behaviour()

    if not NCB.db.locked then
        anchor:Show()
        anchor:SetAlpha(1)
        return
    end

    local show = db.enabled and (NCB.Resources.active ~= nil or Cycling())

    if show and B.hideOnPetBattle and C_PetBattles and C_PetBattles.IsInBattle() then
        show = false
    end
    if show and B.hideInVehicle and UnitHasVehicleUI and UnitHasVehicleUI("player") then
        show = false
    end

    anchor:SetShown(show and true or false)
    if not show then return end

    -- Soft rules only dim the display; hard ones above hide it outright.
    local dim = false
    if B.visibility == "combat" then
        dim = not InCombatLockdown()
    elseif B.visibility == "target" then
        dim = not (UnitName("target") and not UnitIsFriend("player", "target"))
    elseif B.visibility == "spent" then
        -- Needs to know whether the resource is empty. If the value is secret that
        -- is unknowable, so the rule quietly stops applying rather than guessing.
        local plain = NCB.Plain(NCB.Resources:Value())
        dim = (plain ~= nil) and plain <= 0 or false
    end
    -- Never dim while the demo is running: the whole point is to see the thing.
    if Cycling() or not NCB.db.locked then dim = false end

    fadeTarget = dim and (B.fadeAlpha or 0.35) or 1
    if (B.fadeTime or 0) <= 0 then
        anchor:SetAlpha(fadeTarget)
        return
    end

    fadeFrame = fadeFrame or CreateFrame("Frame")
    fadeFrame:SetScript("OnUpdate", function(self, elapsed)
        local current = anchor:GetAlpha()
        local step = elapsed / (behaviour().fadeTime or 0.25)
        if math.abs(fadeTarget - current) <= step then
            anchor:SetAlpha(fadeTarget)
            self:SetScript("OnUpdate", nil)
            return
        end
        anchor:SetAlpha(current + (fadeTarget > current and step or -step))
    end)
end

--------------------------------------------------------------------------------
-- Demo cycle
--
-- Drives the pips through their whole range so the look can be judged without going
-- and hitting something. Two things turn it on: /ncb test, and simply having the
-- options window open.
--
-- The options-window case is the important one. Every colour and glow control acts
-- on a FILLED pip, and a resource sitting at zero out of combat has none - so the
-- window shipped with controls that visibly did nothing, which reads as broken
-- rather than as empty. Cycling while the window is open is what makes them
-- self-evident.
--------------------------------------------------------------------------------
local cycleFrame

Cycling = function() return (Display.testing or Display.previewing) and true or false end

local function StartCycle()
    -- Somewhere to show. A class with no resource of its own still gets a row so the
    -- options window is not a guessing game.
    if not NCB.Resources.active then
        NCB.Resources.active  = NCB.ResourceByKey("combo")
        NCB.Resources.maxPips = 5
        Display.fakeResource = true
    end

    testValue, testDirection = 0, 1
    Display:Rebuild()

    cycleFrame = cycleFrame or CreateFrame("Frame")
    local nextStep = 0
    cycleFrame:SetScript("OnUpdate", function()
        if GetTime() < nextStep then return end
        local res   = NCB.Resources.active
        if not res then return end
        local step  = NCB.Resources:Scale()
        local top   = NCB.Resources.maxPips * step

        testValue = testValue + testDirection * step
        -- Hold at both ends. The full row is where the glow and the recolour live,
        -- and sweeping straight past it is exactly how you miss them.
        if testValue >= top then
            testValue, testDirection = top, -1
            nextStep = GetTime() + 1.4
        elseif testValue <= 0 then
            testValue, testDirection = 0, 1
            nextStep = GetTime() + 0.8
        else
            nextStep = GetTime() + 0.4
        end
        Display:Update()
    end)
end

local function StopCycle()
    if cycleFrame then cycleFrame:SetScript("OnUpdate", nil) end
    -- Refresh rather than Rebuild: the cycle may have borrowed a resource this
    -- character does not have, and only a re-detect undoes that.
    Display.fakeResource = nil
    NCB.Resources:Refresh()
end

-- Called by the options window as it opens and closes.
function Display:SetPreview(on)
    on = on and NCB.db and NCB.db.behaviour.previewInOptions and true or false
    if on == (Display.previewing or false) then return end
    Display.previewing = on
    if on then
        StartCycle()
    elseif not Display.testing then
        StopCycle()
    end
end

function Display:Test()
    Display.testing = not Display.testing
    if Display.testing then
        StartCycle()
        NCB.Print("demo cycle on - |cffffd479/ncb test|r again to stop.")
    else
        if not Display.previewing then StopCycle() end
        NCB.Print("demo cycle off.")
    end
end
