-------------------------------------------------------------------------------
--  EllesmereUI_Profiles.lua
--
--  Global profile system: import/export, presets, spec assignment.
--  Handles serialization (LibDeflate + custom serializer) and profile
--  management across all EllesmereUI addons.
--
--  Load order (via TOC):
--    1. Libs/LibDeflate.lua
--    2. EllesmereUI_Lite.lua
--    3. EllesmereUI.lua
--    4. EllesmereUI_Widgets.lua
--    5. EllesmereUI_Presets.lua
--    6. EllesmereUI_Profiles.lua  -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  LibDeflate reference (loaded before us via TOC)
--  LibDeflate registers via LibStub, not as a global, so use LibStub to get it.
-------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub("LibDeflate", true) or _G.LibDeflate

-------------------------------------------------------------------------------
--  Reload popup: uses Blizzard StaticPopup so the button click is a hardware
--  event and ReloadUI() is not blocked as a protected function call.
-------------------------------------------------------------------------------
StaticPopupDialogs["EUI_PROFILE_RELOAD"] = {
    text = "EllesmereUI Profile switched. Reload UI to apply?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Addon registry: maps addon folder names to their DB accessor info.
--  Each entry: { svName, globalName, isFlat }
--    svName    = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--    globalName = global variable holding the AceDB object (e.g. "_ECME_AceDB")
--    isFlat    = true if the DB is a flat table (Nameplates), false if AceDB
--
--  Order matters for UI display.
-------------------------------------------------------------------------------
local ADDON_DB_MAP = {
    { folder = "EllesmereUINameplates",        display = "Nameplates",         svName = "EllesmereUINameplatesDB",        globalName = nil,            isFlat = true  },
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        svName = "EllesmereUIActionBarsDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        svName = "EllesmereUIUnitFramesDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   svName = "EllesmereUICooldownManagerDB",   globalName = "_ECME_AceDB",  isFlat = false },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      svName = "EllesmereUIResourceBarsDB",      globalName = "_ERB_AceDB",   isFlat = false },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", svName = "EllesmereUIAuraBuffRemindersDB", globalName = "_EABR_AceDB",  isFlat = false },
    { folder = "EllesmereUICursor",            display = "Cursor",             svName = "EllesmereUICursorDB",            globalName = "_ECL_AceDB",   isFlat = false },
}
EllesmereUI._ADDON_DB_MAP = ADDON_DB_MAP

-------------------------------------------------------------------------------
--  Serializer: Lua table <-> string (no AceSerializer dependency)
--  Handles: string, number, boolean, nil, table (nested), color tables
-------------------------------------------------------------------------------
local Serializer = {}

