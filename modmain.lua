GLOBAL.CHEATS_ENABLED = true
GLOBAL.require("debugkeys")

local _G = GLOBAL

local DeBuG = GetModConfigData("debug")
local range = GetModConfigData("range")
local inv_first = GetModConfigData("is_inv_first")
local c = {r = 0, g = 0.3, b = 0}

local Builder = _G.require "components/builder"
local Builder_replica = _G.require "components/builder_replica"
local Highlight = _G.require "components/highlight"
local IngredientUI = _G.require "widgets/ingredientui"
local RecipePopup = _G.require "widgets/recipepopup"
local TabGroup = _G.require "widgets/tabgroup"
local CraftSlot = _G.require "widgets/craftslot"

local highlit = {}
 -- tracking what is highlighted
local consumedChests = {}
local nearbyChests = {}
local validChests = {}

local TEASER_SCALE_TEXT = 1
local TEASER_SCALE_BTN = 1.5
local CONTROL_ACCEPT = _G.CONTROL_ACCEPT

local function isTable(t)
    return type(t) == "table"
end

local function debugPrint(...)
    local arg = {...}
    if DeBuG then
        for k, v in pairs(arg) do
            print(v)
        end
    end
end

local function unhighlight(highlit)
    while #highlit > 0 do
        local v = table.remove(highlit)
        if v and v.components.highlight then
            v.components.highlight:UnHighlight()
        end
    end
end

local function highlight(insts, highlit)
    for k, v in pairs(insts) do
        if not v.components.highlight then
            v:AddComponent("highlight")
        end
        if v.components.highlight then
            v.components.highlight:Highlight(c.r, c.g, c.b)
            table.insert(highlit, v)
        end
    end
end

-- given the list of instances, return the list of instances of chest
local function filterChest(inst)
    local chest = {}
    for k, v in pairs(inst) do
        if (v and v.components.container and v.components.container.type) then
            -- as cooker and backpack are considered as containers as well
            -- regex to match ['chest', 'chester']
            if string.find(v.components.container.type, "chest") ~= nil then
                table.insert(chest, v)
            end
        end
    end
    return chest
end

-- given the player, return the chests close to the player
local function getNearbyChest(player, dist)
    if dist == nil then
        dist = range
    end
    if not player then
        return {}
    end
    local x, y, z = player.Transform:GetWorldPosition()
    local inst = _G.TheSim:FindEntities(x, y, z, dist, {}, {"NOBLOCK", "player", "FX"}) or {}
    return filterChest(inst)
end

-- return: contains (T/F) total (num) qualifyChests (list of chest contains the item)
local function findFromChests(chests, item)
    if not (chests and item) then
        return false, 0, {}
    end
    local qualifyChests = {}
    local total = 0
    local contains = false

    for k, v in pairs(chests) do
        local found, n = v.components.container:Has(item, 1)
        if found then
            contains = true
            total = total + n
            table.insert(qualifyChests, v)
        end
    end
    return contains, total, qualifyChests
end

local function findFromNearbyChests(player, item)
    if not (player and item) then
        return false, 0, {}
    end
    local chests = getNearbyChest(player)
    return findFromChests(chests, item)
end

