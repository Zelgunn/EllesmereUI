-------------------------------------------------------------------------------
--  EllesmereUI Action Bars - Custom Spell Flyout System
--  Replaces Blizzard's SpellFlyout for our action buttons to avoid taint.
--  Intercepts flyout-type action clicks in the secure environment and opens
--  our own flyout frame with spell-type buttons (secure casting, no taint).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Pull shape constants from the main file (loaded before us)
local SHAPE_MASKS              = ns.SHAPE_MASKS
local SHAPE_BORDERS            = ns.SHAPE_BORDERS
local SHAPE_ZOOM_DEFAULTS      = ns.SHAPE_ZOOM_DEFAULTS
local SHAPE_ICON_EXPAND        = ns.SHAPE_ICON_EXPAND
local SHAPE_ICON_EXPAND_OFFSETS = ns.SHAPE_ICON_EXPAND_OFFSETS
local SHAPE_INSETS             = ns.SHAPE_INSETS
local ResolveBorderThickness   = ns.ResolveBorderThickness
local EAB                      = ns.EAB

-- Layout constants
local FLYOUT_BTN_SPACING = 4

-- All known flyout IDs in retail WoW
local KNOWN_FLYOUT_IDS = {
    1, 8, 9, 10, 11, 12, 66, 67, 84, 92, 93, 96,
    103, 106, 217, 219, 220, 222, 223, 224, 225, 226, 227, 229,
}

-- Flyout button mixin (individual spell buttons inside the flyout menu)
local EABFlyoutBtnMixin = {}

function EABFlyoutBtnMixin:Setup()
    self:SetAttribute("type", "spell")
    self:RegisterForClicks("AnyUp", "AnyDown")
    self:SetScript("OnEnter", self.OnEnter)
    self:SetScript("OnLeave", self.OnLeave)
    self:SetScript("PostClick", self.PostClick)
end

function EABFlyoutBtnMixin:OnEnter()
    if GetCVarBool("UberTooltips") then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4)
        if GameTooltip:SetSpellByID(self.spellID) then
            self.UpdateTooltip = self.OnEnter
        else
            self.UpdateTooltip = nil
        end
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.spellName, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        self.UpdateTooltip = nil
    end
end

function EABFlyoutBtnMixin:OnLeave()
    GameTooltip:Hide()
end

function EABFlyoutBtnMixin:OnDataChanged()
    local fid = self:GetAttribute("flyoutID")
    local idx = self:GetAttribute("flyoutIndex")
    local sid, overrideSid, known, name = GetFlyoutSlotInfo(fid, idx)
    local tex = C_Spell.GetSpellTexture(overrideSid)
    self.icon:SetTexture(tex)
    self.icon:SetDesaturated(not known)
    self.spellID = sid
    self.spellName = name
    self:Refresh()
end

function EABFlyoutBtnMixin:PostClick()
    self:RefreshState()
end

function EABFlyoutBtnMixin:Refresh()
    self:RefreshCooldown()
    self:RefreshState()
    self:RefreshUsable()
    self:RefreshCount()
end

function EABFlyoutBtnMixin:RefreshCooldown()
    if self.spellID then
        ActionButton_UpdateCooldown(self)
    end
end

function EABFlyoutBtnMixin:RefreshState()
    if self.spellID then
        self:SetChecked(C_Spell.IsCurrentSpell(self.spellID) and true)
    else
        self:SetChecked(false)
    end
end

function EABFlyoutBtnMixin:RefreshUsable()
    local ico = self.icon
    local sid = self.spellID
    if sid then
        local usable, oom = C_Spell.IsSpellUsable(sid)
        if oom then
            ico:SetDesaturated(true)
            ico:SetVertexColor(0.4, 0.4, 1.0)
        elseif usable then
            ico:SetDesaturated(false)
            ico:SetVertexColor(1, 1, 1)
        else
            ico:SetDesaturated(true)
            ico:SetVertexColor(0.4, 0.4, 0.4)
        end
    else
        ico:SetDesaturated(false)
        ico:SetVertexColor(1, 1, 1)
    end
end

