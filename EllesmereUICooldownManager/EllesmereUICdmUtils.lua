local ADDON_NAME, ns = ...
ns.ECdmUtils = {}

local ECache = ns.ECdmCache

-- region Spell override

-------------------------------------------------------------------------------
--- If it exists, returns the spell override ID and nil otherwise
--- now has Divine Toll selected, display and track Divine Toll instead.
--- @param spellID number The original spell ID
--- @return number|nil overrideID The overrideID if overriden, otherwise nil
-------------------------------------------------------------------------------
local function GetSpellOverrideByID(spellID)
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local overrideID = C_SpellBook.FindSpellOverrideByID(spellID)
        if overrideID and overrideID ~= 0 then
            return overrideID
        end
    end
    return nil
end
ns.ECdmUtils.GetSpellOverrideByID = GetSpellOverrideByID

-------------------------------------------------------------------------------
--- Resolve talent override: if the user added Holy Prism but the player
--- now has Divine Toll selected, display and track Divine Toll instead.
--- @param spellID number The original spell ID
--- @return number resolvedID The overrideID if overriden, otherwise spellID
-------------------------------------------------------------------------------
local function ResolveSpellOverrideID(spellID)
    local overrideID = GetSpellOverrideByID(spellID)
    return overrideID or spellID
end
ns.ECdmUtils.ResolveSpellOverrideID = ResolveSpellOverrideID
-- endregion

-- region CDM Icon update

-- region Apply item (bag item or trinket) cooldown (to icon)

-------------------------------------------------------------------------------
--- General item cooldown helper
--- @param icon         table Our ECME icon frame (has _cooldown, _tex and _lastDesat)
--- @param cdStart      number The start time of the cooldown period
--- @param cdDuration   number The duration of the cooldown period
--- @param enable       number 1 if the item has a cooldown, 0 otherwise
--- @param desatOnCD    number 1 if the icon should be desaturated when on CD, 0 otherwise
-------------------------------------------------------------------------------
local function ApplyItemCooldown(icon, cdStart, cdDuration, enable, desatOnCD)
    if cdStart and cdDuration and cdDuration > 1.5 and enable == 1 then
        icon._cooldown:SetCooldown(cdStart, cdDuration)
        if desatOnCD then
            icon._tex:SetDesaturation(1)
            icon._lastDesat = true
        elseif icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    else
        icon._cooldown:Clear()
        if icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    end
end
ns.ECdmUtils.ApplyItemCooldown = ApplyItemCooldown

-------------------------------------------------------------------------------
---  Trinket cooldown helper (inventory slot based)
---  Handles cooldown display and desaturation for trinket slots.
--- @param icon         table Our ECME icon frame
--- @param slot         number The inventory slot ID
--- @param desatOnCD    number 1 if the icon should be desaturated when on CD, 0 otherwise
-------------------------------------------------------------------------------
local function ApplyTrinketCooldown(icon, slot, desatOnCD)
    local cdStart, cdDuration, enable = GetInventoryItemCooldown("player", slot)
    ApplyItemCooldown(icon, cdStart, cdDuration, enable, desatOnCD)
end
ns.ECdmUtils.ApplyTrinketCooldown = ApplyTrinketCooldown

-------------------------------------------------------------------------------
---  Bag item cooldown helper
---  Handles cooldown display and desaturation for bag items.
--- @param icon         table Our ECME icon frame
--- @param itemID       number The ID of the item
--- @param desatOnCD    number 1 if the icon should be desaturated when on CD, 0 otherwise
-------------------------------------------------------------------------------
local function ApplyBagItemCooldown(icon, itemID, desatOnCD)
    local cdStart, cdDuration, enable = C_Container.GetItemCooldown(itemID)
    ApplyItemCooldown(icon, cdStart, cdDuration, enable, desatOnCD)
end
ns.ECdmUtils.ApplyBagItemCooldown = ApplyBagItemCooldown

-- endregion

-- region Update item (bag item or trinket) icon

-------------------------------------------------------------------------------
----
--- @param icon         table Our ECME icon frame
--- @param slot         number The inventory slot ID
--- @param barType      string The bar type (eg. "misc")
--- @param desatOnCD    number 1 if the icon should be desaturated when on CD, 0 otherwise
--- @return boolean visibility true if the icon is visible, false otherwise
-------------------------------------------------------------------------------
local function UpdateTrinketIcon(icon, slot, barType, desatOnCD)
    local spellID = -slot
    local itemID = GetInventoryItemID("player", slot)
    if itemID then
        --- On misc bars, hide trinkets that have no on-use effect
        local trinketHasOneUse = true
        if barType == "misc" then
            local spellName = C_Item.GetItemSpell(itemID)
            if not spellName then
                icon:Hide()
                return false
            end
        end
        local tex = C_Item.GetItemIconByID(itemID)
        if tex and tex ~= icon._lastTex then
            icon._tex:SetTexture(tex)
            icon._lastTex = tex
        end
        icon._spellID = spellID
        ApplyTrinketCooldown(icon, slot, desatOnCD)
        icon:Show()
        return true
    else
        icon:Hide()
        return false
    end
