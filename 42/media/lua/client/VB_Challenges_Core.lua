-- VB_Challenges: core state, progress tracking, levels and rewards.
-- State lives in player:getModData().VB_Challenges, so it is saved with the character.
require "VB_Challenges_Shared"
require "VB_Challenges_Definitions"
require "VB_Challenges_Rewards"
require "VB_Challenges_Sounds"
require "VB_Challenges_Locations"
require "VB_Challenges_Modifiers"
require "VB_Challenges_Activities"

local Config = VB_Challenges.Config
VB_Challenges.Debug = VB_Challenges.Debug or {}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local function nowHours()
    return getGameTime():getWorldAgeHours()
end

function VB_Challenges.getState(player)
    player = player or getPlayer()
    if not player then return nil end
    local md = player:getModData()
    local s = md.VB_Challenges
    if not s then
        s = {
            version = 1,
            level = 1,
            levelPoints = 0,
            totalPoints = 0,
            active = {},
            offers = {},
            completed = {},
            pendingRewards = {},
            rerollTokens = 0,
            bonusTokens = 0,
            abandoned = 0,
            nextId = 1,
        }
        md.VB_Challenges = s
    end
    return s
end

function VB_Challenges.pointsToNext(state)
    return VB_Challenges.pointsForLevel(state.level)
end

local function notify(player, text, good)
    if not player then return end
    if good == false then
        HaloTextHelper.addBadText(player, text)
    else
        HaloTextHelper.addGoodText(player, text)
    end
end

VB_Challenges.listeners = {}
function VB_Challenges.changed()
    for _, fn in ipairs(VB_Challenges.listeners) do pcall(fn) end
end

----------------------------------------------------------------------
-- Offers / accepting
----------------------------------------------------------------------

local function eligiblePerks(player, template)
    local out = {}
    for _, perkId in ipairs(template.perks or {}) do
        local perk = Perks[perkId]
        if perk then
            local level = player:getPerkLevel(perk)
            if level >= (template.minStartLevel or 0) and level <= (template.maxStartLevel or 10)
                    and level < (template.goalLevel or 11) then -- skills max out at 10
                table.insert(out, perkId)
            end
        end
    end
    return out
end

local function buildQuest(player, state, difficulty, template)
    local q = {
        templateId = template.id,
        difficulty = difficulty,
        type = template.type,
        item = template.item,
        itemGroup = template.itemGroup,
        foodGroup = template.foodGroup,
        dishGroup = template.dishGroup,
        minIngredients = template.minIngredients,
        catchAnimal = template.catchAnimal,
        trackAnimal = template.trackAnimal,
        forageGroup = template.forageGroup,
        fishGoal = template.fishGoal,
        partGroup = template.partGroup,
        recipeGroup = template.recipeGroup,
        buildGroup = template.buildGroup,
    }
    local scale
    if VB_Challenges.Location.isLocationType(template.type) then
        if not VB_Challenges.Location.build(player, q, template) then return nil end
        scale = q.scale
    else
        if template.type == "skill" then
            local perks = eligiblePerks(player, template)
            if #perks == 0 then return nil end
            q.perk = VB_Challenges.pick(perks)
        end
        if template.goalLevel then
            -- Reach an absolute level: progress is the level itself (see acceptOffer).
            q.goalLevel = template.goalLevel
            q.target = template.goalLevel
            scale = 1.0
        else
            q.target = VB_Challenges.randInt(template.min, template.max)
            local span = template.max - template.min
            scale = span > 0 and (0.9 + 0.2 * (q.target - template.min) / span) or 1.0
        end
    end
    scale = scale * (template.pointsMult or 1)
    q.points = math.max(1, math.floor(VB_Challenges.basePoints(difficulty) * scale + 0.5))
    q.id = state.nextId
    state.nextId = state.nextId + 1
    return q
end

