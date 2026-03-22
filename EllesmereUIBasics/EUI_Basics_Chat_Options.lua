-------------------------------------------------------------------------------
--  EUI_Basics_Chat_Options.lua
--  Extended chat options: font face, outline, shadow, class colors, URLs,
--  channel shortening, timestamps, message fade, spacing, copy, search.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local SECTION_ENHANCEMENTS = "ENHANCEMENTS"
local SECTION_FONT         = "FONT"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.Widgets then return end

    local db
    C_Timer.After(0, function() db = _G._EBS_AceDB end)

    local function DB()
        if not db then db = _G._EBS_AceDB end
        return db and db.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function RefreshChat()
        if _G._EBS_ApplyChat then _G._EBS_ApplyChat() end
    end

    ---------------------------------------------------------------------------
    --  Font dropdown values (built once, reused)
    ---------------------------------------------------------------------------
    local fontValues, fontOrder
    local function EnsureFontValues()
        if fontValues then return end
        fontValues = { ["__default"] = { text = "Default (unchanged)" } }
        fontOrder  = { "__default" }
        -- Add EUI bundled fonts
        local FONT_DIR = EllesmereUI.MEDIA_PATH and (EllesmereUI.MEDIA_PATH .. "fonts\\") or ""
        if EllesmereUI.FONT_ORDER then
            for _, name in ipairs(EllesmereUI.FONT_ORDER) do
                if name == "---" then
                    fontOrder[#fontOrder + 1] = "---"
                else
                    local path = (EllesmereUI.FONT_BLIZZARD and EllesmereUI.FONT_BLIZZARD[name])
                        or (FONT_DIR .. (EllesmereUI.FONT_FILES and EllesmereUI.FONT_FILES[name] or "Expressway.TTF"))
                    local displayName = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
                    fontValues[name] = { text = displayName, font = path }
                    fontOrder[#fontOrder + 1] = name
                end
            end
        end
        -- Append LibSharedMedia fonts
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(fontValues, fontOrder, { keyByName = true })
        end
    end

    ---------------------------------------------------------------------------
    --  Outline values
    ---------------------------------------------------------------------------
    local outlineValues = {
        [""]              = { text = "None" },
        ["OUTLINE"]       = { text = "Thin" },
        ["THICKOUTLINE"]  = { text = "Thick" },
    }
    local outlineOrder = { "", "OUTLINE", "THICKOUTLINE" }

    ---------------------------------------------------------------------------
    --  Channel shortening values
    ---------------------------------------------------------------------------
    local shortenValues = {
        ["off"]     = { text = "Off" },
        ["short"]   = { text = "Short (1. T)" },
        ["minimal"] = { text = "Minimal (T)" },
    }
    local shortenOrder = { "off", "short", "minimal" }

    ---------------------------------------------------------------------------
    --  Timestamp values
    ---------------------------------------------------------------------------
    local tsValues = {
        ["none"]         = { text = "Off" },
        ["HH:MM"]        = { text = "14:30" },
        ["HH:MM:SS"]     = { text = "14:30:45" },
        ["HH:MM AP"]     = { text = "2:30 PM" },
        ["HH:MM:SS AP"]  = { text = "2:30:45 PM" },
    }
    local tsOrder = { "none", "HH:MM", "HH:MM:SS", "HH:MM AP", "HH:MM:SS AP" }

    ---------------------------------------------------------------------------
    --  Builder: called from BuildChatPage in EUI_Basics_Options.lua
    ---------------------------------------------------------------------------
    function EllesmereUI._BuildExtendedChatOptions(parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EnsureFontValues()

        -- ─── FONT SECTION ───
        _, h = W:SectionHeader(parent, SECTION_FONT, y);  y = y - h

        -- Font Face | Font Outline
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Font Face",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              values=fontValues, order=fontOrder,
              getValue=function()
                  local c = ChatDB()
                  return (c and c.fontFace) or "__default"
              end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.fontFace = (v == "__default") and nil or v
                  RefreshChat()
              end },
            { type="dropdown", text="Font Outline",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              values=outlineValues, order=outlineOrder,
              getValue=function()
                  local c = ChatDB()
                  return (c and c.fontOutline) or ""
              end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.fontOutline = v
                  RefreshChat()
              end }
        );  y = y - h

        -- Font Shadow | Message Spacing
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Font Shadow",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.fontShadow end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.fontShadow = v
                  RefreshChat()
              end },
            { type="slider", text="Message Spacing", min=0, max=10, step=1,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.messageSpacing or 0 end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.messageSpacing = v
                  RefreshChat()
              end }
        );  y = y - h

        -- ─── ENHANCEMENTS SECTION ───
        _, h = W:SectionHeader(parent, SECTION_ENHANCEMENTS, y);  y = y - h

        -- Class Color Names | Clickable URLs
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Class Color Names",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.classColorNames end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.classColorNames = v
              end },
            { type="toggle", text="Clickable URLs",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.clickableURLs end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.clickableURLs = v
              end }
        );  y = y - h

        -- Channel Shortening | Timestamps
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Shorten Channels",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              values=shortenValues, order=shortenOrder,
              getValue=function()
                  local c = ChatDB()
                  return (c and c.shortenChannels) or "off"
              end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.shortenChannels = v
              end },
            { type="dropdown", text="Timestamps",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              values=tsValues, order=tsOrder,
              getValue=function()
                  local c = ChatDB()
                  return (c and c.timestamps) or "none"
              end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.timestamps = v
                  if _G._EBS_ApplyTimestamps then _G._EBS_ApplyTimestamps() end
              end }
        );  y = y - h

        -- Message Fade | Fade Time
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Message Fade",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.messageFadeEnabled end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.messageFadeEnabled = v
                  RefreshChat()
              end },
            { type="slider", text="Fade Time (seconds)", min=5, max=240, step=5,
              disabled=function()
                  local c = ChatDB()
                  return c and (not c.enabled or not c.messageFadeEnabled)
              end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.messageFadeTime or 120 end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.messageFadeTime = v
                  RefreshChat()
              end }
        );  y = y - h

        -- Copy Button | Search Button
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Copy Button",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.copyButton end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.copyButton = v
                  if _G._EBS_UpdateCopyButtons then _G._EBS_UpdateCopyButtons() end
              end },
            { type="toggle", text="Show Search Button",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.showSearchButton end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.showSearchButton = v
                  if _G._EBS_UpdateSearchButtons then _G._EBS_UpdateSearchButtons() end
              end }
        );  y = y - h

        return math.abs(y) - math.abs(yOffset)
    end
end)
