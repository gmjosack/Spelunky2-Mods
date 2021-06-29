-- This script is adapted from https://spelunky.fyi/mods/m/bat-frend/
-- by Trixelized. Thanks Trix!

meta.name = "Minimoose Frend"
meta.version = "0.1"
meta.description = "The ultimate tool of destruction"
meta.author = "garebear"


GHOST_ID = nil
PLAYER_PREVX = nil
PLAYER_PREVY = nil
TICK = 0


local MINIMOOSE_TEXTURE_ID = nil
do
    local texture_def = get_texture_definition(TEXTURE.DATA_TEXTURES_ITEMS_0)
    texture_def.texture_path = "items-minimoose.png"
    MINIMOOSE_TEXTURE_ID = define_texture(texture_def)
end


function sspring(val, valsp, tar, tension, damping)
    local spd_to_add = (tension * (tar - val)) - (damping * valsp)
    valsp = valsp + spd_to_add

    result = {val + valsp, valsp}

    return result
end


function cclamp(n, low, high)
	return math.min(math.max(n, low), high)
end

function is_good_screen()
	return state.screen == 11 or state.screen == 12 or state.screen == 14
end


function initialize_friend_for_player(player)
	local x, y, l = get_position(player.uid)
		
	PLAYER_PREVX = x
	PLAYER_PREVY = y
	
	GHOST_ID = spawn(ENT_TYPE.ITEM_ROCK, x, y, l, 0, 0)
	local ghost = get_entity(GHOST_ID):as_movable()
	ghost:set_texture(MINIMOOSE_TEXTURE_ID)
	ghost.flags = set_flag(ghost.flags, 28)
end

function initialize_the_friend()
	if not is_good_screen() then
		return
	end

	GHOST_ID = nil
	TICK = 0

	local player = players[1]
	if player == nil then
		return
	end

	initialize_friend_for_player(player)
end
	

set_callback(initialize_the_friend, ON.TRANSITION)
set_callback(initialize_the_friend, ON.LEVEL)
set_callback(initialize_the_friend, ON.CAMP)


set_callback(function()
	if not is_good_screen() then
		return
	end
	
	TICK = TICK + 1

	local player = players[1]
	if player == nil then
		return
	end

	if GHOST_ID == nil then
		return
	end
	
	local x, y, l = get_position(player.uid)
	local p_facing = test_flag(player.flags, 17)
	
	local ghost = get_entity(GHOST_ID):as_movable()
	
	local prev_x = PLAYER_PREVX
	local new_x = x

	local prev_y = PLAYER_PREVY
	local new_y = y
	
	local xmin, ymin, xmax, ymax = get_bounds()
	local bsize_x = xmax - xmin
	local bsize_y = ymin - ymax
	
	if prev_x > xmax - 5 and new_x < xmin + 5 then
		ghost.x = ghost.x - bsize_x
	end
	
	if prev_x < xmin + 5 and new_x > xmax - 5 then
		ghost.x = ghost.x + bsize_x
	end
	
	if prev_y > ymin - 5 and new_y < ymax + 5 then
		ghost.y = _ghost.y - bsize_y
	end
	
	if prev_y < ymax + 5 and new_y > ymin - 5 then
		ghost.y = ghost.y + bsize_y
	end
	
	PLAYER_PREVX = x
	PLAYER_PREVY = y
	
	local xtar = math.sin(TICK / 30) * 0.8
	local ytar = math.cos(TICK / 12) * 0.2 + player.movey * 0.5
	
	if p_facing then
		xtar = xtar + x + 1
	else
		xtar = xtar + x - 1
	end
	
	ytar = ytar + y + 0.5
	
	local spx = sspring(ghost.x, ghost.velocityx, xtar, 0.02, 0.1)
	ghost.x = spx[1]
	ghost.velocityx = spx[2]
	
	local spy = sspring(ghost.y, ghost.velocityy, ytar, 0.02, 0.1)
	ghost.y = spy[1]
	ghost.velocityy = spy[2]
	
	local maxsp = 0.08
	ghost.velocityx = cclamp(ghost.velocityx, -maxsp, maxsp)
	ghost.velocityy = cclamp(ghost.velocityy, -maxsp, maxsp)
	
	ghost.animation_frame = 86 + math.floor(TICK / 2) % 6
	
	if ghost.velocityx >= 0 then
		ghost.width = 1.25
		ghost.height = 1.25
		ghost.angle = ghost.velocityy * 5
	else
		ghost.width = -1.25
		ghost.height = 1.25
		ghost.angle = -ghost.velocityy * 5
	end
end, ON.FRAME)
