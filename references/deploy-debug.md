# Deploy, Build & Debug

**When to load:** building the module, deploying to Move, watching logs, using the display mirror, enabling/disabling verbose logging, or debugging install-path mismatches.

## Authoritative upstream
- `docs/LOGGING.md` — unified logger, enable/disable, format
  — https://github.com/charlesvestal/schwung/blob/main/docs/LOGGING.md
- `BUILDING.md` — build system, cross-compilation
- `scripts/build.sh`, `scripts/install.sh` at the repo root

Optional private notes (may not exist on your machine):
`schwung-wiki/framework/deploy-patterns.md`,
`schwung-wiki/gotchas/deployment-path-gotchas.md`,
`schwung-wiki/gotchas/build-issues.md`,
`BD-1200/implementation/signal-chain-loading-gotchas.md`.

## Build

### Docker (reproducible, preferred)
```bash
docker build -t my-module-builder -f scripts/Dockerfile .
docker run --rm -v "$PWD:/build" -w /build my-module-builder ./scripts/build.sh
```

### Local macOS with Homebrew cross-toolchain
```bash
CROSS_PREFIX=aarch64-unknown-linux-gnu- ./scripts/build.sh
```

Output: `dist/<module>-module.tar.gz` containing `module.json`, `ui.js`, `dsp.so` (if native), `ui_chain.js` (if chainable), and any asset folders declared in `module.json`.

### Including asset folders in the tarball

Modules with user-uploadable assets need the build script to copy them:
```bash
if [ -d "src/custom_chords" ]; then
    mkdir -p "dist/$MODULE_ID/custom_chords"
    cp src/custom_chords/*.mid "dist/$MODULE_ID/custom_chords/" 2>/dev/null || true
fi
```

See `references/manifest.md` for the `assets` declaration.

## Deploy

```bash
scp dist/my-module-module.tar.gz ableton@move.local:/data/UserData/
ssh ableton@move.local 'tar -xzf /data/UserData/my-module-module.tar.gz \
  -C /data/UserData/schwung/modules/audio_fx/'
```

**Install path must match `component_type`** (see `references/manifest.md` table). Mismatch = module invisible.

| `component_type` | Extract into |
|---|---|
| `sound_generator` | `/data/UserData/schwung/modules/sound_generators/` |
| `audio_fx` | `.../modules/audio_fx/` |
| `midi_fx` | `.../modules/midi_fx/` |
| `utility` | `.../modules/utilities/` |
| `tool` | `.../modules/tools/` |
| `overtake` | `.../modules/overtake/` |

If the tarball has a wrapper folder, use `--strip-components=1` or rebuild flat.

## Reload

| Change | What to do |
|---|---|
| UI-only (`ui.js` / `ui_chain.js`) | `host_rescan_modules()` from shadow_ui, or reopen the picker |
| `module.json` | Rescan usually enough |
| DSP (`.so`) or any native code | **Full reboot** — `ssh root@move.local 'reboot'` |
| Cached wrong version showing up | `ssh ableton@move.local 'rm -rf /data/UserData/schwung/modules/<type>/<id>/'`, re-extract |

## Debug surfaces

- Display mirror — `http://move.local:7681` (live OLED view; jog the wheel once if it looks stale)
- Move Manager — `http://move.local:7700`
- Log file — `/data/UserData/schwung/debug.log`

## Enable / tail / clear logs

```bash
# Enable
ssh ableton@move.local 'touch /data/UserData/schwung/debug_log_on'

# Tail live
ssh ableton@move.local 'tail -f /data/UserData/schwung/debug.log'

# Disable (zero overhead when absent)
ssh ableton@move.local 'rm /data/UserData/schwung/debug_log_on'

# Truncate (log never auto-rotates — grows unbounded while enabled)
ssh ableton@move.local ': > /data/UserData/schwung/debug.log'
```

## Logging APIs

**JavaScript** (routes to `debug.log` automatically when enabled):
```js
console.log("my-module: init");
console.warn("...");
console.error("...");

// Or prefix automatically:
import { installConsoleOverride } from '../../shared/logger.mjs';
installConsoleOverride('my-module');   // now console.log prepends "[my-module]"
```

**C DSP**:
```c
#include "host/unified_log.h"
LOG_DEBUG("my-dsp", "cutoff=%f", inst->cutoff);
LOG_INFO("my-dsp", "preset loaded");
LOG_WARN("my-dsp", "...");
LOG_ERROR("my-dsp", "...");
```

Or use the `host->log(msg)` callback passed into `_init` / `create_instance`. Signature is single-arg `const char *` — for printf-style formatting use `snprintf` into a local buffer first, or use the `LOG_*` macros above. It is **not** realtime-safe — never call from `render_block` / `process_midi`. See `references/realtime.md`.

**Never** log from inside `render_block` / SPI callback path — that's the fastest way to cause audio dropouts.

## Verify deploy worked

```bash
# Check file landed
ssh ableton@move.local 'ls -la /data/UserData/schwung/modules/audio_fx/<id>/'

# Check .so exports the right symbol
ssh ableton@move.local \
  'nm -D /data/UserData/schwung/modules/audio_fx/<id>/dsp.so | grep -E "move_plugin_init_v2|move_audio_fx_init_v2|move_midi_fx_init"'

# Grep source for sanity
ssh ableton@move.local 'grep -n "some_unique_token" /data/UserData/schwung/modules/audio_fx/<id>/ui.js'
```

## Common fails

- Install path doesn't match `component_type` → module silently missing from picker
- `.so` not executable after tar extraction → `chmod +x dsp.so` or fix tarball perms on the build side
- Tarball has a wrapper folder → extract with `--strip-components=1` or rebuild flat
- UI edit not visible → try `host_rescan_modules()`, then full reboot; also check `mtime` on device matches local
- Changes to `.so` but no reboot → old DSP is still dlopen'd in the host
- Log file grew to gigabytes → truncate it
- Logging flag left on in production → disable when done (zero overhead when off)