function VB_Challenges.generateOffers(player, difficulty)
    local state = VB_Challenges.getState(player)
    local pool = {}
    for _, t in ipairs(VB_Challenges.Templates[difficulty]) do
        if VB_Challenges.templateAvailable(player, t) then table.insert(pool, t) end
    end
    local offers = {}
    while #offers < VB_Challenges.offerCount() and #pool > 0 do
        -- Weighted pick without replacement (template.weight, default 1).
        local template = VB_Challenges.pickWeighted(pool)
        for i, t in ipairs(pool) do
            if t == template then table.remove(pool, i) break end
        end
        local q = buildQuest(player, state, difficulty, template)
        if q then table.insert(offers, q) end
    end
    state.offers[difficulty] = offers
    VB_Challenges.changed()
    return offers
end

function VB_Challenges.getOrCreateOffers(player, difficulty)
    local state = VB_Challenges.getState(player)
    if state.offers[difficulty] and #state.offers[difficulty] > 0 then
        return state.offers[difficulty]
    end
    return VB_Challenges.generateOffers(player, difficulty)
end

function VB_Challenges.rerollOffers(player, difficulty)
    local state = VB_Challenges.getState(player)
    if state.rerollTokens <= 0 then return false end
    state.rerollTokens = state.rerollTokens - 1
    VB_Challenges.generateOffers(player, difficulty)
    return true
end

-- mods: optional set of modifier ids, e.g. { nofirearms = true, deadline = true }
function VB_Challenges.acceptOffer(player, difficulty, index, mods)
    local state = VB_Challenges.getState(player)
    if state.active[difficulty] then return false end
    local offers = state.offers[difficulty]
    local q = offers and offers[index]
    if not q then return false end

    -- Keep only modifiers that apply to this quest, up to the cap.
    q.mods = {}
    local count = 0
    for _, m in ipairs(VB_Challenges.applicableModifiers(q)) do
        if mods and mods[m.id] and count < VB_Challenges.maxModifiers() then
            q.mods[m.id] = true
            count = count + 1
        end
    end
    q.basePoints = q.points
    q.points = VB_Challenges.pointsWithModifiers(q.points, q.mods)
    q.acceptedAt = nowHours()
    if q.mods.deadline then
        q.deadlineAt = q.acceptedAt + VB_Challenges.deadlineDays(difficulty) * 24
    end
    q.startKills = player:getZombieKills()
    q.counter = 0
    if q.type == "skill" and Perks[q.perk] then
        -- Goal-level quests count from 0 so progress reads as the current level.
        q.startLevel = q.goalLevel and 0 or player:getPerkLevel(Perks[q.perk])
    end
    if q.type == "roundtrip" then
        q.homeX, q.homeY = math.floor(player:getX()), math.floor(player:getY())
    end
    state.active[difficulty] = q
    state.offers[difficulty] = nil
    if count > 0 then
        notify(player, VB_Challenges.T("Notify_AcceptedRisk", VB_Challenges.questTitle(q), VB_Challenges.modifierNames(q.mods)))
    else
        notify(player, VB_Challenges.T("Notify_Accepted", VB_Challenges.questTitle(q)))
    end
    VB_Challenges.changed()
    return true
end

----------------------------------------------------------------------
-- Progress
----------------------------------------------------------------------

local function isDeliverable(item, accepted)
    if not accepted[item:getFullType()] then return false end
    -- Never eat a bag that still has stuff in it.
    if instanceof(item, "InventoryContainer") and item:getInventory():getItems():size() > 0 then
        return false
    end
    return true
end

local function findDeliverables(player, q)
    local accepted = {}
    for _, t in ipairs(VB_Challenges.deliverTypes(q)) do accepted[t] = true end
    return player:getInventory():getAllEvalRecurse(function(item)
        return isDeliverable(item, accepted)
    end)
end

-- Counting walks the whole inventory (bags included) and the HUD and window ask for
-- progress several times a second, so counts are cached briefly per item type / group.
local DELIVER_CACHE_MS = 500
local deliverCache = {} -- item or group id -> { at = ms, count = n }

