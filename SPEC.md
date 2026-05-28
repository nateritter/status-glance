# StatusGlance — Build Spec

A minimalist macOS menu-bar app that shows the live operational status of an
Atlassian-Statuspage-powered service (default: claude.ai) as a colored glyph in
the menu bar. Click the glyph to open a compact popover that mirrors the public
status page — overall status, per-component states, and active incidents.

**Goal:** let the user close the status page browser tab and glance at the menu
bar (or click the glyph) to know if something is broken at the monitored service.

## Platform / Stack (locked)

- **macOS 14+**, Swift 6.1, Xcode 16.3 toolchain.
- **AppKit** `NSStatusItem` for the menu-bar item; **SwiftUI** for popover + settings content (hosted via `NSHostingView` / `NSPopover`).
- **Swift Package Manager** executable target. A `Makefile` assembles a proper
  `StatusGlance.app` bundle (with `Info.plist`, `LSUIElement = true` so there is
  no Dock icon). `swift build` / `swift run` must work for development.
- No third-party dependencies. Foundation `URLSession` only for networking.

## Data source — Atlassian Statuspage v2 API (verified live)

Base URL is the configured status page origin (default `https://status.claude.com`).

- `GET {base}/api/v2/summary.json` — the single endpoint we poll. Returns:
  - `page`: `{ id, name, url, time_zone, updated_at }`
  - `status`: `{ indicator, description }`
  - `components`: array of `{ id, name, status, position, group, group_id, only_show_if_degraded, showcase, description }`
  - `incidents`: array of `{ id, name, status, impact, shortlink, started_at, updated_at, incident_updates: [{ body, status, created_at }] }` (empty when healthy)
  - `scheduled_maintenances`: array (same shape family as incidents)

### Overall `status.indicator` → color (verified values)

| indicator    | meaning                 | color name | hex      |
|--------------|-------------------------|------------|----------|
| `none`       | All Systems Operational | green      | `#3FB950` |
| `minor`      | Minor issue             | yellow     | `#F0B429` |
| `major`      | Major outage            | orange     | `#F0883E` |
| `critical`   | Critical outage         | red        | `#E5484D` |
| `maintenance`| Maintenance             | blue       | `#3B82F6` |
| (none of the above) | unknown / offline / fetch failure | gray | `#8B949E` |

### Component `status` → color

| component status        | color  |
|-------------------------|--------|
| `operational`           | green  |
| `degraded_performance`  | yellow |
| `partial_outage`        | orange |
| `major_outage`          | red    |
| `under_maintenance`     | blue   |

Define a single `ServiceStatus` enum + `StatusColor` mapping used by both the
menu-bar glyph tint and the popover dots. Keep the mapping in ONE place.

## Menu-bar glyph

- `NSStatusItem` with `variableLength`. The button image is a **template-style
  glyph tinted by the current overall status color** (not the default monochrome
  template behavior — we want color).
- **Default glyph:** the Unicode character **`✽` (Heavy Teardrop-Spoked
  Asterisk, U+273D)** rendered in code as an `NSImage` — draw the `✽` character
  with a system font sized to fit the menu bar (~`NSFont.systemFont(ofSize:)`
  around 14–15pt for an 18pt status image), centered, into an `NSImage` via
  `NSImage(size:flipped:drawingHandler:)`, then tint it with the status color.
  Keep it simple: just the `✽` glyph, no spark/circle/custom vector.
  NOT a bundled third-party logo.
- **Custom logo (optional, local only):** if the user sets a custom logo image
  path in settings, load that image, render it as a template, and tint it with
  the status color. This is how the user can use their own Claude logo locally
  WITHOUT the repo ever bundling a trademarked asset. README must state this
  clearly.
