local _G = GLOBAL

local DeBuG = GetModConfigData("debug")
local range = GetModConfigData("range")
local inv_first = GetModConfigData("is_inv_first")
local c = {r = 0, g = 0.3, b = 0}

local Builder = _G.require "components/builder"
local Builder_replica = _G.require "components/builder_replica"
local IngredientUI = _G.require "widgets/ingredientui"
local RecipePopup = _G.require "widgets/recipepopup"
local TabGroup = _G.require "widgets/tabgroup"
local CraftSlot = _G.require "widgets/craftslot"

-- tracking what is highlighted
local highlit = {}

local consumedChests = {}
local validChests = {}

local TEASER_SCALE_TEXT = 1
local TEASER_SCALE_BTN = 1.5
local TEASER_TEXT_WIDTH = 64 * 3 + 24
local TEASER_BTN_WIDTH = TEASER_TEXT_WIDTH / TEASER_SCALE_BTN
local TEXT_WIDTH = 64 * 3 + 30
local CONTROL_ACCEPT = _G.CONTROL_ACCEPT

if DeBuG then
    _G.CHEATS_ENABLED = true
    _G.require("debugkeys")
end

local function debugPrint(...)
    local arg = {...}
    if DeBuG then
        for _, v in ipairs(arg) do
            print(v)
        end
    end
end

local function unhighlight()
    while #highlit > 0 do
        local v = table.remove(highlit)
        if v and v.components.highlight then
            v.components.highlight:UnHighlight()
        end
    end
end

local function highlight(insts)
    for _, v in ipairs(insts) do
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
    for _, v in ipairs(inst) do
        if (v and v.components.container and v.components.container.type) then
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

    for _, v in ipairs(chests) do
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
    for _, v in ipairs(chests) do
        local container = v.components.container
        local found, num_found = container:Has(item, 1)
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
        local _, num_in_inv = inventory:Has(item, 1)
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
        local done, remain = removeFromNearbyChests(player, item, amt)
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
        local found, num = volume:Has(item, 1)
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
        for _, v in ipairs(chests) do
            local container = v.components.container
            if tryGetFromContainer(container) then
                return items
            end
        end
    else -- get ingredients from chests first
        for _, v in ipairs(chests) do
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
function TabGroup:DeselectAll()
    for _, v in ipairs(self.tabs) do
        v:Deselect()
    end
    self.selected = nil
    unhighlight()
end
----------------------------------------------------------
---------------Override Builder functions (DS, RoG)-------
-- to test if canbuild with the material from chest
-- TODO: this fucking thing is broken
function Builder_replica:Canbuild(recipename)
    debugPrint("calling Builder_replica:Canbuild")
    if self.inst.components.builder ~= nil then
        debugPrint("calling inst.components.builder:canbuild")
        return self.inst.components.builder:CanBuild(recipename)
    elseif self.classified ~= nil then
        debugPrint("calling this is classified:canbuild")
        local recipe = _G.GetValidRecipe(recipename)
        if recipe == nil then
            return false
        elseif not self.classified.isfreebuildmode:value() then
            for _, v in ipairs(recipe.ingredients) do
                if
                    not self.inst.replica.inventory:Has(
                        v.type,
                        math.max(1, _G.RoundBiasedUp(v.amount * self:IngredientMod()))
                    )
                 then
                    return false
                end
            end
        end
        for _, v in ipairs(recipe.character_ingredients) do
            if not self:HasCharacterIngredient(v) then
                return false
            end
        end
        for _, v in ipairs(recipe.tech_ingredients) do
            if not self:HasTechIngredient(v) then
                return false
            end
        end
        return true
    else
        return false
    end
end

