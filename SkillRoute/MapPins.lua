-- Map pins: where the nodes of your gathering routes' current steps can spawn, on the world
-- map and the minimap (NodeSpots.lua), plus spots you've gathered at that the data doesn't
-- have ("your finds", SkillRouteDB.finds, shared by your characters).
--
-- Which nodes: for Mining and Herbalism (each one you have), the current step's node, its
-- alternatives ("or Poor Copper Vein") and its "when you see them" rare nodes.
local _, ns = ...
local Core, Data = ns.Core, SkillRouteData
local P = {}
ns.MapPins = P

local LINES = { 186, 182 }                     -- Mining, Herbalism: the lines with node spots
local GATHER_SPELLS = { 2575, 2366 }           -- Mining, Herb Gathering (names, localised)
local GRACE_YARDS = 10 -- a find closer than this to a known spot is that spot: a couple of
                       -- yards, plus your reach (you gather from ~5 yd) and the data's rounding
local MAX_FINDS = 2000
-- minimap diameter in yards at each zoom level (0-5), outdoors and indoors
local MINI_OUT = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local MINI_IN = { [0] = 300, 240, 180, 120, 80, 50 }

local function S() SkillRouteDB.settings = SkillRouteDB.settings or {}; return SkillRouteDB.settings end
function P.MapOn() return S().mapPins ~= false end
function P.MiniOn() return S().miniPins ~= false end
function P.RecordOn() return S().recordFinds ~= false end
function P.KindOn(kind) if kind == "herb" then return S().mapHerbs ~= false end return S().mapOres ~= false end
function P.Alpha() return 1 - (S().pinTransparency or 25) / 100 end

-- Spots ---------------------------------------------------------------------------------
local decoded = {}
-- the data's spots of a node on a zone map: { x1, y1, x2, y2, ... } in 0-1
function P.Spots(name, map)
  local key = name .. "@" .. map
  local d = decoded[key]
  if d then return d end
  d = {}
  local packed = ns.NodeSpots and ns.NodeSpots.spots[name] and ns.NodeSpots.spots[name][map]
  if packed then
    for i = 1, #packed, 6 do
      d[#d + 1] = tonumber(packed:sub(i, i + 2)) / 1000
      d[#d + 1] = tonumber(packed:sub(i + 3, i + 5)) / 1000
    end
  end
  decoded[key] = d
  return d
end

local function finds()
  SkillRouteDB.finds = SkillRouteDB.finds or {}
  return SkillRouteDB.finds
end
-- your finds of a node on a zone map: { x1, y1, ... } in 0-1 (stored x 10000)
function P.Finds(name, map)
  local f = finds()[name]
  local list = f and f[map]
  if not list then return {} end
  local out = {}
  for i = 1, #list do out[i] = list[i] / 10000 end
  return out
end

function P.Canonical(name) return ns.NodeSpots and ns.NodeSpots.alias[name] or name end
function P.Kind(name)
  return (ns.NodeSpots and ns.NodeSpots.kind[name]) or (SkillRouteDB.findKind and SkillRouteDB.findKind[name])
end

-- a zone map's size in yards (the game's own map transform), or nil
local mapYards = {}
function P.MapYards(map)
  local c = mapYards[map]
  if c ~= nil then return c and c[1], c and c[2] end
  mapYards[map] = false
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
  local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 0))
  local ok3, _, d = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 1))
  if not (ok and ok2 and ok3 and a and b and d) then return end
  local ax, ay = a:GetXY()
  local bx, by = b:GetXY()
  local dx, dy = d:GetXY()
  local w = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
  local h = math.sqrt((dx - ax) ^ 2 + (dy - ay) ^ 2)
  if w > 0 and h > 0 then mapYards[map] = { w, h } end
  return w, h
end