- Tooltip on the glyph = page name + overall description (e.g. "Claude — All
  Systems Operational").

## Popover (click the glyph)

Minimalist, mirrors the status page. Dark navy palette like the reference
screenshot. Fixed width ~300pt, height fits content. Sections top→bottom:

1. **Header:** page name (e.g. "Claude") + colored overall status pill with
   `status.description`. A small "updated Xm ago" relative timestamp from
   `page.updated_at`.
2. **Components:** list rows, each = colored status dot + component name +
   (optional) right-aligned status label. Respect `only_show_if_degraded`
   (hide those rows when operational). Indent components that belong to a group.
3. **Active incidents** (only if `incidents` non-empty): incident name, impact,
   latest update body (truncated), and relative time.
4. **Footer:** a refresh button (manual poll), a link "Open status page" that
   opens `page.url` in the browser, a Settings button (gear), and Quit.

Palette (popover): background `#0F1420`-ish dark navy, section headers in a muted
blue `#5B8DEF`/`#7AA2F7`, primary text near-white `#E6EDF3`, secondary text
`#8B949E`. Use SwiftUI `Color` constants in one `Palette` file. Match the
reference screenshot's vibe — clean, dense, dark.

## Settings window (or popover-anchored sheet)

Editable, persisted to `UserDefaults`:

- **Status page URL** (string, default `https://status.claude.com`) — validate it
  has `/api/v2/summary.json` reachable; show a check/✗.
- **Display name** (optional override; otherwise use `page.name` from the API).
- **Poll interval** (seconds, default `60`, min `15`).
- **Custom logo image path** (optional file path; empty = built-in glyph).
- **Launch at login** (toggle) — use `SMAppService.mainApp` (ServiceManagement,
  macOS 13+). Best-effort; guard with availability.

## Polling

- `StatusPoller`: `URLSession` data task to `{base}/api/v2/summary.json` on a
  repeating `Timer` at the configured interval, plus an immediate poll on launch
  and on manual refresh, plus a poll on `NSWorkspace` wake-from-sleep
  notification.
- On network failure / non-200 / decode error → set overall status to a "gray /
  unknown" state, keep last-known component data, show a subtle error note in the
  popover footer. Never crash; never show stale data as if it were live without
  indicating the fetch failed. (Honest-metrics principle: show real or unknown,
  never fake.)
- Decode with `JSONDecoder` + `convertFromSnakeCase`. Use lenient enums:
  unknown indicator/component-status strings decode to an `.unknown` case
  (gray), never throw.

## File manifest (Sources/StatusGlance/)

- `main.swift` — `NSApplication` bootstrap, `setActivationPolicy(.accessory)`, set delegate, run.
- `AppDelegate.swift` — owns `StatusItemController`, `StatusPoller`, settings; wires them together.
- `StatusItemController.swift` — `NSStatusItem`, glyph rendering/tinting, popover show/hide, menu (right-click) with Refresh/Settings/Quit.
- `GlyphRenderer.swift` — draws the built-in default glyph and tints any image (built-in or custom) to a given `NSColor`.
- `StatuspageClient.swift` — async fetch + Codable models (`Summary`, `PageInfo`, `OverallStatus`, `Component`, `Incident`, `IncidentUpdate`) matching the JSON above.
- `ServiceStatus.swift` — `Indicator` + `ComponentStatus` enums (lenient decoding) and the single color mapping.
- `StatusPoller.swift` — timer-driven polling, wake observer, publishes latest `Summary` / error via a callback or `@Published` (ObservableObject).
- `AppSettings.swift` — `UserDefaults`-backed observable settings model + launch-at-login.
- `Palette.swift` — SwiftUI `Color` + `NSColor` palette constants and status→color helpers.
- `PopoverView.swift` — SwiftUI popover content (header, components, incidents, footer).
- `SettingsView.swift` — SwiftUI settings form.

## Packaging / repo root

- `Package.swift` — SPM executable `StatusGlance`, macOS 14 platform.
- `Makefile` — targets: `build` (`swift build -c release`), `app` (assemble
  `StatusGlance.app` with `Info.plist` containing `LSUIElement`=true, bundle id
  `com.nateritter.statusglance`, copy release binary into
  `Contents/MacOS/`), `run`, `clean`, `install` (copy `.app` to `/Applications`).
- `Info.plist` template (or generated by the Makefile via `PlistBuddy`/heredoc).
- `README.md` — what it is, screenshot placeholder, build/run/install
  instructions, configuration, the **custom-logo + trademark note**, and a clear
  statement that this is an independent project, not affiliated with or endorsed
  by Anthropic, and that "Claude"/"Anthropic" are trademarks of their owner.
- `LICENSE` — MIT, copyright Nate Ritter.
- `.gitignore` — `.build/`, `.DS_Store`, `*.xcuserstate`, `DerivedData/`, `StatusGlance.app/`.

## Acceptance criteria

1. `swift build` compiles clean with no errors (warnings minimized).
2. `make app && open StatusGlance.app` launches with a colored glyph in the menu
   bar and NO Dock icon.
3. With live `status.claude.com`, the glyph is green and the popover shows the
   real components (claude.ai, Console, API, Claude Code, Cowork, Government) all
   operational.
4. Changing the status page URL in settings re-points the app and re-polls.
5. Network failure shows gray glyph + error note, not a crash or fake-green.
6. The repo bundles NO trademarked logo asset; default glyph is drawn in code.
