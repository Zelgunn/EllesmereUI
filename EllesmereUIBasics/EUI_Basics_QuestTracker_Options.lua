-------------------------------------------------------------------------------
-- EUI_QuestTracker_Options.lua
-------------------------------------------------------------------------------
local addonName, ns = ...
local EQT = ns.EQT

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EQT then return end

    local function DB()
        local basicsDB = _G._EBS_AceDB
        if basicsDB and basicsDB.profile and basicsDB.profile.questTracker then
            return basicsDB.profile.questTracker
        end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end
    local function Refresh() if EQT.Refresh       then EQT:Refresh()       end end

    local function MakeCogBtn(rgn, showFn)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    local function GetColor(key, dr, dg, db)
        local c = Cfg(key)
        if not c then Set(key, {r=dr,g=dg,b=db}); c = Cfg(key) end
        return c.r, c.g, c.b
    end

    local function BuildPage(_, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local PP = EllesmereUI.PP

        -- ── DISPLAY ────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        local visRow
        visRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES_BASICS,
              order  = EllesmereUI.VIS_ORDER_BASICS,
              getValue=function()
                  if Cfg("enabled") == false then return "disabled" end
                  return Cfg("visibility") or "always"
              end,
              setValue=function(v)
                  if v == "disabled" then
                      Set("enabled", false)
                      Set("visibility", "disabled")
                  else
                      Set("enabled", true)
                      Set("visibility", v)
                  end
                  local f = EQT and EQT.frame
                  if f then
                      if Cfg("enabled") == false then f:Hide()
                      else f:Show(); Refresh() end
                  end
                  if EQT.ApplyBlizzardTrackerVisibility then EQT.ApplyBlizzardTrackerVisibility() end
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k) return Cfg(k) or false end,
                function(k, v)
                    Set(k, v)
                    if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity", min=0, max=100, step=5,
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return math.floor(((Cfg("bgAlpha") or 0.35)*100)+0.5) end,
              setValue=function(v)
                  Set("bgAlpha", v/100)
                  local br, bg, bb = Cfg("bgR") or 0, Cfg("bgG") or 0, Cfg("bgB") or 0
                  if EQT.frame and EQT.frame.bg then EQT.frame.bg:SetColorTexture(br, bg, bb, v/100) end
              end },
            { type="dropdown", text="Alignment",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values = { top = "Top", center = "Centered", bottom = "Bottom" },
              order  = { "top", "center", "bottom" },
              getValue=function() return Cfg("alignment") or "top" end,
              setValue=function(v)
                  Set("alignment", v)
                  Refresh()
              end })
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function() return Cfg("bgR") or 0, Cfg("bgG") or 0, Cfg("bgB") or 0 end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    local a = Cfg("bgAlpha") or 0.35
                    if EQT.frame and EQT.frame.bg then EQT.frame.bg:SetColorTexture(r, g, b, a) end
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Height",
              min=100, max=800, step=10,
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("height") or 600 end,
              setValue=function(v)
                  Set("height", v)
                  Refresh()
              end },
            { type="slider", text="Width", min=160, max=400, step=5,
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("width") or 220 end,
              setValue=function(v)
                  Set("width", v)
                  if EQT.frame then
                      EQT.frame:SetWidth(v)
                      if not EQT._widthDragging then
                          EQT._widthDragging = true
                          for _, r in ipairs(EQT.rows) do
                              if r.text then r.text:SetWordWrap(false) end
                          end
                      end
                      if EQT._widthTimer then EQT._widthTimer:Cancel() end
                      EQT._widthTimer = C_Timer.NewTimer(0.15, function()
                          EQT._widthTimer = nil
                          EQT._widthDragging = false
                          EQT:Refresh()
                      end)
                  end
              end })
        y = y - h

        y = y - 10

        -- ── EXTRAS ─────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Accept Quests",
              getValue=function() return Cfg("autoAccept") or false end,
              setValue=function(v) Set("autoAccept", v) end },
            { type="toggle", text="Auto Turn In Quests",
              getValue=function() return Cfg("autoTurnIn") or false end,
              setValue=function(v) Set("autoTurnIn", v) end })
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Auto Turn In Settings",
                rows = {
                    { type="toggle", label="Hold Shift to Skip",
                      get=function() return Cfg("autoTurnInShiftSkip") ~= false end,
                      set=function(v) Set("autoTurnInShiftSkip", v) end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Zone Quests",
              getValue=function() return Cfg("showZoneQuests") ~= false end,
              setValue=function(v) Set("showZoneQuests", v); Refresh() end },
            { type="toggle", text="Show World Quests",
              getValue=function() return Cfg("showWorldQuests") ~= false end,
              setValue=function(v) Set("showWorldQuests", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Prey Quests",
              getValue=function() return Cfg("showPreyQuests") ~= false end,
              setValue=function(v) Set("showPreyQuests", v); Refresh() end },
            { type="toggle", text="Show Quest Items",
              getValue=function() return Cfg("showQuestItems") ~= false end,
              setValue=function(v) Set("showQuestItems", v); Refresh() end })
        -- Resize icon on Show Quest Items for item size
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Quest Item Settings",
                rows = {
                    { type="slider", label="Item Size", min=16, max=36, step=2,
                      get=function() return Cfg("questItemSize") or 22 end,
                      set=function(v) Set("questItemSize", v); Refresh() end },
                },
            })
            local resBtn = CreateFrame("Button", nil, rgn)
            resBtn:SetSize(26, 26)
            resBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = resBtn
            resBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            resBtn:SetAlpha(0.4)
            local resTex = resBtn:CreateTexture(nil, "OVERLAY")
            resTex:SetAllPoints()
            resTex:SetTexture(EllesmereUI.RESIZE_ICON)
            resBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            resBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            resBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        y = y - h

        -- Quest Item Hotkey row
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type="label", text="" },
            { type="label", text="" })
        do
            local rgn = kbRow._leftRegion
            local SIDE_PAD = 20
            local KB_W, KB_H = 120, 26

            local label = EllesmereUI.MakeFont(rgn, 14, nil, EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", rgn, "LEFT", SIDE_PAD, 0)
            label:SetText("Quest Item Hotkey")

            local kbBtn = CreateFrame("Button", nil, rgn)
            PP.Size(kbBtn, KB_W, KB_H)
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -SIDE_PAD, 0)
            kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
            kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            kbLbl:SetPoint("CENTER")

            local function FormatKey(key)
                if not key or key == "" then return "Not Bound" end
                local parts = {}
                for mod in key:gmatch("(%u+)%-") do
                    parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                end
                local actualKey = key:match("[^%-]+$") or key
                parts[#parts + 1] = actualKey
                return table.concat(parts, " + ")
            end

            local function RefreshLabel()
                kbLbl:SetText(FormatKey(Cfg("questItemHotkey")))
            end
            RefreshLabel()

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then
                        listening = false
                        self:EnableKeyboard(false)
                    end
                    Set("questItemHotkey", nil)
                    if EQT and EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText("Press a key...")
                kbBtn:EnableKeyboard(true)
            end)

            kbBtn:SetScript("OnKeyDown", function(self, key)
                if not listening then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                   or key == "LALT" or key == "RALT" then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                if key == "ESCAPE" then
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    return
                end
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                local fullKey = mods .. key
                Set("questItemHotkey", fullKey)
                if EQT and EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
            end)

            kbBtn:SetScript("OnEnter", function(self)
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, 0.3)
                end
                EllesmereUI.ShowWidgetTooltip(self, "Left-click to set a keybind.\nRight-click to unbind.")
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                end
                EllesmereUI.HideWidgetTooltip()
            end)

            EllesmereUI.RegisterWidgetRefresh(RefreshLabel)

            rgn:SetScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                    RefreshLabel()
                end
            end)
        end
        y = y - h

        y = y - 10

        -- ── TEXT ───────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "TEXT", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Header Size", min=6, max=24, step=1,
              getValue=function() return Cfg("secFontSize") or 8 end,
              setValue=function(v) Set("secFontSize", v); Refresh() end },
            { type="slider", text="Title Size", min=8, max=24, step=1,
              getValue=function() return Cfg("titleFontSize") or 11 end,
              setValue=function(v) Set("titleFontSize", v); Refresh() end })
        do
            local function AttachSwatch(rgn, label, colorKey, dr, dg, db)
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = Cfg(colorKey) or {}
                        return c.r or dr, c.g or dg, c.b or db
                    end,
                    function(r, g, b)
                        local c = Cfg(colorKey) or {}
                        c.r = r; c.g = g; c.b = b; Set(colorKey, c); Refresh()
                    end,
                    false, 20)
                local ctrl = rgn._control
                sw:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, label .. " Color") end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            AttachSwatch(row._leftRegion,  "Header", "secColor",   0.047, 0.824, 0.624)
            AttachSwatch(row._rightRegion, "Title",  "titleColor", 1.0,   0.85,  0.1)
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Quest Size", min=7, max=24, step=1,
              getValue=function() return Cfg("objFontSize") or 10 end,
              setValue=function(v) Set("objFontSize", v); Refresh() end },
            { type="label", text="" })
        do
            local function AttachSwatch(rgn, label, colorKey, dr, dg, db)
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = Cfg(colorKey) or {}
                        return c.r or dr, c.g or dg, c.b or db
                    end,
                    function(r, g, b)
                        local c = Cfg(colorKey) or {}
                        c.r = r; c.g = g; c.b = b; Set(colorKey, c); Refresh()
                    end,
                    false, 20)
                local ctrl = rgn._control
                sw:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, label .. " Color") end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            AttachSwatch(row._leftRegion, "Quest", "objColor", 0.72, 0.72, 0.72)
        end
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildQuestTrackerPage = BuildPage
    _G._EBS_ResetQuestTracker = function()
        local basicsDB = _G._EBS_AceDB
        if basicsDB and basicsDB.profile then basicsDB.profile.questTracker = nil end
        if EQT and EQT.Refresh then EQT:Refresh() end
    end
end)
