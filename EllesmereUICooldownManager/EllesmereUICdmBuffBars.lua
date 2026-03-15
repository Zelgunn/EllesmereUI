--------------------------------------------------------------------------------
--  EllesmereUICdmBuffBars.lua
--  Buff Bars: Tracked Buff Bars v2 (per-bar buff tracking with individual
--  settings) and legacy Buff Bars (disabled). Currently the legacy system is
--  disabled uncomment blocks to re-enable.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Set to true to enable Tracked Buff Bars functionality
local TBB_ENABLED = true

-- Forward references from main CDM file (set during init)
local ECME

function ns.InitBuffBars(ecme)
    ECME = ecme
end

-------------------------------------------------------------------------------
--  Tracked Buff Bars v2: Per-bar buff tracking with individual settings
--  Each bar tracks a single buff/aura and has its own display settings.
-------------------------------------------------------------------------------
local TBB_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local TBB_TEXTURES = {
    ["none"]          = nil,
    ["beautiful"]     = TBB_TEX_BASE .. "beautiful.tga",
    ["plating"]       = TBB_TEX_BASE .. "plating.tga",
    ["atrocity"]      = TBB_TEX_BASE .. "atrocity.tga",
    ["divide"]        = TBB_TEX_BASE .. "divide.tga",
    ["glass"]         = TBB_TEX_BASE .. "glass.tga",
    ["gradient-lr"]   = TBB_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TBB_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TBB_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TBB_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TBB_TEX_BASE .. "matte.tga",
    ["sheer"]         = TBB_TEX_BASE .. "sheer.tga",
}
local TBB_TEXTURE_ORDER = {
    "none", "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local TBB_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
ns.TBB_TEXTURES      = TBB_TEXTURES
ns.TBB_TEXTURE_ORDER = TBB_TEXTURE_ORDER
ns.TBB_TEXTURE_NAMES = TBB_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Popular Buffs: hardcoded entries shown in the spell picker.
--  spellIDs: list of all spell IDs that represent this buff (any match = active).
--  customDuration: fixed duration in seconds used to drive the bar fill.
--  icon: fileID to display (used when no spellID resolves an icon).
--  name: display name shown in the picker and on the bar.
-------------------------------------------------------------------------------
local TBB_POPULAR_BUFFS = {
    {
        key            = "bloodlust",
        name           = "Bloodlust / Heroism",
        icon           = 132313,
        spellIDs       = { 2825, 32182, 80353, 264667, 390386, 381301, 444062, 444257 },
        customDuration = 40,
    },
    {
        key            = "lights_potential",
        name           = "Light's Potential",
        icon           = 7548911,
        spellIDs       = { 1236616, 431932 },
        customDuration = 30,
    },
    {
        key            = "potion_recklessness",
        name           = "Potion of Recklessness",
        icon           = 7548916,
        spellIDs       = { 1236994 },
        customDuration = 30,
    },
    {
        key            = "invis_potion",
        name           = "Invisibility Potion",
        icon           = 134764,
        spellIDs       = { 371125, 431424, 371133, 371134, 1236551 },
        customDuration = 18,
    },
}
ns.TBB_POPULAR_BUFFS = TBB_POPULAR_BUFFS

-- Build a fast lookup: spellID -> popular buff entry (for UNIT_AURA detection)
local _popularSpellIDMap = {}
for _, entry in ipairs(TBB_POPULAR_BUFFS) do
    for _, sid in ipairs(entry.spellIDs) do
        _popularSpellIDMap[sid] = entry
    end
end

-- Forward declaration -- actual table is populated by BuildTrackedBuffBars below
local tbbFrames

--- Returns true if the user has at least one tracked buff bar configured
function ns.HasBuffBars()
    if not ECME or not ECME.db then return false end
    local tbb = ns.GetTrackedBuffBars()
    return tbb and tbb.bars and #tbb.bars > 0
end

-- Listen for spell casts to start duration timers for popular buffs that
-- don't leave a detectable aura (e.g. potions). Sets bar._customStart so
-- the fill animation runs for customDuration seconds.
local tbbCastListener = CreateFrame("Frame")
tbbCastListener:SetScript("OnEvent", function(_, _, _, _, spellID)
    if not spellID then return end
    local entry = _popularSpellIDMap[spellID]
    if not entry or not entry.customDuration then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return end
    local now = GetTime()
    for i, cfg in ipairs(tbb.bars) do
        if cfg.popularKey == entry.key then
            local bar = tbbFrames[i]
            if bar and bar._tbbReady then
                bar._customStart    = now
                bar._activeDuration = entry.customDuration
            end
        end
    end
end)

-- Resolve player class color for default fill
local _tbbClassR, _tbbClassG, _tbbClassB = 0.05, 0.82, 0.62
do
    local _, ct = UnitClass("player")
    if ct then
        local cc = RAID_CLASS_COLORS[ct]
        if cc then _tbbClassR, _tbbClassG, _tbbClassB = cc.r, cc.g, cc.b end
    end
end

local TBB_DEFAULT_BAR = {
    spellID   = 0,
    name      = "New Bar",
    enabled   = true,
    height    = 24,
    width     = 270,
    verticalOrientation = false,
    texture   = "none",
    fillR     = _tbbClassR, fillG = _tbbClassG, fillB = _tbbClassB, fillA = 1,
    bgR       = 0, bgG = 0, bgB = 0, bgA = 0.4,
    gradientEnabled = false,
    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
    gradientDir = "HORIZONTAL",
    opacity   = 1.0,
    showTimer = true,
    timerSize = 11,
    timerX    = 0,
    timerY    = 0,
    showName  = true,
    nameSize  = 11,
    nameX     = 0,
    nameY     = 0,
    showSpark = true,
    iconDisplay = "none",
    iconSize    = 24,
    iconX       = 0,
    iconY       = 0,
    iconBorderSize = 0,
    stacksPosition = "center",
    stacksSize     = 11,
    stacksX        = 0,
    stacksY        = 0,
}
ns.TBB_DEFAULT_BAR = TBB_DEFAULT_BAR

--- Get tracked buff bars profile data (with lazy init)
function ns.GetTrackedBuffBars()
    if not ECME or not ECME.db then return { selectedBar = 1, bars = {} } end
    local p = ECME.db.profile
    if not p.trackedBuffBars then
        p.trackedBuffBars = { selectedBar = 1, bars = {} }
    end
    return p.trackedBuffBars
end

--- Add a new tracked buff bar
function ns.AddTrackedBuffBar()
    local tbb = ns.GetTrackedBuffBars()
    local newBar = {}
    -- Copy settings from the last bar if one exists, otherwise use defaults
    local source = (#tbb.bars > 0) and tbb.bars[#tbb.bars] or TBB_DEFAULT_BAR
    for k, v in pairs(TBB_DEFAULT_BAR) do
        newBar[k] = (source[k] ~= nil) and source[k] or v
    end
    -- Always reset spell-specific fields
    newBar.spellID = 0
    newBar.name = "Bar " .. (#tbb.bars + 1)
    tbb.bars[#tbb.bars + 1] = newBar
    tbb.selectedBar = #tbb.bars

    -- Auto-position: place new bar adjacent to the previous one
    -- Horizontal: stack above; Vertical: place to the right
    local p = ECME and ECME.db and ECME.db.profile
    if p then
        if not p.tbbPositions then p.tbbPositions = {} end
        local prevIdx = #tbb.bars - 1
        if prevIdx >= 1 then
            local prevPosKey = tostring(prevIdx)
            local prevPos = p.tbbPositions[prevPosKey]
            local prevCfg = tbb.bars[prevIdx]
            local newPosKey = tostring(#tbb.bars)
            if prevPos and prevPos.point then
                local px = prevPos.x or 0
                local py = prevPos.y or 0
                if newBar.verticalOrientation then
                    -- Vertical bars: place to the right of previous
                    local barW = (prevCfg and prevCfg.height or 24) + 4
                    p.tbbPositions[newPosKey] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW, y = py,
                    }
                else
                    -- Horizontal bars: place above previous
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    p.tbbPositions[newPosKey] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px, y = py + barH,
                    }
                end
            end
        end
    end

    ns.BuildTrackedBuffBars()
    return #tbb.bars
end

--- Remove a tracked buff bar by index
function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    table.remove(tbb.bars, idx)
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = math.max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

--- Tracked buff bar frames
tbbFrames = {}
local tbbTickFrame
local _tbbRebuildPending = false

local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    return (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm")) or CDM_FONT_FALLBACK
end
local function GetTBBOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag()
    end
    return "OUTLINE"
end
local function GetTBBUseShadow()
    if EllesmereUI and EllesmereUI.GetFontUseShadow then
        return EllesmereUI.GetFontUseShadow()
    end
    return false
end
local function SetTBBFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local outline = GetTBBOutline()
    fs:SetFont(font, size, outline)
    if GetTBBUseShadow() then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function CreateTrackedBuffBarFrame(parent, idx)
    -- wrapFrame is the top-level container for bar + icon + border.
    -- Positioning, show/hide, and unlock mode all operate on wrapFrame.
    -- The StatusBar is a child of wrapFrame so the border can use SetAllPoints
    -- on wrapFrame for a pixel-perfect fit (same pattern as the cast bar).
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. idx, parent)
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(10)

    local bar = CreateFrame("StatusBar", "ECME_TBB" .. idx, wrapFrame)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.65)
    wrapFrame._bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    wrapFrame._bg = bg

    -- Spark
    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:Hide()
    wrapFrame._spark = spark

    -- Gradient clip frame (full-bar gradient masked to fill width)
    wrapFrame._gradClip = nil
    wrapFrame._gradTex = nil

    -- Text overlay: always sits above the fill texture and gradient clip
    local textOverlay = CreateFrame("Frame", nil, bar)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 3)
    wrapFrame._textOverlay = textOverlay

    -- Timer text
    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(timerText, GetCDMFont(), 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    wrapFrame._timerText = timerText

    -- Name text (left side)
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(nameText, GetCDMFont(), 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    wrapFrame._nameText = nameText

    -- Stacks text (positioned relative to the StatusBar)
    local stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetTBBFont(stacksText, GetCDMFont(), 11)
    stacksText:SetTextColor(1, 1, 1, 0.9)
    stacksText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    stacksText:Hide()
    wrapFrame._stacksText = stacksText

    -- Icon: child of wrapFrame so it is part of the combined rect.
    local icon = CreateFrame("Frame", nil, wrapFrame)
    icon:SetSize(24, 24)
    icon:Hide()
    local iconTex = icon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    icon._tex = iconTex
    wrapFrame._icon = icon

    -- Border: SetAllPoints(wrapFrame) so it covers bar + icon exactly.
    -- wrapFrame IS the combined rect, so this is always pixel-perfect.
    local bdrContainer = CreateFrame("Frame", nil, wrapFrame)
    bdrContainer:SetAllPoints(wrapFrame)
    bdrContainer:SetFrameLevel(wrapFrame:GetFrameLevel() + 5)
    bdrContainer:Hide()
    wrapFrame._barBorder = bdrContainer

    -- Hidden Cooldown widget for DurationObject mirroring
    local cd = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(false)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetAlpha(0)
    cd:Hide()
    wrapFrame._cooldown = cd

    wrapFrame:Hide()
    return wrapFrame
end

local function ApplyTrackedBuffBarSettings(bar, cfg)
    -- bar = wrapFrame (top-level container). bar._bar = the StatusBar child.
    if not bar or not cfg then return end
    local sb = bar._bar  -- StatusBar
    if not sb then return end
    local w = cfg.width or 200
    local h = cfg.height or 18
    local isVert = cfg.verticalOrientation
    bar._lastVertical = isVert  -- cached for per-frame spark re-anchor in tick
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = h  -- icon always matches bar height

    -- Size wrapFrame to cover bar + icon (same as cast bar's castBarFrame).
    -- Icon and bar are positioned inside wrapFrame so the border is pixel-perfect.
    if isVert then
        -- Vertical: bar is h wide x w tall; icon adds iSize to height
        local totalH = hasIcon and (w + iSize) or w
        bar:SetSize(h, totalH)
    else
        -- Horizontal: bar is w wide x h tall; icon adds iSize to width
        local totalW = hasIcon and (w + iSize) or w
        bar:SetSize(totalW, h)
    end

    -- Position StatusBar inside wrapFrame
    sb:ClearAllPoints()
    if hasIcon then
        if isVert then
            if iconMode == "left" then
                -- Icon at bottom, bar above it
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, iSize)
            else
                -- Icon at top, bar below it
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0, -iSize)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            end
        else
            if iconMode == "left" then
                -- Icon on left, bar to the right
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     iSize, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0,     0)
            else
                -- Icon on right, bar to the left
                sb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     0,      0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iSize, 0)
            end
        end
    else
        sb:SetAllPoints(bar)
    end

    -- Orientation
    sb:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")

    -- Texture (only re-set if changed to avoid fill flash)
    local texPath = TBB_TEXTURES[cfg.texture or "none"] or "Interface\\Buttons\\WHITE8x8"
    if bar._lastTexPath ~= texPath then
        sb:SetStatusBarTexture(texPath)
        bar._lastTexPath = texPath
    end

    -- Fill color (user-defined, defaults to class color)
    local fR, fG, fB, fA = cfg.fillR or _tbbClassR, cfg.fillG or _tbbClassG, cfg.fillB or _tbbClassB, cfg.fillA or 1
    sb:GetStatusBarTexture():SetVertexColor(fR, fG, fB, fA)

    -- Background color
    if bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end

    -- Gradient (clip frame approach: full-bar gradient masked to fill width)
    local fillTex = sb:GetStatusBarTexture()
    if cfg.gradientEnabled then
        local dir = cfg.gradientDir or "HORIZONTAL"

        fillTex:SetVertexColor(1, 1, 1, 0)

        if not bar._gradClip then
            local clip = CreateFrame("Frame", nil, sb)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(sb:GetFrameLevel() + 1)

            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT",     sb, "TOPLEFT",     0, 0)
            tex:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)

            bar._gradClip = clip
            bar._gradTex = tex
        end

        -- Anchor the clip frame to the fill texture so it tracks
        -- automatically when Blizzard's SetTimerDuration animates the bar.
        -- The fill texture shrinks as the buff expires; anchoring to it
        -- means the clip follows without any per-tick width calculations.
        local clip = bar._gradClip
        clip:ClearAllPoints()
        clip:SetAllPoints(fillTex)

        bar._gradTex:SetTexture(texPath)
        bar._gradTex:SetVertexColor(1, 1, 1, 1)
        bar._gradTex:SetGradient(dir,
            CreateColor(fR, fG, fB, fA),
            CreateColor(cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1)
        )

        clip:Show()
        bar._gradientActive = true
    else
        if bar._gradClip then bar._gradClip:Hide() end
        bar._gradientActive = nil

        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Opacity (target stored for smooth lerp in tick)
    bar._opacityTarget = cfg.opacity or 1.0
    if not bar._tbbReady then
        bar:SetAlpha(bar._opacityTarget)
    end

    -- Timer
    if cfg.showTimer then
        bar._timerText:Show()
        local tSize = cfg.timerSize or 11
        SetTBBFont(bar._timerText, GetCDMFont(), tSize)
        bar._timerText:ClearAllPoints()
        if isVert then
            bar._timerText:SetPoint("TOP", sb, "TOP", cfg.timerX or 0, -8 + (cfg.timerY or 0))
            bar._timerText:SetJustifyH("CENTER")
        else
            bar._timerText:SetPoint("RIGHT", sb, "RIGHT", -8 + (cfg.timerX or 0), cfg.timerY or 0)
            bar._timerText:SetJustifyH("RIGHT")
        end
    else
        bar._timerText:Hide()
    end

    -- Spark
    if cfg.showSpark then
        local sparkAnchor = (bar._gradientActive and bar._gradClip) or sb:GetStatusBarTexture()
        bar._spark:SetSize(8, h)
        bar._spark:SetRotation(0)
        bar._spark:ClearAllPoints()
        if isVert then
            bar._spark:SetPoint("CENTER", sparkAnchor, "TOP", 0, 0)
        else
            bar._spark:SetPoint("CENTER", sparkAnchor, "RIGHT", 0, 0)
        end
        bar._spark:Show()
    else
        bar._spark:Hide()
    end

    -- Name text (hidden in vertical orientation)
    if cfg.showName ~= false and not isVert then
        bar._nameText:Show()
        local nSize = cfg.nameSize or 11
        SetTBBFont(bar._nameText, GetCDMFont(), nSize)
        bar._nameText:ClearAllPoints()
        bar._nameText:SetPoint("LEFT", sb, "LEFT", 8 + (cfg.nameX or 0), cfg.nameY or 0)
        bar._nameText:SetJustifyH("LEFT")
        bar._nameText:SetWidth(w - 12 - (cfg.showTimer and 50 or 0))
    else
        bar._nameText:Hide()
    end

    -- Icon: positioned inside wrapFrame
    if hasIcon and bar._icon then
        bar._icon:SetSize(iSize, iSize)
        bar._icon:ClearAllPoints()
        if isVert then
            if iconMode == "left" then
                bar._icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            end
        else
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            end
        end
        bar._icon:Show()
    elseif bar._icon then
        bar._icon:Hide()
    end

    -- Stacks text positioning
    if bar._stacksText then
        local sPos = cfg.stacksPosition or "center"
        local sSize = cfg.stacksSize or 11
        local sX = cfg.stacksX or 0
        local sY = cfg.stacksY or 0
        SetTBBFont(bar._stacksText, GetCDMFont(), sSize)
        bar._stacksText:ClearAllPoints()
        if sPos == "top" then
            bar._stacksText:SetPoint("BOTTOM", sb, "TOP", sX, 5 + sY)
        elseif sPos == "bottom" then
            bar._stacksText:SetPoint("TOP", sb, "BOTTOM", sX, -5 + sY)
        elseif sPos == "left" then
            bar._stacksText:SetPoint("RIGHT", sb, "LEFT", -5 + sX, sY)
        elseif sPos == "right" then
            bar._stacksText:SetPoint("LEFT", sb, "RIGHT", 5 + sX, sY)
        else
            bar._stacksText:SetPoint("CENTER", sb, "CENTER", sX, sY)
        end
    end

    -- Border: bdrContainer already has SetAllPoints(wrapFrame) from creation.
    -- wrapFrame IS the combined rect, so the border is always pixel-perfect.
    if bar._barBorder then
        local bSz = cfg.borderSize or 0
        if bSz > 0 then
            local PP = EllesmereUI and EllesmereUI.PP
            if PP then
                if not bar._barBorder._ppBorders then
                    PP.CreateBorder(bar._barBorder, cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1, bSz)
                else
                    PP.UpdateBorder(bar._barBorder, bSz, cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1)
                end
                bar._barBorder:Show()
            end
        else
            bar._barBorder:Hide()
        end
    end
