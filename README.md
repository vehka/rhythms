# rhythms

*a companion to [less concepts](https://llllllll.co/t/less-concepts-3/): four lines of drum hits from the same kind of cellular automaton, for the elektron analog rytm and nb voices.*

less concepts reads the bits of a cellular automaton as notes. rhythms reads them as hits: a seed (0-255) and a rule (0-255) make a new generation of 8 cells each step, and each of the four lines plays when the cell of its bit is lit. a seed and rule give the same generations in both scripts, though the two don't share them: run on two norns, each has its own seeds and snapshots, and they only share the clock.

## lines

each line has a **bit** (or mute), a **tune**, a **gate probability**, and plays one of two ways (*plays* in the line's params):

- **kit**: the line plays a kit of four slots, each a rytm track. the generation, read from the line's bit, picks the slot, so each line picks differently from the same seed. a track in two slots is picked twice as often. the default kits are, low to high: BD BD LT BT, SD SD RS CP, CH CH OH CY, MT HT CB RS. on the grid, row 5 shows the four kits, four keys each: press a slot to leave it out of the kit, and again to bring it back. a kit with every slot left out is silent.
- **single**: the line plays one sound: a rytm track (*single: track*), or an nb voice at *single: nb note*.

two lines that hit the same track in one step make one hit, the louder of the two.

**tune** moves the hits up or down by up to 3 steps of *tune step* semitones (2 by default). on the rytm it goes out as the synth tune cc (cc 17) on the track's channel, see *tune via*. kit lines on nb play the general midi drum note of each track and aren't tuned.

## accents

a hit's velocity comes from the cells around the one that played (*dynamics* group):

- **crowd**: a hit with both neighbours lit is an accent, with neither a ghost note, with one a normal hit.
- **lone**: the other way round: lone hits stand out.
- **off**: every hit at the normal velocity.

the three velocities are set in the group.

## step and loom

*automaton*, or (7,6) on the grid:

- **step** (as in less concepts): one generation per step. the screen shows the generations played, newest on top, the cells that played bright.
- **loom** (an experiment): each line has a ring of 8 to 16 cells (*loom length*) that is a bar of steps, grown from the seed and the line's bit. the rule grows the next bar from this one every *loom bars per gen* bars. some rules settle into a loop or a fixed bar, others make a new bar every time, so a few bars per generation is a good start. the screen shows the four rings with the step that plays.

## time

- **time**: 1/8 to 1/32, as in less concepts. on the grid (2,8) to (4,8).
- **loop**: plants the seed again every 4 to 64 steps, for a repeating pattern. off, the automaton runs on.
- **swing**: every other step is late, 50% is straight.
- play starts from the seed on the next beat. (8,6) plants the seed again while it plays.

## snapshots

up to 16, as in less concepts: (16,6) or key 2 takes one, (9,7) to (16,8) recall one, and the automaton starts over from its seed. a snapshot holds the seed, rule, automaton, loom settings, time, loop and, for each line, the bit, tune, gate probability and the slots left out of the kit. the snapshots are saved with the pset, in a file next to it.

**cycle**: (9,6), (10,6) and (11,6) go through the snapshots down, at random or up, every *cycle length* beats. press the lit one again to stop. hold one to make the cycle write: edits then go into the snapshot that plays (it blinks), like the destructive cycle of less concepts. holding a snapshot key holds the cycle.

## morph

a snapshot can be reached slowly, instead of at once, as in less concepts: press one of the morph keys at (7,8) and (8,8), and it blinks, armed. then press a snapshot to start the morph. pressing the armed key again disarms it, and the other key arms its morph instead.

on the way, the bits, tunes and gate probabilities of the lines step from where they are to the snapshot's, spread evenly over the morph. the rule changes a bit at a time, in a random order, so the pattern drifts from one rule to the other. each kit slot the snapshot leaves out or brings back changes at a random point of the morph, so a kit changes a sound at a time. at the end the seed starts over from the snapshot's, and its automaton, loom settings, time and loop come in, as when the snapshot is pressed on its own.

the two morphs have their own length, from 1/4 bar to 32 bars (*morph* group), 1 bar and 4 bars by default. the snapshot blinks while the morph moves to it, faster as it nears the end, and the screen shows how far it has got. a morph counts the beats played, so it stands still while rhythms is stopped. pressing a snapshot on its own stops a morph. a cycle waits while a morph plays, and goes on a cycle length after it ends; a cycle that writes doesn't write the values on the way into its snapshot.

## rytm setup

in *rytm & midi*:

each track is triggered by its own note, BD on note 0 (C0) to CB on note 11 (B0), as the rytm expects (manual, appendix c.8). the rytm's tracks need their default channels 1-12 for these notes to trigger them.

- **rytm notes: track channels** sends each track's note on its own channel, BD on *BD track channel* and the others after it (1-12 by default).
- **rytm notes: auto channel** sends every track's note on the auto channel.
- **tune via synth tune cc** sends cc 17 on the track's channel when its tune changes, 64 being the sound's own tune. a track that is never tuned is never sent the cc.
- **send start/stop** starts and stops the rytm with rhythms. to run two norns together, set both to the same clock source (link, or midi clock from one to the other).

to check on the rytm: the cc 17 scale (how far one step moves the tune), and the other cc numbers, which come from a third party instrument definition, not the manual.

## nb

with [nb](https://github.com/sixolet/nb) installed, each line gets an *nb voice*, and *output* chooses rytm, nb or both. without nb, a line set to nb is silent.

## grid (128)

```
(1,1)-(8,4)    bits, a row per line          (9,y)  mute the line
(10,1)-(16,4)  tune -3 ... +3
(1,5)-(16,5)   the four kits, four slots each: press to leave a sound out
(1,6) seed  (2,6) rule  (3,6) bits  (4,6) tunes  (5,6) time  (6,6) all: randomize
(7,6) step / loom   (8,6) plant the seed
(9,6)-(11,6) cycle < ~ >, hold to write     (14,6) clear all, (15,6) clear selected: hold
(16,6) take snapshot   (9,7)-(16,8) snapshots
(1,8) play/stop   (2,8)-(4,8) time - / 1/16 / +   (7,8) (8,8) morph 1, 2
```

## screen

enc 1 picks a line of the screen. on *seed/rule*, *time*, *feel* (swing, accents) and *cycle* enc 2 and 3 change the left and right side; on *bits*, *tune* and *gate* enc 2 picks a line and enc 3 changes it. key 3 randomizes what is picked; key 2 takes a snapshot, or recalls the one picked on *snapshots*; key 2 held and key 3 deletes it.

## to come

shadow hits (flam, ghost, echo, hocket), ratchets, a form of sections with fills, lfos, a 64 grid.
