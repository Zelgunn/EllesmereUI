-------------------------------------------------------------------------------
--  EllesmereUI_Glows.lua
--  Shared glow rendering engine for the EllesmereUI addon suite.
--  Provides: Pixel Glow (procedural ants), Action Button Glow, Auto-Cast
--  Shine, Shape Glow, and FlipBook-based glows (GCD, Modern WoW, Classic WoW).
--  Each addon attaches to EllesmereUI.Glows.* instead of duplicating engines.
-------------------------------------------------------------------------------
if not EllesmereUI then return end
if EllesmereUI.Glows then return end  -- already loaded by another addon

local floor = math.floor
local min   = math.min
local ceil  = math.ceil
local sin   = math.sin

-------------------------------------------------------------------------------
--  Style Definitions (superset of all addons)
--  Each addon picks from this table by index or iterates for its dropdown.
--  Fields: name, procedural, buttonGlow, autocast, shapeGlow, atlas, texture,
--          rows, columns, frames, duration, frameW, frameH, scale, previewScale
-------------------------------------------------------------------------------
local GLOW_STYLES = {
    { name = "Pixel Glow",         procedural = true },
    { name = "Action Button Glow", buttonGlow = true },
    { name = "Auto-Cast Shine",    autocast   = true },
    { name = "Shape Glow",         shapeGlow  = true },
    { name = "GCD",
      atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow",
      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    { name = "Classic WoW Glow",
      texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3,
      frameW = 48, frameH = 48, texPadding = 1.25 },
}

-------------------------------------------------------------------------------
--  Texture constants
-------------------------------------------------------------------------------
local ANTS_TEX      = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local ICON_ALERT_TEX = [[Interface\SpellActivationOverlay\IconAlert]]
local BG_GLOW_L, BG_GLOW_R = 0.00781250, 0.50781250
local BG_GLOW_T, BG_GLOW_B = 0.27734375, 0.52734375
local SHINE_TEX    = [[Interface\Artifacts\Artifacts]]
local SHINE_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local SHINE_SIZES  = { 7, 6, 5, 4 }

-------------------------------------------------------------------------------
--  Procedural Ants Engine
--  N small rectangles orbit the perimeter of a frame each OnUpdate.
--  Each ant uses 2 textures: primary + overflow for corner wrapping.
-------------------------------------------------------------------------------
local function _EdgeAndOffset(dist, w, h)
    if dist < w then return 0, dist end
    dist = dist - w
    if dist < h then return 1, dist end
    dist = dist - h
    if dist < w then return 2, dist end
    return 3, dist - w
end

local function _PlaceOnEdge(tex, parent, edge, startOff, endOff, w, h, sTh, onePixel)
    local len = endOff - startOff
    if len < 0.5 then tex:Hide(); return end
    -- Snap length and offset to physical pixels (onePixel and sTh precomputed by caller)
    local sLen = floor(len / onePixel + 0.5) * onePixel
    if sLen < onePixel then tex:Hide(); return end
    local sOff = floor(startOff / onePixel + 0.5) * onePixel
    tex:ClearAllPoints()
    if edge == 0 then
        tex:SetSize(sLen, sTh); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", sOff, 0)
    elseif edge == 1 then
        tex:SetSize(sTh, sLen); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", w - sTh, -sOff)
    elseif edge == 2 then
        local sEnd = floor(endOff / onePixel + 0.5) * onePixel
        tex:SetSize(sLen, sTh); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", w - sEnd, -(h - sTh))
    else
        local sEnd = floor(endOff / onePixel + 0.5) * onePixel
        tex:SetSize(sTh, sLen); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(h - sEnd))
    end
    tex:Show()
end

local function _EdgeLen(edge, w, h)
    return (edge == 0 or edge == 2) and w or h
end

