-- VB_Challenges: compact moodle-style tracker.
-- A small vertical stack of tiles: one for your quest level, one per active quest.
-- Each tile fills up with progress; hovering shows details, clicking opens the
-- VB_Challenges window, and dragging moves the stack (position is remembered).
require "ISUI/ISPanel"
require "VB_Challenges_Core"
require "VB_Challenges_UI"

VB_Challenges.HUD = VB_Challenges.HUD or {}

local FONT_SMALL = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local HGT_SMALL = getTextManager():getFontHeight(FONT_SMALL)
local HGT_MEDIUM = getTextManager():getFontHeight(FONT_MEDIUM)
local TILE = math.max(36, HGT_SMALL * 2 + 6)
local TILE_GAP = 4
local POS_FILE = "vb_challenges_hud.txt"
local DRAG_THRESHOLD = 4
local REFRESH_MS = 500        -- tiles are rebuilt this often (or right away when state changes)
local PULSE_RAD_PER_MS = 0.0072 -- attention pulse speed (~1.1 Hz)

local GOLD = { r = 1.0, g = 0.85, b = 0.35 }
local GREEN = { r = 0.45, g = 0.9, b = 0.45 }
local WHITE = { r = 1, g = 1, b = 1 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }
local RED = { r = 0.95, g = 0.35, b = 0.3 }

local TYPE_ICON = {
    kill = "Base.BaseballBat",
    kill_night = "Base.HandTorch",
    kill_firearm = "Base.Pistol",
    survive = "Base.AlarmClock2",
    skill = "Base.Book",
    visit = "Base.Map",
    roundtrip = "Base.Map",
    overnight = "Base.Map",
    craft = "Base.Hammer",
    fish = "Base.FishingRod",
    forage = "Base.BerryBlack",
    cook = "Base.Pot",
    read = "Base.Book",
    plant = "Base.CarrotSeed",
    harvest = "Base.Carrots",
    vehicle = "Base.Wrench",
    pet = "Base.Animal",
    feed = "Base.AnimalFeedBag",
    eggs = "Base.Egg",
    catch = "Base.Animal",
    milk = "Base.Bucket",
    shear = "Base.SheepShears",
    butcher = "Base.MeatCleaver",
    settrap = "Base.TrapBox",
    trapcatch = "Base.TrapCage",
    track = "Base.MagnifyingGlass",
    partinstall = "Base.LugWrench",
    partremove = "Base.Screwdriver",
    hotwire = "Base.ElectronicsScrap",
    weldcraft = "Base.BlowTorch",
    metalbuild = "Base.SheetMetal",
    metalbarricade = "Base.MetalBar",
    tailorcraft = "Base.Needle",
    patch = "Base.Thread",
    reinforce = "Base.LeatherStrips",
    laundry = "Base.Soap2",
    potterycraft = "Base.ClayBowlUnfired",
    masonrycraft = "Base.Stone2",
    masonrybuild = "Base.ClayBrick",
    knapcraft = "Base.SharpedStone",
    glasscraft = "Base.GlassBlowingPipe",
    elecraft = "Base.ElectricWire",
    generator = "Base.Generator",
    fixgenerator = "Base.ElectronicsScrap",
    dish = "Base.Pot",
    cookcraft = "Base.BreadDough",
    carvecraft = "Base.WoodenSpoon",
    woodcraft = "Base.Saw",
    woodbuild = "Base.Plank",
    woodbarricade = "Base.Hammer",
    smithcraft = "Base.SmithingHammer",
}

local texCache = {}
local function itemTexture(fullType)
    if not fullType then return nil end
    if texCache[fullType] ~= nil then return texCache[fullType] or nil end
    local tex
    local si = ScriptManager.instance:getItem(fullType)
    if si then
        local ok, t = pcall(function() return si:getNormalTexture() end)
        if ok and t then tex = t end
        if not tex then
            local icon = si:getIcon()
            if icon then tex = getTexture("Item_" .. icon) or getTexture("media/textures/Item_" .. icon) end
        end
    end
    texCache[fullType] = tex or false
    return tex
end

local wrap = VB_Challenges.UI.wrap
local fmtHours = VB_Challenges.UI.fmtHours

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------

