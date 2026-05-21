---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Warptank",
    version = "0.1",
    description = "Warptank controls for Spelunky 2. Entry for Monthly Spelunky Mod Jam 5.",
    author = "garebear",
}

local FACE = { FLOOR = 0, RIGHT_WALL = 1, CEILING = 2, LEFT_WALL = 3 }

local FACE_DOWN = {
    [FACE.FLOOR]      = { x = 0, y = -1 },
    [FACE.RIGHT_WALL] = { x = 1, y = 0 },
    [FACE.CEILING]    = { x = 0, y = 1 },
    [FACE.LEFT_WALL]  = { x = -1, y = 0 },
}

local FACE_ANGLE = {
    [FACE.FLOOR]      = 0,
    [FACE.RIGHT_WALL] = math.pi / 2,
    [FACE.CEILING]    = math.pi,
    [FACE.LEFT_WALL]  = -math.pi / 2,
}

local FACE_FORWARD = {
    [FACE.FLOOR]      = { x = 1, y = 0 },
    [FACE.RIGHT_WALL] = { x = 0, y = 1 },
    [FACE.CEILING]    = { x = -1, y = 0 },
    [FACE.LEFT_WALL]  = { x = 0, y = -1 },
}

local function opposite(face)
    return (face + 2) % 4
end

local function walk_key(wd)
    if wd.x == 1 then return "+x" end
    if wd.x == -1 then return "-x" end
    if wd.y == 1 then return "+y" end
    if wd.y == -1 then return "-y" end
end

local INSIDE_WRAP = {
    [FACE.FLOOR] = {
        ["+x"] = { face = FACE.RIGHT_WALL, x = 0, y = 1 },
        ["-x"] = { face = FACE.LEFT_WALL, x = 0, y = 1 },
    },
    [FACE.CEILING] = {
        ["+x"] = { face = FACE.RIGHT_WALL, x = 0, y = -1 },
        ["-x"] = { face = FACE.LEFT_WALL, x = 0, y = -1 },
    },
    [FACE.RIGHT_WALL] = {
        ["+y"] = { face = FACE.CEILING, x = -1, y = 0 },
        ["-y"] = { face = FACE.FLOOR, x = -1, y = 0 },
    },
    [FACE.LEFT_WALL] = {
        ["+y"] = { face = FACE.CEILING, x = 1, y = 0 },
        ["-y"] = { face = FACE.FLOOR, x = 1, y = 0 },
    },
}

local OUTSIDE_WRAP = {
    [FACE.FLOOR] = {
        ["+x"] = { face = FACE.LEFT_WALL, x = 0, y = -1 },
        ["-x"] = { face = FACE.RIGHT_WALL, x = 0, y = -1 },
    },
    [FACE.CEILING] = {
        ["+x"] = { face = FACE.LEFT_WALL, x = 0, y = 1 },
        ["-x"] = { face = FACE.RIGHT_WALL, x = 0, y = 1 },
    },
    [FACE.RIGHT_WALL] = {
        ["+y"] = { face = FACE.FLOOR, x = 1, y = 0 },
        ["-y"] = { face = FACE.CEILING, x = 1, y = 0 },
    },
    [FACE.LEFT_WALL] = {
        ["+y"] = { face = FACE.FLOOR, x = -1, y = 0 },
        ["-y"] = { face = FACE.CEILING, x = -1, y = 0 },
    },
}

local WALK_SPEED = 0.10
local WEB_SLOW_FACTOR = 0.25

local TOUCH_DIST = 0.45

local SOLID_MASK = MASK.FLOOR | MASK.ACTIVEFLOOR

local RAGDOLL_STATES = {
    [CHAR_STATE.DYING]    = true,
    [CHAR_STATE.STUNNED]  = true,
    [CHAR_STATE.FLAILING] = true,
}

local pstate = {}
local jump_hook_id = {}
local sm_hook_id = {}
local post_sm_hook_id = {}

local function entity_is_solid_for_warptank(ent)
    if (ent.type.search_flags & SOLID_MASK) == 0 then return false end
    if not test_flag(ent.flags, ENT_FLAG.SOLID) then return false end
    if test_flag(ent.flags, ENT_FLAG.IS_PLATFORM) then return false end
    if test_flag(ent.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT) then return false end
    return true
end

local function is_solid(x, y, layer)
    local uid = get_grid_entity_at(x, y, layer)
    if uid ~= -1 then
        local ent = get_entity(uid)
        if ent and entity_is_solid_for_warptank(ent) then return true end
    end
    local actives = get_entities_at(0, MASK.ACTIVEFLOOR, x, y, layer, 0.5)
    if actives then
        for _, auid in ipairs(actives) do
            local ent = get_entity(auid)
            if ent
                and not test_flag(ent.flags, ENT_FLAG.IS_PLATFORM)
                and not test_flag(ent.flags, ENT_FLAG.PASSES_THROUGH_OBJECTS)
                and not test_flag(ent.flags, ENT_FLAG.PASSES_THROUGH_PLAYER)
                and not test_flag(ent.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING) then
                return true
            end
        end
    end
    return false
