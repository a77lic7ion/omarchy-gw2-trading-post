import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "shaun.gw2-trading-post"
  ipcTarget: "shaun.gw2-trading-post"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string envToken: Quickshell.env("GW2_API_TOKEN")
  property string fileToken: ""
  property string apiToken: setting("apiToken", "") || root.envToken || root.fileToken
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  FileView {
    id: tokenFile
    path: root.home + "/.config/omarchy/gw2-api-token"
    onLoaded: root.fileToken = text().trim()
  }

  onApiTokenChanged: {
    if (hasToken && !loading) refresh()
  }

  Component.onCompleted: {
    console.log("GW2 Panel Component.onCompleted")
    tokenFile.reload()
  }

  property int walletGold: 0
  property bool loading: false
  property string errorMessage: ""
  property string lastUpdated: ""
  property int fetchStamp: 0

  // Wizard's Vault dailies
  property var dailyObjectives: []
  property int metaProgressCurrent: 0
  property int metaProgressComplete: 10
  property string dailiesError: ""
  property string acclaimIconUrl: ""
  property bool dailiesLoaded: false

  readonly property string walletDisplay: Model.formatGold(walletGold)
  readonly property string walletCompact: Model.formatGoldCompact(walletGold)
  readonly property bool hasToken: apiToken !== "" && apiToken.length > 10

  readonly property string label: hasToken ? walletCompact : "GW2"

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    console.log("GW2 refresh() hasToken=" + hasToken + " stamp=" + fetchStamp + " walletRunning=" + walletProc.running + " dailiesRunning=" + dailiesProc.running)
    if (!hasToken) return
    loading = true
    errorMessage = ""
    dailiesError = ""
    // New stamp busts any intermediary cache so every refresh hits the API live
    fetchStamp = Date.now()
    if (!walletProc.running) walletProc.running = true
    if (!dailiesProc.running) dailiesProc.running = true
  }

  function msUntilNextUtcReset() {
    var now = new Date()
    var next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 0)
    return Math.max(1000, next - now.getTime())
  }

  Process {
    id: walletProc
    command: ["curl", "-fsS", "--max-time", "10", "-H", "Cache-Control: no-cache", "https://api.guildwars2.com/v2/account/wallet?access_token=" + root.apiToken + "&_=" + root.fetchStamp]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        walletGold = Model.parseWallet(text)
        lastUpdated = Qt.formatTime(new Date(), "HH:mm:ss")
        loading = false
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        errorMessage = "Wallet fetch failed (exit " + exitCode + ")"
        loading = false
      }
    }
  }

  // Wizard's Vault dailies
  Process {
    id: dailiesProc
    command: ["curl", "-fsS", "--max-time", "10", "-H", "Cache-Control: no-cache", "-H", "Authorization: Bearer " + root.apiToken, "https://api.guildwars2.com/v2/account/wizardsvault/daily?_=" + root.fetchStamp]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseWizardVaultDailies(text)
        dailyObjectives = parsed.objectives
        metaProgressCurrent = parsed.metaProgressCurrent
        metaProgressComplete = parsed.metaProgressComplete
        dailiesLoaded = true
        loading = false
        console.log("GW2 dailies: " + parsed.objectives.length + " PvE objectives, meta " + parsed.metaProgressCurrent + "/" + parsed.metaProgressComplete)
        // Fetch acclaim icon if not cached
        if (root.acclaimIconUrl === "") {
          acclaimIconProc.running = true
        }
      }
    }
    onExited: function(exitCode) {
      console.log("GW2 dailies curl exit=" + exitCode)
      if (exitCode !== 0) {
        dailiesError = "Dailies unavailable"
        dailiesLoaded = true
        loading = false
      }
    }
  }

  // Fetch Astral Acclaim icon (currency 63)
  Process {
    id: acclaimIconProc
    command: ["curl", "-fsS", "--max-time", "10", "https://api.guildwars2.com/v2/currencies/63"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.icon) {
            acclaimIconUrl = data.icon
          }
        } catch (e) {
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // GW2 dailies roll over at 00:00 UTC - resync right after server reset
  Timer {
    id: dailyResetTimer
    interval: root.msUntilNextUtcReset()
    running: root.hasToken
    repeat: true
    onTriggered: {
      root.refresh()
      interval = root.msUntilNextUtcReset()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: Math.min(panel.fittedContentWidth(Style.space(300)), Style.space(320))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: root.refresh()
    }

    Column {
      id: contentColumn
      width: Math.min(parent.width, Style.space(300))
      spacing: Style.space(8)

      // Compact header
      Rectangle {
        width: contentColumn.width
        height: 28
        color: "#141518"
        border.color: "#3A352A"
        border.width: 1

        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: "👑"
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "BLACK LION TRADING COMPANY"
            color: "#E6C267"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // Wallet row
      Rectangle {
        width: contentColumn.width
        height: 56
        color: "#181A20"
        border.color: "#2C2D35"
        border.width: 1

        Row {
          anchors.fill: parent
          anchors.leftMargin: 0
          anchors.rightMargin: 0
          spacing: Style.space(14)

          Text {
            text: "🪙"
            font.pixelSize: 24
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            width: parent.width - Style.space(60)

            Text {
              text: "ACCOUNT WALLET"
              color: "#9A9B9F"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.8
            }
            Text {
              textFormat: Text.PlainText
              text: root.walletDisplay
              color: "#F4C542"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
          }
        }
      }

      // Wizard's Vault Dailies section
      Column {
        id: dailiesColumn
        width: contentColumn.width
        spacing: Style.space(6)
        visible: root.dailiesLoaded || root.loading

        // Section header
        Rectangle {
          width: parent.width
          height: 24
          color: "#141518"
          border.color: "#3A352A"
          border.width: 1

          Item {
            anchors.fill: parent

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                text: "✦"
                font.pixelSize: 10
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "WIZARD'S VAULT DAILIES"
                color: "#E6C267"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              text: root.metaProgressCurrent + " / " + root.metaProgressComplete
              color: "#9A9B9F"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption - 1
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Error state
        Text {
          visible: root.dailiesLoaded && root.dailiesError !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.dailiesError
          color: "#FF4A4A"
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
          anchors.horizontalCenter: parent.horizontalCenter
        }

        // Dailies list
        Column {
          visible: root.dailiesLoaded && root.dailiesError === ""
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.dailyObjectives

            Rectangle {
              width: parent.width
              height: 36
              color: "#181A20"
              border.color: "#2C2D35"
              border.width: 1

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                // Acclaim icon
                Image {
                  width: 20
                  height: 20
                  source: root.acclaimIconUrl
                  fillMode: Image.PreserveAspectFit
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.acclaimIconUrl !== ""
                }

                // Title
                Text {
                  text: modelData.title
                  color: modelData.done ? "#9A9B9F" : "#E6C267"
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.strikeout: modelData.done
                  opacity: modelData.done ? 0.4 : 1.0
                  elide: Text.ElideRight
                  width: parent.width - 40
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }

      // Status row
      Item {
        width: contentColumn.width
        height: Math.max(statusText.implicitHeight, refreshBtn.implicitHeight)

        Row {
          anchors.fill: parent
          spacing: Style.space(10)

          Text {
            id: statusText
            visible: root.errorMessage !== "" || root.loading || root.lastUpdated !== ""
            textFormat: Text.PlainText
            text: root.errorMessage !== "" ? root.errorMessage : (root.loading ? "Synchronizing..." : "Updated: " + root.lastUpdated)
            color: root.errorMessage !== "" ? "#FF4A4A" : "#8C8E96"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: root.loading
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            id: refreshBtn
            text: root.loading ? "Syncing..." : "Refresh"
            enabled: !root.loading && root.hasToken
            fontSize: Style.font.bodySmall
            foreground: "#E6C267"
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.refresh()
          }
        }
      }

      Text {
        visible: !root.hasToken
        width: contentColumn.width
        textFormat: Text.PlainText
        text: "⚠️ No API token. Right-click bar icon → Settings to add GW2 token."
        color: "#D97736"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WrapAnywhere
      }
    }
  }
}