end

-- Reusable helpers for secret-safe aura field access (avoids closure allocation per tick)
local _tbbAura
local function _TBBGetDuration() return _tbbAura.duration end
local function _TBBGetExpiration() return _tbbAura.expirationTime end
local function _TBBGetName() return _tbbAura.name end
local function _TBBGetSpellId() return _tbbAura.spellId end

-- Scan player HELPFUL auras by name and return the matching auraData + spellId.
-- Cleans up _tbbAura after use so callers don't leak stale references.
-- Skips the scan entirely in combat since aura names are secret values.
local function _TBBScanByName(name)
    if InCombatLockdown() then return nil, nil end
    for ai = 1, 40 do
        local aData = C_UnitAuras.GetAuraDataByIndex("player", ai, "HELPFUL")
        if not aData then break end
        _tbbAura = aData
        local nOk, aName = pcall(_TBBGetName)
        if nOk and aName then
            -- Guard against secret values that slip through OOC edge cases.
            -- Wrap the comparison itself in pcall so tainted strings that
            -- bypass issecretvalue cannot propagate an error.
            if issecretvalue and issecretvalue(aName) then
                -- skip, can't compare
            else
                local cmpOk, matched = pcall(function() return aName == name end)
                if cmpOk and matched then
                    local sOk, sid = pcall(_TBBGetSpellId)
                    _tbbAura = nil
                    if sOk and sid and not (issecretvalue and issecretvalue(sid)) and sid > 0 then
                        return aData, sid
                    end
                    return nil, nil
                end
            end
        end
    end
    _tbbAura = nil
    return nil, nil
