-- elementary cellular automata on a ring of cells.
--
-- cell i (1-based) is bit i-1 of the state. a cell's left neighbour is the
-- next higher bit, wrapping around, which is how less concepts reads its
-- seed: the same seed and rule give the same generations in both scripts.

local automaton = {}

local function mask(n) return (1 << n) - 1 end

-- the generation after `state`, under a wolfram `rule` (0-255)
function automaton.next(state, rule, n)
  n = n or 8
  local out = 0
  for i = 0, n - 1 do
    local l = (state >> ((i + 1) % n)) & 1
    local c = (state >> i) & 1
    local r = (state >> ((i - 1) % n)) & 1
    local neighbourhood = (l << 2) | (c << 1) | r
    out = out | (((rule >> neighbourhood) & 1) << i)
  end
  return out
end

-- the value of cell i (1-based, wrapping)
function automaton.cell(state, i, n)
  n = n or 8
  return (state >> ((i - 1) % n)) & 1
end

-- how many of the two cells around cell i are lit: 0, 1 or 2
function automaton.neighbours(state, i, n)
  return automaton.cell(state, i - 1, n) + automaton.cell(state, i + 1, n)
end

-- the state turned so that cell i is the lowest bit
function automaton.rotate(state, i, n)
  n = n or 8
  local s = (i - 1) % n
  if s == 0 then return state & mask(n) end
  return ((state >> s) | (state << (n - s))) & mask(n)
end

-- the bits of a byte in reverse order
function automaton.reverse8(b)
  local out = 0
  for i = 0, 7 do
    out = out | (((b >> i) & 1) << (7 - i))
  end
  return out
end

-- loom mode: a ring of `n` cells (8-16) grown from the 8-bit seed. the low
-- byte is the seed, the high byte the seed reversed and turned by the
-- voice's bit, so each bit gives a voice its own pattern from the same seed
function automaton.loom_ring(seed, bit, n)
  local high = automaton.rotate(automaton.reverse8(seed), bit, 8)
  return (seed | (high << 8)) & mask(n)
end

return automaton
