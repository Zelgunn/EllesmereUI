local ADDON_NAME, ns = ...
ns.ECdmCache = {}
local cache = ns.ECdmCache

-- region Per-Tick

-- region Tick GCD

cache._tickGCD   = {}  -- [spellID] = bool|nil (GCD check result)

-- Reusable helpers to avoid closure allocation in hot-path pcall calls
local _gcdCheckSid
local function _CheckIsGCD()
    local cdData = C_Spell.GetSpellCooldown(_gcdCheckSid)
    return cdData and cdData.isOnGCD
end

-------------------------------------------------------------------------------
--- Checks the GCD for the spell with given ID
---   (per-tick cached to avoid pcall garbage per icon)
--- @param spellID number       The ID of the spell to cache
--- @return boolean isGCD       true if the spell is on the GCD, false otherwise
-------------------------------------------------------------------------------
local function IsGCD(spellID)
    local isGCD = cache._tickGCD[spellID]
    if isGCD == nil then
        _gcdCheckSid = spellID
        local okG, gcdVal = pcall(_CheckIsGCD)
        isGCD = okG and gcdVal or false
        cache._tickGCD[spellID] = isGCD
    end
    return isGCD
end
cache.IsGCD = IsGCD

-- endregion

-- region Tick Charge

cache._tickCharge = {} -- [spellID] = charges table or false

-------------------------------------------------------------------------------
--- Gets charges for the given spellID, from the cache if present otherwise
---   using C_Spell.GetSpellCharges (and caches the result).
--- @param spellID number   The ID of the spell to check
--- @return SpellChargeInfo charges  Charges for the given spell
-------------------------------------------------------------------------------
local function GetTickCharge(spellID)
    local charges = cache._tickCharge[spellID]
    if charges == nil then
        charges = C_Spell.GetSpellCharges(spellID) or false
        cache._tickCharge[spellID] = charges
    end
    return charges
end
cache.GetTickCharge = GetTickCharge

-- endregion

-- region Tick Aura

cache._tickAura  = {}  -- [spellID] = aura table or false
ns._tickAuraCache = cache._tickAura

-------------------------------------------------------------------------------
--- Gets the AuraData from either the cache or C_UnitAuras.GetPlayerAuraBySpellID
---   for the given spellID. Stores in the cache if found and not present in the
---   cache.
--- @param spellID number           The ID of the spell to check
--- @return AuraData|boolean aura   The AuraData if found, false otherwise
-------------------------------------------------------------------------------
local function GetTickAura(spellID)
    local aura = cache._tickAura[spellID]
    if aura == nil then
        local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        aura = (ok and res) or false
        cache._tickAura[spellID] = aura
    end
    return aura
end
cache.GetTickAura = GetTickAura

-- endregion

-- region Tick Blizzard active state

cache._tickBlizzActive = {}  -- [spellID] = true when Blizzard CDM marks spell as active (wasSetFromAura)
cache._tickBlizzOverride = {} -- [baseSpellID] = overrideSpellID, built each tick from all CDM viewer children
cache._tickBlizzChild = {}    -- [overrideSpellID] = blizzChild, for direct charge/cooldown reads on activation overrides
cache._tickBlizzAllChild = {} -- [resolvedSid] = blizzChild, for all CDM children (used by custom bars)
cache._tickBlizzBuffChild = {} -- [resolvedSid] = blizzChild, only from BuffIcon/BuffBar viewers
cache._tickBlizzCDChild   = {} -- [resolvedSid] = blizzChild, only from Essential/Utility viewers
cache._tickBlizzMultiChild = {} -- [baseSid] = { ch1, ch2, ... } when multiple CDM children share a base spellID

-- Export to NS
ns._tickBlizzActiveCache = cache._tickBlizzActive
ns._tickBlizzAllChildCache = cache._tickBlizzAllChild
ns._tickBlizzBuffChildCache = cache._tickBlizzBuffChild

-- region _tickBlizzActive

-- todo: some of the code works the same way, just with different caches
--   it may me worth investigating a class-based approach to streamline all of it

-------------------------------------------------------------------------------
--- Returns true if the spell is marked as active in the cache.
---   When provided, `resolvedID` has priority over `spellID`.
--- Uses `_tickBlizzActive` as the reference cache.
--- @param spellID number           The (original) spell ID
--- @param resolvedID number|nil    (Optional) The resolved spell ID
--- @return boolean isTickBlizzardActive
-------------------------------------------------------------------------------
local function IsTickBlizzardActive(spellID, resolvedID)
    return cache._tickBlizzActive[resolvedID] or cache._tickBlizzActive[spellID]
end
cache.IsTickBlizzardActive = IsTickBlizzardActive

-------------------------------------------------------------------------------
--- Caches the spellID in `_tickBlizzActive`.
--- @param spellID number           The spell ID to cache
-------------------------------------------------------------------------------
local function CacheTickBlizzardActive(spellID)
    cache._tickBlizzActive[spellID] = true
end
cache.CacheTickBlizzardActive = CacheTickBlizzardActive

-------------------------------------------------------------------------------
--- Checks if spellID is cached in `_tickBlizzActive`
--- @param spellID number           The spell ID to check
--- @return boolean spellCachedInTickBlizzardActive
-------------------------------------------------------------------------------
local function IsSpellCachedInTickBlizzardActive(spellID)
    return cache._tickBlizzActive[spellID] ~= nil
end
cache.IsSpellCachedInTickBlizzardActive = IsSpellCachedInTickBlizzardActive

-- endregion

-- region _tickBlizzOverride

-------------------------------------------------------------------------------
--- Get the blizzard override for spellID from the cache `_tickBlizzOverride`
--- @param spellID number           The spell ID to query
--- @return number|nil blizzardOverrideSpell
-------------------------------------------------------------------------------
local function GetSpellOverridenByBlizzard(spellID)
    return cache._tickBlizzOverride[spellID]
end
cache.GetSpellOverridenByBlizzard = GetSpellOverridenByBlizzard

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzOverride` cache the `overrideSpellID` for `spellID`
--- @param spellID number           The spell ID to override
--- @param overrideSpellID number   The blizzard override spell ID for spellID
-------------------------------------------------------------------------------
local function CacheSpellOverridenByBlizzard(spellID, overrideSpellID)
    cache._tickBlizzOverride[spellID] = overrideSpellID
end
cache.CacheSpellOverridenByBlizzard = CacheSpellOverridenByBlizzard

-------------------------------------------------------------------------------
--- Returns the first override from Blizzard between `resolvedID` and `spellID`
---   (`resolvedID` has priority over `spellID`.)
--- Uses `_tickBlizzOverride` as the reference cache.
--- @param spellID number           The (original) spell ID to query
--- @param resolvedID number|nil    The resolved spell ID to query
--- @return number|nil blizzardOverrideSpell
-------------------------------------------------------------------------------
local function GetResolvedSpellOverridenByBlizzard(spellID, resolvedID)
    return cache._tickBlizzOverride[resolvedID] or cache._tickBlizzOverride[spellID]
end
cache.GetResolvedSpellOverridenByBlizzard = GetResolvedSpellOverridenByBlizzard

-------------------------------------------------------------------------------
--- Second-level runtime override: e.g. spell A (base) -> spell B (talent)
--- -> spell C (activation override, e.g. Avenging Crusader transforms Crusader Strike).
--- FindSpellOverrideByID only resolves one level; check the Blizzard CDM
--- children cache for a deeper override on the already-resolved ID.
--- @param baseSpellID number   The base spell ID before resolution
--- @param resolvedID number    The spell ID after the first-level resolution
--- @return number resolvedID   The spell ID after the second-level resolution
-------------------------------------------------------------------------------
local function SecondLevelSpellIDOverride(baseSpellID, resolvedID)
    local blizzOverride = GetResolvedSpellOverridenByBlizzard(baseSpellID, resolvedID)
    if blizzOverride then
        return blizzOverride
    end
    return resolvedID
end
cache.SecondLevelSpellIDOverride = SecondLevelSpellIDOverride

-- endregion

-- region _tickBlizzChild

-------------------------------------------------------------------------------
--- Get the blizzard child for spellID from the cache `_tickBlizzChild`
--- @param spellID number             The spell ID to query
--- @return Frame|nil blizzardChild
-------------------------------------------------------------------------------
local function GetTickBlizzardChild(spellID)
    return cache._tickBlizzChild[spellID]
end
cache.GetTickBlizzardChild = GetTickBlizzardChild

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzChild` cache the `blizzardChild` for `spellID`
--- @param spellID number           The spell ID to override
--- @param blizzardChild Frame      The blizzard child for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardChild(spellID, blizzardChild)
    cache._tickBlizzChild[spellID] = blizzardChild
