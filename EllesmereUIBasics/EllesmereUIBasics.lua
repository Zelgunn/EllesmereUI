-------------------------------------------------------------------------------
--  EllesmereUIBasics.lua
--  Chat, Minimap, and Friends List skinning for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIBasics")

local PP = EllesmereUI.PP

local defaults = {
    profile = {
        chat = {
            enabled       = true,
            bgAlpha       = 0.6,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            fontSize      = 14,
            hideButtons   = false,
            hideTabFlash  = false,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
            -- New fields
            fontFace           = nil,          -- nil = preserve current, else LSM font name
            fontOutline        = "",           -- "", "OUTLINE", "THICKOUTLINE"
            fontShadow         = true,         -- toggle shadow on/off
            classColorNames    = true,         -- color player names by class
            clickableURLs      = true,         -- detect and linkify URLs
            shortenChannels    = "off",        -- "off", "short", "minimal"
            timestamps         = "none",       -- "none","HH:MM","HH:MM:SS","HH:MM AP","HH:MM:SS AP"
            timestampSeparator = false,        -- vertical bar between timestamp and message
            messageFadeEnabled = true,         -- enable message fading
            messageFadeTime    = 120,          -- seconds before fade (5-240)
            messageSpacing     = 0,            -- line spacing (0-10)
            copyButton         = false,        -- show copy button on chat frame
            copyLines          = 200,          -- lines to include in copy (50-500)
            showSearchButton   = true,         -- show search button on chat frame
        },
        minimap = {
            enabled       = true,
            shape         = "square",
            borderSize    = 1,
            showCoords    = false,
            coordPrecision = 1,
            scale         = 1.0,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            hideZoneText  = false,
            scrollZoom    = true,
            autoZoomOut   = true,
            hideZoomButtons      = true,
            hideTrackingButton   = true,
            hideGameTime         = true,
            hideMail             = false,
            hideRaidDifficulty   = false,
            hideCraftingOrder    = false,
            hideAddonCompartment = false,
            hideAddonButtons     = false,
            showClock     = false,
            clockFormat   = "12h",
            lock          = false,
            position      = nil,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        friends = {
            enabled       = true,
            bgAlpha       = 0.8,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        cursor = {
            enabled = true,
            instanceOnly = false,
            useClassColor = true,
            hex = "0CD29D",
            texture = "ring_normal",
            scale = 1,
            gcd = {
                enabled = false,
                attached = true,
                radius = 21,
                ringTex = "light",
                scale = 100,
                hex = "FFFFFF",
                alpha = 80,
                useClassColor = false,
                instanceOnly = false,
            },
            castCircle = {
                enabled = false,
                attached = true,
                radius = 30,
                ringTex = "normal",
                scale = 100,
                hex = "3FA7FF",
                alpha = 80,
                sparkEnabled = true,
                sparkHex = nil,
                useClassColor = true,
                instanceOnly = false,
            },
            trail = false,
            visibility       = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        questTracker = {
            enabled              = true,
            pos                  = nil,
            width                = 220,
            bgAlpha              = 0.6,
            bgR                  = 0,
            bgG                  = 0,
            bgB                  = 0,
            height               = 600,
            alignment            = "top",
            titleFontSize        = 11,
            titleColor           = { r=1.0,  g=0.91, b=0.47 },
            objFontSize          = 10,
            objColor             = { r=0.72, g=0.72, b=0.72 },
            secFontSize          = 12,
            showZoneQuests       = true,
            showWorldQuests      = true,
            zoneCollapsed        = false,
            worldCollapsed       = false,
            showQuestItems       = true,
            questItemSize        = 22,
            secColor             = { r=0.047, g=0.824, b=0.624 },
            delveCollapsed       = false,
            questsCollapsed      = false,
            questItemHotkey      = nil,
            autoAccept           = false,
            autoTurnIn           = false,
            autoTurnInShiftSkip  = true,
            showTopLine          = true,
            hideBlizzardTracker  = true,
            visibility           = "always",
            visOnlyInstances     = false,
            visHideHousing       = false,
            visHideMounted       = false,
            visHideNoTarget      = false,
            visHideNoEnemy       = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetClassColor()
    local _, classFile = UnitClass("player")
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if cc then return cc.r, cc.g, cc.b, 1 end
    return 0.05, 0.05, 0.05, 1
end

local function GetBorderColor(cfg)
    if cfg.useClassColor then
        return GetClassColor()
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local pendingApply = false
local ApplyAll  -- forward declaration

local function QueueApplyAll()
    if pendingApply then return end
    pendingApply = true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingApply then
        pendingApply = false
        ApplyAll()
    end
end)

-------------------------------------------------------------------------------
--  Chat Skin
-------------------------------------------------------------------------------
local skinnedChatFrames = {}

local function SkinChatFrame(chatFrame, p)
    if not chatFrame then return end
    local name = chatFrame:GetName()
    if not name then return end

    -- Dark background
    if not chatFrame._ebsBg then
        chatFrame._ebsBg = chatFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        chatFrame._ebsBg:SetColorTexture(0, 0, 0)
        chatFrame._ebsBg:SetPoint("TOPLEFT", -4, 4)
        chatFrame._ebsBg:SetPoint("BOTTOMRIGHT", 4, -4)
    end
    chatFrame._ebsBg:SetAlpha(p.bgAlpha)

    -- Border
    local r, g, b, a = GetBorderColor(p)
    if not chatFrame._ppBorders then
        PP.CreateBorder(chatFrame, r, g, b, a, 1, "OVERLAY", 7)
    else
        PP.SetBorderColor(chatFrame, r, g, b, a)
    end

    -- Edit box skin
    local editBox = _G[name .. "EditBox"]
    if editBox then
        if not editBox._ebsBg then
            editBox._ebsBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -7)
            editBox._ebsBg:SetColorTexture(0, 0, 0)
            editBox._ebsBg:SetPoint("TOPLEFT", -2, 2)
            editBox._ebsBg:SetPoint("BOTTOMRIGHT", 2, -2)
        end
        editBox._ebsBg:SetAlpha(p.bgAlpha)

        if not editBox._ppBorders then
            PP.CreateBorder(editBox, r, g, b, a, 1, "OVERLAY", 7)
        else
            PP.SetBorderColor(editBox, r, g, b, a)
        end
    end

    -- Font: face, size, outline, shadow
    do
        local fontObj = chatFrame:GetFontObject()
        if fontObj then
            local curFont, _, curFlags = fontObj:GetFont()
            -- Face: use configured LSM font or preserve current
            local face = curFont
            if p.fontFace then
                local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
                if lsm then
                    local lsmPath = lsm:Fetch("font", p.fontFace)
                    if lsmPath then face = lsmPath end
                end
            end
            -- Outline
            local outline = p.fontOutline or ""
            -- Apply
            chatFrame:SetFont(face, p.fontSize, outline)
            -- Shadow
            if p.fontShadow then
                chatFrame:SetShadowOffset(1, -1)
                chatFrame:SetShadowColor(0, 0, 0, 1)
            else
                chatFrame:SetShadowOffset(0, 0)
                chatFrame:SetShadowColor(0, 0, 0, 0)
            end
        end
    end

    -- Message spacing
    if chatFrame.SetSpacing then
        chatFrame:SetSpacing(p.messageSpacing or 0)
    end

    -- Message fade
    if chatFrame.SetTimeVisible then
        if p.messageFadeEnabled then
            chatFrame:SetTimeVisible(p.messageFadeTime or 120)
            chatFrame:SetFadeDuration(3)
        else
            chatFrame:SetTimeVisible(9999)
            chatFrame:SetFadeDuration(0)
        end
    end

    skinnedChatFrames[chatFrame] = true
end

local chatButtonsHidden = false
local chatButtonHooks = {}

local function HideChatButton(btn)
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not chatButtonHooks[btn] then
        hooksecurefunc(btn, "Show", function(self)
            if _G._EBS_AceDB and _G._EBS_AceDB.profile.chat.hideButtons then
                self:Hide()
                self:SetAlpha(0)
            end
        end)
        chatButtonHooks[btn] = true
    end
end

local function ShowChatButton(btn)
    if not btn then return end
    btn:SetAlpha(1)
    btn:Show()
end

local tabFlashHooked = false

local function UnskinChatFrame(chatFrame)
    if not chatFrame then return end
    if chatFrame._ebsBg then chatFrame._ebsBg:SetAlpha(0) end
    if chatFrame._ppBorders then PP.SetBorderColor(chatFrame, 0, 0, 0, 0) end

    local name = chatFrame:GetName()
    if name then
        local editBox = _G[name .. "EditBox"]
        if editBox then
            if editBox._ebsBg then editBox._ebsBg:SetAlpha(0) end
            if editBox._ppBorders then PP.SetBorderColor(editBox, 0, 0, 0, 0) end
        end
    end
end

local function ApplyChat()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.chat

    if not p.enabled then
        -- Revert all skinned chat frames
        for chatFrame in pairs(skinnedChatFrames) do
            UnskinChatFrame(chatFrame)
        end
        -- Restore buttons
        if chatButtonsHidden then
            local buttons = { ChatFrameMenuButton, ChatFrameChannelButton, QuickJoinToastButton }
            for _, btn in ipairs(buttons) do ShowChatButton(btn) end
            chatButtonsHidden = false
        end
        return
    end

    local numWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, numWindows do
        local chatFrame = _G["ChatFrame" .. i]
        SkinChatFrame(chatFrame, p)
    end

    -- Hook dynamic windows
    if not EBS._chatHookDone then
        EBS._chatHookDone = true
        hooksecurefunc("FCF_OpenNewWindow", function()
            C_Timer.After(0.1, function()
                if not EBS.db then return end
                local cp = EBS.db.profile.chat
                if not cp.enabled then return end
                for j = 1, NUM_CHAT_WINDOWS or 10 do
                    local cf = _G["ChatFrame" .. j]
                    if cf and not skinnedChatFrames[cf] then
                        SkinChatFrame(cf, cp)
                    end
                end
            end)
        end)
    end

    -- Hide/show buttons
    local buttons = {
        ChatFrameMenuButton,
        ChatFrameChannelButton,
        QuickJoinToastButton,
    }
    if p.hideButtons then
        for _, btn in ipairs(buttons) do
            HideChatButton(btn)
        end
        chatButtonsHidden = true
    elseif chatButtonsHidden then
        for _, btn in ipairs(buttons) do
            ShowChatButton(btn)
        end
        chatButtonsHidden = false
    end

    -- Hide tab flash
    if p.hideTabFlash and not tabFlashHooked then
        tabFlashHooked = true
        if FCF_StartAlertFlash then
            hooksecurefunc("FCF_StartAlertFlash", function(chatF)
                if EBS.db and EBS.db.profile.chat.hideTabFlash then
                    FCF_StopAlertFlash(chatF)
                end
            end)
        end
    end

    -- Apply timestamps (from EllesmereUIBasics_Chat.lua)
    if _G._EBS_ApplyTimestamps then _G._EBS_ApplyTimestamps() end

    -- Update copy/search buttons (from EllesmereUIBasics_Chat.lua)
    if _G._EBS_UpdateCopyButtons then _G._EBS_UpdateCopyButtons() end
    if _G._EBS_UpdateSearchButtons then _G._EBS_UpdateSearchButtons() end

end

-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
}

local minimapButtonMap = {
    { key = "hideZoomButtons",      names = { "MinimapZoomIn", "MinimapZoomOut" } },
    { key = "hideTrackingButton",   names = { "MiniMapTrackingButton" } },
    { key = "hideGameTime",         names = { "GameTimeFrame" } },
    { key = "hideMail",             names = { "MiniMapMailFrame" } },
    { key = "hideRaidDifficulty",   names = { "MiniMapInstanceDifficulty", "GuildInstanceDifficulty" } },
    { key = "hideCraftingOrder",    names = { "MiniMapCraftingOrderFrame" } },
    { key = "hideAddonCompartment", names = { "AddonCompartmentFrame" } },
}

local minimapButtonHooks = {}

local function HideMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not minimapButtonHooks[name] then
        hooksecurefunc(btn, "Show", function(self)
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp then return end
            for _, entry in ipairs(minimapButtonMap) do
                for _, btnName in ipairs(entry.names) do
                    if btnName == name and mp[entry.key] then
                        self:Hide()
                        self:SetAlpha(0)
                        return
                    end
                end
            end
        end)
        minimapButtonHooks[name] = true
    end
end

local function ShowMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:SetAlpha(1)
    btn:Show()
end

local coordFrame, coordTicker
local clockFrame, clockTicker

local function UpdateClock()
    if not clockFrame then return end
    local p = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    local fmt = (p and p.clockFormat == "24h") and "%H:%M" or "%I:%M %p"
    clockFrame:SetText(date(fmt))
end

local function UpdateCoords()
    if not coordFrame then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then coordFrame:SetText(""); return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then coordFrame:SetText(""); return end
    local x, y = pos:GetXY()
    local p = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    local prec = p and p.coordPrecision or 1
    local fmt = "%." .. prec .. "f, %." .. prec .. "f"
    coordFrame:SetText(format(fmt, x * 100, y * 100))
end

local autoZoomTimer = nil

local function CancelAutoZoom()
    if autoZoomTimer then
        autoZoomTimer:Cancel()
        autoZoomTimer = nil
    end
end

local function ScheduleAutoZoom()
    CancelAutoZoom()
    local p = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    if not p or not p.autoZoomOut then return end
    if Minimap:GetZoom() == 0 then return end
    autoZoomTimer = C_Timer.NewTimer(10, function()
        Minimap:SetZoom(0)
        autoZoomTimer = nil
    end)
end

local addonButtonPoll = nil
local cachedAddonButtons = {}

local function RefreshAddonButtonCache()
    wipe(cachedAddonButtons)
    if not Minimap then return end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = child:GetName()
        if name and name:match("^LibDBIcon10_") then
            cachedAddonButtons[#cachedAddonButtons + 1] = child
        end
    end
end

local function SetAddonButtonsAlpha(alpha)
    for _, btn in ipairs(cachedAddonButtons) do
        btn:SetAlpha(alpha)
    end
end

local function ApplyMinimap()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.minimap

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- Restore default decorations
        for _, name in ipairs(minimapDecorations) do
            local frame = _G[name]
            if frame then frame:Show() end
        end
        -- Restore circular mask
        minimap:SetMaskTexture("Textures\\MinimapMask")
        -- Hide our background & border
        if minimap._ebsBg then minimap._ebsBg:SetAlpha(0) end
        if minimap._ppBorders then PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        -- Reset scale
        minimap:SetScale(1.0)
        -- Restore buttons
        for _, entry in ipairs(minimapButtonMap) do
            for _, btnName in ipairs(entry.names) do
                ShowMinimapButton(btnName)
            end
        end
        -- Restore addon buttons
        if addonButtonPoll then addonButtonPoll:Hide() end
        RefreshAddonButtonCache()
        SetAddonButtonsAlpha(1)
        -- Restore zone text
        local zoneBtn = MinimapZoneTextButton
        if zoneBtn then zoneBtn:Show() end
        if coordFrame then coordFrame:Hide() end
        if coordTicker then coordTicker:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
        minimap:SetMovable(false)
        minimap:EnableMouseWheel(false)
        CancelAutoZoom()
        return
    end

    -- Hide default decorations
    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end

    -- Shape mask
    if p.shape == "square" then
        minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
    else
        minimap:SetMaskTexture("Textures\\MinimapMask")
    end

    -- Dark background
    if not minimap._ebsBg then
        minimap._ebsBg = minimap:CreateTexture(nil, "BACKGROUND", nil, -7)
        minimap._ebsBg:SetColorTexture(0, 0, 0)
    end
    local inset = (p.borderSize or 1) + 1
    minimap._ebsBg:ClearAllPoints()
    minimap._ebsBg:SetPoint("TOPLEFT", -inset, inset)
    minimap._ebsBg:SetPoint("BOTTOMRIGHT", inset, -inset)

    -- Border
    local r, g, b, a = GetBorderColor(p)
    if not minimap._ppBorders then
        PP.CreateBorder(minimap, r, g, b, a, 1, "OVERLAY", 7)
    else
        PP.SetBorderColor(minimap, r, g, b, a)
    end

    -- Border size
    PP.SetBorderSize(minimap, p.borderSize or 1)

    -- Scale
    minimap:SetScale(p.scale)

    -- Individual button toggles
    for _, entry in ipairs(minimapButtonMap) do
        local hide = p[entry.key]
        for _, btnName in ipairs(entry.names) do
            if hide then
                HideMinimapButton(btnName)
            else
                ShowMinimapButton(btnName)
            end
        end
    end

    -- Addon button mouseover
    if p.hideAddonButtons then
        RefreshAddonButtonCache()
        SetAddonButtonsAlpha(0)
        if not addonButtonPoll then
            addonButtonPoll = CreateFrame("Frame")
            addonButtonPoll:RegisterEvent("ADDON_LOADED")
            addonButtonPoll:SetScript("OnEvent", function()
                RefreshAddonButtonCache()
                local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
                if mp and mp.hideAddonButtons and not Minimap:IsMouseOver() then
                    SetAddonButtonsAlpha(0)
                end
            end)
            local abElapsed = 0
            local wasOver = false
            addonButtonPoll:SetScript("OnUpdate", function(_, dt)
                abElapsed = abElapsed + dt
                if abElapsed < 0.15 then return end
                abElapsed = 0
                local over = Minimap:IsMouseOver()
                if over and not wasOver then
                    wasOver = true
                    SetAddonButtonsAlpha(1)
                elseif not over and wasOver then
                    wasOver = false
                    SetAddonButtonsAlpha(0)
                end
            end)
        end
        addonButtonPoll:Show()
    else
        if addonButtonPoll then addonButtonPoll:Hide() end
        SetAddonButtonsAlpha(1)
    end

    -- Clock
    if p.showClock then
        if not clockFrame then
            clockFrame = minimap:CreateFontString(nil, "OVERLAY")
            clockFrame:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            clockFrame:SetPoint("TOP", minimap, "BOTTOM", 0, -6)
            clockFrame:SetTextColor(1, 1, 1, 0.9)
        end
        clockFrame:Show()
        if not clockTicker then
            clockTicker = CreateFrame("Frame")
            local elapsed = 0
            clockTicker:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 1 then return end
                elapsed = 0
                UpdateClock()
            end)
        end
        clockTicker:Show()
        UpdateClock()
    else
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
    end

    -- Zone text
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then
        if p.hideZoneText then
            zoneBtn:Hide()
        else
            zoneBtn:Show()
        end
    end

    -- Coordinates
    if p.showCoords then
        if not coordFrame then
            coordFrame = minimap:CreateFontString(nil, "OVERLAY")
            coordFrame:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            coordFrame:SetPoint("BOTTOM", minimap, "BOTTOM", 0, 4)
            coordFrame:SetTextColor(1, 1, 1, 0.9)
        end
        coordFrame:Show()
        if not coordTicker then
            coordTicker = CreateFrame("Frame")
            local elapsed = 0
            coordTicker:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 0.5 then return end
                elapsed = 0
                UpdateCoords()
            end)
        end
        coordTicker:Show()
        UpdateCoords()
    else
        if coordFrame then coordFrame:Hide() end
        if coordTicker then coordTicker:Hide() end
    end

    -- Mousewheel zoom
    if p.scrollZoom then
        minimap:EnableMouseWheel(true)
        if not minimap._ebsZoomHooked then
            minimap._ebsZoomHooked = true
            minimap:HookScript("OnMouseWheel", function(self, delta)
                local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
                if not mp or not mp.scrollZoom then return end
                local zoom = self:GetZoom()
                if delta > 0 then
                    zoom = min(zoom + 1, 5)
                else
                    zoom = max(zoom - 1, 0)
                end
                self:SetZoom(zoom)
                ScheduleAutoZoom()
            end)
        end
    else
        minimap:EnableMouseWheel(false)
    end

    -- Cancel auto-zoom if disabled
    if not p.autoZoomOut then
        CancelAutoZoom()
    end

    -- Drag to reposition
    minimap:SetClampedToScreen(true)
    minimap:SetMovable(not p.lock)
    if not minimap._ebsDragHooked then
        minimap._ebsDragHooked = true
        minimap:RegisterForDrag("LeftButton")
        minimap:SetScript("OnDragStart", function(self)
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if mp and not mp.lock then
                self:StartMoving()
            end
        end)
        minimap:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if mp then
                mp.position = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end)
    end

    -- Restore saved position
    if p.position then
        minimap:ClearAllPoints()
        minimap:SetPoint(p.position.point, UIParent, p.position.relPoint, p.position.x, p.position.y)
    end
end

-------------------------------------------------------------------------------
--  Friends List Skin
-------------------------------------------------------------------------------
local friendsSkinned = false

-- One-time structural setup (background, NineSlice hide, border creation)
local function SkinFriendsFrame()
    local frame = FriendsFrame
    if not frame or friendsSkinned then return end
    friendsSkinned = true

    -- Dark background
    if not frame._ebsBg then
        frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        frame._ebsBg:SetColorTexture(0, 0, 0)
        frame._ebsBg:SetPoint("TOPLEFT", 0, 0)
        frame._ebsBg:SetPoint("BOTTOMRIGHT", 0, 0)
    end

    -- Hide NineSlice
    if frame.NineSlice then
        frame.NineSlice:Hide()
    end

    -- Create border + tab borders (colors applied by ApplyFriends)
    local p = EBS.db.profile.friends
    local r, g, b, a = GetBorderColor(p)
    PP.CreateBorder(frame, r, g, b, a, 1, "OVERLAY", 7)
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            PP.CreateBorder(tab, r, g, b, a, 1, "OVERLAY", 7)
        end
    end
end

-- Live updates: colors, opacity — safe to call repeatedly
local function ApplyFriends()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.friends

    if not p.enabled then
        if FriendsFrame and friendsSkinned then
            if FriendsFrame._ebsBg then FriendsFrame._ebsBg:SetAlpha(0) end
            if FriendsFrame._ppBorders then PP.SetBorderColor(FriendsFrame, 0, 0, 0, 0) end
            if FriendsFrame.NineSlice then FriendsFrame.NineSlice:Show() end
            for i = 1, 4 do
                local tab = _G["FriendsFrameTab" .. i]
                if tab and tab._ppBorders then PP.SetBorderColor(tab, 0, 0, 0, 0) end
            end
        end
        return
    end

    -- FriendsFrame is load-on-demand — ensure structural setup first
    if not FriendsFrame then return end
    SkinFriendsFrame()

    -- Re-show our elements in case they were hidden by disable
    if FriendsFrame.NineSlice then FriendsFrame.NineSlice:Hide() end

    local r, g, b, a = GetBorderColor(p)
    PP.SetBorderColor(FriendsFrame, r, g, b, a)
    if FriendsFrame._ebsBg then
        FriendsFrame._ebsBg:SetAlpha(p.bgAlpha)
    end
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab and tab._ppBorders then
            PP.SetBorderColor(tab, r, g, b, a)
        end
    end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local _ebsInCombat = false

-- Returns true = show, false = hide, "mouseover" = mouseover mode
local function EvalVisibility(cfg)
    if not cfg or not cfg.enabled then return false end
    if EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(cfg) then
        return false
    end
    local mode = cfg.visibility or "always"
    if mode == "mouseover" then return "mouseover" end
    if mode == "always" then return true end
    if mode == "never" then return false end
    if mode == "in_combat" then return _ebsInCombat end
    if mode == "out_of_combat" then return not _ebsInCombat end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if mode == "in_raid"  then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo"     then return not inGroup end
    return true
end

-- Mouseover poll: single lightweight frame, only runs when needed
-- Cached state avoids redundant SetAlpha calls; only fires API on change
local mouseoverTargets = {}  -- { { frame=, visible= }, ... }
local mouseoverPoll = CreateFrame("Frame")
mouseoverPoll:Hide()
local moElapsed = 0
mouseoverPoll:SetScript("OnUpdate", function(_, dt)
    moElapsed = moElapsed + dt
    if moElapsed < 0.15 then return end
    moElapsed = 0
    for i = 1, #mouseoverTargets do
        local t = mouseoverTargets[i]
        local frame = t.frame
        if frame and frame:IsShown() then
            local over = frame:IsMouseOver()
            if over and not t.visible then
                t.visible = true
                frame:SetAlpha(1)
            elseif not over and t.visible then
                t.visible = false
                frame:SetAlpha(0)
            end
        end
    end
end)

local function RebuildMouseoverTargets()
    wipe(mouseoverTargets)
    if not EBS.db then return end
    local prof = EBS.db.profile
    -- Chat: use first skinned chat frame as hover anchor, apply alpha to all
    if prof.chat and prof.chat.enabled and prof.chat.visibility == "mouseover" then
        for chatFrame in pairs(skinnedChatFrames) do
            mouseoverTargets[#mouseoverTargets + 1] = { frame = chatFrame }
        end
    end
    -- Minimap
    if prof.minimap and prof.minimap.enabled and prof.minimap.visibility == "mouseover" then
        if Minimap then
            mouseoverTargets[#mouseoverTargets + 1] = { frame = Minimap }
        end
    end
    -- Friends
    if prof.friends and prof.friends.enabled and prof.friends.visibility == "mouseover" then
        if FriendsFrame then
            mouseoverTargets[#mouseoverTargets + 1] = { frame = FriendsFrame }
        end
    end
    if #mouseoverTargets > 0 then
        mouseoverPoll:Show()
    else
        mouseoverPoll:Hide()
    end
end

local function UpdateChatVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.chat
    if not p or not p.enabled then return end
    local vis = EvalVisibility(p)
    if vis == "mouseover" then
        -- Start hidden; poll will handle show on hover
        for chatFrame in pairs(skinnedChatFrames) do
            chatFrame:SetAlpha(0)
        end
    else
        for chatFrame in pairs(skinnedChatFrames) do
            chatFrame:SetAlpha(vis and 1 or 0)
        end
    end
end

local function UpdateMinimapVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not p or not p.enabled then return end
    local vis = EvalVisibility(p)
    local minimap = Minimap
    if not minimap then return end
    if vis == "mouseover" then
        minimap:SetAlpha(0)
        minimap:Show()
    elseif vis then
        minimap:SetAlpha(1)
        minimap:Show()
    else
        minimap:Hide()
    end
end

local function UpdateFriendsVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled then return end
    if not FriendsFrame or not FriendsFrame:IsShown() then return end
    local vis = EvalVisibility(p)
    if vis == "mouseover" then
        FriendsFrame:SetAlpha(0)
    else
        FriendsFrame:SetAlpha(vis and 1 or 0)
    end
end

local function UpdateAllVisibility()
    UpdateChatVisibility()
    UpdateMinimapVisibility()
    UpdateFriendsVisibility()
    if _G._EBS_UpdateQTVisibility then _G._EBS_UpdateQTVisibility() end
    if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
    RebuildMouseoverTargets()
end

-- Expose globals for options/quest tracker/cursor
_G._EBS_InCombat = function() return _ebsInCombat end
_G._EBS_UpdateVisibility = UpdateAllVisibility
_G._EBS_EvalVisibility = EvalVisibility

local visFrame = CreateFrame("Frame")
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        _ebsInCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _ebsInCombat = false
    end
    C_Timer.After(0, UpdateAllVisibility)
end)

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyChat()
    ApplyMinimap()
    ApplyFriends()
    C_Timer.After(0, UpdateAllVisibility)
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIBasicsDB", defaults)

    -- Migrate old hideButtons → individual keys
    local mp = EBS.db.profile.minimap
    if mp.hideButtons ~= nil then
        if mp.hideButtons == true then
            mp.hideZoomButtons    = true
            mp.hideTrackingButton = true
            mp.hideGameTime       = true
        else
            mp.hideZoomButtons    = false
            mp.hideTrackingButton = false
            mp.hideGameTime       = false
        end
        mp.hideButtons = nil
    end

    -- Global bridge for options ↔ main communication
    _G._EBS_AceDB        = EBS.db
    _G._EBS_ApplyAll     = ApplyAll
    _G._EBS_ApplyChat    = ApplyChat
    _G._EBS_ApplyMinimap = ApplyMinimap
    _G._EBS_ApplyFriends = ApplyFriends
end

function EBS:OnEnable()
    ApplyAll()

    -- Hook FriendsFrame for load-on-demand
    if not FriendsFrame then
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(self, event, addon)
            if addon == "Blizzard_SocialUI" then
                C_Timer.After(0.1, function()
                    if FriendsFrame and EBS.db.profile.friends.enabled then
                        SkinFriendsFrame()
                    end
                end)
            end
        end)

        -- Also hook ShowUIPanel as a fallback
        if ShowUIPanel then
            hooksecurefunc("ShowUIPanel", function(frame)
                if frame == FriendsFrame and not friendsSkinned then
                    C_Timer.After(0, function()
                        if EBS.db.profile.friends.enabled then
                            SkinFriendsFrame()
                        end
                    end)
                end
            end)
        end
    else
        SkinFriendsFrame()
    end
end
