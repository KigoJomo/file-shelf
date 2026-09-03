import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// File Shelf keeps the edge gesture from the original shelf idea, while the
// actual file browser remains Nautilus. Wayland does not allow a Quickshell
// layer surface to embed another client's GTK surface, so this service owns a
// narrow edge target and manages one regular Nautilus window beside it.
Scope {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property string edge: "right"
  property string screenName: ""
  property var targetScreen: null
  property bool opened: false
  property bool stateLoaded: false
  property string statusText: ""
  property string queuedOperation: ""
  readonly property int revealDelay: 220

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string statePath: stateDir + "/file-shelf.json"
  readonly property string helperPath: {
    var sourceDir = root.manifest && root.manifest.__sourceDir
      ? String(root.manifest.__sourceDir) : ""
    if (sourceDir)
      return sourceDir.replace(/\/$/, "") + "/bin/file-shelf-nautilus"
    return String(Qt.resolvedUrl("bin/file-shelf-nautilus")).replace(/^file:\/\//, "")
  }

  readonly property int edgeWidth: Style.space(8)
  readonly property int handleLength: Style.space(78)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property color accent: Color.accent
  readonly property color foreground: Color.foreground
  readonly property color handleBackground: Color.menu.background

  function normalizeEdge(value) {
    var next = String(value || "").trim().toLowerCase()
    return ["left", "right", "top", "bottom"].indexOf(next) !== -1 ? next : ""
  }

  function normalizeMonitor(value) {
    return String(value || "").trim()
  }

  function hasKnownScreen(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (root.isRealScreen(screens[i]) && screens[i].name === name)
        return true
    }
    return false
  }

  function isRealScreen(candidate) {
    return !!candidate && !!candidate.name && candidate.width > 0 && candidate.height > 0
  }

  function pickScreen() {
    var screens = Quickshell.screens || []
    var preferred = null
    var fallback = null

    for (var i = 0; i < screens.length; i++) {
      var candidate = screens[i]
      if (!root.isRealScreen(candidate))
        continue
      if (!preferred && candidate.name === root.screenName)
        preferred = candidate
      if (!fallback)
        fallback = candidate
    }

    var previous = root.targetScreen ? root.targetScreen.name : ""
    root.targetScreen = preferred || fallback
    if (!root.screenName && root.targetScreen) {
      root.screenName = root.targetScreen.name
      root.saveState()
    }

    if (root.opened && root.targetScreen && root.targetScreen.name !== previous)
      Qt.callLater(function() { root.invoke("show") })
  }

  function restoreState(raw) {
    try {
      var state = JSON.parse(String(raw || "{}"))
      var restoredEdge = root.normalizeEdge(state.edge)
      var restoredMonitor = root.normalizeMonitor(state.monitor)
      if (restoredEdge)
        root.edge = restoredEdge
      if (restoredMonitor)
        root.screenName = restoredMonitor
    } catch (error) {
      // A damaged preference file should never stop the shell plugin loading.
    }
    root.stateLoaded = true
    root.pickScreen()
    Qt.callLater(function() { root.invoke("status") })
  }

  function saveState() {
    if (!root.stateLoaded)
      return
    root.stateWritePending = true
    if (!stateDirectoryProc.running)
      stateDirectoryProc.running = true
  }

  function writeState() {
    if (!root.stateWritePending)
      return
    root.stateWritePending = false
    stateFile.setText(JSON.stringify({
      edge: root.edge,
      monitor: root.screenName
    }, null, 2) + "\n")
  }

  property bool stateWritePending: false

  function invoke(operation) {
    if (operation === "show" && !root.targetScreen)
      return

    if (controllerProc.running) {
      root.queuedOperation = operation
      return
    }

    root.queuedOperation = ""
    controllerProc.operation = operation
    controllerProc.command = [root.helperPath, operation]
    if (operation === "show")
      controllerProc.command = controllerProc.command.concat([
        root.edge,
        root.targetScreen ? root.targetScreen.name : root.screenName
      ])
    controllerProc.running = true
  }

  function open() {
    root.opened = true
    root.invoke("show")
  }

  function close() {
    root.opened = false
    root.invoke("hide")
  }

  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open()
  }

  function setEdge(value) {
    var next = root.normalizeEdge(value)
    if (!next)
      return root.edge
    if (next !== root.edge) {
      root.edge = next
      root.saveState()
      if (root.opened)
        root.invoke("show")
    }
    return root.edge
  }

  function setMonitor(value) {
    var next = root.normalizeMonitor(value)
    if (!next)
      return root.screenName
    if (!root.hasKnownScreen(next))
      return root.screenName
    root.screenName = next
    root.saveState()
    root.pickScreen()
    if (root.opened)
      root.invoke("show")
    return root.screenName
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreState(text())
    onLoadFailed: root.restoreState("{}")
    onFileChanged: reload()
  }

  Process {
    id: stateDirectoryProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: root.writeState()
  }

  Process {
    id: controllerProc
    property string operation: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.statusText = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.statusText = "error"
        if (controllerProc.operation === "show")
          root.opened = false
      }
      var next = root.queuedOperation
      root.queuedOperation = ""
      if (next)
        root.invoke(next)
    }
  }

  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: if (!root.opened) root.open()
  }

  Connections {
    target: Quickshell
    function onScreensChanged() { root.pickScreen() }
  }

  IpcHandler {
    target: "file-shelf"

    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function position(value: string): string { return root.setEdge(value) }
    function monitor(value: string): string { return root.setMonitor(value) }
    function status(): string { return root.statusText || "closed" }
  }

  Variants {
    // Keep a delegate per compositor screen and only show the selected one.
    // This avoids changing a null model during startup, which can make a
    // Quickshell 0.3 Variants delegate miss its first PanelWindow creation.
    model: Quickshell.screens || []

    delegate: Component {
      EdgeSurface {
        required property var modelData
        screen: modelData
        visible: !!root.targetScreen && modelData.name === root.targetScreen.name
      }
    }
  }

  component EdgeSurface: PanelWindow {
    id: window

    color: "transparent"
    WlrLayershell.namespace: "kigojomo-file-shelf"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // The surface occupies the monitor so the edge target can follow all
    // four orientations, but only the narrow region below accepts input.
    // Everything else remains available to Nautilus and the window below.
    mask: Region {
      x: root.edge === "right" ? window.width - root.edgeWidth : 0
      y: root.edge === "bottom" ? window.height - root.edgeWidth : 0
      width: root.edge === "left" || root.edge === "right" ? root.edgeWidth : window.width
      height: root.edge === "top" || root.edge === "bottom" ? root.edgeWidth : window.height
    }

    Item {
      id: edgeTarget
      width: root.edge === "left" || root.edge === "right" ? root.edgeWidth : window.width
      height: root.edge === "top" || root.edge === "bottom" ? root.edgeWidth : window.height
      x: root.edge === "right" ? window.width - width : 0
      y: root.edge === "bottom" ? window.height - height : 0

      HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
          if (hovered && !root.opened)
            revealTimer.restart()
          else
            revealTimer.stop()
        }
      }

      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
          revealTimer.stop()
          root.toggle()
        }
      }

      Rectangle {
        width: root.edge === "left" || root.edge === "right" ? Style.space(4) : root.handleLength
        height: root.edge === "top" || root.edge === "bottom" ? Style.space(4) : root.handleLength
        x: root.edge === "right" ? parent.width - width : (parent.width - width) / 2
        y: root.edge === "bottom" ? parent.height - height : (parent.height - height) / 2
        radius: Math.min(width, height) / 2
        color: root.opened ? root.accent : root.foreground
        opacity: root.opened ? 0.85 : 0.55
      }

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: root.edge === "right" ? -root.edgeWidth : 0
        anchors.rightMargin: root.edge === "left" ? -root.edgeWidth : 0
        anchors.topMargin: root.edge === "bottom" ? -root.edgeWidth : 0
        anchors.bottomMargin: root.edge === "top" ? -root.edgeWidth : 0
        color: root.handleBackground
        opacity: 0.16
        radius: root.cornerRadius
      }
    }
  }

  Component.onCompleted: root.pickScreen()
}
