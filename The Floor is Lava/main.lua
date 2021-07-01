meta.name = "The Floor is Lava"
meta.version = "0.5"
meta.description = "All floor tiles become lava shortly after standing on them"
meta.author = "garebear"

TILES = {}
DEFAULT_LAVA_TIMER = 60 * 2
PARTICLE_DELAY = 15
SAFE_FLOOR = nil

UNSAFE_FLOORS = {
    [ENT_TYPE.FLOORSTYLED_MINEWOOD] = true,
    [ENT_TYPE.FLOOR_GENERIC] = true,
    [ENT_TYPE.FLOOR_SURFACE] = true,
    [ENT_TYPE.FLOOR_SURFACE_HIDDEN] = true,
    [ENT_TYPE.FLOORSTYLED_STONE] = true,
    [ENT_TYPE.FLOORSTYLED_TEMPLE] = true,
    [ENT_TYPE.FLOORSTYLED_PAGODA] = true,
    [ENT_TYPE.FLOORSTYLED_BABYLON] = true,
    [ENT_TYPE.FLOORSTYLED_SUNKEN] = true,
    [ENT_TYPE.FLOORSTYLED_BEEHIVE] = true,
    [ENT_TYPE.FLOORSTYLED_VLAD] = true,
    [ENT_TYPE.FLOORSTYLED_COG] = true,
    [ENT_TYPE.FLOORSTYLED_MOTHERSHIP] = true,
    [ENT_TYPE.FLOORSTYLED_DUAT] = true,
    [ENT_TYPE.FLOORSTYLED_PALACE] = true,
    [ENT_TYPE.FLOORSTYLED_GUTS] = true,
}

register_option_int(
    "lava_timer",
    "Frames before floor tile turns to lava.",
    DEFAULT_LAVA_TIMER,
    60 * 1,
    60 * 5
)
register_option_bool(
    "thicc_lava",
    "Use Thicc Lava",
    true
)
register_option_bool(
    "bomb_olmec",
    "Olmec is Bombs",
    true
)
register_option_bool(
    "bomb_tiamat",
    "Tiamat is Bombs",
    true
)
register_option_bool(
    "safe_platform",
    "Safe Starting Platform",
    false
)
register_option_bool(
    "safe_minewood",
    "Minewood is Safe",
    true
)
register_option_bool(
    "safe_sunken",
    "Sunken Stone is Safe",
    true
)
register_option_bool(
    "safe_pagodas",
    "Pagodas are Safe",
    true
)
register_option_bool(
    "remove_cobwebs",
    "Remove Cobwebs",
    true
)
register_option_bool(
    "remove_quillback_pushblocks",
    "Remove Quillback Pushblocks",
    true
)


function clamp(n, low, high)
    return math.min(math.max(n, low), high)
end

function get_particle_timeout()
    return clamp(options.lava_timer - PARTICLE_DELAY, 0, options.lava_timer)
end

function test_and_get_floor_entity(uid)
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

    return entity
end

function is_level()
    return state.screen == 12 and state.screen_next == 12
end

function emit_particles(uid)
    if not is_level() then
        return
    end

    local entity = test_and_get_floor_entity(uid)
    if entity == nil then
        return
    end

    generate_particles(PARTICLEEMITTER.EXPLOSION_SPARKS, uid)
end

function spawn_lava(x, y)
    if options.thicc_lava then
        return spawn_liquid(ENT_TYPE.LIQUID_STAGNANT_LAVA, x, y)
    end

    return spawn_liquid(ENT_TYPE.LIQUID_LAVA, x, y)
end

function bomb_or_break(uid, x, y, layer, should_bomb)
    if should_bomb then
        spawn_entity(ENT_TYPE.FX_EXPLOSION, x, y, layer, 0, 0)
    else
        kill_entity(uid)
    end
end