end

-- Scan current player buffs OOC to cache the real aura spellID for each TBB bar.
local function RefreshTBBResolvedIDs()
    if InCombatLockdown() then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and cfg.enabled ~= false and cfg.spellID and cfg.spellID > 0 and cfg.name and cfg.name ~= "" then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, cfg.spellID)
            if ok and aura then
                bar._resolvedAuraID = cfg.spellID
            else
                local _, sid = _TBBScanByName(cfg.name)
                if sid then bar._resolvedAuraID = sid end
            end
        end
    end
end
ns.RefreshTBBResolvedIDs = RefreshTBBResolvedIDs

-- Cache _customStart for popular buff bars on UNIT_AURA so the fill timer
-- starts at the right moment. Only needed for multi-ID (popular) bars that
-- use customDuration. Single-ID bars use the DurationObject path from the
-- Blizzard CDM child and need no event-driven caching.
local tbbAuraListener = CreateFrame("Frame")
tbbAuraListener:SetScript("OnEvent", function()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end
    local now = GetTime()
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and bar._tbbReady and cfg.enabled ~= false and cfg.spellIDs and cfg.customDuration then
            -- Only initialize _customStart if not already running
            if not bar._customStart then
                for _, sid in ipairs(cfg.spellIDs) do
                    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                    if ok and result then
                        local dur = result.duration
                        local exp = result.expirationTime
                        local secretD = issecretvalue and issecretvalue(dur)
                        local secretE = issecretvalue and issecretvalue(exp)
                        if not secretD and not secretE and dur and exp and dur > 0 and exp > 0 then
                            bar._activeDuration = cfg.customDuration
                            bar._customStart = now - (cfg.customDuration - math.max(0, exp - now))
                        else
                            -- Secret or no duration: start timer from now
                            bar._activeDuration = cfg.customDuration
                            bar._customStart = now
                        end
                        break
                    end
                end
            end
        end
    end
end)

