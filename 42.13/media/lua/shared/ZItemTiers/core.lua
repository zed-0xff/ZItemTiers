ZItemTiers = ZItemTiers or {}

ZItemTiers.logger = zdk.Logger.new("ZItemTiers", zdk.Logger.DEBUG)
local logger = ZItemTiers.logger

-- Initialize global session ID for bonus tracking (initialized once per game session)
if not ZItemTiers.sid then
    ZItemTiers.sid = ZombRand(1000000)
end

-- Default tier probabilities (percentages): Uncommon, Rare, Epic, Legendary
-- Common gets the remainder. Configurable via sandbox options.
ZItemTiers.DefaultTierChances = {
    Uncommon  = 16.0,
    Rare      = 3.2,
    Epic      = 0.64,
    Legendary = 0.16,
}

-- Build TierProbabilities array [Common, Uncommon, Rare, Epic, Legendary] from sandbox options
-- Called once on first roll, then cached until sandbox options change
function ZItemTiers.BuildTierProbabilities()
    local sv = SandboxVars and SandboxVars.ZItemTiers
    local defaults = ZItemTiers.DefaultTierChances

    local uncommon  = (sv and type(sv.UncommonChance)  == "number" and sv.UncommonChance  or defaults.Uncommon)  / 100.0
    local rare      = (sv and type(sv.RareChance)      == "number" and sv.RareChance      or defaults.Rare)      / 100.0
    local epic      = (sv and type(sv.EpicChance)      == "number" and sv.EpicChance      or defaults.Epic)      / 100.0
    local legendary = (sv and type(sv.LegendaryChance) == "number" and sv.LegendaryChance or defaults.Legendary) / 100.0

    local common = math.max(0, 1.0 - uncommon - rare - epic - legendary)

    ZItemTiers.TierProbabilities = {common, uncommon, rare, epic, legendary}
    return ZItemTiers.TierProbabilities
end

ZItemTiers.TierProbabilities = nil -- lazily initialized on first RollT0()

-- Global constants for convenience
ZItemTiers.CommonIdx = 1

-- Tier metadata: name, color, and index
ZItemTiers.Tiers = {
    Common = {
        t0    = 0,
        index = ZItemTiers.CommonIdx,
        name  = "Common",
        color = {r=1.0, g=1.0, b=1.0},  -- White
    },
    Uncommon = {
        t0    = 1,
        index = ZItemTiers.CommonIdx + 1,
        name  = "Uncommon",
        color = {r=0.2, g=1.0, b=0.2},  -- Green
    },
    Rare = {
        t0    = 2,
        index = ZItemTiers.CommonIdx + 2,
        name  = "Rare",
        color = {r=0.2, g=0.4, b=1.0},  -- Blue
    },
    Epic = {
        t0    = 3,
        index = ZItemTiers.CommonIdx + 3,
        name  = "Epic",
        color = {r=0.8, g=0.2, b=1.0},  -- Purple
    },
    Legendary = {
        t0    = 4,
        index = ZItemTiers.CommonIdx + 4,
        name  = "Legendary",
        color = {r=1.0, g=0.8, b=0.0},  -- Gold/Yellow
    },
}

ZItemTiers.T0_COMMON    = 0
ZItemTiers.T0_UNCOMMON  = 1
ZItemTiers.T0_RARE      = 2
ZItemTiers.T0_EPIC      = 3
ZItemTiers.T0_LEGENDARY = 4

ZItemTiers.MIN_T0 = 0
ZItemTiers.MAX_T0 = 4

local T0_NAMES = {
    [0] = "Common",
    [1] = "Uncommon",
    [2] = "Rare",
    [3] = "Epic",
    [4] = "Legendary",
}

ZItemTiers.Legendary_Happiness = 1 -- each Legendary tier item reduces unhappiness by this amount

function ZItemTiers.GetTierColor(t0)
    local tierName = T0_NAMES[t0]
    local tierData = ZItemTiers.Tiers[tierName]
    return tierData and tierData.color or {r=1.0, g=1.0, b=1.0} -- default to white
end

function ZItemTiers.GetT0FromTierName(tierName)
    return ZItemTiers.Tiers[tierName].t0
end

function ZItemTiers.GetOrCreateZIT(item)
    if not item or not item.getModData then return nil end
    
    local modData = item:getModData()
    if not modData then return nil end

    if type(modData.ZIT) ~= "table" then
        modData.ZIT = {}
    end

    local zit = modData.ZIT

    -- migrate old itemTier
    if modData.itemTier and not zit.itemTier then
        zit.itemTier = modData.itemTier
        if modData.craftedFromTier then
            zit.craftedFromTier = modData.craftedFromTier
        end
    end

    return zit
end

