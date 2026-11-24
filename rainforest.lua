-- rainforest
-- a rainforest, alive
--
-- E1 the hour
-- E2 choose   E3 set
-- K2 weather: living / still
-- K3 lightning
--
-- rain, wind, thunder, birds,
-- monkeys, jaguar, woodpecker,
-- cicadas, insects, frogs,
-- stream, waterfall, drips,
-- variety, space

engine.name = "Rainforest"

local SCENE = include("lib/scene")
local SPR = include("lib/sprites")
local DATA = _path.data .. "rainforest/"

-- ---------------------------------------------------------------- the sounds

-- the layers, slots 1..12 in the engine
local LAYERS = { "rain1", "rain2", "rain3", "day", "night", "frogs", "stream", "wind", "chorus", "waterfall", "cicadas" }
local THUNDER_SLOT, HOWLER_SLOT, WOOD_SLOT, MONKEY_SLOT, JAGUAR_SLOT, FIRST_CALL = 13, 17, 19, 27, 31, 40
local WOOD_LEN = { 1.39, 2.38, 1.82, 0.67, 0.74, 0.8, 0.83, 0.66 }
-- the smaller monkeys: two spider monkey calls, then two tamarins'
local MONKEY_FILES = { "spider_1", "spider_2", "tamarin_1", "tamarin_2" }
local JAGUAR_FILES = 4

-- the birds, in the order variety brings them in. kind: perch, nest (the
-- oropendolas, at their hanging nests), fly (crossing the sky), ground (the
-- tinamou, walking the bank) or hover (the hummingbird, at the flowers).
-- When each sings: at dawn, by day, at dusk, at night.
local SPECIES = {
  { name = "piha", prefix = "piha", files = 6, kind = "perch", bout = 3, dawn = 1.0, day = 1.0, dusk = 0.6, night = 0 },
  { name = "toucan", prefix = "toucan", files = 5, kind = "perch", bout = 2, dawn = 0.8, day = 0.8, dusk = 0.7, night = 0 },
  { name = "potoo", prefix = "potoo", files = 4, kind = "perch", bout = 3, dawn = 0.15, day = 0, dusk = 0.4, night = 1.2 },
  { name = "oropendola", prefix = "oropendola", files = 6, kind = "nest", bout = 2, dawn = 1.3, day = 0.6, dusk = 0.4, night = 0 },
  { name = "macaw", prefix = "macaw", files = 9, kind = "fly", bout = 2, dawn = 1.0, day = 0.7, dusk = 0.9, night = 0 },
  { name = "owl", prefix = "owl", files = 4, kind = "perch", bout = 3, dawn = 0.1, day = 0, dusk = 0.5, night = 1.0 },
  { name = "tinamou", prefix = "tinamou", files = 4, kind = "ground", bout = 3, dawn = 0.9, day = 0.2, dusk = 1.3, night = 0.1 },
  { name = "screamer", prefix = "scream", files = 6, kind = "perch", bout = 2, dawn = 0.9, day = 0.8, dusk = 0.8, night = 0 },
  { name = "parrot", prefix = "parrot", files = 3, kind = "fly", bout = 1, flock = 3, dawn = 1.0, day = 0.6, dusk = 1.0, night = 0 },
  { name = "hummingbird", prefix = "humm", files = 4, kind = "hover", bout = 2, dawn = 0.5, day = 1.0, dusk = 0.3, night = 0 },
  { name = "crested", prefix = "exotic", files = 6, kind = "perch", bout = 2, dawn = 0.7, day = 1.0, dusk = 0.5, night = 0 },
}
local FROG_FILES = 14
local frog_slot0 = 0