function Builder:CanBuild(recname)
    debugPrint("calling Builder:CanBuild")
    local recipe = _G.GetValidRecipe(recname)
    if recipe == nil then
        return false
    elseif not self.freebuildmode then
        local player = self.inst
        local chests = getNearbyChest(player)
        for _, v in ipairs(recipe.ingredients) do
            local amt = math.max(1, _G.RoundBiasedUp(v.amount * self.ingredientmod))
            local _, num_found = findFromChests(chests, v.type)
            local _, num_hold = player.components.inventory:Has(v.type, 1)
            if (amt > num_found + num_hold) then
                return false
            end
        end
    end
    for _, v in ipairs(recipe.character_ingredients) do
        if not self:HasCharacterIngredient(v) then
            return false
        end
    end
    for _, v in ipairs(recipe.tech_ingredients) do
        if not self:HasTechIngredient(v) then
            return false
        end
    end
    return true
end

-- to keep updating the number of chests as the player move around
function Builder:OnUpdate()
    compareValidChests(self.inst)
    self:EvaluateTechTrees()
    if self.EvaluateAutoFixers ~= nil then
        self:EvaluateAutoFixers()
    end
end

function Builder:GetIngredients(recname)
    debugPrint("calling GetIngredients(" .. recname .. ")")
    local recipe = _G.AllRecipes[recname]
    if recipe then
        local ingredients = {}
        for _, v in ipairs(recipe.ingredients) do
            local amt = math.max(1, _G.RoundBiasedUp(v.amount * self.ingredientmod))
            -- local items = self.inst.components.inventory:GetItemByName(v.type, amt)
            local items = playerGetByName(self.inst, v.type, amt)
            ingredients[v.type] = items
        end
        return ingredients
    end
end

function Builder:RemoveIngredients(ingredients, recname)
    for _, ents in pairs(ingredients) do
        for k, v in pairs(ents) do
            for _ = 1, v do
                self.inst.components.inventory:RemoveItem(k, false):Remove()
            end
        end
    end

    local recipe = _G.AllRecipes[recname]
    if recipe then
        local CHARACTER_INGREDIENT = _G.CHARACTER_INGREDIENT
        for _, v in ipairs(recipe.character_ingredients) do
            if v.type == CHARACTER_INGREDIENT.HEALTH then
                --Don't die from crafting!
                local delta = math.min(math.max(0, self.inst.components.health.currenthealth - 1), v.amount)
                self.inst:PushEvent("consumehealthcost")
                self.inst.components.health:DoDelta(-delta, false, "builder", true, nil, true)
            elseif v.type == CHARACTER_INGREDIENT.MAX_HEALTH then
                self.inst:PushEvent("consumehealthcost")
                self.inst.components.health:DeltaPenalty(v.amount)
            elseif v.type == CHARACTER_INGREDIENT.SANITY then
                self.inst.components.sanity:DoDelta(-v.amount)
            -- elseif v.type == CHARACTER_INGREDIENT.MAX_SANITY then
            -- --[[
            --         Because we don't have any maxsanity restoring items we want to be more careful
            --         with how we remove max sanity. Because of that, this is not handled here.
            --         Removal of sanity is actually managed by the entity that is created.
            --         See maxwell's pet leash on spawn and pet on death functions for examples.
            --     --]]
            end
        end
    end
    self.inst:PushEvent("consumeingredients")
