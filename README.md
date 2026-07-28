# AeroNotch

A macOS notch that shows your [AeroSpace](https://github.com/nikitabobko/AeroSpace) workspaces.
It appears only when you **hover the notch area** or **switch workspaces** — otherwise it's
invisible. Written fully in Swift; no dependencies.

Inspired by and architected after [TheBoringNotch](https://github.com/TheBoredTeam/boring.notch)
(notch shape originally from [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)).

![state](https://img.shields.io/badge/state-v0.1.0-blue)

## Features

- **Workspace pills** — all non-empty workspaces (+ focused) as pills inside the notch,
  with app icons per workspace.
- **Agent indicator** — a persistent capsule pinned to the notch's left edge showing your
  AI coding-agent sessions as tracked by [herdr](https://herdr.dev) (Claude Code, pi, …):
  one glyph per agent kind (Claude starburst, π, …) + a status dot per session
  (filled+pulsing = working, thick ring = blocked, dim ring = idle). Hover/tap it to open
  the **Agents popover** — one pill per session, click to jump to that herdr pane.
  Toggle the feature (menu → **Agents**) or just the indicator (**Agent Indicator**).
- **Adaptive width** — the expanded notch measures its content and hugs it (animated),
  clamped between a minimum and `maxOpenWidth`; scrolls only when content exceeds the cap.
- **Click to switch** — clicking a pill runs `aerospace workspace <name>` (with an
  optimistic highlight so it feels instant).
- **Multi-monitor** — one notch per display; each screen highlights the workspace visible
  on *that* monitor (via AeroSpace's `monitor-appkit-nsscreen-screens-id` bridge).
- **Peek on switch** — expands briefly on the screen you switched on, then retracts.
- **Two presentation modes** — for the *workspaces* popover: `notch` (panel expands out
  of the notch) or `menuBarLeft` (a menu-bar-height band from the screen's leading edge to
  the notch). Switch live from the menu bar icon → **Workspace Style**, or set
  `presentationMode` in the config. (The Agents popover always opens at the notch itself,
  and the agent indicator stays visible either way.)
- **One row, no tabs** — the open notch shows a single feature chosen by context:
  workspace peeks show workspaces; opening via the agent indicator shows agents.
- **Extensible** — features plug into a `NotchFeature` registry; ships with Workspaces and Agents.
- **Hover to open** — small delay (configurable) so casual fly-bys don't open it.

## Install

```sh
just install        # builds release binary, assembles + ad-hoc signs AeroNotch.app,
                    # copies to /Applications, launches it
```

Requires: Xcode/Swift toolchain, `just` (`brew install just`), AeroSpace.

### Via Homebrew (tap)

```sh
brew tap jasonmargin/tap
brew trust jasonmargin/tap        # Homebrew 6+ requires trusting third-party taps
brew install --cask aeronotch
# Not notarized — clear Gatekeeper quarantine after install:
xattr -dr com.apple.quarantine /Applications/AeroNotch.app
```

Maintainers: `just release <version>` (zip + sha256 + publish steps) → `just bump-cask <version>` (updates `homebrew-tap/Casks/aeronotch.rb`).

Other recipes: `just build` · `just bundle` · `just run` (dev, no bundle) ·
`just hook` (print the aerospace.toml line) · `just uninstall`

## AeroSpace hook (instant switch detection)

The app polls as a fallback, but the hook makes peeks instant. One line in
`~/.config/aerospace/aerospace.toml` (this repo's installer already extended the
existing sketchybar hook):

```toml
exec-on-workspace-change = ["/bin/bash", "-c", "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE ; /Applications/AeroNotch.app/Contents/MacOS/AeroNotch ping-workspace-change"]
```

Then `aerospace reload-config`. The `ping-workspace-change` CLI command posts a
`DistributedNotification` that the running app listens for. A second command,
`ping-agents`, transiently opens the Agents popover — handy for hotkey daemons.

## Config

`~/.config/aeronotch/config.json` (all keys optional; menu bar icon → Open Config File…
creates a fully-populated default):

| key | default | meaning |
|---|---|---|
| `presentationMode` | `"notch"` | `"notch"` or `"menuBarLeft"` (workspaces popover style) |
| `pollIntervalSeconds` | `2.0` | fallback poll cadence |
| `peekDurationSeconds` | `1.5` | how long the notch stays up after a switch |
| `hoverOpenDelaySeconds` | `0.12` | hover dwell before opening |
| `showEmptyWorkspaces` | `false` | show all configured workspaces |
| `showAppIcons` | `true` | app icons inside pills |
| `maxAppIconsPerWorkspace` | `3` | overflow renders as `+N` |
| `maxOpenWidth` | `680` | cap on expanded width (actual width adapts to content) |
| `openHeight` | `84` | expanded notch height |
| `hiddenWorkspaces` | `[]` | workspaces to never show |
| `agentsEnabled` | `true` | herdr agent-session feature (indicator + popover) |
| `agentsShowClosedIndicator` | `true` | persistent agent-status capsule left of the notch |
| `agentsPollIntervalSeconds` | `3.0` | `herdr agent list` poll cadence |
| `herdrPath` | `null` | explicit herdr binary path (auto-detected when nil) |
| `aerospacePath` | `null` | explicit aerospace binary path |

Restart the app after editing.

## Architecture

```
Sources/AeroNotch/
├── AeroNotchApp.swift          @main app, MenuBarExtra, AppDelegate (window manager: 1 window/screen)
├── CLI.swift                   ping-workspace-change / ping-agents / --version (short-lived processes)
├── Config/AeroNotchConfig.swift
├── Notch/
│   ├── NotchWindow.swift       NSPanel: floating, all-spaces, .mainMenu+3, never key
│   ├── NotchContentView.swift  notch panel + springs + one-row feature content + agent strip
│   ├── NotchShape.swift        animatable notch silhouette (DynamicNotchKit lineage)
│   ├── NotchViewModel.swift    open/closed state, peek/hover/tap timers
│   ├── NotchMetrics.swift      exact physical-notch sizing (auxiliary areas + safeAreaInsets)
│   ├── NotchEnvironment.swift  per-window aerospaceMonitorID
│   └── NSScreen+Display.swift  displayID / appKitScreenIndex / screenWithMouse
├── Features/
│   ├── NotchFeature.swift      protocol + registry  ← the extensibility seam
│   ├── Workspaces/
│   │   ├── WorkspaceStore.swift    snapshot, hook listener + fallback polling, NotchFeature
│   │   └── WorkspacesFeatureView.swift  the pills
│   └── Agents/
│       ├── AgentSession.swift      session model + status severity
│       ├── HerdrClient.swift       `herdr agent list` polling backend (herdr owns detection)
│       ├── AgentSessionStore.swift poll loop + hysteresis, NotchFeature
│       ├── AgentsStatusStrip.swift the always-on left-of-notch capsule (glyphs + dots)
│       ├── AgentGlyph.swift        Claude starburst (drawn, monochrome) + fallback glyphs
│       └── AgentsFeatureView.swift session pills (click → focus herdr pane)
└── Aerospace/
    ├── AeroSpaceClient.swift   WorkspaceProviding protocol + CLI implementation
    └── AppIconProvider.swift   bundle-id → icon (running app → NSWorkspace → name match)
```

Key ideas (borrowed from TheBoringNotch):

- **The window never resizes.** It's a fixed, transparent panel at the top-center of each
  screen; the notch *content* morphs inside it via SwiftUI springs
  (open `spring(0.42, 0.8)`, close `spring(0.45, 1.0)`). No `NSWindow` frame animation —
  this is what makes the motion fluid.
- **Click-through by hit-test shape.** Only the drawn notch shape captures mouse events;
  everything else in the transparent window falls through to the desktop/menu bar.
- **Hardware clearance.** The expanded panel reserves a strip the height of the closed
  notch at the top, so content never slides under the physical cutout.
- **One `WorkspaceStore`, many view models.** Aerospace state is shared; each screen's
  notch owns only its open/closed/hover state.

### Adding a feature

```swift
@MainActor
final class BatteryFeature: NotchFeature {
    let id = "battery"
    let displayName = "Battery"
    func makeContentView() -> AnyView { AnyView(BatteryView()) }
}
// in AppDelegate.applicationDidFinishLaunching:
registry.register(BatteryFeature())
```

With more than one feature registered, content is chosen by context (peek →
workspaces, agent indicator → agents) — one row, no tabs. Features register and
unregister live (menu → **Agents** toggles the Agents feature without a relaunch).

### Agents (herdr integration)

herdr owns all agent detection (screen manifests + integrations); AeroNotch just
polls `herdr agent list` and renders its `idle|working|blocked|unknown` states:

- **Closed notch**: the indicator capsule sits left of the notch, always visible
  while sessions exist — workspace peeks don't hide it.
- **Open**: hover/tap the capsule (or `AeroNotch ping-agents`) → the Agents popover
  hangs from the notch itself (regardless of `presentationMode`, which only styles
  the workspaces popover). One pill per session; click jumps to that herdr pane
  (`herdr agent focus <pane>`).
- Only agents running **inside herdr** are visible — by design (herdr is the
  single source of truth for status). Poll failures blank the capsule after 2
  consecutive errors (hysteresis), never on a single hiccup.

## Notes

- v1 targets the common cases; the closed-notch geometry handles notched and
  notch-less displays (fake notch bar on external monitors).
- Icons resolve from running apps first, so apps outside /Applications still get icons.
