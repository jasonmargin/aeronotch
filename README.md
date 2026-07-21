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
- **Adaptive width** — the expanded notch measures its content and hugs it (animated),
  clamped between a minimum and `maxOpenWidth`; scrolls only when content exceeds the cap.
- **Click to switch** — clicking a pill runs `aerospace workspace <name>` (with an
  optimistic highlight so it feels instant).
- **Multi-monitor** — one notch per display; each screen highlights the workspace visible
  on *that* monitor (via AeroSpace's `monitor-appkit-nsscreen-screens-id` bridge).
- **Peek on switch** — expands briefly on the screen you switched on, then retracts.
- **Hover to open** — small delay (configurable) so casual fly-bys don't open it.
- **Extensible** — features plug into a `NotchFeature` registry; >1 feature automatically
  gets a segmented switcher inside the notch.

## Install

```sh
just install        # builds release binary, assembles + ad-hoc signs AeroNotch.app,
                    # copies to /Applications, launches it
```

Requires: Xcode/Swift toolchain, `just` (`brew install just`), AeroSpace.

### Via Homebrew (tap)

```sh
brew tap jasonmargin/tap
brew install --cask --no-quarantine aeronotch   # not notarized; --no-quarantine skips Gatekeeper friction
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
`DistributedNotification` that the running app listens for.

## Config

`~/.config/aeronotch/config.json` (all keys optional; menu bar icon → Open Config File…
creates a fully-populated default):

| key | default | meaning |
|---|---|---|
| `pollIntervalSeconds` | `2.0` | fallback poll cadence |
| `peekDurationSeconds` | `1.5` | how long the notch stays up after a switch |
| `hoverOpenDelaySeconds` | `0.12` | hover dwell before opening |
| `showEmptyWorkspaces` | `false` | show all configured workspaces |
| `showAppIcons` | `true` | app icons inside pills |
| `maxAppIconsPerWorkspace` | `3` | overflow renders as `+N` |
| `maxOpenWidth` | `680` | cap on expanded width (actual width adapts to content) |
| `openHeight` | `84` | expanded notch height |
| `hiddenWorkspaces` | `[]` | workspaces to never show |
| `aerospacePath` | `null` | explicit aerospace binary path |

Restart the app after editing.

## Architecture

```
Sources/AeroNotch/
├── AeroNotchApp.swift          @main app, MenuBarExtra, AppDelegate (window manager: 1 window/screen)
├── CLI.swift                   ping-workspace-change / --version (short-lived processes)
├── Config/AeroNotchConfig.swift
├── Notch/
│   ├── NotchWindow.swift       NSPanel: floating, all-spaces, .mainMenu+3, never key
│   ├── NotchContentView.swift  notch panel + springs + feature switcher
│   ├── NotchShape.swift        animatable notch silhouette (DynamicNotchKit lineage)
│   ├── NotchViewModel.swift    open/closed state, peek/hover/tap timers
│   ├── NotchMetrics.swift      exact physical-notch sizing (auxiliary areas + safeAreaInsets)
│   ├── NotchEnvironment.swift  per-window aerospaceMonitorID
│   └── NSScreen+Display.swift  displayID / appKitScreenIndex / screenWithMouse
├── Features/
│   ├── NotchFeature.swift      protocol + registry  ← the extensibility seam
│   └── Workspaces/
│       ├── WorkspaceStore.swift    snapshot, hook listener + fallback polling, NotchFeature
│       └── WorkspacesFeatureView.swift  the pills
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

With more than one feature registered, the notch automatically renders a segmented
switcher above the active feature's content.

## Notes

- v1 targets the common cases; the closed-notch geometry handles notched and
  notch-less displays (fake notch bar on external monitors).
- Icons resolve from running apps first, so apps outside /Applications still get icons.
