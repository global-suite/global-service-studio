# Design system

Status: **accepted by the owner on 2026-11-11**, with Midnight as the default appearance. The project has no interface code yet, so these values do not come from project sources. They follow the macOS dark appearance and Apple's pro apps, so that mockups look like a native Mac app and translate directly to AppKit and SwiftUI system colors, materials and controls.

Source for every entry: Apple's macOS system colors and control metrics (dark appearance), approximated in CSS.

## Principles

- It is a Mac app first: unified title bar and toolbar, a translucent sidebar, an inspector, system controls. Nothing that looks like a web dashboard: no cards with heavy borders, no pill badges everywhere, no custom scrollbars, no uppercase letter-spaced labels except small section headers in sidebars.
- Content is the interface. Chrome is quiet; slides and outputs carry the color.
- One accent color, used for selection and the primary action. Red is reserved for "live". Green is reserved for the key output color.

## Appearances

The app is dark only for now, with three appearances the operator can choose. **Midnight is the default**; it matches the owner's reference color `#1C1C1C`. Only the five surface tokens change between appearances; text, accent and status colors stay the same.

| Token | Midnight (default) | Graphite | Black |
|---|---|---|---|
| `window` | `#1C1C1C` | `#1E1E1E` | `#000000` |
| `content-raised` | `#242424` | `#2A2A2C` | `#1C1C1C` |
| `sidebar` | `rgba(22,22,22,0.90)` | `rgba(40,40,42,0.72)` | `rgba(10,10,10,0.94)` |
| `titlebar` | `rgba(28,28,28,0.92)` | `rgba(46,46,48,0.86)` | `rgba(10,10,10,0.94)` |
| `separator` | `rgba(255,255,255,0.10)` | `rgba(255,255,255,0.10)` | `rgba(255,255,255,0.14)` |

- **Midnight**: flat and deep; the sidebar is slightly darker than the content, separated by a hairline.
- **Graphite**: the lighter, more translucent look of the standard macOS dark appearance.
- **Black**: true black for OLED displays and very dark rooms; separators are a little stronger so panes stay readable.

`sidebar` and `titlebar` keep `backdrop-filter: blur(30px) saturate(180%)` in every appearance.

## Color (shared by every appearance)

| Token | Value | Use |
|---|---|---|
| `control` | `rgba(255,255,255,0.08)` | Button and field fill |
| `control-hover` | `rgba(255,255,255,0.13)` | Hover |
| `label` | `rgba(255,255,255,0.85)` | Primary text |
| `label-secondary` | `rgba(255,255,255,0.55)` | Secondary text |
| `label-tertiary` | `rgba(255,255,255,0.28)` | Disabled, placeholders |
| `accent` | `#0A84FF` | Selection, primary button, focus ring |
| `live` | `#FF453A` | What is live, always with a label or icon |
| `next` | `#FF9F0A` | What goes live next |
| `ok` | `#32D74B` | Output connected |
| `key-green` | `#00B140` | The key color drawn in the Key output only |

## Typography

System font only: `-apple-system, "SF Pro Text", "Helvetica Neue", sans-serif`. Numbers that change use `font-variant-numeric: tabular-nums`.

| Style | Size / weight | Use |
|---|---|---|
| Body | 13px / 400 | Default text, list rows |
| Emphasized | 13px / 600 | Selected or important rows, button titles |
| Subheadline | 11px / 500, `label-secondary` | Sidebar section headers, captions |
| Title | 15px / 600 | Window title, pane titles |
| Large | 22px / 700 | Now and Next headings in Live mode |

## Metrics

| Token | Value |
|---|---|
| Window corner radius | 10px |
| Control corner radius | 6px |
| Slide thumbnail radius | 6px |
| Toolbar height | 52px |
| Sidebar width | 240px |
| Inspector width | 280px |
| List row height | 28px |
| Spacing scale | 4, 8, 12, 16, 20, 24 |
| Focus ring | 3px `accent` at 50% opacity, outside the control |

## Components

- **Window**: traffic lights at the left of a unified title bar and toolbar; the title sits next to them; toolbar items are borderless icon buttons that show a rounded fill on hover.
- **Sidebar (source list)**: translucent material; section headers in Subheadline; rows 28px with an icon; the selected row is a rounded rectangle (radius 6) filled with `accent` when the window is key.
- **Segmented control**: one rounded container in `control` fill; the selected segment is a lighter rounded fill with a soft shadow. Used for the Prepare / Live switch and for small choices.
- **Push button**: `control` fill, radius 6, 13px title. Primary uses `accent`. Destructive live actions use a red tint and a text label.
- **Inspector**: right pane on the sidebar material, with grouped sections and disclosure headers.
- **Slide thumbnail**: 16:9, radius 6, black background, centered white text; the section name and index below in Subheadline. Live: 3px `live` ring plus a "LIVE" label. Next: 2px `next` ring plus a "NEXT" label. Selected: 3px `accent` ring.
- **Output monitor**: a 16:9 preview with its name, role and a status dot plus text.
- **Keyboard hints**: a small rounded key cap in `control` fill next to the action it triggers.
