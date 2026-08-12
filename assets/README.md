# Assets — drop your own sprites here

Ace ships with **no bundled character art**. Step A/B render a placeholder pet
drawn in code so nothing copyrighted is included.

## ⚠️ Copyright note
Do **not** drop in art you don't have the rights to (e.g. sprites ripped from a
game or an anime). Use your own original art, or something explicitly licensed
for reuse.

## How sprites will be loaded (Step B)
When you're ready, place a sprite sheet here, e.g.:

```
assets/
  ace_idle.png        # a horizontal (or grid) strip of equal-size frames
  ace.json            # frame metadata (see below)
```

Planned `ace.json` shape (subject to refinement in Step B):

```json
{
  "frameWidth": 64,
  "frameHeight": 64,
  "animations": {
    "idle":     { "row": 0, "frames": 4, "fps": 6 },
    "listening":{ "row": 1, "frames": 4, "fps": 8 },
    "thinking": { "row": 2, "frames": 4, "fps": 8 },
    "speaking": { "row": 3, "frames": 4, "fps": 10 }
  }
}
```

Until you add these, the app falls back to the code-drawn placeholder.
