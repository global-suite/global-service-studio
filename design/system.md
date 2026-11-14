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

## Tokens added with the service plan design (2026-11-14)

Source: the accepted artboards in `design/service-plan/` (01–08) and the owner's decision of 2026-11-14 (`odd/tasks/service-plan.md`, L6). They are shared by every appearance unless a column says otherwise.

### Color

| Token | Value | Use |
|---|---|---|
| `accent-strong` | `#0071E3` | Any filled accent surface behind text: primary push buttons, the Next button in Live, the highlighted menu item, key caps drawn on the accent. White text on it is **4.70:1** (WCAG AA for 13 px text); white on `accent` is only 3.65:1. Against `window` it is 3.63:1, enough for a control boundary |
| `accent-strong-hover` | `accent-strong` under `rgba(0,0,0,0.12)` (≈ `#0063C8`) | Hover and pressed state of `accent-strong`; always darker, never lighter (white text 5.78:1) |
| `on-accent` | `#FFFFFF` | Text and icons on `accent-strong`, on `selection` and on the accent badge of a drag |
| `selection` | `rgba(10,132,255,0.60)` | Selected row in the sidebar, the run sheet and lists when the window is key. White text on it is 6.91:1 on Midnight, 6.84:1 on Graphite, 8.10:1 on Black, 6.61:1 on `content-raised` |
| `destructive-fill` | `rgba(255,69,58,0.16)` | Fill of destructive push buttons such as Clear All; always with a text label. `label` on it is 10.66:1 |
| `destructive-fill-hover` | `rgba(255,69,58,0.24)` | Hover of a destructive push button |
| `destructive-border` | `inset 0 0 0 1px rgba(255,69,58,0.24)` | Hairline of a destructive push button |
| `key-cap` | `control` fill, `inset 0 -1px 0 rgba(0,0,0,0.5)`, text 11px / 600 `label-secondary` | Key labels next to actions, in menus, tooltips and the shortcut legend (`label-secondary` on it is 5.25:1) |
| `key-cap-on-accent` | `window` fill, text `label` | Key labels drawn inside an `accent-strong` button (12.54:1) |

Rule: use `accent-strong` for every filled accent shape that carries text, and `accent` for everything that does not (selection rings, focus ring, outlines, icons, the insertion line of a drag). This replaces `accent` as the fill of the Primary push button in Components.

### Shadows

| Token | Value | Use |
|---|---|---|
| `shadow-window` | `inset 0 0 0 1px separator, 0 0 0 1px rgba(0,0,0,0.5), 0 22px 60px rgba(0,0,0,0.5)` | The main window |
| `shadow-menu` | `0 0 0 1px separator, 0 12px 32px rgba(0,0,0,0.55)` | Menus and context menus |
| `shadow-popover` | `0 0 0 1px separator, 0 16px 40px rgba(0,0,0,0.6)` | Popovers and dialogs anchored to a control |
| `shadow-float` | `0 0 0 1px separator, 0 8px 24px rgba(0,0,0,0.5)` | The drag preview, tooltips and small floating panels |
| `shadow-drawer` | `-12px 0 32px rgba(0,0,0,0.35)` | A drawer that slides over the content from the right |
| `shadow-segment` | `0 1px 2px rgba(0,0,0,0.5)` | The selected segment of a segmented control |
| `shadow-live` | `0 0 0 3px live, 0 0 48px rgba(255,69,58,0.24)` | The live panel in Live mode |

### Mockup backdrop

| Token | Midnight (default) | Graphite | Black | Use |
|---|---|---|---|---|
| `desk` | `#0B0B0B` | `#2A2A2C` | `#000000` | The desktop behind the window in artboards only; not a color of the app |

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

## Window sizes

The layout follows the width of the main window's content area (the window minus the sidebar), not the display. Design and review every new screen at least at compact (1440×900) and wide (3440×1440).

| Class | Content width | Typical display | Live view |
|---|---|---|---|
| Compact | 1100–1599 | 13" and 14" MacBook | `04-native-live`: live panel, Next column with Previous \| Next under it, slide grid of 5 per row below, outputs strip and clear actions in the bottom bar |
| Regular | 1600–2399 | 1920×1080, 2560×1440 | Same structure; panels grow up to their maximum; the slide grid shows 6 per row |
| Wide | 2400 and wider | 3440×1440, 5120×1440 | `06-native-live-ultrawide`: outputs leave the bottom bar and become a right column of large monitors (Center, Sides, Stage, Key) with the clear actions under them; live and Next stay top left, with a stage message panel under them; the slide grid takes the full height between them and the outputs, 5 to 6 per row of large thumbnails. The stage message and timers panel under Next is a Phase 2 feature, drawn as a reference |

What has a maximum size:

- Sidebar 240 and inspector 280: fixed in every class; the order of service always stays.
- Live panel: at most 1280×720, and never taller than about half the content height. In Wide it is about 910 wide, so the grid keeps large thumbnails.
- Next panel: at most 760 wide. Previous \| Next sit beside or under it and match its height.
- Outputs column (Wide only): 440 wide; four 16:9 monitors stacked, clear actions pinned to its bottom.
- Slide thumbnails: about 220 to 380 wide; slide text inside them is 11 to 16 px. Interface text, controls and row heights never scale with the window.

What absorbs extra space: the slide grid, by adding columns and rows, never by growing its thumbnails past their maximum.

Order in which width is given:

1. The live panel, up to its maximum (in Wide, up to about 910).
2. The Next column, up to its maximum.
3. At 2400 and wider, the outputs move from the bottom bar to the right column, which gives the grid the full height.
4. Everything left goes to the slide grid.

No empty regions: when the current item's slides do not fill the grid, it continues with the next items of the order of service as previews, each under its own header. Live stays top left in every class, and the reading and keyboard order is sidebar, live, Next, slides, outputs.

## Components

- **Window**: traffic lights at the left of a unified title bar and toolbar; the title sits next to them; toolbar items are borderless icon buttons that show a rounded fill on hover.
- **Sidebar (source list)**: translucent material; section headers in Subheadline; rows 28px with an icon; the selected row is a rounded rectangle (radius 6) filled with `accent` when the window is key.
- **Segmented control**: one rounded container in `control` fill; the selected segment is a lighter rounded fill with a soft shadow. Used for the Prepare / Live switch and for small choices.
- **Push button**: `control` fill, radius 6, 13px title. Primary uses `accent-strong` (see Additional tokens). Destructive live actions use a red tint and a text label.
- **Inspector**: right pane on the sidebar material, with grouped sections and disclosure headers.
- **Slide thumbnail**: 16:9, radius 6, black background, centered white text; the section name and index below in Subheadline. Live: 3px `live` ring plus a "LIVE" label. Next: 2px `next` ring plus a "NEXT" label. Selected: 3px `accent` ring.
- **Output monitor**: a 16:9 preview with its name, role and a status dot plus text.
- **Keyboard hints**: a small rounded key cap in `control` fill next to the action it triggers.
