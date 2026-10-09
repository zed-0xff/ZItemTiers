-- Hook into refreshContainer to ungroup items with different tiers
zdk.hook({
    ISInventoryPane = {
        refreshContainer = function(orig, self, ...)
            orig(self, ...)

            -- After items are grouped, check for mixed tiers and ungroup them
            if self.itemslist then
                local playerObj = getSpecificPlayer(self.player)
                local newItemslist = {}

                for _, group in ipairs(self.itemslist) do
                    if group.items and #group.items > 0 then
                        -- Check if all items in this group have the same tier
                        local tiers = {}
                        local itemsByTier = {}

                        -- original code adds a duplicate first item at the end of refreshContainer
                        -- Since we hook after originalRefreshContainer, the duplicate should already be there
                        -- We need to check all items (including potential duplicates) and group by tier

                        -- Collect all unique items and their tiers
                        local seenItems = {}
                        for _, item in ipairs(group.items) do
                            if item then
                                -- Use item ID to avoid counting duplicates
                                local itemId = nil
                                local successId, id = pcall(function()
                                    if item.getID then
                                        return item:getID()
                                    end
                                    return nil
                                end)
                                if successId and id then
                                    itemId = id
                                end

                                -- Only process each unique item once
                                if itemId and not seenItems[itemId] then
                                    seenItems[itemId] = true
                                    local tier = ZItemTiers.GetItemTierKey(item)
                                    if not itemsByTier[tier] then
                                        itemsByTier[tier] = {}
                                        tiers[#tiers + 1] = tier
                                    end
                                    table.insert(itemsByTier[tier], item)
                                elseif not itemId then
                                    -- Fallback: if we can't get ID, check by object reference
                                    local found = false
                                    for _, seenItem in pairs(seenItems) do
                                        if seenItem == item then
                                            found = true
                                            break
                                        end
                                    end
                                    if not found then
                                        seenItems[item] = true
                                        local tier = ZItemTiers.GetItemTierKey(item)
                                        if not itemsByTier[tier] then
                                            itemsByTier[tier] = {}
                                            tiers[#tiers + 1] = tier
                                        end
                                        table.insert(itemsByTier[tier], item)
                                    end
                                end
                            end
                        end

                        -- If all items have the same tier, keep the group as-is
                        if #tiers <= 1 then
                            table.insert(newItemslist, group)
                        else
                            -- Items have different tiers - split into separate groups
                            for _, tier in ipairs(tiers) do
                                local tierItems = itemsByTier[tier]
                                if tierItems and #tierItems > 0 then
                                    -- Create a new group for this tier
                                    local newGroup = {}
                                    newGroup.items = {}

                                    -- Add the first item of THIS tier as duplicate (vanilla uses this for title/display)
                                    -- This ensures each tier group shows the correct tier in the title
                                    if #tierItems > 0 then
                                        table.insert(newGroup.items, tierItems[1])
                                    end

                                    -- Add all items of this tier
                                    for _, item in ipairs(tierItems) do
                                        table.insert(newGroup.items, item)
                                    end

                                    newGroup.count = #newGroup.items
                                    newGroup.invPanel = group.invPanel

                                    -- Recalculate name from the first item of this tier group using the same logic as vanilla
                                    -- This ensures each tier group shows the correct item name
                                    if #newGroup.items > 0 and newGroup.items[1] and playerObj then
                                        local itemName = newGroup.items[1]:getName(playerObj)

                                        -- Apply the same prefixes that vanilla uses (equipped, keyring, hotbar)
                                        if group.equipped then
                                            if string.find(itemName, "^equipped:") == nil and
                                                string.find(itemName, "^keyring:") == nil then
                                                itemName = "equipped:" .. itemName
                                            end
                                        end
                                        if group.inHotbar and not group.equipped then
                                            if string.find(itemName, "^hotbar:") == nil then
                                                itemName = "hotbar:" .. itemName
                                            end
                                        end

                                        newGroup.name = itemName
                                    else
                                        newGroup.name = group.name  -- Fallback to original name
                                    end

                                    newGroup.cat = group.cat
                                    newGroup.equipped = group.equipped
                                    newGroup.inHotbar = group.inHotbar
                                    newGroup.matchesSearch = group.matchesSearch

                                    -- Calculate weight for this tier group
                                    local weight = 0
                                    for _, item in ipairs(tierItems) do
                                        if item then
                                            weight = weight + item:getUnequippedWeight()
                                        end
                                    end
                                    newGroup.weight = weight

                                    -- Copy collapsed state (use the new name for the key)
                                    if self.collapsed then
                                        if self.collapsed[newGroup.name] == nil then
                                            self.collapsed[newGroup.name] = true
                                        end
                                    end

                                    table.insert(newItemslist, newGroup)
                                end
                            end
                        end
                    else
                        -- Group has no items or is a separator, keep as-is
                        table.insert(newItemslist, group)
                    end
                end

                -- Replace itemslist with the ungrouped version
                self.itemslist = newItemslist

                -- Keep rarity ordering stable after post-sort tier ungrouping.
                if self.itemSortFunc and ISInventoryPane then
                    if self.itemSortFunc == ISInventoryPane.itemSortByRarityAsc or
                        self.itemSortFunc == ISInventoryPane.itemSortByRarityDesc then
                        if self.searchText and self.searchText ~= "" then
                            -- Preserve CleanUI search priority: matching rows first, then active sort.
                            -- Without this, rarity re-sort would undo search bumping and hide matches in-place.
                            table.sort(self.itemslist, function(a, b)
                                if a.matchesSearch and not b.matchesSearch then
                                    return true
                                end
                                if not a.matchesSearch and b.matchesSearch then
                                    return false
                                end
                                return self.itemSortFunc(a, b)
                            end)
                        else
                            table.sort(self.itemslist, self.itemSortFunc)
                        end
                    end
                end
            end
        end
    },
})