--- Register or unregister TBB event listeners based on whether any bars are configured.
--- Call this whenever bars are added or removed.
function ns.RefreshBuffBarGating()
    local hasBars = ns.HasBuffBars()
    if hasBars then
        if not tbbCastListener:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED") then
            tbbCastListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        if not tbbAuraListener:IsEventRegistered("UNIT_AURA") then
            tbbAuraListener:RegisterUnitEvent("UNIT_AURA", "player")
        end
    else
        tbbCastListener:UnregisterAllEvents()
        tbbAuraListener:UnregisterAllEvents()
    end
end

function ns.BuildTrackedBuffBars()
    if not TBB_ENABLED then return end
    if not ECME or not ECME.db then return end
    if InCombatLockdown() then
        _tbbRebuildPending = true
        return
    end
    _tbbRebuildPending = false

    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local p = ECME.db.profile
    if not p.tbbPositions then p.tbbPositions = {} end

    -- Hide bars beyond current count
    for i = #bars + 1, #tbbFrames do
        if tbbFrames[i] then tbbFrames[i]:Hide() end
    end

    local anyEnabled = false
    for i, cfg in ipairs(bars) do
        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture: for popular buffs use the hardcoded icon, otherwise resolve from spell info
            if bar._icon and bar._icon._tex then
                local iconID = nil
                if cfg.popularKey then
                    -- Find the matching popular entry for its hardcoded icon
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then iconID = pe.icon; break end
                    end
                end
                if not iconID and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    if spInfo then iconID = spInfo.iconID end
                end
                if iconID then bar._icon._tex:SetTexture(iconID) end
            end

            -- Name text: prefer stored name (preserves custom item/spell names),
            -- fall back to spell info only when no name was stored.
            if cfg.showName ~= false and bar._nameText then
                local displayName = cfg.name
                if (not displayName or displayName == "") and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    displayName = spInfo and spInfo.name or ""
                end
                bar._nameText:SetText(displayName or "")
            end

            -- Saved position
            local posKey = tostring(i)
            local pos = p.tbbPositions[posKey]
            bar:ClearAllPoints()
            if pos and pos.point then
                if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            else
                bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
            end

            -- Mark bar as ready but keep hidden; the tick will show it
            -- when the tracked buff is actually active on the player.
            bar._tbbReady = true
            bar:Hide()
        end
    end

    if anyEnabled then
        if not tbbTickFrame then
            tbbTickFrame = CreateFrame("Frame")
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                -- Run every frame for smooth bar fill and spark movement,
                -- same as the cast bar approach.
                -- Smooth opacity lerp for all active bars
                local lerpSpeed = elapsed * 8
                for _, f in ipairs(tbbFrames) do
                    if f and f._opacityTarget then
                        local cur = f:GetAlpha()
                        local tgt = f._opacityTarget
                        if math.abs(cur - tgt) > 0.005 then
                            f:SetAlpha(cur + (tgt - cur) * math.min(1, lerpSpeed))
                        elseif cur ~= tgt then
                            f:SetAlpha(tgt)
                        end
                    end
                end
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        tbbTickFrame:Show()
    elseif tbbTickFrame then
        tbbTickFrame:Hide()
    end

    -- Re-register all bars with unlock mode so new/removed bars are reflected
    if ns.RegisterTBBUnlockElements then
        ns.RegisterTBBUnlockElements()
    end
    -- Gate event listeners based on whether any bars are configured
    ns.RefreshBuffBarGating()
