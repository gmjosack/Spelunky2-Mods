meta.name = "The Floor is Lava"
meta.version = "0.1"
meta.description = "All floor tiles become lava shortly after standing on them"
meta.author = "garebear"

TILES = {}
DEFAULT_LAVA_TIMER = 60 * 2

register_option_int(
    "lava_timer",
    "Frames before floor tile turns to lava.",
    DEFAULT_LAVA_TIMER,
    60 * 1,
    60 * 5
)

function make_tile_lava(uid)
    -- Outstanding callback from previous level, just early exit.
    if TILES[uid] == nil then
        return
    end

    local entity = get_entity(uid)

    if entity == nil then
        return
    end

    if not is_floor(entity) then
        return
    end

    kill_entity(uid)
    spawn_liquid(ENT_TYPE.LIQUID_LAVA, entity.x, entity.y)
end

function maybe_schedule_lava(player)
    -- Already scheduled lava-ing
    if TILES[player.standing_on_uid] ~= nil then
        return
    end
    
    -- Not standing on anything
    if player.standing_on_uid == 0 then
        return
    end
    
    local standing_uid = player.standing_on_uid
    local standing_entity = get_entity(standing_uid)

    -- Didn't get an entity back
    if standing_entity == nil then
        return
    end

    if not is_floor(standing_entity) then
        return
    end

    TILES[standing_uid] = set_timeout(function()
        make_tile_lava(standing_uid)
    end, options.lava_timer)
end 

function is_floor(entity)
    local floor_mask = MASK.FLOOR
    return (entity.type.search_flags & floor_mask) ~= 0
end

set_callback(function()
    -- Clear any outstanding callbacks
    TILES = {}
end, ON.LEVEL)

set_callback(function()
    for _, player in ipairs(players) do
        if player ~= nil then
            maybe_schedule_lava(player)
        end
    end
end, ON.FRAME)