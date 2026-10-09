-- CleanUI integration:
-- - Adds sort by rarity to CleanUI sort menu
-- - Adds rarity comparators to ISInventoryPane
-- - Persists rarity sort in SaveLayout/RestoreLayout

require "ZItemTiers/core"

local function comparePrefix(a, b)
    if a.equipped and not b.equipped then return false end
    if b.equipped and not a.equipped then return true end
    if not a.equipped and not b.equipped then
        if a.type == "separator" then return false end
        if b.type == "separator" then return true end
    end
    return nil
end

local function getRepresentativeItem(group)
    if not group or not group.items then return nil end
    -- CleanUI prepends a synthetic copy of the first real item at index 1.
    -- Use index 2 first so tier lookups read actual stack data consistently.
    if group.items[2] then return group.items[2] end
    return group.items[1]
end

local function getTierIndex(group)
    local item = getRepresentativeItem(group)
    if not item then return ZItemTiers.CommonIdx end
    return ZItemTiers.GetItemTierIndex(item)
end

local function sortTieByNameAsc(a, b)
    return not string.sort(a.name, b.name)
end

local function sortTieByNameDesc(a, b)
    return string.sort(a.name, b.name)
end

local function ensurePaneComparators()
    if not ISInventoryPane then return false end
    if ISInventoryPane.itemSortByRarityAsc and ISInventoryPane.itemSortByRarityDesc then
        return true
    end

    ISInventoryPane.itemSortByRarityAsc = function(a, b)
        local pref = comparePrefix(a, b)
        if pref ~= nil then return pref end

        local at = getTierIndex(a)
        local bt = getTierIndex(b)
        if at == bt then return sortTieByNameAsc(a, b) end
        return at < bt
    end

    ISInventoryPane.itemSortByRarityDesc = function(a, b)
        local pref = comparePrefix(a, b)
        if pref ~= nil then return pref end

        local at = getTierIndex(a)
        local bt = getTierIndex(b)
        if at == bt then return sortTieByNameDesc(a, b) end
        return at > bt
    end

    return true
end

local function ensureComparatorsForPaneInstance(pane)
    if not pane then return false end
    if not ensurePaneComparators() then return false end

    local paneClass = getmetatable(pane)
    if type(paneClass) ~= "table" then return true end
    if paneClass.itemSortByRarityAsc and paneClass.itemSortByRarityDesc then return true end

    -- Loot/inventory pages may run different pane class tables at runtime
    -- (e.g. class swaps/rebuilds). Mirror comparators onto the active class.
    paneClass.itemSortByRarityAsc = ISInventoryPane.itemSortByRarityAsc
    paneClass.itemSortByRarityDesc = ISInventoryPane.itemSortByRarityDesc
    return true
end