local function countDeliverables(player, q)
    local key = q.itemGroup or q.item
    local now = getTimestampMs()
    local c = deliverCache[key]
    if c and now - c.at < DELIVER_CACHE_MS then return c.count end
    local count = findDeliverables(player, q):size()
    if c then
        c.at, c.count = now, count
    else
        deliverCache[key] = { at = now, count = count }
    end
    return count
end

local function invalidateDeliverCache()
    deliverCache = {}
end

-- Returns current progress (not clamped).
function VB_Challenges.getProgress(player, q)
    if q.type == "kill" then
        if VB_Challenges.hasModifier(q, "night") then return q.counter or 0 end
        return player:getZombieKills() - (q.startKills or 0)
    elseif q.type == "kill_night" or q.type == "kill_firearm" then
        return q.counter or 0
    elseif q.type == "survive" then
        return math.floor((nowHours() - q.acceptedAt) / 24)
    elseif q.type == "deliver" then
        return countDeliverables(player, q)
    elseif q.type == "skill" then
        local perk = Perks[q.perk]
        if not perk then return 0 end
        return player:getPerkLevel(perk) - (q.startLevel or 0)
    elseif VB_Challenges.Location.isLocationType(q.type) then
        return VB_Challenges.Location.progress(q)
    elseif VB_Challenges.Activity.isActivityType(q.type) then
        return q.counter or 0
    end
    return 0
end

function VB_Challenges.isReady(player, q)
    return VB_Challenges.getProgress(player, q) >= q.target
end

function VB_Challenges.abandon(player, difficulty)
    local state = VB_Challenges.getState(player)
    local q = state.active[difficulty]
    if not q then return false end
    state.active[difficulty] = nil
    state.abandoned = (state.abandoned or 0) + 1
    notify(player, VB_Challenges.T("Notify_Abandoned", VB_Challenges.questTitle(q)), false)
    VB_Challenges.changed()
    return true
end

local function removeDeliverables(player, q)
    local items = findDeliverables(player, q)
    local toRemove = math.min(q.target, items:size())
    for i = 0, toRemove - 1 do
        local item = items:get(i)
        local container = item:getContainer()
        if container then
            if player:getInventory() == container then
                player:removeAttachedItem(item)
                if player:isEquipped(item) then
                    player:removeFromHands(item)
                    player:removeWornItem(item, false)
                end
            end
            container:DoRemoveItem(item)
            sendRemoveItemFromContainer(container, item)
        end
    end
    triggerEvent("OnClothingUpdated", player)
    invalidateDeliverCache()
end

-- Adds an entry to the front of the completed/failed history, trimming the oldest.
local function recordHistory(state, q, difficulty, fields)
    local entry = {
        title = VB_Challenges.questTitle(q),
        templateId = q.templateId,
        placeId = q.placeId,
        difficulty = difficulty,
        description = VB_Challenges.describeQuest(q),
        modifiers = VB_Challenges.modifierNames(q.mods),
        day = math.floor(nowHours() / 24) + 1,
    }
    for k, v in pairs(fields) do entry[k] = v end
    table.insert(state.completed, 1, entry)
    while #state.completed > Config.MAX_COMPLETED_HISTORY do
        table.remove(state.completed)
    end
end

-- force=true skips requirements and item removal (debug only).
function VB_Challenges.claim(player, difficulty, force)
    local state = VB_Challenges.getState(player)
    local q = state.active[difficulty]
    if not q then return false end
    if not force then
        invalidateDeliverCache() -- turning items in must see the inventory as it is now
        if not VB_Challenges.isReady(player, q) then return false end
        if q.type == "deliver" then removeDeliverables(player, q) end
    end

    local points = q.points
    local bonus = false
    if (state.bonusTokens or 0) > 0 then
        state.bonusTokens = state.bonusTokens - 1
        points = math.floor(points * 1.5 + 0.5)
        bonus = true
    end

    state.active[difficulty] = nil
    recordHistory(state, q, difficulty, { points = points, bonus = bonus })

    notify(player, VB_Challenges.T("Notify_Completed", VB_Challenges.questTitle(q), points))
    VB_Challenges.addPoints(player, points) -- also fires VB_Challenges.changed()
    return true