VB_ChallengesHudTooltip = ISPanel:derive("VB_ChallengesHudTooltip")

local TIP_W = 280
local TIP_PAD = 8

function VB_ChallengesHudTooltip:new()
    local o = ISPanel.new(self, 0, 0, TIP_W, 50)
    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }
    o.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.8 }
    o.lines = {}
    return o
end

-- lines: { { text=, color=, font= } | { bar=frac, color= } }
function VB_ChallengesHudTooltip:setContent(lines, borderColor)
    self.lines = {}
    local inner = TIP_W - TIP_PAD * 2
    local h = TIP_PAD
    for _, l in ipairs(lines) do
        if l.bar then
            table.insert(self.lines, { bar = l.bar, color = l.color, y = h + 2 })
            h = h + 12
        else
            local font = l.font or FONT_SMALL
            for _, w in ipairs(wrap(font, l.text, inner)) do
                table.insert(self.lines, { text = w, color = l.color or WHITE, font = font, y = h })
                h = h + (font == FONT_MEDIUM and HGT_MEDIUM or HGT_SMALL) + 1
            end
        end
    end
    self:setHeight(h + TIP_PAD)
    local c = borderColor or GREY
    self.borderColor = { r = c.r, g = c.g, b = c.b, a = 0.9 }
end

function VB_ChallengesHudTooltip:render()
    for _, l in ipairs(self.lines) do
        if l.bar then
            local w = self.width - TIP_PAD * 2
            self:drawRect(TIP_PAD, l.y, w, 8, 0.7, 0.15, 0.15, 0.15)
            self:drawRect(TIP_PAD, l.y, w * math.max(0, math.min(1, l.bar)), 8, 0.9, l.color.r, l.color.g, l.color.b)
        else
            self:drawText(l.text, TIP_PAD, l.y, l.color.r, l.color.g, l.color.b, 1, l.font)
        end
    end
end

-- The tooltip must never steal the mouse from the game.
function VB_ChallengesHudTooltip:onMouseDown() return false end
function VB_ChallengesHudTooltip:onMouseUp() return false end
function VB_ChallengesHudTooltip:onMouseMove() return false end

----------------------------------------------------------------------
-- Tracker panel
----------------------------------------------------------------------

VB_ChallengesHud = ISPanel:derive("VB_ChallengesHud")

function VB_ChallengesHud:new(x, y)
    local o = ISPanel.new(self, x, y, TILE, TILE)
    o.background = false
    o.tiles = {}
    o.tilesVersion = 0
    o.nextRefresh = 0
    o.dragging = false
    return o
end

function VB_ChallengesHud:createChildren()
    ISPanel.createChildren(self)
    self.tooltip = VB_ChallengesHudTooltip:new()
    self.tooltip:initialise()
    self.tooltip:addToUIManager()
    self.tooltip:setAlwaysOnTop(true)
    self.tooltip:setVisible(false)
end

