# DailySticky — App Icon Handoff

Final icon: **Soft Curl** — a warm sticky-note page with a soft, curved peeled
corner revealing deep teal (with a thin gold underside). macOS Big Sur / Sonoma
rounded-square ("squircle") style.

## Files
- `DailySticky-icon.svg` — master, vector, scales to any size. **Use this as the source of truth.**
- `png/DailySticky-icon-{1024,512,256,128,64,32,16}.png` — rasterized sizes.

## Colors
- Paper (vertical gradient): `#FCEDA0` → `#F3D265`
- Teal reveal (diagonal gradient): `#1F8C7C` → `#115C54`
- Gold curl underside: `#EAC65C` → `#D3A538`
- Crease line: `#0D4F48` @ 28% opacity
- Top sheen: white @ 62% → 0%
- Corner radius: 90 on a 400×400 viewBox = **22.5%** (Apple icon grid)

## Geometry (400×400 viewBox)
- Page fills the squircle; the bottom-right corner is cut by a quadratic curve
  from `(400,250)` through control `(312,312)` to `(250,400)`.
- Teal fills the region between that curve and the corner; the gold band is a
  thin strip along the curve; a faint crease stroke sits on the curve.

## For Claude Code — suggested prompt
> Replace the macOS app icon with `export/DailySticky-icon.svg`. Generate an
> `AppIcon.appiconset` (or `.icns`) from it at all required sizes (16, 32, 64,
> 128, 256, 512, 1024 plus @2x). The SVG is self-contained — render at each size
> rather than upscaling the small PNGs. Keep the squircle radius as authored
> (macOS applies its own mask, so the art already matches the 22.5% grid).

Tip: macOS masks icons to its own superellipse, so you can also export the art
**without** the rounded corners (remove the `clip-path` / `rx`) and let the
system apply the mask — either works.