end

----------------------------------------------------------------------
-- Levels
----------------------------------------------------------------------

-- levelUpSoundDelay: ms to wait before the level-up sound (default: immediately).
function VB_Challenges.addPoints(player, amount, levelUpSoundDelay)
    local state = VB_Challenges.getState(player)
    state.totalPoints = state.totalPoints + amount
    state.levelPoints = state.levelPoints + amount
    local leveled = false
    while state.levelPoints >= VB_Challenges.pointsToNext(state) do
        state.levelPoints = state.levelPoints - VB_Challenges.pointsToNext(state)
        state.level = state.level + 1
        table.insert(state.pendingRewards, {
            level = state.level,
            choices = VB_Challenges.generateRewardChoices(player, state.level),
        })
        leveled = true
    end
    if leveled then
        notify(player, VB_Challenges.T("Notify_LevelUp", state.level))
        VB_Challenges.Sounds.levelUp(levelUpSoundDelay)
        if VB_Challenges.UI and VB_Challenges.UI.openOnPage then VB_Challenges.UI.openOnPage("level") end
    end
    VB_Challenges.changed()
end

----------------------------------------------------------------------
-- Traits
----------------------------------------------------------------------

local function normId(v)
    return string.lower(tostring(v)):gsub("[^%w]", "")
end

local function findTraitDef(id)
    local want = normId(id)
    local defs = CharacterTraitDefinition.getTraits()
    for i = 0, defs:size() - 1 do
        local def = defs:get(i)
        local n = normId(def:getType())
        if n == want or n == "base" .. want then return def end
    end
    return nil
end

local function blockedByExclusive(player, def)
    local ok, blocked = pcall(function()
        local list = def:getMutuallyExclusiveTraits()
        if not list then return false end
        for i = 0, list:size() - 1 do
            if player:hasTrait(list:get(i)) then return true end
        end
        return false
    end)
    return ok and blocked
end

local function gainableTraits(player)
    local out = {}
    for _, id in ipairs(VB_Challenges.GainableTraits) do
        local def = findTraitDef(id)
        if def and not player:hasTrait(def:getType()) and not blockedByExclusive(player, def) then
            table.insert(out, { id = id, label = def:getLabel() })
        end
    end
    return out
end

local function removableTraits(player)
    local out = {}
    local known = player:getCharacterTraits():getKnownTraits()
    for i = 0, known:size() - 1 do
        local def = CharacterTraitDefinition.getCharacterTraitDefinition(known:get(i))
        if def then
            local cost = def:getCost()
            if cost < 0 and cost >= VB_Challenges.MIN_REMOVABLE_TRAIT_COST then
                table.insert(out, { id = normId(def:getType()), label = def:getLabel() })
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Rewards
----------------------------------------------------------------------

local function makeReward(player, category, level)
    if category == "items" then
        local bundle = VB_Challenges.pick(VB_Challenges.ItemBundles[VB_Challenges.rewardTier(level)])
        return { category = "items", bundleId = bundle.id, items = bundle.items }
    elseif category == "xp" then
        local perks = {}
        for _, p in ipairs(VB_Challenges.XpPerks) do
            if Perks[p] and player:getPerkLevel(Perks[p]) < 10 then table.insert(perks, p) end
        end
        local perk = VB_Challenges.pick(perks)
        if not perk then return nil end
        return { category = "xp", perk = perk, amount = VB_Challenges.xpRewardAmount(level) }
    elseif category == "token" then
        if ZombRand(2) == 0 then
            return { category = "token", token = "reroll", count = 2 }
        end
        return { category = "token", token = "bonus", count = 1 }
    elseif category == "trait" then
        local remove = removableTraits(player)
        local gain = gainableTraits(player)
        if #remove > 0 and (#gain == 0 or ZombRand(2) == 0) then
            local t = VB_Challenges.pick(remove)
            return { category = "trait", mode = "remove", trait = t.id, traitLabel = t.label }
        elseif #gain > 0 then
            local t = VB_Challenges.pick(gain)
            return { category = "trait", mode = "gain", trait = t.id, traitLabel = t.label }
        end
    end
    return nil