-- Builds the tile list from the current quest state.
function VB_ChallengesHud:refreshTiles()
    local player = getPlayer()
    self.tiles = {}
    if not player then return end
    self.tilesVersion = self.tilesVersion + 1
    local s = VB_Challenges.getState(player)
    local need = VB_Challenges.pointsToNext(s)

    table.insert(self.tiles, {
        kind = "level",
        label = tostring(s.level),
        frac = s.levelPoints / need,
        color = GOLD,
        alert = #s.pendingRewards > 0,
        tip = function()
            local lines = {
                { text = VB_Challenges.T("Header_Level", s.level), color = GOLD, font = FONT_MEDIUM },
                { bar = s.levelPoints / need, color = GOLD },
                { text = VB_Challenges.T("Header_PointsToLevel", s.levelPoints, need, s.level + 1) },
            }
            if #s.pendingRewards > 0 then
                table.insert(lines, { text = VB_Challenges.T("Hud_RewardsWaiting", #s.pendingRewards), color = GREEN })
            end
            if s.rerollTokens > 0 or (s.bonusTokens or 0) > 0 then
                table.insert(lines, { text = VB_Challenges.T("Header_Tokens", s.rerollTokens, s.bonusTokens or 0), color = GREY })
            end
            local freeIn = VB_Challenges.hoursUntilFreeReroll(s)
            if freeIn then
                table.insert(lines, { text = VB_Challenges.T("Header_FreeReroll", fmtHours(freeIn)), color = GREY })
            end
            table.insert(lines, { text = VB_Challenges.T("Hud_HintLevel"), color = GREY })
            return lines
        end,
        page = "level",
    })

    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = s.active[d]
        if q then
            local progress = VB_Challenges.getProgress(player, q)
            local ready = progress >= q.target
            local color = VB_Challenges.DIFFICULTY_COLOR[d]
            local isLoc = VB_Challenges.Location.isLocationType(q.type)
            local distShort, distDir
            if isLoc and not ready then
                distShort, distDir = VB_Challenges.Location.distanceText(player, q, true)
            end
            local deadlineLeft = (q.deadlineAt and not q.deadlineMet and not ready) and VB_Challenges.hoursUntilDeadline(q) or nil
            table.insert(self.tiles, {
                kind = "quest",
                risky = VB_Challenges.modifierCount(q.mods) > 0,
                urgent = deadlineLeft ~= nil and deadlineLeft < 24,
                distShort = distShort,
                distDir = distDir,
                tex = itemTexture(q.type == "deliver" and VB_Challenges.deliverTypes(q)[1] or TYPE_ICON[q.type]),
                letter = VB_Challenges.T("Hud_Letter_" .. d),
                frac = progress / q.target,
                color = color,
                alert = ready,
                tip = function()
                    local lines = {
                        { text = VB_Challenges.T("Hud_DifficultyQuest", VB_Challenges.difficultyLabel(d)), color = color },
                        { text = VB_Challenges.T("Card_TitlePoints", VB_Challenges.questTitle(q), q.points), color = color, font = FONT_MEDIUM },
                        { text = VB_Challenges.describeQuest(q) },
                        { bar = progress / q.target, color = ready and GREEN or color },
                        { text = VB_Challenges.T("Card_Progress", VB_Challenges.formatProgress(q, progress)), color = ready and GREEN or WHITE },
                    }
                    if VB_Challenges.modifierCount(q.mods) > 0 then
                        table.insert(lines, { text = VB_Challenges.T("Card_Risk", VB_Challenges.modifierNames(q.mods)), color = RED })
                    end
                    if deadlineLeft then
                        table.insert(lines, { text = VB_Challenges.T("Card_DeadlineLeft", fmtHours(math.max(0, deadlineLeft))),
                            color = deadlineLeft < 24 and RED or GOLD })
                    end
                    if isLoc and not ready then
                        local _, _, goalLabel = VB_Challenges.Location.currentGoal(q)
                        table.insert(lines, { text = VB_Challenges.T("Card_DistanceTo", goalLabel, VB_Challenges.Location.distanceText(player, q)), color = GOLD })
                        table.insert(lines, { text = VB_Challenges.T("Hud_MapHint"), color = GREY })
                    end
                    local cacheHint = isLoc and VB_Challenges.Location.cacheHint(player, q)
                    if cacheHint then
                        table.insert(lines, { text = cacheHint, color = GOLD })
                    end
                    if ready then
                        table.insert(lines, { text = VB_Challenges.T("Hud_Ready"), color = GREEN })
                    else
                        table.insert(lines, { text = VB_Challenges.T("Hud_HintQuest"), color = GREY })
                    end
                    return lines
                end,
                page = "challenges",
            })
        end
    end

    self:setHeight(#self.tiles * (TILE + TILE_GAP) - TILE_GAP)
    self:setWidth(TILE)
end

function VB_ChallengesHud:tileAt(y)
    local idx = math.floor(y / (TILE + TILE_GAP)) + 1
    if y - (idx - 1) * (TILE + TILE_GAP) > TILE then return nil end
    return self.tiles[idx], idx
end

function VB_ChallengesHud:render()
    local glow = 0.55 + 0.45 * math.sin(getTimestampMs() * PULSE_RAD_PER_MS)
    for i, t in ipairs(self.tiles) do
        local y = (i - 1) * (TILE + TILE_GAP)
        local c = t.color
        -- background + progress fill rising from the bottom
        self:drawRect(0, y, TILE, TILE, 0.75, 0.08, 0.08, 0.08)
        local fillH = math.floor((TILE - 2) * math.max(0, math.min(1, t.frac)))
        if fillH > 0 then
            self:drawRect(1, y + TILE - 1 - fillH, TILE - 2, fillH, 0.35, c.r, c.g, c.b)
        end
        -- content
        if t.kind == "level" then
            self:drawTextCentre(VB_Challenges.T("Hud_Lv"), TILE / 2, y + 2, GOLD.r, GOLD.g, GOLD.b, 1, FONT_SMALL)
            self:drawTextCentre(t.label, TILE / 2, y + TILE - HGT_SMALL - 3, 1, 1, 1, 1, FONT_SMALL)
        else
            local iconSize = TILE - 12
            if t.tex then
                self:drawTextureScaledAspect(t.tex, 6, y + 6, iconSize, iconSize, 1, 1, 1, 1)
            end
            self:drawText(t.letter, 3, y + 1, c.r, c.g, c.b, 1, FONT_SMALL)
            -- Risk modifiers: red stripe on the left edge, pulsing when a deadline is under a day away.
            if t.risky then
                local a = t.urgent and glow or 0.9
                self:drawRect(0, y, 3, TILE, a, RED.r, RED.g, RED.b)
            end
            -- Location quests: compass direction (top-right) and distance (bottom).
            if t.distShort then
                self:drawRect(1, y + TILE - HGT_SMALL - 2, TILE - 2, HGT_SMALL + 1, 0.6, 0, 0, 0)
                self:drawTextCentre(t.distShort, TILE / 2, y + TILE - HGT_SMALL - 2, GOLD.r, GOLD.g, GOLD.b, 1, FONT_SMALL)
                if t.distDir and t.distDir ~= "" then
                    self:drawTextRight(t.distDir, TILE - 3, y + 1, 1, 1, 1, 1, FONT_SMALL)
                end
            end
        end
        -- border; pulses when something needs attention
        if t.alert then
            local a = t.kind == "level" and GOLD or GREEN
            self:drawRectBorder(0, y, TILE, TILE, glow, a.r, a.g, a.b)
            self:drawRectBorder(1, y + 1, TILE - 2, TILE - 2, glow, a.r, a.g, a.b)
            self:drawTextRight("!", TILE - 3, y + 1, a.r, a.g, a.b, 1, FONT_SMALL)
        else
            self:drawRectBorder(0, y, TILE, TILE, 0.8, c.r, c.g, c.b)
        end
    end
end

function VB_ChallengesHud:update()
    ISPanel.update(self)
    local player = getPlayer()
    local shouldShow = player ~= nil and not player:isDead() and VB_Challenges.HUD.isEnabled()
    if not shouldShow then
        if self:isVisible() then self:setVisible(false) end
        self.tooltip:setVisible(false)
        return
    end
    if not self:isVisible() then self:setVisible(true) end

    local now = getTimestampMs()
    if self.dirty or now >= self.nextRefresh then
        self.dirty = false
        self.nextRefresh = now + REFRESH_MS
        self:refreshTiles()
    end
    self:clampToScreen()
    self:updateTooltip()
end

function VB_ChallengesHud:updateTooltip()
    if self.dragging or not self:isMouseOver() then
        self.tooltip:setVisible(false)
        return
    end
    local tile, idx = self:tileAt(self:getMouseY())
    if not tile then
        self.tooltip:setVisible(false)
        return
    end
    -- Tooltip text is only rebuilt when the hovered tile or the tile data changed.
    if self.tipIndex ~= idx or self.tipVersion ~= self.tilesVersion or not self.tooltip:isVisible() then
        self.tipIndex = idx
        self.tipVersion = self.tilesVersion
        self.tooltip:setContent(tile.tip(), tile.color)
    end
    local tileY = self:getY() + (idx - 1) * (TILE + TILE_GAP)
    local x = self:getX() - self.tooltip:getWidth() - 6
    if x < 0 then x = self:getX() + TILE + 6 end
    local y = math.min(tileY, getCore():getScreenHeight() - self.tooltip:getHeight() - 4)
    self.tooltip:setX(x)
    self.tooltip:setY(math.max(0, y))
    self.tooltip:setVisible(true)
    self.tooltip:bringToTop()
end

function VB_ChallengesHud:clampToScreen()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(self:getX(), sw - self:getWidth()))
    local y = math.max(0, math.min(self:getY(), sh - self:getHeight()))
    if x ~= self:getX() then self:setX(x) end
    if y ~= self:getY() then self:setY(y) end
end

-- Mouse: click opens the window, drag moves the tracker --------------

function VB_ChallengesHud:onMouseDown(x, y)
    self.dragging = true
    self.dragMoved = 0
    self.downY = y
    self:setCapture(true)
    return true
end

function VB_ChallengesHud:onMouseMove(dx, dy)
    if self.dragging then
        self.dragMoved = self.dragMoved + math.abs(dx) + math.abs(dy)
        if self.dragMoved > DRAG_THRESHOLD then
            self:setX(self:getX() + dx)
            self:setY(self:getY() + dy)
        end
    end
    return true
end

function VB_ChallengesHud:onMouseMoveOutside(dx, dy)
    if self.dragging then return self:onMouseMove(dx, dy) end
end

function VB_ChallengesHud:onMouseUp(x, y)
    if not self.dragging then return true end
    self.dragging = false
    self:setCapture(false)
    if self.dragMoved > DRAG_THRESHOLD then
        VB_Challenges.HUD.savePosition(self:getX(), self:getY())
    else
        local tile = self:tileAt(self.downY or y)
        if tile then VB_Challenges.UI.open(tile.page) end
    end
    return true
end

function VB_ChallengesHud:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        self:setCapture(false)
        VB_Challenges.HUD.savePosition(self:getX(), self:getY())
    end
end

----------------------------------------------------------------------
-- Position persistence + lifecycle
----------------------------------------------------------------------

function VB_Challenges.HUD.savePosition(x, y)
    local f = getFileWriter(POS_FILE, true, false)
    if f then
        f:write(string.format("%d|%d", math.floor(x), math.floor(y)))
        f:close()
    end
end

local function loadPosition()
    local ok, f = pcall(getFileReader, POS_FILE, false)
    if not ok or not f then return nil end
    local line = f:readLine()
    f:close()
    if not line then return nil end
    local x, y = string.match(line, "^(%-?%d+)|(%-?%d+)")
    if x then return tonumber(x), tonumber(y) end
    return nil
end

local function defaultPosition()
    -- Just left of the vanilla moodle column (top-right of the screen).
    local sw = getCore():getScreenWidth()
    local x, y = sw - TILE - 70, 110
    local ok, moodle = pcall(UIManager.getMoodleUI, 0)
    if ok and moodle then
        local mx, my = moodle:getX(), moodle:getY()
        if mx and mx > TILE + 20 and mx < sw then
            x, y = mx - TILE - 10, math.max(my, 40)
        end
    end
    return x, y
end

function VB_Challenges.HUD.isEnabled()
    local opts = VB_Challenges.UI.options
    local opt = opts and opts:getOption("showHud")
    if opt then return opt:getValue() ~= false end
    return true
end

function VB_Challenges.HUD.resetPosition()
    local hud = VB_Challenges.HUD.instance
    if not hud then return end
    local x, y = defaultPosition()
    hud:setX(x)
    hud:setY(y)
    VB_Challenges.HUD.savePosition(x, y)
end

local function destroy()
    local hud = VB_Challenges.HUD.instance
    if hud then
        hud.tooltip:removeFromUIManager()
        hud:removeFromUIManager()
        VB_Challenges.HUD.instance = nil
    end
end

local function create()
    destroy()
    local x, y = loadPosition()
    if not x then x, y = defaultPosition() end
    local hud = VB_ChallengesHud:new(x, y)
    hud:initialise()
    hud:addToUIManager()
    hud:refreshTiles()
    VB_Challenges.HUD.instance = hud
end

table.insert(VB_Challenges.listeners, function()
    if VB_Challenges.HUD.instance then VB_Challenges.HUD.instance.dirty = true end
end)

Events.OnGameStart.Add(create)
