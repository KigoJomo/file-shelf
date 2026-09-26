import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kigojomo.file-shelf"

  // Reading the service map itself makes this binding reactive when Omarchy
  // finishes creating a keep-loaded service after the bar widget.
  readonly property var shellServices: bar && bar.shell ? bar.shell._services : null
  readonly property var shelfService: shellServices ? shellServices[moduleName] : null
  readonly property bool opened: shelfService ? shelfService.opened === true : false
  readonly property var positions: ["left", "bottom", "right"]
  readonly property string position: shelfService ? String(shelfService.edge || "right") : "right"
  readonly property int shelfSize: shelfService ? shelfService.shelfSize : 44
  property bool positionMenuOpen: false

  function runCommand(command) {
    if (root.bar) root.bar.run("omarchy-shell file-shelf " + command)
  }

  function open() {
    if (shelfService && typeof shelfService.open === "function") shelfService.open()
    else root.runCommand("show")
  }

  function toggle() {
    if (shelfService && typeof shelfService.toggle === "function") shelfService.toggle()
    else root.runCommand("toggle")
  }

  function close() {
    root.positionMenuOpen = false
    if (shelfService && typeof shelfService.close === "function") shelfService.close()
    else root.runCommand("hide")
  }

  function closePositionMenu() {
    root.positionMenuOpen = false
  }

  function setPosition(next) {
    if (shelfService && typeof shelfService.setEdge === "function") shelfService.setEdge(next)
    else root.runCommand("position " + next)
  }

  function setSize(next) {
    if (shelfService && typeof shelfService.setSize === "function") shelfService.setSize(next)
    else root.runCommand("size " + next)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.opened
    tooltipText: (shelfService && String(shelfService.statusText).indexOf("error:") === 0
      ? shelfService.statusText + " · " : "") + "File Shelf settings · right-click to " + (root.opened ? "retract" : "open") + " · Super+E toggles"
    activeFocusOnTab: true

    Keys.onReturnPressed: root.positionMenuOpen = !root.positionMenuOpen
    Keys.onEnterPressed: root.positionMenuOpen = !root.positionMenuOpen
    Keys.onSpacePressed: root.positionMenuOpen = !root.positionMenuOpen
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Menu
          || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
        root.positionMenuOpen = true
        event.accepted = true
      }
    }

    onPressed: function(button) {
      if (button === Qt.RightButton) root.toggle()
      else if (button === Qt.LeftButton) root.positionMenuOpen = !root.positionMenuOpen
    }
  }

  PopupCard {
    id: positionMenu
    anchorItem: button
    bar: root.bar
    owner: positionMenuOwner
    open: root.positionMenuOpen
    contentWidth: positionMenu.fittedContentWidth(Style.space(310))
    contentHeight: positionMenu.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "File Shelf"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        text: root.opened ? "Open on " + root.position + " · " + root.shelfSize + "%" : "Ready on " + root.position + " · " + root.shelfSize + "%"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
        opacity: 0.75
      }

      Button {
        width: parent.width
        text: root.opened ? "Retract shelf" : "Open shelf"
        focusable: true
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onClicked: { root.toggle(); root.closePositionMenu() }
      }

      Text {
        text: "Screen edge"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          id: positionButtons
          model: root.positions

          Button {
            required property string modelData
            width: (parent.width - Style.space(12)) / 3
            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
            selected: root.position === modelData
            focusable: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onClicked: root.setPosition(modelData)
          }
        }
      }

      Text {
        text: "Shelf size · " + root.shelfSize + "%"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
          model: [30, 44, 60, 75]
          Button {
            required property int modelData
            width: (parent.width - Style.space(18)) / 4
            text: modelData + "%"
            selected: root.shelfSize === modelData
            focusable: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onClicked: root.setSize(modelData)
          }
        }
      }

      Text {
        text: "Drag the screen edge for a custom size · Super+E toggles"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
        opacity: 0.75
      }
    }

    onOpenChanged: if (open) Qt.callLater(function() {
      if (positionButtons.count > 0) positionButtons.itemAt(0).forceActiveFocus()
    })
  }

  QtObject {
    id: positionMenuOwner

    function close() {
      root.closePositionMenu()
    }
  }
}