end
ns.ECdmUtils.UpdateTrinketIcon = UpdateTrinketIcon

-------------------------------------------------------------------------------
--- Updates the visibility, texture, saturation, cooldown and item count of our icon
---  (for bag items).
--- @param icon         table Our ECME icon frame (has _cooldown, _tex and _lastDesat)
--- @param itemID       number The ID of the item
--- @param itemCount    number The corresponding item count
--- @param inLockout    boolean true if the player is in combat lockout
--- @param showCharges  boolean true to show item count as charges
--- @param desatOnCD    number 1 if the icon should be desaturated when on CD, 0 otherwise
--- @return boolean visibility true if the icon is visible, false otherwise
-------------------------------------------------------------------------------
local function UpdateBagItemIcon(icon, itemID, itemCount, inLockout, showCharges, desatOnCD)
    --- Hide if player has none and not in combat lockout
    if itemCount <= 0 and not inLockout then
        icon:Hide()
        return false
    else
        local tex = C_Item.GetItemIconByID(itemID)
        if tex then
            if tex ~= icon._lastTex then
                icon._tex:SetTexture(tex)
                icon._lastTex = tex
            end
            icon._spellID = -itemID
            --- Desaturate when count is 0 (combat lockout keeps icon visible but grayed)
            if itemCount <= 0 then
                icon._tex:SetDesaturation(1)
                icon._cooldown:Clear()
                icon._lastDesat = true
            else
                --- Item cooldown via C_Container.GetItemCooldown
                ApplyBagItemCooldown(icon, itemID, desatOnCD)
            end
            --- Show item count as charge text
            if showCharges and itemCount > 0 then
                icon._chargeText:SetText(tostring(itemCount))
                icon._chargeText:Show()
            else
                icon._chargeText:Hide()
            end
            icon:Show()
            return true
        else
            icon:Hide()
            return false
        end
    end
end
ns.ECdmUtils.UpdateBagItemIcon = UpdateBagItemIcon

-- endregion

-- endregion

-- region Buff bar

-------------------------------------------------------------------------------
--- Gets the texture of the buff widget (handles BuffIcon and BuffBar)
--- - BuffIcon children have Icon as a Texture widget directly.
--- - BuffBar children wrap it: Icon is a Frame, Icon.Icon is the Texture.
--- @param icon table                               Our ECME icon frame
--- @param blizzardBuffChild table                  The Blizzard buff child
--- @param overrideTexture number|nil               Eventual hardcoded icon override
--- @return boolean blizzardBuffChildTextureSet     true if the texture was set, false otherwise
-------------------------------------------------------------------------------
local function CopyBuffWidgetTexture(icon, blizzardBuffChild, overrideTexture)
    if blizzardBuffChild and not overrideTexture then
        local iconWidget = blizzardBuffChild.Icon
        if iconWidget and not iconWidget.GetTexture and iconWidget.Icon then
            iconWidget = iconWidget.Icon
        end
        if iconWidget and iconWidget.GetTexture then
            local childTex = iconWidget:GetTexture()
            if childTex then
                icon._tex:SetTexture(childTex)
                icon._lastTex = 0
                return true
            end
        end
    end
    return false
end
ns.ECdmUtils.CopyBuffWidgetTexture = CopyBuffWidgetTexture

-- endregion

-- region "Procables"

-------------------------------------------------------------------------------
--- Overrides/Sets the texture of the icon to be effectiveTexture if the texture
---   of the icon is not already set to the same, and if either an override texture
---   was defined or a proc is active or no texture was already set.
--- @param icon table                           Our ECME icon frame
--- @param effectiveTexture number              The texture to override with
--- @param blizzardBuffChildTextureSet boolean  true if the texture has already been set
--- @param overrideTexture number|nil           Eventual hardcoded icon override
--- @param procActive boolean                   true if a proc is currently active
-------------------------------------------------------------------------------
local function OverrideTextureForProcable(icon, effectiveTexture, blizzardBuffChildTextureSet, overrideTexture, procActive)
    if (not blizzardBuffChildTextureSet or overrideTexture or procActive)
        and effectiveTexture ~= icon._lastTex then
        icon._tex:SetTexture(effectiveTexture)
        icon._lastTex = effectiveTexture
    end
end
ns.ECdmUtils.OverrideTextureForProcable = OverrideTextureForProcable