function EABFlyoutBtnMixin:RefreshCount()
    local sid = self.spellID
    if sid and C_Spell.IsConsumableSpell(sid) then
        local ct = C_Spell.GetSpellCastCount(sid)
        self.Count:SetText(ct > 9999 and "*" or ct)
    else
        self.Count:SetText("")
    end
end

-- Flyout frame mixin (the container that holds all flyout buttons)
local EABFlyoutFrameMixin = {}

-- Secure snippet: toggles the flyout open/closed, positions buttons
local SECURE_TOGGLE = [[
    local flyoutID = ...
    local caller = self:GetAttribute("caller")

    -- Toggle off if already open on the same button
    if self:IsShown() and caller == self:GetParent() then
        self:Hide()
        return
    end

    -- Sync this flyout's data if we haven't seen it before
    if not EAB_FLYOUT_DATA[flyoutID] then
        self:SetAttribute("_pendingSyncID", flyoutID)
        self:CallMethod("EnsureFlyoutSynced")
    end

    local data = EAB_FLYOUT_DATA[flyoutID]
    local slotCount = data and data.numSlots or 0
    local known = data and data.isKnown or false

    self:SetParent(caller)

    if slotCount == 0 or not known then
        self:Hide()
        return
    end

    local dir = caller:GetAttribute("flyoutDirection") or "UP"
    self:SetAttribute("direction", dir)

    -- Match flyout button size to the caller button
    local cW = caller:GetWidth()
    local cH = caller:GetHeight()

    local prev = nil
    local shown = 0

    for i = 1, slotCount do
        if data[i].isKnown then
            shown = shown + 1
            local btn = EAB_FLYOUT_BTNS[shown]
            btn:SetWidth(cW)
            btn:SetHeight(cH)
            btn:ClearAllPoints()

            if dir == "UP" then
                if prev then
                    btn:SetPoint("BOTTOM", prev, "TOP", 0, EAB_FLYOUT_SPACING)
                else
                    btn:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
                end
            elseif dir == "DOWN" then
                if prev then
                    btn:SetPoint("TOP", prev, "BOTTOM", 0, -EAB_FLYOUT_SPACING)
                else
                    btn:SetPoint("TOP", self, "TOP", 0, 0)
                end
            elseif dir == "LEFT" then
                if prev then
                    btn:SetPoint("RIGHT", prev, "LEFT", -EAB_FLYOUT_SPACING, 0)
                else
                    btn:SetPoint("RIGHT", self, "RIGHT", 0, 0)
                end
            elseif dir == "RIGHT" then
                if prev then
                    btn:SetPoint("LEFT", prev, "RIGHT", EAB_FLYOUT_SPACING, 0)
                else
                    btn:SetPoint("LEFT", self, "LEFT", 0, 0)
                end
            end

            btn:SetAttribute("spell", data[i].spellID)
            btn:SetAttribute("flyoutID", flyoutID)
            btn:SetAttribute("flyoutIndex", i)
            btn:Enable()
            btn:Show()
            btn:CallMethod("OnDataChanged")

            prev = btn
        end
    end

    -- Hide unused buttons
    for i = shown + 1, #EAB_FLYOUT_BTNS do
        EAB_FLYOUT_BTNS[i]:Hide()
    end

    if shown == 0 then
        self:Hide()
        return
    end

    local vert = false

    self:ClearAllPoints()
    if dir == "UP" then
        self:SetPoint("BOTTOM", caller, "TOP", 0, EAB_FLYOUT_SPACING)
        vert = true
    elseif dir == "DOWN" then
        self:SetPoint("TOP", caller, "BOTTOM", 0, -EAB_FLYOUT_SPACING)
        vert = true
    elseif dir == "LEFT" then
        self:SetPoint("RIGHT", caller, "LEFT", -EAB_FLYOUT_SPACING, 0)
    elseif dir == "RIGHT" then
        self:SetPoint("LEFT", caller, "RIGHT", EAB_FLYOUT_SPACING, 0)
    end

    if vert then
        self:SetWidth(cW)
        self:SetHeight((cH + EAB_FLYOUT_SPACING) * shown - EAB_FLYOUT_SPACING)
    else
        self:SetWidth((cW + EAB_FLYOUT_SPACING) * shown - EAB_FLYOUT_SPACING)
        self:SetHeight(cH)
    end

    self:CallMethod("OnFlyoutOpened")
    self:Show()
]]