local function installSortMenuHooks()
    if not ISInventoryCommonHandler_SortMenu then return false end
    if ISInventoryCommonHandler_SortMenu._zitRaritySortPatched then return true end

    function ISInventoryCommonHandler_SortMenu:sortByRarity()
        local window = self:getWindow()
        if not window or not window.inventoryPane then return end

        local pane = window.inventoryPane
        if not ensureComparatorsForPaneInstance(pane) then return end

        if pane.itemSortFunc == ISInventoryPane.itemSortByRarityAsc then
            pane.itemSortFunc = ISInventoryPane.itemSortByRarityDesc
        else
            pane.itemSortFunc = ISInventoryPane.itemSortByRarityAsc
        end
        pane:refreshContainer()
    end

    local function rebindSortControl(self)
        if not self.control then return end
        -- Existing controls can keep old function references after patches/UI rebuilds.
        -- Rebind so every sort button uses the augmented perform() below.
        self.control.target = self
        self.control.onclick = ISInventoryCommonHandler_SortMenu.perform
    end

    ISInventoryCommonHandler_SortMenu.getControl = function(self)
        if not self.control then
            self:createSortControl()
        end
        rebindSortControl(self)
        return self.control
    end

    ISInventoryCommonHandler_SortMenu.createSortControl = function(self)
        local fontHgtSmall = getTextManager():getFontHeight(UIFont.Small)
        local buttonHeight = math.floor(fontHgtSmall * 1.2)

        self.control = ISButton:new(0, 0, buttonHeight, buttonHeight, "", self, ISInventoryCommonHandler_SortMenu.perform)
        self.control:initialise()
        self.control.prerender = function(btn)
            local brightness = btn.mouseOver and 0.2 or 0.1
            btn:drawTextureScaled(getTexture("media/ui/CleanUI/Button/SQBackground.png"), 0, 0, btn.width, btn.height, 0.6, brightness, brightness, brightness)
            btn:drawTextureScaled(getTexture("media/ui/CleanUI/Button/SQBorder.png"), 0, 0, btn.width, btn.height, 1, 0.4, 0.4, 0.4)

            local iconSize = math.floor(btn.width * 0.8)
            local IconXY = (btn.width - iconSize) / 2
            btn:drawTextureScaled(getTexture("media/ui/CleanUI/Icon/Icon_SortButton.png"), IconXY, IconXY, iconSize, iconSize, 1, 0.6, 0.6, 0.6)
        end

        rebindSortControl(self)
    end

    ISInventoryCommonHandler_SortMenu.perform = function(self)
        local window = self:getWindow()
        if not window then return end
        if not self.control then return end

        local x = self.control:getAbsoluteX()
        local y = self.control:getAbsoluteY() + self.control:getHeight()
        local context = ISContextMenu.get(self.playerNum, x, y)

        local nameOption = context:addOption(getText("IGUI_Name"), self, ISInventoryCommonHandler_SortMenu.sortByName)
        local nameIcon = getTexture("media/ui/CleanUI/ICON/Icon_SortByName.png")
        if nameIcon then
            nameOption.iconTexture = nameIcon
        end

        local typeOption = context:addOption(getText("IGUI_invpanel_Category"), self, ISInventoryCommonHandler_SortMenu.sortByType)
        local typeIcon = getTexture("media/ui/CleanUI/ICON/Icon_SortByType.png")
        if typeIcon then
            typeOption.iconTexture = typeIcon
        end

        local weightOption = context:addOption(getText("IGUI_invpanel_weight"), self, ISInventoryCommonHandler_SortMenu.sortByWeight)
        local weightIcon = getTexture("media/ui/CleanUI/ICON/Icon_Weight.png")
        if weightIcon then
            weightOption.iconTexture = weightIcon
        end

        -- Keep native sort options and append rarity as an extra mode.
        context:addOption("Rarity", self, ISInventoryCommonHandler_SortMenu.sortByRarity)

        if context.numOptions > 1 then
            context:setVisible(true)

            if JoypadState.players[self.playerNum + 1] then
                context.origin = window
                context.mouseOver = 1
                setJoypadFocus(self.playerNum, context)
            end
        end
    end

    ISInventoryCommonHandler_SortMenu._zitRaritySortPatched = true
    return true
end

local function installLayoutHooks()
    if not ISInventoryPane then return false end
    if ISInventoryPane._zitRarityLayoutPatched then return true end

    zdk.hook({
        ISInventoryPane = {
            SaveLayout = function(orig, self, name, layout, ...)
                orig(self, name, layout, ...)
                if not ensurePaneComparators() then return end
                if self.itemSortFunc == self.itemSortByRarityAsc then layout.sortBy = "rarityAsc" end
                if self.itemSortFunc == self.itemSortByRarityDesc then layout.sortBy = "rarityDesc" end
            end,

            RestoreLayout = function(orig, self, name, layout, ...)
                if ensurePaneComparators() and layout and layout.sortBy == "rarityAsc" then
                    self.itemSortFunc = self.itemSortByRarityAsc
                elseif ensurePaneComparators() and layout and layout.sortBy == "rarityDesc" then
                    self.itemSortFunc = self.itemSortByRarityDesc
                end
                return orig(self, name, layout, ...)
            end
        }
    })

    ISInventoryPane._zitRarityLayoutPatched = true
    return true
end

local function installCleanUIRaritySort()
    local ok = ensurePaneComparators()
    ok = installLayoutHooks() and ok
    ok = installSortMenuHooks() and ok
    return ok
end

Events.OnGameStart.Add(function()
    installCleanUIRaritySort()
end)
