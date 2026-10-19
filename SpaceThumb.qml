import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Commons

// Workspace thumbnail in the Spaces bar: wallpaper plus live miniatures of
// its windows. Click to switch; drop a dragged window here to move it.
Item {
  id: thumb

  required property var workspace
  required property var monitorView

  readonly property bool active: monitorView.activeWorkspace && monitorView.activeWorkspace.id === workspace.id
  readonly property bool dropHover: monitorView.dropTarget === workspace.id
  readonly property real k: width / Math.max(1, monitorView.width)
  readonly property int radius: Math.min(monitorView.radius, 10)

  readonly property var windows: Hyprland.toplevels.values.filter(function(t) {
    return t.workspace && t.workspace.id === thumb.workspace.id && t.wayland
      && t.lastIpcObject && t.lastIpcObject.at
  })

  scale: mouse.containsMouse || dropHover ? 1.06 : 1

  Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  RectangularShadow {
    anchors.fill: parent
    radius: thumb.radius
    blur: 18
    offset.y: 4
    color: Qt.rgba(0, 0, 0, 0.45)
  }

  Item {
    id: content
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      color: thumb.monitorView.background
    }

    Image {
      anchors.fill: parent
      source: thumb.monitorView.controller.backgroundPath ? "file://" + thumb.monitorView.controller.backgroundPath : ""
      sourceSize.width: 320
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }

    Repeater {
      model: thumb.windows

      ScreencopyView {
        required property var modelData
        readonly property var o: modelData.lastIpcObject

        x: (o.at[0] - (thumb.monitorView.monitor ? thumb.monitorView.monitor.x : 0)) * thumb.k
        y: (o.at[1] - (thumb.monitorView.monitor ? thumb.monitorView.monitor.y : 0)) * thumb.k
        width: o.size[0] * thumb.k
        height: o.size[1] * thumb.k
        captureSource: thumb.monitorView.controller.mapped ? modelData.wayland : null
        live: true
      }
    }
  }

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: thumb.radius
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: parent
    source: content
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -3
    radius: thumb.radius > 0 ? thumb.radius + 3 : 0
    color: "transparent"
    border.width: thumb.active || thumb.dropHover ? 3 : 1
    border.color: thumb.active || thumb.dropHover ? thumb.monitorView.accent : Qt.rgba(1, 1, 1, 0.22)
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.bottom
    anchors.topMargin: 8
    text: thumb.workspace.name
    color: "white"
    opacity: thumb.active ? 1 : 0.75
    font.family: thumb.monitorView.fontFamily
    font.pixelSize: Style.font.body
    font.weight: thumb.active ? Font.DemiBold : Font.Normal
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: thumb.monitorView.switchTo(thumb.workspace.id)
  }
}
