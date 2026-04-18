# Realtime Safety & Performance

**When to load:** diagnosing audio dropouts/glitches, writing code that runs inside `render_block` / `process_midi` / SPI callback path, spawning child processes, or pinning CPU-heavy modules.

## Wiki first
- `schwung-wiki/gotchas/device-constraints.md` — LED buffer, block size, `/tmp` trap
- `schwung-wiki/features/` — audio perf write-ups

Authoritative: `schwung-main/docs/REALTIME_SAFETY.md`, `SPI_PROTOCOL.md` (rate limiting, implementation notes), plus the plans `2026-03-28-integrate-jack-and-rnbo-runner.md` and `2026-03-30-jack-double-buffer.md`.

## Budget

| | |
|---|---|
| Audio block | 128 frames @ 44 100 Hz = **~2.9 ms** |
| SPI callback budget | **~900 µs** after display + MIDI overhead |
| Overrun symptom | Audible clicks, dropouts, `[WARN]` in logs |

## Forbidden inside `render_block` / `process_midi` / SPI callback

- `fprintf`, `fopen`, any file I/O — 78 ms spikes observed
- `unified_log()` — calls `fprintf + fflush`; route logs through the host callback instead
- `malloc` / `new` (pre-allocate in `create_instance`)
- `host_system_cmd()`
- More than ~16 MIDI injections per tick → SIGABRT
- String formatting into large buffers

`host->log("fmt", …)` is lock-free-ish via snapshot + background drain, but still ~1 ms per call — never log in an inner sample loop.

## Scheduling

- SPI thread runs at **FIFO 90 on core 3**
- Child processes inherit **FIFO 70 from MoveOriginal** — they will preempt SPI on other cores unless they reset
- **Reset before `exec`**: `sched_setscheduler(0, SCHED_OTHER, &(struct sched_param){0})`. The `shadow_process.c` wrapper does this.
- Symptom of forgotten reset: random audio glitches whenever the child runs

## CPU pinning for heavy modules

- Compute-heavy modules (e.g. RNBO runner) should be pinned to **cores 0-2** with `taskset 0x7` to avoid contending with SPI on core 3
- RNBO specifically: also pin internal threads at frame 50 after spawn — see `plans/2026-03-28-integrate-jack-and-rnbo-runner.md`

## JACK / audio bridge

The `bridge_read_audio` double-buffer pattern (`plans/2026-03-30-jack-double-buffer.md`) returns a snapshot **without waiting** — this eliminated a 0.34 % miss rate observed in the earlier blocking implementation. Use the same pattern for any cross-thread audio handoff.

## MIDI / LED budgets

| Channel | Safe rate | Danger |
|---|---|---|
| MIDI_IN injection | 4-8 events/frame | > 16/tick → SIGABRT |
| MIDI_OUT (all commands) | ≤ 60 commands/frame | Buffer overflow, flickering LEDs |
| LED init (overtake) | ≤ 8 LEDs/frame | Buffer overflow |

### Progressive LED init pattern

```js
const LEDS_PER_FRAME = 8;
let ledIndex = 0, ledPending = true;
const ALL = [{note: 68, color: White}, /* … */];

globalThis.tick = function() {
  if (ledPending) {
    const end = Math.min(ledIndex + LEDS_PER_FRAME, ALL.length);
    for (let i = ledIndex; i < end; i++) setLED(ALL[i].note, ALL[i].color);
    ledIndex = end;
    if (ledIndex >= ALL.length) ledPending = false;
  }
  drawUI();
};
```

## Glitch triage workflow

1. Enable logging (`references/deploy-debug.md`) and watch for `[WARN]` on SPI budget overruns
2. `ssh ableton@move.local top -H` — any threads on core 3 that aren't SPI?
3. `chrt -p <pid>` on your module's children — confirm `SCHED_OTHER`
4. Bisect: disable your recent changes one by one; last-touched DSP path is almost always it
5. Grep the DSP for stray `fprintf`, `fopen`, `malloc` inside `render_block`
6. If the module does MIDI injection, count events per tick — you may be at the edge of the 16-event ceiling when chords hit

## Quick mental model

The SPI callback is a metronome that must finish in ~900 µs every 2.9 ms, forever. Your DSP has to fit inside that beat. Anything that blocks — file I/O, logging, waiting on a mutex, GC-triggering allocation — steals from the whole device. Audio dropouts are almost always someone else borrowing the beat.
