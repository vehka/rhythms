-- offline harness for rhythms: stubs of the norns host, enough to run the
-- script's params, grid keys and sequencer steps, in plain lua 5.3.
-- it needs norns' lua/lib for util and tabutil: $NORNS, or ~/norns.
-- not covered: matron bindings, nb, audio, real midi and timing.
local ROOT = (arg and arg[0]:match("^(.*/)tests/[^/]*$"))
  or (io.open("rhythms.lua") and "./" or "../")
local NORNS = os.getenv("NORNS") or (os.getenv("HOME") .. "/norns")
package.path = NORNS .. "/lua/lib/?.lua;" .. package.path
util = require("util")
tab = require("tabutil")
util.scandir = function() return {} end
util.file_exists = function() return false end

function include(name) return dofile(ROOT .. name .. ".lua") end
_path = {code = "/nonexistent/", data = "/tmp/"}
norns = {state = {data = "/tmp/", name = "rhythms"}}

-- params -------------------------------------------------------------------
params = {params = {}, lookup = {}}
local P = params
local function add(p)
  table.insert(P.params, p); P.lookup[p.id] = p
  p.action = p.action or function() end
  p.get = function(self) return self.value end
  return p
end
function P:add_group() end
function P:add_separator() end
function P:add_number(id, name, min, max, default, fmt)
  add({id = id, t = "number", min = min, max = max, value = default, fmt = fmt})
end
function P:add_option(id, name, options, default)
  add({id = id, t = "option", min = 1, max = #options, options = options, value = default})
end
function P:add_binary(id, name, kind, default)
  add({id = id, t = "binary", min = 0, max = 1, value = default})
end
function P:add_trigger(id) add({id = id, t = "trigger", min = 0, max = 1, value = 0}) end
function P:set_action(id, f) P.lookup[id].action = f end
function P:lookup_param(id) return assert(P.lookup[id], "no param " .. id) end
function P:get(id) return P:lookup_param(id).value end
function P:set(id, v, silent)
  local p = P:lookup_param(id)
  if p.t == "trigger" then p.action(1) return end
  v = util.clamp(v, p.min, p.max)
  local changed = p.value ~= v
  p.value = v
  if not silent then p.action(v) end
end
function P:delta(id, d) P:set(id, P:get(id) + d) end
function P:string(id)
  local p = P:lookup_param(id)
  if p.options then return p.options[p.value] end
  return p.fmt and p.fmt(p) or tostring(p.value)
end
function P:bang() for _, p in ipairs(P.params) do if p.t ~= "trigger" then p.action(p.value) end end end

-- clock: run() is driven by hand, one step per resume ------------------------
clock = {transport = {}, beats = 0}
clock.coros = {}
function clock.run(f, ...)
  local co = coroutine.create(f)
  table.insert(clock.coros, co)
  local ok, err = coroutine.resume(co, ...)
  assert(ok, err)
  return #clock.coros
end
function clock.cancel(id) clock.coros[id] = nil end
function clock.sync(b) coroutine.yield("sync", b) end
function clock.sleep(s) coroutine.yield("sleep", s) end
function clock.get_beat_sec() return 0.5 end
function clock.get_beats() return clock.beats end

metro = {init = function(f) METRO = {start = function() end, event = f, id = 1}; return METRO end, free = function() end}

-- grid and midi ---------------------------------------------------------------
LEDS = {}
grid = {connect = function()
  GRID = {all = function() LEDS = {} end,
          led = function(self, x, y, l) LEDS[x .. "," .. y] = l end,
          refresh = function() end}
  return GRID
end}
SENT = {}
local port = {name = "rytm"}
function port:note_on(n, v, ch) table.insert(SENT, {"on", ch, n, v}) end
function port:note_off(n, v, ch) table.insert(SENT, {"off", ch, n}) end
function port:cc(cc, v, ch) table.insert(SENT, {"cc", ch, cc, v}) end
function port:start() end
function port:stop() end
midi = {vports = {port}, connect = function() return port end}

screen = setmetatable({}, {__index = function() return function() end end})

dofile(ROOT .. "rhythms.lua")
init()

-- helpers for tests -------------------------------------------------------------
H = {}
function H.key(x, y) GRID.key(x, y, 1); GRID.key(x, y, 0) end
function H.play() H.key(1, 8); H.seq = clock.coros[#clock.coros] end
-- the sequencer clock: resume it until it has played one step
function H.step()
  local co = H.seq
  repeat
    local ok, what = coroutine.resume(co)
    assert(ok, what)
  until what == "sync"
end
return H
