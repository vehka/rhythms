-- rhythms:
-- cellular automata drums
-- v0.2.0
-- a companion to less concepts:
-- four lines of drum hits from
-- the same seeds and rules, for
-- the analog rytm and nb voices
--
-- enc 1: navigate
-- enc 2: change left side,
--   or pick a line
-- enc 3: change right side,
--   or the line's value
-- key 2: take snapshot
-- on snapshots, key 2: recall
-- hold key 2, then key 3:
--   delete selected snapshot
-- key 3: randomize selected
--
-- grid
-- (1,1) to (8,4): bits, a row
--   per line; (9,y) mutes it
-- (10,1) to (16,4): tune
-- (1,5) to (16,5): the kit of
--   each line, four keys each:
--   press to leave a sound out
-- (1,6): random seed, (2,6):
--   random rule, (3,6): bits,
--   (4,6): tunes, (5,6): time,
--   (6,6): randomize all
-- (7,6): step / loom
-- (8,6): back to the seed
-- (9,6) (10,6) (11,6): cycle
--   snapshots < ~ >, hold one
--   to write edits into them
-- (14,6): clear all (hold)
-- (15,6): clear selected (hold)
-- (16,6): take snapshot
-- (9,7) to (16,8): snapshots
-- (1,8): play/stop
-- (2,8) to (4,8): time +/-
-- (7,8) (8,8): morph 1 and 2:
--   press one, then a snapshot,
--   to move there over the
--   morph's length

local automaton = include('lib/automaton')
local kit = include('lib/kit')
local out = include('lib/out')
local snapshots = include('lib/snapshots')
local morph = include('lib/morph')

-- optional: https://github.com/sixolet/nb lets the lines play nb voices.
-- the installed library, or else the copy another script or mod bundles
local function find_nb()
  if util.file_exists(_path.code .. "nb/lib/nb.lua") then return "nb/lib/nb" end
  for _, dir in ipairs(util.scandir(_path.code)) do
    if util.file_exists(_path.code .. dir .. "lib/nb/lib/nb.lua") then
      return dir .. "lib/nb/lib/nb"
    end
  end
end
local nb_path = find_nb()
local nb = nb_path and include(nb_path) or nil

local VOICES = 4
local SLOTS = 4
local TIME_NAMES = {"1/8", "1/8t", "1/16", "1/16t", "1/32"}
local TIME_BEATS = {1/2, 1/3, 1/4, 1/6, 1/8}
local LOOP_NAMES = {"off", "4", "8", "12", "16", "24", "32", "48", "64"}
local LOOP_STEPS = {0, 4, 8, 12, 16, 24, 32, 48, 64}
local AUTOMATA = {"step", "loom"}
local ACCENTS = {"crowd", "lone", "off"}
local CYCLE_NAMES = {"off", "down", "random", "up"}
local CYCLE_SIGNS = {"-", "<", "~", ">"}
local OUTPUTS = {"rytm", "nb", "rytm + nb"}
local HISTORY = 20

local function vp(v, name) return "v" .. v .. "_" .. name end

-- state of the automaton
local ca = 0            -- step mode: the generation that plays next
local rings = {}        -- loom mode: a ring of cells per line
local history = {}      -- step mode: generations played, newest first
local step = 0          -- steps played since play
local since_seed = 0    -- steps since the seed was planted
local beat_pos = 0      -- beats played since play
local next_cycle = 0    -- the beat of the next snapshot cycle
local last_hit = {}     -- per line: the step and kit slot it last played
local rytm_hits = {}    -- the rytm tracks hit in this step: velocity, tune

-- transport and ui
local playing, waiting = false, false
local seq_clock, ui_metro
local screen_dirty, grid_dirty = true, true
local blink = 0
local g = grid.connect()
local focus = 1
local cur_voice = 1
local key2_held = false
local snap_held = false
local recalling = false
local hold_clocks = {}
local morph_armed = nil -- the morph armed by its grid key, 1 or 2
local morph_blink = 0   -- the phases of the blinks of the snapshot a morph
local arm_blink = 0     -- moves to, and of the armed morph key

