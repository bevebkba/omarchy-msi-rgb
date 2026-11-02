pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.bevebkba.msi-rgb"
  manageIpc: false
  property Item anchorItem: null
  property var hostWidget: null
  property string keyboardPreset: "default"
  property string auroraPreset: "default"
  readonly property color foreground: root.barForeground
  readonly property color dim: Qt.alpha(foreground, 0.64)

  CommandRunner { id: runner }

  function label(preset) {
    var labels = {"default": "Default", "disable": "Off", "aqua": "Aqua", "chakra": "Chakra",
      "disco": "Disco", "dragon_shield": "Dragon Shield", "drain": "Drain", "free_way": "Free Way",
      "plain": "Plain", "rainbow_split": "Rainbow Split", "aurora": "Aurora", "blue_flash": "Blue Flash",
      "casino": "Casino", "flux": "Flux", "macaw": "Macaw", "rainbow": "Rainbow"}
    return labels[preset] || preset
  }

  KeyboardPanel {
    id: popup
    bar: root.bar
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    open: root.opened
    popoutSwitching: root.popoutSwitching
    popoutSwitchClosing: root.popoutSwitchClosing
    contentWidth: fittedContentWidth(Style.space(440))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(780))
    focusTarget: keyScope

    FocusScope {
      id: keyScope
      anchors.fill: parent
      Keys.onEscapePressed: root.close()

      Controls.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

        ColumnLayout {
          id: content
          width: scroll.availableWidth
          spacing: Style.space(12)

          PanelHero {
            Layout.fillWidth: true
            title: "MSI RGB"
            meta: "GE66 Raider · Keyboard and light bar"
            foreground: root.foreground
            iconComponent: Component {
              Text {
                text: "\uf11c"
                font.family: Style.font.family
                font.pixelSize: Style.space(32)
                color: Commons.Color.accent
              }
            }
            trailingControl: Component {
              Button { text: "×"; tooltipText: "Close"; focusable: true; onClicked: root.close() }
            }
          }

          Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.foreground, 0.12) }

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Keyboard"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Item { Layout.fillWidth: true }
            Text { text: runner.keyboardPresets.length + " presets"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Button {
              text: "Apply"
              enabled: runner.ready && !runner.busy
              focusable: true
              bordered: true
              onClicked: runner.run("apply", root.keyboardPreset, "")
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 3
            uniformCellWidths: true
            columnSpacing: Style.space(5)
            rowSpacing: Style.space(5)
            enabled: runner.ready && !runner.busy
            Repeater {
              model: runner.keyboardPresets
              Button {
                required property string modelData
                Layout.fillWidth: true
                text: root.label(modelData)
                tooltipText: "--keyboard " + modelData
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(5)
                selected: root.keyboardPreset === modelData
                bordered: true
                focusable: true
                onClicked: root.keyboardPreset = modelData
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Aurora light bar"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Item { Layout.fillWidth: true }
            Text { text: runner.auroraPresets.length + " presets"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Button {
              text: "Apply"
              enabled: runner.ready && !runner.busy
              focusable: true
              bordered: true
              onClicked: runner.run("apply", "", root.auroraPreset)
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 3
            uniformCellWidths: true
            columnSpacing: Style.space(5)
            rowSpacing: Style.space(5)
            enabled: runner.ready && !runner.busy
            Repeater {
              model: runner.auroraPresets
              Button {
                required property string modelData
                Layout.fillWidth: true
                text: root.label(modelData)
                tooltipText: "--aurora " + modelData
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(5)
                selected: root.auroraPreset === modelData
                bordered: true
                focusable: true
                onClicked: root.auroraPreset = modelData
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            enabled: runner.ready && !runner.busy
            Button {
              Layout.fillWidth: true
              text: "Apply both"
              bordered: true
              focusable: true
              onClicked: runner.run("apply", root.keyboardPreset, root.auroraPreset)
            }
            Button { text: "Default"; bordered: true; focusable: true; onClicked: runner.run("defaults") }
            Button { text: "Turn both off"; bordered: true; focusable: true; onClicked: runner.run("off") }
          }

          Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.foreground, 0.12) }

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Tools"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Item { Layout.fillWidth: true }
            Button {
              text: runner.demoRunning ? "Demo running…" : "Start demo"
              enabled: runner.ready && !runner.busy
              focusable: true
              bordered: true
              onClicked: runner.run("demo")
            }
            Button {
              text: runner.stopping ? "Stopping…" : "Stop"
              enabled: runner.busy && !runner.stopping
              focusable: true
              bordered: true
              onClicked: runner.stop()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            enabled: runner.ready && !runner.busy
            Button { Layout.fillWidth: true; text: "Help"; bordered: true; focusable: true; onClicked: runner.run("help") }
            Button { Layout.fillWidth: true; text: "Usage"; bordered: true; focusable: true; onClicked: runner.run("usage") }
            Button { Layout.fillWidth: true; text: "Version"; bordered: true; focusable: true; onClicked: runner.run("version") }
          }

          Text {
            Layout.fillWidth: true
            text: runner.message
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: runner.failed ? "#f08080" : root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            Layout.fillWidth: true
            visible: runner.lastApplied !== ""
            text: "Last sent · " + runner.lastApplied
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(135)
            visible: runner.output !== "" || runner.lastCommand !== ""
            clip: true
            Controls.TextArea {
              readOnly: true
              selectByMouse: true
              text: (runner.lastCommand ? "$ " + runner.lastCommand + "\n\n" : "") + runner.output
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.Wrap
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              background: Rectangle { color: Qt.alpha(root.foreground, 0.06); radius: Style.cornerRadius }
            }
          }
        }
      }
    }
  }
}
