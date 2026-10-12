-- VB_Challenges: the predetermined quest pool.
--
-- Quest types and how progress is measured:
--   kill          zombie kills since the quest was accepted
--   kill_firearm  kills made while holding a ranged weapon
--   kill_night    kills made between 21:00 and 05:00
--   survive       in-game days survived since accepting
--   deliver       items in your inventory; handed in (consumed) on claim. Takes either
--                 item (one type) or itemGroup (any type in VB_Challenges.ItemGroups)
--   skill         perk levels gained since accepting; with goalLevel, reach that level
--                 (progress shows the current level, e.g. 8 / 10)
--   visit         step inside a target building (location quests, see VB_Challenges_Locations)
--   roundtrip     reach the target building, then return to where you accepted
--   overnight     spend N hours inside the target building at night
--   craft / fish / forage / cook / read / plant / harvest
--                 activity counts (see VB_Challenges_Activities); cook takes a foodGroup
--   pet / feed / eggs / catch / milk / shear / butcher
--                 animal activity counts (see VB_Challenges_Activities)
--   settrap / trapcatch
--                 traps placed / catches collected (see VB_Challenges_Activities);
--                 trapcatch can take a catchAnimal (e.g. "rabbit")
--   forage        foraging finds (junk/trash excluded); can take a forageGroup
--   fish          fish landed; can take a fishGoal (see VB_Challenges.FishGoals)
--   partinstall / partremove
--                 vehicle parts installed / removed; can take a partGroup
--   hotwire       vehicles hotwired
--   potterycraft  pottery recipes crafted (clay shaped)
--   knapcraft / glasscraft / elecraft
--                 knapping / glassmaking / electrical recipes crafted
--   dish          dishes of a kind (dishGroup) with at least minIngredients ingredients
--   cookcraft     cooking recipes crafted (use with a recipeGroup: dough, sushi, pickle)
--   carvecraft    carving recipes crafted (can take a recipeGroup)
--   smithcraft    blacksmithing recipes crafted (can take a recipeGroup)
--   woodcraft / woodbuild / woodbarricade
--                 carpentry recipes crafted / wooden structures built (can take a buildGroup) /
--                 plank barricades
--   generator / fixgenerator
--                 generators connected and started / repaired
--   masonrycraft / masonrybuild
--                 masonry recipes crafted / brick and stone structures built (can take a buildGroup)
--   tailorcraft / patch / reinforce / laundry
--                 tailoring recipes crafted / holes patched /
--                 denim or leather reinforcement patches / dirty items washed
--   weldcraft / metalbuild / metalbarricade
--   (Crafting types can take a recipeGroup: words in the recipe name, see RecipeGroups.)
--                 welding recipes crafted / metal structures built / metal barricades
--   track         animal tracks inspected; can take a trackAnimal (e.g. "deer")
--   vehicle       best average part condition (%) of a car you're driving
--
-- Location templates use minDist/maxDist (tiles from the player) and a list of
-- place ids (VB_Challenges.Places).
--
-- Templates with canOffer(player) are only offered when it returns true.
-- Templates with `months` (1-12) are only offered in those months (seasonal finds).
--
-- Animal templates have category = "animal" (sandbox switch EnableAnimalChallenges).
-- Starter ones can be done by anyone who finds a farm; farmer ones also have
-- requiresPerk/requiresLevel and are only offered once the player has that skill.
--
-- Titles come from the translation key UI_VB_Challenges_Tpl_<id> (Translate/EN/UI.json);
-- location titles take the place name as %1.
--
-- `min`/`max` are the randomized target range. Points scale from
-- 90% to 110% of the difficulty's base value across that range.
require "VB_Challenges_Shared"

-- Months (1-12) when seasonal forage (mushrooms, insects, medicinal plants) can be found,
-- matching the vanilla forage definitions.
local GROWING_SEASON = { 3, 4, 5, 6, 7, 8, 9, 10, 11 }

-- Same rule as the vanilla vehicle menu for offering "Hotwire".
-- Using generators needs the "Generator" recipe (magazine, or automatic at Electricity 3).
-- Metal armor recipes also need Tailoring (2 for the simplest pieces).
local function canSewArmor(player)
    return player:getPerkLevel(Perks.Tailoring) >= 2
end

local function knowsGenerators(player)
    local ok, known = pcall(function() return player:isRecipeActuallyKnown("Generator") end)
    return ok and known == true