end

local function scan_solid(px, py, dx, dy, layer)
    local cx, cy = math.floor(px + 0.5) + dx, math.floor(py + 0.5) + dy
    for _ = 1, 200 do
        if is_solid(cx, cy, layer) then return cx, cy end
        cx, cy = cx + dx, cy + dy
    end
end

local function active()
    return state.screen == SCREEN.LEVEL and state.theme ~= THEME.BASE_CAMP
end

local function held(p, flag)
    return test_flag(p.input.buttons, flag)
end

local ANIM_IDLE = 0

local function on_state_machine(p)
    if not active() then return end
    local ps = pstate[p.uid]
    if not ps or ps.ragdoll or ps.freefall then return end

    local d = FACE_DOWN[ps.face]
    local surface_tx = math.floor(p.x + 0.5) + d.x
    local surface_ty = math.floor(p.y + 0.5) + d.y
    local surface_uid = get_grid_entity_at(surface_tx, surface_ty, p.layer)
    if surface_uid and surface_uid ~= -1 then
        p.standing_on_uid = surface_uid
    end
    p.more_flags = clr_flag(p.more_flags, ENT_MORE_FLAG.FALLING)
    p.more_flags = set_flag(p.more_flags, ENT_MORE_FLAG.HIT_GROUND)
    p.falling_timer = 0
end

local function on_state_machine_post(p)
    if not active() then return end
    local ps = pstate[p.uid]
    if not ps or ps.ragdoll or ps.freefall then return end
    if ps.face == FACE.FLOOR then return end
    if not p.current_animation or not p.type or not p.type.animations then return end
    if p.current_animation.id ~= 2 then return end

    local idle = p.type.animations[ANIM_IDLE]
    if not idle then return end
    p.current_animation.id          = idle.id
    p.current_animation.first_tile  = idle.first_tile
    p.current_animation.num_tiles   = idle.num_tiles
    p.current_animation.interval    = idle.interval
    p.current_animation.repeat_mode = idle.repeat_mode
    p.animation_frame               = idle.first_tile
end

local function setup_player(p)
    p:set_gravity(0)
    if not jump_hook_id[p.uid] then
        jump_hook_id[p.uid] = p:set_pre_can_jump(function() return false end)
    end
    if not sm_hook_id[p.uid] then
        sm_hook_id[p.uid] = p:set_pre_update_state_machine(on_state_machine)
    end
    if not post_sm_hook_id[p.uid] then
        post_sm_hook_id[p.uid] = p:set_post_update_state_machine(on_state_machine_post)
    end
    if not pstate[p.uid] then
        pstate[p.uid] = { face = FACE.FLOOR, jump_armed = false, ragdoll = false, freefall = false }
    end
end

local function in_web(p)
    local uids = get_entities_at(ENT_TYPE.ITEM_WEB, MASK.ITEM, p.x, p.y, p.layer, 0.4)
    return uids and #uids > 0
end

local function input_still_held(p, wi)
    return wi ~= nil and held(p, wi.flag)
end

local function read_face_input(p, face)
    local d = FACE_DOWN[face]
    if d.x == 0 then
        if held(p, INPUT_FLAG.RIGHT) then return { flag = INPUT_FLAG.RIGHT }, { x = 1, y = 0 } end
        if held(p, INPUT_FLAG.LEFT) then return { flag = INPUT_FLAG.LEFT }, { x = -1, y = 0 } end
    else
        if held(p, INPUT_FLAG.UP) then return { flag = INPUT_FLAG.UP }, { x = 0, y = 1 } end
        if held(p, INPUT_FLAG.DOWN) then return { flag = INPUT_FLAG.DOWN }, { x = 0, y = -1 } end
    end
end

local function flip_face(p, ps)
    local d = FACE_DOWN[ps.face]
    local tx, ty = scan_solid(p.x, p.y, -d.x, -d.y, p.layer)
    if not tx then return end

    local start_x = math.floor(p.x + 0.5)
    local start_y = math.floor(p.y + 0.5)
    local target_x = tx + d.x
    local target_y = ty + d.y
    local step_x = -d.x
    local step_y = -d.y
    local trail = ps.trail_queue or {}
    local cx, cy = start_x, start_y
    while (cx ~= target_x or cy ~= target_y) and #trail < 200 do
        table.insert(trail, { x = cx, y = cy, layer = p.layer })
        cx = cx + step_x
        cy = cy + step_y
    end
    table.insert(trail, { x = target_x, y = target_y, layer = p.layer })
    ps.trail_queue = trail

    ps.face = opposite(ps.face)
    p.x = target_x
    p.y = target_y
    p.velocityx = 0
    p.velocityy = 0
    ps.walk_input = nil
    ps.walk_dir = nil
