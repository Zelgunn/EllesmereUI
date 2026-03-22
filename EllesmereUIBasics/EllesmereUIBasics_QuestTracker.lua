-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker.lua
-------------------------------------------------------------------------------
local addonName, ns = ...

local C = {
    accent    = { r=0.047, g=0.824, b=0.624 },
    complete  = { r=0.25,  g=1.0,   b=0.35  },
    failed    = { r=1.0,   g=0.3,   b=0.3   },
    header    = { r=1.0,   g=1.0,   b=1.0   },
    section   = { r=0.047, g=0.824, b=0.624 },
    timer     = { r=1.0,   g=0.82,  b=0.2   },
    timerLow  = { r=1.0,   g=0.3,   b=0.3   },
    barBg     = { r=0.15,  g=0.15,  b=0.15  },
    barFill   = { r=0.047, g=0.824, b=0.624 },
}

local EQT      = {}
ns.EQT         = EQT
EQT.rows       = {}
EQT.sections   = {}
EQT.itemBtns   = {}
EQT.timerRows  = {}   -- rows with active timers (need OnUpdate)
EQT.dirty      = false

-------------------------------------------------------------------------------
-- DB
-------------------------------------------------------------------------------
local function DB()
    -- Quest tracker data lives under the shared Basics Lite DB at profile.questTracker
    local basicsDB = _G._EBS_AceDB
    if basicsDB and basicsDB.profile and basicsDB.profile.questTracker then
        return basicsDB.profile.questTracker
    end
    -- Fallback: Lite hasn't initialized yet, return a temporary table
    if not EQT._tmpDB then EQT._tmpDB = {} end
    return EQT._tmpDB
end
local function Cfg(k) return DB()[k] end

-------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local function SafeFont(p)
    if not p or p == "" then return FALLBACK_FONT end
    -- WoW only supports TTF/TGA, not OTF
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return FALLBACK_FONT end
    return p
end
-- Apply shadow based on global outline mode
local function ApplyFontShadow(fs)
    if not fs then return end
    if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end
local function OutlineFlag()
    if EllesmereUI.GetFontOutlineFlag then return EllesmereUI.GetFontOutlineFlag() end
    return ""
end
local function SetFontSafe(fs, path, size, flags)
    if not fs then return end
    local safePath = SafeFont(path)
    fs:SetFont(safePath, size or 11, flags or "NONE")
    -- Verify font was set; if not try forward-slash fallback, then Blizzard default
    if not fs:GetFont() then
        fs:SetFont("Fonts/FRIZQT__.TTF", size or 11, flags or "NONE")
    end
    if not fs:GetFont() then
        fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, flags or "NONE")
    end
    if not fs:GetFont() then
        -- Last resort: copy font from GameFontNormal which always exists
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fs:SetFont(gf, size or 11, flags or "NONE") end
    end
end
local function GlobalFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return SafeFont(EllesmereUI.GetFontPath("unitFrames"))
    end
    return FALLBACK_FONT
end
local function TitleFont() return GlobalFont(), Cfg("titleFontSize") or 11, OutlineFlag() end
local function ObjFont()   return GlobalFont(), Cfg("objFontSize")   or 10, OutlineFlag() end
local function SecFont()   return GlobalFont(), Cfg("secFontSize")   or 8,  OutlineFlag() end

-------------------------------------------------------------------------------
-- Context menu (EUI-styled popup)
-------------------------------------------------------------------------------
local ctxMenu  -- reusable context menu frame
local function ShowContextMenu(anchor, items)
    local PP = EllesmereUI and EllesmereUI.PP
    local E  = EllesmereUI
    if not E then return end

    -- Build or reuse the menu frame
    if not ctxMenu then
        ctxMenu = CreateFrame("Frame", nil, UIParent)
        ctxMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ctxMenu:SetFrameLevel(200)
        ctxMenu:SetClampedToScreen(true)
        ctxMenu:EnableMouse(true)

        -- Background
        local bg = ctxMenu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(E.DD_BG_R, E.DD_BG_G, E.DD_BG_B, E.DD_BG_HA)
        ctxMenu._bg = bg

        -- Pixel-perfect border
        if PP then
            PP.CreateBorder(ctxMenu, 1, 1, 1, E.DD_BRD_A, 1)
        end

        ctxMenu._items = {}

        -- Close when clicking anywhere outside the menu
        local clickOff = CreateFrame("Frame")
        clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")
        clickOff:SetScript("OnEvent", function()
            if ctxMenu:IsShown() and not ctxMenu:IsMouseOver() then
                ctxMenu:Hide()
            end
        end)
    end

    -- Clear old item frames
    for _, btn in ipairs(ctxMenu._items) do
        btn:Hide()
    end
    wipe(ctxMenu._items)

    local ITEM_H = 26
    local MENU_PAD = 4
    local maxTextW = 0

    -- Measure text widths first
    for _, item in ipairs(items) do
        local tmp = ctxMenu:CreateFontString(nil, "OVERLAY")
        SetFontSafe(tmp, GlobalFont(), 12, OutlineFlag())
        tmp:SetText(item.text)
        local w = tmp:GetStringWidth()
        if w > maxTextW then maxTextW = w end
        tmp:Hide()
    end

    local MENU_W = math.max(140, maxTextW + 40)

    -- Create item buttons
    for i, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, ctxMenu)
        btn:SetSize(MENU_W - MENU_PAD * 2, ITEM_H)
        btn:SetPoint("TOPLEFT", ctxMenu, "TOPLEFT", MENU_PAD, -(MENU_PAD + (i - 1) * ITEM_H))

        -- Highlight
        local hl = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)
        btn._hl = hl

        -- Label
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        SetFontSafe(lbl, GlobalFont(), 12, OutlineFlag())
        lbl:SetPoint("LEFT", btn, "LEFT", 10, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(1, 1, 1, 1)
        lbl:SetText(item.text)
        btn._lbl = lbl

        local acR, acG, acB = C.accent.r, C.accent.g, C.accent.b
        btn:SetScript("OnEnter", function()
            hl:SetColorTexture(1, 1, 1, E.DD_ITEM_HL_A)
            lbl:SetTextColor(acR, acG, acB, 1)
        end)
        btn:SetScript("OnLeave", function()
            hl:SetColorTexture(1, 1, 1, 0)
            lbl:SetTextColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnClick", function()
            ctxMenu:Hide()
            if item.onClick then item.onClick() end
        end)

        table.insert(ctxMenu._items, btn)
    end

    ctxMenu:SetSize(MENU_W, MENU_PAD * 2 + #items * ITEM_H)

    -- Position at cursor
    local scale = ctxMenu:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ctxMenu:ClearAllPoints()
    ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    ctxMenu:Show()
end

-------------------------------------------------------------------------------
-- Timer helpers
-------------------------------------------------------------------------------
local function FormatTimeLeft(seconds)
    if seconds <= 0 then return "0:00" end
    if seconds < 60 then
        return string.format("0:%02d", math.floor(seconds))
    elseif seconds < 3600 then
        return string.format("%d:%02d", math.floor(seconds/60), math.floor(seconds%60))
    else
        return string.format("%dh %dm", math.floor(seconds/3600), math.floor((seconds%3600)/60))
    end
end

-- Scan a widget set for a ScenarioHeaderTimer widget (type 20).
-- Returns duration, startTime or nil, nil.
local function GetWidgetSetTimer(setID)
    if not setID or setID == 0 then return nil, nil end
    if not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then return nil, nil end
    local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if not ok or not widgets then return nil, nil end
    for _, w in ipairs(widgets) do
        if w.widgetType == 20 and C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
            local ti = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(w.widgetID)
            if ti and ti.shownState == 1 then
                local tMin     = ti.timerMin   or 0
                local tMax     = ti.timerMax   or 0
                local tVal     = ti.timerValue or 0
                local duration  = tMax - tMin
                local remaining = tVal - tMin
                if remaining > 0 and duration > 0 then
                    local startTime = GetTime() - (duration - remaining)
                    return duration, startTime
                end
            end
        end
    end
    return nil, nil
end

-- Returns duration, startTime (both needed for live countdown), or nil, nil.
-- Priority: GetQuestTimeLeftData -> ScenarioHeaderTimer widget (type 20) from step widgetSetID
local function GetQuestTimer(questID)
    -- 1. Standard quest timer
    if GetQuestTimeLeftData then
        local startTime, duration = GetQuestTimeLeftData(questID)
        if startTime and startTime > 0 and duration and duration > 0 then
            local remaining = duration - (GetTime() - startTime)
            if remaining > 0 then return duration, startTime end
        end
    end
    -- 2. ScenarioHeaderTimer widget from step widgetSetID (covers Assault/Event quests)
    if C_Scenario and C_Scenario.GetStepInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, widgetSetID = pcall(C_Scenario.GetStepInfo)
        if ok and widgetSetID and widgetSetID ~= 0 then
            local dur, start = GetWidgetSetTimer(widgetSetID)
            if dur and start then return dur, start end
        end
    end
    -- 3. ObjectiveTracker widget set fallback
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        local otSet = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        if otSet and otSet ~= 0 then
            local dur, start = GetWidgetSetTimer(otSet)
            if dur and start then return dur, start end
        end
    end
    return nil, nil
end

-- GetProgressBar removed: progress bar logic now lives in BuildEntry

-------------------------------------------------------------------------------
-- Row pool
-------------------------------------------------------------------------------
local rowPool = {}
local function AcquireRow(parent)
    local r = table.remove(rowPool)
    if not r then
        r = {}
        r.frame = CreateFrame("Button", nil, parent)
        r.text  = r.frame:CreateFontString(nil, "OVERLAY")
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(true)
        r.text:SetNonSpaceWrap(false)
        r.frame:SetScript("OnEnter", function(self)
            if EQT._onHoverIn then EQT._onHoverIn() end
            if EQT._qtMouseoverIn then EQT._qtMouseoverIn() end
            if self._questID and r._baseR then
                local br, bg, bb = r._baseR, r._baseG, r._baseB
                r.text:SetTextColor(br + (1 - br) * 0.5, bg + (1 - bg) * 0.5, bb + (1 - bb) * 0.5)
            end
        end)
        r.frame:SetScript("OnLeave", function()
            if EQT._onHoverOut then EQT._onHoverOut() end
            if EQT._qtMouseoverOut then EQT._qtMouseoverOut() end
            if r._baseR then r.text:SetTextColor(r._baseR, r._baseG, r._baseB) end
        end)
    end
    r.frame:SetParent(parent); r.frame._questID = nil
    r.frame:EnableMouse(false); r.frame:Show(); r.text:Show()
    return r
end
local function ReleaseRow(r)
    r.frame:Hide(); r.frame:ClearAllPoints(); r.frame:SetScript("OnClick", nil)
    r._baseR, r._baseG, r._baseB = nil, nil, nil
    if r.numFS then r.numFS:Hide() end
    -- Clean up timer/progressbar sub-widgets
    if r.timerFS     then r.timerFS:Hide()     end
    if r.barBg       then r.barBg:Hide()       end
    if r.barFill     then r.barFill:Hide()     end
    if r.pctFS       then r.pctFS:Hide()       end
    -- Clean up banner sub-widgets
    if r.bannerBg    then r.bannerBg:Hide()    end
    if r.bannerAccent then r.bannerAccent:Hide() end
    if r.bannerIcon  then r.bannerIcon:Hide()  end
    if r.tierFS      then r.tierFS:Hide()      end
    table.insert(rowPool, r)
end
local function ReleaseAll()
    EQT.timerRows = {}
    for i = #EQT.rows, 1, -1 do ReleaseRow(EQT.rows[i]); EQT.rows[i] = nil end
end

-- Section pool
local secPool = {}
local function AcquireSection(parent)
    local s = table.remove(secPool)
    if not s then
        s = {}
        s.frame = CreateFrame("Button", nil, parent)
        s.label = s.frame:CreateFontString(nil, "OVERLAY")
        s.label:SetJustifyH("LEFT")
        s.arrow = s.frame:CreateFontString(nil, "OVERLAY")
        s.arrow:SetJustifyH("CENTER")
        s.line = s.frame:CreateTexture(nil, "ARTWORK")
        s.line:SetHeight(1)
        s.line:SetPoint("BOTTOMLEFT",  s.frame, "BOTTOMLEFT",  0, 0)
        s.line:SetPoint("BOTTOMRIGHT", s.frame, "BOTTOMRIGHT", 0, 0)
    end
    s.frame:SetParent(parent); s.frame:EnableMouse(true)
    s.frame:Show(); s.label:Show(); s.arrow:Show(); s.line:Show()
    return s
end
local function ReleaseSection(s)
    s.frame:Hide(); s.frame:ClearAllPoints(); s.frame:SetScript("OnClick", nil)
    if s.line then s.line:Hide() end
    table.insert(secPool, s)
end

-- Item button pool
local itemPool = {}
-- Item buttons are SecureActionButtonTemplate parented to UIParent.
-- Never reparented or pooled - reparenting secure frames causes taint.
-- Created fresh each Refresh, hidden when not needed.
local allItemBtns = {}  -- all ever-created item buttons

local function AcquireItemBtn()
    -- Find a hidden button or create new one
    for _, b in ipairs(allItemBtns) do
        if not b:IsShown() then
            b._itemID = nil; b._logIdx = nil
            return b
        end
    end
    -- Create new secure button at UIParent level
    local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); b._icon = icon
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(); b._cd = cd
    b:SetScript("OnEnter", function(self)
        if EQT._onHoverIn then EQT._onHoverIn() end
        if EQT._qtMouseoverIn then EQT._qtMouseoverIn() end
        if self._itemID then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self._itemID); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if EQT._onHoverOut then EQT._onHoverOut() end
        if EQT._qtMouseoverOut then EQT._qtMouseoverOut() end
        GameTooltip:Hide()
    end)
    table.insert(allItemBtns, b)
    return b
