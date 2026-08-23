---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Polar Dog",
    version = "0.1",
    description = "A rock dog that moved to the Ice Caves. Entry for Spelunky Mod Jam 8.",
    author = "garebear",
}

local DOG = ENT_TYPE.MOUNT_ROCKDOG
local FIREBALL = ENT_TYPE.ITEM_FIREBALL
local FREEZE_SHOT = ENT_TYPE.ITEM_FREEZERAYSHOT

local TINT = Color:new(0.45, 0.7, 1.0, 1.0)

local MUZZLE = 2.0

register_option_int("rarity", "Rarity",
    "Roughly one Polar Dog per this many valid spots in an Ice Caves level. Lower means more of them.", 60, 10, 400)

local polar_slot = {}

local function dogs()
    return get_entities_by(DOG, MASK.MOUNT, LAYER.BOTH)
end

local function polarity(ent)
    local data = ent.user_data
    if type(data) == "table" and data.polar ~= nil then
        return data.polar
    end
    return nil
end

local function set_polarity(ent, polar)
    ent.user_data = { polar = polar }
    if polar then
        ent.color = TINT
    end
end

local function any_polar_slot()
    for _, polar in pairs(polar_slot) do
        if polar then
            return true
        end
    end
    return false
end

local function rider_slot(uid)
    if uid <= -1 then
        return nil
    end
    for slot, player in pairs(players) do
        if player.uid == uid then
            return slot
        end
    end
    return nil
end

local function spawn_polar_dog(x, y, layer)
    local ent = get_entity(spawn_entity(DOG, x, y, layer, 0, 0)) --[[@as Mount]]
    if ent then
        ent.tamed = false
        set_polarity(ent, true)
    end
end


---@diagnostic disable-next-line: param-type-mismatch
local DOG_CHANCE = define_procedural_spawn("polar_dog", spawn_polar_dog, nil)

set_callback(function(room_gen_ctx)
    local chance = 0
    if state.theme == THEME.ICE_CAVES then
        chance = options.rarity
    end
    room_gen_ctx:set_procedural_spawn_chance(DOG_CHANCE, chance)
end, ON.POST_ROOM_GENERATION)

local function fired_by_polar_dog(x, y, layer)
    for _, uid in pairs(dogs()) do
        local ent = get_entity(uid)
        if ent and polarity(ent) and ent.layer == layer then
            local dog_x, dog_y = get_position(uid)
            if math.abs(dog_x - x) <= MUZZLE and math.abs(dog_y - y) <= MUZZLE then
                return true
            end
        end
    end
    return false
end

set_pre_entity_spawn(function(_, x, y, layer)
    if fired_by_polar_dog(x, y, layer) then
        return spawn_entity_nonreplaceable(FREEZE_SHOT, x, y, layer, 0, 0)
    end
    return nil
end, SPAWN_TYPE.ANY, MASK.ANY, FIREBALL)


set_global_interval(function()
    for _, uid in pairs(dogs()) do
        local ent = get_entity(uid) --[[@as Mount]]
        if ent then
            local slot = rider_slot(ent.rider_uid)
            local polar = polarity(ent)

            if polar == nil then
                if slot ~= nil then
                    polar = polar_slot[slot] == true
                    set_polarity(ent, polar)
                elseif state.screen == SCREEN.LEVEL then
                    polar = false
                    set_polarity(ent, false)
                else
                    polar = any_polar_slot()
                    if polar then
                        set_polarity(ent, true)
                    end
                end
            end

            if polar then
                ent.color = TINT
            end
            if slot then
                polar_slot[slot] = polar
            end
        end
    end
end, 1)

set_callback(function()
    polar_slot = {}
end, ON.START)
