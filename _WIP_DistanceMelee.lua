--------------------------------------------------------------------------------
--  _WIP_DistanceMelee.lua
--  REFERENCE ONLY -- This file is NOT loaded by any TOC.
--
--  Contains the WIP Distance to Target & Out of Melee Indicator feature,
--  extracted from EUI__General_Options.lua during dead code cleanup.
--
--  TO RE-IMPLEMENT:
--  1. Options UI (Block A) goes into EUI__General_Options.lua inside the
--     BuildHUDPage function, after the Secondary Stats section.
--     It creates two toggles (Distance to Target + Out of Melee Indicator)
--     with cog popups for font size, scale, color, and texture settings.
--
--  2. Runtime code (Block B) goes into EUI__General_Options.lua after the
--     options page builder, inside the same top-level do block.
--     It creates the actual frames, range estimation logic, update loop,
--     and the _applyDistanceText / _applyMeleeIndicator callbacks.
--
--  3. Unlock mode registration (Block C) goes into EUI__General_Options.lua
--     right after Block B. It registers both frames with the unlock mode
--     system so users can drag them around.
--
--  EllesmereUIDB keys used:
--    showDistanceText, distanceFontSize, distanceFixedColor, distanceTextColor,
--    distanceTextPos (table with point/relPoint/x/y/scale),
--    showMeleeIndicator, meleeTexture,
--    meleeIndicatorPos (table with point/relPoint/x/y/scale)
--------------------------------------------------------------------------------