end

local function do_wrap(p, ps, entry, new_px, new_py)
    ps.face = entry.face
    ps.walk_dir = { x = entry.x, y = entry.y }
    p.x = new_px
    p.y = new_py
    p.velocityx = 0
    p.velocityy = 0
end

local function try_inside_wrap(p, ps, wd)
    local px_tile = math.floor(p.x + 0.5)
    local py_tile = math.floor(p.y + 0.5)
    local wall_tx = px_tile + wd.x
    local wall_ty = py_tile + wd.y
    if not is_solid(wall_tx, wall_ty, p.layer) then return false end

    local edge_x = wall_tx - wd.x * 0.5
    local edge_y = wall_ty - wd.y * 0.5
    local dist = (edge_x - p.x) * wd.x + (edge_y - p.y) * wd.y
    if dist > TOUCH_DIST then return false end

    local entry = INSIDE_WRAP[ps.face][walk_key(wd)]
    if not entry then return false end
    local nd = FACE_DOWN[entry.face]
    do_wrap(p, ps, entry, wall_tx - nd.x, wall_ty - nd.y)
    return true
end

local function try_outside_wrap(p, ps, wd)
    local d = FACE_DOWN[ps.face]
    local cur_sx = math.floor(p.x + 0.5) + d.x
    local cur_sy = math.floor(p.y + 0.5) + d.y
    if is_solid(cur_sx, cur_sy, p.layer) then return false end

    local entry = OUTSIDE_WRAP[ps.face][walk_key(wd)]
    if not entry then return false end
    local prev_sx = cur_sx - wd.x
    local prev_sy = cur_sy - wd.y
    do_wrap(p, ps, entry, prev_sx + wd.x, prev_sy + wd.y)
    return true
end

local function is_ragdolled(p)
    return RAGDOLL_STATES[p.state] or p.stun_timer > 0 or p.lock_input_timer > 0
end

local function snap_to_nearest_floor(p, ps)
    local tx, ty = scan_solid(p.x, p.y, 0, -1, p.layer)
    if not tx then return end
    ps.face = FACE.FLOOR
    p.x = tx
    p.y = ty + 1
    p.velocityx = 0
    p.velocityy = 0
end

local function rotate_overlay_offset(ent, angle)
    if angle == 0 then
        ent.angle = 0
        return
    end
    local ex, ey = ent.x, ent.y
    local c, s = math.cos(angle), math.sin(angle)
    ent.x = ex * c - ey * s
    ent.y = ex * s + ey * c
    ent.angle = angle
end

