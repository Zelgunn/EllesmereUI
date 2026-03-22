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
            enabled       = false,
            bgAlpha       = 0.6,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            fontSize      = 14,
            hideButtons   = false,
            hideTabFlash  = false,
            position      = nil,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
            fontFace           = nil,
            fontOutline        = "",
            fontShadow         = true,
            classColorNames    = true,
            clickableURLs      = true,
            shortenChannels    = "off",
            timestamps         = "none",
            messageFadeEnabled = true,
            messageFadeTime    = 120,
            messageSpacing     = 0,
            copyButton         = false,
            copyLines          = 200,
            showSearchButton   = true,
        },
        minimap = {
            enabled       = false,
            shape         = "square",
            borderSize    = 1,
            showCoords    = false,
            coordPrecision = 0,
            scale         = 1.0,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
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
            bgAlpha              = 0.7,
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
            showPreyQuests       = true,
            preyCollapsed        = false,
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

local function StripBlizzardChat(chatFrame)
    if chatFrame._ebsStripped then return end
    chatFrame._ebsStripped = true
    local name = chatFrame:GetName()
    if not name then return end

    -- Strip tab textures
    local tab = _G[name .. "Tab"]
    if tab then
        local tabTexSuffixes = {
            "Left", "Middle", "Right",
            "SelectedLeft", "SelectedMiddle", "SelectedRight",
            "ActiveLeft", "ActiveMiddle", "ActiveRight",
            "HighlightLeft", "HighlightMiddle", "HighlightRight",
        }
        for _, suffix in ipairs(tabTexSuffixes) do
            local tex = _G[name .. "Tab" .. suffix] or (tab[suffix])
            if tex and tex.SetTexture then tex:SetTexture(nil) end
        end
        -- Strip tab glow/flash textures
        if tab.glow then tab.glow:SetTexture(nil) end
        if tab.leftGlow then tab.leftGlow:SetTexture(nil) end
        if tab.rightGlow then tab.rightGlow:SetTexture(nil) end
    end

    -- Strip edit box Blizzard borders
    local editBox = _G[name .. "EditBox"]
    if editBox then
        for _, suffix in ipairs({"Left", "Mid", "Right"}) do
            local tex = _G[name .. "EditBox" .. suffix]
            if tex then tex:SetTexture(nil); tex:SetAlpha(0) end
        end
        if editBox.focusLeft then editBox.focusLeft:SetAlpha(0) end
        if editBox.focusRight then editBox.focusRight:SetAlpha(0) end
        if editBox.focusMid then editBox.focusMid:SetAlpha(0) end
        -- Also try named focus textures
        local fl = _G[name .. "EditBoxFocusLeft"]
        local fr = _G[name .. "EditBoxFocusRight"]
        local fm = _G[name .. "EditBoxFocusMid"]
        if fl then fl:SetAlpha(0) end
        if fr then fr:SetAlpha(0) end
        if fm then fm:SetAlpha(0) end
    end

    -- Strip button frame background
    local btnBg = _G[name .. "ButtonFrameBackground"]
    if btnBg then btnBg:SetAlpha(0) end
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then btnFrame:SetAlpha(0) end

    -- Hide scroll bar and scroll-to-bottom button
    if chatFrame.ScrollBar then chatFrame.ScrollBar:SetAlpha(0) end
    if chatFrame.ScrollToBottomButton then chatFrame.ScrollToBottomButton:SetAlpha(0) end

    -- Strip any remaining frame background textures
    local bg = _G[name .. "Background"]
    if bg then bg:SetAlpha(0) end

    -- Disable chat frame clamping so unlock mode can position freely
    chatFrame:SetClampedToScreen(false)
end

local function SkinChatFrame(chatFrame, p)
    if not chatFrame then return end
    local name = chatFrame:GetName()
    if not name then return end

    -- Strip all Blizzard decoration first
    StripBlizzardChat(chatFrame)

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

    -- Restore saved position (managed by unlock mode)
    local cf1 = ChatFrame1
    if cf1 and p.position then
        cf1:SetUserPlaced(true)
        cf1:ClearAllPoints()
        cf1:SetPoint(p.position.point, UIParent, p.position.relPoint, p.position.x, p.position.y)
    end
end

-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
    "MinimapBackdrop",
    "MinimapNorthTag",
    "MinimapCompassTexture",
    "TimeManagerClockButton",
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

-- Forward declarations for flyout system
local addonButtonPoll = nil
local cachedAddonButtons = {}
local flyoutOwnedFrames = {}

-------------------------------------------------------------------------------
--  Minimap Button Flyout
-------------------------------------------------------------------------------
local flyoutToggle = nil   -- the square trigger button
local flyoutPanel  = nil   -- the popup grid container
local flyoutSavedParents = {}  -- original parent/point data for restore
local flyoutSavedRegions = {}  -- original region states for restore

local FLYOUT_BTN_SIZE = 21
local FLYOUT_PADDING  = 4
local FLYOUT_COLS     = 4

-- Textures that are decorative borders/backgrounds on minimap buttons
local MINIMAP_BTN_JUNK = {
    [136467] = true,  -- UI-Minimap-Background
    [136430] = true,  -- MiniMap-TrackingBorder
    [136477] = true,  -- UI-Minimap-ZoomButton-Highlight (used on some buttons)
}
local MINIMAP_BTN_JUNK_PATH = {
    ["Interface\\Minimap\\MiniMap%-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-Background"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-ZoomButton%-Highlight"] = true,
}

local function IsJunkTexture(region)
    if not region or not region.IsObjectType or not region:IsObjectType("Texture") then
        return false
    end
    local texID = region.GetTextureFileID and region:GetTextureFileID()
    if texID and MINIMAP_BTN_JUNK[texID] then return true end
    local texPath = region:GetTexture()
    if texPath and type(texPath) == "string" then
        for pattern in pairs(MINIMAP_BTN_JUNK_PATH) do
            if texPath:match(pattern) then return true end
        end
    end
    return false
end

local function StripButtonDecorations(btn)
    local saved = {}
    for _, region in ipairs({ btn:GetRegions() }) do
        if IsJunkTexture(region) then
            saved[#saved + 1] = { region = region, alpha = region:GetAlpha(), shown = region:IsShown() }
            region:SetAlpha(0)
            region:Hide()
        end
    end
    -- Also hide highlight/pushed overlays that have junk textures
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and IsJunkTexture(hl) then
        saved[#saved + 1] = { region = hl, alpha = hl:GetAlpha(), shown = hl:IsShown() }
        hl:SetAlpha(0)
        hl:Hide()
    end
    flyoutSavedRegions[btn] = saved
end

local function RestoreButtonDecorations(btn)
    local saved = flyoutSavedRegions[btn]
    if not saved then return end
    for _, info in ipairs(saved) do
        info.region:SetAlpha(info.alpha)
        if info.shown then info.region:Show() end
    end
    flyoutSavedRegions[btn] = nil
end

local function CollectFlyoutButtons()
    -- Return all collected minimap buttons (populated by GatherMinimapButtons)
    local collected = {}
    for _, btn in ipairs(cachedAddonButtons) do
        collected[#collected + 1] = btn
    end
    return collected
end

local function LayoutFlyoutButtons()
    if not flyoutPanel then return end
    local buttons = CollectFlyoutButtons()
    local count = #buttons
    if count == 0 then
        flyoutPanel:SetSize(1, 1)
        return
    end

    local cols = math.min(count, FLYOUT_COLS)
    local rows = math.ceil(count / cols)
    local pw = FLYOUT_PADDING + cols * (FLYOUT_BTN_SIZE + FLYOUT_PADDING)
    local ph = FLYOUT_PADDING + rows * (FLYOUT_BTN_SIZE + FLYOUT_PADDING)
    flyoutPanel:SetSize(pw, ph)

    for i, btn in ipairs(buttons) do
        -- Save original parent/points for restore
        if not flyoutSavedParents[btn] then
            local p1, rel, p2, ox, oy = btn:GetPoint(1)
            flyoutSavedParents[btn] = {
                parent = btn:GetParent(),
                strata = btn:GetFrameStrata(),
                point = p1, relTo = rel, relPoint = p2, x = ox, y = oy,
            }
        end

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local xOff = FLYOUT_PADDING + col * (FLYOUT_BTN_SIZE + FLYOUT_PADDING)
        local yOff = -(FLYOUT_PADDING + row * (FLYOUT_BTN_SIZE + FLYOUT_PADDING))

        btn:SetParent(flyoutPanel)
        -- Unlock fixed strata/level first (LibDBIcon locks these)
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetFrameStrata("DIALOG")
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", flyoutPanel, "TOPLEFT", xOff, yOff)
        btn:SetSize(FLYOUT_BTN_SIZE, FLYOUT_BTN_SIZE)
        btn:SetAlpha(1)
        btn:Show()
        btn:SetFrameLevel(flyoutPanel:GetFrameLevel() + 5)
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
        -- Strip decorative border/background textures
        StripButtonDecorations(btn)
        -- Also force all child frames up to the same strata/level
        for _, child in ipairs({ btn:GetChildren() }) do
            child:SetFrameStrata("DIALOG")
            child:SetFrameLevel(flyoutPanel:GetFrameLevel() + 6)
        end
        -- Normalize icon region to fill the button cleanly
        local icon = btn.icon or btn.Icon
        if not icon then
            for _, region in ipairs({ btn:GetRegions() }) do
                if region:IsObjectType("Texture") and region:IsShown()
                   and region:GetAlpha() > 0 and not IsJunkTexture(region) then
                    icon = region
                    break
                end
            end
        end
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        end
        -- Add atlas ring border overlay
        if not btn._flyoutRing then
            local ring = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("AdventureMap-combatally-ring")
            ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
            ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
            btn._flyoutRing = ring
        end
        btn._flyoutRing:Show()
    end
end

local function RestoreFlyoutButtons()
    for btn, saved in pairs(flyoutSavedParents) do
        RestoreButtonDecorations(btn)
        if btn._flyoutRing then btn._flyoutRing:Hide() end
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetParent(saved.parent)
        btn:SetFrameStrata(saved.strata)
        btn:ClearAllPoints()
        if saved.point and saved.relTo then
            btn:SetPoint(saved.point, saved.relTo, saved.relPoint, saved.x, saved.y)
        end
        -- Re-hide on the minimap surface
        btn:Hide()
        btn:SetAlpha(0)
    end
    wipe(flyoutSavedParents)
end

local function ShowFlyoutPanel()
    if not flyoutPanel then
        flyoutPanel = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "TOPLEFT", 0, 2)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
    end
    LayoutFlyoutButtons()
    flyoutPanel:Show()
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        RestoreFlyoutButtons()
    end
end

local function ToggleFlyoutPanel()
    if flyoutPanel and flyoutPanel:IsShown() then
        HideFlyoutPanel()
    else
        ShowFlyoutPanel()
    end
end

local function CreateFlyoutToggle()
    if flyoutToggle then return flyoutToggle end

    local btn = CreateFrame("Button", nil, Minimap)
    btn:SetSize(24, 24)
    btn:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 4, 4)
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = btn:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    btn:SetNormalTexture(norm)

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    btn:SetPushedTexture(pushed)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Map-Filter-Button")
    hl:SetAlpha(0.3)
    btn:SetHighlightTexture(hl)

    btn:SetScript("OnClick", ToggleFlyoutPanel)

    flyoutToggle = btn
    flyoutOwnedFrames[btn] = true
    return btn
end

local coordFrame, coordTicker
local clockFrame, clockTicker, clockBg
local locationFrame, locationBg

local function GetMinimapFont()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "OUTLINE"
    return path, flag
end

local function ApplyMinimapFont(fs, size)
    local path, flag = GetMinimapFont()
    fs:SetFont(path, size, flag)
    if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function UpdateClock()
    if not clockFrame then return end
    local p = EBS.db and EBS.db.profile.minimap
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
    local p = EBS.db and EBS.db.profile.minimap
    local prec = p and p.coordPrecision or 1
    local fmtStr = format("%%.%df, %%.%df", prec, prec)
    coordFrame:SetText(format(fmtStr, x * 100, y * 100))
end

local function UpdateLocation()
    if not locationFrame then return end
    if InCombatLockdown() then return end
    local sub = GetSubZoneText()
    if sub and sub ~= "" then
        locationFrame:SetText(sub)
    else
        locationFrame:SetText(GetZoneText() or "")
    end
    if locationBg then
        local tw = locationFrame:GetStringWidth() or 0
        locationBg:SetSize(tw + 20, 18)
    end
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

-- Blizzard structural frames that should NOT go into the flyout
local flyoutBlacklist = {
    MinimapZoomIn    = true,
    MinimapZoomOut   = true,
    MinimapBackdrop  = true,
}

-- Persistently hide a minimap button via Show hook
local addonButtonHooks = {}

local function HideMinimapChild(btn)
    btn:Hide()
    btn:SetAlpha(0)
    if not addonButtonHooks[btn] then
        hooksecurefunc(btn, "Show", function(self)
            -- Allow showing when parented to the flyout panel
            if self:GetParent() == flyoutPanel then return end
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if mp and mp.enabled and not flyoutOwnedFrames[self] then
                self:Hide()
                self:SetAlpha(0)
            end
        end)
        addonButtonHooks[btn] = true
    end
end

local function ShowMinimapChild(btn)
    btn:SetAlpha(1)
    btn:Show()
end

-- Gather all minimap buttons (Blizzard + addon) into cachedAddonButtons
local function GatherMinimapButtons()
    wipe(cachedAddonButtons)
    if not Minimap then return end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not flyoutOwnedFrames[child] then
            local name = child:GetName()
            -- Only collect actual buttons, skip blacklisted structural frames
            if child:IsObjectType("Button") and name and not flyoutBlacklist[name] then
                cachedAddonButtons[#cachedAddonButtons + 1] = child
            elseif not child:IsObjectType("Button") and name and name:match("^LibDBIcon10_") then
                -- LibDBIcon sometimes uses Frame instead of Button
                cachedAddonButtons[#cachedAddonButtons + 1] = child
            end
        end
    end
end

-- Hide all collected minimap buttons from the map surface
local function HideAllMinimapButtons()
    GatherMinimapButtons()
    for _, btn in ipairs(cachedAddonButtons) do
        HideMinimapChild(btn)
    end
end

local function ShowAllMinimapButtons()
    for _, btn in ipairs(cachedAddonButtons) do
        ShowMinimapChild(btn)
    end
    wipe(cachedAddonButtons)
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
        -- Restore cluster header
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Show()
        end
        if MinimapCluster and MinimapCluster.Tracking then
            MinimapCluster.Tracking:Show()
        end
        -- Restore circular mask
        minimap:SetMaskTexture(186178)
        -- Hide our background & border
        if minimap._ebsBg then minimap._ebsBg:SetAlpha(0) end
        if minimap._ppBorders then PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        -- Reset scale
        minimap:SetScale(1.0)
        -- Tear down flyout and restore all buttons
        HideFlyoutPanel()
        if flyoutToggle then flyoutToggle:Hide() end
        ShowAllMinimapButtons()
        if addonButtonPoll then
            addonButtonPoll:Hide()
            addonButtonPoll:UnregisterAllEvents()
        end
        -- Restore zone text
        local zoneBtn = MinimapZoneTextButton
        if zoneBtn then zoneBtn:Show() end
        if MinimapCluster and MinimapCluster.ZoneTextButton then
            MinimapCluster.ZoneTextButton:Show()
        end
        if MinimapZoneText then MinimapZoneText:Show() end
        if coordFrame then coordFrame:Hide() end
        if coordTicker then coordTicker:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockBg then clockBg:Hide() end
        if clockTicker then clockTicker:Hide() end
        if locationFrame then locationFrame:Hide() end
        if locationBg then locationBg:Hide() end
        minimap:EnableMouseWheel(false)
        CancelAutoZoom()
        return
    end

    -- Hide default decorations
    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end

    -- Hide cluster header bar (zone text + time + tracking above minimap)
    if MinimapCluster and MinimapCluster.BorderTop then
        MinimapCluster.BorderTop:Hide()
    end
    if MinimapCluster and MinimapCluster.Tracking then
        MinimapCluster.Tracking:Hide()
    end

    -- Shape mask (retail texture IDs: 130937 = square, 186178 = circle)
    if p.shape == "square" then
        minimap:SetMaskTexture(130937)
    else
        minimap:SetMaskTexture(186178)
    end

    -- Hide background (no black bg behind minimap)
    if minimap._ebsBg then minimap._ebsBg:SetAlpha(0) end

    -- Border (pixel perfect)
    local r, g, b = GetBorderColor(p)
    local bs = p.borderSize or 1
    if not minimap._ppBorders then
        PP.CreateBorder(minimap, r, g, b, 1, bs, "OVERLAY", 7)
    else
        PP.SetBorderColor(minimap, r, g, b, 1)
    end
    PP.SetBorderSize(minimap, bs)

    -- Scale
    minimap:SetScale(p.scale)

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()
    flyoutToggle:Show()

    -- Hide ALL minimap child frames from the map surface
    HideAllMinimapButtons()

    -- Poll for late-loading addons that attach buttons after ADDON_LOADED
    if not addonButtonPoll then
        addonButtonPoll = CreateFrame("Frame")
        addonButtonPoll:RegisterEvent("ADDON_LOADED")
        addonButtonPoll:SetScript("OnEvent", function()
            HideAllMinimapButtons()
        end)
    end
    addonButtonPoll:Show()

    -- Close the flyout if it was open (layout may have changed)
    HideFlyoutPanel()

    -- Hide Blizzard zone text (we use our own location bar)
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then zoneBtn:Hide() end
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapZoneText then MinimapZoneText:Hide() end

    -- Clock -- top center, text vertically centered on the top edge
    if p.showClock then
        if not clockBg then
            clockBg = CreateFrame("Button", nil, minimap, "BackdropTemplate")
            clockBg:SetSize(80, 16)
            clockBg:SetPoint("TOP", minimap, "TOP", 0, 7)
            clockBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            clockBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            clockBg:RegisterForClicks("AnyUp")
            clockBg:SetScript("OnClick", function()
                if ToggleTimeManager then ToggleTimeManager() end
            end)
        end
        if not clockFrame then
            clockFrame = clockBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(clockFrame, 10)
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
            clockFrame:SetTextColor(1, 1, 1, 0.9)
        end
        do
            local ar, ag, ab = GetBorderColor(p)
            clockBg:SetBackdropColor(ar, ag, ab, 1)
        end
        clockBg:Show()
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
        if clockBg then clockBg:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
    end

    -- Location bar -- bottom center, shows subzone/zone name
    if not p.hideZoneText then
        if not locationBg then
            locationBg = CreateFrame("Frame", nil, minimap, "BackdropTemplate")
            locationBg:SetSize(120, 18)
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", 0, -7)
            locationBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            locationBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            locationBg:RegisterEvent("ZONE_CHANGED")
            locationBg:RegisterEvent("ZONE_CHANGED_INDOORS")
            locationBg:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            locationBg:RegisterEvent("PLAYER_REGEN_ENABLED")
            locationBg:SetScript("OnEvent", function() UpdateLocation() end)
        end
        if not locationFrame then
            locationFrame = locationBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(locationFrame, 10)
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
            locationFrame:SetTextColor(1, 1, 1, 0.9)
        end
        do
            local ar, ag, ab = GetBorderColor(p)
            locationBg:SetBackdropColor(ar, ag, ab, 1)
        end
        locationBg:Show()
        locationFrame:Show()
        UpdateLocation()
    else
        if locationBg then locationBg:Hide() end
        if locationFrame then locationFrame:Hide() end
    end

    -- Coordinates -- top-right, only visible on hover
    if p.showCoords then
        if not coordFrame then
            coordFrame = minimap:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(coordFrame, 11)
            coordFrame:SetPoint("TOPRIGHT", minimap, "TOPRIGHT", -4, -4)
            coordFrame:SetTextColor(1, 1, 1, 0.9)
        end
        coordFrame:Hide()  -- hidden by default, shown on hover
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
        -- Hover scripts on minimap to show/hide coords
        if not minimap._ebsCoordsHooked then
            minimap:HookScript("OnEnter", function()
                if coordFrame then coordFrame:Show() end
            end)
            minimap:HookScript("OnLeave", function()
                if coordFrame then coordFrame:Hide() end
            end)
            minimap._ebsCoordsHooked = true
        end
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

    -- Restore saved position (managed by unlock mode)
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

    -- Migrate old hideButtons to individual keys
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

    -- Global bridge for options <-> main communication
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

    -- Register minimap with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local function MDB() return EBS.db and EBS.db.profile.minimap end
        local function CDB() return EBS.db and EBS.db.profile.chat end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EBS_Minimap",
                label = "Minimap",
                group = "Basics",
                order = 500,
                noResize = true,
                getFrame = function() return Minimap end,
                getSize  = function()
                    local s = Minimap:GetScale()
                    return Minimap:GetWidth() * s, Minimap:GetHeight() * s
                end,
                isHidden = function()
                    local m = MDB()
                    return not m or not m.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local m = MDB(); if not m then return end
                    m.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyMinimap()
                    end
                end,
                loadPos = function()
                    local m = MDB()
                    return m and m.position
                end,
                clearPos = function()
                    local m = MDB(); if not m then return end
                    m.position = nil
                end,
                applyPos = function()
                    ApplyMinimap()
                end,
            }),
            MK({
                key   = "EBS_Chat",
                label = "Chat",
                group = "Basics",
                order = 510,
                getFrame = function() return ChatFrame1 end,
                getSize  = function()
                    return ChatFrame1:GetWidth(), ChatFrame1:GetHeight()
                end,
                isHidden = function()
                    local c = CDB()
                    return not c or not c.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local c = CDB(); if not c then return end
                    c.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyChat()
                    end
                end,
                loadPos = function()
                    local c = CDB()
                    return c and c.position
                end,
                clearPos = function()
                    local c = CDB(); if not c then return end
                    c.position = nil
                end,
                applyPos = function()
                    ApplyChat()
                end,
            }),
        })
    end
end
