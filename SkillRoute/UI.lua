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

local function mats(spell, line)
  local r = Data.professions[line].recipes[spell]
  local parts = {}
  for i = 1, #r.r, 2 do parts[#parts + 1] = r.r[i + 1] .. " " .. itemName(r.r[i]) end
  return table.concat(parts, ", ")
end

-- Frame ----------------------------------------------------------------------------
local frame, scroll, content, info, footer, targetBox, profText, modeBtn, hRange
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
    for _, l in ipairs(self.tip) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function setRow(i, opts)
  local r = row(i)
  r.icon:SetTexture(opts.icon or icon(opts.item, opts.spell))
  r.text:SetText(opts.text or "")
  r.sub:SetText(opts.sub or "")
  r.right:SetText(opts.right or "")
  r.range:SetText(opts.range or "")
  r.item, r.spell, r.tip, r.tipTitle = opts.item, opts.spell, opts.tip, opts.tipTitle or opts.title
  r:Show()
end

local function lines()
  local c = charState()
  local mine = {}
  for line in pairs(Core.Skills()) do mine[#mine + 1] = line end
  table.sort(mine, function(a, b) return Data.professions[a].name < Data.professions[b].name end)
  return mine, c
end

local function routeRows(plan)
  local n = 0
  local function add(o) n = n + 1; setRow(n, o) end
  local trained = plan.max
  local toolShown = {}
  for _, st in ipairs(plan.steps) do
    -- rank training needed before this step?
    while RANKS[trained] and st.from >= trained do
      add({ icon = "Interface\\Icons\\INV_Misc_Book_09",
            text = ("|cffffd100Train %s at your trainer|r"):format(RANKS[trained]),
            sub = ("Needed to go past %d"):format(trained), range = tostring(trained) })
      trained = trained + 75
    end
    -- get each tool (rod, hammer...) right before the first step that needs it
    for _, u in ipairs(st.tools or {}) do
      if not toolShown[u] then
        toolShown[u] = true
        local learn = ""
        if u.learnHow == "trainer" then
          learn = "  |cffffd100Learn at trainer" .. (u.learnCost and (" (" .. money(u.learnCost, YELLOW) .. ")") or "") .. "|r"
        elseif u.learnHow == "trainer?" then
          learn = "  |cffffd100Learn at trainer (not confirmed yet)|r"
        end
        if u.craftSpell then
          add({ item = u.item, spell = u.craftSpell,
                text = ("|cffff8040Craft 1 x %s|r (tool)"):format(itemName(u.item)),
                sub = mats(u.craftSpell, plan.line) .. learn,
                range = ("%d+"):format(math.max(u.from, st.from)), right = money(u.price),
                tip = { ("A tool: needed from %d on. Craft it once and keep it in your bags (not the bank)."):format(st.from) } })
        else
          add({ item = u.item,
                text = ("|cffff8040Buy 1 x %s|r (tool)"):format(itemName(u.item)),
                sub = (Data.items[u.item] and Data.items[u.item][3]) and "From a trade supplies vendor" or "From the auction house",
                right = money(u.price),
                tip = { ("A tool: needed from %d on. Keep it in your bags (not the bank)."):format(st.from) } })
        end
      end
    end
    if st.gap then
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
                        .. (pt.where and ("  -  " .. pt.where) or "")
                        .. (pt.repFaction and ("  -  |cffff8040needs %s with %s|r"):format(
                              RANK_NAMES[pt.repRank] or "?", Data.factions[pt.repFaction] or "?") or "")
                        .. (pt.price and "  -  AH" or "  -  not on the AH in your last scan"),
                  right = pt.price and money(pt.price) or "" })
          end
        end
      end
    else
      local r = Data.professions[plan.line].recipes[st.spell]
      local learn = ""
      if st.learn == "trainer" then
        learn = "  |cffffd100Learn at trainer" .. (st.learnCost and (" (" .. money(st.learnCost, YELLOW) .. ")") or "") .. "|r"
      elseif st.learn == "pattern" then
        if st.unlock and st.unlock.via == "ah" then
          learn = "  |cffffd100Buy pattern on the AH (last seen " .. money(st.learnCost, YELLOW) .. ")|r"
        else
          learn = "  |cffffd100Buy pattern from a vendor (" .. money(st.learnCost, YELLOW) .. ")|r"
        end
      elseif st.learn == "trainer?" then
        learn = "  |cffffd100Learn at trainer (not confirmed yet)|r"
      end
      local tip = {
        ("Each craft: %s%s"):format(money(st.perCraft), st.est and " (estimated)" or ""),
        ("Skill-up chance falls from yellow %d to grey %d."):format(r.y, r.g),
      }
      if st.credited then
        tip[#tip + 1] = ("These crafts use about %s of materials. Later steps use the %s they make and include that cost, so it isn't counted twice.")
          :format(money(st.grossCost), itemName(r.out))
      elseif st.vendorBack > 0 then
        tip[#tip + 1] = ("Vendoring the results gives back about %s (not counted)."):format(money(st.vendorBack))
      end
      if st.learn == "pattern" then
        local sv = st.unlock and st.unlock.savesShown
        tip[#tip + 1] = sv and ("Buying the pattern saves about %s over the whole route, its price included."):format(money(sv))
                        or "No trainer recipe covers this range; this is the cheapest way through."
      end
      if r.where and st.learn == "pattern" then tip[#tip + 1] = "Where: " .. r.where end
      for _, u in ipairs(st.tools or {}) do
        tip[#tip + 1] = ("Needs a %s in your bags: %s."):format(u.name,
          u.craftSpell and "craft one first (on the shopping list)" or ("buy one for " .. money(u.price)))
      end
      if st.alt then
        tip[#tip + 1] = ("Next best here: %s, %s per point vs %s for this one.")
          :format(st.alt.name, money(st.alt.perPoint), money(st.alt.ours))
      end
      if st.learn == "trainer?" then
        tip[#tip + 1] = "|cffffd100Open your profession trainer once: SkillRoute will record what it really teaches and at which skill.|r"
      end
      if st.tools then
        local names = {}
        for _, u in ipairs(st.tools) do names[#names + 1] = u.name end
        learn = learn .. "  |cffff8040needs " .. table.concat(names, ", ") .. "|r"
      end
      add({ item = r.out, spell = st.spell, tip = tip,
            text = ("|cff%s~%d|r x %s"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts - 1e-9), st.name),
            sub = mats(st.spell, plan.line) .. learn,
            range = ("%d-%d"):format(st.from, st.to),
            right = st.credited and "|cff808080counted later|r" or money(st.cost) })
    end
  end
  return n
end

local function shoppingRows(plan)
  local n = 0
  local function add(o) n = n + 1; setRow(n, o) end
  for _, c in ipairs(plan.shopping.craft) do
    local r = Data.professions[plan.line].recipes[c.spell]
    add({ item = r.out, text = ("Craft %d x %s"):format(c.n, c.name),
          sub = c.tool and "|cffff8040Tool for later steps: keep it in your bags|r"
                or "Cheaper to make than to buy; uses the reagents below" })
  end
  for _, b in ipairs(plan.shopping.buy) do
    local tags = {}
    if b.pattern then tags[#tags + 1] = b.ah and "|cffffd100pattern, on the AH (last seen price)|r"
                                         or "|cffffd100pattern, from a vendor|r"
    elseif b.tool then tags[#tags + 1] = "|cffff8040tool: keep it in your bags|r" .. (b.vendor and ", vendor" or "")
    elseif b.vendor then tags[#tags + 1] = "vendor" end
    if b.est then tags[#tags + 1] = "|cffff8040estimated price|r" end
    add({ item = b.item,
          text = b.buy > 0 and ("Buy %d x %s"):format(b.buy, b.name) or ("|cff40bf40Have all %s|r"):format(b.name),
          sub = ("need %d, have %d%s"):format(b.need, b.have, #tags > 0 and ("  -  " .. table.concat(tags, ", ")) or ""),
          right = b.price and money(b.price * b.buy) or money(nil) })
  end
  return n
end

function UI.Refresh()
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

  local plan, err = Core.Plan(line, target)
  if not plan then
    info:SetText(err)
    return
  end
  local src = Core.PriceSource() and "Auctionator prices" or "|cffff4040Auctionator not found|r"
  local warn = {}
  if plan.unpriced > 0 then
    warn[#warn + 1] = ("|cffff8040%d recipes skipped: reagents with no price (scan the AH)|r"):format(plan.unpriced)
  end
  if plan.mismatch and plan.mismatch > 0 then
    warn[#warn + 1] = ("|cffff4040%d recipe colours differ from the data: update SkillRoute|r"):format(plan.mismatch)
  end
  info:SetText(("Skill %d/%d  ->  %d   -   %s%s"):format(plan.skill, plan.max, plan.target, src,
    #warn > 0 and ("\n" .. table.concat(warn, "\n")) or ""))

  local n = state.mode == "route" and routeRows(plan) or shoppingRows(plan)
  for i = n + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, n * ROW_H + ROWS_PAD))
  modeBtn:SetText(state.mode == "route" and "Shopping list" or "Route")
  if state.mode == "route" then hRange:Show() else hRange:Hide() end
  footer:SetText(("Buy for |cffffffff%s|r%s   |cff808080planned in %s|r"):format(money(plan.total, "ffffff"),
    plan.estimated and " |cffff8040(includes estimates)|r" or "",
    plan.ms and ("%.1f ms"):format(plan.ms) or "?"))
end

function UI.IsShown() return frame and frame:IsShown() end

local function build()
  frame = CreateFrame("Frame", "SkillRouteFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(600, 560)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
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
  modeBtn:SetScript("OnClick", function()
    state.mode = state.mode == "route" and "shopping" or "route"
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    UI.Refresh()
  end)

  info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 14, -60); info:SetPoint("RIGHT", -14, 0); info:SetJustifyH("LEFT")

  scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -112)
  -- column headings, aligned with the row columns (scroll area ends 32px from the edge)
  hRange = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hRange:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(32 + RANGE_X), -98)
  hRange:SetWidth(RANGE_W); hRange:SetJustifyH("LEFT"); hRange:SetText("Skill")
  hRange:SetTextColor(RANGE_COLOR[1], RANGE_COLOR[2], RANGE_COLOR[3])
  local hCost = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hCost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(32 + EDGE), -98)
  hCost:SetWidth(COST_W); hCost:SetJustifyH("RIGHT"); hCost:SetText("Cost")
  scroll:SetPoint("BOTTOMRIGHT", -32, 34)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(550, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  footer:SetPoint("BOTTOMLEFT", 14, 12); footer:SetPoint("RIGHT", -14, 0); footer:SetJustifyH("LEFT")
end

-- autoOpened: the window was opened by opening a profession window, so it closes
-- with it. Opened by hand (/sr, Route button) it stays until you close it.
local autoOpened = false

function UI.Toggle(line)
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
  if not frame then build() end
  state.line = line
  if frame:IsShown() then
    UI.Refresh() -- already open: just follow the profession
  else
    autoOpened = true
    frame:Show()
  end
end

function UI.AutoClose()
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
  if cmd == "overtime" and settings then
    local v = tonumber(arg)
    if v and v >= 0 and v <= 100 then
      settings.bonus = v / 100
      print(("SkillRoute: Working Overtime bonus set to %d%%"):format(v))
    else
      print("SkillRoute: /sr overtime <0-100>  (your Working Overtime talent %, 0 if you don't have it)")
    end
  elseif cmd == "estimate" and settings then
    settings.estimate = (arg == "on")
    Core.InvalidatePatterns()
    print("SkillRoute: price estimates for items with no AH price are " .. (settings.estimate and "ON (marked in orange)" or "OFF (those recipes are skipped)"))
  elseif cmd == "cdmats" and settings then
    settings.cdmats = (arg == "on")
    print("SkillRoute: recipes using cooldown-only materials (Mooncloth, Arcanite Bar) are "
          .. (settings.cdmats and "INCLUDED" or "LEFT OUT"))
  elseif cmd == "auto" and settings then
    settings.auto = (arg ~= "off")
    print("SkillRoute: open with the profession window is " .. (settings.auto and "ON" or "OFF"))
    return
  elseif cmd == "help" then
    print("SkillRoute: /sr - open/close   /sr auto on|off   /sr overtime <pct>   /sr estimate on|off   /sr cdmats on|off")
    return
  else
    UI.Toggle()
    return
  end
  Core.Changed()
end
