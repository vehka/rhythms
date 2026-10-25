# AGENTS.md

Notes for coding agents working on rhythms. User docs are in `README.md`; don't repeat them here.

## What it is

A monome norns script (Lua 5.3) and drum companion to less concepts (`../less-concepts`).
- An 8-bit elementary cellular automaton, the same `bang()` as less concepts, drives 4 lines of drum hits.
- Output goes to an Elektron Analog Rytm over MIDI and/or to nb voices.
- Grid 128 layout follows less concepts.

## Files

| file | what's in it |
|---|---|
| `rhythms.lua` (~900 lines) | everything else; sections below |
| `lib/automaton.lua` | `next(state, rule, n)`, `cell`, `neighbours`, `rotate`, `loom_ring` (pure, n-cell ring) |
| `lib/kit.lua` | Rytm track names (BD…CB, 1–12), GM drum notes for nb, default kits |
| `lib/out.lua` | Rytm MIDI out: trigger notes, tune CC with a change-only cache, note-off tracking, transport |
| `lib/snapshots.lua` | up to 16 snapshots (param id → value), PSET sidecar `<pset>.snapshots` |
| `lib/morph.lua` | morph engine: events at fractions of a length in beats; `step`, `flips`, `toggle` kinds |
| `tests/harness.lua` | offline stubs (params, clock, grid, midi, metro, screen) that run the real script |
| `tests/t_morph.lua` | morph test; also an example of driving grid keys and steps |

Don't read all of `rhythms.lua`. Grep for its section banners and read only the section you need:
`-- params ---`, `-- morph ---`, `-- grid ---`, `-- screen ---`, `-- keys and encoders ---`, `-- init and cleanup ---`.
The state, the sequencer (`hit`, `step_mode_tick`, `loom_tick`, `tick`, `run`) and the randomizers come before `-- params`.

## How it works

- **Params are the source of truth.** Most state is a param, with an action that updates derived state.
  - IDs are stable; don't rename them. Per-line IDs are `vp(v, name)` → `"v1_bit"`.
  - `params:bang()` runs near the end of `init`.
- **`tick()` order, once per step:**
  1. `out.release_due`
  2. `morph.tick`
  3. `cycle_check`
  4. step or loom tick
  5. `send_rytm_hits` (one hit per track per step, the louder wins)
  6. counters, and the loop reseed
- **`run()`** syncs to the next beat, then loops: swing sleep on odd steps, `tick()`, `clock.sync(step_beats())`.
- **Snapshots.**
  - They hold the ids from `snapshot_ids()`.
  - `wrap_for_writing` wraps those params' actions so that, while *cycle writes* is on, edits go into the selected snapshot.
  - Set `recalling = true` around any programmatic `params:set` that must not be written. Recall, the morph's `apply`/`finish` and the cycle do this.
- **Morph.**
  - `morph_to(n, i)` copies the snapshot and builds events from `morph_kinds()`.
  - `recall()` cancels a morph, and a cycle waits while a morph is active.
  - A new value in a snapshot that should glide needs an entry in `morph_kinds()`. Otherwise it jumps at the end.
- **UI.** A 30 fps `metro` redraws the screen and grid when `screen_dirty`/`grid_dirty` is set; call `dirty()`. Use a metro, not a clock: cancelling a clock has a core race ("bad argument #1 to 'resume'").
- **nb** is optional. `find_nb()` finds `nb/lib/nb` or a copy bundled in another script (`<script>/lib/nb/lib/nb`). nb params are only added when nb is found, so group sizes depend on it.

## Analog Rytm MIDI facts

- **Verified on hardware (MKII, 2026-10-25):**
  - Notes 0–11 trigger tracks 1–12 (BD…CB); the tracks must be on their default channels 1–12.
  - Notes 12–59 play the active track chromatically. Note 60 and above do nothing.
  - Tune is CC 17 on the track's channel, 64 + semitones, one CC step per semitone. The CC sets the tune rather than adding to it, and the change stays in the Rytm's kit.
- **Unverified:** the other CC numbers in `out.lua`/README come from a third-party Cirklon instrument file. Check them against the MKII manual's Appendix C before relying on them.

## Testing

1. **Syntax:** `luac -p rhythms.lua lib/*.lua`.
2. **Offline:** `lua5.3 tests/t_morph.lua`.
   - It needs norns' `lua/lib` (`$NORNS` or `~/norns`).
   - Add tests in the same style: `H.key(x, y)` presses a grid key, `H.play()` starts the sequencer, `H.step()` plays one step, `METRO.event()` redraws, and `SENT` collects MIDI.
   - Not covered: nb, audio, real timing, matron bindings.
3. **norns-desktop:** run `norns-desktop` (logs in `~/norns.log`).
   - The REPL is the noseda skill's `scripts/nrepl.py`. It needs `websocket-client` in a venv.
   - The REPL runs each line as its own chunk, so send one-line Lua.
   - The desktop needs the built-in sound card's profile on (crone fails with "connectAdcPorts() failed" otherwise).
   - The virtual grid is on grid port 1.
4. **Shield (norns hardware):** `we@10.0.0.138`, REPL with `nrepl.py --host 10.0.0.138`.
   - Deploy: `rsync -a --exclude .git ./ we@10.0.0.138:dust/code/rhythms/`. It's a copy, not a link.
   - The shield's wifi sleeps: if you get "No route to host", wake it and retry.
   - Reloading the script there drops unsaved snapshots, so ask first.
   - To see what goes out to MIDI, wrap `midi.vports[1].device.send`; vport `note_on` bypasses the vport's `send`. Restore the original after.

## Conventions

- **Comments and README:** plain lowercase prose, as in less concepts. Explain the musical behaviour, not the code.
- **Script header:** keep it in sync with the grid and controls. Bump `-- vX.Y.Z` on features.
- **README:** document each user-facing change.
- **Git:**
  - Commit only when asked. Use separate commits for separate changes.
  - Author: `vehka <vehka@iki.fi>` (set in the repo config).
  - Remote: `git@github-vehka:vehka/rhythms`. For `gh`, switch to the `vehka` account first.
  - No AI or Claude attribution in commit messages.
- **Rytm features:** the device integration is planned as a separate mod in `../elektronorns` (see its `PLAN.md`). Keep rhythms' `lib/out.lua` small; it should later play through that mod's nb players.

## Roadmap (not built)

- shadow hits: flam, ghost, echo, hocket
- ratchet weights
- form: sections with fills
- LFOs, including a pitch LFO
- 64-grid support
- a rule density encoder
