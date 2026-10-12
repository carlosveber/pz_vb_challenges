-- VB_Challenges: location quests ("go there").
--
-- Targets are real buildings found through the world meta grid, which knows every
-- room on the map (loaded or not). A building qualifies when one of its rooms has a
-- name from the place's room list (the same room names the loot tables use).
--
-- Objective types:
--   visit      step inside the target building
--   roundtrip  step inside, then get back to where you accepted the quest
--   overnight  spend N minutes inside the target between 22:00 and 05:00
require "VB_Challenges_Shared"

VB_Challenges.Location = VB_Challenges.Location or {}
local L = VB_Challenges.Location

L.TYPES = { visit = true, roundtrip = true, overnight = true }
L.NIGHT_START, L.NIGHT_END = 22, 5
L.HOME_RADIUS = 25 -- tiles from the start point that count as "back"

-- Place categories -> vanilla room names.
-- Names come from UI_VB_Challenges_Place_<id> (in sentences) and UI_VB_Challenges_PlaceTitle_<id> (in titles).
VB_Challenges.Places = {
    police    = { rooms = { "policestorage", "policeoffice", "policegunstorage" } },
    gunstore  = { rooms = { "gunstore", "gunstorestorage" } },
    pharmacy  = { rooms = { "pharmacy", "pharmacystorage" } },
    medical   = { rooms = { "medical", "medicalstorage", "hospitalroom" } },
    fire      = { rooms = { "firestorage" } },
    grocery   = { rooms = { "grocery", "gigamart", "generalstore", "cornerstore", "zippeestore" } },
    gas       = { rooms = { "gasstore", "gasstorage" } },
    school    = { rooms = { "classroom" } },
    library   = { rooms = { "library" } },
    church    = { rooms = { "church" } },
    army      = { rooms = { "armystorage", "armysurplus" } },
    tools     = { rooms = { "toolstore", "toolstorestorage" } },
    mechanic  = { rooms = { "mechanic" } },
    warehouse = { rooms = { "warehouse" } },
    bar       = { rooms = { "bar", "liquorstore" } },
    motel     = { rooms = { "motelroom" } },
    sports    = { rooms = { "sportstore", "sportstorage" } },
    camping   = { rooms = { "camping" } },
    prison    = { rooms = { "prisoncells" } },
    farm      = { rooms = { "barn", "farmstorage" } },
}

-- Town centres (from the vanilla spawn points / map badges), used to name places.
VB_Challenges.Towns = {
    { name = "Muldraugh",      x = 10770, y = 10037 },
    { name = "West Point",     x = 11635, y = 6868 },
    { name = "Riverside",      x = 6167,  y = 5375 },
    { name = "Rosewood",       x = 8125,  y = 11624 },
    { name = "March Ridge",    x = 9883,  y = 12812 },
    { name = "Valley Station", x = 13700, y = 5600 },
    { name = "Louisville",     x = 13000, y = 2500 },
    { name = "Fallas Lake",    x = 7213,  y = 8288 },
    { name = "Ekron",          x = 411,   y = 9761 },
    { name = "Brandenburg",    x = 2152,  y = 6089 },
    { name = "Irvington",      x = 1912,  y = 14381 },
    { name = "Echo Creek",     x = 3573,  y = 10899 },
}

function L.isLocationType(t)
    return L.TYPES[t] == true
end

-- Nearest town to a point: returns name, "in" | "near" (or nil when far from any town).
function L.nearestTown(x, y)
    local best, bestD
    for _, t in ipairs(VB_Challenges.Towns) do
        local d = math.sqrt((t.x - x) ^ 2 + (t.y - y) ^ 2)
        if not bestD or d < bestD then best, bestD = t, d end
    end
    if not best then return nil end
    if bestD < 1200 then return best.name, "in" end
    if bestD < 3000 then return best.name, "near" end
    return nil
end

function L.placeName(q)
    if q.placeId then return VB_Challenges.T("Place_" .. q.placeId) end
    return q.placeLabel or "?"
end

-- " in Rosewood" / " near Muldraugh" / "" (old saves stored the English phrase).
function L.townPhrase(q)
    if q.townName then
        return VB_Challenges.T(q.townRel == "in" and "Town_In" or "Town_Near", q.townName)
    end
    return q.town or ""
