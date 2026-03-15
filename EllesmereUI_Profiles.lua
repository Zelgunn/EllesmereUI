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
--  CDM spell-layout fields: excluded from main profile snapshots/applies.
--  These are managed exclusively by the CDM Spell Profile export/import.
-------------------------------------------------------------------------------
local CDM_SPELL_KEYS = {
    trackedSpells = true,
    extraSpells   = true,
    removedSpells = true,
    dormantSpells = true,
    customSpells  = true,
}

--- Deep-copy a CDM profile, stripping only spell-layout data from bars.
--- Per-bar spell lists (trackedSpells, extraSpells, etc.) are excluded
--- because they are managed by CDM's internal spec profile system.
--- specProfiles, barGlows, and trackedBuffBars ARE included so that new
--- characters seeded from this snapshot receive the correct CDM spell
--- assignments without needing a fresh Blizzard snapshot.
--- Positions (cdmBarPositions, tbbPositions) ARE included in the copy
--- because they belong to the visual/layout profile, not spell assignments.
local function DeepCopyCDMStyleOnly(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    -- Keys that should never appear in layout snapshots because they are
    -- transient runtime state, not user-facing configuration.
    local CDM_INTERNAL = {
        activeSpecKey = true,
        spec = true,
    }
    for k, v in pairs(src) do
        if CDM_INTERNAL[k] then
            -- Omit -- managed by CDM's own spec system
        elseif k == "cdmBars" and type(v) == "table" then
            -- Deep-copy cdmBars but strip spell fields from each bar entry
            local barsCopy = {}
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    local barList = {}
                    for i, bar in ipairs(bv) do
                        local barCopy = {}
                        for fk, fv in pairs(bar) do
                            if not CDM_SPELL_KEYS[fk] then
                                barCopy[fk] = DeepCopy(fv)
                            end
                        end
                        barList[i] = barCopy
                    end
                    barsCopy[bk] = barList
                else
                    barsCopy[bk] = DeepCopy(bv)
                end
            end
            copy[k] = barsCopy
        else
            copy[k] = DeepCopy(v)
        end
    end
    return copy
end

--- Merge a CDM style-only snapshot back into the live profile,
--- preserving all existing spell-layout fields.
--- Positions (cdmBarPositions, tbbPositions) ARE applied from the snapshot
--- because they belong to the visual/layout profile.
local function ApplyCDMStyleOnly(profile, snap)
    -- Keys managed by CDM's internal spec profile system -- never overwrite
    -- from a layout snapshot so spell assignments survive profile switches.
    local CDM_INTERNAL = {
        specProfiles = true,
        activeSpecKey = true,
        barGlows = true,
        trackedBuffBars = true,
        spec = true,
    }

    -- Seed CDM spec profiles from the snapshot for any spec keys that the
    -- live profile does not already have. This covers new characters whose
    -- specProfiles table is empty -- they receive the spell assignments
    -- stored in the profile snapshot so the correct layout appears on login
    -- instead of a fresh Blizzard snapshot.
    if snap.specProfiles and type(snap.specProfiles) == "table" then
        if not profile.specProfiles then profile.specProfiles = {} end
        for specKey, specData in pairs(snap.specProfiles) do
            if not profile.specProfiles[specKey] then
                profile.specProfiles[specKey] = DeepCopy(specData)
            end
        end
    end

    -- Seed barGlows and trackedBuffBars from the snapshot when the live
    -- profile has none (new character / fresh profile).
    if snap.barGlows and type(snap.barGlows) == "table" then
        if not profile.barGlows or not profile.barGlows.assignments
           or not next(profile.barGlows.assignments or {}) then
            profile.barGlows = DeepCopy(snap.barGlows)
        end
    end
    if snap.trackedBuffBars and type(snap.trackedBuffBars) == "table" then
        if not profile.trackedBuffBars or not profile.trackedBuffBars.bars
           or not next(profile.trackedBuffBars.bars or {}) then
            profile.trackedBuffBars = DeepCopy(snap.trackedBuffBars)
        end
    end

    -- Wipe non-internal top-level keys so stale values from a previous
    -- profile (e.g. Spin the Wheel) do not persist when the snapshot is
    -- missing those keys.
    for k in pairs(profile) do
        if not CDM_INTERNAL[k] and k ~= "cdmBars" then
            profile[k] = nil
        end
    end

    -- Apply top-level non-spell keys
    for k, v in pairs(snap) do
        if CDM_INTERNAL[k] then
            -- Skip -- managed by CDM's own spec system (seeded above)
        elseif k == "cdmBars" and type(v) == "table" then
            if not profile.cdmBars then profile.cdmBars = {} end
            -- Wipe non-bars keys so stale values do not persist
            for bk in pairs(profile.cdmBars) do
                if bk ~= "bars" then profile.cdmBars[bk] = nil end
            end
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    if not profile.cdmBars.bars then profile.cdmBars.bars = {} end
                    -- Build a key->index lookup for the live bars so we can
                    -- match by key instead of array index. Index-based matching
                    -- breaks when bar order differs between snapshot and live.
                    local liveIdxByKey = {}
                    for i, liveBar in ipairs(profile.cdmBars.bars) do
                        if liveBar.key then liveIdxByKey[liveBar.key] = i end
                    end
                    for _, barSnap in ipairs(bv) do
                        local snapKey = barSnap.key
                        if snapKey then
                            local liveIdx = liveIdxByKey[snapKey]
                            if liveIdx then
                                local liveBar = profile.cdmBars.bars[liveIdx]
                                -- Wipe non-spell keys so stale randomized
                                -- values do not persist from a previous profile
                                for fk in pairs(liveBar) do
                                    if not CDM_SPELL_KEYS[fk] then
                                        liveBar[fk] = nil
                                    end
                                end
                                for fk, fv in pairs(barSnap) do
                                    if not CDM_SPELL_KEYS[fk] then
                                        liveBar[fk] = DeepCopy(fv)
                                    end
                                end
                            end
                            -- If the bar key doesn't exist in the live profile,
                            -- skip it -- don't create ghost entries.
                        end
                    end
                else
                    profile.cdmBars[bk] = DeepCopy(bv)
                end
            end
        else
            profile[k] = DeepCopy(v)
        end
    end
end

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

--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run and SV globals exist).
--  At this point the spec API is available, so we can resolve the current
--  spec and inject the correct profile snapshot into each child SV before
--  any addon builds its UI.
--
--  The ADDON_LOADED frame below handles the profileKeys rewrite (which must
--  happen before NewDB runs). The actual data injection is done here since
--  the spec is not available at ADDON_LOADED time.
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

        local charKey = UnitName("player") .. " - " .. GetRealmName()

        -- Resolve the current spec. Prefer the saved lastSpecByChar value
        -- (always reliable). If this is a new character with no saved entry,
        -- try GetSpecialization() live -- it is available at ADDON_LOADED
        -- time for returning characters and most new characters. If it
        -- returns nothing, we cannot pre-seed and fall back to the deferred
        -- SwitchProfile path in the spec handler.
        if not EllesmereUIDB.lastSpecByChar then
            EllesmereUIDB.lastSpecByChar = {}
        end
        local lastSpecByChar = EllesmereUIDB.lastSpecByChar
        local resolvedSpecID = lastSpecByChar[charKey]

        if not resolvedSpecID then
            -- No saved entry -- try to read the spec live right now
            local specIdx = GetSpecialization and GetSpecialization()
            if specIdx and specIdx > 0 then
                local liveSpecID = GetSpecializationInfo(specIdx)
                if liveSpecID and specProfiles[liveSpecID] then
                    resolvedSpecID = liveSpecID
                    -- Persist it so future logins use the fast path
                    lastSpecByChar[charKey] = resolvedSpecID
                end
            end
        end

        if not resolvedSpecID or not specProfiles[resolvedSpecID] then
            -- Still no spec -- lock auto-save conservatively so a stale
            -- session cannot corrupt stored profile data.
            if next(specProfiles) then
                EllesmereUI._profileSaveLocked = true
            end
            -- If activeProfile is a spec-assigned profile from another
            -- character, fall back to a safe default so this new character
            -- does not build its UI with another spec's layout and
            -- potentially overwrite it on save.
            local curActive = EllesmereUIDB.activeProfile
            local safe = curActive  -- default: keep current
            if curActive and next(specProfiles) then
                for _, pName in pairs(specProfiles) do
                    if pName == curActive then
                        -- Current active profile belongs to a spec assignment.
                        -- Switch to lastNonSpecProfile or Default.
                        safe = EllesmereUIDB.lastNonSpecProfile
                        if not safe or not (EllesmereUIDB.profiles or {})[safe] then
                            safe = "Default"
                        end
                        EllesmereUIDB.activeProfile = safe
                        break
                    end
                end
            end
            -- Always write profileKeys so NewDB never creates a
            -- per-character profile. Use the safe fallback name.
            if safe then
                for _, entry in ipairs(ADDON_DB_MAP) do
                    local sv = _G[entry.svName]
                    if sv == nil then sv = {} ; _G[entry.svName] = sv end
                    if type(sv) == "table" then
                        if type(sv.profileKeys) ~= "table" then
                            sv.profileKeys = {}
                        end
                        sv.profileKeys[charKey] = safe
                    end
                end
            end
            return
        end

        local targetProfile = specProfiles[resolvedSpecID]
        if not targetProfile then return end

        -- Rewrite profileKeys in each child addon SV so NewDB loads the
        -- correct profile on first read. Data injection happens later in
        -- PreSeedSpecProfile (called just before OnEnable) when the spec
        -- API is guaranteed available.
        for _, entry in ipairs(ADDON_DB_MAP) do
            local sv = _G[entry.svName]
            if sv == nil then sv = {} ; _G[entry.svName] = sv end
            if type(sv) == "table" then
                if type(sv.profileKeys) ~= "table" then sv.profileKeys = {} end
                sv.profileKeys[charKey] = targetProfile
            end
        end

        EllesmereUIDB.activeProfile = targetProfile
    end)
