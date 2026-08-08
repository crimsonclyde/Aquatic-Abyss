# Wallpapers

## Where wallpapers live

Put personal wallpapers here:

```bash
~/Pictures/Wallpapers
```

The installer offers to copy the bundled set into that directory during
installation. It never overwrites existing files, so your own images are safe
if you install again later.

## The picker

![AGS wallpaper picker](../screenshots/wallpaper-picker-preview.png)

The quick settings `Wallpaper` button opens an AGS thumbnail picker with:

- larger image previews in a centered grid
- active wallpaper highlighting
- click-to-apply through Hyprpaper
- random wallpaper action
- folder shortcut for `~/Pictures/Wallpapers`

New images dropped into `~/Pictures/Wallpapers` show up the next time the
picker is opened.

## Fallback

If no personal wallpaper is selected, the startup script falls back to:

```bash
/usr/share/hypr
```

## Mockup

The picker's layout mockup, useful when changing its styling:

```bash
docs/mockups/wallpaper-picker-preview.html
```