-- endregion

-------------------------------------------------------------------------------
--- Sets the icon's keybind text to the resolved/cached keybind.
---  Adds the keybind to the cache if not already present.
--- @param icon table           Our ECME icon frame
--- @param spellID number       The original spell ID
--- @param resolvedID number    The resolved spell ID
--- @param showKeybind boolean  true to show keybind, false otherwise
-------------------------------------------------------------------------------
local function SetIconKeybind(icon, spellID, resolvedID, showKeybind)
    -- Cooldown, desaturation, and charge text (consolidated)
    icon._spellID = resolvedID
    -- Apply cached keybind for this spell if not already set
    if icon._keybindText and showKeybind then
        local cachedKey = ECache._cdmKeybind[resolvedID]
        if not cachedKey then
            local n = C_Spell.GetSpellName and C_Spell.GetSpellName(resolvedID)
            if n then cachedKey = ECache._cdmKeybind[n] end
        end
        -- Also try the base spellID in case keybind was cached under it
        if not cachedKey and resolvedID ~= spellID then
            cachedKey = ECache._cdmKeybind[spellID]
            if not cachedKey then
                local bn = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                if bn then cachedKey = ECache._cdmKeybind[bn] end
            end
        end
        if cachedKey then
            icon._keybindText:SetText(cachedKey)
            icon._keybindText:Show()
        elseif icon._keybindText:IsShown() then
            icon._keybindText:Hide()
        end
    end
end
ns.ECdmUtils.SetIconKeybind = SetIconKeybind

-- Table of CDM viewer names
local _cdmViewerNames = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}
ns.ECdmUtils._cdmViewerNames = _cdmViewerNames

-------------------------------------------------------------------------------
--- Scan all four CDM viewers for a child whose .cooldownID matches the given cooldownID.
--- @param cooldownID number|nil    The ID of the cooldown
--- @return Frame|nil childFrame    The child frame, or nil if not found.
-------------------------------------------------------------------------------
local function FindCDMChildByCooldownID(cooldownID)
    if not cooldownID then return nil end
    -- Fast path: scan the per-tick all-child cache (already built by the
    -- viewer scan in UpdateAllCDMBars). Avoids GetChildren() allocation.
    for _, ch in pairs(ECache._tickBlizzAllChild) do
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
ns.ECdmUtils.FindCDMChildByCooldownID = FindCDMChildByCooldownID

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
        local haveTotem = ECache.GetCachedTotemInfo(totemSlot)
        -- haveTotem can be a secret boolean in combat; secret = active totem
        if issecretvalue and issecretvalue(haveTotem) then
            return ECache.IsTotemChildStillValid(child)
        end
        if haveTotem then return ECache.IsTotemChildStillValid(child) end
        return false
    end
    -- Non-totem: check our hook-captured cooldown state tables
    if ECache._ecmeChildHasDurObj[child] then return true end
    local rawDur = ECache._ecmeRawDur[child]
    if rawDur and (issecretvalue and issecretvalue(rawDur) or rawDur > 0) then return true end
    return false
end
ns.ECdmUtils.IsBuffChildCooldownActive = IsBuffChildCooldownActive