function EABFlyoutFrameMixin:Init()
    self.btns = {}

    -- Initialize secure environment tables
    self:Execute(([[
        EAB_FLYOUT_DATA = newtable()
        EAB_FLYOUT_BTNS = newtable()
        EAB_FLYOUT_SPACING = %d
    ]]):format(FLYOUT_BTN_SPACING))

    self:SetAttribute("Toggle", SECURE_TOGGLE)
    self:SetAttribute("_onhide", [[ self:Hide(true) ]])

    self:SyncAllFlyouts()
end

function EABFlyoutFrameMixin:SyncAllFlyouts()
    -- Discover flyout IDs from all action slots (covers any flyout, including new ones)
    local seen = {}
    local maxSlots = 0
    for slot = 1, 180 do
        local aType, aID = GetActionInfo(slot)
        if aType == "flyout" and aID and not seen[aID] then
            seen[aID] = true
            local n = self:SyncFlyoutData(aID)
            if n > maxSlots then maxSlots = n end
        end
    end
    -- Also sync the known list as a safety net for unbound flyouts
    for _, fid in ipairs(KNOWN_FLYOUT_IDS) do
        if not seen[fid] then
            local n = self:SyncFlyoutData(fid)
            if n > maxSlots then maxSlots = n end
        end
    end
    self:EnsureButtons(maxSlots)
end

function EABFlyoutFrameMixin:SyncSingleFlyout(flyoutID)
    local n = self:SyncFlyoutData(flyoutID)
    if n > #self.btns then
        self:EnsureButtons(n)
        return true
    end
    return false
end

-- Called from the secure toggle via CallMethod when an unknown flyout ID is encountered.
-- Reads the pending ID from an attribute (secure env can't pass args to CallMethod).
function EABFlyoutFrameMixin:EnsureFlyoutSynced()
    local fid = self:GetAttribute("_pendingSyncID")
    if not fid then return end
    self:SyncSingleFlyout(fid)
end

function EABFlyoutFrameMixin:SyncFlyoutData(flyoutID)
    local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutID)

    self:Execute(([[
        local fid = %d
        local ns = %d
        local kn = %q == "true"
        local d = EAB_FLYOUT_DATA[fid] or newtable()
        d.numSlots = ns
        d.isKnown = kn
        EAB_FLYOUT_DATA[fid] = d
        for i = ns + 1, #d do d[i].isKnown = false end
    ]]):format(flyoutID, numSlots, tostring(isKnown)))

    for slot = 1, numSlots do
        local sid, _, slotKnown = GetFlyoutSlotInfo(flyoutID, slot)
        if slotKnown then
            local petIdx, petName = GetCallPetSpellInfo(sid)
            if petIdx and not (petName and petName ~= "") then
                slotKnown = false
            end
        end
        self:Execute(([[
            local d = EAB_FLYOUT_DATA[%d][%d] or newtable()
            d.spellID = %d
            d.isKnown = %q == "true"
            EAB_FLYOUT_DATA[%d][%d] = d
        ]]):format(flyoutID, slot, sid, tostring(slotKnown), flyoutID, slot))
    end

    return numSlots
end

function EABFlyoutFrameMixin:EnsureButtons(count)
    for i = #self.btns + 1, count do
        local btn = self:MakeFlyoutButton(i)
        self:SetFrameRef("_eabFlySlot", btn)
        self:Execute([[ tinsert(EAB_FLYOUT_BTNS, self:GetFrameRef("_eabFlySlot")) ]])
        self.btns[i] = btn
    end
end

-- Secure snippet for flyout button clicks: close the flyout on key-up
local FLYBTN_PRE = [[ if not down then return nil, "close" end ]]
local FLYBTN_POST = [[ if message == "close" then control:Hide() end ]]

