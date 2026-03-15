local ADDON_NAME, ns = ...
ns.ECdmCache = {}

-- region Tables

ns.ECdmCache._tickGCD   = {}  -- [spellID] = bool|nil (GCD check result)
ns.ECdmCache._tickCharge = {} -- [spellID] = charges table or false
ns.ECdmCache._tickAura  = {}  -- [spellID] = aura table or false
ns.ECdmCache._tickBlizzActive = {}  -- [spellID] = true when Blizzard CDM marks spell as active (wasSetFromAura)
ns.ECdmCache._tickBlizzOverride = {} -- [baseSpellID] = overrideSpellID, built each tick from all CDM viewer children
ns.ECdmCache._tickBlizzChild = {}    -- [overrideSpellID] = blizzChild, for direct charge/cooldown reads on activation overrides
ns.ECdmCache._tickBlizzAllChild = {} -- [resolvedSid] = blizzChild, for all CDM children (used by custom bars)
ns.ECdmCache._tickBlizzBuffChild = {} -- [resolvedSid] = blizzChild, only from BuffIcon/BuffBar viewers
ns.ECdmCache._tickBlizzCDChild   = {} -- [resolvedSid] = blizzChild, only from Essential/Utility viewers
ns.ECdmCache._tickBlizzMultiChild = {} -- [baseSid] = { ch1, ch2, ... } when multiple CDM children share a base spellID
ns.ECdmCache._activeMultiScratch = {}      -- reusable scratch table for active multi-child filtering and companion child mapping

ns._tickAuraCache = ns.ECdmCache._tickAura
ns._tickBlizzActiveCache = ns.ECdmCache._tickBlizzActive
ns._tickBlizzAllChildCache = ns.ECdmCache._tickBlizzAllChild
ns._tickBlizzBuffChildCache = ns.ECdmCache._tickBlizzBuffChild


ns.ECdmCache._cdmKeybind = {} -- [spellID] -> formatted key string

-- spellID -> cooldownID map built once from C_CooldownViewer.GetCooldownViewerCategorySet (all categories).
-- Rebuilt on PLAYER_LOGIN and spec change. Used by custom bars to find CDM child frames by spellID.
ns.ECdmCache._spellToCooldownID = {}

-- Separate tables keyed by child frame reference -- avoids reading tainted fields on Blizzard-owned frames.
-- ch.isActive and ch._ecmeDurObj etc. are tainted secret values; we track state in our own tables instead.
ns.ECdmCache._ecmeChildHasDurObj = {}
ns.ECdmCache._ecmeDurObj = {}                           -- [ch] = durObj captured from SetCooldownFromDurationObject hook
ns.ECdmCache._ecmeRawStart = {}                         -- [ch] = start captured from SetCooldown hook
ns.ECdmCache._ecmeRawDur = {}                           -- [ch] = dur captured from SetCooldown hook
ns.ECdmCache._tickTotem = {}                            -- [slot] = haveTotem (cached per tick to avoid inconsistent reads)
ns.ECdmCache._cdmHoverStates = {}                       -- [barKey] = { isHovered=false, fadeDir=nil }

ns._ecmeDurObjCache = ns.ECdmCache._ecmeDurObj
ns._ecmeRawStartCache = ns.ECdmCache._ecmeRawStart
ns._ecmeRawDurCache = ns.ECdmCache._ecmeRawDur

-- Multi-charge spell cache: populated out of combat when values are not secret.
-- Falls back to SavedVariables for combat /reload scenarios.
-- Maps spellID true for spells with maxCharges > 1
ns.ECdmCache._multiChargeSpells = {}
ns.ECdmCache._maxChargeCount    = {}  -- [spellID] = maxCharges, populated alongside _multiChargeSpells


-- endregion

----------------------------------------------------------------------------------------------------------------------
--- Per-tick cached GetTotemInfo to prevent inconsistent reads during totem expiry.
--- @param slot number The slot to check
--- @return boolean haveTotem
----------------------------------------------------------------------------------------------------------------------
local function GetCachedTotemInfo(slot)
    local cached = ns.ECdmCache._tickTotem[slot]
    if cached ~= nil then return cached end
    local haveTotem = GetTotemInfo(slot)
    ns.ECdmCache._tickTotem[slot] = haveTotem
    return haveTotem
end
ns.ECdmCache.GetCachedTotemInfo = GetCachedTotemInfo

----------------------------------------------------------------------------------------------------------------------
--- Secondary validation: GetTotemInfo confirms a totem exists in the slot but not
--- WHICH totem. This checks the child's own aura/cooldown data is still live.
--- comment
--- @param child table The child to check
--- @return boolean haveTotem
----------------------------------------------------------------------------------------------------------------------
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
    if ns.ECdmCache._ecmeChildHasDurObj[child] then return true end
    local rd = ns.ECdmCache._ecmeRawDur[child]
    if rd then
        if issecretvalue and issecretvalue(rd) then return true end
        return rd > 0
    end
    -- Fallback: hook caches are empty after /reload until SetCooldown fires.
    if child.Cooldown and child.Cooldown:IsVisible() then return true end
    return false
end
ns.ECdmCache.IsTotemChildStillValid = IsTotemChildStillValid
