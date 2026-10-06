import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "shaun.gw2-trading-post"

  Component.onCompleted: {
      }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
            root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: {
            if (status === Loader.Error) {
        console.log("GW2: Panel load error:", errorString())
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (panelLoader.item && panelLoader.item.label) ? panelLoader.item.label : "GW2"
    slotSize: Style.bar.statusSlot
    tooltipText: (panelLoader.item && panelLoader.item.walletDisplay) ? "Wallet: " + panelLoader.item.walletDisplay : "GW2 Wallet"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) {
        root.bar.run("omarchy-notification-send \"GW2 Wallet\" \"Wallet: " + (panelLoader.item ? panelLoader.item.walletDisplay : "—") + "\"")
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }
  }
}