function ZItemTiers.GetZIT(item)
    if not item or not item.getModData then return nil end
    
    local modData = item:getModData()
    if not modData then return nil end

    if type(modData.ZIT) ~= "table" then return nil end

    return modData.ZIT
end

-- Roll a random tier based on tier probabilities, return tier 0-based index
function ZItemTiers.RollT0()
    local probs = ZItemTiers.TierProbabilities or ZItemTiers.BuildTierProbabilities()
    local roll = ZombRandFloat(0.0, 1.0)
    local cumulative = 0
    
    for t0 = 0, #probs-1 do
        cumulative = cumulative + probs[t0+1]
        if roll <= cumulative then
            return t0
        end
    end
end

-- Roll a random tier based on tier probabilities, return tier name
function ZItemTiers.RollTier()
    return T0_NAMES[ZItemTiers.RollT0()]
end

-- Check if an item is blacklisted and should never receive tier
-- Returns true if the item should be excluded from tier assignment
function ZItemTiers.IsItemBlacklisted(item)
    if not item then return true end
    
    for getterName, values in pairs(ZItemTiers.NoTierItems) do
        local getter = item[getterName]
        if getter then
            local value = getter(item)
            if value and values[value] then return true end
        end
    end

    return false
end

-- Get the base (unmodified) run speed modifier for a Clothing item
-- Tries: script item getter -> script item field -> stored modData -> instance method
-- Returns 1.0 (neutral) if item has no run speed modifier
function ZItemTiers.GetBaseRunSpeedModifier(item, modData)
    -- Trust stored base only if from current session (prevents using stale 1.0 from old buggy code)
    if modData and modData.itemRunSpeedModifierBase and modData._bonusesApplied == ZItemTiers.sid then
        return modData.itemRunSpeedModifierBase
    end

    local base = 1.0

    -- Primary: script item getter (authoritative, always returns the vanilla base)
    if item.getScriptItem then
        local scriptItem = item:getScriptItem()
        if scriptItem then
            if scriptItem.getRunSpeedModifier then
                base = scriptItem:getRunSpeedModifier()
            elseif scriptItem.runSpeedModifier then
                base = scriptItem.runSpeedModifier
            end
        end
    end

    -- Fallback: instance method (correct on first application before any modifications)
    if math.abs(base - 1.0) <= 0.001 and item.getRunSpeedModifier then
        base = item:getRunSpeedModifier()
    end

    -- Cache in modData for future calls
    if modData then
        modData.itemRunSpeedModifierBase = base
    end

    return base
end

-- returns smth like:
-- {
--    "carbohydrates" => 72,
--           "lipids" => 45,
--         "proteins" => 4.5,
--    "unhappychange" => -5,
--           "weight" => 0.2,
--         "calories" => 720,
--     "hungerchange" => -15
--}
function ZItemTiers.ParseItemScript(scriptItem)
    local all_fields = zdk.parse_item_script(scriptItem)
    local numeric_only = {}
    for k, v in pairs(all_fields) do
        v = tonumber(v)
        if v then
            numeric_only[k] = v
        end
    end
    return numeric_only
end

local _negativeClassCache = {}

ZItemTiers.negativeClassCache = _negativeClassCache -- for debug

