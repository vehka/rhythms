-- snapshots: up to 16 sets of the pattern params, kept with the pset in a
-- file of their own (<pset>.snapshots), as in less concepts.

local snapshots = {}

snapshots.MAX = 16
snapshots.list = {}   -- each a table of param id -> value
snapshots.selected = 0

local SCHEMA = 1
local ids = {}

-- the params a snapshot holds
function snapshots.set_ids(list) ids = list end
function snapshots.holds(id)
  for _, i in ipairs(ids) do if i == id then return true end end
  return false
end

function snapshots.count() return #snapshots.list end

local function take()
  local s = {}
  for _, id in ipairs(ids) do s[id] = params:get(id) end
  return s
end

-- a new snapshot of the params as they are, at the end
function snapshots.add()
  if #snapshots.list >= snapshots.MAX then return nil end
  table.insert(snapshots.list, take())
  snapshots.selected = #snapshots.list
  return snapshots.selected
end

-- set the params to snapshot n
function snapshots.recall(n)
  local s = snapshots.list[n]
  if not s then return false end
  snapshots.selected = n
  for _, id in ipairs(ids) do
    if s[id] ~= nil then params:set(id, s[id]) end
  end
  return true
end

-- write one value into the selected snapshot (while a cycle writes)
function snapshots.write(id, value)
  local s = snapshots.list[snapshots.selected]
  if s then s[id] = value end
end

function snapshots.remove(n)
  if not snapshots.list[n] then return end
  table.remove(snapshots.list, n)
  if snapshots.selected > #snapshots.list then
    snapshots.selected = #snapshots.list
  end
end

function snapshots.clear()
  snapshots.list = {}
  snapshots.selected = 0
end

-- pset hooks
function snapshots.save(filename)
  local err = tab.save({schema = SCHEMA, list = snapshots.list,
    selected = snapshots.selected}, filename .. ".snapshots")
  if err then print("rhythms: snapshots not saved: " .. err) end
end

function snapshots.load(filename)
  local ok, saved = pcall(tab.load, filename .. ".snapshots")
  if ok and type(saved) == "table" and saved.schema == SCHEMA
      and type(saved.list) == "table" then
    snapshots.list = {}
    for i = 1, math.min(#saved.list, snapshots.MAX) do
      if type(saved.list[i]) == "table" then
        table.insert(snapshots.list, saved.list[i])
      end
    end
    snapshots.selected = util.clamp(saved.selected or 0, 0, #snapshots.list)
  else
    snapshots.clear()
  end
end

function snapshots.delete(filename)
  os.remove(filename .. ".snapshots")
end

return snapshots