--[[
================================================================================
BLOCK A: Options UI (goes in BuildHUDPage, after Secondary Stats section)
================================================================================

        local distRow
        distRow, h = W:DualRow(parent, y,
            { type="toggle", text="Distance to Target",
              tooltip="Displays estimated distance range to your current target.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.showDistanceText or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showDistanceText = v
                if EllesmereUI._applyDistanceText then EllesmereUI._applyDistanceText() end
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Out of Melee Indicator",
              tooltip="Displays a visual indicator when your target is out of melee range. Only visible during combat.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.showMeleeIndicator or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showMeleeIndicator = v
                if EllesmereUI._applyMeleeIndicator then EllesmereUI._applyMeleeIndicator() end
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Cog on Distance to Target (left region)
        do
            local leftRgn = distRow._leftRegion
            local function distOff()
                return not (EllesmereUIDB and EllesmereUIDB.showDistanceText)
            end

            local _, distCogShow = EllesmereUI.BuildCogPopup({
                title = "Distance Text Settings",
                rows = {
                    { type = "slider", label = "Font Size", min = 8, max = 36, step = 1,
                      get = function()
                          return (EllesmereUIDB and EllesmereUIDB.distanceFontSize) or 16
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.distanceFontSize = v
                          if EllesmereUI._applyDistanceText then EllesmereUI._applyDistanceText() end
                      end },
                    { type = "toggle", label = "Use Fixed Color",
                      get = function()
                          return EllesmereUIDB and EllesmereUIDB.distanceFixedColor or false
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.distanceFixedColor = v
                          if EllesmereUI._applyDistanceText then EllesmereUI._applyDistanceText() end
                      end },
                    { type = "colorpicker", label = "Fixed Color",
                      disabled = function()
                          return not (EllesmereUIDB and EllesmereUIDB.distanceFixedColor)
                      end,
                      disabledTooltip = "Use Fixed Color",
                      get = function()
                          local c = EllesmereUIDB and EllesmereUIDB.distanceTextColor
                          if c then return c.r, c.g, c.b end
                          return 1, 1, 1
                      end,
                      set = function(r, g, b)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.distanceTextColor = { r = r, g = g, b = b }
                      end },
                    { type = "slider", label = "Scale", min = 50, max = 200, step = 5,
                      get = function()
                          local pos = EllesmereUIDB and EllesmereUIDB.distanceTextPos
                          return floor(((pos and pos.scale) or 1.0) * 100 + 0.5)
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          if not EllesmereUIDB.distanceTextPos then EllesmereUIDB.distanceTextPos = {} end
                          EllesmereUIDB.distanceTextPos.scale = v / 100
                          if EllesmereUI._applyDistanceText then EllesmereUI._applyDistanceText() end
                      end },
                },
            })
            local distCogBtn = CreateFrame("Button", nil, leftRgn)
            distCogBtn:SetSize(26, 26)
            distCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = distCogBtn
            distCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            distCogBtn:SetAlpha(distOff() and 0.15 or 0.4)
            local distCogTex = distCogBtn:CreateTexture(nil, "OVERLAY")
            distCogTex:SetAllPoints()
            distCogTex:SetTexture(EllesmereUI.COGS_ICON)
            distCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            distCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(distOff() and 0.15 or 0.4) end)
            distCogBtn:SetScript("OnClick", function(self) distCogShow(self) end)

            local distCogBlock = CreateFrame("Frame", nil, distCogBtn)
            distCogBlock:SetAllPoints()
            distCogBlock:SetFrameLevel(distCogBtn:GetFrameLevel() + 10)
            distCogBlock:EnableMouse(true)
            distCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(distCogBtn, EllesmereUI.DisabledTooltip("Distance to Target"))
            end)
            distCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if distOff() then
                    distCogBtn:SetAlpha(0.15)
                    distCogBlock:Show()
                else
                    distCogBtn:SetAlpha(0.4)
                    distCogBlock:Hide()
                end
            end)
            distCogBtn:SetAlpha(distOff() and 0.15 or 0.4)
            if distOff() then distCogBlock:Show() else distCogBlock:Hide() end
        end

        -- Cog on Out of Melee Indicator (right region)
        do
            local rightRgn = distRow._rightRegion
            local function meleeOff()
                return not (EllesmereUIDB and EllesmereUIDB.showMeleeIndicator)
            end

            local meleeTexValues = {
                _menuOpts = {
                    icon = function(key)
                        if key and key ~= "" then return key end
                    end,
                    itemHeight = 30,
                },
                ["Interface\\RAIDFRAME\\ReadyCheck-NotReady"]          = { text = "Ready Check X" },
                ["Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"]    = { text = "Alert Icon (New)" },
                ["Interface\\Worldmap\\Skull_64Red"]                   = { text = "Red Skull" },
            }
            local meleeTexOrder = {
                "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
                "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
                "Interface\\Worldmap\\Skull_64Red",
            }

            local _, meleeCogShow = EllesmereUI.BuildCogPopup({
                title = "Melee Indicator Settings",
                rows = {
                    { type = "slider", label = "Scale", min = 25, max = 200, step = 5,
                      get = function()
                          local pos = EllesmereUIDB and EllesmereUIDB.meleeIndicatorPos
                          return floor(((pos and pos.scale) or 1.0) * 100 + 0.5)
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          if not EllesmereUIDB.meleeIndicatorPos then EllesmereUIDB.meleeIndicatorPos = {} end
                          EllesmereUIDB.meleeIndicatorPos.scale = v / 100
                          if EllesmereUI._applyMeleeIndicator then EllesmereUI._applyMeleeIndicator() end
                      end },
                    { type = "dropdown", label = "Texture",
                      values = meleeTexValues, order = meleeTexOrder,
                      get = function()
                          return (EllesmereUIDB and EllesmereUIDB.meleeTexture) or "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.meleeTexture = v
                          if EllesmereUI._applyMeleeIndicator then EllesmereUI._applyMeleeIndicator() end
                      end },
                },
            })
            local meleeCogBtn = CreateFrame("Button", nil, rightRgn)
            meleeCogBtn:SetSize(26, 26)
            meleeCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = meleeCogBtn
            meleeCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            meleeCogBtn:SetAlpha(meleeOff() and 0.15 or 0.4)
            local meleeCogTex = meleeCogBtn:CreateTexture(nil, "OVERLAY")
            meleeCogTex:SetAllPoints()
            meleeCogTex:SetTexture(EllesmereUI.COGS_ICON)
            meleeCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            meleeCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(meleeOff() and 0.15 or 0.4) end)
            meleeCogBtn:SetScript("OnClick", function(self) meleeCogShow(self) end)

            local meleeCogBlock = CreateFrame("Frame", nil, meleeCogBtn)
            meleeCogBlock:SetAllPoints()
            meleeCogBlock:SetFrameLevel(meleeCogBtn:GetFrameLevel() + 10)
            meleeCogBlock:EnableMouse(true)
            meleeCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(meleeCogBtn, EllesmereUI.DisabledTooltip("Out of Melee Indicator"))
            end)
            meleeCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if meleeOff() then
                    meleeCogBtn:SetAlpha(0.15)
                    meleeCogBlock:Show()
                else
                    meleeCogBtn:SetAlpha(0.4)
                    meleeCogBlock:Hide()
                end
            end)
            meleeCogBtn:SetAlpha(meleeOff() and 0.15 or 0.4)
            if meleeOff() then meleeCogBlock:Show() else meleeCogBlock:Hide() end
        end

