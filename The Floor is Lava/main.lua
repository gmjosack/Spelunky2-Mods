meta.name = "The Floor is Lava"
meta.version = "0.4"
meta.description = "All floor tiles become lava shortly after standing on them"
meta.author = "garebear"

TILES = {}
DEFAULT_LAVA_TIMER = 60 * 2
PARTICLE_DELAY = 15
SAFE_FLOOR = nil

register_option_int(
    "lava_timer",
    "Frames before floor tile turns to lava.",
    DEFAULT_LAVA_TIMER,
    60 * 1,
    60 * 5
)
register_option_bool(
    "safe_platform",
    "Provide a safety platform",
    false
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

function emit_particles(uid)
    local entity = test_and_get_floor_entity(uid)
    if entity == nil then
        return
    end

    generate_particles(PARTICLEEMITTER.EXPLOSION_SPARKS, uid)
end

function make_tile_lava(uid)
    local entity = test_and_get_floor_entity(uid)
    if entity == nil then
        return
    end

    local x, y, layer = get_position(uid)

    kill_entity(uid)
    if layer == LAYER.BACK then
        return
    end
    spawn_liquid(ENT_TYPE.LIQUID_STAGNANT_LAVA, x, y)
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

    if standing_entity.type.id == ENT_TYPE.FLOOR_DOOR_PLATFORM then
        return
    end

    local callbacks = {}

    table.insert(callbacks, set_timeout(function()
        emit_particles(standing_uid)
    end, get_particle_timeout()))

    table.insert(callbacks, set_timeout(function()
        make_tile_lava(standing_uid)
    end, options.lava_timer))

    TILES[standing_uid] = callbacks
end 

function is_floor(entity)
    local floor_mask = MASK.FLOOR
    return (entity.type.search_flags & floor_mask) ~= 0
end

set_callback(function()
    -- Clear any outstanding callbacks
    TILES = {}

    for _, player in ipairs(players) do
        if player ~= nil then
            SAFE_FLOOR = player.standing_on_uid
        end
    end
end, ON.LEVEL)

set_callback(function()
    for _, player in ipairs(players) do
        if player ~= nil then
            maybe_schedule_lava(player)
        end
    end
end, ON.FRAME)