-- morph: moves from where the lines are to a snapshot over a length of time,
-- instead of jumping there, as in less concepts.
--
-- each value of the snapshot moves in its own way:
--   "step":   a whole number that steps one at a time, spread evenly over
--             the morph (bits, tunes, gates)
--   "flips":  the bits that differ between two rules flip one at a time,
--             in a random order, so the automaton drifts from one rule to
--             the other
--   "toggle": a switch that changes once, at a random point of the morph
--             (the kit slots, so a kit changes a sound at a time)
-- the rest of the snapshot comes at the end, when it is recalled.
--
-- a morph is counted in the beats played, so it stands still while the
-- sequencer is stopped.

local morph = {}

-- morph lengths, in beats
local LENGTHS = {
  {"1/4 bar", 1}, {"1/2 bar", 2}, {"1 bar", 4}, {"2 bars", 8},
  {"4 bars", 16}, {"8 bars", 32}, {"16 bars", 64}, {"32 bars", 128},
}
local DEFAULT_LENGTHS = {3, 5} -- 1 bar, 4 bars

local active = false
local slot = nil   -- the snapshot it moves to
local target = nil -- a copy of the snapshot, as it was when the morph started
local events = {}  -- the changes along the way, in order: {at = fraction, id, value}
local next_event = 1
local elapsed, total = 0, 1

-- redefine in the script: set a value on the way
function morph.apply(id, value) end
-- redefine in the script: the morph has arrived, recall the snapshot
function morph.finish(to_slot, snapshot) end

-- the steps from one value to another, evenly spaced: one step lands in the
-- middle, the last just before the end
local function add_steps(id, from, to)
  local n = math.abs(to - from)
  local dir = to > from and 1 or -1
  for k = 1, n do
    table.insert(events, {at = (k - 0.5) / n, id = id, value = from + dir * k})
  end
end

-- the bits that differ between two rules, flipped one at a time in a random
-- order, with the same spacing as add_steps
local function add_flips(id, from, to)
  local bits = {}
  for b = 0, 7 do
    if (from >> b) & 1 ~= (to >> b) & 1 then table.insert(bits, b) end
  end
  for k = #bits, 2, -1 do
    local j = math.random(k)
    bits[k], bits[j] = bits[j], bits[k]
  end
  local value = from
  for k, b in ipairs(bits) do
    value = value ~ (1 << b)
    table.insert(events, {at = (k - 0.5) / #bits, id = id, value = value})
  end
end

-- the length of morph 1 or 2, in beats
function morph.length(i)
  return LENGTHS[params:get("morph_length_" .. i)][2]
end

--- start a morph to snapshot `to_slot` over `beats`, from the values in
--- `from` to those in `to`. `kinds` maps each id that moves on the way to
--- "step", "flips" or "toggle"; an id missing from either is left as it is
function morph.start(to_slot, from, to, beats, kinds)
  events = {}
  for id, kind in pairs(kinds) do
    local a, b = from[id], to[id]
    if a ~= nil and b ~= nil and a ~= b then
      if kind == "step" then add_steps(id, a, b)
      elseif kind == "flips" then add_flips(id, a, b)
      elseif kind == "toggle" then
        table.insert(events, {at = math.random(), id = id, value = b})
      end
    end
  end
  table.sort(events, function(x, y) return x.at < y.at end)
  next_event = 1
  elapsed = 0
  total = math.max(beats, 1e-3)
  slot = to_slot
  target = to
  active = true
end

function morph.cancel() active = false end
function morph.active() return active end
function morph.slot() return active and slot or nil end
function morph.progress() return active and math.min(1, elapsed / total) or 0 end

--- call on each step that plays, with the beats of the step. true when
--- something changed
function morph.tick(beats)
  if not active then return false end
  elapsed = elapsed + beats
  local progress = elapsed / total
  local changed = false
  while events[next_event] and events[next_event].at <= progress do
    local e = events[next_event]
    morph.apply(e.id, e.value)
    next_event = next_event + 1
    changed = true
  end
  if elapsed >= total - 1e-6 then
    active = false
    morph.finish(slot, target)
    changed = true
  end
  return changed
end

function morph.add_params()
  local names = {}
  for k, l in ipairs(LENGTHS) do names[k] = l[1] end
  params:add_group("rhythms_morph", "morph", 2)
  for i = 1, 2 do
    params:add_option("morph_length_" .. i, "morph " .. i .. " length", names, DEFAULT_LENGTHS[i])
  end
end

return morph
