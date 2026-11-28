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
local ICON = { ore = "Interface\\Icons\\Spell_Nature_Earthquake", herb = "Interface\\Icons\\INV_Misc_Flower_02" }
-- minimap diameter in yards at each zoom level (0-5), outdoors and indoors
local MINI_OUT = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local MINI_IN = { [0] = 300, 240, 180, 120, 80, 50 }

local function S() SkillRouteDB.settings = SkillRouteDB.settings or {}; return SkillRouteDB.settings end
function P.MapOn() return S().mapPins ~= false end
function P.MiniOn() return S().miniPins ~= false end
function P.RecordOn() return S().recordFinds ~= false end
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
  if wanted and wantedVer == Core.RouteVersion() then return wanted end
  local skills, c = Core.Skills(), Core.Char()
  wanted, wantedVer, pinsCache = {}, Core.RouteVersion(), {}
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
function P.PinsFor(map)
  local w = P.Wanted()
  local c = pinsCache[map]
  if c and c.finds == P.FindCount() then return c.list end
  local out = {}
  for name, role in pairs(w) do
    local s = P.Spots(name, map)
    for i = 1, #s, 2 do out[#out + 1] = { s[i], s[i + 1], name, role } end
    local f = P.Finds(name, map)
    for i = 1, #f, 2 do out[#out + 1] = { f[i], f[i + 1], name, role, true } end
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
  GameTooltip:Show()
end
local function newPin(parent)
  local f = CreateFrame("Button", nil, parent)
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetAllPoints()
  if f.tex.SetTexCoord then f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  f:SetScript("OnEnter", pinTip)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end -- clicks go to the map
  return f
end
local function styled(f, p, size, alpha)
  f.pin = p
  f:SetSize(size, size)
  f.tex:SetTexture(ICON[P.Kind(p[3]) or "ore"])
  if p[5] then f.tex:SetVertexColor(1, 0.85, 0.5) else f.tex:SetVertexColor(1, 1, 1) end
  f:SetAlpha(alpha)
  f:Show()
end

-- World map: pins on the map canvas, sized against its zoom
local worldOverlay, worldPool = nil, {}
function P.RefreshWorld()
  local W = WorldMapFrame
  local canvas = W and W.ScrollContainer and W.ScrollContainer.Child
  if not canvas then return 0 end
  if not worldOverlay then
    worldOverlay = CreateFrame("Frame", nil, canvas)
    worldOverlay:SetAllPoints(canvas)
    if worldOverlay.SetFrameLevel and canvas.GetFrameLevel then worldOverlay:SetFrameLevel((canvas:GetFrameLevel() or 0) + 20) end
  end
  for _, f in ipairs(worldPool) do f:Hide() end
  local map = W.GetMapID and W:GetMapID()
  if not (P.MapOn() and map and W:IsShown()) then return 0 end
  local pins = P.PinsFor(map)
  local w, h = canvas:GetSize()
  local scale = (W.ScrollContainer.GetCanvasScale and W.ScrollContainer:GetCanvasScale()) or 1
  local size, alpha = 14 / math.max(scale, 0.1), P.Alpha()
  for i, p in ipairs(pins) do
    local f = worldPool[i] or newPin(worldOverlay)
    worldPool[i] = f
    styled(f, p, size, alpha)
    f:ClearAllPoints()
    f:SetPoint("CENTER", worldOverlay, "TOPLEFT", p[1] * w, -p[2] * h)
  end
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
  for _, p in ipairs(P.PinsFor(map)) do
    local ox, oy = P.MinimapOffset((p[1] - px) * w, (p[2] - py) * h, radiusYd, radiusPx, facing)
    if ox then
      n = n + 1
      local f = miniPool[n] or newPin(Minimap)
      miniPool[n] = f
      styled(f, p, 12, alpha)
      f:ClearAllPoints()
      f:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
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
                        "PLAYER_LOGIN" }) do
    pcall(f.RegisterEvent, f, ev)
  end
  f:SetScript("OnEvent", function(_, ev, ...)
    if ev == "PLAYER_LOGIN" then
      local W = WorldMapFrame
      if W and hooksecurefunc then
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
