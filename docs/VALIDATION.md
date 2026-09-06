# Validation

This is a source alpha. Keep observed behavior separate from integrations that are implemented but still need a hardware smoke test.

## Automated checks

Run `./scripts/check.sh`. The 58 deterministic checks exercise:

- Presentation priority, editor/drag locks, dismissal and repeated expansion cycles.
- Timer pause/resume, persistence, expiry after elapsed time and one-time completion.
- System media timestamp units, progress clamping and stale metadata clearing.
- Track identities, same-name songs, delayed artwork, A/B/A switching, pause/seek preservation, reconnect/stop invalidation and guarded Music system fallback.
- Shared panel geometry, compact/activity sizes, narrow screens and room for simultaneous messages.
- Atomic library persistence, backup recovery and preservation of corrupt files.
- Real file copies, duplicate names, restart persistence, removal failure, explicit moves and path traversal/recursive import rejection.

These are Foundation-based executable checks, not XCTest. The GitHub workflow runs the same checks and builds/signature-verifies the app; a workflow file alone is not a successful CI run.

## Local observations — 6 September 2026

Platform: Apple Silicon, macOS 26.6.2, Swift 6.3.3, Apple Command Line Tools.

- All 58 checks passed after the artwork, accent and panel-height changes (31 checks at the initial baseline).
- Debug and release applications and the Objective-C media adapter compiled; ad-hoc bundle signatures verified.
- At the initial baseline, a fresh source copy built in 40 seconds without the existing build cache. Its installer successfully installed into an isolated temporary destination and removed the staging app.
- The release app was installed at `~/Applications/NotchFree.app`; the staging duplicate was removed. The actual panel and settings were inspected through macOS accessibility and screenshots.
- A test note entered in the real editor was saved to disk and restored in the UI after quitting and relaunching the same installed bundle. The temporary note was then cleared.
- Now Playing displayed a real track, artist, duration and playback position.
- System settings read the actual output volume, built-in display brightness and battery percentage.

### Artwork, accent and panel-height update

- The updated debug and release builds passed. The installed release bundle passed strict signature verification and its executable UUID matched the release build.
- Apple Music displayed real artwork in both the expanded player and compact strip. Play/pause, several next-track changes, a change to a different album cover and a midpoint seek preserved the correct artwork. Three consecutive previous-track presses returned to the original song with its correct cover in both places. A long two-line title and artist fitted the player.
- Each of the six accent presets could be selected. Accent controls updated immediately, including the panel. Blue remained selected after quitting and reopening the same installed bundle; the original green was restored after testing.
- Before/after screenshots at the same display scale showed the same 720 pt width and a 28 pt reduction in visible height (304 to 276 pt on this display, including its 32 pt notch strip). The expanded section is now 244 pt.
- Media, Calendar, Timer, Notes, Tasks, Shortcuts, the inactive Mirror view and empty Tray fitted the reduced panel. Closing with the panel button and reopening from the compact strip worked. Calendar and camera permissions were not enabled for this inspection.
- The user subsequently confirmed the updated app worked and supplied a screenshot showing one PNG file in Tray. File presence and the populated Tray layout are user-confirmed; outgoing drag and AirDrop are not established by that screenshot.
- Spotify was at its login screen. The user explicitly chose to finish without a live Spotify test; its direct artwork integration is implemented but not verified with an authenticated player in this pass.
- A real track without artwork, visible error banners, physical hover behavior and the full set of file import/drag interactions were not fully exercised in this pass. Deterministic checks cover stale artwork rejection, missing artwork state and additional height for messages; these do not replace those live tests.

## Hardware acceptance checklist

Complete these on each supported macOS/hardware combination before calling it a stable release:

- [ ] Music and Spotify: play/pause, previous/next, seek, artwork, source changes and quit/reopen.
- [ ] Browser media session and a player that does not publish Now Playing.
- [ ] File/folder drop, Command-select and drag multiple files to Finder, promised file from another app.
- [ ] Quick Look and AirDrop recipient selection/cancel/completed transfer.
- [ ] Notes and tasks editing while moving the pointer outside; restart persistence through the UI.
- [ ] Timer expiry while active, sleep/wake and quit/relaunch.
- [ ] Calendar permission allow/deny, selected calendars, next-event activity.
- [ ] Camera allow/deny, camera switching and capture stopping after close/sleep.
- [ ] Shortcuts with success, cancellation and permission failure.
- [ ] Accessibility permission and physical volume/mute/brightness keys, including unsupported output devices.
- [ ] Bluetooth connect/disconnect, charging and low battery.
- [ ] Notched and unnotched displays, different scaling, multiple monitors, Spaces/fullscreen and hot-plug.
- [ ] Reduce Motion, VoiceOver, keyboard focus and idle CPU over a sustained session.
- [ ] Intel and minimum macOS 14.6 compatibility.

No camera, calendar, Bluetooth or Accessibility permission is silently granted by the installer. Testers enable only the integrations they want to exercise.
