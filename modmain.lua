GLOBAL.CHEATS_ENABLED = true
GLOBAL.require("debugkeys")

local _G = GLOBAL

local server_side = _G.TheNet:GetIsServer()
local client_side = _G.TheNet:GetIsClient()

local DeBuG = GetModConfigData("debug")
local range = GetModConfigData("range")
local enabled = GetModConfigData("enable")
local inv_first = GetModConfigData("is_inv_first")

local c = {r = 0, g = 0.3, b = 0}

local Builder = _G.require "components/builder"

local thePlayer = nil
local players = _G.AllPlayers

local function isTable(t)
    return type(t) == "table"
end

local function debugPrint(...)
    local arg = {...}
    -- if DeBuG then
    for i, v in ipairs(arg) do
        print(v)
    end
    -- end
end

-- given the list of instances, return the list of instances of chest
local function filterChest(inst)
    local chest = {}
    for i, v in ipairs(inst) do
        if (v and v.components.container and v.components.container.type) then
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
    local entities = _G.TheSim:FindEntities(x, y, z, dist, {}, {"NOBLOCK", "player", "FX"}) or {}
    return filterChest(entities)
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

        for i, v in ipairs(getNearbyChest(player)) do
            player["cfcChests"]:set(v)
            break
        end
        if not player["cfcChests"]:value() then
            debugPrint("something wrong...")
        end

        player:PushEvent("stacksizechange")
    end
end

local function OnDirtyEventcfcChests(inst)
    debugPrint("calling OnDirtyEventcfcChests")
end

local function OnStackSizeChange(inst)
    debugPrint("calling onStackSizeChange")

    -- testing
    local chests = inst["cfcChests"]:value()
    if chests ~= nil then
        for k, v in pairs(chests) do
            debugPrint(k,v)
        end
    else
        debugPrint("cfcChests is nil")
    end

    if client_side then
        local x, y, z = inst.Transform:GetWorldPosition()
        local entities = _G.TheSim:FindEntities(x, y, z, range, {}, {"NOBLOCK", "player", "FX"}) or {}
        debugPrint("this is client side, found"..#(entities or {}).. "chests")
    end
end

AddPlayerPostInit(
    function(inst)
        -- init the current player ptr
        thePlayer = inst

        -- add network items passing around client & server
        inst["cfcChests"] = _G.net_entity(inst.GUID, "cfcChestsNetStuff", "DirtyEventcfcChests")
        inst["cfcChests"]:set(nil)

        -- register listener
        inst:ListenForEvent("DirtyEventcfcChests", OnDirtyEventcfcChests)
        inst:ListenForEvent("stacksizechange", OnStackSizeChange)
    end
)

local function ServerRPCFunc(owner, highlight, unhighlight)
    debugPrint("calling ServerRPCFunc")

    if owner == nil then
        return
    end

    debugPrint("highlight? " .. highlight)
    debugPrint("unhighlight? " .. unhighlight)

    -- if isTable(owner) then
    --     for k, v in pairs(owner) do
    --         debugPrint(k, v)
    --     end
    -- end
end

function Builder:OnUpdate(dt)
    self:EvaluateTechTrees()
    if server_side then
        for _, player in ipairs(players) do
            compareValidChests(player)
        end
    end
end
-- if thePlayer == player then
-- debugPrint("player is "..player.userid)
-- end