end

-- Helper: update stacks text for a TBB bar.
-- Mirrors the CDM pattern: read the Blizzard child's Applications frame
-- text via GetText and pass it directly to SetText (no comparison needed,
-- works with secret values in combat).  Falls back to per-tick aura cache
-- (same cache CDM uses in ApplyStackCount).
local function UpdateTBBStacks(bar, cfg)
    if not bar._stacksText then return end

    local buffChildCache = ns._tickBlizzBuffChildCache
    local allChildCache  = ns._tickBlizzAllChildCache
    local auraCache      = ns._tickAuraCache

    -- Multi-ID (popular) bars: check each spellID
    if cfg.spellIDs then
        for _, sid in ipairs(cfg.spellIDs) do
            -- Path 1: Blizzard child Applications frame (works in combat)
            local blzChild = buffChildCache[sid] or allChildCache[sid]
            if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
                local appsText = blzChild.Applications.Applications
                if appsText then
                    local ok, txt = pcall(appsText.GetText, appsText)
                    if ok and txt then
                        bar._stacksText:SetText(txt)
                        bar._stacksText:Show()
                        return
                    end
                end
            end
            -- Path 2: per-tick aura cache (same as CDM ApplyStackCount)
            if auraCache then
                local aura = auraCache[sid]
                if aura == nil then
                    local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                    aura = (ok and res) or false
                    auraCache[sid] = aura
                end
                if aura then
                    local apps = aura.applications
                    if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                        bar._stacksText:SetText(tostring(apps))
                        bar._stacksText:Show()
                        return
                    end
                end
            end
        end
        bar._stacksText:Hide()
        return
    end

    -- Single-ID bars
    local resolvedID = bar._resolvedAuraID or cfg.spellID
    if not resolvedID or resolvedID <= 0 then
        bar._stacksText:Hide()
        return
    end

    -- Path 1: Blizzard child Applications frame (works in combat)
    local blzChild = buffChildCache[resolvedID] or allChildCache[resolvedID]
                  or buffChildCache[cfg.spellID] or allChildCache[cfg.spellID]
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local ok, txt = pcall(appsText.GetText, appsText)
            if ok and txt then
                bar._stacksText:SetText(txt)
                bar._stacksText:Show()
                return
            end
        end
    end

    -- Path 2: per-tick aura cache (same as CDM ApplyStackCount)
    if auraCache then
        local aura = auraCache[resolvedID]
        if aura == nil then
            local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
            aura = (ok and res) or false
            auraCache[resolvedID] = aura
        end
        if aura then
            local apps = aura.applications
            if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                bar._stacksText:SetText(tostring(apps))
                bar._stacksText:Show()
                return
            end
        end
    end

    bar._stacksText:Hide()
end

