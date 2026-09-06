# Validation

This is a source alpha. Keep observed behavior separate from integrations that are implemented but still need a hardware smoke test.

## Automated checks

Run `./scripts/check.sh`. The 114 deterministic checks exercise:

- Presentation priority, editor/drag locks, dismissal and repeated expansion cycles.
- Timer input boundaries, presets, motivational states, pause/edit/resume/reset, legacy persistence, expiry after elapsed time and one-time completion.
- English date formatting and app-owned guidance for localized external, permission, missing-file and full-disk errors.
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

### Compact panel, focus timer and English-first update

- All 114 deterministic checks pass, including a separate run with Russian process locale overrides.
- The expanded section is 212 pt; the visible panel is 244 pt tall with the 32 pt strip on this display. The prior visible height was 276 pt. Default width remains 720 pt. The AppKit envelope and pointer/drop geometry use the same shared metrics.
- The real interface was inspected for Media, Calendar, Timer, Notes, Tasks, Shortcuts, inactive Mirror, and empty/populated Tray. A temporary long-filename tray fixture was inserted through the real ShelfRepository and inspected in the UI; this does not claim a successful native file-picker or outgoing drag test.
- Real keyboard checks covered selecting and replacing digits, multi-digit input, Tab between fields, Return to confirm without starting, invalid input disabling Start, Escape cancelling the draft, and a second Escape closing the panel.
- Start, Pause, editing the paused remainder, Resume, completion and all four motivational captions were inspected. Reset was retested while running, paused, completed and editing, including an ordinary mouse click. It restores the selected duration; it does not clear the duration to zero. The button has a full capsule hit area and explains the target duration in its tooltip.
- Native text fields are recreated when returning from the read-only countdown. AppKit owns the active text selection; SwiftUI ticks do not overwrite the field editor. The display clock is synchronized at Start/Resume to avoid an extra second in the first frame.
- App-owned copy and date labels use English; user-provided names, notes and shortcut titles keep their original language. Native macOS dialogs may follow system settings. The duplicate Russian README was removed after confirming its instructions are covered in English.
- Gitleaks 8.30.1 was downloaded from its official release with checksum verification. Full working-directory, two-commit history, installed-bundle and extracted executable-string scans reported no secrets. The final staged diff is also scanned before committing.
- Cleanup removed an unused ShortcutsWidget model dependency and fixed temporary text-import cleanup on failure. The legacy serialized shortcuts field is retained for compatibility. Build caches and validation fixtures are excluded from Git.

The final debug and release builds passed without compiler warnings. The installed release passed strict signature verification; executable UUID `98170B1F-8892-3388-BD1F-4FF8ACE8E33F` matches the release build. It was launched with Russian language/locale arguments: Calendar, panel and timer labels remained English. Installed Start/Pause/Reset returned 04:54 to the selected 05:00 and cleared progress. Temporary tray data was removed, and the original timer configuration was restored.

Calendar/camera permission grants, active camera capture, physical hover across all displays, AirDrop delivery, and Spotify playback remain separate hardware/provider acceptance checks.

### Button hit-area fix

- Before the fix, two coordinate clicks in the Timer dock button's empty padding did nothing; clicking the icon switched immediately. The inactive Tray tab had the same text-versus-padding behavior.
- Plain button labels now define their full interaction bounds after layout: Home/Tray, the widget dock, calendar day/event rows, Shortcuts cards, Settings navigation and timer controls. Timer preset padding and backgrounds now belong to the label. Appearance, layout, disabled states and panel activation policy are unchanged.
- The installed release passed the original Timer/Tray padding clicks, both sides of several dock buttons, five consecutive Home/Tray round trips, all four timer preset edges, Start/Pause/Resume and Reset. Clicking the gap between dock buttons did not switch widgets; clicking a disabled preset did not change the running timer.
- A click in the empty portion of a calendar day selected exactly that day. All six Settings sidebar rows responded at their empty right edges. The coordinate driver for the centered Settings window was calibrated against a temporary native event trace; that instrumentation was removed before the final build.
- Invalid timer input disabled Start; Escape restored the draft, Tab moved between fields, Return confirmed without starting, and Escape then closed the panel. The original ready 50-minute timer and today's calendar selection were restored.
- All 114 deterministic checks passed. Final debug/release builds completed without compiler warnings; the installed release passed strict signature verification and its executable UUID `56AB6FC8-959D-3347-9D2F-B38D10819AB0` matched the release build. There are no new core checks for this change: the regression is in native hit testing, not the Foundation state model.
- Cleanup moved the obsolete README preview, layout fixtures and four old root-level build logs to Trash. The preview's documentation symlink was not followed. Build caches, the pre-validation timer backup, security tools, documentation assets, licenses and vendored sources were retained. Temporary click diagnostics were removed from source and local outputs.
- The user confirmed that, with another app active, hovering over the notch and clicking the empty edge of Timer or Tray switches on the first click. This is user-confirmed on this Mac; other displays and macOS versions remain separate acceptance checks. Calendar permission-dependent event actions and execution of user Shortcuts were not exercised by this pass.

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