end
local function ReleaseItemBtn(b)
    b:Hide(); b:ClearAllPoints()
    b._icon:SetTexture(nil)
    b:SetAttribute("item", nil)
end
local function ReleaseAllItems()
    for i = #EQT.itemBtns, 1, -1 do ReleaseItemBtn(EQT.itemBtns[i]); EQT.itemBtns[i] = nil end
end

-------------------------------------------------------------------------------
-- Misc helpers
-------------------------------------------------------------------------------
local function RemoveWatch(qID)
    if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(qID) end
end

local function GetQuestItem(qID)
    if not GetQuestLogSpecialItemInfo then return nil end
    local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qID)
    if not idx or idx == 0 then return nil end
    local name, tex, charges, _, t0, dur, _, _, _, itemID = GetQuestLogSpecialItemInfo(idx)
    if not name then return nil end
    return {itemID=itemID, logIdx=idx, name=name, texture=tex, charges=charges, startTime=t0, duration=dur}
end

local INTERNAL_TITLES = { ["Tracking Quest"]=true, [""]=true }
local function IsInternalTitle(t)
    if not t then return true end
    if INTERNAL_TITLES[t] then return true end
    if t:match("^Level %d+$") then return true end
    return false
end

local function BuildEntry(info, qID, list)
    local objs = {}
    local ot = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qID)
    if ot then
        for _, o in ipairs(ot) do
            local nf, nr = o.numFulfilled, o.numRequired
            if o.type == "progressbar" then
                local pct = GetQuestProgressBarPercent(qID)
                if pct then
                    nf = pct
                    nr = 100
                end
            end
            table.insert(objs, {
                text         = o.text or "",
                finished     = o.finished,
                objType      = o.type,
                numFulfilled = nf,
                numRequired  = nr,
            })
        end
    end
    table.insert(list, {
        index      = #list + 1,
        title      = (info and info.title) or ("Quest #"..qID),
        questID    = qID,
        objectives = objs,
        isComplete      = C_QuestLog.IsComplete and C_QuestLog.IsComplete(qID) or false,
        isAutoComplete  = info and info.isAutoComplete or false,
        isFailed        = info and info.isFailed or false,
        isTask          = info and info.isTask or false,
    })
end

-------------------------------------------------------------------------------
-- GetScenarioSection
-- Returns a scenario entry when in a Delve/Scenario, with banner info and objectives.
local WIDGET_TYPE_DELVE_HEADER   = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves) or 29
local WIDGET_TYPE_SCENARIO_TIMER = 20
local WIDGET_TYPE_STATUSBAR      = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.StatusBar) or 2

local function GetDelveLivesFromHeaderInfo(hi)
    if not hi or not hi.currencies then
        return nil, nil, nil
    end

    for _, c in ipairs(hi.currencies) do
        local tooltip = tostring(c.tooltip or "")
        if tooltip:find("Total deaths") then
            local remaining = tonumber(c.text)
            if remaining then
                local deaths = tonumber(tooltip:match("[Tt]otal deaths:%s*(%d+)")) or 0
                local maxLives = remaining + deaths
                return remaining, maxLives, deaths
            end
        end
    end

    return nil, nil, nil
end

local function AddDelveLivesObjective(objectives, seenText, remaining, maxLives, deaths)
    if not remaining then return end

    local text
    if maxLives and maxLives > 0 then
        text = string.format("Lives Remaining: %d/%d", remaining, maxLives)
    else
        text = string.format("Lives Remaining: %d", remaining)
    end

    if deaths and deaths > 0 then
        text = text .. string.format(" (Deaths: %d)", deaths)
    end

    if seenText[text] then return end
    seenText[text] = true

    table.insert(objectives, 1, {
        text     = text,
        finished = false,
    })
end

