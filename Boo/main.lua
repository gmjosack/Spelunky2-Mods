---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Boo",
    version = "0.1",
    description = "Shy ghosts that don't like to be looked at. Entry for Spelunky Mod Jam 8.",
    author = "garebear",
}

-- setting ghost_behaviour on these causes the game to crash.
local BOOS = {
    ENT_TYPE.MONS_GHOST_SMALL_ANGRY,
    ENT_TYPE.MONS_GHOST_SMALL_SAD,
    ENT_TYPE.MONS_GHOST_SMALL_SURPRISED,
    ENT_TYPE.MONS_GHOST_SMALL_HAPPY,
}

local SCALE = 0.5

local SPEED = 0.055
local SPEED_SPREAD = 0.35
local TURN = 0.05

local SEPARATION = 1.0
local SEPARATION_PUSH = 0.6
local STALE_AFTER = 3

local WAVE_AMOUNT = 0.35
local WAVE_SPREAD = 0.4
local WAVE_SPEED = 0.07

local WATCH_X = 11.0
local WATCH_Y = 6.5

local SAFE_SPAWN = 9.0

local AREAS = {
    { key = "dwelling",    theme = THEME.DWELLING,     name = "Dwelling" },
    { key = "jungle",      theme = THEME.JUNGLE,       name = "Jungle" },
    { key = "volcana",     theme = THEME.VOLCANA,      name = "Volcana" },
    { key = "olmec",       theme = THEME.OLMEC,        name = "Olmec" },
    { key = "tidepool",    theme = THEME.TIDE_POOL,    name = "Tide Pool" },
    { key = "temple",      theme = THEME.TEMPLE,       name = "Temple" },
    { key = "icecaves",    theme = THEME.ICE_CAVES,    name = "Ice Caves" },
    { key = "neobabylon",  theme = THEME.NEO_BABYLON,  name = "Neo Babylon" },
    { key = "sunkencity",  theme = THEME.SUNKEN_CITY,  name = "Sunken City" },
    { key = "cosmicocean", theme = THEME.COSMIC_OCEAN, name = "Cosmic Ocean" },
}

local AREA_OPTION = {}
for i, area in ipairs(AREAS) do
    local option = string.format("area_%02d_%s", i, area.key)
    register_option_bool(option, "Spawn in " .. area.name, "", true)
    AREA_OPTION[area.theme] = option
end

register_option_int("max_per_level", "Max per level",
    "Max boos per level.", 4, 1, 20)

register_option_int("rarity", "Rarity",
    "Roughly one Boo per this many open spots in a level. Lower means more of them.", 100, 20, 2000)

local candidates = {}
local flock = {}
local made = 0

local function boo_data(ent)
    local data = ent.user_data
    if type(data) == "table" and data.boo then
        return data
    end
    return nil
end

local function watched(x, y, layer)
    for _, player in pairs(players) do
        if player.health > 0 then
            local px, py, player_layer = get_position(player.uid)
            if player_layer == layer then
                local dx, dy = x - px, y - py
                if math.abs(dx) <= WATCH_X and math.abs(dy) <= WATCH_Y then
                    if test_flag(player.flags, ENT_FLAG.FACING_LEFT) == (dx <= 0) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function nearest_player(x, y, layer)
    local best_x, best_y, best_dist
    for _, player in pairs(players) do
        if player.health > 0 then
            local px, py, player_layer = get_position(player.uid)
            if player_layer == layer then
                local dx, dy = px - x, py - y
                local dist = dx * dx + dy * dy
                if not best_dist or dist < best_dist then
                    best_x, best_y, best_dist = px, py, dist
                end
            end
        end
    end
    if not best_dist then
        return nil, nil, math.huge
    end
    return best_x, best_y, math.sqrt(best_dist)
end

local function crowding(self)
    local push_x, push_y = 0.0, 0.0
    for _, other in pairs(flock) do
        if other ~= self and other.layer == self.layer and state.time_level - other.stamp <= STALE_AFTER then
            local dx, dy = self.x - other.x, self.y - other.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < SEPARATION and dist > 0.001 then
                local strength = (SEPARATION - dist) / SEPARATION
                push_x = push_x + dx / dist * strength
                push_y = push_y + dy / dist * strength
            end
        end
    end
    return push_x, push_y
end