end

--- Called by EllesmereUI_Lite just before child addon OnEnable calls fire.
-- At this point the spec API is available. Resolves the current spec,
-- injects the correct profile snapshot into each child SV, and sets
-- _preSeedComplete so the spec handler skips its redundant SwitchProfile.
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

    -- Build a lookup of svName -> db object so we can update db.profile in-place
    local dbByName = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.svName then
                dbByName[db.svName] = db
            end
        end
    end

    local addonSnap = profiles[targetProfile].addons
    for _, entry in ipairs(ADDON_DB_MAP) do
        local sv = _G[entry.svName]
        if sv == nil then sv = {} ; _G[entry.svName] = sv end
        if type(sv) == "table" then
            if type(sv.profileKeys) ~= "table" then sv.profileKeys = {} end
            sv.profileKeys[charKey] = targetProfile
            local snap = addonSnap and addonSnap[entry.folder]
            if snap and not entry.isFlat then
                -- Find the live db object for this SV
                local db = dbByName[entry.svName]
                if db then
                    if entry.folder == "EllesmereUICooldownManager" then
                        -- CDM: apply style-only snapshot so spell profiles
                        -- (specProfiles, per-bar spell lists) are preserved.
                        ApplyCDMStyleOnly(db.profile, snap)
                    else
                        -- Wipe and copy snapshot into the existing db.profile
                        -- table in-place so the reference held by the addon stays valid.
                        wipe(db.profile)
                        for k, v in pairs(snap) do
                            db.profile[k] = DeepCopy(v)
                        end
                    end
                    -- Fill any missing keys from defaults
                    if db._profileDefaults then
                        EllesmereUI.Lite.DeepMergeDefaults(db.profile, db._profileDefaults)
                    end
                    -- Keep sv.profiles in sync
                    if type(sv.profiles) ~= "table" then sv.profiles = {} end
                    sv.profiles[targetProfile] = db.profile
                end
            end
        end
    end

    EllesmereUIDB.activeProfile = targetProfile
    EllesmereUI._preSeedComplete = true
end

--- Get the live profile table for an addon
local function GetAddonProfile(entry)
    if entry.isFlat then
        -- Flat DB (Nameplates): the global IS the profile
        return _G[entry.svName]
    else
        -- AceDB-style: profile lives under .profile
        local aceDB = entry.globalName and _G[entry.globalName]
        if aceDB and aceDB.profile then return aceDB.profile end
        -- Fallback for Lite.NewDB addons: look up the current character's profile
        local raw = _G[entry.svName]
        if raw and raw.profiles then
            -- Determine the profile name for this character
            local profileName = "Default"
            if raw.profileKeys then
                local charKey = UnitName("player") .. " - " .. GetRealmName()
                profileName = raw.profileKeys[charKey] or "Default"
            end
            if raw.profiles[profileName] then
                return raw.profiles[profileName]
            end
        end
        return nil
    end
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                if entry.folder == "EllesmereUICooldownManager" then
                    data.addons[entry.folder] = DeepCopyCDMStyleOnly(profile)
                else
                    data.addons[entry.folder] = DeepCopy(profile)
                end
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
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
                    if folderName == "EllesmereUICooldownManager" then
                        data.addons[folderName] = DeepCopyCDMStyleOnly(profile)
                    else
                        data.addons[folderName] = DeepCopy(profile)
                    end
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    return data
end