function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local now = GetTime()
    local activeCache = ns._tickBlizzActiveCache
    local buffChildCache = ns._tickBlizzBuffChildCache
    local allChildCache = ns._tickBlizzAllChildCache
    local IsBufChildActive = ns.IsBufChildCooldownActive
    local inCombat = InCombatLockdown()

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if not bar or not bar._tbbReady then
            -- bar not configured or disabled, skip
        elseif cfg.enabled == false then
            bar:Hide()
        elseif cfg.spellIDs then
            -- Multi-ID bar (popular buffs). Active if any ID is in the CDM active cache.
            local sb = bar._bar  -- StatusBar child of wrapFrame
            local isActive = false
            for _, sid in ipairs(cfg.spellIDs) do
                if activeCache[sid] then
                    isActive = true
                    break
                end
            end

            -- Fall back to cast-triggered custom timer (covers potions etc. that
            -- may not appear in CDM viewers at all)
            if not isActive and bar._customStart then
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 then
                    local elapsed = now - bar._customStart
                    if elapsed < activeDur then
                        isActive = true
                    else
                        bar._customStart    = nil
                        bar._activeDuration = nil
                    end
                end
            end

            if isActive then
                if not bar:IsShown() then bar:Show() end
                UpdateTBBStacks(bar, cfg)

                -- All multi-ID bars use customDuration for the fill animation
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 and bar._customStart then
                    local elapsed = now - bar._customStart
                    local remaining = math.max(0, activeDur - elapsed)
                    local frac = remaining / activeDur
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(frac)
                    if cfg.showTimer and bar._timerText then
                        if remaining <= 0 then
                            bar._timerText:Hide()
                        else
                            local t
                            if remaining >= 60 then t = format("%dm", floor(remaining / 60))
                            elseif remaining >= 10 then t = format("%d", floor(remaining))
                            else t = format("%.1f", remaining) end
                            bar._timerText:SetText(t)
                            bar._timerText:Show()
                        end
                    end
                    if remaining <= 0 then
                        bar._customStart    = nil
                        bar._activeDuration = nil
                        bar:Hide()
                    end
                else
                    -- Active but no custom timer started yet (or permanent)
                    sb:SetValue(1)
                    if cfg.showTimer and bar._timerText then bar._timerText:Hide() end
                end
            else
                if bar:IsShown() then bar:Hide() end
                if bar._stacksText then bar._stacksText:Hide() end
            end
        elseif not cfg.spellID or cfg.spellID == 0 then
            bar:Hide()
        else
            local spellID = cfg.spellID
            local resolvedID = bar._resolvedAuraID or spellID
            local sb = bar._bar  -- StatusBar child of wrapFrame

            -- Check active state using the same caches the core CDM builds
            local isActive = activeCache[resolvedID] or activeCache[spellID]
            local blzChild = buffChildCache[resolvedID] or buffChildCache[spellID]
                          or allChildCache[resolvedID] or allChildCache[spellID]
            if not isActive then
                if IsBufChildActive and IsBufChildActive(blzChild) then
                    isActive = true
                end
            end

            if not isActive and inCombat and (cfg.customDuration or bar._activeDuration) and bar._customStart then
                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 then
                    local elapsed = now - bar._customStart
                    if elapsed < activeDur then
                        isActive = true
                    else
                        bar._customStart    = nil
                        bar._activeDuration = nil
                    end
                end
            end

            if isActive then
                if not bar:IsShown() then bar:Show() end
                UpdateTBBStacks(bar, cfg)

                local activeDur = bar._activeDuration or cfg.customDuration
                if activeDur and activeDur > 0 and bar._customStart then
                    local elapsed = now - bar._customStart
                    local remaining = math.max(0, activeDur - elapsed)
                    local frac = remaining / activeDur
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(frac)

                    if cfg.showTimer and bar._timerText then
                        if remaining <= 0 then
                            bar._timerText:Hide()
                        else
                            local t
                            if remaining >= 3600 then t = format("%dh", floor(remaining / 3600))
                            elseif remaining >= 60 then t = format("%dm", floor(remaining / 60))
                            elseif remaining >= 10 then t = format("%d", floor(remaining))
                            else t = format("%.1f", remaining) end
                            bar._timerText:SetText(t)
                            bar._timerText:Show()
                        end
                    end

                    if remaining <= 0 then
                        bar._customStart    = nil
                        bar._activeDuration = nil
                        bar:Hide()
                    end
                else
                    -- Standard DurationObject path via Blizzard CDM child
                    local durObj = nil
                    if blzChild then
                        local auraID = blzChild.auraInstanceID
                        local auraUnit = blzChild.auraDataUnit or "player"
                        if auraID then
                            local ok, d = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                            if ok and d then durObj = d end
                        end
                    end

                    if durObj then
                        sb:SetMinMaxValues(0, 1)
                        sb:SetTimerDuration(durObj, Enum.StatusBarInterpolation.None, Enum.StatusBarTimerDirection.RemainingTime)
                        sb:SetToTargetValue()

                        if cfg.showTimer and bar._timerText then
                            local ok, remaining = pcall(durObj.GetRemainingDuration, durObj)
                            if ok and remaining then
                                local isSecret = issecretvalue and issecretvalue(remaining)
                                if isSecret then
                                    local fok, fstr = pcall(format, "%.1f", remaining)
                                    if fok and fstr then
                                        bar._timerText:SetText(fstr)
                                    else
                                        bar._timerText:SetText(remaining)
                                    end
                                else
                                    local t
                                    if remaining >= 3600 then t = format("%dh", floor(remaining / 3600))
                                    elseif remaining >= 60 then t = format("%dm", floor(remaining / 60))
                                    elseif remaining >= 10 then t = format("%d", floor(remaining))
                                    else t = format("%.1f", remaining) end
                                    bar._timerText:SetText(t)
                                end
                                bar._timerText:Show()
                            else
                                bar._timerText:Hide()
                            end
                        end
                    else
                        -- Permanent buff or no duration object available
                        sb:SetValue(1)
                        if cfg.showTimer and bar._timerText then bar._timerText:Hide() end
                    end
                end
            else
                -- Buff not active, hide the bar and clear state
                if bar:IsShown() then bar:Hide() end
                if bar._stacksText then bar._stacksText:Hide() end
                bar._resolvedAuraID = nil
                bar._customStart = nil
                bar._activeDuration = nil
                if bar._cooldown then bar._cooldown:Clear() end
            end
        end
    end

    -- Re-anchor sparks every frame so they track the fill edge smoothly,
    -- same as the cast bar approach.
    for _, bar in ipairs(tbbFrames) do
        if bar and bar._spark and bar._spark:IsShown() and bar._bar then
            local sb = bar._bar
            local cfg_isVert = bar._lastVertical  -- cached from ApplyTrackedBuffBarSettings
            bar._spark:ClearAllPoints()
            if bar._gradientActive and bar._gradClip then
                if cfg_isVert then
                    bar._spark:SetPoint("CENTER", bar._gradClip, "TOP", 0, 0)
                else
                    bar._spark:SetPoint("CENTER", bar._gradClip, "RIGHT", 0, 0)
                end
            else
                if cfg_isVert then
                    bar._spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "TOP", 0, 0)
                else
                    bar._spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)
                end
            end
        end
    end