================================================================================
BLOCK B: Runtime code (goes after the options page builder, inside the same
         top-level do block)
================================================================================

    do
        local distFrame, distText
        local meleeFrame, meleeTex
        local rangeUpdateFrame
        local RANGE_THROTTLE = 0.15
        local rangeElapsed = 0

        -------------------------------------------------------------------
        --  Range Check Data
        --
        --  Each entry: { range_yards, item_id }
        --  item_id is passed to C_Item.IsItemInRange.
        --
        --  Tables are sorted ascending by range.  The range estimator walks
        --  the list and returns the bracket [prevRange, range] for the
        --  first check that returns true.
        -------------------------------------------------------------------

        ---- Melee spell for indicator (accounts for hitbox, unlike items) --
        -- Keyed by spec ID (GetSpecializationInfo).  One spell per melee
        -- spec; ranged specs are absent -- indicator hides automatically.
        -- Recached on PLAYER_SPECIALIZATION_CHANGED.
        local MELEE_SPELL_BY_SPEC = {
            -- Death Knight (all melee)
            [250]  = 47528,   -- Blood:         Mind Freeze
            [251]  = 47528,   -- Frost:         Mind Freeze
            [252]  = 47528,   -- Unholy:        Mind Freeze
            -- Demon Hunter (all melee)
            [577]  = 162794,  -- Havoc:         Chaos Strike
            [581]  = 263642,  -- Vengeance:     Fracture
            -- Druid (Feral + Guardian are melee)
            [103]  = 5221,    -- Feral:         Shred
            [104]  = 33917,   -- Guardian:      Mangle
            -- Hunter (Survival only)
            [255]  = 186270,  -- Survival:      Raptor Strike
            -- Monk (all specs go into melee)
            [268]  = 100780,  -- Brewmaster:    Tiger Palm
            [269]  = 100780,  -- Windwalker:    Tiger Palm
            [270]  = 100780,  -- Mistweaver:    Tiger Palm
            -- Paladin (Prot + Ret are melee; Holy has no reliable melee spell)
            [66]   = 96231,   -- Protection:    Rebuke
            [70]   = 96231,   -- Retribution:   Rebuke
            -- Rogue (all melee)
            [259]  = 1766,    -- Assassination: Kick
            [260]  = 1766,    -- Outlaw:        Kick
            [261]  = 1766,    -- Subtlety:      Kick
            -- Shaman (Enhancement only)
            [263]  = 73899,   -- Enhancement:   Primal Strike
            -- Warrior (all melee)
            [71]   = 6552,    -- Arms:          Pummel
            [72]   = 6552,    -- Fury:          Pummel
            [73]   = 6552,    -- Protection:    Pummel
        }

        local cachedMeleeSpell          -- spell ID or false (ranged spec)
        local meleeSpellResolved = false

        local function GetMeleeSpell()
            if meleeSpellResolved then return cachedMeleeSpell end
            meleeSpellResolved = true
            local specIndex = GetSpecialization()
            if specIndex then
                local specID = GetSpecializationInfo(specIndex)
                cachedMeleeSpell = specID and MELEE_SPELL_BY_SPEC[specID] or false
            else
                cachedMeleeSpell = false
            end
            return cachedMeleeSpell
        end

        --- Returns true (in melee), false (out of melee), or nil (ranged spec).
        local function CheckMeleeRange(unit)
            local spellID = GetMeleeSpell()
            if not spellID then return nil end
            local ok, result = pcall(C_Spell.IsSpellInRange, spellID, unit)
            if ok and result ~= nil then return result end
            return nil
        end

        ---- Use /scanrange to find items for range checking ---------------
        ---- Hostile range checks ------------------------------------------
        local RANGE_HARM = {
            {   5,   8149 },    -- Voodoo Charm
            {  10,   9606 },    -- Treant Muisek Vessel
            {  15,   30651},    -- Dertok's First Wand
            {  20,   1191},     -- Bag of Marbles
            {  25,   13289},    -- Egan's Blaster
            {  30,   835 },     -- Large Rope Net
            {  35,   18904},    -- Zorbin's Ultra-Shrinker
            {  40,   4945 },    -- Faintly Glowing Skull
        }

        ---- Friendly range checks -----------------------------------------
        local RANGE_HELP = {
            {   5,   1970 },    -- Restoring Balm
            {  10,   17626},    -- Frostwolf Muzzle
            {  15,   1251},     -- Linen Bandage
            {  20,   17757},    -- Amulet of Spirits
            {  25,   13289},    -- Egan's Blaster
            {  30,   954},      -- Scroll of Strength
            {  35,   18904},    -- Zorbin's Ultra-Shrinker
            {  40,   1713},     -- Ankh of Life
        }

        -------------------------------------------------------------------
        --  Range estimation
        -------------------------------------------------------------------
        local function GetRangeEstimate(unit)
            if not UnitExists(unit) then return nil, nil end
            local isEnemy = UnitCanAttack("player", unit)
            local checks = isEnemy and RANGE_HARM or RANGE_HELP
            local prevRange = 0
            for _, entry in ipairs(checks) do
                local range, checker = entry[1], entry[2]
                local ok, inRange = pcall(C_Item.IsItemInRange, checker, unit)
                if ok and inRange == true then
                    return prevRange, range
                elseif ok and inRange == false then
                    prevRange = range
                end
            end
            return prevRange, nil
        end

        -------------------------------------------------------------------
        --  Distance color (discrete buckets)
        -------------------------------------------------------------------
        local DIST_COLORS = {
            {  5, 0.0, 1.0, 0.0 },   -- green: melee
            { 20, 1.0, 1.0, 0.0 },   -- yellow: control range
            { 25, 1.0, 0.75, 0.0 },  -- yellow-orange: evoker range
            { 30, 1.0, 0.5, 0.0 },   -- orange: short range spells
            { 40, 1.0, 0.25, 0.0 },  -- red-orange: standard range
        }
        local DIST_COLOR_FAR = { 1.0, 0.0, 0.0 }

        local function GetDistColor(maxRange)
            if not maxRange then
                return DIST_COLOR_FAR[1], DIST_COLOR_FAR[2], DIST_COLOR_FAR[3]
            end
            for _, entry in ipairs(DIST_COLORS) do
                if maxRange <= entry[1] then
                    return entry[2], entry[3], entry[4]
                end
            end
            return DIST_COLOR_FAR[1], DIST_COLOR_FAR[2], DIST_COLOR_FAR[3]
        end

        -------------------------------------------------------------------
        --  Update loop
        -------------------------------------------------------------------
        local inCombat = false

        local function UpdateRangeIndicators()
            local showDist  = EllesmereUIDB and EllesmereUIDB.showDistanceText
            local showMelee = EllesmereUIDB and EllesmereUIDB.showMeleeIndicator

            -- Early out: nothing to do
            if not showDist and not showMelee then
                if distFrame  then distFrame:Hide()  end
                if meleeFrame then meleeFrame:Hide() end
                return
            end

            if not UnitExists("target") then
                if distFrame  then distFrame:Hide()  end
                if meleeFrame then meleeFrame:Hide() end
                return
            end

            -- Only run the expensive item-based range scan when distance
            -- text is enabled.  The melee indicator uses spell range only.
            local minRange, maxRange
            if showDist then
                minRange, maxRange = GetRangeEstimate("target")
            end

            -- Snap to 5-yard increments for cleaner display
            local dispMin = minRange and (floor(minRange / 5) * 5) or nil
            local dispMax = maxRange and (ceil(maxRange / 5) * 5) or nil

            -- Distance text
            if showDist and distFrame then
                if dispMin and dispMax then
                    distText:SetText(dispMin .. " - " .. dispMax)
                elseif dispMin and not dispMax then
                    distText:SetText(dispMin .. "+")
                else
                    distText:SetText("?")
                end
                local useRangeColor = not (EllesmereUIDB and EllesmereUIDB.distanceFixedColor)
                if useRangeColor then
                    distText:SetTextColor(GetDistColor(maxRange))
                else
                    local c = EllesmereUIDB and EllesmereUIDB.distanceTextColor
                    if c then
                        distText:SetTextColor(c.r, c.g, c.b)
                    else
                        distText:SetTextColor(1, 1, 1)
                    end
                end
                local tw = distText:GetStringWidth() + 8
                local th = distText:GetStringHeight() + 4
                distFrame:SetSize(max(tw, 40), max(th, 20))
                distFrame:Show()
            elseif distFrame then
                distFrame:Hide()
            end

            -- Melee indicator (combat-only, melee specs only)
            if showMelee and meleeFrame then
                if not inCombat then
                    meleeFrame:Hide()
                else
                    local meleeResult = CheckMeleeRange("target")
                    if meleeResult == nil then
                        meleeFrame:Hide()
                    elseif meleeResult then
                        meleeFrame:Hide()
                    else
                        meleeFrame:Show()
                    end
                end
            elseif meleeFrame then
                meleeFrame:Hide()
            end
        end

        local function OnRangeUpdate(self, dt)
            rangeElapsed = rangeElapsed + dt
            if rangeElapsed < RANGE_THROTTLE then return end
            rangeElapsed = 0
            UpdateRangeIndicators()
        end

        local function EnsureUpdateFrame()
            if not rangeUpdateFrame then
                rangeUpdateFrame = CreateFrame("Frame")
                rangeUpdateFrame:SetScript("OnEvent", function(_, event)
                    if event == "PLAYER_REGEN_DISABLED" then
                        inCombat = true
                    elseif event == "PLAYER_REGEN_ENABLED" then
                        inCombat = false
                        if meleeFrame then meleeFrame:Hide() end
                    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
                        -- Re-resolve melee spell on spec change
                        meleeSpellResolved = false
                        cachedMeleeSpell = nil
                    else
                        rangeElapsed = RANGE_THROTTLE
                    end
                end)
            end
            local needDist  = EllesmereUIDB and EllesmereUIDB.showDistanceText
            local needMelee = EllesmereUIDB and EllesmereUIDB.showMeleeIndicator
            if needDist or needMelee then
                rangeUpdateFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
                rangeUpdateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                rangeUpdateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                rangeUpdateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
                rangeUpdateFrame:SetScript("OnUpdate", OnRangeUpdate)
                inCombat = InCombatLockdown()
            else
                rangeUpdateFrame:UnregisterAllEvents()
                rangeUpdateFrame:SetScript("OnUpdate", nil)
                if distFrame  then distFrame:Hide()  end
                if meleeFrame then meleeFrame:Hide() end
            end
        end

        -------------------------------------------------------------------
        --  Distance text frame
        -------------------------------------------------------------------
        local function CreateDistanceFrame()
            if distFrame then return end
            distFrame = CreateFrame("Frame", "EUI_DistanceText", UIParent)
            distFrame:SetSize(80, 30)
            distFrame:SetFrameStrata("HIGH")
            distFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            distFrame:EnableMouse(false)

            distText = distFrame:CreateFontString(nil, "OVERLAY")
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            local fontSize = (EllesmereUIDB and EllesmereUIDB.distanceFontSize) or 16
            distText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag())
            if EllesmereUI.GetFontUseShadow() then distText:SetShadowOffset(1, -1) end
            distText:SetPoint("CENTER")
            distText:SetJustifyH("CENTER")
        end

        local function ApplyDistanceText()
            local enabled = EllesmereUIDB and EllesmereUIDB.showDistanceText
            if not enabled then
                if distFrame then distFrame:Hide() end
                EnsureUpdateFrame()
                return
            end
            if not distFrame then CreateDistanceFrame() end
            local pos = EllesmereUIDB and EllesmereUIDB.distanceTextPos
            if pos then
                if pos.scale then pcall(function() distFrame:SetScale(pos.scale) end) end
                if pos.point then
                    distFrame:ClearAllPoints()
                    distFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                end
            end
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            local fontSize = (EllesmereUIDB and EllesmereUIDB.distanceFontSize) or 16
            distText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag())
            if EllesmereUI.GetFontUseShadow() then
                distText:SetShadowOffset(1, -1)
            else
                distText:SetShadowOffset(0, 0)
            end
            EnsureUpdateFrame()
        end

        EllesmereUI._applyDistanceText = ApplyDistanceText
        EllesmereUI._getDistanceFrame = function()
            if not distFrame then CreateDistanceFrame() end
            return distFrame
        end

        -------------------------------------------------------------------
        --  Melee indicator frame
        -------------------------------------------------------------------
        local function CreateMeleeFrame()
            if meleeFrame then return end
            meleeFrame = CreateFrame("Frame", "EUI_MeleeIndicator", UIParent)
            meleeFrame:SetSize(48, 48)
            meleeFrame:SetFrameStrata("HIGH")
            meleeFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            meleeFrame:EnableMouse(false)

            meleeTex = meleeFrame:CreateTexture(nil, "OVERLAY")
            meleeTex:SetAllPoints()
            local texPath = (EllesmereUIDB and EllesmereUIDB.meleeTexture) or "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
            meleeTex:SetTexture(texPath)
            meleeTex:SetVertexColor(1, 0, 0)
        end

        local function ApplyMeleeIndicator()
            local enabled = EllesmereUIDB and EllesmereUIDB.showMeleeIndicator
            if not enabled then
                if meleeFrame then meleeFrame:Hide() end
                EnsureUpdateFrame()
                return
            end
            if not meleeFrame then CreateMeleeFrame() end
            local texPath = (EllesmereUIDB and EllesmereUIDB.meleeTexture) or "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
            meleeTex:SetTexture(texPath)
            meleeTex:SetVertexColor(1, 0, 0)
            local pos = EllesmereUIDB and EllesmereUIDB.meleeIndicatorPos
            if pos then
                if pos.scale then pcall(function() meleeFrame:SetScale(pos.scale) end) end
                if pos.point then
                    meleeFrame:ClearAllPoints()
                    meleeFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                end
            end
            EnsureUpdateFrame()
        end

        EllesmereUI._applyMeleeIndicator = ApplyMeleeIndicator
        EllesmereUI._getMeleeFrame = function()
            if not meleeFrame then CreateMeleeFrame() end
            return meleeFrame
        end

        -- Apply on login
        C_Timer.After(1, function()
            if EllesmereUIDB and EllesmereUIDB.showDistanceText then
                ApplyDistanceText()
            end
            if EllesmereUIDB and EllesmereUIDB.showMeleeIndicator then
                ApplyMeleeIndicator()
            end
        end)
    end

