local ADDON_NAME, ns = ...
ns.ECdmCache = {}
local cache = ns.ECdmCache

-- region Tables


cache._tickBlizzActive = {}  -- [spellID] = true when Blizzard CDM marks spell as active (wasSetFromAura)
cache._tickBlizzOverride = {} -- [baseSpellID] = overrideSpellID, built each tick from all CDM viewer children
cache._tickBlizzChild = {}    -- [overrideSpellID] = blizzChild, for direct charge/cooldown reads on activation overrides
cache._tickBlizzAllChild = {} -- [resolvedSid] = blizzChild, for all CDM children (used by custom bars)
cache._tickBlizzBuffChild = {} -- [resolvedSid] = blizzChild, only from BuffIcon/BuffBar viewers
cache._tickBlizzCDChild   = {} -- [resolvedSid] = blizzChild, only from Essential/Utility viewers
cache._tickBlizzMultiChild = {} -- [baseSid] = { ch1, ch2, ... } when multiple CDM children share a base spellID
cache._activeMultiScratch = {}      -- reusable scratch table for active multi-child filtering and companion child mapping

-- Export to NS
ns._tickBlizzActiveCache = cache._tickBlizzActive
ns._tickBlizzAllChildCache = cache._tickBlizzAllChild
ns._tickBlizzBuffChildCache = cache._tickBlizzBuffChild


cache._cdmKeybind = {} -- [spellID] -> formatted key string

-- spellID -> cooldownID map built once from C_CooldownViewer.GetCooldownViewerCategorySet (all categories).
-- Rebuilt on PLAYER_LOGIN and spec change. Used by custom bars to find CDM child frames by spellID.
cache._spellToCooldownID = {}

-- Separate tables keyed by child frame reference -- avoids reading tainted fields on Blizzard-owned frames.
-- ch.isActive and ch._ecmeDurObj etc. are tainted secret values; we track state in our own tables instead.
cache._ecmeChildHasDurObj = {}
cache._ecmeDurObj = {}                           -- [ch] = durObj captured from SetCooldownFromDurationObject hook
cache._ecmeRawStart = {}                         -- [ch] = start captured from SetCooldown hook
cache._ecmeRawDur = {}                           -- [ch] = dur captured from SetCooldown hook
cache._tickTotem = {}                            -- [slot] = haveTotem (cached per tick to avoid inconsistent reads)
cache._cdmHoverStates = {}                       -- [barKey] = { isHovered=false, fadeDir=nil }

-- Export to NS
ns._ecmeDurObjCache = cache._ecmeDurObj
ns._ecmeRawStartCache = cache._ecmeRawStart
ns._ecmeRawDurCache = cache._ecmeRawDur

-- endregion

-- region Tick

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

-------------------------------------------------------------------------------
--- Wipe per-tick caches (GCD, charges, auras, totem info)
---
-------------------------------------------------------------------------------
local function WipePerTickCaches()
    wipe(cache._tickGCD)
    wipe(cache._tickCharge)
    wipe(cache._tickAura)
    wipe(cache._tickTotem)
end
cache.WipePerTickCaches = WipePerTickCaches

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

-- region Totem Cache

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