function ZItemTiers.ApplyBonuses(item, forceTier)
    if ZItemTiers.IsItemBlacklisted(item) then
        local zit = ZItemTiers.GetZIT(item)
        if zit and zit.itemTier then
            -- logger:debug("Removing tier from blacklisted item %s", item)
            zit.itemTier = nil
            zit.bonuses = nil
        end
        return
    end

    if forceTier then
        ZItemTiers.SetItemTier(item, forceTier)
    end
    local t0 = ZItemTiers.GetItemTierIndex0(item)
    if t0 == 0 then return end -- No bonuses for Common tier

    -- logger:debug("Applying tier %d (%s) to %s", t0, ZItemTiers.GetTierNameFromT0(t0), item)
    if t0 <= 0 then
        logger:error("Invalid tier index %d for item %s, skipping bonuses", t0, item)
        return
    end

    local zit = ZItemTiers.GetOrCreateZIT(item)
    local curTime = getGameTime():getCalender():getTimeInMillis()
    if zit.sid == ZItemTiers.sid and zit.ts and curTime - zit.ts < 600000 then
        -- logger:debug("Bonuses already applied recently for %s, skipping", item)
        return
    end

    zit.ts      = curTime
    zit.sid     = ZItemTiers.sid
    zit.bonuses = zit.bonuses or {}

    local scriptItem    = item:getScriptItem()
    local itemScriptTbl = ZItemTiers.ParseItemScript(scriptItem)
    local itemClass     = getClassSimpleName(item)

    _negativeClassCache[itemClass] = _negativeClassCache[itemClass] or {}
    local nClsCache = _negativeClassCache[itemClass]

    local function apply_bonuses(item, bonuses)
        if not bonuses then return end

        for key, bonus in pairs(bonuses) do
            if not nClsCache[key] then
                local target  = nil
                local base    = nil
                local applied = false

                if bonus.component then -- e.g. FluidContainer
                    target = item:getComponent(bonus.component)
                    if target then
                        local compScript = scriptItem:getComponentScriptFor(bonus.component)
                        base = compScript[bonus.getter] and compScript[bonus.getter](compScript)
                    end
                else
                    target = item
                    base   = itemScriptTbl[key:lower()] or (scriptItem[bonus.getter] and scriptItem[bonus.getter](scriptItem))
                end

                if bonus.applyIfNull or (base and (base ~= 0 or bonus.applyIfZero)) then
                    if target and target[bonus.setter] then
                        base = base or 0 -- when applyIfNull is true, treat nil as 0 for bonus calculation
                        local modified = bonus:func(base, t0, item)
                        if modified and modified ~= base then
                            target[bonus.setter](target, modified)
                            if bonus.afterSet then
                                bonus:afterSet(item, base, modified)
                            end
                            zit.bonuses[key] = {
                                base     = base,
                                modified = modified,
                            }
                            applied = true
                        end
                    else
                        logger:debug("%s: no %s() for %s", item, bonus.setter, itemClass)
                        nClsCache[key] = true -- cache that this class doesn't have this bonus to avoid future warnings
                    end
                end

                if not applied and zit.bonuses[key] then
                    zit.bonuses[key] = nil
                end
            end
        end
    end

    for className, bonuses in pairs(ZItemTiers.ClassBonuses) do
        if instanceof(item, className) then
            apply_bonuses(item, bonuses)
        end
    end

    return true
end

-- Get the 1-based index of the tier for an item, 1 = Common, 2 = Uncommon, ...
-- guaranteed to return a number between 1 and 5
-- (used by ZGlassCutter and ZSpaceship))
---@param item InventoryItem
---@return number
function ZItemTiers.GetItemTierIndex(item)
    if not item then return ZItemTiers.CommonIdx end
    

    local zit = ZItemTiers.GetOrCreateZIT(item)
    if not zit.itemTier then
        return ZItemTiers.CommonIdx
    end

    local tier = ZItemTiers.Tiers[zit.itemTier]
    if not tier then return ZItemTiers.CommonIdx end

    return tier.index
end

-- Get the 0-based index of the tier for an item, 0 = Common, 1 = Uncommon, ...
function ZItemTiers.GetItemTierIndex0(item)
    local idx1 = ZItemTiers.GetItemTierIndex(item)
    return idx1 - 1
end

function ZItemTiers.GetItemT0(item)
    return ZItemTiers.GetItemTierIndex0(item)
end

function ZItemTiers.SetItemTier(item, tierName)
    local zit = ZItemTiers.GetOrCreateZIT(item)
    zit.itemTier = tierName
end

-- Get tier key for an item (returns "Common" if no tier assigned or item is nil)
---@param item InventoryItem
---@return string
function ZItemTiers.GetItemTierKey(item)
    if not item then return nil end
    
    local zit = ZItemTiers.GetZIT(item)
    return (zit and zit.itemTier) or "Common"
end

local function toList(src)
    if type(src) ~= "table" and src.toArray then
        src = src:toArray()
    end
    if type(src) ~= "table" then
        logger:error("Invalid src parameter: expected ArrayList or table, got %s", type(src))
        return {}
    end
    return src
end