end
----------------------------------------------------------
---------------End Override Builder functions-------------
local function GetHintTextForRecipe(player, recipe)
    local validmachines = {}
    local adjusted_level = _G.deepcopy(recipe.level)

    for k, v in pairs(_G.TUNING.PROTOTYPER_TREES) do
        -- Adjust level for bonus so that the hint gives the right message
        if player.replica.builder ~= nil then
            if k == "SCIENCEMACHINE" or k == "ALCHEMYMACHINE" then
                adjusted_level.SCIENCE = adjusted_level.SCIENCE - player.replica.builder:ScienceBonus()
            elseif k == "PRESTIHATITATOR" or k == "SHADOWMANIPULATOR" then
                adjusted_level.MAGIC = adjusted_level.MAGIC - player.replica.builder:MagicBonus()
            elseif k == "ANCIENTALTAR_LOW" or k == "ANCIENTALTAR_HIGH" then
                adjusted_level.ANCIENT = adjusted_level.ANCIENT - player.replica.builder:AncientBonus()
            elseif k == "WAXWELLJOURNAL" then
                adjusted_level.SHADOW = adjusted_level.SHADOW - player.replica.builder:ShadowBonus()
            end
        end

        local canbuild = _G.CanPrototypeRecipe(adjusted_level, v)
        if canbuild then
            table.insert(validmachines, {TREE = tostring(k), SCORE = 0})
        --return tostring(k)
        end
    end

    if #validmachines > 0 then
        if #validmachines == 1 then
            --There's only once machine is valid. Return that one.
            return validmachines[1].TREE
        end

        --There's more than one machine that gives the valid tech level!
        --We have to find the "lowest" one (taking bonus into account).
        for _, v in pairs(validmachines) do
            for rk, rv in pairs(adjusted_level) do
                if _G.TUNING.PROTOTYPER_TREES[v.TREE][rk] == rv then
                    v.SCORE = v.SCORE + 1
                    if player.replica.builder ~= nil then
                        if v.TREE == "SCIENCEMACHINE" or v.TREE == "ALCHEMYMACHINE" then
                            v.SCORE = v.SCORE + player.replica.builder:ScienceBonus()
                        elseif v.TREE == "PRESTIHATITATOR" or v.TREE == "SHADOWMANIPULATOR" then
                            v.SCORE = v.SCORE + player.replica.builder:MagicBonus()
                        elseif v.TREE == "ANCIENTALTAR_LOW" or v.TREE == "ANCIENTALTAR_HIGH" then
                            v.SCORE = v.SCORE + player.replica.builder:AncientBonus()
                        elseif v.TREE == "WAXWELLJOURNAL" then
                            v.SCORE = v.SCORE + player.replica.builder:ShadowBonus()
                        end
                    end
                end
            end
        end

        -- local bestmachine = nil
        -- for each req in recipe.level do
        --     for m in validmachines do
        --         if req > 0 and m[req] >= req and m[req] < bestmachine[req] then
        --             bestmachine = m
        --         end
        --     end
        -- end

        table.sort(
            validmachines,
            function(a, b)
                return (a.SCORE) > (b.SCORE)
            end
        )

        return validmachines[1].TREE
    end

    return "CANTRESEARCH"
end

