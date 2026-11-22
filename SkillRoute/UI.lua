-- Window: route and shopping list. /sr or /skillroute, or the "Route" button on the
-- profession window.
local addonName, ns = ...
local UI = {}
ns.UI = UI

local Data, Core = SkillRouteData, ns.Core
local ROW_H, ROWS_PAD = 36, 4
local RANKS = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local COLORS = { orange = "ff8040", yellow = "ffff00", green = "40bf40", grey = "808080" }

local function money(c)
  if not c then return "|cff808080no price|r" end
  c = math.floor(c + 0.5)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  return (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. cp .. "c"
end

local function icon(item)
  local tex = item and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item))
                        or (GetItemIcon and GetItemIcon(item)))
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
local frame, scroll, content, info, footer, targetBox, profText, modeBtn
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
  r.text:SetPoint("RIGHT", r, "RIGHT", -110, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.sub:SetJustifyH("LEFT")
  r.sub:SetWordWrap(false)
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.right:SetPoint("TOPRIGHT", -6, -3)
  r.right:SetJustifyH("RIGHT")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  r:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) else GameTooltip:SetText(self.tipTitle or "") end
    for _, l in ipairs(self.tip) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function setRow(i, opts)
  local r = row(i)
  r.icon:SetTexture(opts.icon or icon(opts.item))
  r.text:SetText(opts.text or "")
  r.sub:SetText(opts.sub or "")
  r.right:SetText(opts.right or "")
  r.item, r.tip, r.tipTitle = opts.item, opts.tip, opts.tipTitle
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
  for _, st in ipairs(plan.steps) do
    -- rank training needed before this step?
    while RANKS[trained] and st.from >= trained do
      add({ icon = "Interface\\Icons\\INV_Misc_Book_09",
            text = ("|cffffd100Train %s at your trainer|r"):format(RANKS[trained]),
            sub = ("Needed to go past %d"):format(trained), right = tostring(trained) })
      trained = trained + 75
    end
    if st.gap then
      add({ icon = "Interface\\Icons\\INV_Scroll_03",
            text = ("|cffff4040No usable recipe for %d-%d|r"):format(st.from, st.to),
            sub = plan.unpriced > 0 and "Scan the AH (some recipes had no prices), or get a pattern:"
                  or "Needs a pattern. Cheapest that cover this range:",
            right = st.from .. "-" .. st.to })
      for _, g in ipairs(plan.gaps) do
        if g.from == st.from then
          for k = 1, math.min(5, #g.patterns) do
            local pt = g.patterns[k]
            add({ item = pt.item, text = "   " .. pt.name,
                  sub = "   Good until " .. pt.to .. (pt.from and ("  -  " .. pt.from) or "")
                        .. (pt.rep and "  -  |cffff8040needs faction reputation|r" or "")
                        .. (pt.price and "  -  AH" or "  -  not on the AH in your last scan"),
                  right = pt.price and money(pt.price) or "" })
          end
        end
      end
    else
      local r = Data.professions[plan.line].recipes[st.spell]
      local learn = ""
      if st.learn == "trainer" then
        learn = "  |cffffd100Learn at trainer" .. (st.learnCost and (" (" .. money(st.learnCost) .. ")") or "") .. "|r"
      elseif st.learn == "pattern" then
        learn = "  |cffffd100Buy pattern from a vendor (" .. money(st.learnCost) .. ")|r"
      elseif st.learn == "trainer?" then
        learn = "  |cffffd100Learn at trainer (not confirmed yet)|r"
      end
      local tip = {
        ("Each craft: %s%s"):format(money(st.perCraft), st.est and " (estimated)" or ""),
        ("Skill-up chance falls from yellow %d to grey %d."):format(r.y, r.g),
      }
      if st.credited then
        tip[#tip + 1] = ("Makes %s used later in this route, so its cost is counted there."):format(itemName(r.out))
      elseif st.vendorBack > 0 then
        tip[#tip + 1] = ("Vendoring the results gives back about %s (not counted)."):format(money(st.vendorBack))
      end
      if st.alt then
        tip[#tip + 1] = ("Next best here: %s, %s per point vs %s for this one.")
          :format(st.alt.name, money(st.alt.perPoint), money(st.alt.ours))
      end
      if st.learn == "trainer?" then
        tip[#tip + 1] = "|cffffd100Open your profession trainer once: SkillRoute will record what it really teaches and at which skill.|r"
      end
      add({ item = r.out, tip = tip,
            text = ("|cff%s~%d|r x %s"):format(COLORS[st.color] or "ffffff", math.ceil(st.crafts - 1e-9), st.name),
            sub = mats(st.spell, plan.line) .. learn,
            right = ("%d-%d  %s"):format(st.from, st.to, money(st.cost)) })
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
          sub = "Cheaper to make than to buy; uses the reagents below" })
  end
  for _, b in ipairs(plan.shopping.buy) do
    local tags = {}
    if b.vendor then tags[#tags + 1] = "vendor" end
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
  footer:SetText(("Buy for %s%s   |cff808080planned in %s|r"):format(money(plan.total),
    plan.estimated and " |cffff8040(includes estimates)|r" or "",
    plan.ms and ("%.1f ms"):format(plan.ms) or "?"))
end

function UI.IsShown() return frame and frame:IsShown() end

local function build()
  frame = CreateFrame("Frame", "SkillRouteFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 560)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetScript("OnShow", UI.Refresh)
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
  scroll:SetPoint("TOPLEFT", 10, -98)
  scroll:SetPoint("BOTTOMRIGHT", -32, 34)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(510, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  footer:SetPoint("BOTTOMLEFT", 14, 12); footer:SetPoint("RIGHT", -14, 0); footer:SetJustifyH("LEFT")
end

function UI.Toggle(line)
  if not frame then build() end
  if line then state.line = line end
  if frame:IsShown() and not line then frame:Hide() else frame:Show(); UI.Refresh() end
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
    print("SkillRoute: price estimates for items with no AH price are " .. (settings.estimate and "ON (marked in orange)" or "OFF (those recipes are skipped)"))
  elseif cmd == "help" then
    print("SkillRoute: /sr - open/close   /sr overtime <pct>   /sr estimate on|off")
    return
  else
    UI.Toggle()
    return
  end
  Core.Changed()
end