local function _AntsOnUpdate(self, elapsed)
    local d = self._euiAntsData
    if not d then return end
    d.timer = d.timer + elapsed
    if d.timer >= d.period then d.timer = d.timer - d.period end
    d._accum = (d._accum or 0) + elapsed
    if d._accum < 0.016 then return end
    d._accum = 0
    local w, h = d.w, d.h
    local onePixel = d.onePixel
    if w * h == 0 then
        w, h = self:GetSize()
        -- Strip taint from size values (reparented buttons can return
        -- "secret number" tainted dimensions from GetSize).
        w = tonumber(tostring(w)) or 0
        h = tonumber(tostring(h)) or 0
        -- Fallback to the sz passed at start time (SetAllPoints wrappers
        -- may return 0 before layout resolves)
        if w * h == 0 and d.fallbackSz and d.fallbackSz > 0 then
            w = d.fallbackSz; h = d.fallbackSz
        end
        if w * h == 0 then return end
        local PP = EllesmereUI.PP
        local es = self:GetEffectiveScale()
        onePixel = PP.perfect / es
        -- Snap dimensions to physical pixels
        w = floor(w / onePixel + 0.5) * onePixel
        h = floor(h / onePixel + 0.5) * onePixel
        -- Snap thickness once (constant while glow is active)
        local sTh = floor(d.th / onePixel + 0.5) * onePixel
        if sTh < onePixel then sTh = onePixel end
        d.w = w; d.h = h; d.onePixel = onePixel; d.sTh = sTh
    end
    local perim = 2 * (w + h)
    if perim <= 0 then return end
    local progress = d.timer / d.period
    local step = 1 / d.N
    local sTh = d.sTh
    for i = 1, d.N do
        local headDist = ((progress + (i - 1) * step) % 1) * perim
        local tailDist = headDist - d.lineLen
        if tailDist < 0 then tailDist = tailDist + perim end
        local headEdge, headOff = _EdgeAndOffset(headDist, w, h)
        local tailEdge, tailOff = _EdgeAndOffset(tailDist, w, h)
        local primary  = d.lines[i]
        local overflow = d.lines[i + d.N]
        if headEdge == tailEdge then
            _PlaceOnEdge(primary, self, headEdge, tailOff, headOff, w, h, sTh, onePixel)
            overflow:Hide()
        else
            _PlaceOnEdge(primary,  self, headEdge, 0,       headOff,                      w, h, sTh, onePixel)
            _PlaceOnEdge(overflow, self, tailEdge, tailOff, _EdgeLen(tailEdge, w, h), w, h, sTh, onePixel)
        end
    end
end

local function StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)
    if not wrapper._euiAntsData then
        wrapper._euiAntsData = { lines = {}, N = 0, timer = 0, w = 0, h = 0 }
    end
    local d = wrapper._euiAntsData
    d.N = N; d.th = th; d.period = period; d.lineLen = lineLen
    d.w = 0; d.h = 0; d.onePixel = nil; d.fallbackSz = sz or 0  -- reset so OnUpdate re-snaps to physical pixels
    local totalTex = N * 2
    for i = 1, totalTex do
        if not d.lines[i] then
            local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(1, 1, 1, 1)
            d.lines[i] = tex
        end
        d.lines[i]:SetVertexColor(cr, cg, cb, 1)
        d.lines[i]:Show()
    end
    for i = totalTex + 1, #d.lines do d.lines[i]:Hide() end
    wrapper:SetScript("OnUpdate", _AntsOnUpdate)
end

