# Signal Chain Integration

**When to load:** making a module chainable, exposing `chain_params` or `ui_hierarchy`, writing `ui_chain.js`, or debugging "my module doesn't appear in the chain picker" / "knob doesn't map to my param".

## Authoritative upstream
- `docs/MODULES.md` → Chain Parameters, Signal Chain UI Shims, Shadow UI Parameter Hierarchy
  — https://github.com/charlesvestal/schwung/blob/main/docs/MODULES.md
- Chain host: `src/modules/chain/dsp/chain_host.c`, `src/modules/chain/ui.js`
- Reference chainable DSP: `src/modules/audio_fx/freeverb/freeverb.c` + `ui_chain.js`

Optional private notes (may not exist on your machine):
`schwung-wiki/framework/signal-chain-integration.md`,
`schwung-wiki/gotchas/module-loading-failures.md`,
`BD-1200/implementation/bd1200-signal-chain.md`.

## Making a module chainable

Declare `chainable: true` inside `capabilities`:

```json
{
  "capabilities": {
    "chainable": true,
    "component_type": "audio_fx"
  }
}
```

This is the only location the chain UI reads (`src/modules/chain/ui.js` checks `mod.capabilities.chainable`). A top-level `chainable` field is ignored. Every built-in chainable module (freeverb, chord, arp, velocity_scale, linein) uses only the nested form.

## `chain_params` — the DSP-side knob map

Return from `get_param("chain_params")` as a JSON **array**. Do NOT put this in `module.json` — the minimal JSON parser there chokes on nested arrays.

```c
if (strcmp(key, "chain_params") == 0) {
    const char *json =
      "["
        "{\"key\":\"cutoff\",\"name\":\"Cutoff\",\"type\":\"float\",\"min\":0,\"max\":1,\"step\":0.01},"
        "{\"key\":\"mode\",\"name\":\"Mode\",\"type\":\"enum\",\"options\":[\"LP\",\"HP\",\"BP\"]}"
      "]";
    strncpy(buf, json, buf_len - 1);
    return strlen(json);
}
```

Types: `float`, `int`, `enum`. Keys **must** match `set_param`/`get_param` keys exactly — any mismatch and the knob silently sets nothing.

## `ui_hierarchy` — Shadow UI nested menus

Return from `get_param("ui_hierarchy")`. Can be stateful — return different structure based on current mode to show/hide items.

```c
if (strcmp(key, "ui_hierarchy") == 0) {
    const char *json =
      "{\"levels\":{"
        "\"root\":{"
          "\"name\":\"My Synth\","
          "\"knobs\":[\"cutoff\",\"resonance\"],"
          "\"params\":["
            "{\"key\":\"cutoff\",\"name\":\"Cutoff\"},"
            "{\"level\":\"advanced\",\"name\":\"Advanced\"}"
          "]"
        "},"
        "\"advanced\":{"
          "\"name\":\"Advanced\","
          "\"knobs\":[\"drive\"],"
          "\"params\":[{\"key\":\"drive\",\"name\":\"Drive\"}]"
        "]"
      "}}";
    strncpy(buf, json, buf_len - 1);
    return strlen(json);
}
```

`abbrev` in `module.json` (3-6 chars) is what Shadow UI shows in the slot view — keep it short or it truncates.

## `ui_chain.js` — the chain-mode UI file

When your module is used **inside** a chain, the host loads `ui_chain.js` instead of `ui.js`.

```js
globalThis.chain_ui = {
  init()  { /* once */ },
  tick()  { /* inside the chain UI frame */ },
  onMidiMessageInternal(data),
  onMidiMessageExternal(data)
};
```

**Do not override `globalThis.init` / `globalThis.tick` from this file** — those belong to the chain host, and overriding them breaks every other module in the chain.

MIDI delivered to `onMidiMessageInternal` in chain context has already passed through upstream chain modules (e.g., an arpeggiator ahead of you).

## MIDI FX chain specifics

- MIDI FX output is routed back through MIDI_OUT with refcounts to prevent loops
- Multi-pad chord triggers can confuse the echo filter (documented open issue in `MIDI_INJECTION.md`)
- See `references/midi.md` for the broader MIDI story

## Preset save/load with custom values

If your chain params include enum values that the user added at runtime (custom chords, loaded samples), store them as **strings** in presets — not indices. See `references/dsp.md` "Preset save/load".

## Debug checklist when something's wrong

| Symptom | Likely cause |
|---|---|
| Module missing from chain picker | `chainable` missing inside `capabilities`, or `component_type` in capabilities doesn't match a chain slot type |
| Knob doesn't map / does nothing | `chain_params` key doesn't exactly match `set_param` key |
| `ui.js` behaviour shows up in chain (wrong UI) | You forgot `ui_chain.js`, or overrode `globalThis.init` in it |
| Abbrev truncated in slot view | `abbrev` > 6 chars |
| Module loads but chain params don't populate | `get_param("chain_params")` returns empty / malformed JSON — log the string and validate |
| Module works solo but breaks in chain | MIDI arrives pre-transformed; you assumed raw hardware values |