end

-- Map directions: north is up on the world map (-y), east is +x.
-- (Ratio-based so it doesn't depend on math.atan2 being available in Kahlua.)
local TAN_22_5 = 0.41421356
function L.direction(dx, dy)
    if math.abs(dx) < 1 and math.abs(dy) < 1 then return "" end
    local ax, ay = math.abs(dx), math.abs(dy)
    local ns = dy < 0 and "N" or "S"
    local ew = dx > 0 and "E" or "W"
    if ay <= ax * TAN_22_5 then return ew end
    if ax <= ay * TAN_22_5 then return ns end
    return ns .. ew
end

function L.formatDistance(meters)
    if meters >= 1000 then return string.format("%.1f km", meters / 1000) end
    return string.format("%d m", math.floor(meters / 10 + 0.5) * 10)
end

-- Short form for the HUD tile: "1.2k" / "350"
function L.formatDistanceShort(meters)
    if meters >= 1000 then return string.format("%.1fk", meters / 1000) end
    return tostring(math.floor(meters / 10 + 0.5) * 10)
end

----------------------------------------------------------------------
-- Finding targets
----------------------------------------------------------------------

local function roomSetFor(placeIds)
    local set = {}
    for _, id in ipairs(placeIds) do
        local p = VB_Challenges.Places[id]
        if p then
            for _, r in ipairs(p.rooms) do set[r] = id end
        end
    end
    return set
end

-- Returns a list of candidate buildings { placeId, buildingId, x1, y1, x2, y2, cx, cy, dist }
-- whose centre is between minD and maxD tiles from (px, py).
function L.findCandidates(px, py, placeIds, minD, maxD)
    local roomSet = roomSetFor(placeIds)
    local list = ArrayList.new()
    getWorld():getMetaGrid():getRoomsIntersecting(math.floor(px - maxD), math.floor(py - maxD),
        math.floor(maxD * 2), math.floor(maxD * 2), list)
    local seen, out = {}, {}
    for i = 0, list:size() - 1 do
        local room = list:get(i)
        local placeId = roomSet[string.lower(room:getName() or "")]
        if placeId then
            local b = room:getBuilding()
            if b then
                local bid = b:getIDString()
                if not seen[bid] then
                    seen[bid] = true
                    local cx, cy = (b:getX() + b:getX2()) / 2, (b:getY() + b:getY2()) / 2
                    local d = math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2)
                    if d >= minD and d <= maxD then
                        table.insert(out, {
                            placeId = placeId, buildingId = bid,
                            x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2(),
                            cx = math.floor(cx), cy = math.floor(cy), dist = d,
                        })
                    end
                end
            end
        end
    end
    return out
end

-- Fills q with a target for `template`. Returns false when nothing suitable exists nearby.
function L.build(player, q, template)
    if not VB_Challenges.locationChallengesEnabled() then return false end
    local px, py = player:getX(), player:getY()
    local mult = VB_Challenges.locationDistanceMultiplier()
    local minD, maxD = template.minDist * mult, template.maxDist * mult
    local cands = L.findCandidates(px, py, template.places, minD, maxD)
    if #cands == 0 then
        -- Sparse area: widen the search once before giving up.
        cands = L.findCandidates(px, py, template.places, minD * 0.5, maxD * 2)
    end
    if #cands == 0 then return false end
    local c = VB_Challenges.pick(cands)
    q.placeId = c.placeId
    q.buildingId = c.buildingId
    q.bx1, q.by1, q.bx2, q.by2 = c.x1, c.y1, c.x2, c.y2
    q.tx, q.ty = c.cx, c.cy
    q.townName, q.townRel = L.nearestTown(c.cx, c.cy)
    q.stage = 0
    q.counter = 0

    if q.type == "overnight" then
        q.target = (template.nightHours or 4) * 60
    elseif q.type == "roundtrip" then
        q.target = 2
    else
        q.target = 1
    end
    -- Farther targets are worth a little more (90% .. 110%).
    local span = maxD - minD
    local f = span > 0 and math.max(0, math.min(1, (c.dist - minD) / span)) or 0.5
    q.scale = 0.9 + 0.2 * f
    return true
