--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--
--  All legacy migrations have been removed. The beta-exit wipe (reset
--  version 5) guarantees every user starts from a clean slate.
--------------------------------------------------------------------------------

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    -- Perform the full wipe for users updating from beta builds.
    -- This runs before child addons init so they see a clean DB.
    EllesmereUI.PerformResetWipe()
end)