local function GetScenarioSection()
    if not C_Scenario or not C_Scenario.IsInScenario then return nil end
    if not C_Scenario.IsInScenario() then return nil end

    -- Step info: stageName, numCriteria, widgetSetID (index 12)
    local ok, stageName, _, numCriteria, _, _, _, _, _, _, _, widgetSetID = pcall(C_Scenario.GetStepInfo)
    if not ok then return nil end

    -- Prefer C_ScenarioInfo widgetSetID (more reliable)
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local si = C_ScenarioInfo.GetScenarioStepInfo()
        if si and si.widgetSetID and si.widgetSetID > 0 then
            widgetSetID = si.widgetSetID
        end
    end

    -- Scenario name
    local scenarioName
    local iOk, name = pcall(C_Scenario.GetInfo)
    if iOk and name and name ~= "" then scenarioName = name end

    -- Scan widget sets for Delve header (type 29) to get banner info
    local bannerTitle, bannerIcon, bannerTier = nil, nil, nil
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    local delveLivesCur, delveLivesMax, delveDeathsUsed = nil, nil, nil

    local setsToScan = {}
    if widgetSetID and widgetSetID ~= 0 then setsToScan[#setsToScan+1] = widgetSetID end
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        local otSet = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        if otSet and otSet ~= 0 and otSet ~= widgetSetID then setsToScan[#setsToScan+1] = otSet end
    end

    for _, setID in ipairs(setsToScan) do
        if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
            local wOk, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if wOk and widgets then
                for _, w in ipairs(widgets) do
                    local wType = w.widgetType
                    local wID   = w.widgetID
                        -- Delve header widget
                        if wType == WIDGET_TYPE_DELVE_HEADER and
                        C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
                        local dOk, wi = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, wID)
                        if dOk and wi then
                            bannerTitle = (wi.headerText and wi.headerText ~= "") and wi.headerText or bannerTitle
                            bannerTier  = (wi.tierText   and wi.tierText   ~= "") and wi.tierText  or bannerTier
                            bannerIcon  = wi.atlasIcon or wi.icon or bannerIcon

                            local livesCur, livesMax, deathsUsed = GetDelveLivesFromHeaderInfo(wi)
                            if livesCur ~= nil then
                                delveLivesCur = livesCur
                                delveLivesMax = livesMax
                                delveDeathsUsed = deathsUsed
                            end
                            isDelve = true
                        end
                    end
                end
            end
        end
        if bannerTitle then break end
    end

    -- Build display title
    local title
    if isDelve then
        title = bannerTitle or scenarioName or "Delve"
    elseif scenarioName and stageName and stageName ~= "" then
        title = scenarioName .. " - " .. stageName
    elseif stageName and stageName ~= "" then
        title = stageName
    else
        title = scenarioName or "Scenario"
    end

    -- Objectives from criteria
    local objectives = {}
    local seenText = {}
    local timerDuration, timerStartTime = nil, nil

    if C_ScenarioInfo then
        for i = 1, (numCriteria or 0) + 3 do
            local cOk, crit
            if C_ScenarioInfo.GetCriteriaInfoByStep then
                cOk, crit = pcall(C_ScenarioInfo.GetCriteriaInfoByStep, 1, i)
            end
            if (not cOk or not crit) and C_ScenarioInfo.GetCriteriaInfo then
                cOk, crit = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
            end
            if cOk and crit then
                -- Extract timer from criteria (duration/elapsed fields)
                if not timerDuration and crit.duration and crit.duration > 0 then
                    local elapsed = math.max(0, math.min(crit.elapsed or 0, crit.duration))
                    if elapsed < crit.duration then
                        timerDuration  = crit.duration
                        timerStartTime = GetTime() - elapsed
                    end
                end

                local desc = (crit.description and crit.description ~= "") and crit.description
                          or (crit.criteriaString and crit.criteriaString ~= "") and crit.criteriaString
                          or nil
                if desc then
                local numFulfilled = crit.quantity      or 0
                local numRequired  = crit.totalQuantity or 0

                local displayText
                if crit.isWeightedProgress then
                    -- quantity is 0-100 percentage
                    local pct = math.min(100, math.max(0, math.floor(numFulfilled)))
                    displayText = desc
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        table.insert(objectives, {
                            text         = displayText,
                            finished     = crit.completed or false,
                            numFulfilled = pct,
                            numRequired  = 100,
                            objType      = "progressbar",
                        })
                    end
                    elseif numRequired > 0 then
                    -- Only use quantityString prefix when it adds meaningful info (not just "0" or "1")
                    local qs = crit.quantityString
                    local useQS = qs and qs ~= "" and qs ~= "0" and qs ~= "1"
                    if useQS then
                        displayText = qs .. " " .. desc
                    else
                        displayText = string.format("%d/%d %s", numFulfilled, numRequired, desc)
                    end
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        local isBar = numRequired > 1
                        table.insert(objectives, {
                            text         = displayText,
                            finished     = crit.completed or false,
                            numFulfilled = isBar and numFulfilled or nil,
                            numRequired  = isBar and numRequired  or nil,
                        
                        })
                    end
                else
                    displayText = desc
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        table.insert(objectives, {
                            text     = displayText,
                            finished = crit.completed or false,
                        })
                    end
                end
                end -- if desc
            end
        end
    end

    -- Criteria timer fallback: widget timer
    if not timerDuration then
        local dur, start = GetQuestTimer(0) -- 0 = use scenario widget timer path
        -- Actually call widget timer directly
        for _, setID in ipairs(setsToScan) do
            if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
                local wOk, wids = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
                if wOk and wids then
                    for _, w in ipairs(wids) do
                        if w.widgetType == WIDGET_TYPE_SCENARIO_TIMER and
                           C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
                            local ti = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(w.widgetID)
                            if ti and ti.shownState == 1 then
                                local tMin = ti.timerMin or 0
                                local duration = (ti.timerMax or 0) - tMin
                                local remaining = (ti.timerValue or 0) - tMin
                                if remaining > 0 and duration > 0 then
                                    timerDuration  = duration
                                    timerStartTime = GetTime() - (duration - remaining)
                                end
                            end
                        end
                    end
                end
            end
            if timerDuration then break end
        end
    end

    -- StatusBar widgets as progress objectives
    for _, setID in ipairs(setsToScan) do
        if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
            local wOk, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if wOk and widgets then
                for _, w in ipairs(widgets) do
                    if w.widgetType == WIDGET_TYPE_STATUSBAR and
                       C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
                        local si = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
                        if si and si.barMax and si.barMax > 0 then
                            local text = (si.overrideBarText ~= "" and si.overrideBarText) or si.text or ""
                            if not seenText[text] then
                                seenText[text] = true
                                table.insert(objectives, {
                                    text         = text,
                                    finished     = false,
                                    numFulfilled = si.barValue,
                                    numRequired  = si.barMax,
                                    objType      = "progressbar",
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if isDelve and delveLivesCur ~= nil then
    AddDelveLivesObjective(objectives, seenText, delveLivesCur, delveLivesMax, delveDeathsUsed)
end
    
    if #objectives == 0 and title == "Scenario" then return nil end

    return {
        title          = title,
        objectives     = objectives,
        isDelve        = isDelve,
        bannerIcon     = bannerIcon,
        bannerTier     = bannerTier,
        timerDuration  = timerDuration,
        timerStartTime = timerStartTime,
    }
end

-------------------------------------------------------------------------------
-- Prey quest detection
-- Prey quests: Recurring or Meta classification with "Prey" in title,
-- or weekly/recurring frequency with "Prey" in title.
local function IsPreyQuest(qID)
    if not qID then return false end
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qID)
    if not title or not title:find("Prey", 1, true) then return false end

    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification and Enum and Enum.QuestClassification then
        local ok, qc = pcall(C_QuestInfoSystem.GetQuestClassification, qID)
        if ok and qc then
            if qc == Enum.QuestClassification.Recurring then return true end
            if qc == Enum.QuestClassification.Meta then return true end
        end
    end

    local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qID)
    if idx then
        local ok, info = pcall(C_QuestLog.GetInfo, idx)
        if ok and info and info.frequency ~= nil then
            local f = info.frequency
            local isWeekly = f == 2 or f == 3
                or (Enum and Enum.QuestFrequency and f == Enum.QuestFrequency.Weekly)
                or (LE_QUEST_FREQUENCY_WEEKLY and f == LE_QUEST_FREQUENCY_WEEKLY)
            if isWeekly then return true end
        end
    end

    return false
end

-------------------------------------------------------------------------------
-- TryCompleteQuest
-- Attempts to open the quest completion dialog for auto-complete quests.
local function TryCompleteQuest(qID)
    if not qID or not C_QuestLog then return false end
    if not C_QuestLog.IsComplete(qID) then return false end
    if C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(qID)
    end
    if ShowQuestComplete and type(ShowQuestComplete) == "function" then
        local ok = pcall(ShowQuestComplete, qID)
        if ok then return true end
    end
    return false
end

-- GetQuestLists
-------------------------------------------------------------------------------
-- Cache which section each quest was last assigned to so quests don't
-- jump between sections on non-structural refreshes (progress updates, etc.)
-- Cleared on zone change or structural quest events.
local questSectionCache = {}  -- qID -> "watched" | "zone" | "world" | "prey"

function EQT:ClearSectionCache()
    wipe(questSectionCache)
end

local function GetQuestLists()
    local watched = {}
    local zone    = {}
    local world   = {}
    local prey    = {}
    local seen    = {}

    if not C_QuestLog then return watched, zone, world, prey end
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0

    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isInternalOnly then
            local qID = info.questID
            if qID and not seen[qID] then
                -- isTask quests may have isHidden=true in TWW – allow them through
                local skipHidden = info.isHidden and not info.isTask
                if not skipHidden then
                    local tracked = false
                    if C_QuestLog.GetQuestWatchType then
                        local wt = C_QuestLog.GetQuestWatchType(qID)
                        -- wt ~= nil means the quest is watched (0 = auto, 1 = manual)
                        tracked = (wt ~= nil)
                    end
                    if not tracked and C_QuestLog.IsQuestWatched then
                        tracked = C_QuestLog.IsQuestWatched(qID) == true
                    end

                    -- Determine which section this quest belongs to
                    local section
                    if Cfg("showPreyQuests") and IsPreyQuest(qID) then
                        section = "prey"
                    elseif tracked then
                        if Cfg("showZoneQuests") and info.isOnMap and not info.isTask then
                            section = "zone"
                        else
                            section = "watched"
                        end
                    elseif info.isTask then
                        if Cfg("showWorldQuests") and not IsInternalTitle(info.title) then
                            section = "world"
                        end
                    elseif info.isOnMap then
                        if Cfg("showZoneQuests") then
                            section = "zone"
                        end
                    end

                    if section then
                        -- Use cached section if available to prevent jumping
                        local cached = questSectionCache[qID]
                        if cached then
                            if cached == "prey" and IsPreyQuest(qID) then section = "prey"
                            elseif cached == "watched" and tracked then section = "watched"
                            elseif cached == "zone" and (tracked or info.isOnMap) then section = "zone"
                            elseif cached == "world" and info.isTask then section = "world"
                            end
                        end
                        questSectionCache[qID] = section
                        seen[qID] = true
                        if section == "prey" then
                            BuildEntry(info, qID, prey)
                        elseif section == "zone" then
                            BuildEntry(info, qID, zone)
                        elseif section == "world" then
                            BuildEntry(info, qID, world)
                        else
                            BuildEntry(info, qID, watched)
                        end
                    end
                end
            end
        end
    end

    return watched, zone, world, prey
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
local PAD_H    = 8
local PAD_V    = 6
local TXT_PAD  = 5
local ROW_GAP  = 1
local SEC_GAP  = 5
local ITEM_PAD = 3
local BAR_H    = 9   -- progress bar height (doubled)
local BAR_PAD  = 2   -- gap between text and bar

-- Forward declaration; defined after BuildFrame
local UpdateInnerAlignment

function EQT:Refresh()
    local f = self.frame
    if not f then return end
    local content = f.content
    local width   = Cfg("width") or 220
    local tc      = Cfg("titleColor")
    local oc      = Cfg("objColor")
    local iqSize  = Cfg("questItemSize") or 22

    -- Hide content during teardown+rebuild to prevent single-frame flicker
    if f.inner then f.inner:SetAlpha(0) end

    ReleaseAll(); ReleaseAllItems()
    for i = #self.sections, 1, -1 do ReleaseSection(self.sections[i]); self.sections[i] = nil end

    if f.bg then f.bg:SetColorTexture(Cfg("bgR") or 0, Cfg("bgG") or 0, Cfg("bgB") or 0, Cfg("bgAlpha") or 0.35) end
    f:SetWidth(width)
    local contentW = math.max(10, width - PAD_H * 2 - 10)
    content:SetWidth(contentW)
    -- Row width for explicit SetWidth before measuring text height (anchors may not resolve in time)
    local rowW = contentW - TXT_PAD

    local yOff = 0
    local sfp, sfs, sff = SecFont()
    local arrowSize = math.max(sfs + 4, 13)
    local arrowFont = SafeFont(GlobalFont())

    local function AddCollapsibleSection(label, isCollapsed, onToggle)
        local s = AcquireSection(content)
        SetFontSafe(s.label, sfp, sfs, sff)
        local sc = Cfg("secColor") or C.section
        s.label:SetTextColor(sc.r, sc.g, sc.b)
        ApplyFontShadow(s.label)
        s.label:SetText(label)
        s.label:ClearAllPoints()
        s.label:SetPoint("LEFT",  s.frame, "LEFT",  0, 3)
        s.label:SetPoint("RIGHT", s.frame, "RIGHT", -(arrowSize + 4), 3)
        SetFontSafe(s.arrow, arrowFont, arrowSize, OutlineFlag())
        s.arrow:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        s.arrow:SetText(isCollapsed and "+" or "-")
        s.arrow:ClearAllPoints()
        s.arrow:SetPoint("RIGHT", s.frame, "RIGHT", 0, 3)
        s.arrow:SetWidth(arrowSize + 4)
        s.line:SetColorTexture(sc.r, sc.g, sc.b, 0.4)
        local br, bg, bb = sc.r, sc.g, sc.b
        s.frame:SetScript("OnEnter", function()
            if EQT._onHoverIn then EQT._onHoverIn() end
            if EQT._qtMouseoverIn then EQT._qtMouseoverIn() end
            s.label:SetTextColor(br + (1 - br) * 0.5, bg + (1 - bg) * 0.5, bb + (1 - bb) * 0.5)
        end)
        s.frame:SetScript("OnLeave", function()
            if EQT._onHoverOut then EQT._onHoverOut() end
            if EQT._qtMouseoverOut then EQT._qtMouseoverOut() end
            s.label:SetTextColor(br, bg, bb)
        end)
        local textH = math.max(sfs + 6, arrowSize + 2)
        local h = textH + 5 + 1
        s.frame:SetHeight(h)
        s.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        s.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        s.frame:SetScript("OnClick", onToggle)
        yOff = yOff + h + SEC_GAP
        table.insert(self.sections, s)
    end

    local function AddPlainSection(label)
        local s = AcquireSection(content)
        SetFontSafe(s.label, sfp, sfs, sff)
        local sc2 = Cfg("secColor") or C.section
        s.label:SetTextColor(sc2.r, sc2.g, sc2.b)
        s.label:SetText(label)
        s.label:ClearAllPoints()
        s.label:SetPoint("LEFT",  s.frame, "LEFT",  0, 3)
        s.label:SetPoint("RIGHT", s.frame, "RIGHT", 0, 3)
        SetFontSafe(s.arrow, sfp, sfs, sff); s.arrow:SetText("")
        s.line:SetColorTexture(sc2.r, sc2.g, sc2.b, 0.4)
        local br, bg, bb = sc2.r, sc2.g, sc2.b
        s.frame:SetScript("OnEnter", function()
            if EQT._onHoverIn then EQT._onHoverIn() end
            if EQT._qtMouseoverIn then EQT._qtMouseoverIn() end
            s.label:SetTextColor(br + (1 - br) * 0.5, bg + (1 - bg) * 0.5, bb + (1 - bb) * 0.5)
        end)
        s.frame:SetScript("OnLeave", function()
            if EQT._onHoverOut then EQT._onHoverOut() end
            if EQT._qtMouseoverOut then EQT._qtMouseoverOut() end
            s.label:SetTextColor(br, bg, bb)
        end)
        local textH = math.max(sfs + 6, 12)
        local h = textH + 5 + 1
        s.frame:SetHeight(h)
        s.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        s.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        yOff = yOff + h + SEC_GAP
        table.insert(self.sections, s)
    end

    local tfp, tfs, tff = TitleFont()
    local ofp, ofs, off = ObjFont()

    -- Timer row: countdown text + shrinking bar
    local function AddTimerRow(questID, isAutoComplete, presetDuration, presetStartTime)
        local duration = presetDuration
        local startTime = presetStartTime
        if not duration or not startTime then
            duration, startTime = GetQuestTimer(questID)
        end
        if not duration or not startTime then return end

        local TIMER_BAR_H = BAR_H + 2
        local TEXT_H      = math.max(ofs, 10)
        local TOTAL_H     = TEXT_H + 4 + TIMER_BAR_H + 4

        local r = AcquireRow(content)
        r.frame:SetHeight(TOTAL_H)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)

        -- Countdown text
        SetFontSafe(r.text, ofp, TEXT_H, OutlineFlag())
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  20, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -4, 0)
        r.text:SetHeight(TEXT_H + 2)
        r.text:Show()

        -- Timer bar background
        if r.barBg then r.barBg:Hide(); r.barBg = nil end
        r.barBg = r.frame:CreateTexture(nil, "BACKGROUND")
        r.barBg:SetColorTexture(C.barBg.r, C.barBg.g, C.barBg.b, 0.8)
        r.barBg:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, -(TEXT_H + 4))
        r.barBg:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -4, -(TEXT_H + 4))
        r.barBg:SetHeight(TIMER_BAR_H)
        r.barBg:Show()

        -- Timer bar fill
        if r.barFill then r.barFill:Hide(); r.barFill = nil end
        r.barFill = r.frame:CreateTexture(nil, "ARTWORK")
        r.barFill:SetColorTexture(C.timer.r, C.timer.g, C.timer.b, 0.85)
        r.barFill:SetPoint("TOPLEFT",    r.barBg, "TOPLEFT",    0, 0)
        r.barFill:SetPoint("BOTTOMLEFT", r.barBg, "BOTTOMLEFT", 0, 0)
        r.barFill:Show()

        local function UpdateTimer()
            if not r.text or not r.frame:IsShown() then return end
            local remaining = duration - (GetTime() - startTime)
            if remaining < 0 then remaining = 0 end
            -- Text
            r.text:SetText(FormatTimeLeft(remaining))
            if remaining < 30 then
                r.text:SetTextColor(C.timerLow.r, C.timerLow.g, C.timerLow.b)
                r.barFill:SetColorTexture(C.timerLow.r, C.timerLow.g, C.timerLow.b, 0.9)
            elseif remaining < 120 then
                r.text:SetTextColor(1, 0.9, 0.3)
                r.barFill:SetColorTexture(1, 0.9, 0.3, 0.85)
            else
                r.text:SetTextColor(C.timer.r, C.timer.g, C.timer.b)
                r.barFill:SetColorTexture(C.timer.r, C.timer.g, C.timer.b, 0.85)
            end
            -- Shrink bar proportionally
            local barW = r.barBg:GetWidth()
            if barW and barW > 0 then
                local pct = math.max(0, math.min(1, remaining / duration))
                r.barFill:SetWidth(math.max(1, barW * pct))
            end
        end
        UpdateTimer()

        yOff = yOff + TOTAL_H + ROW_GAP + 2
        table.insert(self.rows, r)
        r._updateTimer = UpdateTimer
        table.insert(self.timerRows, r)
    end

    -- Progress bar row
    local function AddProgressRow(cur, max)
        local r = AcquireRow(content)
        r.text:Hide()

        local pct = math.max(0, math.min(1, cur / max))
        local barW = (content:GetWidth() or width - PAD_H*2) - 14 - 30

        -- Background
        if not r.barBg then
            r.barBg = r.frame:CreateTexture(nil, "BACKGROUND")
        end
        r.barBg:SetColorTexture(C.barBg.r, C.barBg.g, C.barBg.b, 0.8)
        r.barBg:ClearAllPoints()
        r.barBg:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, -2)
        r.barBg:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -30, -2)
        r.barBg:SetHeight(BAR_H)
        r.barBg:Show()

        -- Fill
        if not r.barFill then
            r.barFill = r.frame:CreateTexture(nil, "ARTWORK")
        end
        r.barFill:SetColorTexture(C.barFill.r, C.barFill.g, C.barFill.b, 0.9)
        r.barFill:ClearAllPoints()
        r.barFill:SetPoint("TOPLEFT", r.barBg, "TOPLEFT", 0, 0)
        r.barFill:SetHeight(BAR_H)
        r.barFill:SetWidth(math.max(1, barW * pct))
        r.barFill:Show()

        -- Percentage text (always recreate - reparenting loses font state)
        if r.pctFS then r.pctFS:Hide(); r.pctFS = nil end
        r.pctFS = r.frame:CreateFontString(nil, "OVERLAY")
        SetFontSafe(r.pctFS, GlobalFont(), BAR_H + 2, OutlineFlag())
        r.pctFS:SetJustifyH("RIGHT")
        r.pctFS:SetJustifyV("MIDDLE")
        r.pctFS:SetTextColor(1, 1, 1)
        r.pctFS:SetText(math.floor(pct * 100 + 0.5).."%")
        r.pctFS:ClearAllPoints()
        r.pctFS:SetPoint("RIGHT",  r.frame,  "RIGHT",  0, 0)
        r.pctFS:SetPoint("TOP",    r.barBg,  "TOP",    0, 0)
        r.pctFS:SetPoint("BOTTOM", r.barBg,  "BOTTOM", 0, 0)
        r.pctFS:SetWidth(30)
        r.pctFS:Show()

        local rh = BAR_H + BAR_PAD * 2 + 2
        r.frame:SetHeight(rh)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function AddTitleRow(text, cr, cg, cb, qID, isAutoComplete, isComplete)
        local r = AcquireRow(content)
        SetFontSafe(r.text, tfp, tfs, tff)
        r.text:SetTextColor(cr, cg, cb)
        r._baseR, r._baseG, r._baseB = cr, cg, cb
        ApplyFontShadow(r.text)
        r.text:SetText(text)
        r.text:Show()
        local item = Cfg("showQuestItems") and qID and GetQuestItem(qID)
        local rightPad = item and (iqSize + ITEM_PAD * 2) or 0
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  2, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -rightPad, 0)
        r.frame:SetWidth(rowW)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        -- Force text width so GetStringHeight respects word wrap on first layout
        r.text:SetWidth(rowW - 2 - rightPad)
        local th = r.text:GetStringHeight()
        if th < tfs then th = tfs end
        local rh = math.max(th + 4, item and iqSize or 0)
        r.frame:SetHeight(rh); r.text:SetHeight(rh)
        if item then
            local btn = AcquireItemBtn()
            btn:SetSize(iqSize, iqSize)
            -- Anchor to r.frame but parented to UIParent - use SetPoint with explicit frame ref
            btn:SetPoint("RIGHT", r.frame, "RIGHT", -ITEM_PAD, 0)
            btn:SetFrameLevel(r.frame:GetFrameLevel() + 2)
            btn._icon:SetTexture(item.texture); btn._itemID = item.itemID; btn._logIdx = item.logIdx
            -- Set item attribute directly (we are outside combat at Refresh time)
            if not InCombatLockdown() then btn:SetAttribute("item", item.name) end
            if item.startTime and item.startTime > 0 and item.duration and item.duration > 0 then
                btn._cd:SetCooldown(item.startTime, item.duration); btn._cd:Show()
            else btn._cd:Hide() end
            if item.charges and item.charges > 0 then
                if not btn._chargeFS then
                    btn._chargeFS = btn:CreateFontString(nil, "OVERLAY")
                    SetFontSafe(btn._chargeFS, GlobalFont(), 9, OutlineFlag())
                    btn._chargeFS:SetTextColor(1,1,1)
                    btn._chargeFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 2)
                end
                btn._chargeFS:SetText(item.charges); btn._chargeFS:Show()
            elseif btn._chargeFS then btn._chargeFS:Hide() end
            table.insert(self.itemBtns, btn)
        end
        if qID then
            r.frame._questID = qID; r.frame:EnableMouse(true)
            r.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r.frame:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" then
                    ShowContextMenu(self, {
                        { text = "Untrack Quest", onClick = function()
                            RemoveWatch(qID); EQT.dirty = true
                        end },
                        { text = "Abandon Quest", onClick = function()
                            C_QuestLog.SetSelectedQuest(qID)
                            C_QuestLog.SetAbandonQuest()
                            StaticPopup_Show("ABANDON_QUEST", C_QuestLog.GetTitleForQuestID(qID))
                        end },
                    })
                else
                    -- Suppress refresh so QUEST_LOG_UPDATE from SetSelectedQuest
                    -- doesn't rebuild the list and cause quests to jump
                    EQT._suppressDirty = true
                    if EQT._suppressTimer then EQT._suppressTimer:Cancel() end
                    EQT._suppressTimer = C_Timer.NewTimer(0.5, function()
                        EQT._suppressDirty = false; EQT._suppressTimer = nil
                    end)
                    -- Auto-complete quests: open the completion dialog directly
                    if isAutoComplete and isComplete then
                        if AutoQuestPopupTracker_RemovePopUp then
                            AutoQuestPopupTracker_RemovePopUp(qID)
                        end
                        if TryCompleteQuest(qID) then return end
                    end
                    -- Set waypoint to clicked quest
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(qID)
                    end
                    -- Toggle map: close if already open to this quest, open otherwise
                    if WorldMapFrame and WorldMapFrame:IsShown() then
                        HideUIPanel(WorldMapFrame)
                    else
                        if C_QuestLog.SetSelectedQuest then
                            C_QuestLog.SetSelectedQuest(qID)
                        end
                        if QuestMapFrame_OpenToQuestDetails then
                            QuestMapFrame_OpenToQuestDetails(qID)
                        elseif OpenQuestLog then
                            OpenQuestLog(qID)
                        elseif WorldMapFrame then
                            ShowUIPanel(WorldMapFrame)
                        end
                    end
                end
            end)
        end
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function AddObjRow(text, cr, cg, cb)
        local r = AcquireRow(content)
        SetFontSafe(r.text, ofp, ofs, off)
        r.text:SetTextColor(cr, cg, cb)
        ApplyFontShadow(r.text)
        r.text:SetText(text)
        r.text:Show()
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  20, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT",  0, 0)
        r.frame:SetWidth(rowW)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        -- Force text width so GetStringHeight respects word wrap on first layout
        r.text:SetWidth(rowW - 20)
        local th = r.text:GetStringHeight()
        if th < ofs then th = ofs end
        local rh = th + 4; r.frame:SetHeight(rh); r.text:SetHeight(rh)
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function RenderList(list, startIdx)
        for i, q in ipairs(list) do
            local tr, tg, tb
            if q.isFailed then tr, tg, tb = C.failed.r, C.failed.g, C.failed.b
            elseif q.isComplete then tr, tg, tb = C.complete.r, C.complete.g, C.complete.b
            else tr, tg, tb = tc.r, tc.g, tc.b end
            AddTitleRow(((startIdx or 0)+i).."  "..q.title, tr, tg, tb, q.questID, q.isAutoComplete, q.isComplete)

            -- Timer (for world/task quests)
            if q.isTask then
                AddTimerRow(q.questID)
            end

            -- Objectives
            for _, obj in ipairs(q.objectives) do
                if obj.objType == "progressbar" and obj.numRequired and obj.numRequired > 0 then
                    -- Show progress bar instead of text
                    AddProgressRow(obj.numFulfilled or 0, obj.numRequired)
                else
                    local cr = obj.finished and C.complete.r or oc.r
                    local cg = obj.finished and C.complete.g or oc.g
                    local cb = obj.finished and C.complete.b or oc.b
                    if obj.text and obj.text ~= "" then
                        AddObjRow(obj.text, cr, cg, cb)
                    end
                end
            end
            yOff = yOff + 3
        end
    end

    local watched, zone, world, prey = GetQuestLists()
    local scenario = GetScenarioSection()

    -- Scenario / Delve section
    if scenario then
        if #watched > 0 or #zone > 0 or #world > 0 then yOff = yOff + 4 end

        -- Collapsible "DELVES" section header (only for delves, plain for other scenarios)
        local dc = false
        if scenario.isDelve then
            dc = Cfg("delveCollapsed") or false
            AddCollapsibleSection("DELVES", dc, function()
                DB().delveCollapsed = not Cfg("delveCollapsed"); EQT:Refresh()
            end)
        end

        if not dc then
        -- Delve banner: icon + title + tier badge
        if scenario.isDelve then
            local BANNER_H = 42
            local ICON_SIZE = 36
            local r = AcquireRow(content)
            r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  TXT_PAD, -yOff)
            r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
            r.frame:SetHeight(BANNER_H)

            -- Dark background with subtle border
            if not r.bannerBg then
                r.bannerBg = r.frame:CreateTexture(nil, "BACKGROUND")
            end
            r.bannerBg:SetAllPoints()
            r.bannerBg:SetColorTexture(0.05, 0.04, 0.08, 0.8)
            r.bannerBg:Show()

            -- Accent border on left
            if not r.bannerAccent then
                r.bannerAccent = r.frame:CreateTexture(nil, "BORDER")
            end
            r.bannerAccent:SetWidth(2)
            r.bannerAccent:SetPoint("TOPLEFT",    r.frame, "TOPLEFT",  0, 0)
            r.bannerAccent:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, 0)
            r.bannerAccent:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.9)
            r.bannerAccent:Show()

            -- Icon (large, right-aligned, slightly faded)
            if scenario.bannerIcon then
                if not r.bannerIcon then
                    r.bannerIcon = r.frame:CreateTexture(nil, "ARTWORK")
                    r.bannerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                end
                r.bannerIcon:SetSize(ICON_SIZE, ICON_SIZE)
                r.bannerIcon:SetTexture(scenario.bannerIcon)
                r.bannerIcon:SetPoint("RIGHT", r.frame, "RIGHT", -6, 0)
                r.bannerIcon:SetAlpha(0.55)
                r.bannerIcon:Show()
            end

            -- Tier badge circle (top-right)
            if scenario.bannerTier then
                if not r.tierFS then
                    r.tierFS = r.frame:CreateFontString(nil, "OVERLAY")
                    r.tierFS:SetJustifyH("CENTER")
                end
                SetFontSafe(r.tierFS, GlobalFont(), tfs + 4, OutlineFlag())
                r.tierFS:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
                r.tierFS:SetText(scenario.bannerTier)
                r.tierFS:ClearAllPoints()
                r.tierFS:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -8, -6)
                r.tierFS:Show()
            end

            -- Title text (vertically centered in banner)
            local bc = Cfg("titleColor") or {r=1.0,g=0.82,b=0.0}
            local leftPad = 10
            SetFontSafe(r.text, tfp, tfs + 2, tff)
            r.text:SetTextColor(bc.r, bc.g, bc.b)
            r.text:SetText(scenario.title)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT",  r.frame, "LEFT",  leftPad, 0)
            r.text:SetPoint("RIGHT", r.frame, "RIGHT", -(ICON_SIZE + 10), 0)
            r.text:SetJustifyV("MIDDLE")
            r.text:SetHeight(BANNER_H)
            r.text:Show()
            ApplyFontShadow(r.text)

            yOff = yOff + BANNER_H + 6  -- extra gap below banner
            table.insert(self.rows, r)
        else
            AddPlainSection(scenario.title)
        end

        -- Timer row (if scenario has a countdown)
        if scenario.timerDuration and scenario.timerStartTime then
            AddTimerRow(nil, false, scenario.timerDuration, scenario.timerStartTime)
        end

        -- Objectives
        for _, obj in ipairs(scenario.objectives) do
            local cr = obj.finished and C.complete.r or oc.r
            local cg = obj.finished and C.complete.g or oc.g
            local cb = obj.finished and C.complete.b or oc.b
            if obj.objType == "progressbar" and obj.numRequired and obj.numRequired > 0 then
                AddProgressRow(obj.numFulfilled or 0, obj.numRequired)
                if obj.text and obj.text ~= "" then
                    AddObjRow(obj.text, cr, cg, cb)
                end
            else
                if obj.text and obj.text ~= "" then
                    AddObjRow(obj.text, cr, cg, cb)
                end
            end
        end
        end -- if not dc
    end

    -- Order: Delves (above), Zone Quests, World Quests, Quests (bottom)
    local anyAbove = scenario ~= nil

    if Cfg("showPreyQuests") and #prey > 0 then
        if anyAbove then yOff = yOff + 4 end; anyAbove = true
        local pc = Cfg("preyCollapsed") or false
        AddCollapsibleSection("PREYS", pc, function()
            DB().preyCollapsed = not Cfg("preyCollapsed"); EQT:Refresh()
        end)
        if not pc then RenderList(prey, 0) end
    end
    if Cfg("showZoneQuests") and #zone > 0 then
        if anyAbove then yOff = yOff + 4 end; anyAbove = true
        local zc = Cfg("zoneCollapsed") or false
        AddCollapsibleSection("ZONE QUESTS", zc, function()
            DB().zoneCollapsed = not Cfg("zoneCollapsed"); EQT:Refresh()
        end)
        if not zc then RenderList(zone, 0) end
    end
    if Cfg("showWorldQuests") and #world > 0 then
        if anyAbove then yOff = yOff + 4 end; anyAbove = true
        local wc = Cfg("worldCollapsed") or false
        AddCollapsibleSection("WORLD QUESTS", wc, function()
            DB().worldCollapsed = not Cfg("worldCollapsed"); EQT:Refresh()
        end)
        if not wc then RenderList(world, 0) end
    end
    if #watched > 0 then
        if anyAbove then yOff = yOff + 4 end
        local qc = Cfg("questsCollapsed") or false
        AddCollapsibleSection("QUESTS", qc, function()
            DB().questsCollapsed = not Cfg("questsCollapsed"); EQT:Refresh()
        end)
        if not qc then RenderList(watched, 0) end
    end
    if not scenario and #watched == 0 and #zone == 0 and #world == 0 and #prey == 0 then
        AddObjRow("No tracked quests.", oc.r, oc.g, oc.b)
    end

    content:SetHeight(math.max(yOff, 1))
    local totalH = PAD_V + 2 + yOff + PAD_V + 5
    local maxH = Cfg("height") or 600
    -- Outer frame stays at max height (consistent with unlock mode)
    f:SetHeight(maxH)
    -- Inner frame auto-collapses to content
    if f.inner then
        f.inner:SetHeight(math.min(totalH, maxH))
        UpdateInnerAlignment(f)
    end
    -- Clamp scroll position to valid range (don't reset to 0)
    if f.sf then
        local maxScroll = EllesmereUI.SafeScrollRange(f.sf)
        local cur = f.sf:GetVerticalScroll()
        if cur > maxScroll then
            f.sf:SetVerticalScroll(maxScroll)
        end
        if f._updateScrollThumb then f._updateScrollThumb() end
    end

    -- Restore visibility after rebuild is complete (prevents teardown flicker)
    if f.inner then f.inner:SetAlpha(1) end
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
UpdateInnerAlignment = function(f)
    local inner = f.inner
    if not inner then return end
    inner:ClearAllPoints()
    local align = Cfg("alignment") or "top"
    if align == "bottom" then
        inner:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
        inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    elseif align == "center" then
        inner:SetPoint("LEFT",  f, "LEFT",  0, 0)
        inner:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    else -- top (default)
        inner:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        inner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    end
end

local function BuildFrame()
    local f = CreateFrame("Frame", "EUI_QuestTrackerFrame", UIParent)
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(false)

    -- Inner frame holds all visual content; aligns within f based on setting
    local inner = CreateFrame("Frame", nil, f)
    inner:EnableMouse(true)
    f.inner = inner

    local bg = inner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(Cfg("bgR") or 0, Cfg("bgG") or 0, Cfg("bgB") or 0, Cfg("bgAlpha") or 0.35); f.bg = bg

    local topLine = inner:CreateTexture(nil, "ARTWORK")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT",  inner, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, 0)
    topLine:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.7)
    if not Cfg("showTopLine") then topLine:Hide() end
    f.topLine = topLine

    local sf = CreateFrame("ScrollFrame", "EUI_QuestTrackerScroll", inner)
    sf:SetPoint("TOPLEFT",     inner, "TOPLEFT",     PAD_H, -(PAD_V + 2))
    sf:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -(PAD_H + 10), PAD_V + 5)
    sf:EnableMouseWheel(true)
    sf:SetClipsChildren(true)
    f.sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(math.max(10, (Cfg("width") or 220) - PAD_H*2 - 10))
    content:SetHeight(1)
    sf:SetScrollChild(content); f.content = content

    -- Thin scrollbar (parented to inner so it isn't clipped by ScrollFrame)
    local scrollTrack = CreateFrame("Frame", nil, inner)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -4, -(PAD_V + 2 + 4))
    scrollTrack:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -4, PAD_V + 5 + 4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 3)
    scrollTrack:Hide()

    local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.02)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop", function() end)

    local scrollHitArea = CreateFrame("Button", nil, inner)
    scrollHitArea:SetWidth(16)
    scrollHitArea:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, -(PAD_V + 2 + 4))
    scrollHitArea:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", 0, PAD_V + 5 + 4)
    scrollHitArea:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
    scrollHitArea:EnableMouse(true)
    scrollHitArea:RegisterForDrag("LeftButton")
    scrollHitArea:SetScript("OnDragStart", function() end)
    scrollHitArea:SetScript("OnDragStop", function() end)
    scrollHitArea:SetScript("OnEnter", function()
        if EQT._onHoverIn then EQT._onHoverIn() end
        if EQT._qtMouseoverIn then EQT._qtMouseoverIn() end
    end)
    scrollHitArea:SetScript("OnLeave", function()
        if EQT._onHoverOut then EQT._onHoverOut() end
        if EQT._qtMouseoverOut then EQT._qtMouseoverOut() end
    end)

    local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 0.27)

    local SCROLL_STEP = 60
    local SMOOTH_SPEED = 12
    local isDragging = false
    local dragStartY, dragStartScroll
    local scrollTarget = 0
    local isSmoothing = false

    local function StopScrollDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end

    local scrollbarHovered = false
    local FADE_DUR = 0.2
    local hoverFade = 0   -- 0 = fully out, 1 = fully in
    scrollTrack:SetAlpha(0)
    scrollTrack:Show()

    local function UpdateScrollThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then scrollTrack:SetAlpha(0); hoverFade = 0; return end
        local trackH = scrollTrack:GetHeight()
        local visH   = sf:GetHeight()
        local visibleRatio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * visibleRatio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        local maxThumbTravel = trackH - thumbH
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * maxThumbTravel))
    end
    f._updateScrollThumb = UpdateScrollThumb

    -- Smooth scroll OnUpdate
    local smoothFrame = CreateFrame("Frame")
    smoothFrame:Hide()
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        local scale = sf:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateScrollThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        if diff > 0 then
            newScroll = math.ceil(newScroll * scale) / scale
        else
            newScroll = math.floor(newScroll * scale) / scale
        end
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        sf:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        local scale = sf:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        scrollTarget = math.max(0, math.min(maxScroll, target))
        scrollTarget = math.floor(scrollTarget * scale + 0.5) / scale
        scrollTarget = math.min(scrollTarget, maxScroll)
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
        SmoothScrollTo(base - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateScrollThumb() end)

    local function ScrollThumbOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then StopScrollDrag(); return end
        isSmoothing = false; smoothFrame:Hide()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = scrollTrack:GetHeight()
        local maxThumbTravel = trackH - self:GetHeight()
        if maxThumbTravel <= 0 then return end
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxThumbTravel) * maxScroll))
        local scale = sf:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        sf:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    scrollHitArea:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / scrollTrack:GetEffectiveScale()
        local top = scrollTrack:GetTop() or 0
        local trackH = scrollTrack:GetHeight()
        local thumbH = scrollThumb:GetHeight()
        if trackH <= thumbH then return end
        local frac = (top - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        local newScroll = frac * maxScroll
        local scale = sf:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        sf:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
        isDragging = true
        dragStartY = cy
        dragStartScroll = newScroll
        scrollThumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollHitArea:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    f:HookScript("OnSizeChanged", function(self, w)
        if EQT._widthDragging then return end
        local cw = math.max(10, w - PAD_H*2 - 10)
        content:SetWidth(cw); sf:SetWidth(cw)
        UpdateScrollThumb()
    end)

    -- Event-driven hover fade (0.2s transition for scrollbar + bg opacity)
    local frameHovered = false
    local fadeFrame = CreateFrame("Frame")
    fadeFrame:Hide()
    fadeFrame:SetScript("OnUpdate", function(_, dt)
        local target = frameHovered and 1 or 0
        if hoverFade == target then fadeFrame:Hide(); return end
        local speed = dt / FADE_DUR
        if target > hoverFade then
            hoverFade = math.min(1, hoverFade + speed)
        else
            hoverFade = math.max(0, hoverFade - speed)
        end
        -- Scrollbar alpha
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll > 0 then
            scrollTrack:SetAlpha(hoverFade)
        else
            scrollTrack:SetAlpha(0)
        end
        -- Background opacity boost (0 to +0.15)
        local baseA = Cfg("bgAlpha") or 0.6
        local curA = baseA + 0.15 * hoverFade
        f.bg:SetColorTexture(Cfg("bgR") or 0, Cfg("bgG") or 0, Cfg("bgB") or 0, math.min(1, curA))
        -- Snap when close enough
        if math.abs(hoverFade - target) < 0.01 then
            hoverFade = target
        end
    end)

    local function OnHoverIn()
        if frameHovered then return end
        frameHovered = true
        scrollbarHovered = true
        UpdateScrollThumb()
        fadeFrame:Show()
    end
    local function OnHoverOut()
        -- Defer one frame: OnLeave fires when entering a child frame too
        C_Timer.After(0, function()
            if f:IsMouseOver() then return end
            frameHovered = false
            scrollbarHovered = false
            fadeFrame:Show()
        end)
    end
    -- Use the outer frame for hover detection so child buttons don't break it.
    -- f is always full-size; inner/sf/content children all live inside it.
    f:SetScript("OnEnter", OnHoverIn)
    f:SetScript("OnLeave", OnHoverOut)
    inner:SetScript("OnEnter", OnHoverIn)
    inner:SetScript("OnLeave", OnHoverOut)
    sf:HookScript("OnEnter", OnHoverIn)
    sf:HookScript("OnLeave", OnHoverOut)
    -- Propagate hover from child buttons (quest rows, sections, items)
    EQT._onHoverIn = OnHoverIn
    EQT._onHoverOut = OnHoverOut

    -- Stop all standalone frames when hidden (M+, raids, disabled, etc.)
    f:HookScript("OnHide", function()
        fadeFrame:Hide()
        smoothFrame:Hide()
        frameHovered = false
        scrollbarHovered = false
        hoverFade = 0
        scrollTrack:SetAlpha(0)
        isSmoothing = false
    end)

    UpdateInnerAlignment(f)

    return f
end

-------------------------------------------------------------------------------
-- Position / Slash / Init / Load
-------------------------------------------------------------------------------
function EQT:ApplyPosition()
    local f = self.frame; if not f then return end
    -- Skip if unlock mode owns the position
    if EllesmereUI and EllesmereUI.IsUnlockAnchored
        and EllesmereUI.IsUnlockAnchored("EQT_Tracker") and f:GetLeft() then
        return
    end
    f:ClearAllPoints()
    -- Migrate legacy xPos/yPos to new pos format
    local db = DB()
    if db.xPos and db.yPos and not db.pos then
        local uiW, uiH = UIParent:GetSize()
        local fW, fH = f:GetSize()
        local cx = db.xPos + fW / 2
        local cy = (db.yPos + uiH) - fH / 2
        db.pos = {
            point = "CENTER", relPoint = "CENTER",
            x = cx - uiW / 2, y = cy - uiH / 2,
        }
        db.xPos = nil; db.yPos = nil
    end
    local pos = db.pos
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -200)
    end
