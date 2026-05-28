# StatusGlance

A minimalist macOS menu-bar app that shows the live operational status of any
[Atlassian Statuspage](https://www.atlassian.com/software/statuspage)-powered
service as a single colored glyph in your menu bar. Click the glyph for a
compact popover that mirrors the public status page — overall status, every
component with a per-day **history bar**, and active incidents. You choose
**which platform drives the menu-bar glyph** (e.g. track "Claude Code"
specifically), and the popover sizes itself to show every component without
scrolling.

**Why:** close the status-page browser tab. Glance at the menu bar (or click the
glyph) to know instantly whether something is broken at the service you monitor.
Green means all systems operational; yellow, orange, and red escalate from
there; gray means StatusGlance could not reach the page (it never shows stale
data as if it were live).

It ships pointed at `https://status.claude.com` by default, but works with **any
Atlassian Statuspage site** — just change the status page URL in settings.

> _Screenshot coming soon._ The default glyph is the character `✽` (Heavy
> Teardrop-Spoked Asterisk), tinted by status color — green when operational.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.1 / Xcode 16.3 toolchain (for building from source)

## Build / Run / Install

```sh
# Development: compile and run straight from source
swift build          # debug build
swift run            # build and launch for development

# Release: assemble a proper StatusGlance.app bundle (LSUIElement, no Dock icon)
make app             # -> ./StatusGlance.app
open StatusGlance.app

# Install into /Applications
make install
```

Other `make` targets: `build` (release binary only), `run`, `clean`, `help`.

## Configuration

Settings live in the in-app Settings window (open the popover, click the gear).
Changes **save automatically** and take effect when you close the window — there
is no Apply button, just **Close**.

| Setting | Default | Notes |
|---|---|---|
| **Status page URL** | `https://status.claude.com` | Any Atlassian Statuspage origin. The app polls `{url}/api/v2/summary.json` and shows a check/✗ for reachability. |
| **Menu bar tracks** | `claude.ai` | Which component's status colors the ✽ glyph. Pick **Overall status** or any single component (e.g. Claude Code). |
| **Poll interval** | `60` seconds | Minimum `15`. Also polls on launch, on manual refresh, and on wake-from-sleep. |
| **Launch at login** | off | Uses `SMAppService` (ServiceManagement, macOS 13+). |

The popover shows each component with a per-day **history bar** (green/yellow/
orange/red) reconstructed from the public incident feed, over the window the
feed actually covers (labeled "last N days") — it never paints days it has no
data for as operational.

## The glyph

The menu-bar glyph is the `✽` character (Heavy Teardrop-Spoked Asterisk, U+273D),
drawn entirely in code and tinted by the current status color. There are no
trademarked or third-party image assets bundled anywhere in this repository, and
no user-supplied images.

## Can't see the glyph?

If you run a **menu-bar manager** (Hidden Bar, Bartender, Ice, Dozer, etc.), a
newly launched app's status item often starts in the _hidden_ section. Reveal
it (expand the manager) and **⌘-drag** the `✽` into the always-visible area.
macOS itself also lets you ⌘-drag menu-bar items to reorder them. On a very full
menu bar, items can be clipped behind the active app's menus — quit a couple of
other menu-bar items or use a manager to make room.

## Disclaimer

StatusGlance is an independent, unofficial project. It is **not affiliated with,
sponsored by, or endorsed by Anthropic** (or any service it can be pointed at).
"Claude" and "Anthropic" are trademarks of Anthropic, PBC; all other product and
company names are the property of their respective owners. StatusGlance only
reads publicly available Atlassian Statuspage data via the public
`/api/v2/summary.json` endpoint.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Nate Ritter.
