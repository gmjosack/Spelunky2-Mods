---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Sloffy",
    version = "0.1",
    description = "Front facing Sloffy, a slime Roffy. Entry for Spelunky Mod Jam 8.",
    author = "garebear",
}

local SLOFFY_BASE = ENT_TYPE.MONS_FROG

local SLOFFY_TEXTURE
do
    local texture_def = get_texture_definition(TEXTURE.DATA_TEXTURES_MONSTERS03_0)
    texture_def.texture_path = "sloffy.png"
    texture_def.width, texture_def.height = 85, 85
    texture_def.tile_width, texture_def.tile_height = 85, 85
    texture_def.sub_image_offset_x, texture_def.sub_image_offset_y = 0, 0
    texture_def.sub_image_width, texture_def.sub_image_height = 0, 0
    SLOFFY_TEXTURE = define_texture(texture_def)
end

local SIZES = { 1.4, 1.0, 0.7 }
local JUMPS = { 0.95, 1.1, 1.3 }

local FROG_HITBOX_X = 0.32
local FROG_HITBOX_Y = 0.35
local FROG_OFFSET_Y = -0.1

local SPLIT_VX = 0.06
local SPLIT_VY = 0.09

local IDLE_AMOUNT = 0.05
local IDLE_SPEED = 0.08
local WINDUP_FRAMES = 14
local WINDUP_SQUASH = 0.3
local AIR_STRETCH = 1.2
local MAX_STRETCH = 0.35
local IMPACT_SQUASH = 0.35
local IMPACT_DECAY = 0.09
local SQUASH_MIN = 0.55
local SQUASH_MAX = 1.5

local AREAS = {
    { key = "dwelling",    theme = THEME.DWELLING,     name = "Dwelling",    on = true },
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
    register_option_bool(option, "Spawn in " .. area.name, "", area.on == true)
    AREA_OPTION[area.theme] = option
end

register_option_int("rarity", "Rarity",
    "Roughly one Sloffy per this many valid spots in a level. Lower means more of them.", 45, 10, 400)

local splits = {}

local function clamp(n, low, high)
    return math.min(math.max(n, low), high)
end

local function sloffy_data(ent)
    local data = ent.user_data
    if type(data) == "table" and data.sloffy then
        return data
    end
    return nil
end

---@param ent Frog
local function shape(ent)
    local data = sloffy_data(ent)
    if not data then
        return
    end

    data.tick = data.tick + 1
    ent.animation_frame = 0

    local grounded = ent.standing_on_uid > -1
    if grounded and data.airborne then
        data.impact = 1.0
    end
    data.airborne = not grounded

    local scale
    if grounded then
        local windup = 0.0
        if ent.jump_timer > 0 and ent.jump_timer <= WINDUP_FRAMES then
            windup = (WINDUP_FRAMES - ent.jump_timer) / WINDUP_FRAMES
        end
        scale = 1.0
            - windup * WINDUP_SQUASH
            - data.impact * IMPACT_SQUASH
            + math.sin(data.tick * IDLE_SPEED) * IDLE_AMOUNT
        data.impact = math.max(0.0, data.impact - IMPACT_DECAY)
    else
        scale = 1.0 + math.min(math.abs(ent.velocityy) * AIR_STRETCH, MAX_STRETCH)
    end
    scale = clamp(scale, SQUASH_MIN, SQUASH_MAX)

    local size = SIZES[data.size]
    local height = size * scale
    ent.height = height
    ent.width = size / scale

    local lift = (size - height) * 0.5
    ent.y = ent.y - (lift - data.lift)
    ent.offsety = FROG_OFFSET_Y * size + lift
    data.lift = lift
end

local function split_later(ent)
    local data = sloffy_data(ent)
    if not data or data.dead then
        return
    end
    data.dead = true

    if data.size >= #SIZES then
        return
    end

    local x, y, layer = get_position(ent.uid)
    splits[#splits + 1] = { size = data.size + 1, x = x, y = y, layer = layer }
end

local function make_sloffy(uid, index)
    local ent = get_entity(uid) --[[@as Movable]]
    if not ent then
        return nil
    end

    local size = SIZES[index]
    ent:set_texture(SLOFFY_TEXTURE)
    ent.animation_frame = 0
    ent.width, ent.height = size, size
    ent.hitboxx, ent.hitboxy = FROG_HITBOX_X * size, FROG_HITBOX_Y * size
    ent.offsetx, ent.offsety = 0.0, FROG_OFFSET_Y * size
    ent.jump_height_multiplier = JUMPS[index]
    ent.user_data = {
        sloffy = true,
        size = index,
        tick = 0,
        lift = 0.0,
        impact = 0.0,
        airborne = false,
        dead = false,
    }

    ent:set_post_update_state_machine(shape)
    ent:set_post_kill(split_later)

    return ent
end

local function spawn_sloffy(x, y, layer)
    make_sloffy(spawn_entity(SLOFFY_BASE, x, y, layer, 0, 0), 1)
end

---@diagnostic disable-next-line: param-type-mismatch
local SLOFFY_CHANCE = define_procedural_spawn("sloffy", spawn_sloffy, nil)

set_callback(function(room_gen_ctx)
    local option = AREA_OPTION[state.theme]
    local chance = 0
    if option and options[option] then
        chance = options.rarity
    end
    room_gen_ctx:set_procedural_spawn_chance(SLOFFY_CHANCE, chance)
end, ON.POST_ROOM_GENERATION)

set_callback(function()
    if #splits == 0 then
        return
    end

    local queued = splits
    splits = {}

    if state.screen ~= SCREEN.LEVEL then
        return
    end

    for _, split in ipairs(queued) do
        for dir = -1, 1, 2 do
            local uid = spawn_entity(SLOFFY_BASE, split.x, split.y, split.layer, dir * SPLIT_VX, SPLIT_VY)
            make_sloffy(uid, split.size)
        end
    end
end, ON.GAMEFRAME)

set_callback(function()
    splits = {}
end, ON.PRE_LEVEL_GENERATION)
