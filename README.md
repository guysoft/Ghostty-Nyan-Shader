# Ghostty Nyan Shader

A custom cursor shader for [Ghostty](https://ghostty.org) that turns your text cursor into 🌈 **Nyan Cat** 🐱 with a 6-stripe rainbow trail whenever it jumps.

The cat itself is drawn entirely procedurally with signed distance fields — no image textures (Ghostty's `custom-shader` doesn't expose any sampler other than the terminal contents). At the size of one terminal cell it reads as a tiny pop-tart with a grey cat head poking out and two wiggling legs. The rainbow is what really sells it.

## Behavior

- **Idle**: normal Ghostty block cursor. No nyan.
- **Cursor jumps** (arrow keys, `Ctrl+A`/`Ctrl+E`, mouse click, scrolling, etc.): nyan flies in at the new cursor position with a rainbow streak connecting old → new, plus a few shimmer stars trailing behind.
- **After ~0.5 s of stillness**: nyan fades out, default cursor returns.

The legs wiggle continuously while nyan is visible (`sin(iTime * 14)`).

## Requirements

- **Ghostty ≥ 1.0** (anything that supports `custom-shader`, `iCurrentCursor`, `iPreviousCursor`, `iTimeCursorChange`).
- macOS, Linux — anywhere Ghostty itself runs. The shader is plain GLSL/Shadertoy syntax with no platform-specific bits.

## Install

1. Drop the shader file somewhere Ghostty can read:

   **macOS:**
   ```sh
   mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty/shaders"
   curl -fsSL https://raw.githubusercontent.com/guysoft/Ghostty-Nyan-Shader/main/shaders/nyan.glsl \
     -o "$HOME/Library/Application Support/com.mitchellh.ghostty/shaders/nyan.glsl"
   ```

   **Linux:**
   ```sh
   mkdir -p "$HOME/.config/ghostty/shaders"
   curl -fsSL https://raw.githubusercontent.com/guysoft/Ghostty-Nyan-Shader/main/shaders/nyan.glsl \
     -o "$HOME/.config/ghostty/shaders/nyan.glsl"
   ```

2. Add to your Ghostty config (`~/Library/Application Support/com.mitchellh.ghostty/config` on macOS, `~/.config/ghostty/config` on Linux):

   ```conf
   # Procedural nyan cat cursor with rainbow trail
   custom-shader = ~/Library/Application Support/com.mitchellh.ghostty/shaders/nyan.glsl
   custom-shader-animation = true

   # Recommended — OS-level blink looks broken on top of the procedural cat
   cursor-style = block
   cursor-style-blink = false
   ```

   (On Linux, swap the `custom-shader` path for `~/.config/ghostty/shaders/nyan.glsl`.)

3. Reload Ghostty: **`⌘⇧,`** on macOS / **`Ctrl+Shift+,`** on Linux. If the shader doesn't appear, fully restart Ghostty.

A ready-to-include snippet is in [`ghostty.example.conf`](./ghostty.example.conf).

## Uninstall / disable

Comment out the two `custom-shader*` lines in your Ghostty config and reload. No other state to clean up.

## How it works

The shader runs as a post-process pass over the terminal framebuffer (`iChannel0`). For each fragment it:

1. Samples the terminal contents underneath.
2. Reads `iTime - iTimeCursorChange` to compute a `trailAlpha` that decays exponentially after each cursor move. Everything nyan-related is gated on this so the effect is invisible when idle.
3. If the cursor moved far enough, draws a rainbow band along the segment from `iPreviousCursor.xy → iCurrentCursor.xy`, sliced into 6 horizontal stripes (red/orange/yellow/green/blue/purple). The portion of the segment under the cat is cut out so the rainbow looks like it's coming out of nyan's tail end.
4. Adds a few jittered shimmer stars that drift along the trail.
5. Draws the cat (pop-tart body + procedural sprinkles + grey cat head + ears + eyes + cheeks + wiggling legs) centered at the current cursor.
6. Masks out Ghostty's default block cursor underneath nyan so they don't double up.

The cursor-coordinate convention follows [`KroneCorylus/ghostty-shader-playground`](https://github.com/KroneCorylus/ghostty-shader-playground)'s `cursor_smear.glsl`: `iCurrentCursor.xy` is already in `fragCoord` space (Y-up), with `.y` being the **top edge** of the cursor box, so `center = xy + (halfW, -halfH)` — no `iResolution.y - y` flip needed.

## Limitations

- **Single-segment trail.** Only the last cursor jump leaves a streak — fast typing won't accumulate a long continuous rainbow. Ghostty's shader pipeline doesn't expose a feedback buffer that would let us paint history across frames.
- **Tiny at default font size.** At ~7×16 px per cell (11 pt JetBrains Mono on Retina) the cat is more "tiny pixel nyan" than detailed sprite. The rainbow does the heavy lifting visually. Scale your font up if you want more detail.
- **No external sprites.** Ghostty's `custom-shader` exposes only `iChannel0` (terminal contents) as a sampler. There is no way to load a real Nyan Cat PNG. The whole cat is SDFs.
- **Selection / dim text under cursor.** The shader runs after Ghostty composites everything, so nyan overpaints selected text under the cursor. Visible only during the brief animation.
- **Always-on animation.** `custom-shader-animation = true` re-renders the screen at the display refresh rate while the window is focused. Modest GPU load on Apple Silicon, more noticeable on integrated GPUs at 4K.

## Tweaking

Common knobs at the top of [`shaders/nyan.glsl`](./shaders/nyan.glsl):

| What | Where | Default |
| --- | --- | --- |
| Trail lifetime (s) | `float trailLife = 0.55;` | `0.55` |
| Trail fade rate | `exp(-dt / trailLife * 2.5)` | `2.5` (higher = snappier) |
| Stripe band thickness | `float bandH = cell.y * 0.45;` | `0.45 ×` cursor height |
| Cat size | `float s = min(cellSize.x, cellSize.y * 0.55);` in `drawNyan` | `≈` cursor cell |
| Leg wiggle speed | `sin(t * 14.0)` in `drawNyan` | `14` rad/s |
| Number of shimmer stars | `for (int i = 0; i < 3; i++)` | `3` |

## Credits

- [Ghostty](https://ghostty.org) by Mitchell Hashimoto — the actual terminal and its custom-shader hook.
- [`KroneCorylus/ghostty-shader-playground`](https://github.com/KroneCorylus/ghostty-shader-playground) — reference for Ghostty's cursor-coordinate conventions.
- Nyan Cat © Christopher Torres / PRGuitarman — the original 2011 animation that this barely approximates.

## License

MIT. See [`LICENSE`](./LICENSE).
