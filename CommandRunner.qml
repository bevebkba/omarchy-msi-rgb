import QtQuick
import Quickshell.Io

QtObject {
  id: root
  property var keyboardPresets: []
  property var auroraPresets: []
  property bool ready: false
  readonly property bool busy: process.running
  readonly property bool demoRunning: busy && activeAction === "demo"
  property bool failed: false
  property string message: "Loading controls…"
  property string output: ""
  property string lastApplied: ""
  property string lastCommand: ""
  property string activeAction: "catalog"
  property string pendingLabel: ""
  property bool received: false
  property bool stopping: false

  function run(action, keyboard, aurora) {
    if (busy) return
    activeAction = action
    received = false
    stopping = false
    failed = false
    output = ""
    message = action === "demo" ? "Demo running. Effects change every 3 seconds." : "Running…"
    var path = decodeURIComponent(Qt.resolvedUrl("controller.py").toString().replace(/^file:\/\//, ""))
    var args = ["/usr/bin/python3", path, action]
    if (keyboard) args = args.concat(["--keyboard", keyboard])
    if (aurora) args = args.concat(["--aurora", aurora])
    pendingLabel = action === "apply"
      ? [keyboard ? "Keyboard: " + keyboard : "", aurora ? "Light bar: " + aurora : ""].filter(function(x) { return x !== "" }).join(" · ")
      : action === "off" ? "Keyboard and light bar off" : action === "defaults" ? "Keyboard and light bar: default" : "Demo completed"
    process.command = args
    process.running = true
  }

  function stop() {
    if (!busy || stopping) return
    stopping = true
    message = "Stopping…"
    process.signal(15)
  }

  function consume(text) {
    try {
      var result = JSON.parse(text)
      received = true
      if (activeAction === "catalog" && result.ok) {
        keyboardPresets = result.keyboard
        auroraPresets = result.aurora
        ready = true
        message = "Choose a preset, then press Apply."
        return
      }
      output = result.output || ""
      lastCommand = result.command ? result.command.join(" ") : ""
      failed = !result.ok && !result.cancelled
      if (result.cancelled) message = "Demo/command stopped."
      else if (!result.ok) message = "Command failed. See the output below."
      else if (["help", "usage", "version"].indexOf(activeAction) >= 0) message = "Information loaded."
      else {
        lastApplied = pendingLabel
        message = "Command sent."
      }
    } catch (error) {
      received = true
      failed = true
      message = "Could not read the command response."
      output = text
    }
  }

  property Process process: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { if (text.trim()) root.consume(text.trim()) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { if (text.trim()) { root.output = text.trim(); root.failed = true } }
    }
    onExited: function(code) {
      Qt.callLater(function() {
        if (!root.received) {
          root.failed = true
          root.message = "Could not run command (exit " + code + ")."
        }
      })
    }
  }
  Component.onCompleted: run("catalog")
  Component.onDestruction: { if (process.running) process.signal(15) }
}
