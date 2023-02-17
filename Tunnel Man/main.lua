---@diagnostic disable-next-line: lowercase-global
meta = {
    name = "Tunnel Man",
    version = "0.1",
    description = "Makes the Spelunker behave like Tunnel Man from Spelunky Classic.",
    author = 'garebear',
}

set_callback(function()
    local player = get_player(1, false)
    if player then
        player.health = 2
        player.inventory.bombs = 0
        player.inventory.ropes = 0
    end
end, ON.START)

set_pre_entity_spawn(function(entity_type, x, y, layer, overlay, spawn_flags)
    local player = get_player(1, false)
    if player.standing_on_uid > -1 then
        local uid = spawn_entity(ENT_TYPE.ITEM_MATTOCK, x, y, layer, 0, 0)
        local ent = get_entity(uid)
        ent.user_data = { whip = true }
        if player then
            player:pick_up(ent)
        end
        return uid
    end
end, SPAWN_TYPE.ANY, MASK.ITEM, ENT_TYPE.ITEM_WHIP)

set_post_entity_spawn(function(ent, spawn_flags)
    ent:destroy()
end, SPAWN_TYPE.ANY, MASK.ITEM, ENT_TYPE.ITEM_WHIP)

set_callback(function()
    local player = get_player(1, false)
    if player then
        local held_ent = player:get_held_entity()
        if held_ent and held_ent.type.id == ENT_TYPE.ITEM_MATTOCK and player.state ~= CHAR_STATE.ATTACKING and held_ent.user_data and held_ent.user_data.whip then
            player:drop(held_ent)
            held_ent:destroy()
        end
    end
end, ON.GAMEFRAME)