function RecipePopup:Refresh()
    debugPrint("calling RecipePopup:Refresh")
    validChests = {}

    local STRINGS = _G.STRINGS
    local recipe = self.recipe
    local owner = self.owner
    if owner == nil then
        return false
    end

    local builder_replica = owner.replica.builder
    local inventory_replica = owner.replica.inventory

    local knows = builder_replica:KnowsRecipe(recipe.name)
    local buffered = builder_replica:IsBuildBuffered(recipe.name)
    local can_build = buffered or builder_replica:CanBuild(recipe.name)
    local tech_level = builder_replica:GetTechTrees()
    local should_hint =
        not knows and _G.ShouldHintRecipe(recipe.level, tech_level) and
        not _G.CanPrototypeRecipe(recipe.level, tech_level)

    self.skins_list = self:GetSkinsList()
    self.skins_options = self:GetSkinOptions() -- In offline mode, this will return the default option and nothing else

    if #self.skins_options == 1 then
        -- No skins available, so use the original version of this popup
        if self.skins_spinner ~= nil then
            self:BuildNoSpinner(self.horizontal)
        end
    else
        --Skins are available, use the spinner version of this popup
        if self.skins_spinner == nil then
            self:BuildWithSpinner(self.horizontal)
        end

        self.skins_spinner.spinner:SetOptions(self.skins_options)
        local last_skin = _G.Profile:GetLastUsedSkinForItem(recipe.name)
        if last_skin then
            self.skins_spinner.spinner:SetSelectedIndex(self:GetIndexForSkin(last_skin) or 1)
        end
    end

    self.name:SetTruncatedString(
        STRINGS.NAMES[string.upper(self.recipe.name)],
        TEXT_WIDTH,
        self.smallfonts and 51 or 41,
        true
    )
    self.desc:SetMultilineTruncatedString(
        STRINGS.RECIPE_DESC[string.upper(self.recipe.name)],
        2,
        TEXT_WIDTH,
        self.smallfonts and 40 or 33,
        true
    )

    for _, v in ipairs(self.ing) do
        v:Kill()
    end

    self.ing = {}

    local num =
        (recipe.ingredients ~= nil and #recipe.ingredients or 0) +
        (recipe.character_ingredients ~= nil and #recipe.character_ingredients or 0) +
        (recipe.tech_ingredients ~= nil and #recipe.tech_ingredients or 0)
    local w = 64
    local div = 10
    local half_div = div * .5
    local offset = 315 --center
    if num > 1 then
        offset = offset - (w * .5 + half_div) * (num - 1)
    end

    local hint_tech_ingredient = nil

    -- processing tech ingredients
    for _, v in ipairs(recipe.tech_ingredients) do
        if v.type:sub(-9) == "_material" then
            local has, _ = builder_replica:HasTechIngredient(v)
            local ing =
                self.contents:AddChild(
                IngredientUI(
                    v.atlas,
                    v.type .. ".tex",
                    nil,
                    nil,
                    has,
                    STRINGS.NAMES[string.upper(v.type)],
                    owner,
                    v.type
                )
            )
            if num > 1 and #self.ing > 0 then
                offset = offset + half_div
            end
            ing:SetPosition(_G.Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
            offset = offset + w + half_div
            table.insert(self.ing, ing)
            if not has and hint_tech_ingredient == nil then
                hint_tech_ingredient = v.type:sub(1, -10):upper()
            end
        end
    end

    -- processing normal ingredients
    for _, v in ipairs(recipe.ingredients) do
        local need = _G.RoundBiasedUp(v.amount * builder_replica:IngredientMod())
        local _, num_found_inv = inventory_replica:Has(v.type, need)
        local _, num_found_chest, valid_chests_for_ingredient = findFromNearbyChests(owner, v.type)
        local total = num_found_chest + num_found_inv
        -- local has, num_found =
        --     inventory_replica:Has(v.type, _G.RoundBiasedUp(v.amount * builder_replica:IngredientMod()))
        -- merge tables
        for _, v1 in ipairs(valid_chests_for_ingredient) do
            table.insert(validChests, v1)
        end

        local ingredientUI =
            IngredientUI(
            v.atlas,
            v.type .. ".tex",
            need,
            total,
            total >= need,
            STRINGS.NAMES[string.upper(v.type)],
            owner,
            v.type
        )
        ingredientUI.quant:SetString(string.format("All:%d/%d\n(Inv:%d)", total, need, num_found_inv))
        local ing = self.contents:AddChild(ingredientUI)
        if num > 1 and #self.ing > 0 then
            offset = offset + half_div
        end
        ing:SetPosition(_G.Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
        offset = offset + w + half_div
        table.insert(self.ing, ing)
    end

    -- processing character ingredients
    for _, v in ipairs(recipe.character_ingredients) do
        --#BDOIG - does this need to listen for deltas and change while menu is open?
        --V2C: yes, but the entire craft tabs does. (will be added there)
        local has, amount = builder_replica:HasCharacterIngredient(v)
        local ing =
            self.contents:AddChild(
            IngredientUI(
                v.atlas,
                v.type .. ".tex",
                v.amount,
                amount,
                has,
                STRINGS.NAMES[string.upper(v.type)],
                owner,
                v.type
            )
        )
        if num > 1 and #self.ing > 0 then
            offset = offset + half_div
        end
        ing:SetPosition(_G.Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
        offset = offset + w + half_div
        table.insert(self.ing, ing)
    end

    local equippedBody = inventory_replica:GetEquippedItem(_G.EQUIPSLOTS.BODY)
    local showamulet = equippedBody and equippedBody.prefab == "greenamulet"

    if should_hint or hint_tech_ingredient ~= nil then
        self.button:Hide()

        local str
        if should_hint then
            local hint_text = {
                ["SCIENCEMACHINE"] = STRINGS.UI.CRAFTING.NEEDSCIENCEMACHINE,
                ["ALCHEMYMACHINE"] = STRINGS.UI.CRAFTING.NEEDALCHEMYENGINE,
                ["SHADOWMANIPULATOR"] = STRINGS.UI.CRAFTING.NEEDSHADOWMANIPULATOR,
                ["PRESTIHATITATOR"] = STRINGS.UI.CRAFTING.NEEDPRESTIHATITATOR,
                ["CANTRESEARCH"] = STRINGS.UI.CRAFTING.CANTRESEARCH,
                ["ANCIENTALTAR_HIGH"] = STRINGS.UI.CRAFTING.NEEDSANCIENT_FOUR
            }
            str = hint_text[GetHintTextForRecipe(owner, recipe)]
        else
            str = STRINGS.UI.CRAFTING.NEEDSTECH[hint_tech_ingredient]
        end
        self.teaser:SetScale(TEASER_SCALE_TEXT)
        self.teaser:SetMultilineTruncatedString(str, 3, TEASER_TEXT_WIDTH, 38, true)
        self.teaser:Show()
        showamulet = false
    else
        self.teaser:Hide()

        local buttonstr =
            (not (knows or recipe.nounlock) and STRINGS.UI.CRAFTING.PROTOTYPE) or
            (buffered and STRINGS.UI.CRAFTING.PLACE) or
            STRINGS.UI.CRAFTING.TABACTION[recipe.tab.str] or
            STRINGS.UI.CRAFTING.BUILD

        if _G.TheInput:ControllerAttached() then
            self.button:Hide()
            self.teaser:Show()

            if can_build then
                self.teaser:SetScale(TEASER_SCALE_BTN)
                self.teaser:SetTruncatedString(
                    _G.TheInput:GetLocalizedControl(_G.TheInput:GetControllerID(), CONTROL_ACCEPT) .. " " .. buttonstr,
                    TEASER_BTN_WIDTH,
                    26,
                    true
                )
            else
                self.teaser:SetScale(TEASER_SCALE_TEXT)
                self.teaser:SetMultilineTruncatedString(STRINGS.UI.CRAFTING.NEEDSTUFF, 3, TEASER_TEXT_WIDTH, 38, true)
            end
        else
            self.button:Show()
            if self.skins_spinner ~= nil then
                self.button:SetPosition(320, -155, 0)
            else
                self.button:SetPosition(320, -105, 0)
            end
            self.button:SetScale(1, 1, 1)

            self.button:SetText(buttonstr)
            if can_build then
                self.button:Enable()
            else
                self.button:Disable()
            end
        end
    end

    if showamulet then
        self.amulet:Show()
    else
        self.amulet:Hide()
    end

    -- update new tags
    if self.skins_spinner then
        self.skins_spinner.spinner:Changed()
    end

    highlight(validChests)
end

function CraftSlot:OnLoseFocus()
    CraftSlot._base.OnLoseFocus(self)
    unhighlight()
    self:Close()
end

-- AddClassPostConstruct("widgets/tabgroup", function(self)
--     local __TabGroup_DeselectAll = self.DeselectAll
--     function self:DeselectAll(...)
--       DoHighlightStuff(GLOBAL.ThePlayer,nil,"CraftingClose",true,false)
--       return __TabGroup_DeselectAll(self, ...)
--     end
-- end)