================================================================================
BLOCK C: Unlock mode registration (goes right after Block B)
================================================================================

    C_Timer.After(1.5, function()
        if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
        EllesmereUI:RegisterUnlockElements({
            {
                key = "EUI_DistanceText",
                label = "Distance Text",
                order = 720,
                getFrame = function()
                    return EllesmereUI._getDistanceFrame and EllesmereUI._getDistanceFrame()
                end,
                getSize = function()
                    local f = EllesmereUI._getDistanceFrame and EllesmereUI._getDistanceFrame()
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 80, 30
                end,
                savePosition = function(key, point, relPoint, x, y, scale)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.distanceTextPos = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    local f = EllesmereUI._getDistanceFrame and EllesmereUI._getDistanceFrame()
                    if f then
                        if scale then pcall(function() f:SetScale(scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPosition = function()
                    return EllesmereUIDB and EllesmereUIDB.distanceTextPos
                end,
                getScale = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.distanceTextPos
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    if EllesmereUIDB then EllesmereUIDB.distanceTextPos = nil end
                end,
                applyPosition = function()
                    local f = EllesmereUI._getDistanceFrame and EllesmereUI._getDistanceFrame()
                    if not f then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.distanceTextPos
                    if pos and pos.point then
                        if pos.scale then pcall(function() f:SetScale(pos.scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            },
            {
                key = "EUI_MeleeIndicator",
                label = "Melee Indicator",
                order = 721,
                getFrame = function()
                    return EllesmereUI._getMeleeFrame and EllesmereUI._getMeleeFrame()
                end,
                getSize = function()
                    local f = EllesmereUI._getMeleeFrame and EllesmereUI._getMeleeFrame()
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 48, 48
                end,
                savePosition = function(key, point, relPoint, x, y, scale)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.meleeIndicatorPos = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    local f = EllesmereUI._getMeleeFrame and EllesmereUI._getMeleeFrame()
                    if f then
                        if scale then pcall(function() f:SetScale(scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPosition = function()
                    return EllesmereUIDB and EllesmereUIDB.meleeIndicatorPos
                end,
                getScale = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.meleeIndicatorPos
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    if EllesmereUIDB then EllesmereUIDB.meleeIndicatorPos = nil end
                end,
                applyPosition = function()
                    local f = EllesmereUI._getMeleeFrame and EllesmereUI._getMeleeFrame()
                    if not f then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.meleeIndicatorPos
                    if pos and pos.point then
                        if pos.scale then pcall(function() f:SetScale(pos.scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            },
        })
    end)

--]]