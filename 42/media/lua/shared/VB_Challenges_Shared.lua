-- VB_Challenges: shared config + helpers. Loaded first (shared -> client -> server).
VB_Challenges = VB_Challenges or {}
VB_Challenges.VERSION = "0.8.0"

VB_Challenges.DIFFICULTIES = { "easy", "medium", "hard" }
VB_Challenges.DIFFICULTY_COLOR = {
    easy   = { r = 0.45, g = 0.85, b = 0.45 },
    medium = { r = 0.95, g = 0.80, b = 0.30 },
    hard   = { r = 0.95, g = 0.40, b = 0.35 },
}

-- Fixed values. Everything tunable lives in the sandbox options (media/sandbox-options.txt)
-- and is read through the accessors below, so defaults here must match that file.
VB_Challenges.Config = {
    BASE_POINTS = { easy = 10, medium = 30, hard = 80 },
    BASE_DEADLINE_DAYS = { easy = 3, medium = 7, hard = 12 },
    MAX_COMPLETED_HISTORY = 200,
}

----------------------------------------------------------------------
-- Translation
----------------------------------------------------------------------

-- VB_Challenges.T("Key", a, b) -> getText("UI_VB_Challenges_Key", a, b) with %1..%9 substitution.
-- Arguments are converted to strings; format numbers before passing them.
-- getText always runs Java string formatting on the text, so translation files must
-- write a literal percent sign as %% ("+%1%% points"); a lone % logs a warning.
function VB_Challenges.T(key, ...)
    local full = "UI_VB_Challenges_" .. key
    local n = select("#", ...)
    if n == 0 then return getText(full) end
    local args = {}
    for i = 1, n do args[i] = tostring((select(i, ...))) end
    return getText(full, unpack(args))
end

function VB_Challenges.difficultyLabel(d)
    return VB_Challenges.T("Difficulty_" .. tostring(d))
end

----------------------------------------------------------------------
-- Sandbox options (SandboxVars.VB_Challenges.*), with defaults when unavailable
----------------------------------------------------------------------

function VB_Challenges.opt(name, default)
    local vars = SandboxVars and SandboxVars.VB_Challenges
    local v = vars and vars[name]
    if v == nil then return default end
    return v
end

function VB_Challenges.basePoints(difficulty)
    local p = VB_Challenges.Config.BASE_POINTS[difficulty] * VB_Challenges.opt("PointMultiplier", 1.0)
    return math.max(1, math.floor(p + 0.5))
end

function VB_Challenges.offerCount() return VB_Challenges.opt("OfferCount", 3) end
function VB_Challenges.abandonLockHours() return VB_Challenges.opt("AbandonLockDays", 2) * 24 end
function VB_Challenges.freeRerollHours() return VB_Challenges.opt("FreeRerollHours", 24) end
function VB_Challenges.traitRewardEvery() return VB_Challenges.opt("TraitRewardEvery", 5) end
function VB_Challenges.modifierBonus() return VB_Challenges.opt("ModifierBonusPercent", 50) / 100 end
function VB_Challenges.maxModifiers() return VB_Challenges.opt("MaxModifiers", 2) end
function VB_Challenges.locationChallengesEnabled() return VB_Challenges.opt("EnableLocationChallenges", true) end
function VB_Challenges.locationDistanceMultiplier() return VB_Challenges.opt("LocationDistanceMultiplier", 1.0) end
function VB_Challenges.locationCachesEnabled() return VB_Challenges.opt("EnableLocationCaches", true) ~= false end
function VB_Challenges.animalChallengesEnabled() return VB_Challenges.opt("EnableAnimalChallenges", true) ~= false end

function VB_Challenges.deadlineDays(difficulty)
    local days = VB_Challenges.Config.BASE_DEADLINE_DAYS[difficulty] or 7
    return math.max(1, math.floor(days * VB_Challenges.opt("DeadlineMultiplier", 1.0) + 0.5))
end

-- Score needed to go from `level` to `level + 1`. Quest scores don't scale with level and
-- level-up rewards stop growing around L15 (XP cap, top item tier), so the curve is linear
-- (+35 per level) up to L15 and then flattens to +15 per level. Default curve:
-- L1->2: 40, L2->3: 75, L3->4: 110, L4->5: 145, L5->6: 180 ... L10->11: 355
-- L15->16: 530, L20->21: 605, L30->31: 755
-- Results are rounded to a multiple of 5 so the numbers stay tidy with any multiplier.
local CURVE_START, CURVE_STEP, CURVE_KNEE, CURVE_LATE_STEP = 40, 35, 15, 15
function VB_Challenges.pointsForLevel(level)
    local n = math.max(0, level - 1)
    local early = math.min(n, CURVE_KNEE - 1)
    local late = n - early
    local base = CURVE_START + CURVE_STEP * early + CURVE_LATE_STEP * late
    local scaled = base * VB_Challenges.opt("LevelCurveMultiplier", 1.0)
    return math.max(5, math.floor(scaled / 5 + 0.5) * 5)
end

function VB_Challenges.log(msg)
    print("[VB_Challenges] " .. tostring(msg))
end

function VB_Challenges.randInt(min, max)
    if max <= min then return min end
    return min + ZombRand(max - min + 1)
end

function VB_Challenges.pick(list)
    if not list or #list == 0 then return nil end
    return list[ZombRand(#list) + 1]
end

-- Weighted pick: entries are { weight = n, ... }
function VB_Challenges.pickWeighted(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end
    if total <= 0 then return nil end
    local roll = ZombRand(total)
    for _, e in ipairs(list) do
        roll = roll - (e.weight or 1)
        if roll < 0 then return e end
    end
    return list[#list]
end

function VB_Challenges.itemName(fullType)
    local ok, name = pcall(getItemNameFromFullType, fullType)
    if ok and name then return name end
    return fullType
end

function VB_Challenges.perkName(perkId)
    local perk = Perks[perkId]
    if perk then
        local ok, name = pcall(function() return perk:getName() end)
        if ok and name then return name end
    end
    return perkId
end
