pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Watch Steam's free-specials search and notify when a newly free game
// appears. Parsing, seen-id transitions, and notification copy live in
// Model.js; this file owns transport, persistence, and rendering.
Panel {
  id: root
  moduleName: "nille.steam-sniper"
  ipcTarget: "nille.steam-sniper"
  manageIpc: false

  readonly property string stateDir: Quickshell.env("STEAM_SNIPER_STATE")
    || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/omarchy-steam-sniper")
  readonly property string seenPath: stateDir + "/seen.json"
  property string seenFilePath: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int refreshMinutes:
    Model.normalizeRefreshMinutes(setting("refreshMinutes", 15))
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  readonly property bool notificationsEnabled:
    setting("notificationsEnabled", true) !== false
  readonly property string country: Model.normalizeCountry(setting("country", ""))

  property var games: []
  property var watchState: Model.emptyWatchState()
  property bool seenLoaded: false
  property bool requestInFlight: false
  property string lastError: ""
  property double lastSuccessAt: 0
  property double nowMs: Date.now()
  property int retryDelayMs: 30000
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property bool stale: lastSuccessAt > 0
    && nowMs - lastSuccessAt >= Model.STALE_AFTER_MS
  readonly property string freshness: Model.freshnessLabel(
    lastSuccessAt, nowMs, requestInFlight, lastError)
  readonly property bool hasGames: games.length > 0

  function ingestSeen(raw) {
    if (seenLoaded) return
    watchState = Model.parseSeen(raw)
    seenLoaded = true
  }

  function persistSeen() {
    if (!seenLoaded) return
    seenFile.setText(Model.serializeSeen(watchState) + "\n")
  }

  function refresh() {
    if (requestInFlight) return
    requestInFlight = true
    lastError = ""
    fetchProc.command = Model.fetchArgs(Model.resultsUrl(country))
    fetchProc.running = true
  }

  // An unloaded seen.json is not primed, so it cannot false-alarm here; the
  // file wins once it loads and the next refresh compares against it.
  function publish(raw) {
    var parsed = Model.parseSearchPayload(raw)
    if (!parsed) {
      finishFailure("Steam returned invalid data")
      return
    }

    games = parsed
    lastSuccessAt = Date.now()
    nowMs = lastSuccessAt
    lastError = ""
    requestInFlight = false
    retryDelayMs = 30000
    retryTimer.stop()

    var transition = Model.transitionAlerts(
      watchState, games, notificationsEnabled)
    watchState = transition.state
    persistSeen()

    var argv = Model.notificationArgs(
      Model.notificationFor(transition.alerts, country))
    if (argv) Quickshell.execDetached(argv)

    setCursor(selectedIndex)
  }

  function finishFailure(message) {
    requestInFlight = false
    lastError = String(message || "Could not reach Steam")
    retryTimer.interval = retryDelayMs
    retryTimer.restart()
    retryDelayMs = Math.min(15 * 60 * 1000, retryDelayMs * 2)
  }

  function openStore() {
    Quickshell.execDetached(["omarchy-launch-browser", Model.searchUrl(country)])
  }

  function openGame(game) {
    var url = game && game.url ? game.url : Model.searchUrl(country)
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function setCursor(index) {
    selectedIndex = Math.max(0, Math.min(Math.max(0, games.length - 1), index))
  }

  function selectedGame() {
    return selectedIndex >= 0 && selectedIndex < games.length
      ? games[selectedIndex] : null
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: function(exitCode) {
      if (exitCode === 0) root.seenFilePath = root.seenPath
      else root.ingestSeen("")
    }
  }

  FileView {
    id: seenFile
    path: root.seenFilePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: if (root.seenFilePath) root.ingestSeen(text())
    onLoadFailed: if (root.seenFilePath) root.ingestSeen("")
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.publish(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.requestInFlight)
        root.finishFailure("Could not reach Steam")
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: retryTimer
    interval: 30000
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (lastSuccessAt === 0 || stale) refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !(hideWhenEmpty && lastSuccessAt > 0 && !hasGames)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.BAR_ICON
    dimmed: !root.hasGames || root.stale
    tooltipText: Model.tooltipText(
      root.games, root.requestInFlight, root.lastError, root.freshness)

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton) root.openStore()
      else root.toggle()
    }
  }

  SequentialAnimation {
    running: root.requestInFlight
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation {
      target: button
      property: "scale"
      to: 0.72
      duration: 260
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: button
      property: "scale"
      to: 1.08
      duration: 260
      easing.type: Easing.InOutSine
    }
    onStopped: button.scale = 1
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight,
                                             Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.setCursor(root.selectedIndex + dy)
      }
      onActivateRequested: {
        var game = root.selectedGame()
        if (game) root.openGame(game)
        else root.openStore()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "r") root.refresh()
        else if (key === "o") root.openStore()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height
          ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.spacing.panelGap

          Item {
            id: hero
            readonly property color tint:
              root.lastError && !root.hasGames ? root.urgent : root.foreground
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight,
                                     heroLabels.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Model.BAR_ICON
              color: hero.tint
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: Model.statusTitle(
                  root.games, root.requestInFlight, root.lastError)
                color: hero.tint
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              // Wraps rather than elides: the empty state is a full sentence.
              Text {
                width: parent.width
                textFormat: Text.PlainText
                visible: text !== ""
                text: Model.statusDetail(root.games, root.requestInFlight,
                                         root.lastError, root.freshness).toUpperCase()
                color: Qt.darker(hero.tint, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Repeater {
            id: gameRepeater
            model: root.games

            Rectangle {
              id: gameRow
              required property var modelData
              required property int index
              width: panelColumn.width
              implicitHeight: Math.max(Style.space(28), gameTitle.implicitHeight + Style.spacing.sm)
              radius: Style.cornerRadius
              color: root.cursorActive && root.selectedIndex === index
                ? (root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                            : "transparent")
                : (rowMouse.containsMouse
                  ? (root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                              : "transparent")
                  : "transparent")

              Text {
                id: gameTitle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                text: gameRow.modelData.title
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openGame(gameRow.modelData)
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.hasGames
            wrapMode: Text.WordWrap
            text: root.lastError
              ? root.lastError
              : "No 100% off games right now. Steam Sniper will notify you when one appears."
            color: root.lastError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            width: parent.width
            text: "Open Steam search"
            iconText: "\u{F03CC}"
            bordered: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.openStore()
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Left-click the icon for this list. Middle-click refreshes. Right-click opens Steam."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