-- return: whether it is enough to fullfill the amt requirement, and the amt not fulfilled.
local function removeFromNearbyChests(player, item, amt)
    if not (player and item and amt ~= nil) then
        debugPrint("removeFromNearbyChests: player | item | amt missing!")
        return false, amt
    end
    debugPrint("removeFromNearbyChests", player, item, amt)

    consumedChests = {}
     -- clear consumed chests
    local chests = getNearbyChest(player, range + 3)
     -- extend the range a little bit, avoid error caused by slight player movement
    local numItemsFound = 0
    for k, v in pairs(chests) do
        local container = v.components.container
        found, num_found = container:Has(item, 1)
        if found then
            numItemsFound = numItemsFound + num_found
            table.insert(consumedChests, v)
            if (amt > num_found) then -- not enough
                container:ConsumeByName(item, num_found)
                amt = amt - num_found
            else
                container:ConsumeByName(item, amt)
                amt = 0
                break
            end
        end
    end
    debugPrint("Found " .. numItemsFound .. " " .. item .. " from " .. #consumedChests .. " chests")
    if amt == 0 then
        return true, 0
    else
        return false, amt
    end
end

local function playerConsumeByName(player, item, amt)
    if not (player and item and amt) then
        return false
    end
    local inventory = player.components.inventory
    if inv_first then
        found_inv, num_in_inv = inventory:Has(item, 1)
        if amt <= num_in_inv then
            -- there are more resources available in inv then needed
            inventory:ConsumeByName(item, amt)
            return true
        end
        inventory:ConsumeByName(item, num_in_inv)
        amt = amt - num_in_inv
        debugPrint("Found " .. num_in_inv .. " in inventory, take " .. amt .. "from chests")
        removeFromNearbyChests(player, item, amt)
        return true
    else
        done, remain = removeFromNearbyChests(player, item, amt)
        if not done then
            inventory:ConsumeByName(item, remain)
        end
        return true
    end
end

local function playerGetByName(player, item, amt)
    debugPrint("playerGetByName " .. item)
    if not (player and item and amt and amt ~= 0) then
        debugPrint("playerGetByName: player | item | amt missing!")
        return {}
    end

    local items = {}

    local function addToItems(another_item)
        for k, v in pairs(another_item) do
            if items[k] == nil then
                items[k] = v
            else
                items[k] = items[k] + v
            end
        end
    end

    local function tryGetFromContainer(volume)
        found, num = volume:Has(item, 1)
        if found then
            if num >= amt then -- there is more than necessary
                addToItems(volume:GetItemByName(item, amt))
                amt = 0
                return true
            else -- it's not enough
                addToItems(volume:GetItemByName(item, num))
                amt = amt - num
                return false
            end
        end
        return false
    end

    local inventory = player.components.inventory
    local chests = getNearbyChest(player)

    if inv_first then -- get ingredients from inventory first
        if tryGetFromContainer(inventory) then
            return items
        end
        for k, v in pairs(chests) do
            local container = v.components.container
            if tryGetFromContainer(container) then
                return items
            end
        end
    else -- get ingredients from chests first
        for k, v in pairs(chests) do
            local container = v.components.container
            if tryGetFromContainer(container) then
                return items
            end
        end
        tryGetFromContainer(inventory)
        return items
    end
    return items
end

-- detect if the number of chests around the player changes.
-- If true, push event stacksizechange
-- TODO: find a better event to push than "stacksizechange"
local _oldCmpChestsNum = 0
local _newCmpChestsNum = 0
local function compareValidChests(player)
    _newCmpChestsNum = table.getn(getNearbyChest(player))
    if (_oldCmpChestsNum ~= _newCmpChestsNum) then
        _oldCmpChestsNum = _newCmpChestsNum
        debugPrint("Chest number changed!")
        player:PushEvent("stacksizechange")
    end
end

-- override original function
-- Support DS, RoG. SW not tested
-- to unhighlight chest when tabgroup are deselected
-- function TabGroup:DeselectAll(...)
--     for k, v in ipairs(self.tabs) do v:Deselect() end
--     unhighlight(highlit)
-- end

----------------------------------------------------------
---------------Override Builder functions (DS, RoG)-------
-- to test if canbuild with the material from chest
-- function Builder:CanBuild(recname)
--     if self.freebuildmode then return true end

--     local player = self.inst
--     local chests = getNearbyChest(player)
--     local recipe = _G.GetRecipe(recname)
--     if recipe then
--         for ik, iv in pairs(recipe.ingredients) do
--             local amt = math.max(1, _G.RoundUp(iv.amount * self.ingredientmod))
--             found, num_found = findFromChests(chests, iv.type)
--             has, num_hold = player.components.inventory:Has(iv.type, amt)
--             if (amt > num_found + num_hold) then
--                 return false
--             end
--         end
--         return true
--     end
--     return false
-- end
-- Builder_replica.Canbuild = function (recipename)
--     if self.inst.components.builder ~= nil then
--         print("calling inst.components.builder:canbuild")
--         return self.inst.components.builder:CanBuild(recipename)
--     elseif self.classified ~= nil then
--         print("calling this is classified:canbuild")
--         local recipe = _G.GetValidRecipe(recipename)
--         if recipe == nil then
--             return false
--         elseif not self.classified.isfreebuildmode:value() then
--             for i, v in ipairs(recipe.ingredients) do
--                 if not self.inst.replica.inventory:Has(v.type, math.max(1, _G.RoundBiasedUp(v.amount * self:IngredientMod()))) then
--                     return false
--                 end
--             end
--         end
--         for i, v in ipairs(recipe.character_ingredients) do
--             if not self:HasCharacterIngredient(v) then
--                 return false
--             end
--         end
--         for i, v in ipairs(recipe.tech_ingredients) do
--             if not self:HasTechIngredient(v) then
--                 return false
--             end
--         end
--         return true
--     else
--         return false
--     end
-- end

-- to keep updating the number of chests as the player move around
function Builder:OnUpdate(dt)
    compareValidChests(self.inst)
    self:EvaluateTechTrees()
    if self.EvaluateAutoFixers ~= nil then
        self:EvaluateAutoFixers()
    end
end

-- This function is for RoG, base game doesn't have this function'
-- function Builder:GetIngredients(recname)
--     debugPrint('Custom Builder:GetIngredients: ' .. recname)
--     local recipe = _G.GetRecipe(recname)
--     if recipe then
--         local ingredients = {}
--         for k, v in pairs(recipe.ingredients) do
--             local amt = math.max(1, _G.RoundUp(v.amount * self.ingredientmod))
--             -- local items = self.inst.components.inventory:GetItemByName(v.type, amt)
--             local items = playerGetByName(self.inst, v.type, amt)
--             ingredients[v.type] = items
--         end
--         return ingredients
--     end
-- end

-- to take ingredients from both inv and chests
-- function Builder:RemoveIngredients(recname_or_ingre)
--     if not isTable(recname_or_ingre) then -- param is a recname, which is base game
--         local recipe = _G.GetRecipe(recname_or_ingre)
--         self.inst:PushEvent("consumeingredients", {recipe = recipe})
--         if recipe then
--             for k, v in pairs(recipe.ingredients) do
--                 local amt = math.max(1, _G.RoundUp(v.amount * self.ingredientmod))
--                 playerConsumeByName(self.inst, v.type, amt)
--             end
--         end
--     else
--         -- this is RoG version of removeIngredients
--         -- RoG uses another function: getingredients to load all ingredients, so this part
--         -- does not require a lot modification
--         debugPrint('RoG Ver Builder:RemoveIngredients')
--         for item, ents in pairs(recname_or_ingre) do
--             for k, v in pairs(ents) do
--                 for i = 1, v do
--                     -- TODO: change this line
--                     -- Now it can successfully deduct the number of items, but if the item is in
--                     -- the chest, it will not pushevent: "loseitem". Although I didn't see a major
--                     -- effect on that, but better to add it back
--                     self.inst.components.inventory:RemoveItem(k, false):Remove()
--                 end
--             end
--         end
--         self.inst:PushEvent("consumeingredients")
--     end
-- end
----------------------------------------------------------
---------------End Override Builder functions-------------
-- function RecipePopup:Refresh()
--     -- unhighlight(highlit)
--     local recipe = self.recipe
--     local owner = self.owner

--     if not owner then return false end

--     local knows = owner.components.builder:KnowsRecipe(recipe.name)
--     local buffered = owner.components.builder:IsBuildBuffered(recipe.name)
--     local can_build = owner.components.builder:CanBuild(recipe.name) or buffered
--     local tech_level = owner.components.builder.accessible_tech_trees
--     local should_hint = not knows and _G.ShouldHintRecipe(recipe.level, tech_level) and not _G.CanPrototypeRecipe(recipe.level, tech_level)
--     local equippedBody = owner.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.BODY)
--     local showamulet = equippedBody and equippedBody.prefab == "greenamulet"
--     local controller_id = _G.TheInput:GetControllerID()

