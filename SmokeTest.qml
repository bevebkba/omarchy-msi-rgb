import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: suite
  property int step: 0
  Plugin.CommandRunner { id: runner }
  function check(ok, message) {
    if (ok) return true
    console.error("GE66_SMOKE_FAIL: " + message)
    timer.stop()
    Qt.quit()
    return false
  }
  Timer {
    id: timer
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      if (runner.busy || !runner.ready) return
      if (suite.step === 0) {
        if (!suite.check(runner.keyboardPresets.length === 10 && runner.auroraPresets.length === 12,
                         "catalog must expose all presets")) return
        if (!suite.check(runner.lastApplied === "", "loading must not apply hardware presets")) return
        suite.step = 1
        runner.run("version")
      } else if (suite.step === 1) {
        if (!suite.check(!runner.failed && runner.output.indexOf("MSI GE66 Raider RGB 0.1") >= 0,
                         "real version output must reach the GUI")) return
        suite.step = 2
        runner.run("apply", "not-a-preset", "")
      } else {
        if (!suite.check(runner.failed && runner.output.indexOf("Invalid") >= 0,
                         "invalid preset error must reach GUI")) return
        if (!suite.check(runner.lastApplied === "", "failed writes must not change last successful status")) return
        console.info("GE66_SMOKE_PASS: catalog, real version, error reporting, status integrity")
        timer.stop()
        Qt.quit()
      }
    }
  }
  Timer {
    interval: 5000
    running: true
    onTriggered: suite.check(false, "GUI runner timed out")
  }
}
