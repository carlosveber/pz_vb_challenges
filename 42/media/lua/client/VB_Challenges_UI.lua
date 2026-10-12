-- VB_Challenges: the quest window (VB_Challenges / Level / Completed / Debug tabs).
-- Layout is flow-based: every block measures its own text, cards grow to fit
-- their content, button rows wrap, and the content area scrolls. The window is
-- resizable and re-lays itself out when its width changes.
require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "VB_Challenges_Core"

VB_Challenges.UI = VB_Challenges.UI or {}

local FONT_SMALL = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local HGT_SMALL = getTextManager():getFontHeight(FONT_SMALL)
local HGT_MEDIUM = getTextManager():getFontHeight(FONT_MEDIUM)
local PAD = 10          -- outer padding
local CARD_PAD = 8      -- padding inside cards
local GAP = 6           -- vertical gap between blocks
local LINE_GAP = 2
local BTN_H = math.max(24, HGT_SMALL + 8)
local BAR_H = math.max(8, math.floor(HGT_SMALL / 2))
local SCROLLBAR_W = 14
local COMPLETED_PER_PAGE = 10
local POLL_MS = 500     -- how often an open window checks for state changes it wasn't told about

local WHITE = { r = 1, g = 1, b = 1 }
local GREY = { r = 0.65, g = 0.65, b = 0.65 }
local GOLD = { r = 1.0, g = 0.85, b = 0.35 }
local GREEN = { r = 0.45, g = 0.9, b = 0.45 }
local RED = { r = 0.95, g = 0.45, b = 0.4 }

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text)
end

local function fontHeight(font)
    return font == FONT_MEDIUM and HGT_MEDIUM or HGT_SMALL
end

-- Word-wraps text to `width`. Words longer than the width are hard-split.
-- Shared with the HUD tooltip.
local function wrap(font, text, width)
    local lines, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if measure(font, candidate) <= width then
            line = candidate
        else
            if line ~= "" then table.insert(lines, line) end
            line = word
            while measure(font, line) > width and #line > 1 do
                local cut = #line - 1
                while cut > 1 and measure(font, line:sub(1, cut)) > width do cut = cut - 1 end
                table.insert(lines, line:sub(1, cut))
                line = line:sub(cut + 1)
            end
        end
    end
    if line ~= "" then table.insert(lines, line) end
    if #lines == 0 then lines[1] = "" end
    return lines
end

local function fmtHours(h)
    if h >= 24 then return VB_Challenges.T("Time_Days", string.format("%.1f", h / 24)) end
    return VB_Challenges.T("Time_Hours", math.ceil(h))
end

VB_Challenges.UI.wrap = wrap
VB_Challenges.UI.fmtHours = fmtHours

local function buttonWidth(title, minW)
    return math.max(minW or 80, measure(FONT_SMALL, title) + 24)
end

----------------------------------------------------------------------
-- Content panel (scrollable)
----------------------------------------------------------------------

VB_ChallengesContentPanel = ISPanel:derive("VB_ChallengesContentPanel")

function VB_ChallengesContentPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.page = "challenges"
    o.offerFor = nil
    o.completedPage = 1
    o.ops = {}
    o.questButtons = {}
    o.lastSignature = ""
    o.lastWidth = -1
    o.nextPoll = 0
    o.dirty = false
    return o
end

function VB_ChallengesContentPanel:createChildren()
    ISPanel.createChildren(self)
    self:setScrollChildren(true)
    self:addScrollBars()
    self.vscroll.doRepaintStencil = true
end

-- Usable width for content (leaves room for the scrollbar).
function VB_ChallengesContentPanel:innerWidth()
    return self:getWidth() - PAD * 2 - SCROLLBAR_W
end

-- Drawing primitives (recorded, replayed every frame) ------------------

function VB_ChallengesContentPanel:text(x, y, text, color, font)
    font = font or FONT_SMALL
    table.insert(self.ops, { kind = "text", x = x, y = y, text = text, c = color or WHITE, font = font })
    return y + fontHeight(font) + LINE_GAP
end

function VB_ChallengesContentPanel:wrapped(x, y, text, width, color, font)
    for _, l in ipairs(wrap(font or FONT_SMALL, text, width)) do
        y = self:text(x, y, l, color, font)
    end
    return y
end

function VB_ChallengesContentPanel:bar(x, y, w, frac, color)
    frac = math.max(0, math.min(1, frac))
    table.insert(self.ops, { kind = "bar", x = x, y = y, w = w, h = BAR_H, frac = frac, c = color or GREEN })
    return y + BAR_H + 4
