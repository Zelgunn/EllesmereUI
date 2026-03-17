local ADDON_NAME, ns = ...
ns.ECdmUtils = {}

local utils = ns.ECdmUtils
local ECache = ns.ECdmCache

-- region Spell ID resolution

-------------------------------------------------------------------------------
--- Resolve the best spellID from a CooldownViewerCooldownInfo struct.
--- Priority: overrideSpellID > first linkedSpellID > spellID.
--- The base spellID field can be a spec aura (e.g. 137007 "Unholy Death
--- Knight") while the real tracked spell lives in linkedSpellIDs.
--- @param info CooldownViewerCooldown The spell info to perform resolution on
--- @return number|nil resolvedID
-------------------------------------------------------------------------------
local function ResolveInfoSpellID(info)
    if not info then return nil end
    local sid
    if info.overrideSpellID and info.overrideSpellID > 0 then
        sid = info.overrideSpellID
    else
        local linked = info.linkedSpellIDs
        if linked then
            for i = 1, #linked do
                if linked[i] and linked[i] > 0 then sid = linked[i]; break end
            end
        end
        if not sid and info.spellID and info.spellID > 0 then sid = info.spellID end
    end
    return sid and (ns.BUFF_SPELLID_CORRECTIONS[sid] or sid) or nil
end
utils.ResolveInfoSpellID = ResolveInfoSpellID

-------------------------------------------------------------------------------
--- Resolve the best spellID from a Blizzard CDM viewer child frame.
--- For buff bars the cooldownInfo struct often contains the wrong spellID
--- (spec aura instead of the actual tracked buff). The child frame itself
--- knows the correct spell via GetAuraSpellID / GetSpellID at runtime.
--- Falls back to ResolveInfoSpellID when the frame methods aren't available.
--- ONLY used in out-of-combat paths (snapshot, dropdown, reconcile).
--- @param child table
--- @return number|nil resolvedID
-------------------------------------------------------------------------------
local function ResolveChildSpellID(child)
    if not child then return nil end
    -- Prefer the aura spellID (most accurate for buff viewers).
    -- Wrap comparisons in pcall: these frame methods can return secret
    -- number values in combat which cannot be compared with > 0.
    if child.GetAuraSpellID then
        local ok, auraID = pcall(child.GetAuraSpellID, child)
        if ok and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return ns.BUFF_SPELLID_CORRECTIONS[auraID] or auraID end
        end
    end
    -- Then try the frame's own spellID
    if child.GetSpellID then
        local ok, fid = pcall(child.GetSpellID, child)
        if ok and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return ns.BUFF_SPELLID_CORRECTIONS[fid] or fid end
        end
    end
    -- Fall back to cooldownInfo struct
    local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        return ResolveInfoSpellID(info)
    end
    return nil
end
utils.ResolveChildSpellID = ResolveChildSpellID

-- endregion

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
utils.GetSpellOverrideByID = GetSpellOverrideByID

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
utils.ResolveSpellOverrideID = ResolveSpellOverrideID
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
utils.ApplyItemCooldown = ApplyItemCooldown

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
utils.ApplyTrinketCooldown = ApplyTrinketCooldown

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
utils.ApplyBagItemCooldown = ApplyBagItemCooldown

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
utils.UpdateTrinketIcon = UpdateTrinketIcon

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
utils.UpdateBagItemIcon = UpdateBagItemIcon

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
    if blizzardBuffChild and not overrideTexture and blizzardBuffChild.Icon then
        local iconWidget = blizzardBuffChild.Icon
        if not iconWidget.GetTexture and iconWidget.Icon then
            iconWidget = iconWidget.Icon
        end
        if iconWidget.GetTexture then
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
utils.CopyBuffWidgetTexture = CopyBuffWidgetTexture

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
utils.OverrideTextureForProcable = OverrideTextureForProcable

-------------------------------------------------------------------------------
--- Get the texture for a "procable" buff. If a proc is active, returns the proc's
---     texture if one can be found. Caches the proc texture if needed. Otherwise,
---     returns the base texture given as currentTexture
--- @param spellID number           The base spell ID before resolution
--- @param resolvedID number        The spell ID after resolution
--- @param currentTexture number    The base/current texture to fallback to without proc
--- @return number updatedTexture, boolean procActive  The proc texture if relevant and if it exists, otherwise currentTexture
--- 
-------------------------------------------------------------------------------
local function GetTextureForProcable(spellID, resolvedID, currentTexture)
    local procEntry = ns.BUFF_PROC_ICON_OVERRIDES[spellID] or ns.BUFF_PROC_ICON_OVERRIDES[resolvedID]
    if procEntry then
        local buffChild = ECache.GetTickBlizzardBuffChild(procEntry.buffID)
        if ECache.IsBuffChildCooldownActive(buffChild) then
            local procTexture = ECache.CacheSpellIconTexture(procEntry.replacementSpellID)
            if procTexture then
                return procTexture, true
            end
        end
    end
    return currentTexture, false
end
utils.GetTextureForProcable = GetTextureForProcable

-- endregion

-- region Icon Keybind

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
        local cachedKey = ECache.GetCDMKeybind(resolvedID)
        if not cachedKey then
            local n = C_Spell.GetSpellName and C_Spell.GetSpellName(resolvedID)
            if n then cachedKey = ECache.GetCDMKeybind(n) end
        end
        -- Also try the base spellID in case keybind was cached under it
        if not cachedKey and resolvedID ~= spellID then
            cachedKey = ECache.GetCDMKeybind(spellID)
            if not cachedKey then
                local bn = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                if bn then cachedKey = ECache.GetCDMKeybind(bn) end
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
utils.SetIconKeybind = SetIconKeybind

-- endregion

-- region Aura Cooldown/Duration

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
    local blizzChild = assignedChild or ECache.GetTickBlizzardAllChild(resolvedID)
    if not blizzChild then
        local cdID = ECache.GetResolvedCooldownIDFromSpell(spellID, resolvedID)
        if cdID then
            blizzChild = ECache.FindCDMChildByCooldownID(cdID)
        end
    end
    -- For CD/utility bars, prefer the CD-viewer child over the buff-viewer
    -- child so spells that appear in both viewers show their cooldown, not
    -- their buff duration (e.g. Voltaic Blaze).
    if not isBuffBar then
        local cdChild = ECache.GetResolvedTickBlizzardCDChild(spellID, resolvedID)
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
            and (ECache.GetResolvedTickBlizzardCDChild(spellID, resolvedID))
        if not skipActiveCache then
            if ECache.IsTickBlizzardActive(spellID, resolvedID) then
                isAura = true
            end
        end
    end

    if isAura and activeAnim ~= "hideActive" then
        -- When the spell has a runtime override on a non-buff bar,
        -- skip aura duration display so the override spell's actual
        -- cooldown is shown (e.g. 2min ability becomes 24s kick).
        if not hasRuntimeOverride then
            local isChargeSid = ECache.IsCachedChargeSpell(resolvedID)
            -- Charge spells: prefer recharge timer unless the
            -- buff-viewer is actively tracking this spell.
            local chargeShowsAura = not isChargeSid or isBuffBar
            if isChargeSid and not isBuffBar then
                local bufCh = ECache.GetResolvedBlizzardBuffChild(spellID, resolvedID)
                if ECache.IsBuffChildCooldownActive(bufCh) then
                    chargeShowsAura = true
                end
            end
            if auraID and chargeShowsAura then
                local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                if ok and auraDurObj then
                    icon._cooldown:Clear()
                    pcall(icon._cooldown.SetCooldownFromDurationObject, icon._cooldown, auraDurObj, true)
                    icon._cooldown:SetReverse(false)
                    return true, true
                else
                    -- Totems: skip auraHandled so summon-type fallback shows totem duration
                    -- todo: move to a separate function?
                    local bts = blizzChild and blizzChild.preferredTotemUpdateSlot
                    if not (bts and type(bts) == "number" and bts > 0) then
                        local fixedDur = ns.PLACED_UNIT_DURATIONS[resolvedID]
                                         or ns.PLACED_UNIT_DURATIONS[spellID]
                        local fixedSid = fixedDur and (ns.PLACED_UNIT_DURATIONS[resolvedID] and resolvedID or spellID)
                        if fixedDur and isBuffBar then
                            ECache.CachePlacedUnitStart(fixedSid)
                            icon._cooldown:Clear()
                            pcall(icon._cooldown.SetCooldown, icon._cooldown, ECache.GetPlacedUnitStart(fixedSid), fixedDur)
                            icon._cooldown:SetReverse(false)
                            return true, true
                        else
                            return true, false
                        end
                    end
                end
            else
                return true, false
            end
        end
    end

    -- Final fallback: _tickBlizzActiveCache covers spells active in CDM viewers
    if not hasRuntimeOverride and ECache.IsTickBlizzardActive(spellID, resolvedID) then
        return true, false
    end

    -- Buff bar fallback for spells with no aura (e.g. summons):
    -- when the Blizzard CDM marks the spell as active, the effect is active.
    -- Also check if the buff-viewer child is visible (covers summon
    -- spells like Dreadstalkers that have no aura and no wasSetFromAura).
    -- Copy the child's cooldown state to show the effect duration.
    if not hasRuntimeOverride and activeAnim ~= "hideActive" then
        local blzFbActive = ECache.IsTickBlizzardActive(spellID, resolvedID)
        if not blzFbActive then
            local blzBufCh = ECache.GetResolvedBlizzardBuffChild(spellID, resolvedID)
            if ECache.IsBuffChildCooldownActive(blzBufCh) then blzFbActive = true end
        end
        if blzFbActive and isBuffBar then
            local blzCh = ECache.GetResolvedBlizzardAllChild(spellID, resolvedID)
            -- Use the cached DurationObject captured by our hook
            -- to avoid secret-value arithmetic from GetCooldownTimes.
            if blzCh then
                local blzCD = blzCh.Cooldown
                if blzCD then
                    icon._cooldown:Clear()
                    if ECache.GetECMEDurationObject(blzCh) then
                        pcall(icon._cooldown.SetCooldownFromDurationObject, icon._cooldown, ECache.GetECMEDurationObject(blzCh), true)
                    elseif ECache.GetECMERawStart(blzCh) and ECache.GetECMERawDuration(blzCh) then
                        pcall(icon._cooldown.SetCooldown, icon._cooldown, ECache.GetECMERawStart(blzCh), ECache.GetECMERawDuration(blzCh))
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
utils.ApplyAuraCooldownOrDuration = ApplyAuraCooldownOrDuration

-------------------------------------------------------------------------------
--- Updates the icon cooldown swipe direction (reverse for buffs).
--- Also updates the displayed timer if it is a placed unit (e.g. Consecration)
--- @param icon table                   Our ECME icon frame
--- @param spellID number               The original spell ID
--- @param resolvedID number            The resolved spell ID
--- @param auraHandled boolean          true if the aura has already been handled
--- @return boolean auraHandled         true if the aura was handled previously or by this function
-------------------------------------------------------------------------------
local function UpdateBuffSwipeAndTimer(icon, spellID, resolvedID, auraHandled)
    local fixedDur = ns.PLACED_UNIT_DURATIONS[resolvedID] or ns.PLACED_UNIT_DURATIONS[spellID]
    if fixedDur then
        local fixedSid = ns.PLACED_UNIT_DURATIONS[resolvedID] and resolvedID or spellID
        local isPlacedActive = ECache.IsTickBlizzardActive(spellID, resolvedID)
        if isPlacedActive then
            ECache.CachePlacedUnitStart(fixedSid)
            icon._cooldown:Clear()
            pcall(icon._cooldown.SetCooldown, icon._cooldown, ECache.GetPlacedUnitStart(fixedSid), fixedDur)
            if icon._tex then icon._tex:SetDesaturation(0) end
            icon._lastDesat = false
            auraHandled = true
        else
            ECache.RemovePlacedUnitStart(fixedSid)
        end
    end
    icon._cooldown:SetReverse(auraHandled)
    return auraHandled
end
utils.UpdateBuffSwipeAndTimer = UpdateBuffSwipeAndTimer

-- endregion

-- region Category data

-------------------------------------------------------------------------------
--- Pre-scan ALL categories before the main loop. Blizzard can issue two cdIDs
--- for the same spell (one learned, one not) and they can be in different
--- categories. Building spellIDKnown per-category would miss cross-category
--- matches, causing the spell to appear unlearned if the unlearned cdID is in
--- an earlier category than the learned one. Register every spellID variant
--- (frame-resolved, override/linked, base) for learned cdIDs.
--- @param cdIDToChildSID {[number]: number}
--- @return {[number]: boolean}
-------------------------------------------------------------------------------
local function ScanAllCategories(cdIDToChildSID)
    local spellIDKnown = {}
    for _, cd in ipairs(ECache.GetCategoryDataCache()) do
        for _, cdID in ipairs(cd.allIDs) do
            if cd.knownSet[cdID] then
                local s1 = cdIDToChildSID[cdID]
                if s1 and s1 > 0 then spellIDKnown[s1] = true end
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    local s2 = ResolveInfoSpellID(info)
                    if s2 and s2 > 0 then spellIDKnown[s2] = true end
                    if info.spellID and info.spellID > 0 then spellIDKnown[info.spellID] = true end
                end
            end
        end
    end
    return spellIDKnown
end
utils.ScanAllCategories = ScanAllCategories

-- endregion
