meta.name = "Sushilotl"
meta.version = "0.1"
meta.description = "Replaces all Axolotl with Sushi"
meta.author = "garebear"


local SUSHI_TEXTURE_ID = nil
do
    local texture_def = get_texture_definition(TEXTURE.DATA_TEXTURES_ITEMS_0)
    texture_def.texture_path = "sushilotl.png"
    SUSHI_TEXTURE_ID = define_texture(texture_def)
end

set_pre_entity_spawn(function(ent_type, x, y, l, overlay)
    local uid = spawn(ENT_TYPE.ITEM_PICKUP_COOKEDTURKEY, x, y, l, 0, 0)
	local entity = get_entity(uid)
	entity:set_texture(SUSHI_TEXTURE_ID)
	return uid
end, SPAWN_TYPE.ANY, 0, ENT_TYPE.MOUNT_AXOLOTL)