--------------------------------------------------------------------------------
-- nugsComboBar
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsComboBar  -  Options.lua
-- One movable settings window in the same flat dark skin as RaidReady,
-- nugsCooldownPulse and nugsCastBars: tabs across the top, two columns of settings
-- below, and every control applying live so the pips on screen are the preview.
--
-- Widgets are hand-rolled rather than built on Blizzard templates, which get
-- renamed between expansions.
--------------------------------------------------------------------------------
local ADDON_NAME, NCB = ...

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------
local C = {
    bg     = { 0.07, 0.07, 0.07, 0.96 },
    header = { 0.10, 0.10, 0.10, 1.00 },
    panel  = { 0.10, 0.10, 0.10, 0.90 },
    input  = { 0.14, 0.14, 0.14, 1.00 },
    btn    = { 0.16, 0.16, 0.16, 1.00 },
    btnHi  = { 0.24, 0.24, 0.24, 1.00 },
    accent = { 0.35, 0.72, 1.00, 1.00 },
    rowB   = { 1, 1, 1, 0.055 },
    text   = { 0.82, 0.82, 0.82 },
    faint  = { 0.50, 0.50, 0.50 },
    gold   = { 1.00, 0.84, 0.42 },
}

local ADDON_ICON = "Interface\\AddOns\\nugsComboBar\\icon"

-- The two columns have to fit inside the window minus the panel inset, the scroll
-- inset and the scroll indicator, or the right column runs off under the edge.
local WIDTH, HEIGHT = 812, 640
local CONTENT_W = WIDTH - 46
local COL_GAP   = 22
local COL_W     = math.floor((CONTENT_W - COL_GAP) / 2)
local ROW_H     = 22

local window, tabStrip
local panels = {}                  -- keyed by tab: { panel, scroll, content, widgets, cols }
local currentKey = "general"
local sink                         -- where newly built widgets register themselves
local RelayoutAll

-- SetPropagateKeyboardInput is protected during combat, and a blocked call is not a
-- Lua error: pcall does not contain it, it raises ADDON_ACTION_BLOCKED and taints the
-- addon for the rest of the session. So it is never called inside a lockdown, and the
-- next key pressed after combat ends restores propagation on its own.
local function SafePropagate(frame, value)
    if InCombatLockdown() then return end
    frame:SetPropagateKeyboardInput(value)
end

local function look()      return NCB.db.look      end
local function behaviour() return NCB.db.behaviour end
local function extras()    return NCB.db.extras    end

-- Every control ends in the same place: restyle the pips and re-run the panel
-- layout, because most settings hide or reveal other settings.
local function Apply()
    NCB.Display:Rebuild()