function make_tile_lava(uid)
    if not is_level() then
        return
    end

    local entity = test_and_get_floor_entity(uid)
    if entity == nil then
        return
    end

    local x, y, layer = get_position(uid)

    if state.theme == THEME.OLMEC then
        bomb_or_break(uid, x, y, layer, options.bomb_olmec)
    elseif state.theme == THEME.TIAMAT then
        bomb_or_break(uid, x, y, layer, options.bomb_tiamat)
    else
        kill_entity(uid)
        if layer == LAYER.BACK then
            return
        end
        spawn_lava(x, y)
    end
end

function get_player_or_mount(player)
    overlay = player.overlay
    if overlay == nil then
        return player
    end

    if overlay.type.search_flags & MASK.MOUNT == 0 then
        return player
    end

    local mount = overlay:as_mount()
    return mount
end

function queue_lava(uid)
    local callbacks = {}

    table.insert(callbacks, set_timeout(function()
        emit_particles(uid)
    end, get_particle_timeout()))

    table.insert(callbacks, set_timeout(function()
        make_tile_lava(uid)
    end, options.lava_timer))

    TILES[uid] = callbacks
end

function maybe_schedule_lava(player)
    local player = get_player_or_mount(player)

    -- Already scheduled lava-ing
    if TILES[player.standing_on_uid] ~= nil then
        return
    end
    
    -- Not standing on anything
    if player.standing_on_uid <= 0 then
        return
    end

    local standing_uid = player.standing_on_uid
    if options.safe_platform and standing_uid == SAFE_FLOOR then
        return
    end

    local standing_entity = get_entity(standing_uid)

    -- Didn't get an entity back
    if standing_entity == nil then
        return
    end

    if not is_floor(standing_entity) then
        return
    end

    if options.safe_minewood and standing_entity.type.id == ENT_TYPE.FLOORSTYLED_MINEWOOD then
        return
    end

    if options.safe_pagodas and standing_entity.type.id == ENT_TYPE.FLOORSTYLED_PAGODA then
        return
    end

    if options.safe_sunken and standing_entity.type.id == ENT_TYPE.FLOORSTYLED_SUNKEN then
        return
    end

    queue_lava(standing_uid)
end 

function is_floor(entity)
    return UNSAFE_FLOORS[entity.type.id] ~= nil
end

function remove_all(ent_type)
    uids = get_entities_by_type(ent_type)
    for _, uid in ipairs(uids) do
        kill_entity(uid)
    end
end

set_callback(function()
    -- Clear any outstanding callbacks
    TILES = {}

    for _, player in ipairs(players) do
        if player ~= nil then
            SAFE_FLOOR = player.standing_on_uid
        end
    end

    if options.remove_quillback_pushblocks and state.world == 1 and state.level == 4 then
        remove_all(ENT_TYPE.ACTIVEFLOOR_PUSHBLOCK)
    end

    if options.remove_cobwebs then
        remove_all(ENT_TYPE.ITEM_WEB)
    end

end, ON.LEVEL)

function clean_up_lava(lava_uid, exit_uids)
    if state.world == 5 then
        local x, y, _ = get_position(lava_uid)
        if y < 5 then
            kill_entity(lava_uid)
        end
    end

    if exit_uids == nil or #exit_uids <= 0 then
        return
    end

    for _, exit_uid in ipairs(exit_uids) do
        local exit = get_entity(exit_uid)
        local lava = get_entity(lava_uid)
        if exit:overlaps_with(lava) then
            kill_entity(lava_uid)
        end
    end
end

set_callback(function()
    for _, player in ipairs(players) do
        if player ~= nil then
            maybe_schedule_lava(player)
        end
    end

    lava_uids = get_entities_by_mask(MASK.LAVA)
    exit_uids = get_entities_by_type(ENT_TYPE.FLOOR_DOOR_EXIT)
    for _, lava_uid in ipairs(lava_uids) do
        clean_up_lava(lava_uid, exit_uids)
    end

end, ON.FRAME)

-- Boulder doesn't like hitting lava
set_pre_entity_spawn(function(ent_type, x, y, l, overlay)
    return spawn(ENT_TYPE.ITEM_ROCK, x, y, l, 0, 0)
end, SPAWN_TYPE.ANY, 0, ENT_TYPE.ACTIVEFLOOR_BOULDER)
