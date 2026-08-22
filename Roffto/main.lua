---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Roffto",
    version = "0.2",
    description = "Phanto dons a Roffy mask as he haunts the caves. Entry for Spelunky Mod Jam 8.",
    author = "garebear",
}

local ROFFTO_BASE = ENT_TYPE.MONS_GHOST_SMALL_ANGRY

local function load_texture(path, size)
    local texture_def = get_texture_definition(TEXTURE.DATA_TEXTURES_MONSTERS_GHOST_0)
    texture_def.texture_path = path
    texture_def.width, texture_def.height = size, size
    texture_def.tile_width, texture_def.tile_height = size, size
    texture_def.sub_image_offset_x, texture_def.sub_image_offset_y = 0, 0
    texture_def.sub_image_width, texture_def.sub_image_height = 0, 0
    return define_texture(texture_def)
end

local BEETLE_TEXTURE = load_texture("beetle_guard.png", 128)
local ROFFY_TEXTURE = load_texture("roffto.png", 85)

local function roffto_texture()
    if options.roffy then
        return ROFFY_TEXTURE
    end
    return BEETLE_TEXTURE
end

local WHITE = Color:white()

local KEYS = {
    [ENT_TYPE.ITEM_KEY] = true,
    [ENT_TYPE.ITEM_LOCKEDCHEST_KEY] = true,
}

local SPRITE_SIZE = 1.0
local HITBOX = 0.25
local HOVER_ABOVE = 0.35
local DRAG = 0.994

local SWOOP_BOOST = 2.4
local SWOOP_FAR = 18.0
local SWOOP_NEAR = 8.0

local SPAWN_MARGIN = 4.0
local SPAWN_ABOVE = 3.0

local FLEE_ACCEL = 0.015
local FLEE_TIMEOUT = 600
local FLEE_DISTANCE = 18.0

local TILT = 1.6
local BOB_AMOUNT = 0.045
local BOB_SPEED = 0.11

local SPEED = 0.09
local TURN = 0.005

register_option_bool("hard", "Hard Mode", "Roffto hunts you for carrying anything at all, not just a key.", false)
register_option_bool("roffy", "Roffy Mode", "Swap the beetle guard back to the original Roffy mask sprite.", false)

local roffto = {
    uid = nil,
    x = 0.0,
    y = 0.0,
    vx = 0.0,
    vy = 0.0,
    angle = 0.0,
    tick = 0,
    fleeing = false,
    roffy = false,
    flee_timer = 0,
    flee_x = 0.0,
    flee_y = 0.0,
}

local function clamp(n, low, high)
    return math.min(math.max(n, low), high)
end

local function forget_roffto()
    roffto.uid = nil
    roffto.vx, roffto.vy = 0.0, 0.0
    roffto.angle = 0.0
    roffto.tick = 0
    roffto.fleeing = false
end

local function hunted_player()
    for _, player in pairs(players) do
        if player.health > 0 then
            local held = player:get_held_entity()
            if held and (options.hard or KEYS[held.type.id]) then
                return player
            end
        end
    end
    return nil
end

local function live_roffto()
    if not roffto.uid then
        return nil
    end
    local ent = get_entity(roffto.uid)
    if not ent or ent.type.id ~= ROFFTO_BASE or type(ent.user_data) ~= "table" or not ent.user_data.roffto then
        forget_roffto()
        return nil
    end
    return ent
end

local function place(ent)
    ent.x = roffto.x
    ent.y = roffto.y + math.sin(roffto.tick * BOB_SPEED) * BOB_AMOUNT
    ent.velocityx, ent.velocityy = 0.0, 0.0
    ent.angle = roffto.angle
    ent.animation_frame = 0
    ent.color = WHITE
    ent.rendering_info.shader = WORLD_SHADER.DEFERRED_TEXTURE_COLOR
end

local function view_half_width()
    local per_tile = math.abs(screen_distance(1.0))
    if per_tile < 0.0001 then
        return 11.0
    end
    return 1.0 / per_tile
end

