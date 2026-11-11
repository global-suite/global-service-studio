# Design

What Global Service Studio is going to look like, before it is built.

| Path | Contents |
|---|---|
| [system.md](system.md) | The design system: three dark appearances (Midnight is the default), colors, typography, metrics and component rules. Use these values when building interface. |
| [operator-window/](operator-window/) | The main window. `04-native-live.html` and `05-native-prepare.html` are the accepted views; `01` to `03` are earlier directions kept for reference. |

## Viewing a mockup

Each mockup is one self-contained HTML file with inline CSS and no external resources. Open it in a browser at 1440 by 900 or larger. The accepted views respond to the arrow keys, Space and clicks, and have an appearance switcher at the bottom of the sidebar.

`design.json` in each folder lists the mockups with the tradeoff each one makes.

## Rules

- A mockup is a reference, not application code. The app is native: nothing here is shipped.
- Mockups use invented content. No real song lyrics.
- A new screen is designed here first, following `system.md`, and proposed through an issue like any other change.