local function StopProceduralAnts(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiAntsData then
        for _, tex in ipairs(wrapper._euiAntsData.lines) do tex:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Action Button Glow Engine
--  Outer glow (soft border from IconAlert) + animated marching ants.
-------------------------------------------------------------------------------
local function _ButtonGlowOnUpdate(self, elapsed)
    local d = self._euiBgData
    if not d then return end
    AnimateTexCoords(d.ants, 256, 256, 48, 48, 22, elapsed, 0.01)
end

local function StartButtonGlow(wrapper, sz, cr, cg, cb, scale)
    scale = scale or 1.0
    if not wrapper._euiBgData then
        local glow = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetTexture(ICON_ALERT_TEX)
        glow:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER")
        local ants = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        ants:SetTexture(ANTS_TEX)
        ants:SetBlendMode("ADD")
        ants:SetPoint("CENTER")
        wrapper._euiBgData = { glow = glow, ants = ants }
    end
    local d = wrapper._euiBgData
    -- The ants texture has transparent padding baked into its frames,
    -- so we scale up to compensate and match the button edge visually.
    local antsSz = sz * 1.35
    local glowSz = antsSz * 1.3
    d.glow:SetSize(glowSz, glowSz)
    d.glow:SetDesaturated(true); d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()
    d.ants:SetSize(antsSz, antsSz)
    d.ants:SetDesaturated(true); d.ants:SetVertexColor(cr, cg, cb, 1)
    d.ants:SetAlpha(1); d.ants:Show()
    wrapper:SetScript("OnUpdate", _ButtonGlowOnUpdate)
end

local function StopButtonGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiBgData then
        wrapper._euiBgData.ants:Hide()
        wrapper._euiBgData.glow:Hide()
    end
end

-------------------------------------------------------------------------------
--  Auto-Cast Shine Engine
--  4 layers of N sparkle dots orbit the perimeter at different speeds.
-------------------------------------------------------------------------------
local function _AutoCastOnUpdate(self, elapsed)
    local d = self._euiAcData
    if not d then return end
    local timers = d.timers
    local pK1 = d.period
    for k = 1, 4 do
        timers[k] = timers[k] + elapsed / (pK1 * k)
        if timers[k] > 1 then timers[k] = timers[k] - 1 end
    end
    d._accum = (d._accum or 0) + elapsed
    if d._accum < 0.033 then return end
    d._accum = 0
    local w, h = d.w, d.h
    if w * h == 0 then
        w, h = self:GetSize()
        -- Strip taint from size values (reparented buttons can return
        -- "secret number" tainted dimensions from GetSize).
        w = tonumber(tostring(w)) or 0
        h = tonumber(tostring(h)) or 0
        -- Fallback to the sz passed at start time (SetAllPoints wrappers
        -- may return 0 before layout resolves)
        if w * h == 0 and d.fallbackSz and d.fallbackSz > 0 then
            w = d.fallbackSz; h = d.fallbackSz
        end
        if w * h == 0 then return end
        d.w = w; d.h = h
        local perim = 2 * (w + h)
        d.perim = perim
        d.rightLim = h + w
        d.bottomLim = h * 2 + w
        d.space = perim / d.N
        -- Precompute per-dot base offsets (space * i) to avoid multiplication each frame
        local offsets = d.offsets
        if not offsets then offsets = {}; d.offsets = offsets end
        for i = 1, d.N do offsets[i] = d.space * i end
    end
    local perim = d.perim
    local rightLim = d.rightLim
    local bottomLim = d.bottomLim
    local offsets = d.offsets
    local dots = d.dots
    local N = d.N
    local texIdx = 0
    for k = 1, 4 do
        local tK = timers[k] * perim
        for i = 1, N do
            texIdx = texIdx + 1
            local pos = (offsets[i] + tK) % perim
            local dot = dots[texIdx]
            dot:ClearAllPoints()
            if pos > bottomLim then
                dot:SetPoint("CENTER", self, "BOTTOMRIGHT", -(pos - bottomLim), 0)
            elseif pos > rightLim then
                dot:SetPoint("CENTER", self, "TOPRIGHT", 0, -(pos - rightLim))
            elseif pos > h then
                dot:SetPoint("CENTER", self, "TOPLEFT", pos - h, 0)
            else
                dot:SetPoint("CENTER", self, "BOTTOMLEFT", 0, pos)
            end
        end
    end
end

local function StartAutoCastShine(wrapper, sz, cr, cg, cb, scale)
    scale = scale or 1.0
    local N = 4
    local totalDots = N * 4
    if not wrapper._euiAcData then
        wrapper._euiAcData = { dots = {}, timers = { 0, 0.25, 0.5, 0.75 }, N = N, period = 2, w = 0, h = 0 }
    end
    local d = wrapper._euiAcData
    d.N = N
    d.timers[1] = 0; d.timers[2] = 0.25; d.timers[3] = 0.5; d.timers[4] = 0.75
    for idx = 1, totalDots do
        if not d.dots[idx] then
            local dot = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            dot:SetTexture(SHINE_TEX)
            dot:SetTexCoord(SHINE_COORDS[1], SHINE_COORDS[2], SHINE_COORDS[3], SHINE_COORDS[4])
            dot:SetDesaturated(true); dot:SetBlendMode("ADD")
            d.dots[idx] = dot
        end
        local layer = ceil(idx / N)
        local baseSz = (SHINE_SIZES[layer] or 4) * scale
        d.dots[idx]:SetSize(baseSz, baseSz)
        d.dots[idx]:SetVertexColor(cr, cg, cb, 1)
        d.dots[idx]:Show()
    end
    for idx = totalDots + 1, #d.dots do d.dots[idx]:Hide() end
    d.w = 0; d.h = 0; d.fallbackSz = sz or 0
    wrapper:SetScript("OnUpdate", _AutoCastOnUpdate)
end

local function StopAutoCastShine(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiAcData then
        for _, dot in ipairs(wrapper._euiAcData.dots) do dot:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Shape Glow Engine
--  Pulsing additive glow using the icon's shape mask texture.
--  Used by ActionBars (custom shapes) and CDM (custom icon shapes).
--  opts.maskPath   — path to the shape mask texture
--  opts.borderPath — path to the shape border texture
--  opts.shapeMask  — MaskTexture object for AddMaskTexture
-------------------------------------------------------------------------------
local function _ShapeGlowOnUpdate(self, elapsed)
    local d = self._euiSgData
    if not d then return end
    local timer = d.timer + elapsed * d.speed
    if timer > 6.2832 then timer = timer - 6.2832 end
    d.timer = timer
    d.glow:SetAlpha(0.25 + 0.25 * (0.5 + 0.5 * sin(timer)))
    local bright = d.bright
    if bright then
        local bTimer = (d.bTimer or 0) + elapsed * d.speed * 0.50
        if bTimer > 6.2832 then bTimer = bTimer - 6.2832 end
        d.bTimer = bTimer
        bright:SetAlpha(0.35 + 0.10 * (0.5 + 0.5 * sin(bTimer)))
    end
end

local function StartShapeGlow(wrapper, sz, cr, cg, cb, scale, opts)
    scale = scale or 1.20
    opts = opts or {}
    local btn = wrapper:GetParent()
    if not btn then return end
    if not wrapper._euiSgData then
        local glow   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        glow:SetBlendMode("ADD")
        local edge   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetBlendMode("ADD")
        local bright = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        bright:SetBlendMode("ADD")
        wrapper._euiSgData = { glow = glow, edge = edge, bright = bright, timer = 0, speed = 10.0 }
    end
    local d = wrapper._euiSgData
    d.timer = 0

    -- Glow extends slightly past the button edge for the pulsing effect
    local extend = sz * 0.10
    d.glow:ClearAllPoints()
    d.glow:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -extend,  extend)
    d.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  extend, -extend)
    local maskPath   = opts.maskPath
    local borderPath = opts.borderPath
    if maskPath then
        d.glow:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        d.glow:SetColorTexture(1, 1, 1, 1)
    end
    d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()

    -- Edge glow
    d.edge:ClearAllPoints()
    local inset = 4
    d.edge:SetPoint("TOPLEFT",     btn, "TOPLEFT",      inset, -inset)
    d.edge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  -inset,  inset)
    if borderPath then
        d.edge:SetTexture(borderPath)
    elseif maskPath then
        d.edge:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        d.edge:SetColorTexture(1, 1, 1, 1)
    end
    d.edge:SetBlendMode("ADD")
    d.edge:SetVertexColor(cr, cg, cb, 1)
    d.edge:SetAlpha(0.85); d.edge:Show()

    -- Bright border overlay
    d.bright:ClearAllPoints(); d.bright:SetAllPoints(btn)
    if borderPath then
        d.bright:SetTexture(borderPath)
    else
        d.bright:SetColorTexture(0, 0, 0, 0)
    end
    d.bright:SetVertexColor(cr, cg, cb, 1)
    d.bright:SetAlpha(0.5); d.bright:Show()

    -- Mask the pulsing glow with the shape mask texture
    local shapeMask = opts.shapeMask
    if shapeMask then
        pcall(d.glow.RemoveMaskTexture, d.glow, shapeMask)
        pcall(d.glow.AddMaskTexture, d.glow, shapeMask)
    end
    wrapper:SetScript("OnUpdate", _ShapeGlowOnUpdate)
