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
launcher. They cover ownership, failure handling, launch ambiguity, lock
inheritance, scratchpad placement, and scaled/rotated geometry. The Node tests
execute the QML controller's JavaScript completion callback with controlled
process results to cover startup, queued intent, and failure recovery.

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