-- the settings E2 runs along (and the grid's columns), each with what it does:
-- the animals' are how often they come, the ambiences' how loud or how full
local PARAMS = {
  { id = "rain", label = "RAIN", hint = "HOW HEAVY" },
  { id = "wind", label = "WIND", hint = "HOW STRONG" },
  { id = "thunder", label = "THUNDER", hint = "HOW STORMY" },
  { id = "birds", label = "BIRDS", hint = "HOW OFTEN" },
  { id = "monkeys", label = "MONKEYS", hint = "HOW OFTEN" },
  { id = "jaguar", label = "JAGUAR", hint = "HOW OFTEN" },
  { id = "woodpecker", label = "WOODPECKER", hint = "HOW OFTEN" },
  { id = "cicadas", label = "CICADAS", hint = "HOW LOUD" },
  { id = "insects", label = "INSECTS", hint = "HOW LOUD" },
  { id = "frogs", label = "FROGS", hint = "HOW MANY" },
  { id = "stream", label = "STREAM", hint = "HOW FULL" },
  { id = "waterfall", label = "WATERFALL", hint = "HOW FULL" },
  { id = "drips", label = "DRIPS", hint = "AFTER RAIN" },
  { id = "variety", label = "VARIETY", hint = "HOW MANY KINDS" },
  { id = "space", label = "SPACE", hint = "REVERB" },
}

-- ---------------------------------------------------------------- state

local t_now, last_t = 0, 0
local hour = 6.5
local living = true
local weather = { rain = 0, target = 0, next_change = 0, wet = 0, storm = 0 }
local birds, frogs_seen, monkeys, peckers, flutters = {}, {}, {}, {}, {}
local drops, ripples, drips, flies, bats = {}, {}, {}, {}, {}
local jaguar = nil
local flash = { t = -10, bolt = nil, near = 0 }
local thunders = {}
local hud, hud_until = nil, 0
local sel = 1
local IMG = {}
local stars = {}
local redraw_metro, sound_metro = nil, nil
local g = grid.connect()

local function P(id) return params:get(id) end

local function smooth(u)
  u = util.clamp(u, 0, 1)
  return u * u * (3 - 2 * u)
end

local function bump(h, c, w) return math.max(0, 1 - ((h - c) / w) ^ 2) end

-- 0 at night, 1 by day, with dawn and dusk between
local function dayness(h) return smooth(math.min((h - 5) / 2, (19.5 - h) / 2)) end
-- the choruses: strongest at first light, again before dark
local function dawnness(h) return math.max(bump(h, 6.2, 1.3), 0.75 * bump(h, 18.0, 1.1)) end

-- ---------------------------------------------------------------- the weather and the forest's answer

local function rain_now() return living and weather.rain or P("rain") end

local function update_weather(dt)
  local base = P("rain")
  if living then
    -- showers come and go around the setting: a new target every one to four minutes
    if t_now >= weather.next_change then
      local r = math.random()
      if r < 0.35 then weather.target = base * 0.25
      elseif r < 0.75 then weather.target = base
      elseif r < 0.92 then weather.target = math.min(1, base + 0.35)
      else weather.target = math.min(1, base + 0.6) end
      weather.next_change = t_now + 60 + math.random() * 180
    end
    weather.rain = weather.rain + (weather.target - weather.rain) * math.min(1, dt / 25)
  else
    weather.rain = base
  end
  local r = rain_now()
  -- wet: what the rain leaves behind, rising with it, drying over minutes
  weather.wet = math.max(r, weather.wet - dt / 240)
  weather.storm = util.clamp((r - 0.55) / 0.4, 0, 1)
end

local function levels()
  local r, h = rain_now(), hour
  local day, dawn = dayness(h), dawnness(h)
  local function tri(x, a, b, c)
    if x <= a or x >= c then return 0 end
    return x < b and (x - a) / (b - a) or (c - x) / (c - b)
  end
  local rv = r ^ 0.7
  local L = {}
  L[1] = rv * (tri(r, 0, 0.22, 0.55) + (r < 0.22 and r > 0 and 0.4 or 0))
  L[2] = rv * tri(r, 0.25, 0.55, 0.88)
  L[3] = rv * smooth((r - 0.55) / 0.4)
  L[4] = P("insects") * day * (1 - 0.6 * r) * 0.7
  L[5] = P("insects") * (1 - day) * (1 - 0.4 * r) * 0.9
  L[6] = P("frogs") * (0.25 + 0.75 * (1 - day)) * (0.45 + 0.8 * weather.wet) * 0.8
  L[7] = P("stream") * (0.8 + 0.5 * weather.wet)
  L[8] = math.min(1, P("wind") * 0.8 + weather.storm * 0.4)
  L[9] = P("birds") * (0.15 + 0.85 * dawn) * day * (1 - 0.9 * r) * 0.8
  L[10] = P("waterfall") * (0.75 + 0.4 * weather.wet)
  -- cicadas: the heat of the day, in swells that come and go
  local swell = 0.55 + 0.45 * math.sin(t_now * 2 * math.pi / 23)
  L[11] = P("cicadas") * day ^ 1.5 * (1 - 0.75 * r) * swell
  return L
end

local last_levels = {}

local function send_levels()
  local L = levels()
  for i = 1, #LAYERS do
    local v = math.floor(L[i] * 100 + 0.5) / 100
    if v ~= last_levels[i] then
      engine.layer(i, v)
      last_levels[i] = v
    end
  end
  local r = rain_now()
  engine.drops(math.max(r * 0.8, weather.wet * P("drips")))
  engine.hiss(r)
  engine.wind(math.min(1, P("wind") + weather.storm * 0.5))
end

-- ---------------------------------------------------------------- voices, and what they look like

local function slot_of(sp, n) return sp.slot0 + n - 1 end

-- A bird that perches flies in, stays its time (singing when its calls
-- come), and flies off; one that crosses the sky just crosses it; the
-- tinamou walks in along the bank and back out; the hummingbird darts in to
-- a flower, hovers at it, and darts off.
local function new_bird(sp, dist, delay)
  local b = { sp = sp, dist = dist, t0 = t_now + (delay or 0), face = math.random() < 0.5 and -1 or 1, calls = {}, seed = math.random() * 10 }
  if sp.kind == "fly" then
    b.dir = math.random() < 0.5 and 1 or -1
    b.x0 = b.dir > 0 and -14 or 142
    b.y = 6 + math.random() * 14
    b.speed = (24 + math.random() * 14) * (1.2 - dist * 0.5)
    b.life = 170 / b.speed
  elseif sp.kind == "ground" then
    local bank = SCENE.bank
    b.dist, b.face = 0.25, -1
    b.x, b.y, b.from = bank[1] + math.random() * (bank[2] - bank[1]), bank[3], 136
    b.arrive, b.stay = (b.from - b.x) / 9, 6 + math.random() * 4
    b.life = b.arrive * 2 + b.stay
  elseif sp.kind == "hover" then
    local f = SCENE.flowers[math.random(#SCENE.flowers)]
    b.dist = 0.2
    -- beside the flower on the clearing's side, facing it, its bill at it
    b.face = f[1] < 64 and -1 or 1
    b.x, b.y = f[1] - b.face * 7, f[2] + 6
    b.from = b.face > 0 and -10 or 138
    b.arrive, b.stay = 0.6, 3 + math.random() * 3
    b.life = b.arrive + b.stay + 0.8
  else
    if sp.kind == "nest" then
      local n = SCENE.nests[math.random(#SCENE.nests)]
      b.x, b.y = n[1], n[2] + 3
    else
      local pool = {}
      for _, p in ipairs(SCENE.perches) do
        if (dist < 0.45 and p[3] == 1) or (dist >= 0.45 and p[3] == 2) then pool[#pool + 1] = p end
      end
      local p = pool[math.random(#pool)]
      b.x, b.y = p[1], p[2]
    end
    b.arrive, b.stay = 0.8, 6 + math.random() * 6
    b.life = b.arrive + b.stay + 1.2
    b.from = b.x < 64 and -12 or 140
    b.face = b.from < 0 and 1 or -1
  end
  return b
end

local function calling(b)
  for _, c in ipairs(b.calls) do
    if c.started and t_now - c.started < 1.3 then return true end
  end
  return false
end

-- where a bird is, and what it is doing, now
local function bird_state(b)
  local age = t_now - b.t0
  local kind = b.sp.kind
  if kind == "fly" then return b.x0 + b.dir * b.speed * math.max(0, age), b.y, "fly", b.dir end
  local leave = age - b.arrive - b.stay
  if kind == "ground" then
    if age < b.arrive then return b.from + (b.x - b.from) * (age / b.arrive), b.y, "walk", -1 end
    if leave > 0 then return b.x + leave * 9, b.y, "walk", 1 end
    return b.x, b.y, calling(b) and "call" or "stand", b.face
  end
  if kind == "hover" then
    if age < b.arrive then
      local u = smooth(age / b.arrive)
      return b.from + (b.x - b.from) * u, b.y - 10 * (1 - u), "hover", b.face
    end
    if leave > 0 then return b.x - b.face * leave * 90, b.y - leave * 40, "hover", -b.face end
    return b.x + math.sin(t_now * 7 + b.seed) * 0.8, b.y + math.sin(t_now * 5.3 + b.seed) * 0.7, "hover", b.face
  end
  if age < b.arrive then
    local u = smooth(age / b.arrive)
    return b.from + (b.x - b.from) * u, b.y - 12 * (1 - u) * (1 - u), "fly", b.face
  end
  if leave > 0 then
    return b.x - b.face * leave * 60, b.y - leave * 30, "fly", -b.face
  end
  return b.x, b.y, calling(b) and "sing" or "perch", b.face
end

-- a call: chosen by the hour from the species variety lets in, at a place,
-- heard from there, sometimes answered once or twice
local function bird_call(forced)
  local n = 3 + math.floor(P("variety") * (#SPECIES - 3) + 0.5)
  local h = hour
  local day = dayness(h)
  local weights, total = {}, 0
  for i = 1, n do
    local sp = SPECIES[i]
    local w = sp.day * day + sp.dawn * dawnness(h) + sp.dusk * bump(h, 18.5, 1.5) + sp.night * (1 - day)
    -- one tinamou, one hummingbird at a time
    if (sp.kind == "ground" or sp.kind == "hover") then
      for _, b in ipairs(birds) do
        if b.sp == sp then w = 0 end
      end
    end
    weights[i] = w
    total = total + w
  end
  if total <= 0 then return end
  local pick, acc = math.random() * total, 0
  local sp = SPECIES[1]
  for i = 1, n do
    acc = acc + weights[i]
    if pick <= acc then
      sp = SPECIES[i]
      break
    end
  end
  local dist = forced and 0.2 or (0.1 + math.random() * 0.85)
  local count = sp.flock or 1
  local lead
  for f = 1, count do
    local b = new_bird(sp, dist, (f - 1) * 0.35)
    if f > 1 and sp.kind == "fly" then
      b.x0, b.y, b.dir, b.speed, b.life = lead.x0 - lead.dir * 11 * (f - 1), lead.y + (f % 2) * 4, lead.dir, lead.speed, lead.life
    end
    lead = lead or b
    birds[#birds + 1] = b
  end
  -- the hummingbird is heard as it comes, the others once they are there
  local start = (sp.kind == "fly" or sp.kind == "hover") and 0.1 or (lead.arrive + 0.4)
  for k = 1, math.random(1, sp.bout) do
    lead.calls[#lead.calls + 1] = { t = t_now + start + (k - 1) * (1.2 + math.random() * 1.6), slot = slot_of(sp, math.random(sp.files)) }
  end
end

local function frog_call()
  local near = math.random() < 0.3
  frogs_seen[#frogs_seen + 1] = { t0 = t_now, near = near, life = 0.7 }
  local dist = near and 0.15 or (0.3 + math.random() * 0.6)
  local pan = near and 0.15 or (math.random() * 1.6 - 0.8)
  engine.shot(frog_slot0 + math.random(FROG_FILES) - 1, 0.55, pan, 2 ^ ((math.random() - 0.5) * 0.4), dist)
end

-- lightning now, thunder when its sound arrives
local function lightning(dist)
  dist = dist or (0.2 + math.random() * 0.8)
  flash.t, flash.near = t_now, 1 - dist
  local x = 15 + math.random() * 98
  local pts, y = { { x, -2 } }, -2
  while y < 30 + dist * 6 do
    y = y + 2 + math.random() * 4
    x = x + (math.random() - 0.5) * 9
    pts[#pts + 1] = { x, y }
  end
  local k = math.random(2, math.max(2, #pts - 1))
  local bx, by = pts[k][1], pts[k][2]
  local branch = { { bx, by } }
  for _ = 1, 3 do
    bx, by = bx + (math.random() - 0.3) * 8, by + 3 + math.random() * 3
    branch[#branch + 1] = { bx, by }
  end
  flash.bolt, flash.branch, flash.show = pts, branch, dist < 0.65
  thunders[#thunders + 1] = { t = t_now + 0.3 + dist * 5.5, dist = dist, pan = (pts[1][1] - 64) / 64 }
end

-- the monkeys. The howlers roar from a low branch by one of the trunks
local function howl()
  local where = SCENE.monkeys[math.random(#SCENE.monkeys)]
  monkeys[#monkeys + 1] = { kind = "howler", t0 = t_now, x = where[1], y = where[2], face = where[3], life = 7.5, calls = {} }
  engine.shot(HOWLER_SLOT + math.random(0, 1), 0.6, where[1] < 64 and -0.6 or 0.6, 1, 0.45 + math.random() * 0.35)
end

-- a spider monkey lets itself down under a branch, hangs by its tail, calls
local function spider_monkey()
  local where = SCENE.hangs[math.random(#SCENE.hangs)]
  local m = { kind = "spider", t0 = t_now, x = where[1], y = where[2], face = where[1] < 64 and 1 or -1, life = 9, calls = {} }
  for k = 1, math.random(1, 3) do
    m.calls[k] = { t = t_now + 1.4 + (k - 1) * (1.4 + math.random() * 1.4), slot = MONKEY_SLOT + math.random(0, 1) }
  end
  monkeys[#monkeys + 1] = m
end

-- tamarins, one to three, run out along a branch from the trunk, chatter,
-- and run back
local function tamarins()
  local run = SCENE.runs[math.random(#SCENE.runs)]
  for i = 1, math.random(1, 3) do
    local m = { kind = "tamarin", t0 = t_now + (i - 1) * 0.45, run = run, calls = {} }
    m.stop = math.max(2, #run - (i - 1) * 3 - math.random(0, 2))
    m.out = (m.stop - 1) / 7
    m.stay = 4 + math.random() * 3
    m.life = m.out * 2 + m.stay
    if i == 1 then
      for k = 1, math.random(1, 3) do
        m.calls[k] = { t = t_now + m.out + 0.3 + (k - 1) * (0.9 + math.random()), slot = MONKEY_SLOT + 2 + math.random(0, 1) }
      end
    end
    monkeys[#monkeys + 1] = m
  end
end

-- where a monkey is, which frame, which way it faces
local function monkey_state(m)
  local age = t_now - m.t0
  local function heard()
    for _, c in ipairs(m.calls) do
      if c.started and t_now - c.started < 1.0 then return true end
    end
    return false
  end
  if m.kind == "spider" then
    local y = m.y - 8 * math.max(0, 1 - age / 1.2) - 10 * math.max(0, (age - m.life + 1.2) / 1.2)
    return m.x, y, heard() and "spider_call" or "spider_hang", m.face
  elseif m.kind == "tamarin" then
    local run = m.run
    local out_dir = run[#run][1] > run[1][1] and 1 or -1
    local p, moving, face = 1, false, out_dir
    if age < 0 then return nil end
    if age < m.out then
      p, moving = 1 + (m.stop - 1) * age / m.out, true
    elseif age < m.out + m.stay then
      p = m.stop
    else
      p, moving, face = math.max(1, m.stop - (m.stop - 1) * (age - m.out - m.stay) / m.out), true, -out_dir
    end
    local i = math.floor(p)
    local f = p - i
    local a, b = run[i], run[math.min(#run, i + 1)]
    local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
    local frame = moving and (math.floor(t_now * 9) % 2 == 0 and "tamarin_runA" or "tamarin_runB") or (heard() and "tamarin_call" or "tamarin_sit")
    return x, y, frame, face
  end
  local howling = age > 0.8 and age < m.life - 1.2
  return m.x, m.y, howling and "monkey_howl" or "monkey_sit", m.face
end

-- the jaguar walks the near bank, stops, growls, and goes on
local function prowl()
  local dir = math.random() < 0.5 and 1 or -1
  local j = { t0 = t_now, dir = dir, x0 = dir > 0 and -16 or 144, speed = 11, wait = 4.5 }
  j.stop_x = 36 + math.random() * 56
  j.t_stop = math.abs(j.stop_x - j.x0) / j.speed
  j.growl_t = t_now + j.t_stop + 0.8
  j.life = j.t_stop + j.wait + (160 - math.abs(j.stop_x - j.x0)) / j.speed + 1
  jaguar = j
end

local function jaguar_state()
  local j = jaguar
  local age = t_now - j.t0
  if age < j.t_stop then return j.x0 + j.dir * j.speed * age, "walk" end
  if age < j.t_stop + j.wait then
    local since = t_now - j.growl_t
    return j.stop_x, (since >= 0 and since < 2.4) and "growl" or "stand"
  end
  return j.stop_x + j.dir * j.speed * (age - j.t_stop - j.wait), "walk"
end

-- a woodpecker on the side of a trunk, drumming
local function peck()
  local where = SCENE.peckers[math.random(#SCENE.peckers)]
  local n = math.random(#WOOD_LEN)
  local p = { t0 = t_now, x = where[1], y = where[2], face = where[3], drum = t_now + 0.6, len = WOOD_LEN[n], life = 3.2 + WOOD_LEN[n] }
  peckers[#peckers + 1] = p
  clock.run(function()
    clock.sleep(0.6)
    engine.shot(WOOD_SLOT + n - 1, 0.7, where[1] < 64 and -0.7 or 0.7, 0.95 + math.random() * 0.1, 0.35 + math.random() * 0.3)
  end)
end

local function schedule(dt)
  local r, h = rain_now(), hour
  local day = dayness(h)
  local quiet = 1 - 0.85 * smooth(r * 1.2)
  local variety = P("variety")
  -- birds: busiest at first light, quieter in the dark (the night's own
  -- birds then), quiet under a downpour
  local activity = 0.2 + 0.52 * day + 1.2 * dawnness(h)
  if math.random() < P("birds") * 0.75 * activity * quiet * dt then bird_call() end
  local frog_rate = P("frogs") * (0.15 + 0.9 * (1 - day)) * (0.3 + weather.wet) * 1.6
  if math.random() < frog_rate * dt then frog_call() end
  local storm = living and weather.storm or util.clamp(r * 1.5 - 0.3, 0, 1)
  if math.random() < P("thunder") * (0.01 + 0.14 * storm) * dt then lightning() end
  -- monkeys: the howlers at dawn and dusk; by day the spider monkeys and the
  -- tamarins, as variety lets them in
  if #monkeys == 0 then
    if math.random() < P("monkeys") * 0.025 * (0.3 + 2 * dawnness(h)) * (1 - r) * dt then
      howl()
    elseif variety >= 0.25 and math.random() < P("monkeys") * 0.03 * day * quiet * dt then
      if variety >= 0.5 and math.random() < 0.5 then tamarins() else spider_monkey() end
    end
  end
  if not jaguar and math.random() < P("jaguar") * 0.012 * (0.25 + 0.75 * (1 - day) + 0.5 * dawnness(h)) * (1 - 0.6 * r) * dt then
    prowl()
  end
  if #peckers == 0 and math.random() < P("woodpecker") * 0.06 * day * quiet * dt then peck() end
  -- what is due
  for _, b in ipairs(birds) do
    for _, c in ipairs(b.calls) do
      if not c.started and t_now >= c.t then
        c.started = t_now
        local x = bird_state(b)
        engine.shot(c.slot, 0.65, util.clamp((x - 64) / 64, -1, 1), 2 ^ ((math.random() - 0.5) / 6), b.dist)
      end
    end
  end
  for _, m in ipairs(monkeys) do
    for _, c in ipairs(m.calls) do
      if not c.started and t_now >= c.t then
        c.started = t_now
        local x = monkey_state(m) or 64
        engine.shot(c.slot, 0.6, util.clamp((x - 64) / 64, -1, 1), 2 ^ ((math.random() - 0.5) / 8), 0.35)
      end
    end
  end
  if jaguar and not jaguar.growled and t_now >= jaguar.growl_t then
    jaguar.growled = true
    engine.shot(JAGUAR_SLOT + math.random(0, JAGUAR_FILES - 1), 0.8, util.clamp((jaguar.stop_x - 64) / 64, -1, 1) * 0.8, 1, 0.25)
  end
  for i = #thunders, 1, -1 do
    local th = thunders[i]
    if t_now >= th.t then
      engine.shot(THUNDER_SLOT + math.random(0, 3), 0.95, th.pan * 0.8, 0.85 + math.random() * 0.25, th.dist)
      table.remove(thunders, i)
    end
  end
end

-- ---------------------------------------------------------------- drawing: letters

local FONT3 = {
  A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110",
  E = "111100110100111", F = "111100110100100", G = "011100101101011", H = "101101111101101",
  I = "111010010010111", K = "101101110101101", L = "100100100100111", M = "101111111101101",
  N = "110101101101101", O = "010101101101010", P = "110101110100100", R = "110101110101101",
  S = "011100010001110", T = "111010010010010", U = "101101101101111", V = "101101101101010",
  W = "101101111111101", Y = "101101010010010", ["0"] = "111101101101111", ["1"] = "010110010010111",
  ["2"] = "110001010100111", ["3"] = "110001010001110", ["4"] = "101101111001001", ["5"] = "111100110001110",
  ["6"] = "011100111101111", ["7"] = "111001010010010", ["8"] = "111101111101111", ["9"] = "111101111001110",
  [":"] = "000010000010000", ["%"] = "101001010100101", ["/"] = "001001010100100",
}

local function text3(s, x, y, level)
  screen.level(level)
  for i = 1, #s do
    local glyph = FONT3[s:sub(i, i)]
    if glyph then
      for k = 0, 14 do
        if glyph:sub(k + 1, k + 1) == "1" then screen.rect(x + (i - 1) * 4 + k % 3, y + math.floor(k / 3), 1, 1) end
      end
    end
  end
  screen.fill()
end

-- ---------------------------------------------------------------- drawing: the scene

local function light_index(h)
  if h < 4.4 or h >= 20.5 then return "night" end
  if h < 5.4 then return "predawn" end
  if h < 7 then return "dawn" end
  if h < 10 then return "morning" end
  if h < 14.5 then return "day" end
  if h < 17.2 then return "afternoon" end
  if h < 19 then return "dusk" end
  return "evening"
end

-- under a storm, the forest takes a darker light than the hour's
local DARKER = { day = "dusk", afternoon = "dusk", morning = "dawn", dawn = "predawn", dusk = "evening",
  evening = "night", predawn = "night", night = "night" }

local function img(name, x)
  local i = IMG[name]
  if i then screen.display_image(i, x or 0, 0) end
end

-- a sprite, standing on (x, y)
local function sprite(name, x, y)
  local f = SPR[name]
  if f and IMG.sprites then
    screen.display_image_region(IMG.sprites, f[1], f[2], f[3], f[4], math.floor(x - f[5] + 0.5), math.floor(y - f[6] + 0.5))
  end
end

local function sky_level(h)
  return math.floor(1 + 11 * dayness(h) + 3 * dawnness(h) * 0.5)
end

local function draw_sun_moon(h, r)
  screen.aa(1)
  if h > 5.6 and h < 18.6 then
    local t = (h - 6) / 12
    local x, y = 8 + t * 112, 36 - 28 * math.sin(math.pi * util.clamp(t, 0, 1))
    if r <= 0.3 then
      screen.level(math.floor(6 + 4 * dayness(h)))
      screen.circle(x, y, 5.5)
      screen.fill()
    end
    screen.level(r > 0.3 and math.floor(9 - r * 6) or 15)
    screen.circle(x, y, 3.5)
    screen.fill()
  elseif h < 5.6 or h > 19 then
    local t = ((h - 19) % 24) / 10.5
    local x, y = 10 + t * 108, 34 - 26 * math.sin(math.pi * util.clamp(t, 0, 1))
    if r < 0.4 then
      screen.level(3)
      screen.circle(x, y, 4.5)
      screen.fill()
      screen.level(12)
      screen.circle(x, y, 3)
      screen.fill()
      screen.level(1)
      screen.circle(x + 1.6, y - 0.8, 2.6)
      screen.fill()
    end
  end
  screen.aa(0)
end

local function draw_stars(h, r)
  local night = 1 - dayness(h)
  if night < 0.3 or r > 0.45 then return end
  for i, s in ipairs(stars) do
    local tw = math.sin(t_now * s[4] + i)
    if tw > -0.2 then
      screen.level(math.floor(util.clamp((3 + 6 * s[3]) * night * (0.6 + 0.4 * tw), 1, 12)))
      screen.rect(s[1], s[2], 1, 1)
      screen.fill()
    end
  end
end

-- the waterfall: water falling down its channel, white at the foot
local function draw_waterfall(h)
  local amt = P("waterfall")
  if amt < 0.03 then return end
  local w = SCENE.waterfall
  local x0, x1, top, foot = w[1], w[2], w[3], w[4]
  local bright = math.floor(4 + 9 * dayness(h) * 0.8 + 2)
  local speed = 40 + 30 * amt
  local width = math.max(1, math.floor((x1 - x0 + 1) * (0.4 + 0.6 * amt) + 0.5))
  local xs = math.floor((x0 + x1) / 2 - width / 2 + 0.5)
  for x = xs, xs + width - 1 do
    local off = (t_now * speed + x * 7.3) % 7
    for y = top, foot - 1 do
      local k = (y - off) % 7
      local lvl = k < 3 and bright or (k < 5 and bright - 3 or bright - 5)
      screen.level(util.clamp(lvl, 1, 15))
      screen.rect(x, y, 1, 1)
      screen.fill()
    end
  end
  -- foam and spray at the foot
  for k = 1, 3 + math.floor(amt * 6) do
    local fx = xs + math.random(-2, width + 1)
    local fy = foot - math.random(0, 2)
    screen.level(math.min(15, bright + 1))
    screen.rect(fx, fy, 1, 1)
    screen.fill()
  end
end

local function draw_water(h, r)
  local x0, x1, y0 = 26, 100, 57
  local base = math.floor(1 + 4 * dayness(h))
  screen.level(base)
  screen.rect(x0, y0, x1 - x0, 64 - y0)
  screen.fill()
  local sl = math.min(15, sky_level(h))
  local flow = P("stream") * (1 + weather.wet)
  for row = 0, 6 do
    local y = y0 + row
    for k = 1, 3 + row do
      local seed = (k * 37 + row * 91)
      local x = x0 + ((seed * 13 + math.floor(t_now * (6 + flow * 18) * (1 + row * 0.2))) % (x1 - x0))
      screen.level(math.max(base, sl - 3 - row))
      screen.rect(x, y, 2 + (seed % 5), 1)
      screen.fill()
    end
  end
  for i = #ripples, 1, -1 do
    local p = ripples[i]
    local age = t_now - p.t
    if age > 0.8 then
      table.remove(ripples, i)
    else
      local rr = 1 + age * 6
      screen.level(math.max(base, math.floor(sl - age * 12)))
      screen.rect(math.floor(p.x - rr), p.y, 1, 1)
      screen.rect(math.floor(p.x + rr), p.y, 1, 1)
      if age < 0.4 then screen.rect(math.floor(p.x - rr * 0.5), p.y + 1, math.max(1, math.floor(rr)), 1) end
      screen.fill()
    end
  end
end

local function draw_frog(h)
  -- on its pad at the water's edge, its throat swelling when it calls
  local x, y = 74, 59
  local calling = 0
  for _, f in ipairs(frogs_seen) do
    if f.near then
      local age = t_now - f.t0
      if age < f.life then calling = math.max(calling, math.sin(age / f.life * math.pi)) end
    end
  end
  local lvl = math.floor(2 + 3 * dayness(h))
  screen.aa(1)
  screen.level(lvl + 3)
  screen.move(x - 8, y + 1.5)
  screen.line(x + 8, y + 1.5)
  screen.line(x + 5, y + 3)
  screen.line(x - 5, y + 3)
  screen.close()
  screen.fill()
  screen.level(0)
  screen.circle(x, y - 0.2, 3.4)
  screen.fill()
  screen.level(lvl + 1)
  screen.circle(x, y, 2.8)
  screen.fill()
  screen.circle(x + 2.2, y - 1.6, 1.7)
  screen.fill()
  if calling > 0.05 then
    screen.level(math.min(15, lvl + 8))
    screen.circle(x + 2.6, y + 0.6, 0.8 + 2.0 * calling)
    screen.fill()
  end
  screen.aa(0)
  screen.level(math.min(15, lvl + 10))
  screen.rect(math.floor(x + 2), math.floor(y - 3), 1, 1)
  screen.fill()
end

local function song(x, y, face, near)
  local ph = (t_now * 2.2) % 1
  screen.aa(1)
  for k = 0, 1 do
    local u = (ph + k * 0.5) % 1
    local rr = 2 + u * (near and 9 or 5)
    local lvl = math.floor(14 * (1 - u))
    if lvl > 1 then
      screen.level(lvl)
      local a = face > 0 and 0 or math.pi
      screen.arc(x, y, rr, a - 0.7, a + 0.7)
      screen.stroke()
    end
  end
  screen.aa(0)
end

local function draw_bird(b)
  if t_now < b.t0 then return end
  local x, y, pose, face = bird_state(b)
  local suffix = face < 0 and "_l" or ""
  local kind = b.sp.kind
  if kind == "ground" then
    local frame = pose == "walk" and (math.floor(t_now * 6) % 2 == 0 and "walkA" or "walkB") or (pose == "call" and "call" or "walkB")
    sprite("tinamou_" .. frame .. suffix, x, y)
    if pose == "call" then song(x + face * 5, y - 8, face, true) end
    return
  end
  if kind == "hover" then
    sprite("hummingbird_" .. (math.floor(t_now * 20) % 2 == 0 and "hoverA" or "hoverB") .. suffix, x, y)
    return
  end
  local size = b.dist < 0.45 and "near" or "far"
  local frame = pose
  if pose == "fly" then frame = math.floor(t_now * 8 + b.t0 * 3) % 2 == 0 and "flyA" or "flyB" end
  local name = b.sp.name .. "_" .. size .. "_" .. frame .. suffix
  sprite(name, x, y)
  if pose == "sing" then
    local f = SPR[name]
    local hy = f and (y - f[6] + 2) or (y - 8)
    song(x + face * (size == "near" and 5 or 3), hy, face, size == "near")
  end
end

local function draw_monkey(m)
  local x, y, frame, face = monkey_state(m)
  if not x then return end
  sprite(frame .. (face < 0 and "_l" or ""), x, y)
  if frame == "monkey_howl" then
    local ph = (t_now * 1.1) % 1
    screen.aa(1)
    screen.level(math.floor(11 * (1 - ph)))
    local a = face > 0 and -0.5 or math.pi + 0.5
    screen.arc(x + face * 5, y - 11, 3 + ph * 12, a - 0.6, a + 0.6)
    screen.stroke()
    screen.aa(0)
  end
end

local function draw_jaguar()
  if not jaguar then return end
  local x, pose = jaguar_state()
  local frame = pose == "walk" and (math.floor(t_now * 4) % 2 == 0 and "walkA" or "walkB") or pose
  sprite("jaguar_" .. frame .. (jaguar.dir < 0 and "_l" or ""), x, 63)
end

local function draw_bats()
  for _, b in ipairs(bats) do
    sprite(math.floor(t_now * 10 + b.phase) % 2 == 0 and "bat_flapA" or "bat_flapB", b.x, b.y)
  end
end

local function draw_pecker(p)
  local drumming = t_now >= p.drum and t_now < p.drum + p.len
  local tap = drumming and math.floor(t_now * 14) % 2 == 0
  sprite("woodpecker_" .. (tap and "tap" or "rest") .. (p.face < 0 and "_l" or ""), p.x, p.y)
  if drumming then
    screen.level(9)
    screen.rect(p.x + p.face * (4 + math.random(0, 2)), p.y - 9 + math.random(0, 2), 1, 1)
    screen.fill()
  end
end

-- a palm frond from (x, y), at an angle, bending; swaying with the wind
local function frond(x, y, ang, len, bend, n, lvl, phase)
  local wind = math.min(1, P("wind") + weather.storm * 0.6)
  local sway = (0.05 + 0.25 * wind) * math.sin(t_now * (0.8 + wind * 1.6) + phase) + 0.08 * wind
  local a = ang + sway
  local px, py = x, y
  screen.level(lvl)
  for i = 1, n do
    local t = i / n
    a = a + bend / n
    local nx, ny = px + math.cos(a) * len / n, py + math.sin(a) * len / n
    screen.line_width(t < 0.5 and 2 or 1)
    screen.move(px, py)
    screen.line(nx, ny)
    screen.stroke()
    screen.line_width(1)
    -- leaflets on both sides, longest in the middle, drooping and swinging
    local ll = (1 - (2 * t - 1) ^ 2) * len * 0.34 + 1
    for side = -1, 1, 2 do
      local la = a + side * 1.15 + 0.35 + 0.08 * math.sin(t_now * 2 + i + phase) * wind
      local mx, my = nx + math.cos(la) * ll * 0.5, ny + math.sin(la) * ll * 0.5 + ll * 0.08
      screen.move(nx, ny)
      screen.curve(mx, my, mx, my, nx + math.cos(la) * ll, ny + math.sin(la) * ll + ll * 0.3)
      screen.stroke()
    end
    px, py = nx, ny
  end
end

-- the box at the top left: a setting's name and value, a bar, and what it does
local function draw_hud()
  if not hud or t_now > hud_until then return end
  local w = math.max(52, #hud.label * 4 + 30, hud.hint and (#hud.hint * 4 + 5) or 0)
  local h = (hud.bar and 11 or 7) + (hud.hint and 6 or 0)
  screen.level(0)
  screen.rect(1, 1, w, h)
  screen.fill()
  screen.level(4)
  screen.rect(1.5, 1.5, w - 1, h - 1)
  screen.stroke()
  text3(hud.label, 3, 2, 15)
  if hud.value then text3(hud.value, w - #hud.value * 4, 2, 9) end
  if hud.bar then
    screen.level(3)
    screen.rect(3, 9, w - 4, 1)
    screen.fill()
    screen.level(15)
    screen.rect(3, 9, math.floor((w - 4) * hud.bar + 0.5), 1)
    screen.fill()
  end
  if hud.hint then text3(hud.hint, 3, (hud.bar and 11 or 7), 7) end
end

local function show(label, value, bar, hint)
  hud, hud_until = { label = label, value = value, bar = bar, hint = hint }, t_now + 2.2
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)
  local h, r = hour, rain_now()
  local wind = math.min(1, P("wind") + weather.storm * 0.6)
  local light = light_index(h)
  if r > 0.7 then light = DARKER[light] end
  local since = t_now - flash.t
  local flashing = since < 0.35 and (since < 0.08 or (since > 0.16 and since < 0.24))
  -- the sky: lit by the flash, else by the hour, clouded by the rain
  if flashing then
    screen.level(math.floor(8 + 7 * flash.near))
    screen.rect(0, 0, 128, 64)
    screen.fill()
  else
    if r > 0.3 then
      img("cloud_" .. light)
    else
      img("sky_" .. light)
      draw_stars(h, r)
    end
    draw_sun_moon(h, r)
  end
  if flashing and flash.show and flash.bolt then
    screen.level(15)
    for _, path in ipairs({ flash.bolt, flash.branch }) do
      screen.move(path[1][1], path[1][2])
      for i = 2, #path do screen.line(path[i][1], path[i][2]) end
      screen.stroke()
    end
  end
  img("far_" .. light)
  if not flashing then draw_waterfall(h) end
  -- mist along the ridges: at dawn, after rain, by the waterfall
  local mist = util.clamp(dawnness(h) * 0.8 + weather.wet * 0.6 + P("waterfall") * 0.2, 0, 1)
  local M = IMG["mist_" .. light]
  if mist > 0.2 and M then
    local ox = math.floor(t_now * 2) % 128
    screen.display_image_region(M, ox, 0, 128, 16, 0, 25)
    if mist > 0.6 then screen.display_image_region(M, (ox + 64) % 128, 0, 128, 16, 0, 31) end
  end
  local sway = math.floor(math.sin(t_now * 0.9) * wind * 1.4 + 0.5)
  img("mid_" .. light, sway)
  -- shafts of sun through the canopy, on clear mornings and afternoons
  if ((h >= 7.5 and h <= 10.5) or (h >= 14.5 and h <= 17)) and r < 0.15 and not flashing then img("rays") end
  draw_bats()
  img("near_" .. light, math.floor(sway * 1.5))
  for _, m in ipairs(monkeys) do draw_monkey(m) end
  for _, p in ipairs(peckers) do draw_pecker(p) end
  for _, b in ipairs(birds) do draw_bird(b) end
  draw_water(h, r)
  draw_frog(h)
  draw_jaguar()
  -- drips from the leaves while they are wet
  screen.level(math.floor(4 + 6 * dayness(h)))
  for _, d in ipairs(drips) do screen.rect(math.floor(d.x), math.floor(d.y), 1, 1) end
  screen.fill()
  -- butterflies in the sun, fireflies in the dark
  for _, f in ipairs(flutters) do
    sprite(math.floor(t_now * 9 + f.phase) % 2 == 0 and "butterfly_open" or "butterfly_shut", f.x, f.y)
  end
  for _, f in ipairs(flies) do
    local blink = math.sin(t_now * f.rate + f.phase)
    if blink > 0.3 then
      screen.level(math.floor(6 + 9 * blink))
      screen.rect(math.floor(f.x), math.floor(f.y), 1, 1)
      screen.fill()
    end
  end
  -- the understory in front of everything, black against it: a clump of
  -- fronds at the lower left, one long frond arching in from the right, one
  -- hanging from above
  frond(-3, 67, -1.1, 34, 0.95, 11, 0, 0)
  frond(5, 67, -0.55, 22, 0.75, 7, 0, 1.3)
  frond(11, 68, -1.35, 15, 0.5, 5, 0, 2.6)
  frond(133, 58, -2.75, 30, -0.7, 9, 0, 2.1)
  frond(129, -4, 2.0, 19, 0.45, 6, 0, 4.0)
  -- rain, in front of all of it
  local slant = 0.15 + wind * 0.7
  for _, d in ipairs(drops) do
    screen.level(d.lvl)
    screen.move(d.x, d.y)
    screen.line(d.x - slant * d.len, d.y - d.len)
    screen.stroke()
  end
  draw_hud()
  screen.update()
end

-- ---------------------------------------------------------------- the particles

local function update_particles(dt)
  local r = rain_now()
  local wind = math.min(1, P("wind") + weather.storm * 0.6)
  local want = math.floor((r ^ 1.2) * 95)
  while #drops < want do
    local far = math.random() < 0.55
    drops[#drops + 1] = { x = math.random() * 150 - 10, y = math.random() * -64, far = far,
      len = far and (2 + r * 3) or (4 + r * 6), v = (far and 70 or 120) * (0.8 + r * 0.5),
      lvl = far and math.random(4, 7) or math.random(8, 12) }
  end
  local slant = 0.15 + wind * 0.7
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.y = d.y + d.v * dt
    d.x = d.x + d.v * dt * slant
    if d.y > (d.far and 50 or 60) then
      if #drops > want then
        table.remove(drops, i)
      else
        if d.x > 26 and d.x < 100 and math.random() < 0.5 then ripples[#ripples + 1] = { x = d.x, y = 57 + math.random(0, 5), t = t_now } end
        d.y = math.random() * -10
        d.x = math.random() * 150 - 10
      end
    end
  end
  -- drips: wet leaves let go of their water
  local wet = weather.wet * P("drips")
  if wet > 0.08 and math.random() < wet * 1.2 then
    local p = SCENE.drips[math.random(#SCENE.drips)]
    drips[#drips + 1] = { x = p[1], y = p[2], v = 0 }
  end
  for i = #drips, 1, -1 do
    local d = drips[i]
    d.v = d.v + 120 * dt
    d.y = d.y + d.v * dt
    if d.y > 62 then
      if d.x > 26 and d.x < 100 then ripples[#ripples + 1] = { x = d.x, y = 58, t = t_now } end
      table.remove(drips, i)
    end
  end
  -- fireflies: in the night, more with the insects, none in rain
  local night = 1 - dayness(hour)
  local want_f = math.floor(P("insects") * night * (1 - r) * 18)
  while #flies < want_f do
    flies[#flies + 1] = { x = 20 + math.random() * 88, y = 34 + math.random() * 20, rate = 1 + math.random() * 2.5,
      phase = math.random() * 6, vx = (math.random() - 0.5) * 3, vy = (math.random() - 0.5) * 2 }
  end
  while #flies > want_f do table.remove(flies) end
  for _, f in ipairs(flies) do
    f.x = f.x + f.vx * dt + math.sin(t_now * 0.7 + f.phase) * 0.05
    f.y = f.y + f.vy * dt + math.cos(t_now * 0.5 + f.phase) * 0.04
    if f.x < 16 or f.x > 112 then f.vx = -f.vx end
    if f.y < 30 or f.y > 56 then f.vy = -f.vy end
  end
  -- butterflies: in sunshine, more with variety
  local want_b = math.floor(dayness(hour) * (1 - smooth(r * 3)) * (1 + P("variety") * 3))
  while #flutters < want_b do
    flutters[#flutters + 1] = { x = 30 + math.random() * 70, y = 36 + math.random() * 16, phase = math.random() * 10,
      vx = (math.random() < 0.5 and -1 or 1) * (6 + math.random() * 6), seed = math.random() * 100 }
  end
  while #flutters > want_b do table.remove(flutters) end
  for _, f in ipairs(flutters) do
    f.x = f.x + f.vx * dt
    f.y = f.y + math.sin(t_now * 3 + f.seed) * 14 * dt
    if f.x < 22 or f.x > 106 then f.vx = -f.vx end
    f.y = util.clamp(f.y, 30, 56)
  end
  for i = #birds, 1, -1 do
    if t_now - birds[i].t0 > birds[i].life then table.remove(birds, i) end
  end
  for _, list in ipairs({ frogs_seen, monkeys, peckers }) do
    for i = #list, 1, -1 do
      if t_now - list[i].t0 > list[i].life then table.remove(list, i) end
    end
  end
  if jaguar and t_now - jaguar.t0 > jaguar.life then jaguar = nil end
  -- bats: out after dark, hunting the insects, none in rain
  local want_bats = night > 0.6 and math.floor(P("insects") * (1 - r) * 4 * night + 0.5) or 0
  while #bats < want_bats do
    bats[#bats + 1] = { x = math.random() * 128, y = 6 + math.random() * 20, vx = (math.random() < 0.5 and -1 or 1) * (18 + math.random() * 14),
      vy = 0, phase = math.random() * 10 }
  end
  while #bats > want_bats do table.remove(bats) end
  for _, b in ipairs(bats) do
    b.vy = util.clamp(b.vy + (math.random() - 0.5) * 120 * dt - (b.y - 16) * 0.8 * dt, -14, 14)
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    if b.x < -6 or b.x > 134 or math.random() < 0.5 * dt then b.vx = -b.vx end
  end
end

-- ---------------------------------------------------------------- time

local function advance_hour(dt)
  local mode = params:get("clock")
  if mode == 2 then
    local t = os.date("*t")
    hour = t.hour + t.min / 60 + t.sec / 3600
  elseif mode == 3 then
    hour = (hour + dt / 60) % 24 -- an hour a minute
  end
end

local function tick()
  local now = util.time()
  local dt = math.min(0.2, now - last_t)
  last_t = now
  t_now = t_now + dt
  advance_hour(dt)
  update_weather(dt)
  schedule(dt)
  update_particles(dt)
  redraw()
end

-- ---------------------------------------------------------------- controls

local function hhmm(h)
  local hh = math.floor(h)
  return string.format("%02d:%02d", hh, math.floor((h - hh) * 60))
end

local function show_param(i)
  local p = PARAMS[i]
  show(p.label, math.floor(P(p.id) * 100 + 0.5) .. "%", P(p.id), p.hint)
end

function enc(n, d)
  if n == 1 then
    if params:get("clock") == 2 then params:set("clock", 1) end
    hour = (hour + d * 0.25) % 24
    params:set("hour", hour)
    show("TIME", hhmm(hour))
  elseif n == 2 then
    sel = util.clamp(sel + d, 1, #PARAMS)
    show_param(sel)
  else
    local p = PARAMS[sel]
    params:set(p.id, util.clamp(P(p.id) + d * 0.02, 0, 1))
    show_param(sel)
  end
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then
    params:set("weather", living and 1 or 2)
    show(living and "LIVING WEATHER" or "STILL WEATHER")
  elseif n == 3 then
    lightning(0.15 + math.random() * 0.45)
  end
end

-- the grid, if there is one: a fader for each setting
local function grid_redraw()
  g:all(0)
  for i, p in ipairs(PARAMS) do
    local v = math.floor(P(p.id) * 8 + 0.5)
    for y = 1, 8 do g:led(i, 9 - y, y <= v and (i == sel and 13 or 8) or 1) end
  end
  g:refresh()
end

g.key = function(x, y, z)
  if z == 0 or x > #PARAMS then return end
  sel = x
  params:set(PARAMS[x].id, (8 - y) / 7)
  show_param(x)
end

-- ---------------------------------------------------------------- life

function init()
  math.randomseed(os.time())
  params:add_separator("rainforest", "rainforest")
  local function amount(id, name, default)
    params:add_control(id, name, controlspec.new(0, 1, "lin", 0.01, default))
  end
  amount("rain", "rain", 0.35)
  amount("wind", "wind", 0.3)
  amount("thunder", "thunder", 0.4)
  amount("birds", "birds", 0.6)
  amount("monkeys", "monkeys", 0.3)
  amount("jaguar", "jaguar", 0.3)
  amount("woodpecker", "woodpecker", 0.4)
  amount("cicadas", "cicadas", 0.4)
  amount("insects", "insects", 0.6)
  amount("frogs", "frogs", 0.5)
  amount("stream", "stream", 0.4)
  amount("waterfall", "waterfall", 0.4)
  amount("drips", "drips", 0.6)
  amount("variety", "variety", 0.7)
  amount("space", "space", 0.4)
  params:set_action("space", function(v) engine.space(v) end)
  params:add_control("canopy", "canopy", controlspec.new(0, 1, "lin", 0.01, 0))
  params:set_action("canopy", function(v) engine.canopy(v) end)
  params:add_control("level", "level", controlspec.new(0, 1.5, "lin", 0.01, 1))
  params:set_action("level", function(v) engine.level(v) end)
  params:add_control("hour", "hour", controlspec.new(0, 24, "lin", 0.25, 6.5))
  params:set_action("hour", function(v) hour = v end)
  params:add_option("clock", "time", { "held", "real", "an hour a minute" }, 1)
  params:add_option("weather", "weather", { "still", "living" }, 2)
  params:set_action("weather", function(i) living = i == 2 end)

  -- the sounds
  local path = norns.state.path .. "sounds/"
  for i, name in ipairs(LAYERS) do engine.buf(i, path .. name .. ".wav") end
  for k = 1, 4 do engine.buf(THUNDER_SLOT + k - 1, path .. "thunder" .. k .. ".wav") end
  for k = 1, 2 do engine.buf(HOWLER_SLOT + k - 1, path .. "howler" .. k .. ".wav") end
  for k = 1, #WOOD_LEN do engine.buf(WOOD_SLOT + k - 1, path .. "wood/wood_" .. k .. ".wav") end
  for k, name in ipairs(MONKEY_FILES) do engine.buf(MONKEY_SLOT + k - 1, path .. "monkeys/" .. name .. ".wav") end
  for k = 1, JAGUAR_FILES do engine.buf(JAGUAR_SLOT + k - 1, path .. "jaguar/jaguar_" .. k .. ".wav") end
  local slot = FIRST_CALL
  for _, sp in ipairs(SPECIES) do
    sp.slot0 = slot
    for k = 1, sp.files do
      engine.buf(slot, path .. "birds/" .. sp.prefix .. "_" .. k .. ".wav")
      slot = slot + 1
    end
  end
  frog_slot0 = slot
  for k = 1, FROG_FILES do
    engine.buf(slot, path .. "frogs/frog_" .. k .. ".wav")
    slot = slot + 1
  end

  -- the scenery, the animals
  for _, L in ipairs(SCENE.lights) do
    for _, layer in ipairs({ "sky", "cloud", "mist", "far", "mid", "near" }) do
      local name = layer .. "_" .. L.name
      local ok, im = pcall(screen.load_png, norns.state.path .. "img/" .. name .. ".png")
      if ok then IMG[name] = im end
    end
  end
  for _, name in ipairs({ "rays", "sprites" }) do
    local ok, im = pcall(screen.load_png, norns.state.path .. "img/" .. name .. ".png")
    if ok then IMG[name] = im end
  end
  for i = 1, 40 do stars[i] = { math.random(0, 127), math.random(0, 26), math.random(), 0.5 + math.random() * 2 } end

  util.make_dir(DATA)
  if util.file_exists(DATA .. "state.pset") then params:read(DATA .. "state.pset") end
  params:bang()
  hour = params:get("hour")
  weather.rain = P("rain")
  weather.target = P("rain")
  weather.next_change = 30
  last_t = util.time()
  -- a fault in a frame says so once and stops, rather than every frame
  sound_metro = metro.init(function()
    local ok, err = pcall(send_levels)
    if not ok then
      print("rainforest: " .. tostring(err))
      sound_metro:stop()
    end
  end, 0.25)
  sound_metro:start()
  redraw_metro = metro.init(function()
    local ok, err = pcall(function()
      tick()
      grid_redraw()
    end)
    if not ok then
      print("rainforest: " .. tostring(err))
      redraw_metro:stop()
    end
  end, 1 / 24)
  redraw_metro:start()
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if sound_metro then sound_metro:stop() end
  params:set("hour", hour)
  util.make_dir(DATA)
  params:write(DATA .. "state.pset")
end