end

local function StopShapeGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiSgData then
        wrapper._euiSgData.glow:Hide()
        wrapper._euiSgData.edge:Hide()
        wrapper._euiSgData.bright:Hide()
    end
end

-------------------------------------------------------------------------------
--  FlipBook Glow Engine
--  Handles atlas-based and raw-texture FlipBook animations (GCD, Modern WoW
--  Glow, Classic WoW Glow, and any future FlipBook styles).
-------------------------------------------------------------------------------
local function StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
    -- FlipBook frames have transparent padding baked in. Each atlas
    -- has a different amount, so the style entry carries a texPadding
    -- multiplier (defaults to 1 = no compensation).
    local texSz = sz * (entry.texPadding or 1)

    if not wrapper._euiFlipData then
        local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint("CENTER")
        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        wrapper._euiFlipData = { tex = tex, ag = ag, anim = anim }
    end
    local d = wrapper._euiFlipData
    d.tex:SetSize(texSz, texSz)
    if entry.atlas then
        d.tex:SetAtlas(entry.atlas)
    elseif entry.texture then
        d.tex:SetTexture(entry.texture)
    end
    d.tex:SetDesaturated(true)
    d.tex:SetVertexColor(cr, cg, cb)
    d.tex:Show()
    d.anim:SetFlipBookRows(entry.rows or 6)
    d.anim:SetFlipBookColumns(entry.columns or 5)
    d.anim:SetFlipBookFrames(entry.frames or 30)
    d.anim:SetDuration(entry.duration or 1.0)
    d.anim:SetFlipBookFrameWidth(entry.frameW or 0)
    d.anim:SetFlipBookFrameHeight(entry.frameH or 0)
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()

    -- Ants overlay: a non-desaturated duplicate at low alpha for atlas styles
    if entry.atlas then
        if not d.ants then
            local aTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            aTex:SetPoint("CENTER")
            aTex:SetBlendMode("ADD")
            local aAg = aTex:CreateAnimationGroup()
            aAg:SetLooping("REPEAT")
            local aAnim = aAg:CreateAnimation("FlipBook")
            d.ants = aTex; d.antsAg = aAg; d.antsAnim = aAnim
        end
        d.ants:SetSize(texSz, texSz)
        d.ants:SetAtlas(entry.atlas)
        d.ants:SetDesaturated(false)
        d.ants:SetVertexColor(1, 1, 1)
        d.ants:SetAlpha(0.35)
        d.antsAnim:SetFlipBookRows(entry.rows or 6)
        d.antsAnim:SetFlipBookColumns(entry.columns or 5)
        d.antsAnim:SetFlipBookFrames(entry.frames or 30)
        d.antsAnim:SetDuration(entry.duration or 1.0)
        d.antsAnim:SetFlipBookFrameWidth(entry.frameW or 0)
        d.antsAnim:SetFlipBookFrameHeight(entry.frameH or 0)
        d.ants:Show()
        if d.antsAg:IsPlaying() then d.antsAg:Stop() end
        d.antsAg:Play()
    elseif d.ants then
        d.ants:Hide()
        if d.antsAg then d.antsAg:Stop() end
    end

    wrapper:SetScript("OnUpdate", nil)
