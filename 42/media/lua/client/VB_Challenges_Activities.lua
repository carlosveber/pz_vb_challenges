-- VB_Challenges: activity quests (crafting, farming, animals, vehicles...).
--
-- Progress comes from wrapping vanilla timed actions on the acting client. Most count
-- when perform() runs, i.e. when the action finishes (not when it's cancelled):
--   craft    ISHandcraftAction          any handcrafted recipe
--   fish     ISPickupFishAction         landing a fish (trash catches don't count); q.fishGoal
--                                      can require a species group, weight, size or trophy
--   forage   ISForageAction             picking up a foraging find; junk and trash don't count,
--                                      and q.forageGroup can require a category group
--   cook     ISAddItemInRecipe          adding an ingredient of a food group to a meal;
--                                      each meal counts once
--   dish     ISAddItemInRecipe          a dish of a kind (q.dishGroup) reaching
--                                      q.minIngredients ingredients; each dish counts once
--            (Both are checked after complete(): adding the first ingredient replaces the
--            base item, e.g. a pot of water becomes a stew, so only then is the meal final.)
--   cookcraft ISHandcraftAction         a recipe that awards Cooking XP (with q.recipeGroup:
--                                      doughs, sushi, pickling)
--   carvecraft ISHandcraftAction        a recipe that awards Carving XP (wood and bone)
--   read     ISReadABook                finishing a skill book; each book counts once
--   plant    ISSeedActionNew            sowing seeds
--   harvest  ISHarvestPlantAction       harvesting a crop
--   feed     ISFeedAnimalFromHand       hand-feeding an animal; each animal counts once
--   catch    ISPickupAnimal             picking up an animal; each animal counts once
--   butcher  ISButcherAnimal            butchering a carcass on the ground, or the first
--            ISCutAnimalOnHook          cut on a butchering hook; each carcass counts once
-- Some animal actions normally end by stopping themselves, so they're handled apart:
--   pet      ISPetAnimal                the "pettingFinished" animation event; each
--                                      animal counts once
--   feed     ISGiveWaterToAnimal        watering an animal (its thirst went down)
--   eggs     ISHutchGrabEgg             eggs taken from a nest box (counts every egg)
--   milk     ISMilkAnimal               a milking that drew at least MILK_MIN_LITERS
--   shear    ISShearAnimal              a shearing that took at least WOOL_MIN units
--   settrap   ISPlaceTrap                placing a trap
--   trapcatch ISCheckTrapAction          collecting a catch from a trap; the species is read
--                                        when the action starts (emptying clears it) and can
--                                        be required with q.catchAnimal
--   track     ISInspectAnimalTrackAction inspecting an animal track; each track counts once,
--                                        and q.trackAnimal can require a species
-- Vehicle actions can fail on a skill roll, so they're checked right after complete()
-- (which applies the outcome) and only count when they worked:
--   partinstall ISInstallVehiclePart     a part is now installed; q.partGroup can filter
--   partremove  ISUninstallVehiclePart   a part is now removed; q.partGroup can filter
--   hotwire     ISHotwireVehicle         the vehicle is now hotwired
--   Each vehicle part slot counts once per quest, so swapping one part back and forth
--   doesn't farm progress.
-- Welding: a recipe counts as welding when it awards MetalWelding XP.
--   weldcraft      ISHandcraftAction      crafting a welding recipe
--   masonrycraft   ISHandcraftAction      a recipe that awards Masonry XP (stone cutting, heads)
--   knapcraft      ISHandcraftAction      a recipe that awards FlintKnapping XP
--   glasscraft     ISHandcraftAction      a recipe that awards Glassmaking XP
--   elecraft       ISHandcraftAction      a recipe that awards Electricity XP
--   generator      ISActivateGenerator    a connected generator is now running (the start
--                                         can fail on a worn generator); once per generator
--   fixgenerator   ISFixGenerator         a generator repair step was done; once per generator
--   masonrybuild   ISBuildIsoEntity       building a Masonry recipe from the build menu (brick /
--                                         stone walls, frames, floors, cooking pits, mill, quern);
--                                         q.buildGroup can require entity names; once per tile
--   metalbuild     ISBuildIsoEntity       building a welding recipe from the build menu (metal
--                                         walls, frames, fences, gates, doors, floors); counts
--                                         when a new object appears, once per tile
--   metalbarricade ISBarricadeAction      a metal sheet / metal bar barricade, once per window
-- Tailoring:
--   potterycraft   ISHandcraftAction      shaping clay: a recipe that awards Pottery XP
--                                         (by hand, pottery wheel or hand press)
--   tailorcraft    ISHandcraftAction      crafting a recipe that awards Tailoring XP
--   Skill crafts (weld/pottery/masonry/knap/glass/tailor) can require recipe names with
--   q.recipeGroup (see VB_Challenges.RecipeGroups).
--   patch          ISRepairClothing       a patch sewn over a hole
--   reinforce      ISRepairClothing       a denim / leather patch on an intact spot
--                                         (patches count once per garment and body part)
--   laundry        ISWashClothing         washing a dirty or bloody item, once per item
-- vehicle quests are polled: best average part condition of a car you're driving.
require "VB_Challenges_Shared"

VB_Challenges.Activity = VB_Challenges.Activity or {}
local A = VB_Challenges.Activity

A.TYPES = {
    craft = true, fish = true, forage = true, cook = true,
    read = true, plant = true, harvest = true, vehicle = true,
    pet = true, feed = true, eggs = true, catch = true, settrap = true, trapcatch = true, track = true,
    partinstall = true, partremove = true, hotwire = true,
    weldcraft = true, metalbuild = true, metalbarricade = true,
    tailorcraft = true, patch = true, reinforce = true, laundry = true,
    potterycraft = true, masonrycraft = true, masonrybuild = true, knapcraft = true,
    glasscraft = true, elecraft = true, generator = true, fixgenerator = true,
    dish = true, cookcraft = true, carvecraft = true,
    milk = true, shear = true, butcher = true,
}

-- Smallest amounts that count as a real milking / shearing, so starting and
-- cancelling an action over and over doesn't farm progress.
local MILK_MIN_LITERS = 0.25
local WOOL_MIN = 1

-- Food groups for cooking quests -> vanilla FoodType values.
VB_Challenges.FoodGroups = {
    vegetables = { "Vegetables", "Bean", "Mushroom" },
    meat       = { "Meat", "Poultry", "Game" },
    fish       = { "Fish", "Seafood" },
}

-- Groups for foraging quests -> vanilla forage categories (Foraging/forageCategories.lua).
VB_Challenges.ForageGroups = {
    wildfood  = { "Berries", "Mushrooms" },
    insects   = { "Insects" },
    medicinal = { "MedicinalPlants", "WildHerbs" },
    materials = { "Firewood", "Stones" },
    rarities  = { "ForestRarities", "Artifacts" },
}
-- Goals for fishing quests (q.fishGoal). All listed species live in rivers and lakes.
-- minWeight is in pounds (fish weight is stored as kg * 2.2).
local BASS = { "Base.LargemouthBass", "Base.SmallmouthBass", "Base.SpottedBass", "Base.StripedBass", "Base.WhiteBass" }
local CATFISH = { "Base.BlueCatfish", "Base.ChannelCatfish", "Base.FlatheadCatfish" }
VB_Challenges.FishGoals = {
    bass       = { species = BASS },
    big        = { big = true },
    species    = { distinct = true },  -- each species counts once
    heavy      = { minWeight = 5 },
    bigcatfish = { species = CATFISH, minWeight = 15 },
    trophy     = { trophy = true },
}
local BIG_FISH_POUNDS = 45 -- vanilla also treats fish this heavy as "Big"

-- Vehicle part groups for mechanics quests (q.partGroup): part id prefixes.
VB_Challenges.PartGroups = {
    radio   = { "Radio" },
    battery = { "Battery" },
    tires   = { "Tire" },
}

-- Build groups for masonry quests (q.buildGroup): lowercase parts of the build entity
-- name (e.g. StoneWall, BrickWallLvl1, Simple_Cooking_Pit, Stone_Mill).
VB_Challenges.BuildGroups = {
    cookingpit = { "cooking_pit" },
    wall       = { "wall" },
    millquern  = { "mill", "quern" },
}

-- Recipe groups (q.recipeGroup): words in the craft recipe name.
VB_Challenges.RecipeGroups = {
    leather   = { "Leather", "Hide", "Sheepskin" },       -- tailoring
    blade     = { "StoneBlade", "StoneChisel" },          -- knapping: blades (saw/scythe/long too), chisel
    heavyhead = { "StoneAxeHead", "StoneMaulHead" },      -- knapping: large axe head, maul head
    panel     = { "GlassPanel" },                         -- glassmaking: cast glass panel
    mirrorjar = { "Mirror", "GlassJar" },                 -- glassmaking: mirror, glass jar
    dismantle = { "Dismantle" },                          -- electrical: salvaging electronics
    light     = { "ImprovisedFlashlight", "ImprovisedLantern" },
    radio     = { "MakeshiftRadio", "MakeshiftWalkieTalkie" },
    hamradio  = { "MakeshiftHAMRadio" },
    dough     = { "Dough", "Batter", "Biscuits", "Pancake", "Muffins" }, -- cooking: baking prep
    sushi     = { "Sushi", "Maki", "Onigiri" },
    pickle    = { "MakeJar" },                            -- cooking: pickling vegetables in jars
    spear     = { "CarveSpear", "FireHardenSpear" },      -- carving: wooden spears
    bonetool  = { "MakeBone", "MakeDullBone", "Sharpen" },-- carving: bone needle, hook, awl, knife...
    handle    = { "Handle" },                             -- carving: small / medium / long handles
    utensil   = { "Spoon", "Fork", "Goblets", "CuttingBoards" },
    bat       = { "CarveBat", "CarveShortBat" },          -- carving: baseball bat, short bat
}

-- Dish groups for meal quests (q.dishGroup): lowercase parts of the evolved recipe name
-- (variants like StewBucket, SoupForged, PieSweet are covered).
VB_Challenges.DishGroups = {
    handheld = { "sandwich", "burger", "taco", "hotdog", "burrito" },
    pot      = { "stew", "soup" },
    baked    = { "pie", "cake" },
}
-- Fabrics that make a patch count as reinforcement (dirty variants included).
local REINFORCING_FABRICS = { "Base.DenimStrips", "Base.LeatherStrips" }

-- Finds made only of these categories don't count for general foraging quests.
local JUNK_CATEGORIES = { Junk = true, Trash = true, JunkFood = true, JunkWeapons = true }

function A.isActivityType(t)
    return A.TYPES[t] == true
end

local function activeQuests(player, qtype)
    local state = player:getModData().VB_Challenges
    if not state then return {} end
    local out = {}
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and q.type == qtype then table.insert(out, q) end
    end
    return out
end

local function bump(q, amount)
    if (q.counter or 0) >= q.target then return false end
    q.counter = math.min(q.target, (q.counter or 0) + (amount or 1))
    return true
end

-- Records `amount` (default 1) occurrences of an activity. `accept(q)` can filter /
-- dedupe per quest.
function A.record(player, qtype, accept, amount)
    if not player or player ~= getPlayer() then return end
    local changed = false
    for _, q in ipairs(activeQuests(player, qtype)) do
        if (not accept or accept(q)) and bump(q, amount) then changed = true end
    end
    if changed then VB_Challenges.changed() end
end

local function inFoodGroup(item, group)
    if not item or not instanceof(item, "Food") then return false end
    local ok, foodType = pcall(function() return item:getFoodType() end)
    if not ok or not foodType then return false end
    for _, t in ipairs(VB_Challenges.FoodGroups[group] or {}) do
        if t == foodType then return true end
    end
    return false
end

-- Each quest remembers ids it already counted (meals, books) so repeats don't count.
local function firstTime(q, id)
    if not id then return true end
    q.seen = q.seen or {}
    local key = tostring(id)
    if q.seen[key] then return false end
    q.seen[key] = true
    return true
end

-- Stable id for an animal (or carcass) so the same one isn't counted twice.
local function animalKey(obj)
    if not obj then return nil end
    local ok, id = pcall(function() return obj:getAnimalID() end)
    if ok and id then return "a" .. tostring(id) end
    return tostring(obj)
end

local function recordPerAnimal(character, qtype, animal)
    local key = animalKey(animal)
    A.record(character, qtype, function(q) return firstTime(q, key) end)
end

local function fishConfig(fullType)
    if not (Fishing and Fishing.fishes) then return nil end
    for _, cfg in ipairs(Fishing.fishes) do
        if cfg.itemType == fullType then return cfg end
    end
    return nil
end

-- What we know about a landed fish. Size comes from the hand model vanilla picks
-- (<Type>_Hand_Big / _Medium / _Little); a trophy is longer or heavier than its
-- species' normal maximum, which only the Legendary roll allows.
local function describeFish(item)
    local md = item:getModData()
    local weight = item:getActualWeight()
    local cfg = fishConfig(item:getFullType())
    local trophy = cfg ~= nil and ((cfg.maxLength and (md.fishing_FishSize or 0) > cfg.maxLength)
        or (cfg.maxWeight and weight > cfg.maxWeight * 2.2 + 0.01))
    local hand = tostring(md.fishing_FishHandItem or "")
    return {
        fullType = item:getFullType(),
        weight = weight,
        trophy = trophy,
        big = trophy or weight >= BIG_FISH_POUNDS or string.sub(hand, -4) == "_Big",
    }
end

local function fishMatches(q, fish)
    local goal = q.fishGoal and VB_Challenges.FishGoals[q.fishGoal]
    if not goal then return true end
    if goal.species then
        local ok = false
        for _, t in ipairs(goal.species) do
            if t == fish.fullType then ok = true break end
        end
        if not ok then return false end
    end
    if goal.minWeight and fish.weight < goal.minWeight then return false end
    if goal.big and not fish.big then return false end
    if goal.trophy and not fish.trophy then return false end
    if goal.distinct then return firstTime(q, fish.fullType) end -- last: it records the species
    return true
end

local function onFishLanded(self)
    if not self.isFish or not self.item then return end
    local fish = describeFish(self.item)
    A.record(self.character, "fish", function(q) return fishMatches(q, fish) end)
end

local function onForage(self)
    local categories = self.itemDef and self.itemDef.categories or {}
    local found = {}
    local useful = #categories == 0 -- unknown item: don't hold it against the player
    for _, c in ipairs(categories) do
        found[c] = true
        if not JUNK_CATEGORIES[c] then useful = true end
    end
    A.record(self.character, "forage", function(q)
        if not q.forageGroup then return useful end
        for _, c in ipairs(VB_Challenges.ForageGroups[q.forageGroup] or {}) do
            if found[c] then return true end
        end
        return false
    end)
end

local function isSkillBook(item)
    if not item then return false end
    local ok, skill = pcall(function() return item:getSkillTrained() end)
    return ok and skill ~= nil and skill ~= "" and SkillBook ~= nil and SkillBook[skill] ~= nil
end

----------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------

-- Wraps cls[method] so fn(self, ...) runs first. Errors in fn are logged, never thrown,
-- so a broken hook can't break the vanilla action.
local function wrap(className, method, fn)
    local cls = _G[className]
    local original = cls and cls[method]
    if not original then return false end
    cls[method] = function(self, ...)
        local ok, err = pcall(fn, self, ...)
        if not ok then VB_Challenges.log("activity hook " .. className .. ":" .. method .. " failed: " .. tostring(err)) end
        return original(self, ...)
    end
    return true
end

-- Like wrap, but fn(self, result) runs after the original, once it has applied its outcome.
local function wrapAfter(className, method, fn)
    local cls = _G[className]
    local original = cls and cls[method]
    if not original then return false end
    cls[method] = function(self, ...)
        local result = original(self, ...)
        local ok, err = pcall(fn, self, result)
        if not ok then VB_Challenges.log("activity hook " .. className .. ":" .. method .. " failed: " .. tostring(err)) end
        return result
    end
    return true
end

local function partInGroup(partId, group)
    for _, prefix in ipairs(VB_Challenges.PartGroups[group] or {}) do
        if string.sub(partId, 1, string.len(prefix)) == prefix then return true end
    end
    return false
end

-- Records a vehicle part that was installed (wantInstalled) or removed, if that worked.
local function recordPartChange(self, qtype, wantInstalled)
    local part, vehicle = self.part, self.vehicle
    if not part or not vehicle then return end
    if (part:getInventoryItem() ~= nil) ~= wantInstalled then return end -- the roll failed
    local partId = part:getId()
    local ok, vehicleId = pcall(function() return vehicle:getMechanicalID() end)
    local key = tostring(ok and vehicleId or vehicle) .. ":" .. partId
    A.record(self.character, qtype, function(q)
        return (q.partGroup == nil or partInGroup(partId, q.partGroup)) and firstTime(q, key)
    end)
end

-- Whether a craft recipe awards XP in the given skill (e.g. "MetalWelding").
local function recipeAwards(recipe, perkId)
    local perk = Perks[perkId]
    if not recipe or not perk then return false end
    local ok, found = pcall(function()
        for i = 0, recipe:getXPAwardCount() - 1 do
            if recipe:getXPAward(i):getPerk() == perk then return true end
        end
        return false
    end)
    return ok and found
end

local function recipeInGroup(recipe, group)
    local name = recipe and recipe:getName() or ""
    for _, word in ipairs(VB_Challenges.RecipeGroups[group] or {}) do
        if string.find(name, word, 1, true) then return true end
    end
    return false
end

-- Quest type counted for crafting a recipe that awards XP in each skill.
local SKILL_CRAFTS = {
    { perk = "MetalWelding", qtype = "weldcraft" },
    { perk = "Pottery", qtype = "potterycraft" },
    { perk = "Masonry", qtype = "masonrycraft" },
    { perk = "FlintKnapping", qtype = "knapcraft" },
    { perk = "Glassmaking", qtype = "glasscraft" },
    { perk = "Electricity", qtype = "elecraft" },
    { perk = "Cooking", qtype = "cookcraft" },
    { perk = "Carving", qtype = "carvecraft" },
    { perk = "Tailoring", qtype = "tailorcraft" },
}

local function onCraft(self)
    local recipe = self.craftRecipe
    A.record(self.character, "craft")
    local function accept(q) return q.recipeGroup == nil or recipeInGroup(recipe, q.recipeGroup) end
    for _, s in ipairs(SKILL_CRAFTS) do
        if recipeAwards(recipe, s.perk) then A.record(self.character, s.qtype, accept) end
    end
end

-- Patches: whether the spot had a hole and which fabric is used are read before
-- complete() sews the patch on and uses up the fabric.
local function onPatchBefore(self)
    local hole = self.clothing and self.part and self.clothing:getVisual():getHole(self.part) or 0
    self.vbHadHole = hole > 0
    self.vbFabric = self.fabric and self.fabric:getFullType() or ""
end

local function onPatchAfter(self, result)
    if result ~= true or self.vbHadHole == nil then return end
    local key = tostring(self.clothing:getID()) .. ":" .. tostring(self.part)
    if self.vbHadHole then
        A.record(self.character, "patch", function(q) return firstTime(q, key) end)
        return
    end
    for _, fabric in ipairs(REINFORCING_FABRICS) do
        if string.sub(self.vbFabric, 1, string.len(fabric)) == fabric then
            A.record(self.character, "reinforce", function(q) return firstTime(q, key) end)
            return
        end
    end
end

local function squareKey(sq)
    return sq and (sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()) or nil
end

-- Generators count once each, keyed by where they stand.
local function recordGenerator(self, qtype)
    local key = squareKey(self.generator and self.generator:getSquare())
    A.record(self.character, qtype, function(q) return firstTime(q, key) end)
end

local function onGeneratorStarted(self)
    local g = self.generator
    if self.activate and g and g:isActivated() and g:isConnected() then recordGenerator(self, "generator") end
end

local function onGeneratorFixed(self, result)
    if result == true then recordGenerator(self, "fixgenerator") end
end

-- Evolved recipe name, untranslated and lowercase (e.g. "stew", "piesweet").
local function dishName(recipe)
    for _, getter in ipairs({ "getOriginalname", "getUntranslatedName", "getName" }) do
        local ok, name = pcall(function() return recipe[getter](recipe) end)
        if ok and name then return string.lower(name) end
    end
    return ""
end

local function dishInGroup(name, group)
    for _, part in ipairs(VB_Challenges.DishGroups[group] or {}) do
        if string.find(name, part, 1, true) then return true end
    end
    return false
end

local function onIngredientAdded(self, result)
    local dish = self.baseItem -- complete() swapped in the resulting dish
    if result == false or not dish or not self.recipe then return end
    local key = dish:getID()
    A.record(self.character, "cook", function(q)
        return inFoodGroup(self.usedItem, q.foodGroup) and firstTime(q, key)
    end)
    local name = dishName(self.recipe)
    local ok, extras = pcall(function() return dish:getExtraItems() end)
    local ingredients = (ok and extras) and extras:size() or 0
    A.record(self.character, "dish", function(q)
        return dishInGroup(name, q.dishGroup) and ingredients >= (q.minIngredients or 1)
            and firstTime(q, key)
    end)
end

-- Laundry: only items that needed it, once each.
local function onWash(self, result)
    if result ~= true or not self.item then return end
    if (self.bloodAmount or 0) + (self.dirtAmount or 0) <= 0 then return end
    local key = tostring(self.item:getID())
    A.record(self.character, "laundry", function(q) return firstTime(q, key) end)
end

-- Metal barricades: once per window/door, so taking one down and putting it back
-- doesn't count twice.
local function onBarricade(self, result)
    if result ~= true or not (self.isMetal or self.isMetalBar) then return end
    local key = squareKey(self.item and self.item:getSquare())
    local ok, north = pcall(function() return self.item:getNorth() end)
    if key and ok then key = key .. (north and "N" or "W") end
    A.record(self.character, "metalbarricade", function(q) return firstTime(q, key) end)
end

-- Lowercase name of what a build-menu entity builds, e.g. "stonewall".
local function buildName(build)
    local ok, name = pcall(function() return build.objectInfo:getScript():getParent():getName() end)
    if not ok or not name then
        ok, name = pcall(function() return build.craftRecipe:getName() end)
    end
    return string.lower(tostring(ok and name or ""))
end

local function nameInGroup(name, group)
    for _, part in ipairs(VB_Challenges.BuildGroups[group] or {}) do
        if string.find(name, part, 1, true) then return true end
    end
    return false
end

-- Build-menu entities: create() returns nothing on success, so success is a new object
-- on the target square.
local function installBuildHook()
    local cls = ISBuildIsoEntity
    local original = cls and cls.create
    if not original then return false end
    cls.create = function(self, x, y, z, ...)
        local sq = getCell():getGridSquare(x, y, z)
        local before = sq and sq:getObjects():size() or 0
        local result = original(self, x, y, z, ...)
        local ok, err = pcall(function()
            local after = self.sq or sq
            if not after or after:getObjects():size() <= before then return end
            local key = squareKey(after)
            if recipeAwards(self.craftRecipe, "MetalWelding") then
                A.record(self.character, "metalbuild", function(q) return firstTime(q, key) end)
            end
            if recipeAwards(self.craftRecipe, "Masonry") then
                local name = buildName(self)
                A.record(self.character, "masonrybuild", function(q)
                    return (q.buildGroup == nil or nameInGroup(name, q.buildGroup)) and firstTime(q, key)
                end)
            end
        end)
        if not ok then VB_Challenges.log("activity hook ISBuildIsoEntity:create failed: " .. tostring(err)) end
        return result
    end
    return true
end

-- Checked after complete(): { class, fn(self, result) }.
local COMPLETE_HOOKS = {
    { class = "ISInstallVehiclePart", fn = function(self) recordPartChange(self, "partinstall", true) end },
    { class = "ISUninstallVehiclePart", fn = function(self) recordPartChange(self, "partremove", false) end },
    { class = "ISBarricadeAction", fn = onBarricade },
    { class = "ISWashClothing", fn = onWash },
    { class = "ISActivateGenerator", fn = onGeneratorStarted },
    { class = "ISFixGenerator", fn = onGeneratorFixed },
    { class = "ISAddItemInRecipe", fn = onIngredientAdded },
    { class = "ISHotwireVehicle", fn = function(self)
        local vehicle = self.character:getVehicle()
        if vehicle and vehicle:isHotwired() then A.record(self.character, "hotwire") end
    end },
}

-- Counted when perform() runs (the action finished).
local PERFORM_HOOKS = {
    { class = "ISHandcraftAction", fn = onCraft },
    { class = "ISPickupFishAction", fn = onFishLanded },
    { class = "ISForageAction", fn = onForage },
    { class = "ISReadABook", fn = function(self)
        if not isSkillBook(self.item) then return end
        -- Only count a book that's actually been read through.
        local pages = self.item:getNumberOfPages()
        if pages > 0 and self.item:getAlreadyReadPages() < pages then return end
        local bookId = self.item:getID()
        A.record(self.character, "read", function(q) return firstTime(q, bookId) end)
    end },
    { class = "ISSeedActionNew", fn = function(self) A.record(self.character, "plant") end },
    { class = "ISHarvestPlantAction", fn = function(self) A.record(self.character, "harvest") end },
    { class = "ISFeedAnimalFromHand", fn = function(self) recordPerAnimal(self.character, "feed", self.animal) end },
    { class = "ISPickupAnimal", fn = function(self) recordPerAnimal(self.character, "catch", self.animal) end },
    { class = "ISButcherAnimal", fn = function(self) recordPerAnimal(self.character, "butcher", self.body) end },
    { class = "ISCutAnimalOnHook", fn = function(self) recordPerAnimal(self.character, "butcher", self.body) end },
    { class = "ISPlaceTrap", fn = function(self) A.record(self.character, "settrap") end },
}

-- Animal tracks. A track's type can be a migration group ("deer") or one of its
-- members ("buck", "doe", "fawn"); both count for a quest asking for the group.
local function trackMatches(animalType, wanted)
    if wanted == nil or animalType == wanted then return true end
    local group = MigrationGroupDefinitions and MigrationGroupDefinitions[wanted]
    return group ~= nil and (animalType == group.male or animalType == group.female or animalType == group.baby)
end

local function onTrackInspected(self)
    -- Ground tracks and picked-up track items both expose their AnimalTracks.
    local tracks = self.track and self.track:getAnimalTracks()
    if not tracks then return end
    local animalType = tracks:getAnimalType()
    local key = tostring(tracks)
    A.record(self.character, "track", function(q)
        return trackMatches(animalType, q.trackAnimal) and firstTime(q, key)
    end)
end

-- Trap catches: the species is read when the check starts, because emptying the trap
-- clears it. "Check Trap" is only offered when something was caught.
local function onTrapCheckStart(self)
    local animal = self.trap and self.trap.animal
    self.vbChallengesCatch = animal and animal.type
end

local function onTrapCheckPerform(self)
    local caught = self.vbChallengesCatch
    if not caught then return end
    self.vbChallengesCatch = nil
    A.record(self.character, "trapcatch", function(q)
        return q.catchAnimal == nil or q.catchAnimal == caught
    end)
end

-- Measured from start() to whichever of perform() / stop() ends the action: these
-- usually stop themselves (animal milked dry, nest box empty, thirst quenched).
-- finish(self, before, after) receives measure(self) at both ends.
local MEASURED_HOOKS = {
    { class = "ISHutchGrabEgg",
      measure = function(self) return self.nestbox:getEggsNb() end,
      finish = function(self, before, after)
          if before > after then A.record(self.character, "eggs", nil, before - after) end
      end },
    { class = "ISMilkAnimal",
      measure = function(self) return self.animal:getData():getMilkQuantity() end,
      finish = function(self, before, after)
          if before - after >= MILK_MIN_LITERS then A.record(self.character, "milk") end
      end },
    { class = "ISShearAnimal",
      measure = function(self) return self.animal:getData():getWoolQuantity() end,
      finish = function(self, before, after)
          if before - after >= WOOL_MIN then A.record(self.character, "shear") end
      end },
    { class = "ISGiveWaterToAnimal",
      measure = function(self) return self.animal:getStats():get(CharacterStat.THIRST) end,
      finish = function(self, before, after)
          if after < before then recordPerAnimal(self.character, "feed", self.animal) end
      end },
}

local function installMeasured(h)
    local key = "vbChallengesBefore_" .. h.class
    local function finish(self)
        local before = self[key]
        if before == nil then return end
        self[key] = nil -- count once, whichever of perform() / stop() comes first
        h.finish(self, before, h.measure(self))
    end
    local ok = wrap(h.class, "start", function(self) self[key] = h.measure(self) end)
    ok = wrap(h.class, "perform", finish) and ok
    ok = wrap(h.class, "stop", finish) and ok
    return ok
end

local installed = {}
local function installHooks()
    for _, h in ipairs(PERFORM_HOOKS) do
        if not installed[h.class] and wrap(h.class, "perform", h.fn) then installed[h.class] = true end
    end
    if not installed.ISBuildIsoEntity and installBuildHook() then installed.ISBuildIsoEntity = true end
    if not installed.ISRepairClothing and wrap("ISRepairClothing", "complete", onPatchBefore)
            and wrapAfter("ISRepairClothing", "complete", onPatchAfter) then
        installed.ISRepairClothing = true
    end
    for _, h in ipairs(COMPLETE_HOOKS) do
        if not installed[h.class] and wrapAfter(h.class, "complete", h.fn) then installed[h.class] = true end
    end
    for _, h in ipairs(MEASURED_HOOKS) do
        if not installed[h.class] and installMeasured(h) then installed[h.class] = true end
    end
    -- Petting completes on an animation event and then stops itself.
    if not installed.ISPetAnimal and wrap("ISPetAnimal", "animEvent", function(self, event)
        if event == "pettingFinished" then recordPerAnimal(self.character, "pet", self.animal) end
    end) then
        installed.ISPetAnimal = true
    end
    if not installed.ISInspectAnimalTrackAction and wrap("ISInspectAnimalTrackAction", "perform", onTrackInspected) then
        installed.ISInspectAnimalTrackAction = true
    end
    if not installed.ISCheckTrapAction and wrap("ISCheckTrapAction", "start", onTrapCheckStart)
            and wrap("ISCheckTrapAction", "perform", onTrapCheckPerform) then
        installed.ISCheckTrapAction = true
    end
end

-- Shared timed actions are loaded before client files; retry at game start just in case.
installHooks()
Events.OnGameStart.Add(installHooks)

----------------------------------------------------------------------
-- Vehicle condition
----------------------------------------------------------------------

-- Average condition (0-100) of the vehicle's installable parts; missing parts count as 0.
function A.vehicleCondition(vehicle)
    local total, count = 0, 0
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local itemTypes = part:getItemType()
        if itemTypes and not itemTypes:isEmpty() then
            count = count + 1
            if part:getInventoryItem() then total = total + part:getCondition() end
        end
    end
    if count == 0 then return 0 end
    return math.floor(total / count + 0.5)
end

-- Called once per in-game minute.
function A.tick(player)
    local vehicle = player:getVehicle()
    if not vehicle or not vehicle:isDriver(player) then return end
    local quests = activeQuests(player, "vehicle")
    if #quests == 0 then return end
    local cond = A.vehicleCondition(vehicle)
    local changed = false
    for _, q in ipairs(quests) do
        if cond > (q.counter or 0) then
            q.counter = cond
            changed = true
        end
    end
    if changed then VB_Challenges.changed() end
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

function A.describe(q)
    if q.type == "cook" then
        return VB_Challenges.T("Desc_cook", q.target, VB_Challenges.T("FoodGroup_" .. tostring(q.foodGroup)))
    elseif q.type == "trapcatch" and q.catchAnimal then
        return VB_Challenges.T("Desc_trapcatch_" .. q.catchAnimal, q.target)
    elseif q.type == "fish" and q.fishGoal then
        local goal = VB_Challenges.FishGoals[q.fishGoal] or {}
        local pounds = goal.minWeight or 0
        return VB_Challenges.T("Desc_fish_" .. q.fishGoal, q.target, pounds,
            string.format("%.1f", pounds / 2.2))
    elseif (q.type == "partinstall" or q.type == "partremove") and q.partGroup then
        return VB_Challenges.T("Desc_" .. q.type .. "_" .. q.partGroup, q.target)
    elseif q.type == "dish" then
        return VB_Challenges.T("Desc_dish_" .. tostring(q.dishGroup), q.target, q.minIngredients or 1)
    elseif q.recipeGroup then
        return VB_Challenges.T("Desc_" .. q.type .. "_" .. q.recipeGroup, q.target)
    elseif q.type == "masonrybuild" and q.buildGroup then
        return VB_Challenges.T("Desc_masonrybuild_" .. q.buildGroup, q.target)
    elseif q.type == "forage" and q.forageGroup then
        return VB_Challenges.T("Desc_forage_" .. q.forageGroup, q.target)
    elseif q.type == "track" and q.trackAnimal then
        return VB_Challenges.T("Desc_track_" .. q.trackAnimal, q.target)
    end
    return VB_Challenges.T("Desc_" .. q.type, q.target)
end

function A.formatProgress(q, progress)
    if q.type == "vehicle" then
        return VB_Challenges.T("Progress_Vehicle", math.min(progress, 100), q.target)
    end
    return string.format("%d / %d", math.min(progress, q.target), q.target)
end
