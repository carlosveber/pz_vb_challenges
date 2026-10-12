-- VB_Challenges: sound effects.
-- Played as UI sounds (non-positional), so they never attract real zombies.
require "VB_Challenges_Shared"

VB_Challenges.Sounds = VB_Challenges.Sounds or {}

local LEVEL_UP = "UIAchievement"

local queue = {} -- { at = ms, name = sound }

function VB_Challenges.Sounds.isEnabled()
    local opts = VB_Challenges.UI and VB_Challenges.UI.options
    local opt = opts and opts:getOption("playSounds")
    if opt then return opt:getValue() ~= false end
    return true
end

local function playNow(name)
    pcall(function() getSoundManager():playUISound(name) end)
end

local function schedule(name, delayMs)
    if not VB_Challenges.Sounds.isEnabled() then return end
    if not delayMs or delayMs <= 0 then
        playNow(name)
    else
        table.insert(queue, { at = getTimestampMs() + delayMs, name = name })
    end
end

function VB_Challenges.Sounds.levelUp(delayMs)
    schedule(LEVEL_UP, delayMs)
end

Events.OnTick.Add(function()
    if #queue == 0 then return end
    local t = getTimestampMs()
    for i = #queue, 1, -1 do
        if t >= queue[i].at then
            playNow(table.remove(queue, i).name)
        end
    end
end)