end

-- Display text for a reward choice (old saves stored English label/detail).
function VB_Challenges.rewardLabel(r)
    if r.category == "items" and r.bundleId then
        return VB_Challenges.T("Reward_Items", VB_Challenges.T("Bundle_" .. r.bundleId))
    elseif r.category == "xp" and r.perk then
        return VB_Challenges.T("Reward_Xp", VB_Challenges.perkName(r.perk))
    elseif r.category == "token" and r.token then
        return VB_Challenges.T(r.token == "reroll" and "Reward_Reroll" or "Reward_Bounty", r.count or 1)
    elseif r.category == "trait" and r.traitLabel then
        return VB_Challenges.T(r.mode == "remove" and "Reward_TraitRemove" or "Reward_TraitGain", r.traitLabel)
    end
    return r.label or "?"
end

function VB_Challenges.rewardDetail(r)
    if r.category == "items" and r.bundleId then
        local parts = {}
        for _, it in ipairs(r.items) do
            table.insert(parts, VB_Challenges.T("Reward_ItemsEntry", it[2], VB_Challenges.itemName(it[1])))
        end
        return VB_Challenges.T("Reward_ItemsDetail", table.concat(parts, ", "))
    elseif r.category == "xp" and r.perk then
        return VB_Challenges.T("Reward_XpDetail", r.amount, VB_Challenges.perkName(r.perk))
    elseif r.category == "token" and r.token then
        return VB_Challenges.T(r.token == "reroll" and "Reward_RerollDetail" or "Reward_BountyDetail")
    elseif r.category == "trait" and r.traitLabel then
        return VB_Challenges.T(r.mode == "remove" and "Reward_TraitRemoveDetail" or "Reward_TraitGainDetail", r.traitLabel)
    end
    return r.detail or ""
end

function VB_Challenges.isTraitLevel(level)
    local every = VB_Challenges.traitRewardEvery()
    return every > 0 and level % every == 0
end

