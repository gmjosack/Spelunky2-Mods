meta.name = "Poison Run"
meta.version = "1.1"
meta.description = "You're always poisoned. Can you survive?"
meta.author = "garebear"

register_option_int(
    "poison_ticks",
    "Number of game ticks until you're damaged from poison.",
    1800,
    0,
    18000
)


DEBUG = false

function debug(msg)
    if DEBUG then
        message(tostring(msg))
    end
end


function clear_poison()
    for i, player in ipairs(players) do
        if player.health ~= 0 and player:is_poisoned() then
            debug("Clearing poison on player " .. tostring(i))
            player:poison(-1)
        end
    end
end


function set_poison()
    for i, player in ipairs(players) do
        if player.health ~= 0 and not player:is_poisoned() then
            debug("Setting poison on player " .. tostring(i))
            player:poison(options.poison_ticks)
        end
    end 
end


function increment_health()
    for i, player in ipairs(players) do
        if player.health ~= 0 then
            debug("Giving health to player " .. tostring(i))
            player.health = player.health + 1
        end
    end 
end


function pets_saved()
    saved = state.saved_dogs + state.saved_cats + state.saved_hamsters
    debug("Pets saved: " .. tostring(saved))
    return saved
end


LAST_PETS_SAVED = 0

set_callback(function()
    debug("Starting new run")
    LAST_PETS_SAVED = 0
end, ON.START)


set_callback(function()
    current_saved = pets_saved()
    if current_saved > LAST_PETS_SAVED then
        increment_health()
    end
    LAST_PETS_SAVED = current_saved
end, ON.TRANSITION)


set_callback(function()
    clear_poison()
end, ON.LEVEL)


set_callback(function()
    set_poison()
end, ON.FRAME)