end

local function canHotwire(player)
    if player:getPerkLevel(Perks.Electricity) >= 1 and player:getPerkLevel(Perks.Mechanics) >= 2 then return true end
    local ok, burglar = pcall(function() return player:hasTrait(CharacterTrait.BURGLAR) end)
    return ok and burglar == true
end

-- Item groups for deliver quests (itemGroup): any of these items counts.
-- Names come from UI_VB_Challenges_ItemGroup_<id>.
VB_Challenges.ItemGroups = {
    firedware = { "Base.ClayBowl", "Base.ClayMug", "Base.ClayPlate", "Base.ClayPot",
                  "Base.ClayJar", "Base.ClayJarGlazed", "Base.CeramicTeacup" },
}

-- Item types a deliver quest accepts.
function VB_Challenges.deliverTypes(q)
    return (q.itemGroup and VB_Challenges.ItemGroups[q.itemGroup]) or { q.item }
end

-- Every skill that can be trained by doing things (passive Fitness/Strength excluded).
-- Ids missing from the running game version are skipped when offers are built.
VB_Challenges.TrainableSkills = {
    "Cooking", "Woodwork", "Fishing", "Farming", "PlantScavenging", "Trapping", "Tailoring",
    "Doctor", "Mechanics", "Electricity", "MetalWelding", "Maintenance", "Husbandry",
    "Butchering", "Tracking", "Masonry", "Pottery", "Carving", "Blacksmith", "Glassmaking",
    "FlintKnapping", "Aiming", "Reloading", "Axe", "Blunt", "SmallBlunt", "SmallBlade",
    "LongBlade", "Spear", "Sprinting", "Lightfoot", "Nimble", "Sneak",
}