local function update(p, ps)
    if ps.trail_queue and #ps.trail_queue > 0 then
        local tile = table.remove(ps.trail_queue, 1)
        if tile then
            spawn_entity(ENT_TYPE.FX_TELEPORTSHADOW, tile.x, tile.y, tile.layer, 0, 0)
        end
    end

    if is_ragdolled(p) then
        if not ps.ragdoll then
            ps.ragdoll = true
            ps.face = FACE.FLOOR
            p.angle = 0
            p:reset_gravity()
        end
        return
    end

    if ps.ragdoll then
        ps.ragdoll = false
        ps.walk_input = nil
        ps.walk_dir = nil
        p:set_gravity(0)
        snap_to_nearest_floor(p, ps)
    end

    local d = FACE_DOWN[ps.face]
    local surface_tx = math.floor(p.x + 0.5) + d.x
    local surface_ty = math.floor(p.y + 0.5) + d.y
    if not is_solid(surface_tx, surface_ty, p.layer) and (not ps.walk_dir or (ps.walk_dir.x == 0 and ps.walk_dir.y == 0)) then
        if not ps.freefall then
            ps.freefall = true
            ps.face = FACE.FLOOR
            p.angle = 0
            p:reset_gravity()
            ps.walk_input = nil
            ps.walk_dir = nil
        end
        return
    end

    if ps.freefall then
        if p.state == CHAR_STATE.STANDING and p.standing_on_uid and p.standing_on_uid > 0 then
            ps.freefall = false
            p:set_gravity(0)
            snap_to_nearest_floor(p, ps)
        else
            return
        end
    end

    p:set_gravity(0)

    if not input_still_held(p, ps.walk_input) then
        ps.walk_input = nil
        ps.walk_dir = nil
        local wi, wd = read_face_input(p, ps.face)
        if wi then
            ps.walk_input = wi
            ps.walk_dir = wd
        end
    end

    local d = FACE_DOWN[ps.face]
    local wd = ps.walk_dir or { x = 0, y = 0 }

    if d.x ~= 0 then
        local tx = math.floor(p.x + 0.5) + d.x
        p.x = tx - d.x
    end
    if d.y ~= 0 then
        local ty = math.floor(p.y + 0.5) + d.y
        p.y = ty - d.y
    end

    local speed = WALK_SPEED
    if in_web(p) then speed = speed * WEB_SLOW_FACTOR end

    p.x = p.x + wd.x * speed
    p.y = p.y + wd.y * speed
    p.velocityx = 0
    p.velocityy = 0

    if wd.x ~= 0 or wd.y ~= 0 then
        if not try_inside_wrap(p, ps, wd) then
            try_outside_wrap(p, ps, wd)
        end
    end

    if not p:is_button_held(BUTTON.JUMP) then
        ps.jump_armed = true
    end
    if ps.jump_armed and p:is_button_pressed(BUTTON.JUMP) then
        ps.jump_armed = false
        flip_face(p, ps)
    end

    p.angle = FACE_ANGLE[ps.face]

    if wd.x ~= 0 or wd.y ~= 0 then
        local ff = FACE_FORWARD[ps.face]
        p:flip(wd.x * ff.x + wd.y * ff.y < 0)
    end

    local held_entity = p:get_held_entity()
    local current_uid = (held_entity and held_entity.uid and held_entity.uid > -1) and held_entity.uid or nil
    if ps.last_held_uid and ps.last_held_uid ~= current_uid then
        local prev = get_entity(ps.last_held_uid)
        if prev then prev.angle = 0 end
    end
    ps.last_held_uid = current_uid
    if held_entity and current_uid then
        rotate_overlay_offset(held_entity, FACE_ANGLE[ps.face])
    end

    local back_uid = p:worn_backitem()
    local current_back_uid = (back_uid and back_uid > -1) and back_uid or nil
    if ps.last_back_uid and ps.last_back_uid ~= current_back_uid then
        local prev = get_entity(ps.last_back_uid)
        if prev then prev.angle = 0 end
    end
    ps.last_back_uid = current_back_uid
    if current_back_uid then
        local back_ent = get_entity(current_back_uid)
        if back_ent then rotate_overlay_offset(back_ent, FACE_ANGLE[ps.face]) end
    end

    if ps.whip_uid then
        local whip = get_entity(ps.whip_uid)
        if not whip or not whip.overlay then
            ps.whip_uid = nil
            ps.whip_last_x = nil
            ps.whip_last_y = nil
        else
            local angle = FACE_ANGLE[ps.face]
            if angle ~= 0 and (whip.x ~= ps.whip_last_x or whip.y ~= ps.whip_last_y) then
                local wx, wy = whip.x, whip.y
                local c, s = math.cos(angle), math.sin(angle)
                whip.x = wx * c - wy * s
                whip.y = wx * s + wy * c
                ps.whip_last_x = whip.x
                ps.whip_last_y = whip.y
            end
            whip.angle = angle
        end
    end
end

set_callback(function()
    pstate = {}
    jump_hook_id = {}
    sm_hook_id = {}
    post_sm_hook_id = {}
end, ON.PRE_LEVEL_GENERATION)

set_post_entity_spawn(function(ent, spawn_flags)
        if state.theme == THEME.BASE_CAMP then return end
        ent:destroy()
    end, SPAWN_TYPE.LEVEL_GEN, MASK.ANY,
    ENT_TYPE.FLOOR_LADDER,
    ENT_TYPE.FLOOR_LADDER_PLATFORM,
    ENT_TYPE.FLOOR_PLATFORM,
    ENT_TYPE.ACTIVEFLOOR_PUSHBLOCK,
    ENT_TYPE.ACTIVEFLOOR_CHAINEDPUSHBLOCK)

set_post_entity_spawn(function(ent, spawn_flags)
    if not active() then return end
    local nearest_p, best_d = nil, math.huge
    for _, p in pairs(players) do
        local dx, dy = p.x - ent.x, p.y - ent.y
        local d = dx * dx + dy * dy
        if d < best_d then
            best_d = d
            nearest_p = p
        end
    end
    if not nearest_p then return end
    local ps = pstate[nearest_p.uid]
    if not ps then return end
    ps.whip_uid = ent.uid
    ps.whip_last_x = nil
    ps.whip_last_y = nil
end, SPAWN_TYPE.ANY, MASK.ITEM, ENT_TYPE.ITEM_WHIP)

set_callback(function()
    if not active() then return end
    for _, p in pairs(players) do
        setup_player(p)
    end
end, ON.LEVEL)

set_callback(function()
    if not active() then return end
    for _, p in pairs(players) do
        if not jump_hook_id[p.uid] then setup_player(p) end
        update(p, pstate[p.uid])
    end
end, ON.GAMEFRAME)