end
function ns.IsTBBRebuildPending()
    return _tbbRebuildPending
end

-------------------------------------------------------------------------------
--  Register Tracked Buff Bars with unlock mode
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not TBB_ENABLED then return end
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars or #bars == 0 then return end

    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        if bar then
            elements[#elements + 1] = {
                key = "TBB_" .. posKey,
                label = "Buff Bar: " .. (cfg.name or ("Bar " .. idx)),
                group = "Cooldown Manager",
                order = 650,
                getFrame = function() return tbbFrames[idx] end,
                getSize = function()
                    local f = tbbFrames[idx]
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 200, 24
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    local p = ECME.db.profile
                    if not p.tbbPositions then p.tbbPositions = {} end
                    p.tbbPositions[posKey] = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    local f = tbbFrames[idx]
                    if f then
                        if scale then pcall(function() f:SetScale(scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x, y)
                    end
                    ns.BuildTrackedBuffBars()
                end,
                loadPosition = function()
                    local p = ECME.db.profile
                    return p.tbbPositions and p.tbbPositions[posKey]
                end,
                getScale = function()
                    local p = ECME.db.profile
                    local pos = p.tbbPositions and p.tbbPositions[posKey]
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    local p = ECME.db.profile
                    if p.tbbPositions then p.tbbPositions[posKey] = nil end
                end,
                applyPosition = function()
                    ns.BuildTrackedBuffBars()
                end,
            }
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements)
    end
end