---@param ent Ghost
local function creep(ent)
    local data = boo_data(ent)
    if not data then
        return
    end

    data.layer = ent.layer
    data.stamp = state.time_level

    if watched(data.x, data.y, data.layer) then
        data.vx, data.vy = 0.0, 0.0
    else
        local want_x, want_y = 0.0, 0.0

        local tx, ty = nearest_player(data.x, data.y, data.layer)
        if tx then
            local dx, dy = tx - data.x, ty - data.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.01 then
                want_x, want_y = dx / dist * data.speed, dy / dist * data.speed
            end
        end

        local push_x, push_y = crowding(data)
        want_x = want_x + push_x * data.speed * SEPARATION_PUSH
        want_y = want_y + push_y * data.speed * SEPARATION_PUSH

        local want = math.sqrt(want_x * want_x + want_y * want_y)
        if want > data.speed then
            want_x, want_y = want_x / want * data.speed, want_y / want * data.speed
        end

        data.vx = data.vx + (want_x - data.vx) * TURN
        data.vy = data.vy + (want_y - data.vy) * TURN
        data.x = data.x + data.vx
        data.y = data.y + data.vy
        data.tick = data.tick + 1
    end

    ent.x = data.x
    ent.y = data.y + math.sin(data.tick * data.wave_speed + data.phase) * data.wave
    ent.velocityx, ent.velocityy = 0.0, 0.0
    ent.width, ent.height = data.width, data.height
end

local function spread(base, amount)
    return base * (1.0 + (prng:random() * 2.0 - 1.0) * amount)
end

local function make_boo(x, y, layer, index)
    local uid = spawn_entity(BOOS[index], x, y, layer, 0, 0)
    local ent = get_entity(uid) --[[@as Ghost]]
    if not ent then
        return nil
    end

    ent.width, ent.height = ent.width * SCALE, ent.height * SCALE
    ent.hitboxx, ent.hitboxy = ent.hitboxx * SCALE, ent.hitboxy * SCALE

    local data = {
        boo = true,
        x = x,
        y = y,
        vx = 0.0,
        vy = 0.0,
        tick = 0,
        layer = layer,
        stamp = state.time_level,
        speed = spread(SPEED, SPEED_SPREAD),
        wave = spread(WAVE_AMOUNT, WAVE_SPREAD),
        wave_speed = spread(WAVE_SPEED, 0.2),
        phase = prng:random() * math.pi * 2.0,
        width = ent.width,
        height = ent.height,
    }

    ent.user_data = data
    flock[uid] = data
    ent:set_post_update_state_machine(creep)

    return ent
end

local function open_at(x, y, layer)
    return get_grid_entity_at(x, y, layer) == -1
end

local function valid_boo_spawn(x, y, layer)
    return open_at(x, y, layer) and open_at(x, y + 1, layer) and open_at(x, y - 1, layer)
end

local function remember_spot(x, y, layer)
    candidates[#candidates + 1] = { x = x, y = y, layer = layer }
end

local BOO_CHANCE = define_procedural_spawn("boo", remember_spot, valid_boo_spawn)

set_callback(function(room_gen_ctx)
    local option = AREA_OPTION[state.theme]
    local chance = 0
    if option and options[option] then
        chance = options.rarity
    end
    room_gen_ctx:set_procedural_spawn_chance(BOO_CHANCE, chance)
end, ON.POST_ROOM_GENERATION)

set_callback(function()
    candidates = {}
    flock = {}
    made = 0
end, ON.PRE_LEVEL_GENERATION)

set_callback(function()
    local spots = candidates
    candidates = {}

    local usable = {}
    for _, spot in ipairs(spots) do
        if valid_boo_spawn(spot.x, spot.y, spot.layer) then
            local _, _, dist = nearest_player(spot.x, spot.y, spot.layer)
            if dist >= SAFE_SPAWN then
                usable[#usable + 1] = spot
            end
        end
    end

    local wanted = math.min(#usable, options.max_per_level)
    if wanted < 1 then
        return
    end

    local first = prng:random_index(#BOOS, PRNG_CLASS.PROCEDURAL_SPAWNS) or 1
    local step = #usable / wanted
    for i = 1, wanted do
        local spot = usable[math.floor((i - 1) * step) + 1]
        make_boo(spot.x, spot.y, spot.layer, ((first + made) % #BOOS) + 1)
        made = made + 1
    end
end, ON.POST_LEVEL_GENERATION)
