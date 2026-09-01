pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as SteamSniper
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
  readonly property color accent: Color.accent
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
  property var pendingSnapshot: null
  property bool requestInFlight: false
  property bool refreshPulse: false
  property bool refreshQueued: false
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
    if (pendingSnapshot) {
      applySnapshot(pendingSnapshot)
      pendingSnapshot = null
    }
  }

  function persistSeen() {
    if (!seenLoaded) return
    seenFile.setText(Model.serializeSeen(watchState) + "\n")
  }

  function refresh() {
    if (requestInFlight) {
      refreshQueued = true
      return
    }
    requestInFlight = true
    refreshPulse = true
    refreshQueued = false
    lastError = ""
    fetchProc.command = Model.fetchArgs(Model.resultsUrl(country))
    fetchProc.running = true
    refreshPulseTimer.restart()
  }

  function publish(raw) {
    var parsed = Model.parseSearchPayload(raw)
    if (!parsed) {
      finishFailure("Steam returned invalid data")
      return
    }
    if (!seenLoaded) {
      pendingSnapshot = parsed
      requestInFlight = false
      if (!refreshPulseTimer.running) refreshPulse = false
      retryDelayMs = 30000
      retryTimer.stop()
      if (refreshQueued) refresh()
      return
    }
    applySnapshot(parsed)
  }

  function applySnapshot(parsed) {
    games = parsed.games
    lastSuccessAt = Date.now()
    nowMs = lastSuccessAt
    lastError = ""
    requestInFlight = false
    if (!refreshPulseTimer.running) refreshPulse = false
    retryDelayMs = 30000
    retryTimer.stop()

    var transition = Model.transitionAlerts(
      watchState, games, notificationsEnabled)
    watchState = transition.state
    persistSeen()

    if (transition.alerts.length > 0) {
      var argv = Model.notificationArgs(
        Model.notificationFor(transition.alerts, country))
      if (argv) Quickshell.execDetached(argv)
    }

    clampCursor()
    if (refreshQueued) refresh()
  }

  function finishFailure(message) {
    requestInFlight = false
    if (!refreshPulseTimer.running) refreshPulse = false
    lastError = String(message || "Could not reach Steam")
    retryTimer.interval = retryDelayMs
    retryTimer.restart()
    retryDelayMs = Math.min(15 * 60 * 1000, retryDelayMs * 2)
    if (refreshQueued) refresh()
  }

  function openStore() {
    Quickshell.execDetached(["omarchy-launch-browser", Model.searchUrl(country)])
  }

  function openGame(game) {
    var url = game && game.url ? game.url : Model.searchUrl(country)
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function setCursor(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(Math.max(0, games.length - 1), index))
  }

  function moveCursor(delta) {
    setCursor(selectedIndex + delta)
  }

  function clampCursor() {
    selectedIndex = Math.max(0, Math.min(Math.max(0, games.length - 1), selectedIndex))
  }

  function selectedGame() {
    return selectedIndex >= 0 && selectedIndex < games.length
      ? games[selectedIndex] : null
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function state(): string {
      return JSON.stringify({
        games: root.games,
        error: root.lastError,
        freshness: root.freshness
      })
    }
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
    id: refreshPulseTimer
    interval: 1200
    onTriggered: if (!root.requestInFlight) root.refreshPulse = false
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
    text: Model.barIcon()
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
    running: root.refreshPulse
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
        if (dy !== 0) root.moveCursor(dy)
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

          SteamSniper.WrappingPanelHero {
            width: parent.width
            title: Model.statusTitle(
              root.games, root.requestInFlight, root.lastError)
            meta: Model.statusDetail(
              root.games, root.requestInFlight, root.lastError, root.freshness)
            foreground: root.lastError && !root.hasGames ? root.urgent : root.foreground
            fontFamily: root.fontFamily
            titleFontSize: Style.font.title
            metaFontSize: Style.font.caption
            iconGap: Style.space(14)
            labelGap: Style.space(2)

            iconComponent: Component {
              Text {
                text: Model.barIcon()
                color: root.lastError && !root.hasGames ? root.urgent : root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.display
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
            accent: root.accent
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