--     if should_hint then
--         self.recipecost:Hide()
--         self.button:Hide()
--         local hint_text = {
--             ["SCIENCEMACHINE"] = _G.STRINGS.UI.CRAFTING.NEEDSCIENCEMACHINE,
--             ["ALCHEMYMACHINE"] = _G.STRINGS.UI.CRAFTING.NEEDALCHEMYENGINE,
--             ["SHADOWMANIPULATOR"] = _G.STRINGS.UI.CRAFTING.NEEDSHADOWMANIPULATOR,
--             ["PRESTIHATITATOR"] = _G.STRINGS.UI.CRAFTING.NEEDPRESTIHATITATOR,
--             ["CANTRESEARCH"] = _G.STRINGS.UI.CRAFTING.CANTRESEARCH,
--             ["ANCIENTALTAR_HIGH"] = _G.STRINGS.UI.CRAFTING.NEEDSANCIENT_FOUR,
--             ["SEALAB"] = _G.STRINGS.UI.CRAFTING.NEEDALCHEMYENGINE,
--         }

--         if _G.SaveGameIndex:IsModeShipwrecked() then
--             hint_text["PRESTIHATITATOR"] = _G.STRINGS.UI.CRAFTING.NEEDPIRATIHATITATOR
--         end

--         local str = hint_text[_G.GetHintTextForRecipe(recipe)] or "Text not found."
--         self.teaser:SetScale(TEASER_SCALE_TEXT)
--         self.teaser:SetString(str)
--         self.teaser:Show()
--         showamulet = false
--     elseif knows then
--         self.teaser:Hide()
--         self.recipecost:Hide()

