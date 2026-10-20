import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// macOS-style Mission Control overlay. One MonitorView per screen spreads out
// the windows of that monitor's active workspace; a Spaces bar on top shows
// every workspace on the monitor.
//
//   omarchy-shell shell toggle io.github.joaovitor2763.mission-control '{}'
Item {
  id: root

  property var shell: null
  property var manifest: null

  // Host contract: toggle() reads `opened`. It flips to false as soon as a
  // close starts so a second toggle during the close animation reopens.
  property bool opened: false
  // Keeps the windows mapped until the close animation has finished.
  property bool mapped: false
  // 0 = previews sit on top of the real windows, 1 = spread out.
  property real progress: 0

  readonly property string pluginId: (manifest && manifest.id) || "io.github.joaovitor2763.mission-control"
  readonly property string backgroundLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  property string backgroundPath: ""

  function open(payloadJson) {
    if (root.opened) return
    root.opened = true
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
    backgroundProc.running = true
    // Give the refresh a moment so previews start from accurate geometry.
    openDelay.restart()
  }

  function close() {
    openDelay.stop()
    if (!root.mapped) {
      root.opened = false
      return
    }
    root.opened = false
    openAnim.stop()
    closeAnim.restart()
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    else
      root.close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Omarchy's Hyprland config is Lua, so dispatchers are Lua expressions.
  function dispatch(expression) {
    Hyprland.dispatch("hl.dsp." + expression)
  }

  function focusWindow(address) {
    dispatch("focus({ window = 'address:0x" + address + "' })")
  }

  function closeWindow(address) {
    dispatch("window.close({ window = 'address:0x" + address + "' })")
  }

  // Hyprland refocuses the previous window when the overlay gives up
  // keyboard focus, which undoes a workspace switch made while open. So
  // close first and switch once the focus has been released.
  property string pendingWorkspace: ""

  function focusWorkspace(workspace) {
    root.pendingWorkspace = String(workspace)
    root.dismiss()
    workspaceSwitch.restart()
  }

  function moveWindow(address, workspace) {
    dispatch("window.move({ workspace = '" + workspace + "', follow = false, window = 'address:0x" + address + "' })")
  }

  Timer {
    id: workspaceSwitch
    interval: 50
    onTriggered: {
      root.dispatch("focus({ workspace = '" + root.pendingWorkspace + "' })")
      root.pendingWorkspace = ""
    }
  }

  Timer {
    id: openDelay
    interval: 45
    onTriggered: {
      if (!root.opened) return
      closeAnim.stop()
      root.progress = 0
      root.mapped = true
      openAnim.restart()
    }
  }

  NumberAnimation {
    id: openAnim
    target: root
    property: "progress"
    to: 1
    duration: 420
    easing.type: Easing.OutQuint
  }

  SequentialAnimation {
    id: closeAnim
    NumberAnimation {
      target: root
      property: "progress"
      to: 0
      duration: 300
      easing.type: Easing.OutCubic
    }
    ScriptAction {
      script: root.mapped = false
    }
  }

  Process {
    id: backgroundProc
    command: ["readlink", "-f", root.backgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backgroundPath = String(text || "").trim()
    }
  }

  Variants {
    model: Quickshell.screens

    MonitorView {
      required property var modelData
      screen: modelData
      controller: root
    }
  }
}
