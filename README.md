# File Shelf

`kigojomo.file-shelf` is an Omarchy shell plugin that puts Nautilus on a
screen edge. Rest the pointer on the edge or use the bar folder icon, and a
managed Nautilus window appears at that edge so files can be browsed directly.
The plugin also adds a folder icon to Omarchy's Quickshell bar for quick
access. Omarchy's default bar is Quickshell-based rather than a standalone
Waybar module. Its tooltip explains the two clicks: left-click opens/retracts
the shelf, while right-click opens an explicit position chooser.

## Important limitation

Nautilus is a separate GTK/Wayland application. Wayland does not provide a
general protocol for embedding one client's surface inside a Quickshell layer
surface, so this plugin cannot literally re-parent Nautilus into QML. The
result is the same user-facing workflow: the plugin owns a narrow edge target
and manages one real Nautilus window beside it.

## Install

From a public repository:

```bash
omarchy plugin add https://github.com/KigoJomo/file-shelf.git --enable --yes
```

For local development, link this checkout into Omarchy's plugin directory:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/kigojomo.file-shelf
omarchy-shell shell rescanPlugins
omarchy plugin enable kigojomo.file-shelf
```

The plugin needs Omarchy 4+, Nautilus, Hyprland, `jq`, `flock`, `awk`, and
`uwsm-app`. Nautilus and the other command-line dependencies are already part
of the normal Omarchy setup; the plugin does not install packages.

## Use

- Click the bar folder icon, or rest the pointer on the configured edge, to show
  Nautilus.
- Press `Super + E` to open or retract it from anywhere.
- Right-click the bar folder icon to choose `Left`, `Bottom`, or `Right` in the
  position menu. The selected edge is remembered.
- Click the edge handle to toggle/retract the shelf.
- Browse, search, open, copy, move, and manage files using normal Nautilus
  behavior.
- When Nautilus loses focus, the shelf retracts to a special workspace. The
  Nautilus window is parked rather than closed, and its current folder stays
  intact, so reopening it preserves your context.
- If the scratchpad is visible, the shelf shares that special workspace while
  it is open, so both windows remain available for drag-and-drop.

The initial edge is the right side of the first available monitor. The choice
of edge and monitor is stored in `~/.local/state/omarchy/file-shelf.json`.
Supported edges are `left`, `bottom`, and `right`.
The managed window address and a short-lived control lock are stored beside
it. The window is never killed or closed by the plugin: hiding parks it in the
private `special:file-shelf` Hyprland workspace, and removing the plugin leaves
the Nautilus process untouched.

## IPC and command line

The service exposes the `file-shelf` IPC target:

```bash
omarchy-shell file-shelf show
omarchy-shell file-shelf hide
omarchy-shell file-shelf toggle
omarchy-shell file-shelf position left
omarchy-shell file-shelf monitor HDMI-A-1
omarchy-shell file-shelf status
```

`position` accepts `left`, `bottom`, or `right`. The window becomes a tall side
panel on the left/right and a wide panel along the bottom. The bar's
right-click position menu persists the choice. The default binding is
`Super + E`; add or change it in your own bindings if desired, for example:

```lua
o.bind("SUPER + ALT + D", "File Shelf", "omarchy-shell file-shelf toggle")
```

## Safety and ownership

The helper only acts on a Nautilus window whose class is
`org.gnome.Nautilus`, and it validates Hyprland window addresses before using
them. It only moves/resizes/focuses that window. It never deletes files,
changes Nautilus settings, kills Nautilus, or uses elevated privileges.

## Development and validation

```bash
omarchy plugin validate .
QT6_QMLLINT="${QT6_QMLLINT:-/usr/lib/qt6/bin/qmllint}"
"$QT6_QMLLINT" -I "$OMARCHY_PATH/shell" Service.qml
"$QT6_QMLLINT" -I "$OMARCHY_PATH/shell" Widget.qml
bash -n bin/file-shelf-nautilus
```

Use a Qt 6 `qmllint`; the system `qmllint` on some Omarchy installations is
the unrelated Qt 5 binary. The `qs.*` warnings are expected outside the live
Quickshell shell; the shell reload below is the runtime check.

After QML changes, restart the shell if the service window does not reload:

```bash
omarchy restart shell
```

Runtime smoke test:

- Confirm `omarchy-shell shell ping` returns `ok` and the folder icon is in the
  bar.
- Open with `Super + E`, move focus to another window, and confirm the shelf
  retracts while Nautilus remains open.
- Open it again and confirm the same folder is still shown.
- With the scratchpad visible, open the shelf and confirm both windows remain
  available in the scratchpad workspace.
- Use the bar icon's right-click menu to exercise `Left`, `Bottom`, and
  `Right`, then confirm the choice survives a shell restart.

On this Omarchy host, the default `Super + E` shortcut is installed in the
user's `~/.config/hypr/bindings.lua`. Omarchy plugins cannot run install hooks or
modify Hyprland user config, so a new host should add the same one-line binding
manually:

```lua
o.bind("SUPER + E", "File Shelf", "omarchy-shell file-shelf toggle")
```

If that key is already customized, keep the existing binding and use the bar
icon or an alternate binding instead.

## License

MIT. See [LICENSE](LICENSE).
