# MIDI I/O & Input Processing

**When to load:** routing MIDI from pads / knobs / USB, sending MIDI out, debugging echo / injection issues, or handling raw MIDI.

## Authoritative upstream
- `docs/API.md` (MIDI section)
  — https://github.com/charlesvestal/schwung/blob/main/docs/API.md
- `docs/MIDI_INJECTION.md` — echo filter, safety, 8-byte stride
- `docs/SPI_PROTOCOL.md` — 8-byte MIDI_IN event format
- Hardware CC/note constants: `src/shared/constants.mjs`

Optional private notes (may not exist on your machine):
`schwung-wiki/patterns/midi-handling.md`,
`schwung-wiki/patterns/enum-handling.md`,
`schwung-wiki/schwung-hardware-api-reference.md`.

## Cable routing

- **cable-0 (internal)** → `globalThis.onMidiMessageInternal(data)` — Move hardware: pads, knobs, buttons, jog, capacitive touch, Shift
- **cable-2 (external)** → `globalThis.onMidiMessageExternal(data)` — USB-A host port

Sending back out:
- `move_midi_internal_send([type, status, note, value])`
- `move_midi_external_send([cable, status, d1, d2])`
- `move_midi_inject_to_move([type, status, d1, d2])` — inject to Move firmware (e.g. for MIDI FX effects)

## Hardware map

| Input | Note / CC |
|---|---|
| Pads (32, 4×8 grid) | notes **68-99** |
| Sequencer steps (16) | notes **16-31** |
| Track buttons 1-4 | CC **43, 42, 41, 40** (reversed) |
| Jog click / turn | CC **3** / CC **14** (1-63 CW, 65-127 CCW) |
| Shift (held) | CC **49** = 127 |
| Menu / Back | CC **50** / **51** |
| Up / Down / Left / Right | CC **55** / **54** / **62** / **63** |
| Knobs 1-8 | CC **71-78** |
| Master volume | CC **79** (needs `claims_master_knob`) |
| Play / Record / Mute | CC **85** / **86** / **88** |
| Capacitive knob touch | notes **0-9** — filter unless `raw_midi` |

## Host-applied transforms (skipped only with `raw_midi: true`)

- Velocity curves (user setting: linear / soft / hard / full), read via `host_get_setting("velocity_curve")`
- Aftertouch enable + deadzone (`aftertouch_enabled`, `aftertouch_deadzone`)
- Capacitive-touch filter drops notes 0-9

`raw_midi` is **all or nothing** — there's no selective bypass. Use it only for modules that own the full input surface.

Always call `shouldFilterMessage(data)` at the top of `onMidiMessageInternal` if you're not raw — otherwise capacitive touches masquerade as notes.

## MIDI FX echo filter

MIDI FX modules emit via `process_midi` return / `tick` return. The host refcounts outgoing notes to prevent feedback loops through MIDI_OUT, but multi-pad chords can confuse the filter (documented open issue in `MIDI_INJECTION.md`). If you see stuck notes with chord triggers, that's the echo filter.

## Injection safety

MIDI_IN events written to the SPI mailbox are **8 bytes each** (USB-MIDI packet + 4-byte timestamp) — not 4 bytes. Writing 4-byte packets with 8-byte stride misaligns the ring buffer and triggers SIGABRT.

Rate limits:
- Safe: 4-8 injections per frame
- Danger: > 16 per tick → crash
- Overtake modules updating LEDs also share MIDI_OUT slots — budget ≤ 60 commands/frame total

## Knob delta decoding

Raw CC values on the jog wheel and knobs are:
- `1..63` = CW (positive delta)
- `65..127` = CCW (negative delta, as `value - 128`)
- `64` = no movement

Use `decodeDelta(value)` or `decodeAcceleratedDelta(value, 'knob1')` from `shared/input_filter.mjs` — don't decode by hand.

## MIDI file parsing inside DSP

See `references/dsp.md` "MIDI file parsing essentials" — variable-length delta times, running status, meta/SysEx skipping, 8 KB cap.

## Typical mistakes

- Forgetting `shouldFilterMessage()` → phantom notes from capacitive touches when the user just rests a hand on a knob
- Assuming `raw_midi` is selective — it kills the velocity curve too, which surprises people
- Overtake modules blowing the LED/MIDI_OUT budget (see `references/realtime.md` and `references/ui.md`)
- Writing MIDI_IN injection packets as 4 bytes
- Ignoring running status when parsing `.mid` files — half the notes silently go missing
