-- VB_Challenges: level-up reward pools.
-- Each level-up offers 2 choices from different categories. The player must pick one.
-- Bundle display names come from UI_VB_Challenges_Bundle_<id> (Translate/EN/UI.json).
require "VB_Challenges_Shared"

-- Item bundles by tier. tier = ceil(level / 3), capped at the highest tier defined.
VB_Challenges.ItemBundles = {
    [1] = {
        { id = "medical_supplies", items = { { "Base.Bandage", 4 }, { "Base.Disinfectant", 1 } } },
        { id = "canned_rations",   items = { { "Base.TinnedBeans", 2 }, { "Base.CannedCorn", 2 }, { "Base.TinOpener", 1 } } },
        { id = "carpenters_start", items = { { "Base.Hammer", 1 }, { "Base.Nails", 25 } } },
        { id = "repair_kit",       items = { { "Base.DuctTape", 2 }, { "Base.Glue", 1 }, { "Base.Rope", 2 } } },
        { id = "fire_starters",    items = { { "Base.Lighter", 1 }, { "Base.Matches", 2 }, { "Base.Battery", 2 } } },
    },
    [2] = {
        { id = "woodworking_tools", items = { { "Base.Saw", 1 }, { "Base.Nails", 40 } } },
        { id = "crowbar",           items = { { "Base.Crowbar", 1 } } },
        { id = "trauma_kit",        items = { { "Base.Antibiotics", 1 }, { "Base.SutureNeedle", 2 }, { "Base.Bandage", 4 } } },
        { id = "ammo_9mm",          items = { { "Base.Bullets9mmBox", 1 } } },
        { id = "shotgun_shells",    items = { { "Base.ShotgunShellsBox", 1 } } },
        { id = "hand_axe",          items = { { "Base.HandAxe", 1 } } },
    },
    [3] = {
        { id = "fire_axe",          items = { { "Base.Axe", 1 } } },
        { id = "machete",           items = { { "Base.Machete", 1 } } },
        { id = "welding_kit",       items = { { "Base.BlowTorch", 1 }, { "Base.WeldingRods", 2 } } },
        { id = "alice_pack",        items = { { "Base.Bag_ALICEpack", 1 } } },
        { id = "ammo_cache",        items = { { "Base.Bullets9mmBox", 2 }, { "Base.ShotgunShellsBox", 1 } } },
    },
    [4] = {
        { id = "generator",         items = { { "Base.Generator", 1 } } },
        { id = "demolition_tools",  items = { { "Base.Sledgehammer", 1 }, { "Base.Crowbar", 1 } } },
        { id = "field_hospital",    items = { { "Base.Antibiotics", 2 }, { "Base.SutureNeedle", 3 }, { "Base.Splint", 2 }, { "Base.Bandage", 6 } } },
    },
}

-- Perks eligible for XP rewards (passive Fitness/Strength excluded on purpose).
VB_Challenges.XpPerks = {
    "Cooking", "Woodwork", "Fishing", "Farming", "PlantScavenging", "Trapping", "Tailoring",
    "Doctor", "Mechanics", "Electricity", "MetalWelding", "Aiming", "Reloading",
    "Axe", "Blunt", "SmallBlunt", "SmallBlade", "LongBlade", "Spear", "Maintenance",
    "Sprinting", "Lightfoot", "Nimble", "Sneak",
}

-- Cheap positive traits (cost 2-4) that can be gained.
VB_Challenges.GainableTraits = {
    "dextrous", "fastreader", "irongut", "outdoorsman", "nightvision", "lighteater",
    "lowthirst", "inconspicuous", "organized", "graceful", "needslesssleep", "eagleeyed",
}
-- Negative traits may be removed if their cost is between -2 and -6.
VB_Challenges.MIN_REMOVABLE_TRAIT_COST = -6

-- Category weights for level-up choices.
VB_Challenges.RewardCategories = {
    { id = "items", weight = 40 },
    { id = "xp",    weight = 35 },
    { id = "token", weight = 15 },
    { id = "trait", weight = 30 }, -- only eligible every VB_Challenges.traitRewardEvery() levels
}

-- Sandbox switches per category.
local CATEGORY_OPTION = { items = "EnableItemRewards", xp = "EnableXpRewards", token = "EnableTokenRewards", trait = "EnableTraitRewards" }
function VB_Challenges.rewardCategoryEnabled(id)
    local opt = CATEGORY_OPTION[id]
    return opt == nil or VB_Challenges.opt(opt, true) ~= false
end

function VB_Challenges.rewardTier(level)
    local tier = math.ceil(level / 3)
    if tier < 1 then tier = 1 end
    if tier > #VB_Challenges.ItemBundles then tier = #VB_Challenges.ItemBundles end
    return tier
end

-- XP amount for an XP reward at a given level (raw XP, multipliers off).
function VB_Challenges.xpRewardAmount(level)
    local amount = math.min(100 + 75 * level, 1200) * VB_Challenges.opt("XpRewardMultiplier", 1.0)
    return math.max(1, math.floor(amount + 0.5))
end