--[[ BUFF BARS: DISABLED (untested uncomment to re-enable)
-------------------------------------------------------------------------------
--  Buff Bars: Custom aura tracking display
--  Shows player buffs as horizontal timer bars
-------------------------------------------------------------------------------
local FormatTime, UpdateBuffBars
do
local buffBarFrame       -- container
local buffBarPool = {}   -- reusable bar frames
local activeBuffBars = {}
local CLASS_COLORS_BUFF = {
    WARRIOR = {0.78,0.61,0.43}, PALADIN = {0.96,0.55,0.73}, HUNTER = {0.67,0.83,0.45},
    ROGUE = {1,0.96,0.41}, PRIEST = {1,1,1}, DEATHKNIGHT = {0.77,0.12,0.23},
    SHAMAN = {0,0.44,0.87}, MAGE = {0.25,0.78,0.92}, WARLOCK = {0.53,0.53,0.93},
    MONK = {0,1,0.60}, DRUID = {1,0.49,0.04}, DEMONHUNTER = {0.64,0.19,0.79},
    EVOKER = {0.20,0.58,0.50},
}

local function CreateBuffBar(parent, idx)
    local p = ECME.db.profile.buffBars
    local bar = CreateFrame("StatusBar", "ECME_BuffBar" .. idx, parent)
    bar:SetSize(p.width, p.height)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, p.bgAlpha)
    bar._bg = bg

    -- Border via unified PP system (outside the bar)
    local PP = EllesmereUI and EllesmereUI.PP
    local borderWrap = CreateFrame("Frame", nil, bar)
    borderWrap:SetFrameLevel(bar:GetFrameLevel())
    bar._borderWrap = borderWrap

    function bar:ApplyBorder(s, r, g, b, a)
        local bw = self._borderWrap
        if s and s > 0 then
            bw:ClearAllPoints()
            if PP then
                PP.SetOutside(bw, self, s, s)
            else
                bw:SetPoint("TOPLEFT", self, "TOPLEFT", -s, s)
                bw:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", s, -s)
            end
            if not bw._ppBorders then
                if PP then PP.CreateBorder(bw, r, g, b, a or 1, s, "OVERLAY", 7) end
            else
                if PP then PP.UpdateBorder(bw, s, r, g, b, a or 1) end
            end
            bw:Show()
        else
            bw:Hide()
        end
    end

    -- Icon
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(p.iconSize, p.iconSize)
    icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    bar._icon = icon

    -- Name text
    local nameText = bar:CreateFontString(nil, "OVERLAY")
    SetTBBFont(nameText, GetCDMFont(), 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetJustifyH("LEFT")
    bar._nameText = nameText

    -- Timer text
    local timerText = bar:CreateFontString(nil, "OVERLAY")
    SetTBBFont(timerText, GetCDMFont(), 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    bar._timerText = timerText

    bar:Hide()
    return bar
end

FormatTime = function(sec)
    local key = floor(sec * 10)
    local now = floor(GetTime())
    if now ~= _fmtCacheSec then
        wipe(_fmtCache)
        _fmtCacheSec = now
    end
    local cached = _fmtCache[key]
    if cached then return cached end
    local result
    if sec >= 3600 then result = format("%dh", floor(sec / 3600))
    elseif sec >= 60 then result = format("%dm", floor(sec / 60))
    elseif sec >= 10 then result = format("%d", floor(sec))
    else result = format("%.1f", sec)
    end
    _fmtCache[key] = result
    return result
end

local function MatchesFilter(name, filterMode, filterList)
    if filterMode == "all" then return true end
    if not filterList or filterList == "" then return filterMode == "blacklist" end
    local lower = name:lower()
    for entry in filterList:gmatch("[^,;]+") do
        entry = entry:match("^%s*(.-)%s*$"):lower()
        if entry ~= "" and lower:find(entry, 1, true) then
            return filterMode == "whitelist"
        end
    end
    return filterMode == "blacklist"
end

local _buffBarBuf = {}
local _buffSortNow = 0
local function _SortBuffsByRemaining(a, b)
    local ra = a.expires > 0 and (a.expires - _buffSortNow) or 9999
    local rb = b.expires > 0 and (b.expires - _buffSortNow) or 9999
    return ra < rb
end

UpdateBuffBars = function()
    if not ECME or not ECME.db then return end
    local p = ECME.db.profile.buffBars
    if not p.enabled then
        if buffBarFrame then buffBarFrame:Hide() end
        return
    end

    if not buffBarFrame then
        buffBarFrame = CreateFrame("Frame", "ECME_BuffBarFrame", UIParent)
        buffBarFrame:SetPoint("CENTER", UIParent, "CENTER", p.offsetX, p.offsetY)
        buffBarFrame:SetSize(p.width + 4, 200)
        buffBarFrame:SetFrameStrata("MEDIUM")
        buffBarFrame:SetMovable(true)
        buffBarFrame:SetClampedToScreen(true)
        if buffBarFrame.EnableMouseClicks then buffBarFrame:EnableMouseClicks(false) end
        buffBarFrame:RegisterForDrag("LeftButton")
        buffBarFrame:SetScript("OnDragStart", function(self)
            if not ECME.db.profile.buffBars.locked then self:StartMoving() end
        end)
        buffBarFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint(1)
            if x then
                ECME.db.profile.buffBars.offsetX = x
                ECME.db.profile.buffBars.offsetY = y
            end
        end)
    end

    buffBarFrame:Show()
    buffBarTickFrame:Show()

    local _, classFile = UnitClass("player")
    local now = GetTime()
    local buffs = _buffBarBuf
    local buffCount = 0

    for i = 1, 40 do
        local auraData = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex("player", i)
        if not auraData then break end
        local name = auraData.name
        local iconTex = auraData.icon
        local duration = auraData.duration or 0
        local expirationTime = auraData.expirationTime or 0

        if name and MatchesFilter(name, p.filterMode, p.filterList) then
            buffCount = buffCount + 1
            local entry = buffs[buffCount]
            if not entry then
                entry = {}
                buffs[buffCount] = entry
            end
            entry.name = name
            entry.icon = iconTex
            entry.duration = duration
            entry.expires = expirationTime
        end
        if buffCount >= p.maxBars then break end
    end
    for i = buffCount + 1, #buffs do buffs[i] = nil end

    _buffSortNow = now
    table.sort(buffs, _SortBuffsByRemaining)

    local cr, cg, cb = p.barR, p.barG, p.barB
    if p.useClassColor then
        local cc = CLASS_COLORS_BUFF[classFile]
        if cc then cr, cg, cb = cc[1], cc[2], cc[3] end
    end

    for idx = 1, #buffs do
        local data = buffs[idx]
        local bar = buffBarPool[idx]
        if not bar then
            bar = CreateBuffBar(buffBarFrame, idx)
            buffBarPool[idx] = bar
        end

        bar:SetSize(p.width, p.height)
        bar:ClearAllPoints()
        local yDir = p.growUp and 1 or -1
        bar:SetPoint("TOPLEFT", buffBarFrame, "TOPLEFT", 0, yDir * (idx - 1) * (p.height + p.spacing))
        bar:ApplyBorder(p.borderSize, p.borderR, p.borderG, p.borderB, p.borderA)
        bar._bg:SetColorTexture(0, 0, 0, p.bgAlpha)
        bar:GetStatusBarTexture():SetVertexColor(cr, cg, cb, 1)

        if p.showIcon and data.icon then
            bar._icon:SetTexture(data.icon)
            bar._icon:SetSize(p.iconSize, p.iconSize)
            bar._icon:Show()
            bar._nameText:SetPoint("LEFT", bar._icon, "RIGHT", 4, 0)
        else
            bar._icon:Hide()
            bar._nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        end

        bar._nameText:SetText(data.name)
        bar._data = data
        bar._nameText:SetWidth(p.width - (p.showIcon and p.iconSize + 8 or 8) - (p.showTimer and 40 or 0))

        if data.duration > 0 and data.expires > 0 then
            local remaining = data.expires - now
            if remaining < 0 then remaining = 0 end
            bar:SetValue(remaining / data.duration)
            if p.showTimer then
                bar._timerText:SetText(FormatTime(remaining))
                bar._timerText:Show()
            else
                bar._timerText:Hide()
            end
        else
            bar:SetValue(1)
            if p.showTimer then
                bar._timerText:SetText("")
            end
            bar._timerText:Hide()
        end

        bar:Show()
        activeBuffBars[idx] = bar
    end

    for i = #buffs + 1, #buffBarPool do
        if buffBarPool[i] then buffBarPool[i]:Hide() end
    end
    for i = #buffs + 1, #activeBuffBars do activeBuffBars[i] = nil end

    local totalH = #buffs * (p.height + p.spacing)
    buffBarFrame:SetSize(p.width + 4, totalH > 0 and totalH or 1)
end

local buffBarTickFrame = CreateFrame("Frame")
buffBarTickFrame:Hide()
buffBarTickFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.05 then return end
    self.elapsed = 0
    if not ECME or not ECME.db or not ECME.db.profile.buffBars.enabled then
        self:Hide()
        return
    end
    local now = GetTime()
    for idx, bar in ipairs(activeBuffBars) do
        if bar and bar:IsShown() and bar._data then
            local data = bar._data
            if data.duration > 0 and data.expires > 0 then
                local remaining = data.expires - now
                if remaining < 0 then remaining = 0 end
                bar:SetValue(remaining / data.duration)
                if ECME.db.profile.buffBars.showTimer then
                    bar._timerText:SetText(FormatTime(remaining))
                end
            end
        end
    end
end)

end  -- do (Buff Bars scope)
--]] -- END BUFF BARS DISABLED