end

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------
local function Backdrop(frame, color, borderAlpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(color))
    frame.bgTex = bg
    if borderAlpha then
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetHeight(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
        for _, p in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetWidth(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
    end
    return bg
end

local function Panel(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    Backdrop(f, color or C.panel, 1)
    return f
end

local function Label(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or C.text))
    return fs
end

local function SectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(C.accent))
    return fs
end

-- One white triangle, pointed whichever way is asked for.
--
-- Our own art rather than Blizzard's: UI-SortArrow is a whole arrow with a tail, which
-- is not what a marker on a small button should look like, and stock texture paths are
-- the thing that gets renamed between expansions.
--
-- Rotated by texture coordinates rather than shipping four files. The eight-argument
-- form of SetTexCoord rotates the quad; the four-argument form can only flip it, which
-- is why left and right cannot be done by mirroring an up arrow.
--
-- The two horizontal entries look backwards and are not: rotating the COORDINATES
-- clockwise rotates the drawn IMAGE counter-clockwise. Trace the apex rather than
-- reasoning about the rotation - the reasoning is what got them swapped the first time.
local ARROW_TEX = "Interface\\AddOns\\nugsComboBar\\arrow"
local ARROW_COORDS = {
    up    = { 0, 0, 0, 1, 1, 0, 1, 1 },
    down  = { 1, 1, 1, 0, 0, 1, 0, 0 },
    left  = { 1, 0, 0, 0, 1, 1, 0, 1 },
    right = { 0, 1, 1, 1, 0, 0, 1, 0 },
}

local function Arrow(owner, facing, point, x)
    local a = owner:CreateTexture(nil, "OVERLAY")
    a:SetTexture(ARROW_TEX)
    a:SetTexCoord(unpack(ARROW_COORDS[facing]))
    a:SetVertexColor(1, 1, 1)
    a:SetSize(8, 8)
    a:SetPoint(point, x, 0)
    a:SetAlpha(0.8)
    return a
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Backdrop(b, C.btn, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(unpack(C.text))
    b:SetScript("OnEnter", function(self) self.bgTex:SetColorTexture(unpack(C.btnHi)) end)
    b:SetScript("OnLeave", function(self) self.bgTex:SetColorTexture(unpack(C.btn)) end)
    b:SetScript("OnClick", onClick)
    b.SetLabel = function(self, t) self.text:SetText(t) end

    -- Marks this button as one that CYCLES: an arrow each side, because the next value
    -- is one click away and there is no list to open.
    --
    -- The pair is the point. A dropdown and a cycler are the same rectangle with the
    -- same text in it, and the only way to know which you were looking at was to click
    -- it. One chevron down means "a list appears"; arrows both sides mean "this steps".
    --
    -- Only ever put on a control that really behaves that way - one wearing the wrong
    -- marker is worse than one wearing none, because the marker becomes the thing
    -- misleading you.
    b.MarkAsCycle = function(self)
        if self.leftArrow then return self end
        self.leftArrow  = Arrow(self, "left",  "LEFT",   5)
        self.rightArrow = Arrow(self, "right", "RIGHT", -5)
        if self.text then
            self.text:ClearAllPoints()
            self.text:SetPoint("LEFT", 16, 0)
            self.text:SetPoint("RIGHT", -16, 0)
        end
        return self
    end

    b.MarkAsDropdown = function(self)
        if self.arrow then return self end
        self.arrow = Arrow(self, "down", "RIGHT", -6)
        if self.text then
            self.text:ClearAllPoints()
            self.text:SetPoint("LEFT", 6, 0)
            self.text:SetPoint("RIGHT", -18, 0)
            self.text:SetJustifyH("LEFT")
        end
        return self
    end
    return b
end

-- Deliberately built to match RaidReady's header so the suite reads as one thing:
-- a 30px bar with a storm-blue underline, the addon icon on the left, a gold title
-- with a blue tail, and a small flat close button.

local function HeaderBar(f, titleText, tailText)
    local header = CreateFrame("Frame", nil, f)
    Backdrop(header, C.header, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")

    -- Dragging, and the guarantee that a move ends: from the shared nugsMove.lua,
    -- which asserts that a frame nobody is holding is not moving rather than closing
    -- one more route by which a move could be left running. Read the note at the top
    -- of that file before changing anything here.
    NCB.InstallMove(f, { label = "the settings window", handle = header, body = true })

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(3)
    accent:SetColorTexture(unpack(C.accent))

    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(ADDON_ICON)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(titleText .. (tailText and (" |cff8cd2ff" .. tailText .. "|r") or ""))
    title:SetTextColor(unpack(C.gold))

    local close = Button(header, "x", 22, 18, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    -- Shown only when nugsSuite is absent. _G.nugsSuite is the suite's own handle,
    -- so this also reads correctly when it is installed but switched off - a
    -- disabled suite is no more use than a missing one.
    --
    -- A note, never a warning, and never a dependency: this addon works perfectly
    -- well on its own and the suite is only worth having once you run more than one.
    if not _G.nugsSuite then
        local suite = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        suite:SetPoint("RIGHT", close, "LEFT", -10, 0)
        suite:SetText("Part of the |cff8cd2ffnugs suite|r")
        suite:SetTextColor(unpack(C.faint))
    end

    return header
end

-- Checkbox: a small square that fills with the accent colour when on.
local function Check(parent, text, getter, setter, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    Backdrop(box, C.input, 1)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(unpack(C.text))

    b:SetScript("OnClick", function()
        setter(not getter())
        Apply()
        NCB.RefreshOptions()
    end)
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(unpack(C.text))
        GameTooltip:Hide()
    end)

    b.Refresh = function() fill:SetShown(getter() and true or false) end
    sink[#sink + 1] = b
    return b
end

-- Slider: title on the left, live value on the right, bar underneath.
local sliderIndex = 0
local function Slider(parent, title, minV, maxV, step, getter, setter, fmt)
    sliderIndex = sliderIndex + 1
    local name = "nugsComboBarSlider" .. sliderIndex

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(40)

    local titleFS = Label(holder, title, "GameFontNormalSmall")
    titleFS:SetPoint("TOPLEFT", 0, 0)

    -- Typeable rather than a read-only label: dragging is for finding a value,
    -- typing is for repeating one you already know. Both drive the same setter.
    --
    -- Commits on Enter AND on losing focus, so clicking away is not a silent
    -- discard. Anything that is not a number puts the live value back rather than
    -- becoming zero, and the result is clamped to the slider's own range so a stray
    -- extra digit cannot push a setting somewhere the slider could never reach.
    local valueBox = CreateFrame("EditBox", nil, holder)
    valueBox:SetPoint("TOPRIGHT", 0, 2)
    valueBox:SetSize(56, 18)
    valueBox:SetAutoFocus(false)
    valueBox:SetFontObject("GameFontHighlightSmall")
    valueBox:SetJustifyH("RIGHT")
    valueBox:SetTextInsets(4, 4, 0, 0)
    valueBox:SetTextColor(unpack(C.accent))
    Backdrop(valueBox, C.input, 1)

    local valueFS = {
        SetText = function(_, text)
            if not valueBox:HasFocus() then
                valueBox:SetText(text)
                valueBox:SetCursorPosition(0)
            end
        end,
    }

    local function CommitTyped(text)
        local n = tonumber(text)
        -- Do nothing when the text already matches the live value. Losing focus fires
        -- this too, so clicking straight onto the slider would otherwise re-apply
        -- whatever was in the box over the value you just clicked - which reads as
        -- the slider jumping out from under you.
        if n and math.abs(n - (getter() or 0)) < 1e-6 then n = nil end
        if n then
            if n < minV then n = minV elseif n > maxV then n = maxV end
            n = tonumber(string.format("%.4f", math.floor(n / step + 0.5) * step))
            setter(n)
            NCB.Display:Rebuild()
        end
        local v = getter()
        valueBox:SetText(string.format(fmt or "%.2f", v))
        valueBox:SetCursorPosition(0)
        if holder.Refresh then holder.Refresh() end
    end

    valueBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    valueBox:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format(fmt or "%.2f", getter()))
        self:ClearFocus()
    end)
    valueBox:SetScript("OnEditFocusLost", function(self) CommitTyped(self:GetText()) end)

    local sl
    local ok = pcall(function()
        sl = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    end)
    if not ok or not sl then
        -- Template missing on this client: fall back to a bare slider we skin ourselves.
        sl = CreateFrame("Slider", name, holder)
        sl:SetOrientation("HORIZONTAL")
        local track = sl:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        track:SetHeight(4)
        track:SetColorTexture(0.25, 0.25, 0.25, 1)
        sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end
    sl:SetPoint("TOPLEFT", 2, -18)
    sl:SetPoint("TOPRIGHT", -2, -18)
    sl:SetHeight(16)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end

    -- The template ships Low/High/Text labels we do not want.
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local fs = sl[suffix] or _G[name .. suffix]
        if fs and fs.SetText then fs:SetText("") end
    end

    local applying = false
    sl:SetScript("OnValueChanged", function(self, value)
        if applying then return end
        -- SetValueStep does not round for us on every path, and the leftover float
        -- noise would end up in saved variables.
        value = tonumber(string.format("%.4f", math.floor(value / step + 0.5) * step))
        setter(value)
        valueFS:SetText(string.format(fmt or "%.2f", value))
        Apply()
    end)

    holder.Refresh = function()
        applying = true
        local v = getter()
        sl:SetValue(v)
        valueFS:SetText(string.format(fmt or "%.2f", v))
        applying = false
    end
    sink[#sink + 1] = holder
    return holder
end

-- Cycling choice button. A dropdown would be the obvious widget, but Blizzard has
-- renamed that one twice in two expansions, and with three or four options a
-- click-to-cycle button is fewer motions anyway.
local function Choice(parent, prefix, options, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_H)

    local function keyOf(o) return type(o) == "table" and o.key or o end
    local function labelOf(o) return type(o) == "table" and o.label or o end

    local btn
    btn = Button(holder, "", 100, ROW_H, function()
        local index = 1
        for i, o in ipairs(options) do
            if keyOf(o) == getter() then index = i break end
        end
        setter(keyOf(options[(index % #options) + 1]))
        Apply()
        NCB.RefreshOptions()
    end)
    btn:MarkAsCycle()
    btn:SetPoint("LEFT", 0, 0)
    btn:SetPoint("RIGHT", 0, 0)

    holder.Refresh = function()
        local text = tostring(getter())
        for _, o in ipairs(options) do
            if keyOf(o) == getter() then text = labelOf(o) end
        end
        btn:SetLabel(prefix .. ": " .. text)
    end
    sink[#sink + 1] = holder
    return holder
end

-- Colour swatch. Opens the game's own picker, which knows how to be a colour
-- picker better than anything hand-rolled would.
local function ShowColorPicker(r, g, b, a, hasAlpha, apply)
    local function currentAlpha()
        if ColorPickerFrame.GetColorAlpha then
            local ok, v = pcall(ColorPickerFrame.GetColorAlpha, ColorPickerFrame)
            if ok and type(v) == "number" then return v end
        end
        if _G.OpacitySliderFrame then return 1 - _G.OpacitySliderFrame:GetValue() end
        return a or 1
    end
    local function onChange()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        apply(nr, ng, nb, hasAlpha and currentAlpha() or a)
    end

    local info = {
        r = r, g = g, b = b,
        hasOpacity = hasAlpha,
        opacity    = hasAlpha and (a or 1) or nil,
        swatchFunc = onChange,
        opacityFunc = onChange,
        cancelFunc = function() apply(r, g, b, a) end,
    }

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Pre-11.x shape, kept so the window is never dead on an older client.
        ColorPickerFrame.func        = info.swatchFunc
        ColorPickerFrame.opacityFunc = info.opacityFunc
        ColorPickerFrame.cancelFunc  = info.cancelFunc
        ColorPickerFrame.hasOpacity  = hasAlpha
        ColorPickerFrame.opacity     = hasAlpha and (1 - (a or 1)) or nil
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function Swatch(parent, text, getter, hasAlpha, highlight)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)

    local well = CreateFrame("Frame", nil, b)
    well:SetSize(30, 14)
    well:SetPoint("LEFT", 0, 0)
    Backdrop(well, { 0, 0, 0, 1 }, 1)

    local fill = well:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", well, "RIGHT", 8, 0)
    fs:SetText(text)
    fs:SetTextColor(unpack(C.text))

    b:SetScript("OnClick", function()
        local color = getter()
        ShowColorPicker(color[1], color[2], color[3], color[4] or 1, hasAlpha,
            function(r, g, b2, a)
                local c = getter()
                c[1], c[2], c[3] = r, g, b2
                if hasAlpha then c[4] = a end
                Apply()
                NCB.RefreshOptions()
            end)
    end)
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(unpack(C.text)) end)

    b.Refresh = function()
        local c = getter()
        fill:SetColorTexture(c[1], c[2], c[3], hasAlpha and (c[4] or 1) or 1)
        -- The resource this character actually uses is called out in gold, so a
        -- list of eleven colours still answers "which one is mine" at a glance.
        fs:SetTextColor(unpack(highlight and highlight() and C.gold or C.text))
    end
    sink[#sink + 1] = b
    return b
end

-- Shared behaviour for every floating list and panel: closes when you click away
-- from it, closes on Escape, and never outlives the window it belongs to.
--
-- `closeOnOutside` is false for panels that hold typed input. Dismissing a form on a
-- stray click loses whatever was in it, which is worse than an extra click on Close.
--
-- There is no "clicked anywhere" event, so the outside click is caught by a full
-- screen button underneath the popup, shown and hidden with it. It swallows the click
-- that dismisses - first click closes, second one acts - which is how every dropdown
-- in the game behaves, Blizzard's included.
local function AttachPopupBehaviour(popup, closeOnOutside)
    local catcher
    if closeOnOutside then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:RegisterForClicks("AnyUp")
        catcher:Hide()
        catcher:SetScript("OnClick", function() popup:Hide() end)
    end

    -- Escape closes the list rather than the window behind it. Propagation is left on
    -- for every other key, so this never swallows movement or typing; it is turned off
    -- only for the Escape that is actually being handled, which is what stops the same
    -- press also reaching CloseSpecialWindows and shutting the window.
    popup:EnableKeyboard(true)
    SafePropagate(popup, true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            SafePropagate(self, false)
            self:Hide()
        else
            SafePropagate(self, true)
        end
    end)

    -- The anchor is read back from the popup's own SetPoint rather than passed in, so
    -- this works for every caller without any of them having to remember to say who
    -- owns them. IsVisible is false when any ancestor is hidden, which is exactly the
    -- case being watched for.
    local function WatchOwner(self)
        if self.owner and not self.owner:IsVisible() then self:Hide() end
    end

    popup:HookScript("OnShow", function(self)
        local _, relativeTo = self:GetPoint(1)
        self.owner = relativeTo
        self:SetScript("OnUpdate", WatchOwner)
        if catcher then
            catcher:SetFrameStrata(self:GetFrameStrata())
            catcher:SetFrameLevel(110)
            self:SetFrameLevel(120)
            catcher:Show()
        end
    end)
    popup:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        SafePropagate(self, true)
        if catcher then catcher:Hide() end
    end)
    return popup
end

local function ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    -- Frames, not textures. The bar used to be two textures, and a texture cannot
    -- take mouse input - so it showed you where you were and gave you no way to act
    -- on it. On a long list that left the wheel as the only option.
    --
    -- BAR_W is the grab area and is wider than the 3px line you can see: a 3px
    -- target is not something anybody can reliably hit. It overlaps the right edge of
    -- the rows underneath, which is why it is hidden outright when everything fits -
    -- an invisible strip that eats row clicks would be worse than no bar at all.
    local BAR_W = 9

    local bar = CreateFrame("Frame", nil, scroll)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetWidth(BAR_W)
    bar:EnableMouse(true)

    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(BAR_W)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetPoint("TOPRIGHT", 0, 0)
    thumbTex:SetPoint("BOTTOMRIGHT", 0, 0)
    thumbTex:SetWidth(3)
    thumbTex:SetColorTexture(unpack(C.accent))

    local function MaxScroll()
        return math.max(0, (content:GetHeight() or 1) - (scroll:GetHeight() or 1))
    end

    local function ScrollTo(value)
        local maxScrol = MaxScroll()
        scroll:SetVerticalScroll(math.max(0, math.min(maxScrol, value)))
        scroll:UpdateBar()
    end

    function scroll:UpdateBar()
        local viewH    = self:GetHeight() or 1
        local totalH   = content:GetHeight() or 1
        local maxScrol = math.max(0, totalH - viewH)
        if self:GetVerticalScroll() > maxScrol then self:SetVerticalScroll(maxScrol) end
        if maxScrol <= 0 then
            bar:Hide()
            return
        end
        bar:Show()
        local frac   = math.min(1, viewH / totalH)
        local thumbH = math.max(20, viewH * frac)
        local travel = viewH - thumbH
        local pos    = (self:GetVerticalScroll() / maxScrol) * travel
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -pos)
        -- Kept for the drag maths below, which needs the travel distance and cannot
        -- recompute it from a frame mid-drag without fighting its own SetPoint.
        self.thumbTravel = travel
    end

    -- Cursor position comes back in screen pixels at the *root* scale, so it has to
    -- be divided by the frame's effective scale before it can be compared with
    -- anything measured off the frame itself. Skipping that makes dragging track the
    -- cursor at the wrong speed on any UI scale other than 1.
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (thumb:GetEffectiveScale() or 1)
    end

    local function OnDrag(self)
        local travel = scroll.thumbTravel or 0
        if travel <= 0 then return end
        -- Cursor down is a decreasing y, and scrolling down is an increasing scroll
        -- value, hence grab minus now rather than the other way round.
        local delta = (self.grabY - CursorY()) * (MaxScroll() / travel)
        ScrollTo(self.grabScroll + delta)
    end

    thumb:SetScript("OnMouseDown", function(self)
        self.grabY      = CursorY()
        self.grabScroll = scroll:GetVerticalScroll()
        thumbTex:SetColorTexture(1, 1, 1, 0.9)
        self:SetScript("OnUpdate", OnDrag)
    end)
    -- OnHide as well as OnMouseUp: releasing the button outside the frame does not
    -- always deliver OnMouseUp, and an OnUpdate left running would drag the list
    -- around with the cursor forever.
    local function EndDrag(self)
        self:SetScript("OnUpdate", nil)
        thumbTex:SetColorTexture(unpack(C.accent))
    end
    thumb:SetScript("OnMouseUp", EndDrag)
    thumb:SetScript("OnHide", EndDrag)

    -- Clicking the track pages toward the click rather than jumping to it. A jump
    -- would be a guess at where in the list that pixel means; a page is the same
    -- thing the wheel does, only faster.
    bar:SetScript("OnMouseDown", function(self)
        local viewH = scroll:GetHeight() or 1
        local top   = thumb:GetTop()
        local bot   = thumb:GetBottom()
        local y     = CursorY()
        if top and bot and y <= top and y >= bot then return end   -- on the thumb
        ScrollTo(scroll:GetVerticalScroll() + ((top and y > top) and -viewH or viewH))
    end)

-- If the content frame is still sitting at zero when the scroll frame gets its
    -- real size, give it that size. A frame positioned by anchors measures 0 until a
    -- layout pass has run, so a caller that sized its content from scroll:GetWidth()
    -- on the very first call built every row zero-wide - which is the "the list is
    -- empty until I click a second time" bug, and it has now been found three times.
    --
    -- Only when it is zero: several callers set a deliberate width, and clobbering
    -- those would trade this bug for a layout one. Rows are anchored to the content's
    -- edges, so they take the corrected width with them.
    --
    -- The width of the *scroll frame* is checked too, and that is not belt and braces.
    -- This handler also fires during the first layout pass, while the scroll frame
    -- itself still measures 0. Without the check it copies that 0 onto the content, the
    -- content is then no longer "unset" - 0 is still <= 1 - and no further size change
    -- arrives to correct it. Rows anchored to the content's two top corners come out
    -- zero-wide, which still *draws*, because a FontString does not clip to its parent,
    -- but a zero-wide Button has no hit rectangle: a list you can read and cannot click.
    -- Every list here also sets an explicit content width at its call site, which is the
    -- primary mechanism; this stays a backstop for the next one that does not.
    scroll:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth() or 0
        if w > 1 and (self.content:GetWidth() or 0) <= 1 then
            self.content:SetWidth(w)
        end
        if self.UpdateBar then self:UpdateBar() end
    end)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local viewH    = self:GetHeight() or 1
        local maxScrol = math.max(0, (content:GetHeight() or 1) - viewH)
        local new = math.max(0, math.min(maxScrol, self:GetVerticalScroll() - delta * 34))
        self:SetVerticalScroll(new)
        self:UpdateBar()
    end)

    return scroll
end

-- Saved-profile picker.
--
-- Width comes from the popup's own SetSize, NOT from scroll:GetWidth(): the scroll is
-- sized by anchors, so on the first open - the frame having just been created, with no
-- layout pass yet - it measures 0, every row is built zero-wide, and the list looks
-- empty until you click again.
--
-- The fill is lifted off the window's near-black and edged in accent, so a floating
-- list reads as sitting on top rather than blending into the panel behind it.
local namePopup

local function ToggleNamePicker(parent, anchorTo, names, onPick)
    if namePopup and namePopup:IsShown() then
        namePopup:Hide()
        return
    end

    if not namePopup then
        namePopup = CreateFrame("Frame", nil, UIParent)
        namePopup:SetSize(200, 200)
        namePopup:SetFrameStrata("FULLSCREEN_DIALOG")
        namePopup:SetToplevel(true)
        namePopup:SetClampedToScreen(true)
        namePopup:EnableMouse(true)
        Backdrop(namePopup, { 0.13, 0.13, 0.15, 0.98 }, 1)
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                             { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
            local edge = namePopup:CreateTexture(nil, "OVERLAY")
            edge:SetPoint(p[1]); edge:SetPoint(p[2])
            if p[3] == "h" then edge:SetHeight(1) else edge:SetWidth(1) end
            edge:SetColorTexture(0.35, 0.72, 1.00, 0.55)
        end
        namePopup.scroll = ScrollArea(namePopup)
        namePopup.scroll:SetPoint("TOPLEFT", 5, -5)
        namePopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        namePopup.rows = {}
        AttachPopupBehaviour(namePopup, true)
    end

    local content = namePopup.scroll.content
    content:SetWidth(namePopup:GetWidth() - 10)

    for index, name in ipairs(names) do
        local row = namePopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 22)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
            row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0) end)
            namePopup.rows[index] = row
        end
        row.label:SetText(name)
        row:SetScript("OnClick", function()
            onPick(name)
            namePopup:Hide()
        end)
        row:Show()
    end
    for index = #names + 1, #namePopup.rows do namePopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #names * 22))
    namePopup.scroll:SetVerticalScroll(0)
    if namePopup.scroll.UpdateBar then namePopup.scroll:UpdateBar() end

    namePopup:ClearAllPoints()
    local below = (anchorTo:GetBottom() or 0) - namePopup:GetHeight()
    if below < 20 then
        namePopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        namePopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    namePopup:Raise()
    namePopup:Show()
end

--------------------------------------------------------------------------------
-- Column layout
-- Widgets declare when they are relevant (`show`), and the column re-flows around
-- whatever is hidden. That is what keeps the Extras tab honest: a Paladin never
-- sees the Stagger controls, and no hole is left where they would have been.
--------------------------------------------------------------------------------
local function NewColumn(parent, xOffset, width)
    local col = { parent = parent, x = xOffset, width = width, items = {} }

    function col:Add(region, height, show, indent)
        local isText = region.GetObjectType and region:GetObjectType() == "FontString"
        self.items[#self.items + 1] = {
            region = region, h = height, show = show,
            indent = indent or 0, stretch = not isText,
        }
        return region
    end

    -- The leading gap carries the section's own visibility, so a section that does
    -- not apply leaves no hole where it would have been.
    function col:Header(text, show)
        self:Gap(6, show)
        return self:Add(SectionHeader(self.parent, text), 22, show)
    end

    function col:Hint(text, show)
        local fs = Label(self.parent, text, "GameFontDisableSmall", C.faint)
        local _, lines = text:gsub("\n", "")
        return self:Add(fs, 14 + lines * 12, show)
    end

    function col:Gap(h, show)
        self.items[#self.items + 1] = { h = h, show = show }
    end

    function col:Layout()
        local y = 0
        for _, item in ipairs(self.items) do
            local visible = (not item.show) or item.show()
            if item.region then
                if visible then
                    item.region:Show()
                    item.region:ClearAllPoints()
                    item.region:SetPoint("TOPLEFT", self.parent, "TOPLEFT",
                        self.x + item.indent, -y)
                    if item.stretch then
                        item.region:SetPoint("TOPRIGHT", self.parent, "TOPLEFT",
                            self.x + self.width, -y)
                    else
                        item.region:SetWidth(self.width - item.indent)
                    end
                    y = y + item.h
                else
                    item.region:Hide()
                end
            elseif visible then
                y = y + item.h
            end
        end
        return y
    end

    return col
end

--------------------------------------------------------------------------------
-- Media picker
-- A popup list rather than a dropdown, and every entry previews itself: fonts are
-- drawn in their own font, bar textures as an actual filled bar. Picking a look
-- from a list of names alone is guesswork.
--------------------------------------------------------------------------------
local mediaPopup

local function ToggleMediaPicker(kind, anchorTo, current, onPick)
    if mediaPopup and mediaPopup:IsShown() and mediaPopup.kind == kind
       and mediaPopup.anchorTo == anchorTo then
        mediaPopup:Hide()
        return
    end

    if not mediaPopup then
        mediaPopup = CreateFrame("Frame", nil, UIParent)
        mediaPopup:SetSize(250, 300)
        mediaPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        mediaPopup:EnableMouse(true)
        mediaPopup:SetClampedToScreen(true)
        Backdrop(mediaPopup, C.bg, 1)
        mediaPopup.scroll = ScrollArea(mediaPopup)
        mediaPopup.scroll:SetPoint("TOPLEFT", 5, -5)
        mediaPopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        mediaPopup.rows = {}
        AttachPopupBehaviour(mediaPopup, true)
    end

    mediaPopup.kind     = kind
    mediaPopup.anchorTo = anchorTo

    local entries = (kind == "font") and NCB.FontList() or NCB.TextureList()
    local content = mediaPopup.scroll.content
    -- Width from the popup's own SetSize, NOT from scroll:GetWidth(). The scroll is
    -- positioned by anchors, so on the very first call - the frame having been created
    -- microseconds earlier with no layout pass yet - it measures 0, every row is built
    -- zero-wide, and the list looks empty until you click a second time. The same bug
    -- was fixed in the other pickers and this one was missed.
    content:SetWidth(mediaPopup:GetWidth() - 10)

    for index, entry in ipairs(entries) do
        local row = mediaPopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(24)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.preview = CreateFrame("StatusBar", nil, row)
            row.preview:SetPoint("LEFT", 6, 0)
            row.preview:SetSize(70, 14)
            row.preview:SetMinMaxValues(0, 1)
            row.preview:SetValue(1)
            row.preview:SetStatusBarColor(unpack(C.accent))
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
            row:SetScript("OnLeave", function(self)
                self.stripe:SetColorTexture(1, 1, 1, self.selected and 0.10 or 0)
            end)
            mediaPopup.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * 24)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * 24)
        row.label:ClearAllPoints()
        row.label:SetText(entry.name)

        if kind == "font" then
            row.preview:Hide()
            row.label:SetPoint("LEFT", 8, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            local ok, applied = pcall(row.label.SetFont, row.label, entry.path, 13, "")
            if not ok or applied == false then
                row.label:SetFontObject("GameFontHighlightSmall")
                row.label:SetText(entry.name .. " |cff888888(unavailable)|r")
            end
        else
            row.preview:Show()
            row.preview:SetStatusBarTexture(entry.path)
            row.label:SetFontObject("GameFontHighlightSmall")
            row.label:SetPoint("LEFT", row.preview, "RIGHT", 8, 0)
            row.label:SetPoint("RIGHT", -6, 0)
        end

        row.selected = (entry.name == current)
        row.stripe:SetColorTexture(1, 1, 1, row.selected and 0.10 or 0)
        row:SetScript("OnClick", function()
            onPick(entry.name)
            mediaPopup:Hide()
        end)
        row:Show()
    end

    for index = #entries + 1, #mediaPopup.rows do mediaPopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #entries * 24))
    mediaPopup.scroll:SetVerticalScroll(0)
    mediaPopup.scroll:UpdateBar()

    mediaPopup:ClearAllPoints()
    -- Drop down if there is room, otherwise open upwards. Clamping alone would slide
    -- the list over the button that opened it, which hides the thing being changed.
    local below = (anchorTo:GetBottom() or 0) - mediaPopup:GetHeight()
    if below < 20 then
        mediaPopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        mediaPopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    mediaPopup:Show()
end

local function MediaButton(parent, kind, prefix, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_H)

    local btn
    btn = Button(holder, "", 100, ROW_H, function()
        ToggleMediaPicker(kind, btn, getter(), function(name)
            setter(name)
            Apply()
            NCB.RefreshOptions()
        end)
    end)
    btn:MarkAsDropdown()
    btn:SetPoint("LEFT", 0, 0)
    btn:SetPoint("RIGHT", 0, 0)

    holder.Refresh = function() btn:SetLabel(prefix .. ": " .. tostring(getter())) end
    sink[#sink + 1] = holder
    return holder
end

--------------------------------------------------------------------------------
-- Shape picker
-- The one control where a row of names would be useless: each button draws the
-- shape it selects, at the size the pips are actually set to.
--------------------------------------------------------------------------------
local function ShapeRow(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(46)

    local buttons = {}
    for i, shape in ipairs(NCB.SHAPES) do
        local b = CreateFrame("Button", nil, holder)
        b:SetSize(52, 40)
        b:SetPoint("LEFT", (i - 1) * 56, 0)
        Backdrop(b, C.btn, 1)

        local mask = b:CreateMaskTexture()
        mask:SetPoint("CENTER")
        mask:SetSize(34, 22)
        mask:SetTexture("Interface\\AddOns\\nugsComboBar\\mask-" .. shape.key,
                        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        local swatch = b:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("CENTER")
        swatch:SetSize(34, 22)
        swatch:SetColorTexture(unpack(C.accent))
        swatch:AddMaskTexture(mask)
        b.swatch = swatch

        b:SetScript("OnClick", function()
            look().shape = shape.key
            Apply()
            NCB.RefreshOptions()
        end)
        b:SetScript("OnEnter", function(self)
            self.bgTex:SetColorTexture(unpack(C.btnHi))
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(shape.label)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.bgTex:SetColorTexture(unpack(look().shape == shape.key and C.btnHi or C.btn))
            GameTooltip:Hide()
        end)

        b.shapeKey = shape.key
        buttons[#buttons + 1] = b
    end

    holder.Refresh = function()
        for _, b in ipairs(buttons) do
            local on = (look().shape == b.shapeKey)
            b.bgTex:SetColorTexture(unpack(on and C.btnHi or C.btn))
            b.swatch:SetVertexColor(unpack(on and { 1, 1, 1 } or { 0.55, 0.55, 0.6 }))
        end
    end
    sink[#sink + 1] = holder
    return holder
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------
local TABS = {
    { key = "general",    label = "General"    },
    { key = "appearance", label = "Appearance" },
    { key = "colours",    label = "Colours"    },
    { key = "bars",       label = "Resource bars" },
    { key = "extras",     label = "Extras"     },
}

local tabs = {}

local function SelectTab(key)
    currentKey = key
    if NCB.char then NCB.char.lastTab = key end
    for _, tab in ipairs(tabs) do
        local on = (tab.key == key)
        tab.underline:SetShown(on)
        tab.text:SetTextColor(unpack(on and C.gold or C.faint))
    end
    for k, p in pairs(panels) do
        p.panel:SetShown(k == key)
    end
    NCB.RefreshOptions()
end


-- A real dropdown: the current value on the face, the whole list on one click.
--
-- Choice() cycles instead, which is the right control for two or three options where
-- the next one is always one click away. It is wrong past four or five: finding the
-- ninth means clicking eight times and watching the label, and you cannot see what is
-- on offer without visiting all of it. Both are kept - the cycling form is still
-- better for a short list, and it now says which it is with an arrow at each side.
local listPopup

local function ToggleListPicker(anchorTo, entries, onPick)
    if listPopup and listPopup:IsShown() then listPopup:Hide() return end

    if not listPopup then
        listPopup = CreateFrame("Frame", nil, UIParent)
        listPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        listPopup:EnableMouse(true)
        listPopup:SetClampedToScreen(true)
        Backdrop(listPopup, C.bg, 1)
        listPopup.scroll = ScrollArea(listPopup)
        listPopup.scroll:SetPoint("TOPLEFT", 5, -5)
        listPopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        listPopup.rows = {}
        AttachPopupBehaviour(listPopup, true)
    end

    -- Sized to its contents, capped so a long list scrolls instead of running off the
    -- screen. The scroll bar hides itself when everything fits, so a short list gets
    -- no furniture it has no use for.
    local rowH = 22
    listPopup:SetSize(170, math.min(#entries * rowH + 10, 240))

    local content = listPopup.scroll.content
    -- From the popup's own size, NOT from scroll:GetWidth(): the scroll is positioned
    -- by anchors and measures 0 on the very first call, which builds every row
    -- zero-wide and makes the list look empty until the second click.
    content:SetWidth(listPopup:GetWidth() - 10)

    for index, entry in ipairs(entries) do
        local row = listPopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(rowH)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(1, 1, 1, 0.10) end)
            row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0) end)
            listPopup.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowH)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowH)
        row.label:SetText(entry.label)
        row:SetScript("OnClick", function()
            onPick(entry.key)
            listPopup:Hide()
        end)
        row:Show()
    end
    for index = #entries + 1, #listPopup.rows do listPopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #entries * rowH))
    listPopup.scroll:SetVerticalScroll(0)
    listPopup.scroll:UpdateBar()

    listPopup:ClearAllPoints()
    local below = (anchorTo:GetBottom() or 0) - listPopup:GetHeight()
    if below < 20 then
        listPopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        listPopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    listPopup:Show()
end

local function Dropdown(parent, prefix, options, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_H)

    -- Same shape as Choice: an option may be a table with key and label, or a bare
    -- string that is both. Anchors and outlines are stored as plain string lists.
    local function keyOf(o)   return type(o) == "table" and o.key or o end
    local function labelOf(o) return type(o) == "table" and o.label or o end
    local function list()     return type(options) == "function" and options() or options end

    local btn
    btn = Button(holder, "", 100, ROW_H, function()
        local entries = {}
        for _, o in ipairs(list()) do
            entries[#entries + 1] = { key = keyOf(o), label = labelOf(o) }
        end
        ToggleListPicker(btn, entries, function(key)
            setter(key)
            Apply()
            NCB.RefreshOptions()
        end)
    end)
    btn:MarkAsDropdown()
    btn:SetPoint("LEFT", 0, 0)
    btn:SetPoint("RIGHT", 0, 0)

    holder.Refresh = function()
        local text = tostring(getter())
        for _, o in ipairs(list()) do
            if keyOf(o) == getter() then text = labelOf(o) end
        end
        btn:SetLabel(prefix .. ": " .. text)
    end
    sink[#sink + 1] = holder
    return holder
end

local function BuildTabs(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(26)

    local x = 0
    for _, entry in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, strip)
        tab.key = entry.key
        tab:SetHeight(24)

        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.text:SetPoint("CENTER", 0, 1)
        tab.text:SetText(entry.label)

        local w = math.max(60, tab.text:GetStringWidth() + 26)
        tab:SetWidth(w)
        tab:SetPoint("LEFT", x, 0)

        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
        tab.underline:SetHeight(2)
        tab.underline:SetColorTexture(unpack(C.accent))
        tab.underline:Hide()

        tab:SetScript("OnClick", function() SelectTab(entry.key) end)
        tab:SetScript("OnEnter", function(self)
            if self.key ~= currentKey then self.text:SetTextColor(1, 1, 1) end
        end)
        tab:SetScript("OnLeave", function(self)
            self.text:SetTextColor(unpack(self.key == currentKey and C.gold or C.faint))
        end)

        x = x + w + 2
        tabs[#tabs + 1] = tab
    end

    strip:SetWidth(x)
    return strip
end

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------
local function BuildGeneral(p)
    sink = p.widgets
    local content = p.content
    local G = NewColumn(content, 0, COL_W * 2 - 40)
    p.cols = { G }

    G:Header("nugsComboBar")
    G:Hint("Draws your class resource - combo points, holy power, chi, soul shards,\n" ..
           "arcane charges, runes or essence - as a row of pips you can put anywhere.\n" ..
           "The pips on screen update as you change these settings, so there is no\n" ..
           "separate preview to trust.")

    G:Header("Profile")
    G:Hint("Saved account-wide, so a profile made on one character can be loaded on\n" ..
           "any other. Nothing auto-saves: a change you make now simply stays until\n" ..
           "you Save it into a profile or Load a different one over it.")

    -- Built inline: this file has no EditBox helper, and one edit box does not earn
    -- a new one.
    local profileBox = CreateFrame("EditBox", nil, content)
    profileBox:SetHeight(22)
    profileBox:SetAutoFocus(false)
    profileBox:SetFontObject("GameFontHighlightSmall")
    profileBox:SetTextInsets(6, 6, 0, 0)
    Backdrop(profileBox, C.input, 1)
    profileBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    profileBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Name box and picker on one row: the column is wide, and a fourth button
    -- crammed next to Save/Load/Delete read as clutter rather than a way in.
    local nameRow = CreateFrame("Frame", nil, content)
    nameRow:SetHeight(24)
    profileBox:SetParent(nameRow)
    profileBox:ClearAllPoints()
    profileBox:SetPoint("LEFT", 0, 0)
    profileBox:SetWidth(220)
    local pPick = Button(nameRow, "Pick a saved profile...", 170, 22, function(self)
        local names = NCB.ProfileNames()
        if #names == 0 then NCB.Print("no profiles saved yet.") return end
        ToggleNamePicker(window, self, names, function(chosen)
            profileBox:SetText(chosen) profileBox:SetCursorPosition(0)
        end)
    end)
    pPick:SetPoint("LEFT", profileBox, "RIGHT", 8, 0)
    G:Add(nameRow, 28)
    local profileHint = Label(profileBox, "profile name...", "GameFontDisableSmall", C.faint)
    profileHint:SetPoint("LEFT", 8, 0)
    profileBox:SetScript("OnTextChanged", function(self)
        profileHint:SetShown((self:GetText() or "") == "")
    end)

    local profileRow = CreateFrame("Frame", nil, content)
    profileRow:SetHeight(22)
    local pSave = Button(profileRow, "Save", 66, 22, function()
        local name = NCB.TrimName(profileBox:GetText())
        if name == "" then NCB.Print("give the profile a name first.") return end
        local existed = NCB.Profile.account.profiles[name] ~= nil
        if NCB.SaveProfile(name) then
            NCB.Print((existed and "profile updated: " or "profile saved: ") .. name)
            NCB.RefreshOptions()
        end
    end)
    pSave:SetPoint("LEFT", 0, 0)
    local pLoad = Button(profileRow, "Load", 66, 22, function()
        local name = NCB.TrimName(profileBox:GetText())
        if NCB.LoadProfile(name) then NCB.Print("profile loaded: " .. name)
        else NCB.Print("no profile called \"" .. name .. "\".") end
    end)
    pLoad:SetPoint("LEFT", pSave, "RIGHT", 5, 0)
    local pDelete = Button(profileRow, "Delete", 70, 22, function()
        local name = NCB.TrimName(profileBox:GetText())
        if NCB.DeleteProfile(name) then
            NCB.Print("profile deleted: " .. name)
            NCB.RefreshOptions()
        else NCB.Print("no profile called \"" .. name .. "\".") end
    end)
    pDelete:SetPoint("LEFT", pLoad, "RIGHT", 5, 0)
    G:Add(profileRow, 28)

    local savedList = Label(content, "", "GameFontDisableSmall", C.faint)
    savedList.Refresh = function()
        local names = NCB.ProfileNames()
        local active, matches = NCB.ProfileStatus()

        -- "modified" is the honest state after loading a profile and then changing
        -- anything, and saying so is what stops somebody assuming their change was
        -- written back into the profile. It was not; Save does that.
        local current
        if not active then
            current = "Loaded: |cff777777none|r"
        elseif matches then
            current = "Loaded: |cff8cd2ff" .. active .. "|r"
        else
            current = "Loaded: |cff8cd2ff" .. active .. "|r |cffd8a13f(modified)|r"
        end

        savedList:SetText(current .. "\n" .. (#names > 0
            and ("Saved: |cff8cd2ff" .. table.concat(names, "|r, |cff8cd2ff") .. "|r")
            or  "No profiles saved yet."))
    end
    p.widgets[#p.widgets + 1] = savedList
    G:Add(savedList, 34)

    G:Header("Master switches")
    G:Add(Check(content, "nugsComboBar enabled",
        function() return NCB.db.enabled end,
        function(v) NCB.db.enabled = v end), ROW_H)
    G:Add(Check(content, "Show the minimap button",
        function() return not NCB.db.minimapHidden end,
        function(v)
            NCB.db.minimapHidden = not v
            NCB.SetMinimapShown(v)
        end), ROW_H)

    G:Header("Placing it")
    local lockBtn = Button(content, "", 200, 22, function()
        NCB.Display:ToggleLock(not NCB.db.locked)
    end)
    lockBtn.Refresh = function()
        lockBtn:SetLabel(NCB.db.locked and "Unlock for dragging" or "Lock in place")
    end
    p.widgets[#p.widgets + 1] = lockBtn
    G:Add(lockBtn, 26)
    G:Hint("While unlocked the pips show a grab handle and stay visible even when\n" ..
           "the resource is empty, so there is always something to drag.")
    G:Add(Slider(content, "Horizontal position", -900, 900, 1,
        function() return NCB.db.anchor.x end,
        function(v) NCB.db.anchor.x = v end, "%d"), 42)
    G:Add(Slider(content, "Vertical position", -700, 700, 1,
        function() return NCB.db.anchor.y end,
        function(v) NCB.db.anchor.y = v end, "%d"), 42)
    G:Add(Slider(content, "Scale", 0.5, 3.0, 0.05,
        function() return NCB.db.anchor.scale end,
        function(v) NCB.db.anchor.scale = v end, "%.2fx"), 42)
    G:Hint("Offsets from the screen point the row was last dropped on, so dragging\n" ..
           "it and nudging it here always agree.")

    G:Header("Seeing what you are changing")
    G:Add(Check(content, "Demo the pips while this window is open",
        function() return behaviour().previewInOptions end,
        function(v)
            behaviour().previewInOptions = v
            NCB.Display:SetPreview(v)
        end,
        "Runs the resource up and down so the colour, glow and empty-pip settings " ..
        "have something to act on. Without it, configuring at zero resource looks " ..
        "like nothing is happening."), ROW_H)

    G:Header("When to show it")
    G:Add(Choice(content, "Show", NCB.VISIBILITY,
        function() return behaviour().visibility end,
        function(v) behaviour().visibility = v end), 26)
    G:Add(Slider(content, "Dimmed to", 0, 1, 0.05,
        function() return behaviour().fadeAlpha end,
        function(v) behaviour().fadeAlpha = v end, "%.2f"), 42,
        function() return behaviour().visibility ~= "always" end)
    G:Add(Slider(content, "Fade over", 0, 1, 0.05,
        function() return behaviour().fadeTime end,
        function(v) behaviour().fadeTime = v end, "%.2fs"), 42,
        function() return behaviour().visibility ~= "always" end)
    G:Hint("'When not empty' needs to read the resource, which 12.0 sometimes hands\n" ..
           "over as a secret value. When it does, the rule quietly stops applying\n" ..
           "rather than guessing wrong.",
        function() return behaviour().visibility == "spent" end)
    G:Add(Check(content, "Hide while in a vehicle",
        function() return behaviour().hideInVehicle end,
        function(v) behaviour().hideInVehicle = v end), ROW_H)
    G:Add(Check(content, "Hide during pet battles",
        function() return behaviour().hideOnPetBattle end,
        function(v) behaviour().hideOnPetBattle = v end), ROW_H)

    G:Header("Start over")
    G:Add(Button(content, "Reset everything to defaults", 220, 22, function()
        NCB.ResetAll()
        NCB.Print("reset to defaults.")
        NCB.RefreshOptions()
    end), 26)

    G:Header("Commands")
    G:Hint("|cffffd479/ncb|r opens this window\n" ..
           "|cffffd479/ncb unlock|r and |cffffd479/ncb lock|r place the pips\n" ..
           "|cffffd479/ncb test|r cycles the pips so you can judge the look\n" ..
           "|cffffd479/ncb diag|r reports what the addon sees for your spec\n" ..
           "|cffffd479/ncb reset|r starts over")
end

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------
local function BuildAppearance(p)
    sink = p.widgets
    local content = p.content
    local L = NewColumn(content, 0, COL_W)
    local R = NewColumn(content, COL_W + COL_GAP, COL_W)
    p.cols = { L, R }

    ----------------------------------------------------------------- left column
    L:Header("Shape")
    L:Add(ShapeRow(content), 46)
    L:Hint("The pip is your chosen texture seen through this shape.")

    L:Header("Size and spacing")
    -- Up to 250 because a pip and a bar are the same control here, and a bar wants
    -- the width of a resource bar rather than the width of one combo point.
    L:Add(Slider(content, "Pip width", 4, 250, 1,
        function() return look().pipWidth end,
        function(v) look().pipWidth = v end, "%d px"), 42)
    L:Add(Slider(content, "Pip height", 4, 120, 1,
        function() return look().pipHeight end,
        function(v) look().pipHeight = v end, "%d px"), 42)
    L:Add(Slider(content, "Gap between pips", 0, 30, 1,
        function() return look().spacing end,
        function(v) look().spacing = v end, "%d px"), 42)
    L:Add(Choice(content, "Fill order", NCB.DIRECTIONS,
        function() return look().direction end,
        function(v) look().direction = v end), 26)

    L:Header("Texture")
    L:Add(MediaButton(content, "texture", "Texture",
        function() return look().texture end,
        function(v) look().texture = v end), 26)

    L:Header("Border")
    L:Add(Check(content, "Draw a border",
        function() return look().showBorder end,
        function(v) look().showBorder = v end), ROW_H)
    local borderOn = function() return look().showBorder end
    L:Add(Slider(content, "Border thickness", 1, 6, 1,
        function() return look().borderSize end,
        function(v) look().borderSize = v end, "%d px"), 42, borderOn)

    ---------------------------------------------------------------- right column
    R:Header("Empty pips")
    R:Add(Choice(content, "Empty pip", NCB.EMPTY_STYLES,
        function() return look().emptyStyle end,
        function(v) look().emptyStyle = v end), 26)
    R:Add(Slider(content, "Fill opacity", 0, 1, 0.05,
        function() return look().emptyAlpha end,
        function(v) look().emptyAlpha = v end, "%.2f"), 42,
        function() return look().emptyStyle == "dim" end)
    R:Hint("'Filled, dimmed' is the pip shape in the empty colour below; 'Outline\n" ..
           "only' is the border ring and nothing else. At a low fill opacity and a\n" ..
           "dark empty colour the two look almost identical - raise the opacity or\n" ..
           "lighten the colour to tell them apart.")
    R:Hint("|cffff8080'Outline only' has no border to draw.|r Turn one on in the left column.",
        function() return look().emptyStyle == "hollow" and not look().showBorder end)

    R:Header("Motion")
    R:Add(Check(content, "Pop a pip when it fills",
        function() return look().animate end,
        function(v) look().animate = v end,
        "Needs to notice that the count went up. Buff-stack resources arrive as " ..
        "secret values in 12.0, so those draw perfectly but do not animate."), ROW_H)
    R:Add(Slider(content, "How big a pop", 1.0, 1.6, 0.02,
        function() return look().gainPop end,
        function(v) look().gainPop = v end, "%.2fx"), 42,
        function() return look().animate end)
    R:Add(Check(content, "Glow on Supercharged points",
        function() return look().glow end,
        function(v) look().glow = v end,
        "Rogues and Feral druids get points worth double after Supercharger. " ..
        "Those pips are recoloured and lit."), ROW_H)
    R:Add(Slider(content, "Glow strength", 0, 1, 0.05,
        function() return look().glowAlpha end,
        function(v) look().glowAlpha = v end, "%.2f"), 42,
        function() return look().glow end)
    R:Header("At maximum")
    R:Hint("Two independent tells for a capped resource. Both colours are on the\n" ..
           "Colours tab.")
    R:Add(Check(content, "Glow every pip",
        function() return look().fullGlow end,
        function(v) look().fullGlow = v end,
        "The whole row lights up and haloes the moment the resource caps."), ROW_H)
    local glowOn = function() return look().fullGlow end
    R:Add(Slider(content, "Glow strength", 0.1, 1.5, 0.05,
        function() return look().fullGlowStrength end,
        function(v) look().fullGlowStrength = v end, "%.2f"), 42, glowOn)
    R:Add(Check(content, "Let the glow breathe",
        function() return look().fullGlowPulse end,
        function(v) look().fullGlowPulse = v end,
        "A slow pulse rather than a flat glow."), ROW_H, glowOn)
    R:Add(Check(content, "Also recolour the pips",
        function() return look().fullHighlight end,
        function(v) look().fullHighlight = v end,
        "Repaints the filled pips in the 'Resource at maximum' colour. Independent " ..
        "of the glow - you can have either, both or neither."), ROW_H)

    R:Header("Number")
    R:Add(Choice(content, "Count", NCB.COUNT_MODES,
        function() return look().countMode end,
        function(v) look().countMode = v end), 26)
    local numOn = function() return look().countMode ~= "none" end
    R:Add(MediaButton(content, "font", "Font",
        function() return look().font end,
        function(v) look().font = v end), 26, numOn)
    R:Add(Choice(content, "Outline", NCB.OUTLINES,
        function() return look().fontOutline end,
        function(v) look().fontOutline = v end), 26, numOn)
    R:Add(Slider(content, "Font size", 6, 32, 1,
        function() return look().fontSize end,
        function(v) look().fontSize = v end, "%d"), 42, numOn)
end

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------
local function BuildColours(p)
    sink = p.widgets
    local content = p.content
    local L = NewColumn(content, 0, COL_W)
    local R = NewColumn(content, COL_W + COL_GAP, COL_W)
    p.cols = { L, R }

    L:Header("Resource colours")
    L:Hint("The one your character uses is picked out in gold.")

    -- Every resource in the registry gets a row, not just this character's: the
    -- saved variables are account-wide, so setting the Chi colour on a Paladin and
    -- having it stick when you log into your Monk is the point.
    local half = math.ceil(#NCB.RESOURCES / 2)
    for i, res in ipairs(NCB.RESOURCES) do
        local col = (i <= half) and L or R
        if col == R and i == half + 1 then
            R:Header("Resource colours (cont.)")
            R:Gap(4)
        end
        local key = res.key
        local isMine = function()
            return NCB.Resources.active and NCB.Resources.active.key == key
        end
        col:Add(Swatch(content, res.label,
            function() return NCB.ResourceConfig(key).color end, false, isMine), ROW_H)
        col:Add(Check(content, "Draw this resource",
            function() return NCB.ResourceConfig(key).enabled end,
            function(v)
                NCB.ResourceConfig(key).enabled = v
                NCB.Resources:Refresh()
            end), ROW_H, nil, 16)
        col:Add(Check(content, "Draw as one bar",
            function() return NCB.ResourceConfig(key).barMode end,
            function(v)
                NCB.ResourceConfig(key).barMode = v

                -- A bar with no number on it is the one thing this option is not for.
                -- Turned on for you the first time, and said out loud rather than done
                -- quietly, because the number is a shared setting and changing it
                -- affects every resource.
                if v and look().countMode == "none" then
                    look().countMode = "center"
                    NCB.Print("turned the number on so the bar has something to read; "
                              .. "it is under Look if you want it elsewhere.")
                end

                NCB.Resources:Refresh()
                NCB.Display:Rebuild()
                NCB.RefreshOptions()
            end,
            "Pips answer \"how many have I got\", which is right for five combo " ..
            "points. A bar answers \"how full am I\", which is right for something " ..
            "like Insanity that moves continuously and has no meaningful single " ..
            "point."), ROW_H, nil, 16)
        -- A percentage of the bar rather than a number of resource units, so it
        -- cannot be wrong about what the units ARE. Insanity is shown as 0-100 and
        -- has been stored at ten times that; half the bar is half the bar either way.
        col:Add(Slider(content, "Mark at", 0, 100, 1,
            function() return NCB.ResourceConfig(key).markAt or 0 end,
            function(v)
                NCB.ResourceConfig(key).markAt = v
                -- Refresh, not just Rebuild: where the line goes is worked out when
                -- the resource is resolved, because it can come from a spell's cost.
                NCB.Resources:Refresh()
                NCB.Display:Rebuild()
            end, "%d%%"),
            42, function() return NCB.ResourceConfig(key).barMode end, 16)

        if res.blizz then
            col:Add(Check(content, "Hide Blizzard's version",
                function() return NCB.ResourceConfig(key).hideBlizzard end,
                function(v)
                    NCB.ResourceConfig(key).hideBlizzard = v
                    NCB.Resources:ApplyBlizzardVisibility()
                end,
                "Blizzard's resource frames are protected, so this takes effect the " ..
                "moment you drop out of combat."), ROW_H, nil, 16)
        end
        col:Gap(6)
    end

    R:Header("Shared colours")
    R:Add(Swatch(content, "Resource at maximum",
        function() return look().colorFull end), ROW_H)
    R:Add(Swatch(content, "Glow at maximum",
        function() return look().colorFullGlow end), ROW_H)
    R:Add(Swatch(content, "Empty pip backing",
        function() return look().colorEmpty end, true), ROW_H)
    R:Add(Swatch(content, "Border",
        function() return look().colorBorder end, true), ROW_H)
    R:Add(Swatch(content, "Number",
        function() return look().colorText end), ROW_H)
    R:Hint("Supercharged combo points are always drawn gold, because a colour you\n" ..
           "can change would eventually collide with one of the above.")
end

--------------------------------------------------------------------------------
-- Extras
--------------------------------------------------------------------------------
local function BuildExtras(p)
    sink = p.widgets
    local content = p.content
    local G = NewColumn(content, 0, COL_W * 2 - 40)
    p.cols = { G }

    local function classIs(class)
        return function() return NCB.Resources.class == class end
    end
    local function activeIs(key)
        return function()
            return NCB.Resources.active and NCB.Resources.active.key == key
        end
    end

    G:Header("Extras for your class")
    G:Hint("Only what applies to the character you are on is listed. Log in on\n" ..
           "another class and this tab fills with different controls.")

    G:Header("Stagger", classIs("MONK"))
    G:Add(Check(content, "Show a Stagger bar under the pips",
        function() return extras().stagger end,
        function(v)
            extras().stagger = v
            NCB.Resources:Refresh()
        end,
        "Brewmaster only. Green, yellow then red as the damage you have parked " ..
        "climbs past a third and two thirds of your health."), ROW_H, classIs("MONK"))
    G:Add(Slider(content, "Stagger bar height", 2, 24, 1,
        function() return look().staggerHeight end,
        function(v) look().staggerHeight = v end, "%d px"), 42,
        function() return NCB.Resources.class == "MONK" and extras().stagger end)

    G:Header("Runes", classIs("DEATHKNIGHT"))
    G:Add(Check(content, "Sweep a spent rune as it recharges",
        function() return extras().runeCooldowns end,
        function(v) extras().runeCooldowns = v end,
        "A radial wipe over the empty pip, the way Blizzard's own rune frame " ..
        "reads."), ROW_H, classIs("DEATHKNIGHT"))

    G:Header("Combo points", activeIs("combo"))
    G:Add(Check(content, "Draw points past the normal maximum",
        function() return extras().comboAnticipation end,
        function(v)
            extras().comboAnticipation = v
            NCB.Resources:Refresh()
        end,
        "Talents that raise your combo point cap add pips rather than squeezing " ..
        "the existing ones."), ROW_H, activeIs("combo"))

    G:Header("Soul Shards", activeIs("soulFragments"))
    G:Hint("Destruction reads its shards in tenths, so the shard you are building\n" ..
           "shows as a partly filled pip. Nothing to configure - it is how the pips\n" ..
           "are fed.", activeIs("soulFragments"))

    G:Header("What this spec has")
    local status = Label(content, "", "GameFontHighlightSmall", C.text)
    status.Refresh = function()
        local res = NCB.Resources.active
        if not res then
            status:SetText("|cffff8080No class resource for this spec.|r Nothing is drawn. " ..
                "|cffffd479/ncb test|r still shows a demo row if you want to place it.")
        else
            local source = res.aura and "buff stacks"
                or res.castCount and "a cast count"
                or "a power type"
            status:SetText(("Showing |cffffd479%s|r - %d pips, read from %s.")
                :format(res.label, NCB.Resources.maxPips, source))
        end
    end
    p.widgets[#p.widgets + 1] = status
    G:Add(status, 34)

    G:Hint("12.0 moved several class resources off the power system entirely.\n" ..
           "Maelstrom Weapon, Icicles and Tip of the Spear are buff stacks now, and\n" ..
           "Vengeance's Soul Fragments are a cast count. They are all drawn here the\n" ..
           "same way, but the game hands their counts over as secret values, so those\n" ..
           "resources do not animate.")

    G:Header("Try it out")
    G:Add(Button(content, "Cycle the pips", 200, 22, function()
        NCB.Display:Test()
        NCB.RefreshOptions()
    end), 26)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local unlockBtn


-- One column of controls for one resource bar. Both bars get exactly the same set,
-- because they are the same thing pointed at different powers - the only difference
-- is that the second one has to be told which power, and the first asks the client.
local function BarControls(col, content, id, title, hint)
    local function c() return NCB.db[id] end
    local function on() return c().enabled end
    local function changed()
        NCB.Power:Rebuild()
        NCB.RefreshOptions()
    end

    col:Header(title)
    col:Hint(hint)

    col:Add(Check(content, "Show this bar",
        function() return c().enabled end,
        function(v) c().enabled = v; changed() end), ROW_H)

    if id == "power2" then
        col:Add(Dropdown(content, "Power", NCB.POWER_CHOICES,
            function() return c().powerType end,
            function(v) c().powerType = v; changed() end), 26, on)
    end

    col:Add(Slider(content, "Width", 40, 400, 1,
        function() return c().width end,
        function(v) c().width = v; changed() end, "%d px"), 42, on)
    col:Add(Slider(content, "Height", 4, 60, 1,
        function() return c().height end,
        function(v) c().height = v; changed() end, "%d px"), 42, on)
    -- "texture" is the kind the picker knows; "statusbar" would open an empty list.
    col:Add(MediaButton(content, "texture", "Texture",
        function() return c().texture end,
        function(v) c().texture = v; changed() end), 26, on)
    col:Add(Choice(content, "Number", NCB.POWER_TEXT_MODES,
        function() return c().textMode end,
        function(v) c().textMode = v; changed() end), 26, on)

    -- The number's font. Shared with the pip row unless this bar asks for its own.
    local function numberOn() return on() and c().textMode ~= "none" end
    local function ownOn() return numberOn() and c().ownFont end
    col:Add(Check(content, "Own font for the number",
        function() return c().ownFont end,
        function(v)
            -- Start from what the bar is showing right now, so ticking the box
            -- changes nothing on screen until a font setting is actually changed.
            if v and not c().ownFont then
                local L = NCB.db.look
                c().font, c().fontSize, c().fontOutline = L.font, L.fontSize, L.fontOutline
            end
            c().ownFont = v
            changed()
        end,
        "Off, the number uses the font from the Appearance tab, so the bar matches " ..
        "the pips. On, this bar gets its own font, outline and size."), ROW_H, numberOn)
    col:Add(MediaButton(content, "font", "Font",
        function() return c().font end,
        function(v) c().font = v; changed() end), 26, ownOn)
    col:Add(Choice(content, "Outline", NCB.OUTLINES,
        function() return c().fontOutline end,
        function(v) c().fontOutline = v; changed() end), 26, ownOn)
    col:Add(Slider(content, "Font size", 6, 32, 1,
        function() return c().fontSize end,
        function(v) c().fontSize = v; changed() end, "%d"), 42, ownOn)

    col:Add(Check(content, "Use the game's colour for this power",
        function() return c().useClassColor end,
        function(v) c().useClassColor = v; changed() end,
        "Energy yellow, Fury purple, Rage red, and so on - the same colours the " ..
        "default UI uses."), ROW_H, on)
    col:Add(Swatch(content, "Custom colour",
        function() return c().color end, false),
        ROW_H, function() return on() and not c().useClassColor end)
    col:Add(Check(content, "Border",
        function() return c().showBorder end,
        function(v) c().showBorder = v; changed() end), ROW_H, on)
    col:Add(Check(content, "Hide it while it is full",
        function() return c().hideWhenFull end,
        function(v) c().hideWhenFull = v; changed() end,
        "For a resource that sits at maximum out of combat and only matters once " ..
        "you start spending it."), ROW_H, on)
    col:Gap(8)
end

local function BuildBars(p)
    sink = p.widgets
    local content = p.content
    local L = NewColumn(content, 0, COL_W)
    local R = NewColumn(content, COL_W + COL_GAP, COL_W)
    p.cols = { L, R }

    BarControls(L, content, "power", "Primary resource",
        "Whatever this character actually spends - Energy, Fury, Rage, Focus,\n" ..
        "Runic Power, Insanity. It follows your spec and your form on its own,\n" ..
        "so a druid gets Energy in cat and Rage in bear with nothing to set.")

    BarControls(R, content, "power2", "Second resource",
        "For a class that has two at once: Shadow spends Insanity and still has\n" ..
        "Mana, a resto druid in cat form has Energy and Mana. It stays hidden if\n" ..
        "you do not have the power you pick, or if it is already the primary.")

    R:Header("Both bars")
    R:Hint("Drag them where you want while the display is unlocked. They use the\n" ..
           "font and number colour from the Appearance tab, so the whole display\n" ..
           "matches without setting the same thing twice. Tick Own font for the\n" ..
           "number on a bar to give it its own font, outline and size.")
end

local BUILDERS = {
    general    = BuildGeneral,
    appearance = BuildAppearance,
    colours    = BuildColours,
    extras     = BuildExtras,
    bars       = BuildBars,
}

local function BuildWindow()
    local f = CreateFrame("Frame", "nugsComboBarOptions", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- See the note above about the CENTER anchor: convert it to explicit, pixel
    -- aligned coordinates the first time the window is shown, so the first drag has
    -- no conversion left to do and nothing twitches.
    f:HookScript("OnShow", function(self)
        if self.__anchored then return end
        local left, bottom = self:GetLeft(), self:GetBottom()
        if not (left and bottom) then return end   -- not laid out yet; try again next show
        self.__anchored = true
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                      math.floor(left + 0.5), math.floor(bottom + 0.5))
    end)
    Backdrop(f, C.bg, 1)
    tinsert(UISpecialFrames, "nugsComboBarOptions")   -- Escape closes it
    window = f

    HeaderBar(f, "nugsComboBar", "v" .. NCB.version)

    tabStrip = BuildTabs(f)
    tabStrip:SetPoint("TOPLEFT", 10, -36)

    -- One panel per tab, each owning its own scroll frame, so switching tabs does
    -- not carry another tab's scroll position with it.
    for _, entry in ipairs(TABS) do
        local panel = Panel(f, { 0.05, 0.05, 0.05, 0.9 })
        panel:SetPoint("TOPLEFT", 10, -68)
        panel:SetPoint("BOTTOMRIGHT", -10, 44)

        local scroll = ScrollArea(panel)
        scroll:SetPoint("TOPLEFT", 10, -10)
        scroll:SetPoint("BOTTOMRIGHT", -10, 10)
        scroll.content:SetWidth(CONTENT_W)

        local p = { panel = panel, scroll = scroll, content = scroll.content, widgets = {} }
        panels[entry.key] = p
        BUILDERS[entry.key](p)
    end

    -- Bottom bar ---------------------------------------------------------------
    unlockBtn = Button(f, "", 128, 22, function()
        NCB.Display:ToggleLock(not NCB.db.locked)
    end)
    unlockBtn:SetPoint("BOTTOMLEFT", 10, 12)

    local testBtn = Button(f, "", 110, 22, function()
        NCB.Display:Test()
        NCB.RefreshOptions()
    end)
    testBtn:SetPoint("LEFT", unlockBtn, "RIGHT", 6, 0)
    testBtn.Refresh = function()
        testBtn:SetLabel(NCB.Display.testing and "Stop the demo" or "Keep demoing")
    end
    f.testBtn = testBtn

    local resetBtn = Button(f, "Reset everything", 130, 22, function()
        NCB.ResetAll()
        NCB.Print("reset to defaults.")
        NCB.RefreshOptions()
    end)
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 6, 0)

    local hint = Label(f, "|cff8cd2ff/ncb|r for commands", "GameFontDisableSmall", C.faint)
    hint:SetPoint("BOTTOMRIGHT", -12, 18)
    hint:SetJustifyH("RIGHT")

    -- HookScript, NOT SetScript: this window already has an OnShow handler set
    -- further up (the guard that stops a drag left running when the window is
    -- hidden mid-move). SetScript would throw it away silently. Checked by
    -- dragcheck.js HOOKKILL.
    f:HookScript("OnShow", function()
        -- Run the pips through their range while the window is open, so the colour
        -- and glow controls are acting on something you can actually see.
        NCB.Display:SetPreview(true)
        NCB.RefreshOptions()
    end)
    -- HookScript, NOT SetScript: this window already has an OnHide handler set
    -- further up (the guard that stops a drag left running when the window is
    -- hidden mid-move). SetScript would throw it away silently. Checked by
    -- dragcheck.js HOOKKILL.
    f:HookScript("OnHide", function()
        NCB.Display:SetPreview(false)
        if mediaPopup then mediaPopup:Hide() end
    end)

    SelectTab((NCB.char and NCB.char.lastTab and panels[NCB.char.lastTab]) and NCB.char.lastTab
              or "general")

    -- CreateFrame hands back a *shown* frame, so without this the first /ncb
    -- would toggle the brand new window straight back off.
    f:Hide()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
RelayoutAll = function()
    local p = panels[currentKey]
    if not p then return end
    local h = 0
    for _, col in ipairs(p.cols or {}) do
        h = math.max(h, col:Layout())
    end
    p.content:SetHeight(h + 12)
    p.scroll:UpdateBar()
end

function NCB.RefreshOptions()
    if not window or not NCB.db then return end

    local p = panels[currentKey]
    if p then
        for _, w in ipairs(p.widgets) do
            if w.Refresh then w.Refresh() end
        end
    end

    if unlockBtn then
        unlockBtn:SetLabel(NCB.db.locked and "Unlock" or "Lock in place")
    end
    if window.testBtn and window.testBtn.Refresh then window.testBtn.Refresh() end

    RelayoutAll()
end

--------------------------------------------------------------------------------
-- Move bar
--
-- Placing things means dragging boxes that the settings window is usually sitting on
-- top of, so the window had to be shoved aside first and dragged back after. The
-- window gets out of the way on its own now: unlocking hides it and puts up a small
-- bar instead, and locking brings it back exactly where it was.
--
-- It is deliberately not a saved position. It moves if it is in the way, and starts
-- near the top of the screen next time; persisting it would mean a new saved
-- variable, and a setting nobody would ever go looking for.
--------------------------------------------------------------------------------
local moveBar

local function BuildMoveBar()
    local f = CreateFrame("Frame", "nugsComboBarMoveBar", UIParent)
    f:SetSize(216, 78)
    f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    -- Dragging, from the shared nugsMove.lua. This bar is the likeliest frame in
    -- the addon to be hidden mid-move: the settings window hides it the instant it
    -- opens, and a frame hidden between StartMoving and StopMovingOrSizing is never
    -- given OnDragStop.
    NCB.InstallMove(f, { label = "the move bar" })
    Backdrop(f, C.bg, 1)

    -- Storm-blue edge, so a floating bar reads as sitting on top of the world rather
    -- than being part of it. nugsCooldownPulse gets the same from its PopupChrome
    -- helper; this file has no such helper, so it is drawn here.
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local edge = f:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(p[1]); edge:SetPoint(p[2])
        if p[3] == "h" then edge:SetHeight(1) else edge:SetWidth(1) end
        edge:SetColorTexture(0.35, 0.72, 1.00, 0.55)
    end

    local title = Label(f, "Placing the resource bar", "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 10, -9)

    local hint = Label(f, "Drag it to where you want it.", "GameFontDisableSmall", C.faint)
    hint:SetPoint("TOPLEFT", 10, -28)

    -- Lock is the way out of this state, so it is first and it is the wide one.
    local lockBtn = Button(f, "Lock bar", 110, 22, function()
        NCB.Display:ToggleLock(true)
    end)
    lockBtn:SetPoint("BOTTOMLEFT", 10, 10)

    local extra0 = Button(f, "Demo", 70, 22, function()
        NCB.Display:Test()
            NCB.RefreshOptions()
    end)
    extra0:SetPoint("LEFT", lockBtn, "RIGHT", 6, 0)

    -- Escape locks rather than just dismissing the bar. Hiding it while things were
    -- still unlocked would leave the state with nothing on screen to end it.
    f:EnableKeyboard(true)
    SafePropagate(f, true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            SafePropagate(self, false)
            NCB.Display:ToggleLock(true)
        else
            SafePropagate(self, true)
        end
    end)

    return f
end

-- Whether the settings window was open when things were unlocked, so locking can put
-- it back only if it was there to begin with. Unlocking from the slash command with
-- nothing open should not conjure a window on lock.
local windowWasOpen = false

function NCB.OnLockChanged(locked)
    if not locked then
        if window and window:IsShown() then
            windowWasOpen = true
            window:Hide()
        end
        moveBar = moveBar or BuildMoveBar()
        SafePropagate(moveBar, true)
        moveBar:Show()
    else
        if moveBar then moveBar:Hide() end
        if windowWasOpen then
            windowWasOpen = false
            if window then window:Show() end
        end
    end
end

-- Builds the window once and hooks it once. Hooked here rather than inside
-- BuildWindow because moveBar is declared in this block: a closure written above its
-- declaration would bind to a nil global instead, silently, until somebody clicked.
--
-- The two hooks keep the pair consistent whichever one the player acts on. Opening
-- settings while unlocked should not leave two lock buttons on screen, and closing
-- settings while unlocked should put the bar back rather than leaving the state with
-- no way out of it.
local function EnsureWindow()
    if window then return end
    BuildWindow()
    window:HookScript("OnShow", function()
        if moveBar then moveBar:Hide() end
    end)
    window:HookScript("OnHide", function()
        if not NCB.db.locked then NCB.OnLockChanged(false) end
    end)
end

--------------------------------------------------------------------------------
-- Combat
--
-- The settings window closes and the anchor locks the moment a fight starts.
--
-- Not because anything here would be blocked: none of these windows touch a secure
-- frame, so nothing throws "action blocked" the way an addon driving action bars
-- does. The reason is that both states put FAKE data on screen - the pips demo themselves while the window is open - and
-- sample data during a real pull is worse than none, because it cannot be told apart
-- from the real thing.
--
-- Nothing reopens when combat drops. A window appearing by itself while you are
-- looting is worse than pressing a button.
--------------------------------------------------------------------------------
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatch:SetScript("OnEvent", function()
    if NCB.db and not NCB.db.locked then
        -- SetLocked and OnLockChanged directly rather than ToggleLock: ToggleLock
        -- prints, and a line of chat on every pull is noise.
        --
        -- Clearing windowWasOpen FIRST is the part that matters. OnLockChanged puts
        -- the settings window back when it was open before the unlock, and doing that
        -- as a fight starts is precisely the wrong moment - it would read as a window
        -- popping open on every pull.
        windowWasOpen = false
        NCB.Display:SetLocked(true)
        NCB.OnLockChanged(true)
        if NCB.RefreshOptions then NCB.RefreshOptions() end
    end
    if window and window:IsShown() then window:Hide() end
end)

function NCB.ToggleOptions()
    EnsureWindow()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

--------------------------------------------------------------------------------
-- A stub in the Blizzard settings list so the addon is findable there; the real
-- controls live in our own window, which stays movable.
--------------------------------------------------------------------------------
function NCB.InitOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local panel = CreateFrame("Frame")
    panel.name = "nugsComboBar"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("nugsComboBar")

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Your class resource as a row of configurable pips." ..
        "\n\nAll settings live in the nugsComboBar window - open it with the button below or with |cffffd479/ncb|r.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 24)
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    open:SetText("Open nugsComboBar options")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        EnsureWindow()
        window:Show()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "nugsComboBar")
    category.ID = "nugsComboBar"
    Settings.RegisterAddOnCategory(category)
end