--- Apply a profile data table to all loaded addons
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end

    -- Build a svName -> db lookup from the Lite registry so we can write
    -- directly into db.profile (the reference the addon actually holds)
    -- rather than going through the SV profileKeys lookup which may still
    -- point to the old profile name.
    local dbByName = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.svName then dbByName[db.svName] = db end
        end
    end

    local charKey = UnitName("player") .. " - " .. GetRealmName()

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            if entry.folder == "EllesmereUICooldownManager" then
                -- CDM: use globalName accessor, apply style-only
                local aceDB = entry.globalName and _G[entry.globalName]
                local profile = aceDB and aceDB.profile
                if profile then ApplyCDMStyleOnly(profile, snap) end
            elseif entry.isFlat then
                -- Flat DB (Nameplates): wipe and copy the global SV directly
                local db = _G[entry.svName]
                if db then
                    for k in pairs(db) do
                        if not k:match("^_") then db[k] = nil end
                    end
                    for k, v in pairs(snap) do
                        if not k:match("^_") then db[k] = DeepCopy(v) end
                    end
                end
            else
                -- Lite.NewDB addon: write directly into db.profile so the
                -- addon's held reference is updated, then sync the SV.
                local db = dbByName[entry.svName]
                if db then
                    local profile = db.profile
                    for k in pairs(profile) do profile[k] = nil end
                    for k, v in pairs(snap) do profile[k] = DeepCopy(v) end
                    -- Fill missing keys from defaults
                    if db._profileDefaults then
                        EllesmereUI.Lite.DeepMergeDefaults(profile, db._profileDefaults)
                    end
                    -- Ensure per-unit bg colors are never nil after a profile load
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
                    -- Keep the SV in sync: point profileKeys to the active
                    -- profile name and store the live table there.
                    local sv = _G[entry.svName]
                    local activeName = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                    if sv then
                        if type(sv.profileKeys) ~= "table" then sv.profileKeys = {} end
                        sv.profileKeys[charKey] = activeName
                        if type(sv.profiles) ~= "table" then sv.profiles = {} end
                        sv.profiles[activeName] = profile
                        db._profileName = activeName
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
        -- Save outgoing profile
        local wasLocked = EllesmereUI._profileSaveLocked
        EllesmereUI._profileSaveLocked = false
        EllesmereUI.AutoSaveActiveProfile()
        EllesmereUI._profileSaveLocked = wasLocked
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
                    if folderName == "EllesmereUICooldownManager" then
                        ApplyCDMStyleOnly(profile, snap)
                    elseif entry.isFlat then
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
                            profile[k] = DeepCopy(v)
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
--    { version = 1, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"
local CDM_LAYOUT_PREFIX = "!EUICDM_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    local payload = { version = 1, type = "full", data = profileData }
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
    local payload = { version = 1, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--- Export CDM spell profiles for selected spec keys.
--- specKeys = { "250", "251", ... } (specID strings)
function EllesmereUI.ExportCDMSpellLayouts(specKeys)
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return nil end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return nil end
    local exported = {}
    for _, key in ipairs(specKeys) do
        if profile.specProfiles[key] then
            exported[key] = DeepCopy(profile.specProfiles[key])
        end
    end
    if not next(exported) then return nil end
    local payload = { version = 1, type = "cdm_spells", data = exported }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Import CDM spell profiles from a string. Overwrites matching spec profiles.
function EllesmereUI.ImportCDMSpellLayouts(importStr)
    -- Detect profile strings pasted into the wrong import
    if importStr and importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return false, "This is a UI Profile string, not a CDM Spell Profile. Use the Profile import instead."
    end
    if not importStr or #importStr < 5 then
        return false, "Invalid string"
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return false, "Not a valid CDM Spell Profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return false, "LibDeflate not available" end

    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return false, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return false, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return false, "Unsupported CDM spell profile version"
    end
    if payload.type ~= "cdm_spells" or not payload.data then
        return false, "Invalid CDM spell profile data"
    end

    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return false, "Cooldown Manager not found" end
    local profile = GetAddonProfile(cdmEntry)
    if not profile then return false, "Cooldown Manager profile not available" end

    if not profile.specProfiles then profile.specProfiles = {} end

    -- Build a set of spellIDs the importing user actually has in their CDM
    -- viewer. Spells not in this set are "not displayed" and should be
    -- filtered out so the user is not given spells they cannot track.
    local userCDMSpells
    if _G._ECME_GetCDMSpellSet then
        userCDMSpells = _G._ECME_GetCDMSpellSet()
    end

    -- Helper: filter an array of spellIDs, keeping only those in the user's CDM
    local function FilterSpellList(list)
        if not list or not userCDMSpells then return list end
        local filtered = {}
        for _, sid in ipairs(list) do
            if userCDMSpells[sid] then
                filtered[#filtered + 1] = sid
            end
        end
        return filtered
    end

    -- Helper: filter a removedSpells table (spellID keys, boolean values)
    local function FilterSpellMap(map)
        if not map or not userCDMSpells then return map end
        local filtered = {}
        for sid, v in pairs(map) do
            if userCDMSpells[sid] then
                filtered[sid] = v
            end
        end
        return filtered
    end

    -- Overwrite matching spec profiles from the imported data, filtering spells
    local count = 0
    for specKey, specData in pairs(payload.data) do
        local data = DeepCopy(specData)

        -- Filter barSpells
        if data.barSpells then
            for barKey, barSpells in pairs(data.barSpells) do
                if barSpells.trackedSpells then
                    barSpells.trackedSpells = FilterSpellList(barSpells.trackedSpells)
                end
                if barSpells.extraSpells then
                    barSpells.extraSpells = FilterSpellList(barSpells.extraSpells)
                end
                if barSpells.removedSpells then
                    barSpells.removedSpells = FilterSpellMap(barSpells.removedSpells)
                end
                if barSpells.dormantSpells then
                    barSpells.dormantSpells = FilterSpellMap(barSpells.dormantSpells)
                end
                if barSpells.customSpells then
                    barSpells.customSpells = FilterSpellList(barSpells.customSpells)
                end
            end
        end

        -- Filter tracked buff bars
        if data.trackedBuffBars and data.trackedBuffBars.bars then
            local kept = {}
            for _, tbb in ipairs(data.trackedBuffBars.bars) do
                if not tbb.spellID or tbb.spellID <= 0
                   or not userCDMSpells
                   or userCDMSpells[tbb.spellID] then
                    kept[#kept + 1] = tbb
                end
            end
            data.trackedBuffBars.bars = kept
        end

        profile.specProfiles[specKey] = data
        count = count + 1
    end

    -- If the user's current spec matches one of the imported specs, apply it
    -- to the live bars immediately so it takes effect without a /reload.
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and payload.data[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
            -- Rebuild visual CDM bar frames with the newly loaded data
            if _G._ECME_Apply then _G._ECME_Apply() end
        end
    end

    return true, nil, count
end

--- Get a list of saved CDM spec profile keys with display info.
--- Returns: { { key="250", name="Blood", icon=... }, ... }
function EllesmereUI.GetCDMSpecProfiles()
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return {} end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return {} end
    local result = {}
    for specKey in pairs(profile.specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key  = specKey,
            name = name or ("Spec " .. specKey),
            icon = icon,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function EllesmereUI.ExportCurrentProfile()
    local profileData = EllesmereUI.SnapshotAllAddons()
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 1, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect CDM layout strings pasted into the wrong import
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) == CDM_LAYOUT_PREFIX then
        return nil, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
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
    if payload.version ~= 1 then
        return nil, "Unsupported profile version"
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
        return false, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
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
        db.profiles[profileName] = DeepCopy(payload.data)
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            -- Save the profile but do not activate or apply it
            return true, nil, "spec_locked"
        end
        -- Make it the active profile
        db.activeProfile = profileName
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Re-snapshot after fixup so the stored profile has correct colors
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    elseif payload.type == "partial" then
        -- Partial: copy current profile, overwrite the imported addons
        local currentSnap = EllesmereUI.SnapshotAllAddons()
        -- Merge imported addon data over current
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                currentSnap.addons[folder] = DeepCopy(snap)
            end
        end
        -- Merge fonts/colors if present
        if payload.data.fonts then
            currentSnap.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            currentSnap.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        db.profiles[profileName] = currentSnap
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
        EllesmereUI.ApplyProfileData(currentSnap)
        FixupImportedClassColors()
        -- Re-snapshot after fixup
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    db.activeProfile = name
end

--- Create a new profile populated with default settings (does not switch to it).
function EllesmereUI.CreateDefaultProfile(name)
    local db = GetProfilesDB()
    -- Reset each addon DB to defaults, snapshot, then restore the live profile
    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry or {}
    local backups = {}
    for i, ldb in ipairs(registry) do
        if ldb.profile then
            backups[i] = DeepCopy(ldb.profile)
            ldb:ResetProfile()
        end
    end
    local snap = EllesmereUI.SnapshotAllAddons()
    -- Restore current profile data
    for i, ldb in ipairs(registry) do
        if backups[i] then
            for k in pairs(ldb.profile) do ldb.profile[k] = nil end
            for k, v in pairs(backups[i]) do ldb.profile[k] = v end
        end
    end
    db.profiles[name] = snap
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
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
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    local profileData = db.profiles[name]
    if not profileData then return end
    db.activeProfile = name
    EllesmereUI.ApplyProfileData(profileData)
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
--  Auto-save active profile on setting changes
--  Called by addons after any setting change to keep the active profile
--  in sync with live settings.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    if EllesmereUI._profileSaveLocked then return end
    local db = GetProfilesDB()
    local name = db.activeProfile or "Default"
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
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
                -- Auto-save current profile before switching, unless this is
                -- the very first event in the session on the same character
                -- (SavedVariables already holds the correct state in that case).
                if not isFirstLogin or charChanged then
                    db.profiles[current] = EllesmereUI.SnapshotAllAddons()
                end
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T3xAVTnYs7(xz(49(HiW9f5pz7eNe4jXgoAEN4dgadkjAl(AjsDiPghpb()(TQEH9c7MsYlzMChhGdoEOi7LA5PEQQ7M87N2emEvEBg8hjJZ3u8LzzlZlDgf5NI)ljmknij9GtBIh3mRopV8dLUbbosx43l9cJCo4bSLAVFDo8)D9MLlXB4pZRBkQklDpa)X5zKUjC81vLTnWFfn(MLvtZw246m(DFBDDEtZDz3FAJR74QnTllkZ)u1CS9kRkZH231B8SnnTvRoUAzvDdPTMTmRP57p8a2AzZNxvIx2lA87wUmVzvED(V9XJRQwoV6UYpLvMDtE93jn00nxF9rz10Plo(s4xcBG0XnlQUBsb0atWjYQSVH)szczEp9MdxUErgiLcitSPz1Vh(ps8G)lyQmTQEEE9xk(lEdJT1hNvvsAQM1zZkkVP0J8tfWLP3jTPZlZMUmF(jKUH0oxu6W7e4ph5eEG43oK0bqxEDXY286FTOPTXzm(7vxFDtE7xl9DCKU)JiTv447kM3UO0ZPRLpc144icuj1v39BRprQzjkb)XzuDkTLEpPLIgViV4MfT8rpTxVS8n0M21F8MM8JrnerJDc(elRMDlmbbfMx44RwvCtDwB(8ZatL6I55FzD(YLF8TntipnyrCBr5rKEeVKxG4johA1I)u(bIhpB(kMcStsoHndB(oQ3dzd)jlkMDBjyVH2SlkkXbgkgUHkHCJrdWZU(ISYBYXH2YS7pHyx20Mn72JR2u2Eer2hpUCZQlQURHPQVn)(PfLZpeKNOtJBa)kNXuiE9uF(4TawCZyMPnsTZ75k4M7kwNZT6IPTmAw9LUXZjejww5Sfv1NX0doKMFkoRg5OyGnH0cZwKvFt(jG7i1g09Gobb1StF8JQwQIfUP)NIMIPfllAVh99wcUUneze7jOnjPvI6MCI(IA)pv2feE2SzTGs9WYIvepQq6yaS)YA3GQ9Zkp(TevAz2QCqODSqOPAAcQAABbsOwsdI92YI)6VYQNRPkVG37IlXe8EuHX768krP5fCPjmVODPIjUQZwctLmPc(HnTeXfv711xczVN74fGtWraquZVViV8JL05WekUcouO2akgBSHVpX19Tf15WZa4GbJ)13DYetisEosYzLXokdqGpqQ2wGGasiueqF2nCmXWPPhGgiri)mtRmj)BTtOcn0JicVJumQqBbO0pRUiVe0oWGTVX7xlLbUywJYAiQ1TBY4fvBAG()dGG7DYg30w78QMcM4yz(1TAgzCDetss9PtPZ5fzR5XE4YH)tv1kUYhNuVN)FWCAEF)H5xlLeBNs7Mt0gfOc8HHHN0gIpgakVd0r50hdMrMunBnaNzcEsywWSn7dmPbYPanPBgQckzW39FiasXJ)nUSsdoYcqQju8xeCOTHh(daqkC8fF89FyprKucFjHg55kCReOrgbrEcGsA4p2aBmGlzf)rkGahCXaKKLGZ)iGM0iXSNatMh3BL5KcWupAuMGLcj81Bo1em2JerYgBnbWKI14plGsHJpIkPECqs6g4)lbssNd(amJ89e3W))iwKzYg)iWISfxylGsBnzoDbLjijtGoW4HwbIRcUYnW3lX19Q40OtnNIMjmgfAodaqydmWIxXaU)EEJpMmM)LUKL(fil5FX1KtCmEHjyvCusi1eaGfZ7NQBVkmY24hDbt5iblVpo5Q(uwloJFKrhClX6E8U465EBpfgDFCtEY9qdTHzmaK6lGtUw4m5Gs7LB9JKPHj3AqHWCRdr36uhhVRId)b6vRhI3U3mOdzEZe1f3tUxO9DjTIN9i2gHe6HXybct1jElUQ2DY3QB7Zwfl2t3gtrMTfe3arM((3wXhuGrEIERgqBfXiyCW3l32hrLl2E04iMBB8vbob)a9B3)OXM8F965)AizI)MCF7PSn5rRvJzf)Rxoh5N)4VMCBhkFddE0pnpxBacpNE09J1OfRyVCNFgJclCNJb35GWWOKRI89(b6oVhHHdh)PIMz5lxMvMdAmdXG3jF4xkw0gzaygSs1FvnkSfW6xoFADmThRNSkt6xQCL75SVNucEIEYdL(wY426IYBZBBW1ghEy4hEB(1zBwsw69HMNp5vAOVdU5kR5AOYDgRl3aUY9zxAWVZ86NAc4QxPhnYKBFPdSZvSBBE12nKnua5DjfafW89MqHjFc7bomM26WfzZ(QfAVEDBRuFBfd6Xw4UEObkyPdSORMleRkUCVvcTx9Jha755K(GREn6usGN4rsggmJ2jpqSjO7mJoWMVFQnY7i2047Hze4(5gf7gh6L6tg115lpVQOSfgHh)Upp5DxG7KL1AxXD83kFJBs0O4G0KG4axpWd8HtTXTG3BUJIdDCsDdd9I9d2ZUZlnAeUxPWDkLxGh2DsfpJ1fVjnEusIVRpmDccJ3ZUiWBuCuusCKNNtSJp2fm648MpmDuSBuGVtuuGtK3(1(ufNXIGWLqHuruSxqCQx4(18VX3lzuGBuuyuqAGBa2BDRQSK8jonnXXjj2lXzpv5rHJcanGBKdiMIoGeYZF8vZYwdWR5ZpRCgHVUhVtL445nUD6uHH5dNkdVlTdXWFiwzBLTPUPc3nzasZS5K))f5FdgyNq(h6jvNnVytdDTkdh3qBjYwJcW5jWejS44fLGFgmkpRC59eFki49naidCJlXDyLe32tiZn9nwfaf3cEQlYjECDDMXwhqQML10ECr9SL5sdC)tomwzG77SVdC4kaQv9TIytIPseeIOEv2YHNlt0NlguKY88dbIozflprmnCo(TEPV1ylhpUfaUHwcHXWX1v0H0de4tjL7Nbs(RxcXGBOBxWfRppVEgeacSuGUSMQtGEaBVVSSQ9c8k4fwKNTSDb7UjWLTvRX7GGu7rIuep(6kWxJmQKIItdXCcgOB(Y7)85h3GvzYJOSalXFRem8ZRR3SUTykrXbS6ay7acBIX3i(ZA6FsHErADy))vA0fo7G55i(Xh7wpDYaZN3xFGTV(IPi(8z5KQ1a2wEz(Q7rjenQgqG5TijgW)bdlkX7jgN78()9q442fD8mdOBd0WWXFeNvxNnl)poCoOHB(dj9WFSkFEr2FqU1)qShrhnzckA8hFnxybJg0e8s2K8nESG2u1bmJMWu8sjHd2nZ)eySYyr4fqNSycExklSGaRR)8MvtZXayY1ZB2mSvjQrM2WLPkCz6bkUrISauwpagDKnW65v3beTe7T1oDRFNQnjqPjd4MvkJ04XRZkNNVQy27xcK)wNNpVmG6OQQTzxKRBKUi4pHeHAjnq79ljUk5CnYMcIo))UjVP9tvtLTGpHorfkCfdoFQpJwNXCey5viVRAHFQoRo)DaADUyytKzosYS3TAD79QImVorMxNZajOmAD39GOMez42cICsVHYhYg(TlwqN1lzIHM5e207MkpK5IdUtCFjhMkI2PMKqD2J4OJilfaneNUpwEC1QPzTDtwx)4UPl)VXjCcBqq9YXH8VVaKKNqgaktfLQwYSPugxrDJdvLhOhua)uEiiQAw5TFiR5WBaA4Dd3iHYjrODCiqvEcyMJZribnFW11vxxSmhiEsWKtfW1)YB(LdRZZ(LqpC0kHE8l)F8U9)lvqizxQ4bW7YFf(rHRnfZfbve8RbXJqZ1dZKyJkhZTdKe1L(y)tezkg1A6FUQAxSUaOhBgRqVWHfphdHDPAVWNzBVxIL8xugQHJVfsUBc8)uIErbooSga6LxFpwiLoJG0oBGGotGywh2j10mnD5jJQ4Q7ejS(5)Dn7V1NahDJ2ZMiSfDKngt8yIy0c(xRWSTvnIDftGyXZLqKz0traAHiQPlqGcsi6qWPJleXNsf6VJKsZePzlf)nva)EkA3l7zjH96PG9tVc3IsQefrcGynZpXW59zRPfOXVtrVDRfGMgnHZZHOS5T9cBadN5RB(CEw9UlobFUolITpcsv8MLn7zOXBfhQlCTeIhJ3IG0xIgoLeeHsG(lvjC1rE7I8S53BiCLVG8wk1geI0ntnMToORwFqQEsx4BAbLeQ1Ef9)4UF6eILH0GF7s7OEKVOPyrAygIiTAkkSfe0wJf8wtcfZD3WyMd4ISMf)ArzoJmnnDei5Sze)lHcjqWY73jNSLOduMoO1GKsYNfv8sjVrPEtYLkMWfKKhaLIY6)Nsx6rWbu1Ze5FXeetumbikOTlhDydhYKIfOamLzrUTYirqSxJbOqFZ)bxQ4qyCqGOBiz61MTED(8oLIqLiuiHmSur0pLEKjikUUygjhaY8qL7KuWxLhnvH(hNHowU226cyy9M)0JmtLSlf6rq5KVbY9B5UHKKiXfYOanwXEz76nxkpk516KBikGCDeI(pq(jAEeuJl5j)27ViztITE7E0C8P6BLCGrAEk4xcApXsuq19o4EyAzgcq66S86zcX5SieoBF4lsT7dg75q5P32AnmdwiO5NR0I8iyp45P5tstTte3uN6MSDCkzS8fPQKOLiMwoDEc70eLUv9PqWi6roKuces2H0yRFNCjoGLO1R1M(t7cn)yktHkZnkln(4o4a(SjLjG15NX5HXFc(FZ5Trhx9rIhUEhSkB0nmc7AZHR3Hz2Cm4bERXanyqj0b4Ewped8)gUejBfOFaEISsOehpyjueLYANlSYJJa6qfBXivudLAzVyNAHBJbEMBtrpaAzpcndwZgHhyxfBOLX5bvsOC6MD3Ryef5Xy(AQappgUNrK5wUWT0Zx0XHUcp5OWUmFgUcq7DDEmZqZy9NmsuMXjMpO9fU9CHLkDwkZxtPDHR7BNMws6nqLOSqeDO6qrR5eF46PnATsDBB1GAReTSuKkBXfSq61cds784SK5GLU1ad(bR9L5q92Mt2OXz7(nqJBG6eAUez2OYzRp3nEVdwOolm46xtABJbBL1ZkxpdL0Jv8UtTbInyjcnM3tFIAYiQEs42egedwZWHYv2aLnB1i0Evfmqt0AjN4LwIpvCKewsLCYuIo7xvkTUwdsEgeXHsgXgkHPuOynNDdjs2tr8v188KNaw(j6ZTDd3(5CiBI0fzaV3KXRkklMcUWD6Gq3eH5uGFNoinjGbFyCP5mvCw7E3YEwAj8k)tAmuhOKU2RQGDk)9xWa6cdWN98LlGVmcu3jDQQ7sp1VIY2d4yzvrmxSgAZ3pph7fa8Qz4nnCHi9c6YT8lGLmBxXHtGgYsVVOQPTqA9vDePR5Y7pGdsQbLTYA751pfwk5h3q2Cgf2wRhHf)pqhjNKy32SIikE0UHH095decu5ybz3AWEvk6kzM26oGOgVdTjph0j0T9eEPdxU8TK4anN0tCE5UbFzLsNYIHImzjdwnubU3)PAOcC0Ih0yqZPkZV)qHnbsSMcIqKMmsfum1WTa3z3MwEtbCoWxaFx4GoRjYl1fYZf36xxaZxystEj44AylWGK7HrtR4(yHrvUA3YOth1aRcW4CZk0Yq5TRd83EJPBAopWy5MvqBCv9Ms6M0OfPZCl9VP7teCpZbS(Bi7BJ7Q2uYoTlfL3E)vtxImDWB4Ug2UaPUAnyFpHT5sNIBKeYWbsURDXYI)KEbavbI5IpkwJSmAHytgFhmvUEt99SmLRy9v2Q1llU(E6JMaozT5xLn))L2WqdTkVTQ8Mn09Sl5xBYkNrlC2D5zRRkVkVC2c6Kb4ram2GgeAnAIiqM0xdPVaCPXXeCdW)x7vBAYNtqEiBkZ15ZkYw285QYpY2(me)npXd)7Ko6D0(rTru2Bp(s9hmdvVtqzJ6I3w0a(J3tEnofnE19TGi9uAIw3E)rOq))uHiioJFaf0ZP3(3rHdASIBXvuUj)g6sEmKGVfVUd30XLm2kZi7mQdj7HhcIAf6i0EpDidc5AKYslaRKbdOp9U3(XF7t4TDpppnhkfTBukDMCu(4yscK0CRH)MYlGSVo5hYF6U4Jqvj)BSdXooDeM2hG953KHyO3HmWilUBh)oQ)7wc09aEFBkX30vaYo5(UV8n((PJs8H)HBHUdu2EBXJNC2503wp893M0LWn4MRtum5PJ8stJit4usothX3eGuAzYMuNO7OMvmb3Lun3EpXvzk8aBAjEhRQAVJET6QY)kN5Xu32BVKft6LZAxaihFQOPHz3hsIuOdnaKMQwsD6AwKnV6oOjxrhcvRiopn3do1vTfm3RPqRMxF7v0ja5oMN)NvxrItsBVRPT388R531dgN8tKh4pqX4KGl)TYI2tqZq2(7QjFz(Sw0jQVXo6KbYcqA3slhIy)PrE5IXcKSLgXbAeiNakdawirYvyfv4sUjOHcPYT7528uUTQwMr0w7YY3W2zd8XmXV3BShfqGCtatKZ4UKoSmzOoLQjeHmrOH9HyvLTSd)crElp0XBrEFvTaIpVCxPPUMLLDbBxApnh86jccYVWOjY3G1Q75BC)WtOwjkzhVuKYJpY9NsLkODY5mjZj9ucFLZCt(I0c9XRhiKGhjYTMCHNrgD8Wg1(SeQjT2ecwA9QmSWhRZRxVM090663lvXi5)jxf9(xFQHR)GqiGCC5kQtfL(NfvGowwWglqSJPI0(deMvmbtF9Uq4OvcyUbwkJRR9AdZi6klqfdkMHjJ4m99mPuHuHylLCwrmAKtiREeFQumpxBZWdabZZPUVCdb6X7iPZLbbE4)9x7kox7usfLwkV19fUzeJmR(1yXcfMnYnrANx2x5pUb1aMaA7uYds24qCc9SBv3(pKzwDsXYLcdlSIMPDMmjutf)ap3KOodSa)up3Wy30O0u2LRl57pCHEsriqxOiEEcB3P3H4f(XYlG4xutsA91WwgmqOYvAXH620OzBAR66kYl9rrDpCFcOvUs6LVQQ)6Jj5quc0eR4Qvz1YVwrRmBJ0BQHEOyM2HeDnR0eYdV6r3CMe3Pa8sIafTI9TUOeLc7Pl58X6Jj5f1ZhqDvpsWwNKNLQdEIQ8F76A7WnscZUrQSWChbic6Cm1aJPK)(cmcNqmp4tidG2dg4wikuS6hmiHd(gJLHh1TjaSJa2NBqQq4OTn)zZ2VkjYKYhMz5qDEoKCkMOXnrJdMnPVqCQSVWKf(0FGYHwLNHRlZ79CihmkrsfIhrkGbsJQeHdQk(hFgCjp4RUPj9fa7KtTWQHitKKDUCzKuN7qDMudYo0k0yMNKxQLbN2TfB522kRoH0GPGnrmlvfVKhNGGUSxSVKb)y(GrsgE6okds9rYIvbYOZI9strhzZst84MCQDEC9PujFMC1ij62b4Iho2thGLsxqEvqpvwJceBUZsh8LGlW8CXQBj4sqVrfkvW4TZB8YExr1iqqc6uUFgmJuJXtQXBK0XgqAnzOLS0a2)rcjw8bNAJ5iB52NSihZEhtekcsCeEq6z7ChZBHTQVAOpbsMwsxoHXJP3YPKvkTd1m1nKWccgv9iztohW9AHrojXjb(4XFZpnvEBceJzU7heb)AShtmoaxysrdBRApNUzD2lVYDiBuz6jdA5V7kfTeJ6b7Vp59qoGGwsb1qWCPzGSDUJl1w8rKsXEMo7lwwyee95z13sCAoHIfiodSyTWWmzO73cEHIsc9WtlzyKdy15qDLjvakcpcMaz9uphuL0RurpGLizTud57okmX33jXZnn1L1qXrbyZNgfgKeezRHaRBssv82ko2DKxqAQxCONdZX5BLr0EimneUEsIL2cnzjngddM3ME0QltoaQ9pzNQj6rMpXX4ipi0lWjMvX(VvMgfdUTqAmXbEP2NoQYyZthxVOKrWOY31lXj0wB5kVXp6MlEBzUikueTyGHy)N4fbOnEX8(p2XFKBuStCKRRJvXPhBYOnLccr5GBQtQBCAxtc4yJGleK4aGxMBsQkYWPLLQ1M01ngY2MUqosR5DglWgDDloILrUkJypgpTE5gnCPsmuUS9Taq0cfsNbhoTPQE6JPiqAuEnNXUgMya7WcPMoe5mfTyBrtofPxP4cXAuCGMq(6uijxnh9owAMZAKt6U8XY6pQkvP7ybs1u0D6aL7vIjUwRCPj2mjUh0tFjLIoTqwwcb4s8P4L8NWlQda81qU)RnKRzXGN74RKb0(e7djcfQJxinLbJRRyzHJcfB6Wq67Wa5GkMHgFbkePTSmETuKpMsrATAfpl1KC4QE)svuYDmw7p66q6mwQMu2GXirj3HQtkokjsseXb07zQ4L2lA4wJx3R6M6HPF81iYEjphUi4gccqjFSNvhtVEBwYD)XvwvlvNC3dRAzHAEElXQsTL1RVZZvPu3XIn(mvy1blzSzEfgk0AV6xATsQBBLt2wXgTwbutermr50qXpPqu6477vflTucr7fSulpjpI)A)xmO2kV6GfS9Pul0DBj0Twm09K(9utl8Z(xOuBPx9pTQLQVcOp(6CASCQA1C)LVwOwZvMgf1meGl59ZK)Bv3og83mu8nNdVquty52nPRSqtemWrzOsT0O81KltYeEjy0QU1tNIUoL8oFwtmYnMsSbI3)ZLITUT7JJ(RbkU2RJqFkUwDyS4MS7hAppfVlJ1lABlXoTupBHKQ9c68K4wYwdwRC9uyUm0ryJ9jJyllu6JMwLsxRYUxNvKf2h7ACEZb1tupJxuTd)ui1pUPHWKjS3QNZihWIpwohpwEvSJmld9)XedlTxlIJcp2I0)pQWy7tXdLdczpVQEL7y)QGH1JFLS18wogwaubUZDfZQjvKGrtovTaOejhXgWxxJ1zqLYmBaPWP7FXj29Aq03mK064bxGG1D6W1ByV2fMr6DLsmRDO6bwkJSTcjSLnAJuwlYNA(TxcHPpp1iWkX8b2ysQ5p)4suUxMwMYtDNtnvBfnEosPmrBbh4vzYqwJMYfZkRrRLByWmyhknPbQAYqjAAB7QTxP(ynJfl1XW4ATzlBuPClPGhgZTuRAE7yDwuE5lqcm0vBShFLTgyF980YhDRLBOhQwh1U(PxTRfMzGIlBOIcMRCG(2NsoaNYHw3667nqzusOr6yvdqeMZyn40RELxprMDE1628ww7Ny8eUaPJa5CgeiT2pgU(udxNsiD6oxktATuzmQuIqn8RYefdokJb5tIh59n)r0Vd94HqCtdyOOlBKjKKglrDZxKZwKtaledTn(nT35ZUKp(bNlTHscgd9RpPdUV8nUqUDKdnKNtAueTUL7ZzokngetXXrjobHbP0Dvf0(rS2poyuSJJJl9DsUwZVT3y3UobUJGrf9nUo)Sx)UVbcvMaCdG7wYNkHXj0zsIxqSt8Epv8saZfySgfNeqpEeKPINKOYFewvdixyNOG9U9dsDhfhd2JXXEbjDTFcV99tbnboas8DDc333F6UPJcGNnikal5syxZZF7S)MOqY0ZXpbUP098Tlpb6nE8NYkqRwEtMeIB3Ou3OOuNG4924bSPhf56654heI2E0sv9UYz4xsasORUXot16NgL6sISUxDKliVXQBK4hfIhSoUSjUt16gpYnnnne(dxssB7HS5nbEeXDe0K3inOHbAa5voFAItQ32Th1m(J9ch547dtyYlR)hWh)tfZQRu6I4yY3vG0i3Kq)9Sl8I8rPsSNNRtuk59pu64VqoBCYkzyCebsnhWl0v)16)2L9XoUJcsCJdcavmFnXppVvQh8s8h5Hs)yV4q)09v6h7ocSaJ8ctJJcJ6uU8pteVbaGig(bakLFS3(18WJs2NDKpkbGEiKEqbd7E9))U53KRd6Y(mBGbnX3LyLfROmjqrsedOwk1AYc54jye2ddpsP3O56pIeBiv8uAnOPDRLBxweyONo3zs7SPP77XXBZAZWBGotwxxroC89gvqR9F3KvtEv31qRuu3GHfrKCIFzuV5Td5AUu6iurrVB2V7MnxaodhT3NHxv8sF0tcPfuxmoeVZtKNLpHa2byyz1WXEJjaF0twCxgow)s5eZOwHfJr8Qzcsgr5B9K83BjKid5Z8dm93odmy4SeFX(UOUAZnlO5vO9bAchIkFp1sK(qqr6b2PXpI)K7uxl9jwJ9zZX030iAvTLAxPe9IzF8N(cj1gKKqdDLd6M)s3SXpIrDIx1EeiGVxR8IpRT1(coKToxpDhjBhlTK63QiVXBwJIkqbtCa5BydjBOVYZNFfi8YR(Z8ALpbw6zXTTrqVpbrmluPPJOsH9lpAGyyi95gou3IPJqU0BHMoNNUAEr0PNNnFExUnUSlQ9z4krE4P81WQs8XIchUlG)7)cmmWV9iYJv6hib8vomv(snSaRI55Lu5ic1Z)uhPW)9vh6(o0Upg3zvz8P)D4iBQC)Vm(X83Nx9DKn7b9c7iBabZa66Kt)NIRCs3xdUthWp2mMOM39a5B2hhWClA2N2QdGzBv7tdZweAo6kjY(ZjMKb59ZoY0JKQX)aWM(bsYGbFB2r85IOHjUd7bILzNIOX4fQbb9N5tgwUggqGEgr4SaM944FOeBUxicsQ1xKVMLA9teJYSTz447iRkvGZaHKu9QNGdRfSvfj5GbMEwD(6jT(Wzx8X)ZzFEYH)6dYLr7Nt0TxzCD6FdOAwHXmq9Qh9S9huBVGW21SNSGtzet7VDWRDI01KhKRB9pN(Z)yyRK8QF9ZQFT3R(1pN(1IGApGSg(65)BJvIYQL9kqMDGS0HKX)lgitcCITlw6xsi71e5vCSxaCmdlp9tep7VLkbf)Idj59sbj9YMReZL)vWONlwvjuXZRGrppGrgswsExN8tgwK6(z5NSbV2oL5ffn9F9e8O(PVIP(AMQVaGQkm8K3BA)C6t)YYqY9j7l)k)OxRM8lMVSTQjh8ZR)8pMy0Vwn5Nx)6xJr)S6xlfJ(HtP2oIneTrX722aUWmLV5E5DZdKZPR02f(I8MQn1eo(0VBn45aIroiemxYMJZpfJxIc5qYWqjqS)4g88IkoUu4DK21gVVKEUJexH3gzKZQi1alC81flxEeCVK5MHpGqjUj45biXninj2v7GmS9nRFAq0i8varKVVti9tieFo9EYiORK5EosJUllFtiUNZblQBUGAYs)wU9f(CEIOHoICdIj6rmBl5VHqPSNgFR4sEdEGF0d7on8Aw90drk7OJIdHJy8GA1oww4VDyj9tuEkTnnPlUGPlGEQtNXPwr76lyAd6IoqFTUshYKVoJ0cWYBoarrDTb46rQgghuVxs7I9EAKw3Fjt4tgZY2cODtyivpDtEzED2YVRB1m06uqLN9pbBjmtlMzDNAgp1IpqndWZ(23j(RTlGNCb4pkfYq9dPfZKyMy)YB0FPscmv9DIS8bluX36eYmO1WHb1rmUUGcliDfApk5p5Lg46ghfe7qFhflFZhXmiS4k4gjn4bze7OHbsvbgmZZWWROsv3cLpKwkw69T)yM6gAZod9qTzchMPZ0L(2A0z8Fw0umTyzr79W8IgTq1mv240H8o)Xp2dpXFDwWME9BoSLx)pLAqu1UX65ZyFeTLS0dsDC59Fa1QFDDXQS67nBjIEIbmRxdV2aE6wPU0xejIxgg2nBDoqlKWoy2IFrZPhoZq)4WeVbTI1TXrBd3OeWMoiWZXXN8Y)WInCSQjCObtybkGZEyqNWEQjvyu786PxroBY1SiR)qS47je0nZ8C2tFIlKGGvGXFoCc8Kg(473MISLNvU8(t6J572)mEbHHYHiHZT6sCc5t4xw9rSWKg8by)(HmY3Q2)qUhvZ0QmQ2luGDc4EsFBDhk6RNFiIgpSXoB36QzUh5gc6AV4GqNuk5hsqzvciVNzz1zT7N03ANAF72ZEwXCny86I1Nzx5MG)(VRAvPyzYNRKipUDw4U9S8nW1VVHtk2DFqIFg3RqdapuZ2nz8Sf47)S5hP(FEi3PeA2UVzMhy33Wnqm7ogtoQ0FqZzMD2fmGcwVIYLyUp97jDi7gFV6nIZLGGd0HKfojPh8a(V)F)" },
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
    -- These should never be randomized — users want their frames to stay visible.
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
        -- Save bar visibility and all spell layout data per bar
        savedVis.cdmBars = {}
        if profile.cdmBars.bars then
            for i, bar in ipairs(profile.cdmBars.bars) do
                local saved = { barVisibility = bar.barVisibility }
                for fk, fv in pairs(bar) do
                    if CDM_SPELL_KEYS[fk] then
                        saved[fk] = fv  -- shallow ref is fine, we restore before GC
                    end
                end
                savedVis.cdmBars[i] = saved
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
                    for fk, fv in pairs(saved) do
                        if CDM_SPELL_KEYS[fk] then
                            profile.cdmBars.bars[i][fk] = fv
                        end
                    end
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

    -- Bar texture (skip texture key randomization — texture list is addon-local)
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
    -- Register pre-logout save via Lite so it runs BEFORE StripDefaults
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Default"
            db.profiles[name] = EllesmereUI.SnapshotAllAddons()
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it
            -- instead of inheriting a spec-specific profile from another char.
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

        -- Migration: rename legacy "Custom" profile to "Default".
        -- Only runs if no user-created "Default" profile already exists;
        -- otherwise we leave "Custom" as-is to avoid data loss.
        if db.profiles["Custom"] and not db.profiles["Default"] then
            db.profiles["Default"] = db.profiles["Custom"]
            db.profiles["Custom"] = nil
            if db.activeProfile == "Custom" then
                db.activeProfile = "Default"
            end
            for i, n in ipairs(db.profileOrder) do
                if n == "Custom" then db.profileOrder[i] = "Default"; break end
            end
            if db.specProfiles then
                for specID, pName in pairs(db.specProfiles) do
                    if pName == "Custom" then db.specProfiles[specID] = "Default" end
                end
            end
        end

        -- Migration: remap per-character profile keys to named profiles.
        -- Old versions created profiles named "CharName - Realm" via
        -- defaultToCharKey. Remap those characters to the activeProfile
        -- (or Default) and leave the old profile data intact so nothing
        -- is lost. Also clean up profileKeys in child SVs.
        if not db._charProfilesMigrated then
            db._charProfilesMigrated = true
            local fallback = db.activeProfile or "Default"
            -- Build a set of "real" named profiles (user-created or presets)
            local namedSet = {}
            for _, n in ipairs(db.profileOrder) do namedSet[n] = true end
            -- Scan child addon SVs for character-keyed profileKeys
            for _, entry in ipairs(ADDON_DB_MAP) do
                local sv = _G[entry.svName]
                if sv and type(sv.profileKeys) == "table" then
                    for ck, pName in pairs(sv.profileKeys) do
                        -- A per-character profile is one where the profile
                        -- name matches the character key pattern and is NOT
                        -- a named profile the user explicitly created.
                        if pName == ck and not namedSet[pName] then
                            -- Remap this character to the fallback profile
                            sv.profileKeys[ck] = fallback
                        end
                    end
                end
            end
        end

        -- On first install, create "Default" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Default"
        end
        -- Ensure Default profile exists with current settings
        if not db.profiles["Default"] then
            -- Delay slightly to let all addons initialize their DBs
            EllesmereUI._profileSaveLocked = true
            C_Timer.After(0.5, function()
                db.profiles["Default"] = EllesmereUI.SnapshotAllAddons()
                EllesmereUI._profileSaveLocked = false
            end)
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

        -- Migration: re-save the active profile after all addons have
        -- initialized so the snapshot includes CDM specProfiles data
        -- (previously stripped by DeepCopyCDMStyleOnly). This ensures
        -- new characters seeded from this profile receive CDM spell
        -- assignments. Only needs to run once; subsequent logouts will
        -- keep the snapshot up to date via the pre-logout callback.
        if not db._specProfileSnapshotMigrated then
            C_Timer.After(2, function()
                if EllesmereUI._profileSaveLocked then return end
                db._specProfileSnapshotMigrated = true
                local name = db.activeProfile or "Default"
                if db.profiles[name] then
                    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
                end
            end)
        end

        -- Auto-save active profile when the settings panel closes
        C_Timer.After(1, function()
            -- Restore saved profile keybinds
            EllesmereUI.RestoreProfileKeybinds()
            if EllesmereUI._mainFrame and not EllesmereUI._profileAutoSaveHooked then
                EllesmereUI._profileAutoSaveHooked = true
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    EllesmereUI.AutoSaveActiveProfile()
                end)
            end

            -- Debounced auto-save on every settings change (RefreshPage call).
            -- Uses a 2-second timer so rapid slider drags collapse into one save.
            if not EllesmereUI._profileRefreshHooked then
                EllesmereUI._profileRefreshHooked = true
                local _saveTimer = nil
                local _origRefresh = EllesmereUI.RefreshPage
                EllesmereUI.RefreshPage = function(self, ...)
                    _origRefresh(self, ...)
                    if _saveTimer then _saveTimer:Cancel() end
                    _saveTimer = C_Timer.NewTimer(2, function()
                        _saveTimer = nil
                        EllesmereUI.AutoSaveActiveProfile()
                    end)
                end
            end
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
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
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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

