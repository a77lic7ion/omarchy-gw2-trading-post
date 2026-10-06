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
    tokenFile.reload()
  }

  property int walletGold: 0
  property bool loading: false
  property string errorMessage: ""
  property string lastUpdated: ""
  property int fetchStamp: 0

  // Token entry. Lives in the panel so the bar's right-click stays a
  // notification; the value is stored on this widget's shell.json entry.
  property bool settingsOpen: false
  property string settingsStatus: ""
  readonly property var shellApi: root.bar && root.bar.shell ? root.bar.shell : null
  readonly property string tokenSource: String(setting("apiToken", "")) !== "" ? "this panel"
    : (root.envToken !== "" ? "$GW2_API_TOKEN"
    : (root.fileToken !== "" ? "~/.config/omarchy/gw2-api-token" : "nothing yet"))

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

  // The API key must never reach a command line: anything in argv is readable
  // by other local users through /proc/<pid>/cmdline. curl is fed a config
  // stream over stdin (`--config -`) instead, so the key stays out of its
  // process arguments and out of the environment. Same pattern as Omarchy's
  // own network panel, which sends the 802.1X password over stdin.
  // The config format is line-oriented, so a stray newline or quote in the
  // stored key is stripped rather than allowed to inject another directive.
  readonly property string safeToken: String(root.apiToken).replace(/[\r\n"\\]/g, "")

  readonly property string walletCurlConfig:
    'url = "https://api.guildwars2.com/v2/account/wallet?_=' + root.fetchStamp + '"\n'
    + 'header = "Authorization: Bearer ' + root.safeToken + '"\n'
    + 'header = "Cache-Control: no-cache"\n'

  readonly property string dailiesCurlConfig:
    'url = "https://api.guildwars2.com/v2/account/wizardsvault/daily?_=' + root.fetchStamp + '"\n'
    + 'header = "Authorization: Bearer ' + root.safeToken + '"\n'
    + 'header = "Cache-Control: no-cache"\n'

  function open() {
    settingsOpen = false
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

  // ---- Settings ------------------------------------------------------------
  // The token lives on this widget's shell.json entry, read first by the
  // `apiToken` binding above. The shell patches the entry into the running
  // widget in place, so a save takes effect without a remount.
  function openSettings() {
    settingsOpen = true
    settingsStatus = ""
    tokenField.text = String(setting("apiToken", ""))
    Qt.callLater(function() {
      tokenField.forceActiveFocus()
      tokenField.selectAll()
    })
  }

  function closeSettings() {
    settingsOpen = false
    settingsStatus = ""
    keyCatcher.forceActiveFocus()
  }

  function persistToken(values) {
    var entry = { id: moduleName }
    var current = hostWidget && hostWidget.settings ? hostWidget.settings : (root.settings || {})
    for (var k in current) if (k !== "id") entry[k] = current[k]
    for (var key in values) entry[key] = values[key]
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (root.shellApi && typeof root.shellApi.updateEntryInline === "function")
      return root.shellApi.updateEntryInline(moduleName, entry) === true
    return false
  }

  function saveToken() {
    keyCatcher.forceActiveFocus()
    var value = String(tokenField.text).trim()
    if (value !== "" && (value.length < 30 || value.indexOf("-") === -1)) {
      settingsStatus = "That does not look like a GW2 API key (they are long and hyphenated)."
      return
    }
    var previous = String(setting("apiToken", ""))
    if (value === previous) {
      settingsStatus = value === "" ? "No change: still using " + tokenSource + "." : "No change."
      return
    }
    var written = persistToken({ apiToken: value })
    // Computed here rather than from tokenSource: the binding above only
    // re-evaluates after this call returns.
    var nextSource = value !== "" ? "this panel"
      : (root.envToken !== "" ? "$GW2_API_TOKEN"
      : (root.fileToken !== "" ? "~/.config/omarchy/gw2-api-token" : "nothing yet"))
    settingsStatus = !written ? "Saved for this session only: the widget is not in the bar layout."
      : value === "" ? "Cleared. Now using " + nextSource + "." : "Saved."
    if (hasToken && !loading) refresh()
  }

  function clearToken() {
    keyCatcher.forceActiveFocus()
    tokenField.text = ""
    saveToken()
  }

  function formFieldKey(event, input) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      saveToken()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      input.text = String(setting("apiToken", ""))
      closeSettings()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      keyCatcher.forceActiveFocus()
      event.accepted = true
    }
  }

  function refresh() {
    if (!hasToken) return
    loading = true
    errorMessage = ""
    dailiesError = ""
    // New stamp busts any intermediary cache so every refresh hits the API live
    fetchStamp = Date.now()
    // Each run needs its stdin pipe reopened, because the previous run closed it
    // to signal EOF to curl.
    if (!walletProc.running) {
      walletProc.stdinEnabled = true
      walletProc.running = true
    }
    if (!dailiesProc.running) {
      dailiesProc.stdinEnabled = true
      dailiesProc.running = true
    }
  }

  function msUntilNextUtcReset() {
    var now = new Date()
    var next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 0)
    return Math.max(1000, next - now.getTime())
  }

  Process {
    id: walletProc
    command: ["curl", "-fsS", "--max-time", "10", "--config", "-"]
    // The key is written to curl's stdin, then stdin is closed so curl sees EOF
    // and starts the transfer. Nothing secret reaches argv.
    stdinEnabled: true
    onStarted: {
      write(root.walletCurlConfig)
      stdinEnabled = false
    }
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
    command: ["curl", "-fsS", "--max-time", "10", "--config", "-"]
    stdinEnabled: true
    onStarted: {
      write(root.dailiesCurlConfig)
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseWizardVaultDailies(text)
        dailyObjectives = parsed.objectives
        metaProgressCurrent = parsed.metaProgressCurrent
        metaProgressComplete = parsed.metaProgressComplete
        dailiesLoaded = true
        loading = false
        // Fetch acclaim icon if not cached
        if (root.acclaimIconUrl === "") {
          acclaimIconProc.running = true
        }
      }
    }
    onExited: function(exitCode) {
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
    contentHeight: panel.fittedContentHeight(root.settingsOpen ? settingsColumn.implicitHeight : contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the token field has the keyboard every key goes to it, so
      // Escape/Tab/Enter mean the field, not the panel.
      blocked: tokenField.activeFocus
      onCloseRequested: {
        if (root.settingsOpen) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.settingsOpen) return
        root.switchPanel(direction)
      }
      onReturnRequested: root.settingsOpen ? root.saveToken() : root.refresh()
    }

    Column {
      id: contentColumn
      visible: !root.settingsOpen
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
        height: Math.max(statusText.implicitHeight, refreshBtn.implicitHeight, settingsBtn.implicitHeight)

        Row {
          anchors.fill: parent
          spacing: Style.space(8)

          Text {
            id: statusText
            visible: root.errorMessage !== "" || root.loading || root.lastUpdated !== ""
            // Constrained to what the two buttons leave, so a long error
            // truncates instead of pushing Settings out of the panel.
            width: Math.max(0, parent.width - refreshBtn.implicitWidth - settingsBtn.implicitWidth - 2 * Style.space(8))
            textFormat: Text.PlainText
            text: root.errorMessage !== "" ? root.errorMessage : (root.loading ? "Synchronizing..." : "Updated: " + root.lastUpdated)
            color: root.errorMessage !== "" ? "#FF4A4A" : "#8C8E96"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: root.loading
            elide: Text.ElideRight
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

          Button {
            id: settingsBtn
            text: "Settings"
            fontSize: Style.font.bodySmall
            foreground: "#9A9B9F"
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.openSettings()
          }
        }
      }

      Rectangle {
        width: contentColumn.width
        height: noTokenText.implicitHeight + Style.space(10)
        color: "#1D1811"
        border.color: "#4A3A22"
        border.width: 1
        visible: !root.hasToken

        Text {
          id: noTokenText
          anchors.fill: parent
          anchors.margins: Style.space(5)
          textFormat: Text.PlainText
          text: "⚠️ No API token. Open Settings and paste your GW2 API key."
          color: "#D97736"
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openSettings()
        }
      }
    }

    // ---- Settings view -----------------------------------------------------
    // Own column so the panel's look stays as it is; contentHeight above
    // follows whichever column is showing.
    Column {
      id: settingsColumn
      visible: root.settingsOpen
      width: Math.min(parent.width, Style.space(300))
      spacing: Style.space(8)

      // Compact header, same shape as the main one, with a back affordance.
      Rectangle {
        width: settingsColumn.width
        height: 28
        color: "#141518"
        border.color: "#3A352A"
        border.width: 1

        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: "‹"
            font.pixelSize: 14
            color: "#9A9B9F"
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "SETTINGS"
            color: "#E6C267"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeSettings()
        }
      }

      Text {
        width: settingsColumn.width
        textFormat: Text.PlainText
        text: "Paste a Guild Wars 2 API key with \"Account\" and \"Wallet\" permissions. Saved on this widget in shell.json, so the panel and bar both pick it up at once."
        color: "#9A9B9F"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Text {
        width: settingsColumn.width
        textFormat: Text.PlainText
        text: "Currently using: " + root.tokenSource
        color: root.hasToken ? "#8C8E96" : "#D97736"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      TextField {
        id: tokenField
        width: settingsColumn.width
        password: true
        placeholderText: "0ABC-1234-..."
        foreground: "#E6C267"
        accent: "#E6C267"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(6)
        Keys.onPressed: function(event) { root.formFieldKey(event, tokenField) }
      }

      Text {
        visible: root.settingsStatus !== ""
        width: settingsColumn.width
        textFormat: Text.PlainText
        text: root.settingsStatus
        color: root.hasToken ? "#9A9B9F" : "#D97736"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Row {
        spacing: Style.space(8)

        Button {
          id: saveBtn
          text: "Save"
          enabled: tokenField.text.trim() !== ""
          fontSize: Style.font.bodySmall
          foreground: "#E6C267"
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          onClicked: root.saveToken()
        }

        Button {
          id: clearBtn
          text: "Clear"
          fontSize: Style.font.bodySmall
          foreground: "#9A9B9F"
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          onClicked: root.clearToken()
        }

        Button {
          text: "Back"
          fontSize: Style.font.bodySmall
          foreground: "#9A9B9F"
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.closeSettings()
        }
      }

      Text {
        width: settingsColumn.width
        textFormat: Text.PlainText
        text: "Esc reverts and goes back. Enter saves."
        color: "#8C8E96"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }
  }
}