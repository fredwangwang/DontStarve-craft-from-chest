local _G = GLOBAL

local range = GetModConfigData("range")
local c = {r = 0, g = 0.5, b = 0}

local Builder = _G.require 'components/builder'
local Highlight = _G.require 'components/highlight'
local IngredientUI = _G.require 'widgets/ingredientui'
local RecipePopup = _G.require 'widgets/recipepopup'
local TabGroup = _G.require 'widgets/tabgroup'
local CraftSlot = _G.require 'widgets/craftslot'

local highlit = {} -- tracking what is highlighted
local consumedChest = {}
local validChests = {}


local TEASER_SCALE_TEXT = 1
local TEASER_SCALE_BTN = 1.5

local function filterChest(inst)
    local chest = {}
    for k, v in pairs(inst) do
        if (v and v.components.container) then
            table.insert(chest, v)
        end
    end
    return chest
end

local function getNearbyChest(owner)
    local x, y, z = owner.Transform:GetWorldPosition()
    local inst = _G.TheSim:FindEntities(x, y, z, range, {}, {'NOBLOCK', 'player', 'FX'}) or {}
    return filterChest(inst)
end

local function findFromChests(chests, item)
    if not (chests and item) then return false, 0, {} end
    local qualifyChests = {}
    local total = 0
    local contains = false
    
    for k, v in pairs(chests) do
        local found, n = v.components.container:Has(item, 1)
        if found then
            contains = true
            total = total + n
            table.insert(qualifyChests, v);
        end
    end
    return contains, total, qualifyChests
end

local function findFromNearbyChests(player, item)
    chests = getNearbyChest(player)
    if not (chests and item) then return false, 0, {} end
    return findFromChests(chests, item)
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
        if not v.components.highlight then v:AddComponent('highlight') end
        if v.components.highlight then
            v.components.highlight:Highlight(c.r, c.g, c.b)
            table.insert(highlit, v)
        end
    end
end

