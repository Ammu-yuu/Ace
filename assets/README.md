# Assets — sprite frames

Ace uses the classic **Shimeji** layout: individual PNG frames (e.g.
`shime1.png`), grouped into animation clips by `ace.json`.

```
assets/
  ace.json          # maps frames → states (committed; no images)
  ace.example.json  # a copy you can start from
  sprites/          # the actual PNG frames  (gitignored — see below)
```

As soon as `ace.json` + the referenced frames in `sprites/` exist, Ace loads and
animates them. Otherwise it falls back to a code-drawn placeholder, so the app
always runs.

## ⚠️ Copyright — why `sprites/` is gitignored
The frames in `sprites/` are copyrighted character art, so they are **never
committed or pushed** (see the `assets/sprites/` line in `.gitignore`). They live
only on your machine. A fresh clone of this repo ships **no images** and runs in
placeholder mode. Only ever put art here that you have the rights to.

## ace.json format
```json
{
  "spritesDir": "sprites",
  "animations": {
    "idle":      { "frames": ["shime1.png", "shime2.png", "shime3.png"], "fps": 3 },
    "listening": { "frames": ["shime11.png", "shime12.png"], "fps": 3 },
    "thinking":  { "frames": ["shime40.png"], "fps": 1 },
    "speaking":  { "frames": ["shime1.png", "shime35.png"], "fps": 6 }
  }
}
```

- Only `idle` is required; missing states fall back to `idle`.
- A single-frame clip just shows a still image.
- `fps` controls playback speed of that clip.

## Using a different set of frames
1. Drop your PNG frames into `assets/sprites/`.
2. Edit `ace.json` to list which files play for each state, in order.
3. `swift run` — the startup log prints e.g.
   `Ace: loaded sprites [idle:3 listening:2 thinking:1 speaking:2]`
   so you can confirm what loaded (or `no sprites found` → check paths).

## Current mapping (One Piece "Ace" Shimeji set)
| State     | Frames                     | Meaning                |
|-----------|----------------------------|------------------------|
| idle      | shime1, shime2, shime3     | standing / breathing   |
| listening | shime11, shime12           | sitting, attentive     |
| thinking  | shime40                    | hand near face         |
| speaking  | shime1, shime35            | talking motion         |

There are 46 frames (plus mirrored `-r` variants) available in `sprites/` — remap
freely by editing `ace.json`.
