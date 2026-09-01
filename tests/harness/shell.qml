import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

ShellRoot {
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 240
    color: Color.background
    visible: true

    QtObject {
      id: stubBar
      property string fontFamily: Style.font.family
      property color foreground: Color.bar.text
      property color barForeground: Color.bar.text
      property color background: Color.bar.background
      property color urgent: Color.bar.active
      property bool vertical: false
      property int barSize: Style.bar.sizeHorizontal
      property string position: "top"
      property var activePopout: null

      function requestPopout(owner) {
        if (activePopout && activePopout !== owner) activePopout.close()
        activePopout = owner
      }
      function releasePopout(owner) {
        if (activePopout === owner) activePopout = null
      }
      function showTooltip(item, text) {}
      function hideTooltip(item) {}
      function registerClickTarget(item) {}
      function unregisterClickTarget(item) {}
      function moduleWidgets(name) { return [] }
      function switchPanelFrom(panel, direction) { return false }
    }

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.bar.sizeHorizontal
      color: Color.bar.background

      Loader {
        id: widgetLoader
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        source: (Quickshell.env("STEAM_SNIPER_DIR") || ".") + "/Panel.qml"
        onLoaded: {
          item.bar = stubBar
          item.moduleName = "nille.steam-sniper"
          item.settings = {
            refreshMinutes: 15,
            hideWhenEmpty: false,
            notificationsEnabled: false,
            country: "US"
          }
        }
      }
    }

    Timer {
      interval: 500
      running: true
      onTriggered: if (widgetLoader.item) widgetLoader.item.open()
    }
  }
}