end

local function StopFlipBookGlow(wrapper)
    if wrapper._euiFlipData then
        wrapper._euiFlipData.tex:Hide()
        if wrapper._euiFlipData.ag then wrapper._euiFlipData.ag:Stop() end
        if wrapper._euiFlipData.ants then wrapper._euiFlipData.ants:Hide() end
        if wrapper._euiFlipData.antsAg then wrapper._euiFlipData.antsAg:Stop() end
    end
end

-------------------------------------------------------------------------------
--  StopAllGlows — clears any active glow engine on a wrapper frame
-------------------------------------------------------------------------------
local function StopAllGlows(wrapper)
    if not wrapper then return end
    StopProceduralAnts(wrapper)
    StopButtonGlow(wrapper)
    StopAutoCastShine(wrapper)
    StopShapeGlow(wrapper)
    StopFlipBookGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
end

-------------------------------------------------------------------------------
--  StartGlow — unified entry point
--  wrapper  : Frame to render the glow on
--  styleIdx : index into GLOW_STYLES (1-based)
--  sz       : icon/frame size in pixels
--  cr,cg,cb : glow color (0-1)
--  opts     : optional table with overrides:
--    .scale       — override entry.scale
--    .N, .th, .period — pixel glow tuning
--    .maskPath, .borderPath, .shapeMask — shape glow textures
-------------------------------------------------------------------------------
local function StartGlow(wrapper, styleIdx, sz, cr, cg, cb, opts)
    if not wrapper then return end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]
    opts = opts or {}
    sz = sz or 36
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    -- Stop any previous glow
    StopAllGlows(wrapper)

    if entry.procedural then
        local N       = opts.N or 8
        local th      = opts.th or 2
        local period  = opts.period or 4
        local lineLen = floor((sz + sz) * (2 / N - 0.1))
        lineLen = min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)

    elseif entry.buttonGlow then
        StartButtonGlow(wrapper, sz, cr, cg, cb)

    elseif entry.autocast then
        StartAutoCastShine(wrapper, sz, cr, cg, cb, 1.0)

    elseif entry.shapeGlow then
        StartShapeGlow(wrapper, sz, cr, cg, cb, 1.20, opts)

    else
        -- FlipBook mode (GCD, Modern WoW Glow, Classic WoW Glow, etc.)
        StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
    end

    wrapper._euiGlowActive = true
    wrapper:SetAlpha(1)
    wrapper:Show()
end

local function StopGlow(wrapper)
    if not wrapper then return end
    StopAllGlows(wrapper)
    wrapper._euiGlowActive = false
    wrapper:SetAlpha(0)
end

-------------------------------------------------------------------------------
--  Public API — attached to EllesmereUI.Glows
-------------------------------------------------------------------------------
EllesmereUI.Glows = {
    STYLES              = GLOW_STYLES,

    -- High-level API (recommended)
    StartGlow           = StartGlow,
    StopGlow            = StopGlow,

    -- Low-level engines (for addons that need direct control)
    StartProceduralAnts = StartProceduralAnts,
    StopProceduralAnts  = StopProceduralAnts,
    StartButtonGlow     = StartButtonGlow,
    StopButtonGlow      = StopButtonGlow,
    StartAutoCastShine  = StartAutoCastShine,
    StopAutoCastShine   = StopAutoCastShine,
    StartShapeGlow      = StartShapeGlow,
    StopShapeGlow       = StopShapeGlow,
    StartFlipBookGlow   = StartFlipBookGlow,
    StopFlipBookGlow    = StopFlipBookGlow,
    StopAllGlows        = StopAllGlows,
}
