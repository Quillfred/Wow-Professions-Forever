-- Window: route and shopping list. /sr or /skillroute, or the "Route" button on the
-- profession window.
local addonName, ns = ...
local UI = {}
ns.UI = UI

local Data, Core = SkillRouteData, ns.Core
local ROW_H, ROWS_PAD = 36, 4
-- Right-hand columns: skill range (fixed position, left-aligned, blue) and cost
-- (right-aligned at the edge), so neither moves with the other's length.
local COST_W, RANGE_W, COL_GAP, EDGE = 100, 62, 10, 6
local RANGE_X = EDGE + COST_W + COL_GAP            -- range column's right edge, from row's right
local RANGE_COLOR = { 0.55, 0.80, 1.00 }
local RANKS = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local ahWhy -- defined with the shopping list

local RANK_STEP = { Journeyman = 2, Expert = 3, Artisan = 4 }
local RANK_NAMES = { [3] = "Neutral", [4] = "Friendly", [5] = "Honored", [6] = "Revered", [7] = "Exalted" }
local COLORS = { orange = "ff8040", yellow = "ffff00", green = "40bf40", grey = "808080" }

-- Money like the game's money display: numbers in the text colour, with "g", "s"
-- and "c" in gold, silver and copper. resume = colour of the text around it, so a
-- cost inside yellow text stays yellow after each coloured letter.
local GOLD, SILVER, COPPER = "ffd700", "c7c7cf", "eda55f"
local function money(c, resume)
  if not c then return "|cff808080no price|r" .. (resume and ("|cff" .. resume) or "") end
  c = math.floor(c + 0.5)
  local after = resume and ("|cff" .. resume) or ""
  local function unit(n, col, letter) return n .. "|cff" .. col .. letter .. "|r" .. after end
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = unit(g, GOLD, "g") end
  if g > 0 or s > 0 then out[#out + 1] = unit(s, SILVER, "s") end
  out[#out + 1] = unit(cp, COPPER, "c")
  return table.concat(out, " ")
end
local YELLOW = "ffd100"

local function icon(item, spell)
  local tex = item and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item))
                        or (GetItemIcon and GetItemIcon(item)))
  if not tex and spell then -- enchants make no item: use the spell's icon
    tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell))
          or (GetSpellTexture and GetSpellTexture(spell))
  end
  return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemName(item)
  local n = GetItemInfo and GetItemInfo(item)
  return n or (Data.items[item] and Data.items[item][1]) or ("item " .. item)
end

UI.Money, UI.Icon, UI.ItemName = money, icon, itemName -- shared with the mini panel

-- The last skill at which a recipe is orange, yellow and green, in those colours (green
-- from the midpoint of yellow and grey, as Planner.Color). One place for both panels.
function UI.Bands(r, sep)
  local greenFrom = math.floor((r.y + r.g) / 2)
  local learnAt = math.min(r.learn or r.y, r.y)
  local b = {}
  if r.y - 1 >= learnAt then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.orange, r.y - 1) end
  if greenFrom - 1 >= r.y then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.yellow, greenFrom - 1) end
  if r.g - 1 >= greenFrom then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.green, r.g - 1) end
  return table.concat(b, sep or " ")
end
-- text without colour codes or leading spaces (to reuse a row's words elsewhere)
function UI.Plain(s)
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""))
end

