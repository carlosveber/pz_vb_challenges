-- VB_Challenges: optional risk modifiers chosen when accepting a quest.
-- Each one adds a points bonus (sandbox: ModifierBonusPercent); breaking one fails the quest.
require "VB_Challenges_Shared"

-- Bonus per modifier, the max per quest and deadline lengths are sandbox options
-- (see VB_Challenges.modifierBonus / VB_Challenges.maxModifiers / VB_Challenges.deadlineDays).

-- Night window used by "Only at night" (same as the night-kill quests).
function VB_Challenges.isNight()
    local h = getGameTime():getHour()
    return h >= 21 or h < 5
end

VB_Challenges.Modifiers = {
    {
        id = "nofirearms",
        describe = function(q) return VB_Challenges.T("ModDesc_nofirearms") end,
        -- Only meaningful on kill quests (and not the firearm-kill quest, which needs guns).
        applies = function(q) return q.type == "kill" or q.type == "kill_night" end,
    },
    {
        id = "night",
        describe = function(q)
            if q.type == "kill" then return VB_Challenges.T("ModDesc_night_kill") end
            return VB_Challenges.T("ModDesc_night_location")
        end,
        applies = function(q)
            return q.type == "kill" or q.type == "visit" or q.type == "roundtrip"
        end,
    },
    {
        id = "deadline",
        describe = function(q)
            return VB_Challenges.T("ModDesc_deadline", VB_Challenges.deadlineDays(q.difficulty))
        end,
        applies = function(q) return q.type ~= "survive" end,
    },
}

VB_Challenges.ModifierById = {}
for _, m in ipairs(VB_Challenges.Modifiers) do VB_Challenges.ModifierById[m.id] = m end

function VB_Challenges.applicableModifiers(q)
    local out = {}
    for _, m in ipairs(VB_Challenges.Modifiers) do
        if m.applies(q) then table.insert(out, m) end
    end
    return out
end

function VB_Challenges.hasModifier(q, id)
    return q.mods ~= nil and q.mods[id] == true
end

function VB_Challenges.modifierCount(mods)
    local n = 0
    for _, on in pairs(mods or {}) do if on then n = n + 1 end end
    return n
end

function VB_Challenges.modifierLabel(id)
    return VB_Challenges.T("Mod_" .. id)
end

function VB_Challenges.pointsWithModifiers(basePoints, mods)
    return math.floor(basePoints * (1 + VB_Challenges.modifierBonus() * VB_Challenges.modifierCount(mods)) + 0.5)
end

-- "No firearms, Deadline"
function VB_Challenges.modifierNames(mods)
    local names = {}
    for _, m in ipairs(VB_Challenges.Modifiers) do
        if mods and mods[m.id] then table.insert(names, VB_Challenges.modifierLabel(m.id)) end
    end
    return table.concat(names, ", ")
end
