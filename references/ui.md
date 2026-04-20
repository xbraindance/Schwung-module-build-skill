# UI / Display / Menu System

**When to load:** writing or fixing anything that draws on the 128×64 display, handles encoders/pads/buttons, implements menus, or lives in `ui.js` / `ui_chain.js`.

## Authoritative upstream
- `docs/MODULES.md` (JavaScript UI, Menu System, Signal Chain UI Shims)
  — https://github.com/charlesvestal/schwung/blob/main/docs/MODULES.md
- `docs/API.md` (Display, Menu Layout Helpers)
- Reference UI modules: `src/modules/chain/ui.js`, `src/modules/store/ui.js`
- Shared helpers: `src/shared/menu_layout.mjs`, `menu_nav.mjs`, `input_filter.mjs`, `constants.mjs`

Optional private notes (may not exist on your machine):
`schwung-wiki/patterns/ui-patterns.md`,
`schwung-wiki/patterns/ui-hierarchy-patterns.md`,
`schwung-wiki/patterns/print-color-codes.md`,
`schwung-wiki/framework/ui-customization-options.md`,
`BD-1200/implementation/ui-rendering-architecture.md`.

## Entry points `ui.js` must export

```js
globalThis.init = function() { /* once after load */ }
globalThis.tick = function() { /* ~44 Hz — 128 frames @ 44.1 kHz */ }
globalThis.onMidiMessageInternal = function(data) { /* cable-0: pads, knobs, buttons */ }
globalThis.onMidiMessageExternal = function(data) { /* cable-2: USB-A device */ }
```

Clear the display in `init()` — otherwise you see stale pixels from the previous module.
Call `shouldFilterMessage(data)` at the top of `onMidiMessageInternal` to drop capacitive knob-touch (notes 0-9), unless you have `raw_midi: true`.

## Display (128 × 64, 1-bit monochrome)

Procedural API:

```js
clear_screen()
print(x, y, text, color)       // color: 0=black, 1=white, 2=invert
set_pixel(x, y, value)
draw_rect(x, y, w, h, value)   // outline
fill_rect(x, y, w, h, value)   // solid
text_width(text)               // → px width (monospace ~4.8 px/char)
host_flush_display()
host_set_refresh_rate(hz)      // effective cap ~11 Hz
```

Object API: `display.drawText(...)`, `display.fillRect(...)`, `display.drawLine(...)`, `display.flush()`.

### Layout zones (use these consistently)

```
y=0-11   Header   (title at x=2, y=2; separator line at y=11)
y=12-52  Content  (~5 lines × 8 px spacing, 2 px left/right margin, safe width ~100 px)
y=53-63  Footer   (status/help at y=54; separator at y=52)
```

Font is ~4.8 px/char → ~20-21 chars/line max. For safety use ≤ 18 chars; anything longer needs scrolling or truncation (see Bug 1 below).

## Hardware MIDI map (cable-0 / `onMidiMessageInternal`)

| Input | Note / CC |
|---|---|
| Pads (32, 4×8 grid) | notes **68-99** |
| Sequencer steps (16) | notes **16-31** |
| Track buttons 1-4 | CC **43, 42, 41, 40** (reversed) |
| Jog click | CC **3** |
| Jog turn | CC **14** (1-63 CW, 65-127 CCW) |
| Shift | CC **49** (127 while held) |
| Menu / Back | CC **50** / **51** |
| Up / Down / Left / Right | CC **55 / 54 / 62 / 63** |
| Knobs 1-8 | CC **71-78** |
| Master volume | CC **79** (needs `claims_master_knob`) |
| Play / Record / Mute | CC **85 / 86 / 88** |
| Capacitive knob touch | notes **0-9** — **always filter unless raw_midi** |

## Menu system

Use `menu_nav.mjs` for navigation dispatch — don't reimplement.

Item types: `SUBMENU` (lazy-evaluated via `getMenu()` factory), `VALUE` (needs `min`, `max`, `step`, `fineStep`), `ENUM`, `TOGGLE`, `ACTION`, `BACK`.

Helpers: `drawMenuHeader(...)`, `drawMenuList(...)`, `drawMenuFooter(...)`.

## Signal Chain UI (`ui_chain.js`)

When your module is used inside a chain, the host loads `ui_chain.js` **instead of** `ui.js`.

Export pattern:
```js
globalThis.chain_ui = {
  init() { /* once */ },
  tick() { /* inside chain UI frame */ },
  onMidiMessageInternal(data),
  onMidiMessageExternal(data)
}
```

**Do NOT override `globalThis.init` / `globalThis.tick` from `ui_chain.js`** — those belong to the chain host and overriding them breaks the chain.

MIDI delivered here has already been transformed by upstream chain modules.

## Shared utility modules (import, don't reimplement)

```js
import { shouldFilterMessage, decodeDelta, decodeAcceleratedDelta } from '../../shared/input_filter.mjs';
import { setLED, setButtonLED, clearAllLEDs,
         Black, DarkGrey, LightGrey, White,
         Red, Orange, Yellow, Green, Cyan, Blue, Purple, Pink,
         BrightRed, BrightGreen, BrightBlue, BrightWhite } from '../../shared/constants.mjs';
import { getMenuLabelScroller } from '../../shared/text_scroll.mjs';
import { openTextEntry, isTextEntryActive, handleTextEntryMidi,
         drawTextEntry, tickTextEntry } from '../../shared/text_entry.mjs';
import { menu_stack, MenuStack } from '../../shared/menu_stack.mjs';
import { FileBrowser } from '../../shared/filepath_browser.mjs';
import { installConsoleOverride } from '../../shared/logger.mjs';
```

Working examples of every pattern live in the upstream repo at `src/modules/` (controller, store, text-test, chord-flow, etc.).

## Six bugs that hit everyone

1. **Text truncates / overflows** — measure with `text_width()` and trim with `...` if > safe width.
2. **Menu items overlap** — line spacing must be **8 px**, not 6 px. `y = 15 + i*8`.
3. **Display frozen / stale** — missing `clear_screen()` at top of `tick()`. Also: jog the hardware wheel once to refresh the mirror at `http://move.local:7681`.
4. **Selection invisible** — use inverted highlight: `fill_rect(0, y-1, 128, 8, 1)` then `print(x, y, text, 0)`.
5. **Knob jumps by large steps** — decode delta with `decodeDelta(value)` or `decodeAcceleratedDelta(value, 'knob1')`; raw CC values 1-63 are CW, 65-127 are CCW.
6. **LEDs flicker / buffer overflow** — overtake modules have ≤~60 MIDI packets/frame. Init LEDs progressively (≤8/frame) across many ticks. See `references/realtime.md`.

## Performance

- Gate redraws behind a `needsRedraw` flag, flipped by input events. Redrawing every tick burns CPU for no benefit above ~11 Hz refresh.
- Measure text once in `init()`, not every `tick()`.
- Progressive LED init only matters for overtake modules; regular modules rarely saturate the MIDI buffer.