-- Two choices from two different categories. Every VB_Challenges.traitRewardEvery() levels,
-- one of the choices is guaranteed to be a trait reward (when one is possible).
function VB_Challenges.generateRewardChoices(player, level)
    local choices = {}
    local used = {}
    if VB_Challenges.isTraitLevel(level) and VB_Challenges.rewardCategoryEnabled("trait") then
        local r = makeReward(player, "trait", level)
        if r then table.insert(choices, r); used.trait = true end
    end
    local guard = 0
    while #choices < 2 and guard < 20 do
        guard = guard + 1
        local cats, fallback = {}, {}
        for _, c in ipairs(VB_Challenges.RewardCategories) do
            if c.id ~= "trait" and VB_Challenges.rewardCategoryEnabled(c.id) then
                table.insert(fallback, c)
                if not used[c.id] then table.insert(cats, c) end
            end
        end
        -- With fewer than two categories enabled, the same category may appear twice.
        local cat = VB_Challenges.pickWeighted(#cats > 0 and cats or fallback)
        if not cat then break end
        used[cat.id] = true
        local r = makeReward(player, cat.id, level)
        if r then table.insert(choices, r) end
    end
    return choices
end

local function applyReward(player, state, r)
    if r.category == "items" then
        local sq = player:getCurrentSquare()
        for _, it in ipairs(r.items) do
            for _ = 1, it[2] do
                if sq then
                    sq:AddWorldInventoryItem(it[1], ZombRand(20, 80) / 100, ZombRand(20, 80) / 100, 0)
                else
                    player:getInventory():AddItem(it[1])
                end
            end
        end
    elseif r.category == "xp" then
        local perk = Perks[r.perk]
        if perk then
            player:getXp():AddXP(perk, r.amount, false, false, false, false)
            SyncXp(player)
        end
    elseif r.category == "token" then
        if r.token == "reroll" then
            state.rerollTokens = state.rerollTokens + (r.count or 1)
        else
            state.bonusTokens = (state.bonusTokens or 0) + (r.count or 1)
        end
    elseif r.category == "trait" then
        local def = findTraitDef(r.trait)
        if not def then return false end
        local t = def:getType()
        if r.mode == "gain" then
            if player:hasTrait(t) then return false end
            player:getCharacterTraits():add(t)
            player:modifyTraitXPBoost(t, false)
        else
            if not player:hasTrait(t) then return false end
            player:getCharacterTraits():remove(t)
            player:modifyTraitXPBoost(t, true)
        end
        SyncXp(player)
    end
    return true
end

function VB_Challenges.chooseReward(player, choiceIndex)
    local state = VB_Challenges.getState(player)
    local pending = state.pendingRewards[1]
    if not pending then return false end
    local r = pending.choices[choiceIndex]
    if not r then return false end
    if not applyReward(player, state, r) then
        -- Trait no longer valid (e.g. gained it another way): regenerate the choices.
        pending.choices = VB_Challenges.generateRewardChoices(player, pending.level)
        notify(player, VB_Challenges.T("Notify_RewardRerolled"), false)
        VB_Challenges.changed()
        return false
    end
    table.remove(state.pendingRewards, 1)
    notify(player, VB_Challenges.T("Notify_Reward", VB_Challenges.rewardLabel(r)))
    VB_Challenges.changed()
    return true
end

----------------------------------------------------------------------
-- Event hooks
----------------------------------------------------------------------

local lastKills = {}

local function holdingFirearm(player)
    local w = player:getPrimaryHandItem()
    return w ~= nil and instanceof(w, "HandWeapon") and w:isRanged()
end

local function onPlayerUpdate(player)
    if not player or player:isDead() then return end
    local num = player:getPlayerNum()
    local kills = player:getZombieKills()
    local last = lastKills[num]
    lastKills[num] = kills
    if not last or kills <= last then return end

    local delta = kills - last
    local state = player:getModData().VB_Challenges
    if not state then return end
    local night, gun = VB_Challenges.isNight(), holdingFirearm(player)
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and ((q.type == "kill_night" and night) or (q.type == "kill_firearm" and gun)
                or (q.type == "kill" and night and VB_Challenges.hasModifier(q, "night"))) then
            q.counter = (q.counter or 0) + delta
        end
    end
end

----------------------------------------------------------------------
-- Modifiers: failing quests
----------------------------------------------------------------------

function VB_Challenges.hoursUntilDeadline(q)
    if not q.deadlineAt then return nil end
    return q.deadlineAt - nowHours()
end

-- reason: "deadline" | "gunshot" (translation key suffix). Old saves stored English text.
function VB_Challenges.failReasonText(reason)
    if reason == "deadline" or reason == "gunshot" then return VB_Challenges.T("FailReason_" .. reason) end
    return tostring(reason or "?")
end

function VB_Challenges.failQuest(player, difficulty, reason)
    local state = VB_Challenges.getState(player)
    local q = state.active[difficulty]
    if not q then return end
    state.active[difficulty] = nil
    state.failed = (state.failed or 0) + 1
    recordHistory(state, q, difficulty, { points = 0, failed = true, reasonKey = reason })
    notify(player, VB_Challenges.T("Notify_Failed", VB_Challenges.questTitle(q), VB_Challenges.failReasonText(reason)), false)
    VB_Challenges.changed()
end

-- Once the objective is met in time, the deadline can no longer fail the quest.
local function checkDeadlines(player, state)
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and q.deadlineAt and not q.deadlineMet then
            if VB_Challenges.isReady(player, q) then
                q.deadlineMet = true
            elseif nowHours() > q.deadlineAt then
                VB_Challenges.failQuest(player, d, "deadline")
            end
        end
    end
end

local function failNoFirearmQuests(player, state)
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and VB_Challenges.hasModifier(q, "nofirearms") and not VB_Challenges.isReady(player, q) then
            VB_Challenges.failQuest(player, d, "gunshot")
        end
    end
end

local function onWeaponFired(character, weapon)
    local player = getPlayer()
    if character ~= player or not weapon or not weapon:isRanged() then return end
    local state = player:getModData().VB_Challenges
    if state then failNoFirearmQuests(player, state) end
end
Events.OnWeaponSwingHitPoint.Add(onWeaponFired)

local function checkReadyQuests()
    local player = getPlayer()
    if not player or player:isDead() then return end
    local state = player:getModData().VB_Challenges
    if not state then return end
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and not q.notified and VB_Challenges.isReady(player, q) then
            q.notified = true
            notify(player, VB_Challenges.T("Notify_Ready", VB_Challenges.questTitle(q)))
            VB_Challenges.changed()
        end
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
-- Free reroll token: after freeRerollHours() in-game hours with no reroll tokens, the
-- player gets one. The clock (state.noRerollSince, world-age hours) starts when they run out.
function VB_Challenges.hoursUntilFreeReroll(state)
    local every = VB_Challenges.freeRerollHours()
    if every <= 0 or state.rerollTokens > 0 or not state.noRerollSince then return nil end
    return math.max(0, every - (nowHours() - state.noRerollSince))
end

local function checkFreeReroll(player, state)
    local every = VB_Challenges.freeRerollHours()
    if every <= 0 or state.rerollTokens > 0 then
        state.noRerollSince = nil
        return
    end
    if not state.noRerollSince then
        state.noRerollSince = nowHours()
    elseif nowHours() - state.noRerollSince >= every then
        state.rerollTokens = 1
        state.noRerollSince = nil
        notify(player, VB_Challenges.T("Notify_FreeReroll"))
        VB_Challenges.changed()
    end
end

Events.EveryOneMinute.Add(function()
    local player = getPlayer()
    if not player or player:isDead() then return end
    local state = player:getModData().VB_Challenges
    if not state then return end
    VB_Challenges.Location.tick(player, state, notify)
    VB_Challenges.Activity.tick(player)
    checkDeadlines(player, state)
    checkReadyQuests()
    checkFreeReroll(player, state)
    -- Settle level-ups owed after the curve or LevelCurveMultiplier changed on an existing save.
    if state.levelPoints >= VB_Challenges.pointsToNext(state) then VB_Challenges.addPoints(player, 0) end
end)
Events.OnGameStart.Add(function()
    lastKills = {}
    invalidateDeliverCache()
    VB_Challenges.log("Loaded v" .. VB_Challenges.VERSION)
end)

----------------------------------------------------------------------
-- Debug actions (only exposed in the UI when the game runs with -debug)
----------------------------------------------------------------------

function VB_Challenges.Debug.addPoints(n)
    VB_Challenges.addPoints(getPlayer(), n)
end

function VB_Challenges.Debug.levelUp()
    local s = VB_Challenges.getState()
    VB_Challenges.addPoints(getPlayer(), VB_Challenges.pointsToNext(s) - s.levelPoints)
end

function VB_Challenges.Debug.addPendingReward()
    local s = VB_Challenges.getState()
    table.insert(s.pendingRewards, { level = s.level, choices = VB_Challenges.generateRewardChoices(getPlayer(), s.level) })
    VB_Challenges.changed()
end

function VB_Challenges.Debug.addTraitReward()
    local s = VB_Challenges.getState()
    local lvl = s.level
    while not VB_Challenges.isTraitLevel(lvl) do lvl = lvl + 1 end
    table.insert(s.pendingRewards, { level = lvl, choices = VB_Challenges.generateRewardChoices(getPlayer(), lvl) })
    VB_Challenges.changed()
end

function VB_Challenges.Debug.resetAll()
    getPlayer():getModData().VB_Challenges = nil
    VB_Challenges.getState()
    VB_Challenges.changed()
end

function VB_Challenges.Debug.resetScore()
    local s = VB_Challenges.getState()
    s.level, s.levelPoints, s.totalPoints, s.pendingRewards = 1, 0, 0, {}
    VB_Challenges.changed()
end

function VB_Challenges.Debug.clearCompleted()
    VB_Challenges.getState().completed = {}
    VB_Challenges.changed()
end

function VB_Challenges.Debug.forceComplete(d)
    VB_Challenges.claim(getPlayer(), d, true)
end

function VB_Challenges.Debug.makeReady(d)
    local player = getPlayer()
    local q = VB_Challenges.getState().active[d]
    if not q then return end
    if q.type == "kill" then
        q.startKills = player:getZombieKills() - q.target
    elseif q.type == "kill_night" or q.type == "kill_firearm" then
        q.counter = q.target
    elseif q.type == "survive" then
        q.acceptedAt = math.min(q.acceptedAt, nowHours() - q.target * 24)
    elseif q.type == "deliver" then
        local missing = q.target - VB_Challenges.getProgress(player, q)
        local itemType = VB_Challenges.deliverTypes(q)[1]
        for _ = 1, missing do player:getInventory():AddItem(itemType) end
        invalidateDeliverCache()
    elseif q.type == "skill" then
        q.startLevel = player:getPerkLevel(Perks[q.perk]) - q.target
    elseif q.type == "visit" then
        q.stage = 1
    elseif q.type == "roundtrip" then
        q.stage = 2
    elseif q.type == "overnight" or VB_Challenges.Activity.isActivityType(q.type) then
        q.counter = q.target
    end
    VB_Challenges.changed()
end

function VB_Challenges.Debug.expireDeadline(d)
    local q = VB_Challenges.getState().active[d]
    if q and q.deadlineAt then
        q.deadlineMet = false
        q.deadlineAt = nowHours() - 0.01
        checkDeadlines(getPlayer(), VB_Challenges.getState())
    end
end

function VB_Challenges.Debug.simulateGunshot()
    local player = getPlayer()
    failNoFirearmQuests(player, VB_Challenges.getState(player))
end

-- Teleports to the current goal of a location quest (target building, or start point).
function VB_Challenges.Debug.teleportToTarget(d)
    local q = VB_Challenges.getState().active[d]
    if not q or not VB_Challenges.Location.isLocationType(q.type) then return end
    local x, y = VB_Challenges.Location.currentGoal(q)
    if x then getPlayer():teleportTo(x + 0.5, y + 0.5, 0) end
end

function VB_Challenges.Debug.teleportToCache(d)
    local q = VB_Challenges.getState().active[d]
    if not q or q.cacheState ~= "hidden" then return end
    getPlayer():teleportTo(q.cacheX + 1.5, q.cacheY + 0.5, q.cacheZ)
end

function VB_Challenges.Debug.newOffers(d)
    VB_Challenges.generateOffers(getPlayer(), d)
end

function VB_Challenges.Debug.addTokens()
    local s = VB_Challenges.getState()
    s.rerollTokens = s.rerollTokens + 1
    s.bonusTokens = (s.bonusTokens or 0) + 1
    VB_Challenges.changed()
end

local function dump(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(indent .. tostring(k) .. ":")
            dump(v, indent .. "  ")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

function VB_Challenges.Debug.dumpState()
    VB_Challenges.log("---- state dump ----")
    dump(VB_Challenges.getState())
    local player = getPlayer()
    for _, id in ipairs(VB_Challenges.GainableTraits) do
        local def = findTraitDef(id)
        VB_Challenges.log("trait '" .. id .. "' -> " .. (def and (tostring(def:getType()) .. " / " .. def:getLabel()) or "NOT FOUND"))
    end
    VB_Challenges.log("gainable now: " .. #gainableTraits(player) .. ", removable now: " .. #removableTraits(player))
end