local FOCI = {"seed/rule", "bits", "tune", "gate", "time", "feel", "snapshots", "cycle"}

local function is_loom() return params:get("automaton") == 2 end
local function loom_len() return params:get("loom_len") end
local function step_beats() return TIME_BEATS[params:get("time")] end

local function dirty()
  screen_dirty = true
  grid_dirty = true
end

-- plant the seed: the automaton starts over from it
local function plant()
  local seed = params:get("seed")
  ca = seed
  for v = 1, VOICES do
    rings[v] = automaton.loom_ring(seed, math.max(1, params:get(vp(v, "bit"))), loom_len())
  end
  since_seed = 0
  dirty()
end

-- the kit slots a line may play
local function slots_of(v)
  local list = {}
  for s = 1, SLOTS do
    if params:get(vp(v, "slot" .. s .. "_on")) == 1 then list[#list + 1] = s end
  end
  return list
end

-- the velocity of a hit with `n` lit neighbours
local VEL_IDS = {"vel_ghost", "vel_normal", "vel_accent"}
local function velocity(n)
  local mode = params:get("accents")
  local level = 2
  if mode == 1 then level = n + 1
  elseif mode == 2 then level = 3 - n end
  return params:get(VEL_IDS[level])
end

-- line v hits. `choice` (0 to 1) picks the sound from its kit, `n` is the
-- number of lit neighbours of the cell that played
local function hit(v, choice, n)
  if math.random(100) > params:get(vp(v, "gate")) then return false end
  local track, slot
  local kit_mode = params:get(vp(v, "mode")) == 1
  if kit_mode then
    local list = slots_of(v)
    if #list == 0 then return false end
    slot = list[math.min(#list, math.floor(choice * #list) + 1)]
    track = params:get(vp(v, "slot" .. slot))
  else
    track = params:get(vp(v, "track"))
  end
  local vel = velocity(n)
  local semis = params:get(vp(v, "tune")) * params:get(vp(v, "tune_step"))
  local o = params:get(vp(v, "out"))
  if o ~= 2 then
    -- two lines on one track in a step make one hit, the louder
    local h = rytm_hits[track]
    if not h or vel > h.vel then rytm_hits[track] = {vel = vel, semis = semis} end
  end
  if nb and o ~= 1 then
    local player = params:lookup_param(vp(v, "nb")):get_player()
    local note = kit_mode and out.gm_note(track) or params:get(vp(v, "nb_note")) + semis
    out.nb(player, note, vel, step_beats())
  end
  last_hit[v] = {step = step, slot = slot}
  return true
end

local function send_rytm_hits()
  for track = 1, #kit.names do
    local h = rytm_hits[track]
    if h then out.rytm(track, h.semis, h.vel, step + 1) end
  end
  rytm_hits = {}
end

local function step_mode_tick()
  local rule = params:get("rule")
  local hits = 0
  for v = 1, VOICES do
    local bit = params:get(vp(v, "bit"))
    if bit > 0 and automaton.cell(ca, bit) == 1 then
      -- the generation read from this line's bit picks its sound, so each
      -- line picks differently from the same seed
      local choice = (automaton.rotate(ca, bit) >> 1) / 128
      if hit(v, choice, automaton.neighbours(ca, bit)) then
        hits = hits | (1 << (bit - 1))
      end
    end
  end
  table.insert(history, 1, {state = ca, hits = hits})
  history[HISTORY + 1] = nil
  ca = automaton.next(ca, rule)
end

-- loom mode: each ring is a bar of steps. the rule grows the next bar from
-- this one, every `loom_bars` bars
local function loom_tick()
  local len = loom_len()
  local p = step % len + 1
  for v = 1, VOICES do
    local ring = rings[v]
    if params:get(vp(v, "bit")) > 0 and automaton.cell(ring, p, len) == 1 then
      local a = automaton.cell(ring, p + 2, len)
      local b = automaton.cell(ring, p - 2, len)
      hit(v, (a * 2 + b) / 4, automaton.neighbours(ring, p, len))
    end
  end
  if p == len and (step + 1) // len % params:get("loom_bars") == 0 then
    local rule = params:get("rule")
    for v = 1, VOICES do rings[v] = automaton.next(rings[v], rule, len) end
  end
end

-- a snapshot recalled at once stops a morph
local function recall(n)
  morph.cancel()
  recalling = true
  local ok = snapshots.recall(n)
  recalling = false
  if ok then plant() end
end

-- the next snapshot, when a cycle is on and its beats have passed
local function cycle_check()
  local mode = params:get("cycle_mode")
  if mode == 1 or snapshots.count() == 0 or snap_held then return end
  if morph.active() then
    -- a morph holds the cycle, which goes on a cycle length after it ends
    next_cycle = beat_pos + params:get("cycle_beats")
    return
  end
  if beat_pos + 1e-6 < next_cycle then return end
  next_cycle = next_cycle + params:get("cycle_beats")
  local count, n = snapshots.count(), snapshots.selected
  if mode == 2 then n = n - 1; if n < 1 then n = count end
  elseif mode == 4 then n = n + 1; if n > count then n = 1 end
  else n = math.random(1, count) end
  recall(n)
end

local function tick()
  out.release_due(step)
  morph.tick(step_beats())
  cycle_check()
  if is_loom() then loom_tick() else step_mode_tick() end
  send_rytm_hits()
  step = step + 1
  since_seed = since_seed + 1
  beat_pos = beat_pos + step_beats()
  local loop = LOOP_STEPS[params:get("loop")]
  if loop > 0 and since_seed >= loop then plant() end
  dirty()
end

local function run()
  clock.sync(1) -- play starts on the next beat
  waiting = false
  playing = true
  step, beat_pos = 0, 0
  next_cycle = params:get("cycle_beats")
  history = {}
  plant()
  while true do
    -- swing: every other step is late, by up to half a step
    local swing = (params:get("swing") - 50) / 50
    if step % 2 == 1 and swing > 0 then
      clock.sleep(swing * step_beats() * clock.get_beat_sec())
    end
    tick()
    clock.sync(step_beats())
  end
end

local function start()
  if seq_clock then return end
  waiting = true
  seq_clock = clock.run(run)
  if params:get("send_transport") == 2 then out.transport(true) end
  dirty()
end

local function stop()
  if seq_clock then
    clock.cancel(seq_clock)
    seq_clock = nil
  end
  if playing and params:get("send_transport") == 2 then out.transport(false) end
  playing, waiting = false, false
  out.all_off()
  last_hit = {}
  dirty()
end

local function toggle_play()
  if seq_clock then stop() else start() end
end

function clock.transport.start() start() end
function clock.transport.stop() stop() end

-- randomize
local function random_seed() params:set("seed", math.random(0, 255)) end
local function random_rule() params:set("rule", math.random(0, 255)) end
local function random_bit(v) params:set(vp(v, "bit"), math.random(1, 8)) end
local function random_tune(v) params:set(vp(v, "tune"), math.random(-3, 3)) end
local function random_time() params:set("time", math.random(1, #TIME_NAMES)) end
local function randomize_all()
  random_seed()
  random_rule()
  for v = 1, VOICES do random_bit(v); random_tune(v) end
end

local function add_snapshot()
  if snapshots.add() then dirty() end
end

local function remove_snapshot(n)
  morph.cancel()
  snapshots.remove(n)
  if snapshots.count() == 0 then params:set("cycle_mode", 1) end
  dirty()
end

-- params ----------------------------------------------------------------

local function signed(param)
  local v = param:get()
  return v > 0 and ("+" .. v) or tostring(v)
end

local function add_pattern_params()
  params:add_group("rhythms_pattern", "rhythms", 9)
  params:add_number("seed", "seed", 0, 255, 36)
  params:set_action("seed", function() plant() end)
  params:add_number("rule", "rule", 0, 255, 30)
  params:set_action("rule", dirty)
  params:add_option("automaton", "automaton", AUTOMATA, 1)
  params:set_action("automaton", function() plant() end)
  params:add_number("loom_len", "loom length", 8, 16, 16)
  params:set_action("loom_len", function() plant() end)
  params:add_number("loom_bars", "loom bars per gen", 1, 8, 1)
  params:add_option("time", "time", TIME_NAMES, 3)
  params:set_action("time", dirty)
  params:add_option("loop", "loop (steps)", LOOP_NAMES, 1)
  params:set_action("loop", dirty)
  params:add_number("swing", "swing", 50, 75, 50, function(p) return p:get() .. "%" end)
  params:set_action("swing", dirty)
  params:add_trigger("play", "play/stop")
  params:set_action("play", toggle_play)

  params:add_group("rhythms_dynamics", "dynamics", 4)
  params:add_option("accents", "accents", ACCENTS, 1)
  params:set_action("accents", dirty)
  params:add_number("vel_ghost", "ghost velocity", 1, 127, 40)
  params:add_number("vel_normal", "normal velocity", 1, 127, 90)
  params:add_number("vel_accent", "accent velocity", 1, 127, 127)

  params:add_group("rhythms_snapshots", "snapshots", 3)
  params:add_option("cycle_mode", "cycle", CYCLE_NAMES, 1)
  params:set_action("cycle_mode", function()
    next_cycle = beat_pos + params:get("cycle_beats")
    dirty()
  end)
  params:add_number("cycle_beats", "cycle length (beats)", 1, 64, 4)
  params:set_action("cycle_beats", dirty)
  params:add_binary("cycle_write", "cycle writes edits", "toggle", 0)
  params:set_action("cycle_write", dirty)
end

local function add_voice_params(v)
  params:add_group("rhythms_v" .. v, "line " .. v, 17 + (nb and 2 or 0))
  params:add_number(vp(v, "bit"), "bit", 0, 8, 2 * v - 1,
    function(p) return p:get() == 0 and "mute" or tostring(p:get()) end)
  params:set_action(vp(v, "bit"), function(b)
    rings[v] = automaton.loom_ring(params:get("seed"), math.max(1, b), loom_len())
    dirty()
  end)
  params:add_number(vp(v, "tune"), "tune", -3, 3, 0, signed)
  params:set_action(vp(v, "tune"), dirty)
  params:add_number(vp(v, "tune_step"), "tune step (semitones)", 1, 12, 2)
  params:add_number(vp(v, "gate"), "gate probability", 0, 100, 100,
    function(p) return p:get() .. "%" end)
  params:set_action(vp(v, "gate"), dirty)
  params:add_option(vp(v, "mode"), "plays", {"kit", "single"}, 1)
  params:set_action(vp(v, "mode"), dirty)
  params:add_option(vp(v, "out"), "output", OUTPUTS, 1)
  params:add_option(vp(v, "track"), "single: track", kit.names, kit.default_single[v])
  if nb then nb:add_param(vp(v, "nb"), "nb voice") end
  params:add_number(vp(v, "nb_note"), "single: nb note", 0, 127, 60)
  params:add_separator("rhythms_v" .. v .. "_kit", "kit")
  for s = 1, SLOTS do
    params:add_option(vp(v, "slot" .. s), "slot " .. s, kit.names, kit.default_slots[v][s])
  end
  for s = 1, SLOTS do
    params:add_binary(vp(v, "slot" .. s .. "_on"), "slot " .. s .. " plays", "toggle", 1)
    params:set_action(vp(v, "slot" .. s .. "_on"), dirty)
  end
end

local function midi_device_names()
  local names = {}
  for i = 1, #midi.vports do
    names[i] = i .. ": " .. midi.vports[i].name
  end
  return names
end

local function add_midi_params()
  params:add_group("rhythms_midi", "rytm & midi", 6)
  params:add_option("midi_device", "midi out", midi_device_names(), 1)
  params:set_action("midi_device", function(i)
    out.all_off()
    out.forget_tune()
    out.port = midi.connect(i)
  end)
  params:add_option("rytm_mode", "rytm notes", {"track channels", "auto channel"}, 1)
  params:set_action("rytm_mode", function() out.all_off() end)
  params:add_number("rytm_base_ch", "BD track channel", 1, 16, 1)
  params:set_action("rytm_base_ch", function() out.all_off(); out.forget_tune() end)
  params:add_number("rytm_auto_ch", "auto channel", 1, 16, 14)
  params:set_action("rytm_auto_ch", function() out.all_off() end)
  params:add_option("rytm_tune_via", "tune via", {"synth tune cc", "off"}, 1)
  params:add_option("send_transport", "send start/stop", {"off", "on"}, 1)
end

-- the params a snapshot holds
local function snapshot_ids()
  local ids = {"seed", "rule", "automaton", "loom_len", "loom_bars", "time", "loop"}
  for v = 1, VOICES do
    table.insert(ids, vp(v, "bit"))
    table.insert(ids, vp(v, "tune"))
    table.insert(ids, vp(v, "gate"))
    for s = 1, SLOTS do table.insert(ids, vp(v, "slot" .. s .. "_on")) end
  end
  return ids
end

-- while a cycle writes, an edit goes into the selected snapshot too
local function wrap_for_writing(ids)
  for _, id in ipairs(ids) do
    local p = params:lookup_param(id)
    local action = p.action
    p.action = function(x)
      action(x)
      if params:get("cycle_write") == 1 and not recalling then
        snapshots.write(id, x)
      end
    end
  end
end

-- morph ---------------------------------------------------------------------

-- how each value moves on the way to a snapshot; the rest comes at the end
local function morph_kinds()
  local kinds = {rule = "flips"}
  for v = 1, VOICES do
    kinds[vp(v, "bit")] = "step"
    kinds[vp(v, "tune")] = "step"
    kinds[vp(v, "gate")] = "step"
    for s = 1, SLOTS do kinds[vp(v, "slot" .. s .. "_on")] = "toggle" end
  end
  return kinds
end

-- move to snapshot n with morph i, from where the lines are. the morph keeps
-- its own copy, as a cycle that writes may change the snapshot
local function morph_to(n, i)
  local to = snapshots.list[n]
  if not to then return end
  local from, copy = {}, {}
  for id, value in pairs(to) do
    copy[id] = value
    from[id] = params:get(id)
  end
  morph.start(n, from, copy, morph.length(i), morph_kinds())
end

-- the values on the way aren't edits, so a cycle that writes keeps them out
-- of its snapshot
morph.apply = function(id, value)
  recalling = true
  params:set(id, value)
  recalling = false
end

morph.finish = function(n, snapshot)
  recalling = true
  for id, value in pairs(snapshot) do
    if params.lookup[id] then params:set(id, value) end
  end
  recalling = false
  snapshots.selected = math.min(n, snapshots.count())
  plant()
end

-- grid --------------------------------------------------------------------

local function recent(v)
  return last_hit[v] and last_hit[v].step == step - 1
end

local function snapshot_xy(n)
  return 8 + (n - 1) % 8 + 1, n <= 8 and 7 or 8
end

local function grid_redraw()
  g:all(0)
  local shown = history[1] and history[1].state or ca
  for v = 1, VOICES do
    local bit = params:get(vp(v, "bit"))
    if not is_loom() then
      for i = 1, 8 do
        if automaton.cell(shown, i) == 1 then g:led(9 - i, v, 2) end
      end
    end
    g:led(9 - bit, v, bit == 0 and 8 or 6)
    if bit > 0 and recent(v) then g:led(9 - bit, v, 15) end
    g:led(13, v, 3)
    g:led(params:get(vp(v, "tune")) + 13, v, 12)
  end

  for v = 1, VOICES do
    local kit_mode = params:get(vp(v, "mode")) == 1
    for s = 1, SLOTS do
      local x = (v - 1) * SLOTS + s
      local level = 0
      if kit_mode then
        level = params:get(vp(v, "slot" .. s .. "_on")) == 1 and 5 or 1
        if recent(v) and last_hit[v].slot == s then level = 15 end
      elseif s == 1 then
        level = recent(v) and 15 or 5
      end
      g:led(x, 5, level)
    end
  end

  for x = 1, 6 do g:led(x, 6, 3) end
  g:led(7, 6, is_loom() and 12 or 3)
  g:led(8, 6, 3)
  local mode = params:get("cycle_mode")
  for i = 1, 3 do
    local level = snapshots.count() > 0 and 4 or 1
    if mode == i + 1 then
      level = 15
      if params:get("cycle_write") == 1 and blink % 8 < 4 then level = 4 end
    end
    g:led(8 + i, 6, level)
  end
  g:led(14, 6, 2)
  g:led(15, 6, 4)
  g:led(16, 6, 6)

  for n = 1, snapshots.MAX do
    local x, y = snapshot_xy(n)
    local level = 2
    if n <= snapshots.count() then level = 6 end
    if n == snapshots.selected then level = 15 end
    if n == morph.slot() then level = morph_blink < 0.5 and 15 or 2 end
    g:led(x, y, level)
  end

  for i = 1, 2 do
    local level = snapshots.count() > 0 and 4 or 1
    if morph_armed == i then level = arm_blink < 0.5 and 15 or 0 end
    g:led(6 + i, 8, level)
  end

  g:led(1, 8, playing and 15 or (waiting and 8 or 4))
  local t = params:get("time")
  g:led(2, 8, util.round(15 * (#TIME_NAMES - t + 1) / #TIME_NAMES))
  g:led(3, 8, 8)
  g:led(4, 8, util.round(15 * t / #TIME_NAMES))
  g:refresh()
end

-- run `fn` if key `id` is held for `seconds`
local function on_hold(id, seconds, fn)
  hold_clocks[id] = clock.run(function()
    clock.sleep(seconds)
    hold_clocks[id] = nil
    fn()
    dirty()
  end)
end

local function release_hold(id)
  if hold_clocks[id] then
    clock.cancel(hold_clocks[id])
    hold_clocks[id] = nil
    return true -- released before the hold fired
  end
  return false
end

local function cycle_key(x, z)
  local mode = x - 7 -- 9 down, 10 random, 11 up
  if z == 1 then
    on_hold("cycle" .. x, 0.5, function()
      params:set("cycle_mode", mode)
      params:set("cycle_write", 1 - params:get("cycle_write"))
    end)
  elseif release_hold("cycle" .. x) then
    if params:get("cycle_mode") == mode then
      params:set("cycle_mode", 1)
      params:set("cycle_write", 0)
    elseif snapshots.count() > 0 then
      params:set("cycle_mode", mode)
    end
  end
end

local function grid_key(x, y, z)
  if y <= VOICES then
    if z == 1 then
      if x <= 9 then params:set(vp(y, "bit"), 9 - x)
      else params:set(vp(y, "tune"), x - 13) end
    end
  elseif y == 5 then
    local v = (x - 1) // SLOTS + 1
    local s = (x - 1) % SLOTS + 1
    if z == 1 and params:get(vp(v, "mode")) == 1 then
      local id = vp(v, "slot" .. s .. "_on")
      params:set(id, 1 - params:get(id))
    end
  elseif y == 6 then
    if x >= 9 and x <= 11 then
      cycle_key(x, z)
    elseif x == 14 or x == 15 then
      if z == 1 then
        on_hold("clear" .. x, 0.75, function()
          if x == 14 then
            morph.cancel()
            snapshots.clear()
            params:set("cycle_mode", 1)
          else
            remove_snapshot(snapshots.selected)
          end
        end)
      else
        release_hold("clear" .. x)
      end
    elseif z == 1 then
      if x == 1 then random_seed()
      elseif x == 2 then random_rule()
      elseif x == 3 then for v = 1, VOICES do random_bit(v) end
      elseif x == 4 then for v = 1, VOICES do random_tune(v) end
      elseif x == 5 then random_time()
      elseif x == 6 then randomize_all()
      elseif x == 7 then params:set("automaton", is_loom() and 1 or 2)
      elseif x == 8 then plant()
      elseif x == 16 then add_snapshot()
      end
    end
  elseif x >= 9 then
    local n = (y == 7 and 0 or 8) + x - 8
    if z == 1 then
      if n <= snapshots.count() then
        if morph_armed then
          morph_to(n, morph_armed)
          morph_armed = nil
        else
          recall(n)
        end
      end
      snap_held = true
    else
      snap_held = false
    end
  elseif y == 8 and z == 1 then
    if x == 1 then toggle_play()
    elseif x == 2 then params:delta("time", -1)
    elseif x == 3 then params:set("time", 3)
    elseif x == 4 then params:delta("time", 1)
    elseif x == 7 or x == 8 then
      -- arm a morph, or disarm it
      local i = x - 6
      morph_armed = morph_armed ~= i and i or nil
      arm_blink = 0
    end
  end
  dirty()
end

-- screen ------------------------------------------------------------------

local function level_for(f) return FOCI[focus] == f and 15 or 3 end

local function draw_history()
  for gen, h in ipairs(history) do
    local y = 2 + (gen - 1) * 2
    for i = 1, 8 do
      local on = automaton.cell(h.state, i) == 1
      if on then
        screen.level(((h.hits >> (i - 1)) & 1) == 1 and 15 or 3)
        screen.rect((8 - i) * 5, y, 4, 1)
        screen.fill()
      end
    end
  end
end

local function draw_rings()
  local len = loom_len()
  local w = 48 // len -- 3 pixels a step at 16 steps
  local p = (step - 1) % len + 1
  for v = 1, VOICES do
    local y = 2 + (v - 1) * 11
    for i = 1, len do
      local on = automaton.cell(rings[v], i, len) == 1
      local level = on and 4 or 0
      if playing and i == p then level = on and 15 or 1 end
      if params:get(vp(v, "bit")) == 0 and on then level = 1 end
      if level > 0 then
        screen.level(level)
        screen.rect((i - 1) * w, y, w - 1, 8)
        screen.fill()
      end
    end
  end
end

local function draw_voices(y, label, f, value)
  screen.level(level_for(f))
  screen.move(48, y)
  screen.text(label)
  for v = 1, VOICES do
    local selected = FOCI[focus] == f and v == cur_voice
    screen.level(selected and 15 or (FOCI[focus] == f and 6 or 3))
    screen.move(68 + (v - 1) * 15, y)
    screen.text(value(v))
  end
end

function redraw()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)
  if is_loom() then draw_rings() else draw_history() end

  screen.level(level_for("seed/rule"))
  screen.move(48, 8)
  screen.text("s " .. params:get("seed") .. " // r " .. params:get("rule"))
  screen.level(is_loom() and 15 or 3)
  screen.move(0, 50)
  screen.text(is_loom() and "loom" or "step")

  draw_voices(16, "bits", "bits", function(v)
    local b = params:get(vp(v, "bit"))
    return b == 0 and "-" or tostring(b)
  end)
  draw_voices(24, "tune", "tune", function(v) return params:string(vp(v, "tune")) end)
  draw_voices(32, "gate", "gate", function(v) return tostring(params:get(vp(v, "gate"))) end)

  screen.level(level_for("time"))
  screen.move(48, 40)
  screen.text(params:string("time") .. " // loop " .. params:string("loop"))
  screen.level(level_for("feel"))
  screen.move(48, 48)
  screen.text("swing " .. params:get("swing") .. " // " .. params:string("accents"))

  for n = 1, snapshots.MAX do
    local level = FOCI[focus] == "snapshots" and 2 or 1
    if n <= snapshots.count() then level = 4 end
    if n == snapshots.selected then level = FOCI[focus] == "snapshots" and 15 or 8 end
    if n == morph.slot() then level = morph_blink < 0.5 and 15 or 1 end
    screen.level(level)
    screen.rect(((n - 1) % 8) * 5, 54 + (n > 8 and 5 or 0), 4, 4)
    screen.fill()
  end
  screen.level(level_for("cycle"))
  screen.move(48, 62)
  if morph.active() then
    screen.text("morph > " .. morph.slot() .. "  "
      .. util.round(100 * morph.progress()) .. "%")
  else
    local write = params:get("cycle_write") == 1 and "*" or ""
    screen.text("cycle " .. CYCLE_SIGNS[params:get("cycle_mode")] .. write
      .. " " .. params:get("cycle_beats") .. " beats")
  end
  screen.update()
end

-- keys and encoders ---------------------------------------------------------

function enc(n, d)
  local f = FOCI[focus]
  if n == 1 then
    focus = util.clamp(focus + d, 1, #FOCI)
  elseif n == 2 then
    if f == "seed/rule" then params:delta("seed", d)
    elseif f == "bits" or f == "tune" or f == "gate" then
      cur_voice = util.clamp(cur_voice + d, 1, VOICES)
    elseif f == "time" then params:delta("time", d)
    elseif f == "feel" then params:delta("swing", d)
    elseif f == "snapshots" and snapshots.count() > 0 then
      snapshots.selected = util.clamp(snapshots.selected + d, 1, snapshots.count())
    elseif f == "cycle" then params:delta("cycle_mode", d)
    end
  elseif n == 3 then
    if f == "seed/rule" then params:delta("rule", d)
    elseif f == "bits" then params:delta(vp(cur_voice, "bit"), -d)
    elseif f == "tune" then params:delta(vp(cur_voice, "tune"), d)
    elseif f == "gate" then params:delta(vp(cur_voice, "gate"), d)
    elseif f == "time" then params:delta("loop", d)
    elseif f == "feel" then params:delta("accents", d)
    elseif f == "cycle" then params:delta("cycle_beats", d)
    end
  end
  dirty()
end

function key(n, z)
  local f = FOCI[focus]
  if n == 2 then
    key2_held = z == 1
    if z == 1 then
      if f == "snapshots" and snapshots.selected > 0 then recall(snapshots.selected)
      else add_snapshot() end
    end
  elseif n == 3 and z == 1 then
    if key2_held then
      remove_snapshot(snapshots.selected)
    elseif f == "seed/rule" then random_seed(); random_rule()
    elseif f == "bits" then random_bit(cur_voice)
    elseif f == "tune" then random_tune(cur_voice)
    elseif f == "gate" then params:set(vp(cur_voice, "gate"), math.random(0, 100))
    elseif f == "time" then random_time()
    elseif f == "snapshots" then randomize_all()
    elseif f == "cycle" then params:set("cycle_write", 1 - params:get("cycle_write"))
    end
  end
  dirty()
end

-- init and cleanup ----------------------------------------------------------

function init()
  if nb then nb:init() end
  add_pattern_params()
  for v = 1, VOICES do add_voice_params(v) end
  morph.add_params()
  add_midi_params()
  if nb then nb:add_player_params() end

  local ids = snapshot_ids()
  snapshots.set_ids(ids)
  wrap_for_writing(ids)

  params.action_write = function(filename) snapshots.save(filename) end
  params.action_read = function(filename)
    snapshots.load(filename)
    plant()
    dirty()
  end
  params.action_delete = function(filename) snapshots.delete(filename) end

  g.key = grid_key
  grid.add = function() grid_dirty = true end

  params:bang()
  plant()

  -- the screen and grid are drawn at 30 fps, when something has changed
  ui_metro = metro.init(function()
    blink = blink + 1
    if params:get("cycle_write") == 1 then grid_dirty = true end
    if morph.active() then
      -- faster as it nears the end: once a second at the start, 8 at the end
      morph_blink = (morph_blink + (1 + 7 * morph.progress()) / 30) % 1
      dirty()
    end
    if morph_armed then
      arm_blink = (arm_blink + 3 / 30) % 1
      grid_dirty = true
    end
    if screen_dirty then redraw(); screen_dirty = false end
    if grid_dirty then grid_redraw(); grid_dirty = false end
  end, 1 / 30, -1)
  ui_metro:start()
end

function cleanup()
  stop()
  if ui_metro then metro.free(ui_metro.id); ui_metro = nil end
end
