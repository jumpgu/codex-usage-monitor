# Changelog

## v0.1.6 - 2026-06-17

Quota priority release.

- Let the menu bar automatically switch to the 7-day quota when the weekly window is the tighter limit.
- Keep the expanded popover unchanged so both 5-hour and 7-day windows remain visible.
- Bump the macOS app bundle version to 0.1.6 (7).

## v0.1.5 - 2026-06-16

Maintenance release.

- Add uninstall and reinstall scripts.
- Document the local independent Git repository workflow with GitCode and GitHub remotes.
- Ignore generated app iconset files in the repository.

## v0.1.4 - 2026-06-16

Usage detail release.

- Show cached and non-cached token usage separately in the popover and main dashboard.
- Keep the compact row layout while adding cache hit/miss detail.

## v0.1.3 - 2026-06-15

Display polish.

- Show 5-hour reset as clock time only, even when it lands on the next day.
- Keep 7-day reset dates visible.

## v0.1.2 - 2026-06-15

Bugfix release.

- Fix expired 5-hour window fallback so reset time keeps the original minute/second cadence.
- Stop forcing expired-window usage to 0%, avoiding false `100%` remaining displays.

## v0.1.1 - 2026-06-15

Polished menu bar release.

- Add compact menu bar display with Codex badge, colored quota bar, remaining percent, and reset time.
- Redesign the expanded popover with a centered title, compact rows, and quota-color progress bar.
- Redesign the main app window as a lightweight dashboard.
- Keep menu bar text stable during refreshes.
- Remove non-cache details from the primary UI.

## v0.1.0 - 2026-06-15

Initial public release.

- Add macOS menu bar monitor for Codex usage.
- Show remaining 5-hour quota in the menu bar.
- Show 5-hour and 7-day reset times.
- Refresh local usage summary every 60 seconds.
- Read local Codex session logs only.
- Install LaunchAgents for background collection and menu bar startup.
- Generate and package a native macOS app icon.