end

local function RegisterSlash()
    SLASH_EUIQUEST1 = "/euiqt"
    SlashCmdList["EUIQUEST"] = function(msg)
        msg = strtrim(msg or ""):lower()
        if msg == "" or msg == "toggle" then
            local f = EQT.frame
            if f then if f:IsShown() then f:Hide() else f:Show(); EQT:Refresh() end end
        elseif msg == "reset" then
            DB().pos = nil; EQT:ApplyPosition()
        end
    end
end

-------------------------------------------------------------------------------
-- Snapshot Blizzard ObjectiveTrackerFrame position on first install
-- Captures position, width, and font size so our tracker starts where the
-- user had Blizzard's tracker in Edit Mode. Only runs once per install.
-------------------------------------------------------------------------------
local function CaptureBlizzardTracker()
    local ot = _G.ObjectiveTrackerFrame
    if not ot then return end
    local db = DB()
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    -- Get center position, scale-adjusted to UIParent coords
    local cx, cy = ot:GetCenter()
    if not cx or not cy then return end
    local bScale = ot:GetEffectiveScale()
    cx = cx * bScale / uiScale
    cy = cy * bScale / uiScale
    -- Store as CENTER/CENTER offset
    db.pos = {
        point = "CENTER", relPoint = "CENTER",
        x = cx - (uiW / 2), y = cy - (uiH / 2),
    }
    -- Capture width if available
    local w = ot:GetWidth()
    if w and w > 50 then
        db.width = math.floor(w * bScale / uiScale + 0.5)
    end
    -- Capture height as fixed height
    local h = ot:GetHeight()
    if h and h > 50 then
        db.height = math.floor(h * bScale / uiScale + 0.5)
    end
    -- Capture text size from Blizzard's edit mode setting (index 2)
    if ot.GetSettingValue then
        local ok, val = pcall(ot.GetSettingValue, ot, 2)
        if ok and val and val > 0 then
            local s = math.floor(val + 0.5)
            db.titleFontSize = s
            db.objFontSize   = math.max(s - 1, 6)
            db.secFontSize   = s + 1
        end
    end
    db._capturedOnce = true
