# System Architecture & Bootstrap (reference / forking only)

**When to load:** forking Schwung, modifying the shim/host, changing shared-memory struct layout, or debugging cross-process issues. **Module authors rarely need this file** — if you're just building a module, skip.

## Authoritative upstream
- https://github.com/charlesvestal/schwung/tree/main/docs —
  `SPI_PROTOCOL.md`, `REALTIME_SAFETY.md`, `MIDI_INJECTION.md`,
  and any `LINK_AUDIO*` / `GAIN_STAGING*` files currently shipped.
- `CLAUDE.md` at repo root — Gain Staging and Link Audio sections.
- Source: `src/schwung_shim.c`, `src/host/module_manager.c`,
  `src/host/link_audio.h`, `src/host/link_subscriber.cpp`.

Optional private notes (may not exist on your machine):
`schwung-wiki/schwung-architecture-overview.md`,
`schwung-wiki/schwung-hardware-api-reference.md`.

## Four-layer bootstrap

1. **Install** — `install.sh` replaces `/opt/move/Move` with a shim entrypoint; Schwung assets copied to `/data/UserData/schwung/`. The original binary is renamed `MoveOriginal`.
2. **LD_PRELOAD shim** — intercepts `mmap()` (claims SPI mailbox address) and `ioctl()` (MIDI monitor + hotkey combo). Hotkey: Shift held + Volume knob touched + Jog encoder touched → spawns `shadow_ui`.
3. **Host runtime** — opens `/dev/ablspi0.0`, maps 4 KB SPI mailbox, embeds QuickJS, loads `menu_ui.js`.
4. **Module loading** — scans `/data/UserData/schwung/modules/<type>/`, parses `module.json` (8 KB cap, minimal JSON reader), `dlopen()`s DSP, resolves entry symbol by `component_type` — see `references/manifest.md` for the symbol table.

## SPI mailbox layout

- 4 KB shared region between host and hardware
- Audio TX at offset **256**: 512 frames interleaved int16 little-endian
- MIDI IN / OUT ring buffers: **8-byte** events (USB-MIDI packet + 4-byte timestamp) — note this is twice the naive size, see `references/midi.md` injection safety
- Callback fires every 2.9 ms at FIFO 90 on core 3; ~900 µs realistic work budget
- Display frames flushed via the same mailbox (rate-limits to ~11 Hz effective refresh)

## Struct layout safety (forks)

- `shadow_control_t` is **64 bytes** in shared memory across processes — **never shrink**. Add fields by consuming from the `reserved[]` tail.
- `ui_flags` (8 bits) is fully allocated upstream; fork extensions belong in `reserved16`.
- Layout changes that break alignment cause the shim and host to see different structures → hard crash or garbage data.
- Keep fork-only fields behind a clear comment block so upstream-merge diffs are readable.

## Link Audio (per-track capture)

As of the 2026-04 migration to the official `abl_link` audio C API,
reception is handled by a separate sidecar process, not by a shim hook:

- `src/host/link_subscriber.cpp` subscribes to Move's `1-MIDI…4-MIDI`
  and `Main` Link Audio channels and writes samples into a
  `/schwung-link-in` SPSC ring (5 slots).
- The shim (`schwung_shim.c`) is a **reader** of that SHM, not an
  interceptor. It feeds the shadow chain mixer from there.
- The sidecar also publishes shadow-slot output back to Live as `ME-N`
  channels via `/schwung-pub-audio` → `LinkAudioSink`s.
- Feature gate: `link_audio_enabled: true` in `features.json`.
- The earlier `sendto()` / `chnnlsv` UDP interception path was deleted
  in that migration — don't expect to find it in the current shim.

Design docs: upstream `docs/plans/2026-04-17-link-audio-official-api-migration.md`.

## Master FX gain staging (known issue)

Active Master FX applies to the combined Move + Schwung bus, so your module's output is attenuated differently than with Master FX bypassed. This is an architectural issue, not a module-level one — documented in `GAIN_STAGING_ANALYSIS.md`. Don't try to compensate at the module level; it'll break parity with FX-off.

## Build / fork merge hygiene

- Build script (`scripts/build.sh`) uses labelled sections — preserve them when merging
- After `git subtree pull` from upstream, verify no build targets were dropped; missing targets that call `unified_log()` will fail LTO linking against `unified_log.o`
- Keep fork-specific code in separate files or clearly blocked regions, not sprinkled across shared files
- Category extension (adding a new `component_type`): update `CATEGORIES` in `store_utils.mjs`, `install.sh`, and `build.sh` together — missing any one breaks discovery
- Shadow UI view system: create a `.mjs` file under `shared/views/`, import in `shadow_ui.js`, add a dispatch case. Use `enterView` callbacks to reset state on each entry — state leaks across module loads otherwise.

## When forking, read these plans

- `plans/2026-03-13-move-anything-2.0-architecture.md` — high-level architectural evolution
- `plans/2026-04-08-remote-ui-design.md` — param bridge, WebSocket protocol, module web UI
- `plans/2026-03-28-integrate-jack-and-rnbo-runner.md` — JACK shim, RNBO runner build
- `plans/2026-03-28-per-module-exit-hooks.md` — lifecycle callback pattern
- `plans/2026-03-30-jack-double-buffer.md` — realtime audio handoff pattern

## Mental model

The shim sits between the stock Move binary and the kernel, claiming the audio/MIDI/display surfaces and forwarding them to Schwung's host. Schwung never runs as a standalone process — it always co-exists with MoveOriginal, sharing the SPI mailbox and MIDI pipes. That's why scheduling matters so much (`references/realtime.md`) and why struct layout can't drift: two independent binaries have to agree on the shared memory format.
