import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// System monitor popup — top processes by CPU and RAM
// Shown when clicking the CPU/RAM pill in the bar

PopupWindow {
    id: popup
    visible: false
    grabFocus: true

    required property var anchorWindow
    required property var anchorItem

    anchor.window: anchorWindow
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    // Theme colors (passed from root)
    required property color bgColor
    required property color fgColor
    required property color mutedColor
    required property color accentBlue
    required property color accentTeal
    required property color accentYellow
    required property color accentRed
    required property string fontFamily
    required property int fontSize

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    // ─────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────
    property string activeTab: "cpu"    // "cpu" or "ram"
    property var cpuProcs: []
    property var ramProcs: []
    property string _buf: ""

    readonly property string scriptsDir:
        Qt.resolvedUrl("../scripts/").toString().replace("file://", "")

    // ─────────────────────────────────────────────────────
    // Status polling
    // ─────────────────────────────────────────────────────
    Process {
        id: sysmonProc
        command: ["bash", popup.scriptsDir + "sysmon_panel.sh", "--status"]
        stdout: SplitParser {
            onRead: function(line) { popup._buf += line }
        }
        onExited: function() {
            try {
                var d = JSON.parse(popup._buf)
                popup.cpuProcs = d.cpu || []
                popup.ramProcs = d.ram || []
            } catch(e) {}
            popup._buf = ""
        }
    }

    Timer {
        id: pollTimer
        interval: 3000
        running: popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: sysmonProc.running = true
    }

    // ─────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────
    Rectangle {
        id: popupContent
        width: 320
        height: mainColumn.height + 24
        color: popup.bgColor
        border.color: popup.mutedColor
        border.width: 1
        radius: 6

        Column {
            id: mainColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            // ── Tab buttons ─────────────────────────────
            Row {
                spacing: 4
                width: parent.width

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "cpu"
                           ? Qt.rgba(popup.accentTeal.r, popup.accentTeal.g, popup.accentTeal.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uF4BC  CPU"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "cpu"
                        color: popup.activeTab === "cpu" ? popup.accentTeal : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "cpu"
                    }
                }

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "ram"
                           ? Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uF2DB  RAM"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "ram"
                        color: popup.activeTab === "ram" ? popup.accentBlue : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "ram"
                    }
                }
            }

            // ── Divider ─────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Column headers ──────────────────────────
            Row {
                width: parent.width
                spacing: 0

                Text {
                    width: parent.width * 0.45
                    text: "PROCESS"
                    font.pixelSize: popup.fontSize - 3
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }
                Text {
                    width: parent.width * 0.25
                    text: "CPU %"
                    font.pixelSize: popup.fontSize - 3
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    horizontalAlignment: Text.AlignRight
                }
                Text {
                    width: parent.width * 0.30
                    text: "RAM MB"
                    font.pixelSize: popup.fontSize - 3
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── Process list ────────────────────────────
            Repeater {
                model: popup.activeTab === "cpu" ? popup.cpuProcs : popup.ramProcs

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 26
                    radius: 3
                    color: index % 2 === 0
                           ? "transparent"
                           : Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.03)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 0

                        Text {
                            width: parent.width * 0.45
                            text: modelData.name
                            font.pixelSize: popup.fontSize - 1
                            font.family: popup.fontFamily
                            color: popup.fgColor
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: parent.width * 0.25
                            text: modelData.cpu.toFixed(1)
                            font.pixelSize: popup.fontSize - 1
                            font.family: popup.fontFamily
                            color: modelData.cpu > 50 ? popup.accentRed
                                 : modelData.cpu > 20 ? popup.accentYellow
                                 : popup.accentTeal
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: parent.width * 0.30
                            text: modelData.ram.toFixed(0)
                            font.pixelSize: popup.fontSize - 1
                            font.family: popup.fontFamily
                            color: modelData.ram > 2048 ? popup.accentRed
                                 : modelData.ram > 512  ? popup.accentYellow
                                 : popup.accentBlue
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: (popup.activeTab === "cpu" ? popup.cpuProcs : popup.ramProcs).length === 0
                text: "Loading\u2026"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
            }
        }
    }
}