function EABFlyoutFrameMixin:MakeFlyoutButton(idx)
    local name = "EABFlyoutBtn" .. idx
    local btn = CreateFrame("CheckButton", name, self,
        "SmallActionButtonTemplate, SecureActionButtonTemplate")
    Mixin(btn, EABFlyoutBtnMixin)
    btn:Setup()
    self:WrapScript(btn, "OnClick", FLYBTN_PRE, FLYBTN_POST)
    return btn
end

function EABFlyoutFrameMixin:ForVisible(method, ...)
    for _, btn in ipairs(self.btns) do
        if btn:IsShown() then btn[method](btn, ...) end
    end
end

-- Style flyout buttons to match the parent bar's appearance.
-- Called from the secure toggle via CallMethod after the flyout opens.
function EABFlyoutFrameMixin:OnFlyoutOpened()
    local caller = self:GetParent()
    if not caller then return end

    -- Find the bar key from the caller button
    local barKey = caller._eabBarKey
    if not barKey then return end

    local prof = EAB.db and EAB.db.profile
    if not prof then return end
    local s = prof.bars and prof.bars[barKey]
    if not s then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local shape = s.buttonShape or "none"
    local zoom = ((s.iconZoom or prof.iconZoom or 5.5)) / 100
    local brdSz = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    local brdColor = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    local shapeBrdColor = s.shapeBorderColor or brdColor
    local sbR, sbG, sbB, sbA = shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, shapeBrdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then sbR, sbG, sbB = cc.r, cc.g, cc.b end
        end
    end

    for _, btn in ipairs(self.btns) do
        if btn:IsShown() then
            -- Strip default SmallActionButton art
            self:StripFlyoutButtonArt(btn)

            if shape ~= "none" and shape ~= "cropped" and SHAPE_MASKS[shape] then
                -- Apply shape mask to flyout button
                self:ApplyFlyoutShape(btn, shape, brdOn, sbR, sbG, sbB, sbA, brdSz, zoom)
            else
                -- Square/cropped: apply borders and zoom
                self:ApplyFlyoutSquare(btn, brdOn, cr, cg, cb, ca, brdSz, zoom, shape == "cropped")
            end

            -- Apply pushed/highlight/misc texture animations to match the bar
            -- Only outside combat SetPushedTexture is restricted on secure buttons in combat.
            -- The textures persist after being set, so this only needs to run once per button.
            if not InCombatLockdown() then
                self:ApplyFlyoutAnimations(btn, prof)
            end
        end
    end
end

-- Apply pushed/highlight/misc button texture animations to a flyout button,
-- matching the global animation settings used on all action bar buttons.
-- NOTE: called via CallMethod (restricted env) cannot use file-local upvalues.
-- All texture operations are inlined; texture paths are read from the EAB profile.
function EABFlyoutFrameMixin:ApplyFlyoutAnimations(btn, prof)
    local useCC = prof.pushedUseClassColor
    local customC = prof.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb, ca = customC.r, customC.g, customC.b, customC.a or 1
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    local mediaDir = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
    local hlTex = {
        mediaDir .. "highlight-2.png",
        mediaDir .. "highlight-3.png",
        mediaDir .. "highlight-4.png",
    }
    local function ApplyTex(tex, path)
        if not tex then return end
        tex:SetAtlas(nil)
        tex:SetTexture(path)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetAllPoints(btn)
    end

    -- Pushed texture
    local pType = prof.pushedTextureType or 2
    if pType == 6 then
        btn:SetPushedTexture("")
        local pt = btn:GetPushedTexture()
        if pt then pt:SetAlpha(0) end
    else
        local texPath
        if pType <= 3 then
            texPath = hlTex[pType] or hlTex[2]
        elseif pType == 4 then
            texPath = "Interface\\Buttons\\WHITE8X8"
        else -- pType == 5
            texPath = hlTex[1]
        end
        btn:SetPushedTexture(texPath)
        local pt = btn:GetPushedTexture()
        if pt then
            pt:SetAlpha(1)
            pt:SetTexCoord(0, 1, 0, 1)
            pt:ClearAllPoints()
            pt:SetAllPoints(btn)
            if pType == 4 then
                pt:SetVertexColor(cr, cg, cb, 0.35)
            else
                pt:SetVertexColor(cr, cg, cb, 1)
            end
        end
    end

    -- Highlight texture
    local hType = prof.highlightTextureType or 2
    local hUseCC = prof.highlightUseClassColor
    local hCustomC = prof.highlightCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local hr, hg, hb = hCustomC.r, hCustomC.g, hCustomC.b
    if hUseCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then hr, hg, hb = cc.r, cc.g, cc.b end end
    end
    if btn.HighlightTexture then
        if hType == 6 then
            btn.HighlightTexture:SetAlpha(0)
        else
            btn.HighlightTexture:SetAlpha(1)
            if hType <= 3 then
                ApplyTex(btn.HighlightTexture, hlTex[hType] or hlTex[1])
                btn.HighlightTexture:SetVertexColor(hr, hg, hb, 1)
            elseif hType == 4 then
                btn.HighlightTexture:SetColorTexture(hr, hg, hb, 0.35)
            elseif hType == 5 then
                ApplyTex(btn.HighlightTexture, hlTex[1])
                btn.HighlightTexture:SetVertexColor(hr, hg, hb, 1)
            end
        end
    end

    -- NewActionTexture (uses pushed color)
    if btn.NewActionTexture then
        btn.NewActionTexture:SetDesaturated(true)
        btn.NewActionTexture:SetVertexColor(cr, cg, cb, ca)
    end
