import QtQuick
import Quickshell
import Quickshell.Hyprland
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

  property string edge: "right"
  property int shelfSize: 44
  property string screenName: ""
  property var targetScreen: null
  property bool opened: false
  property bool stateLoaded: false
  property string statusText: ""
  property string queuedOperation: ""
  property int focusGeneration: 0
  property int focusMisses: 0
  property bool focusCheckReady: false
  readonly property int revealDelay: 220
  readonly property int focusCheckDelay: 180
  readonly property int focusWarmupDelay: 700

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
    return ["left", "right", "bottom"].indexOf(next) !== -1 ? next : ""
  }

  function normalizeSize(value) {
    var number = Number(value)
    return isFinite(number) ? Math.max(25, Math.min(75, Math.round(number))) : 44
  }

  function setSize(value) {
    var next = root.normalizeSize(value)
    if (next !== root.shelfSize) {
      root.shelfSize = next
      root.saveState()
      if (root.opened) root.invoke("show")
    }
    return root.shelfSize
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
      Qt.callLater(function() {
        if (root.opened && root.targetScreen)
          root.invoke("show")
      })
  }

  function restoreState(raw) {
    try {
      var state = JSON.parse(String(raw || "{}"))
      var restoredEdge = root.normalizeEdge(state.edge)
      var restoredMonitor = root.normalizeMonitor(state.monitor)
      if (restoredEdge)
        root.edge = restoredEdge
      root.shelfSize = root.normalizeSize(state.size)
      if (restoredMonitor)
        root.screenName = restoredMonitor
    } catch (error) {
      // A damaged preference file should never stop the shell plugin loading.
    }
    root.stateLoaded = true
    root.pickScreen()
    Qt.callLater(function() {
      // Preserve a click received while preferences/screens were loading.
      root.invoke(root.queuedOperation || (root.opened ? "show" : "status"))
    })
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
      size: root.shelfSize,
      monitor: root.screenName
    }, null, 2) + "\n")
  }

  property bool stateWritePending: false

  function invoke(operation) {
    if (!root.stateLoaded || (operation === "show" && !root.targetScreen)) {
      root.queuedOperation = operation
      return
    }

    if (controllerProc.running) {
      root.queuedOperation = operation
      return
    }

    root.queuedOperation = ""
    if (operation !== "status") root.focusGeneration += 1
    controllerProc.operation = operation
    controllerProc.command = [root.helperPath, operation]
    if (operation === "show")
      controllerProc.command = controllerProc.command.concat([
        root.edge,
        root.targetScreen ? root.targetScreen.name : root.screenName,
        String(root.shelfSize)
      ])
    controllerProc.running = true
  }

  function open() {
    root.focusGeneration += 1
    root.opened = true
    root.focusMisses = 0
    root.focusCheckReady = false
    root.invoke("show")
  }

  function close() {
    // Retracting parks the existing Nautilus window in a special workspace;
    // it does not close the window or discard its current folder.
    root.focusGeneration += 1
    root.opened = false
    root.focusMisses = 0
    root.focusCheckReady = false
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
    return root.screenName
  }

  function retractIfUnfocused() {
    if (!root.opened || !root.focusCheckReady || controllerProc.running || focusProc.running)
      return

    // Ask Hyprland directly. Quickshell's active-toplevel object can briefly
    // lag behind the compositor while a window changes special workspaces.
    focusProc.generation = root.focusGeneration
    focusProc.running = true
  }

  function handleFocusStatus(result) {
    if (!root.opened)
      return
    if (result === "closed") {
      root.statusText = "closed"
      root.opened = false
      root.focusMisses = 0
      root.focusCheckReady = false
      return
    }
    if (result === "focused") {
      root.focusMisses = 0
      // The compositor focus signal schedules the next check. Do not spawn
      // shell processes continuously while someone browses a folder.
      return
    }
    if (result !== "unfocused") {
      focusCheckTimer.restart()
      return
    }
    root.focusMisses += 1
    if (root.focusMisses >= 2)
      root.close()
    else
      focusCheckTimer.restart()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreState(text())
    onLoadFailed: root.restoreState("{}")
  }

  Process {
    id: shortcutProc
    command: ["hyprctl", "eval", "hl.unbind(\"SUPER + E\"); hl.bind(\"SUPER + E\", hl.dsp.exec_cmd(\"omarchy-shell file-shelf toggle\"), { description = \"File Shelf\" })"]
    onExited: function(exitCode) {
      if (exitCode !== 0) root.statusText = "error: could not register Super+E"
    }
  }

  Process {
    id: stateDirectoryProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode === 0) root.writeState()
      else root.statusText = "error: could not save preferences"
    }
  }

  Process {
    id: controllerProc
    property string operation: ""
    property string result: ""
    property string errorText: ""
    onStarted: { result = ""; errorText = "" }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: controllerProc.result = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: controllerProc.errorText = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var operation = controllerProc.operation
      var next = root.queuedOperation
      root.queuedOperation = ""
      if (exitCode !== 0) {
        root.statusText = "error: " + (controllerProc.errorText || "could not " + operation + " File Shelf")
        console.warn("File Shelf:", root.statusText)
        // A failed hide may have left the window visible. Reconcile it.
        if (next) root.invoke(next)
        else if (operation !== "status") root.invoke("status")
        return
      }
      if (next) {
        root.invoke(next)
        return
      }
      // Startup and failure recovery must restore both status and bar state.
      root.opened = controllerProc.result === "open"
      if (root.statusText.indexOf("error:") !== 0 || operation !== "status")
        root.statusText = controllerProc.result
      root.focusMisses = 0
      root.focusCheckReady = false
      if (root.opened) focusWarmupTimer.restart()
    }
  }

  Process {
    id: focusProc
    property int generation: 0
    command: [root.helperPath, "focused"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (focusProc.generation === root.focusGeneration)
          root.handleFocusStatus(String(text || "").trim())
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.opened && root.focusCheckReady)
        focusCheckTimer.restart()
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

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      if (root.opened)
        focusCheckTimer.restart()
    }
  }

  Timer {
    id: focusCheckTimer
    interval: root.focusCheckDelay
    onTriggered: root.retractIfUnfocused()
  }

  Timer {
    id: focusWarmupTimer
    interval: root.focusWarmupDelay
    onTriggered: {
      if (!root.opened)
        return
      root.focusCheckReady = true
      focusCheckTimer.restart()
    }
  }

  IpcHandler {
    target: "file-shelf"

    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function position(value: string): string { return root.setEdge(value) }
    function monitor(value: string): string { return root.setMonitor(value) }
    function size(value: string): string { return String(root.setSize(value)) }
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

    // The surface occupies the monitor so the edge target can follow the
    // supported orientations, but only the narrow region below accepts input.
    // Everything else remains available to Nautilus and the window below.
    mask: Region {
      x: root.edge === "right" ? window.width - root.edgeWidth : 0
      y: root.edge === "bottom" ? window.height - root.edgeWidth : 0
      width: root.edge === "left" || root.edge === "right" ? root.edgeWidth : window.width
      height: root.edge === "bottom" ? root.edgeWidth : window.height
    }

    Item {
      id: edgeTarget
      width: root.edge === "left" || root.edge === "right" ? root.edgeWidth : window.width
      height: root.edge === "bottom" ? root.edgeWidth : window.height
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

      DragHandler {
        id: sizeDrag
        acceptedButtons: Qt.LeftButton
        property real startingSize: 44
        onActiveChanged: {
          if (active) startingSize = root.shelfSize
          else if (translation.x !== 0 || translation.y !== 0) {
            var span = root.edge === "bottom" ? window.height : window.width
            var delta = root.edge === "right" ? -translation.x : root.edge === "left" ? translation.x : -translation.y
            root.setSize(startingSize + delta * 100 / span)
          }
        }
      }

      Rectangle {
        width: root.edge === "left" || root.edge === "right" ? Style.space(4) : root.handleLength
        height: root.edge === "bottom" ? Style.space(4) : root.handleLength
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
        anchors.bottomMargin: 0
        color: root.handleBackground
        opacity: 0.16
        radius: root.cornerRadius
      }
    }
  }

  Component.onCompleted: {
    root.pickScreen()
    shortcutProc.running = true
  }
}
