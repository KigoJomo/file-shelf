# File Shelf

`kigojomo.file-shelf` is an Omarchy shell plugin that puts Nautilus on a
screen edge. Rest the pointer on the edge or call the plugin over IPC, and a
managed Nautilus window appears at that edge so files can be browsed directly.

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

- Rest the pointer on the configured edge to show Nautilus.
- Click the edge handle to toggle it.
- Browse, search, open, copy, move, and manage files using normal Nautilus
  behavior.
- Move the pointer wherever you need; the browser stays open until it is
  explicitly toggled or hidden.

The initial edge is the right side of the first available monitor. The choice
of edge and monitor is stored in `~/.local/state/omarchy/file-shelf.json`.
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

`position` accepts `left`, `right`, `top`, or `bottom`. The window becomes a
tall side panel on the left/right and a wide panel on the top/bottom. The
plugin does not add a Hyprland keybinding automatically; add one in your own
bindings if desired, for example:

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
qmllint -I "$OMARCHY_PATH/shell" Service.qml
bash -n bin/file-shelf-nautilus
```

After QML changes, restart the shell if the service window does not reload:

```bash
omarchy restart shell
```

## License

MIT. See [LICENSE](LICENSE).
