import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// One live window preview. It interpolates between the window's real
// geometry (progress 0) and its spread-out slot (progress 1), so opening and
// closing look like the windows themselves move.
Item {
  id: tile

  required property var toplevel
  required property var monitorView
  property var rect: null
  property bool selected: false
  property bool dimmed: false
  readonly property bool hovered: mouse.containsMouse

  readonly property var ipc: toplevel ? toplevel.lastIpcObject : null
  readonly property real p: monitorView.p
  readonly property bool settled: p > 0.9 && !dragging
  readonly property bool highlighted: (selected || hovered) && settled

  // Real on-screen geometry, relative to this monitor
  readonly property real realX: (ipc && ipc.at ? ipc.at[0] : 0) - (monitorView.monitor ? monitorView.monitor.x : 0)
  readonly property real realY: (ipc && ipc.at ? ipc.at[1] : 0) - (monitorView.monitor ? monitorView.monitor.y : 0)
  readonly property real realWidth: ipc && ipc.size ? ipc.size[0] : 100
  readonly property real realHeight: ipc && ipc.size ? ipc.size[1] : 100

  // Spread-out geometry, animated when the layout changes underneath
  property real gridX: rect ? rect.x : realX
  property real gridY: rect ? rect.y : realY
  property real gridWidth: rect ? rect.w : realWidth
  property real gridHeight: rect ? rect.h : realHeight

  Behavior on gridX { enabled: tile.p === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on gridY { enabled: tile.p === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on gridWidth { enabled: tile.p === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on gridHeight { enabled: tile.p === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

  property real dragX: 0
  property real dragY: 0
  property bool dragging: false

  Behavior on dragX { enabled: !tile.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
  Behavior on dragY { enabled: !tile.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  readonly property real radius: monitorView.radius * p

  x: realX + (gridX - realX) * p + dragX
  y: realY + (gridY - realY) * p + dragY
  width: realWidth + (gridWidth - realWidth) * p
  height: realHeight + (gridHeight - realHeight) * p
  z: dragging ? 100 : (selected ? 2 : 1)
  opacity: dimmed ? 0.25 : 1
  scale: dragging ? 0.55 : (highlighted ? 1.03 : 1.0)

  Behavior on opacity { NumberAnimation { duration: 150 } }
  Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  RectangularShadow {
    anchors.fill: parent
    radius: tile.radius
    blur: 30
    offset.y: 8
    color: Qt.rgba(0, 0, 0, 0.45 * tile.p)
  }

  Rectangle {
    anchors.fill: parent
    radius: tile.radius
    color: tile.monitorView.background
  }

  ScreencopyView {
    id: preview
    anchors.fill: parent
    captureSource: tile.monitorView.controller.mapped && tile.toplevel ? tile.toplevel.wayland : null
    live: true
    visible: false
  }

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: tile.radius
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: parent
    source: preview
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -4
    radius: tile.radius > 0 ? tile.radius + 4 : 0
    color: "transparent"
    border.width: 3
    border.color: tile.monitorView.accent
    opacity: tile.highlighted ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  // App icon badge, bottom center
  Image {
    id: icon

    readonly property var entry: {
      DesktopEntries.applications.values // re-run when the entry index updates
      return DesktopEntries.heuristicLookup((tile.ipc && tile.ipc["class"]) || "")
    }
    readonly property string path: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""

    visible: path.length > 0 && !tile.dragging
    source: path
    width: Math.min(56, Math.max(28, tile.height * 0.16))
    height: width
    sourceSize.width: 128
    sourceSize.height: 128
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.bottom
    opacity: tile.p
  }

  // Title under the tile, shown for the hovered/selected window
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.bottom
    anchors.topMargin: icon.visible ? icon.height / 2 + 8 : 10
    width: Math.min(title.implicitWidth + 24, Math.max(tile.width, 220))
    height: 26
    radius: Math.min(tile.monitorView.radius, height / 2)
    color: Qt.rgba(0, 0, 0, 0.6)
    opacity: tile.highlighted ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Text {
      id: title
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - 24)
      text: tile.toplevel ? tile.toplevel.title : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: "white"
      font.family: tile.monitorView.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouse

    property point start
    property bool moved: false

    anchors.fill: parent
    hoverEnabled: true
    enabled: tile.p > 0.5
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    onPressed: function(m) {
      start = mapToItem(tile.monitorView.contentItem, m.x, m.y)
      moved = false
    }

    onPositionChanged: function(m) {
      if (!pressed || m.buttons !== Qt.LeftButton) return
      var g = mapToItem(tile.monitorView.contentItem, m.x, m.y)
      var dx = g.x - start.x, dy = g.y - start.y
      if (!moved && Math.sqrt(dx * dx + dy * dy) > 8) {
        moved = true
        tile.dragging = true
      }
      if (tile.dragging) {
        tile.dragX = dx
        tile.dragY = dy
        tile.monitorView.dropTarget = tile.monitorView.dropTargetAt(tile.monitorView.contentItem, g.x, g.y)
      }
    }

    onReleased: function(m) {
      if (tile.dragging) {
        var target = tile.monitorView.dropTarget
        tile.monitorView.dropTarget = null
        tile.dragging = false
        if (target !== null && target !== tile.toplevel.workspace.id) {
          tile.monitorView.moveWindow(tile.toplevel, target)
          return
        }
        tile.dragX = 0
        tile.dragY = 0
        return
      }
      if (m.button === Qt.MiddleButton) tile.monitorView.closeWindow(tile.toplevel)
      else tile.monitorView.activate(tile.toplevel)
    }
  }

  // Close button, top-left on hover
  Rectangle {
    width: 24
    height: 24
    radius: 12
    x: -8
    y: -8
    color: closeMouse.containsMouse ? Commons.Color.urgent : Qt.rgba(0.15, 0.15, 0.15, 0.9)
    border.color: Qt.rgba(1, 1, 1, 0.25)
    visible: (tile.hovered || closeMouse.containsMouse) && tile.settled

    Text {
      anchors.centerIn: parent
      text: "✕"
      color: "white"
      font.pixelSize: 11
    }

    MouseArea {
      id: closeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.monitorView.closeWindow(tile.toplevel)
    }
  }
}