end

-- Returns true if the player is in a Normal+ raid or M+ dungeon
local function IsInHiddenInstance()
    local _, iType, diffID = GetInstanceInfo()
    diffID = tonumber(diffID) or 0
    -- Raid difficulties: Normal(14), Heroic(15), Mythic(16), LFR(17)
    if iType == "raid" and diffID >= 14 then return true end
    -- Mythic+ dungeon: difficultyID 8 (Mythic Keystone)
    if iType == "party" and diffID == 8 then return true end
    return false
end

function EQT:Init()
    DB()
    EQT.sections  = EQT.sections  or {}
    EQT.itemBtns  = EQT.itemBtns  or {}
    EQT.timerRows = EQT.timerRows or {}
    if not Cfg("enabled") then return end
    self._needsCapture = not DB()._capturedOnce
    self.frame = BuildFrame()
    self.frame:SetWidth(Cfg("width") or 220)
    self.frame:SetHeight(Cfg("height") or 600)
    self:ApplyPosition()

    -- Hide/show Blizzard ObjectiveTrackerFrame based on setting
    local function ApplyBlizzardTrackerVisibility()
        local ot = _G.ObjectiveTrackerFrame
        if not ot then return end
        if Cfg("hideBlizzardTracker") and Cfg("enabled") ~= false then
            ot:SetAlpha(0)
            ot:EnableMouse(false)
        else
            ot:SetAlpha(1)
            ot:EnableMouse(true)
        end
    end
    EQT.ApplyBlizzardTrackerVisibility = ApplyBlizzardTrackerVisibility
    -- Hook Show and SetAlpha so Blizzard/unlock mode can't restore it
    local ot = _G.ObjectiveTrackerFrame
    if ot then
        local suppressing = false
        local function SuppressBlizzTracker()
            if suppressing then return end
            if Cfg("hideBlizzardTracker") and Cfg("enabled") ~= false then
                suppressing = true
                ot:SetAlpha(0)
                ot:EnableMouse(false)
                suppressing = false
            end
        end
        hooksecurefunc(ot, "Show", SuppressBlizzTracker)
        hooksecurefunc(ot, "SetAlpha", SuppressBlizzTracker)
    end
    C_Timer.After(1, ApplyBlizzardTrackerVisibility)

    -- Visibility system: check mode + options + instance hiding
    local qtMouseoverActive = false
    local function QTMouseoverIn()
        if not qtMouseoverActive then return end
        EQT.frame:SetAlpha(1)
    end
    local function QTMouseoverOut()
        if not qtMouseoverActive then return end
        C_Timer.After(0, function()
            if not qtMouseoverActive then return end
            if not self.frame:IsMouseOver() then
                self.frame:SetAlpha(0)
            end
        end)
    end
    -- Hook onto outer frame + inner + sf for mouseover visibility.
    -- Child buttons propagate via EQT._onHoverIn/_onHoverOut which
    -- already call OnHoverIn/OnHoverOut (handles scrollbar/bg fade).
    -- For mouseover visibility mode, we also need QTMouseoverIn/Out.
    EQT._qtMouseoverIn = QTMouseoverIn
    EQT._qtMouseoverOut = QTMouseoverOut
    self.frame:HookScript("OnEnter", QTMouseoverIn)
    self.frame:HookScript("OnLeave", QTMouseoverOut)
    local innerFrame = self.frame.inner or self.frame
    innerFrame:HookScript("OnEnter", QTMouseoverIn)
    innerFrame:HookScript("OnLeave", QTMouseoverOut)
    if self.frame.sf then
        self.frame.sf:HookScript("OnEnter", QTMouseoverIn)
        self.frame.sf:HookScript("OnLeave", QTMouseoverOut)
    end

    local function UpdateQTVisibility()
        if not EQT.frame then return end
        if Cfg("enabled") == false then EQT.frame:Hide(); qtMouseoverActive = false; return end
        if IsInHiddenInstance() then EQT.frame:Hide(); qtMouseoverActive = false; return end
        local qt = DB()
        if EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(qt) then
            EQT.frame:Hide(); qtMouseoverActive = false; return
        end
        local mode = qt.visibility or "always"
        if mode == "mouseover" then
            qtMouseoverActive = true
            EQT.frame:Show()
            EQT.frame:SetAlpha(0)
            return
        end
        qtMouseoverActive = false
        EQT.frame:SetAlpha(1)
        local show = true
        if mode == "never" then
            show = false
        elseif mode == "in_combat" then
            show = _G._EBS_InCombat and _G._EBS_InCombat() or false
        elseif mode == "out_of_combat" then
            show = not (_G._EBS_InCombat and _G._EBS_InCombat())
        elseif mode == "in_raid" then
            show = IsInRaid()
        elseif mode == "in_party" then
            show = IsInGroup() and not IsInRaid()
        elseif mode == "solo" then
            show = not IsInGroup()
        end
        if show then EQT.frame:Show() else EQT.frame:Hide() end
    end
    _G._EBS_UpdateQTVisibility = UpdateQTVisibility

    local QUEST_EVENTS = {
        "QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN",
        "UNIT_QUEST_LOG_CHANGED",
    }
    local QUEST_EVENTS_SAFE = {
        "QUEST_WATCH_LIST_CHANGED","QUEST_WATCH_UPDATE","QUEST_TASK_PROGRESS_UPDATE",
        "TASK_IS_TOO_DIFFERENT","SCENARIO_CRITERIA_UPDATE","SCENARIO_UPDATE",
        "SCENARIO_COMPLETED","CRITERIA_COMPLETE",
        "UI_WIDGET_UNIT_CHANGED",
        "QUEST_DATA_LOAD_RESULT","QUEST_POI_UPDATE","AREA_POIS_UPDATED",
        "SUPER_TRACKING_CHANGED",
    }
    local ZONE_EVENTS = {"ZONE_CHANGED_NEW_AREA","ZONE_CHANGED"}

    local w = CreateFrame("Frame")
    local zoneFrame = CreateFrame("Frame")

    local function RegisterQTEvents()
        w:RegisterEvent("PLAYER_ENTERING_WORLD")
        for _, ev in ipairs(QUEST_EVENTS) do w:RegisterEvent(ev) end
        for _, ev in ipairs(QUEST_EVENTS_SAFE) do pcall(w.RegisterEvent, w, ev) end
        for _, ev in ipairs(ZONE_EVENTS) do zoneFrame:RegisterEvent(ev) end
    end
    local function UnregisterQTEvents()
        for _, ev in ipairs(QUEST_EVENTS) do w:UnregisterEvent(ev) end
        for _, ev in ipairs(QUEST_EVENTS_SAFE) do pcall(w.UnregisterEvent, w, ev) end
        for _, ev in ipairs(ZONE_EVENTS) do zoneFrame:UnregisterEvent(ev) end
        -- Keep PLAYER_ENTERING_WORLD so visibility is re-evaluated on zone transitions
    end

    RegisterQTEvents()

    zoneFrame:SetScript("OnEvent", function()
        -- Zone changed: clear section cache so quests re-categorize
        EQT:ClearSectionCache()
        C_Timer.After(0.5,  function() EQT.dirty = true end)
        C_Timer.After(1.5,  function() EQT.dirty = true end)
        C_Timer.After(3.0,  function() EQT.dirty = true end)
        C_Timer.After(5.0,  function() EQT.dirty = true end)
    end)

    -- Structural events always trigger a rebuild (quest actually added/removed)
    local STRUCTURAL_EVENTS = {
        PLAYER_ENTERING_WORLD = true,
        QUEST_ACCEPTED = true,
        QUEST_REMOVED = true,
        QUEST_TURNED_IN = true,
        QUEST_WATCH_LIST_CHANGED = true,
        SCENARIO_COMPLETED = true,
    }
    w:SetScript("OnEvent", function(_, event)
        -- Non-structural events (progress, selection, POI) are suppressible
        if EQT._suppressDirty and not STRUCTURAL_EVENTS[event] then
            return
        end
        -- Structural events clear section cache so quests re-categorize
        if STRUCTURAL_EVENTS[event] then
            EQT:ClearSectionCache()
        end
        EQT.dirty = true
        if event == "PLAYER_ENTERING_WORLD" then
            -- First install: snapshot Blizzard tracker position before we hide it
            if EQT._needsCapture then
                EQT._needsCapture = false
                CaptureBlizzardTracker()
                if EQT.frame then
                    EQT.frame:SetWidth(Cfg("width") or 220)
                end
            end
            EQT:ApplyPosition()
            UpdateQTVisibility()
        end
        if EQT.UpdateQuestItemAttribute then EQT.UpdateQuestItemAttribute() end
    end)

    -- Fully suspend/resume quest tracking when hidden/shown
    self.frame:HookScript("OnHide", function()
        UnregisterQTEvents()
    end)
    self.frame:HookScript("OnShow", function()
        RegisterQTEvents()
        EQT.dirty = true
    end)

    -------------------------------------------------------------------------------
    -- Auto Accept / Auto Turn-in
    -------------------------------------------------------------------------------
    local autoFrame = CreateFrame("Frame")
    -- QUEST_DETAIL: fires when a quest offer is shown to the player (NPC or item)
    -- QUEST_COMPLETE: fires when the turn-in dialog opens
    -- QUEST_ACCEPTED: fires after quest is accepted (used to confirm, not trigger)
    autoFrame:RegisterEvent("QUEST_DETAIL")
    autoFrame:RegisterEvent("QUEST_COMPLETE")
    autoFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "QUEST_DETAIL" then
            if not Cfg("autoAccept") then return end
            -- AcceptQuest() works immediately on QUEST_DETAIL in TWW
            -- No delay needed – the event fires exactly when the offer is ready
            AcceptQuest()
        elseif event == "QUEST_COMPLETE" then
            if not Cfg("autoTurnIn") then return end
            -- Skip auto turn-in if Shift is held (allows reading rewards)
            if Cfg("autoTurnInShiftSkip") and IsShiftKeyDown() then return end
            -- CompleteQuest() submits the turn-in
            CompleteQuest()
        end
    end)

    local elapsed = 0
    local timerElapsed = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 and EQT.dirty then
            elapsed = 0; EQT.dirty = false; EQT:Refresh()
        end
        -- Update active timers every second
        timerElapsed = timerElapsed + dt
        if timerElapsed >= 1.0 then
            timerElapsed = 0
            for _, r in ipairs(EQT.timerRows) do
                if r._updateTimer then r._updateTimer() end
            end
        end
    end)
    RegisterSlash()
    C_Timer.After(1.5, function() EQT.dirty = true end)

    -------------------------------------------------------------------------------
    -- Quest item hotkey using SecureHandlerAttributeTemplate pattern (no taint)
    -- _onattributechanged runs in the secure environment and calls SetBindingClick
    -- The binding name 'EUI_QUESTITEM' is set via SetBinding/SaveBinding in options
    -------------------------------------------------------------------------------
    local qItemBtn = CreateFrame("Button", "EUI_QuestItemHotkeyBtn", UIParent,
        "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    qItemBtn:SetSize(32, 32)
    qItemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    qItemBtn:SetAlpha(0)
    qItemBtn:EnableMouse(false)
    qItemBtn:RegisterForClicks("LeftButtonUp")

    -- Secure attribute setup must be deferred if we loaded during combat
    -- (e.g. /reload while in combat), otherwise the restricted environment
    -- handles are not yet valid and SetAttribute triggers an error.
    local function InitSecureAttributes()
        qItemBtn:SetAttribute("type", "item")
        qItemBtn:SetAttribute("_onattributechanged", [[
            if name == 'item' then
                self:ClearBindings()
                if value then
                    local key1, key2 = GetBindingKey('EUI_QUESTITEM')
                    if key1 then self:SetBindingClick(false, key1, self, 'LeftButton') end
                    if key2 then self:SetBindingClick(false, key2, self, 'LeftButton') end
                end
            end
        ]])
    end
    if InCombatLockdown() then
        local initFrame = CreateFrame("Frame")
        initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        initFrame:SetScript("OnEvent", function(f)
            f:UnregisterAllEvents()
            InitSecureAttributes()
            if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
            if EQT.UpdateQuestItemAttribute then EQT.UpdateQuestItemAttribute() end
        end)
    else
        InitSecureAttributes()
    end

    EQT.qItemBtn = qItemBtn

    -- Set the WoW binding so GetBindingKey('EUI_QUESTITEM') works
    -- This uses SaveBindings which is the standard API
    local _applyingQuestItemHotkey = false

local function ApplyQuestItemHotkey()
    if InCombatLockdown() then return end
    if _applyingQuestItemHotkey then return end

    _applyingQuestItemHotkey = true

    local ok, err = pcall(function()
        local key = Cfg("questItemHotkey")
        local old1, old2 = GetBindingKey("EUI_QUESTITEM")
        local hasOld = old1 or old2
        local hasNew = key and key ~= ""

        if not hasOld and not hasNew then
            return
        end

        local changed = false

        if hasOld then
            if old1 and old1 ~= key then
                SetBinding(old1)
                changed = true
            end
            if old2 and old2 ~= key then
                SetBinding(old2)
                changed = true
            end
        end

        if hasNew then
            local alreadyBound = (old1 == key or old2 == key)
            if not alreadyBound then
                SetBinding(key, "EUI_QUESTITEM")
                changed = true
            end
        end

        if changed then
            local bindingSet = GetCurrentBindingSet()
            if bindingSet and bindingSet >= 1 and bindingSet <= 2 then
                SaveBindings(bindingSet)
            end
        end

        local cur = qItemBtn:GetAttribute("item")
        qItemBtn:SetAttribute("item", nil)
        qItemBtn:SetAttribute("item", cur)
    end)

    _applyingQuestItemHotkey = false

    if not ok and err then
        geterrorhandler()(err)
    end
end
EQT.ApplyQuestItemHotkey = ApplyQuestItemHotkey

    -- Register the binding name globally so WoW knows about it
    _G["BINDING_NAME_EUI_QUESTITEM"] = "Use Quest Item"

    local function UpdateQuestItemAttribute()
        if InCombatLockdown() then return end
        local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
        for pass = 1, 3 do
            for i = 1, n do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and not info.isInternalOnly then
                    local qID = info.questID
                    local wt = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(qID)
                    local isRelevant = (pass == 1 and wt ~= nil)
                        or (pass == 2 and info.isOnMap and not info.isTask)
                        or (pass == 3 and info.isTask)
                    if isRelevant and not (info.isHidden and not info.isTask) then
                        local item = GetQuestItem(qID)
                        if item and item.name then
                            qItemBtn:SetAttribute("item", item.name)
                            return
                        end
                    end
                end
            end
        end
        qItemBtn:SetAttribute("item", nil)
    end
    EQT.UpdateQuestItemAttribute = UpdateQuestItemAttribute

    local qItemFrame = CreateFrame("Frame")
    qItemFrame:RegisterEvent("QUEST_LOG_UPDATE")
    qItemFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    qItemFrame:RegisterEvent("ZONE_CHANGED")
    qItemFrame:RegisterEvent("UPDATE_BINDINGS")
    qItemFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    qItemFrame:SetScript("OnEvent", function(_, event)
    if InCombatLockdown() then return end

    if event == "PLAYER_REGEN_ENABLED" then
        ApplyQuestItemHotkey()
        UpdateQuestItemAttribute()
        return
    end

    if event == "UPDATE_BINDINGS" then
        local cur = qItemBtn:GetAttribute("item")
        qItemBtn:SetAttribute("item", nil)
        qItemBtn:SetAttribute("item", cur)
        return
    end

    UpdateQuestItemAttribute()
end)

    C_Timer.After(1.5, function()
        if InCombatLockdown() then return end
        ApplyQuestItemHotkey()
        UpdateQuestItemAttribute()
    end)

    ---------------------------------------------------------------------------
    -- Register unlock mode element
    ---------------------------------------------------------------------------
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local f = self.frame
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EQT_Tracker",
                label = "Quest Tracker",
                group = "Basics",
                order = 510,
                noResize = false,
                getFrame = function() return f end,
                getSize  = function()
                    return f:GetWidth(), f:GetHeight()
                end,
                setWidth = function(_, w)
                    local minW = 120
                    w = math.max(minW, math.floor(w + 0.5))
                    DB().width = w
                    f:SetWidth(w)
                    -- Suppress OnSizeChanged + disable word wrap during drag
                    if not EQT._widthDragging then
                        EQT._widthDragging = true
                        for _, r in ipairs(EQT.rows) do
                            if r.text then r.text:SetWordWrap(false) end
                        end
                    end
                    -- Debounce the expensive full refresh
                    if EQT._resizeTimer then EQT._resizeTimer:Cancel() end
                    EQT._resizeTimer = C_Timer.NewTimer(0.15, function()
                        EQT._resizeTimer = nil
                        EQT._widthDragging = false
                        EQT:Refresh()
                    end)
                    EllesmereUI.RepositionBarToMover("EQT_Tracker")
                end,
                setHeight = function(_, h)
                    h = math.max(60, math.floor(h + 0.5))
                    DB().height = h
                    f:SetHeight(h)
                    -- Lightweight inner resize (no full rebuild)
                    if f.inner then
                        local totalH = (f.content and f.content:GetHeight() or 0) + PAD_V*2 + 7
                        f.inner:SetHeight(math.min(totalH, h))
                    end
                    -- Debounce the expensive full refresh
                    if EQT._resizeTimer then EQT._resizeTimer:Cancel() end
                    EQT._resizeTimer = C_Timer.NewTimer(0.15, function()
                        EQT._resizeTimer = nil
                        EQT:Refresh()
                    end)
                    EllesmereUI.RepositionBarToMover("EQT_Tracker")
                end,
                savePos = function(_, point, relPoint, x, y)
                    DB().pos = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        EQT:ApplyPosition()
                    end
                end,
                loadPos = function()
                    return DB().pos
                end,
                clearPos = function()
                    DB().pos = nil
                end,
                applyPos = function()
                    EQT:ApplyPosition()
                end,
            }),
        })
    end
end

-- Re-apply quest tracker after UI scale changes so position and layout stay correct
do
    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("UI_SCALE_CHANGED")
    scaleFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleFrame:SetScript("OnEvent", function()
        if not EQT.frame then return end
        C_Timer.After(0, function()
            EQT:ApplyPosition()
            EQT:Refresh()
        end)
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded == addonName then
        EQT:Init()
    end
    -- Catch Blizzard's tracker loading: capture position then hide it
    if loaded == "Blizzard_ObjectiveTracker" then
        if EQT._needsCapture then
            EQT._needsCapture = false
            CaptureBlizzardTracker()
            if EQT.frame then
                EQT.frame:SetWidth(Cfg("width") or 220)
                EQT:ApplyPosition()
            end
        end
        if EQT.ApplyBlizzardTrackerVisibility then
            EQT.ApplyBlizzardTrackerVisibility()
        end
    end
end)
