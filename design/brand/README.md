# Crubik app icon assets

The launcher icon uses the cute crab-and-cube mark with a solved 3x3 cube:
white on top, green on the left/front face, and red on the right face. These
visible faces follow the standard opposite color pairs of white/yellow,
green/blue, and red/orange.

## Source assets

- `crubik-app-logo-universal-master.png`: full-resolution full-color master.
- `crubik-app-logo-universal-1024.png`: 1024 px full-color launcher master.
- `crubik-app-logo-foreground.png`: transparent full-color foreground layer.
- `crubik-app-logo-monochrome.png`: transparent single-color mask with negative
  space preserving the face and 3x3 sticker grid.

## Platform mapping

- Android uses full-color legacy launcher PNGs plus adaptive foreground,
  background, and monochrome layers. The monochrome layer enables user-themed
  launcher icons where supported.
- iOS uses the opaque full-color icon set. The system generates dark and tinted
  treatments because custom appearance variants are intentionally omitted.
- macOS and Windows use resized full-color assets.
- Web uses opaque standard icons and safe-area-adjusted maskable icons.

The adaptive and maskable foregrounds are inset so claws and legs remain inside
platform masks. Keep the primary artwork centered and do not bake rounded
corners into source artwork; operating systems apply the final mask.