local function SerializeValue(v, parts)
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = "s"
        -- Length-prefixed to avoid delimiter issues
        parts[#parts + 1] = #v
        parts[#parts + 1] = ":"
        parts[#parts + 1] = v
    elseif t == "number" then
        parts[#parts + 1] = "n"
        parts[#parts + 1] = tostring(v)
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = v and "T" or "F"
    elseif t == "nil" then
        parts[#parts + 1] = "N"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        -- Serialize array part first (integer keys 1..n)
        local n = #v
        for i = 1, n do
            SerializeValue(v[i], parts)
        end
        -- Then hash part (non-integer keys, or integer keys > n)
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "number" and k >= 1 and k <= n and k == math.floor(k) then
                -- Already serialized in array part
            else
                parts[#parts + 1] = "K"
                SerializeValue(k, parts)
                SerializeValue(val, parts)
            end
        end
        parts[#parts + 1] = "}"
    end
end

function Serializer.Serialize(tbl)
    local parts = {}
    SerializeValue(tbl, parts)
    return table.concat(parts)
end

-- Deserializer
local function DeserializeValue(str, pos)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        -- Find the colon after the length
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local val = str:sub(colonPos + 1, colonPos + len)
        return val, colonPos + len + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "N" then
        return nil, pos + 1
    elseif tag == "{" then
        local tbl = {}
        local idx = 1
        local p = pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1
            elseif c == "K" then
                -- Key-value pair
                local key, val
                key, p = DeserializeValue(str, p + 1)
                val, p = DeserializeValue(str, p)
                if key ~= nil then
                    tbl[key] = val
                end
            else
                -- Array element
                local val
                val, p = DeserializeValue(str, p)
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return tbl, p
    end
    return nil, pos + 1
end

function Serializer.Deserialize(str)
    if not str or #str == 0 then return nil end
    local val, _ = DeserializeValue(str, 1)
    return val
end

EllesmereUI._Serializer = Serializer

-------------------------------------------------------------------------------
--  Deep copy utility
-------------------------------------------------------------------------------
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            DeepMerge(dst[k], v)
        else
            dst[k] = DeepCopy(v)
        end
    end
end

EllesmereUI._DeepCopy = DeepCopy




-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Default"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Default", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end
EllesmereUI.GetProfilesDB = GetProfilesDB

--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Re-point all db.profile references to the given profile name.
--- Called when switching profiles so addons see the new data immediately.
local function RepointAllDBs(profileName)
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end

    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not registry then return end
    -- Save CDM barGlows before repointing so it survives profile switches
    local savedBarGlows
    for _, db in ipairs(registry) do
        if db.folder == "EllesmereUICooldownManager" and db.profile then
            savedBarGlows = db.profile.barGlows
            break
        end
    end
    for _, db in ipairs(registry) do
        local folder = db.folder
        if folder then
            if type(profileData.addons[folder]) ~= "table" then
                profileData.addons[folder] = {}
            end
            db.profile = profileData.addons[folder]
            db._profileName = profileName
            -- Re-merge defaults so new profile has all keys
            if db._profileDefaults then
                EllesmereUI.Lite.DeepMergeDefaults(db.profile, db._profileDefaults)
            end
            -- Restore barGlows into the new profile
            if folder == "EllesmereUICooldownManager" and savedBarGlows then
                db.profile.barGlows = savedBarGlows
            end
        end
    end
    -- Restore flat addons (e.g. Nameplates) from the profile snapshot.
    -- Flat addons write directly to their global SV, so RepointAllDBs must
    -- overwrite the global with the target profile's stored snapshot.
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.isFlat then
            local snap = profileData.addons[entry.folder]
            local sv = _G[entry.svName]
            if sv and snap then
                for k in pairs(sv) do
                    if not k:match("^_") then sv[k] = nil end
                end
                for k, v in pairs(snap) do
                    if not k:match("^_") then sv[k] = DeepCopy(v) end
                end
            end
        end
    end
    -- Restore unlock layout from the profile
    if profileData.unlockLayout then
        local ul = profileData.unlockLayout
        EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors     or {})
        EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch  or {})
        EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch or {})
    end
    -- Restore fonts and custom colors from the profile
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
    end
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run).
--  At this point the spec API is available, so we can resolve the current
--  spec and re-point all db.profile references to the correct profile table
--  in the central store before any addon builds its UI.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  ADDON_LOADED handler: resolve which profile this character should use
--  and set EllesmereUIDB.activeProfile. NewDB reads directly from the
--  central store, so no injection into child SVs is needed.
-------------------------------------------------------------------------------
do
    local preSeedFrame = CreateFrame("Frame")
    preSeedFrame:RegisterEvent("ADDON_LOADED")
    preSeedFrame:SetScript("OnEvent", function(self, event, addonName)
        if addonName ~= "EllesmereUI" then return end
        self:UnregisterEvent("ADDON_LOADED")

        if not EllesmereUIDB then return end

        local specProfiles = EllesmereUIDB.specProfiles
        if not specProfiles then return end

        -- Resolve the current spec. Prefer the saved lastSpecByChar value
        -- (always reliable). If this is a new character with no saved entry,
        -- try GetSpecialization() live -- it is available at ADDON_LOADED
        -- time for returning characters and most new characters.
        local charKey = UnitName("player") .. " - " .. GetRealmName()
        if not EllesmereUIDB.lastSpecByChar then
            EllesmereUIDB.lastSpecByChar = {}
        end
        local lastSpecByChar = EllesmereUIDB.lastSpecByChar
        local resolvedSpecID = lastSpecByChar[charKey]

        if not resolvedSpecID then
            local specIdx = GetSpecialization and GetSpecialization()
            if specIdx and specIdx > 0 then
                local liveSpecID = GetSpecializationInfo(specIdx)
                if liveSpecID and specProfiles[liveSpecID] then
                    resolvedSpecID = liveSpecID
                    lastSpecByChar[charKey] = resolvedSpecID
                end
            end
        end

        if not resolvedSpecID or not specProfiles[resolvedSpecID] then
            if next(specProfiles) then
                EllesmereUI._profileSaveLocked = true
            end
            -- If activeProfile belongs to a spec assignment from another
            -- character, fall back to a safe default.
            local curActive = EllesmereUIDB.activeProfile
            local safe = curActive
            if curActive and next(specProfiles) then
                for _, pName in pairs(specProfiles) do
                    if pName == curActive then
                        safe = EllesmereUIDB.lastNonSpecProfile
                        if not safe or not (EllesmereUIDB.profiles or {})[safe] then
                            safe = "Default"
                        end
                        EllesmereUIDB.activeProfile = safe
                        break
                    end
                end
            end
            return
        end

        local targetProfile = specProfiles[resolvedSpecID]
        if not targetProfile then return end

        EllesmereUIDB.activeProfile = targetProfile
    end)
end

--- Called by EllesmereUI_Lite just before child addon OnEnable calls fire.
--- Resolves the current spec and re-points all db.profile references to
--- the correct profile table in the central store.
function EllesmereUI.PreSeedSpecProfile()
    if not EllesmereUIDB then return end
    local specProfiles = EllesmereUIDB.specProfiles
    if not specProfiles or not next(specProfiles) then return end

    local charKey = UnitName("player") .. " - " .. GetRealmName()

    if not EllesmereUIDB.lastSpecByChar then
        EllesmereUIDB.lastSpecByChar = {}
    end
    local lastSpecByChar = EllesmereUIDB.lastSpecByChar
    local resolvedSpecID = lastSpecByChar[charKey]

    if not resolvedSpecID then
        local specIdx = GetSpecialization and GetSpecialization()
        if specIdx and specIdx > 0 then
            local liveSpecID = GetSpecializationInfo(specIdx)
            if liveSpecID and specProfiles[liveSpecID] then
                resolvedSpecID = liveSpecID
                lastSpecByChar[charKey] = resolvedSpecID
            end
        end
    end

    if not resolvedSpecID or not specProfiles[resolvedSpecID] then
        if next(specProfiles) then
            EllesmereUI._profileSaveLocked = true
        end
        return
    end

    local targetProfile = specProfiles[resolvedSpecID]
    if not targetProfile then return end

    local profiles = EllesmereUIDB.profiles
    if not profiles or not profiles[targetProfile] then return end

    EllesmereUIDB.activeProfile = targetProfile
    RepointAllDBs(targetProfile)

    EllesmereUI._preSeedComplete = true
end

--- Get the live profile table for an addon.
--- In single-storage mode, non-flat addons read from the db registry
--- (which points into EllesmereUIDB.profiles[active].addons[folder]).
local function GetAddonProfile(entry)
    if entry.isFlat then
        return _G[entry.svName]
    end
    -- Look up from the Lite db registry (canonical source)
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder == entry.folder then
                return db.profile
            end
        end
    end
    -- Fallback: CDM globalName accessor
    local aceDB = entry.globalName and _G[entry.globalName]
    if aceDB and aceDB.profile then return aceDB.profile end
    return nil
end

--- Strip barGlows from a CDM addon snapshot (and from specProfiles entries).
--- barGlows is per-spec internal state that should never be in profile data.
local function StripCDMBarGlows(snapshot)
    if not snapshot or not snapshot.addons then return end
    local cdm = snapshot.addons["EllesmereUICooldownManager"]
    if not cdm then return end
    cdm.barGlows = nil
    if cdm.specProfiles then
        for _, sp in pairs(cdm.specProfiles) do
            if type(sp) == "table" then sp.barGlows = nil end
        end
    end
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                data.addons[entry.folder] = DeepCopy(profile)
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    -- Include unlock mode layout data (anchors, size matches)
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        }
    end
    -- barGlows is excluded from all profile data
    StripCDMBarGlows(data)
    return data
end

--- Snapshot a single addon's profile
function EllesmereUI.SnapshotAddon(folderName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == folderName and IsAddonLoaded(folderName) then
            local profile = GetAddonProfile(entry)
            if profile then return DeepCopy(profile) end
        end
    end
    return nil
end

--- Snapshot multiple addons (for multi-addon export)
function EllesmereUI.SnapshotAddons(folderList)
    local data = { addons = {} }
    for _, folderName in ipairs(folderList) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    data.addons[folderName] = DeepCopy(profile)
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    -- Include unlock mode layout data
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        }
    end
    -- barGlows is excluded from all profile data
    StripCDMBarGlows(data)
    return data
end

--- Apply imported profile data into the live db.profile tables.
--- Used by import to write external data into the active profile.
--- For normal profile switching, use SwitchProfile (which calls RepointAllDBs).
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end

    -- Build a folder -> db lookup from the Lite registry
    local dbByFolder = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder then dbByFolder[db.folder] = db end
        end
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            if entry.isFlat then
                local sv = _G[entry.svName]
                if sv then
                    for k in pairs(sv) do
                        if not k:match("^_") then sv[k] = nil end
                    end
                    for k, v in pairs(snap) do
                        if not k:match("^_") then sv[k] = DeepCopy(v) end
                    end
                end
            else
                local db = dbByFolder[entry.folder]
                if db then
                    local profile = db.profile
                    -- Preserve barGlows and specProfiles across CDM profile applies
                    local savedBarGlows, savedSpecProfiles
                    if entry.folder == "EllesmereUICooldownManager" then
                        savedBarGlows = profile.barGlows
                        savedSpecProfiles = profile.specProfiles
                    end
                    for k in pairs(profile) do profile[k] = nil end
                    for k, v in pairs(snap) do profile[k] = DeepCopy(v) end
                    if savedBarGlows then
                        profile.barGlows = savedBarGlows
                    end
                    if savedSpecProfiles then
                        profile.specProfiles = savedSpecProfiles
                    end
                    if db._profileDefaults then
                        EllesmereUI.Lite.DeepMergeDefaults(profile, db._profileDefaults)
                    end
                    -- Ensure per-unit bg colors are never nil after import
                    if entry.folder == "EllesmereUIUnitFrames" then
                        local UF_UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
                        local DEF_BG = 17/255
                        for _, uKey in ipairs(UF_UNITS) do
                            local s = profile[uKey]
                            if s and s.customBgColor == nil then
                                s.customBgColor = { r = DEF_BG, g = DEF_BG, b = DEF_BG }
                            end
                        end
                    end
                end
            end
        end
    end
    -- Apply fonts and colors
    do
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        if profileData.fonts then
            for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    do
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        if profileData.customColors then
            for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
        end
    end
    -- Restore unlock mode layout data
    if EllesmereUIDB then
        local ul = profileData.unlockLayout
        EllesmereUIDB.unlockAnchors     = ul and DeepCopy(ul.anchors)     or {}
        EllesmereUIDB.unlockWidthMatch  = ul and DeepCopy(ul.widthMatch)  or {}
        EllesmereUIDB.unlockHeightMatch = ul and DeepCopy(ul.heightMatch) or {}
    end
end

--- Trigger live refresh on all loaded addons after a profile apply.
function EllesmereUI.RefreshAllAddons()
    -- ResourceBars (full rebuild)
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM (full rebuild)
    if _G._ECME_Apply then _G._ECME_Apply() end
    -- Cursor (style + position)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders (refresh + position)
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end
    -- ActionBars (style + layout + position)
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames (style + layout + position)
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions (the absolute saved positions), resync anchor
    -- offsets so the anchor relationships stay correct for future drags.
    -- Double-deferred so it runs AFTER debounced rebuilds (e.g. UnitFrames
    -- OnUpdate throttle) have completed and frames are at final positions.
    if EllesmereUI.ResyncAnchorOffsets then
        C_Timer.After(0, function()
            C_Timer.After(0, EllesmereUI.ResyncAnchorOffsets)
        end)
    end
end

-------------------------------------------------------------------------------
--  Profile Keybinds
--  Each profile can have a key bound to switch to it instantly.
--  Stored in EllesmereUIDB.profileKeybinds = { ["Name"] = "CTRL-1", ... }
--  Uses hidden buttons + SetOverrideBindingClick, same pattern as Party Mode.
-------------------------------------------------------------------------------
local _profileBindBtns = {} -- [profileName] = hidden Button

local function GetProfileKeybinds()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profileKeybinds then EllesmereUIDB.profileKeybinds = {} end
    return EllesmereUIDB.profileKeybinds
end

local function EnsureProfileBindBtn(profileName)
    if _profileBindBtns[profileName] then return _profileBindBtns[profileName] end
    local safeName = profileName:gsub("[^%w]", "")
    local btn = CreateFrame("Button", "EllesmereUIProfileBind_" .. safeName, UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        local active = EllesmereUI.GetActiveProfileName()
        if active == profileName then return end
        local _, profiles = EllesmereUI.GetProfileList()
        local fontWillChange = EllesmereUI.ProfileChangesFont(profiles and profiles[profileName])
        EllesmereUI.SwitchProfile(profileName)
        EllesmereUI.RefreshAllAddons()
        if fontWillChange then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        else
            EllesmereUI:RefreshPage()
        end
    end)
    _profileBindBtns[profileName] = btn
    return btn
end

function EllesmereUI.SetProfileKeybind(profileName, key)
    local kb = GetProfileKeybinds()
    -- Clear old binding for this profile
    local oldKey = kb[profileName]
    local btn = EnsureProfileBindBtn(profileName)
    if oldKey then
        ClearOverrideBindings(btn)
    end
    if key then
        kb[profileName] = key
        SetOverrideBindingClick(btn, true, key, btn:GetName())
    else
        kb[profileName] = nil
    end
end

function EllesmereUI.GetProfileKeybind(profileName)
    local kb = GetProfileKeybinds()
    return kb[profileName]
end

--- Called on login to restore all saved profile keybinds
function EllesmereUI.RestoreProfileKeybinds()
    local kb = GetProfileKeybinds()
    for profileName, key in pairs(kb) do
        if key then
            local btn = EnsureProfileBindBtn(profileName)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    end
end

--- Update keybind references when a profile is renamed
function EllesmereUI.OnProfileRenamed(oldName, newName)
    local kb = GetProfileKeybinds()
    local key = kb[oldName]
    if key then
        local oldBtn = _profileBindBtns[oldName]
        if oldBtn then ClearOverrideBindings(oldBtn) end
        _profileBindBtns[oldName] = nil
        kb[oldName] = nil
        kb[newName] = key
        local newBtn = EnsureProfileBindBtn(newName)
        SetOverrideBindingClick(newBtn, true, key, newBtn:GetName())
    end
end

--- Clean up keybind when a profile is deleted
function EllesmereUI.OnProfileDeleted(profileName)
    local kb = GetProfileKeybinds()
    if kb[profileName] then
        local btn = _profileBindBtns[profileName]
        if btn then ClearOverrideBindings(btn) end
        _profileBindBtns[profileName] = nil
        kb[profileName] = nil
    end
end

--- Returns true if applying profileData would change the global font or outline mode.
--- Used to decide whether to show a reload popup after a profile switch.
function EllesmereUI.ProfileChangesFont(profileData)
    if not profileData or not profileData.fonts then return false end
    local cur = EllesmereUI.GetFontsDB()
    local curFont    = cur.global      or "Expressway"
    local curOutline = cur.outlineMode or "shadow"
    local newFont    = profileData.fonts.global      or "Expressway"
    local newOutline = profileData.fonts.outlineMode or "shadow"
    -- "none" and "shadow" are both drop-shadow (no outline) -- treat as identical
    if curOutline == "none" then curOutline = "shadow" end
    if newOutline == "none" then newOutline = "shadow" end
    return curFont ~= newFont or curOutline ~= newOutline
end

--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    if entry.isFlat then
                        local db = _G[entry.svName]
                        if db then
                            for k, v in pairs(snap) do
                                if not k:match("^_") then
                                    db[k] = DeepCopy(v)
                                end
                            end
                        end
                    else
                        for k, v in pairs(snap) do
                            -- barGlows is excluded from profile data
                            if not (folderName == "EllesmereUICooldownManager" and k == "barGlows") then
                                profile[k] = DeepCopy(v)
                            end
                        end
                    end
                end
                break
            end
        end
    end
    -- Always apply fonts and colors if present
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 2, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profileName == (db.activeProfile or "Default") then
        profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        profileData.unlockLayout = {
            anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        }
    end
    -- DeepCopy so we can strip barGlows without affecting the live store
    local exportData = DeepCopy(profileData)
    StripCDMBarGlows(exportData)
    local payload = { version = 2, type = "full", data = exportData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local sw, sh = GetPhysicalScreenSize()
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 2, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

-------------------------------------------------------------------------------
--  CDM spec profile helpers for export/import spec picker
-------------------------------------------------------------------------------

--- Get info about which specs have data in the CDM specProfiles table.
--- Returns: { { key="250", name="Blood", icon=..., hasData=true }, ... }
--- Includes ALL specs for the player's class, with hasData indicating
--- whether specProfiles contains data for that spec.
function EllesmereUI.GetCDMSpecInfo()
    local cdmProfile
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == "EllesmereUICooldownManager" then
            cdmProfile = GetAddonProfile(entry)
            break
        end
    end
    local specProfiles = cdmProfile and cdmProfile.specProfiles or {}
    local result = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, sName, _, sIcon = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            result[#result + 1] = {
                key     = key,
                name    = sName or ("Spec " .. key),
                icon    = sIcon,
                hasData = specProfiles[key] ~= nil,
            }
        end
    end
    return result
end

--- Filter specProfiles in a CDM addon snapshot to only include selected specs.
--- Modifies the snapshot in-place. selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.FilterExportSpecProfiles(snapshot, selectedSpecs)
    if not snapshot or not snapshot.addons then return end
    local cdmSnap = snapshot.addons["EllesmereUICooldownManager"]
    if not cdmSnap or not cdmSnap.specProfiles then return end
    for key in pairs(cdmSnap.specProfiles) do
        if not selectedSpecs[key] then
            cdmSnap.specProfiles[key] = nil
        end
    end
end

--- After a profile import, apply only selected specs' specProfiles from the
--- imported data into the live CDM profile. Non-selected specs are untouched.
--- importedCDMSnap = the CDM addon data from the imported profile.
--- selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.ApplyImportedSpecProfiles(importedCDMSnap, selectedSpecs)
    if not importedCDMSnap or not importedCDMSnap.specProfiles then return end
    local cdmProfile
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == "EllesmereUICooldownManager" then
            cdmProfile = GetAddonProfile(entry)
            break
        end
    end
    if not cdmProfile then return end
    if not cdmProfile.specProfiles then cdmProfile.specProfiles = {} end
    for key, data in pairs(importedCDMSnap.specProfiles) do
        if selectedSpecs[key] then
            cdmProfile.specProfiles[key] = DeepCopy(data)
        end
    end
    -- If the current spec was imported, reload it live
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and selectedSpecs[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
        end
    end
end

--- Get the list of spec keys that have data in an imported CDM snapshot.
--- Returns same format as GetCDMSpecInfo but based on imported data.
function EllesmereUI.GetImportedCDMSpecInfo(importedCDMSnap)
    if not importedCDMSnap or not importedCDMSnap.specProfiles then return {} end
    local result = {}
    for specKey in pairs(importedCDMSnap.specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key     = specKey,
            name    = name or ("Spec " .. specKey),
            icon    = icon,
            hasData = true,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

-------------------------------------------------------------------------------
--  CDM Spec Picker Popup
--  Thin wrapper around ShowSpecAssignPopup for CDM export/import.
--
--  opts = {
--      title    = string,
--      subtitle = string,
--      confirmText = string (button label),
--      specs    = { { key, name, icon, hasData, checked }, ... },
--      onConfirm = function(selectedSpecs)  -- { ["250"]=true, ... }
--      onCancel  = function() (optional)
--  }
--  specs[i].hasData = false grays out the row and shows disabled tooltip.
--  specs[i].checked = initial checked state (only for hasData=true rows).
-------------------------------------------------------------------------------
do
    -- Dummy db/dbKey/presetKey for the assignments table
    local dummyDB = { _cdmPick = { _cdm = {} } }

    function EllesmereUI:ShowCDMSpecPickerPopup(opts)
        local specs = opts.specs or {}

        -- Reset assignments
        dummyDB._cdmPick._cdm = {}

        -- Build a set of specIDs that are in the caller's list
        local knownSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then knownSpecs[numID] = sp end
        end

        -- Build disabledSpecs map (specID -> tooltip string)
        -- Any spec NOT in the caller's list gets disabled too
        local disabledSpecs = {}
        -- Build preCheckedSpecs set
        local preCheckedSpecs = {}

        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then
                if not sp.hasData then
                    disabledSpecs[numID] = "Create a CDM spell layout for this spec first"
                end
                if sp.checked then
                    preCheckedSpecs[numID] = true
                end
            end
        end

        -- Disable all specs not in the caller's list (other classes, etc.)
        local SPEC_DATA = EllesmereUI._SPEC_DATA
        if SPEC_DATA then
            for _, cls in ipairs(SPEC_DATA) do
                for _, spec in ipairs(cls.specs) do
                    if not knownSpecs[spec.id] then
                        disabledSpecs[spec.id] = "Not available for this operation"
                    end
                end
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = disabledSpecs,
            preCheckedSpecs = preCheckedSpecs,
            onConfirm       = opts.onConfirm and function(assignments)
                -- Convert numeric specID assignments back to string keys
                local selected = {}
                for specID in pairs(assignments) do
                    selected[tostring(specID)] = true
                end
                opts.onConfirm(selected)
            end,
            onCancel        = opts.onCancel,
        })
    end
end

function EllesmereUI.ExportCurrentProfile(selectedSpecs)
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- Filter CDM specProfiles to only include selected specs
    if selectedSpecs then
        EllesmereUI.FilterExportSpecProfiles(profileData, selectedSpecs)
    end
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 2, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect old CDM bar layout strings (format removed in 5.1.2)
    if importStr:sub(1, 9) == "!EUICDM_" then
        return nil, "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
    end
    if importStr:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "Not a valid EllesmereUI string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#EXPORT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if not payload.version or payload.version < 2 then
        return nil, "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
    end
    if payload.version > 2 then
        return nil, "This profile was created with a newer version of EllesmereUI. Please update your addon."
    end
    return payload, nil
end

--- Reset class-dependent fill colors in Resource Bars after a profile import.
--- The exporter's class color may be baked into fillR/fillG/fillB; this
--- resets them to the importer's own class/power colors and clears
--- customColored so the bars use runtime class color lookup.
local function FixupImportedClassColors()
    local rbEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUIResourceBars" then rbEntry = e; break end
    end
    if not rbEntry or not IsAddonLoaded(rbEntry.folder) then return end
    local profile = GetAddonProfile(rbEntry)
    if not profile then return end

    local _, classFile = UnitClass("player")
    -- CLASS_COLORS and POWER_COLORS are local to ResourceBars, so we
    -- use the same lookup the addon uses at init time.
    local classColors = EllesmereUI.CLASS_COLOR_MAP
    local cc = classColors and classColors[classFile]

    -- Health bar: reset to importer's class color
    if profile.health and not profile.health.darkTheme then
        profile.health.customColored = false
        if cc then
            profile.health.fillR = cc.r
            profile.health.fillG = cc.g
            profile.health.fillB = cc.b
        end
    end
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function EllesmereUI.ImportProfile(importStr, profileName)
    local payload, err = EllesmereUI.DecodeImportString(importStr)
    if not payload then return false, err end

    local db = GetProfilesDB()

    if payload.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Check if current spec has an assigned profile (blocks auto-apply)
    local specLocked = false
    do
        local si = GetSpecialization and GetSpecialization() or 0
        local sid = si and si > 0 and GetSpecializationInfo(si) or nil
        if sid then
            local assigned = db.specProfiles and db.specProfiles[sid]
            if assigned then specLocked = true end
        end
    end

    if payload.type == "full" then
        -- Full profile: store as a new named profile
        local stored = DeepCopy(payload.data)
        -- specProfiles are per-spec, not per-profile; strip from stored data
        -- (the caller handles selective import via ApplyImportedSpecProfiles)
        if stored.addons and stored.addons["EllesmereUICooldownManager"] then
            stored.addons["EllesmereUICooldownManager"].specProfiles = nil
        end
        db.profiles[profileName] = stored
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        -- Make it the active profile and re-point db references
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Apply imported data into the live db.profile tables
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- No re-snapshot needed: fixup wrote directly to the central store
        return true, nil
    elseif payload.type == "partial" then
        -- Partial: deep-copy current profile, overwrite the imported addons
        local current = db.activeProfile or "Default"
        local currentData = db.profiles[current]
        local merged = currentData and DeepCopy(currentData) or {}
        if not merged.addons then merged.addons = {} end
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                local copy = DeepCopy(snap)
                -- specProfiles are per-spec, not per-profile
                if folder == "EllesmereUICooldownManager" and type(copy) == "table" then
                    copy.specProfiles = nil
                end
                merged.addons[folder] = copy
            end
        end
        if payload.data.fonts then
            merged.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            merged.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        db.profiles[profileName] = merged
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        EllesmereUI.ApplyProfileData(merged)
        FixupImportedClassColors()
        return true, nil
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    local current = db.activeProfile or "Default"
    local src = db.profiles[current]
    -- Deep-copy the current profile into the new name
    local copy = src and DeepCopy(src) or {}
    -- Ensure fonts/colors/unlock layout are current
    copy.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    copy.unlockLayout = {
        anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
        widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
        heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
    }
    db.profiles[name] = copy
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    -- Switch to the new profile using the standard path so the outgoing
    -- profile's state is properly saved before repointing.
    EllesmereUI.SwitchProfile(name)
end

function EllesmereUI.DeleteProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == name then table.remove(db.profileOrder, i); break end
    end
    -- Clean up spec assignments
    for specID, pName in pairs(db.specProfiles) do
        if pName == name then db.specProfiles[specID] = nil end
    end
    -- Clean up keybind
    EllesmereUI.OnProfileDeleted(name)
    -- If deleted profile was active, fall back to Default
    if db.activeProfile == name then
        db.activeProfile = "Default"
        RepointAllDBs("Default")
    end
end

function EllesmereUI.RenameProfile(oldName, newName)
    local db = GetProfilesDB()
    if not db.profiles[oldName] then return end
    db.profiles[newName] = db.profiles[oldName]
    db.profiles[oldName] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == oldName then db.profileOrder[i] = newName; break end
    end
    for specID, pName in pairs(db.specProfiles) do
        if pName == oldName then db.specProfiles[specID] = newName end
    end
    if db.activeProfile == oldName then
        db.activeProfile = newName
        RepointAllDBs(newName)
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    if not db.profiles[name] then return end
    -- Save current fonts/colors into the outgoing profile before switching
    local outgoing = db.profiles[db.activeProfile or "Default"]
    if outgoing then
        outgoing.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        outgoing.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        -- Save unlock layout into outgoing profile
        outgoing.unlockLayout = {
            anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        }
        -- Save flat addon data into outgoing profile
        if not outgoing.addons then outgoing.addons = {} end
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.isFlat and IsAddonLoaded(entry.folder) then
                local sv = _G[entry.svName]
                if sv then
                    outgoing.addons[entry.folder] = DeepCopy(sv)
                end
            end
        end
    end
    db.activeProfile = name
    RepointAllDBs(name)
end

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Default"
end

function EllesmereUI.GetProfileList()
    local db = GetProfilesDB()
    return db.profileOrder, db.profiles
end

function EllesmereUI.AssignProfileToSpec(profileName, specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = profileName
end

function EllesmereUI.UnassignSpec(specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = nil
end

function EllesmereUI.GetSpecProfile(specID)
    local db = GetProfilesDB()
    return db.specProfiles[specID]
end

-------------------------------------------------------------------------------
--  AutoSaveActiveProfile: no-op in single-storage mode.
--  Addons write directly to EllesmereUIDB.profiles[active].addons[folder],
--  so there is nothing to snapshot. Kept as a stub so existing call sites
--  (keybind buttons, options panel hooks) do not error.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    -- Intentionally empty: single-storage means data is always in sync.
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    local lastKnownCharKey = nil
    local pendingReload = false
    local pendingFontCheck = nil
    local specRetryTimer = nil  -- retry handle for new characters

    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        -- Deferred reload: fire once combat ends
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingReload then
                pendingReload = false
                EllesmereUI.RefreshAllAddons()
                if pendingFontCheck then
                    pendingFontCheck = nil
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Reload Required",
                        message     = "Font changed. A UI reload is needed to apply the new font.",
                        confirmText = "Reload Now",
                        cancelText  = "Later",
                        onConfirm   = function() ReloadUI() end,
                    })
                end
            end
            return
        end

        -- PLAYER_ENTERING_WORLD has no unit arg; PLAYER_SPECIALIZATION_CHANGED
        -- fires with "player" as unit. For PEW, always check current spec.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil
        if not specID then
            -- Spec info not available yet (common on brand new characters).
            -- Start a short polling retry so we can re-assign the correct
            -- profile once the server sends spec data. By the time the
            -- retry fires, all addons have already built their UI, so we
            -- do a full SwitchProfile + RefreshAllAddons (not the deferred
            -- first-login path which skips refresh).
            if not specRetryTimer and (lastKnownSpecID == nil) then
                local attempts = 0
                specRetryTimer = C_Timer.NewTicker(1, function(ticker)
                    attempts = attempts + 1
                    local idx = GetSpecialization and GetSpecialization() or 0
                    local sid = idx and idx > 0
                        and GetSpecializationInfo(idx) or nil
                    if sid then
                        ticker:Cancel()
                        specRetryTimer = nil
                        -- Record the spec so future events use the fast path
                        lastKnownSpecID = sid
                        local ck = UnitName("player") .. " - " .. GetRealmName()
                        lastKnownCharKey = ck
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.lastSpecByChar then
                            EllesmereUIDB.lastSpecByChar = {}
                        end
                        EllesmereUIDB.lastSpecByChar[ck] = sid
                        EllesmereUI._profileSaveLocked = false
                        -- Resolve the target profile for this spec
                        local pdb = GetProfilesDB()
                        local target = pdb.specProfiles[sid]
                        if target and pdb.profiles[target] then
                            local cur = pdb.activeProfile or "Default"
                            if cur ~= target then
                                local fontChange = EllesmereUI.ProfileChangesFont(
                                    pdb.profiles[target])
                                EllesmereUI.SwitchProfile(target)
                                EllesmereUI.RefreshAllAddons()
                                if fontChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                end
                            end
                        end
                    elseif attempts >= 10 then
                        ticker:Cancel()
                        specRetryTimer = nil
                    end
                end)
            end
            return
        end
        -- Spec resolved -- cancel any pending retry
        if specRetryTimer then
            specRetryTimer:Cancel()
            specRetryTimer = nil
        end

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        local isFirstLogin = (lastKnownSpecID == nil)
        -- charChanged is true when the active character is different from the
        -- last session (alt-swap). On a plain /reload the charKey stays the same.
        local charChanged = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= charKey)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), skip if same character
        -- and same spec -- a plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and not charChanged and specID == lastKnownSpecID then
                return -- same char, same spec, nothing to do
            end
        end
        lastKnownSpecID = specID
        lastKnownCharKey = charKey

        -- Persist the current spec so the pre-seed logic at ADDON_LOADED
        -- can guarantee the correct profile is loaded on next login.
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.lastSpecByChar then EllesmereUIDB.lastSpecByChar = {} end
        EllesmereUIDB.lastSpecByChar[charKey] = specID

        -- Spec resolved successfully -- unlock auto-save if it was locked
        -- during ADDON_LOADED / PreSeedSpecProfile when spec was unavailable.
        EllesmereUI._profileSaveLocked = false

        local db = GetProfilesDB()
        local targetProfile = db.specProfiles[specID]
        if targetProfile and db.profiles[targetProfile] then
            local current = db.activeProfile or "Default"
            if current ~= targetProfile then
                local function doSwitch()
                    local fontWillChange = EllesmereUI.ProfileChangesFont(db.profiles[targetProfile])
                    EllesmereUI.SwitchProfile(targetProfile)
                    if InCombatLockdown() then
                        pendingReload = true
                        pendingFontCheck = fontWillChange
                    else
                        EllesmereUI.RefreshAllAddons()
                        if not isFirstLogin and fontWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = "Reload Required",
                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                confirmText = "Reload Now",
                                cancelText  = "Later",
                                onConfirm   = function() ReloadUI() end,
                            })
                        end
                    end
                end
                if isFirstLogin then
                    -- Defer two frames: one frame lets child addon OnEnable
                    -- callbacks run, a second frame lets any deferred
                    -- registrations inside OnEnable (e.g. SetupOptionsPanel)
                    -- complete before SwitchProfile tries to rebuild frames.
                    C_Timer.After(0, function()
                        C_Timer.After(0, doSwitch)
                    end)
                else
                    doSwitch()
                end
            elseif isFirstLogin or charChanged then
                -- activeProfile already matches the target. If the pre-seed
                -- already injected the correct data into each child SV, the
                -- addons built with the right values and no further action is
                -- needed. Only call SwitchProfile if the pre-seed did not run
                -- (e.g. first session after update, no lastSpecByChar entry).
                if not EllesmereUI._preSeedComplete then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(targetProfile)
                        end)
                    end)
                end
            end
        elseif isFirstLogin or charChanged then
            -- No spec assignment for this character. If the current
            -- activeProfile is spec-assigned (left over from a previous
            -- character), switch to the last non-spec profile so this
            -- character doesn't inherit another spec's layout.
            local current = db.activeProfile or "Default"
            local currentIsSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == current then currentIsSpecAssigned = true; break end
                end
            end
            if currentIsSpecAssigned then
                -- Find the best fallback: lastNonSpecProfile, or any profile
                -- that isn't spec-assigned, or Default as last resort.
                local fallback = db.lastNonSpecProfile
                if not fallback or not db.profiles[fallback] then
                    -- Walk profileOrder to find first non-spec-assigned profile
                    local specAssignedSet = {}
                    if db.specProfiles then
                        for _, pName in pairs(db.specProfiles) do
                            specAssignedSet[pName] = true
                        end
                    end
                    for _, pName in ipairs(db.profileOrder or {}) do
                        if not specAssignedSet[pName] and db.profiles[pName] then
                            fallback = pName
                            break
                        end
                    end
                end
                fallback = fallback or "Default"
                if fallback ~= current and db.profiles[fallback] then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(fallback)
                        end)
                    end)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name + string.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T3vwZTnUY6)k33UpfxeG70pz7eLKYzXxhnNj5utvPOKOT4nYK6ssLepPY)9BVascWfT44SDgpVmouKanA09x)1nab)Y5Lor3Kufd)rquYM03mpEvsM1rE2H4)f46f6eeE85L(rLZlssYEwMWXXs7c)zM01Z64VITu1TRtG)3vBwTcVHpMuuMMNLjpg)XfXu34gDvEwvj8xErxVkFw8QsHv0t(86IKYYpfF75Lcru(MQvPzjVmFrcCBLlJxK)jOheYOnzRYN)HxeFlClFb7K4S5lZlW2lm6jxE67Vi)tjfuRxfxCDsvPWNU(zRIllVmPmFtX8e8bZV6QYKQ3LjoY222X21YnWn0oGK1YuQJp91tN(6x2EZVn7rw4DB77yjHNX3fh3G8Ev(8nLC)P31U8py2BbgpFtVzhn91xO3vUwh5i88KUH(EUEYJ5Xp3Y97Q6)WSVScSDSCCDewcxVT0x(wOy5e6zfwpOKrpjBE(MSQKItJ7Pq)Cvr8jZRGz3t3uvLNP3TGoYYYsiLw(w2cP7o0OEhjSSDb5t6M8ilQZTJw3D0TEv8TjfgDJW6iFNWqRahhFPN3U6gWO2ZZn01XnimWb7M6MxVN8JEzCAgmI17kRJGjcphH02LK02UYn6YN)0NnvVN8mM2OXty0BQa70KokYHgvIJ2MnXJ8LhH(LOxP0rk5rb3kFdJcNOx8KjgdIhjciJhLBbPUe2rN94x((555Ra3XSsdBcb9BBQsxLwDRX0K7r(GPaR1bJlyoEh9mocd89dLHEbOXi7ITmj96LvVmUA(sc1cgC28)tI3Gv0NsxuTS(3HhGC6JlRG7yemanaJopWxzpa0Po)MZYxHamKQoEXICAKl9IEYQvjL3KuK8hp)mLo5LXzXxttfWtxUoz(ff5xLc3g(erEU4p4gb(oZ)qYIt3C1vOWrdNz4FqOWWJTA1ZFC5xYGzkppH3Xzo2IqBgbWkcWzM)HY3K(3jzcXXiGA688my6f(BPG)5Plb00LGm9KS4zRswmH63RlIxKMKvPU4u6IM3)LGvccbkC68dzUeMFsZJg20CpfEgeIV9kNKHcMSBB8Y4pRjp(9)1mHfnGYIVjHhqacA6QvNc9GVm0ri8dqRsS36j64nHDlmtwlhpoTa1yp71x(8)9RF10tEbQPXgh79xG2t)3L)xxKxb3AA8Q2rD5f5LPi4gmJppbHaX5E2cmt6Wr)OB8TAsjpQ9RNaBM(q8SzxFjDNHqWS8pnnfmBm0HNQ078Kj3QG)wfEJncJBubkbK3Y645GJg1JGPgoMAUnNOvjxb3LiSJgAAkiXLwrKFl2YSow9puDAx1kpQWrWP0neqsiz(rAcqNHx408Ifjf0LT00pVt9VQs(C1Mc0FplplHBVtGXm1cHitHQuG6XRlqLrmomMGQhsWAn1B1xxQS5cOHUUZa(VFRMU(nRJl(Wu8xiaImPVfl1SZ9J3uqDxMnp4Wh5vqtmKZXtvwyOW)uTjEuycD9c8Kbw(sF7aCohS7wNVEZkado52sHx0kCUR89R1m3eKQ7XPLicEJUHBuSZCDcTeHE2q8nWu64V2bFqgaHxYSLIa5Xzbqqu7JZKEoEE(WvdTq5iZoqyBjaieG1gqIa))sx)FLHsaWohxxhPNTLV3XFVHvesigDG02YZpiiyihGdcxXp6zjf5PL3CFdMqZ17lsIfmwCaU7cGTtO9XpaRCiWkiMTNNDGRpO8Co((eJX5BdJby9buJCd88bQ6umqdmMWOzRYZxSc6Z9aBPJHVILvzYQK5va3K4ImjtDfyM8g0iKtXsN9hAjXuzu3aOFaUViMKamabWilhFBf1XIKBY)yZDEoOJC9HFC654nlfhpfLa3OzaPOrABPJW2n44mG9kamKjLa2Mpj4(rkINd)GwoGSicbVc8)Bjr0seRuiG5yi1vfBVQzZAm2)cDrhId3xQhaLFivzqwYtDZxCdOOAFOEkOOBX0uGOdGjLJxORpBpvKS6I80mmdGZEYRM(KlXr(6oxre9ziRLqI0UEsGA6iS59CWmsfUoW8OTJ7H1(uE7gApDjw1Rhwt6zt5z5b(ociKJA(H1uLFXe4VL2leF8JPLVoB1TppRKYvQCc5bXP33deki6dj3olndqNjSkFSKbV(QlJZUo51GBpyZpb7RSn3Cz(Nk5BYP(HETkxd5XMYttRIyiyvpebrlZ3uMMD9ZGSv0c25W(9OR7zysYtyVNM)9tBG3qhxlvCqyiITZlP0Qxqc4mYE60Aqs1D8Q8PuEvA3cJ6Ram5wudZ0MKwbjvNTeFwYe1cvWNE9jRwVmEqDaKFMKFs1LzyoL0W980LaaFwszjwHNLPzmYg1jtYZQAbgn0aNQcGXTrnC)hiCQgFeYXINIRLhvikqU)xPLPZidtmXRvFcGXidL6NUTZL8iRTZnKP45vPFm5KS0BqCVa3Ux9ss2ubWdJott40hq8T1rEvr38udtkbtkFXjNpaseK(ldDXyF1WKmaylAzGQlMM3GBdT11f5FciEKmxf0wv4bGN2sWIbtMS8pxMK98mEKnLzpaXZZUotAy)9m2KEkgJMSpuMFwQrbR9owZFGh7HS92Y41TrCrwKFkDDcBIbPPb3N0st7AQsCv)c45ur)m0hZwL(3)DCXcspsgWQzGPq09PTb1jw1JfuVD09Q8NKLCZTAUoCCuJjtLDMt0IKY4km(CYRZo7XOpJK1jAuk1nwQzROumSFUsnEPgtM)DE(n1(PQy58)qDVditVT5sGo4CU9N0CHPGsPkD9KV(daTuoasX)jHwk(ncTSj685FpXkdo(8dgQ0p6pAKS7zGYDsz77biPWWS7bqYhaj)NnLszRI(xDqsvorN)9eI8orN0n6uLGDpJq2jj4hWdFapCB4HCfoO5CLIBkPx2u2CH6LJAYxpF4fPs0T8q)hY6wPxy4XlF8Hvg6TSUv7EDb2YQk8Dz5RAR14HS4vJw6Y7ZInBur5Tu552cjpsLMnQg9VofBwEC)Ai3wD5(vE(qxdRHwHX2LxqS1L0yBReYdRBvpOKURB13xyL(RB14RfWwwbH7VLTAiqKDSOvpGGCpGG0B5QU)Gt6VCv7Czg)(JT0BDR4vNrXqCDYCkSAK15dSKoKJO(22ztrzUA36KQssetyK80kPTcPGDTMhxwDwAX8vjdE30U9bu4TWknpVfReJRGH7s6NSbVOpdMt2toXFYe0Wc1tBkz4BFW8gOzt3rwEXnXR0aD4ubasBTeKP(kMishyXBEoU5To7XYWhBIyr06sxnbVRRNVyWXsJ4izBKDooMq)NUK7YKA2UGpPRGpWiR1LbSlWw)9Sk5ReoV2mjAFcgmv8oTYj6k0fAXQBFdy7(4KRI3SQcVLsvUuqJ(Mv5vxsuVe4ajEv1YlskqKoYiSkFnEhShoLeHpVzojrtl8bN9Xev)9Qlod7dPKSyaAY)rwkIDwSzDv6m26jQaD5P8gJUU9pNX)jZ(gXUW()TCUH1GxGurGF9(j76(7zmaTWN9LQhPtZxdoVjyooOEGt3c8ZR91XSM0YYnesXbZOEQbYRp2)mQQdVlEDDJEoo8UkEEYFDYIfVoR8V0Mv(RBswKg)x0T(xTBX3JMof1r2nZsOiHwFVtnKEKKguEQ5fyynTdYjawbgYqWXIpOGgzyybh0vx1eyoDtZFQPbHAoqOMaeQTZ785y)T77uYzEcA(NdywCE1Zr7xApfEw7UhStRaemCAMZ5fi3P2IZq29JwhNTi5M05pDfIPNKSiJEsjvWJN3lguTT2LjXlUTXyJ3SauhB3ASXjM5BQEAlwdyH8)TjPS6L5Z0T5NWQu2qya7Wg7tnbt56OQIwDw)QbYY0Qz5FM245VvbZaDDRA8j3SU6wDTiZAMhosZrtq0nPzPZYllBUxxrq7D7y3C)Q9amiBB1qhgROFcvwU9ZOqTPVrRIANrl1K5S8kWIyiLwJTmidLbn(50psETpp7S8BMfx1mUAhvcB)Mrf(38OYqQ1CTBm0mebpdOL2PoyMWW8W4HWDJE2hEwC5jxFDrEJKz1cTf0o)WBEbzlK0zePY3zkf00E68Pq7snkZAxZAtZQs20uVa(XwObg79vnuDuKBAv(AG6mUj5h1gUpSJmU75CB2iApTpa4LXm3a9DnO4fy4S31hKhhy7Ux818GmM0CJ(aW5f59AeeJ3h3NuuaWmTAcpYmchxd6B43grPJvMOUkMg(TaNTgtJ6)EM6V7k0NEDNNnO1R3sZUc)BvfRaJMxKJfP00EmOf21V95eHmGboXHt1T7VnxARPFcmWRvC4tzcT3qsHQjE9O9nv3Uc3cbj1HazJjnNenquPb2oFLARiT6q7fnAe)gX5PXR51S1UzYD3wiHgexUGEhck5AzUyD5RsIl2F1OKziZRWGbdonNj0l1WEMxXJZAggnHwAgXpfmhRw2MYNwWC21uZdpqNSZwIIosa5MrKTmu5tBe(RrpiCBnIdC14UPEXzCAzT8Nu6vQDd885Dcx7zOzAhj(rzjBaE6R2lvpm6YQj)Ybyx)VW38hxwNmVLVTAMEAFu9oGWDPLn1qybT7UnUAzW2zMO1OT(hOhugnaaVRcvI4(qUwGNwJV1M0ZnJP(otUYVFokLVNtm8cG7i)AQy(8gmzgW48KvREmXeUKDq1iR8U646U62(7HMrtrQz(6BynS72XMKpAvlUagztieQUu63NMzhAitUB7Ub90tDyN3og4z96KfT01AS0B9SQ9RmD9Bd4BcX0jA3Y4YLVinlrLChNKnE9ANu9mMavOourZYuscTwclpBOhw4RBmPGUAIQiO4aVkxhuT1TwQ5wxxLtoleJLKKvTT4i8(Jhn)EJww6GGuexK8KvPvjT37aqHOEPK37h6HtqoOEkhlAgTbGPdDKAD7oNMXAl14JOJ0TmVSkvlTyEFmY0AfnQelcPZVoh3M7UfiUnDkoEKS)ufdglC7yxOfrwluBherQQLTmKk5ivmz1RsNt(BejcD2rwQPl6hSXF48M6EbKuAPF1Ju8Bho)vaWq)xujAOX7wlCwxI3a165KG0gl1SCcgJybsbOdXErFptvddZkjAjNzRDNTZHHEUQWvgP0IW6zkkJukl67yXqdSN6AaqlaqrkGA8OpkpVP26QNKDeCvwO8mW704XHW1nw61uDrtMa96jHS)WL(8sqqZWn89xijeCMk3CdoVzSvMH)wgLOipfV56BGzX3xSjJxp9kuA)qcv(TRGUgllleVRKUWNY3KruWTGK3)WTVF2kmLn8g(eEdyDwYxmvTVtMXlapIrhxuTCv6h5l4RQHhUW3i(BmhMpi6tGWF1Mc(FexvKVgq04El(M1RsV6wUbcaJIQK3hV4)LBEqmVjPkp76nCvFPFTmoJEwNOpLeVop79jzZxYDkGbbtiqdcTg7UVUi5QKIcWXchXWna)VQ3VPmzbVghujQtMNgVQ8v5z17qhYBq2(W)j1rpH7hZgXOaT2A9hOVmVtyghNluLuw9oLFZTvGQ4CUOjF42tr1()ohX6TIQtNyfwI9gdGVs1ReSlWPEJENXh6mm0noG0dZxnf))L53WQF(DA)Q8IBi1x5TWKBEvQsbpd6WKIp8EU5O7yrYhZFpLng3ExXTZIKRQVlEN2VGhMFbNurGdCBT07nShF1wXsFFcvn3j49EngV721jkOL2HxNLzbmokWuRbcQvXGI8Lp5Xp)pOx16BR9YOGqHulomzBFAbYu0TH)(RNxx3)A3Fb)Isq4Uj0g6qvmZMseYlg3NnrTW7qhIuHD2ecLzkSJWvFfVp(CgaIes33TzpsgsVydEcph7qcEv7LIWhFrT53K563kcTlHVweclr4rsNWqryqOGk9uiv2NtvVmhMGjXPS5YhULCPNbkInvuRV8gEHDCIUjV6t8VwKN93jk0IIQPFDqBYUlQHpDhVUAjyR9Y0YsLVlgmYWYVvJBPQGJgo5FKLwnbThi9ehLFwCXR1TyaNtqQGXAftIVDreoF714ftRUSS2KWdNqDIQlUhKMfe6A1(vs3avV0MAkx3du0(KXAlolbSAjplYmxrAWtrAGU7PKxvXnXyW01jfRxFoV6RWVX3VYAKUIIHyD1MOAc3R2g7OUi92JvncotQ9D194afDPUHRBufjD9hNAwI4fxq7lutxt61r86iIi0AxKRiIkFFvl)UShPQ8lV2XCYiz4wvrVqD8SIsfz7O0rSnun1AvUYJBMiBSViSDzKeJXyoe5syvlNtAvb4cevFpN3Uuq1R)inbVCD7K)PAg3wwDeT6Fje)bvh0ST(iMw66HM2UlkLk75o6mAzBe9hwkfXxhttuFyACyEmhYehTi)98L2(8Z3GVGUJPL44b0F99x2fmZ(62m8u9a(nBDkSNPG(uOY8VtrNy3asR4Pv0jxr9jzsE1fpmn)B00mFOTmT(aOb3U5z1LHvRKtbQB8m2QOn(cx(wI9aZe8M4pREovU(deaAmC)bdNSTWDm9cwApzgWKC2eY0ZqyB291FtHqgl2DhRthT1ZPB0dFnPvjBO4gAkUQhH5ncAZt10L7x0cArMw20HTv2(uUd7OFuQIDfPYrFvrQFQUxvPRnDBce9N0ndzOD4bjg79LO3wKgOaUiHzWv7lW7V7GgiGZ1XdEdFs)OklI(1)7K6bZagoHn(wn7eSzvZiL6ZB3EygPZt8lB84X92pUMPppBbwJM8ALKSPH1at4QlrBV(xzSlP2bOsl(zZetV3jJX9Ifd9(ziTmgOViNlWuJkC)3LbsDCnhSv7QABujd4mv75zS(F61pAm3NDAsZdqsZ9UUoCk(EdaEYoxCwHVbAQPBFNcOE9uI26ogyaI7HTcNXUvkaVovHzLi3jCeVL7FE2fXfv3YWdJ(ANivvM6e(0RJcLHLBTP0H9DJTOvhSPSYXBQYpVPkKxyetUUyJBnaPrOnupA6RW(skVRUSzTANEExVR82A1y3wKkdTArnvW0tsxTYKyqGN9a2V4bsiL9PxpOhT9CPp32dbvRgitxMG1UahAEqc0WdIV7rhcCn5f1G9a)TAxfzYDkSbK7Tdfe8GtyBSvgx3gFhRqoGAGL0ODuonNYCNR4KgikQjX1eqA3DgSXaluzgndpH5uqN1R70UjDARm2rJfLQU2FOR59DjtOZ3wE9dskQZW0iCts7YmtJcjE1tV2OchdhlwFotVS2BJ7JYlxblOVXq6B4BUo7bn2IMqTbMX129SJg8xxEik8VUg7uxRbG2kkg4NHnx(T1bDQVGM(1UfiXyxqOhrK)bmqrhUIdNdsqRr0WYJ6nhqoc2cREnPqQ2WF4uFdbaJybkDL2iBR5AnA5fKgJCDt8r4EogF5UVjFmdydpXAsZETQComyxP9qYXu2Yjh68oVTH4c4ZkQ9HZBZn3zESjtigkzW3dGMO3VBiYKklal9Pi9(qe2KxUMADY57klPHt3Ymps9crQNJuBmeL05pI95UdFeQrNYyy5zaDRzSAPiZCzCQ22CUtcFYWrKOo2WA09AEFfHRO9gM0SyZJKQMfJ6AsvyusDgScnHj1jS)UAYQDW)hNsD3QktbuzPulA6DSMh95GrpoUcRuZ9vJL8Di35bQHGHN)bMcxpsmd7)nygDFB8Dgi1VHYRFWech1tDuNGdL)YG5pEaKAgpvZ7iDN9ml0XzfnuwOMLusOMa7XEQ3EGF)5nPLq6OacBLS0qlGWpmIshEsUJZGACsxBBDdURanD5RDWGRZ2w1jgJ(3yuLgle025nCNtBFywNdx7RdJl6oliW9jz17EXf6seAiQQBRKxJYuTxu(9LEW2yHUvsZdTiTDk7yB5Q6h5FlR23q8X2kvVr4Xo6sjSf21D59nAka9lVJObmgzKC(4jdCimthGN8DNj6HK5WbxZPEzy(RvDMgp9ITM6zhQ4DRD7(vqkTQMYRxyZcpTNejNSde5FkmkhxJ(pvgKBd5(NmfYrxvYV3uiV7OvJvnUEPhp06NShmr366RChz3DWezhTushod3olJtxIMJZ)9qxhDvTUgJ7OXAe1lE6ierhJ36bK16SUf4CeUi)(ZEDhfl97mh2r4oF)v11(vSA4LF7G5jUDUUdYHCaIRBzz8MT1CZgJk5ijf3ztMm2xeGTvQ4rZS9Ng71dId6qlf7bZlDOkW9lg30ozfUVPUDyLo4UrDD8sarn5cC)qJdPjmuF7HXVO7hMnAJCh44JNy(YalxpB7ohy(7Zg52t9f(k0puyROZ15ZYg1r(U20hOmzOJmqCW9JDOlE2)hg6zz17l9f3b(H4xAnlHR0nWp8q7bpBxAhTR(IGP2Ii1NDc3MjvV9oFo7r2s(eTIBh1XiPz9OjvRVnPAdLww(D)weSBbke0S4xhplqAcccpUtIk3ddzH0Z(i3MpoDkh821kOUBKmxv6lKqBJv)HoG5mzS3aAEq3D8Gn7gxsFzl0)yXDOJgCce1xo(2sWy(y1rHu9rUt92YNNuN2ZoDAZ830wf90UUntuY80w7p6nnX89aq9TauDqr6hTEtjaD0DHu03TcH(AyCQx7pcKZYrTKvCB8hDoZGeTNyRpzX1CQps6OJs6A8ld8GClQbwsmz4ZcvCIep6aYsVHJzYkSzMFFp4V7CnwJYa0AYs4j9ScoCRrHVp958ZvegeOCaH23t1((oh5R9Lu0S5313HdHLJ4iWJY1v6B7W6ur0)ZMKn05OARtRqeyr(usxPWA3oTMDJdAd6557h4ek4nAc)r5RRosAh4icoyB8GqgtWZXb6Mq1W4FLSmD(QKN850wFjPGgfU2owU(hC)akzheneAgh)WGMXrqD7JWXb4Sb40A5EGFNvEKi8ih4zD8CcQ)SHsnVBDZ76zrMc((cHO7Rx0UA(69iuVplN1TUNWt)7g5ovoDmLSTOpdnbwHQ9suZ3xYgCp1Xd2bkY9(iJYsRN)rJA3VptL2oO46dHn9TA11(ntLUIJKOUwcglIGdtWFKJR8iliih)TnLIrDA81AIVq45CKd95Z1ku6VtXVJYgKkS99cf0jF5xXh)LPZlYn6cfYrONapx8pSUadcI(SsWF3l0MzMP)fkTH(In9FGzJy32mdeCstcj90fjv62mb200GRVe6RWdDAWxO)PrQzw2PXJsYWAaDcHV7bolBXbtDXxNsmAQ6GuwLx96IC(TxU5TPdp4auxSxChJtz5hhxfJHjNqjR1KhIQwD0lGzD23)FBIlO3FF1zmJ2HVSkoe5bv3V0ZsYISTD7jm(gXiVBHMRdV3vO1oeRDpQ(LfrjDdLO1GViO6ALVb(dQtMA9i2dxLKTCK07R2pgyAugNS3mZiTQ3GNCpiEB9BkdAT17lfab0HVoU7oPZ(LCsBOxpSRhY0t07drGsU4cQaPEUiHoXZd0(QgqTUQI)B9iYx107NSp033awrN)XKIcmjyD9IRERZ1cGeDFLa8gQaeOYv581OgBZ7F4ZmFMxN2zI(qf0E4VpcTNyMduMIHp04n2uU1NrcJnBzRA0oNJKXRt6wz6DnV39i(xgTHx)s2G8I4flAoofc07cTUwY6u2YP(Z3a((fd4w4CM236bp9jrcBIBAJMG)kyec6eJdxJM2t7Q9(2rOSj0e02QAiudQoFmbQVm7pkvFep7yMRmzno38AWmQpJs6VqyW4AvkDm1MV5A(fLpREGxxM082JRx0Czj8V)BW8uDIS3mQ5tVr88JIvymiI2BnrdEJUJJrobdjHFpWVC4xU(F64xgoI)2GC1d3PlMLqvd3HaT2xmQbnwoFie)bWAUhqWg6vl5Nga2yr2pCmGbW3ekpedao8A)Ka44Jl4bcpoeuUqj7heiwqZjr(5BbbB4ae9W1gSUd9Tshw7ncc2yoQJ4tCWdbd1LrLa(XXH83km4HIM9FiGVMMQtpF0D6qFAIdzCDpa9(Rn5r1SZ)8GE)HsFSlPh3OSKpMOEz8gIePB0BVqv7LVrW3HbzR)ws4WRl4(GSov7dkIi44TnChdCON2R9BmXxpFOYl(no2)rh4rVKz)4c9O(ou8qONhc98qONFrc9WhBT)wg6PD9a)XbH9qfy)2XZ2ZkWUnuThkb73cu23ujy)jIv9FOLG197me2W62VfqSEQUVbEw)YbpDVt3Aes8dY56Wdp8paqSH8E3BmS6DN(WzJneTNoOBheo2DbCQdHm1RUspq3XQbRzkw8gu6(ciRlhJHQcR(2u53U0GVmz99JO)7t1lA3ZsJKNZ9qiNFrR58az(UVHLAZg5NtuPFuKMh2o2is(abh6fe6qd4mgC(9zmNbIl2dPCW4s7f5uhfKzFC7HXrUlrkoOqr9jPnq0r(d9sh28dXe9qInFNd30N3CFssOEyKDK63ie(p6OpMB)YFZe(oBSZhsF5xY0xy469peX(hr4H0x(XK(InF9FxYEP(lO6Dl7fj)cd)Jm7fJ34GhqX(LefJLWhqX(9fftTBQ)DbfZr0dX6aqXON(hlkw7BOYdqypaHD(dqy3)qypuh5VRyy4aiS9n0QZ7snOpQFHVQ1OFLo3W0EvXVmPmFtbLrk)DVR9R6k)zBe)8L)0S6t(c(m94fQRZosxxeVahFAZAYORNV4uqFTiU42lP5mFLr9jQ)LrPXkXJhP2JghuHh20UyVR6CTw9e4QHUg3yDthtNsn88MB0vPRwDkCZ0BOgFeQqFnKNQpcBATAX8sfgk)VEk9VARWShpVw3XGdMzbJph)Nvq7(Y4IpuEPHCb2oU4Sd4eEn3lTIXPg9k)Ve2kzw1AtRhu8WvVJoLUcpgFZA(ltyR65uLFGh8a3K0(5xrtPY9iFEnPo9VqX8u1WNEU3QlvVPEIJRNzZ8yZPXsJS9us2Wwd11k3vSjE6zpUU7NGIl1jKDqOXS7L1MbAnADt1QbR11vDoU1QxtbribfWhG2NbixzjRWNRSZaO5WJPd(ooaEQMLfkvHE9uKnEmd8TR03n8i3a8mpr64BT73i5UNlhWJ75557ey54fqVB8SOG9PR6DGMpPEyQnvlb9WY8vlmGv7fLsy(j9unjpV9L(uvtBt34CJn4G(P)I(ryLHl)eEoS98ys7i0SrwVSX4U(kCp2XFw)govzGSnN2AbgCc9uNjAXAHWu(Khz5P)FKX6aCl64NU7TdOUZn76R8UgOdB8uC7mmFARFWhhK42abSRT(L0Hlwhlxd0KbzcRm6hsTSLvnRXKY4dOTSDKCXC1UBTR9Rpe3k9gWn6ldpC((y(k4t8Q2JOPXTNToUtiS9WEgae8XJxgBPRJFyVPvL(VJ6PEjlt(m(D6(5x9Q86a2t6B8lcGjiHvOlaSy7nUNqGPJG7pEhHU(2pDiPFp9ngcH1jGoTdSdcXJ4JJpuewp(SkWY3tgYNYxJ6S1hEDQMdwhVlt3WH91mXhKAkj8O)lnEf(a3V(K1yQIbDfVojlPiE1x2zdBHMqDpMtnzJPXbcpYYOvePmbiASq5SpO6CpD39W()uYWqNj3GU6s(yMsbmSvF9E0v74vh6IhRy(spVqhRGb9QBdA5nIbRmGoDpCc9eYa37Ibl(4aWIR68SX4R1TjoGIa1)kE1g6dSEpN)U4kb2HHc)a3aVaB3w0bX(HgmKJ)601nFBXpEl2Kxwtl3igLd(8VEClXa83)tDpToqn(cPRDOTeu1YWwOg90uy3VrlmuFaUqStRRiV84wqkLi3iaNHkkAfkg35oikpFE7esq08Ly)WcVV(vo18gAYjyVPgO8AUu3f60gUjmRD1LFQk7avFHtooohBelXo4yDmea7e)V)))" },
    { name = "Spin the Wheel", description = "Randomize all settings", exportString = nil },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }

-------------------------------------------------------------------------------
--  Spin the Wheel: global randomizer
--  Randomizes all addon settings except X/Y offsets, scale, and enable flags.
--  Does not touch Party Mode.
-------------------------------------------------------------------------------
function EllesmereUI.SpinTheWheel()
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end
    local function rRange(lo, hi) return lo + math.random() * (hi - lo) end
    local floor = math.floor

    -- Randomize each loaded addon (except Nameplates which has its own randomizer)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) and entry.folder ~= "EllesmereUINameplates" then
            local profile = GetAddonProfile(entry)
            if profile then
                EllesmereUI._RandomizeProfile(profile, entry.folder)
            end
        end
    end

    -- Nameplates: use the existing randomizer keys from the preset system
    if IsAddonLoaded("EllesmereUINameplates") then
        local db = _G.EllesmereUINameplatesDB
        if db then
            EllesmereUI._RandomizeNameplates(db)
        end
    end

    -- Randomize class colors
    local colorsDB = EllesmereUI.GetCustomColorsDB()
    colorsDB.class = {}
    for token in pairs(EllesmereUI.CLASS_COLOR_MAP) do
        colorsDB.class[token] = rColor()
    end
end

--- Generic profile randomizer for AceDB-style addons.
--- Skips keys containing "offset", "Offset", "scale", "Scale", "X", "Y",
--- "pos", "Pos", "position", "Position", "anchor", "Anchor" (position-related),
--- and boolean keys that look like enable/disable toggles.
function EllesmereUI._RandomizeProfile(profile, folderName)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end

    local function IsPositionKey(k)
        local kl = k:lower()
        if kl:find("offset") then return true end
        if kl:find("scale") then return true end
        if kl:find("position") then return true end
        if kl:find("anchor") then return true end
        if kl == "x" or kl == "y" then return true end
        if kl == "offsetx" or kl == "offsety" then return true end
        if kl:find("unlockpos") then return true end
        return false
    end

    -- Boolean keys that control whether a feature/element is enabled.
    -- These should never be randomized â€” users want their frames to stay visible.
    local function IsEnableKey(k)
        local kl = k:lower()
        if kl == "enabled" then return true end
        if kl:sub(1, 6) == "enable" then return true end
        if kl:sub(1, 4) == "show" then return true end
        if kl:sub(1, 4) == "hide" then return true end
        if kl:find("enabled$") then return true end
        if kl:find("visible") then return true end
        return false
    end

    local function RandomizeTable(tbl, depth)
        if depth > 5 then return end  -- safety limit
        for k, v in pairs(tbl) do
            if type(k) == "string" and IsPositionKey(k) then
                -- Skip position/scale keys
            elseif type(k) == "string" and type(v) == "boolean" and IsEnableKey(k) then
                -- Skip enable/show/hide toggle keys
            elseif type(v) == "table" then
                -- Check if it's a color table
                if v.r and v.g and v.b then
                    tbl[k] = rColor()
                    if v.a then tbl[k].a = v.a end  -- preserve alpha
                else
                    RandomizeTable(v, depth + 1)
                end
            elseif type(v) == "boolean" then
                tbl[k] = rBool()
            elseif type(v) == "number" then
                -- Randomize numbers within a reasonable range of their current value
                if v == 0 then
                    -- Leave zero values alone (often flags)
                elseif v >= 0 and v <= 1 then
                    tbl[k] = math.random() -- 0-1 range (likely alpha/ratio)
                elseif v > 1 and v <= 50 then
                    tbl[k] = math.random(1, math.floor(v * 2))
                end
            end
        end
    end

    -- Snapshot visibility settings that must survive randomization
    local savedVis = {}

    if folderName == "EllesmereUIUnitFrames" and profile.enabledFrames then
        savedVis.enabledFrames = {}
        for k, v in pairs(profile.enabledFrames) do
            savedVis.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and profile.cdmBars then
        -- Save bar visibility
        savedVis.cdmBars = {}
        if profile.cdmBars.bars then
            for i, bar in ipairs(profile.cdmBars.bars) do
                savedVis.cdmBars[i] = { barVisibility = bar.barVisibility }
            end
        end
        -- Save top-level CDM internal tables that must not be randomized
        savedVis.specProfiles    = profile.specProfiles
        savedVis.activeSpecKey   = profile.activeSpecKey
        savedVis.barGlows        = profile.barGlows
        savedVis.trackedBuffBars = profile.trackedBuffBars
        savedVis.spec            = profile.spec
    elseif folderName == "EllesmereUIResourceBars" then
        savedVis.secondary = profile.secondary and profile.secondary.visibility
        savedVis.health    = profile.health    and profile.health.visibility
        savedVis.primary   = profile.primary   and profile.primary.visibility
    elseif folderName == "EllesmereUIActionBars" and profile.bars then
        savedVis.bars = {}
        for key, bar in pairs(profile.bars) do
            savedVis.bars[key] = {
                alwaysHidden      = bar.alwaysHidden,
                mouseoverEnabled  = bar.mouseoverEnabled,
                mouseoverAlpha    = bar.mouseoverAlpha,
                combatHideEnabled = bar.combatHideEnabled,
                combatShowEnabled = bar.combatShowEnabled,
            }
        end
    end

    RandomizeTable(profile, 0)

    -- Restore visibility settings
    if folderName == "EllesmereUIUnitFrames" and savedVis.enabledFrames then
        if not profile.enabledFrames then profile.enabledFrames = {} end
        for k, v in pairs(savedVis.enabledFrames) do
            profile.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and savedVis.cdmBars then
        if profile.cdmBars and profile.cdmBars.bars then
            for i, saved in pairs(savedVis.cdmBars) do
                if profile.cdmBars.bars[i] then
                    profile.cdmBars.bars[i].barVisibility = saved.barVisibility
                end
            end
        end
        -- Restore top-level CDM internal tables
        profile.specProfiles    = savedVis.specProfiles
        profile.activeSpecKey   = savedVis.activeSpecKey
        profile.barGlows        = savedVis.barGlows
        profile.trackedBuffBars = savedVis.trackedBuffBars
        profile.spec            = savedVis.spec
    elseif folderName == "EllesmereUIResourceBars" then
        if profile.secondary then profile.secondary.visibility = savedVis.secondary end
        if profile.health    then profile.health.visibility    = savedVis.health    end
        if profile.primary   then profile.primary.visibility   = savedVis.primary   end
    elseif folderName == "EllesmereUIActionBars" and savedVis.bars then
        if profile.bars then
            for key, vis in pairs(savedVis.bars) do
                if profile.bars[key] then
                    profile.bars[key].alwaysHidden      = vis.alwaysHidden
                    profile.bars[key].mouseoverEnabled   = vis.mouseoverEnabled
                    profile.bars[key].mouseoverAlpha     = vis.mouseoverAlpha
                    profile.bars[key].combatHideEnabled  = vis.combatHideEnabled
                    profile.bars[key].combatShowEnabled  = vis.combatShowEnabled
                end
            end
        end
    end
end

--- Nameplate-specific randomizer (reuses the existing logic from the
--- commented-out preset system in the nameplates options file)
function EllesmereUI._RandomizeNameplates(db)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end

    local borderOptions = { "ellesmere", "simple" }
    local glowOptions = { "ellesmereui", "vibrant", "none" }
    local cpPosOptions = { "bottom", "top" }
    local timerOptions = { "topleft", "center", "topright", "none" }

    -- Aura slots: exclusive pick
    local auraSlots = { "top", "left", "right", "topleft", "topright", "bottom" }
    local function pickAuraSlot()
        if #auraSlots == 0 then return "none" end
        local i = math.random(#auraSlots)
        local s = auraSlots[i]
        table.remove(auraSlots, i)
        return s
    end

    db.borderStyle = pick(borderOptions)
    db.borderColor = rColor()
    db.targetGlowStyle = pick(glowOptions)
    db.showTargetArrows = rBool()
    db.showClassPower = rBool()
    db.classPowerPos = pick(cpPosOptions)
    db.classPowerClassColors = rBool()
    db.classPowerGap = math.random(0, 6)
    db.classPowerCustomColor = rColor()
    db.classPowerBgColor = rColor()
    db.classPowerEmptyColor = rColor()

    -- Text slots
    local textPool = { "enemyName", "healthPercent", "healthNumber",
        "healthPctNum", "healthNumPct" }
    local function pickText()
        if #textPool == 0 then return "none" end
        local i = math.random(#textPool)
        local e = textPool[i]
        table.remove(textPool, i)
        return e
    end
    db.textSlotTop = pickText()
    db.textSlotRight = pickText()
    db.textSlotLeft = pickText()
    db.textSlotCenter = pickText()
    db.textSlotTopColor = rColor()
    db.textSlotRightColor = rColor()
    db.textSlotLeftColor = rColor()
    db.textSlotCenterColor = rColor()

    db.healthBarHeight = math.random(10, 24)
    db.healthBarWidth = math.random(2, 10)
    db.castBarHeight = math.random(10, 24)
    db.castNameSize = math.random(8, 14)
    db.castNameColor = rColor()
    db.castTargetSize = math.random(8, 14)
    db.castTargetClassColor = rBool()
    db.castTargetColor = rColor()
    db.castScale = math.random(10, 40) * 5
    db.showCastIcon = math.random() > 0.3
    db.castIconScale = math.floor((0.5 + math.random() * 1.5) * 10 + 0.5) / 10

    db.debuffSlot = pickAuraSlot()
    db.buffSlot = pickAuraSlot()
    db.ccSlot = pickAuraSlot()
    db.debuffYOffset = math.random(0, 8)
    db.sideAuraXOffset = math.random(0, 8)
    db.auraSpacing = math.random(0, 6)

    db.topSlotSize = math.random(18, 34)
    db.rightSlotSize = math.random(18, 34)
    db.leftSlotSize = math.random(18, 34)
    db.toprightSlotSize = math.random(18, 34)
    db.topleftSlotSize = math.random(18, 34)

    local timerPos = pick(timerOptions)
    db.debuffTimerPosition = timerPos
    db.buffTimerPosition = timerPos
    db.ccTimerPosition = timerPos

    db.auraDurationTextSize = math.random(8, 14)
    db.auraDurationTextColor = rColor()
    db.auraStackTextSize = math.random(8, 14)
    db.auraStackTextColor = rColor()
    db.buffTextSize = math.random(8, 14)
    db.buffTextColor = rColor()
    db.ccTextSize = math.random(8, 14)
    db.ccTextColor = rColor()

    db.raidMarkerPos = pickAuraSlot()
    db.classificationSlot = pickAuraSlot()

    db.textSlotTopSize = math.random(8, 14)
    db.textSlotRightSize = math.random(8, 14)
    db.textSlotLeftSize = math.random(8, 14)
    db.textSlotCenterSize = math.random(8, 14)

    db.hashLineEnabled = math.random() > 0.7
    db.hashLinePercent = math.random(10, 50)
    db.hashLineColor = rColor()
    db.focusCastHeight = 100 + math.random(0, 4) * 25

    -- Font
    local validFonts = {}
    for _, f in ipairs(EllesmereUI.FONT_ORDER) do
        if f ~= "---" then validFonts[#validFonts + 1] = f end
    end
    db.font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        .. (EllesmereUI.FONT_FILES[pick(validFonts)] or "Expressway.TTF")

    -- Colors
    db.focusColorEnabled = true
    db.tankHasAggroEnabled = true
    db.focus = rColor()
    db.caster = rColor()
    db.miniboss = rColor()
    db.enemyInCombat = rColor()
    db.castBar = rColor()
    db.interruptReady = rColor()
    db.castBarUninterruptible = rColor()
    db.tankHasAggro = rColor()
    db.tankLosingAggro = rColor()
    db.tankNoAggro = rColor()
    db.dpsHasAggro = rColor()
    db.dpsNearAggro = rColor()

    -- Bar texture (skip texture key randomization â€” texture list is addon-local)
    db.healthBarTextureClassColor = math.random() > 0.5
    if not db.healthBarTextureClassColor then
        db.healthBarTextureColor = rColor()
    end
    db.healthBarTextureScale = math.random(5, 20) / 10
    db.healthBarTextureFit = math.random() > 0.3
end

-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Default" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout callback to persist fonts, colors, and unlock layout
    -- into the active profile, and track the last non-spec profile.
    -- No addon data snapshot needed for NewDB addons -- they write directly
    -- to the central store. Flat addons (e.g. Nameplates) write to their own
    -- global SV, so we snapshot them back into the profile here.
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Default"
            local profileData = db.profiles[name]
            if profileData then
                profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
                profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
                profileData.unlockLayout = {
                    anchors     = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
                    widthMatch  = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
                    heightMatch = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
                }
                -- Snapshot flat addon data into the active profile
                if not profileData.addons then profileData.addons = {} end
                for _, entry in ipairs(ADDON_DB_MAP) do
                    if entry.isFlat and IsAddonLoaded(entry.folder) then
                        local sv = _G[entry.svName]
                        if sv then
                            profileData.addons[entry.folder] = DeepCopy(sv)
                        end
                    end
                end
            end
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it.
            local isSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == name then isSpecAssigned = true; break end
                end
            end
            if not isSpecAssigned then
                db.lastNonSpecProfile = name
            end
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()

        -- On first install, create "Default" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Default"
        end
        -- Ensure Default profile exists (empty table -- NewDB fills defaults)
        if not db.profiles["Default"] then
            db.profiles["Default"] = {}
        end
        -- Ensure Default is in the order list
        local hasDefault = false
        for _, n in ipairs(db.profileOrder) do
            if n == "Default" then hasDefault = true; break end
        end
        if not hasDefault then
            table.insert(db.profileOrder, "Default")
        end

        ---------------------------------------------------------------
        --  Note: multiple specs may intentionally point to the same
        --  profile. No deduplication is performed here.
        ---------------------------------------------------------------

        -- Restore saved profile keybinds
        C_Timer.After(1, function()
            EllesmereUI.RestoreProfileKeybinds()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Shared popup builder for Export and Import
--  Matches the info popup look: dark bg, thin scrollbar, smooth scroll.
-------------------------------------------------------------------------------
local SCROLL_STEP  = 45
local SMOOTH_SPEED = 12

local function BuildStringPopup(title, subtitle, readOnly, onConfirm, confirmLabel)
    local POPUP_W, POPUP_H = 520, 310
    local FONT = EllesmereUI.EXPRESSWAY

    -- Dimmer
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    -- Popup
    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    -- Title
    local titleFS = EllesmereUI.MakeFont(popup, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -20)
    titleFS:SetText(title)

    -- Subtitle
    local subFS = EllesmereUI.MakeFont(popup, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(subtitle)

    -- ScrollFrame containing the EditBox
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     20, -58)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 52)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local editBox = CreateFrame("EditBox", nil, sc)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT",     sc, "TOPLEFT",     0, 0)
    editBox:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",   -14, 0)
    editBox:SetHeight(1)  -- grows with content

    -- Scrollbar track
    local scrollTrack = CreateFrame("Frame", nil, sf)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -2, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2,  4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
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
    scrollThumb:SetScript("OnDragStop",  function() end)
    local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 0.27)

    local scrollTarget = 0
    local isSmoothing  = false
    local smoothFrame  = CreateFrame("Frame")
    smoothFrame:Hide()

    local function UpdateThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then scrollTrack:Hide(); return end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = sf:GetHeight()
        local ratio  = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
        UpdateThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        SmoothScrollTo((isSmoothing and scrollTarget or self:GetVerticalScroll()) - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Thumb drag
    local isDragging, dragStartY, dragStartScroll
    local function StopDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end
    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cy = GetCursorPosition()
        dragStartY      = cy / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
            isSmoothing = false; smoothFrame:Hide()
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / self2:GetEffectiveScale()
            local trackH   = scrollTrack:GetHeight()
            local maxTravel = trackH - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            local newScroll = math.max(0, math.min(maxScroll,
                dragStartScroll + ((dragStartY - cy2) / maxTravel) * maxScroll))
            scrollTarget = newScroll
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDrag() end
    end)

    -- Reset on hide
    dimmer:HookScript("OnHide", function()
        isSmoothing = false; smoothFrame:Hide()
        scrollTarget = 0
        sf:SetVerticalScroll(0)
        editBox:ClearFocus()
    end)

    -- Auto-select for export (read-only): click selects all for easy copy.
    -- For import (editable): just re-focus so the user can paste immediately.
    if readOnly then
        editBox:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
    else
        editBox:SetScript("OnMouseUp", function(self)
            self:SetFocus()
        end)
        -- Click anywhere in the scroll area should also focus the editbox
        sf:SetScript("OnMouseDown", function()
            editBox:SetFocus()
        end)
    end

    if readOnly then
        editBox:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or ""); self:HighlightText()
        end)
    end

    -- Resize scroll child to fit editbox content
    local function RefreshHeight()
        C_Timer.After(0.01, function()
            local lineH = (editBox.GetLineHeight and editBox:GetLineHeight()) or 14
            local h = editBox:GetNumLines() * lineH
            local sfH = sf:GetHeight() or 100
            -- Only grow scroll child beyond the visible area when content is taller
            if h <= sfH then
                sc:SetHeight(sfH)
                editBox:SetHeight(sfH)
            else
                sc:SetHeight(h + 4)
                editBox:SetHeight(h + 4)
            end
            UpdateThumb()
        end)
    end
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput then
            self:SetText(self._readOnly or ""); self:HighlightText()
        end
        RefreshHeight()
    end)

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, popup)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11,
            EllesmereUI.WB_COLOURS, function()
                local str = editBox:GetText()
                if str and #str > 0 then
                    dimmer:Hide()
                    onConfirm(str)
                end
            end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(120, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
        cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    else
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(120, 26)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    end

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return dimmer, editBox, RefreshHeight
end

-------------------------------------------------------------------------------
--  Export Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowExportPopup(exportStr)
    local dimmer, editBox, RefreshHeight = BuildStringPopup(
        "Export Profile",
        "Copy the string below and share it",
        true, nil, nil)

    editBox._readOnly = exportStr
    editBox:SetText(exportStr)
    RefreshHeight()

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Import Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowImportPopup(onImport)
    local dimmer, editBox = BuildStringPopup(
        "Import Profile",
        "Paste an EllesmereUI profile string below",
        false,
        function(str) if onImport then onImport(str) end end,
        "Import")

    dimmer:Show()
    C_Timer.After(0.05, function() editBox:SetFocus() end)
end