end
cache.CacheTickBlizzardChild = CacheTickBlizzardChild

-- endregion

-- region _tickBlizzAllChild

-------------------------------------------------------------------------------
--- Get the blizzard child for spellID from the cache `_tickBlizzAllChild`
--- @param spellID number           The spell ID to query
--- @return Frame|nil blizzardChild
-------------------------------------------------------------------------------
local function GetTickBlizzardAllChild(spellID)
    return cache._tickBlizzAllChild[spellID]
end
cache.GetTickBlizzardAllChild = GetTickBlizzardAllChild

-- Table of CDM viewer names
local _cdmViewerNames = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-------------------------------------------------------------------------------
--- Returns the i-th CDM viewer name
--- @param index number     The index of the CDM viewer to query
--- @return string cdmViewerName
-------------------------------------------------------------------------------
local function GetCDMViewerName(index)
    return _cdmViewerNames[index]
end
cache.GetCDMViewerName = GetCDMViewerName

-------------------------------------------------------------------------------
--- Clear cached viewer child info so the next tick re-reads from API
--- (overrideSpellID may have changed with the new talent set)
--- 
-------------------------------------------------------------------------------
local function ClearCachedViewerChildInfo()
    for _, vname in ipairs(_cdmViewerNames) do
        local vf = _G[vname]
        if vf and vf:GetNumChildren() > 0 then
            local children = { vf:GetChildren() }
            for ci = 1, #children do
                local ch = children[ci]
                if ch then
                    ch._ecmeResolvedSid = nil
                    ch._ecmeBaseSpellID = nil
                    ch._ecmeOverrideSid = nil
                    ch._ecmeCachedCdID = nil
                    ch._ecmeIsChargeSpell = nil
                    ch._ecmeMaxCharges = nil
                end
            end
        end
    end
end
cache.ClearCachedViewerChildInfo = ClearCachedViewerChildInfo

-------------------------------------------------------------------------------
--- Scan all four CDM viewers for a child whose .cooldownID matches the given cooldownID.
--- @param cooldownID number|nil    The ID of the cooldown
--- @return Frame|nil childFrame    The child frame, or nil if not found.
-------------------------------------------------------------------------------
local function FindCDMChildByCooldownID(cooldownID)
    if not cooldownID then return nil end
    -- Fast path: scan the per-tick all-child cache (already built by the
    -- viewer scan in UpdateAllCDMBars). Avoids GetChildren() allocation.
    for _, ch in pairs(cache._tickBlizzAllChild) do
        local chID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
        if chID == cooldownID then return ch end
    end
    -- Slow fallback: only needed if tick cache is empty (first frame, etc.)
    for _, vname in ipairs(_cdmViewerNames) do
        local viewer = _G[vname]
        if viewer then
            local nCh = viewer:GetNumChildren()
            if nCh > 0 then
                local children = { viewer:GetChildren() }
                for ci = 1, nCh do
                    local ch = children[ci]
                    if ch then
                        local chID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
                        if chID == cooldownID then
                            return ch
                        end
                    end
                end
            end
        end
    end
    return nil
end
cache.FindCDMChildByCooldownID = FindCDMChildByCooldownID

-------------------------------------------------------------------------------
--- Check whether a spellID has a Blizzard CDM child (i.e. is "Displayed").
--- Used by the options preview to show the untracked overlay.
-------------------------------------------------------------------------------
local function IsSpellInBlizzCDM(spellID)
    if not spellID then return false end
    -- Fast path: check the per-tick all-child cache first
    if cache._tickBlizzAllChild[spellID] then return true end
    -- Slow path: resolve via cooldownID
    local cdID = cache._spellToCooldownID[spellID]
    if cdID and FindCDMChildByCooldownID(cdID) then return true end
    return false
end
cache.IsSpellInBlizzCDM = IsSpellInBlizzCDM
ns.IsSpellInBlizzCDM = IsSpellInBlizzCDM

-------------------------------------------------------------------------------
---
---
-------------------------------------------------------------------------------
local function IsBlizzardChildUntracked(spellID, resolvedID)
    return not cache._tickBlizzAllChild[resolvedID]
           and not cache._tickBlizzAllChild[spellID]
           and not cache._tickBlizzChild[resolvedID]
           and not cache._tickBlizzChild[spellID]

end
cache.IsBlizzardChildUntracked = IsBlizzardChildUntracked

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzAllChild` cache the `blizzardChild` for `spellID`
--- @param spellID number           The spell ID to override
--- @param blizzardChild Frame      The blizzard child for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardAllChild(spellID, blizzardChild)
    cache._tickBlizzAllChild[spellID] = blizzardChild
end
cache.CacheTickBlizzardAllChild = CacheTickBlizzardAllChild

-------------------------------------------------------------------------------
--- Returns the first blizzard child between `resolvedID` and `spellID`
---   (`resolvedID` has priority over `spellID`.)
--- Uses `_tickBlizzAllChild` as the reference cache.
--- @param spellID number           The (original) spell ID to query
--- @param resolvedID number|nil    The resolved spell ID to query
--- @return Frame|nil blizzardChild
-------------------------------------------------------------------------------
local function GetResolvedBlizzardAllChild(spellID, resolvedID)
    return cache._tickBlizzAllChild[resolvedID] or cache._tickBlizzAllChild[spellID]
end
cache.GetResolvedBlizzardAllChild = GetResolvedBlizzardAllChild

-------------------------------------------------------------------------------
--- Checks if spellID is cached in `_tickBlizzAllChild`
--- @param spellID number           The spell ID to check
--- @return boolean spellCachedInTickBlizzardAllChild
-------------------------------------------------------------------------------
local function IsSpellCachedInTickBlizzardAllChild(spellID)
    return cache._tickBlizzAllChild[spellID] ~= nil
end
cache.IsSpellCachedInTickBlizzardAllChild = IsSpellCachedInTickBlizzardAllChild

-- endregion

-- region _tickBlizzBuffChild

-------------------------------------------------------------------------------
--- Get the blizzard buff child for spellID from the cache `_tickBlizzBuffChild`
--- @param spellID number           The spell ID to query
--- @return Frame|nil blizzardBuffChild
-------------------------------------------------------------------------------
local function GetTickBlizzardBuffChild(spellID)
    return cache._tickBlizzBuffChild[spellID]
end
cache.GetTickBlizzardBuffChild = GetTickBlizzardBuffChild

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzBuffChild` cache the `blizzardBuffChild` for `spellID`
--- @param spellID number           The spell ID to override
--- @param blizzardBuffChild Frame      The blizzard child for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardBuffChild(spellID, blizzardBuffChild)
    cache._tickBlizzBuffChild[spellID] = blizzardBuffChild
end
cache.CacheTickBlizzardBuffChild = CacheTickBlizzardBuffChild