local function spawn_roffto(target)
    local _, py, layer = get_position(target.uid)
    local cx = get_camera_position()
    local left, top, right, bottom = get_bounds()


    local side = (cx - left) > (right - cx) and -1 or 1

    local x = cx + side * (view_half_width() + SPAWN_MARGIN)
    local y = clamp(py + SPAWN_ABOVE, bottom, top)

    local uid = spawn_entity(ROFFTO_BASE, x, y, layer, 0, 0)
    local ent = get_entity(uid)
    if not ent then
        return nil
    end

    ent:set_texture(roffto_texture())
    ent.width, ent.height = SPRITE_SIZE, SPRITE_SIZE
    ent.hitboxx, ent.hitboxy = HITBOX, HITBOX
    ent.offsetx, ent.offsety = 0.0, 0.0
    ent.user_data = { roffto = true }

    roffto.uid = uid
    roffto.x, roffto.y = x, y
    roffto.vx, roffto.vy = -side * SPEED, 0.0
    roffto.angle = 0.0
    roffto.tick = 0
    roffto.fleeing = false
    roffto.roffy = options.roffy

    place(ent)
    ent:set_post_update_state_machine(place)

    return ent
end

local function fly(ent)
    roffto.x = roffto.x + roffto.vx
    roffto.y = roffto.y + roffto.vy
    roffto.angle = clamp(-roffto.vx * TILT, -0.5, 0.5)
    place(ent)
end

local function cap_speed(limit)
    local speed = math.sqrt(roffto.vx * roffto.vx + roffto.vy * roffto.vy)
    if speed > limit then
        roffto.vx = roffto.vx / speed * limit
        roffto.vy = roffto.vy / speed * limit
    end
end

local function chase(ent, target)
    local tx, ty = get_position(target.uid)
    local dx, dy = tx - roffto.x, (ty + HOVER_ABOVE) - roffto.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > 0.01 then
        roffto.vx = roffto.vx + dx / dist * TURN
        roffto.vy = roffto.vy + dy / dist * TURN
    end
    roffto.vx = roffto.vx * DRAG
    roffto.vy = roffto.vy * DRAG

    local swoop = clamp((dist - SWOOP_NEAR) / (SWOOP_FAR - SWOOP_NEAR), 0.0, 1.0)
    cap_speed(SPEED * (1.0 + (SWOOP_BOOST - 1.0) * swoop))

    if ent.layer ~= target.layer then
        ent:set_layer(target.layer)
    end

    fly(ent)
end

local function start_fleeing()
    roffto.fleeing = true
    roffto.flee_timer = FLEE_TIMEOUT
    roffto.flee_x, roffto.flee_y = 0.0, 1.0

    local nearest_x, nearest_y, nearest_dist
    for _, player in pairs(players) do
        local px, py = get_position(player.uid)
        local dx, dy = roffto.x - px, roffto.y - py
        local dist = dx * dx + dy * dy
        if not nearest_dist or dist < nearest_dist then
            nearest_x, nearest_y, nearest_dist = px, py, dist
        end
    end
    if nearest_dist and nearest_dist > 0.01 then
        local dist = math.sqrt(nearest_dist)
        roffto.flee_x = (roffto.x - nearest_x) / dist
        roffto.flee_y = (roffto.y - nearest_y) / dist + 0.7
    end
end

local function flee(ent)
    roffto.flee_timer = roffto.flee_timer - 1

    roffto.vx = roffto.vx + roffto.flee_x * FLEE_ACCEL
    roffto.vy = roffto.vy + roffto.flee_y * FLEE_ACCEL
    cap_speed(SPEED)
    fly(ent)

    if roffto.flee_timer <= 0 then
        ent:destroy()
        forget_roffto()
        return
    end

    for _, player in pairs(players) do
        local px, py = get_position(player.uid)
        local dx, dy = roffto.x - px, roffto.y - py
        if math.sqrt(dx * dx + dy * dy) < FLEE_DISTANCE then
            return
        end
    end
    ent:destroy()
    forget_roffto()
end

local function in_play()
    return state.screen == SCREEN.LEVEL
end

set_callback(function()
    if not in_play() then
        return
    end

    local ent = live_roffto()
    local target = hunted_player()

    if not ent then
        if not target then
            return
        end
        ent = spawn_roffto(target)
        if not ent then
            return
        end
    end

    roffto.tick = roffto.tick + 1

    if roffto.roffy ~= options.roffy then
        roffto.roffy = options.roffy
        ent:set_texture(roffto_texture())
    end

    if target then
        roffto.fleeing = false
        chase(ent, target)
    else
        if not roffto.fleeing then
            start_fleeing()
        end
        flee(ent)
    end
end, ON.GAMEFRAME)

set_callback(forget_roffto, ON.START)
set_callback(forget_roffto, ON.RESET)
set_callback(forget_roffto, ON.CAMP)
set_callback(forget_roffto, ON.LEVEL)
set_callback(forget_roffto, ON.TRANSITION)
