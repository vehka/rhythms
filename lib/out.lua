-- the hits go out here: to the analog rytm over midi, and to nb players.
--
-- a rytm hit is the track's trigger note, 0 (BD) to 11 (CB), on the
-- track's channel (track channels) or on the auto channel. the rytm only
-- triggers tracks with these notes (manual, appendix c.8): notes 12-59 play
-- the active track chromatically, and higher notes do nothing. the tune
-- goes as the synth tune cc. each note is ended after a step,
-- on the port and channel it was sent on, so a change of device or channel
-- never leaves a note hanging.

local kit = include('lib/kit')

local out = {}

out.port = nil      -- the midi vport, set by the midi device param
local sounding = {} -- notes that are on: {port, ch, note, off}

-- the param ids this module reads
local P = {
  mode = "rytm_mode",         -- 1 track channels, 2 auto channel
  base = "rytm_base_ch",      -- channel of track 1 (BD) with track channels
  auto = "rytm_auto_ch",
  tune = "rytm_tune_via",     -- 1 synth tune cc, 2 off
}

local TUNE_CC = 17          -- the rytm's synth tune, 64 is no change

local function track_channel(track)
  local ch = params:get(P.base) + track - 1
  if ch > 16 then return nil end
  return ch
end

local function end_sounding(i)
  local s = sounding[i]
  s.port:note_off(s.note, 0, s.ch)
  table.remove(sounding, i)
end

-- end the notes whose step has come
function out.release_due(step)
  for i = #sounding, 1, -1 do
    if step >= sounding[i].off then end_sounding(i) end
  end
end

function out.all_off()
  for i = #sounding, 1, -1 do end_sounding(i) end
end

local function note_on(ch, note, vel, off)
  -- a note that sounds already is ended first, so its note off can't cut
  -- the new one short
  for i = #sounding, 1, -1 do
    local s = sounding[i]
    if s.port == out.port and s.ch == ch and s.note == note then
      end_sounding(i)
    end
  end
  out.port:note_on(note, vel, ch)
  table.insert(sounding, {port = out.port, ch = ch, note = note, off = off})
end

-- the synth tune cc last sent on each channel. 64 is the sound's own tune,
-- and is what a track has until it is moved, so a line that never tunes
-- never touches the knob
local tune_sent = {}

local function send_tune(ch, semis)
  local value = util.clamp(64 + semis, 0, 127)
  if (tune_sent[ch] or 64) ~= value then
    out.port:cc(TUNE_CC, value, ch)
    tune_sent[ch] = value
  end
end

-- a new device or channel: nothing has been tuned there yet
function out.forget_tune() tune_sent = {} end

-- a hit on a rytm track (1-12), `semis` from its own pitch
function out.rytm(track, semis, vel, off)
  if not out.port then return end
  local ch_track = track_channel(track)
  if params:get(P.tune) == 1 and ch_track then send_tune(ch_track, semis) end
  local note = track - 1
  if params:get(P.mode) == 1 then
    if ch_track then note_on(ch_track, note, vel, off) end
  else
    note_on(params:get(P.auto), note, vel, off)
  end
end

-- a hit on an nb player. `beats` is the length of the note
function out.nb(player, note, vel, beats)
  if player then
    player:play_note(util.clamp(note, 0, 127), vel / 127, beats)
  end
end

function out.gm_note(track) return kit.gm_notes[track] end

function out.transport(start)
  if not out.port then return end
  if start then out.port:start() else out.port:stop() end
end

return out