-------------------------------------------------------------------------------
--  CDM Spell Profiles
--  Separate import/export system for CDM ability assignments only.
--  Captures which spells are assigned to which bars and tracked buff bars,
--  but NOT bar glows, visual styling, or positions.
--
--  Export format: !EUICDM_<base64 encoded compressed serialized data>
--  Payload: { version = 1, bars = { ... }, buffBars = { ... } }
--
--  On import, the system:
--    1. Decodes and validates the string
--    2. Analyzes which spells need to be tracked/enabled in CDM
--    3. Prints required spells to chat
--    4. Blocks import until all spells are verified as tracked
--    5. Applies the layout once verified
-------------------------------------------------------------------------------

--- Snapshot the current CDM spell profile (spell assignments only, no styling/glows)
function EllesmereUI.ExportCDMLayout()
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return nil, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return nil, "No CDM bars found" end

    local layoutData = { bars = {}, buffBars = {} }

    -- Capture bar definitions and spell assignments
    for _, barData in ipairs(p.cdmBars.bars) do
        local entry = {
            key      = barData.key,
            name     = barData.name,
            barType  = barData.barType,
            enabled  = barData.enabled,
        }
        -- Spell assignments depend on bar type
        if barData.trackedSpells then
            entry.trackedSpells = DeepCopy(barData.trackedSpells)
        end
        if barData.extraSpells then
            entry.extraSpells = DeepCopy(barData.extraSpells)
        end
        if barData.removedSpells then
            entry.removedSpells = DeepCopy(barData.removedSpells)
        end
        if barData.dormantSpells then
            entry.dormantSpells = DeepCopy(barData.dormantSpells)
        end
        if barData.customSpells then
            entry.customSpells = DeepCopy(barData.customSpells)
        end
        layoutData.bars[#layoutData.bars + 1] = entry
    end

    -- Capture tracked buff bars (spellID assignments only, not visual settings)
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for i, tbb in ipairs(p.trackedBuffBars.bars) do
            layoutData.buffBars[#layoutData.buffBars + 1] = {
                spellID = tbb.spellID,
                name    = tbb.name,
                enabled = tbb.enabled,
            }
        end
    end

    local payload = { version = 1, data = layoutData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil, "LibDeflate not available" end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Decode a CDM spell profile import string without applying it
function EllesmereUI.DecodeCDMLayoutString(importStr)
    if not importStr or #importStr < 5 then
        return nil, "Invalid string"
    end
    -- Detect profile strings pasted into the wrong import
    if importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return nil, "This is a UI Profile string, not a CDM bar layout string."
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return nil, "Not a valid CDM spell profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return nil, "Unsupported CDM spell profile version"
    end
    if not payload.data or not payload.data.bars then
        return nil, "Invalid CDM spell profile data"
    end
    return payload.data, nil
end

--- Collect all unique spellIDs from a decoded CDM spell profile
local function CollectLayoutSpellIDs(layoutData)
    local spells = {}  -- { [spellID] = barName }
    for _, bar in ipairs(layoutData.bars) do
        local barName = bar.name or bar.key or "Unknown"
        if bar.trackedSpells then
            for _, sid in ipairs(bar.trackedSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.extraSpells then
            for _, sid in ipairs(bar.extraSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.customSpells then
            for _, sid in ipairs(bar.customSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- dormantSpells are talent-dependent, include them too
        if bar.dormantSpells then
            for _, sid in ipairs(bar.dormantSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- removedSpells are intentionally excluded from bars, don't require them
    end
    -- Buff bar spells
    if layoutData.buffBars then
        for _, tbb in ipairs(layoutData.buffBars) do
            if tbb.spellID and tbb.spellID > 0 then
                spells[tbb.spellID] = "Buff Bar: " .. (tbb.name or "Unknown")
            end
        end
    end
    return spells
end

--- Check which spells from a layout are currently tracked in CDM
--- Returns: missingSpells (table of {spellID, name, barName}), allPresent (bool)
function EllesmereUI.AnalyzeCDMLayoutSpells(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then
        return {}, false
    end
    local p = aceDB.profile

    -- Build set of all currently tracked spellIDs across all bars
    local currentlyTracked = {}
    if p.cdmBars and p.cdmBars.bars then
        for _, barData in ipairs(p.cdmBars.bars) do
            if barData.trackedSpells then
                for _, sid in ipairs(barData.trackedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.extraSpells then
                for _, sid in ipairs(barData.extraSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.removedSpells then
                for _, sid in ipairs(barData.removedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.customSpells then
                for _, sid in ipairs(barData.customSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.dormantSpells then
                for _, sid in ipairs(barData.dormantSpells) do
                    currentlyTracked[sid] = true
                end
            end
        end
    end
    -- Also check buff bars
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for _, tbb in ipairs(p.trackedBuffBars.bars) do
            if tbb.spellID and tbb.spellID > 0 then
                currentlyTracked[tbb.spellID] = true
            end
        end
    end

    -- Compare against layout requirements
    local requiredSpells = CollectLayoutSpellIDs(layoutData)
    local missing = {}
    for sid, barName in pairs(requiredSpells) do
        if not currentlyTracked[sid] then
            local spellName
            if C_Spell and C_Spell.GetSpellName then
                spellName = C_Spell.GetSpellName(sid)
            end
            missing[#missing + 1] = {
                spellID = sid,
                name    = spellName or ("Spell #" .. sid),
                barName = barName,
            }
        end
    end

    -- Sort by bar name then spell name for readability
    table.sort(missing, function(a, b)
        if a.barName == b.barName then return a.name < b.name end
        return a.barName < b.barName
    end)

    return missing, #missing == 0
end

--- Print missing spells to chat
function EllesmereUI.PrintCDMLayoutMissingSpells(missing)
    local EG = "|cff0cd29f"
    local WHITE = "|cffffffff"
    local YELLOW = "|cffffff00"
    local GRAY = "|cff888888"
    local R = "|r"

    print(EG .. "EllesmereUI|r: CDM Spell Profile Import - Spell Check")
    print(EG .. "----------------------------------------------|r")

    if #missing == 0 then
        print(EG .. "All spells are already tracked. Ready to import.|r")
        return
    end

    print(YELLOW .. #missing .. " spell(s) need to be enabled in CDM before importing:|r")
    print(" ")

    local lastBar = nil
    for _, entry in ipairs(missing) do
        if entry.barName ~= lastBar then
            lastBar = entry.barName
            print(EG .. "  [" .. entry.barName .. "]|r")
        end
        print(WHITE .. "    - " .. entry.name .. GRAY .. " (ID: " .. entry.spellID .. ")" .. R)
    end

    print(" ")
    print(YELLOW .. "Enable these spells in CDM, then click Import again.|r")
end

--- Apply a decoded CDM spell profile to the current profile
function EllesmereUI.ApplyCDMLayout(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return false, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return false, "No CDM bars found" end

    -- Build a lookup of existing bars by key
    local existingByKey = {}
    for i, barData in ipairs(p.cdmBars.bars) do
        existingByKey[barData.key] = barData
    end

    -- Apply spell assignments from the layout
    for _, importBar in ipairs(layoutData.bars) do
        local target = existingByKey[importBar.key]
        if target then
            -- Bar exists: update spell assignments only
            if importBar.trackedSpells then
                target.trackedSpells = DeepCopy(importBar.trackedSpells)
            end
            if importBar.extraSpells then
                target.extraSpells = DeepCopy(importBar.extraSpells)
            end
            if importBar.removedSpells then
                target.removedSpells = DeepCopy(importBar.removedSpells)
            end
            if importBar.dormantSpells then
                target.dormantSpells = DeepCopy(importBar.dormantSpells)
            end
            if importBar.customSpells then
                target.customSpells = DeepCopy(importBar.customSpells)
            end
            target.enabled = importBar.enabled
        end
        -- If bar doesn't exist (custom bar from another user), skip it.
        -- We only apply to matching bar keys.
    end

    -- Apply tracked buff bars
    if layoutData.buffBars and #layoutData.buffBars > 0 then
        if not p.trackedBuffBars then
            p.trackedBuffBars = { selectedBar = 1, bars = {} }
        end
        -- Merge: update existing buff bars by index, add new ones
        for i, importTBB in ipairs(layoutData.buffBars) do
            if p.trackedBuffBars.bars[i] then
                -- Update existing buff bar's spell assignment
                p.trackedBuffBars.bars[i].spellID = importTBB.spellID
                p.trackedBuffBars.bars[i].name = importTBB.name
                p.trackedBuffBars.bars[i].enabled = importTBB.enabled
            else
                -- Add new buff bar with default visual settings + imported spell
                local newBar = {}
                -- Use TBB defaults if available
                local defaults = {
                    spellID = importTBB.spellID,
                    name = importTBB.name or ("Bar " .. i),
                    enabled = importTBB.enabled ~= false,
                    height = 24, width = 270,
                    verticalOrientation = false,
                    texture = "none",
                    fillR = 0.05, fillG = 0.82, fillB = 0.62, fillA = 1,
                    bgR = 0, bgG = 0, bgB = 0, bgA = 0.4,
                    gradientEnabled = false,
                    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
                    gradientDir = "HORIZONTAL",
                    opacity = 1.0,
                    showTimer = true, timerSize = 11, timerX = 0, timerY = 0,
                    showName = true, nameSize = 11, nameX = 0, nameY = 0,
                    showSpark = true,
                    iconDisplay = "none", iconSize = 24, iconX = 0, iconY = 0,
                    iconBorderSize = 0,
                }
                for k, v in pairs(defaults) do newBar[k] = v end
                p.trackedBuffBars.bars[#p.trackedBuffBars.bars + 1] = newBar
            end
        end
    end

    -- Save to current spec profile
    local specKey = p.activeSpecKey
    if specKey and specKey ~= "0" and p.specProfiles then
        -- Update the spec profile's barSpells to match
        if not p.specProfiles[specKey] then p.specProfiles[specKey] = {} end
        local prof = p.specProfiles[specKey]
        prof.barSpells = {}
        for _, barData in ipairs(p.cdmBars.bars) do
            local key = barData.key
            if key then
                local entry = {}
                if barData.trackedSpells then
                    entry.trackedSpells = DeepCopy(barData.trackedSpells)
                end
                if barData.extraSpells then
                    entry.extraSpells = DeepCopy(barData.extraSpells)
                end
                if barData.removedSpells then
                    entry.removedSpells = DeepCopy(barData.removedSpells)
                end
                if barData.dormantSpells then
                    entry.dormantSpells = DeepCopy(barData.dormantSpells)
                end
                if barData.customSpells then
                    entry.customSpells = DeepCopy(barData.customSpells)
                end
                prof.barSpells[key] = entry
            end
        end
        -- Update buff bars in spec profile
        if p.trackedBuffBars then
            prof.trackedBuffBars = DeepCopy(p.trackedBuffBars)
        end
    end

    return true, nil
end