end

----------------------------------------------------------------------
-- Progress
----------------------------------------------------------------------

function L.isInside(player, q)
    local sq = player:getCurrentSquare()
    if not sq then return false end
    local room = sq:getRoom()
    if not room then return false end
    local def = room:getRoomDef()
    local b = def and def:getBuilding()
    if b and b:getIDString() == q.buildingId then return true end
    -- Fallback: inside any room within the building's bounds.
    local x, y = sq:getX(), sq:getY()
    return x >= q.bx1 and x <= q.bx2 and y >= q.by1 and y <= q.by2
end

-- Night-stay window (L.NIGHT_START..L.NIGHT_END); differs from VB_Challenges.isNight used for kills.
local function inOvernightWindow()
    local h = getGameTime():getHour()
    return h >= L.NIGHT_START or h < L.NIGHT_END
end

function L.progress(q)
    if q.type == "overnight" then return q.counter or 0 end
    return q.stage or 0
end

-- The point the player should currently head to: { x, y, label }
function L.currentGoal(q)
    if q.type == "roundtrip" and (q.stage or 0) >= 1 and q.homeX then
        return q.homeX, q.homeY, VB_Challenges.T("Loc_StartPoint")
    end
    return q.tx, q.ty, L.placeName(q)
end

function L.distanceText(player, q, short)
    local gx, gy = L.currentGoal(q)
    if not gx then return "" end
    local dx, dy = gx - player:getX(), gy - player:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    local dir = L.direction(dx, dy)
    if short then return L.formatDistanceShort(d), dir end
    return L.formatDistance(d) .. (dir ~= "" and (" " .. dir) or "")
end

function L.describe(q)
    local where = VB_Challenges.T("Loc_Where", L.placeName(q), L.townPhrase(q))
    local text = ""
    if q.type == "visit" then
        text = VB_Challenges.T("Desc_visit", where)
    elseif q.type == "roundtrip" then
        text = VB_Challenges.T("Desc_roundtrip", where)
    elseif q.type == "overnight" then
        text = VB_Challenges.T("Desc_overnight", math.floor(q.target / 60), where,
            string.format("%02d:00", L.NIGHT_START), string.format("%02d:00", L.NIGHT_END))
    end
    if text ~= "" and VB_Challenges.locationCachesEnabled() and q.cacheState ~= "none" then
        text = text .. " " .. VB_Challenges.T("Loc_CacheBonus")
    end
    return text
end

function L.formatProgress(q, progress)
    if q.type == "visit" then
        return VB_Challenges.T(progress >= 1 and "Loc_Reached" or "Loc_NotReached")
    elseif q.type == "roundtrip" then
        if progress >= 2 then return VB_Challenges.T("Loc_BackAtStart") end
        if progress >= 1 then return VB_Challenges.T("Loc_HeadBack") end
        return VB_Challenges.T("Loc_HeadToTarget")
    elseif q.type == "overnight" then
        return VB_Challenges.T("Loc_NightHours", string.format("%.1f", math.min(progress, q.target) / 60), math.floor(q.target / 60))
    end
    return ""
end

----------------------------------------------------------------------
-- Supply caches: the first time you step inside the target building, a bag of
-- supplies is hidden somewhere on your floor of it. The quest card gives a
-- hot/cold hint until you get close enough to spot it.
----------------------------------------------------------------------

L.CACHE_BAG = "Base.Bag_DuffelBag"
L.CACHE_MIN_DIST = 8     -- tiles from the player; it should take some searching
L.CACHE_FOUND_DIST = 2.5 -- tiles; close enough to see it
L.CACHE_TRIES = 300      -- random squares sampled per attempt
L.CACHE_MAX_ATTEMPTS = 5 -- in-game minutes of failed searches before dropping it at your feet
L.CACHE_HOT, L.CACHE_WARM, L.CACHE_COLD = 6, 15, 40

-- Bundle tier offset per difficulty, relative to the level's reward tier.
local CACHE_TIER_OFFSET = { easy = -1, medium = 0, hard = 1 }
-- Too bulky to hide in a bag.
local CACHE_EXCLUDED_BUNDLES = { generator = true }