end

-- Remove default SmallActionButton template art from a flyout button
function EABFlyoutFrameMixin:StripFlyoutButtonArt(btn)
    if btn._eabFlyStripped then return end
    local nt = btn.NormalTexture or btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if btn.SlotBackground then btn.SlotBackground:Hide() end
    if btn.SlotArt then btn.SlotArt:Hide() end
    if btn.IconMask then
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end
    if btn.FlyoutBorderShadow then btn.FlyoutBorderShadow:SetAlpha(0) end
    -- Ensure icon fills the button
    local icon = btn.icon or btn.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
    end
    btn._eabFlyStripped = true
end

-- Apply square borders and zoom to a flyout button
function EABFlyoutFrameMixin:ApplyFlyoutSquare(btn, brdOn, cr, cg, cb, ca, brdSz, zoom, cropped)
    local PP = EllesmereUI and EllesmereUI.PP
    -- Remove shape mask if previously applied
    if btn._eabShapeMask then
        local icon = btn.icon or btn.Icon
        if icon then pcall(icon.RemoveMaskTexture, icon, btn._eabShapeMask) end
        if btn.cooldown and not btn.cooldown:IsForbidden() then
            pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, btn._eabShapeMask)
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "")
        end
        btn._eabShapeMask:Hide()
    end
    if btn._eabShapeBorder then btn._eabShapeBorder:Hide() end

    local icon = btn.icon or btn.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
        if cropped then
            local z = zoom or 0
            icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif zoom > 0 then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end

    if PP then
        if brdOn then
            if not btn._eabBorders then
                PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", -1)
                btn._eabBorders = btn._ppBorders
            end
            PP.UpdateBorder(btn, brdSz, cr, cg, cb, ca)
            PP.ShowBorder(btn)
        elseif btn._eabBorders then
            PP.HideBorder(btn)
        end
    end
end

