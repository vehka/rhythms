-- the twelve tracks of the analog rytm, in its own order, with a general
-- midi drum note for each, for nb voices and other drum machines

local kit = {}

kit.names = {"BD", "SD", "RS", "CP", "BT", "LT", "MT", "HT", "CH", "OH", "CY", "CB"}

kit.long_names = {
  "bass drum", "snare", "rim shot", "clap", "bass tom", "low tom",
  "mid tom", "high tom", "closed hat", "open hat", "cymbal", "cowbell",
}

kit.gm_notes = {36, 38, 37, 39, 41, 43, 47, 50, 42, 46, 49, 56}

-- what each line plays by default in a kit: a doubled track is picked more
-- often. the four lines, low to high: kick and toms, snare, hats, percussion
kit.default_slots = {
  {1, 1, 6, 5},
  {2, 2, 3, 4},
  {9, 9, 10, 11},
  {7, 8, 12, 3},
}

-- the track a line plays when it plays a single sound
kit.default_single = {1, 2, 9, 4}

return kit