-- "Afterwards: sell the 5 Formal White Shirts to a vendor (5s 50c each) - AH 5s 40c
-- after the cut, can't be disenchanted. Not counted in the cost." Same comparison as
-- the shopping list's crafted-items section.
local ACTION_SHORT = { ah = "List on the AH", de = "Disenchant", vendor = "Sell to a vendor" }
-- returns the action ("List on the AH, 38c each") and the comparison ("vendor 1c · can't disenchant")
-- The other choices "Best" was weighed against, for any tooltip: AH (with how many are
-- listed), disenchanting (unless shown elsewhere: noDE), vendor.
function UI.Compared(a, item, noDE)
  local ench = Core.Skills()[333]
  local parts = {}
  local listed = a.listed and ((a.crowded and " |cffff8040(%d listed: crowded)|r" or " (%d listed)"):format(a.listed)) or ""
  if a.best ~= "ah" and a.ahCounted then
    -- crowded: why a higher AH price lost - it counted for less (it may not sell)
    listed = (" |cffff8040(%d listed: crowded, counted as %s (%d%%))|r"):format(a.listed, money(a.ahCounted, "ff8040"),
      math.floor(Core.CrowdedShare() * 100 + 0.5))
  end
  if a.best ~= "ah" then
    parts[#parts + 1] = a.bound and "soulbound: no AH" or a.ah and ("AH " .. money(a.ah) .. listed) or "AH: no fresh price"
  end
  if a.best ~= "de" and not noDE then
    if a.de then parts[#parts + 1] = "disenchant ~" .. money(a.de)
    elseif not Core.DisenchantOf(item) then parts[#parts + 1] = "can't disenchant"
    elseif not ench then parts[#parts + 1] = "disenchant: needs Enchanting"
    elseif a.deSkill and ench.rank < a.deSkill then parts[#parts + 1] = ("disenchant: needs %d"):format(a.deSkill)
    else parts[#parts + 1] = "disenchant: no fresh prices" end
  end
  if a.best ~= "vendor" then parts[#parts + 1] = a.vendor > 0 and ("vendor " .. money(a.vendor)) or "vendor: won't buy it" end
  return table.concat(parts, " · "), listed
end

local function afterCrafting(item, n)
  local ench = Core.Skills()[333]
  local a = Core.ItemAdvice(item, ench and ench.rank, n, ench and Core.EnchantingNeeds() or nil)
  local compared, listed = UI.Compared(a, item)
  local used = {}
  for _, u in ipairs(a.best == "de" and a.deUsed or {}) do
    used[#used + 1] = (u.units >= 1 and (u.units .. " ") or "") .. itemName(u.item)
  end
  local action = ("|cff40bf40%s, %s each|r"):format(ACTION_SHORT[a.best], money(a.bestValue))
    .. (a.best == "ah" and listed or "")
  return action, compared,
         #used > 0 and ("counts %s at buy price (your Enchanting route needs %s)"):format(table.concat(used, ", "),
           #used == 1 and "it" or "them") or nil
end

-- A gathering step's zones as shown everywhere (route, mini panel, tracker): your
-- faction's first, then contested, the other faction's last; most spots first within
-- each. "Mulgore (268)"; Fishing: names only, all of them.
function UI.GatherZones(st, max)
  local list = {}
  for k = 1, #(st.zones or {}), 2 do
    list[#list + 1] = { z = st.zones[k], n = st.zones[k + 1], r = Core.ZoneRank(st.zones[k]), i = k }
  end
  table.sort(list, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.i < b.i end)
  local zones = {}
  for _, x in ipairs(list) do
    if st.fishing then zones[#zones + 1] = Core.ZoneName(x.z)
    elseif #zones < (max or 3) then zones[#zones + 1] = ("%s (%d)"):format(Core.ZoneName(x.z), x.n) end
  end
  return zones
end

local function mats(spell, line)
  local r = Data.professions[line].recipes[spell]
  local parts = {}
  for i = 1, #r.r, 2 do parts[#parts + 1] = r.r[i + 1] .. " " .. itemName(r.r[i]) end
  return table.concat(parts, ", ")
end

-- Frame ----------------------------------------------------------------------------
-- 7000 -> "7,000"
local function thousands(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local favorTip -- the Favor note's hover lines (set when the route is drawn)
local frame, scroll, content, info, footer, targetBox, profText, modeBtn, hRange, ahBtn, scanBtn, hShop
local autoOpened = false -- opened with the profession window (so it closes with it)
local lastPlan
local rows = {}
local state = { mode = "route" }
UI._state = state -- for tests

local function charState()
  local c = Core.Char()
  c.targets = c.targets or {}
  return c
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(26, 26)
  r.icon:SetPoint("LEFT", 4, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
  r.text:SetPoint("RIGHT", r, "RIGHT", -(RANGE_X + RANGE_W + 6), 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.sub:SetJustifyH("LEFT")
  r.sub:SetWordWrap(false)
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.right:SetPoint("TOPRIGHT", -EDGE, -3)
  r.right:SetWidth(COST_W)
  r.right:SetJustifyH("RIGHT")
  r.range = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.range:SetPoint("TOPRIGHT", -RANGE_X, -3)
  r.range:SetWidth(RANGE_W)
  r.range:SetJustifyH("LEFT")
  r.range:SetTextColor(RANGE_COLOR[1], RANGE_COLOR[2], RANGE_COLOR[3])
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  r:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item)
    elseif self.spell and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spell)
    else GameTooltip:SetText(self.tipTitle or "") end
    UI.AddTipLines(self.tip)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      -- a recipe you know: open it in the profession window; else (or with Shift)
      -- a waypoint to the trainer / vendor that has it
      local shift = IsShiftKeyDown and IsShiftKeyDown()
      if not shift and self.recipe and state.line and Core.IsRecipeKnown(state.line, self.recipe) then
        if Core.OpenRecipe(self.recipe) then return end
        print("SkillRoute: open your profession window to craft " .. (self.skipName or "it") .. ".")
        return
      end
      if self.waypoint then Core.Waypoint(self.waypoint) end
      return
    end
    if not (self.skipSpell and state.line) then return end
    local skipped = Core.ToggleSkip(state.line, self.skipSpell)
    print(("SkillRoute: %s %s. /sr unskip brings back everything you skipped."):format(
      skipped and "skipping" or "no longer skipping", self.skipName or "?"))
    UI.Refresh()
  end)
  rows[i] = r
  return r
end

-- Tooltip lines: a string (wrapped white text), { header = "SkillRoute" }, { "Label", "value" }
-- (two columns), { "label", "value", sub = true } (grey, under the line above),
-- { note = "..." } (grey, wrapped), { gap = true } (blank line, never doubled or last).
function UI.AddTipLines(lines)
  local gapNext = false
  for _, l in ipairs(lines or {}) do
    if type(l) == "table" and l.gap then
      gapNext = true
    else
      if gapNext then GameTooltip:AddLine(" "); gapNext = false end
      if type(l) == "string" then GameTooltip:AddLine(l, 1, 1, 1, true)
      elseif l.header then GameTooltip:AddLine(" "); GameTooltip:AddLine(l.header, 0.2, 0.8, 1)
      elseif l.note then GameTooltip:AddLine(l.note, 0.62, 0.62, 0.62, true)
      elseif l.sub then GameTooltip:AddDoubleLine("  " .. (l[1] or ""), l[2] or "", 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
      else GameTooltip:AddDoubleLine(l[1] or "", l[2] or "", 1, 0.82, 0, 1, 1, 1) end
    end
  end
end

local function setRow(i, opts)
  local r = row(i)
  r.icon:SetTexture(opts.icon or icon(opts.item, opts.spell))
  r.text:SetText(opts.text or "")
  r.sub:SetText(opts.sub or "")
  r.right:SetText(opts.right or "")
  r.range:SetText(opts.range or "")
  r.item, r.spell, r.tip, r.tipTitle = opts.item, opts.spell, opts.tip, opts.tipTitle or opts.title
  r.skipSpell, r.skipName, r.waypoint, r.recipe = opts.skipSpell, opts.skipName, opts.waypoint, opts.recipe
  -- "Buy" button (auction house open): this step's reagents -> Auctionator list
  rawset(r, "ahStep", opts.ahStep)
  if opts.ahStep and not rawget(r, "buyBtn") then
    local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    b:SetSize(44, 16)
    b:SetPoint("BOTTOMRIGHT", -EDGE, 2)
    b:SetText("Buy")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
      local st = rawget(r, "ahStep")
      if st and lastPlan then b:SetText(Core.BuyStep(lastPlan, st, button == "RightButton")) end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local auc = Core.CanExportToAuctionator()
      GameTooltip:SetText(auc and "Add to your AH shopping list" or "Search the auction house")
      GameTooltip:AddLine("This step's reagents x the crafts it still needs (with your safety margin),"
        .. " minus what you have; vendor items left out.", 1, 1, 1, true)
      GameTooltip:AddLine(auc and "Right-click: take them back out."
        or "Searches one material per click; chat says how many you need.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.buyBtn = b
  end
  if rawget(r, "buyBtn") then
    if opts.ahStep then r.buyBtn:Show() else r.buyBtn:Hide() end
    r.sub:SetPoint("RIGHT", r, "RIGHT", opts.ahStep and -(EDGE + 50) or -6, 0)
  end
  if r.SetAlpha then r:SetAlpha(opts.later and 0.45 or 1) end -- past your character level's stop
  r:Show()
end

-- Where your character level stops a route: the first rank cap it passes that needs a
-- higher level. Returns cap, level needed, your level (or nil).
local function levelStop(plan)
  if plan.gather then return nil end
  for cap = plan.max, plan.target - 1, 75 do
    local stepN = ({ [75] = 2, [150] = 3, [225] = 4 })[cap]
    local need, mine
    if stepN then need, mine = Core.RankLevelShort(plan.line, stepN) end
    if need then return cap, need, mine end
  end
end
UI._levelStop = levelStop

local function lines()
  local c = charState()
  local mine = {}
  for line in pairs(Core.Skills()) do mine[#mine + 1] = line end
  table.sort(mine, function(a, b) return Data.professions[a].name < Data.professions[b].name end)
  return mine, c
end

local function shortTravel(loc) local t = loc and Core.TravelText(loc); return t and t:gsub("^about ", "~"):gsub(" away", "") end

-- A craft step's tooltip (the full route's rows and the mini panel share it). Returns
-- the recipe, the tooltip lines, the waypoint, the learn text for the row and the step
-- for the AH Buy button (nil when the AH isn't open).
local function stepTip(plan, st)
  local r = Data.professions[plan.line].recipes[st.spell]
  local learn = ""
  local trainerLoc, exact, questLoc
  local specName = r.spec and Data.specNames and Data.specNames[r.spec]
  if (st.learn == "trainer" or st.learn == "trainer?") and not specName then
    trainerLoc, exact = Core.NearestRecipeTrainer(plan.line, st.spell, r.learn or r.y)
  end
  if st.learn == "trainer" and specName then
    learn = "  |cffffd100Learn at your " .. specName .. " trainer"
            .. (st.learnCost and (" (" .. money(st.learnCost, YELLOW) .. ")") or "") .. "|r"
  elseif st.learn == "trainer" then
    learn = "  |cffffd100Learn at " .. (trainerLoc and trainerLoc.npc or "trainer")
            .. (st.learnCost and (" (" .. money(st.learnCost, YELLOW) .. ")") or "") .. "|r"
  elseif st.learn == "pattern" then
    if st.unlock and st.unlock.via == "owned" then
      learn = "  |cffffd100Learn from your " .. itemName(st.unlock.item) .. " (" .. st.unlock.owned .. ")|r"
    elseif st.unlock and st.unlock.via == "ah" then
      learn = "  |cffffd100Buy pattern on the AH (last seen " .. money(st.learnCost, YELLOW) .. ")|r"
              .. ahWhy(st.unlock.item)
    elseif st.unlock and st.unlock.via == "favor" then
      local v = Core.NearestVendor(st.unlock.item)
      learn = "  |cffffd100Buy pattern from " .. (v and v.npc or "the Favor vendor") .. " (" .. st.unlock.favor .. " Favor)|r"
    else
      local p = st.unlock and (Core.Place("vendor", st.unlock.item) or Core.NearestVendor(st.unlock.item))
      local who = (p and p.npc) or (st.unlock and st.unlock.vendorNames and st.unlock.vendorNames:match("^[^,]+")) or "a vendor"
      learn = "  |cffffd100Buy pattern from " .. who .. " (" .. money(st.learnCost, YELLOW) .. ")|r"
              .. ((not p and st.unlock and st.unlock.unverified) and " |cff808080(vendor faction unverified)|r" or "")
    end
  elseif st.learn == "trainer?" then
    learn = "  |cffffd100Learn at trainer (not confirmed yet)|r"
  elseif st.learn == "quest" then
    questLoc = Core.RecipeQuest(st.spell)
    learn = questLoc and ("  |cffffd100Quest \"%s\" from %s|r"):format(questLoc.title, questLoc.loc.npc)
            or "  |cffffd100Learn from a quest|r"
  end
  -- tooltip: label / value rows, details in grey under them (see UI.AddTipLines)
  local tip = { { header = "SkillRoute" } }
  local function row(l, v) tip[#tip + 1] = { l, v } end
  local function sub(l, v) if v and v ~= "" then tip[#tip + 1] = { l, v, sub = true } end end
  local function note(t) tip[#tip + 1] = { note = t } end
  local function gap() tip[#tip + 1] = { gap = true } end
  local function travel(loc) local t = Core.TravelText(loc); return t and t:gsub("^about ", "~"):gsub(" away", "") end
  row("Cost per craft", money(st.perCraft) .. (st.est and " |cffff8040(estimated)|r" or ""))
  -- the last skill at which the recipe is each colour (Planner.Color: green from the
  -- midpoint of yellow and grey)
  row("Skill-ups through", UI.Bands(r, " · "))
  sub("", ("last skill-up at each colour; no more from %d"):format(r.g))
  local sv = st.learn == "pattern" and st.unlock and st.unlock.savesShown
  local w = st.why
  local points = st.to - st.from
  if sv then
    row("Why this one", "the pattern pays off")
    sub("saves", money(sv) .. " over the route, price included")
  elseif w and w.gap >= 1 then
    row("Why this one", "cheapest here, saves " .. money(w.gap) .. " / point")
  elseif w then
    row("Why this one", "about as cheap as the next best")
  elseif st.only then
    row("Why this one", "only option here")
    sub("", ("no other recipe you can get covers %d-%d"):format(st.from, st.to))
  end
  if w then
    sub("next best", ("%s, %s / point"):format(w.name, money(w.perPoint)))
    if not sv and w.gap >= 1 and points > 1 then sub("over this step", "~" .. money(w.gap * points)) end
    local because = w.because == "reliable" and ("skills up more reliably (%.1f vs %.1f crafts per point)"):format(w.craftsOurs, w.craftsAlt)
      or w.because == "feeds" and "what it makes is used by later steps"
      or w.because == "resale" and ("sells back well (your Expect to sell setting, %d%%)"):format((SkillRouteDB.settings and SkillRouteDB.settings.resale) or 0)
      or w.because == "fee" and "the next best needs a trainer fee"
      or w.because == "time" and "fewer crafts (your craft's-time setting)"
      or w.because == "sticky" and "keeps going with the next step's recipe (within 3%)"
      or nil
    sub("because", because)
  end
  gap()
  -- where the recipe comes from
  local waypoint = trainerLoc
  if questLoc then
    local ql = questLoc.loc
    waypoint = ql
    row("Recipe", ('Quest "%s"'):format(questLoc.title))
    sub("from", ql.npc .. ", " .. (Core.Where(ql) or "?"))
    sub("travel", travel(ql))
    if questLoc.skill > 0 then sub("needs", ("skill %d"):format(questLoc.skill)) end
    note("A quest counts as 1g of effort when choosing recipes (time, sometimes materials); not added to what you spend.")
  elseif st.learn == "trainer" and specName then
    row("Recipe", ("Learn at your %s trainer%s"):format(specName, st.learnCost and (", " .. money(st.learnCost)) or ""))
  elseif st.learn == "trainer" then
    row("Recipe", ("Learn at %s%s"):format(trainerLoc and trainerLoc.npc or "your trainer",
      st.learnCost and (", " .. money(st.learnCost)) or ""))
    if trainerLoc then
      sub("where", Core.Where(trainerLoc))
      sub("travel", travel(trainerLoc))
      if not exact then sub("", "tier estimated from the skill level") end
    end
  elseif st.learn == "trainer?" then
    row("Recipe", "a trainer (not confirmed yet)")
    sub("", "open your trainer once: SkillRoute records what it teaches")
  elseif st.learn == "pattern" and st.unlock then
    local p, n = Core.Place("vendor", st.unlock.item)
    local buy = st.unlock.via ~= "ah" and st.unlock.via ~= "owned"
    local near = not p and buy and Core.NearestVendor(st.unlock.item)
    waypoint = buy and (p or near) or nil
    if st.unlock.via == "owned" then
      row("Recipe", "your " .. itemName(st.unlock.item))
      sub("", st.unlock.owned .. (st.unlock.owned == "in your bank" and ": take it out and use it"
        or st.unlock.owned == "on an alt" and ": mail it to this character" or ""))
    elseif st.unlock.via == "favor" then
      local v = p or near
      row("Recipe", ("%s, %d Merchant's Favor"):format(v and v.npc or "the Favor vendor", st.unlock.favor))
      if v then sub("where", Core.Where(v)); sub("travel", travel(v)) end
      sub("you have", ("%d Favor"):format(Core.FavorBalance()))
      if (st.unlock.rank or 0) > 0 then sub("needs", Core.RankName(st.unlock.rank) .. " with your trade faction") end
      note("Favor patterns cost no gold. Earn Favor by filling Waylaid Crates and handing them in.")
    elseif st.unlock.via == "ah" then
      row("Recipe", "AH, last seen " .. money(st.learnCost))
      local why = ahWhy(st.unlock.item, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^ %(", ""):gsub("%)$", "")
      if why ~= "" then note(why) end
    else
      local v = p or near
      row("Recipe", ("%s, %s"):format(v and v.npc or (st.unlock.vendorNames and st.unlock.vendorNames:match("^[^,]+")) or "a vendor",
        money(st.learnCost)))
      if p then
        sub("where", Core.FormatPlace(p, true):gsub("^[^,]+, ", "") .. (p.limited and " (limited stock)" or ""))
        if n > 1 then sub("", ("%d vendors known"):format(n)) end
      elseif near then
        sub("where", Core.Where(near))
        sub("travel", travel(near))
      elseif st.unlock.vendorNames then
        sub("sold by", st.unlock.vendorNames)
      elseif r.where then
        sub("where", r.where)
      end
      if not p and st.unlock.unverified then
        note("|cffff8040New in Forever: no vendor data yet, so it's not certain a vendor of your faction sells it.|r")
      end
    end
  end
  if specName then row("Needs", specName .. " |cff9d9d9d(your specialisation)|r") end
  for _, u in ipairs(st.tools or {}) do
    row("Needs", u.name .. " |cff9d9d9d(in your bags)|r")
    sub("", u.craftSpell and "craft one first (on the shopping list)" or ("buy one, " .. money(u.price)))
  end
  gap()
  -- what to do with what you make
  if st.credited then
    row("Afterwards", "used by later steps")
    sub("materials", money(st.grossCost) .. ", counted there")
  elseif st.resale then
    row("Afterwards", "|cff40bf40Sell on the AH|r")
    sub("brings back", money(st.resale) .. " at your Expect to sell setting")
  elseif r.out then
    local action, compared, used = afterCrafting(r.out, math.ceil(st.crafts - 1e-9) * (r.outN or 1))
    row("Afterwards", action)
    -- one alternative per line, so the tooltip stays narrow
    local first = true
    for part in (compared .. " · "):gmatch("(.-) · ") do
      sub(first and "compared" or "", part)
      first = false
    end
    if used then sub("", used) end
  end
  gap()
  local hints = {}
  if Core.IsRecipeKnown(plan.line, st.spell) then
    hints[#hints + 1] = "Click: open recipe"
    if waypoint then hints[#hints + 1] = "Shift-click: waypoint" end
  elseif waypoint then
    hints[#hints + 1] = "Click: waypoint"
  end
  hints[#hints + 1] = "Right-click: skip recipe"
  if st.tools then
    local names = {}
    for _, u in ipairs(st.tools) do names[#names + 1] = u.name end
    learn = learn .. "  |cffff8040needs " .. table.concat(names, ", ") .. "|r"
  end
  local ahStep = Core.CanBuyHere() and st or nil
  if ahStep then hints[#hints + 1] = Core.CanExportToAuctionator() and "Buy: add reagents to your AH shopping list" or "Buy: search the AH for them" end
  tip[#tip + 1] = { note = table.concat(hints, " · ") }
  return r, tip, waypoint, learn, ahStep
end
UI.StepTip = stepTip
UI.AfterCrafting = function(item, n) return afterCrafting(item, n) end

local function routeRows(plan)
  local n = 0
  local stopCap, stopNeed, stopMine = levelStop(plan)
  local later = false
  local function add(o) n = n + 1; o.later = later; setRow(n, o) end
  local trained = plan.max
  local toolShown = {}
  for _, st in ipairs(plan.steps) do
    -- rank training needed before this step?
    while RANKS[trained] and st.from >= trained do
      local rank = RANKS[trained]
      if stopCap and trained == stopCap and not later then
        add({ icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",
              text = ("|cffff4040After character level %d|r (you're %d)"):format(stopNeed, stopMine),
              sub = ("You can level to %d now. The faded steps below are for later."):format(stopCap),
              tip = { { header = "SkillRoute" }, { "Character level", ("%d needed past %d"):format(stopNeed, stopCap) },
                      { "you", ("level %d"):format(stopMine), sub = true },
                      { note = "The route below is planned already, so you can see what it will cost. \"Buy for\" counts it separately." } } })
        later = true
      end
      local rh = Core.RankHow(plan.line, RANK_STEP[rank]) -- visited trainer / ATT book or quest / nearest
      local p, n, loc = rh.place, rh.nPlaces, rh.loc
      local where = p and (p.zone .. (p.sub and (", " .. p.sub) or "") .. (p.x and (" (%.1f, %.1f)"):format(p.x, p.y) or ""))
                    or Core.Where(loc)
      local travelOf = function(l) local t = l and Core.TravelText(l); return t and t:gsub("^about ", "~"):gsub(" away", "") end
      local needLvl, myLvl = Core.RankLevelShort(plan.line, RANK_STEP[rank])
      local lvlWarn = needLvl and ("  |cffff4040needs character level %d (you're %d)|r"):format(needLvl, myLvl) or ""
      local gateSkill = ({ Journeyman = 50, Expert = 125, Artisan = 200 })[rank]
      local reqLine = ("skill %d, character level %d"):format(gateSkill, (Data.rankLevel and Data.rankLevel[RANK_STEP[rank]]) or 0)
      local function rankTip(howRow, howVal, from, extra, waypointLoc)
        local t = { { header = "SkillRoute" }, { howRow, howVal } }
        if from then
          t[#t + 1] = { "from", from.npc .. ", " .. (Core.Where(from) or "?"), sub = true }
          local tr = travelOf(from)
          if tr then t[#t + 1] = { "travel", tr, sub = true } end
        end
        t[#t + 1] = { "Needs", reqLine .. (needLvl and (" |cffff4040(you're level %d)|r"):format(myLvl) or "") }
        if rank == "Artisan" and howRow == "Train" then t[#t + 1] = { "", "some guides say skill 225: try at 200", sub = true } end
        for _, e in ipairs(extra or {}) do t[#t + 1] = e end
        if waypointLoc then t[#t + 1] = { gap = true }; t[#t + 1] = { note = "Click: waypoint" } end
        return t
      end
      -- no trainer teaches it: a book (Expert First Aid) or a quest (Artisan: "Triage").
      -- ATT's Forever data says which; a trainer you saw offer it still wins.
      local book, quest = rh.book, rh.quest
      if book then
        local bl = book.loc
        local tip = rankTip("Book", book.owned and ("your " .. book.name .. ", " .. (book.where or "in your bags")) or book.name,
          bl, { { note = book.owned and ("Use it to learn " .. rank .. ".") or ("No trainer teaches " .. rank .. ": it's this book.") } }, bl)
        add({ icon = "Interface\\Icons\\INV_Misc_Book_09", item = book.item,
              text = ("|cffffd100%s %s|r"):format(book.owned and "Read" or "Buy", book.name),
              sub = ("Teaches %s, needed past %d"):format(rank, trained)
                    .. (bl and ("  -  from %s, %s"):format(bl.npc, Core.Where(bl) or "?") or ("  -  " .. (book.where or "in your bags")))
                    .. lvlWarn,
              range = tostring(trained), right = (not book.owned and book.price) and money(book.price) or nil,
              tipTitle = book.name, tip = tip, waypoint = bl })
      elseif quest then
        local ql = quest.loc
        local tip = rankTip("Quest", '"' .. quest.title .. '"', ql,
          { { "", ("needs skill %d"):format(quest.skill), sub = true }, { note = "No trainer teaches " .. rank .. ": it's this quest's reward." } }, ql)
        add({ icon = "Interface\\Icons\\INV_Misc_Note_01",
              text = ("|cffffd100Quest \"%s\"|r for %s"):format(quest.title, rank),
              sub = ("Needs skill %d  -  from %s, %s"):format(quest.skill, ql.npc, Core.Where(ql) or "?") .. lvlWarn,
              range = tostring(trained), tipTitle = quest.title, tip = tip, waypoint = ql })
      else
        local extra = {}
        if p then
          extra[#extra + 1] = { "", ("you talked to them here%s"):format(n > 1 and (", %d trainers known"):format(n) or ""), sub = true }
        elseif loc then
          extra[#extra + 1] = { note = ("Forever trainers teach only the rank below their own title, and nothing until your skill reaches it.") }
        else
          extra[#extra + 1] = { note = "No trainer known. Talk to one once and SkillRoute remembers where they are." }
        end
        local tip = rankTip("Train", loc and loc.npc or "at your trainer", (not p) and loc or nil, extra, loc)
        if p then table.insert(tip, 3, { "where", where, sub = true }) end
        add({ icon = "Interface\\Icons\\INV_Misc_Book_09",
              text = ("|cffffd100Train %s|r"):format(rank) .. (loc and (" at " .. loc.npc) or " at your trainer"),
              sub = ("Needed to go past %d"):format(trained)
                    .. (where and ("  -  " .. where) or ("  -  |cff808080no %s trainer known|r"):format(rank)) .. lvlWarn,
              range = tostring(trained), tipTitle = ("Train %s"):format(rank), tip = tip, waypoint = loc })
      end
      trained = trained + 75
    end
    -- get each tool (rod, hammer...) right before the first step that needs it
    for _, u in ipairs(st.tools or {}) do
      if not toolShown[u] then
        toolShown[u] = true
        local learn = ""
        if u.learnHow == "trainer" then
          local r = u.craftSpell and Data.professions[plan.line].recipes[u.craftSpell]
          local t = r and Core.NearestRecipeTrainer(plan.line, u.craftSpell, r.learn or r.y)
          learn = "  |cffffd100Learn at " .. (t and t.npc or "trainer")
                  .. (u.learnCost and (" (" .. money(u.learnCost, YELLOW) .. ")") or "") .. "|r"
        elseif u.learnHow == "trainer?" then
          learn = "  |cffffd100Learn at trainer (not confirmed yet)|r"
        end
        if u.craftSpell then
          add({ item = u.item, spell = u.craftSpell, ahStep = Core.CanBuyHere()
                  and { spell = u.craftSpell, name = itemName(u.item), crafts = 1, var = 0, from = st.from, to = st.from } or nil,
                text = ("|cffff8040Craft 1 x %s|r (tool)"):format(itemName(u.item)),
                sub = mats(u.craftSpell, plan.line) .. learn,
                range = ("%d+"):format(math.max(u.from, st.from)), right = money(u.price),
                tip = { { header = "SkillRoute" }, { "Tool", ("needed from %d on"):format(st.from) },
                        { "", "craft one, keep it in your bags (not the bank)", sub = true } } })
        else
          local isVendor = Data.items[u.item] and Data.items[u.item][3]
          local v = isVendor and (Core.Place("vendor", u.item) or Core.NearestVendor(u.item)) or nil
          local tip = { { header = "SkillRoute" }, { "Tool", ("needed from %d on"):format(st.from) },
                        { "", u.equip and "equip it: you can only fish with it in your hands"
                                  or "keep it in your bags (not the bank)", sub = true } }
          if v then
            tip[#tip + 1] = { "Buy from", v.npc }
            tip[#tip + 1] = { "where", Core.Where(v) or "?", sub = true }
            local tr = shortTravel(v)
            if tr then tip[#tip + 1] = { "travel", tr, sub = true } end
            tip[#tip + 1] = { gap = true }
            tip[#tip + 1] = { note = "Click: waypoint" }
          end
          add({ item = u.item,
                text = ("|cffff8040Buy 1 x %s|r (tool)"):format(itemName(u.item)),
                sub = v and ("From %s, %s"):format(v.npc, Core.Where(v) or "?")
                      or isVendor and "From a trade supplies vendor" or "From the auction house",
                right = money(u.price), tip = tip, waypoint = v })
        end
      end
    end
    if st.smeltStep then -- ore already in your bags whose smelting still gives skill
      local r = Data.professions[plan.line].recipes[st.spell]
      local known = Core.IsRecipeKnown(plan.line, st.spell)
      add({ item = r and r.out, spell = st.spell,
            text = ("|cff%sSmelt %d x %s|r"):format(COLORS[st.color] or "ffffff", st.crafts, st.ore),
            sub = (st.bronzeStep and "Copper and Tin Bars (or their ore) in your bags, at any forge" or "The ore in your bags, at any forge")
                  .. (known and "" or "  |cffffd100learn " .. st.name .. " at your Mining trainer|r"),
            range = ("%d-%d"):format(st.from, st.to),
            tipTitle = st.name,
            tip = st.bronzeStep
                  and { { header = "SkillRoute" }, { "Smelt", ("%d x Bronze: a Copper Bar and a Tin Bar each"):format(st.crafts) },
                        { "", "smelt Copper and Tin Ore into bars first (no skill-up)", sub = true },
                        { "Skill-ups through", UI.Bands(r, " · ") },
                        { note = "For the Bronze Bars your other route uses. Needs a forge (most towns)." } }
                  or { { header = "SkillRoute" }, { "Smelt", ("%d x %s in your bags"):format(st.crafts, st.ore) },
                       { "Skill-ups through", UI.Bands(r, " · ") },
                       { note = "Smelting gives Mining skill until its recipe turns grey. Needs a forge (most towns)." } } })
    elseif st.gather then
      local zones = UI.GatherZones(st)
      add({ icon = st.skinning and "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
                   or st.fishing and "Interface\\Icons\\Trade_Fishing"
                   or (plan.line == 186 and "Interface\\Icons\\Trade_Mining" or "Interface\\Icons\\Trade_Herbalism"),
            text = st.skinning and ("|cff%s~%d|r x skin %s"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts), st.name)
                   or st.fishing and ("|cff%s~%d|r catches"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts - 1e-9))
                   or ("|cff%s~%d|r x %s"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts - 1e-9), st.name)
                      .. ((st.alt and st.alt[1]) and (" |cffcccccc(or %s)|r"):format(st.alt[1]) or "")
                      -- one line: with an alternative there's only room for the short form
                      .. (st.bronze and ((st.alt and st.alt[1]) and " |cffffd100+ Bronze|r"
                                         or ", |cffffd100smelting the ore into Bronze|r")
                          or st.smelt and ((st.alt and st.alt[1]) and " |cffffd100+ smelt|r"
                                           or ", |cffffd100smelting the ore as you go|r") or ""),
            sub = st.fishing and (#zones > 0 and ("No fish get away in: " .. table.concat(zones, ", "))
                                  or "Fish in your starting zone's waters")
                  or st.skinning and (#zones > 0 and ("Best zones: " .. table.concat(zones, ", "))
                                      or "Skin the highest-level beasts you can: always a skill point.")
                  or ((#zones > 0 and ("Best zones: " .. table.concat(zones, ", ")) or "")
                      -- kept short (one line): the names are in the tooltip
                      .. ((st.also and #st.also == 1 and #st.also[1] <= 18) and ("  |cff40bf40+ " .. st.also[1] .. " when you see it|r")
                          or (st.also and #st.also > 0) and ("  |cff40bf40+ %d more when you see them|r"):format(#st.also) or "")),
            range = ("%d-%d"):format(st.from, st.to),
            tipTitle = st.name,
            tip = st.fishing and (function()
                    local t = { { header = "SkillRoute" },
                      { "Skill-up", st.from < 75 and "every catch below 75"
                                    or ("about 1 in %d catches at %d, fewer as you go"):format(math.ceil(1 / ns.Planner.FishChance(st.from)), st.from) } }
                    if st.parts and #st.parts > 1 then
                      for i, part in ipairs(st.parts) do
                        t[#t + 1] = { i == 1 and "Catches" or "", ("%d-%d: ~%d"):format(part.from, part.to, math.ceil(part.crafts - 1e-9)) }
                      end
                    end
                    t[#t + 1] = { note = "Below a zone's fishing level you hook nothing; until 95 above it some fish get away." }
                    return t
                  end)()
                  or st.skinning and {
                    { header = "SkillRoute" },
                    { "Skin", "the highest-level beasts you can" },
                    { "", "beasts of level 21+ need 5 x their level in skill", sub = true },
                    { note = "Zones: most skinnable beasts of these levels (Classic spawn data), your faction's first." } }
                  or (function()
                    local t = { { header = "SkillRoute" },
                      { "Zones", "most spots of this node" } }
                    for i, z in ipairs(zones) do t[#t + 1] = { i == 1 and "" or "", z, sub = true } end
                    if st.alt and #st.alt > 0 then
                      t[#t + 1] = { "Or", st.alt[1] }
                      for i = 2, math.min(#st.alt, 5) do t[#t + 1] = { "", st.alt[i], sub = true } end
                      if #st.alt > 5 then t[#t + 1] = { "", ("and %d more"):format(#st.alt - 5), sub = true } end
                    end
                    if st.smelt then
                      t[#t + 1] = { "Smelt", ("~%d %s as you go (%s)"):format(st.smelt.n, st.smelt.ore, st.smelt.name) }
                      t[#t + 1] = { "", "each smelt is a chance at a skill-up too: fewer veins", sub = true }
                    end
                    if st.bronze then
                      local p = Core.Price(2770)
                      t[#t + 1] = { "Bronze", ("~%d x %s: ~%d Bronze Bars for your %s route"):format(st.bronze.n, st.bronze.name,
                        st.bronze.bars, table.concat(st.bronze.who or {}, " and ")) }
                      t[#t + 1] = { "", ("each needs a Copper Bar: buy ~%d Copper Ore%s"):format(st.bronze.copper,
                        p and (" (~" .. money(p * st.bronze.copper) .. ")") or ""), sub = true }
                      t[#t + 1] = { "", "smelt the Tin and Copper into bars, then Bronze", sub = true }
                    end
                    if st.buy then
                      local p = Core.Price(st.buy.oreItem)
                      t[#t + 1] = { "Or buy", ("~%d %s on the AH%s and only smelt"):format(st.buy.n, st.buy.ore,
                        p and (" (~" .. money(p * st.buy.n) .. ")") or "") }
                    end
                    if st.also and #st.also > 0 then
                      t[#t + 1] = { "When you see them", st.also[1] }
                      for i = 2, #st.also do t[#t + 1] = { "", st.also[i], sub = true } end
                    end
                    t[#t + 1] = { note = "Counts nodes: one skill-up per node at most, however many times you gather it (more swings give more ore or herbs, not more skill). Gather anything orange or yellow on the way." }
                    return t
                  end)() })
    elseif st.gap then
      add({ icon = "Interface\\Icons\\INV_Scroll_03",
            text = ("|cffff4040No usable recipe for %d-%d|r"):format(st.from, st.to),
            sub = plan.unpriced > 0 and "Scan the AH (some recipes had no prices), or get a pattern:"
                  or "Needs a pattern. Cheapest that cover this range:",
            range = st.from .. "-" .. st.to })
      for _, g in ipairs(plan.gaps) do
        if g.from == st.from then
          for k = 1, math.min(5, #g.patterns) do
            local pt = g.patterns[k]
            add({ item = pt.item, text = "   " .. pt.name,
                  sub = "   Good until " .. pt.to .. (pt.from and ("  -  " .. pt.from) or "")
                        .. ((Core.Place("vendor", pt.item) and ("  -  Sold by " .. Core.FormatPlace(Core.Place("vendor", pt.item))))
                            or (pt.where and ("  -  " .. pt.where)) or "")
                        .. (pt.otherSide and ("  -  |cffff8040%s vendors only|r"):format(pt.otherSide == "A" and "Alliance" or "Horde") or "")
                        .. (pt.repFaction and ("  -  |cffff8040needs %s with %s|r"):format(
                              RANK_NAMES[pt.repRank] or "?", Data.factions[pt.repFaction] or "?") or "")
                        .. (pt.price and "  -  AH" or "  -  not on the AH in your last scan"),
                  right = pt.price and money(pt.price) or "" })
          end
        end
      end
    else
      local r, tip, waypoint, learn, ahStep = stepTip(plan, st)
      add({ item = r.out, spell = st.spell, tip = tip, skipSpell = st.spell, skipName = st.name, waypoint = waypoint,
            recipe = st.spell, ahStep = ahStep,
            text = ("|cff%s~%d|r x %s"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts - 1e-9), st.name),
            sub = mats(st.spell, plan.line) .. learn,
            range = ("%d-%d"):format(st.from, st.to),
            right = st.credited and "|cff808080counted later|r" or money(st.cost) })
    end
  end
  return n
end

-- why a pattern is bought on the AH: no vendor of your faction sells it, or the AH
-- is cheaper than the vendor
ahWhy = function(item, long) -- long: with the vendors' names (tooltips)
  local pv = Data.patternVendors and Data.patternVendors[item]
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  local me = mine == "Alliance" and "A" or mine == "Horde" and "H" or nil
  if pv and me and not pv[1]:find(me, 1, true) then
    local other = me == "H" and pv[2] or pv[3]
    if not long then return (" |cff808080(only %s vendors sell it)|r"):format(me == "H" and "Alliance" or "Horde") end
    return (" |cff808080(only %s vendors sell it%s. Auction houses are per faction: buy it when someone lists it on yours, or at a"
      .. " neutral one - Booty Bay, Gadgetzan, Everlook - which takes a 15%% cut.)|r"):format(
      me == "H" and "Alliance" or "Horde", other ~= "" and (": " .. other) or "")
  end
  local it = Data.items[item]
  if it and it[3] then return (" |cff808080(cheaper than the vendor's %s)|r"):format(money(it[3])) end
  if not pv then return " |cff808080(no vendor sells it)|r" end
  return ""
end

UI.AhWhy = function(item, long) return ahWhy(item, long) end

-- "What to do with crafted items in your bags": AH, disenchant or vendor, whichever
-- brings most (fresh AH prices only)
local ACTION = { ah = "|cff40bf40List on the AH|r", de = "|cffa335eeDisenchant|r", vendor = "|cffffd100Sell to a vendor|r" }
local function craftedRows(plan, add)
  local list = Core.CraftedAdvice(plan)
  if #list == 0 then return end
  add({ icon = "Interface\\Icons\\INV_Misc_Bag_10", text = "|cffffffffCrafted items in your bags|r",
        sub = "The best of: AH (fresh price, after the 5% cut), disenchant (results at AH prices), vendor." })
  for _, x in ipairs(list) do
    local a = x.advice
    local parts = {}
    parts[#parts + 1] = a.ah and ("AH " .. money(a.ah) .. (a.listed and ((a.crowded and " |cffff8040(%d listed: crowded)|r" or " (%d listed)"):format(a.listed)) or "")) or "AH: no fresh price"
    if a.de then parts[#parts + 1] = "disenchant ~" .. money(a.de) .. ((a.deUsed and #a.deUsed > 0) and " (Enchanting route needs the results)" or "")
    elseif a.deSkill then parts[#parts + 1] = Core.Skills()[333] and "disenchant: no fresh prices" or "disenchant: needs Enchanting" end
    parts[#parts + 1] = "vendor " .. money(a.vendor)
    local tip = { { header = "SkillRoute" }, { "Best", ACTION[a.best] .. ", " .. money(a.bestValue) .. " each" },
                  { "AH", a.ah and (money(a.ah) .. " after the 5% cut") or "no fresh price", sub = true } }
    if a.listed then
      tip[#tip + 1] = { "listed", ("%d now%s"):format(a.listed, a.crowded and ": crowded, so the AH counts for 70% when choosing" or ""), sub = true }
    end
    if a.de then tip[#tip + 1] = { "disenchant", "~" .. money(a.de) .. ((a.deUsed and #a.deUsed > 0) and " (counts what Enchanting needs)" or ""), sub = true }
    elseif a.deSkill then tip[#tip + 1] = { "disenchant", Core.Skills()[333] and "no fresh prices for what it gives" or "needs Enchanting", sub = true } end
    tip[#tip + 1] = { "vendor", money(a.vendor), sub = true }
    if a.deLoot then
      tip[#tip + 1] = { gap = true }
      for i = 1, #a.deLoot, 4 do
        tip[#tip + 1] = { i == 1 and "Disenchants into" or "", ("%d%%  %d-%d %s"):format(a.deLoot[i + 1], a.deLoot[i + 2], a.deLoot[i + 3], itemName(a.deLoot[i])) }
      end
      tip[#tip + 1] = { note = "Classic loot tables, checked against Forever." }
    end
    if a.best == "ah" then
      tip[#tip + 1] = { note = "Listing costs a deposit, lost if it doesn't sell; the price is today's lowest listing." }
    end
    add({ item = x.item, tip = tip,
          text = ("%s %d x %s"):format(ACTION[a.best], x.count, itemName(x.item)),
          sub = "each: " .. table.concat(parts, "  -  "),
          right = money(a.bestValue * x.count) })
  end
end

local function shoppingRows(plan)
  local n = 0
  local function add(o) n = n + 1; setRow(n, o) end
  for _, c in ipairs(plan.shopping.craft) do
    local r = Data.professions[c.line or plan.line].recipes[c.spell]
    if c.line then -- made with another of your professions (a miner's bars...)
      local prof = Data.professions[c.line].name
      add({ item = r.out, spell = c.spell,
            text = ("Make %d x %s |cff9d9d9d(%s: %s)|r"):format(c.n * (r.outN or 1), itemName(r.out), prof, c.name),
            sub = ("|cff40bf40You have %s:|r cheaper than buying. Uses the materials below, yours first."):format(prof) })
    else
    add({ item = r.out, text = ("Craft %d x %s"):format(c.n, c.name),
          sub = c.tool and "|cffff8040Tool for later steps: keep it in your bags|r"
                or "Cheaper to make than to buy; uses the reagents below" })
    end
  end
  for _, b in ipairs(plan.shopping.buy) do
    local tags = {}
    -- who sells it, as on the route: a vendor you visited, else the nearest for your faction
    local sold = (b.pattern or b.tool or b.book or b.vendor) and not b.ah
    local p = sold and Core.Place("vendor", b.item)
    local near = sold and not p and Core.NearestVendor(b.item)
    local loc = p or near or nil
    local who = p and Core.FormatPlace(p, true) or near and (near.npc .. ", " .. (Core.Where(near) or "?")) or nil
    if b.book then tags[#tags + 1] = "|cffffd100rank-up book, from " .. (who or "a vendor") .. "|r"
    elseif b.pattern and b.favor then tags[#tags + 1] = "|cffffd100pattern, for Merchant's Favor from " .. (who or "the Favor vendor") .. "|r"
    elseif b.pattern then tags[#tags + 1] = b.ah and ("|cffffd100pattern, on the AH (last seen price)|r" .. ahWhy(b.item))
                                         or ("|cffffd100pattern, from " .. (who or "a vendor") .. "|r")
    elseif b.tool then tags[#tags + 1] = "|cffff8040tool: keep it in your bags|r"
                                         .. (who and (", from " .. who) or b.vendor and ", vendor" or "")
    elseif b.vendor then tags[#tags + 1] = who and ("vendor: " .. who) or "vendor" end
    local tip
    if loc then
      tip = { { header = "SkillRoute" }, { "Buy from", loc.npc .. (p and " |cff9d9d9d(you visited them)|r" or "") },
              { "where", p and (Core.FormatPlace(p, true):gsub("^[^,]+, ", "")) or (Core.Where(near) or "?"), sub = true } }
      local tr = shortTravel(loc)
      if tr then tip[#tip + 1] = { "travel", tr, sub = true } end
      tip[#tip + 1] = { gap = true }
      tip[#tip + 1] = { note = "Click: waypoint" }
    end
    if b.est then tags[#tags + 1] = "|cffff8040estimated price|r" end
    do -- essences: the other form can be cheaper (3 lesser = 1 greater)
      local other, n2, _, how = Core.EssenceSwap(b.item, b.buy)
      if other and b.buy > 0 then
        tags[#tags + 1] = ("|cff40bf40cheaper as %d x %s (%s)|r"):format(n2, itemName(other),
          how == "split" and "right-click each to split into 3" or "combine 3 into 1")
      end
    end
    if not tip and not b.farm and not b.vendor then
      local pi = Core.PriceInfo(b.item)
      if pi.ah or pi.paid then
        tip = { { header = "SkillRoute" } }
        if pi.ah then
          tip[#tip + 1] = { "AH price", money(pi.ah) .. " each" .. (pi.forN and (" for %d"):format(pi.forN) or "") }
          if pi.cheapest and pi.cheapest < pi.ah then tip[#tip + 1] = { "cheapest", money(pi.cheapest), sub = true } end
          if pi.age then
            tip[#tip + 1] = { "seen", pi.age == 0 and "today" or pi.age == 1 and "yesterday" or ("%d days ago"):format(pi.age), sub = true }
          end
        end
        if pi.paid then
          tip[#tip + 1] = { "You paid", money(pi.paid) .. " each" .. (pi.paidDays == 0 and " (today)"
                             or (" (%d day%s ago)"):format(pi.paidDays, pi.paidDays == 1 and "" or "s")) }
          if not pi.ah then tip[#tip + 1] = { note = "Not on the AH in the last scan: priced at what you paid." } end
        end
      end
    end
    if b.farm and b.buy > 0 then
      add({ item = b.item,
            text = ("|cff40bf40Farm %d x %s|r"):format(b.buy, b.name),
            sub = Core.FarmText(b.item) or "",
            tip = (function()
              local t = { { header = "SkillRoute" }, { "Farm it", "not on the auction house" },
                          { "need", ("%d, have %d"):format(b.need, b.have), sub = true }, { gap = true } }
              for line in ((Core.FarmText(b.item, true) or "") .. "\n"):gmatch("(.-)\n") do
                if line ~= "" then t[#t + 1] = { #t == 4 and "Where" or "", line } end
              end
              return t
            end)() })
    else
    add({ item = b.item,
          text = b.buy > 0 and ("Buy %d x %s"):format(b.buy, b.name) or ("|cff40bf40Have all %s|r"):format(b.name),
          sub = ("need %d%s, have %d%s%s"):format(b.need,
                  (b.expected and b.expected < b.need) and (" (~%d expected)"):format(b.expected) or "",
                  b.have, (b.alts or 0) > 0 and (" |cff40bf40(+%d on alts)|r"):format(b.alts) or "",
                  #tags > 0 and ("  -  " .. table.concat(tags, ", ")) or ""),
          right = b.favor and ("|cffffd100%d Favor|r"):format(b.favor) or b.price and money(b.price * b.buy) or money(nil),
          tipTitle = loc and b.name or nil, tip = tip, waypoint = loc })
    end
  end
  craftedRows(plan, add)
  return n
end

-- Bottom-right buttons: Scan AH while the auction house is open, Send to Auctionator in
-- the shopping list; the footer text stops short of whichever are showing.
function UI.UpdateButtons()
  if not frame then return end
  local P = ns.Prices
  local scanning = P and P.Scanning()
  if scanBtn then
    if Core.ahOpen and P then
      scanBtn:Show()
      scanBtn:SetText(scanning and "Scanning..." or "Scan AH")
      if scanning then scanBtn:Disable() else scanBtn:Enable() end
    else scanBtn:Hide() end
  end
  -- shopping view: Send to Auctionator, or without it SkillRoute's buying panel at the AH
  local auc = Core.CanExportToAuctionator()
  local showAuc = state.mode == "shopping" and (auc or (Core.ahOpen and ns.BuyPanel and ns.BuyPanel.CanUse()))
  if ahBtn then ahBtn:SetText(auc and "Send to AH list" or "Buy shopping list") end
  if ahBtn then
    ahBtn:ClearAllPoints()
    if scanBtn and scanBtn:IsShown() then ahBtn:SetPoint("RIGHT", scanBtn, "LEFT", -4, 0)
    else ahBtn:SetPoint("BOTTOMRIGHT", -14, 8) end
    if showAuc then ahBtn:Show() else ahBtn:Hide() end
  end
  local inset = 14 + ((scanBtn and scanBtn:IsShown()) and 124 or 0) + (showAuc and 154 or 0)
  footer:SetPoint("RIGHT", -math.max(inset, 20), 0)
  UI.FitFooter() -- a narrower footer may now wrap
end

-- The list ends just above the footer, however many lines the footer takes.
local TIMING = "   |cff808080planned in"
local rawFooterSet, footerFull -- the footer's own SetText (its SetText also fits the list), its full text
function UI.FitFooter()
  if not (scroll and footer) then return end
  -- the "planned in" timing goes first when the line is too long: the total matters more
  local full = footerFull
  local _, size = footer:GetFont()
  local oneLine = (size or 12) * 1.6
  local cut = full and full:find(TIMING, 1, true)
  if cut then
    rawFooterSet(footer, full)
    if (footer:GetStringHeight() or 0) > oneLine then
      rawFooterSet(footer, full:sub(1, cut - 1))
    end
  end
  local h = footer:GetStringHeight() or 0
  local bottom = math.max(34, math.ceil(12 + h + 8))
  if bottom == scroll.bottom then return end
  scroll.bottom = bottom
  scroll:SetPoint("BOTTOMRIGHT", -32, bottom)
end
UI._footer = function() return footer, scroll end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  local mine, c = lines()
  if #mine == 0 then
    profText:SetText("No crafting profession")
    info:SetText("Learn a crafting profession first.")
    for _, r in ipairs(rows) do r:Hide() end
    footer:SetText("")
    return
  end
  local line = state.line
  if not line or not Data.professions[line] then line = c.lastLine end
  local okLine = false
  for _, l in ipairs(mine) do if l == line then okLine = true end end
  if not okLine then line = mine[1] end
  state.line, c.lastLine = line, line
  profText:SetText(Data.professions[line].name)
  local target = c.targets[line] or 300
  if not targetBox:HasFocus() then targetBox:SetText(tostring(target)) end

  local plan, err, why = Core.Plan(line, target)
  if not plan then
    info:SetText(why == "maxed" and ("|cff40bf40" .. err .. "|r") or err)
    for _, r in ipairs(rows) do r:Hide() end -- not the last profession's route
    footer:SetText("")
    return
  end
  local src = Core.PriceSource()
  src = src and (src .. " prices") or "|cffff4040No AH prices yet: scan the AH (Scan AH button)|r"
  local warn = {}
  local nSkip = 0
  for _ in pairs(Core.Skips(plan.line)) do nSkip = nSkip + 1 end
  if nSkip > 0 then
    warn[#warn + 1] = ("|cffffd100%d recipe%s skipped by you (/sr unskip to bring back)|r"):format(nSkip, nSkip > 1 and "s" or "")
  end
  if plan.unpriced > 0 then
    local n = plan.unpriced
    local names = {}
    for item in pairs(plan.unpricedItems or {}) do names[#names + 1] = UI.ItemName(item) end
    table.sort(names)
    if Core.PriceSource() and #names > 0 then
      -- you've scanned: nobody is selling it right now (another scan won't help)
      if #names > 3 then names = { names[1], names[2], ("%d more"):format(#names - 2) } end
      warn[#warn + 1] = ("|cff9d9d9d%d recipe%s left out: no %s on the AH right now|r"):format(n, n == 1 and "" or "s",
        table.concat(names, ", "))
    else
      warn[#warn + 1] = ("|cffff8040%d recipe%s skipped: reagents with no price (scan the AH)|r"):format(n, n == 1 and "" or "s")
    end
  end
  if plan.mismatch and plan.mismatch > 0 then
    warn[#warn + 1] = ("|cffff4040%d recipe colours differ from the data: update SkillRoute|r"):format(plan.mismatch)
  end
  -- the first rank this route passes that your character level is too low for
  do
    local cap, need, mine = levelStop(plan)
    if cap then
      warn[#warn + 1] = ("|cffff4040You can level to %d now; past it needs character level %d (you're %d). Faded steps are for later.|r")
        :format(cap, need, mine)
    end
  end
  -- Favor patterns that would save gold but can't be had yet (balance or reputation)
  if plan.favorWanted and next(plan.favorWanted) and #warn < 2 then
    local names, all = {}, {}
    for key, w in pairs(plan.favorWanted) do all[#all + 1] = { key = key, w = w } end
    table.sort(all, function(a, b) return a.w.saves > b.w.saves end)
    local tip = { "Merchant's Favor patterns that would save gold" }
    local have = Core.FavorBalance()
    local short = 0
    for i, x in ipairs(all) do
      local spell = tonumber(x.key:match("^p:(%d+)"))
      local r = spell and Data.professions[plan.line].recipes[spell]
      local fav = r and r.pat and Core.FavorOf(r.pat[1])
      local togo = fav and fav[2] > 0 and Core.RepToGo(fav[2])
      if i <= 2 then
        names[#names + 1] = (r and r.n or "?") .. (fav and (x.w.why == "rep"
          and (" (needs %s%s)"):format(Core.RankName(fav[2]), togo and (", " .. thousands(togo) .. " rep") or "")
          or (" (%d Favor, you have %d)"):format(fav[1], have)) or "")
      elseif i == 3 then names[#names + 1] = ("%d more"):format(#all - 2) end
      if fav then
        short = math.max(short, fav[1] - have)
        -- the planner's estimate includes its gap penalty when the pattern fills a gap: no
        -- real gold figure then, so none is shown (as on the route's own tooltips)
        local real = x.w.saves and x.w.saves < 1e8
        tip[#tip + 1] = ("%s: %d Favor%s%s"):format(r and r.n or "?", fav[1],
          fav[2] > 0 and (", needs " .. Core.RankName(fav[2]) .. (togo and togo > 0 and (" (" .. thousands(togo) .. " rep to go)") or "")) or "",
          real and (", saves ~" .. money(x.w.saves)) or "")
      end
    end
    tip[#tip + 1] = ("You have %d Favor."):format(have)
    local tiers = Core.CheapestFavor()
    if short > 0 and #tiers > 0 then
      local parts = {}
      for _, t in ipairs(tiers) do parts[#parts + 1] = ("%s crates ~%s"):format(t.tier, money(short * t.per)) end
      tip[#tip + 1] = ("%d more Favor, in crate materials at today's prices: %s. Which crates you find depends on the mobs you fight; hover one for its cheapest fill.")
        :format(short, table.concat(parts, ", "))
    end
    tip[#tip + 1] = "Reputation: Craftsman's Writs (75 / 125 / 200) and Crate Returns (50)."
    favorTip = tip
    warn[#warn + 1] = "|cff9d9d9dWould save gold with Merchant's Favor: " .. table.concat(names, ", ") .. "  (hover)|r"
  else
    favorTip = nil
  end
  local fb = Data.favor and Core.FavorBalance() or 0
  if fb > 0 then src = src .. ("   -   %d Favor"):format(fb) end
  info:SetText(("Skill %d/%d  ->  %d   -   %s%s"):format(plan.skill, plan.max, plan.target, src,
    #warn > 0 and ("\n" .. table.concat(warn, "\n")) or ""))

  lastPlan = plan
  UI.UpdateButtons()
  local n = state.mode == "route" and routeRows(plan) or shoppingRows(plan)
  for i = n + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, n * ROW_H + ROWS_PAD))
  modeBtn:SetText(state.mode == "route" and "Shopping list" or "Route")
  if state.mode == "route" then hRange:Show(); hShop:Hide()
  else
    hShop:SetText(("need: covers bad luck, %d%% sure (Options)  ·  expected: the average")
      :format((SkillRouteDB.settings or {}).margin or 90))
    hShop:Show(); hRange:Hide()
  end
  if plan.gather then
    footer:SetText(("Gathering route: about %d %s   |cff808080planned in %s|r"):format(math.ceil(plan.gathers or 0),
      plan.line == 393 and "skins" or plan.line == 356 and "catches" or "nodes", plan.ms and ("%.1f ms"):format(plan.ms) or "?"))
    return
  end
  -- the part of it for steps past your character level's stop (their materials and patterns)
  local laterText = ""
  do
    local cap, need = levelStop(plan)
    if cap then
      local later, seen = 0, {}
      for _, st in ipairs(plan.steps) do
        if not st.gap and st.from >= cap then
          if not st.credited then later = later + (st.cost or 0) end
          local u = st.unlock
          if u and u.via ~= "owned" and not seen[u] then seen[u] = true; later = later + (u.price or 0) end
        end
      end
      if later > 0 then laterText = (" |cff9d9d9d(~%s of it after level %d)|r"):format(money(math.min(later, plan.total), "9d9d9d"), need) end
    end
  end
  footer:SetText(("Buy for |cffffffff%s|r%s%s%s   |cff808080planned in %s|r"):format(money(plan.total, "ffffff"), laterText,
    ((plan.fees or 0) > 0 and (" + |cffffffff" .. money(plan.fees, "ffffff") .. "|r training") or "")
    .. (function()
      local back = 0
      for _, st in ipairs(plan.steps) do back = back + (st.resale or 0) end
      return back > 0 and ("  |cff40bf40(~%s back from sales)|r"):format(money(back, "40bf40")) or ""
    end)(),
    plan.estimated and " |cffff8040(includes estimates)|r" or "",
    plan.ms and ("%.1f ms"):format(plan.ms) or "?"))
end

function UI.Refresh()
  local ok, err = pcall(refresh)
  if not ok then
    Core.ReportError("window", err)
    if info then
      info:SetText("|cffff4040SkillRoute couldn't plan: " .. tostring(err) .. "|r\nType /sr check and send a screenshot.")
    end
    for _, r in ipairs(rows) do r:Hide() end
  end
end

function UI.IsShown() return frame and frame:IsShown() end
-- "route" or "shopping" (the Route / Shopping list button); also for the tests
function UI.SetMode(mode)
  state.mode = mode
  if frame and frame:IsShown() then UI.Refresh() end
end
function UI.Rows() return rows end
function UI._lastPlan() return lastPlan end -- for the tests

-- A window you can drag, that opens where you left it (saved in settings[key], kept
-- across reloads and characters). place() puts it back; call it when it's built.
function UI.Draggable(f, key, point, x, y)
  local function place()
    local p = (SkillRouteDB.settings or {})[key]
    f:ClearAllPoints()
    if p then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else f:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0) end
  end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, t = self:GetLeft(), self:GetTop()
    if l and t then
      SkillRouteDB.settings = SkillRouteDB.settings or {}
      SkillRouteDB.settings[key] = { math.floor(l + 0.5), math.floor(t + 0.5) }
    end
    place() -- anchored to the saved spot, not wherever the drag left its points
  end)
  place()
  return place
end

local function build()
  frame = CreateFrame("Frame", "SkillRouteFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(600, 560)
  UI.Draggable(frame, "routePos")
  frame:SetClampedToScreen(true)
  frame:SetScript("OnShow", function() Core.InvalidatePatterns(); UI.Refresh() end)
  frame:SetScript("OnHide", function() autoOpened = false end)
  tinsert(UISpecialFrames, "SkillRouteFrame") -- Escape closes it
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("SkillRoute")

  local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  prev:SetSize(24, 22); prev:SetPoint("TOPLEFT", 12, -30); prev:SetText("<")
  profText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  profText:SetPoint("LEFT", prev, "RIGHT", 8, 0); profText:SetWidth(150); profText:SetJustifyH("LEFT")
  local nextB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextB:SetSize(24, 22); nextB:SetPoint("LEFT", profText, "RIGHT", 4, 0); nextB:SetText(">")
  local function cycle(d)
    local mine = lines()
    if #mine == 0 then return end
    local idx = 1
    for i, l in ipairs(mine) do if l == state.line then idx = i end end
    state.line = mine[(idx - 1 + d) % #mine + 1]
    UI.Refresh()
  end
  prev:SetScript("OnClick", function() cycle(-1) end)
  nextB:SetScript("OnClick", function() cycle(1) end)

  local tl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tl:SetPoint("LEFT", nextB, "RIGHT", 16, 0); tl:SetText("Target")
  targetBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  targetBox:SetSize(40, 20); targetBox:SetPoint("LEFT", tl, "RIGHT", 10, 0)
  targetBox:SetAutoFocus(false); targetBox:SetNumeric(true); targetBox:SetMaxLetters(3)
  local function applyTarget(self)
    local v = tonumber(self:GetText())
    if v and state.line then charState().targets[state.line] = math.max(2, math.min(300, v)) end
    self:ClearFocus()
    UI.Refresh()
  end
  targetBox:SetScript("OnEnterPressed", applyTarget)
  targetBox:SetScript("OnEditFocusLost", function(self) if self:GetText() ~= "" then applyTarget(self) end end)
  targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UI.Refresh() end)

  modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  modeBtn:SetSize(110, 22); modeBtn:SetPoint("TOPRIGHT", -14, -30)
  local optBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  optBtn:SetSize(64, 22); optBtn:SetPoint("RIGHT", modeBtn, "LEFT", -4, 0); optBtn:SetText("Options")
  optBtn:SetScript("OnClick", function() if ns.Options then ns.Options.Toggle() end end)
  modeBtn:SetScript("OnClick", function()
    state.mode = state.mode == "route" and "shopping" or "route"
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    UI.Refresh()
  end)

  info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 14, -60); info:SetPoint("RIGHT", -14, 0); info:SetJustifyH("LEFT")
  -- hovering the lines under the title: the Merchant's Favor details, when there are any
  local infoHit = CreateFrame("Frame", nil, frame)
  infoHit:SetPoint("TOPLEFT", 14, -60); infoHit:SetPoint("RIGHT", -14, 0); infoHit:SetHeight(36)
  infoHit:EnableMouse(true)
  infoHit:SetScript("OnEnter", function(self)
    if not favorTip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(favorTip[1])
    for i = 2, #favorTip do GameTooltip:AddLine(favorTip[i], 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  infoHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- still drags the window, like the rest of it
  infoHit:RegisterForDrag("LeftButton")
  infoHit:SetScript("OnDragStart", function() local f = frame:GetScript("OnDragStart"); if f then f(frame) end end)
  infoHit:SetScript("OnDragStop", function() local f = frame:GetScript("OnDragStop"); if f then f(frame) end end)
  UI._favorTip = function() return favorTip end -- for the tests

  scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -112)
  -- column headings, aligned with the row columns (scroll area ends 32px from the edge)
  hRange = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hRange:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(32 + RANGE_X), -98)
  hRange:SetWidth(RANGE_W); hRange:SetJustifyH("LEFT"); hRange:SetText("Skill")
  hRange:SetTextColor(RANGE_COLOR[1], RANGE_COLOR[2], RANGE_COLOR[3])
  -- shopping list: what "need" and "expected" mean, on the headings row
  hShop = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hShop:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -98); hShop:SetPoint("RIGHT", frame, "RIGHT", -(32 + EDGE + COST_W), 0)
  hShop:SetJustifyH("LEFT")
  if hShop.SetWordWrap then hShop:SetWordWrap(false) end -- one line: never runs into the list
  local hCost = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hCost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(32 + EDGE), -98)
  hCost:SetWidth(COST_W); hCost:SetJustifyH("RIGHT"); hCost:SetText("Cost")
  scroll:SetPoint("BOTTOMRIGHT", -32, 34)
  scroll.bottom = 34
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(550, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  footer:SetPoint("BOTTOMLEFT", 14, 12); footer:SetPoint("RIGHT", -170, 0); footer:SetJustifyH("LEFT")
  -- the footer can run to two lines (a long total, a narrow window): the list then ends
  -- above it instead of underneath
  rawFooterSet = footer.SetText
  footer.SetText = function(self, t) footerFull = t; rawFooterSet(self, t); UI.FitFooter() end

  ahBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  ahBtn:SetSize(150, 22); ahBtn:SetPoint("BOTTOMRIGHT", -14, 8)
  ahBtn:SetText("Send to AH list")
  ahBtn:SetScript("OnClick", function()
    if not lastPlan then return end
    if Core.CanExportToAuctionator() then Core.ExportToAuctionator(lastPlan)
    elseif ns.BuyPanel then
      ns.BuyPanel.Open(Core.ShoppingToBuy(lastPlan), "Buy: " .. Data.professions[lastPlan.line].name .. " shopping list")
    end
  end)
  ahBtn:Hide()
  scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  scanBtn:SetSize(120, 22); scanBtn:SetPoint("BOTTOMRIGHT", -14, 8)
  scanBtn:SetText("Scan AH")
  scanBtn:SetScript("OnClick", function() if ns.Prices and ns.Prices.Scan() then UI.UpdateButtons() end end)
  scanBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Scan the auction house")
    GameTooltip:AddLine("Reads the lowest price of everything listed, in one search. SkillRoute uses the freshest price it has for each item.", 1, 1, 1, true)
    local b = ns.Prices and ns.Prices.Book()
    if b and b.t then GameTooltip:AddLine(("Last scan: %s, %d items."):format(date("%b %d %H:%M", b.t), b.count or 0), 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
  end)
  scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  scanBtn:Hide()
  if ns.Prices then
    ns.Prices.OnStatus(function(text)
      UI.UpdateButtons()
      if text then if footer then footer:SetText("|cff33ccff" .. text .. "|r") end
      else UI.Refresh() end -- finished or stopped: back to the route's own footer
    end)
  end
  frame:Hide() -- new frames start shown; the first open must show it (and refresh via OnShow)
end

-- autoOpened: the window was opened by opening a profession window, so it closes
-- with it. Opened by hand (/sr, Route button) it stays until you close it.
-- (autoOpened is declared near the top: the window's OnHide resets it)

-- once per account: how to use the window, in chat
local function firstRunTips()
  SkillRouteDB = SkillRouteDB or {}
  if SkillRouteDB.tipsShown then return end
  SkillRouteDB.tipsShown = true
  local t = "|cff33ccffSkillRoute:|r "
  print(t .. "the route lists each step top to bottom. |cffffd100Hover|r a step for details, |cffffd100click|r to open the recipe or set a waypoint, |cffffd100right-click|r to skip a recipe you can't get.")
  print(t .. "|cffffd100Shopping list|r (top right) is what to buy, minus what you have. Prices come from SkillRoute's own scan (Scan AH button at the auction house) or your AH addon's: scan first.")
  print(t .. "|cffffd100Options|r for margins and settings; |cffffd100/sr help|r for commands, |cffffd100/sr check|r if something looks wrong.")
end

function UI.Toggle(line)
  firstRunTips()
  if not frame then build() end
  if line then state.line = line end
  if frame:IsShown() and not line then
    frame:Hide()
  else
    autoOpened = false
    if frame:IsShown() then UI.Refresh() else frame:Show() end -- OnShow refreshes
  end
end

function UI.AutoOpen(line)
  firstRunTips()
  -- an open full window follows the profession too (e.g. opened with Full route, then
  -- you switch from Enchanting to Tailoring)
  if frame and frame:IsShown() and line and line ~= state.line then
    state.line = line
    UI.Refresh()
  end
  -- the mini panel docked to the profession window, unless switched off in the options
  if ns.Mini and (SkillRouteDB.settings or {}).mini ~= false and ns.Mini.Show(line) then return end
  if not frame then build() end
  state.line = line
  if frame:IsShown() then
    UI.Refresh() -- already open: just follow the profession
  else
    autoOpened = true
    frame:Show()
  end
end

-- Step aside while the options window is open, then come back as it was, still
-- closing with the profession window if it opened with it.
local steppedAside, wasAuto = false, false
function UI.StepAside()
  if frame and frame:IsShown() then
    steppedAside, wasAuto = true, autoOpened
    frame:Hide() -- (its OnHide clears autoOpened)
  end
end
function UI.ComeBack()
  if steppedAside and frame then
    steppedAside = false
    frame:Show()
    autoOpened = wasAuto
  end
end

function UI.AutoClose()
  if steppedAside and wasAuto then steppedAside = false end -- closed with the profession: don't come back
  if autoOpened and frame and frame:IsShown() then frame:Hide() end
  autoOpened = false
end

-- "Route" button on whichever profession window this client uses.
local attached = {}
function UI.AttachButton()
  local parent = ProfessionsFrame or TradeSkillFrame
  if not parent or attached[parent] then return end
  attached[parent] = true
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(70, 20)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -2)
  b:SetFrameStrata("HIGH")
  b:SetText("Route")
  b:SetScript("OnClick", function()
    local line
    local T = C_TradeSkillUI
    local infoT = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    if infoT and infoT.professionID and Data.professions[infoT.professionID] then line = infoT.professionID end
    UI.Toggle(line)
  end)
end

SLASH_SKILLROUTE1, SLASH_SKILLROUTE2 = "/sr", "/skillroute"
SlashCmdList.SKILLROUTE = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local settings = SkillRouteDB and SkillRouteDB.settings
  if cmd == "log" then
    if ns.Recorder then ns.Recorder.Command(arg) end
  elseif cmd == "scanlog" then
    if ns.Prices then for _, l in ipairs(ns.Prices.ScanLogLines()) do print("|cff33ccffSkillRoute scan:|r " .. l) end end
  elseif cmd == "bank" then
    if ns.Helpers then ns.Helpers.BankDebug() end
  elseif cmd == "scan" then
    if ns.Prices then ns.Prices.Scan() end
  elseif cmd == "overtime" and settings then
    local v = tonumber(arg)
    if v and v >= 0 and v <= 100 then
      Core.Bonus(); Core.Char().bonus = v / 100
      Core.InvalidatePatterns(); Core.Changed()
      local o = Core.OvertimeInfo()
      if o.rank then
        print(("SkillRoute: your Legacy Tree says Working Overtime rank %d (+%d%%); that's used. %d%% is kept for when it can't be read."):format(o.rank, o.rank * o.per * 100, v))
      else
        print(("SkillRoute: Working Overtime set to %d%% for this character (your Legacy Tree couldn't be read)."):format(v))
      end
    else
      print("SkillRoute: /sr overtime <0-100>  (your Working Overtime talent %, 0 if you don't have it)")
    end
  elseif cmd == "estimate" and settings then
    settings.estimate = (arg == "on")
    Core.InvalidatePatterns()
    print("SkillRoute: price estimates for items with no AH price are " .. (settings.estimate and "ON (marked in orange)" or "OFF (those recipes are skipped)"))
  elseif cmd == "craftcost" and settings then
    local v = tonumber(arg)
    if v and v >= 0 then
      settings.craftValue = math.floor(v)
      print(("SkillRoute: each craft now counts as %s of your time when choosing recipes (not added to the total)."):format(money(settings.craftValue)))
    else
      print("SkillRoute: /sr craftcost <copper>  (prefer fewer crafts: extra material cost accepted per craft saved; 0 = cheapest)")
    end
  elseif cmd == "resale" and settings then
    local v = tonumber(arg)
    if v and v >= 0 and v <= 100 then
      settings.resale = v
      print(v == 0 and "SkillRoute: crafted items are not counted as sold."
        or ("SkillRoute: crafted items count as sold on the AH for %d%% of their price (minus the 5%% cut)."):format(v))
    else
      print("SkillRoute: /sr resale <0-100>  (0 = off; e.g. 50 to count half the AH price - selling many lowers it)")
    end
  elseif cmd == "alts" and settings then
    settings.alts = (arg ~= "off")
    print("SkillRoute: materials on your other characters are " .. (settings.alts and "counted" or "not counted"))
  elseif cmd == "margin" and settings then
    local v = tonumber(arg)
    if v and v >= 50 and v <= 99 then
      settings.margin = v
      print(("SkillRoute: shopping list covers the route %d times in 100%s."):format(v,
        v == 50 and " (just the expected amount)" or ""))
    else
      print(("SkillRoute: /sr margin <50-99>  (now %d: buy enough to finish the route that many times in 100)"):format(settings.margin or 90))
    end
  elseif cmd == "crowded" and settings then
    local v = tonumber(arg)
    if v and v >= 30 and v <= 100 then
      settings.crowded = v
      Core.InvalidatePatterns()
      print(("SkillRoute: a crowded AH listing counts as %d%% of its price%s."):format(v, v == 100 and " (crowding ignored)" or ""))
    else
      print(("SkillRoute: /sr crowded <30-100>  (now %d: how much of the AH price counts when 20+ are already listed)")
        :format(math.floor(Core.CrowdedShare() * 100 + 0.5)))
    end
  elseif cmd == "ah" then
    if lastPlan then Core.ExportToAuctionator(lastPlan) else print("SkillRoute: open the window first (/sr).") end
    return
  elseif cmd == "options" or cmd == "config" then
    if ns.Options then ns.Options.Toggle() end
    return
  elseif cmd == "minimap" and settings then
    settings.minimapHide = (arg == "off")
    if ns.Options then ns.Options.UpdateMinimap() end
    print("SkillRoute: minimap button " .. (settings.minimapHide and "hidden" or "shown"))
    return
  elseif cmd == "check" then
    Core.Check()
    return
  elseif cmd == "unskip" then
    Core.ClearSkips()
    print("SkillRoute: all skipped recipes are back in the plan.")
  elseif cmd == "cdmats" and settings then
    settings.cdmats = (arg == "on")
    print("SkillRoute: recipes using cooldown-only materials (Mooncloth, Arcanite Bar) are "
          .. (settings.cdmats and "INCLUDED" or "LEFT OUT"))
  elseif cmd == "auto" and settings then
    settings.auto = (arg ~= "off")
    print("SkillRoute: open with the profession window is " .. (settings.auto and "ON" or "OFF"))
    return
  elseif cmd == "help" then
    print("SkillRoute: /sr - open/close   /sr options   /sr minimap on|off   /sr check   /sr auto on|off   /sr overtime <pct>   /sr estimate on|off   /sr cdmats on|off   /sr margin <50-99>   /sr craftcost <copper>   /sr alts on|off   /sr resale <pct>   /sr crowded <pct>   /sr ah   /sr scan   /sr log on|off|skip|boat   /sr unskip   (right-click a step to skip it)")
    return
  else
    UI.Toggle()
    return
  end
  Core.Changed()
end