local function buildingIdAt(sq)
    local room = sq:getRoom()
    local def = room and room:getRoomDef()
    local b = def and def:getBuilding()
    return b and b:getIDString()
end

-- A random free square in the target building on the player's floor, preferably
-- not right next to the player. Only loaded squares qualify.
local function findCacheSquare(player, q)
    local cell = getCell()
    local z = math.floor(player:getZ())
    local px, py = player:getX(), player:getY()
    local near
    for _ = 1, L.CACHE_TRIES do
        local x, y = VB_Challenges.randInt(q.bx1, q.bx2), VB_Challenges.randInt(q.by1, q.by2)
        local sq = cell:getGridSquare(x, y, z)
        if sq and sq:isFree(false) and buildingIdAt(sq) == q.buildingId then
            local dx, dy = x - px, y - py
            if dx * dx + dy * dy >= L.CACHE_MIN_DIST * L.CACHE_MIN_DIST then return sq end
            near = near or sq
        end
    end
    return near
end

local function pickCacheBundle(level, difficulty)
    local tier = VB_Challenges.rewardTier(level) + (CACHE_TIER_OFFSET[difficulty] or 0)
    tier = math.max(1, math.min(tier, #VB_Challenges.ItemBundles))
    local pool = {}
    for _, b in ipairs(VB_Challenges.ItemBundles[tier]) do
        if not CACHE_EXCLUDED_BUNDLES[b.id] then table.insert(pool, b) end
    end
    return VB_Challenges.pick(pool)
end

local function spawnCache(sq, bundle)
    local bag = sq:AddWorldInventoryItem(L.CACHE_BAG, ZombRand(20, 80) / 100, ZombRand(20, 80) / 100, 0)
    local inv = bag and bag.getItemContainer and bag:getItemContainer()
    if bag then
        pcall(function()
            bag:setName(VB_Challenges.T("Cache_BagName"))
            bag:setCustomName(true)
        end)
    end
    for _, it in ipairs(bundle.items) do
        for _ = 1, it[2] do
            if inv then
                inv:AddItem(it[1])
            else
                sq:AddWorldInventoryItem(it[1], ZombRand(20, 80) / 100, ZombRand(20, 80) / 100, 0)
            end
        end
    end
end

-- Tries to hide the cache once the player is inside. Returns true when it was placed.
local function tryHideCache(player, state, q, difficulty)
    local sq = findCacheSquare(player, q)
    q.cacheAttempts = (q.cacheAttempts or 0) + 1
    if not sq then
        if q.cacheAttempts < L.CACHE_MAX_ATTEMPTS then return false end
        sq = player:getCurrentSquare()
        if not sq then return false end
    end
    local bundle = pickCacheBundle(state.level or 1, difficulty)
    if not bundle then
        q.cacheState = "none"
        return false
    end
    spawnCache(sq, bundle)
    q.cacheState = "hidden"
    q.cacheX, q.cacheY, q.cacheZ = sq:getX(), sq:getY(), sq:getZ()
    return true
end

local function updateCache(player, state, q, difficulty, notify)
    if q.cacheState == nil then
        if not VB_Challenges.locationCachesEnabled() or not L.isInside(player, q) then return end
        local ok, placed = pcall(tryHideCache, player, state, q, difficulty)
        if not ok then
            VB_Challenges.log("Could not hide supply cache: " .. tostring(placed))
            q.cacheState = "none"
        elseif placed then
            notify(player, VB_Challenges.T("Notify_CacheHidden"))
            VB_Challenges.changed()
        end
    elseif q.cacheState == "hidden" then
        local dx, dy = player:getX() - (q.cacheX + 0.5), player:getY() - (q.cacheY + 0.5)
        if math.floor(player:getZ()) == q.cacheZ and dx * dx + dy * dy <= L.CACHE_FOUND_DIST * L.CACHE_FOUND_DIST then
            q.cacheState = "found"
            notify(player, VB_Challenges.T("Notify_CacheFound"))
            VB_Challenges.changed()
        end
    end
end

-- Hot/cold hint for a hidden cache, or nil when there is nothing to search for.
function L.cacheHint(player, q)
    if q.cacheState ~= "hidden" then return nil end
    if math.floor(player:getZ()) ~= q.cacheZ and L.isInside(player, q) then
        return VB_Challenges.T("Cache_OtherFloor")
    end
    local dx, dy = player:getX() - q.cacheX, player:getY() - q.cacheY
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= L.CACHE_HOT then return VB_Challenges.T("Cache_Hot") end
    if d <= L.CACHE_WARM then return VB_Challenges.T("Cache_Warm") end
    if d <= L.CACHE_COLD then return VB_Challenges.T("Cache_Cold") end
    return VB_Challenges.T("Cache_Far", L.placeName(q))
end

-- Called once per in-game minute.
function L.tick(player, state, notify)
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and L.isLocationType(q.type) then
            updateCache(player, state, q, d, notify)
            local before = L.progress(q)
            -- "Only at night" modifier: reaching the target only counts at night.
            local canReach = not VB_Challenges.hasModifier or not VB_Challenges.hasModifier(q, "night") or VB_Challenges.isNight()
            if q.type == "visit" then
                if (q.stage or 0) < 1 and canReach and L.isInside(player, q) then q.stage = 1 end
            elseif q.type == "roundtrip" then
                if (q.stage or 0) == 0 and canReach and L.isInside(player, q) then
                    q.stage = 1
                    notify(player, VB_Challenges.T("Notify_TargetReached"))
                elseif q.stage == 1 and q.homeX then
                    local dx, dy = player:getX() - q.homeX, player:getY() - q.homeY
                    if dx * dx + dy * dy <= L.HOME_RADIUS * L.HOME_RADIUS then q.stage = 2 end
                end
            elseif q.type == "overnight" then
                if (q.counter or 0) < q.target and inOvernightWindow() and L.isInside(player, q) then
                    q.counter = (q.counter or 0) + 1
                end
            end
            if L.progress(q) ~= before then VB_Challenges.changed() end
        end
    end
end

----------------------------------------------------------------------
-- World map marker
----------------------------------------------------------------------

local function drawMarker(ui, mapAPI, x, y, color, label)
    local ux, uy = mapAPI:worldToUIX(x, y), mapAPI:worldToUIY(x, y)
    local s = 12
    ui:drawRect(ux - s / 2 - 2, uy - s / 2 - 2, s + 4, s + 4, 0.9, 0, 0, 0)
    ui:drawRect(ux - s / 2, uy - s / 2, s, s, 1, color.r, color.g, color.b)
    local tw = getTextManager():MeasureStringX(UIFont.Small, label)
    local th = getTextManager():getFontHeight(UIFont.Small)
    ui:drawRect(ux - tw / 2 - 4, uy + s / 2 + 3, tw + 8, th + 2, 0.75, 0, 0, 0)
    ui:drawTextCentre(label, ux, uy + s / 2 + 4, color.r, color.g, color.b, 1, UIFont.Small)
end

function L.drawMapMarkers(ui)
    local player = getPlayer()
    local mapAPI = ui.mapAPI
    if not player or not mapAPI then return end
    local state = player:getModData().VB_Challenges
    if not state then return end
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        if q and L.isLocationType(q.type) and q.tx then
            local color = VB_Challenges.DIFFICULTY_COLOR[d]
            local stage = q.stage or 0
            local showTarget = (q.type == "visit" and stage < 1)
                or (q.type == "roundtrip" and stage == 0)
                or (q.type == "overnight" and (q.counter or 0) < q.target)
            if showTarget then
                drawMarker(ui, mapAPI, q.tx, q.ty, color, VB_Challenges.T("Map_Marker", VB_Challenges.questTitle(q)))
            end
            if q.type == "roundtrip" and stage == 1 and q.homeX then
                drawMarker(ui, mapAPI, q.homeX, q.homeY, color, VB_Challenges.T("Map_ReturnHere"))
            end
        end
    end
end

local hooked = false
Events.OnGameStart.Add(function()
    if hooked or not ISWorldMap then return end
    hooked = true
    local original = ISWorldMap.render
    ISWorldMap.render = function(self, ...)
        original(self, ...)
        pcall(L.drawMapMarkers, self)
    end
end)
