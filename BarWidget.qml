import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.bevebkba.msi-rgb"
  readonly property bool opened: panel.opened
  readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing

  function open() { panel.open() }
  function close() { panel.close() }
  function toggle() { panel.toggle() }
  function closeForPopoutSwitch() { panel.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf11c"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "MSI RGB · Keyboard and light bar"
    onPressed: function(code) { root.toggle() }
  }

  RgbPanel {
    id: panel
    bar: root.bar
    anchorItem: button
    hostWidget: root
  }
}