-------------------------------------------------------------------------------
--- Returns the first blizzard child between `resolvedID` and `spellID`
---   (`resolvedID` has priority over `spellID`.)
--- Uses `_tickBlizzBuffChild` as the reference cache.
--- @param spellID number           The (original) spell ID to query
--- @param resolvedID number|nil    The resolved spell ID to query
--- @return Frame|nil blizzardBuffChild
-------------------------------------------------------------------------------
local function GetResolvedBlizzardBuffChild(spellID, resolvedID)
    return cache._tickBlizzBuffChild[resolvedID] or cache._tickBlizzBuffChild[spellID]
end
cache.GetResolvedBlizzardBuffChild = GetResolvedBlizzardBuffChild

-------------------------------------------------------------------------------
--- Checks if spellID is cached in `_tickBlizzBuffChild`
--- @param spellID number           The spell ID to check
--- @return boolean spellCachedInTickBlizzardBuffChild
-------------------------------------------------------------------------------
local function IsSpellCachedInTickBlizzardBuffChild(spellID)
    return cache._tickBlizzBuffChild[spellID] ~= nil
end
cache.IsSpellCachedInTickBlizzardBuffChild = IsSpellCachedInTickBlizzardBuffChild

-- endregion

-- region _tickBlizzCDChild

-- CD/utility viewer child cache: used by CD bars to
-- avoid picking up the buff viewer's aura state for
-- spells that appear in both viewer types.

-------------------------------------------------------------------------------
--- Get the blizzard CD child for spellID from the cache `_tickBlizzCDChild`
--- @param spellID number               The spell ID to query
--- @return Frame|nil blizzardCDChild
-------------------------------------------------------------------------------
local function GetTickBlizzardCDChild(spellID)
    return cache._tickBlizzCDChild[spellID]
end
cache.GetTickBlizzardCDChild = GetTickBlizzardCDChild

-------------------------------------------------------------------------------
--- Returns the first blizzard CD child between `resolvedID` and `spellID`
---   (`resolvedID` has priority over `spellID`.)
--- Uses `_tickBlizzCDChild` as the reference cache.
--- @param spellID number           The (original) spell ID to query
--- @param resolvedID number|nil    The resolved spell ID to query
--- @return Frame|nil blizzardCDChild
-------------------------------------------------------------------------------
local function GetResolvedTickBlizzardCDChild(spellID, resolvedID)
    return cache._tickBlizzCDChild[resolvedID] or cache._tickBlizzCDChild[spellID]
