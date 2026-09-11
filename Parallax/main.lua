---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Parallax",
    version = "0.1",
    description = "The walls are shifting...",
    author = "garebear",
}

local BACKWALL = ENT_TYPE.BG_LEVEL_BACKWALL
local DECO = ENT_TYPE.BG_LEVEL_DECO

local WALL_TILES = 4.0
local CUT = 3.0

local WHITE = Color:new(1.0, 1.0, 1.0, 1.0)

register_option_int("drift", "Drift",
    "How far the wall lags behind the camera. 0 is vanilla, 100 locks to the camera.", 30, 0, 100)

register_option_int("vertical", "Vertical drift",
    "Percent of drift applied to vertical camera movement.", 60, 0, 100)

local wall = {}
local deco = {}
local anchor_x, anchor_y
local last_x, last_y

local function parallaxed()
    return state.theme ~= THEME.BASE_CAMP
end

local function shift()
    if not anchor_x then
        return 0.0, 0.0
    end

    local cx, cy = get_camera_position()
    local k = options.drift / 100.0
    return (cx - anchor_x) * k,
        (cy - anchor_y) * k * options.vertical / 100.0
end

local function forget()
    wall = {}
    deco = {}
    anchor_x, anchor_y = nil, nil
    last_x, last_y = nil, nil
end

set_post_entity_spawn(function(ent)
    if parallaxed() then
        ent:set_invisible(true)
    end
end, SPAWN_TYPE.ANY, MASK.ANY, BACKWALL)

local function remember_deco(ent)
    local w, h = ent.width, ent.height
    if w <= 0.0 or h <= 0.0 then
        w, h = ent.type.width, ent.type.height
    end

    local texture = ent:get_texture()
    local def = get_texture_definition(texture)
    local per_row = math.max(1, math.floor(def.width / def.tile_width))
    local frame = ent.animation_frame

    deco[#deco + 1] = {
        x = ent.x,
        y = ent.y,
        hw = w / 2.0,
        hh = h / 2.0,
        layer = ent.layer,
        texture = texture,
        shader = ent.rendering_info.shader,
        row = math.floor(frame / per_row),
        col = frame % per_row,
    }

    ent:set_invisible(true)
end

set_callback(function()
    forget()
    if not parallaxed() then
        return
    end

    for _, uid in ipairs(get_entities_by(BACKWALL, MASK.ANY, LAYER.BOTH)) do
        local ent = get_entity(uid)
        if ent and not wall[ent.layer] then
            wall[ent.layer] = {
                texture = ent:get_texture(),
                shader = ent.rendering_info.shader,
                depth = ent.draw_depth,
            }
        end
    end

    for _, uid in ipairs(get_entities_by(DECO, MASK.ANY, LAYER.BOTH)) do
        local ent = get_entity(uid)
        if ent then
            remember_deco(ent)
        end
    end
end, ON.POST_LEVEL_GENERATION)

set_callback(forget, ON.PRE_LEVEL_GENERATION)
set_callback(forget, ON.RESET)

set_callback(function()
    if not next(wall) then
        return
    end

    local cx, cy = get_camera_position()

    if not anchor_x then
        anchor_x, anchor_y = cx, cy
        last_x, last_y = cx, cy
    elseif math.abs(cx - last_x) > CUT or math.abs(cy - last_y) > CUT then
        anchor_x = anchor_x + (cx - last_x)
        anchor_y = anchor_y + (cy - last_y)
    end
    last_x, last_y = cx, cy
end, ON.GAMEFRAME)

set_callback(function(ctx, draw_depth)
    local layer = wall[state.camera_layer]
    if not layer or draw_depth ~= layer.depth then
        return
    end

    local view = ctx.bounding_box
    local shift_x, shift_y = shift()

    local x = math.floor((view.left - shift_x) / WALL_TILES) * WALL_TILES + shift_x
    local first_y = math.floor((view.bottom - shift_y) / WALL_TILES) * WALL_TILES + shift_y

    while x < view.right do
        local y = first_y
        while y < view.top do
            ctx:draw_world_texture(layer.texture, 0, 0,
                Quad:new(AABB:new(x, y + WALL_TILES, x + WALL_TILES, y)), WHITE, layer.shader)
            y = y + WALL_TILES
        end
        x = x + WALL_TILES
    end

    for _, d in ipairs(deco) do
        if d.layer == state.camera_layer then
            local dx = d.x + shift_x
            local dy = d.y + shift_y
            if dx + d.hw > view.left and dx - d.hw < view.right
                and dy + d.hh > view.bottom and dy - d.hh < view.top then
                ctx:draw_world_texture(d.texture, d.row, d.col,
                    Quad:new(AABB:new(dx - d.hw, dy + d.hh, dx + d.hw, dy - d.hh)), WHITE, d.shader)
            end
        end
    end
end, ON.RENDER_PRE_DRAW_DEPTH)