--         if _G.TheInput:ControllerAttached() then
--             self.button:Hide()
--             self.teaser:Show()

--             if can_build then
--                 self.teaser:SetScale(TEASER_SCALE_BTN)
--                 self.teaser:SetString(_G.TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. (buffered and _G.STRINGS.UI.CRAFTING.PLACE or _G.STRINGS.UI.CRAFTING.BUILD))
--             else
--                 self.teaser:SetScale(TEASER_SCALE_TEXT)
--                 self.teaser:SetString(_G.STRINGS.UI.CRAFTING.NEEDSTUFF)
--             end
--         else
--             self.button:Show()
--             self.button:SetPosition(320, -105, 0)
--             self.button:SetScale(1, 1, 1)

--             self.button:SetText(buffered and _G.STRINGS.UI.CRAFTING.PLACE or _G.STRINGS.UI.CRAFTING.BUILD)
--             if can_build
--             then self.button:Enable()
--             else self.button:Disable() end
--         end
--     else
--         self.teaser:Hide()
--         self.recipecost:Hide()

--         if _G.TheInput:ControllerAttached() then
--             self.button:Hide()
--             self.teaser:Show()
--             self.teaser:SetColour(1, 1, 1, 1)
--             if can_build then
--                 self.teaser:SetScale(TEASER_SCALE_BTN)
--                 self.teaser:SetString(_G.TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. _G.STRINGS.UI.CRAFTING.PROTOTYPE)
--             else
--                 self.teaser:SetScale(TEASER_SCALE_TEXT)
--                 self.teaser:SetString(_G.STRINGS.UI.CRAFTING.NEEDSTUFF)
--             end
--         else
--             self.button.image_normal = "button.tex"
--             self.button.image:SetTexture(_G.UI_ATLAS, self.button.image_normal)

--             self.button:Show()
--             self.button:SetPosition(320, -105, 0)
--             self.button:SetScale(1, 1, 1)

--             self.button:SetText(_G.STRINGS.UI.CRAFTING.PROTOTYPE)
--             if can_build
--             then self.button:Enable()
--             else self.button:Disable() end
--         end
--     end

--     if not showamulet then self.amulet:Hide()
--     else self.amulet:Show() end

--     self.name:SetString(_G.STRINGS.NAMES[string.upper(self.recipe.name)])
--     self.desc:SetString(_G.STRINGS.RECIPE_DESC[string.upper(self.recipe.name)])

--     for k, v in pairs(self.ing) do
--         v:Kill()
--     end
--     self.ing = {}

--     local center = 330
--     local num = 0
--     for k, v in pairs(recipe.ingredients) do num = num + 1 end
--     local w = 64
--     local div = 10

--     local offset = center
--     if num > 1 then
--         offset = offset - (w / 2 + div) * (num - 1)
--     end

--     local total, need, has_chest, num_found_chest, has_inv, num_found_inv
--     validChests = {}

--     for k, v in pairs(recipe.ingredients) do
--         -- calculations
--         local validChestsOfIngredient = {}
--         need = _G.RoundUp(v.amount * owner.components.builder.ingredientmod)
--         has_inv, num_found_inv = owner.components.inventory:Has(v.type, need)
--         has_chest, num_found_chest, validChestsOfIngredient = findFromNearbyChests(owner, v.type)

--         total = num_found_chest + num_found_inv

--         -- merge tables
--         for k1, v1 in pairs(validChestsOfIngredient) do table.insert(validChests, v1) end

--         local item_img = v.type
--         if _G.SaveGameIndex:IsModeShipwrecked() and _G.SW_ICONS[item_img] ~= nil then
--             item_img = _G.SW_ICONS[item_img]
--         end

--         local ingredientUI = IngredientUI(v.atlas, item_img .. ".tex", need, total, total >= need, _G.STRINGS.NAMES[string.upper(v.type)], owner)
--         -- ingredientUI.quant:SetString(string.format("Inv:%d/%d\nAll:%d/%d", num_found_inv, need, total, need))
--         ingredientUI.quant:SetString(string.format("All:%d/%d\n(Inv:%d)", total, need, num_found_inv))
--         local ing = self.contents:AddChild(ingredientUI)
--         ing:SetPosition(_G.Vector3(offset, 80, 0))
--         offset = offset + (w + div)
--         self.ing[k] = ing
--     end

--     highlight(validChests, highlit)
-- end

-- function CraftSlot:OnLoseFocus()
--     CraftSlot._base.OnLoseFocus(self)
--     unhighlight(highlit)
--     self:Close()
-- end