-- Calculate output tier based on ingredient tiers (Factorio-style)
-- Returns the calculated tier name
-- Parameters:
--   src:               ArrayList/table of ingredient items
--   perk:   [optional] relevant Perk for skill level calculation (overrides recipe's)
--   player: [optional] IsoGameCharacter performing the craft
--   recipe: [optional] CraftRecipe being performed
--   tools:  [optional] table of tools used (e.g. for sewing machine)
-- Rules:
-- 1. If all ingredients are Epic, output is at least Epic
-- 2. If ingredients have different tiers, output tier is based on their ratio/probability
-- 3. Output is always at least the minimum (highest tier) tier among ingredients
-- 4. Skill level affects the result:
--    - Level 0: 50% chance to be 1 tier lower
--    - Level 1: Keep calculated tier (no change)
--    - Level > 1: Small chance (5% per level above 1) to be 1 tier higher
function ZItemTiers.CalculateCraftingT0(tbl)
    local logger = logger:withPrefix("CalculateCraftingT0() ")
    local result = ZItemTiers.RollT0()

    local perk   = tbl.perk
    local player = tbl.player
    local recipe = tbl.recipe
    local src    = toList(tbl.src)
    local tools  = toList(tbl.tools)

    logger:debug("tools = %s", tools)

    if table.isempty(src) then
        logger:debug("No ingredients, use normal spawn probability")
        return result
    end

    -- Get crafting skill level
    local skillLevel = nil
    if player then
        skillLevel = (perk and player:getPerkLevel(perk)) or (recipe and recipe:getHighestRelevantSkillLevel(player))
    end
    logger:debug("detected skill level: %s", skillLevel)

    skillLevel = skillLevel or 1
    
    -- Collect tiers from all ingredients
    local tierCounts = {}
    local totalIngredients = 0
    
    for _, ingredient in ipairs(src) do
        if ingredient then
            local t0 = ZItemTiers.GetItemT0(ingredient)
            tierCounts[t0] = (tierCounts[t0] or 0) + 1
            totalIngredients = totalIngredients + 1
        end
    end
    logger:debug("tierCounts = %s, totalIngredients = %d", tierCounts, totalIngredients)
    
    if totalIngredients == 0 then
        return result
    end
    
    -- Calculate weighted average of ingredient tiers based on count
    local weightedSum = 0
    for t0, count in pairs(tierCounts) do
        weightedSum = weightedSum + (t0+1) * count
    end
    local avgT1 = weightedSum / totalIngredients
    logger:debug("avgT1 = %d / %d = %.2f", weightedSum, totalIngredients, avgT1)
    
    local resT1 = math.floor(avgT1)
    if resT1 > 1 then
        result = result + resT1 - 1
        logger:debug("resT1 %d => result %d", resT1, result)
    end
    
    -- Apply skill level modifiers
    if skillLevel == 0 then
        -- Skill level 0: 50% chance to be 1 tier lower
        local roll = ZombRandFloat(0.0, 1.0)
        if roll < 0.5 then
            -- Reduce by 1 tier
            local oldResult = result
            result = result - 1
            logger:debug("skill level 0 reduced tier from %d to %d (roll=%.2f)", oldResult, result, roll)
        else
            logger:debug("skill level 0 kept tier at %d (roll=%.2f)", result, roll)
        end
    elseif skillLevel > 1 then
        -- Skill level > 1: Small chance to be 1 tier higher
        -- Chance = 5% per level above 1 (so level 2 = 5%, level 3 = 10%, etc.)
        local upgradeChance = (skillLevel - 1) * 0.05
        local roll = ZombRandFloat(0.0, 1.0)
        
        if roll < upgradeChance then
            -- Upgrade by 1 tier
            local oldResult = result
            result = result + 1
            logger:debug("skill level %d upgraded tier from %d to %d (roll=%.2f, chance=%.3f)", skillLevel, oldResult, result, roll, upgradeChance)
        end
    else
        -- Skill level 1: No change
        logger:debug("skill level 1 kept tier at %d (no change)", result)
    end

    -- apply tool level, if any
    local maxToolLevel = 0
    if tools then
        for _, tool in ipairs(tools) do
            local t0 = ZItemTiers.GetItemTierIndex0(tool)
            logger:debug("tool=%s, level=%d", tool, t0)
            if t0 > maxToolLevel then
                maxToolLevel = t0
            end
        end
    end
    if maxToolLevel > 0 then
        local upgradeChance = maxToolLevel * 0.05
        local roll = ZombRandFloat(0.0, 1.0)

        if roll < upgradeChance then
            -- Upgrade by 1 tier
            local oldResult = result
            result = result + 1
            logger:debug("tool level %d upgraded tier from %d to %d (roll=%.2f, chance=%.3f)", skillLevel, oldResult, result, roll, upgradeChance)
        end
    end
    
    return zdk.clamp(result, ZItemTiers.MIN_T0, ZItemTiers.MAX_T0)
end

function ZItemTiers.CalculateCraftingTier(...)
    return T0_NAMES[ZItemTiers.CalculateCraftingT0(...)]
end

-- capture instanceItem() calls while calling origFun() and apply crafting tier bonuses to crafted items based on src ingredients
-- see CalculateCraftingT0() for tbl parameters description
function ZItemTiers.AutoTierCraftedItems(tbl, origFun, ...)
    return zdk.scoped_hook({
        _G = {
            instanceItem = function(orig, ...)
                local item = orig(...)
                local tier = ZItemTiers.CalculateCraftingTier(tbl)
                logger:debug("AutoTierCraftedItems: assigned tier %s to %s", tier, item)

                if tier then
                    ZItemTiers.ApplyBonuses(item, tier)
                end
                return item
            end
        }
    }, origFun, ...)
end