-- Is there a spot of this node (the data's, or one of your finds) within the grace distance?
function P.Covered(name, map, x, y)
  local w, h = P.MapYards(map)
  w, h = w or 4000, h or 2667 -- no map transform: a typical zone's size
  local lim = GRACE_YARDS * GRACE_YARDS
  for _, list in ipairs({ P.Spots(name, map), P.Finds(name, map) }) do
    for i = 1, #list, 2 do
      local dx, dy = (list[i] - x) * w, (list[i + 1] - y) * h
      if dx * dx + dy * dy <= lim then return true end
    end
  end
  return false
end

-- Save a gather here if no known spot covers it. Returns true when it's a new spot.
function P.Record(name, map, x, y, kind)
  name = P.Canonical(name)
  if not (name and map and x and y) or P.Covered(name, map, x, y) then return false end
  local f = finds()
  f[name] = f[name] or {}
  local list = f[name][map] or {}
  f[name][map] = list
  list[#list + 1] = math.floor(x * 10000 + 0.5)
  list[#list + 1] = math.floor(y * 10000 + 0.5)
  SkillRouteDB.findCount = (SkillRouteDB.findCount or 0) + 1
  if kind and not P.Kind(name) then
    SkillRouteDB.findKind = SkillRouteDB.findKind or {}
    SkillRouteDB.findKind[name] = kind
  end
  if SkillRouteDB.findCount > MAX_FINDS then -- keep the newest: drop the oldest of this node
    table.remove(list, 1); table.remove(list, 1)
    SkillRouteDB.findCount = SkillRouteDB.findCount - 1
  end
  return true
end
function P.FindCount() return SkillRouteDB and SkillRouteDB.findCount or 0 end

-- Which nodes ---------------------------------------------------------------------------
-- { [node] = role } for the current steps of your Mining and Herbalism routes:
-- role "step", "alt" or "rare" ("when you see them"); cached until skills or the route change
-- (worked out again when your skills change - the events below - or the route does)
local wanted, wantedVer, pinsCache = nil, nil, {}
function P.Invalidate() wanted, pinsCache = nil, {} end
function P.Wanted()
  -- keyed on your Mining and Herbalism ranks too: right after login the game may not have
  -- reported your professions yet, and that first answer mustn't stick
  local skills = Core.Skills()
  local ver = Core.RouteVersion() .. ":" .. (skills[186] and skills[186].rank or "-") .. ":" .. (skills[182] and skills[182].rank or "-")
  if wanted and wantedVer == ver then return wanted end
  local c = Core.Char()
  wanted, wantedVer, pinsCache = {}, ver, {}
  for _, line in ipairs(LINES) do
    if skills[line] then
      local ok, plan = pcall(Core.Plan, line, (c.targets and c.targets[line]) or 300)
      for _, st in ipairs(ok and plan and plan.steps or {}) do
        if st.gather and st.name then
          wanted[st.name] = "step"
          for _, a in ipairs(st.alt or {}) do wanted[a] = wanted[a] or "alt" end
          for _, a in ipairs(st.also or {}) do wanted[a] = wanted[a] or "rare" end
          break
        end
      end
    end
  end
  return wanted
end

-- the zone map you're in (an outdoor zone) and your spot on it, or nil
function P.PlayerZone()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetPlayerMapPosition) then return end
  local m = C_Map.GetBestMapForUnit("player")
  for _ = 1, 6 do
    local info = m and C_Map.GetMapInfo(m)
    if not info then return end
    if info.mapType == 3 then
      local pos = C_Map.GetPlayerMapPosition(m, "player")
      if not pos then return end
      local x, y = pos:GetXY()
      return m, x, y
    end
    m = info.parentMapID
  end
end

-- every pin for a zone map: { {x, y, name, role, find}, ... } (kept until the nodes or
-- your finds change: the minimap reads it a few times a second)
local SAME_SPOT_YARDS = 15 -- spots of one kind (ore, herb) this close are one spot: the data has
                           -- some twice, and herbs share spawn points (the other names go in p[6])
local ROLE_ORDER = { step = 1, alt = 2, rare = 3 }
function P.PinsFor(map)
  local w = P.Wanted()
  local c = pinsCache[map]
  if c and c.finds == P.FindCount() then return c.list end
  local all = {}
  for name, role in pairs(w) do
    if P.KindOn(P.Kind(name) or "ore") then -- Veins/Deposits and Herbs can each be turned off in Options
      local s = P.Spots(name, map)
      for i = 1, #s, 2 do all[#all + 1] = { s[i], s[i + 1], name, role } end
      local f = P.Finds(name, map)
      for i = 1, #f, 2 do all[#all + 1] = { f[i], f[i + 1], name, role, true } end
    end
  end
  -- the step's node stands for a merged spot before an alternative or a rare one
  table.sort(all, function(a, b)
    local ra, rb = ROLE_ORDER[a[4]] or 9, ROLE_ORDER[b[4]] or 9
    if ra ~= rb then return ra < rb end
    if (a[5] and 1 or 0) ~= (b[5] and 1 or 0) then return not a[5] end
    if a[3] ~= b[3] then return a[3] < b[3] end
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
  end)
  local yw, yh = P.MapYards(map)
  yw, yh = yw or 4000, yh or 2667
  local cell, grid, out = SAME_SPOT_YARDS, {}, {}
  for _, p in ipairs(all) do
    local kind = P.Kind(p[3]) or "ore"
    local gx, gy = math.floor(p[1] * yw / cell), math.floor(p[2] * yh / cell)
    local near
    for dx = -1, 1 do
      for dy = -1, 1 do
        for _, q in ipairs(grid[(gx + dx) .. ":" .. (gy + dy)] or {}) do
          if not near and q.kind == kind and ((q[1] - p[1]) * yw) ^ 2 + ((q[2] - p[2]) * yh) ^ 2 <= cell * cell then near = q end
        end
      end
    end
    if near then
      if near[3] ~= p[3] then
        near[6] = near[6] or {}
        local dup = false
        for _, a in ipairs(near[6]) do if a == p[3] then dup = true end end
        if not dup then near[6][#near[6] + 1] = p[3] end
      end
    else
      p.kind = kind
      out[#out + 1] = p
      local key = gx .. ":" .. gy
      grid[key] = grid[key] or {}
      table.insert(grid[key], p)
    end
  end
  pinsCache[map] = { finds = P.FindCount(), list = out }
  return out
end

-- Pins ----------------------------------------------------------------------------------
local ROLE_TEXT = { step = "this step's node", alt = "counts the same as this step's node", rare = "rare: gather it when you see it" }
local function pinTip(self)
  local p = self.pin
  if not p then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(p[3])
  GameTooltip:AddLine("SkillRoute", 0.2, 0.8, 1)
  GameTooltip:AddLine(ROLE_TEXT[p[4]] or "", 1, 0.82, 0)
  GameTooltip:AddLine(p[5] and "A spot you found: not in the map data" or "A spot where it can spawn; it may not be up now",
    1, 1, 1, true)
  if self.also and #self.also > 0 then -- spots merged into this square on the minimap
    GameTooltip:AddLine("Also here: " .. table.concat(self.also, ", "), 1, 0.82, 0, true)
  end
  GameTooltip:Show()
end
-- Minimap: a hollow square, so the game's own tracking blip (drawn under anything an addon
-- puts on the minimap) shows through the middle. Copper for ores, green for herbs, gold for finds.
local RING = { ore = { 0.95, 0.55, 0.2 }, herb = { 0.35, 0.9, 0.3 }, find = { 1, 0.82, 0 } }
local function newMiniPin(parent)
  local f = CreateFrame("Button", nil, parent)
  f.edges = {}
  for i = 1, 4 do
    local t = f:CreateTexture(nil, "OVERLAY")
    if i == 1 then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(2)
    elseif i == 2 then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(2)
    elseif i == 3 then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(2)
    else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(2) end
    f.edges[i] = t
  end
  f:SetScript("OnEnter", pinTip)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end -- clicks go to the minimap
  return f
end
local function styledMini(f, p, size, alpha)
  f.pin = p
  f:SetSize(size, size)
  local c = p[5] and RING.find or RING[P.Kind(p[3]) or "ore"]
  for _, t in ipairs(f.edges) do
    if t.SetColorTexture then t:SetColorTexture(c[1], c[2], c[3], 1) else t:SetTexture(c[1], c[2], c[3], 1) end
  end
  f:SetAlpha(alpha)
  f:Show()
end

-- World map: the map's own pins (a data provider, as for its quest icons): the map places each
-- one by its map coordinates, layers and scales it. The same hollow squares as the minimap.
-- The pin template (MapPins.xml) names this mixin, so it has to be global.
local TEMPLATE = "SkillRouteMapPinTemplate"
local provider
local function makeMixin() -- once the map's own pin mixin exists (the map can load after us)
  if SkillRouteMapPinMixin or not (MapCanvasPinMixin and CreateFromMixins) then return end
  SkillRouteMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
  function SkillRouteMapPinMixin:OnLoad()
    pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end -- about the same size at any zoom
    self.edges = { self.top, self.bottom, self.left, self.right }
  end
  function SkillRouteMapPinMixin:OnAcquired(p, alpha)
    self.pin, self.also = p, p[6]
    local c = p[5] and RING.find or RING[P.Kind(p[3]) or "ore"]
    for _, t in ipairs(self.edges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    self:SetAlpha(alpha)
    if self.SetMouseClickEnabled then pcall(self.SetMouseClickEnabled, self, false) end -- clicks go to the map
    self:SetPosition(p[1], p[2])
  end
  function SkillRouteMapPinMixin:OnMouseEnter() pinTip(self) end
  function SkillRouteMapPinMixin:OnMouseLeave() GameTooltip:Hide() end
end
local function useProvider()
  makeMixin()
  local W = WorldMapFrame
  if provider then return provider end
  local missing = not W and "WorldMapFrame" or not W.AddDataProvider and "AddDataProvider"
    or not MapCanvasDataProviderMixin and "MapCanvasDataProviderMixin" or not MapCanvasPinMixin and "MapCanvasPinMixin"
    or not CreateFromMixins and "CreateFromMixins" or nil
  if missing then P.providerMissing = missing; return nil end
  local pr = CreateFromMixins(MapCanvasDataProviderMixin)
  function pr:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(TEMPLATE) end
  function pr:RefreshAllData()
    self:RemoveAllData()
    local m = self:GetMap()
    local map = m:GetMapID()
    if not (P.MapOn() and map) then return end
    local alpha = P.Alpha()
    local ok, pins = pcall(P.PinsFor, map)
    if not ok then
      P.lastWorld = { map = map, n = 0, mode = "the map's own pins", err = tostring(pins) }
      Core.ReportError("world map spots", pins)
      return
    end
    -- one spot that fails mustn't stop the rest: count them, keep the first error for /sr check
    local drawn, firstErr = 0, nil
    for _, p in ipairs(pins) do
      local okPin, err = pcall(m.AcquirePin, m, TEMPLATE, p, alpha)
      if okPin then drawn = drawn + 1 elseif not firstErr then firstErr = tostring(err) end
    end
    P.lastWorld = { map = map, n = drawn, of = #pins, mode = "the map's own pins", err = firstErr }
    if firstErr then Core.ReportError("world map spots", firstErr) end
  end
  local ok, err = pcall(W.AddDataProvider, W, pr)
  if ok then provider, P.providerMissing = pr, nil else P.providerMissing = "AddDataProvider failed: " .. tostring(err) end
  return provider
end
P.UseProvider = useProvider

-- Without the map's pin system: our own squares laid over its canvas
local worldOverlay, worldPool = nil, {}
function P.RefreshWorld()
  local W = WorldMapFrame
  if provider and W then
    if W:IsShown() then provider:RefreshAllData() end
    local map = W.GetMapID and W:GetMapID()
    return map and P.MapOn() and #P.PinsFor(map) or 0
  end
  local canvas = W and W.ScrollContainer and W.ScrollContainer.Child
  if not canvas then return 0 end
  if not worldOverlay then
    worldOverlay = CreateFrame("Frame", nil, canvas)
    worldOverlay:SetAllPoints(canvas)
    if worldOverlay.SetFrameLevel and canvas.GetFrameLevel then worldOverlay:SetFrameLevel((canvas:GetFrameLevel() or 0) + 20) end
    -- the map can size its canvas after showing: place the squares again by its new size
    worldOverlay:SetScript("OnSizeChanged", function() P.RefreshWorld() end)
  end
  for _, f in ipairs(worldPool) do f:Hide() end
  local map = W.GetMapID and W:GetMapID()
  if not (P.MapOn() and map and W:IsShown()) then return 0 end
  local pins = P.PinsFor(map)
  local w, h = canvas:GetSize()
  local scale = (W.ScrollContainer.GetCanvasScale and W.ScrollContainer:GetCanvasScale()) or 1
  local size, alpha = 12 / math.max(scale, 0.1), P.Alpha()
  for i, p in ipairs(pins) do
    local f = worldPool[i] or newMiniPin(worldOverlay)
    worldPool[i] = f
    styledMini(f, p, size, alpha)
    f.also = p[6]
    f:ClearAllPoints()
    f:SetPoint("CENTER", worldOverlay, "TOPLEFT", p[1] * w, -p[2] * h)
  end
  P.lastWorld = { map = map, n = #pins, mode = ("own layer, canvas %dx%d"):format(w or 0, h or 0) }
  return #pins
end

-- Minimap: the pins within its range, a few times a second while there are any
local miniPool, ticker = {}, nil
function P.MinimapOffset(dxYd, dyYd, radiusYd, radiusPx, facing)
  -- dx east, dy south (map directions) -> pixels from the minimap's centre (x right, y up)
  local x, y = dxYd, -dyYd
  if facing then -- a rotating minimap: you always face up
    local c, s = math.cos(facing), math.sin(facing)
    x, y = x * c + y * s, -x * s + y * c
  end
  if x * x + y * y > radiusYd * radiusYd then return nil end
  return x / radiusYd * radiusPx, y / radiusYd * radiusPx
end
function P.RefreshMinimap()
  for _, f in ipairs(miniPool) do f:Hide() end
  if not (P.MiniOn() and Minimap and Minimap.IsShown and Minimap:IsShown()) or not next(P.Wanted()) then return 0 end
  local map, px, py = P.PlayerZone()
  if not map then return 0 end
  local w, h = P.MapYards(map)
  if not w then return 0 end
  local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
  local indoors = IsIndoors and IsIndoors()
  local radiusYd = ((indoors and MINI_IN or MINI_OUT)[zoom] or 466.67) / 2
  local radiusPx = (Minimap:GetWidth() or 140) / 2
  local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
  local facing = rotate and GetPlayerFacing and GetPlayerFacing() or nil
  local n, alpha = 0, P.Alpha()
  local MERGE = 8 -- px (squares are 14): spots of the same kind closer than this share one square
  for _, p in ipairs(P.PinsFor(map)) do
    local ox, oy = P.MinimapOffset((p[1] - px) * w, (p[2] - py) * h, radiusYd, radiusPx, facing)
    if ox then
      local kind, near = P.Kind(p[3]) or "ore", nil
      for i = 1, n do
        local g = miniPool[i]
        if g.kind == kind and (g.ox - ox) ^ 2 + (g.oy - oy) ^ 2 < MERGE * MERGE then near = g; break end
      end
      if near then
        if near.pin[3] ~= p[3] then
          local dup = false
          for _, a in ipairs(near.also) do if a == p[3] then dup = true end end
          if not dup then near.also[#near.also + 1] = p[3] end
        end
      else
        n = n + 1
        local f = miniPool[n] or newMiniPin(Minimap)
        miniPool[n] = f
        f.kind, f.ox, f.oy, f.also = kind, ox, oy, {}
        for _, a in ipairs(p[6] or {}) do f.also[#f.also + 1] = a end
        styledMini(f, p, 14, alpha)
        f:ClearAllPoints()
        f:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
      end
    end
  end
  return n
end

function P.Refresh()
  P.Invalidate()
  P.RefreshWorld()
  P.RefreshMinimap()
end

-- Finds: a gather where no spot is known ------------------------------------------------
local gatherName, pending = nil, {}
local function isGather(spell)
  if not gatherName then
    gatherName = {}
    for i, s in ipairs(GATHER_SPELLS) do
      local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s)) or (GetSpellInfo and GetSpellInfo(s))
      if n then gatherName[n] = i == 1 and "ore" or "herb" end
    end
  end
  local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or (GetSpellInfo and GetSpellInfo(spell))
  return n and gatherName[n]
end
function P.OnEvent(ev, a1, a2, a3, a4)
  if ev == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    local kind = isGather(a4)
    if kind and a2 and a2 ~= "" then pending[a3] = { name = a2, kind = kind } end
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    local p = pending[a2]
    pending = {}
    if p and P.RecordOn() then
      local map, x, y = P.PlayerZone()
      if map and P.Record(p.name, map, x, y, p.kind) then
        P.RefreshMinimap()
        if P.MapOn() then P.RefreshWorld() end
      end
    end
  elseif ev == "UNIT_SPELLCAST_FAILED" or ev == "UNIT_SPELLCAST_INTERRUPTED" then
    if a1 == "player" then pending[a2] = nil end
  elseif ev == "SKILL_LINES_CHANGED" or ev == "CHAT_MSG_SKILL" or ev == "ZONE_CHANGED_NEW_AREA" then
    P.Invalidate()
    P.RefreshMinimap()
  end
end

do
  local f = CreateFrame("Frame")
  for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
                        "UNIT_SPELLCAST_INTERRUPTED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "ZONE_CHANGED_NEW_AREA",
                        "PLAYER_LOGIN", "ADDON_LOADED" }) do
    pcall(f.RegisterEvent, f, ev)
  end
  f:SetScript("OnEvent", function(_, ev, ...)
    if ev == "ADDON_LOADED" then -- the game's world map, loaded after us: its pins
      if ... == "Blizzard_WorldMap" and not provider then pcall(useProvider) end
      return
    end
    if ev == "PLAYER_LOGIN" then
      local W = WorldMapFrame
      if useProvider() then
        -- the map refreshes its providers itself (map changes, showing)
      elseif W and hooksecurefunc then
        pcall(hooksecurefunc, W, "OnMapChanged", function() P.RefreshWorld() end)
        pcall(hooksecurefunc, W, "OnCanvasScaleChanged", function() P.RefreshWorld() end)
        if W.HookScript then W:HookScript("OnShow", function() P.RefreshWorld() end) end
      end
      if C_Timer and C_Timer.NewTicker and not ticker then
        ticker = C_Timer.NewTicker(0.2, function()
          local ok, err = pcall(P.RefreshMinimap)
          if not ok then Core.ReportError("minimap pins", err); P.RefreshMinimap = function() return 0 end end
        end)
      end
      return
    end
    local ok, err = pcall(P.OnEvent, ev, ...)
    if not ok then Core.ReportError("map pins", err) end
  end)
end
