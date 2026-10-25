-- morph: run with `lua5.3 tests/t_morph.lua` from the repo
local H = dofile((arg[0]:gsub("t_morph.lua$", "harness.lua")))
local function vp(v, n) return "v" .. v .. "_" .. n end
local function show(tag)
  local b, t, gt = {}, {}, {}
  for v = 1, 4 do b[v] = params:get(vp(v, "bit")); t[v] = params:get(vp(v, "tune")); gt[v] = params:get(vp(v, "gate")) end
  print(string.format("%-6s rule %3d bits %s tunes %s gates %s slots v1 %d%d%d%d time %d seed %d",
    tag, params:get("rule"), table.concat(b, ","), table.concat(t, ","), table.concat(gt, ","),
    params:get("v1_slot1_on"), params:get("v1_slot2_on"), params:get("v1_slot3_on"), params:get("v1_slot4_on"),
    params:get("time"), params:get("seed")))
end
math.randomseed(7)
-- snapshot 1: A
params:set("seed", 10); params:set("rule", 30)
H.key(16, 6)
-- snapshot 2: B
params:set("seed", 99); params:set("rule", 110)
local bits, tunes = {8, 0, 2, 4}, {3, -3, 0, 1}
for v = 1, 4 do params:set(vp(v, "bit"), bits[v]); params:set(vp(v, "tune"), tunes[v]); params:set(vp(v, "gate"), 40) end
params:set("v1_slot2_on", 0); params:set("v1_slot4_on", 0); params:set("time", 1)
H.key(16, 6)
assert(params:get("cycle_mode") == 1)
-- back to A, then play and morph 1 (1 bar = 4 beats) to B
H.key(9, 7)
show("A")
params:set("cycle_write", 1)   -- a morph's values must not be written into A
H.play()
H.key(7, 8)
for i = 1, 3 do METRO.event() end
assert(LEDS["7,8"] == 15, "armed key not lit")
H.key(10, 7)
local steps = 0
while true do
  H.step(); steps = steps + 1
  if steps % 2 == 0 then show("s" .. steps) end
  if steps > 64 then error("morph never ended") end
  -- the screen and grid draw while it runs
  METRO.event()
  if steps == 2 then assert(LEDS["10,7"] ~= nil and LEDS["7,8"] == 4, "leds during morph") end
  if params:get("time") == 1 then break end
end
show("end")
print("steps", steps)
local B = {rule = 110, seed = 99, time = 1}
for k, v in pairs(B) do assert(params:get(k) == v, k) end
for v = 1, 4 do
  assert(params:get(vp(v, "bit")) == bits[v]); assert(params:get(vp(v, "tune")) == tunes[v]); assert(params:get(vp(v, "gate")) == 40)
end
assert(params:get("v1_slot2_on") == 0 and params:get("v1_slot4_on") == 0)
-- A was not written to by the morph
H.key(9, 7)
show("A again")
assert(params:get("rule") == 30 and params:get("v1_gate") == 100 and params:get("v1_bit") == 1)
-- a recall in the middle of a morph stops it
H.key(8, 8); H.key(10, 7)
for i = 1, 6 do H.step() end
local mid = params:get("rule")
H.key(9, 7)
for i = 1, 40 do H.step() end
assert(params:get("rule") == 30 and params:get("time") == 3, "recall did not stop the morph")
-- arm, disarm
H.key(7, 8); H.key(7, 8); H.key(10, 7)
assert(params:get("time") == 1, "a disarmed key still morphed")
print("all ok")
