meta.name = "Poison Run"
meta.version = "1"
meta.description = "You're always poisoned. Can you survive?"
meta.author = "garebear"

register_option_int(
    "poison_ticks",
    "Number of game ticks until you're damaged from poison.",
    1800,
    0, 18000
)

set_callback(function()
    for i, player in ipairs(players) do
        if player.health ~= 0 then
            player:poison(-1)
        end
    end
end, ON.LEVEL)

set_callback(function()
    for i, player in ipairs(players) do
        if player.health ~= 0 and not player:is_poisoned() then
            player:poison(options.poison_ticks)
        end
    end
end, ON.FRAME)
