# Workspace Pill + Left Flyout — Design

**Date:** 2026-07-21
**Status:** Approved (pending spec review)

## Goal

Rework the existing **"Menu Bar Strip"** presentation mode (`AeroNotchConfig.PresentationMode.menuBarLeft`)
so the workspace popup is a **pill that expands leftward along the menu bar on hover**, instead of a
notch-shaped panel that drops downward from screen-center.

The **"Notch"** mode (`.notch`) is untouched — it remains the downward-drop alternative.

## Current behavior (what we're replacing)

In `menuBarLeft` mode today (`NotchContentView.menuBarModePanel`), the closed indicator is a small fake
notch shape centered on the notch. On workspace-switch peek **or** hover it expands into a notch-shaped
panel that widens symmetrically around screen-center and grows **downward**, hosting whichever feature is
active. The agent status strip is pinned to the notch's left edge.

## Target behavior

### Resting state

```
[ ● 3 ] [ agents ] ▐███NOTCH███▌
  ^pill   ^strip     ^notch
```

- A **workspace pill** — a rounded capsule matching the `AgentsStatusStrip` visual language
  (black fill, hairline `Color.white.opacity(0.15)` stroke) — showing the **focused workspace name**.
- Left-to-right ordering: **workspace pill (leftmost/outboard) → agent strip → notch.**
  Putting the workspace pill outboard gives its flyout unlimited room to grow left without
  colliding with the agent strip.
- Position is notch-aware:
  - **Hardware notch present:** pill sits just left of the notch cutout (screen-center is occupied
    by hardware), offset further left by the agent strip's width when the strip is showing.
  - **No hardware notch** (external display): the "notch" is a fake shape at screen-center; the pill
    sits just left of it, same relative placement.

### Hover state

```
[ 1  2 ▸3◂ 4  5 ] [ agents ] ▐███NOTCH███▌
└── pill morphed left ──┘
```

- On **hover of the pill only**, the pill **morphs** (one continuous capsule, not a separate popup)
  **leftward** to reveal the full workspace pill row, focused workspace highlighted.
- Stays at **menu-bar height** — no downward drop.
- Anchored at the pill's **right edge**; width grows to the **left**.
- Leaving the pill collapses it back to the resting pill (with the existing brief hover-close grace period).

### Triggers

- **Pill hover** expands the flyout and holds it open while hovered.
- **Workspace switches also peek** the flyout: a switch transiently expands the pill into the full row
  (via the existing `peek()` path), then it auto-collapses back to the resting label after
  `peekDurationSeconds`. Same peek behavior as `.notch` mode.
- The agent strip retains its own independent hover→Agents behavior (unchanged).

## Components & changes

### `NotchContentView.swift`
- Replace `menuBarModePanel` so that in `menuBarLeft` mode:
  - The workspace content renders as a hover-expanding capsule, at menu-bar height, right-anchored,
    growing left — no `NotchShape`, no downward growth, no symmetric-around-center widening.
  - Resting = pill sized to the focused-workspace label; hovering = pill sized to the measured
    workspace row width (reuse the existing `openContentWidths` measurement plumbing).
  - Lay out **workspace pill → agent strip → notch** left-to-right, anchored `.topTrailing` off the
    notch's leading edge (reuse the existing left-extending window and trailing-padding approach).
- The pill's resting content: focused workspace name. Reuse `WorkspaceStore` snapshot
  (`visibleByMonitor` / `focused`) already available to `WorkspacesFeatureView`; the compact pill can
  render just the name (optionally its focused-app icon later — not in scope).

### `WorkspacesFeatureView.swift`
- Already reports its ideal row width via `reportOpenContentWidth`; already renders `compact` pills in
  `menuBarLeft` mode. The flyout reuses this as-is. Add a compact **resting label** rendering path
  (focused workspace only) if it's cleaner to own it here than in `NotchContentView`.

### `NotchViewModel.swift`
- No new state required for open/close (hover already drives `.open`/`.closed`).
- The workspace-switch peek must be suppressed in `menuBarLeft` mode — see AppDelegate.

### `AeroNotchApp.swift` (`AppDelegate`)
- `peekRelevantNotch()` / `onFocusedWorkspaceDidChange`: in `menuBarLeft` mode, do **not** call
  `viewModel.peek()` for workspace switches — the pill updates its label reactively via the store; only
  hover expands. (`peekAll` from the menu action and the agents `ping` path are separate and unchanged.)
- Window geometry for `menuBarLeft` (already left-extending from screen leading edge to past the notch)
  is reused; confirm width still accommodates the widest workspace flyout (`panelMaxWidth`).

## Non-goals / YAGNI

- No new config keys, no new menu items. "Menu Bar Strip" label stays.
- No change to `.notch` mode.
- No flash/animation on workspace switch.
- No app-icon rendering inside the resting pill (future, if wanted).

## Open questions

- None blocking. The resting-pill label uses the plain workspace name; if a workspace has no name it
  falls back to whatever `WorkspaceStore` reports (same as today's pills).
