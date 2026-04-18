# Host Functions & Module Lifecycle

**When to load:** calling into the host from `ui.js` (`host_*` functions), doing file I/O, recording, TTS, controlling modules, or implementing lifecycle hooks.

## Wiki first
- `schwung-wiki/framework/api-entry-points.md` — JS entry symbols, host callbacks
- `schwung-wiki/patterns/state-serialization.md` — `host_module_get/set_param`, UI↔DSP round-trip
- `schwung-wiki/gotchas/device-constraints.md` — filesystem layout, `/tmp` trap

Authoritative: `schwung-main/docs/API.md` (Host Functions, Module Management, File System Utilities, Sampler, Screen Reader, System Commands).

## Filesystem rule (load-bearing)

| Path | Status | Use? |
|---|---|---|
| `/` rootfs | ~463 MB, **almost always 100 % full** | NO — writes fill disk and crash the device |
| `/tmp` | mapped to rootfs | **NEVER WRITE** |
| `/opt/move/` | read-only firmware | read-only |
| `/data/UserData/` | ~49 GB writable | YES — all persistent data, modules, logs |

Always build paths from `module_dir` (DSP) or `/data/UserData/schwung/...` (UI). Never hardcode `/tmp`.

## Module management

```js
host_list_modules()                  // → [{id, name, version, component_type}, …]
host_load_module(id_or_index)
host_load_ui_module(path)            // UI-only (DSP skipped)
host_unload_module()
host_return_to_menu()                // go back to host menu (any module)
host_exit_module()                   // TOOL MODULES ONLY — crashes elsewhere
host_is_module_loaded()              // → boolean
host_get_current_module()            // → {id, name, …}
host_rescan_modules()                // refresh picker; 100+ ms, call from idle
host_module_send_midi(msg, source)   // inject MIDI into the loaded module
```

## Parameter bridge to DSP

```js
host_module_set_param(key, value)    // → DSP set_param(key, val)
host_module_get_param(key)           // → string from DSP get_param(key)
host_module_get_error()              // call after each op to detect failure
```

Everything is stringly-typed — parse in the UI if you need numbers/booleans. Silent failures are common; check `host_module_get_error()` after each write.

## Display

```js
clear_screen(); print(x,y,text,color); set_pixel; draw_rect; fill_rect; text_width
host_flush_display()
host_set_refresh_rate(hz)            // effective cap ~11 Hz
host_get_refresh_rate()
```

See `references/ui.md` for layout + colors.

## Settings

```js
host_get_setting(key)                // velocity_curve, aftertouch_enabled, aftertouch_deadzone
host_set_setting(key, val)
host_save_settings()                 // persist
host_reload_settings()
host_get_volume() / host_set_volume(v)   // 0–100
```

## File I/O

Always under `/data/UserData/`:
```js
host_file_exists(path)
host_read_file(path)                 // → string or null
host_write_file(path, content)       // → boolean
host_ensure_dir(path)                // mkdir -p
host_remove_dir(path)                // rm -rf
host_http_download(url, dest)
host_extract_tar(tarball, dir)
host_extract_tar_strip(tarball, dir, strip)   // --strip-components
```

File operations block briefly — never inside a tight `tick()` loop. For DSP-side file I/O see `references/dsp.md`.

## Sampler / TTS / system

```js
host_sampler_start(path)             // start recording WAV
host_sampler_stop()
host_sampler_is_recording()          // → boolean

host_announce_screenreader(text)     // TTS via Flite; ~200 ms onset, 4 s ring buffer

host_system_cmd("cmd")               // allowlisted; shadow_ui context only, not RT
```

## MIDI out from UI

```js
move_midi_internal_send([type, status, note, value])
move_midi_external_send([cable, status, d1, d2])
move_midi_inject_to_move([type, status, d1, d2])
```

See `references/midi.md` for cable routing, rate limits, and the 8-byte injection format gotcha.

## LEDs

```js
import { setLED, setButtonLED, clearAllLEDs,
         Black, DarkGrey, LightGrey, White,
         Red, Orange, Yellow, Green, Cyan, Blue, Purple, Pink,
         BrightRed, BrightGreen, BrightBlue, BrightWhite } from '../../shared/constants.mjs';
setLED(note, color);      // pad LEDs (notes 68-99, steps 16-31)
setButtonLED(cc, color);  // button LEDs (CC-addressed)
clearAllLEDs();
```

Overtake modules must init LEDs progressively (≤ 8/frame) to avoid MIDI buffer overflow — see `references/realtime.md`.

## Lifecycle rules

- `init()` runs once after load. Clear the display, pre-measure text, set up state.
- `tick()` runs at ~44 Hz while the module is active.
- Unload is asynchronous — don't assume `tick()` stops on the same frame as `host_unload_module()`.
- `host_exit_module()` is **only dynamically bound for tool modules**; calling it elsewhere crashes the host.
- `host_rescan_modules()` is not free (~100 ms) — call from idle input, never every tick.
- Per-module exit hooks: `schwung-main/docs/plans/2026-03-28-per-module-exit-hooks.md`.

## Common mistakes

- Forgetting `host_module_get_error()` after a param set — silent failure, UI and DSP diverge
- Writing to `/tmp` instead of `/data/UserData/`
- Calling `host_exit_module()` from a non-tool module
- `host_rescan_modules()` from `tick()` — audible judder
- Storing the `host_api_v1_t*` pointer globally in the DSP (see `references/dsp.md` host lifecycle)
