local ADDON_NAME, ns = ...
ns.ECdmUtils = {}

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
---
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
        -- On misc bars, hide trinkets that have no on-use effect
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
    -- Hide if player has none and not in combat lockout
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
            -- Desaturate when count is 0 (combat lockout keeps icon visible but grayed)
            if itemCount <= 0 then
                icon._tex:SetDesaturation(1)
                icon._cooldown:Clear()
                icon._lastDesat = true
            else
                -- Item cooldown via C_Container.GetItemCooldown
                ApplyBagItemCooldown(icon, itemID, desatOnCD)
            end
            -- Show item count as charge text
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
