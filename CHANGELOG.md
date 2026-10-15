# Changelog

## v0.1.10 - 2026-10-15

- Close the Codex popover on outside clicks, application switches, and Escape; remove event monitors immediately when closed.
- Keep the disk menu stable while open so periodic refresh cannot interrupt dismissal.
- Implement the disk details shortcut and add popup lifecycle regression tests.

## v0.1.9 - 2026-10-15

- Compress previous app versions instead of leaving indexed app bundles behind after upgrades.
- Use the app standard preference domain for disk settings and add explicit opt-in/out CLI controls.
- Show disk capacity and a details shortcut in the resident dashboard.

## v0.1.8 - 2026-10-15

- Add an opt-in, independent disk menu bar item with capacity details and low-space colors.
- Start disk reads and the monitoring timer only after opt-in; cancel monitoring and reject in-flight results on opt-out.
- Mark Codex snapshots and disk readings with a warning when they are stale for 180 seconds or reads fail.
- Check freshness independently of refresh completion and immediately after system wake.
- Discard resident stdout/stderr instead of appending periodic logs; keep disk snapshots in memory.
- Add privacy declarations, settings and lifecycle regression tests, and a local Command Line Tools fallback.

## v0.1.7 - 2026-10-14

- Name quota windows from their actual duration, including weekly primary windows.
- Hide expired quota percentages until a new local snapshot arrives; preserve observed reset times.
- Cache unchanged session token events and skip duplicate cumulative usage notifications.
- Support CODEX_HOME, timer tolerance, and refresh after system wake.
- Install only the native menu bar app with one login agent and preserve the previous app on upgrade.
- Add regression tests for quota windows, duplicate events, malformed logs, and cache invalidation.

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