local _oldCmpChests = {}
local _newCmpChests = {}
local function compareValidChests(player)
    _newCmpChests = getNearbyChest(player)
    if (#_oldCmpChests ~= #_newCmpChests) then
        _oldCmpChests = _newCmpChests
        _newCmpChests = {}
        player:PushEvent("stacksizechange")
    -- print("detect #chest changing")
    end
end

function TabGroup:DeselectAll(...)
    for k, v in ipairs(self.tabs) do
        v:Deselect()
    end
    unhighlight(highlit)
end

function Builder:CanBuild(recname)
    if self.freebuildmode then return true end
    
    local player = self.inst
    local chests = getNearbyChest(player)
    local recipe = _G.GetRecipe(recname)
    if recipe then
        for ik, iv in pairs(recipe.ingredients) do
            local amt = math.max(1, _G.RoundUp(iv.amount * self.ingredientmod))
            found, num_found = findFromChests(chests, iv.type)
            has, num_hold = player.components.inventory:Has(iv.type, amt)
            if (amt > num_found + num_hold) then
                return false
            end
        end
        return true
    end
    return false
end

function Builder:OnUpdate(dt)
    local player = self.inst
    compareValidChests(player)
    self:EvaluateTechTrees()
end

local function removeFromValidChests(owner, chests, item, amt)
    print(#chests)
    for k, v in pairs(chests) do
        local container = v.components.container
        found, num_found = container:Has(item, 1)
        if found then
            print('foundCorrectChest')
            table.insert(consumedChest, v)
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
    
    if (amt > 0) then
        print("cannot produce, do one more round")
        removeFromValidChests(owner, getNearbyChest(owner), item, amt)
    end
end

_G.DoRecipeClick = function(owner, recipe)
    -- consumedChest = {}
    -- for k, v in pairs(recipe.ingredients) do removeFromValidChests(owner, validChests, v.type, _G.RoundUp(v.amount * owner.components.builder.ingredientmod)) end
    if recipe and owner and owner.components.builder then
        local knows = owner.components.builder:KnowsRecipe(recipe.name)
        local can_build = owner.components.builder:CanBuild(recipe.name)
        if not can_build then
            owner:PushEvent("cantbuild", {owner = owner, recipe = recipe})
            --You might have the materials now. Check again.
            can_build = owner.components.builder:CanBuild(recipe.name)
        end
        local buffered = owner.components.builder:IsBuildBuffered(recipe.name)
        if knows then
            if buffered then
                --TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
                --owner.HUD.controls.crafttabs.tabs:DeselectAll()
                if recipe.placer then
                    owner.components.playercontroller:StartBuildPlacementMode(recipe, function(pt) return owner.components.builder:CanBuildAtPoint(pt, recipe) end)
                else
                    owner.components.builder:MakeRecipe(recipe)
                end
            elseif can_build then
                --TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
                if recipe.placer then
                    --owner.HUD.controls.crafttabs.tabs:DeselectAll()
                    owner.components.builder:BufferBuild(recipe.name)
                    owner.components.playercontroller:StartBuildPlacementMode(recipe, function(pt) return owner.components.builder:CanBuildAtPoint(pt, recipe) end)
                else
                    owner.components.builder:MakeRecipe(recipe)
                    return true
                end
            else
                return true
            end
        else
            local tech_level = owner.components.builder.accessible_tech_trees
            if can_build and _G.CanPrototypeRecipe(recipe.level, tech_level) then
                owner.SoundEmitter:PlaySound("dontstarve/HUD/research_unlock")
                local onsuccess = function()
                    owner.components.builder:ActivateCurrentResearchMachine()
                    owner.components.builder:UnlockRecipe(recipe.name)
                end
                if recipe.placer then
                    onsuccess()
                    owner.components.builder:BufferBuild(recipe.name)
                    owner.components.playercontroller:StartBuildPlacementMode(recipe, function(pt) return owner.components.builder:CanBuildAtPoint(pt, recipe) end)
                else
                    owner.components.builder:MakeRecipe(recipe, nil, onsuccess)
                end
            else
                return true
            end
        end
    end
end

function RecipePopup:Refresh()
    unhighlight(highlit)
    local recipe = self.recipe
    local owner = self.owner
    
    if not owner then return false end
    
    local knows = owner.components.builder:KnowsRecipe(recipe.name)
    local buffered = owner.components.builder:IsBuildBuffered(recipe.name)
    local can_build = owner.components.builder:CanBuild(recipe.name) or buffered
    local tech_level = owner.components.builder.accessible_tech_trees
    local should_hint = not knows and _G.ShouldHintRecipe(recipe.level, tech_level) and not _G.CanPrototypeRecipe(recipe.level, tech_level)
    local equippedBody = owner.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.BODY)
    local showamulet = equippedBody and equippedBody.prefab == "greenamulet"
    local controller_id = _G.TheInput:GetControllerID()
    
    if should_hint then
        self.recipecost:Hide()
        self.button:Hide()
        local hint_text = {
            ["SCIENCEMACHINE"] = _G.STRINGS.UI.CRAFTING.NEEDSCIENCEMACHINE,
            ["ALCHEMYMACHINE"] = _G.STRINGS.UI.CRAFTING.NEEDALCHEMYENGINE,
            ["SHADOWMANIPULATOR"] = _G.STRINGS.UI.CRAFTING.NEEDSHADOWMANIPULATOR,
            ["PRESTIHATITATOR"] = _G.STRINGS.UI.CRAFTING.NEEDPRESTIHATITATOR,
            ["CANTRESEARCH"] = _G.STRINGS.UI.CRAFTING.CANTRESEARCH,
            ["ANCIENTALTAR_HIGH"] = _G.STRINGS.UI.CRAFTING.NEEDSANCIENT_FOUR,
        }
        
        if _G.SaveGameIndex:IsModeShipwrecked() then
            hint_text["PRESTIHATITATOR"] = _G.STRINGS.UI.CRAFTING.NEEDPIRATIHATITATOR
        end
        
        local str = hint_text[_G.GetHintTextForRecipe(recipe)] or "Text not found."
        self.teaser:SetScale(TEASER_SCALE_TEXT)
        self.teaser:SetString(str)
        self.teaser:Show()
        showamulet = false
    elseif knows then
        self.teaser:Hide()
        self.recipecost:Hide()
        
        if _G.TheInput:ControllerAttached() then
            self.button:Hide()
            self.teaser:Show()
            
            if can_build then
                self.teaser:SetScale(TEASER_SCALE_BTN)
                self.teaser:SetString(_G.TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. (buffered and _G.STRINGS.UI.CRAFTING.PLACE or _G.STRINGS.UI.CRAFTING.BUILD))
            else
                self.teaser:SetScale(TEASER_SCALE_TEXT)
                self.teaser:SetString(_G.STRINGS.UI.CRAFTING.NEEDSTUFF)
            end
        else
            self.button:Show()
            self.button:SetPosition(320, -105, 0)
            self.button:SetScale(1, 1, 1)
            
            self.button:SetText(buffered and _G.STRINGS.UI.CRAFTING.PLACE or _G.STRINGS.UI.CRAFTING.BUILD)
            if can_build
            then self.button:Enable()
            else self.button:Disable() end
        end
    else
        self.teaser:Hide()
        self.recipecost:Hide()
        
        if _G.TheInput:ControllerAttached() then
            self.button:Hide()
            self.teaser:Show()
            self.teaser:SetColour(1, 1, 1, 1)
            if can_build then
                self.teaser:SetScale(TEASER_SCALE_BTN)
                self.teaser:SetString(_G.TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. _G.STRINGS.UI.CRAFTING.PROTOTYPE)
            else
                self.teaser:SetScale(TEASER_SCALE_TEXT)
                self.teaser:SetString(_G.STRINGS.UI.CRAFTING.NEEDSTUFF)
            end
        else
            self.button.image_normal = "button.tex"
            self.button.image:SetTexture(_G.UI_ATLAS, self.button.image_normal)
            
            self.button:Show()
            self.button:SetPosition(320, -105, 0)
            self.button:SetScale(1, 1, 1)
            
            self.button:SetText(_G.STRINGS.UI.CRAFTING.PROTOTYPE)
            if can_build
            then self.button:Enable()
            else self.button:Disable() end
        end
    end
    
    if not showamulet then self.amulet:Hide()
    else self.amulet:Show() end
    
    self.name:SetString(_G.STRINGS.NAMES[string.upper(self.recipe.name)])
    self.desc:SetString(_G.STRINGS.RECIPE_DESC[string.upper(self.recipe.name)])
    
    for k, v in pairs(self.ing) do
        v:Kill()
    end
    self.ing = {}
    
    local center = 330
    local num = 0
    for k, v in pairs(recipe.ingredients) do num = num + 1 end
    local w = 64
    local div = 10
    
    local offset = center
    if num > 1 then
        offset = offset - (w / 2 + div) * (num - 1)
    end
    
    local total, need, has_chest, num_found_chest, has_inv, num_found_inv
    validChests = {}
    
    for k, v in pairs(recipe.ingredients) do
        -- calculations
        local validChestsOfIngredient = {}
        need = _G.RoundUp(v.amount * owner.components.builder.ingredientmod)
        has_inv, num_found_inv = owner.components.inventory:Has(v.type, need)
        has_chest, num_found_chest, validChestsOfIngredient = findFromNearbyChests(owner, v.type)
        
        total = num_found_chest + num_found_inv
        
        -- merge tables
        for k1, v1 in pairs(validChestsOfIngredient) do table.insert(validChests, v1) end
        
        local item_img = v.type
        if _G.SaveGameIndex:IsModeShipwrecked() and _G.SW_ICONS[item_img] ~= nil then
            item_img = _G.SW_ICONS[item_img]
        end
        
        local ingredientUI = IngredientUI(v.atlas, item_img .. ".tex", need, total, total > need, _G.STRINGS.NAMES[string.upper(v.type)], owner)
        ingredientUI.quant:SetString(string.format("Inv:%d/%d\nAll:%d/%d", num_found_inv, need, total, need))
        local ing = self.contents:AddChild(ingredientUI)
        ing:SetPosition(_G.Vector3(offset, 80, 0))
        offset = offset + (w + div)
        self.ing[k] = ing
    end
    
    highlight(validChests, highlit)
end

-- function CraftSlot:OnGainFocus()
--     CraftSlot._base.OnGainFocus(self)
--     self:Open()
--     print(self.recipename)
--     recipe = self.recipe
--     if (recipe and recipe.ingredients)
--     if (self.recipe) then
--     print(table.concat(self.recipe, ','))
--     end
-- end
function CraftSlot:OnLoseFocus()
    CraftSlot._base.OnLoseFocus(self)
    self:Close()
    unhighlight(highlit)
end

-- local function openChests(...)
--     if not #consumedChest then return end
--     for k, v in pairs(consumedChest) do
--         if v and v.components.container then
--             v.components.container:Open()
--         end
--     end
-- end

-- local function closeChests(...)
--     while #consumedChest > 0 do
--         local v = table.remove(consumedChest)
--         if v and v.components.container then
--             v.components.container:Close()
--         end
--     end
-- end

-- local function init(owner)
--     if not owner then return end
-- -- owner:ListenForEvent('consumeingredients', openChests)
-- -- owner:ListenForEvent('newactiveitem', closeChests)
-- end

-- AddPlayerPostInit(function(owner)
--     init(owner)
-- end)
