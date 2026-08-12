# Assets — drop your own sprite sheet here

Ace ships with **no bundled character art**. It draws a placeholder pet in code,
so nothing copyrighted is included in the app. Add art by dropping two files
into this folder:

```
assets/
  ace_sheet.png    # your sprite sheet: a grid of equal-size frames
  ace.json         # tells Ace how to slice the sheet (see below)
```

As soon as both exist, Ace loads and animates them automatically. Remove them
and it falls back to the placeholder.

## ⚠️ Copyright
Use art you actually have the rights to — your own drawings, or something
explicitly licensed for reuse. Don't use frames ripped from a game/anime.

## ace.json format
The sheet must be a **uniform grid**: every frame the same width/height. Sizes
and positions are in **pixels** of the PNG. `row` 0 is the **top** row; `col` 0
is the leftmost column. `startCol` defaults to 0 if omitted.

```json
{
  "frameWidth": 100,
  "frameHeight": 100,
  "animations": {
    "idle":      { "row": 0, "startCol": 0, "frames": 6, "fps": 6 },
    "listening": { "row": 1, "startCol": 0, "frames": 4, "fps": 8 },
    "thinking":  { "row": 2, "startCol": 0, "frames": 4, "fps": 8 },
    "speaking":  { "row": 3, "startCol": 0, "frames": 4, "fps": 10 }
  }
}
```

Only `idle` is required. Missing states fall back to `idle`. A clip with a
single frame just shows a still image (no animation).

### Steps to use your own sheet
1. Save your grid sheet as `assets/ace_sheet.png`.
2. Measure one cell in pixels → set `frameWidth` / `frameHeight`.
3. For each pose row, set `row` and how many `frames` are in it.
4. Copy `ace.example.json` → `ace.json` and edit the numbers.
5. Run `swift run` — Ace animates your art. Tune `fps` to taste.

> Tip: if your art isn't a clean grid, re-arrange the poses into evenly spaced
> cells (one row per state) in any image editor first — that's all the loader
> needs.