VB_Challenges.Templates = {
    easy = {
        { id = "e_kill",       type = "kill", min = 10, max = 20 },
        { id = "e_night",      type = "kill_night", min = 5,  max = 10 },
        { id = "e_survive",    type = "survive", min = 2,  max = 2 },
        { id = "e_nails",      type = "deliver", item = "Base.Nails",        min = 10, max = 20 },
        { id = "e_planks",     type = "deliver", item = "Base.Plank",        min = 3, max = 6 },
        { id = "e_sheets",     type = "deliver", item = "Base.RippedSheets", min = 4, max = 8 },
        { id = "e_beans",      type = "deliver", item = "Base.TinnedBeans",  min = 1, max = 2 },
        { id = "e_bandage",    type = "deliver", item = "Base.Bandage",      min = 2, max = 3 },
        { id = "e_battery",    type = "deliver", item = "Base.Battery",      min = 1, max = 2 },
        { id = "e_tape",       type = "deliver", item = "Base.DuctTape",    min = 1, max = 1 },
        { id = "e_firststeps", type = "skill", goalLevel = 1, maxStartLevel = 0,
          perks = VB_Challenges.TrainableSkills },
        { id = "e_skill",      type = "skill", min = 1, max = 1, maxStartLevel = 4,
          perks = { "Cooking", "Woodwork", "Fishing", "Farming", "PlantScavenging", "Trapping", "Tailoring", "Doctor", "Maintenance", "Tracking", "Pottery", "Masonry", "FlintKnapping", "Glassmaking", "Carving", "Blacksmith" } },
        { id = "e_scout",      weight = 3, type = "visit", minDist = 200, maxDist = 700,
          places = { "grocery", "gas", "pharmacy", "church", "library", "motel", "bar", "tools", "mechanic" } },
        { id = "e_craft",      type = "craft", min = 3, max = 5 },
        { id = "e_fish",       type = "fish", min = 2, max = 3 },
        { id = "e_bass",       type = "fish", fishGoal = "bass", min = 1, max = 2 },
        { id = "e_carradio",   type = "partremove", partGroup = "radio", min = 1, max = 1 },    -- text assumes 1
        { id = "e_carbattery", type = "partinstall", partGroup = "battery", min = 1, max = 1 }, -- text assumes 1
        { id = "e_weld",       type = "weldcraft", min = 2, max = 2 },
        { id = "e_patch",      type = "patch", min = 3, max = 3 },
        { id = "e_laundry",    type = "laundry", min = 3, max = 4 },
        { id = "e_clay",       type = "deliver", item = "Base.Clay", min = 5, max = 5 },
        { id = "e_shapeclay",  type = "potterycraft", min = 2, max = 2 },
        { id = "e_stonecut",   type = "masonrycraft", min = 3, max = 3 },
        { id = "e_cookpit",    type = "masonrybuild", buildGroup = "cookingpit", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Masonry", requiresLevel = 1 },
        { id = "e_flint",      type = "deliver", item = "Base.FlintNodule", min = 3, max = 3 },
        { id = "e_knap",       type = "knapcraft", min = 2, max = 2 },
        { id = "e_brokenglass", type = "deliver", item = "Base.BrokenGlass", min = 6, max = 6 },
        { id = "e_salvage",    type = "elecraft", recipeGroup = "dismantle", min = 3, max = 3 },
        { id = "e_sandwich",   type = "dish", dishGroup = "handheld", min = 1, max = 1 },      -- text assumes 1
        { id = "e_pickle",     type = "cookcraft", recipeGroup = "pickle", min = 1, max = 1 },
        { id = "e_whittle",    type = "carvecraft", min = 3, max = 3 },
        { id = "e_spear",      type = "carvecraft", recipeGroup = "spear", min = 1, max = 1 },   -- text assumes 1
        { id = "e_sawlogs",    type = "woodcraft", recipeGroup = "sawlogs", min = 3, max = 3 },
        { id = "e_boardup",    type = "woodbarricade", min = 2, max = 2 },
        { id = "e_rustic",     type = "woodbuild", buildGroup = "rustic", min = 3, max = 3 },
        { id = "e_forge",      type = "smithcraft", min = 2, max = 2 },
        { id = "e_forgenails", type = "smithcraft", recipeGroup = "smithnails", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Blacksmith", requiresLevel = 1 },
        { id = "e_flashlight", type = "elecraft", recipeGroup = "light", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Electricity", requiresLevel = 1 },
        { id = "e_forage",     type = "forage", min = 5, max = 8 },
        { id = "e_wildfood",   type = "forage", forageGroup = "wildfood", min = 4, max = 6 },
        { id = "e_bugs",       type = "forage", forageGroup = "insects", min = 5, max = 8, months = GROWING_SEASON },
        { id = "e_cook",       type = "cook", min = 1, max = 2, foodGroup = "vegetables" },
        { id = "e_read",       type = "read", min = 1, max = 1 },
        { id = "e_plant",      type = "plant", min = 4, max = 8 },
        { id = "e_traps",      type = "settrap", min = 2, max = 3 },
        { id = "e_firstcatch", type = "trapcatch", min = 1, max = 1 },
        { id = "e_tracks",     type = "track", min = 2, max = 3 },
        { id = "e_farm",       category = "animal", type = "visit", minDist = 200, maxDist = 1200,
          places = { "farm" } },
        { id = "e_pet",        category = "animal", type = "pet", min = 2, max = 3 },
        { id = "e_feed",       category = "animal", type = "feed", min = 2, max = 3 },
    },
    medium = {
        { id = "m_kill",       type = "kill", min = 40, max = 75 },
        { id = "m_night",      type = "kill_night", min = 20, max = 30 },
        { id = "m_firearm",    type = "kill_firearm", min = 10, max = 20 },
        { id = "m_survive",    type = "survive", min = 4,  max = 5 },
        { id = "m_logs",       type = "deliver", item = "Base.Log",             min = 8,  max = 12 },
        { id = "m_scrap",      type = "deliver", item = "Base.ScrapMetal",      min = 6,  max = 10 },
        { id = "m_electro",    type = "deliver", item = "Base.ElectronicsScrap", min = 10, max = 15 },
        { id = "m_wipes",      type = "deliver", item = "Base.AlcoholWipes",    min = 3,  max = 5 },
        { id = "m_saw",        type = "deliver", item = "Base.Saw",             min = 1,  max = 1 },
        { id = "m_chili",      type = "deliver", item = "Base.CannedChili",     min = 3,  max = 4 },
        { id = "m_skill",      type = "skill", min = 2, max = 2, maxStartLevel = 3,
          perks = { "Cooking", "Woodwork", "Fishing", "Farming", "PlantScavenging", "Trapping", "Tailoring", "Doctor", "Mechanics", "Electricity", "MetalWelding", "Tracking", "Pottery", "Masonry", "FlintKnapping", "Glassmaking", "Carving", "Blacksmith" } },
        { id = "m_expedition", weight = 2, type = "visit", minDist = 700, maxDist = 1500,
          places = { "police", "fire", "medical", "school", "gunstore", "sports", "warehouse", "camping" } },
        { id = "m_supplyrun",  weight = 2, type = "roundtrip", minDist = 400, maxDist = 1000,
          places = { "pharmacy", "grocery", "tools", "gas", "medical", "sports" } },
        { id = "m_craft",      type = "craft", min = 10, max = 15 },
        { id = "m_fish",       type = "fish", min = 5,  max = 8 },
        { id = "m_bigfish",    type = "fish", fishGoal = "big", min = 1, max = 1 },
        { id = "m_species",    type = "fish", fishGoal = "species", min = 3, max = 3 },
        { id = "m_heavyfish",  type = "fish", fishGoal = "heavy", min = 1, max = 1 },
        { id = "m_tires",      type = "partinstall", partGroup = "tires", min = 2, max = 4 },
        { id = "m_chopshop",   type = "partremove", min = 6, max = 10 },
        { id = "m_hotwire",    type = "hotwire", min = 1, max = 1, canOffer = canHotwire },     -- text assumes 1
        { id = "m_metalbarricade", type = "metalbarricade", min = 2, max = 3 },
        { id = "m_metalbuild", type = "metalbuild", min = 3, max = 3,
          requiresPerk = "MetalWelding", requiresLevel = 1 },
        { id = "m_reinforce",  type = "reinforce", min = 4, max = 4 },
        { id = "m_sew",        type = "tailorcraft", min = 2, max = 2 },
        { id = "m_kilnware",   type = "deliver", itemGroup = "firedware", min = 2, max = 3 },
        { id = "m_pottery",    type = "potterycraft", min = 6, max = 6 },
        { id = "m_stonework",  type = "masonrycraft", min = 6, max = 6,
          requiresPerk = "Masonry", requiresLevel = 1 },
        { id = "m_masonry",    type = "masonrybuild", min = 4, max = 4,
          requiresPerk = "Masonry", requiresLevel = 1 },
        { id = "m_knap",       type = "knapcraft", min = 5, max = 5 },
        { id = "m_stoneblade", type = "knapcraft", recipeGroup = "blade", min = 1, max = 1, -- text assumes 1
          requiresPerk = "FlintKnapping", requiresLevel = 1 },
        { id = "m_glasspanel", type = "glasscraft", recipeGroup = "panel", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Pottery", requiresLevel = 1 },
        { id = "m_crucible",   type = "deliver", item = "Base.CeramicCrucibleWithGlass", min = 1, max = 1,
          requiresPerk = "Pottery", requiresLevel = 1 },
        { id = "m_powerup",    type = "generator", min = 1, max = 1, canOffer = knowsGenerators }, -- text assumes 1
        { id = "m_fixgen",     type = "fixgenerator", min = 1, max = 1,                        -- text assumes 1
          requiresPerk = "Electricity", requiresLevel = 1 },
        { id = "m_radio",      type = "elecraft", recipeGroup = "radio", min = 1, max = 1,     -- text assumes 1
          requiresPerk = "Electricity", requiresLevel = 2 },
        { id = "m_stew",       type = "dish", dishGroup = "pot", minIngredients = 3, min = 1, max = 1 }, -- text assumes 1
        { id = "m_dough",      type = "cookcraft", recipeGroup = "dough", min = 3, max = 3 },
        { id = "m_bonetools",  type = "carvecraft", recipeGroup = "bonetool", min = 3, max = 3 },
        { id = "m_handles",    type = "carvecraft", recipeGroup = "handle", min = 4, max = 4,
          requiresPerk = "Carving", requiresLevel = 1 },
        { id = "m_utensils",   type = "carvecraft", recipeGroup = "utensil", min = 3, max = 3 },
        { id = "m_furniture",  type = "woodbuild", buildGroup = "furniture", min = 2, max = 2,
          requiresPerk = "Woodwork", requiresLevel = 1 },
        { id = "m_handyman",   type = "woodbuild", min = 6, max = 6,
          requiresPerk = "Woodwork", requiresLevel = 1 },
        { id = "m_rainwater",  type = "woodbuild", buildGroup = "raincollector", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Woodwork", requiresLevel = 3 },
        { id = "m_cookware",   type = "smithcraft", recipeGroup = "cookware", min = 3, max = 3,
          requiresPerk = "Blacksmith", requiresLevel = 2 },
        { id = "m_toolheads",  type = "smithcraft", recipeGroup = "toolhead", min = 3, max = 3,
          requiresPerk = "Blacksmith", requiresLevel = 4 },
        { id = "m_forgework",  type = "smithcraft", min = 6, max = 6,
          requiresPerk = "Blacksmith", requiresLevel = 1 },
        { id = "m_forage",     type = "forage", min = 15, max = 25 },
        { id = "m_herbalist",  type = "forage", forageGroup = "medicinal", min = 3, max = 5, months = GROWING_SEASON },
        { id = "m_supplies",   type = "forage", forageGroup = "materials", min = 6, max = 10 },
        { id = "m_cook",       type = "cook", min = 2,  max = 3, foodGroup = "meat" },
        { id = "m_read",       type = "read", min = 2,  max = 3 },
        { id = "m_harvest",    type = "harvest", min = 3,  max = 5 },
        { id = "m_vehicle",    type = "vehicle", min = 65, max = 75 },
        { id = "m_eggs",       category = "animal", type = "eggs", min = 4, max = 6 },
        { id = "m_catch",      category = "animal", type = "catch", min = 1, max = 1 }, -- text assumes 1
        { id = "m_trapline",   type = "trapcatch", min = 4, max = 6 },
        { id = "m_rabbits",    type = "trapcatch", catchAnimal = "rabbit", min = 1, max = 2 },
        { id = "m_tracks",     type = "track", min = 8, max = 10 },
        { id = "m_deertracks", type = "track", trackAnimal = "deer", min = 1, max = 2 },
        { id = "m_milk",       category = "animal", type = "milk", min = 2, max = 3,
          requiresPerk = "Husbandry", requiresLevel = 1 },
        { id = "m_shear",      category = "animal", type = "shear", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Husbandry", requiresLevel = 1 },
        { id = "m_eggcrate",   category = "animal", type = "deliver", item = "Base.Egg", min = 10, max = 12,
          requiresPerk = "Husbandry", requiresLevel = 1 },
    },
    hard = {
        { id = "h_kill",       type = "kill", min = 150, max = 250 },
        { id = "h_firearm",    type = "kill_firearm", min = 50,  max = 75 },
        { id = "h_night",      type = "kill_night", min = 60, max = 80 },
        { id = "h_survive",    type = "survive", min = 10,  max = 14 },
        { id = "h_generator",  type = "deliver", item = "Base.Generator",    min = 1, max = 1 },
        { id = "h_sledge",     type = "deliver", item = "Base.Sledgehammer",   min = 1, max = 1 },
        { id = "h_torch",      type = "deliver", item = "Base.BlowTorch",      min = 1, max = 1 },
        { id = "h_antibio",    type = "deliver", item = "Base.Antibiotics",    min = 2, max = 3 },
        { id = "h_alice",      type = "deliver", item = "Base.Bag_ALICEpack",  min = 1, max = 1 },
        { id = "h_logs",       type = "deliver", item = "Base.Log",            min = 30, max = 40 },
        -- Long haul: only offered from level 8, worth extra points.
        { id = "h_grandmaster", type = "skill", goalLevel = 10, minStartLevel = 8, pointsMult = 1.5,
          perks = VB_Challenges.TrainableSkills },
        { id = "h_skill",      type = "skill", min = 2, max = 2, maxStartLevel = 6,
          perks = { "Cooking", "Woodwork", "Fishing", "Farming", "PlantScavenging", "Trapping", "Tailoring", "Doctor", "Mechanics", "Electricity", "MetalWelding", "Aiming", "Axe", "Blunt", "SmallBlade", "LongBlade", "Spear", "Tracking", "Pottery", "Masonry", "FlintKnapping", "Glassmaking", "Carving", "Blacksmith" } },
        { id = "h_overnight",  weight = 2, type = "overnight", minDist = 300, maxDist = 1500, nightHours = 4,
          places = { "police", "medical", "fire", "school", "prison", "army", "gunstore", "warehouse" } },
        { id = "h_longroad",   weight = 2, type = "visit", minDist = 1500, maxDist = 3500,
          places = { "army", "prison", "police", "medical", "gunstore" } },
        { id = "h_fish",       type = "fish", min = 15, max = 20 },
        { id = "h_catfish",    type = "fish", fishGoal = "bigcatfish", min = 1, max = 1 },
        -- Trophy fish only bite at Fishing 8+ (about 1 in 20 big fish).
        { id = "h_trophy",     type = "fish", fishGoal = "trophy", min = 1, max = 1, pointsMult = 1.5,
          requiresPerk = "Fishing", requiresLevel = 8 },
        { id = "h_junkyard",   type = "partremove", min = 20, max = 25 },
        { id = "h_mechanic",   type = "partinstall", min = 10, max = 12 },
        { id = "h_metalbuild", type = "metalbuild", min = 10, max = 12,
          requiresPerk = "MetalWelding", requiresLevel = 1 },
        { id = "h_weld",       type = "weldcraft", min = 15, max = 15,
          requiresPerk = "MetalWelding", requiresLevel = 1 },
        { id = "h_tailor",     type = "tailorcraft", min = 8, max = 8,
          requiresPerk = "Tailoring", requiresLevel = 1 },
        { id = "h_leather",    type = "tailorcraft", recipeGroup = "leather", min = 3, max = 3,
          requiresPerk = "Tailoring", requiresLevel = 1 },
        { id = "h_bricks",     type = "deliver", item = "Base.ClayBrick", min = 12, max = 12 },
        { id = "h_potter",     type = "potterycraft", min = 15, max = 15,
          requiresPerk = "Pottery", requiresLevel = 1 },
        { id = "h_walls",      type = "masonrybuild", buildGroup = "wall", min = 12, max = 12,
          requiresPerk = "Masonry", requiresLevel = 2 },
        { id = "h_mill",       type = "masonrybuild", buildGroup = "millquern", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Masonry", requiresLevel = 1 },
        { id = "h_knap",       type = "knapcraft", min = 12, max = 12,
          requiresPerk = "FlintKnapping", requiresLevel = 1 },
        { id = "h_stonehead",  type = "knapcraft", recipeGroup = "heavyhead", min = 1, max = 1, -- text assumes 1
          requiresPerk = "FlintKnapping", requiresLevel = 4 },
        { id = "h_glassblow",  type = "glasscraft", min = 3, max = 3,
          requiresPerk = "Glassmaking", requiresLevel = 2 },
        { id = "h_mirror",     type = "glasscraft", recipeGroup = "mirrorjar", min = 1, max = 1, -- text assumes 1
          requiresPerk = "Glassmaking", requiresLevel = 4 },
        { id = "h_hamradio",   type = "elecraft", recipeGroup = "hamradio", min = 1, max = 1,  -- text assumes 1
          requiresPerk = "Electricity", requiresLevel = 3 },
        { id = "h_electrician", type = "elecraft", min = 10, max = 10,
          requiresPerk = "Electricity", requiresLevel = 1 },
        { id = "h_pie",        type = "dish", dishGroup = "baked", min = 1, max = 1 },         -- text assumes 1
        { id = "h_sushi",      type = "cookcraft", recipeGroup = "sushi", min = 3, max = 3 },
        { id = "h_preserve",   type = "cookcraft", recipeGroup = "pickle", min = 4, max = 4 },
        { id = "h_carve",      type = "carvecraft", min = 15, max = 15,
          requiresPerk = "Carving", requiresLevel = 1 },
        { id = "h_bat",        type = "carvecraft", recipeGroup = "bat", min = 1, max = 1,     -- text assumes 1
          requiresPerk = "Carving", requiresLevel = 7 },
        { id = "h_woodwalls",  type = "woodbuild", buildGroup = "woodwall", min = 12, max = 12,
          requiresPerk = "Woodwork", requiresLevel = 2 },
        { id = "h_stairs",     type = "woodbuild", buildGroup = "stairs", min = 1, max = 1,     -- text assumes 1
          requiresPerk = "Woodwork", requiresLevel = 3 },
        { id = "h_blades",     type = "smithcraft", recipeGroup = "smithblade", min = 2, max = 2,
          requiresPerk = "Blacksmith", requiresLevel = 4 },
        { id = "h_armor",      type = "smithcraft", recipeGroup = "armor", min = 1, max = 1,   -- text assumes 1
          requiresPerk = "Blacksmith", requiresLevel = 4, canOffer = canSewArmor },
        { id = "h_smith",      type = "smithcraft", min = 15, max = 15,
          requiresPerk = "Blacksmith", requiresLevel = 2 },
        { id = "h_cook",       type = "cook", min = 3,  max = 4, foodGroup = "fish" },
        { id = "h_read",       type = "read", min = 4,  max = 6 },
        { id = "h_harvest",    type = "harvest", min = 10, max = 15 },
        { id = "h_vehicle",    type = "vehicle", min = 88, max = 95 },
        { id = "h_dairy",      category = "animal", type = "milk", min = 6, max = 8,
          requiresPerk = "Husbandry", requiresLevel = 1 },
        { id = "h_butcher",    category = "animal", type = "butcher", min = 2, max = 3,
          requiresPerk = "Husbandry", requiresLevel = 1 },
        { id = "h_eggcrate",   category = "animal", type = "deliver", item = "Base.Egg", min = 24, max = 30,
          requiresPerk = "Husbandry", requiresLevel = 1 },
        { id = "h_trapper",    type = "trapcatch", min = 12, max = 15 },
        { id = "h_tracker",    type = "track", min = 18, max = 22 },
        { id = "h_forager",    type = "forage", min = 40, max = 50 },
        { id = "h_rarity",     type = "forage", forageGroup = "rarities", min = 1, max = 1 }, -- text assumes 1
    },
}

-- Whether a template may be offered to this player right now.
function VB_Challenges.templateAvailable(player, t)
    if t.category == "animal" and not VB_Challenges.animalChallengesEnabled() then return false end
    if t.months then
        local month = getGameTime():getMonth() + 1 -- getMonth() is 0-based
        local inSeason = false
        for _, m in ipairs(t.months) do
            if m == month then inSeason = true break end
        end
        if not inSeason then return false end
    end
    if t.requiresPerk then
        local perk = Perks[t.requiresPerk]
        if not perk or player:getPerkLevel(perk) < (t.requiresLevel or 1) then return false end
    end
    if t.canOffer and not t.canOffer(player) then return false end
    return true
end

-- Display title. Old saves may have a stored English title without a template key.
function VB_Challenges.questTitle(q)
    if not q.templateId then return q.title or "?" end
    if q.placeId then
        return VB_Challenges.T("Tpl_" .. q.templateId, VB_Challenges.T("PlaceTitle_" .. q.placeId))
    end
    return VB_Challenges.T("Tpl_" .. q.templateId)
end

function VB_Challenges.describeQuest(q)
    if q.type == "kill" then
        return VB_Challenges.T("Desc_kill", q.target)
    elseif q.type == "kill_night" then
        return VB_Challenges.T("Desc_kill_night", q.target)
    elseif q.type == "kill_firearm" then
        return VB_Challenges.T("Desc_kill_firearm", q.target)
    elseif q.type == "survive" then
        return VB_Challenges.T("Desc_survive", q.target)
    elseif q.type == "deliver" then
        if q.itemGroup then
            return VB_Challenges.T("Desc_deliverGroup", q.target, VB_Challenges.T("ItemGroup_" .. q.itemGroup))
        end
        return VB_Challenges.T("Desc_deliver", q.target, VB_Challenges.itemName(q.item))
    elseif q.type == "skill" then
        if q.goalLevel then
            return VB_Challenges.T("Desc_skillGoal", q.goalLevel, VB_Challenges.perkName(q.perk))
        end
        return VB_Challenges.T("Desc_skill", q.target, VB_Challenges.perkName(q.perk))
    elseif VB_Challenges.Location and VB_Challenges.Location.isLocationType(q.type) then
        return VB_Challenges.Location.describe(q)
    elseif VB_Challenges.Activity and VB_Challenges.Activity.isActivityType(q.type) then
        return VB_Challenges.Activity.describe(q)
    end
    return "?"
end

-- Human-readable progress line, e.g. "12 / 20" or "1.5 / 4 hours at night".
function VB_Challenges.formatProgress(q, progress)
    if VB_Challenges.Location and VB_Challenges.Location.isLocationType(q.type) then
        return VB_Challenges.Location.formatProgress(q, progress)
    end
    if VB_Challenges.Activity and VB_Challenges.Activity.isActivityType(q.type) then
        return VB_Challenges.Activity.formatProgress(q, progress)
    end
    return string.format("%d / %d", math.min(progress, q.target), q.target)
end
