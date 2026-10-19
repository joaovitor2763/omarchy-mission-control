import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

PanelWindow {
  id: view

  required property var controller
  readonly property real p: controller.progress

  readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
  readonly property var activeWorkspace: monitor ? monitor.activeWorkspace : null

  readonly property color accent: Commons.Color.accent
  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property string fontFamily: Style.font.family
  readonly property int radius: Style.cornerRadius

  // Spaces bar geometry
  readonly property real thumbHeight: Math.round(height * 0.095)
  readonly property real thumbWidth: Math.round(thumbHeight * width / Math.max(1, height))
  readonly property real barTop: 22
  readonly property real barBottom: barTop + thumbHeight + 34

  // Area the windows are spread over; the bottom margin leaves room for the
  // icon badge and title under the last row.
  readonly property real areaX: 64
  readonly property real areaY: barBottom + 28
  readonly property real areaWidth: width - 2 * areaX
  readonly property real areaHeight: height - areaY - 110

  property string query: ""
  property int selectedIndex: -1
  property var dropTarget: null

  readonly property var workspaces: {
    var name = monitor ? monitor.name : ""
    return Hyprland.workspaces.values
      .filter(function(w) { return w.id > 0 && w.monitor && w.monitor.name === name })
      .sort(function(a, b) { return a.id - b.id })
  }

  readonly property var windows: {
    var wsId = activeWorkspace ? activeWorkspace.id : -1
    var list = Hyprland.toplevels.values.filter(function(t) {
      var o = t.lastIpcObject
      return t.workspace && t.workspace.id === wsId && t.wayland && o && o.at && o.size && !o.hidden
    })
    // Reading order: top-to-bottom bands, then left-to-right.
    return list.sort(function(a, b) {
      var A = a.lastIpcObject, B = b.lastIpcObject
      var band = Math.round(A.at[1] / 300) - Math.round(B.at[1] / 300)
      return band !== 0 ? band : A.at[0] - B.at[0]
    })
  }

  readonly property var layout: computeLayout(windows, areaWidth, areaHeight)

  // One shared scale keeps windows in proportion to each other, like macOS:
  // binary-search the largest scale at which the windows, packed greedily
  // into centered rows, still fit the area.
  function computeLayout(wins, W, H) {
    var n = wins.length
    if (n === 0 || W <= 0 || H <= 0) return []
    var gap = 40
    var sizes = wins.map(function(t) {
      return { w: Math.max(1, t.lastIpcObject.size[0]), h: Math.max(1, t.lastIpcObject.size[1]) }
    })

    function pack(k) {
      var rows = [], row = [], rowW = 0
      for (var i = 0; i < n; i++) {
        var w = sizes[i].w * k
        if (row.length > 0 && rowW + gap + w > W) {
          rows.push(row)
          row = []
          rowW = 0
        }
        rowW += (row.length > 0 ? gap : 0) + w
        row.push(i)
      }
      rows.push(row)
      var height = gap * (rows.length - 1)
      rows.forEach(function(r) {
        height += Math.max.apply(null, r.map(function(i) { return sizes[i].h * k }))
      })
      var fits = height <= H && sizes.every(function(s) { return s.w * k <= W })
      return { rows: rows, height: height, fits: fits }
    }

    var lo = 0.02, hi = 0.78
    if (!pack(hi).fits) {
      for (var step = 0; step < 24; step++) {
        var mid = (lo + hi) / 2
        if (pack(mid).fits) lo = mid
        else hi = mid
      }
      hi = lo
    }
    var k = hi
    var packed = pack(k)

    var rects = new Array(n)
    var y = areaY + (H - packed.height) / 2
    packed.rows.forEach(function(row, ri) {
      var rowH = Math.max.apply(null, row.map(function(i) { return sizes[i].h * k }))
      var rowW = row.reduce(function(a, i) { return a + sizes[i].w * k }, 0) + gap * (row.length - 1)
      var x = areaX + (W - rowW) / 2
      row.forEach(function(i) {
        var w = sizes[i].w * k, h = sizes[i].h * k
        rects[i] = { x: x, y: y + (rowH - h) / 2, w: w, h: h, row: ri }
        x += w + gap
      })
      y += rowH + gap
    })
    return rects
  }

  function matches(t) {
    if (query.length === 0) return true
    var q = query.toLowerCase()
    var cls = (t.lastIpcObject && t.lastIpcObject["class"]) || ""
    return (t.title || "").toLowerCase().indexOf(q) !== -1 || cls.toLowerCase().indexOf(q) !== -1
  }

  function activate(t) {
    controller.focusWindow(t.address)
    controller.dismiss()
  }

  function closeWindow(t) {
    controller.closeWindow(t.address)
    refreshSoon.restart()
  }

  function switchTo(workspace) {
    controller.focusWorkspace(workspace)
    controller.dismiss()
  }

  function moveWindow(t, target) {
    controller.moveWindow(t.address, target === "new" ? "emptym" : String(target))
    refreshSoon.restart()
  }

  // Workspace id, "new", or null for a point in `item` coordinates.
  function dropTargetAt(item, x, y) {
    for (var i = 0; i < spacesRepeater.count; i++) {
      var thumb = spacesRepeater.itemAt(i)
      if (thumb && thumb.contains(thumb.mapFromItem(item, x, y))) return thumb.workspace.id
    }
    return addSpace.contains(addSpace.mapFromItem(item, x, y)) ? "new" : null
  }

  function moveSelection(dx, dy) {
    var n = windows.length
    if (n === 0) return
    if (selectedIndex < 0 || selectedIndex >= n) {
      selectedIndex = 0
      return
    }
    if (dx !== 0) {
      selectedIndex = (selectedIndex + dx + n) % n
      return
    }
    // Nearest tile horizontally in the row above/below.
    var cur = layout[selectedIndex]
    var cx = cur.x + cur.w / 2
    var bestIndex = -1, bestDistance = Infinity
    layout.forEach(function(r, i) {
      if (r.row !== cur.row + dy) return
      var d = Math.abs(r.x + r.w / 2 - cx)
      if (d < bestDistance) {
        bestDistance = d
        bestIndex = i
      }
    })
    if (bestIndex >= 0) selectedIndex = bestIndex
  }

  Timer {
    id: refreshSoon
    interval: 60
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshWorkspaces()
    }
  }

  Connections {
    target: view.controller
    function onMappedChanged() {
      if (!view.controller.mapped) return
      view.query = ""
      view.selectedIndex = Math.max(0, view.windows.indexOf(Hyprland.activeToplevel))
      if (view.monitor && view.monitor.focused) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  visible: controller.mapped
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }

  WlrLayershell.namespace: "omarchy-mission-control"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: controller.opened && monitor && monitor.focused
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // Blurred wallpaper backdrop
  Item {
    anchors.fill: parent
    opacity: view.p

    Rectangle {
      anchors.fill: parent
      color: view.background
    }

    Image {
      id: wallpaper
      anchors.fill: parent
      source: view.controller.backgroundPath ? "file://" + view.controller.backgroundPath : ""
      sourceSize.width: 960
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: wallpaper
      visible: wallpaper.status === Image.Ready
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      saturation: 0.15
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.32)
    }
  }

  // Clicking empty space closes, like macOS.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: view.controller.dismiss()
  }

  // Spaces bar
  Row {
    spacing: 18
    anchors.horizontalCenter: parent.horizontalCenter
    y: view.barTop - (1 - view.p) * (view.barBottom + 20)
    opacity: view.p

    Repeater {
      id: spacesRepeater
      model: view.workspaces

      SpaceThumb {
        required property var modelData
        workspace: modelData
        monitorView: view
        width: view.thumbWidth
        height: view.thumbHeight
      }
    }

    Rectangle {
      id: addSpace

      readonly property bool dropHover: view.dropTarget === "new"

      width: view.thumbHeight * 0.8
      height: view.thumbHeight
      radius: view.radius
      color: dropHover || addMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
      border.color: dropHover ? view.accent : Qt.rgba(1, 1, 1, 0.18)
      border.width: dropHover ? 2 : 1

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: "+"
        color: "white"
        font.family: view.fontFamily
        font.pixelSize: view.thumbHeight * 0.38
        font.weight: Font.Light
      }

      MouseArea {
        id: addMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: view.switchTo("emptym")
      }
    }
  }

  Repeater {
    model: view.windows

    WindowTile {
      required property var modelData
      required property int index
      toplevel: modelData
      monitorView: view
      rect: view.layout[index] || null
      selected: view.selectedIndex === index
      dimmed: !view.matches(modelData)
      onHoveredChanged: if (hovered) view.selectedIndex = index
    }
  }

  Text {
    visible: view.windows.length === 0
    anchors.centerIn: parent
    anchors.verticalCenterOffset: view.barBottom / 2
    opacity: view.p * 0.7
    text: "No windows on this workspace"
    color: "white"
    font.family: view.fontFamily
    font.pixelSize: Style.font.title
  }

  // Type-to-filter pill
  Rectangle {
    visible: view.query.length > 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 22
    height: 38
    width: queryText.implicitWidth + 44
    radius: Math.min(view.radius, height / 2)
    color: Qt.rgba(0, 0, 0, 0.55)
    border.color: Qt.rgba(1, 1, 1, 0.15)

    Text {
      id: queryText
      anchors.centerIn: parent
      text: "/ " + view.query
      textFormat: Text.PlainText
      color: "white"
      font.family: view.fontFamily
      font.pixelSize: Style.font.subtitle
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: view.controller.opened

    Keys.onPressed: function(event) {
      var k = event.key
      if (k === Qt.Key_Escape) {
        if (view.query.length > 0) view.query = ""
        else view.controller.dismiss()
      } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        var i = view.selectedIndex
        if (i < 0 || i >= view.windows.length || !view.matches(view.windows[i]))
          i = view.windows.findIndex(function(t) { return view.matches(t) })
        if (i >= 0) view.activate(view.windows[i])
        else view.controller.dismiss()
      } else if (k === Qt.Key_Left) {
        view.moveSelection(-1, 0)
      } else if (k === Qt.Key_Right || k === Qt.Key_Tab) {
        view.moveSelection(1, 0)
      } else if (k === Qt.Key_Backtab) {
        view.moveSelection(-1, 0)
      } else if (k === Qt.Key_Up) {
        view.moveSelection(0, -1)
      } else if (k === Qt.Key_Down) {
        view.moveSelection(0, 1)
      } else if (k === Qt.Key_Backspace) {
        view.query = view.query.slice(0, -1)
      } else if (view.query.length === 0 && k >= Qt.Key_1 && k <= Qt.Key_9) {
        view.switchTo(k - Qt.Key_0)
      } else if (event.text.length === 1 && event.text >= " "
          && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
        view.query += event.text
        var first = view.windows.findIndex(function(t) { return view.matches(t) })
        if (first >= 0) view.selectedIndex = first
      } else {
        return
      }
      event.accepted = true
    }
  }
}