-- Apply shape mask, border, and zoom to a flyout button
function EABFlyoutFrameMixin:ApplyFlyoutShape(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSz, zoom)
    local PP = EllesmereUI and EllesmereUI.PP
    local maskTex = SHAPE_MASKS[shape]
    if not maskTex then return end

    -- Hide square borders when using shapes
    if btn._eabBorders and PP then PP.HideBorder(btn) end

    -- Create or reuse shape mask
    if not btn._eabShapeMask then
        btn._eabShapeMask = btn:CreateMaskTexture()
    end
    local mask = btn._eabShapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:ClearAllPoints()
    if brdSz and brdSz >= 1 then
        if PP then
            PP.Point(mask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
            PP.Point(mask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        else
            mask:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            mask:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        end
    else
        mask:SetAllPoints(btn)
    end
    mask:Show()

    local icon = btn.icon or btn.Icon
    if icon then
        pcall(icon.RemoveMaskTexture, icon, mask)
        icon:AddMaskTexture(mask)
    end

    -- Expand icon for shape inset
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon and PP then
        icon:ClearAllPoints()
        PP.Point(icon, "TOPLEFT", btn, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Expand texcoords for shape
    local insetPx = SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon then icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Mask cooldown frame
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
        pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
        if btn.cooldown.SetSwipeTexture then
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if btn.cooldown.SetUseCircularEdge then
            pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, useCircular)
        end
    end

    -- Shape border overlay
    if not btn._eabShapeBorder then
        btn._eabShapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = btn._eabShapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(btn)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
    else
        borderTex:Hide()
    end
end

-------------------------------------------------------------------------------
--  Flyout Manager
--  Creates the frame on demand, registers buttons, handles events
-------------------------------------------------------------------------------
local EABFlyout = CreateFrame("Frame")

-- Secure snippet: intercepts flyout-type action clicks on registered buttons
local INTERCEPT_CLICK = [[
    local aType, aID = GetActionInfo(self:GetEffectiveAttribute("action", button))
    if aType == "flyout" then
        if not down then
            control:SetAttribute("caller", self:GetFrameRef("_eabFlyOwner") or self)
            control:RunAttribute("Toggle", aID)
        end
        return false
    end
]]

function EABFlyout:GetFrame()
    if self._frame then return self._frame end

    local f = CreateFrame("Frame", nil, nil, "SecureHandlerShowHideTemplate")
    Mixin(f, EABFlyoutFrameMixin)
    f:Init()
    f:HookScript("OnShow", function() self:OnShown() end)
    f:HookScript("OnHide", function() self:OnHidden() end)

    self:RegisterEvent("SPELL_FLYOUT_UPDATE")
    self:RegisterEvent("PET_STABLE_UPDATE")
    self:SetScript("OnEvent", self.OnEvent)

    self._frame = f
    return f
end

function EABFlyout:RegisterButton(button, owner)
    local f = self:GetFrame()
    -- Store a reference to the "real" parent button so the secure env
    -- can reparent the flyout to the correct visual button
    if owner then
        SecureHandlerSetFrameRef(button, "_eabFlyOwner", owner)
    end
    f:WrapScript(button, "OnClick", INTERCEPT_CLICK)
end

function EABFlyout:OnEvent(event, arg1)
    if event == "SPELL_FLYOUT_UPDATE" then
        if arg1 then
            if InCombatLockdown() then
                self._pendingSync = true
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                self._frame:SyncSingleFlyout(arg1)
            end
        end
        if self._frame then self._frame:ForVisible("Refresh") end
    elseif event == "PET_STABLE_UPDATE" then
        if InCombatLockdown() then
            self._pendingSync = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            self._frame:SyncAllFlyouts()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self._pendingSync then
            self._frame:SyncAllFlyouts()
            self._pendingSync = nil
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        if self._frame then self._frame:ForVisible("RefreshState") end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if self._frame then self._frame:ForVisible("RefreshCooldown") end
    elseif event == "SPELL_UPDATE_USABLE" then
        if self._frame then self._frame:ForVisible("RefreshUsable") end
    end
end

function EABFlyout:OnShown()
    if not self._flyoutVisible then
        self._flyoutVisible = true
        self:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("SPELL_UPDATE_USABLE")
    end
end

function EABFlyout:OnHidden()
    if self._flyoutVisible then
        self._flyoutVisible = nil
        self:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED")
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        self:UnregisterEvent("SPELL_UPDATE_USABLE")
    end
end

-- Public API for checking flyout visibility (used by mouseover fade logic)
function EABFlyout:IsVisible()
    return self._frame and self._frame:IsVisible()
end

function EABFlyout:IsMouseOver(...)
    return self._frame and self._frame:IsMouseOver(...)
end

function EABFlyout:GetParent()
    return self._frame and self._frame:GetParent()
end

-- Export for the main file and options
ns.EABFlyout = EABFlyout