end
cache.GetResolvedTickBlizzardCDChild = GetResolvedTickBlizzardCDChild

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzCDChild` cache the `blizzardCDChild` for `spellID`
--- @param spellID number           The spell ID to override
--- @param blizzardCDChild Frame    The blizzard CD child for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardCDChild(spellID, blizzardCDChild)
    cache._tickBlizzCDChild[spellID] = blizzardCDChild
end
cache.CacheTickBlizzardCDChild = CacheTickBlizzardCDChild

-- endregion

-- region _tickBlizzMultiChild

-------------------------------------------------------------------------------
--- Get the list of blizzard CDM children for spellID from the 
---   cache `_tickBlizzMultiChild`.
--- @param spellID number               The spell ID to query
--- @return Frame[]|nil blizzardChildren
-------------------------------------------------------------------------------
local function GetTickBlizzardMultiChild(spellID)
    return cache._tickBlizzMultiChild[spellID]
end
cache.GetTickBlizzardMultiChild = GetTickBlizzardMultiChild

-------------------------------------------------------------------------------
--- Checks if the `spellID` is currently stored in `_tickBlizzMultiChild`
--- @param spellID number               The spell ID to check
--- @return boolean spellInCache
-------------------------------------------------------------------------------
local function IsSpellCachedInTickBlizzardMultiChild(spellID)
    return cache._tickBlizzMultiChild[spellID] ~= nil
end
cache.IsSpellCachedInTickBlizzardMultiChild = IsSpellCachedInTickBlizzardMultiChild

-------------------------------------------------------------------------------
--- Stores in the `_tickBlizzMultiChild` cache the list `blizzardChildren` 
---   for `spellID`. 
--- If the `spellID` is already present, this function does nothing.
--- @param spellID number           The spell ID to override
--- @param blizzardChildren Frame[] The blizzard CD children list for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardMultiChild(spellID, blizzardChildren)
    if IsSpellCachedInTickBlizzardMultiChild(spellID) then return end
    cache._tickBlizzMultiChild[spellID] = blizzardChildren
end
cache.CacheTickBlizzardMultiChild = CacheTickBlizzardMultiChild

-------------------------------------------------------------------------------
--- Appends `blizzardChild` to the list for `spellID` in `_tickBlizzMultiChild`.
--- @param spellID number        The spell ID to override
--- @param blizzardChild Frame    The blizzard CD child for spellID
-------------------------------------------------------------------------------
local function AppendTickBlizzardMultiChild(spellID, blizzardChild)
    if not IsSpellCachedInTickBlizzardMultiChild(spellID) then return end
    cache._tickBlizzMultiChild[spellID][#cache._tickBlizzMultiChild[spellID] + 1] = blizzardChild
end
cache.AppendTickBlizzardMultiChild = AppendTickBlizzardMultiChild

--

-------------------------------------------------------------------------------
--- For buff bars, this function returns the CDM's child
---   based on assignedChild and cached data.
--- Returns nil otherwise.
--- @param spellID number           The base spell ID before resolution
--- @param resolvedID number        The spell ID after resolution
--- @param isBuffBar boolean        true if the current bar is a buff bar, otherwise false
--- @param assignedChild table|nil  Companion child for multi-child buff spells (e.g. Eclipse)
---  When set, this specific CDM child is used instead of cache lookups.
--- @return table|nil blizzardBuffChild The CDM's child's live icon if it exists
-------------------------------------------------------------------------------
local function GetBlizzardBuffChild(spellID, resolvedID, isBuffBar, assignedChild)
    return isBuffBar
        and (assignedChild
             or GetResolvedBlizzardBuffChild(spellID, resolvedID)
             or GetResolvedBlizzardAllChild(spellID, resolvedID))
        or nil
end
cache.GetBlizzardBuffChild = GetBlizzardBuffChild

-- endregion

-- region _activeMultiScratch

cache._activeMultiScratch = {}      -- reusable scratch table for active multi-child filtering and companion child mapping

-------------------------------------------------------------------------------
--- Get the blizzard child at the given `index` from cache `_activeMultiScratch`.
--- @param index number               The spell ID to query
--- @return Frame|nil blizzardChild
-------------------------------------------------------------------------------
local function GetTickBlizzardMultiScratch(index)
    return cache._activeMultiScratch[index]
end
cache.GetTickBlizzardMultiScratch = GetTickBlizzardMultiScratch

-------------------------------------------------------------------------------
--- Stores in the `_activeMultiScratch` cache the `blizzardChild` 
---   at the given `index`. 
--- @param index number           The spell ID to override
--- @param blizzardChild Frame    The blizzard CD child for spellID
-------------------------------------------------------------------------------
local function CacheTickBlizzardMultiScratch(index, blizzardChild)
    cache._activeMultiScratch[index] = blizzardChild
end
cache.CacheTickBlizzardMultiScratch = CacheTickBlizzardMultiScratch

-------------------------------------------------------------------------------
--- Wipes the `_activeMultiScratch`, then rebuilds it if current bar is a buff bar. 
--- Updates the `combinedCount` and returns if there are multiple active children.
--- 
--- @param isBuffBar boolean        true if current bar is a buff bar.
--- @param combined table           the combined spell list (tracked + extras)
--- @param combinedCount number     the original tracked spell count
--- @return boolean hasCompanions, number combinedCount
-------------------------------------------------------------------------------
local function RebuildMultiScratch(isBuffBar, combined, combinedCount)
    wipe(cache._activeMultiScratch)
    if not isBuffBar then return false, combinedCount end

    local hasCompanions = false
    local baseCount = combinedCount
    for bi = 1, baseCount do
        local sid = combined[bi]
        local multiChildren = GetTickBlizzardMultiChild(sid)
        if multiChildren then
            -- Collect only active (shown) children to avoid showing inactive eclipses
            -- and to avoid tainted Icon textures from inactive CDM children.
            -- Use :IsShown() instead of .isActive to avoid WoW taint on secure properties.
            local activeCount = 0
            local mc1, mc2, mc3, mc4
            for mi = 1, #multiChildren do
                local mc = multiChildren[mi]
                if mc:IsShown() then
                    activeCount = activeCount + 1
                    if     activeCount == 1 then mc1 = mc
                    elseif activeCount == 2 then mc2 = mc
                    elseif activeCount == 3 then mc3 = mc
                    else                         mc4 = mc end
                end
            end
            if activeCount > 0 then
                hasCompanions = true
                CacheTickBlizzardMultiScratch(bi, mc1)
                local extras2 = { mc2, mc3, mc4 }
                for ci = 1, activeCount - 1 do
                    combinedCount = combinedCount + 1
                    combined[combinedCount] = sid
                    CacheTickBlizzardMultiScratch(combinedCount, extras2[ci])
                end
            end
        end
    end
    return hasCompanions, combinedCount
end
cache.RebuildMultiScratch = RebuildMultiScratch

-- todo: check if hasCompanions can be replaced by a check on the size of _activeMultiScratch
-------------------------------------------------------------------------------
--- Returns the `_activeMultiScratch` cache if `hasCompanions` is true, nil otherwise
--- @param hasCompanions boolean  true if the icon's child has companions
--- @return table|nil _activeMultiScratch
-------------------------------------------------------------------------------
local function GetCachedCompanionChild(hasCompanions)
    return hasCompanions and cache._activeMultiScratch or nil
end
cache.GetCachedCompanionChild = GetCachedCompanionChild

-- endregion

-------------------------------------------------------------------------------
--- Wipe per-tick caches (GCD, charges, auras, totem info, blizzard active states)
---
-------------------------------------------------------------------------------
local function WipePerTickCaches()
    -- Wipe per-tick caches (GCD, charges, auras, totem info)
    wipe(cache._tickGCD)
    wipe(cache._tickCharge)
    wipe(cache._tickAura)
    wipe(cache._tickTotem)

    -- Build per-tick Blizzard active state cache: scan all CDM viewers for
    -- children marked wasSetFromAura, map their resolved spellID -> true.
    -- Also build override cache: maps base spellID -> current overrideSpellID
    -- so custom bars can resolve runtime activation overrides (e.g. Crusader
    -- Strike -> Hammer of Wrath during Avenging Crusader).
    wipe(cache._tickBlizzActive)
    wipe(cache._tickBlizzOverride)
    wipe(cache._tickBlizzChild)
    wipe(cache._tickBlizzAllChild)
    wipe(cache._tickBlizzBuffChild)
    wipe(cache._tickBlizzCDChild)
    wipe(cache._tickBlizzMultiChild)
end
cache.WipePerTickCaches = WipePerTickCaches

-- endregion

-- endregion

-- region Multi-charge spells

-- Multi-charge spell cache: populated out of combat when values are not secret.
-- Falls back to SavedVariables for combat /reload scenarios.
-- Maps spellID true for spells with maxCharges > 1
cache._multiChargeSpells = {}
cache._maxChargeCount    = {}  -- [spellID] = maxCharges, populated alongside _multiChargeSpells

-- Export to NS (Expose charge cache to options file for preview rendering)
ns._multiChargeSpells    = cache._multiChargeSpells
ns._maxChargeCount       = cache._maxChargeCount

-------------------------------------------------------------------------------
--- Wipe multi-charge spells cache (_multiChargeSpells and _maxChargeCount)
--- 
-------------------------------------------------------------------------------
local function WipeMultiChargeSpellCache()
    wipe(cache._multiChargeSpells)
    wipe(cache._maxChargeCount)
end
cache.WipeMultiChargeSpellCache = WipeMultiChargeSpellCache

-------------------------------------------------------------------------------
--- Caches the multi-charge spell to _multiChargeSpells and _maxChargeCount (if not already present)
--- Uses out-of-combat to build a persistent DB
--- @param spellID number       The ID of the spell to cache
--- @param blizzChild table     The CDM child
-------------------------------------------------------------------------------
local function CacheMultiChargeSpell(spellID, blizzChild)
    if not spellID or not C_Spell.GetSpellCharges then return end
    if cache._multiChargeSpells[spellID] ~= nil then return end
    local charges = C_Spell.GetSpellCharges(spellID)
    if not charges or charges.maxCharges == nil then return end

    if not issecretvalue(charges.maxCharges) then
        -- Out of combat (or non-secret): cache live and persist to DB
        local result = charges.maxCharges > 1
        cache._multiChargeSpells[spellID] = result or false
        if result then
            cache._maxChargeCount[spellID] = charges.maxCharges
            -- Tag the CDM child so variant swaps in combat can inherit
            -- charge status without needing API calls (SECRET-proof).
            if blizzChild then
                blizzChild._ecmeIsChargeSpell = true
                blizzChild._ecmeMaxCharges = charges.maxCharges
            end
            -- Only persist confirmed charge spells — never persist false so
            -- stale DB entries don't block re-detection on login or talent swap.
            local db = ns.ECME.db
            if db and db.sv then
                if not db.sv.multiChargeSpells then
                    db.sv.multiChargeSpells = {}
                end
                db.sv.multiChargeSpells[spellID] = true
            end
        end
    else
        -- Secret (in combat): fall back to persisted DB value if available.
        -- Do NOT cache false here -- after a talent swap the DB may be empty,
        -- and caching false permanently blocks charge detection for the new
        -- spell until the next full cache wipe.
        local db = ns.ECME.db
        if db and db.sv and db.sv.multiChargeSpells and db.sv.multiChargeSpells[spellID] then
            cache._multiChargeSpells[spellID] = true
        end
        -- CDM child propagation: for multi-child spells like Eclipse, the
        -- same CDM child swaps between variant spell IDs (Lunar/Solar).
        -- If we tagged the child OOC when the previous variant was active,
        -- inherit that charge status for the new variant.
        if not cache._multiChargeSpells[spellID] and blizzChild
                and blizzChild._ecmeIsChargeSpell then
            cache._multiChargeSpells[spellID] = true
            cache._maxChargeCount[spellID] = blizzChild._ecmeMaxCharges
        end
        -- If no DB entry and no child tag: leave nil so we retry next tick
    end
end
cache.CacheMultiChargeSpell = CacheMultiChargeSpell
ns.CacheMultiChargeSpell = CacheMultiChargeSpell

-------------------------------------------------------------------------------
--- Checks if a spell is in the multi-charge spells cache (by ID)
---   and checks if a multi-charge spell.
--- @param spellID number                   The ID of the spell to check
--- @return boolean isCachedChargeSpell
-------------------------------------------------------------------------------
local function IsCachedChargeSpell(spellID)
    return cache._multiChargeSpells[spellID] == true
end
cache.IsCachedChargeSpell = IsCachedChargeSpell

-------------------------------------------------------------------------------
--- Adds the spellID to the cache and set its corresponding value to true
--- @param spellID number   The spell ID to add to the cache
-------------------------------------------------------------------------------
local function AddChargeSpellToCache(spellID)
    cache._multiChargeSpells[spellID] = true
end
cache.AddChargeSpellToCache = AddChargeSpellToCache

-------------------------------------------------------------------------------
--- Propagate charge cache from base to override so talent-swapped spells
--- show charges correctly even before the override ID has been seen OOC.
--- Always attempt direct detection on the final resolvedID first so it may
--- have charges even if the base spell doesn't (three-level chain).
--- @param spellID number       The base spell ID before resolution
--- @param resolvedID number    The spell ID after resolution
-------------------------------------------------------------------------------
local function PropagateResolvedSpellChargeCache(spellID, resolvedID)
    local propChild = cache._tickBlizzAllChild[resolvedID] or cache._tickBlizzAllChild[spellID]
    -- Always try direct detection on the resolved ID (cheapest path)
    CacheMultiChargeSpell(resolvedID, propChild)
    -- If resolved ID still unknown (secret/combat), check if we have a
    -- live Blizzard child for it and mark it as a charge spell so
    -- ApplySpellCooldown uses the charge display path.
    if not IsCachedChargeSpell(resolvedID) and cache._tickBlizzChild[resolvedID] then
        -- We have a live Blizzard child -- treat as charge spell so the
        -- charge display path runs. ApplySpellCooldown will call
        -- GetSpellCharges which may still be secret, but the shadow
        -- cooldown frames will correctly reflect the charge state.
        AddChargeSpellToCache(resolvedID)
    end
    -- If still unknown, try propagating from intermediate (only if true)
    if not IsCachedChargeSpell(resolvedID) then
        local intermediate = C_SpellBook and C_SpellBook.FindSpellOverrideByID
            and C_SpellBook.FindSpellOverrideByID(spellID)
        if intermediate and intermediate ~= 0 and intermediate ~= resolvedID then
            CacheMultiChargeSpell(intermediate, propChild)
            if IsCachedChargeSpell(intermediate) == true then
                AddChargeSpellToCache(resolvedID)
                if cache._maxChargeCount[intermediate] then
                    cache._maxChargeCount[resolvedID] = cache._maxChargeCount[intermediate]
                end
            end
        end
    end
    -- If still unknown, propagate from base -- but only if base is true
    if not IsCachedChargeSpell(resolvedID) then
        CacheMultiChargeSpell(spellID, propChild)
        if IsCachedChargeSpell(spellID) then
            AddChargeSpellToCache(resolvedID)
            if cache._maxChargeCount[spellID] then
                cache._maxChargeCount[resolvedID] = cache._maxChargeCount[spellID]
            end
        end
    end
end
cache.PropagateResolvedSpellChargeCache = PropagateResolvedSpellChargeCache

-- endregion

-- region Zero-charge spells

-- Spells that use the charge system but start at 0 and build stacks in combat.
-- These report maxCharges > 1 but currentCharges = 0 at rest, so we hide the
-- charge text when it would show "0".
local _zeroStartChargeSpells = {
    [399491] = true,  -- Teachings of the Monastery
    [115294] = true,  -- Mana Tea
    [55090]  = true,  -- Scourge Strike
}

-------------------------------------------------------------------------------
--- Returns true if the spell ID is registered in `_zeroStartChargeSpells` 
---   (with value true)
--- @param spellID number   The ID of the spell to check
--- @returns boolean isZeroChargeSpell
-------------------------------------------------------------------------------
local function IsZeroChargeSpell(spellID)
    return _zeroStartChargeSpells[spellID] == true
end
cache.IsZeroChargeSpell = IsZeroChargeSpell

-- Cast-count spell cache: identifies spells that use GetSpellCastCount for
-- stack tracking (e.g. Sheilun's Gift, Mana Tea). These spells start at 0
-- stacks and build them in combat, so we cache the last known non-zero count
-- OOC and persist to SavedVariables for combat use.
-- Maps spellID -> last known count (number) or false (confirmed not a cast-count spell)
cache._castCountSpells = {}

-------------------------------------------------------------------------------
--- Pre-seed zero-start charge spells so the cast-count display path
--- always recognizes them without needing to see count > 0 OOC first.
--- 
-------------------------------------------------------------------------------
local function InitCastCountSpellsCache()
    for sid in pairs(_zeroStartChargeSpells) do
        cache._castCountSpells[sid] = true
    end
end
cache.InitCastCountSpellsCache = InitCastCountSpellsCache

-------------------------------------------------------------------------------
--- Returns true if the spell ID is registered in `_castCountSpells`
---   (and not nil)
--- @param spellID number   The ID of the spell to check
--- @returns boolean isCachedCastCountSpell
-------------------------------------------------------------------------------
local function IsCachedCastCountSpell(spellID)
    return cache._castCountSpells[spellID] ~= nil
end
cache.IsCachedCastCountSpell = IsCachedCastCountSpell

-------------------------------------------------------------------------------
--- Adds a cast-count spell to the cache (if it is a cache-count spell)
--- @param spellID number   The ID of the cast-count spell to cache
-------------------------------------------------------------------------------
local function CacheCastCountSpell(spellID)
    if not spellID or not C_Spell.GetSpellCastCount then return end
    -- Already confirmed not a cast-count spell -- skip
    if cache._castCountSpells[spellID] == false then return end
    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
    if not ok or count == nil then return end

    if not (issecretvalue and issecretvalue(count)) then
        -- OOC: if count > 0, remember this spell uses cast counts
        if count > 0 then
            cache._castCountSpells[spellID] = count
            local db = ns.ECME.db
            if db and db.sv then
                if not db.sv.castCountSpells then
                    db.sv.castCountSpells = {}
                end
                db.sv.castCountSpells[spellID] = true
            end
        end
        -- Don't cache false here -- spell may just not have stacks yet
    elseif cache._castCountSpells[spellID] == nil then
        -- Secret (combat): check DB for whether we've ever seen this spell with stacks
        local db = ns.ECME.db
        if db and db.sv and db.sv.castCountSpells and db.sv.castCountSpells[spellID] then
            cache._castCountSpells[spellID] = true
        end
    end
end
cache.CacheCastCountSpell = CacheCastCountSpell

-- endregion

-- region Totem/Summon/Aura-type spells

-- region Totem Cache

cache._tickTotem = {}                            -- [slot] = haveTotem (cached per tick to avoid inconsistent reads)

-------------------------------------------------------------------------------
--- Per-tick cached GetTotemInfo to prevent inconsistent reads during totem expiry.
--- @param slot number The slot to check
--- @return boolean haveTotem
-------------------------------------------------------------------------------
local function GetCachedTotemInfo(slot)
    local cached = cache._tickTotem[slot]
    if cached ~= nil then return cached end
    local haveTotem = GetTotemInfo(slot)
    cache._tickTotem[slot] = haveTotem
    return haveTotem
end
cache.GetCachedTotemInfo = GetCachedTotemInfo

-------------------------------------------------------------------------------
--- Secondary validation: GetTotemInfo confirms a totem exists in the slot but not
--- WHICH totem. This checks the child's own aura/cooldown data is still live.
--- comment
--- @param child table The child to check
--- @return boolean haveTotem
-------------------------------------------------------------------------------
local function IsTotemChildStillValid(child)
    if child.auraInstanceID then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                               child.auraDataUnit or "player", child.auraInstanceID)
        if ok then
            if issecretvalue and issecretvalue(data) then return true end
            return data ~= nil
        end
        return true  -- pcall failed, trust GetTotemInfo
    end
    if cache._ecmeChildHasDurObj[child] then return true end
    local rd = cache._ecmeRawDur[child]
    if rd then
        if issecretvalue and issecretvalue(rd) then return true end
        return rd > 0
    end
    -- Fallback: hook caches are empty after /reload until SetCooldown fires.
    if child.Cooldown and child.Cooldown:IsVisible() then return true end
    return false
end
cache.IsTotemChildStillValid = IsTotemChildStillValid

-- endregion

-- region ECME Start/Duration

-- Separate tables keyed by child frame reference -- avoids reading tainted fields on Blizzard-owned frames.
-- ch.isActive and ch._ecmeDurObj etc. are tainted secret values; we track state in our own tables instead.
--- @type {[Frame]: boolean}
cache._ecmeChildHasDurObj = {}
--- @type {[Frame]: number}
cache._ecmeDurObj = {}                           -- [ch] = durObj captured from SetCooldownFromDurationObject hook
--- @type {[Frame]: number}
cache._ecmeRawStart = {}                         -- [ch] = start captured from SetCooldown hook
--- @type {[Frame]: number}
cache._ecmeRawDur = {}                           -- [ch] = dur captured from SetCooldown hook
--- @type {[number]: {isHovered: boolean, fadeDir: string}}
cache._cdmHoverStates = {}                       -- [barKey] = { isHovered=false, fadeDir=nil }

-- Export to NS
ns._ecmeDurObjCache = cache._ecmeDurObj
ns._ecmeRawStartCache = cache._ecmeRawStart
ns._ecmeRawDurCache = cache._ecmeRawDur


-------------------------------------------------------------------------------
--- Get if the blizzardChild has a duration object from the cache `_ecmeChildHasDurObj`.
---   Captured from SetCooldownFromDurationObject.
--- @param blizzardChild Frame     The blizzardChild to query
--- @return boolean|nil childHasDurationObject
-------------------------------------------------------------------------------
local function GetECMEChildHasDurationObject(blizzardChild)
    return cache._ecmeChildHasDurObj[blizzardChild]
end
cache.GetECMEChildHasDurationObject = GetECMEChildHasDurationObject

-------------------------------------------------------------------------------
--- Get the duration for blizzardChild from the cache `_ecmeDurObj`.
---   Duration captured from SetCooldownFromDurationObject.
--- @param blizzardChild Frame     The blizzardChild to query
--- @return number|nil duration
-------------------------------------------------------------------------------
local function GetECMEDurationObject(blizzardChild)
    return cache._ecmeDurObj[blizzardChild]
end
cache.GetECMEDurationObject = GetECMEDurationObject

-------------------------------------------------------------------------------
--- Get the start time for blizzardChild from the cache `_ecmeRawStart` captured
---   from SetCooldown hook.
--- @param blizzardChild Frame     The blizzardChild to query
--- @return number|nil startTime
-------------------------------------------------------------------------------
local function GetECMERawStart(blizzardChild)
    return cache._ecmeRawStart[blizzardChild]
end
cache.GetECMERawStart = GetECMERawStart

-------------------------------------------------------------------------------
--- Get the duration for blizzardChild from the cache `_ecmeRawDur` captured
---   from SetCooldown hook.
--- @param blizzardChild Frame     The blizzardChild to query
--- @return number|nil duration
-------------------------------------------------------------------------------
local function GetECMERawDuration(blizzardChild)
    return cache._ecmeRawDur[blizzardChild]
end
cache.GetECMERawDuration = GetECMERawDuration

-------------------------------------------------------------------------------
--- Caches the duration for blizzardChild in `_ecmeDurObj` captured
---   from SetCooldownFromDurationObject hook and sets the matching value 
---   in `_ecmeChildHasDurObj` to true if `durationObject` is not nil 
---   (clears otherwise).
--- @param blizzardChild Frame      The blizzardChild to query
--- @param durationObject number    The duration object
-------------------------------------------------------------------------------
local function CacheECMEObjectDuration(blizzardChild, durationObject)
    cache._ecmeDurObj[blizzardChild] = durationObject
    if durationObject ~= nil then
        cache._ecmeChildHasDurObj[blizzardChild] = true
    else
        cache._ecmeChildHasDurObj[blizzardChild] = nil
    end
end
cache.CacheECMEObjectDuration = CacheECMEObjectDuration

-------------------------------------------------------------------------------
--- Caches the start time and duration captured for blizzardChild 
---   from SetCooldown hook in `_ecmeRawStart` and `_ecmeRawDur` respectively.
--- @param blizzardChild Frame     The blizzardChild to query
--- @param startTime number        The raw start time of the cooldown
--- @param duration number         The raw duration of the cooldown
-------------------------------------------------------------------------------
local function CacheECMERawCooldownTime(blizzardChild, startTime, duration)
    cache._ecmeRawStart[blizzardChild] = startTime
    cache._ecmeRawDur[blizzardChild] = duration
end
cache.CacheECMERawCooldownTime = CacheECMERawCooldownTime

-------------------------------------------------------------------------------
--- Returns `true` if `blizzardChild` is present in  `_ecmeRawStart` and 
---   `_ecmeRawDur`.
--- @param blizzardChild Frame     The blizzardChild to query
--- @return boolean isCached
-------------------------------------------------------------------------------
local function GetIsCachedInRawCooldownTimes(blizzardChild)
    return (cache._ecmeRawStart[blizzardChild] ~= nil)
           and (cache._ecmeRawDur[blizzardChild] ~= nil)
end
cache.GetIsCachedInRawCooldownTimes = GetIsCachedInRawCooldownTimes

-------------------------------------------------------------------------------
--- Clear cooldown duration/time data for blizzardChild. 
---   Useful when duration=0 or when Blizzard clears the cooldown.
--- @param blizzardChild Frame     The blizzardChild to clear caches for
-------------------------------------------------------------------------------
local function ClearECMEInactiveCooldown(blizzardChild)
    cache._ecmeDurObj[blizzardChild] = nil
    cache._ecmeChildHasDurObj[blizzardChild] = nil
    cache._ecmeRawStart[blizzardChild] = nil
    cache._ecmeRawDur[blizzardChild] = nil
end
cache.ClearECMEInactiveCooldown = ClearECMEInactiveCooldown

-------------------------------------------------------------------------------
--- Wipe hook-captured cooldown caches
---   (`_ecmeChildHasDurObj`, `_ecmeDurObj`, `_ecmeRawStart` and `_ecmeRawDur`)
--- 
-------------------------------------------------------------------------------
local function WipeECMECooldownTimeCaches()
    wipe(cache._ecmeChildHasDurObj)
    wipe(cache._ecmeDurObj)
    wipe(cache._ecmeRawStart)
    wipe(cache._ecmeRawDur)
end
cache.WipeECMECooldownTimeCaches = WipeECMECooldownTimeCaches

-- endregion

-- region Placed Unit Start

--- @type {[number]: number}
cache._placedUnitStart = {}                 -- [spellID] = GetTime() when placed unit first detected active
ns._placedUnitStartCache = cache._placedUnitStart

-------------------------------------------------------------------------------
--- Get the start time for spellID from the cache `_placedUnitStart`
--- @param spellID number           The spell ID to query
--- @return number|nil time
-------------------------------------------------------------------------------
local function GetPlacedUnitStart(spellID)
    return cache._placedUnitStart[spellID]
end
cache.GetPlacedUnitStart = GetPlacedUnitStart

-------------------------------------------------------------------------------
--- Stores in `_placedUnitStart` the `time` for `spellID`
--- @param spellID number       The spell ID to override
--- @param time number|nil      The time the unit what placed. Defaults to GetTime()
-------------------------------------------------------------------------------
local function CachePlacedUnitStart(spellID, time)
    if not cache._placedUnitStart[spellID] then
        cache._placedUnitStart[spellID] = time or GetTime()
    end
end
cache.CachePlacedUnitStart = CachePlacedUnitStart

-------------------------------------------------------------------------------
--- Sets the start time for spellID to nil.
--- If spellID was not present, does nothing.
--- @param spellID number       The spell ID to remove
-------------------------------------------------------------------------------
local function RemovePlacedUnitStart(spellID)
    if cache._placedUnitStart[spellID] ~= nil then
        cache._placedUnitStart[spellID] = nil
    end
end
cache.RemovePlacedUnitStart = RemovePlacedUnitStart

-------------------------------------------------------------------------------
--- Clear placed-unit start times for spells no longer active
--- 
-------------------------------------------------------------------------------
local function ClearInactivePlacedUnitStart()
    for sid in pairs(cache._placedUnitStart) do
        if not IsTickBlizzardActive(sid) then
            cache._placedUnitStart[sid] = nil
        end
    end
end
cache.ClearInactivePlacedUnitStart = ClearInactivePlacedUnitStart

-- endregion

-------------------------------------------------------------------------------
--- Check if a Blizzard CDM buff-viewer child represents an actively running effect.
--- Uses only our own tracking tables and safe APIs — never reads tainted fields.
--- For totem-type spells: uses GetCachedTotemInfo(preferredTotemUpdateSlot).
--- For summon/aura-type spells: uses our hook-captured cooldown state tables.
--- @param child table      The child to check
--- @return boolean true    if the buff child cooldown is actively running, false otherwise
-------------------------------------------------------------------------------
local function IsBuffChildCooldownActive(child)
    if not child then return false end
    -- Totem check: preferredTotemUpdateSlot is set by Blizzard on totem CDM children.
    local totemSlot = child.preferredTotemUpdateSlot
    if totemSlot and type(totemSlot) == "number" and totemSlot > 0 then
        local haveTotem = GetCachedTotemInfo(totemSlot)
        -- haveTotem can be a secret boolean in combat; secret = active totem
        if issecretvalue and issecretvalue(haveTotem) then
            return IsTotemChildStillValid(child)
        end
        if haveTotem then return IsTotemChildStillValid(child) end
        return false
    end
    -- Non-totem: check our hook-captured cooldown state tables
    if cache._ecmeChildHasDurObj[child] then return true end
    local rawDur = cache._ecmeRawDur[child]
    if rawDur and (issecretvalue and issecretvalue(rawDur) or rawDur > 0) then return true end
    return false
end
cache.IsBuffChildCooldownActive = IsBuffChildCooldownActive

-- endregion

-- region Spell to Cooldown

-- spellID -> cooldownID map built once from C_CooldownViewer.GetCooldownViewerCategorySet (all categories).
-- Rebuilt on PLAYER_LOGIN and spec change. Used by custom bars to find CDM child frames by spellID.
--- @type {[number]: number}
cache._spellToCooldownID = {}

-------------------------------------------------------------------------------
---
---
---
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--- Get the spell coolodwn ID for spellID (from `_spellToCooldownID`)
--- @param spellID number           The spell ID to query
--- @return number|nil cooldownID
-------------------------------------------------------------------------------
local function GetCooldownIDFromSpell(spellID)
    return cache._spellToCooldownID[spellID]
end
cache.GetCooldownIDFromSpell = GetCooldownIDFromSpell

-------------------------------------------------------------------------------
--- Returns the first coolodwn ID between `resolvedID` and `spellID`
---   (`resolvedID` has priority over `spellID`.)
--- Uses `_spellToCooldownID` as the reference cache.
--- @param spellID number           The (original) spell ID to query
--- @param resolvedID number|nil    The resolved spell ID to query
--- @return number|nil blizzardBuffChild
-------------------------------------------------------------------------------
local function GetResolvedCooldownIDFromSpell(spellID, resolvedID)
    return cache._spellToCooldownID[resolvedID] or cache._spellToCooldownID[spellID]
end
cache.GetResolvedCooldownIDFromSpell = GetResolvedCooldownIDFromSpell

-- endregion

-- region Action Button

-------------------------------------------------------------------------------
--  Action Button Lookup (supports Blizzard and popular bar addons)
-------------------------------------------------------------------------------
local blizzBarNames = {
    [1] = "ActionButton",
    [2] = "MultiBarBottomLeftButton",
    [3] = "MultiBarBottomRightButton",
    [4] = "MultiBarRightButton",
    [5] = "MultiBarLeftButton",
    [6] = "MultiBar5Button",
    [7] = "MultiBar6Button",
    [8] = "MultiBar7Button",
}

-- EAB slot offsets match BAR_SLOT_OFFSETS in EllesmereUIActionBars.lua
local eabSlotOffsets = { 0, 60, 48, 24, 36, 144, 156, 168 }


---@type {[number]: string}
local actionButtonCache = {}
-------------------------------------------------------------------------------
--- Returns the buttonID for the given bar and button index. First searches in
---   the cache then the global variable _G.
--- @param bar number       The index of the bar
--- @param i number         The index of the button
--- @return string buttonID
-------------------------------------------------------------------------------
local function GetActionButton(bar, i)
    bar = bar or 1
    local cacheKey = bar * 100 + i
    if actionButtonCache[cacheKey] then return actionButtonCache[cacheKey] end
    -- Try EABButton first (EllesmereUIActionBars creates these when Blizzard
    -- buttons are unavailable, e.g. when Dominos hides ActionButton1-12)
    local eabSlot = (eabSlotOffsets[bar] or 0) + i
    local btn = _G["EABButton" .. eabSlot]
    -- Fall back to standard Blizzard button names
    if not btn then
        local prefix = blizzBarNames[bar]
        btn = prefix and _G[prefix .. i]
    end
    if btn then actionButtonCache[cacheKey] = btn end
    return btn
end
cache.GetActionButton = GetActionButton

-- endregion

-- region Spell Icon

-- Spell icon texture cache (avoids C_Spell.GetSpellInfo per tick per icon)

---@type {[number]: number}
cache._spellIcon = {}

-------------------------------------------------------------------------------
--- Get the spell icon for spellID (from `_spellIcon`)
--- @param spellID number           The spell ID to query
--- @return number|nil spellIcon
-------------------------------------------------------------------------------
local function GetSpellIcon(spellID)
    return cache._spellIcon[spellID]
end
cache.GetSpellIcon = GetSpellIcon

-------------------------------------------------------------------------------
--- Cache spell icon texture to avoid C_Spell.GetSpellInfo per tick
--- @param spellID number           The base spell ID before resolution
--- @return number|nil textureID    The ID of the spell's texture if it exists, otherwise nil
-------------------------------------------------------------------------------
local function CacheSpellIconTexture(spellID)
    local textureID = cache._spellIcon[spellID]
    if not textureID then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then
            textureID = spellInfo.iconID
            cache._spellIcon[spellID] = textureID
        end
    end
    return textureID
end
cache.CacheSpellIconTexture = CacheSpellIconTexture

-------------------------------------------------------------------------------
--- Cache spell icon texture to avoid C_Spell.GetSpellInfo per tick
--- Uses the resolvedID first then spellID
--- 
--- Fallback: C_Spell.GetSpellTexture is more reliable for bar-type
---     buff spells where GetSpellInfo may return nil.
--- @param spellID number           The base spell ID before resolution
--- @param resolvedID number        The spell ID after resolution
--- @return number|nil textureID    The ID of the spell's texture if it exists, otherwise nil
-------------------------------------------------------------------------------
local function CacheResolvedSpellIconTexture(spellID, resolvedID)
    local textureID = cache._spellIcon[resolvedID]
    if not textureID then
        local spellInfo = C_Spell.GetSpellInfo(resolvedID)
        if spellInfo then
            textureID = spellInfo.iconID
        end
    end
    if not textureID then
        textureID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(resolvedID)
        if not textureID and resolvedID ~= spellID then
            textureID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        end
    end
    if textureID then
        cache._spellIcon[resolvedID] = textureID
    end
    return textureID
end
cache.CacheResolvedSpellIconTexture = CacheResolvedSpellIconTexture

-------------------------------------------------------------------------------
--- Wipes `_spellIcon`

-------------------------------------------------------------------------------
local function WipeSpellIconCache()
    wipe(cache._spellIcon)
end
cache.WipeSpellIconCache = WipeSpellIconCache

-- endregion

-- region CDM Keybind

-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Reads HotKey text directly from action button frames -- the same source
--  the action bar itself uses, so it's always correct regardless of bar addon.
--  Deferred if called during combat; fires on PLAYER_REGEN_ENABLED instead.
-------------------------------------------------------------------------------

--- @type {[number|string]: string}
cache._cdmKeybind = {} -- [spellID|spellName] -> formatted key string
cache._keybindCacheReady = false  -- true after successful build
ns.CDMKeybindCache = cache._cdmKeybind

-------------------------------------------------------------------------------
--- Get the CDM keybind for spellID/spellName from the cache `_cdmKeybind`
--- @param spellID number|string  The ID or the name of the spell ID to query
--- @return string|nil cdmKeybind
-------------------------------------------------------------------------------
local function GetCDMKeybind(spellID)
    return cache._cdmKeybind[spellID]
end
cache.GetCDMKeybind = GetCDMKeybind

-------------------------------------------------------------------------------
--- First attempts to get the CDM keybind for spellID from cache `_cdmKeybind`.
---   If it fails, fallsback to the spell name for spellID using GetSpellName.
---   Returns the keybind or nil if the spell could not be found in the cache.
--- @param spellID number  The ID of the spell ID to query
--- @return string|nil cdmKeybind
-------------------------------------------------------------------------------
local function GetCDMKeybindNameFallback(spellID)
    local cdmKeybind = GetCDMKeybind(spellID)
    if not cdmKeybind then
        local spellName = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if spellName then
            cdmKeybind = GetCDMKeybind(spellName)
        end
    end
    return cdmKeybind
end
cache.GetCDMKeybindNameFallback = GetCDMKeybindNameFallback

-------------------------------------------------------------------------------
--- Stores in the `_cdmKeybind` cache the `cdmKeybind` for spellID/spellName.
---   Note: if spellID/spellName is already present in cache, this function 
---   does nothing.
--- @param spellID number|string  The ID or the name of the spell ID to cache
--- @param cdmKeybind string|nil  The associated keybind
-------------------------------------------------------------------------------
local function CacheCDMKeybind(spellID, cdmKeybind)
    if not cache._cdmKeybind[spellID] then
        cache._cdmKeybind[spellID] = cdmKeybind
    end
end
cache.CacheCDMKeybind = CacheCDMKeybind

-- Action bar slot ΓåÆ binding name map. Non-bar-1 entries listed first so that
-- if a spell appears on multiple bars, the more specific bar wins over bar 1.
--- @type {prefix: string, startSlot: number}
local _barBindingDefs = {
    { prefix = "MULTIACTIONBAR1BUTTON", startSlot = 61  },  -- bar 2 bottom left
    { prefix = "MULTIACTIONBAR2BUTTON", startSlot = 49  },  -- bar 3 bottom right
    { prefix = "MULTIACTIONBAR3BUTTON", startSlot = 25  },  -- bar 4 right
    { prefix = "MULTIACTIONBAR4BUTTON", startSlot = 37  },  -- bar 5 left
    { prefix = "MULTIACTIONBAR5BUTTON", startSlot = 145 },  -- bar 6
    { prefix = "MULTIACTIONBAR6BUTTON", startSlot = 157 },  -- bar 7
    { prefix = "MULTIACTIONBAR7BUTTON", startSlot = 169 },  -- bar 8
    { prefix = "ACTIONBUTTON",          startSlot = 1   },  -- bar 1 (last = lowest priority)
}

-------------------------------------------------------------------------------
--- Formats the given `key` (effectively making it shorter if relevant).
---   Returns nil if the key was nil or an empty string.
--- @param key string|nil   The keybind to format
--- @return string|nil key  The formatted keybind
-------------------------------------------------------------------------------
local function FormatKeybindKey(key)
    if not key or key == "" then return nil end
    key = key:gsub("SHIFT%-", "S")
    key = key:gsub("CTRL%-",  "C")
    key = key:gsub("ALT%-",   "A")
    key = key:gsub("Mouse Button ", "M")
    key = key:gsub("MOUSEWHEELUP",   "MwU")
    key = key:gsub("MOUSEWHEELDOWN", "MwD")
    key = key:gsub("NUMPADDECIMAL",  "N.")
    key = key:gsub("NUMPADPLUS",     "N+")
    key = key:gsub("NUMPADMINUS",    "N-")
    key = key:gsub("NUMPADMULTIPLY", "N*")
    key = key:gsub("NUMPADDIVIDE",   "N/")
    key = key:gsub("NUMPAD",         "N")
    key = key:gsub("BUTTON",         "M")
    return key ~= "" and key or nil
end

-------------------------------------------------------------------------------
--- Wipe the CDM Keybind cache `_cdmKeybind`
---
-------------------------------------------------------------------------------
local function WipeCDMKeybindCache()
    wipe(cache._cdmKeybind)
    cache._keybindCacheReady = false
end

-------------------------------------------------------------------------------
--- Rebuilds the Keybind cache `_cdmKeybind`. First wipes this cache,
---   then iterates through `_barBindingDefs` and through the 12 buttons
---   of each action bar to get their keybinds.
--- Works with macros.
--- Sets the `_keybindCacheReady` flag to true when it finishes.
---
-------------------------------------------------------------------------------
local function RebuildKeybindCache()
    WipeCDMKeybindCache()
    for _, def in ipairs(_barBindingDefs) do
        for i = 1, 12 do
            local bindName = def.prefix .. i
            local key = GetBindingKey(bindName)
            if key then
                local slot = def.startSlot + i - 1
                local slotType, id = GetActionInfo(slot)
                local spellID
                if slotType == "spell" then
                    spellID = id
                elseif slotType == "macro" and id then
                    -- GetMacroSpell works for macro-index based entries.
                    -- For direct spell macros, GetActionInfo returns the spell ID as id.
                    local macroSpell = GetMacroSpell(id)
                    spellID = macroSpell or (id > 0 and id) or nil
                end
                if spellID then
                    local formatted = FormatKeybindKey(key)
                    CacheCDMKeybind(spellID, formatted)
                    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                    if name then
                        CacheCDMKeybind(name, formatted)
                    end
                end
            end
        end
    end
    cache._keybindCacheReady = true
end
cache.RebuildKeybindCache = RebuildKeybindCache

-- endregion

-- region Category data

-- Cache category data to avoid double API calls (pre-scan + main loop).
--- @type {[number]: {cat:number, allIDs:number[], knownSet:{[number]:boolean}}}
cache._categoryData = {}

-------------------------------------------------------------------------------
--- Returns the category data cache.
--- @return {[number]: {cat:number, allIDs:number[], knownSet:{[number]:boolean}}} categoryDataCache
-------------------------------------------------------------------------------
local function GetCategoryDataCache()
    return cache._categoryData
end
cache.GetCategoryDataCache = GetCategoryDataCache

-------------------------------------------------------------------------------
--- Wipes the category data cache.
---
-------------------------------------------------------------------------------
local function WipeCategoryDataCache()
    wipe(cache._categoryData)
end
cache.WipeCategoryDataCache = WipeCategoryDataCache

-------------------------------------------------------------------------------
--- (Re)builds the category data cache. First wipes the cache.
--- @param categories {[number]: number}
-------------------------------------------------------------------------------
local function BuildCategoryDataCache(categories)
    WipeCategoryDataCache()

    for _, category in ipairs(categories) do
        local allIDs  = C_CooldownViewer.GetCooldownViewerCategorySet(category, true) or {}
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, false) or {}
        local knownSet = {}
        for _, id in ipairs(knownIDs) do knownSet[id] = true end
        cache._categoryData[#cache._categoryData + 1] = {cat = category,
                                                         allIDs = allIDs,
                                                         knownSet = knownSet}
    end
end
cache.BuildCategoryDataCache = BuildCategoryDataCache
cache.RebuildCategoryDataCache = BuildCategoryDataCache

-- endregion
