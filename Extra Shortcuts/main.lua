meta.name = "Extra Shortcuts"
meta.version = "0.1"
meta.description = "Spawns extra shortcuts to help with testing"
meta.author = "garebear"

function spawn_shortcut_door(x, y, world, level, theme, texture)
    spawn_door(x, y, LAYER.FRONT, world, level, theme)
    local uid = spawn(ENT_TYPE.BG_DOOR, x, y, LAYER.FRONT, 0, 0)
    local entity = get_entity(uid)
    unlock_door_at(x, y)
    if texture ~= nil then
        entity:set_texture(texture)
    end
end


set_callback(function()
    spawn_shortcut_door(38, 91, 2, 1, THEME.JUNGLE, TEXTURE.DATA_TEXTURES_FLOOR_JUNGLE_1)
    spawn_shortcut_door(40, 91, 2, 1, THEME.VOLCANA, TEXTURE.DATA_TEXTURES_FLOOR_VOLCANO_2)
    --goes to shortcut, figure it out later
    --spawn_shortcut_door(42, 91, 3, 1, THEME.OLMEC, TEXTURE.DATA_TEXTURES_DECO_JUNGLE_2)
    spawn_shortcut_door(44, 91, 4, 1, THEME.TIDE_POOL, TEXTURE.DATA_TEXTURES_FLOOR_TIDEPOOL_3)
    spawn_shortcut_door(46, 91, 4, 1, THEME.TEMPLE, TEXTURE.DATA_TEXTURES_FLOOR_TEMPLE_1)
    spawn_shortcut_door(39, 88, 6, 1, THEME.NEO_BABYLON, TEXTURE.DATA_TEXTURES_FLOOR_BABYLON_1)
    spawn_shortcut_door(41, 88, 6, 4, THEME.TIAMAT, TEXTURE.DATA_TEXTURES_FLOOR_BABYLON_1)
    spawn_shortcut_door(43, 88, 7, 1, THEME.SUNKEN_CITY, TEXTURE.DATA_TEXTURES_FLOOR_SUNKEN_3)
    spawn_shortcut_door(45, 88, 7, 4, THEME.HUNDUN, TEXTURE.DATA_TEXTURES_FLOOR_SUNKEN_3)
end, ON.CAMP)
