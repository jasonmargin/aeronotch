# AeroNotch

A macOS notch that shows your [AeroSpace](https://github.com/nikitabobko/AeroSpace) workspaces.
It appears only when you **hover the notch area** or **switch workspaces** — otherwise it's
invisible. Written fully in Swift; no dependencies.

Inspired by and architected after [TheBoringNotch](https://github.com/TheBoredTeam/boring.notch)
(notch shape originally from [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)).

![state](https://img.shields.io/badge/state-v0.1.0-blue)

## Features

- **Workspace grid** — all non-empty workspaces (+ focused) as pills in a drop-down
  grid, max 5 per row, with app icons per workspace. The panel always grows to show
  every row — no scrolling. The active workspace shows in a persistent capsule at
  the notch's left edge; the grid opens on hover of the notch or the capsule.
- **Agent indicator** — a persistent capsule pinned to the notch's left edge showing your
  AI coding-agent sessions as tracked by [herdr](https://herdr.dev) (Claude Code, pi, …):
  one glyph per agent kind (Claude starburst, π, …) + a status dot per session
  (filled+pulsing = working, thick ring = blocked, dim ring = idle). Hover/tap it to open
  the **Agents list** — one row per session (same list layout as Notes), click to jump
  to that herdr pane. While Notes is pinned, hovering shows the Agents list *over* the
  notes panel (reverts on hover-out; the pin is never disturbed).
  Toggle the feature (menu → **Agents**) or just the indicator (**Agent Indicator**).
- **Adaptive size** — the expanded notch measures its content and hugs it (animated):
  width clamped between a minimum and `maxOpenWidth`, height between the single-row
  default and `notesMaxHeight`; scrolls only when content exceeds the cap.
- **Click to switch** — clicking a pill runs `aerospace workspace <name>` (with an
  optimistic highlight so it feels instant).
- **Multi-monitor** — one notch per display; each screen highlights the workspace visible
  on *that* monitor (via AeroSpace's `monitor-appkit-nsscreen-screens-id` bridge).
- **Hover to open, not on switch** — the notch expands only when you hover it (small
  configurable delay filters fly-bys); the active workspace lives in the left-edge
  capsule. A brief expand-on-switch peek is available via menu → **Peek on Workspace
  Switch** or `peekOnWorkspaceSwitch` (default off).
- **One feature at a time, no tabs** — the open notch shows a single feature chosen by
  context: plain hover shows workspaces; opening via a strip deep-links to that feature.
- **Notes notepad** — a taller drop-down (checklist strip between the workspaces and agents pills,
  menu → **Open Notes**, or `AeroNotch ping-notes`): a
  combined to-do list. App-created to-dos persist in `~/.config/aeronotch/notes.json`;
  it also scans your Obsidian vaults for `- [ ]` tasks and **writes toggles back to
  the markdown files** (two-way). Checking a task off records the completion date —
  `completedAt` in the app store, `✅ yyyy-MM-dd` (Tasks-plugin style) in Obsidian —
  and completed items are shown for the past 7 days, with a **load more** button
  extending the window in 7-day increments. The panel resists closing while it has
  keyboard focus, so moving the mouse away mid-sentence never loses input.
- **Completion heatmap** — a GitHub-style contribution map (weeks × weekdays; the more
  completions, the brighter the dot) in three places: the Notes drop-down (12 weeks),
  the Completed settings tab (20 weeks), and an optional **desktop widget** (menu →
  **Completion Widget**) that floats on the wallpaper behind your windows, draggable.
- **Pinnable cards** — every drop-down (Workspaces, Agents, Notes) has a pin button in
  its header: the card stays permanently open on that screen — peeks/hover never close
  it, it hangs below the menu bar instead of covering it, and the pin (screen +
  feature) survives restarts. Hovering another strip overlays that feature over the
  pinned card without disturbing the pin.
- **Extensible** — features plug into a `NotchFeature` registry; ships with Workspaces and Agents.
- **Hover to open** — small delay (configurable) so casual fly-bys don't open it.
- **Vim mode** — hotkey-opened panels take the keyboard: `h/j/k/l` navigate
  (workspaces grid moves in all four directions; lists move `j/k`), `Enter`
  activates (switch workspace / focus agent pane / toggle to-do), `i` focuses
  the add-to-do field in Notes, `d` deletes the selected app to-do, `Esc`
  backs out (blurs the field first, then closes).
- **Settings window** — menu → **Settings…** (⌘,): live-bound preferences (persisted
  to `config.json`) plus a **Completed** tab listing every checked-off to-do from
  both sources, grouped by day.
- **JetBrains Mono** — all notch text renders in JetBrains Mono when installed
  (falls back to the system monospaced font).

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
```

Not notarized (ad-hoc signature) — the cask strips the Gatekeeper quarantine flag
automatically on install. If macOS still complains, run
`xattr -dr com.apple.quarantine /Applications/AeroNotch.app`.

Maintainers: `just release <version>` (zip + sha256 + publish steps) → `just bump-cask <version>` (updates `homebrew-tap/Casks/aeronotch.rb`).

Other recipes: `just build` · `just bundle` · `just run` (dev, no bundle) ·
`just hook` (print the aerospace.toml line) · `just uninstall`

## AeroSpace hook (instant switch detection)

The app polls as a fallback, but the hook makes state updates instant. One line in
`~/.config/aerospace/aerospace.toml` (this repo's installer already extended the
existing sketchybar hook):

```toml
exec-on-workspace-change = ["/bin/bash", "-c", "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE ; /Applications/AeroNotch.app/Contents/MacOS/AeroNotch ping-workspace-change"]
```

Then `aerospace reload-config`. The `ping-workspace-change` CLI command posts a
`DistributedNotification` that the running app listens for. Two more commands,
`ping-agents` and `ping-notes`, transiently open the Agents popover / Notes
drop-down — handy for hotkey daemons.

## Config

`~/.config/aeronotch/config.json` (all keys optional; menu bar icon → Open Config File…
creates a fully-populated default):

| key | default | meaning |
|---|---|---|
| `pollIntervalSeconds` | `2.0` | fallback poll cadence |
| `peekOnWorkspaceSwitch` | `false` | expand the notch briefly on every workspace switch (off = hover-only) |
| `peekDurationSeconds` | `1.5` | how long the notch stays up after a peek |
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
| `notesEnabled` | `true` | Notes notepad feature (drop-down + indicator) |
| `notesShowClosedIndicator` | `true` | persistent checklist capsule between workspaces and agents pills |
| `notesVaultPaths` | `null` | explicit Obsidian vault paths to scan (auto-detected when nil: margindept-kb + Obsidian's registry) |
| `notesMaxHeight` | `460` | expanded Notes drop-down height |
| `notesScanIntervalSeconds` | `60` | Obsidian rescan cadence |
| `completionWidgetEnabled` | `false` | desktop completion-heatmap widget |
| `pinnedDisplayID` | `null` | screen with a card pinned open (set by the pin button) |
| `pinnedFeatureID` | `null` | feature pinned on that screen (`"workspaces"` / `"agents"` / `"notes"`) |

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
│   ├── FeaturePanel.swift      shared drop-down canvas (one width/padding/header for all features)
│   ├── Workspaces/
│   │   ├── WorkspaceStore.swift    snapshot, hook listener + fallback polling, NotchFeature
│   │   ├── WorkspacesStatusStrip.swift active-workspace capsule (name + app icons)
│   │   └── WorkspacesFeatureView.swift  the drop-down grid (max 5 pills per row)
│   └── Agents/
│       ├── AgentSession.swift      session model + status severity
│       ├── HerdrClient.swift       `herdr agent list` polling backend (herdr owns detection)
│       ├── AgentSessionStore.swift poll loop + hysteresis, NotchFeature
│       ├── AgentsStatusStrip.swift the always-on left-of-notch capsule (glyphs + dots)
│       ├── AgentGlyph.swift        Claude starburst (drawn, monochrome) + fallback glyphs
│       └── AgentsFeatureView.swift session list rows (click → focus herdr pane)
│   └── Notes/
│       ├── NoteItem.swift          AppTodo / ObsidianTodo / persisted payload
│       ├── ObsidianTodoScanner.swift vault discovery + `- [ ]` scan + checkbox write-back
│       ├── NotesStore.swift        app todos persistence, scan loop, NotchFeature
│       ├── NotesStatusStrip.swift  the left-cluster capsule (glyph + open count)
│       └── NotesFeatureView.swift  the to-do drop-down (add row, heatmap, todo list)
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
- **Open**: hover/tap the capsule (or `AeroNotch ping-agents`) → the Agents list
  hangs from the notch itself. One row per session; click jumps to that herdr pane
  (`herdr agent focus <pane>`). While a card is pinned, hovering the capsule shows
  the Agents list over the pinned panel without disturbing the pin.
- Only agents running **inside herdr** are visible — by design (herdr is the
  single source of truth for status). Poll failures blank the capsule after 2
  consecutive errors (hysteresis), never on a single hiccup.

## Notes

- v1 targets the common cases; the closed-notch geometry handles notched and
  notch-less displays (fake notch bar on external monitors).
- Icons resolve from running apps first, so apps outside /Applications still get icons.