-------------------------------------------------------------------------------
--- Detect active aura state before applying cooldown.
--- If the spell has an active player aura, show its duration on the
--- cooldown frame (same as the main bar path for buff bars).
--- When the spell has a runtime override (resolvedID != spellID) on
--- a non-buff bar, skip aura display so the override's actual cooldown
--- is shown instead (e.g. a 2min ability that becomes a 24s kick).
--- @param icon table                   Our ECME icon frame
--- @param spellID number               The original spell ID
--- @param resolvedID number            The resolved spell ID
--- @param isBuffBar boolean            true if the current bar is a buff bar, otherwise false
--- @param activeAnim string            The name of the current animation
--- @param hasRuntimeOverride boolean   true if the spell has a runtime override on a non-buff bar
--- @param assignedChild Frame|nil      The CDM child (for buff bars)
--- @return boolean auraHandled, boolean skipCDDisplay
-------------------------------------------------------------------------------
local function ApplyAuraCooldownOrDuration(icon, spellID, resolvedID, isBuffBar,
                                           activeAnim, hasRuntimeOverride, assignedChild)
    -- Primary: look up the Blizzard CDM child for this spell via the
    -- spellID -> cooldownID map, then find the child frame by cooldownID.
    -- This works for custom bar spells not present in _tickBlizzAllChildCache
    -- because they may not be visible in any viewer at the moment.
    local blizzChild = assignedChild or ECache._tickBlizzAllChild[resolvedID]
    if not blizzChild then
        local cdID = ECache._spellToCooldownID[resolvedID] or ECache._spellToCooldownID[spellID]
        if cdID then
            blizzChild = FindCDMChildByCooldownID(cdID)
        end
    end
    -- For CD/utility bars, prefer the CD-viewer child over the buff-viewer
    -- child so spells that appear in both viewers show their cooldown, not
    -- their buff duration (e.g. Voltaic Blaze).
    if not isBuffBar then
        local cdChild = ECache._tickBlizzCDChild[resolvedID] or ECache._tickBlizzCDChild[spellID]
        if cdChild then blizzChild = cdChild end
    end
    local isAura = blizzChild and (blizzChild.wasSetFromAura == true or blizzChild.auraInstanceID ~= nil)
    local auraID = blizzChild and blizzChild.auraInstanceID
    local auraUnit = blizzChild and blizzChild.auraDataUnit or "player"

    -- Fallback: spell not in any CDM viewer — check _tickBlizzActiveCache
    -- which covers all four viewers scanned each tick.
    if not isAura then
        -- For CD/utility bars: only use the active cache if there's no
        -- dedicated CD-viewer child for this spell. If there is a CD child,
        -- the active cache may have been set by the buff viewer for a
        -- dual-viewer spell — trust the CD child's state instead.
        local skipActiveCache = not isBuffBar
            and (ECache._tickBlizzCDChild[resolvedID] or ECache._tickBlizzCDChild[spellID])
        if not skipActiveCache then
            if ECache._tickBlizzActive[resolvedID] or ECache._tickBlizzActive[spellID] then
                isAura = true
            end
        end
    end

    if isAura and activeAnim ~= "hideActive" then
        -- When the spell has a runtime override on a non-buff bar,
        -- skip aura duration display so the override spell's actual
        -- cooldown is shown (e.g. 2min ability becomes 24s kick).
        if not hasRuntimeOverride then
            local isChargeSid = ECache._multiChargeSpells[resolvedID] == true
            if auraID and (not isChargeSid or isBuffBar) then
                local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                if ok and auraDurObj then
                    icon._cooldown:Clear()
                    pcall(icon._cooldown.SetCooldownFromDurationObject, icon._cooldown, auraDurObj, true)
                    icon._cooldown:SetReverse(false)
                    return true, true
                else
                    -- Totems: skip auraHandled so summon-type fallback shows totem duration
                    local bts = blizzChild and blizzChild.preferredTotemUpdateSlot
                    if not (bts and type(bts) == "number" and bts > 0) then
                        return true, false
                    end
                end
            else
                return true, false
            end
        end
    end

    -- Final fallback: _tickBlizzActiveCache covers spells active in CDM viewers
    if not hasRuntimeOverride and (ECache._tickBlizzActive[resolvedID] or ECache._tickBlizzActive[spellID]) then
        return true, false
    end

    -- Buff bar fallback for spells with no aura (e.g. summons):
    -- when the Blizzard CDM marks the spell as active, the effect is active.
    -- Also check if the buff-viewer child is visible (covers summon
    -- spells like Dreadstalkers that have no aura and no wasSetFromAura).
    -- Copy the child's cooldown state to show the effect duration.
    if not hasRuntimeOverride and activeAnim ~= "hideActive" then
        local blzFbActive = ECache._tickBlizzActive[resolvedID] or ECache._tickBlizzActive[spellID]
        if not blzFbActive then
            local blzBufCh = ECache._tickBlizzBuffChild[resolvedID] or ECache._tickBlizzBuffChild[spellID]
            if IsBuffChildCooldownActive(blzBufCh) then blzFbActive = true end
        end
        if blzFbActive and isBuffBar then
            local blzCh = ECache._tickBlizzAllChild[resolvedID] or ECache._tickBlizzAllChild[spellID]
            -- Use the cached DurationObject captured by our hook
            -- to avoid secret-value arithmetic from GetCooldownTimes.
            if blzCh then
                local blzCD = blzCh.Cooldown
                if blzCD then
                    icon._cooldown:Clear()
                    if ECache._ecmeDurObj[blzCh] then
                        pcall(icon._cooldown.SetCooldownFromDurationObject, icon._cooldown, ECache._ecmeDurObj[blzCh], true)
                    elseif ECache._ecmeRawStart[blzCh] and ECache._ecmeRawDur[blzCh] then
                        pcall(icon._cooldown.SetCooldown, icon._cooldown, ECache._ecmeRawStart[blzCh], ECache._ecmeRawDur[blzCh])
                    end
                    icon._cooldown:SetReverse(false)
                end
            end
            return true, true
        elseif blzFbActive then
            return true, false
        end
    end

    return false, false
end
ns.ECdmUtils.ApplyAuraCooldownOrDuration = ApplyAuraCooldownOrDuration
