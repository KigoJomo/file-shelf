# Development and validation

Link a checkout for local development only when the destination does not already
exist. Do not overwrite an installed plugin.

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/kigojomo.file-shelf
omarchy-shell shell rescanPlugins
# Discovery is asynchronous. Wait until listPlugins includes the ID.
omarchy-shell shell listPlugins
omarchy plugin enable kigojomo.file-shelf
```

Saving plugin code reloads it in the shell. A linked development checkout does
not use the normal `omarchy plugin update` workflow. Switch it back to a normal
installation when development is finished.

## Automated checks

```bash
omarchy plugin validate .
bash -n bin/file-shelf-nautilus
python -m unittest discover -s tests -v
node --test tests/service.test.mjs
git diff --check
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Service.qml Widget.qml
```

The Python tests execute the real helper with a stateful fake compositor and
D-Bus service. They cover ownership, concurrent launches, interrupted setup,
lost replies, path encoding, scratchpad placement, and scaled/rotated geometry.
The Node tests execute the QML controller's JavaScript completion callback with
controlled process results to cover startup, queued intent, and failure recovery.

Standalone Qt 6 `qmllint` cannot resolve the shell's `qs.*` runtime imports and
some Quickshell types. Its warnings are not a clean runtime pass. Check actual
loading in Omarchy and inspect the user journal for QML errors. Do not use the
unrelated Qt 5 `qmllint` binary.

## Runtime checklist

Use sample files and preserve unrelated application windows.

- [ ] Enable the service and confirm the folder icon and edge handle appear.
- [ ] Show, hide, and reopen. Confirm the same address and folder are reused.
- [ ] Focus another app. Confirm the window is parked and the bar is inactive.
- [ ] Focus a native Nautilus dialog. Confirm the shelf stays available.
- [ ] Rescan/reload while the shelf is open. Confirm state and focus handling recover.
- [ ] Rapidly alternate show/hide and confirm the latest intent wins.
- [ ] Exercise left, bottom, and right. Check the reserved bar area remains clear.
- [ ] Open with a visible scratchpad and confirm both windows remain available.
- [ ] Test invalid monitor/edge values and recovery after manually closing Nautilus.
- [ ] Check the bar position menu with pointer and keyboard.
- [ ] On suitable hardware, test display reconnect and scale/resolution changes.

## Automatic launch ownership

A new window request uses the normal Nautilus D-Bus service and a private,
randomly named empty directory. The helper matches that URI in Nautilus's
`OpenWindowsWithLocations` property, and matches its unique folder title and
the service owner's PID in Hyprland. It checks and tags the window in one Lua
compositor operation, then parks it while preparing Home.

For the first map, a temporary named Hyprland rule parks new Nautilus windows
before their bootstrap title is available. The helper disables the rule after
tagging its own window or on failure, and restores unrelated Nautilus windows
that appeared during the same brief interval. It floats and sizes the shelf
while hidden, then moves it to the visible workspace as the final step.

All navigation actions address the exact GTK window path on the **unique**
D-Bus owner, so another Nautilus process cannot take over a request addressed
to a service name. A fresh Home tab replaces the bootstrap tab, leaving the
active tab with a clean Back history. Empty bootstrap directories are removed
with `rmdir`; any files someone puts there are preserved. Existing user tabs
and unrelated windows are never used for this initialization.

The in-progress request is saved in `file-shelf.window`. A retry after a lost
reply or failed preparation resumes that same request/window. Unknown or
changed contents are left untouched. The helper never falls back to selecting
the first newly visible Nautilus window.

This needs the D-Bus interfaces/actions shipped by Nautilus and Hyprland's Lua
`hl.get_window`/`hl.dsp.window.tag` support. Runtime validation used Nautilus
50.2.2 with Omarchy 4.0.2 and Hyprland 0.56.2. No Python module, extension,
additional package installation, private session bus, or user configuration is
needed by the plugin. `busctl` is provided by systemd.

Relevant upstream implementation:

- [Nautilus application Open and window-to-location mapping](https://github.com/GNOME/nautilus/blob/main/src/nautilus-application.c)
- [Nautilus window actions and fresh-tab creation](https://github.com/GNOME/nautilus/blob/main/src/nautilus-window.c)

For the opt-in desktop concurrency check, run `python tests/live_launch.py`.
It opens temporary test windows, checks that existing windows retain their
workspace and tags, and closes only the windows it created and verified.
Do not run it while interacting with the test windows.

## Marketplace publication

The marketplace currently renders the manifest description and one preview. It
does not render this repository's README or a screenshot gallery. Keep the
manifest description within its 500-character limit. Root `preview.png` is
automatically discovered; the additional images are for the README.

Listing content comes from an exact approved snapshot. Merging this repository
alone does not replace the published description or preview.

After the ready-for-review PR is merged:

1. Copy the full 40-character commit SHA of the repository's current `main`.
2. Open the [plugin verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml).
3. Select **Verify and publish a newer upstream commit**.
4. Supply `kigojomo.file-shelf`, `https://github.com/KigoJomo/file-shelf`, and that SHA.
5. Wait for the compatibility/baseline reports and marketplace maintainer approval.
6. Confirm the live listing shows version 0.4.0, the expanded summary, and preview.

See the marketplace's [publication rules](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md#promoting-a-plugin-update).
Do not claim the older verification badge covers a new commit.
