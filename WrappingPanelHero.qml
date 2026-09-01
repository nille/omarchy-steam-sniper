import QtQuick

Item {
  id: root

  property Component iconComponent: null
  property string title: ""
  property string meta: ""
  property color foreground: "white"
  property string fontFamily: "monospace"
  property real titleFontSize: 14
  property real metaFontSize: 10
  property real iconGap: 14
  property real labelGap: 2
  property real iconOpacity: 1.0

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property int metaLineCount: metaText.lineCount
  readonly property bool metaTruncated: metaText.truncated

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconLoader.implicitHeight, heroLabels.implicitHeight)

  Loader {
    id: iconLoader
    sourceComponent: root.iconComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.iconOpacity
  }

  Column {
    id: heroLabels
    anchors.left: iconLoader.right
    anchors.leftMargin: root.iconGap
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.labelGap

    Text {
      width: parent.width
      textFormat: Text.PlainText
      visible: root.title !== ""
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.titleFontSize
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      id: metaText
      width: parent.width
      textFormat: Text.PlainText
      visible: text !== ""
      text: root.meta.toUpperCase()
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.metaFontSize
      font.bold: true
      font.letterSpacing: 1.2
      wrapMode: Text.WordWrap
    }
  }
}