end

-- Cards: open one, lay out content, then close it with the final y so the
-- background box is sized to what was actually drawn.
function VB_ChallengesContentPanel:beginCard(x, y, w, color, alpha)
    local op = { kind = "box", x = x, y = y, w = w, h = 0, c = color or GREY, a = alpha or 0.08 }
    table.insert(self.ops, op)
    return op
end

function VB_ChallengesContentPanel:endCard(card, yEnd)
    card.h = yEnd - card.y
    return yEnd
end

-- Buttons ---------------------------------------------------------------

function VB_ChallengesContentPanel:button(x, y, w, title, action, enabled, tooltip)
    local btn = ISButton:new(x, y, w, BTN_H, title, self, function(_, b) b.questAction() end)
    -- Rebuilt on the next update rather than right away, so the clicked button
    -- isn't removed from inside its own click handler.
    btn.questAction = function()
        action()
        self.dirty = true
    end
    btn:initialise()
    btn:instantiate()
    if enabled == false then btn:setEnable(false) end
    if tooltip then btn:setTooltip(tooltip) end
    self:addChild(btn)
    table.insert(self.questButtons, btn)
    return btn
end

-- Lays out buttons left to right, wrapping onto new rows when out of room.
-- specs: { { title, action, enabled, tooltip, minW }, ... }. Returns y below the last row.
function VB_ChallengesContentPanel:buttonRow(x, y, maxW, specs, equalWidth)
    local cx = x
    local fixedW
    if equalWidth then
        local perRow = math.max(1, math.min(#specs, equalWidth))
        fixedW = math.floor((maxW - (perRow - 1) * GAP) / perRow)
    end
    for _, s in ipairs(specs) do
        local w = fixedW or math.min(maxW, buttonWidth(s[1], s[5]))
        if cx > x and cx + w > x + maxW then
            cx = x
            y = y + BTN_H + GAP
        end
        self:button(cx, y, w, s[1], s[2], s[3], s[4])
        cx = cx + w + GAP
    end
    return y + BTN_H + GAP
end

-- Rendering -------------------------------------------------------------

function VB_ChallengesContentPanel:prerender()
    self:setStencilRect(0, 0, self:getWidth(), self:getHeight())
    ISPanel.prerender(self)
    for _, op in ipairs(self.ops) do
        if op.kind == "text" then
            self:drawText(op.text, op.x, op.y, op.c.r, op.c.g, op.c.b, 1, op.font)
        elseif op.kind == "box" then
            self:drawRect(op.x, op.y, op.w, op.h, op.a, op.c.r, op.c.g, op.c.b)
            self:drawRectBorder(op.x, op.y, op.w, op.h, 0.5, op.c.r, op.c.g, op.c.b)
        elseif op.kind == "bar" then
            self:drawRect(op.x, op.y, op.w, op.h, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(op.x, op.y, op.w * op.frac, op.h, 0.9, op.c.r, op.c.g, op.c.b)
            self:drawRectBorder(op.x, op.y, op.w, op.h, 0.8, 0.5, 0.5, 0.5)
        end
    end
end

-- Re-layout when the window was resized or the game state changed. Changes are
-- batched into at most one rebuild per frame. Done in update() rather than during
-- drawing so children aren't swapped mid-render.
function VB_ChallengesContentPanel:update()
    ISPanel.update(self)
    if not self:isVisible() or not self.window or not self.window:isVisible() then return end
    if self.dirty or self:getWidth() ~= self.lastWidth then
        self.window:refresh()
        return
    end
    local now = getTimestampMs()
    if now >= self.nextPoll then
        self.nextPoll = now + POLL_MS
        if self:signature() ~= self.lastSignature then self.window:refresh() end
    end
end

function VB_ChallengesContentPanel:render()
    ISPanel.render(self)
    self:clearStencilRect()
    self:repaintStencilRect(0, 0, self:getWidth(), self:getHeight())
end

function VB_ChallengesContentPanel:onMouseWheel(del)
    if self:getScrollHeight() > self:getHeight() then
        self:setYScroll(self:getYScroll() - del * 40)
        return true
    end
    return false
end

-- Cheap signature of everything that affects the layout, so the panel can
-- rebuild itself when a quest becomes claimable / abandonable while open.
function VB_ChallengesContentPanel:signature()
    local player = getPlayer()
    local s = player and VB_Challenges.getState(player)
    if not s then return "" end
    local freeIn = VB_Challenges.hoursUntilFreeReroll(s)
    local parts = { s.level, s.levelPoints, #s.pendingRewards, #s.completed, s.rerollTokens, s.bonusTokens or 0,
        freeIn and math.ceil(freeIn) or "-" }
    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = s.active[d]
        if q then
            table.insert(parts, d .. q.id .. ":" .. VB_Challenges.getProgress(player, q))
        else
            table.insert(parts, d .. "-" .. (s.offers[d] and #s.offers[d] or 0))
        end
    end
    return table.concat(parts, "|")
end

function VB_ChallengesContentPanel:resetScroll()
    self:setYScroll(0)
end

function VB_ChallengesContentPanel:rebuild()
    for _, b in ipairs(self.questButtons) do self:removeChild(b) end
    self.questButtons = {}
    self.ops = {}
    self.dirty = false
    self.lastSignature = self:signature()
    self.lastWidth = self:getWidth()

    local player = getPlayer()
    local y = PAD
    if player then
        local state = VB_Challenges.getState(player)
        if self.page == "challenges" then
            if self.offerFor then y = self:buildOffers(player, state) else y = self:buildQuests(player, state) end
        elseif self.page == "level" then
            y = self:buildLevel(player, state)
        elseif self.page == "completed" then
            y = self:buildCompleted(player, state)
        elseif self.page == "debug" then
            y = self:buildDebug(player, state)
        end
    end

    self:setScrollHeight(y + PAD)
    -- Keep the scroll position valid after content shrinks.
    local maxScroll = math.max(0, (y + PAD) - self:getHeight())
    if -self:getYScroll() > maxScroll then self:setYScroll(-maxScroll) end
    if self.vscroll then self.vscroll:bringToTop() end
end

----------------------------------------------------------------------
-- Pages (each returns the y after its last element)
----------------------------------------------------------------------

function VB_ChallengesContentPanel:header(state, y)
    local w = self:innerWidth()
    local need = VB_Challenges.pointsToNext(state)
    y = self:text(PAD, y, VB_Challenges.T("Header_Level", state.level), GOLD, FONT_MEDIUM)
    y = self:bar(PAD, y + 2, w, state.levelPoints / need, GOLD)
    y = self:wrapped(PAD, y, VB_Challenges.T("Header_PointsToLevel", state.levelPoints, need, state.level + 1), w, WHITE)
    y = self:wrapped(PAD, y, VB_Challenges.T("Header_Tokens", state.rerollTokens, state.bonusTokens or 0), w, GREY)
    local freeIn = VB_Challenges.hoursUntilFreeReroll(state)
    if freeIn then
        y = self:wrapped(PAD, y, VB_Challenges.T("Header_FreeReroll", fmtHours(freeIn)), w, GREY)
    end
    if #state.pendingRewards > 0 then
        y = self:wrapped(PAD, y, VB_Challenges.T("Header_RewardsWaiting", #state.pendingRewards), w, GREEN)
    end
    return y + GAP
end

function VB_ChallengesContentPanel:buildQuests(player, state)
    local y = self:header(state, PAD)
    local w = self:innerWidth()
    local iw = w - CARD_PAD * 2
    local ix = PAD + CARD_PAD

    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local color = VB_Challenges.DIFFICULTY_COLOR[d]
        local label = VB_Challenges.difficultyLabel(d)
        local q = state.active[d]
        local card = self:beginCard(PAD, y, w, color)
        local ty = y + CARD_PAD

        if q then
            ty = self:text(ix, ty, label, color)
            ty = self:wrapped(ix, ty, VB_Challenges.T("Card_TitlePoints", VB_Challenges.questTitle(q), q.points), iw, color, FONT_MEDIUM)
            ty = self:wrapped(ix, ty, VB_Challenges.describeQuest(q), iw, WHITE)
            local progress = VB_Challenges.getProgress(player, q)
            local ready = progress >= q.target
            ty = self:bar(ix, ty + 2, iw, progress / q.target, ready and GREEN or color)
            ty = self:wrapped(ix, ty, VB_Challenges.T(ready and "Card_ProgressReady" or "Card_Progress", VB_Challenges.formatProgress(q, progress)),
                iw, ready and GREEN or GREY)
            if not ready and VB_Challenges.Location.isLocationType(q.type) then
                local _, _, goalLabel = VB_Challenges.Location.currentGoal(q)
                ty = self:wrapped(ix, ty, VB_Challenges.T("Card_DistanceTo", goalLabel, VB_Challenges.Location.distanceText(player, q)), iw, GOLD)
            end
            local cacheHint = VB_Challenges.Location.isLocationType(q.type) and VB_Challenges.Location.cacheHint(player, q)
            if cacheHint then
                ty = self:wrapped(ix, ty, cacheHint, iw, GOLD)
            end
            if VB_Challenges.modifierCount(q.mods) > 0 then
                ty = self:wrapped(ix, ty, VB_Challenges.T("Card_Risk", VB_Challenges.modifierNames(q.mods)), iw, RED)
            end
            if q.deadlineAt then
                if q.deadlineMet or ready then
                    ty = self:wrapped(ix, ty, VB_Challenges.T("Card_DeadlineMet"), iw, GREEN)
                else
                    local left = math.max(0, VB_Challenges.hoursUntilDeadline(q))
                    ty = self:wrapped(ix, ty, VB_Challenges.T("Card_DeadlineLeft", fmtHours(left)), iw, left < 24 and RED or GOLD)
                end
            end
            ty = self:buttonRow(ix, ty + 4, iw, {
                { VB_Challenges.T(q.type == "deliver" and "Btn_TurnIn" or "Btn_Claim"), function() VB_Challenges.claim(getPlayer(), d) end,
                  ready, ready and nil or VB_Challenges.T("Tip_NotDone"), 100 },
                { VB_Challenges.T("Btn_Abandon"), function() VB_Challenges.abandon(getPlayer(), d) end, true,
                  VB_Challenges.T("Tip_Abandon"), 100 },
            })
        else
            ty = self:text(ix, ty, label, color)
            ty = self:wrapped(ix, ty, VB_Challenges.T("Card_NoQuest"), iw, color, FONT_MEDIUM)
            local hasOffers = state.offers[d] and #state.offers[d] > 0
            ty = self:wrapped(ix, ty, hasOffers and VB_Challenges.T("Card_OffersWaiting")
                or VB_Challenges.T("Card_PickFrom", VB_Challenges.offerCount(), label), iw, GREY)
            ty = self:buttonRow(ix, ty + 4, iw, {
                { VB_Challenges.T(hasOffers and "Btn_ViewOptions" or "Btn_FindQuest"), function()
                    VB_Challenges.getOrCreateOffers(getPlayer(), d)
                    self.offerFor = d
                    self:resetScroll()
                end, true, nil, 140 },
            })
        end

        y = self:endCard(card, ty - GAP + CARD_PAD) + GAP
    end
    return y
end

function VB_ChallengesContentPanel:buildOffers(player, state)
    local d = self.offerFor
    local offers = VB_Challenges.getOrCreateOffers(player, d)
    local color = VB_Challenges.DIFFICULTY_COLOR[d]
    local w = self:innerWidth()
    local iw = w - CARD_PAD * 2
    local ix = PAD + CARD_PAD

    local y = PAD
    y = self:wrapped(PAD, y, VB_Challenges.T("Offers_Title", VB_Challenges.difficultyLabel(d)), w, color, FONT_MEDIUM) + GAP

    self.offerMods = self.offerMods or {}
    for i, q in ipairs(offers) do
        local chosen = self.offerMods[q.id] or {}
        self.offerMods[q.id] = chosen
        local nChosen = VB_Challenges.modifierCount(chosen)

        local card = self:beginCard(PAD, y, w, color)
        local ty = y + CARD_PAD
        ty = self:wrapped(ix, ty, VB_Challenges.questTitle(q), iw, color, FONT_MEDIUM)
        if nChosen > 0 then
            ty = self:wrapped(ix, ty, VB_Challenges.T("Offers_PointsBonus",
                VB_Challenges.pointsWithModifiers(q.points, chosen), q.points,
                math.floor(VB_Challenges.modifierBonus() * 100 * nChosen + 0.5)), iw, GOLD)
        else
            ty = self:wrapped(ix, ty, VB_Challenges.T("Offers_Points", q.points), iw, GOLD)
        end
        ty = self:wrapped(ix, ty, VB_Challenges.describeQuest(q), iw, WHITE)
        if VB_Challenges.Location.isLocationType(q.type) then
            ty = self:wrapped(ix, ty, VB_Challenges.T("Offers_Distance", VB_Challenges.Location.distanceText(player, q)), iw, GOLD)
        end

        -- Risk modifiers: toggle for +bonus points each.
        local applicable = VB_Challenges.applicableModifiers(q)
        if #applicable > 0 and VB_Challenges.maxModifiers() > 0 then
            ty = self:wrapped(ix, ty + 4, VB_Challenges.T("Offers_RiskHeader",
                math.floor(VB_Challenges.modifierBonus() * 100 + 0.5), VB_Challenges.maxModifiers()), iw, GREY)
            local specs = {}
            for _, m in ipairs(applicable) do
                local on = chosen[m.id] == true
                local canToggle = on or nChosen < VB_Challenges.maxModifiers()
                table.insert(specs, { (on and "[x] " or "[  ] ") .. VB_Challenges.modifierLabel(m.id), function()
                    chosen[m.id] = not on or nil
                end, canToggle, m.describe(q) })
            end
            ty = self:buttonRow(ix, ty, iw, specs)
            for _, m in ipairs(applicable) do
                if chosen[m.id] then ty = self:wrapped(ix, ty, "- " .. m.describe(q), iw, RED) end
            end
        end

        ty = self:buttonRow(ix, ty + 4, iw, {
            { VB_Challenges.T(nChosen > 0 and "Btn_AcceptRisk" or "Btn_Accept"), function()
                if VB_Challenges.acceptOffer(getPlayer(), d, i, chosen) then
                    self.offerMods = {}
                    self.offerFor = nil
                    self:resetScroll()
                end
            end, true, nil, 110 },
        })
        y = self:endCard(card, ty - GAP + CARD_PAD) + GAP
    end

    y = self:buttonRow(PAD, y + 4, w, {
        { VB_Challenges.T("Btn_Back"), function() self.offerFor = nil; self:resetScroll() end, true, nil, 90 },
        { VB_Challenges.T("Btn_Reroll", state.rerollTokens), function()
            VB_Challenges.rerollOffers(getPlayer(), d)
        end, state.rerollTokens > 0, VB_Challenges.T("Tip_Reroll") },
    })
    return y
end

function VB_ChallengesContentPanel:buildLevel(player, state)
    local y = self:header(state, PAD)
    local w = self:innerWidth()
    y = self:wrapped(PAD, y, VB_Challenges.T("Level_TotalScore", state.totalPoints), w, WHITE)
    local done = 0
    for _, c in ipairs(state.completed) do if not c.failed then done = done + 1 end end
    y = self:wrapped(PAD, y, VB_Challenges.T("Level_Stats",
        done, state.failed or 0, state.abandoned or 0), w, WHITE) + GAP

    local pending = state.pendingRewards[1]
    if pending then
        y = self:wrapped(PAD, y, VB_Challenges.T("Level_RewardTitle", pending.level), w, GREEN, FONT_MEDIUM)
        if #state.pendingRewards > 1 then
            y = self:wrapped(PAD, y, VB_Challenges.T("Level_MoreRewards", #state.pendingRewards - 1), w, GREY)
        end
        y = y + 4

        -- Side by side when there's room, stacked when the window is narrow.
        local sideBySide = w >= 440
        local colW = sideBySide and math.floor((w - GAP) / 2) or w
        local rowTop = y
        local cards, bottoms = {}, {}
        for i, r in ipairs(pending.choices) do
            local x = sideBySide and (PAD + (i - 1) * (colW + GAP)) or PAD
            local top = sideBySide and rowTop or y
            local card = self:beginCard(x, top, colW, GOLD)
            local ty = top + CARD_PAD
            ty = self:wrapped(x + CARD_PAD, ty, VB_Challenges.rewardLabel(r), colW - CARD_PAD * 2, GOLD, FONT_MEDIUM)
            ty = self:wrapped(x + CARD_PAD, ty + 2, VB_Challenges.rewardDetail(r), colW - CARD_PAD * 2, WHITE)
            cards[i], bottoms[i] = { card = card, x = x }, ty
            if not sideBySide then
                ty = self:buttonRow(x + CARD_PAD, ty + 4, colW - CARD_PAD * 2, {
                    { VB_Challenges.T("Btn_Choose"), function() VB_Challenges.chooseReward(getPlayer(), i) end, true, nil, 120 },
                })
                y = self:endCard(card, ty - GAP + CARD_PAD) + GAP
            end
        end
        if sideBySide then
            -- Align both "Choose" buttons to the taller card.
            local maxBottom = rowTop
            for _, b in ipairs(bottoms) do maxBottom = math.max(maxBottom, b) end
            local by = maxBottom + 4
            for i, c in ipairs(cards) do
                self:button(c.x + CARD_PAD, by, colW - CARD_PAD * 2, VB_Challenges.T("Btn_Choose"), function() VB_Challenges.chooseReward(getPlayer(), i) end)
                self:endCard(c.card, by + BTN_H + CARD_PAD)
            end
            y = by + BTN_H + CARD_PAD + GAP
        end
        y = y + GAP
    else
        y = self:wrapped(PAD, y, VB_Challenges.T("Level_NoRewards"), w, GREY) + GAP
    end

    y = self:wrapped(PAD, y, VB_Challenges.T("Level_Upcoming"), w, GOLD, FONT_MEDIUM)
    for lvl = state.level, state.level + 4 do
        local key = VB_Challenges.isTraitLevel(lvl + 1) and "Level_RowTrait" or "Level_Row"
        y = self:wrapped(PAD + CARD_PAD, y, VB_Challenges.T(key, lvl, lvl + 1, VB_Challenges.pointsForLevel(lvl)),
            w - CARD_PAD, lvl == state.level and WHITE or GREY)
    end
    y = y + GAP
    y = self:wrapped(PAD, y, VB_Challenges.T("Level_PointsInfo",
        VB_Challenges.basePoints("easy"), VB_Challenges.basePoints("medium"), VB_Challenges.basePoints("hard")), w, GREY)
    if VB_Challenges.traitRewardEvery() > 0 and VB_Challenges.rewardCategoryEnabled("trait") then
        y = self:wrapped(PAD, y, VB_Challenges.T("Level_TraitInfo", VB_Challenges.traitRewardEvery()), w, GREY)
    end
    return y
end

function VB_ChallengesContentPanel:buildCompleted(player, state)
    local w = self:innerWidth()
    local iw = w - CARD_PAD * 2
    local ix = PAD + CARD_PAD
    local total = #state.completed
    local y = self:wrapped(PAD, PAD, VB_Challenges.T("History_Title", total), w, GOLD, FONT_MEDIUM) + 4
    if total == 0 then
        return self:wrapped(PAD, y, VB_Challenges.T("History_Empty"), w, GREY)
    end

    local pages = math.max(1, math.ceil(total / COMPLETED_PER_PAGE))
    self.completedPage = math.max(1, math.min(self.completedPage, pages))
    if pages > 1 then
        y = self:pager(y, w, pages)
    end

    local first = (self.completedPage - 1) * COMPLETED_PER_PAGE + 1
    for i = first, math.min(total, first + COMPLETED_PER_PAGE - 1) do
        local c = state.completed[i]
        local color = VB_Challenges.DIFFICULTY_COLOR[c.difficulty] or WHITE
        local card = self:beginCard(PAD, y, w, color, 0.06)
        local ty = y + CARD_PAD
        local right = c.failed and VB_Challenges.T("History_Failed")
            or VB_Challenges.T(c.bonus and "History_PointsBonus" or "History_Points", c.points)
        local rightW = measure(FONT_SMALL, right)
        self:text(ix + iw - rightW, ty, right, c.failed and RED or GOLD)
        ty = self:wrapped(ix, ty, string.format("[%s] %s", VB_Challenges.difficultyLabel(c.difficulty), c.templateId and VB_Challenges.questTitle(c) or c.title),
            iw - rightW - 12, color)
        ty = self:wrapped(ix, ty, c.description or "", iw, GREY)
        if c.modifiers and c.modifiers ~= "" then
            ty = self:wrapped(ix, ty, VB_Challenges.T("Card_Risk", c.modifiers), iw, RED)
        end
        if c.failed then
            ty = self:wrapped(ix, ty, VB_Challenges.T("History_FailedOn", c.day or 0, VB_Challenges.failReasonText(c.reasonKey or c.reason)), iw, RED)
        else
            ty = self:wrapped(ix, ty, VB_Challenges.T("History_CompletedOn", c.day or 0), iw, GREY)
        end
        y = self:endCard(card, ty - LINE_GAP + CARD_PAD) + GAP
    end
    if pages > 1 then
        y = self:pager(y + 4, w, pages)
    end
    return y
end

function VB_ChallengesContentPanel:pager(y, w, pages)
    local label = VB_Challenges.T("History_Page", self.completedPage, pages)
    local prevW, nextW = 80, 80
    self:button(PAD, y, prevW, VB_Challenges.T("Btn_Prev"), function()
        self.completedPage = self.completedPage - 1
        self:resetScroll()
    end, self.completedPage > 1)
    self:text(PAD + prevW + GAP * 2, y + (BTN_H - HGT_SMALL) / 2, label, GREY)
    self:button(PAD + prevW + GAP * 4 + measure(FONT_SMALL, label), y, nextW, VB_Challenges.T("Btn_Next"), function()
        self.completedPage = self.completedPage + 1
        self:resetScroll()
    end, self.completedPage < pages)
    return y + BTN_H + GAP
end

function VB_ChallengesContentPanel:buildDebug(player, state)
    local D = VB_Challenges.Debug
    local w = self:innerWidth()
    local cols = w >= 480 and 3 or 2
    local y = PAD
    y = self:wrapped(PAD, y, "Debug tools", w, RED, FONT_MEDIUM)
    y = self:wrapped(PAD, y, "Only visible when the game runs with -debug.", w, GREY) + GAP

    y = self:wrapped(PAD, y, "Score & level", w, GOLD)
    y = self:buttonRow(PAD, y, w, {
        { "+10 points", function() D.addPoints(10) end },
        { "+100 points", function() D.addPoints(100) end },
        { "Level up now", D.levelUp },
        { "Add reward choice", D.addPendingReward },
        { "Add trait reward", D.addTraitReward },
        { "+1 reroll & bounty", D.addTokens },
        { "Reset score/level", D.resetScore },
        { "Clear completed", D.clearCompleted },
        { "Dump state (console)", D.dumpState },
        { "Reset HUD position", function() if VB_Challenges.HUD then VB_Challenges.HUD.resetPosition() end end },
        { "Test level-up sound", function() VB_Challenges.Sounds.levelUp() end },
        { "Simulate gunshot", D.simulateGunshot, true, "Triggers the 'No firearms' check as if you fired a gun." },
    }, cols) + GAP

    for _, d in ipairs(VB_Challenges.DIFFICULTIES) do
        local q = state.active[d]
        local color = VB_Challenges.DIFFICULTY_COLOR[d]
        y = self:wrapped(PAD, y, VB_Challenges.difficultyLabel(d) .. ": " .. (q and VB_Challenges.questTitle(q) or "(no active challenge)"), w, color)
        if q then
            y = self:buttonRow(PAD, y, w, {
                { "Make ready", function() D.makeReady(d) end, true, "Fulfils the objective (deliver challenges spawn the items in your inventory)." },
                { "Force complete", function() D.forceComplete(d) end, true, "Completes and awards points without checking requirements." },
                { "Expire deadline", function() D.expireDeadline(d) end, q.deadlineAt ~= nil and not q.deadlineMet,
                  "Makes the deadline pass now (fails the challenge unless it's already done)." },
                { "Teleport to target", function() D.teleportToTarget(d) end, VB_Challenges.Location.isLocationType(q.type),
                  "Location challenges only: jumps to the target building (or back to the start point on the return leg)." },
                { "Teleport to cache", function() D.teleportToCache(d) end, q.cacheState == "hidden",
                  "Jumps next to the hidden supply cache." },
            }, cols)
        else
            y = self:buttonRow(PAD, y, w, {
                { "New offers", function()
                    D.newOffers(d)
                    self.page = "challenges"
                    self.offerFor = d
                    self:resetScroll()
                end },
            }, cols)
        end
        y = y + GAP
    end

    y = self:buttonRow(PAD, y + GAP, w, {
        { "RESET EVERYTHING", D.resetAll, true, "Wipes all challenge data for this character." },
    }, cols)
    return y
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

VB_ChallengesWindow = ISCollapsableWindow:derive("VB_ChallengesWindow")

-- Labels come from UI_VB_Challenges_Tab_<id>.
local TABS = {
    { id = "challenges" },
    { id = "level" },
    { id = "completed" },
    { id = "debug", debugOnly = true },
}

local function tabWidth(label)
    return math.max(90, measure(FONT_SMALL, label .. " (!)") + 24)
end

function VB_ChallengesWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = VB_Challenges.T("WindowTitle")
    o.resizable = true
    o.minimumWidth = 360
    o.minimumHeight = 300
    return o
end

function VB_ChallengesWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    self.tabButtons = {}
    local x = PAD
    for _, t in ipairs(TABS) do
        if not t.debugOnly or isDebugEnabled() then
            local label = VB_Challenges.T("Tab_" .. t.id)
            local tw = tabWidth(label)
            local btn = ISButton:new(x, th + GAP, tw, BTN_H, label, self, VB_ChallengesWindow.onTab)
            btn.internal = t.id
            btn.baseLabel = label
            btn:initialise()
            btn:instantiate()
            self:addChild(btn)
            table.insert(self.tabButtons, btn)
            x = x + tw + 4
        end
    end
    -- Never let the window get narrower than the tab strip.
    self.minimumWidth = math.max(self.minimumWidth, x + PAD)

    local top = th + GAP + BTN_H + GAP
    local bottom = self:resizeWidgetHeight()
    self.content = VB_ChallengesContentPanel:new(0, top, self.width, self.height - top - bottom)
    self.content.window = self
    self.content.anchorRight = true
    self.content.anchorBottom = true
    self.content:initialise()
    self.content:instantiate()
    self:addChild(self.content)

    -- Keep the resize grips above the content panel so they stay grabbable.
    if self.resizeWidget then self.resizeWidget:bringToTop() end
    if self.resizeWidget2 then self.resizeWidget2:bringToTop() end
    self:refresh()
end

function VB_ChallengesWindow:onTab(button)
    self.content.page = button.internal
    self.content.offerFor = nil
    self.content:resetScroll()
    self:refresh()
end

function VB_ChallengesWindow:updateTabs()
    local state = VB_Challenges.getState()
    for _, b in ipairs(self.tabButtons) do
        local title = b.baseLabel
        if b.internal == "level" and state and #state.pendingRewards > 0 then
            title = title .. " (!)"
        end
        b:setTitle(title)
        if b.internal == self.content.page then
            b.backgroundColor = { r = 0.35, g = 0.3, b = 0.1, a = 1 }
        else
            b.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
        end
    end
end

function VB_ChallengesWindow:refresh()
    if not self.content then return end
    self:updateTabs()
    self.content:rebuild()
end

----------------------------------------------------------------------
-- Open / toggle
----------------------------------------------------------------------

local function defaultSize()
    -- Scale with the game's font size option, but stay on screen.
    local fontScale = getCore():getOptionFontSizeReal() or 1
    local w = math.min(520 + fontScale * 40, getCore():getScreenWidth() - 40)
    local h = math.min(560 + fontScale * 40, getCore():getScreenHeight() - 80)
    return w, h
end

function VB_Challenges.UI.getWindow(create)
    if not VB_Challenges.UI.window and create then
        local w, h = defaultSize()
        local x = (getCore():getScreenWidth() - w) / 2
        local y = (getCore():getScreenHeight() - h) / 2
        local win = VB_ChallengesWindow:new(x, y, w, h)
        win:initialise()
        win:addToUIManager()
        win:setVisible(false)
        VB_Challenges.UI.window = win
    end
    return VB_Challenges.UI.window
end

function VB_Challenges.UI.open(page)
    if not getPlayer() then return end
    local win = VB_Challenges.UI.getWindow(true)
    if page then
        win.content.page = page
        win.content.offerFor = nil
        win.content:resetScroll()
    end
    win:setVisible(true)
    win:bringToTop()
    win:refresh()
end

function VB_Challenges.UI.openOnPage(page)
    VB_Challenges.UI.open(page)
end

function VB_Challenges.UI.toggle()
    local win = VB_Challenges.UI.getWindow(false)
    if win and win:isVisible() then
        win:close()
    else
        VB_Challenges.UI.open()
    end
end

table.insert(VB_Challenges.listeners, function()
    local win = VB_Challenges.UI.window
    if win and win.content then win.content.dirty = true end
end)

-- Hotkey (rebindable in Options > Mods)
local options = PZAPI.ModOptions:create("VB_Challenges", VB_Challenges.T("WindowTitle"))
options:addKeyBind("openKey", VB_Challenges.T("Opt_OpenKey"), Keyboard.KEY_K)
options:addTickBox("showHud", VB_Challenges.T("Opt_ShowHud"), true, VB_Challenges.T("Opt_ShowHud_tooltip"))
options:addTickBox("playSounds", VB_Challenges.T("Opt_PlaySounds"), true, VB_Challenges.T("Opt_PlaySounds_tooltip"))
VB_Challenges.UI.options = options

Events.OnKeyPressed.Add(function(key)
    if not getPlayer() then return end
    local opt = options:getOption("openKey")
    if opt and key == opt:getValue() then VB_Challenges.UI.toggle() end
end)

-- Right-click menu entry as an alternative way to open it.
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    context:addOption(VB_Challenges.T("ContextMenu_Open"), nil, function() VB_Challenges.UI.open() end)
end)

Events.OnGameStart.Add(function()
    if VB_Challenges.UI.window then
        VB_Challenges.UI.window:removeFromUIManager()
        VB_Challenges.UI.window = nil
    end
end)
